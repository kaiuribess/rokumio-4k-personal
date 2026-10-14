function PrefetchTest_Event(task as object) as object
    return {task:task, GetRoSGNode:function() as object
        return m.task
    end function,GetData:function() as dynamic
        return m.task.result
    end function}
end function

function PrefetchTest_Node() as object
    return {ObserveField:sub(field as string, callback as string)
        m.observed = callback
    end sub, UnobserveField:sub(field as string)
        m.observed = ""
    end sub, callFunc:function(name as string, value as dynamic) as dynamic
        if name = "Prepare" then return PrefetchTest_Prepare(value)
        if name = "Snapshot" then return PrefetchTest_Snapshot(value)
        if name = "Cancel" then PrefetchTest_Cancel(value)
        return invalid
    end function}
end function

sub AsyncTask_Reap(task as object, parent as object, doStop as boolean)
    task.reaped = true
    task.stopped = doStop
end sub
function AsyncTask_Launch(parent as object, kind as string, callback as string, fields as object, id as string) as object
    task = {id:id, kind:kind, result:invalid, reaped:false, stopped:false}
    for each field in fields
        task[field] = fields[field]
    end for
    m.launched.Push(task)
    return task
end function
sub RenderActiveProvider()
    m.renderCalls = m.renderCalls + 1
end sub
sub EmptyStreamsList()
end sub
sub UpdateQualityHint()
end sub
sub ResetProviderNavigation()
end sub
sub CancelEpisodeLoad()
end sub
sub ApplyParamsChrome(params as object)
end sub
sub StartEpisodeLoad(params as object)
end sub
sub RestoreFocus()
    m.focusCalls = m.focusCalls + 1
end sub
sub PushAutomaticPlayer(first as object, sources as object, remembered = false as boolean)
    m.pushCalls = m.pushCalls + 1
end sub
function EntryAt(row as integer, index as integer) as dynamic
    if row <> 0 or index < 0 or index >= m.testEpisodes.Count() then return invalid
    return {season:1,ep:m.testEpisodes[index]}
end function
function Transport() as object
    return {}
end function
function PlaybackStore(http as object) as object
    streams = [{name:"AAC 2.0 1080p",url:"https://media.example.test/movie.mkv"}]
    if Type(m.testProviderStreams) = "roArray" then streams = m.testProviderStreams
    return {availableSources:streams,Streams:function(address as string, kind as string, videoId as string) as object
        return {ok:true,streams:m.availableSources}
    end function}
end function

sub PrefetchTest_Setup(providerCount = 2 as integer)
    m.launched = []
    m.renderCalls = 0
    m.focusCalls = 0
    m.pushCalls = 0
    m.coordinatorNode = PrefetchTest_Node()
    m.top = {screenActive:true, GetScene:function() as object
        return {FindNode:function(id as string) as dynamic
            return m.coordinatorNode
        end function,coordinatorNode:m.coordinatorNode}
    end function,coordinatorNode:m.coordinatorNode}
    m.prefetchState = {sequence:0,context:invalid,entries:[],tasks:[],deadline:0,top:{revision:0},expiry:{control:"stop",duration:60},clock:{now:0,TotalMilliseconds:function() as integer
        return m.now
    end function}}
    installed = []
    for i = 0 to providerCount - 1
        installed.Push({id:"provider"+i.ToStr(),name:"Provider "+i.ToStr(),address:"https://provider.example.test/config"+i.ToStr(),resources:["stream"],types:["movie","series"],idPrefixes:["tt"]})
    end for
    m.stores = {addons:{installed:installed,callFunc:function(name as string,a=invalid as dynamic,b=invalid as dynamic,c=invalid as dynamic,d=invalid as dynamic,e=invalid as dynamic,f=invalid as dynamic) as dynamic
        if name = "AddonsGetAll" then return m.installed
        if name = "AddonsSupportsResource" then return true
        return invalid
    end function},settings:{mode:"projector",callFunc:function(name as string) as string
        return m.mode
    end function},episodes:{callFunc:function(name as string,id as string,season as integer,episode as integer,meta as object) as string
        return id+":"+season.ToStr()+":"+episode.ToStr()
    end function}}
    m.params = {addonAddress:"https://catalog.example.test",metaType:"movie",metaId:"tt123",videoId:"tt123"}
    m.prefetchContext = invalid
    m.prefetchNode = invalid
    m.prefetchWaiting = []
    m.loadTasks = invalid
    m.loadSeq = 0
    m.loadToken = ""
    m.loadKey = ""
    m.selectionTask = invalid
    m.autoPlayEnabled = false
    m.autoPlaySent = false
    m.activeIndex = -1
    m.pendingCount = 0
    m.status = {text:""}
    m.streams = []
    m.streamsList = {rowItemSelected:[0,0]}
