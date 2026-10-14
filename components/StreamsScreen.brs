' StreamsScreen — the stream picker behind every Play/Resume action.
'
' The left panel renders the media entirely from params the pusher already had:
' title, the episode line for series, synopsis, and the Cinemeta background
' artwork (deliberately no poster). The pusher hands over what it knows — the
' movie plays its description and runtime, EpisodesScreen the episode name and
' overview it just fetched — so the panel is full the instant the screen
' opens. The right side lists ranked choices grouped by eligible stream add-on.
' The shared coordinator queues providers within a two-worker budget.
' OK drops straight into the PlayerScreen: the torrent is resolved
' there (logo pulse while its engine warms up), so the picker answers instantly
' and a resolution failure stays on the player with a message instead of
' bouncing back here.
'
' Source-list networking runs on worker tasks. Results appear progressively;
' queued work pauses behind Player. Two occupied slots can delay later providers.
' The player owns playback resolution, not the source-list scheduler.
'
' Params: { addonAddress, metaType, metaId, videoId, season, episode, position,
'           name, poster, logo, background }, plus the panel's data where the
'           pusher holds it: description + runtime (movie), and episodeName +
'           episodeOverview (series from EpisodesScreen). A series push straight
'           from Details (Play/Resume, so no video list travelled) enriches the
'           panel with the same two fields via a parallel MetaLoaderTask — the
'           right-side stream list never waits on it.

sub init()
    m.providerStatus = m.top.FindNode("providerStatus")
    m.headTitle = m.top.FindNode("headTitle")
    m.headSub = m.top.FindNode("headSub")
    m.synopsis = m.top.FindNode("synopsis")
    m.status = m.top.FindNode("status")
    m.bgPoster = m.top.FindNode("bgPoster")
    m.streamsList = m.top.FindNode("streamsList")
    m.arrowLeft = m.top.FindNode("arrowLeft")
    m.arrowRight = m.top.FindNode("arrowRight")
    m.providerName = m.top.FindNode("providerName")
    m.providerSegments = m.top.FindNode("providerSegments")
    m.streamsPlaceholder = m.top.FindNode("streamsPlaceholder")
    m.bg = m.top.FindNode("streamBg")
    m.scrim = m.top.FindNode("bgScrim")
    m.qualityHint = m.top.FindNode("qualityHint")
    m.fourKOnly = false

    t = Theme()
    m.bg.color = t.screenBg
    m.scrim.color = t.scrim
    m.headTitle.color = t.textPrimary
    m.headSub.color = t.accent
    m.synopsis.color = t.textSecondary
    m.status.color = t.accent
    m.providerName.color = t.textPrimary
    m.streamsPlaceholder.color = t.textSecondary
    m.qualityHint.color = t.accentInfo

    m.streamsList.ObserveField("rowItemSelected", "onStreamSelected")
    m.streamsList.ObserveField("rowItemFocused", "onSourceRowFocused")

    m.streams = []
    m.sourcePage = 0
    m.sourceRows = []
    m.pageFocusTarget = invalid
    m.pageSelectionBlocked = invalid
    m.hasSourcePaging = false
    m.loadTasks = invalid
    m.loadKey = ""
    m.loadContextKey = ""
    m.loadSeq = 0
    m.loadToken = ""
    m.providers = invalid
    m.providersTotal = 0
    m.pendingCount = 0
    m.listFilled = false
    m.activeIndex = -1
    m.segments = []
    m.epMetaTask = invalid
    m.selectionTask = invalid
    m.autoPlayEnabled = false
    m.autoPlaySent = false
    m.prefetchNode = invalid
    m.prefetchContext = invalid
    m.prefetchWaiting = []
    m.sourceQueue = []
    m.sourcesSuspended = false
    m.sourceRevision = 0
    m.selectionRevision = -1
    m.selectionSequence = 0
    m.autoGraceTimer = m.top.FindNode("autoPlayGrace")
    m.autoGraceTimer.ObserveField("fire","onAutomaticGrace")
    m.autoClock = CreateObject("roTimespan")
    m.autoClock.Mark()
    m.autoGraceDeadline = invalid
    m.autoGraceToken = ""
    UpdateQualityHint()
end sub

function OnEnter(params as object) as void
    ' Re-entry after the player pops: params is invalid and the Group was given
    ' focus by the stack. The stream list must take it back.
    if params = invalid
        m.sourcesSuspended = false
        if m.reloadNeeded = true
            m.reloadNeeded = false
            LoadStreams(m.params,false)
            ResetProviderNavigation()
        end if
        if m.prefetchNode <> invalid and m.prefetchContext <> invalid
            reentryContext = SourcePrefetch_Context(m.stores,m.params)
            if reentryContext <> invalid and reentryContext.key = m.prefetchContext.key then m.prefetchNode.callFunc("SetPriority",reentryContext.key,reentryContext.providerPriority)
            m.prefetchNode.callFunc("Resume",m.prefetchContext.key)
        end if
        onSourcePrefetchChanged()
        PumpProviderSources()
        RenderActiveProvider()
        MaybeStartAutomaticPlayback()
        RestoreFocus()
        return
    end if

    ' Same episode, batch still in flight: let it finish instead of restarting
    ' it. This screen is not reaped between visits, and StopStreamsLoad below
    ' would re-fetch every provider from scratch — but STOP does not interrupt an
    ' roUrlTransfer, so the batch being abandoned keeps its sockets open and
    ' keeps fetching after this screen has forgotten it. The cost is not a wrong
    ' list, it is a second identical request per add-on: four copies of the same
    ' torrentio manifest inside one device log is exactly this.
    '
    ' m.loadTasks is emptied as providers land (see onStreamsLoaded), so this
    ' only ever holds while there is genuinely something in flight to wait for.
    ' A different episode, or a revisit to a batch that already reported in, falls
    ' through and rebuilds as before.
    currentContext = SourcePrefetch_Context(m.stores, params)
    sameContext = currentContext <> invalid and currentContext.key = m.loadContextKey
    if m.pendingCount > 0 and m.loadKey <> "" and EpisodeKey(params) = m.loadKey and sameContext
        m.sourcesSuspended = false
        if m.prefetchNode <> invalid and m.prefetchContext <> invalid
            m.prefetchNode.callFunc("SetPriority",currentContext.key,currentContext.providerPriority)
            m.prefetchNode.callFunc("Resume",m.prefetchContext.key)
        end if
        onSourcePrefetchChanged()
        PumpProviderSources()
        MaybeStartAutomaticPlayback()
        RestoreFocus()
        return
    end if

    CancelStreamsLoad()
    CancelEpisodeLoad()
    m.params = params
    m.fourKOnly = PlaybackPreferences(m.stores,params).fourKOnly
    m.autoPlayEnabled = params.autoPlay = true
    m.autoPlaySent = false
    m.sourcesSuspended = false
    ApplyParamsChrome(params)

    m.streams = []
    m.listFilled = false
    EmptyStreamsList()

    LoadStreams(params)
    StartEpisodeLoad(params)
    ResetProviderNavigation()
