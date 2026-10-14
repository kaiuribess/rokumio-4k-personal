function TestContent() as object
    return {
        children: []
        CreateChild: function(kind as string) as object
            child = TestContent()
            m.children.Push(child)
            return child
        end function
        AddFields: sub(fields as object)
            for each field in fields
                m[field] = fields[field]
            end for
        end sub
    }
end function

function FocusNode() as object
    return { focused: false, SetFocus: sub(value as boolean)
        m.focused = value
    end sub }
end function

function TestEvent(task as object) as object
    return { task: task, GetRoSGNode: function() as object
        return m.task
    end function, GetData: function() as dynamic
        return m.task.result
    end function }
end function

function Theme() as object
    return { accentFocus: "focus", itemFace: "selected", accentClear: "clear", tileFace: "idle" }
end function

sub TestStreamTileRecycling()
    Harness_Suite("Production StreamTile recycling and long-line visibility")
    m.top = { itemContent: invalid, itemHasFocus: false, rowHasFocus: false }
    m.title = { text: "Old title" }
    m.quality = { text: "Old quality" }
    m.lines = []
    for i = 0 to 4
        m.lines.Push({ text: "old line", measured: 0,
            callFunc: function(name as string) as integer
                return m.measured
            end function })
    end for
    m.border = {}
    m.face = {}
    m.content = { translation: [-200, 0] }
    m.measureTimer = { control: "start" }
    m.scrollTimer = { control: "start" }
    onItemContentChanged()
    Harness_Equal(m.title.text, "", "empty recycled cell clears the previous title")
    Harness_Equal(m.quality.text, "", "empty recycled cell clears the previous quality")
    Harness_Equal(m.lines[0].text, "", "empty recycled cell clears release text")
    Harness_Equal(m.measureTimer.control, "stop", "empty cell stops queued measurements")
    Harness_Equal(m.scrollTimer.control, "stop", "empty cell stops scrolling ticks")
    Harness_Equal(m.content.translation[0], 0, "recycled cell resets the scroll origin")
    m.top.itemContent = { title: "Next title", qualityBadge: "1080p source label", description: "Short line" }
    onItemContentChanged()
    Harness_Equal(m.title.text, "Next title", "replacement cell receives its own title")
    Harness_Equal(m.lines[1].text, "", "replacement cell clears unused text rows")
    Harness_Equal(m.measureTimer.control, "stop", "unfocused content does not keep a measurement timer armed")
    m.top.itemHasFocus = true
    m.top.rowHasFocus = true
    m.lines[0].measured = 1010
    m.speed = 80
    m.interval = 0.03
    m.startHold = 0.6
    m.endHold = 1.5
    m.tailPad = 30
    UpdateLook()
    onMeasureTick()
    Harness_Equal(m.overflow, 6, "measurement includes the label inset inside the clipping window")
    Harness_Equal(m.scrollTimer.control, "start", "a line clipped by only a few pixels can be read by scrolling")
    m.top.itemHasFocus = false
    UpdateLook()
    Harness_Equal(m.measureTimer.control, "stop", "leaving a cell cancels a queued measurement")
    Harness_Equal(m.scrollTimer.control, "stop", "leaving a cell stops its animation")
end sub

sub AsyncTask_Reap(task as object, parent as object, doStop as boolean)
    task.reaped = true
end sub

function AsyncTask_Launch(parent as object, kind as string, handler as string, fields as object, id as string) as object
    task = { id: id, result: invalid, reaped: false }
    for each key in fields
        task[key] = fields[key]
    end for
    if m.launched = invalid then m.launched = []
    m.launched.Push(task)
    return task
end function