end sub

function PrefetchTest_Result(id as string) as object
    source = {name:"AAC 2.0 1080p",url:"https://media.example.test/"+id+".mkv"}
    return {ok:true,streams:[source],readyStreams:[source],error:""}
end function

function PrefetchTest_RememberedHash(identity as string) as string
    if identity = m.expectedRememberedIdentity then return String(64,"a")
    return ""
end function

function PrefetchTest_Registry() as object
    m.testRegistry = {reads:0,Read:function(key as string) as string
        m.reads = m.reads + 1
        return ""
    end function}
    return m.testRegistry
end function

Harness_Suite("Exact source prefetch context never crosses changed configuration")
PrefetchTest_Setup()
context = SourcePrefetch_Context(m.stores,m.params)
Harness_Equal(context.providers.Count(),2,"only matching source providers are in the request context")
originalKey = context.key
Harness_Equal(SourcePrefetch_Context(m.stores,m.params).key,originalKey,"unchanged context is stable")
m.stores.settings.mode = "surround"
Harness_Ok(SourcePrefetch_Context(m.stores,m.params).key <> originalKey,"audio output mode changes cache context")
m.stores.settings.mode = "projector"
m.stores.addons.installed[0].address = "https://provider.example.test/config-new"
Harness_Ok(SourcePrefetch_Context(m.stores,m.params).key <> originalKey,"configured provider path changes cache context")
m.stores.addons.installed[0].address = "https://provider.example.test/config0"
m.params.metaType = "series"
m.params.videoId = "tt123:1:1"
m.params.season = 1
m.params.episode = 1
episodeKey = SourcePrefetch_Context(m.stores,m.params).key
Harness_Ok(episodeKey <> originalKey,"series and exact episode differ from the movie")
m.params.episode = 2
m.params.videoId = "tt123:1:2"
Harness_Ok(SourcePrefetch_Context(m.stores,m.params).key <> episodeKey,"episode selection invalidates prior sources")
Harness_Equal(SourcePrefetch_Context(m.stores,{metaType:"movie",videoId:""}),invalid,"missing media id never starts lookup")

Harness_Suite("One bounded coordinator batch handles cancellation, freshness and stale events")
PrefetchTest_Setup(6)
context = SourcePrefetch_Context(m.stores,m.params)
snapshot = SourcePrefetch_Prepare(m.top,context)
Harness_Equal(m.launched.Count(),4,"prefetch limits one displayed title to four providers")
Harness_Equal(snapshot.entries.Count(),4,"shared memory is limited to four provider entries")
Harness_Equal(m.launched[0].kind,"SourcePrefetchTask","prefetch uses the source JSON worker")
Harness_Equal(m.prefetchState.expiry.duration,60,"cache deadline is one minute")
again = SourcePrefetch_Prepare(m.top,context)
Harness_Equal(m.launched.Count(),4,"same pending context never starts duplicate lookups")
oldTask = m.launched[0]
oldTask.result = invalid
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(oldTask))
Harness_Equal(m.prefetchState.entries[0].status,"pending","blank alwaysNotify completion leaves a real lookup pending")
oldTask.result = PrefetchTest_Result("first")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(oldTask))
Harness_Equal(m.prefetchState.entries[0].status,"ready","successful provider JSON becomes reusable")
revision = m.prefetchState.top.revision
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(oldTask))
Harness_Equal(m.prefetchState.top.revision,revision,"duplicate completion does not republish results")
newParams = {metaType:"movie",metaId:"tt456",videoId:"tt456"}
newContext = SourcePrefetch_Context(m.stores,newParams)
SourcePrefetch_Prepare(m.top,newContext)
Harness_Ok(m.launched[1].stopped,"navigation stops ownership of unfinished old provider workers")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(oldTask))
Harness_Equal(m.prefetchState.entries[0].status,"pending","prior title completion cannot populate the current title")
SourcePrefetch_Cancel(m.top,context)
Harness_Ok(PrefetchTest_Snapshot(newContext.key) <> invalid,"cancel from prior context cannot cancel the new title")
m.prefetchState.clock.now = 1000
PrefetchTest_onPrefetchExpired()
Harness_Ok(m.prefetchState.context <> invalid,"queued expiry from a prior context cannot expire fresh results")
m.prefetchState.clock.now = 60000
Harness_Equal(PrefetchTest_Snapshot(newContext.key),invalid,"snapshot refuses sources at or beyond the deadline")
Harness_Equal(m.prefetchState.context,invalid,"expired URLs are removed from retained memory")