end function

' Build the left panel instantly from the params the pusher already had — title,
' the SxE action line (or "Movie"), the background artwork Details/Episodes were
' already showing, and the synopsis data the pusher held (movie description, or
' the episode the EpisodesScreen had already fetched). Missing data leaves a
' placeholder instead of a blank panel — no fetch ever fills this pane.
sub ApplyParamsChrome(params as object)
    name = params.name
    if name = invalid then name = ""
    m.headTitle.text = name

    bg = params.background
    if bg = invalid then bg = ""
    m.bgPoster.uri = bg

    action = ""
    synopsis = ""
    if params.metaType = "series"
        season = ParamString(params.season)
        episode = ParamString(params.episode)
        if season <> "" or episode <> ""
            action = "S" + season + "E" + episode
        end if
        episodeName = params.episodeName
        if episodeName <> invalid and episodeName <> ""
            if action <> "" then action = action + "  " + episodeName else action = episodeName
        end if
        episodeOverview = params.episodeOverview
        if episodeOverview <> invalid and episodeOverview <> "" then synopsis = episodeOverview
    else if params.metaType <> invalid and params.metaType <> ""
        action = "Movie"
        description = params.description
        if description <> invalid and description <> "" then synopsis = description
        runtime = params.runtime
        if runtime <> invalid and runtime <> ""
            formatted = FormatRuntime(runtime)
            if formatted <> "" then action = "Movie  ·  " + formatted
        end if
    end if
    m.headSub.text = action

    if synopsis = "" then synopsis = "No synopsis available."
    m.synopsis.text = synopsis
end sub

' Deterministically blank the stream list: a fresh empty content node, so no
' previously rendered cards can linger while the new load is in flight.
sub EmptyStreamsList()
    content = CreateObject("roSGNode", "ContentNode")
    m.streamsList.content = content
    m.streamsList.numRows = 0
    ResetSourcePagination()
end sub

' Kick the stream-list fetches off the render thread. The coordinator owns up
' to two source-list workers — each answers with its own { streams,
' error } the instant that address responds, and onStreamsLoaded routes it into
' the matching provider slot. The installed add-ons are read here (registry reads
' only, no network) so only the addresses that can actually serve a stream for
' this exact media cross into the tasks: the add-on must advertise the "stream"
' resource and its declared types AND idPrefixes must cover this media (Stremio's
' own resource matching). A live-TV add-on is never asked for a movie/series
' stream, a movie/series add-on is never asked for a channel, and an add-on
' whose idPrefixes exclude this id (say "tt"/"kitsu" on a YouTube id) is never
' asked at all. Failure handling mirrors Home: on total failure the grid
' stays empty. Slow occupied slots can delay providers still in the queue.
sub LoadStreams(params as object, allowPrefetch = true as boolean)
    if m.stores = invalid then return
    if m.loadTasks <> invalid and m.loadTasks.Count() > 0 then return
    ResetSourcePagination()
    m.hasSourcePaging = false
    m.audioMode = CurrentAudioMode()
    requestContext = SourcePrefetch_Context(m.stores, params)
    m.loadContextKey = ""
    if requestContext <> invalid then m.loadContextKey = requestContext.key

    providers = []
    for each addon in m.stores.addons.callFunc("AddonsGetAll")
        if m.stores.addons.callFunc("AddonsSupportsResource", addon.resources, addon.types, addon.idPrefixes, "stream", ParamString(params.metaType), ParamString(params.videoId))
            if addon.address <> invalid and addon.address <> ""
                name = AddonDiagnostics_Name(addon)
                providers.Push({ name: name, id: ParamString(addon.id), address: addon.address, streams: [], error: "" })
            end if
        end if
    end for

    m.providers = providers
    m.providersTotal = providers.Count()
    m.pendingCount = providers.Count()
    m.loadError = ""
    m.loadTasks = []
    m.loadKey = EpisodeKey(params)
    ' A token per batch, not per episode. Two passes over the SAME episode (the
    ' user backing out and re-entering) must not be able to accept each other's
    ' reports, so the token cannot be the key — it counts passes instead.
    ' Monotonic rather than a random or blank-able value: only this screen
    ' writes it, and a task can outlive a hundred navigations, so the value has
    ' to keep differing for as long as the component lives. A counter toStr()'d
    ' is the cheapest thing that cannot repeat.
    m.loadSeq = m.loadSeq + 1
    m.loadToken = m.loadSeq.ToStr()

    m.prefetchWaiting = []
    m.sourceQueue = []
    m.sourceRevision = 0
    m.selectionRevision = -1
    CancelAutomaticGrace()
    for i = 0 to providers.Count() - 1
        m.loadTasks.Push(invalid)
        m.prefetchWaiting.Push(false)
    end for
    snapshot = invalid
    if requestContext <> invalid
        m.prefetchContext = requestContext
        m.prefetchNode = SourcePrefetch_Node(m.top)
        if m.prefetchNode <> invalid and m.prefetchContext <> invalid
            m.prefetchNode.ObserveField("revision", "onSourcePrefetchChanged")
            if not allowPrefetch then m.prefetchNode.callFunc("Cancel",m.prefetchContext.key)
            snapshot = m.prefetchNode.callFunc("Adopt", m.prefetchContext)
        end if
    end if

    for i = 0 to providers.Count() - 1
        entry = invalid
        if Type(snapshot) = "roAssociativeArray" and Type(snapshot.entries) = "roArray"
            if i < snapshot.entries.Count() then entry = snapshot.entries[i]
        end if
        if Type(entry) = "roAssociativeArray" and entry.status = "ready"
            ApplyProviderSources(i, entry.result)
        else if Type(entry) = "roAssociativeArray" and (entry.status = "pending" or entry.status = "queued")
            m.prefetchWaiting[i] = true
        else if Type(entry) = "roAssociativeArray" and entry.status = "failed"
            ApplyProviderSources(i, entry.result)
        else
            m.sourceQueue.Push(i)
        end if
    end for
    PumpProviderSources()

    UpdateStreamsStatus()
    MaybeStartAutomaticPlayback()
end sub

' A Play action adopts the coordinator's already-running source-list request.
' It never adopts a movie decoder or starts a second copy of a pending lookup.
sub LaunchProviderSources(index as integer)
    if m.sourcesSuspended = true or not m.top.screenActive then return
    if m.loadTasks = invalid or m.providers = invalid then return
    if index < 0 or index >= m.providers.Count() or index >= m.loadTasks.Count() then return
    if m.loadTasks[index] <> invalid then return
    provider = m.providers[index]
    m.loadTasks[index] = AsyncTask_Launch(m.top, "StreamsLoaderTask", "onStreamsLoaded", {
        metaType:ParamString(m.params.metaType), videoId:ParamString(m.params.videoId),
        addonAddress:provider.address, providerIndex:index, providerName:provider.name,
        providerId:provider.id, loadToken:m.loadToken, audioMode:m.audioMode
    }, "streamsLoader" + m.loadToken + "_" + index.ToStr())
