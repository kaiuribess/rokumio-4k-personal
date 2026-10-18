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
    end sub, callFunc:function(name as string, value as dynamic, priority=invalid as dynamic) as dynamic
        if name = "Prepare" then return PrefetchTest_Prepare(value)
        if name = "Snapshot"
            if priority = true then return PrefetchTest_Snapshot(value,true)
            return PrefetchTest_Snapshot(value)
        end if
        if name = "Adopt" then return PrefetchTest_Adopt(value)
        if name = "SetPriority" then PrefetchTest_SetPriority(value,priority)
        if name = "Suspend" then PrefetchTest_Suspend(value)
        if name = "Resume" then return PrefetchTest_Resume(value)
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
    m.prefetchState = {sequence:0,context:invalid,entries:[],tasks:[],activeTasks:[],fullLoad:false,suspended:false,deadline:0,top:{revision:0},expiry:{control:"stop",duration:60},clock:{now:0,TotalMilliseconds:function() as integer
        return m.now
    end function}}
    installed = []
    m.priorityHashKeys = {}
    for i = 0 to providerCount - 1
        addon = {id:"provider"+i.ToStr(),name:"Provider "+i.ToStr(),address:"https://provider.example.test/config"+i.ToStr(),resources:["stream"],types:["movie","series"],idPrefixes:["tt"]}
        installed.Push(addon)
        m.priorityHashKeys[ProviderPriority_Identity(addon)] = String(64, Mid("abcdef0123456789", i+1, 1))
    end for
    m.stores = {addons:{installed:installed,callFunc:function(name as string,a=invalid as dynamic,b=invalid as dynamic,c=invalid as dynamic,d=invalid as dynamic,e=invalid as dynamic,f=invalid as dynamic) as dynamic
        if name = "AddonsGetAll" then return m.installed
        if name = "AddonsSupportsResource" then return true
        return invalid
    end function},settings:{mode:"projector",priority:{preferredProviderKey:"",lastWorkingProviderKey:""},callFunc:function(name as string) as dynamic
        if name = "SettingsGetProviderPriority" then return m.priority
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
    m.sourceQueue = []
    m.sourcesSuspended = false
    m.sourceRevision = 0
    m.selectionRevision = -1
    m.freshnessRefreshUsed = false
    m.autoGraceTimer = {control:"stop",duration:0.75}
    m.autoClock = {now:0,TotalMilliseconds:function() as integer
        return m.now
    end function}
    m.autoGraceDeadline = invalid
    m.autoGraceToken = ""
    m.fourKOnly = false
    m.reloadNeeded = false
    m.streams = []
    m.streamsList = {rowItemSelected:[0,0]}
end sub

function PrefetchTest_Result(id as string) as object
    source = {name:"AAC 2.0 1080p",url:"https://media.example.test/"+id+".mkv"}
    return {ok:true,streams:[source],readyStreams:[source],uhdCount:0,error:""}
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

function PrefetchTest_PriorityHash(identity as string) as dynamic
    m.lastPriorityIdentity = identity
    value = m.priorityHashKeys[identity]
    if Type(value) = "String" or Type(value) = "roString" then return value
    return ""
end function

function PrefetchTest_InvalidPriorityHash(identity as string) as dynamic
    return "not-a-digest"
end function

function PrefetchTest_WarmCount(entries as object) as integer
    count = 0
    for each entry in entries
        if entry.warm = true then count = count + 1
    end for
    return count
end function

Harness_Suite("Provider keys contain public ID and hostname only, never configuration")
PrefetchTest_Setup(6)
addon = m.stores.addons.installed[0]
identity = ProviderPriority_Identity(addon)
firstKey = ProviderPriority_Key(addon, PrefetchTest_PriorityHash)
Harness_Equal(firstKey,String(64,"a"),"injected digest is an opaque validated lowercase key")
Harness_Ok(identity.InStr("config0") < 0 and identity.InStr("https://") < 0,"configured path and scheme do not enter provider identity")
addon.address = "https://PROVIDER.EXAMPLE.TEST:443/new-private-config?token=private-value#fragment"
Harness_Equal(ProviderPriority_Key(addon, PrefetchTest_PriorityHash),firstKey,"path query fragment port and host case do not change priority")
Harness_Equal(ProviderPriority_StreamKey({sourceMemoryProvider:"provider0|PROVIDER.EXAMPLE.TEST:443"}, PrefetchTest_PriorityHash),firstKey,"loaded source and manifest produce the same opaque key")
Harness_Equal(ProviderPriority_StreamKey({sourceMemoryProvider:"provider0|provider.example.test/private"}, PrefetchTest_PriorityHash),"","stream identity cannot smuggle a path")
Harness_Equal(ProviderPriority_StreamKey({sourceMemoryProvider:"provider0|provider.example.test?token=private-value"}, PrefetchTest_PriorityHash),"","stream identity cannot smuggle a query")
Harness_Equal(ProviderPriority_StreamKey({sourceMemoryProvider:"provider0|user:private-value@provider.example.test"}, PrefetchTest_PriorityHash),"","stream identity rejects userinfo")
Harness_Equal(ProviderPriority_StreamKey({sourceMemoryProvider:"provider0|provider.example.test|extra"}, PrefetchTest_PriorityHash),"","extra provider separator is refused")
addon.address = "https://user:private-value@provider.example.test/config"
Harness_Equal(ProviderPriority_Key(addon, PrefetchTest_PriorityHash),"","configured userinfo disables priority instead of persisting it")
addon.address = "https://provider.example.test:bad/config"
Harness_Equal(ProviderPriority_Key(addon, PrefetchTest_PriorityHash),"","invalid port cannot acquire a scheduling identity")
addon.address = "https://provider.example.test./private"
Harness_Equal(ProviderPriority_Key(addon, PrefetchTest_PriorityHash),firstKey,"trailing hostname dot is normalized")
addon.id = "https://private.example.test/token"
Harness_Equal(ProviderPriority_Key(addon, PrefetchTest_PriorityHash),"","a configured URL cannot substitute for a public add-on ID")
addon.id = "provider0"
Harness_Equal(ProviderPriority_Key(addon, PrefetchTest_InvalidPriorityHash),"","unavailable invalid digest never falls back to clear identity")
Harness_Equal(ProviderPriority_Key(invalid, PrefetchTest_PriorityHash),"","malformed provider does not interrupt scheduling")
Harness_Equal(ProviderPriority_Hostname("http://localhost:8080/config?key=private-value"),"localhost","local HTTP provider identity excludes port and configuration")
Harness_Equal(ProviderPriority_Hostname("https://[2001:db8::1]:443/config"),"[2001:db8::1]","IPv6 authority is normalized without its port")
Harness_Equal(ProviderPriority_Hostname("https://bad..example.test/config"),"","invalid hostname labels are rejected")
Harness_Equal(ProviderPriority_Snapshot({preferredProviderKey:"configured-url",lastWorkingProviderKey:String(64,"A")}).preferredProviderKey,"","raw configured values are excluded from priority snapshot")
Harness_Equal(ProviderPriority_Snapshot({preferredProviderKey:"",lastWorkingProviderKey:String(64,"A")}).lastWorkingProviderKey,"","stored keys must be lowercase hexadecimal")
Harness_Ok(not ProviderPriority_IsKey(" " + String(64,"a")),"stored keys cannot contain surrounding whitespace")
Harness_Ok(not ProviderPriority_IsKey(123),"numeric configured values cannot become opaque keys")

Harness_Suite("Preferred and recent providers choose warm slots without changing UI indices")
PrefetchTest_Setup(6)
m.stores.settings.priority = {preferredProviderKey:String(64,"f"),lastWorkingProviderKey:String(64,"e")}
context = SourcePrefetch_Context(m.stores,m.params)
Harness_Equal(context.providers[5].priority,2,"preferred provider retains its original late index")
Harness_Equal(context.providers[4].priority,1,"recently accepted provider is second priority")
Harness_Equal(context.providers[0].priority,0,"ordinary providers retain stable ordinal ties")
snapshot = SourcePrefetch_Prepare(m.top,context)
Harness_Equal(m.launched[0].providerIndex,5,"preferred provider beyond the original first four warms first")
Harness_Equal(m.launched[1].providerIndex,4,"recently working provider takes the other free warm slot")
Harness_Equal(snapshot.entries.Count(),6,"snapshot remains aligned to every original provider index")
Harness_Equal(PrefetchTest_WarmCount(snapshot.entries),4,"only four providers are retained in the warm budget")
Harness_Equal(snapshot.entries[0].status,"queued","ordinary ordinal zero is next warm lookup")
Harness_Equal(snapshot.entries[1].status,"queued","ordinary ordinal one follows stable order")
Harness_Equal(snapshot.entries[2].status,"idle","unselected provider is aligned but not warmed")
first = m.launched[0]
first.result = PrefetchTest_Result("preferred")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(first))
Harness_Equal(m.launched[2].providerIndex,0,"first completion fills a free slot in stable ordinary order")
LoadStreams(m.params)
Harness_Equal(m.providers[5].streams[0].url,first.result.streams[0].url,"adoption routes preferred late-index result to its matching provider")
Harness_Equal(m.prefetchState.entries[2].status,"queued","explicit Play queues providers omitted from warming")
Harness_Equal(m.launched.Count(),3,"adoption never raises two active-transfer budget")
Harness_Equal(m.prefetchState.activeTasks.Count(),2,"priority never preempts an active request")

Harness_Suite("Busy slots choose priority next, missing keys keep stable order")
PrefetchTest_Setup(6)
old = SourcePrefetch_Context(m.stores,m.params)
SourcePrefetch_Prepare(m.top,old)
oldFirst = m.launched[0]
oldSecond = m.launched[1]
SourcePrefetch_Cancel(m.top,old)
m.stores.settings.priority = {preferredProviderKey:String(64,"f"),lastWorkingProviderKey:String(64,"e")}
nextContext = SourcePrefetch_Context(m.stores,{metaType:"movie",videoId:"tt-next"})
SourcePrefetch_Prepare(m.top,nextContext)
Harness_Equal(m.launched.Count(),2,"preferred queued title does not preempt two abandoned transfers")
oldSecond.result = PrefetchTest_Result("abandoned")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(oldSecond))
Harness_Equal(m.launched[2].providerIndex,5,"first freed old slot starts preferred provider of latest title")
Harness_Equal(m.launched[2].videoId,"tt-next","old ownership never launches abandoned title work")
Harness_Equal(m.prefetchState.entries[1].status,"queued","old result cannot satisfy a latest-title provider slot")
oldFirst.result = PrefetchTest_Result("abandoned-again")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(oldFirst))
Harness_Equal(m.launched[3].providerIndex,4,"next freed slot starts recently accepted provider")
revision = m.prefetchState.top.revision
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(oldSecond))
Harness_Equal(m.launched.Count(),4,"duplicate old callback does not release a current slot")
Harness_Equal(m.prefetchState.top.revision,revision,"duplicate old callback cannot republish current queue")
PrefetchTest_Setup(3)
m.stores.settings.priority = {preferredProviderKey:String(64,"f"),lastWorkingProviderKey:String(64,"e")}
missingContext = SourcePrefetch_Context(m.stores,m.params)
SourcePrefetch_Prepare(m.top,missingContext)
Harness_Equal(m.launched[0].providerIndex,0,"uninstalled preferred identity falls back to stable original order")
Harness_Equal(m.launched[1].providerIndex,1,"missing recent identity cannot hide another provider")