Harness_Suite("Providers beyond the prefetch cap retain the normal Play path")
PrefetchTest_Setup(6)
context = SourcePrefetch_Context(m.stores,m.params)
SourcePrefetch_Prepare(m.top,context)
LoadStreams(m.params)
Harness_Equal(m.launched.Count(),6,"Play starts only the two providers outside the four-worker prefetch cap")
Harness_Equal(m.launched[4].kind,"StreamsLoaderTask","fifth provider is loaded normally at explicit Play")
Harness_Equal(m.pendingCount,6,"all adopted and new providers remain counted")
CancelStreamsLoad()

Harness_Suite("Play consumes completed and pending source JSON without duplicate requests")
PrefetchTest_Setup(3)
context = SourcePrefetch_Context(m.stores,m.params)
SourcePrefetch_Prepare(m.top,context)
first = m.launched[0]
first.result = PrefetchTest_Result("ready")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(first))
LoadStreams(m.params)
Harness_Equal(m.launched.Count(),3,"pressing Play during prefetch reuses the same requests")
Harness_Equal(m.providers[0].streams.Count(),1,"completed provider is available immediately at Play")
Harness_Equal(m.pendingCount,2,"only genuinely pending providers remain in the loading count")
Harness_Ok(isTaskPending(1),"shared pending provider gets a truthful loading placeholder")
second = m.launched[1]
second.result = PrefetchTest_Result("second")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(second))
onSourcePrefetchChanged()
Harness_Equal(m.pendingCount,1,"shared completion counts down exactly once")
Harness_Equal(m.providers[1].streams.Count(),1,"shared result reaches the correct provider slot")
onSourcePrefetchChanged()
Harness_Equal(m.pendingCount,1,"repeated coordinator revision cannot apply twice")
third = m.launched[2]
third.result = {ok:false}
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(third))
onSourcePrefetchChanged()
Harness_Equal(m.launched.Count(),4,"failed provider is refreshed once by the normal Play loader")
Harness_Equal(m.launched[3].kind,"StreamsLoaderTask","failure refresh stays in the ordinary source loading path")
onSourcePrefetchChanged()
Harness_Equal(m.launched.Count(),4,"repeated failure notification cannot duplicate the retry")
retry = m.launched[3]
retry.result = PrefetchTest_Result("retry")
onStreamsLoaded(PrefetchTest_Event(retry))
Harness_Equal(m.pendingCount,0,"normal retry completes the adopted batch")
Harness_Equal(m.providers[2].streams.Count(),1,"fresh provider result replaces a failed prefetch")
RefreshStreams()
Harness_Equal(m.launched.Count(),7,"manual refresh always requests fresh sources from every provider")
Harness_Equal(m.prefetchState.context,invalid,"manual refresh invalidates retained prefetch URLs")
Harness_Equal(m.providers[0].streams.Count(),0,"manual refresh removes formerly cached links immediately")

