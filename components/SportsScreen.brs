sub init()
    m.list = m.top.FindNode("sportsList"):m.filters = m.top.FindNode("sportsFilters")
    m.status = m.top.FindNode("sportsStatus"):m.name = m.top.FindNode("sportsName"):m.detail = m.top.FindNode("sportsDetail")
    m.list.ObserveField("rowItemSelected","onSportsSelected")
    m.list.ObserveField("rowItemFocused","onSportsFocus")
    m.filters.ObserveField("chipActivated","onSportsChip")
    m.filters.ObserveField("optionPicked","onSportsOption")
    t = Theme()
    m.top.FindNode("sportsTitle").color = t.accent
    m.top.FindNode("sportsSubtitle").color = t.textSecondary
    m.top.FindNode("sportsHelp").color = t.textSecondary
    m.top.FindNode("sportsPlate").color = t.tileFace
    m.name.color = t.textPrimary:m.detail.color = t.textSecondary:m.status.color = t.textSecondary
    m.leagues = Sports_Leagues():m.leagueIndex = 0:m.dayIndex = 1:m.stateIndex = 0
    m.states = [{raw:"",label:"All events"},{raw:"in",label:"Live"},{raw:"pre",label:"Upcoming"},{raw:"post",label:"Completed"}]
    m.events = []:m.rows = []:m.days = []:m.catalogs = []
    m.browseProviders = true:m.allowUnknownLiveAudio = true:m.livePlayback = true
    m.task = invalid:m.sequence = 0:m.desired = "":m.applied = "":m.loaded = "":m.loadClock = invalid
end sub

function OnEnter(params as object) as void
    if Type(params) = "roAssociativeArray"
        m.previousEventName = ""
        m.previousProviderAddress = ""
        if params.backupMode = true
            m.browseProviders = true:m.livePlayback = true
            m.allowUnknownLiveAudio = params.allowUnknownLiveAudio = true
            m.previousEventName = Sports_Text(params.previousEventName,120)
            m.previousProviderAddress = params.previousProviderAddress
        end if
    end if
    SportsDays()
    SportsCatalogs()
    SportsChips()
    if m.filters.callFunc("IsMenuOpen") then m.filters.callFunc("HideMenu")
    m.filters.callFunc("FocusChips")
    if m.browseProviders = true then RenderSportsCatalogs():return
    key = SportsQueryKey()
    if m.loaded <> key or m.loadClock = invalid
        SportsRequest()
    else if m.loadClock.TotalMilliseconds() >= 60000
        SportsRequest()
    else
        RenderSportsRows()
    end if
end function

sub SportsDays()
    now = CreateObject("roDateTime")
    seconds = now.AsSeconds()
    m.days = []
    for offset = -1 to 7
        day = CreateObject("roDateTime"):day.FromSeconds(seconds + offset * 86400)
        iso = day.ToISOString().Left(10)
        label = iso
        if offset = -1 then label = "Yesterday"
        if offset = 0 then label = "Today"
        if offset = 1 then label = "Tomorrow"
        m.days.Push({raw:iso.Replace("-",""),label:label})
    end for
end sub

sub SportsCatalogs()
    m.catalogs = [{raw:"",label:"Manage add-ons"}]
    if m.stores = invalid then return
    addons = m.stores.addons.callFunc("AddonsGetAll")
    if Type(addons) <> "roArray" then return
    ' Prioritize other providers before the 40-row budget, not after it. A
    ' large current provider must not crowd every backup out of this view.
    if m.previousProviderAddress <> invalid and m.previousProviderAddress <> ""
        ordered = []:current = []
        for each addon in addons
            if Type(addon) <> "roAssociativeArray" then continue for
            if addon.address = m.previousProviderAddress then current.Push(addon) else ordered.Push(addon)
        end for
        ordered.Append(current):addons = ordered
    end if
    for each addon in addons
        if Type(addon) <> "roAssociativeArray" then continue for
        if Type(addon.catalogs) <> "roArray" then continue for
        for each catalog in addon.catalogs
            if Type(catalog) <> "roAssociativeArray" then continue for
            if catalog.type <> "tv" and catalog.type <> "channel" and catalog.type <> "sports" then continue for
            cap = m.stores.addons.callFunc("AddonsCatalogCapabilities",catalog)
            if cap = invalid or cap.feed <> true then continue for
            if m.catalogs.Count() >= 40 then exit for
            label = Sports_Text(addon.name,28) + " · " + Sports_Text(catalog.name,28)
            if addon.address = m.previousProviderAddress then label = "Current · " + label
            m.catalogs.Push({raw:catalog.id,label:label,params:{metaType:catalog.type,catalogId:catalog.id,addonAddress:addon.address}})
        end for
    end for