end sub

' Fallback for isolated screens with no Scene coordinator. Production requests
' all use the coordinator, including warm adoption and abandoned transfers.
sub PumpProviderSources()
    if m.sourcesSuspended = true or not m.top.screenActive then return
    if m.prefetchNode <> invalid or Type(m.sourceQueue) <> "roArray" then return
    active = 0
    if Type(m.loadTasks) = "roArray"
        for each task in m.loadTasks
            if task <> invalid then active = active + 1
        end for
    end if
    while active < 2 and m.sourceQueue.Count() > 0
        index = m.sourceQueue.Shift()
        LaunchProviderSources(index)
        active = active + 1
    end while
end sub


sub ApplyProviderSources(index as integer, result as dynamic)
    if m.providers = invalid or index < 0 or index >= m.providers.Count() then return
    if Type(result) <> "roAssociativeArray" then return
    provider = m.providers[index]
    provider.readyStreams = result.readyStreams
    if Type(result.streams) = "roArray" then provider.streams = result.streams
    if result.error <> invalid and result.error <> ""
        provider.error = result.error
        if m.loadError = "" then m.loadError = result.error
    end if
    if m.pendingCount > 0 then m.pendingCount = m.pendingCount - 1
    if m.sourceRevision = invalid then m.sourceRevision = 0
    m.sourceRevision = m.sourceRevision + 1
end sub

sub onSourcePrefetchChanged()
    if m.loadToken = "" or m.prefetchNode = invalid or m.prefetchContext = invalid then return
    context = SourcePrefetch_Context(m.stores, m.params)
    if context = invalid or context.key <> m.prefetchContext.key
        ' Settings/add-ons changed: never apply the former configuration.
        CancelStreamsLoad()
        if m.sourcesSuspended = true or not m.top.screenActive
            m.reloadNeeded = true
            return
        end if
        LoadStreams(m.params, false)
        ResetProviderNavigation()
        return
    end if
    m.prefetchNode.callFunc("SetPriority",context.key,context.providerPriority)
    snapshot = m.prefetchNode.callFunc("Snapshot", context.key)
    for i = 0 to m.prefetchWaiting.Count() - 1
        if m.prefetchWaiting[i] <> true then continue for
        entry = invalid
        if Type(snapshot) = "roAssociativeArray" and Type(snapshot.entries) = "roArray"
            if i < snapshot.entries.Count() then entry = snapshot.entries[i]
        end if
        if Type(entry) = "roAssociativeArray" and (entry.status = "pending" or entry.status = "queued") then continue for
        m.prefetchWaiting[i] = false
        if Type(entry) = "roAssociativeArray" and (entry.status = "ready" or entry.status = "failed")
            ApplyProviderSources(i, entry.result)
            if i = m.activeIndex and m.top.screenActive and m.sourcesSuspended <> true then RenderActiveProvider()
        else
            ' Error/expiry/cancellation requires a fresh normal request on Play.
            m.sourceQueue.Push(i)
        end if
    end for
    PumpProviderSources()
    if m.top.screenActive and m.sourcesSuspended <> true then UpdateStreamsStatus()
    MaybeStartAutomaticPlayback()
end sub

sub CancelAutomaticGrace()
    if m.autoGraceTimer <> invalid then m.autoGraceTimer.control = "stop"
    m.autoGraceDeadline = invalid
    m.autoGraceToken = ""
end sub

sub onAutomaticGrace()
    if m.autoGraceToken <> m.loadToken or m.autoGraceDeadline = invalid then return
    if m.sourcesSuspended = true or not m.top.screenActive then return
    if not SourcePrefetch_DelayReady(m.autoGraceTimer,m.autoClock,m.autoGraceDeadline) then return
    MaybeStartAutomaticPlayback()
end sub

sub MaybeStartAutomaticPlayback()
    if not m.top.screenActive or m.sourcesSuspended = true then return
    if m.autoPlayEnabled <> true or m.autoPlaySent = true then return
    if m.selectionTask <> invalid then return
    if m.selectionRevision = m.sourceRevision then return
    pool = []
    readyCount = 0
    if m.providers <> invalid
        for each provider in m.providers
            if Type(provider.streams) = "roArray"
                for each stream in provider.streams
                    pool.Push(stream)
                end for
            end if
            if Type(provider.readyStreams) = "roArray" then readyCount = readyCount + CinemaFilterReadyStreams(provider.readyStreams,m.fourKOnly).Count()
        end for
    end if
    prefs = PlaybackPreferences(m.stores,m.params)
    if m.pendingCount > 0
        if prefs.waitForProviders = true or readyCount = 0 then return
        if m.autoGraceDeadline = invalid
            if m.autoClock <> invalid then m.autoGraceDeadline = m.autoClock.TotalMilliseconds() + 750
            m.autoGraceToken = m.loadToken
            if m.autoGraceTimer <> invalid and m.autoClock <> invalid
                m.autoGraceTimer.duration = 0.75
                m.autoGraceTimer.control = "start"
                return
            end if
        end if
        if not SourcePrefetch_DelayReady(m.autoGraceTimer,m.autoClock,m.autoGraceDeadline) then return
    end if
    CancelAutomaticGrace()
    m.selectionRevision = m.sourceRevision
    if m.selectionSequence = invalid then m.selectionSequence = 0
    m.selectionSequence = m.selectionSequence + 1
    m.selectionTask = AsyncTask_Launch(m.top, "SourceSelectionTask", "onAutomaticSourcesReady", {streams:pool,videoId:ParamString(m.params.videoId),audioMode:CurrentAudioMode(),fourKOnly:m.fourKOnly,loadToken:m.loadToken}, "automaticSources" + m.loadToken + "_" + ParamString(m.selectionSequence))
end sub

sub onAutomaticSourcesReady(event as object)
    if m.selectionTask = invalid then return
    task = event.GetRoSGNode()
    if task = invalid or task.id <> m.selectionTask.id or task.loadToken <> m.loadToken then return
    result = event.GetData()
    if Type(result) <> "roAssociativeArray" then return
    m.selectionTask = invalid
    AsyncTask_Reap(task, m.top, false)
    if not m.top.screenActive or m.sourcesSuspended = true or m.autoPlayEnabled <> true or m.autoPlaySent = true then return
    if task.fourKOnly <> m.fourKOnly or task.audioMode <> CurrentAudioMode()
        m.selectionRevision = -1
        MaybeStartAutomaticPlayback()
        return
    end if
    if Type(result.streams) <> "roArray" or result.streams.Count() = 0
        if m.pendingCount = 0 then m.status.text = "No compatible source candidates found. Play/Pause checks fresh links; Back cancels."
        MaybeStartAutomaticPlayback()
        return
    end if
    m.autoPlaySent = true
    SuspendSourceLoading()
    PushAutomaticPlayer(result.streams[0], result.streams, result.rememberedSource = true)