Harness_Suite("Expired pending requests fall back, with no stuck loading slots")
PrefetchTest_Setup()
context = SourcePrefetch_Context(m.stores,m.params)
SourcePrefetch_Prepare(m.top,context)
LoadStreams(m.params)
m.prefetchState.clock.now = 60000
PrefetchTest_onPrefetchExpired()
onSourcePrefetchChanged()
Harness_Equal(m.launched.Count(),4,"expired shared providers each get one fresh normal request")
Harness_Equal(m.pendingCount,2,"fallback keeps the two outstanding slots counted")
onSourcePrefetchChanged()
Harness_Equal(m.launched.Count(),4,"repeated expiry notification cannot duplicate fallback")
CancelStreamsLoad()
Harness_Equal(m.loadToken,"","Back disowns the current source batch")
Harness_Equal(m.pendingCount,0,"Back clears pending counts")
Harness_Equal(m.prefetchWaiting.Count(),0,"Back clears shared waiting slots")

Harness_Suite("Same episode can only reuse its pending batch under the same configuration")
PrefetchTest_Setup()
LoadStreams(m.params)
OnEnter(m.params)
Harness_Equal(m.launched.Count(),2,"same episode with identical current settings keeps the pending requests")
Harness_Equal(m.focusCalls,1,"same batch only restores focus")
m.stores.settings.mode = "surround"
OnEnter(m.params)
Harness_Equal(m.launched.Count(),4,"changed audio mode requires fresh requests even for the same episode")
Harness_Ok(m.launched[0].stopped,"changed context disowns the old source batch")
Harness_Equal(m.launched[2].audioMode,"surround","fresh batch uses the changed audio policy")

Harness_Suite("Manual source choice cannot be superseded by automatic selection")
PrefetchTest_Setup()
m.providers = [{streams:[{url:"https://media.example.test/selected.mkv"}]}]
m.streams = m.providers[0].streams
m.autoPlayEnabled = true
m.pendingCount = 0
m.loadToken = "live"
MaybeStartAutomaticPlayback()
selection = m.selectionTask
Harness_Ok(selection <> invalid,"explicit Play may rank candidates while Streams is active")
onStreamSelected()
Harness_Equal(m.pushCalls,1,"manual OK pushes exactly the chosen source once")
Harness_Ok(not m.autoPlayEnabled and m.autoPlaySent,"manual source choice disarms automatic playback")
Harness_Ok(selection.stopped and m.selectionTask = invalid,"manual source choice cancels and disowns in-flight automatic ranking")
selection.result = {streams:m.streams}
onAutomaticSourcesReady(PrefetchTest_Event(selection))
Harness_Equal(m.pushCalls,1,"late ranking result cannot replace the manual selection")
MaybeStartAutomaticPlayback()
Harness_Equal(m.launched.Count(),1,"returning to Streams cannot automatically rank another choice")
m.autoPlayEnabled = true
m.autoPlaySent = false
m.top.screenActive = false
MaybeStartAutomaticPlayback()
Harness_Equal(m.launched.Count(),1,"hidden Streams never starts an automatic selection worker")
m.top.screenActive = true
MaybeStartAutomaticPlayback()
selection = m.selectionTask
selection.result = {streams:m.streams}
m.top.screenActive = false
onAutomaticSourcesReady(PrefetchTest_Event(selection))
Harness_Ok(selection.reaped and m.selectionTask = invalid,"hidden completion is reaped instead of stranding the ranking slot")
Harness_Equal(m.pushCalls,1,"hidden ranking completion cannot push a player")