Harness_Suite("Configured variants share public priority with stable original ordering")
PrefetchTest_Setup(3)
m.stores.addons.installed[2].id = "provider1"
m.stores.addons.installed[2].address = "https://provider.example.test/other-private-configuration?key=private-value"
m.stores.settings.priority.preferredProviderKey = String(64,"b")
variants = SourcePrefetch_Context(m.stores,m.params)
Harness_Equal(variants.providers[1].priorityKey,variants.providers[2].priorityKey,"same public ID and host deliberately share priority across private configurations")
SourcePrefetch_Prepare(m.top,variants)
Harness_Equal(m.launched[0].providerIndex,1,"first equivalent preferred variant keeps earlier installed ordinal")
Harness_Equal(m.launched[1].providerIndex,2,"second equivalent variant stays independently addressable")
Harness_Equal(m.prefetchState.entries[0].status,"queued","ordinary provider remains queued instead of being lost")

Harness_Suite("Priority changes preserve source validity and only update waiting lookup order")
PrefetchTest_Setup(6)
firstContext = SourcePrefetch_Context(m.stores,m.params)
SourcePrefetch_Prepare(m.top,firstContext)
oldFirst = m.launched[0]
oldSecond = m.launched[1]
m.stores.settings.priority.preferredProviderKey = String(64,"f")
secondContext = SourcePrefetch_Context(m.stores,m.params)
Harness_Equal(firstContext.key,secondContext.key,"preferred provider change does not invalidate still-current sources")
PrefetchTest_SetPriority(secondContext.key,secondContext.providerPriority)
Harness_Equal(m.launched.Count(),2,"updating priority starts no request and never preempts two transfers")
Harness_Equal(m.prefetchState.entries[5].status,"queued","preferred idle provider replaces an unstarted warm slot")
Harness_Equal(PrefetchTest_WarmCount(m.prefetchState.entries),4,"reprioritized warming still has at most four attempts")
Harness_Equal(m.prefetchState.entries[3].status,"idle","latest ordinary unstarted warm slot returns to idle")
oldFirst.result = PrefetchTest_Result("same-current-source")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(oldFirst))
Harness_Equal(m.launched[2].providerIndex,5,"new preference wins the next available slot after ordinary completion")
Harness_Equal(m.prefetchState.entries[0].result.streams[0].url,oldFirst.result.streams[0].url,"completed source remains valid after priority update")
LoadStreams(m.params)
Harness_Equal(m.providers[0].streams.Count(),1,"Play adopts earlier completed source despite changed preference")
Harness_Equal(m.launched.Count(),3,"Play does not refetch accepted current-context results")
SuspendSourceLoading()
m.top.screenActive = false
m.stores.settings.priority.lastWorkingProviderKey = String(64,"e")
recentContext = SourcePrefetch_Context(m.stores,m.params)
Harness_Equal(recentContext.key,secondContext.key,"recent native success cannot invalidate current URL cache")
PrefetchTest_SetPriority(recentContext.key,recentContext.providerPriority)
Harness_Equal(m.launched.Count(),3,"hidden priority update never launches queued work")
preferred = m.launched[2]
preferred.result = PrefetchTest_Result("preferred-ready")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(preferred))
onSourcePrefetchChanged()
Harness_Equal(m.launched.Count(),3,"hidden completion keeps other providers queued")
Harness_Equal(m.providers[5].streams.Count(),1,"late preferred result remains attached to correct source tab")
Harness_Ok(not m.reloadNeeded,"recording recent provider does not trigger a needless source reload")
m.top.screenActive = true
OnEnter(invalid)
Harness_Equal(m.launched.Count(),4,"Back fills only the free slot without re-fetching completed providers")
Harness_Equal(m.launched[3].providerIndex,4,"updated recently accepted provider wins the next waiting ordinary slot")
Harness_Equal(m.providers[0].streams.Count(),1,"Back preserves earlier completed sources")
Harness_Equal(m.prefetchState.activeTasks.Count(),2,"Back respects active ownership while queue priorities change")
PrefetchTest_SetPriority("wrong-title",{preferredProviderKey:String(64,"b"),lastWorkingProviderKey:""})
Harness_Equal(m.prefetchState.context.providerPriority.preferredProviderKey,String(64,"f"),"stale title cannot reprioritize a current queue")

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
Harness_Ok(SourcePrefetch_Context(m.stores,{metaType:"channel",videoId:"channel:1"}) <> invalid,"live channel source requests share the coordinator budget")

