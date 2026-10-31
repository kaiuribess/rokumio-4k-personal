' A grouped front door over installed catalogs, sharing the original screen
' and player. One catalog worker remains owned until FINISHED, even on Back.
sub SportsBrowserInit()
    m.catalogView = "sports":m.catalogPage = 0
    m.browserMode = "groups":m.browserGroup = "":m.browserGroupLabel = ""
    m.browserEvents = []:m.browserQueue = []:m.browserMore = []:m.browserFailed = []
    m.browserTask = invalid:m.browserSequence = 0:m.browserGeneration = 0
    m.browserApplied = false:m.browserPage = 0:m.browserSelection = 0:m.browserRouteCount = 0
    m.browserSignature = "":m.browserClock = invalid:m.browserEpoch = 0
    m.browserSeen = {}:m.browserMatches = {}:m.browserSkipped = 0:m.browserNotices = 0
end sub

sub SportsBrowserReset()
    m.browserGeneration++
    m.browserMode = "groups":m.browserPage = 0:m.browserSelection = 0
    m.browserEvents = []:m.browserQueue = []:m.browserMore = []:m.browserFailed = []
    m.browserSeen = {}:m.browserMatches = {}:m.browserRouteCount = 0:m.browserSkipped = 0:m.browserNotices = 0
end sub

sub SportsBrowserEnter(params as dynamic)
    signature = FormatJson(m.catalogs)
    epoch = AccountEpoch_Read(m.top)
    if signature <> m.browserSignature or epoch <> m.browserEpoch then SportsBrowserReset():m.catalogPage = 0
    m.browserSignature = signature:m.browserEpoch = epoch
    if Type(params) = "roAssociativeArray"
        SportsBrowserReset()
        m.catalogView = "sports":m.catalogPage = 0
        if params.backupMode = true then m.catalogView = "providers"
    end if
    if m.catalogView = "sports" and m.browserMode = "events"
        if m.browserClock <> invalid
            if m.browserClock.TotalMilliseconds() >= 30000 then SportsBrowserStart(m.browserGroup,m.browserGroupLabel)
        end if
    end if
end sub

function SportsBrowserCurrent() as boolean
    return m.top.screenActive = true and m.browseProviders = true and m.catalogView = "sports" and AccountEpoch_Read(m.top) = m.browserEpoch
end function

sub SportsBrowserStart(groupKey as string, label as string)
    SportsBrowserReset()
    m.browserGroup = groupKey:m.browserGroupLabel = label:m.browserMode = "events"
    specific = []:mixed = []
    for each entry in m.catalogs
        if entry.params = invalid or entry.browseOnly = true then continue for
        if entry.recorded <> (m.livePlayback <> true) then continue for
        job = {entry:entry,offset:0,firstId:""}
        if entry.groupKey = groupKey
            specific.Push(job)
        else if entry.groupKey = "other" and groupKey <> "channels"
            mixed.Push(job)
        end if
    end for
    m.browserQueue.Append(specific):m.browserQueue.Append(mixed)
    m.browserClock = CreateObject("roTimespan"):m.browserClock.Mark()
    SportsBrowserRender():SportsBrowserPump()
    m.list.callFunc("SetListFocus")
end sub

sub SportsBrowserPump()
    if not SportsBrowserCurrent() or m.browserMode <> "events" or m.browserTask <> invalid then return
    if m.browserQueue.Count() = 0 or m.browserRouteCount > 192 then return
    m.browserJob = m.browserQueue.Shift()
    m.browserTaskGeneration = m.browserGeneration:m.browserApplied = false
    m.browserSequence++
    try
        m.browserTask = AsyncTask_Launch(m.top,"SportsCatalogTask","onSportsCatalogResult",{entry:m.browserJob.entry,offset:m.browserJob.offset},"sportsCatalog" + m.browserSequence.ToStr(),"onSportsCatalogFinished")
    catch e
        m.browserTask = invalid:m.browserFailed.Push(m.browserJob)
        m.browserNotices++
        m.browserFailed.Append(m.browserQueue):m.browserQueue = []
        SportsBrowserRender()
    end try
    SportsBrowserStatus()
end sub

sub onSportsCatalogResult(event as object)
    if m.browserTask = invalid then return
    task = event.GetRoSGNode()
    if task = invalid or task.id <> m.browserTask.id then return
    SportsBrowserApply(task.result)