end sub

sub PushAutomaticPlayer(first as object, candidates as object, remembered = false as boolean)
    serverAddress = ""
    prefs = PlaybackPreferences(m.stores,m.params)
    if m.stores <> invalid then serverAddress = m.stores.settings.callFunc("SettingsGetServerAddress")
    m.top.pushRequest = {screen:"playerScreen",params:{stream:first,candidates:candidates,rememberedSource:remembered,fourKOnly:m.fourKOnly = true,serverAddress:serverAddress,audioMode:CurrentAudioMode(),diagnostic:m.params.diagnostic = true,metaType:m.params.metaType,metaId:m.params.metaId,videoId:m.params.videoId,season:m.params.season,episode:m.params.episode,position:m.params.position,name:m.headTitle.text,poster:m.params.poster,posterShape:m.params.posterShape,logo:m.params.logo,background:m.params.background,addonAddress:m.params.addonAddress,seriesMeta:m.params.seriesMeta,autoNextEpisode:prefs.autoNextEpisode,autoSourceRetry:prefs.autoSourceRetry,waitForProviders:prefs.waitForProviders}}
end sub

' A single provider's stream list landed (or failed). The task reports which
' provider it was via its providerIndex slot; results can arrive in any order.
' A stale result that landed after CancelStreamsLoad is dropped by the slot
' guard — the slot was cleared, so nothing applies. Only the active provider's
' landing re-renders the list; the status line keeps counting down regardless.
sub onStreamsLoaded(event as object)
    if m.loadTasks = invalid then return
    task = event.GetRoSGNode()
    if task = invalid then return
    ' Which batch this report belongs to, before anything else. A cancelled batch
    ' cannot be interrupted mid-transfer — STOP does not reach an roUrlTransfer —
    ' so its workers can still report in after a later episode has launched a new
    ' batch, and providerIndex alone cannot tell the two apart: the index is only
    ' unique WITHIN a batch, so an old worker's index can land squarely inside the
    ' new list. Accepted blindly, it would take a live task's slot, push the
    ' previous episode's streams into this episode's provider, and never decrement
    ' pendingCount.
    '
    ' Compared as a scalar, not as nodes. roSGNode offers no identity test — the
    ' reference lists ifAssociativeArray, ifSGNodeChildren, ifSGNodeField,
    ' ifSGNodeDict, ifSGNodeFocus, ifSGNodeBoundingRect and
    ' ifSGNodeHttpAgentAccess, with no IsSame, and `m.loadTasks[index] <> task`
    ' between two nodes is a runtime &h18 Type Mismatch. The device rejected both
    ' attempts at this comparison before the token was introduced. Stamping the
    ' batch onto each task at launch (see loadToken) is the way that is actually
    ' expressible.
    if m.loadToken = "" or task.loadToken <> m.loadToken then return
    index = task.providerIndex
    if index < 0 or index >= m.loadTasks.Count() then return
    ' Already claimed by whichever task actually owned this slot: a provider
    ' reports once, and a duplicate notification for it has nothing to add. This
    ' also has to precede m.loadTasks[index] = invalid, because an empty slot is
    ' what tells a repeat apart from a first arrival.
    if m.loadTasks[index] = invalid then return
    ' alwaysNotify can report before the worker has published its answer.
    result = task.result
    if Type(result) <> "roAssociativeArray" then return
    m.loadTasks[index] = invalid
    AsyncTask_Reap(task, m.top, false)
    if m.providers = invalid or index >= m.providers.Count() then
        ' Counted as landed above, so the count stays honest even though there is
        ' no longer a provider slot to write into.
        if m.pendingCount > 0 then m.pendingCount = m.pendingCount - 1
        return
    end if

    ApplyProviderSources(index, result)
    if index = m.activeIndex and m.top.screenActive and m.sourcesSuspended <> true then RenderActiveProvider()
    PumpProviderSources()
    if m.top.screenActive and m.sourcesSuspended <> true then UpdateStreamsStatus()
    MaybeStartAutomaticPlayback()
end sub

' Fresh push: point the header at the first provider (known synchronously from
' LoadStreams' registry pass) and render its section. A re-entry after the
' player pops skips this and only restores focus (OnEnter's invalid-params
' branch), so the last-viewed provider is preserved.
sub ResetProviderNavigation()
    ResetSourcePagination()
    if m.providers = invalid or m.providers.Count() = 0
        m.activeIndex = -1
        m.streams = []
        EmptyStreamsList()
        m.streamsPlaceholder.text = "No stream add-ons installed."
        m.streamsPlaceholder.visible = true
        UpdateHeader()
        return
    end if
    m.activeIndex = 0
    m.listFilled = false
    UpdateHeader()
    RenderActiveProvider()
end sub

' Move the header and list onto another provider.
sub SelectProvider(index as integer)
    if m.providers = invalid or m.activeIndex < 0 then return
    if index < 0 or index >= m.providers.Count() then return
    if index = m.activeIndex then return
    m.activeIndex = index
    ResetSourcePagination()
    UpdateHeader()
    RenderActiveProvider()
end sub

' Cached links can expire and new releases can become available while this
' screen stays open. An explicit remote refresh starts a new provider batch;
' its monotonic token rejects late results from the canceled request.
sub RefreshStreams()
    if m.params = invalid or m.stores = invalid then return
    selectedAddress = ""
    if m.providers <> invalid and m.activeIndex >= 0 and m.activeIndex < m.providers.Count() then selectedAddress = ParamString(m.providers[m.activeIndex].address)
    CancelStreamsLoad()
    m.streams = []
    m.listFilled = false
    EmptyStreamsList()
    ' Remote refresh discards even a successful in-memory prefetch.
    SourcePrefetch_Cancel(m.top, SourcePrefetch_Context(m.stores, m.params))
    LoadStreams(m.params, false)
    UpdateQualityHint()
    ResetProviderNavigation()
    if selectedAddress <> "" and m.providers <> invalid
        for i = 0 to m.providers.Count() - 1
            if ParamString(m.providers[i].address) = selectedAddress
                SelectProvider(i)
                exit for
            end if
        end for
    end if
end sub

' Header chrome for the active provider: its name, arrows only for the
' directions the user can actually move, and the segment dots marking the
' position. The dots rebuild only when the provider count changes; the active
' slot just repaints.
sub UpdateHeader()
    if m.providers = invalid then return

    if m.activeIndex < 0 or m.activeIndex >= m.providers.Count()
        m.providerName.text = ""
        m.arrowLeft.visible = false
        m.arrowRight.visible = false
        if m.providerSegments <> invalid then m.providerSegments.visible = false
        return
    end if

    provider = m.providers[m.activeIndex]
    name = provider.name
    if name = invalid or name = "" then name = "Source provider"
    m.providerName.text = name

    m.arrowLeft.visible = m.activeIndex > 0
    m.arrowRight.visible = m.activeIndex < m.providers.Count() - 1

    if m.segments.Count() <> m.providers.Count() then RebuildSegments()
    m.providerSegments.visible = m.segments.Count() > 1
    t = Theme()
    for i = 0 to m.segments.Count() - 1
        if i = m.activeIndex
            m.segments[i].color = t.accent
        else
            m.segments[i].color = t.segmentIdle
        end if
    end for