Harness_Suite("Shared budget includes warm, queued, abandoned and fresh title lookups")
PrefetchTest_Setup(6)
context = SourcePrefetch_Context(m.stores,m.params)
snapshot = SourcePrefetch_Prepare(m.top,context)
Harness_Equal(m.launched.Count(),2,"warm browse starts only two source-list workers")
Harness_Equal(snapshot.entries.Count(),6,"warm browse keeps original provider indices aligned")
Harness_Equal(PrefetchTest_WarmCount(snapshot.entries),4,"warm browse selects only four provider lookups")
Harness_Equal(snapshot.entries[2].status,"queued","warm providers beyond slots remain queued")
Harness_Equal(m.prefetchState.activeTasks.Count(),2,"shared budget owns exactly two transfers")
SourcePrefetch_Prepare(m.top,context)
Harness_Equal(m.launched.Count(),2,"same context cannot duplicate warm lookups")
first = m.launched[0]
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(first))
Harness_Equal(m.prefetchState.activeTasks.Count(),2,"blank alwaysNotify never frees an active slot")
LoadStreams(m.params)
Harness_Equal(m.launched.Count(),2,"Play adopts warm work instead of launching more than two")
Harness_Equal(m.prefetchState.entries.Count(),6,"all matching providers survive explicit Play adoption")
Harness_Equal(m.pendingCount,6,"running and queued providers are counted")
Harness_Ok(isTaskPending(5),"queued provider shows truthful loading state")
first.result = PrefetchTest_Result("fast")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(first))
onSourcePrefetchChanged()
Harness_Equal(m.providers[0].streams.Count(),1,"ready warm source reaches correct provider")
Harness_Equal(m.pendingCount,5,"one completion counts down exactly once")
Harness_Equal(m.launched.Count(),3,"one completion opens exactly one queued request")
Harness_Equal(m.launched[2].kind,"StreamsLoaderTask","unstarted warm provider becomes full ordinary lookup")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(first))
onSourcePrefetchChanged()
Harness_Equal(m.launched.Count(),3,"duplicate notification never frees another slot")
Harness_Equal(m.pendingCount,5,"duplicate notification never applies twice")
oldSecond = m.launched[1]
CancelStreamsLoad()
Harness_Ok(not oldSecond.stopped,"abandoned running HTTP lookup keeps its observer and budget slot")
Harness_Equal(m.prefetchState.activeTasks.Count(),2,"cancellation does not pretend to free network ownership")
contextB = SourcePrefetch_Context(m.stores,{metaType:"movie",videoId:"ttB"})
contextC = SourcePrefetch_Context(m.stores,{metaType:"movie",videoId:"ttC"})
SourcePrefetch_Prepare(m.top,contextB)
SourcePrefetch_Prepare(m.top,contextC)
Harness_Equal(m.launched.Count(),3,"rapid A to B to C navigation never exceeds two owned lookups")
oldSecond.result = PrefetchTest_Result("abandoned")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(oldSecond))
Harness_Equal(m.launched.Count(),4,"completed abandoned transfer frees one current-title slot")
Harness_Equal(m.launched[3].videoId,"ttC","only latest title is launched, never abandoned queued B")
Harness_Equal(m.prefetchState.entries[0].status,"pending","old source result cannot populate new title")
Harness_Equal(m.prefetchState.activeTasks.Count(),2,"old plus new owned lookup stay under shared cap")
revision = m.prefetchState.top.revision
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(oldSecond))
Harness_Equal(m.prefetchState.top.revision,revision,"duplicate abandoned callback cannot release live slot")
SourcePrefetch_Cancel(m.top,context)
Harness_Ok(PrefetchTest_Snapshot(contextC.key) <> invalid,"old context cancel cannot cancel latest context")
m.prefetchState.clock.now = 1000
PrefetchTest_onPrefetchExpired()
Harness_Ok(m.prefetchState.context <> invalid,"queued old expiry cannot bypass latest deadline")
m.prefetchState.clock.now = 60000
Harness_Equal(PrefetchTest_Snapshot(contextC.key),invalid,"warm retained URLs expire after one minute")
Harness_Equal(m.prefetchState.activeTasks.Count(),2,"expiry keeps unfinished lookups budgeted until result")

Harness_Suite("Suspended source queues preserve every provider and resume on Back")
PrefetchTest_Setup(5)
LoadStreams(m.params)
Harness_Equal(m.launched.Count(),2,"ordinary Play is budgeted with no warm prefetch")
Harness_Equal(m.launched[0].kind,"StreamsLoaderTask","cold explicit Play preserves full ordinary source response")
SuspendSourceLoading()
m.top.screenActive = false
first = m.launched[0]
second = m.launched[1]
first.result = PrefetchTest_Result("ready")
second.result = {streams:[],readyStreams:[],error:"deadline exceeded"}
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(first))
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(second))
onSourcePrefetchChanged()
Harness_Equal(m.launched.Count(),2,"hidden Player leaves remaining providers queued")
Harness_Equal(m.renderCalls,0,"hidden result never rebuilds source UI")
Harness_Equal(m.pendingCount,3,"hidden completed and error responses still count honestly")
m.top.screenActive = true
OnEnter(invalid)
Harness_Equal(m.launched.Count(),4,"returning to Sources resumes two queued lookups")
Harness_Equal(m.prefetchState.activeTasks.Count(),2,"return does not exceed the shared budget")
third = m.launched[2]
third.result = {streams:[],readyStreams:[],error:""}
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(third))
onSourcePrefetchChanged()
Harness_Equal(m.launched.Count(),5,"empty ordinary answer advances the next queued provider")
Harness_Equal(m.pendingCount,2,"empty provider is completed once")
RefreshStreams()
Harness_Ok(m.recoveryManual and m.autoPlayEnabled,"explicit refresh enables fresh automatic retry without source picking")
Harness_Equal(m.recoveryExcluded.Count(),0,"explicit refresh clears the previous attempt exclusions")
Harness_Equal(m.launched.Count(),5,"refresh queues new requests behind unfinished old transfers")
Harness_Equal(m.pendingCount,5,"refresh preserves all matching providers")
Harness_Equal(m.providers[0].streams.Count(),0,"refresh removes formerly cached links")
oldFourth = m.launched[3]
oldFourth.result = PrefetchTest_Result("expired")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(oldFourth))
onSourcePrefetchChanged()
Harness_Equal(m.launched.Count(),6,"old refresh completion frees exactly one fresh lookup")
Harness_Equal(m.launched[5].kind,"StreamsLoaderTask","explicit refresh never truncates new source responses via warm worker")
Harness_Equal(m.pendingCount,5,"expired old response cannot satisfy refreshed provider")
Harness_Equal(m.providers[1].streams.Count(),0,"expired old response cannot restore stale links")