end sub

sub SportsBrowserApply(packet as dynamic)
    if not SportsBrowserCurrent() or m.browserMode <> "events" then return
    if m.browserTaskGeneration <> m.browserGeneration or m.browserApplied = true then return
    if Type(packet) <> "roAssociativeArray" or Type(packet.events) <> "roArray" then return
    m.browserApplied = true
    job = m.browserJob
    if packet.ok <> true
        m.browserFailed.Push(job)
    else
        ' A server ignoring skip switches to bounded local slices of a fresh
        ' page-zero response. Never loop the same remote offset indefinitely.
        repeated = job.entry.skipSupported = true and job.offset > 0 and packet.firstId <> "" and packet.firstId = job.firstId
        if repeated
            localEntry = {}
            for each key in job.entry
                localEntry[key] = job.entry[key]
            end for
            localEntry.skipSupported = false
            m.browserQueue.Unshift({entry:localEntry,offset:job.offset,firstId:""})
        else
            for each item in packet.events
                if m.browserRouteCount >= 240 then exit for
                if m.browserGroup = "other" or item.category = m.browserGroup then SportsBrowserAddEvent(item)
            end for
            if packet.skipped <> invalid then m.browserSkipped = m.browserSkipped + packet.skipped
            if packet.hasMore = true and packet.nextOffset > job.offset
                m.browserMore.Push({entry:job.entry,offset:packet.nextOffset,firstId:packet.firstId})
            end if
        end if
    end if
    SportsBrowserRender()
end sub

sub onSportsCatalogFinished(event as object)
    if m.browserTask = invalid then return
    task = event.GetRoSGNode()
    if task = invalid or task.id <> m.browserTask.id or task.finished <> true then return
    SportsBrowserApply(task.result)
    if m.browserTaskGeneration = m.browserGeneration and m.browserApplied <> true
        if SportsBrowserCurrent() and m.browserMode = "events"
            m.browserFailed.Push(m.browserJob)
        else
            ' Covered by details/player: defer adoption and any more network
            ' work until the user returns to the event list.
            m.browserQueue.Unshift(m.browserJob)
        end if
    end if
    m.browserTask = invalid
    AsyncTask_Reap(task,m.top,false)
    SportsBrowserPump()
    if SportsBrowserCurrent() and m.browserMode = "events" then SportsBrowserRender()
end sub

sub SportsBrowserAddEvent(item as object)
    route = item.routes[0]
    identity = Sports_RouteIdentity(route)
    if m.browserSeen.DoesExist(identity) then return
    m.browserSeen[identity] = true:m.browserRouteCount++
    if item.matchKey <> "" and m.browserMatches.DoesExist(item.matchKey)
        index = m.browserMatches[item.matchKey]
        m.browserEvents[index].routes.Push(route)
        return
    end if
    if item.matchKey <> "" then m.browserMatches[item.matchKey] = m.browserEvents.Count()
    m.browserEvents.Push(item)
end sub

sub SportsBrowserStatus()
    if m.browserMode <> "events" then return
    text = m.browserGroupLabel + " · " + m.browserEvents.Count().ToStr() + " listings"
    if m.browserTask <> invalid or m.browserQueue.Count() > 0 then text = text + " · Loading catalogs…"
    if m.browserRouteCount > 192 and (m.browserQueue.Count() > 0 or m.browserMore.Count() > 0) then text = m.browserGroupLabel + " · More events available in the next batch"
    if m.browserFailed.Count() > 0 then text = text + " · " + m.browserFailed.Count().ToStr() + " catalog(s) failed; retry below"
    if m.browserNotices > 0 or m.browserSkipped > 0 then text = text + " · Some entries unavailable; provider browsing remains available"
    m.status.text = text
end sub

sub SportsBrowserRow(content as object, entry as object, title as string, description as string)
    m.rows.Push(entry)
    row = content.CreateChild("ContentNode"):item = row.CreateChild("ContentNode")
    item.title = title:item.description = description
end sub

function SportsBrowserRowKey(row as object) as string
    if row.kind = invalid then return ""
    if row.kind = "event" or row.kind = "route" then return row.kind + ":" + row.index.ToStr()
    if row.kind = "group" then return row.kind + ":" + row.key
    return row.kind
end function