Harness_Suite("Focus debounce only preloads the displayed movie or focused episode")
PrefetchTest_Setup()
m.meta = {id:"tt123",type:"movie"}
m.addonAddress = m.params.addonAddress
m.prefetchTimer = {control:"stop"}
m.prefetchClock = {now:0,TotalMilliseconds:function() as integer
    return m.now
end function}
ScheduleDetailsPrefetch()
Harness_Equal(m.launched.Count(),0,"opening Details waits for the debounce rather than immediately fetching")
Harness_Equal(m.prefetchTimer.control,"start","movie Details schedules source-only prefetch")
onDetailsPrefetch()
Harness_Equal(m.launched.Count(),0,"queued old Details timer cannot bypass the new debounce deadline")
m.prefetchClock.now = 500
onDetailsPrefetch()
Harness_Equal(m.launched.Count(),2,"movie timer fetches only its matching providers")
m.prefetchHandOff = true
DetailsTest_BlurFocus()
Harness_Equal(m.prefetchTimer.control,"stop","Play transition stops the screen debounce")
Harness_Ok(m.prefetchState.context <> invalid,"explicit Play preserves the shared pending batch")
m.top.screenActive = false
onDetailsPrefetch()
Harness_Equal(m.launched.Count(),2,"hidden Details timer cannot start a request")
m.prefetchHandOff = false
DetailsTest_BlurFocus()
Harness_Equal(m.prefetchState.context,invalid,"ordinary navigation cancels the displayed title's prefetch")
m.top.screenActive = true
m.meta = {id:"tt123",type:"series"}
ScheduleDetailsPrefetch()
Harness_Equal(m.prefetchTimer.control,"stop","series Details does not guess or preload every episode")
m.testEpisodes = [{episode:1,name:"Pilot"},{episode:2,name:"Next"}]
m.epList = {rowItemFocused:[0,0]}
ScheduleEpisodePrefetch()
Harness_Equal(m.launched.Count(),2,"episode focus is debounced")
m.epList.rowItemFocused = [0,1]
ScheduleEpisodePrefetch()
onEpisodePrefetch()
Harness_Equal(m.launched.Count(),2,"queued old episode timer cannot bypass a changed focus debounce")
m.prefetchClock.now = 1000
onEpisodePrefetch()
Harness_Equal(m.prefetchState.context.videoId,"tt123:1:2","debounce resolves only the currently focused episode")
ScheduleEpisodePrefetch()
Harness_Equal(m.launched.Count(),4,"repeated focus on the same episode preserves its existing requests")
Harness_Equal(m.prefetchTimer.control,"stop","same episode does not schedule another debounce request")
m.resume = invalid
PushEpisode(1,m.testEpisodes[1])
Harness_Equal(m.launched.Count(),4,"Play reuses the focused episode's two requests")
Harness_Equal(m.top.pushRequest.params.videoId,"tt123:1:2","explicit Play keeps the exact episode identity")
EpisodesTest_BlurFocus()
Harness_Ok(m.prefetchState.context <> invalid,"episode Play preserves the pending handoff")
Harness_Equal(m.prefetchTimer.control,"stop","episode Play stops the debounce timer")

Harness_Suite("Source-only task bounds retained sources without filename-only audio rejection")
raw = []
for i = 0 to 299
    raw.Push({name:"2160p DTS",url:"https://media.example.test/"+i.ToStr()+".mkv"})