Harness_Suite("Warm failure retries once and explicit Play outlives warm expiry")
PrefetchTest_Setup(3)
context = SourcePrefetch_Context(m.stores,m.params)
SourcePrefetch_Prepare(m.top,context)
LoadStreams(m.params)
first = m.launched[0]
first.result = {ok:false}
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(first))
onSourcePrefetchChanged()
Harness_Equal(m.launched.Count(),3,"one failed warm lookup becomes one fresh ordinary request")
Harness_Equal(m.launched[2].kind,"StreamsLoaderTask","warm failure retries via ordinary worker")
retry = m.launched[2]
revision = m.prefetchState.top.revision
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(first))
Harness_Equal(m.prefetchState.activeTasks.Count(),2,"duplicate failed warm callback cannot free the ordinary replacement slot")
Harness_Equal(m.prefetchState.top.revision,revision,"failed warm callback cannot be republished under a reused worker ID")
Harness_Ok(first.id <> retry.id,"every lookup launch has a unique ID even within the same provider and title")
retry.result = {streams:[],readyStreams:[],error:"deadline exceeded"}
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(retry))
onSourcePrefetchChanged()
Harness_Equal(m.pendingCount,2,"ordinary failure completes without looping warm retry")
Harness_Equal(m.providers[0].error,"deadline exceeded","ordinary failure retains redacted UI diagnostics")
m.prefetchState.clock.now = 60000
PrefetchTest_onPrefetchExpired()
Harness_Ok(m.prefetchState.context <> invalid,"queued old warm expiry cannot expire an adopted Play batch")
CancelStreamsLoad()
Harness_Equal(m.loadToken,"","Back disowns current source batch")
Harness_Equal(m.pendingCount,0,"Back clears pending count")
Harness_Equal(m.prefetchWaiting.Count(),0,"Back clears shared waiting slots")

Harness_Suite("Hidden changed configuration defers reload until Sources returns")
PrefetchTest_Setup(3)
LoadStreams(m.params)
first = m.launched[0]
SuspendSourceLoading()
m.top.screenActive = false
m.stores.settings.mode = "surround"
first.result = PrefetchTest_Result("old-settings")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(first))
onSourcePrefetchChanged()
Harness_Ok(m.reloadNeeded,"late settings change marks source batch for reload")
Harness_Equal(m.launched.Count(),2,"hidden changed configuration never launches new title work")
Harness_Equal(m.renderCalls,0,"hidden changed configuration never touches source UI")
m.top.screenActive = true
OnEnter(invalid)
Harness_Equal(m.launched.Count(),3,"returning starts only available budget slot for fresh configuration")
Harness_Equal(m.launched[2].audioMode,"surround","return reload uses current audio policy")
Harness_Equal(m.launched[2].kind,"StreamsLoaderTask","deferred cold reload uses full ordinary source worker")
Harness_Equal(m.pendingCount,3,"fresh configuration retains all providers")

Harness_Suite("Bounded HD comparison waits for UHD without waiting forever")
PrefetchTest_Setup(2)
m.params.autoPlay = true
m.autoPlayEnabled = true
LoadStreams(m.params)
fast = m.launched[0]
fast.result = PrefetchTest_Result("fast")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(fast))
onSourcePrefetchChanged()
Harness_Equal(m.pendingCount,1,"slow provider remains outstanding")
Harness_Equal(m.selectionTask,invalid,"first fast source begins comparison grace rather than instant playback")
Harness_Equal(m.autoGraceTimer.control,"start","comparison grace timer is armed")
m.autoClock.now = 100
onAutomaticGrace()
Harness_Equal(m.selectionTask,invalid,"queued stale timer cannot bypass comparison grace")
m.autoClock.now = 750
onAutomaticGrace()
Harness_Equal(m.selectionTask,invalid,"early HD waits for potential UHD instead of starting at 750ms")
m.autoClock.now = 3999
onAutomaticGrace()
Harness_Equal(m.selectionTask,invalid,"HD fallback waits to the bounded comparison deadline")
m.autoClock.now = 4000
onAutomaticGrace()
Harness_Ok(m.selectionTask <> invalid,"HD fallback starts after four seconds despite slow provider")
selection = m.selectionTask
Harness_Equal(selection.providerGroups[0].Count(),1,"early candidate pool contains only completed sources")
selection.result = {streams:fast.result.streams}
onAutomaticSourcesReady(PrefetchTest_Event(selection))
Harness_Equal(m.pushCalls,1,"fast provider can start without waiting for every provider")
Harness_Ok(m.sourcesSuspended and m.prefetchState.suspended,"automatic handoff suspends queued work before player push")
Harness_Equal(m.autoGraceTimer.control,"stop","handoff cancels comparison timer")

Harness_Suite("Compare providers, strict 4K, changed filter and empty early ranking")
PrefetchTest_Setup(2)
m.params.waitForProviders = true
m.autoPlayEnabled = true
LoadStreams(m.params)
fast = m.launched[0]
fast.result = PrefetchTest_Result("fast")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(fast))
onSourcePrefetchChanged()
m.autoClock.now = 10000
onAutomaticGrace()
Harness_Equal(m.selectionTask,invalid,"saved compare providers waits for all provider replies")
m.params.waitForProviders = false
m.fourKOnly = true
MaybeStartAutomaticPlayback()
Harness_Equal(m.autoGraceDeadline,invalid,"HD-only fast source cannot open a strict 4K grace")
m.fourKOnly = false
MaybeStartAutomaticPlayback()
m.autoClock.now = 14000
onAutomaticGrace()
selection = m.selectionTask
Harness_Ok(selection <> invalid,"explicit all-quality policy permits the available HD source")
' Quality changed while ranking is pending; stale completion must not hand off.
m.fourKOnly = true
selection.result = {streams:fast.result.streams}
onAutomaticSourcesReady(PrefetchTest_Event(selection))
Harness_Equal(m.pushCalls,0,"ranking from old quality policy cannot bypass new 4K-only setting")
Harness_Equal(m.selectionTask,invalid,"old ranking worker is reaped and disowned")
slow = m.launched[1]
slow.result = {streams:[{name:"2160p AAC 2.0",url:"https://media.example.test/4k.mkv"}],readyStreams:[{name:"2160p AAC 2.0",url:"https://media.example.test/4k.mkv"}],uhdCount:1,error:""}
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(slow))
onSourcePrefetchChanged()
Harness_Ok(m.selectionTask <> invalid,"final provider results rerank the new strict quality pool")
Harness_Ok(m.selectionTask.fourKOnly,"new ranking carries strict 4K policy")

PrefetchTest_Setup(2)
m.autoPlayEnabled = true
LoadStreams(m.params)
fast = m.launched[0]
fast.result = PrefetchTest_Result("fast")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(fast))
onSourcePrefetchChanged()
m.autoClock.now = 4000
onAutomaticGrace()
selection = m.selectionTask
slow = m.launched[1]
slow.result = PrefetchTest_Result("later")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(slow))
onSourcePrefetchChanged()
selection.result = {streams:[]}
onAutomaticSourcesReady(PrefetchTest_Event(selection))
Harness_Ok(m.selectionTask <> invalid,"new results during empty early ranking are reranked rather than stranded")
Harness_Equal(m.selectionTask.providerGroups[0].Count()+m.selectionTask.providerGroups[1].Count(),2,"rerank includes the later provider")

Harness_Suite("Late UHD beats early HD before automatic handoff")
PrefetchTest_Setup(3)
m.autoPlayEnabled = true
LoadStreams(m.params)
fast = m.launched[0]
fast.result = PrefetchTest_Result("early-HD")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(fast))
onSourcePrefetchChanged()
m.autoClock.now = 1000
slow = m.launched[1]
uhd = {name:"2160p English AAC",url:"https://media.example.test/late-4k.mkv"}
slow.result = {streams:[uhd],readyStreams:[uhd],uhdCount:1,error:""}
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(slow))
onSourcePrefetchChanged()
Harness_Equal(m.autoGraceDeadline,1750,"UHD arrival shortens existing HD wait to 750ms")
m.autoClock.now = 1749
onAutomaticGrace()
Harness_Equal(m.selectionTask,invalid,"stale grace event cannot prematurely select UHD")
m.autoClock.now = 1750
onAutomaticGrace()
Harness_Ok(m.selectionTask <> invalid,"UHD starts brief comparison without waiting for remaining provider")
Harness_Equal(m.selectionTask.providerGroups[1][0].url,uhd.url,"selection receives late UHD provider")