sub TestStreamsRemoteRefresh()
    Harness_Suite("Production remote source refresh rejects canceled responses")
    m.autoPlayEnabled = false
    m.autoPlaySent = false
    m.selectionTask = invalid
    m.top = FocusNode()
    m.top.screenActive = true
    m.streamsList = FocusNode()
    m.qualityHint = {}
    m.status = {}
    m.streamsPlaceholder = {}
    m.providerName = {}
    m.arrowLeft = {}
    m.arrowRight = {}
    m.providerSegments = {}
    m.segments = [{}, {}]
    m.params = {metaType:"movie", metaId:"tt-refresh", videoId:"tt-refresh"}
    m.fourKOnly = true
    m.activeIndex = 1
    m.loadSeq = 7
    m.loadToken = "7"
    m.loadKey = EpisodeKey(m.params)
    m.pendingCount = 2
    m.providersTotal = 2
    m.providers = [
        { name: "Provider A", address: "https://a.example", streams: [], error: "" }
        { name: "Provider B", address: "https://b.example", streams: [], error: "" }
    ]
    firstOld = {loadToken:"7", providerIndex:0, result:invalid, reaped:false}
    secondOld = {loadToken:"7", providerIndex:1, result:invalid, reaped:false}
    m.loadTasks = [firstOld, secondOld]
    m.launched = []
    m.stores = { addons: {
        installed: [
            { name: "Provider A", address: "https://a.example", resources: ["stream"], types: ["movie"] }
            { name: "Provider B", address: "https://b.example", resources: ["stream"], types: ["movie"] }
        ]
        callFunc: function(name as string, arg1 = invalid as dynamic, arg2 = invalid as dynamic, arg3 = invalid as dynamic, arg4 = invalid as dynamic, arg5 = invalid as dynamic, arg6 = invalid as dynamic) as dynamic
            if name = "AddonsGetAll" then return m.installed
            if name = "AddonsSupportsResource" then return true
            return invalid
        end function
    } }
    Harness_Ok(not onKeyEvent("play", false), "Play/Pause key release does not launch requests")
    Harness_Equal(m.launched.Count(), 0, "no duplicate refresh on key-up")
    Harness_Ok(onKeyEvent("play", true), "Play/Pause handles source refresh")
    Harness_Ok(firstOld.reaped and secondOld.reaped, "refresh cancels each old provider worker")
    Harness_Equal(m.launched.Count(), 2, "refresh launches one new request per current provider")
    Harness_Equal(m.loadToken, "8", "refresh mints a new batch identity")
    Harness_Equal(m.activeIndex, 1, "refresh preserves the selected provider")
    Harness_Ok(m.fourKOnly, "refresh preserves the explicit 4K filter")
    Harness_Ok(m.qualityHint.text.InStr("Play refresh") >= 0, "source controls advertise the refresh action")
    Harness_Equal(m.streams.Count(), 0, "refresh removes expired prior links")
    Harness_Equal(m.pendingCount, 2, "refresh starts with every provider pending")
    secondOld.result = {streams:[{name:"2160p old", url:"https://old.example/expired.mkv"}], error:""}
    onStreamsLoaded(TestEvent(secondOld))
    Harness_Equal(m.pendingCount, 2, "late canceled response cannot complete a refreshed request")
    Harness_Equal(m.streams.Count(), 0, "late canceled response cannot restore expired links")
    current = m.loadTasks[1]
    current.result = {streams:[{name:"2160p new", url:"https://new.example/fresh.mkv"}], error:""}
    onStreamsLoaded(TestEvent(current))
    Harness_Equal(m.pendingCount, 1, "new provider completion updates only its live batch")
    Harness_Equal(m.streams[0].url, "https://new.example/fresh.mkv", "refreshed stream becomes the visible selection")
    onStreamsLoaded(TestEvent(current))
    Harness_Equal(m.pendingCount, 1, "duplicate refreshed result cannot decrement twice")
    Harness_Equal(m.streams.Count(), 1, "duplicate refreshed result cannot repeat cards")
    Harness_Ok(not onKeyEvent("play", false), "release after a completed provider still does not refresh")
    Harness_Equal(m.launched.Count(), 2, "refresh remains one launch per key press")
end sub