end sub

sub SportsChips()
    if m.browseProviders = true
        audio = "Audio: English + unlabelled"
        if m.allowUnknownLiveAudio <> true then audio = "Audio: verified English"
        playback = "Playback: Live"
        if m.livePlayback <> true then playback = "Playback: Recorded"
        m.filters.callFunc("SetChips",[{raw:"mode",label:"Provider catalogs"},{raw:"playback",label:playback},{raw:"audio",label:audio},{raw:"channels",label:"Manage add-ons"}])
        return
    end if
    m.filters.callFunc("SetChips",[{raw:"league",label:m.leagues[m.leagueIndex].label},{raw:"day",label:m.days[m.dayIndex].label},{raw:"state",label:m.states[m.stateIndex].label},{raw:"channels",label:"TV / sports add-ons"}])
end sub

function SportsQueryKey() as string
    return m.leagues[m.leagueIndex].raw + "|" + m.days[m.dayIndex].raw
end function

sub SportsRequest()
    if m.browseProviders = true then SportsCatalogs():RenderSportsCatalogs():return
    key = SportsQueryKey()
    if m.loaded <> key then m.events = []
    m.desired = key
    RenderSportsRows()
    m.status.text = "Updating schedule… Back remains available."
    SportsPump()
end sub

' Retain ownership until FINISHED. Changing leagues/Back cannot multiply live
' network transfers; only the latest requested query starts after this one.
sub SportsPump()
    if m.top.screenActive <> true or m.desired = "" or m.task <> invalid then return
    m.sequence++
    m.taskKey = m.desired
    m.applied = ""
    try
        m.task = AsyncTask_Launch(m.top,"SportsScheduleTask","onSportsResult",{league:m.leagues[m.leagueIndex].raw,day:m.days[m.dayIndex].raw},"sports" + m.sequence.ToStr(),"onSportsFinished")
    catch e
        m.task = invalid:m.desired = ""
        m.status.text = "Could not start schedule request. Play/Pause retries."
    end try
end sub

sub onSportsResult(event as object)
    if m.task = invalid then return
    task = event.GetRoSGNode()
    if task = invalid or task.id <> m.task.id then return
    SportsApply(task.result)
end sub

sub SportsApply(packet as dynamic)
    if m.browseProviders = true then return
    if m.top.screenActive <> true or m.taskKey <> m.desired or m.applied = m.task.id then return
    if Type(packet) <> "roAssociativeArray" or Type(packet.events) <> "roArray" then return
    m.applied = m.task.id
    if packet.ok <> true
        m.status.text = "Schedule unavailable. Play/Pause retries."
        if m.events.Count() > 0 then m.status.text = "Refresh failed; showing earlier schedule. Play/Pause retries."
        return
    end if
    m.events = packet.events:m.loaded = m.taskKey
    m.loadClock = CreateObject("roTimespan"):m.loadClock.Mark()
    RenderSportsRows()
    m.status.text = "ESPN schedule · " + m.days[m.dayIndex].label + " · Start times UTC · Play/Pause refreshes"
    if packet.truncated = true then m.status.text = "Showing first 100 events · Schedule has more events"
    if packet.skipped > 0 then m.status.text = m.status.text + " · Some entries could not be read"
end sub

sub onSportsFinished(event as object)
    if m.task = invalid then return
    task = event.GetRoSGNode()
    if task = invalid or task.id <> m.task.id or task.finished <> true then return
    SportsApply(task.result)
    if m.browseProviders <> true and m.top.screenActive = true and m.taskKey = m.desired and m.applied <> task.id then m.status.text = "Schedule worker ended without a result. Play/Pause retries."
    completed = m.taskKey
    m.task = invalid
    AsyncTask_Reap(task,m.top,false)
    if m.desired = completed then m.desired = ""
    SportsPump()
end sub