Harness_Suite("Nonempty stale ranking cannot beat newer provider results")
PrefetchTest_Setup(2)
m.autoPlayEnabled = true
LoadStreams(m.params)
fast = m.launched[0]
fast.result = PrefetchTest_Result("early-HD")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(fast))
onSourcePrefetchChanged()
m.autoClock.now = 4000
onAutomaticGrace()
selection = m.selectionTask
slow = m.launched[1]
uhd = {name:"2160p English AAC",url:"https://media.example.test/new-4k.mkv"}
slow.result = {streams:[uhd],readyStreams:[uhd],uhdCount:1,error:""}
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(slow))
onSourcePrefetchChanged()
selection.result = {streams:fast.result.streams}
onAutomaticSourcesReady(PrefetchTest_Event(selection))
Harness_Equal(m.pushCalls,0,"old HD decision cannot hand off after UHD already arrived")
Harness_Ok(m.selectionTask <> invalid and m.selectionTask.id <> selection.id,"fresh revision reranks once before playback")
current = m.selectionTask
current.result = {streams:[uhd]}
onAutomaticSourcesReady(PrefetchTest_Event(current))
Harness_Equal(m.pushCalls,1,"fresh UHD decision hands off exactly once")
onAutomaticSourcesReady(PrefetchTest_Event(selection))
Harness_Equal(m.pushCalls,1,"stale nonempty completion cannot replace accepted playback")

Harness_Suite("Unavailable optional comparison clock never strands automatic selection")
PrefetchTest_Setup(2)
m.autoPlayEnabled = true
m.autoClock = invalid
LoadStreams(m.params)
fast = m.launched[0]
fast.result = PrefetchTest_Result("fast")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(fast))
onSourcePrefetchChanged()
Harness_Ok(m.selectionTask <> invalid,"missing comparison clock falls back to immediate ready-candidate selection")
Harness_Equal(m.autoGraceTimer.control,"stop","missing clock does not arm an unfinishable grace timer")

Harness_Suite("Actual quality button cancels grace and stale ranking")
PrefetchTest_Setup(2)
m.autoPlayEnabled = true
m.activeIndex = 0
LoadStreams(m.params)
fast = m.launched[0]
fast.result = PrefetchTest_Result("fast")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(fast))
onSourcePrefetchChanged()
Harness_Ok(onKeyEvent("options",true),"native quality button is handled during grace")
Harness_Ok(m.fourKOnly,"quality button enables strict 4K")
Harness_Equal(m.autoGraceTimer.control,"stop","quality button stops old comparison grace")
m.autoClock.now = 750
onAutomaticGrace()
Harness_Equal(m.selectionTask,invalid,"canceled old grace cannot select old HD policy")
Harness_Ok(onKeyEvent("options",true),"quality button can restore all-quality policy")
m.autoClock.now = 4750
onAutomaticGrace()
oldSelection = m.selectionTask
Harness_Ok(oldSelection <> invalid,"restored quality schedules its own automatic ranking")
onKeyEvent("options",true)
Harness_Ok(oldSelection.stopped,"quality button cancels in-flight old ranking")
onKeyEvent("options",true)
m.autoClock.now = 8750
onAutomaticGrace()
newSelection = m.selectionTask
Harness_Ok(newSelection <> invalid and newSelection.id <> oldSelection.id,"repeated policy changes always mint a unique ranking worker ID")
oldSelection.result = {streams:fast.result.streams}
onAutomaticSourcesReady(PrefetchTest_Event(oldSelection))
Harness_Equal(m.pushCalls,0,"old ranking with matching restored quality still cannot claim a newer selection")
Harness_Equal(m.selectionTask.id,newSelection.id,"old ranking never reaps current ranking slot")
CancelStreamsLoad()
onAutomaticGrace()
Harness_Equal(m.pushCalls,0,"canceling current title disowns queued grace notification")

Harness_Suite("Manual source choice always supersedes automatic selection")
PrefetchTest_Setup()
m.providers = [{streams:[{url:"https://media.example.test/selected.mkv"}]}]
m.streams = m.providers[0].streams
m.autoPlayEnabled = true
m.pendingCount = 0
m.loadToken = "live"
m.sourceRows = [{kind:"source",index:0,loadToken:"live",providerIndex:0,page:0}]
m.sourcePage = 0
m.activeIndex = 0
m.listFilled = true
m.pageSelectionBlocked = invalid
m.streamsList.rowItemFocused = [0,0]
MaybeStartAutomaticPlayback()
selection = m.selectionTask
Harness_Ok(selection <> invalid,"explicit Play can rank completed sources")
onStreamSelected()
Harness_Equal(m.pushCalls,1,"manual OK pushes the chosen source once")
Harness_Ok(not m.autoPlayEnabled and m.autoPlaySent,"manual choice disarms automatic playback")
Harness_Ok(selection.stopped and m.selectionTask = invalid,"manual choice cancels pending automatic ranking")
selection.result = {streams:m.streams}
onAutomaticSourcesReady(PrefetchTest_Event(selection))
Harness_Equal(m.pushCalls,1,"late ranking cannot replace manual choice")
Harness_Ok(m.sourcesSuspended,"manual handoff suspends remaining lookup queue")
MaybeStartAutomaticPlayback()
Harness_Equal(m.launched.Count(),1,"hidden or returned manual choice cannot trigger automatic repick")

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
for each abandoned in [m.launched[0],m.launched[1]]
    abandoned.result = PrefetchTest_Result("done")
    PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(abandoned))
end for
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
Harness_Equal(bounded[0].name,"2160p DTS","UHD labels take priority; native inspection still checks alternate audio")
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
Harness_Equal(strict4K.Count(),100,"UHD-first ranking retains all 100 available UHD entries inside the cap")
Harness_Equal(reserved[0].url,"https://media.example.test/uhd/0.mkv","UHD is tried before HD stereo fallback")
Harness_Equal(reserved[191].url,mixed[91].url,"HD alternatives retain provider order after the UHD tier")
ordered4K = true
for i = 0 to 63
    if strict4K[i].url <> "https://media.example.test/uhd/"+i.ToStr()+".mkv" then ordered4K = false