sub TestWorkerPreparedSources()
    Harness_Suite("Large worker-prepared source list never ranks on the render thread")
    raw = []
    for i = 0 to 255
        name = "1080p H264"
        if i mod 2 = 1 then name = "2160p HEVC DDP HDR10"
        raw.Push({name:name,title:"Source " + i.ToStr(),url:"https://example.invalid/" + i.ToStr() + ".mkv"})
    end for
    prepared = CinemaChooseStreams(raw, false)
    m.providers = [{name:"Provider",streams:[],error:""}]
    m.activeIndex = 0
    m.fourKOnly = false
    m.listFilled = false
    m.pendingCount = 1
    m.providersTotal = 1
    m.loadToken = "worker-prepared"
    task = {loadToken:m.loadToken,providerIndex:0,reaped:false,result:{streams:raw,readyStreams:prepared,error:""}}
    m.loadTasks = [task]
    m.cinemaRankCalls = 0
    onStreamsLoaded(TestEvent(task))
    Harness_Equal(m.streams.Count(), 256, "All worker-prepared sources reach the list")
    Harness_Equal(m.pendingCount, 0, "Large successful result ends provider loading")
    Harness_Equal(m.status.text, "", "Large list does not remain on Checking available sources")
    Harness_Equal(m.cinemaRankCalls, 0, "Completion and status update perform no render-thread ranking")
    Harness_Ok(onKeyEvent("options", true), "4K filter remains usable after a large batch")
    Harness_Equal(m.streams.Count(), 128, "4K filter preserves every UHD-labelled ready source")
    Harness_Equal(m.cinemaRankCalls, 0, "Remote quality filter reuses worker order")
    m.providers = [{name:"Provider",streams:[],error:""}]
    m.pendingCount = 1
    m.loadError = ""
    task = {loadToken:m.loadToken,providerIndex:0,reaped:false,result:{streams:[],readyStreams:[],error:"Timed out at https://private.invalid/PRIVATE_KEY"}}
    m.loadTasks = [task]
    onStreamsLoaded(TestEvent(task))
    Harness_Equal(m.pendingCount, 0, "Provider timeout leaves loading state")
    Harness_Ok(m.streamsPlaceholder.text.InStr("could not load sources") >= 0, "Empty worker result still surfaces its transport failure")
    Harness_Ok(m.status.text.InStr("Sources could not load") >= 0, "Timeout is not misreported as a title with no sources")
    Harness_Ok(m.status.text.InStr("PRIVATE_KEY") < 0, "Transport failure remains redacted")
    m.providers = [{name:"Provider",streams:[{name:"2160p Dolby DTS",url:"https://media.example/mixed-tracks.mkv"}],error:""}]
    m.listFilled = false
    RenderActiveProvider()
    Harness_Equal(m.streams.Count(),1,"raw provider fallback retains a file whose stereo track is absent from the filename")
    Harness_Equal(m.streams[0].url,"https://media.example/mixed-tracks.mkv","manual picker preserves the candidate for actual native audio inspection")
end sub