end sub

sub RebuildSegments()
    while m.providerSegments.GetChildCount() > 0
        m.providerSegments.RemoveChildIndex(0)
    end while
    m.segments = []
    if m.providers = invalid then return
    for i = 0 to m.providers.Count() - 1
        segment = CreateObject("roSGNode", "Rectangle")
        segment.width = 28
        segment.height = 6
        segment.translation = [i * 36, 0]
        segment.color = Theme().segmentIdle
        m.providerSegments.AppendChild(segment)
        m.segments.Push(segment)
    end for
end sub

' The status line: while any provider is still resolving, show how many remain
' ("2/3 providers loading…"); when all are done, clear it, or report failure/empty
' precisely the way the old single-shot load did. Counts span all providers, since
' m.streams now holds only the active provider's cards.
sub UpdateStreamsStatus()
    if m.status = invalid then return
    UpdateProviderStatus()
    total = 0
    failedNames = []
    if m.providers <> invalid
        for each provider in m.providers
            if AddonDiagnostics_Text(provider.error) <> "" then failedNames.Push(AddonDiagnostics_Name(provider))
            if Type(provider.readyStreams) = "roArray"
                total = total + provider.readyStreams.Count()
            else
                total = total + CinemaCountReadyStreams(provider.streams)
            end if
        end for
    end if
    if m.pendingCount > 0
        requesting = 0
        queued = 0
        for i = 0 to m.providers.Count() - 1
            state = ProviderRequestState(i)
            if state = "pending" then requesting = requesting + 1
            if state = "queued" then queued = queued + 1
        end for
        m.status.text = requesting.ToStr() + " requesting sources; " + queued.ToStr() + " queued."
    else
        if total = 0
            if m.loadError <> ""
                m.status.text = "Sources could not load. Check Add-ons or try another provider."
            else
                m.status.text = "No ready direct streams found for this title."
            end if
        else
            m.status.text = ""
            if failedNames.Count() > 0 then m.status.text = failedNames.Count().ToStr() + " provider(s) need attention: " + failedNames[0].Left(40) + ". Other sources are available."
        end if
    end if
end sub

sub UpdateProviderStatus()
    label = m.providerStatus
    if label = invalid then return
    label.color = Theme().textSecondary
    if m.providers = invalid or m.activeIndex < 0 or m.activeIndex >= m.providers.Count()
        label.text = "Connect a source in Add-ons"
        return
    end if
    count = 0
    if Type(m.streams) = "roArray" then count = m.streams.Count()
    provider = m.providers[m.activeIndex]
    skipped = invalid
    if count = 0 then skipped = CinemaSkippedSources(provider.streams)
    label.text = AddonDiagnostics_ProviderLabel(provider,ProviderRequestState(m.activeIndex),count,skipped)
    if count > 48 and m.sourcePage <> invalid
        first = m.sourcePage * 48 + 1
        last = first + 47
        if last > count then last = count
        label.text = label.text + " | " + first.ToStr() + "-" + last.ToStr() + " of " + count.ToStr()
    end if
    if AddonDiagnostics_Text(provider.error) <> "" then label.color = Theme().accentWarm
end sub

sub CancelStreamsLoad()
    m.reloadNeeded = false
    CancelAutomaticGrace()
    m.sourceQueue = []
    if m.prefetchNode <> invalid then m.prefetchNode.UnobserveField("revision")
    SourcePrefetch_Cancel(m.top, m.prefetchContext)
    m.prefetchNode = invalid
    m.prefetchContext = invalid
    m.prefetchWaiting = []
    if m.selectionTask <> invalid
        selection = m.selectionTask
        m.selectionTask = invalid
        AsyncTask_Reap(selection, m.top, true)
    end if
    if m.loadTasks <> invalid
        for each task in m.loadTasks
            if task <> invalid then AsyncTask_Reap(task, m.top, true)
        end for
    end if
    m.loadTasks = invalid
    ' Cancelling disowns the batch. Without this, pendingCount keeps its old value
    ' and loadKey keeps naming an episode whose tasks have just been reaped, so
    ' OnEnter's same-episode guard would match it and skip the reload — leaving the
    ' list permanently empty, because the fetch that would fill it was the one
    ' just cancelled. Guard on "a batch this screen still owns", not on the last
    ' key it happened to write.
    m.pendingCount = 0
    m.loadKey = ""
    m.loadContextKey = ""
    ' Disown the token immediately; the sequence counter survives cancellation
    ' and LoadStreams mints a different nonempty token for the next batch.
    m.loadToken = ""
end sub

' Series opened straight from Details carry no episode name/overview in their
' params (resume/Play-S1E1 never passed through EpisodesScreen). Spin a parallel
' MetaLoaderTask so the panel can refine once the video land — the stream list
' is not held back. Movies and EpisodesScreen-origin series (which already pass
' both fields) skip this.
sub StartEpisodeLoad(params as object)
    if params = invalid or params.metaType <> "series" then return
    if params.addonAddress = invalid or params.addonAddress = "" then return
    if params.metaId = invalid or params.metaId = "" then return
    if params.episodeName <> invalid and params.episodeName <> "" then return
    if params.episodeOverview <> invalid and params.episodeOverview <> "" then return
    if m.epMetaTask <> invalid then return

    task = AsyncTask_Launch(m.top, "MetaLoaderTask", "onEpisodeMetaLoaded", {
        addonAddress: ParamString(params.addonAddress)
        metaType: "series"
        metaId: ParamString(params.metaId)
    }, "episodeMetaLoader" + m.loadToken)
    m.epMetaTask = task
end sub

' The series meta came back. If it holds the target episode, fill the two panel
' params the pusher couldn't supply and re-run the pure chrome builder — the
' SxE line and synopsis refine in place, everything else stays. A stale result
' that landed after CancelEpisodeLoad is dropped by the m.epMetaTask guard.
sub onEpisodeMetaLoaded(event as object)
    if m.epMetaTask = invalid then return
    task = event.GetRoSGNode()
    if task = invalid or task.id <> m.epMetaTask.id then return
    result = task.result
    if Type(result) <> "roAssociativeArray" then return
    m.epMetaTask = invalid
    AsyncTask_Reap(task, m.top, false)

    if result = invalid or not result.ok or result.meta = invalid then return
    if m.params = invalid then return
    m.params.seriesMeta = result.meta

    episode = EpisodeInMeta(result.meta, m.params.season, m.params.episode)
    if episode = invalid then return
    if m.params.episodeName = invalid or m.params.episodeName = "" then m.params.episodeName = episode.name
    if m.params.episodeOverview = invalid or m.params.episodeOverview = "" then m.params.episodeOverview = episode.overview
    ApplyParamsChrome(m.params)