end for
Harness_Ok(ordered4K,"reserved 4K files retain provider rank without reversing replacements")
Harness_Equal(mixed.Count(),400,"reserve replacement never mutates the provider response array")
mixed.Push(remembered)
rememberedReserve = SourcePrefetch_LimitStreams(mixed,"projector","tt123",memory,1760000001#,PrefetchTest_RememberedHash)
Harness_Equal(rememberedReserve[0].url,remembered.url,"cache retains the verified HD fallback; automatic selection reapplies UHD-first tiers")
Harness_Equal(CinemaFilterReadyStreams(rememberedReserve,true).Count(),100,"remembered HD priority cannot displace UHD candidates")
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
Harness_Equal(shortReserved[255].url,mixed[252].url,"three UHD entries still leave room for the first 253 HD alternatives")

already4K = []
for i = 0 to 9
    already4K.Push({name:"2160p AAC2.0",url:"https://media.example.test/first-uhd/"+i.ToStr()+".mkv"})
end for
for each stream in mixed
    already4K.Push(stream)
end for
alreadyReserved = SourcePrefetch_LimitStreams(already4K,"projector")
alreadyStrict = CinemaFilterReadyStreams(alreadyReserved,true)
Harness_Equal(alreadyStrict.Count(),110,"all 110 UHD candidates fit and remain available ahead of HD fallback")
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
Harness_Equal(m.top.result.readyStreams[0].url,"https://media.example.test/mixed-tracks.mkv","4K first retains quality priority; file audio checks decide compatibility")
StreamsTest_Load()
Harness_Equal(m.top.result.readyStreams.Count(),2,"ordinary source worker uses the same non-destructive audio hint policy")
Harness_Equal(m.top.result.readyStreams[0].url,"https://media.example.test/mixed-tracks.mkv","ordinary worker uses the same UHD-first policy while retaining HD fallback")
Harness_Suite("Warm provider diagnostics survive candidate filtering")
for each statusSource in [
    {name:"Torrentio [TB Error]",url:"https://torrentio.strem.fun/videos/failed_access_v3.mp4"},
    {name:"Torrentio [TB Download] 2160p",url:"https://torrentio.strem.fun/videos/downloading_v3.mp4"}
]
    m.testProviderStreams = [statusSource]
    PrefetchTest_Load()
    warmResult = m.top.result
    warmLabel = AddonDiagnostics_ProviderLabel(warmResult, false, 0, CinemaSkippedSources(warmResult.streams))
    StreamsTest_Load()
    ordinaryResult = m.top.result
    ordinaryLabel = AddonDiagnostics_ProviderLabel(ordinaryResult, false, 0, CinemaSkippedSources(ordinaryResult.streams))
    Harness_Equal(warmLabel,ordinaryLabel,"warm path retains account and pending-download explanations")
    Harness_Equal(warmResult.streams.Count(),0,"diagnostic records do not become playable candidates")
end for
Harness_Suite("Source waiting stays visible and progress stops on cancellation")
PrefetchTest_Setup(2)
m.sourceProgress={control:"stop"}
LoadStreams(m.params)
m.autoClock.now=12000
onSourceProgress()
Harness_Ok(m.status.text.InStr("12s elapsed")>=0,"waiting shows elapsed time instead of a static freeze-like status")
Harness_Ok(m.status.text.InStr("Back cancels")>=0,"cancellation remains visible while providers wait")
info=SourceLoadStatus()
Harness_Equal(info.pending,2,"safe status reports outstanding providers")
Harness_Equal(info.elapsedSeconds,12,"safe status exposes age without provider URLs")
Harness_Ok(FormatJson(info).InStr("https://")<0,"diagnostic contains no configured endpoint")
CancelStreamsLoad()
onSourceProgress()
Harness_Equal(m.sourceProgress.control,"stop","Back disarms progress updates")
Harness_Suite("Completed playback recovery really refreshes the provider batch")
PrefetchTest_Setup(2)
LoadStreams(m.params)
oldFirst = m.launched[0]:oldSecond = m.launched[1]
oldFirst.result = PrefetchTest_Result("expired-first")
oldSecond.result = PrefetchTest_Result("expired-second")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(oldFirst))
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(oldSecond))
onSourcePrefetchChanged()
Harness_Equal(m.pendingCount,0,"production callbacks complete both old providers")
Harness_Equal(m.loadTasks.Count(),2,"completed screen retains its two invalid task slots")
Harness_Equal(m.loadTasks[0],invalid,"a retained slot is not an active source request")
oldToken = m.loadToken
SuspendSourceLoading():m.top.screenActive = false
request = {videoId:m.params.videoId,position:1136.63,excludedUrls:[oldFirst.result.streams[0].url,oldSecond.result.streams[0].url],round:1,manual:false}
Harness_Ok(PrepareSourceRecovery(request),"real recovery preparation accepts the completed title")
Harness_Ok(m.reloadNeeded,"completed batch requests a fresh provider pass")
m.top.screenActive = true:OnEnter(invalid)
Harness_Equal(m.launched.Count(),4,"real re-entry starts two fresh requests despite completed invalid slots")
Harness_Equal(m.prefetchState.activeTasks.Count(),2,"fresh recovery retains the shared two-transfer budget")
Harness_Ok(m.loadToken <> oldToken,"recovery reload mints a new screen batch token")
Harness_Equal(m.pendingCount,2,"fresh batch exposes both pending providers")
Harness_Equal(m.providers[0].streams.Count(),0,"expired retained sources are cleared before fresh requests")
Harness_Equal(m.params.position,1136.63,"recovery reload preserves accepted resume progress")
Harness_Equal(m.recoveryRound,1,"recovery reload preserves its bounded round")
Harness_Equal(m.recoveryExcluded.Count(),2,"automatic recovery retains both failed delivery exclusions")
Harness_Equal(m.recoveryExcluded[0],oldFirst.result.streams[0].url,"exact failed URL remains private and excluded")
Harness_Ok(m.autoPlayEnabled and not m.autoPlaySent,"fresh results retain automatic handoff intent")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(oldFirst))
onSourcePrefetchChanged()
Harness_Equal(m.pendingCount,2,"duplicate old completion cannot complete a current provider")
Harness_Equal(m.providers[0].streams.Count(),0,"old completed sources cannot repopulate the fresh batch")
if m.launched.Count() >= 4
    fresh = m.launched[2]
    fresh.result = PrefetchTest_Result("fresh-working")
    PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(fresh))
    onSourcePrefetchChanged()
    Harness_Equal(m.providers[0].streams[0].url,fresh.result.streams[0].url,"fresh provider result crosses the actual coordinator-to-screen boundary")
end if
OnEnter(invalid)
Harness_Equal(m.launched.Count(),4,"duplicate re-entry never starts another replacement batch")

Harness_Suite("Pending recovery resumes existing work without cancelling or refetching it")
PrefetchTest_Setup(3)
LoadStreams(m.params)
first = m.launched[0]
first.result = PrefetchTest_Result("already-failed")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(first))
onSourcePrefetchChanged()
Harness_Equal(m.pendingCount,2,"two providers remain after the first source is offered")
oldToken = m.loadToken:oldSequence = m.prefetchState.sequence
SuspendSourceLoading():m.top.screenActive = false
request = {videoId:m.params.videoId,position:456,excludedUrls:[first.result.streams[0].url],round:1,manual:false}
PrepareSourceRecovery(request)
Harness_Ok(not m.reloadNeeded,"automatic early-pool exhaustion preserves pending source work")
m.top.screenActive = true:OnEnter(invalid)
Harness_Equal(m.launched.Count(),3,"pending recovery launches no duplicate source requests")
Harness_Equal(m.loadToken,oldToken,"pending recovery keeps the same screen ownership token")
Harness_Equal(m.prefetchState.sequence,oldSequence,"pending recovery does not cancel coordinator ownership")
Harness_Equal(m.prefetchState.activeTasks.Count(),2,"pending recovery remains inside the two-transfer budget")
Harness_Equal(m.providers[0].streams[0].url,first.result.streams[0].url,"retained results remain available for filtered ranking")
Harness_Equal(m.recoveryExcluded.Count(),1,"failed early candidate stays excluded while queued providers resume")
Harness_Equal(m.params.position,456,"pending recovery also preserves the accepted checkpoint")