sub Main()
    m.cinemaRankCalls = 0
    Harness_Suite("Production StreamsScreen callbacks")
    m.autoPlayEnabled = false
    m.autoPlaySent = false
    m.selectionTask = invalid
    m.top = FocusNode()
    m.top.screenActive = true
    m.streamsList = FocusNode()
    m.qualityHint = {}
    m.streamsPlaceholder = {}
    m.status = {}
    m.params = {metaType:"series",metaId:"tt-sample",videoId:"opaque:id/with space",season:2,episode:4,position:61.5,poster:"",logo:""}
    m.headTitle = {text:"Diagnostic"}
    m.stores = invalid
    m.activeIndex = 0
    m.listFilled = false
    m.fourKOnly = false
    raw = []
    for i = 0 to 24
        quality = "1080p H264"
        if i mod 2 = 1 then quality = "2160p HEVC AAC HDR10"
        raw.Push({name:quality,title:"sample " + i.ToStr(),url:"https://example.invalid/" + i.ToStr() + ".mkv"})
    end for
    raw.Push({name:"2160p torrent",infoHash:"not-a-direct-source"})
    m.providers = [{name:"Provider",streams:raw,error:""}]
    m.loadTasks = [invalid]
    RenderActiveProvider()
    Harness_Equal(m.streams.Count(), 25, "All direct HTTPS sources remain accessible")
    Harness_Equal(m.streamsList.content.children.Count(), 25, "Each candidate has a content row")
    Harness_Equal(m.streamsList.numRows, 3, "Visible rows capped to screen viewport")
    Harness_Ok(CinemaIs4KLabel(m.streams[0]), "4K labels placed first")
    Harness_Ok(m.streamsList.focused, "First results take remote focus")
    Harness_Equal(m.streamsList.content.children[0].children[0].qualityBadge, "2160p / 4K source label", "Badge distinguishes labels from decoded resolution")
    m.streamsList.rowItemSelected = [1,0]
    onStreamSelected()
    Harness_Equal(m.top.pushRequest.params.stream.url, m.streams[1].url, "OK passes exactly the visible sorted source")
    Harness_Equal(m.top.pushRequest.params.videoId, "opaque:id/with space", "Opaque episode ID preserved through playback handoff")
    Harness_Equal(m.top.pushRequest.params.position, 61.5, "Resume position passed unchanged")
    Harness_Equal(m.top.pushRequest.params.serverAddress, "", "Direct-source playback has no server requirement")
    Harness_Equal(m.top.pushRequest.params.fourKOnly, false, "All-quality selection passes an explicit false 4K-only guard")
    Harness_Ok(onKeyEvent("options", true), "Star filter handled")
    Harness_Equal(m.streams.Count(), 12, "4K-only filters out HD")
    Harness_Equal(raw.Count(), 26, "Filtering leaves provider response unchanged")
    m.streamsList.rowItemSelected = [0,0]
    onStreamSelected()
    Harness_Equal(m.top.pushRequest.params.fourKOnly, true, "Explicit 4K-only selection preserves the encoded-quality guard in Player")
    m.providers[0].streams = [{name:"1080p",url:"https://example.invalid/hd.mp4"}]
    RenderActiveProvider()
    Harness_Equal(m.streams.Count(), 0, "No silent HD fallback in 4K-only mode")
    Harness_Ok(m.streamsPlaceholder.text.InStr("Press *") >= 0, "Empty 4K mode provides an escape")
    Harness_Ok(m.top.focused, "Empty picker retains remote focus")
    Harness_Ok(onKeyEvent("options", true), "Star switches back to all qualities")
    Harness_Equal(m.streams.Count(), 1, "1080p source becomes available explicitly")
    Harness_Equal(m.streamsList.numRows, 1, "Single-source viewport")
    Harness_Ok(not onKeyEvent("options", false), "Key release does not toggle mode twice")

    m.loadToken = "new-batch"
    live = {loadToken:"new-batch",providerIndex:0,result:invalid,reaped:false}
    m.loadTasks = [live]
    m.pendingCount = 1
    m.providersTotal = 1
    m.activeIndex = -1
    m.providers[0].streams = []
    m.loadError = ""
    stale = {loadToken:"old-batch",providerIndex:0,result:{streams:[{name:"old"}]}}
    onStreamsLoaded(TestEvent(stale))
    Harness_Equal(m.pendingCount, 1, "Stale provider result cannot claim current slot")
    onStreamsLoaded(TestEvent(live))
    Harness_Ok(not live.reaped, "Empty notification does not dispose live worker")
    Harness_Equal(m.pendingCount, 1, "Empty notification leaves provider pending")
    live.result = {streams:[{name:"current",url:"https://example.invalid/current.mkv"}],error:""}
    onStreamsLoaded(TestEvent(live))
    Harness_Equal(m.pendingCount, 0, "Current result decrements pending once")
    Harness_Ok(live.reaped, "Finished provider worker is disposed")
    Harness_Equal(m.providers[0].streams.Count(), 1, "Current sources applied")
    onStreamsLoaded(TestEvent(live))
    Harness_Equal(m.providers[0].streams.Count(), 1, "Duplicate notification cannot append twice")
    currentMeta = {id:"episodeMetaLoader2",result:invalid,reaped:false}
    m.epMetaTask = currentMeta
    onEpisodeMetaLoaded(TestEvent({id:"episodeMetaLoader1",result:{ok:true,meta:{}}}))
    Harness_Ok(not currentMeta.reaped, "Old episode metadata cannot reap current worker")
    onEpisodeMetaLoaded(TestEvent(currentMeta))
    Harness_Ok(not currentMeta.reaped, "Empty episode notification keeps current worker")
    m.activeIndex = 0
    m.listFilled = false
    m.fourKOnly = true
    m.providers[0].streams = [{name:"[TB download] Torrentio 4k",url:"https://torrentio.strem.fun/resolve/torbox/PRIVATE_PLACEHOLDER/movie.mkv"}]
    RenderActiveProvider()
    Harness_Equal(m.streams.Count(), 0, "Download-to-debrid entry never becomes a selectable movie")
    Harness_Ok(m.streamsPlaceholder.text.InStr("uncached") >= 0, "Download-only result explains cache availability")
    m.providers[0].streams = [{name:"Torrentio" + Chr(10) + "TB error",url:"https://torrentio.strem.fun/videos/failed_access_v3.mp4",title:"PRIVATE_KEY_IN_BAD_PROVIDER_TEXT"}]
    RenderActiveProvider()
    Harness_Equal(m.streams.Count(), 0, "Provider error clip never becomes a selectable movie")
    Harness_Ok(m.streamsPlaceholder.text.InStr("account or service error") >= 0, "Provider status gives actionable message")
    Harness_Ok(m.streamsPlaceholder.text.InStr("PRIVATE_KEY") < 0, "Provider error text is not displayed")
    m.providers[0].error = "Request failed at https://private.invalid/PRIVATE_KEY"
    Harness_Ok(ProviderEmptyLabel().InStr("PRIVATE_KEY") < 0, "Provider transport errors cannot expose configuration in the placeholder")
    m.providers[0].streams = []
    m.loadError = m.providers[0].error
    m.pendingCount = 0
    UpdateStreamsStatus()
    Harness_Ok(m.status.text.InStr("PRIVATE_KEY") < 0, "Provider transport errors cannot expose configuration in the status")
    m.providers[0].error = ""
    m.loadTasks = [{result:invalid}]
    Harness_Ok(ProviderEmptyLabel().InStr("45 seconds") >= 0, "Loading placeholder explains the provider wait budget")
    m.grid = {}
    m.header = {}
    m.typeFilter = "all"
    m.sort = "recent"
    m.chunk = 5
    saved = []
    for i = 1 to 37
        saved.Push({name:"Saved " + i.ToStr(), metaId:i.ToStr(), metaType:"movie"})
    end for
    m.stores = { library: {
        testItems: saved
        callFunc: function(name as string, arg1 = invalid as dynamic, arg2 = invalid as dynamic) as dynamic
            if name = "LibraryLibraryView" then return m.testItems
            if name = "LibraryProgressFraction" then return 0
            return ""
        end function
    } }
    BuildRows()
    Harness_Equal(m.grid.numRows, 1, "Library viewport stays below filters")
    Harness_Equal(m.grid.content.children.Count(), 8, "All saved library rows remain available")
    Harness_Equal(m.grid.content.children[7].children[1].title, "Saved 37", "Last library entry is preserved")
    m.stores.library.testItems = []
    BuildRows()
    Harness_Equal(m.grid.numRows, 0, "Empty library has zero visible rows")
    firstId = NextSettingsWorkerId("heartbeat")
    secondId = NextSettingsWorkerId("heartbeat")
    Harness_Ok(firstId <> secondId, "Diagnostic worker ids never repeat on re-entry")
    m.status.text = "Pending"
    heartbeat = {id:secondId,result:invalid,reaped:false}
    m.heartbeatTask = heartbeat
    onTestServerResult(TestEvent({id:firstId,result:{alive:true}}))
    Harness_Equal(m.status.text, "Pending", "Old heartbeat cannot replace the current status")
    onTestServerResult(TestEvent(heartbeat))
    Harness_Ok(not heartbeat.reaped, "Blank heartbeat notification stays pending")
    heartbeat.result = {alive:false,error:"https://private.invalid/key"}
    onTestServerResult(TestEvent(heartbeat))
    Harness_Ok(heartbeat.reaped, "Completed heartbeat reaped")
    Harness_Ok(m.status.text.InStr("private") < 0, "Heartbeat errors do not expose configured addresses")
    network = {id:NextSettingsWorkerId("network"),result:invalid,reaped:false}
    m.netDiagTask = network
    m.status.text = "Current"
    onNetDiagResult(TestEvent({id:"network-old",result:{done:true,summary:"Old"}}))
    Harness_Equal(m.status.text, "Current", "Old diagnostic cannot claim a replacement task")
    onNetDiagResult(TestEvent(network))
    Harness_Ok(not network.reaped, "Blank diagnostic stays pending")
    network.result = {done:false,summary:"A=200"}
    onNetDiagResult(TestEvent(network))
    Harness_Equal(m.status.text, "A=200", "Current progressive diagnostic displayed")
    Harness_Ok(not network.reaped, "Partial diagnostic is not disposed")
    network.result = {done:true,summary:"A=200 B=200"}
    onNetDiagResult(TestEvent(network))
    Harness_Ok(network.reaped, "Final diagnostic is disposed")
    TestWorkerPreparedSources()
    TestStreamsRemoteRefresh()
    TestStreamTileRecycling()
    Harness_Finish()
end sub