end sub

sub CancelEpisodeLoad()
    if m.epMetaTask <> invalid
        task = m.epMetaTask
        m.epMetaTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' Find the video for a (season, episode) inside a fetched series meta. The video
' list mirrors the episode tiles EpisodesScreen builds from the same store.
function EpisodeInMeta(meta as object, season as dynamic, episode as dynamic) as dynamic
    if meta = invalid or meta.videos = invalid or season = invalid or episode = invalid then return invalid
    for each video in meta.videos
        if video.season <> invalid and video.season = season and video.episode <> invalid and video.episode = episode then return video
    end for
    return invalid
end function

' Render the active provider's section: its cards when it has streams, or a
' placeholder in the list area (still loading / provider error / no streams).
' Focus falls to the list on the first fill after a switch; when the active
' provider has nothing to show, the screen Group keeps focus so Left/Right can
' still move on. m.streams retains every eligible candidate; sourceRows maps
' the bounded page's native rows to full-array indexes or page navigation.
sub RenderActiveProvider()
    if m.providers = invalid or m.activeIndex < 0 or m.activeIndex >= m.providers.Count() then return
    provider = m.providers[m.activeIndex]
    if Type(provider.readyStreams) = "roArray"
        m.streams = CinemaFilterReadyStreams(provider.readyStreams, m.fourKOnly)
    else
        m.streams = CinemaChooseStreams(provider.streams, m.fourKOnly, CurrentAudioMode(), false)
    end if
    UpdateQualityHint()

    if m.streams.Count() = 0
        UpdateProviderStatus()
        EmptyStreamsList()
        label = ProviderEmptyLabel()
        if provider.streams.Count() > 0
            skipped = CinemaSkippedSources(provider.streams)
            if m.fourKOnly
                label = "No HTTPS stream labelled 4K. Press * to check other qualities."
            else
                label = "This provider returned no direct HTTPS streams. A torrent alone cannot play on Roku."
            end if
            if skipped.uncached > 0 then label = "Only uncached downloads are available. Choose a cached source or another title."
            if skipped.status > 0 then label = "Provider reported an account or service error. Check your provider configuration."
        end if
        if label = ""
            m.streamsPlaceholder.visible = false
        else
            m.streamsPlaceholder.text = label
            m.streamsPlaceholder.visible = true
        end if
        if m.top.screenActive then m.top.SetFocus(true)
        return
    end if

    m.streamsPlaceholder.visible = false

    ' Preserve the remote's current row when this same provider is refreshed or
    ' the player returns. Unrelated provider results never rebuild this content.
    focusedRow = 0
    focused = m.streamsList.rowItemFocused
    if Type(focused) = "roArray" and focused.Count() >= 2
        if Type(focused[0]) = "Integer" or Type(focused[0]) = "roInt" then focusedRow = focused[0]
    end if
    if m.sourcePage = invalid or m.sourcePage < 0 then m.sourcePage = 0
    lastPage = Int((m.streams.Count() - 1) / 48)
    if m.sourcePage > lastPage then m.sourcePage = lastPage
    pageStart = m.sourcePage * 48
    pageEnd = pageStart + 48
    if pageEnd > m.streams.Count() then pageEnd = m.streams.Count()
    m.sourceRows = []
    content = CreateObject("roSGNode", "ContentNode")
    if m.streams.Count() > 48 then m.hasSourcePaging = true
    ' Keep the two control indexes reserved for this title even when another
    ' provider/filter has fewer sources. A stale control can never become a film.
    if m.hasSourcePaging = true
        AddSourcePageNavigation(content, "previous", m.sourcePage - 1, lastPage + 1)
        AddSourcePageNavigation(content, "more", m.sourcePage + 1, lastPage + 1)
    end if
    for i = pageStart to pageEnd - 1
        row = content.CreateChild("ContentNode")
        item = row.CreateChild("ContentNode")
        stream = m.streams[i]
        item.title = "Play source " + (i + 1).ToStr()
        item.AddFields({ qualityBadge: CinemaQualityLabel(stream) })
        lines = CinemaCleanSourceLines(stream, CurrentAudioMode())
        if lines.Count() > 0
            description = ""
            for each line in lines
                if description <> "" then description = description + chr(10)
                description = description + line
            end for
            item.description = description
        end if
        m.sourceRows.Push({kind:"source",index:i,loadToken:m.loadToken,providerIndex:m.activeIndex,page:m.sourcePage})
    end for
    m.streamsList.content = content
    UpdateProviderStatus()
    ' The viewport shows three rows; the page has at most 48 real source cards
    ' plus Previous/More. Every candidate remains available through these pages.
    m.streamsList.numRows = 3
    if m.sourceRows.Count() < 3 then m.streamsList.numRows = m.sourceRows.Count()
    if not m.listFilled
        focusedRow = 0
        if m.hasSourcePaging = true then focusedRow = 2
        if m.pageFocusTarget = "last"
            focusedRow = pageEnd - pageStart - 1
            if m.hasSourcePaging = true then focusedRow = focusedRow + 2
        end if
    end if
    if focusedRow < 0 then focusedRow = 0
    if focusedRow >= m.sourceRows.Count() then focusedRow = m.sourceRows.Count() - 1
    m.streamsList.jumpToRowItem = [focusedRow, 0]
    m.pageFocusTarget = invalid
    if not m.listFilled
        m.listFilled = true
        if m.top.screenActive then m.streamsList.SetFocus(true)
    end if
end sub

' Paging owns only lightweight content nodes. It does not trim the fallback pool
' or make a network request, and Back continues to cancel the screen normally.
sub ResetSourcePagination()
    m.sourcePage = 0
    m.sourceRows = []
    m.pageFocusTarget = invalid
    m.pageSelectionBlocked = invalid
    m.listFilled = false
end sub

sub AddSourcePageNavigation(content as object, kind as string, targetPage as integer, pageCount as integer)
    row = content.CreateChild("ContentNode")
    item = row.CreateChild("ContentNode")
    enabled = targetPage >= 0 and targetPage < pageCount
    item.title = "More sources"
    if kind = "previous" then item.title = "Previous sources"
    badge = "Page " + (m.sourcePage + 1).ToStr() + " of " + pageCount.ToStr()
    item.description = "No further page in this direction. Back cancels."
    if enabled
        badge = "Page " + (targetPage + 1).ToStr() + " of " + pageCount.ToStr()
        item.description = "OK opens this page. Back cancels."
    end if
    item.AddFields({qualityBadge:badge})
    m.sourceRows.Push({kind:kind,targetPage:targetPage,enabled:enabled,loadToken:m.loadToken,providerIndex:m.activeIndex,page:m.sourcePage})
end sub