Harness_Suite("Completed results expire by receipt age without abandoning active transfers")
PrefetchTest_Setup(3)
LoadStreams(m.params)
first = m.launched[0]
second = m.launched[1]
m.prefetchState.clock.now = 100000
first.result = PrefetchTest_Result("old-receipt")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(first))
onSourcePrefetchChanged()
third = m.launched[2]
Harness_Equal(m.prefetchState.entries[0].receivedAt,100000,"completion stores monotonic receipt time rather than batch creation time")
m.prefetchState.clock.now = 399999
snapshot = PrefetchTest_Snapshot(m.prefetchContext.key,true)
Harness_Ok(not snapshot.refreshed,"completed result remains reusable immediately before five-minute receipt budget")
Harness_Equal(m.launched.Count(),3,"fresh snapshot does not duplicate existing provider work")
m.params.position = 234.5
m.recoveryExcluded = [first.result.streams[0].url]
m.recoveryRound = 1
oldToken = m.loadToken
oldSequence = m.prefetchState.sequence
m.prefetchState.clock.now = 400000
Harness_Ok(RefreshExpiredSourceResults(),"new selection expires completed results exactly at receipt budget")
Harness_Equal(m.providers[0].streams.Count(),0,"expired private URLs leave screen state before handoff")
Harness_Equal(m.pendingCount,3,"expired provider becomes pending once alongside two preserved transfers")
Harness_Equal(m.prefetchState.entries[0].status,"queued","two occupied transfers keep refresh queued")
Harness_Equal(m.prefetchState.activeTasks.Count(),2,"expiry preserves shared two-worker ownership")
Harness_Equal(m.launched.Count(),3,"expiry never cancels or duplicates still-running providers")
Harness_Ok(not second.stopped and not third.stopped,"in-flight source tasks are not stopped by freshness expiry")
Harness_Equal(m.loadToken,oldToken,"freshness keeps the screen's live batch identity")
Harness_Equal(m.prefetchState.sequence,oldSequence,"freshness keeps pending coordinator ownership")
Harness_Equal(m.params.position,234.5,"accepted checkpoint survives refresh")
Harness_Equal(m.recoveryRound,1,"bounded recovery round survives refresh")
Harness_Equal(m.recoveryExcluded.Count(),1,"failed delivery exclusions survive refresh")
Harness_Ok(not RefreshExpiredSourceResults(),"repeated freshness check does not enqueue an expired provider twice")
Harness_Equal(m.pendingCount,3,"duplicate refresh cannot increment pending twice")
second.result = PrefetchTest_Result("slow-original")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(second))
onSourcePrefetchChanged()
Harness_Equal(m.providers[1].streams[0].url,second.result.streams[0].url,"already-running completion still belongs to the original title")
Harness_Equal(m.launched.Count(),4,"one freed slot launches exactly one expired-provider replacement")
replacement = m.launched[3]
Harness_Equal(replacement.providerIndex,0,"replacement refreshes only expired completed provider")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(first))
onSourcePrefetchChanged()
Harness_Equal(m.pendingCount,2,"duplicate expired worker event cannot satisfy replacement")
Harness_Equal(m.providers[0].streams.Count(),0,"duplicate expired result cannot return old signed links")
replacement.result = PrefetchTest_Result("fresh-replacement")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(replacement))
onSourcePrefetchChanged()
Harness_Equal(m.providers[0].streams[0].url,replacement.result.streams[0].url,"fresh replacement reaches screen through production callbacks")
Harness_Equal(m.pendingCount,1,"only the original third transfer remains pending")

Harness_Suite("Playback suspension does not expire sources until a new screen return")
PrefetchTest_Setup(2)
LoadStreams(m.params)
for each task in m.launched
    task.result = PrefetchTest_Result(task.id)
    PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(task))
end for
onSourcePrefetchChanged()
SuspendSourceLoading():m.top.screenActive = false
m.prefetchState.clock.now = 3600000
snapshot = PrefetchTest_Snapshot(m.prefetchContext.key)
Harness_Equal(snapshot.entries[0].status,"ready","passive snapshot never expires a playing source")
snapshot = PrefetchTest_Snapshot(m.prefetchContext.key,true)
Harness_Ok(not snapshot.refreshed,"even explicit freshness requests respect accepted-playback suspension")
Harness_Ok(not RefreshExpiredSourceResults(),"hidden source screen cannot refresh or push playback")
PrefetchTest_onPrefetchExpired()
Harness_Equal(m.prefetchState.entries[0].status,"ready","old warm timer cannot expire adopted playback results")
Harness_Equal(m.launched.Count(),2,"one hour of accepted playback never launches new provider transfers")
m.top.screenActive = true:OnEnter(invalid)
Harness_Equal(m.launched.Count(),4,"return from a long movie refreshes both expired completed providers")
Harness_Equal(m.pendingCount,2,"screen return reflects fresh work")
Harness_Equal(m.providers[0].streams.Count(),0,"source screen cannot retain an expired first provider")
Harness_Equal(m.providers[1].streams.Count(),0,"source screen cannot retain an expired second provider")
OnEnter(invalid)
Harness_Equal(m.launched.Count(),4,"repeated return does not restart pending replacements")

Harness_Suite("Freshness blocks stale automatic ranking and manual handoffs")
PrefetchTest_Setup(1)
LoadStreams(m.params)
first = m.launched[0]
first.result = PrefetchTest_Result("old-automatic")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(first))
onSourcePrefetchChanged()
m.autoPlayEnabled = true
MaybeStartAutomaticPlayback()
selection = m.selectionTask
m.prefetchState.clock.now = 300000
selection.result = {streams:first.result.streams,rememberedSource:false}
onAutomaticSourcesReady(PrefetchTest_Event(selection))
Harness_Equal(m.pushCalls,0,"ranking completed after receipt expiry cannot launch an old URL")
Harness_Equal(m.pendingCount,1,"stale automatic result starts a fresh lookup")
Harness_Ok(selection.reaped,"stale automatic ranking releases its worker")
replacement = m.launched[2]
replacement.result = PrefetchTest_Result("new-automatic")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(replacement))
onSourcePrefetchChanged()
selection = m.selectionTask
selection.result = {streams:replacement.result.streams,rememberedSource:false}
onAutomaticSourcesReady(PrefetchTest_Event(selection))
Harness_Equal(m.pushCalls,1,"fresh replacement can hand off normally")
PrefetchTest_Setup(1)
LoadStreams(m.params)
first = m.launched[0]
first.result = PrefetchTest_Result("old-manual")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(first))
onSourcePrefetchChanged()
m.activeIndex = 0:m.sourcePage = 0:m.listFilled = true
m.streams = first.result.streams
m.sourceRows = [{kind:"source",index:0,loadToken:m.loadToken,providerIndex:0,page:0}]
m.streamsList.rowItemFocused = [0,0]
m.prefetchState.clock.now = 300000
onStreamSelected()
Harness_Equal(m.pushCalls,0,"manual row cannot hand off an expired link")
Harness_Equal(m.pendingCount,1,"manual selection refreshes the expired provider")
Harness_Ok(not m.autoPlayEnabled,"manual freshness refresh preserves manual source-choice intent")
Harness_Ok(not m.sourcesSuspended,"manual refresh leaves screen usable while new results arrive")

Harness_Suite("Adoption, failures and clock reset have bounded result retention")
PrefetchTest_Setup(1)
LoadStreams(m.params)
failed = m.launched[0]
failed.result = {error:"offline"}
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(failed))
onSourcePrefetchChanged()
Harness_Equal(m.prefetchState.entries[0].status,"failed","ordinary lookup failure is completed")
m.prefetchState.clock.now = 300000
snapshot = PrefetchTest_Adopt(m.prefetchContext)
Harness_Equal(snapshot.entries[0].status,"pending","new adoption retries stale completed failures")
Harness_Equal(m.launched.Count(),2,"expired failure gets one bounded replacement")
PrefetchTest_Adopt(m.prefetchContext)
Harness_Equal(m.launched.Count(),2,"repeated adoption preserves pending replacement")
replacement = m.launched[1]
m.prefetchState.clock.now = 400000
replacement.result = PrefetchTest_Result("clock-reset")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(replacement))
m.prefetchState.clock.now = 1
snapshot = PrefetchTest_Snapshot(m.prefetchContext.key,true)
Harness_Ok(snapshot.refreshed,"backwards monotonic clock invalidates uncertain receipt age")
Harness_Equal(m.launched.Count(),3,"clock reset starts one refresh, not an unbounded loop")

Harness_Suite("Slow Compare-providers batches reach a bounded handoff beyond receipt TTL")
PrefetchTest_Setup(16)
m.params.waitForProviders = true
m.autoPlayEnabled = true
LoadStreams(m.params)
for i = 0 to 15
    m.prefetchState.clock.now = (Int(i / 2) + 1) * 45000
    m.autoClock.now = m.prefetchState.clock.now
    completed = m.launched[i]
    completed.result = PrefetchTest_Result("slow-provider-" + i.ToStr())
    PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(completed))
    onSourcePrefetchChanged()