sub RenderSportsRows()
    m.rows = []
    content = CreateObject("roSGNode","ContentNode")
    for each event in m.events
        if m.states[m.stateIndex].raw <> "" and event.state <> m.states[m.stateIndex].raw then continue for
        if m.rows.Count() >= 100 then exit for
        m.rows.Push(event)
        row = content.CreateChild("ContentNode"):item = row.CreateChild("ContentNode")
        item.title = event.name
        item.description = event.phase + " · " + event.detail
        if event.score <> "" then item.description = item.description + " · " + event.score
    end for
    m.list.content = content
    ShowSportsDetail(0)
end sub

function SportsProviderCount(id as string) as integer
    count = 0
    if m.stores = invalid then return count
    addons = m.stores.addons.callFunc("AddonsGetAll")
    if Type(addons) <> "roArray" then return count
    for each addon in addons
        if m.stores.addons.callFunc("AddonsSupportsResource",addon.resources,addon.types,addon.idPrefixes,"stream","tv",id) = true then count++
    end for
    return count
end function

sub ShowSportsDetail(index as integer)
    if m.browseProviders = true then ShowSportsCatalogDetail(index):return
    if index < 0 or index >= m.rows.Count()
        m.name.text = "No events in this view"
        m.detail.text = "Try another date, league or status. TV / sports add-ons opens your installed channel catalogs, including competitions outside this schedule."
        return
    end if
    event = m.rows[index]
    m.name.text = event.name
    nl = Chr(10)
    m.detail.text = event.phase + " · " + event.detail + nl + event.score + nl + "Start (UTC): " + event.date + nl + nl
    count = SportsProviderCount(event.id)
    if count = 0
        m.detail.text = m.detail.text + "Schedule only. No installed provider advertises streams for this event ID. Add a compatible authorized sports provider in Add-ons."
    else
        m.detail.text = m.detail.text + "OK checks " + count.ToStr() + " provider(s). A listing does not guarantee a stream or regional access."
    end if
end sub

sub onSportsFocus()
    focus = m.list.rowItemFocused
    if Type(focus) = "roArray" and focus.Count() > 0 then ShowSportsDetail(focus[0])
end sub

sub onSportsSelected()
    if m.top.screenActive <> true then return
    selected = m.list.rowItemSelected
    if Type(selected) <> "roArray" or selected.Count() = 0 then return
    index = selected[0]
    if index < 0 or index >= m.rows.Count() then return
    if m.browseProviders = true then OpenSportsCatalog(index):return
    event = m.rows[index]
    if event.state = "pre"
        m.status.text = "Upcoming event. Refresh near its start time; a stream is not guaranteed."
        return
    end if
    if SportsProviderCount(event.id) = 0
        m.status.text = "Schedule only · Open TV / sports add-ons to manage providers or browse channels."
        return
    end if
    m.top.pushRequest = {screen:"streamsScreen",params:Sports_StreamRequest(event)}
end sub

sub onSportsChip()
    index = m.filters.chipActivated
    options = []:current = 0
    if m.browseProviders = true
        if index = 0 then options = [{label:"Provider catalogs",raw:"providers"},{label:"ESPN schedules (separate IDs)",raw:"schedule"}]
        if index = 1 then options = [{label:"Live: no resume / no next episode",raw:"live"},{label:"Recorded: standard playback checks",raw:"recorded"}]
        if index = 2 then options = [{label:"Prefer English; allow unlabelled live audio",raw:"unknown"},{label:"Require verified English",raw:"english"}]
        if index = 3 then m.top.pushRequest = {screen:"addonsScreen",params:{}}:return
        if options.Count() > 0 then m.filters.callFunc("ShowMenu",options,0)
        return
    end if
    if index = 0 then options = m.leagues:current = m.leagueIndex
    if index = 1 then options = m.days:current = m.dayIndex
    if index = 2 then options = m.states:current = m.stateIndex
    if index = 3
        SportsCatalogs():options = []
        options.Append(m.catalogs)
        options.Push({raw:"browse",label:"Return to provider catalogs"})
    end if
    if options.Count() > 0 then m.filters.callFunc("ShowMenu",options,current)
end sub