sub SportsBrowserRender(focusOverride = -1 as integer)
    focused = 0
    if Type(m.list.rowItemFocused) = "roArray" and m.list.rowItemFocused.Count() > 0 then focused = m.list.rowItemFocused[0]
    focusKey = ""
    if focusOverride < 0 and focused >= 0 and focused < m.rows.Count() then focusKey = SportsBrowserRowKey(m.rows[focused])
    if focusOverride >= 0 then focused = focusOverride
    content = CreateObject("roSGNode","ContentNode"):m.rows = []
    if m.browserMode = "groups"
        available = {}
        for each entry in m.catalogs
            if entry.params <> invalid and entry.browseOnly <> true
                if entry.recorded = (m.livePlayback <> true) then available[entry.groupKey] = true
            end if
        end for
        for each group in Sports_Groups()
            if available.DoesExist(group.key) then SportsBrowserRow(content,{kind:"group",key:group.key,label:group.label,detail:group.detail},group.label,group.detail)
        end for
        SportsBrowserRow(content,{kind:"providers"},"Browse by provider","Original catalogs and channels · advanced browsing")
        SportsBrowserRow(content,{kind:"addons"},"Manage add-ons","Add or manage your sports providers")
        m.status.text = "Choose a sport · Listings come from your installed providers"
    else if m.browserMode = "events"
        start = m.browserPage * 48:last = start + 48
        if last > m.browserEvents.Count() then last = m.browserEvents.Count()
        for i = start to last - 1
            event = m.browserEvents[i]
            description = event.phase + " (provider) · " + event.routes[0].provider
            if event.phase = "Status unverified" then description = event.phase + " · " + event.routes[0].provider
            if event.routes.Count() > 1 then description = description + " · " + event.routes.Count().ToStr() + " providers"
            SportsBrowserRow(content,{kind:"event",index:i},event.name,description)
        end for
        if m.browserPage > 0 then SportsBrowserRow(content,{kind:"previous"},"Previous page","Earlier listings in this batch")
        if last < m.browserEvents.Count() then SportsBrowserRow(content,{kind:"next"},"Next page","More games and events")
        if m.browserTask = invalid and m.browserQueue.Count() = 0 and m.browserMore.Count() > 0
            SportsBrowserRow(content,{kind:"load"},"More events","Load the next provider pages")
        else if m.browserRouteCount > 192 and m.browserTask = invalid and m.browserQueue.Count() > 0
            SportsBrowserRow(content,{kind:"load"},"More events","Next batch · earlier events remain in provider browsing")
        end if
        if m.browserFailed.Count() > 0 then SportsBrowserRow(content,{kind:"retry"},"Retry unavailable catalogs","Keep loaded games and retry failed providers")
        if m.browserEvents.Count() = 0
            emptyTitle = "No events available"
            emptyDetail = "Try another sport, refresh or browse provider catalogs"
            if m.browserTask <> invalid or m.browserQueue.Count() > 0 then emptyTitle = "Loading events…":emptyDetail = "Back returns immediately"
            SportsBrowserRow(content,{kind:"status"},emptyTitle,emptyDetail)
        end if
        SportsBrowserRow(content,{kind:"providers"},"Browse other catalogs","Original provider listings and uncategorized events")
        SportsBrowserStatus()
    else
        event = m.browserEvents[m.browserSelection]
        if m.browserMode = "event"
            SportsBrowserRow(content,{kind:"watch"},"Watch","Automatically choose a compatible source from " + event.routes[0].provider)
            SportsBrowserRow(content,{kind:"sources"},"More sources","Choose a provider or stream manually")
        else
            for i = 0 to event.routes.Count() - 1
                SportsBrowserRow(content,{kind:"route",index:i},event.routes[i].provider,"Choose a stream for " + event.name)
            end for
            SportsBrowserRow(content,{kind:"providers"},"Browse another provider","Find the same event manually; uncertain matches stay separate")
        end if
        m.status.text = event.name + " · " + event.phase
    end if
    if focusKey <> ""
        focused = 0
        for i = 0 to m.rows.Count() - 1
            if SportsBrowserRowKey(m.rows[i]) = focusKey then focused = i:exit for
        end for
    end if
    if focused >= m.rows.Count() then focused = 0
    m.list.content = content
    m.list.callFunc("FocusRow",focused)
    SportsBrowserDetail(focused)