end for
Harness_Equal(m.pendingCount,0,"sixteen 45-second providers can all finish despite batch age exceeding five minutes")
Harness_Equal(m.launched.Count(),17,"long Compare batch does not continually restart earlier results during loading")
selection = m.selectionTask
selection.result = {streams:m.providers[0].streams,rememberedSource:false}
onAutomaticSourcesReady(PrefetchTest_Event(selection))
Harness_Equal(m.pendingCount,2,"handoff makes one freshness sweep for the two expired earliest completions")
Harness_Equal(m.prefetchState.activeTasks.Count(),2,"bounded refresh still uses only two workers")
replacementOne = m.launched[17]
replacementTwo = m.launched[18]
m.prefetchState.clock.now = 405000:m.autoClock.now = 405000
for each replacement in [replacementOne,replacementTwo]
    replacement.result = PrefetchTest_Result("fresh-slow-" + replacement.providerIndex.ToStr())
    PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(replacement))
    onSourcePrefetchChanged()
end for
Harness_Equal(m.pendingCount,0,"one bounded sweep finishes while later original results have also aged")
selection = m.selectionTask
selection.result = {streams:m.providers[0].streams,rememberedSource:false}
onAutomaticSourcesReady(PrefetchTest_Event(selection))
Harness_Equal(m.pushCalls,1,"Compare hands off instead of entering a sliding expiry loop")
Harness_Equal(m.launched.Count(),20,"sixteen provider calls plus two replacements and two rankings bound the action")
Harness_Equal(m.prefetchState.activeTasks.Count(),0,"completed bounded refresh leaves no abandoned transfer")

Harness_Suite("Safe status distinguishes empty, failed, HD and UHD-labelled results")
PrefetchTest_Setup(3)
LoadStreams(m.params)
first = m.launched[0]
first.result = PrefetchTest_Result("hd-status")
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(first))
second = m.launched[1]
second.result = {error:"private fixture error must not be exposed"}
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(second))
third = m.launched[2]
third.result = PrefetchTest_Result("uhd-status")
third.result.uhdCount = 1
PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(third))
onSourcePrefetchChanged()
info = SourceLoadStatus()
Harness_Equal(info.providers,3,"safe status reports matching provider count")
Harness_Equal(info.completed,3,"safe status reports both success and failure completions")
Harness_Equal(info.failed,1,"safe status separately counts lookup failures")
Harness_Equal(info.readyCandidates,2,"safe status counts ready candidates without exposing identities")
Harness_Equal(info.uhdLabelCandidates,1,"status calls the quality count UHD labels, not decoded UHD")
Harness_Ok(FormatJson(info).InStr("private") < 0,"status does not expose provider error text")
Harness_Ok(FormatJson(info).InStr("https://") < 0,"status does not expose provider or media URLs")
Harness_Equal(info.Count(),13,"diagnostic shape is a fixed scalar allowlist including effective playback mode")
Harness_Ok(not info.fourKOnly and not info.waitForProviders,"default source status reports all-quality Start sooner mode")
m.fourKOnly = true:m.params.waitForProviders = true
info = SourceLoadStatus()
Harness_Ok(info.fourKOnly and info.waitForProviders,"source status exposes effective strict UHD and Compare providers settings")
m.fourKOnly = false:m.params.fourKOnly = true
Harness_Ok(not SourceLoadStatus().fourKOnly,"source status reports the active screen filter rather than a stale parameter")
m.headTitle = {text:"Fixture"}
m.autoPlayEnabled = true
PrefetchTest_PushAutomaticPlayer(first.result.streams[0],first.result.streams)
Harness_Ok(m.top.pushRequest.params.preferUhd,"automatic player receives measured-HD deferral intent")
DisableAutomaticForManualBrowse()
PrefetchTest_PushAutomaticPlayer(first.result.streams[0],first.result.streams)
Harness_Ok(not m.top.pushRequest.params.preferUhd,"manual player keeps the selected source without automatic UHD deferral")
Harness_Suite("Native boxed integer source counts cross coordinator, screen and automatic startup")
boxedCount = CreateObject("roInt"):boxedCount.SetInt(1)
boxedLongCount = CreateObject("roLongInteger"):boxedLongCount.SetLongInt(1&)
nativeResult = {uhdCount:boxedCount}
Harness_Equal(Type(nativeResult.uhdCount),"roInt","regression fixture retains a real boxed roInt inside the task-result associative array")
Harness_Equal(Type(boxedLongCount),"roLongInteger","regression fixture also exercises a real native 64-bit integer wrapper")
for each count in [1,1&,boxedCount,boxedLongCount]
    PrefetchTest_Setup(2)
    m.autoPlayEnabled = true
    m.fourKOnly = true
    LoadStreams(m.params)
    completed = m.launched[0]
    uhd = {name:"2160p English AAC",url:"https://media.example.test/boxed-count.mkv"}
    completed.result = {streams:[uhd],readyStreams:[uhd],uhdCount:count,error:""}
    PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(completed))
    onSourcePrefetchChanged()
    Harness_Equal(m.providers[0].uhdCount,1,"integer count survives the actual worker-to-screen callback boundary")
    Harness_Equal(Type(m.providers[0].uhdCount),"Integer","accepted native wrapper is normalized to a small scalar integer")
    Harness_Equal(SourceLoadStatus().uhdLabelCandidates,1,"safe status reports the completed UHD count while another provider is pending")
    Harness_Ok(SourceLoadStatus().fourKOnly,"safe status confirms the active strict-UHD filter independently of source counts")
    Harness_Equal(m.autoGraceDeadline,750,"eligible UHD uses the bounded 750ms comparison interval")
    m.autoClock.now = 749
    onAutomaticGrace()
    Harness_Equal(m.selectionTask,invalid,"boxed count cannot bypass the startup grace timer")
    m.autoClock.now = 750
    onAutomaticGrace()
    Harness_Ok(m.selectionTask <> invalid,"strict UHD starts ranking without waiting for the remaining slow provider")
    if m.selectionTask <> invalid then Harness_Ok(m.selectionTask.fourKOnly,"count admission preserves the separate strict UHD selection policy")
end for

Harness_Suite("Source count admission rejects coercion and bounds native integer counters")
boxedFloat = CreateObject("roFloat"):boxedFloat.SetFloat(1.0)
for each count in [invalid,"1",true,false,1.0,1.0#,boxedFloat,[],{},-1,-1&]
    PrefetchTest_Setup(1)
    LoadStreams(m.params)
    completed = m.launched[0]
    completed.result = {streams:[uhd],readyStreams:[uhd],uhdCount:count,error:""}
    PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(completed))
    onSourcePrefetchChanged()
    Harness_Equal(m.providers[0].uhdCount,0,"malformed, floating-point or negative counts cannot become UHD evidence")
    Harness_Equal(SourceLoadStatus().uhdLabelCandidates,0,"rejected count stays zero in safe diagnostics")
end for
hugeCount = CreateObject("roLongInteger"):hugeCount.SetLongInt(4294967296&)
for each count in [2,4294967296&,hugeCount]
    PrefetchTest_Setup(1)
    LoadStreams(m.params)
    completed = m.launched[0]
    completed.result = {streams:[uhd],readyStreams:[uhd],uhdCount:count,error:""}
    PrefetchTest_onPrefetchLoaded(PrefetchTest_Event(completed))
    onSourcePrefetchChanged()
    Harness_Equal(m.providers[0].uhdCount,1,"oversized integer counts clamp before 32-bit conversion to the actual candidate budget")
end for
PrefetchTest_Setup(1)
LoadStreams(m.params)
ApplyProviderSources(0,{streams:[uhd],readyStreams:invalid,uhdCount:boxedCount,error:""})
Harness_Equal(m.providers[0].uhdCount,0,"no ready array means no counted UHD candidates")
Harness_Finish()