end for
raw.Push({name:"1080p AAC 2.0",url:"https://media.example.test/english.mkv"})
bounded = SourcePrefetch_LimitStreams(raw,"projector")
Harness_Equal(bounded.Count(),256,"retained candidate URLs are bounded per provider")
Harness_Equal(bounded[0].name,"1080p AAC 2.0","ranking keeps the preferred stereo-labelled candidate within the cap")
Harness_Equal(bounded[1].name,"2160p DTS","raw candidates retain potentially usable alternate audio tracks")
Harness_Equal(raw.Count(),301,"prefetch ranking does not mutate the provider response array")
remembered = {name:"1080p",url:"https://media.example.test/rotating-signed-url.mkv",behaviorHints:{filename:"remembered.1080p.mkv"},sourceMemoryProvider:"provider|provider.example.test"}
raw.Push(remembered)
baseline = SourcePrefetch_LimitStreams(raw,"projector")
Harness_Ok(baseline[255].name <> "1080p","unlabelled remembered file ordinarily falls below the 256 label-rank cap")
memory = {version:1,entries:[{key:String(64,"a"),outcome:"working",touched:1760000000#,expires:1760001000#}]}
m.expectedRememberedIdentity = SourceMemory_Identity(remembered,"tt123","projector")
warm = SourcePrefetch_LimitStreams(raw,"projector","tt123",memory,1760000001#,PrefetchTest_RememberedHash)
Harness_Equal(warm[0].behaviorHints.filename,"remembered.1080p.mkv","existing verified file is moved ahead of the cap")
Harness_Equal(warm.Count(),256,"preserving a warm working file does not enlarge retained memory")
Harness_Equal(memory.entries.Count(),1,"browse ordering does not record a new source outcome")
otherEpisode = SourcePrefetch_LimitStreams(raw,"projector","tt123:1:2",memory,1760000001#,PrefetchTest_RememberedHash)
Harness_Ok(otherEpisode[0].name <> "1080p","remembered outcomes cannot escape their exact video identity")
otherMode = SourcePrefetch_LimitStreams(raw,"surround","tt123",memory,1760000001#,PrefetchTest_RememberedHash)
Harness_Ok(otherMode[0].name <> "1080p","projector outcomes cannot rank a different surround policy")
duplicates = []
for i = 0 to 299
    duplicates.Push(remembered)
end for
duplicates.Push({name:"2160p",url:"https://media.example.test/fallback.mkv"})
duplicates.Push({name:"2160p",url:"https://media.example.test/Fallback.mkv"})
duplicates.Push({name:"2160p",url:"https://media.example.test/fallback.mkv?signature=new"})
deduped = SourcePrefetch_LimitStreams(duplicates,"projector","tt123",memory,1760000001#,PrefetchTest_RememberedHash)
Harness_Equal(deduped.Count(),4,"hundreds of repeated working URLs cannot consume the cap and hide unique fallback files")
Harness_Equal(deduped[0].url,remembered.url,"exact URL dedupe preserves the memory-prioritized working file first")
Harness_Equal(deduped[1].url,"https://media.example.test/fallback.mkv","first unique fallback remains available")
Harness_Equal(deduped[2].url,"https://media.example.test/Fallback.mkv","case-sensitive delivery paths remain separate candidates")
Harness_Equal(deduped[3].url,"https://media.example.test/fallback.mkv?signature=new","rotated signed URLs remain separate fresh candidates")

Harness_Suite("Bounded projector prefetch preserves a 4K reserve beneath hundreds of HD stereo hints")
mixed = []
for i = 0 to 299
    mixed.Push({name:"1080p AAC2.0",url:"https://media.example.test/hd/"+i.ToStr()+".mkv"})
end for
for i = 0 to 99
    mixed.Push({name:"2160p DTS",url:"https://media.example.test/uhd/"+i.ToStr()+".mkv"})
end for
reserved = SourcePrefetch_LimitStreams(mixed,"projector")
strict4K = CinemaFilterReadyStreams(reserved,true)
Harness_Equal(reserved.Count(),256,"the 4K reserve stays inside the existing unique-source cap")
Harness_Equal(strict4K.Count(),64,"strict 4K filtering exposes a reserve even when 300 HD stereo sources outrank it")
Harness_Equal(reserved[0].url,mixed[0].url,"highest-ranked HD stereo remains the first ordinary playback candidate")
Harness_Equal(reserved[191].url,mixed[191].url,"the first 192 HD stereo candidates retain their original priority")
ordered4K = true
for i = 0 to 63
    if strict4K[i].url <> "https://media.example.test/uhd/"+i.ToStr()+".mkv" then ordered4K = false
end for
Harness_Ok(ordered4K,"reserved 4K files retain provider rank without reversing replacements")
Harness_Equal(mixed.Count(),400,"reserve replacement never mutates the provider response array")
mixed.Push(remembered)
rememberedReserve = SourcePrefetch_LimitStreams(mixed,"projector","tt123",memory,1760000001#,PrefetchTest_RememberedHash)
Harness_Equal(rememberedReserve[0].url,remembered.url,"an earlier verified HD source remains first when the 4K reserve is added")
Harness_Equal(CinemaFilterReadyStreams(rememberedReserve,true).Count(),64,"remembered HD priority cannot consume the 4K reserve")
Harness_Equal(rememberedReserve.Count(),256,"remembered priority and the 4K reserve share the same bounded cache")
Harness_Equal(memory.entries.Count(),1,"reserving candidates never records or changes an outcome")

shortMixed = []
for i = 0 to 299
    shortMixed.Push(mixed[i])
end for
for i = 0 to 79
    shortMixed.Push({name:"2160p DTS",url:"https://media.example.test/Uhd.mkv"})
end for
shortMixed.Push({name:"2160p DTS",url:"https://media.example.test/uhd.mkv"})
shortMixed.Push({name:"2160p DTS",url:"https://media.example.test/uhd.mkv?signature=new"})
shortReserved = SourcePrefetch_LimitStreams(shortMixed,"projector")
short4K = CinemaFilterReadyStreams(shortReserved,true)
Harness_Equal(shortReserved.Count(),256,"a short 4K reserve does not waste the remaining cache capacity")
Harness_Equal(short4K.Count(),3,"duplicate 4K URLs do not inflate a short reserve or hide later unique candidates")
Harness_Equal(short4K[0].url,"https://media.example.test/Uhd.mkv","short reserve preserves the first exact 4K URL")
Harness_Equal(short4K[1].url,"https://media.example.test/uhd.mkv","case-sensitive 4K paths remain different reserve entries")
Harness_Equal(short4K[2].url,"https://media.example.test/uhd.mkv?signature=new","signed URL rotation remains an exact distinct candidate")
Harness_Equal(shortReserved[252].url,mixed[252].url,"a three-entry reserve retains the first 253 ranked HD candidates")

already4K = []
for i = 0 to 9
    already4K.Push({name:"2160p AAC2.0",url:"https://media.example.test/first-uhd/"+i.ToStr()+".mkv"})
end for
for each stream in mixed
    already4K.Push(stream)
end for
alreadyReserved = SourcePrefetch_LimitStreams(already4K,"projector")
alreadyStrict = CinemaFilterReadyStreams(alreadyReserved,true)
Harness_Equal(alreadyStrict.Count(),64,"higher-ranked 4K entries count toward the minimum reserve rather than adding a second reserve")
Harness_Equal(alreadyReserved[0].url,"https://media.example.test/first-uhd/0.mkv","highest-ranked stereo 4K remains the first ordinary candidate")
Harness_Equal(alreadyStrict[9].url,"https://media.example.test/first-uhd/9.mkv","existing high-ranked 4K order is preserved")
Harness_Equal(alreadyStrict[10].url,"https://media.example.test/uhd/0.mkv","later 4K reserve starts after existing higher-ranked 4K")
Harness_Equal(alreadyStrict[63].url,"https://media.example.test/uhd/53.mkv","only the required later 4K candidates replace HD entries")
m.top = {addonAddress:"https://provider.example.test/config",metaType:"movie",videoId:"tt123",providerId:"provider",audioMode:"projector"}
PrefetchTest_Load()
Harness_Ok(m.top.result.ok,"source-only production task publishes a valid successful response")
Harness_Equal(m.top.result.streams[0].sourceMemoryProvider,"provider|provider.example.test","source memory identity excludes the configured secret path")
Harness_Equal(m.testRegistry.reads,1,"prefetch consults existing outcome metadata once without requiring a write method")
m.testProviderStreams = [{name:"2160p Dolby DTS",url:"https://media.example.test/mixed-tracks.mkv"},{name:"1080p AAC2.0",url:"https://media.example.test/stereo.mkv"}]
PrefetchTest_Load()
Harness_Equal(m.top.result.readyStreams.Count(),2,"prefetched picker retains a Dolby-labelled file whose stereo alternative was not named")
Harness_Equal(m.top.result.readyStreams[0].url,"https://media.example.test/stereo.mkv","prefetch still ranks likely playable stereo ahead of uncertain audio")
StreamsTest_Load()
Harness_Equal(m.top.result.readyStreams.Count(),2,"ordinary source worker uses the same non-destructive audio hint policy")
Harness_Equal(m.top.result.readyStreams[0].url,"https://media.example.test/stereo.mkv","ordinary source worker keeps projector preference while retaining alternatives")
Harness_Finish()