end sub

sub SportsBrowserDetail(index as integer)
    if index < 0 or index >= m.rows.Count() then return
    row = m.rows[index]
    if m.browserMode = "event" or m.browserMode = "sources"
        event = m.browserEvents[m.browserSelection]
    else if row.kind = "event"
        event = m.browserEvents[row.index]
    else
        m.name.text = "Sports"
        m.detail.text = "Choose a sport, select a game, then Watch. More sources keeps manual stream selection available. Listings and status come from providers; availability can change."
        if row.kind = "group" then m.name.text = row.label:m.detail.text = row.detail + Chr(10) + Chr(10) + "Games from your installed providers, in one list."
        if row.kind = "providers" then m.name.text = "Provider catalogs":m.detail.text = "Browse each provider's original catalogs. Use this for channels, unclassified events or a manual backup. Match the event before playing."
        return
    end if
    m.name.text = event.name
    m.detail.text = event.phase + " · Provider-reported" + Chr(10) + event.competition + Chr(10) + event.start + Chr(10) + Chr(10) + "Watch chooses within " + event.routes[0].provider + ". More sources opens manual choices. No automatic switch to another provider's game."
    if event.phase = "Status unverified" then m.detail.text = "Time/status unverified" + Chr(10) + Chr(10) + "Watch checks " + event.routes[0].provider + " for fresh sources. More sources opens manual choices."
end sub

sub SportsBrowserSelect(index as integer)
    if not SportsBrowserCurrent() or index < 0 or index >= m.rows.Count() then return
    row = m.rows[index]
    if row.kind = "group" then SportsBrowserStart(row.key,row.label):return
    if row.kind = "addons" then m.top.pushRequest = {screen:"addonsScreen",params:{}}:return
    if row.kind = "providers"
        m.catalogView = "providers":m.catalogPage = 0
        SportsChips():RenderSportsCatalogs():m.list.callFunc("SetListFocus"):return
    end if
    if row.kind = "event"
        m.browserSelection = row.index:m.browserMode = "event"
        SportsBrowserRender(0):m.list.callFunc("SetListFocus"):return
    end if
    if row.kind = "sources" then m.browserMode = "sources":SportsBrowserRender(0):return
    if row.kind = "watch" or row.kind = "route"
        event = m.browserEvents[m.browserSelection]
        if m.livePlayback = true and (event.phase = "Upcoming" or event.phase = "Postponed / cancelled")
            m.status.text = event.phase + " · Refresh near the event's start time":return
        end if
        routeIndex = 0
        if row.kind = "route" then routeIndex = row.index
        route = event.routes[routeIndex]
        if m.livePlayback <> true
            ' Recorded catalogs retain the established metadata/details route.
            m.top.pushRequest = {screen:"detailsScreen",params:{addonAddress:route.addonAddress,meta:{id:route.metaId,type:route.metaType,name:route.name,poster:route.poster}}}
        else
            m.top.pushRequest = {screen:"streamsScreen",params:Sports_WatchRequest(route,row.kind = "watch",true,m.allowUnknownLiveAudio = true)}
        end if
        return
    end if
    if row.kind = "next" then m.browserPage++
    if row.kind = "previous" then m.browserPage--
    if row.kind = "load"
        if m.browserRouteCount > 192
            m.browserEvents = []:m.browserSeen = {}:m.browserMatches = {}:m.browserRouteCount = 0:m.browserPage = 0
        end if
        m.browserQueue.Append(m.browserMore):m.browserMore = []
    end if
    if row.kind = "retry" then m.browserQueue.Append(m.browserFailed):m.browserFailed = []
    SportsBrowserRender(0):SportsBrowserPump()
end sub

function SportsBrowserBack() as boolean
    if m.catalogView = "providers"
        m.catalogView = "sports":m.catalogPage = 0
        SportsChips():SportsBrowserRender():SportsBrowserPump():m.list.callFunc("SetListFocus"):return true
    end if
    if m.browserMode = "sources" then m.browserMode = "event":SportsBrowserRender(0):return true
    if m.browserMode = "event"
        m.browserMode = "events":SportsBrowserRender(m.browserSelection mod 48):SportsBrowserPump():return true
    end if
    if m.browserMode = "events"
        SportsBrowserReset():SportsBrowserRender():return true
    end if
    return false
end function