sub ChangeSourcePage(targetPage as integer)
    if Type(m.streams) <> "roArray" or m.streams.Count() = 0 then return
    lastPage = Int((m.streams.Count() - 1) / 48)
    if targetPage < 0 or targetPage > lastPage or targetPage = m.sourcePage then return
    oldPage = m.sourcePage
    m.sourcePage = targetPage
    m.pageFocusTarget = invalid
    if targetPage < oldPage then m.pageFocusTarget = "last"
    m.listFilled = false
    RenderActiveProvider()
end sub

' Paging is a deliberate manual browsing action. A ranking reply already queued
' for automatic Play must not interrupt it; provider results can keep loading.
sub DisableAutomaticForManualBrowse()
    CancelAutomaticGrace()
    m.autoPlayEnabled = false
    m.autoPlaySent = true
    if m.selectionTask <> invalid
        task = m.selectionTask
        m.selectionTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

sub UpdateQualityHint()
    if m.qualityHint = invalid then return
    if m.fourKOnly
        mode = "4K source labels only  |  * show all qualities"
    else
        mode = "4K source labels first + 1080p  |  * 4K only"
    end if
    m.qualityHint.text = mode + Chr(10) + "OK plays + retries automatically  |  Play refresh  |  Back cancels"
end sub

function CurrentAudioMode() as string
    if Type(m.params) = "roAssociativeArray"
        if m.params.audioMode = "projector" or m.params.audioMode = "surround" then return m.params.audioMode
    end if
    if m.stores <> invalid and m.stores.settings <> invalid
        if m.stores.settings.callFunc("SettingsGetAudioMode") = "surround" then return "surround"
    end if
    return "projector"
end function

' The placeholder text for an empty active provider: its own task still running
' -> loading; its error -> failure; otherwise nothing found from it.
function ProviderEmptyLabel() as string
    provider = m.providers[m.activeIndex]
    if provider.error <> "" then return AddonDiagnostics_Error(provider.error).detail
    requestState = ProviderRequestState(m.activeIndex)
    if requestState = "queued" then return "Queued for source lookup. Other requests are finishing. Back cancels."
    if requestState = "pending" then return "Requesting sources… This can take up to 45 seconds."
    return "No streams found for this provider."
end function

' Distinguish waiting for a shared worker from an active network request.
' Read only the exact coordinator context; provider addresses never reach UI.
function ProviderRequestState(index as integer) as string
    if m.providers = invalid or index < 0 or index >= m.providers.Count() then return "done"
    if m.prefetchNode <> invalid and m.prefetchContext <> invalid
        snapshot = m.prefetchNode.callFunc("Snapshot",m.prefetchContext.key)
        if Type(snapshot) = "roAssociativeArray" and Type(snapshot.entries) = "roArray"
            if index < snapshot.entries.Count()
                entry = snapshot.entries[index]
                if Type(entry) = "roAssociativeArray"
                    if entry.status = "queued" then return "queued"
                    if entry.status = "pending" then return "pending"
                    if entry.status = "ready" or entry.status = "failed" then return "done"
                end if
            end if
        end if
    end if
    if Type(m.sourceQueue) = "roArray"
        for each queued in m.sourceQueue
            if queued = index then return "queued"
        end for
    end if
    if m.loadTasks <> invalid and index < m.loadTasks.Count()
        if m.loadTasks[index] <> invalid then return "pending"
    end if
    if Type(m.prefetchWaiting) = "roArray" and index < m.prefetchWaiting.Count()
        if m.prefetchWaiting[index] = true then return "queued"
    end if
    return "done"
end function

function isTaskPending(index as integer) as boolean
    if m.loadTasks = invalid then return false
    if index < 0 or index >= m.loadTasks.Count() then return false
    if Type(m.sourceQueue) = "roArray"
        for each queued in m.sourceQueue
            if queued = index then return true
        end for
    end if
    if m.prefetchWaiting <> invalid and index < m.prefetchWaiting.Count()
        if m.prefetchWaiting[index] = true then return true
    end if
    return m.loadTasks[index] <> invalid
end function

' The card's primary line: the add-on's stream name, then title, then a generic
' label.
function StreamLabel(stream as object) as string
    label = CinemaOptionalText(stream.name)
    if label = "" then label = CinemaOptionalText(stream.title)
    if label = "" then label = "Stream"
    return FlattenNewlines(label).Trim()
end function

' The card's lines below the name. Sources merge in order, each split at its
' embedded line feeds: the title (one add-on idiom packs the release, then the
' file path, then the "👤 412 💾 54.2 GB" stats line into it), then the
' description (the official stream spec — other add-ons keep filename/size/
' quality there instead of a title), then behaviorHints.filename, and finally a
' human size from behaviorHints.videoSize when nothing else produced a line.
' Exact duplicates are skipped so an add-on setting both title and description
' never double-prints a file name. Direct URLs and add-ons with no text at all
' keep the "source · quality" line so the card is never empty.
function StreamTitleLines(stream as object) as object
    lines = []
    if stream = invalid then return lines
    AddStreamLines(lines, stream.title)
    AddStreamLines(lines, stream.description)
    if Type(stream.behaviorHints) = "roAssociativeArray"
        AddStreamLines(lines, stream.behaviorHints.filename)
    end if
    if lines.Count() = 0 and Type(stream.behaviorHints) = "roAssociativeArray"
        size = HumanSize(stream.behaviorHints.videoSize)
        if size <> "" then lines.Push(size)
    end if
    if lines.Count() = 0
        if CinemaOptionalText(stream.source) <> "" then lines.Push(CinemaOptionalText(stream.source))
        if CinemaOptionalText(stream.quality) <> "" then lines.Push(CinemaOptionalText(stream.quality))
    end if
    return lines
end function

' Split one candidate stream text at its line feeds and append the non-empty
' pieces, skipping exact duplicates already collected.
sub AddStreamLines(lines as object, text as dynamic)
    if text = invalid then return
    if Type(text) <> "roString" and Type(text) <> "String" then return
    if text.Trim() = "" then return
    pieces = text.Trim().Split(chr(10))
    if pieces = invalid or pieces.Count() = 0 then return
    for each piece in pieces
        line = piece.Trim()
        if line = "" then continue for
        if not ContainsLine(lines, line) then lines.Push(line)
    end for
end sub

' True when lines already holds an exact match for line.
function ContainsLine(lines as object, line as string) as boolean
    for each existing in lines
        if existing = line then return true
    end for
    return false
end function

' Bytes to a readable size. 1024-based GB/TB, consistent with the "💾 n GB"
' sizes stream text commonly carries; two decimals below 10 GB, one at or above.
function HumanSize(bytes as dynamic) as string
    if bytes = invalid then return ""
    value = 0.0
    kind = Type(bytes)
    if kind = "roString" or kind = "String"
        value = bytes.ToFloat()
    else
        if kind <> "Integer" and kind <> "roInt" and kind <> "roInteger" and kind <> "Float" and kind <> "roFloat" and kind <> "Double" and kind <> "roDouble" then return ""
        value = CDbl(bytes)
    end if
    if value <= 0 then return ""
    gb = value / 1073741824.0
    if gb >= 1024
        return Str(Int(gb / 1024.0 * 10 + 0.5) / 10.0).Trim() + " TB"
    end if
    if gb < 10
        return Str(Int(gb * 100 + 0.5) / 100.0).Trim() + " GB"
    end if
    return Str(Int(gb * 10 + 0.5) / 10.0).Trim() + " GB"