sub onSportsOption()
    pick = m.filters.optionPicked
    if Type(pick) <> "roAssociativeArray" then return
    if Type(pick.index) <> "Integer" and Type(pick.index) <> "roInt" then return
    index = pick.index
    if index < 0 then return
    m.filters.callFunc("HideMenu")
    if m.browseProviders = true
        if index > 1 then return
        if pick.chip = 0
            m.browseProviders = index = 0
            SportsChips():SportsRequest():return
        end if
        if pick.chip = 1 then m.livePlayback = index = 0
        if pick.chip = 2 then m.allowUnknownLiveAudio = index = 0
        SportsChips():RenderSportsCatalogs():return
    end if
    if pick.chip = 3
        if index = m.catalogs.Count() then m.browseProviders = true:SportsChips():RenderSportsCatalogs():return
        if index >= m.catalogs.Count() then return
        if index = 0
            m.top.pushRequest = {screen:"addonsScreen",params:{}}
        else
            OpenSportsCatalog(index)
        end if
        return
    end if
    if pick.chip = 0 and index < m.leagues.Count() then m.leagueIndex = index
    if pick.chip = 1 and index < m.days.Count() then m.dayIndex = index
    if pick.chip = 2 and index < m.states.Count() then m.stateIndex = index
    SportsChips()
    if pick.chip = 2 then RenderSportsRows() else SportsRequest()
end sub

function OnKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.filters.callFunc("IsMenuOpen") then return false
    if key = "options" or key = "left"
        m.filters.callFunc("FocusChips")
        return true
    end if
    if key = "down" and m.filters.callFunc("FocusIsOnChips")
        if m.rows.Count() > 0 then m.list.callFunc("SetListFocus")
        return true
    end if
    if key = "play" then SportsRequest():return true
    return false
end function

function OnBackPressed() as boolean
    if m.filters.callFunc("IsMenuOpen") then m.filters.callFunc("HideMenu"):return true
    m.desired = ""
    return false
end function

function OnExit() as void
    m.desired = ""
end function

sub BlurFocus()
    m.desired = ""
end sub

' Use the installed provider's catalogs and opaque IDs, not ESPN IDs. Nothing
' is installed here; Manage add-ons keeps the existing explicit import flow.
sub RenderSportsCatalogs()
    m.desired = ""
    m.rows = []
    content = CreateObject("roSGNode","ContentNode")
    for index = 0 to m.catalogs.Count() - 1
        entry = m.catalogs[index]
        m.rows.Push({catalogIndex:index})
        row = content.CreateChild("ContentNode"):item = row.CreateChild("ContentNode")
        item.title = entry.label
        item.description = "Open this provider's catalog"
        if index = 0 then item.description = "Import a provider you are authorized to use; no account required by Crimson"
    end for
    m.list.content = content
    m.status.text = "Provider listings are not playback guarantees · Play/Pause refreshes installed catalogs"
    if m.previousEventName <> invalid and m.previousEventName <> "" then m.status.text = "Find the same event: " + m.previousEventName
    ShowSportsCatalogDetail(0)
end sub

sub ShowSportsCatalogDetail(index as integer)
    if index < 0 or index >= m.catalogs.Count() then return
    m.name.text = m.catalogs[index].label
    if index = 0
        m.detail.text = "Use Add-ons to import a sports provider's HTTPS manifest. Return here to browse its own events. No third-party provider is installed automatically. Use the first filter for separate ESPN schedules."
        return
    end if
    m.detail.text = "OK opens the original provider catalog. Select an event, then a direct video source. Availability, rights and region depend on the provider. Browser-only links cannot play on Roku."
    if m.livePlayback = true
        m.detail.text = m.detail.text + Chr(10) + Chr(10) + "Live mode: start near the live edge; no resume or next episode. For replays, choose Playback: Recorded."
        if m.allowUnknownLiveAudio = true then m.detail.text = m.detail.text + Chr(10) + "English preferred. Unlabelled audio is allowed, with language unverified."
    end if
    if m.previousEventName <> invalid and m.previousEventName <> ""
        m.detail.text = "Match the teams, competition and Live/Recorded status before playing." + Chr(10) + Chr(10) + "Providers may share feeds. A second listing does not guarantee a working backup." + Chr(10) + Chr(10) + "OK opens this provider's own events. No automatic event matching."
    end if
end sub

sub OpenSportsCatalog(index as integer)
    if index < 0 or index >= m.catalogs.Count() then return
    if index = 0 then m.top.pushRequest = {screen:"addonsScreen",params:{}}:return
    params = {}
    for each key in m.catalogs[index].params
        params[key] = m.catalogs[index].params[key]
    end for
    params.livePlayback = m.livePlayback = true
    params.allowUnknownLiveAudio = m.allowUnknownLiveAudio = true
    params.previousEventName = m.previousEventName
    m.top.pushRequest = {screen:"discoverScreen",params:params}
end sub