end function

' Stream names/titles carry embedded line feeds; the card labels are
' single-line, so replace them with a space.
function FlattenNewlines(text as string) as string
    if text = "" then return text
    pieces = text.Split(chr(10))
    if pieces = invalid or pieces.Count() <= 1 then return text
    result = ""
    for each piece in pieces
        if result <> "" then result = result + " "
        result = result + piece
    end for
    return result
end function

' Runtime echoed straight from the meta JSON — Cinemeta ships plain minutes, so
' no parsing and no "2h 5m" conversion.
function FormatRuntime(runtime as dynamic) as string
    if runtime = invalid then return ""
    return runtime.ToStr().Trim()
end function

' OK on a stream card drops straight into the player with the raw stream and the
' streaming-server address. The PlayerScreen resolves it (ResolvePlayback passes
' a direct URL through as-is and creates a torrent engine on the server, up to
' the 120s long timeout on a cold engine) while its logo pulses, so the picker
' answers instantly and stays the place a failed source lands back on.
sub onSourceRowFocused()
    if m.pageSelectionBlocked = invalid then return
    focused = m.streamsList.rowItemFocused
    if Type(focused) <> "roArray" or focused.Count() < 2 then return
    ' A queued selection from a page navigation must not act again until focus
    ' has moved from that old control into the freshly displayed page.
    if focused[0] <> m.pageSelectionBlocked then m.pageSelectionBlocked = invalid
end sub

sub onStreamSelected(event = invalid as dynamic)
    if not m.top.screenActive or m.sourcesSuspended = true or m.listFilled <> true then return
    data = m.streamsList.rowItemSelected
    if Type(data) <> "roArray" or data.Count() < 2 then return
    if Type(data[0]) <> "Integer" and Type(data[0]) <> "roInt" then return
    if Type(data[1]) <> "Integer" and Type(data[1]) <> "roInt" then return
    if data[1] <> 0 then return
    if m.pageSelectionBlocked <> invalid and data[0] = m.pageSelectionBlocked then return
    focused = m.streamsList.rowItemFocused
    if Type(focused) <> "roArray" or focused.Count() < 2 then return
    if focused[0] <> data[0] or focused[1] <> data[1] then return
    ' Drop notifications that no longer describe the RowList's current field.
    if event <> invalid
        notified = event.GetData()
        if Type(notified) <> "roArray" or notified.Count() < 2 then return
        if notified[0] <> data[0] or notified[1] <> data[1] then return
    end if
    rowIndex = data[0]
    if Type(m.sourceRows) <> "roArray" or rowIndex < 0 or rowIndex >= m.sourceRows.Count() then return
    choice = m.sourceRows[rowIndex]
    if choice.loadToken <> m.loadToken or choice.providerIndex <> m.activeIndex or choice.page <> m.sourcePage then return
    if choice.kind = "more" or choice.kind = "previous"
        if choice.enabled <> true then return
        DisableAutomaticForManualBrowse()
        m.pageSelectionBlocked = rowIndex
        ChangeSourcePage(choice.targetPage)
        return
    end if
    if choice.kind <> "source" then return
    index = choice.index
    if Type(m.streams) <> "roArray" or index < 0 or index >= m.streams.Count() then return
    DisableAutomaticForManualBrowse()
    SuspendSourceLoading()
    PushAutomaticPlayer(m.streams[index], m.streams)
end sub

' Params values can carry invalid; string interface fields cannot, so coerce.
function ParamString(value as dynamic) as string
    if value = invalid then return ""
    return value.ToStr()
end function

' Identity of the episode this list is being built for, as one comparable
' string. metaType/metaId plus videoId is the play; season and episode pin down
' which one of a series, and addonAddress scopes it to the add-on the list was
' reached through, so the same title offered by two providers is two lists and
' must not be mistaken for a revisit.
'
' Ordinals go through Int() in a try, because a series opened from a deep link
' can carry them as strings ("3") and Int("3") is the only thing that compares
' equal to the integer the Episodes screen passed — without that, a revisit with
' "3" where the first visit had 3 reads as a different episode and rebuilds the
' list every time.
function EpisodeKey(params as object) as string
    if params = invalid then return ""
    season = 0
    if params.season <> invalid
        try
            season = Int(params.season)
        catch notAnOrdinal
            season = 0
        end try
    end if
    episode = 0
    if params.episode <> invalid
        try
            episode = Int(params.episode)
        catch notAnOrdinal
            episode = 0
        end try
    end if
    return ParamString(params.metaType) + "|" + ParamString(params.metaId) + "|" + ParamString(params.videoId) + "|" + season.toStr() + "|" + episode.toStr() + "|" + ParamString(params.addonAddress)
end function

sub RestoreFocus()
    if m.activeIndex >= 0 and m.providers <> invalid and m.activeIndex < m.providers.Count()
        provider = m.providers[m.activeIndex]
        if m.streams.Count() > 0 then m.streamsList.SetFocus(true) else m.top.SetFocus(true)
    end if
end sub

' Left/Right flip between providers: the single-column RowList swallows Up/Down
' but lets Left/Right bubble here at its edges, so each press moves one provider
' and the header + segments follow. At the ends there is nothing to move to, so
' the key is left for the stack/Scene. Whether an edge press really bubbles is
' device-dependent — verify on-device.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "play"
        m.autoPlaySent = false
        RefreshStreams()
        return true
    end if
    if m.providers = invalid or m.activeIndex < 0 then return false
    if key = "options"
        m.fourKOnly = not m.fourKOnly
        m.params.fourKOnly = m.fourKOnly
        CancelAutomaticGrace()
        if m.selectionTask <> invalid
            selection = m.selectionTask
            m.selectionTask = invalid
            AsyncTask_Reap(selection,m.top,true)
        end if
        m.selectionRevision = -1
        ResetSourcePagination()
        RenderActiveProvider()
        MaybeStartAutomaticPlayback()
        return true
    end if
    if key = "left"
        if m.activeIndex > 0
            SelectProvider(m.activeIndex - 1)
            return true
        end if
    else if key = "right"
        if m.activeIndex < m.providers.Count() - 1
            SelectProvider(m.activeIndex + 1)
            return true
        end if
    end if
    return false
end function

function OnExit() as void
    CancelStreamsLoad()
    CancelEpisodeLoad()
end function

function OnBackPressed() as boolean
    return false
end function

sub SuspendSourceLoading()
    m.sourcesSuspended = true
    CancelAutomaticGrace()
    if m.prefetchNode <> invalid and m.prefetchContext <> invalid then m.prefetchNode.callFunc("Suspend",m.prefetchContext.key)
end sub

sub BlurFocus()
    SuspendSourceLoading()
end sub
