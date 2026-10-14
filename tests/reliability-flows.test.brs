function ReliabilityClock() as object
    return {elapsed:0,Mark:sub()
        m.elapsed=0
    end sub,TotalMilliseconds:function() as integer
        return m.elapsed
    end function}
end function
function ReliabilityNoMemory() as dynamic
    return invalid
end function
function SourceMemory_Load(registry as dynamic, now as dynamic) as dynamic
    return invalid
end function
function ReliabilityEvent(task as object) as object
    return {task:task,GetRoSGNode:function() as object
        return m.task
    end function}
end function
sub AsyncTask_Reap(task as object, parent as object, stopped as boolean)
    task.reaped=true:task.stopped=stopped
end sub
function AsyncTask_Launch(parent as object, kind as string, callback as string, fields as object, id as string) as object
    fields.id=id:fields.kind=kind:fields.result=invalid
    m.launched.Push(fields)
    return fields
end function
sub ReportStoreFault(reason as string, active as boolean)
    if active then m.faults[reason]=true else m.faults.Delete(reason)
end sub
sub ClearAddonSyncFaults()
end sub
sub AddAddonSyncFault(reason as string)
    ReportStoreFault(reason,true)
end sub
sub PumpPendingLibrarySync()
end sub
sub HandleRevokedSession()
    m.revoked=true
end sub
sub ScheduleWatchStatePush()
    m.scheduled=true
end sub
sub StartAddonSync()
end sub
sub StartLibrarySync()
    m.pullRequested=true
end sub
sub FinishImport()
    m.importFinished=true
end sub
sub PumpImport()
    m.importPumped=true
end sub
function MetadataOrigin_Key(stores as dynamic, address as dynamic) as string
    return ""
end function
sub CancelResolve()
end sub
sub ResetVideoNode()
    m.video.control="stop"
end sub
sub StartResolve(stream as object, address as dynamic, season as integer, episode as integer)
    m.resolves=m.resolves+1
end sub
function ResolveOrdinal(value as dynamic) as integer
    return 0
end function
sub ArmSourceStartupLimit(force as boolean)
end sub
sub CancelAutomaticGrace()
    m.graceCancelled=true
end sub

function ReliabilityTestBudget(sectionName as string, key as string, value as string) as boolean
    return true
end function
function ReliabilityHost(scope as string) as object
    native = MockRegistry()
    return {native:native,library:LibraryStore(RegistryIO(native,"library",ReliabilityTestBudget),"stremio",scope),authKey:"fixture-A",session:"stremio",addonCalls:0,watch:invalid,callFunc:function(name as string,a=invalid as dynamic,b=invalid as dynamic,c=invalid as dynamic,d=invalid as dynamic,e=invalid as dynamic,f=invalid as dynamic,g=invalid as dynamic,h=invalid as dynamic,i=invalid as dynamic,j="" as dynamic,k="" as dynamic) as dynamic
        if name="AuthGetSession" then return m.session
        if name="AuthGetAuthKey" then return m.authKey
        if name="LibraryBuildLibraryChangeItem" then return m.library.BuildLibraryChangeItem(a,b,c,d,e)
        if name="LibraryBuildWatchStateItem" then return m.library.BuildWatchStateItem(a)
        if name="LibraryBuildWatchedStateItem" then return m.library.BuildWatchedStateItem(a)
        if name="LibrarySetAccountOutbox" then return m.library.SetAccountOutbox(a)
        if name="LibraryGetAccountOutbox" then return m.library.GetAccountOutbox()
        if name="LibrarySyncFromStremio" then m.library.SyncFromStremio(a)
        if name="LibraryAddSaved" then return m.library.AddSaved(a,b,c,d)
        if name="LibraryRemoveSaved" then m.library.RemoveSaved(a)
        if name="LibraryIsChannelType" then return m.library.IsChannelType(a)
        if name="LibrarySetPosition" then return m.library.SetPosition(a,b,c,d,e,f,g,h,i,j,k)
        if name="LibraryMarkWatchedIfFinished" then return false
        if name="WatchRecord" then m.watch=a
        if name="WatchClear" then m.watch=invalid
        if name="AddonsReconcileAccount" then m.addonCalls=m.addonCalls+1:return {ok:true}
        return invalid
    end function}
end function
sub ReliabilitySetup()
    m.top={}:m.faults={}:m.launched=[]:m.watchStatePump={control:"stop"}
    m.storeHost=ReliabilityHost(String(64,"a"))
    m.stack={top:function() as dynamic
        return invalid
    end function}
    m.homeScreen=invalid:m.libraryScreen=invalid:m.playerScreen=invalid
    InitAccountWork()
end sub
function ReliabilityChange(id as string, added=true as boolean) as object
    return {accountGeneration:AccountGeneration(),metaId:id,metaType:"movie",name:id,poster:"",added:added}
end function

Harness_Suite("Distinct queued edits, acknowledgements and restart outbox")
ReliabilitySetup()
QueueAccountEdit("libraryChange",ReliabilityChange("A"))
PumpLibraryWrites()
Harness_Equal(m.launched.Count(),0,"write waits for initial account baseline")
pull={id:"pull-A",accountGeneration:0,result:{ok:true,items:[],revokedSession:false}}
m.librarySyncTask=pull:onLibrarySyncResult(ReliabilityEvent(pull))
PumpLibraryWrites():held=m.libraryWriteTask
Harness_Equal(held.item._id,"A","first actual full-item write launched")
QueueAccountEdit("libraryChange",ReliabilityChange("B"))
QueueAccountEdit("libraryChange",ReliabilityChange("C"))
PumpLibraryWrites()
Harness_Equal(m.launched.Count(),1,"one account write at a time")
Harness_Equal(m.storeHost.library.GetAccountOutbox().Count(),3,"in-flight A and distinct B/C retained durably")
held.result={ok:true}:onLibraryWriteResult(ReliabilityEvent(held))
Harness_Equal(m.libraryWriteTask.item._id,"B","B was not overwritten by C")
failed=m.libraryWriteTask:failed.result={ok:false}:onLibraryWriteResult(ReliabilityEvent(failed))
Harness_Equal(m.libraryWriteTask.item._id,"C","unrelated C can proceed after B fails")
Harness_Ok(m.accountWrites[0].blocked,"failed B retained with visible retry state")
last=m.libraryWriteTask:last.result={ok:true}:onLibraryWriteResult(ReliabilityEvent(last))
Harness_Equal(m.accountWrites.Count(),1,"failure not silently discarded")
Harness_Equal(m.storeHost.library.GetAccountOutbox()[0].metaId,"B","failed write survives in account-owned storage")
before=m.storeHost.library.GetAccountOutbox()
InitAccountWork():RestoreAccountWrites()
Harness_Equal(m.accountWrites.Count(),1,"restart restores unsynced edit")
Harness_Ok(m.accountWrites[0].blocked,"uncertain completion is not replayed silently on restart")
m.accountLibraryReady=true:RetryAccountWrites():PumpLibraryWrites()
Harness_Equal(m.libraryWriteTask,invalid,"explicit retry waits for a fresh server baseline")
m.librarySyncTask={id:"retryPull",accountGeneration:0,result:{ok:true,items:[],revokedSession:false}}
onLibrarySyncResult(ReliabilityEvent(m.librarySyncTask)):PumpLibraryWrites()
Harness_Equal(m.libraryWriteTask.item._id,"B","explicit retry reaches retained title")
retried=m.libraryWriteTask:retried.result={ok:true}:onLibraryWriteResult(ReliabilityEvent(retried))
Harness_Equal(m.storeHost.library.GetAccountOutbox().Count(),0,"server acknowledgement removes durable pending edit")
QueueAccountEdit("libraryChange",ReliabilityChange("B",true))
QueueAccountEdit("libraryChange",ReliabilityChange("B",false))
QueueAccountEdit("libraryChange",ReliabilityChange("C",true))
Harness_Equal(m.accountWrites.Count(),2,"coalescing is per item and kind")
Harness_Equal(m.accountWrites[0].payload.added,false,"latest same-item membership wins")

Harness_Suite("Coalesced watched edits retain their desired state across restart")
ReliabilitySetup()
ids=["one","two"]
packet={accountGeneration:0,metaId:"show",metaType:"series",name:"Show",poster:"",videoId:"one",orderedVideoIds:ids}
m.storeHost.library.MarkEpisodeWatched("show","one")
QueueAccountEdit("watched",packet)
packet2={accountGeneration:0,metaId:"show",metaType:"series",name:"Show",poster:"",videoId:"two",orderedVideoIds:ids}
m.storeHost.library.MarkEpisodeWatched("show","two")
QueueAccountEdit("watched",packet2):PersistAccountWrites()
Harness_Equal(m.accountWrites.Count(),1,"same-series watched job coalesces without losing local marks")
reboot=MockRegistry()
for each key in m.storeHost.native.durable
    reboot.values[key]=m.storeHost.native.durable[key]
end for
m.storeHost.native=reboot:m.storeHost.library=LibraryStore(RegistryIO(reboot,"library",ReliabilityTestBudget),"stremio",String(64,"a"))
InitAccountWork():RestoreAccountWrites()
set=m.storeHost.library.WatchedSetFor("show",ids)
Harness_Ok(set.one=true and set.two=true,"both desired watched marks restored with the outbox")
RetryAccountWrites()
m.librarySyncTask={id:"watchPull",accountGeneration:0,result:{ok:true,items:[],revokedSession:false}}
onLibrarySyncResult(ReliabilityEvent(m.librarySyncTask)):PumpLibraryWrites()
decoded=m.storeHost.library.codec.WatchedDecode(m.libraryWriteTask.item.state.watched,ids)
Harness_Ok(decoded.one=true and decoded.two=true,"fresh retry encodes both marks into the actual outgoing item")
m.storeHost.library.MarkEpisodeUnwatched("show","one")
QueueAccountEdit("watched",packet2):PersistAccountWrites()
reopened=LibraryStore(m.storeHost.library.registry,"stremio",String(64,"a"))
set=reopened.WatchedSetFor("show",ids)
Harness_Ok(set.one=invalid and set.two=true,"unsynced unwatch override is durable too")

Harness_Suite("Pending watch checkpoint survives the fresh server pull")
ReliabilitySetup()
packet={accountGeneration:0,videoId:"resume",metaId:"resume",metaType:"movie",season:0,episode:0,name:"Resume",poster:"",position:120,duration:600}
QueueAccountEdit("watchState",packet):PersistAccountWrites()
m.librarySyncTask={id:"resumePull",accountGeneration:0,result:{ok:true,items:[],revokedSession:false}}
onLibrarySyncResult(ReliabilityEvent(m.librarySyncTask))
Harness_Equal(m.storeHost.library.Position("resume"),120,"pending watch packet reapplies local progress after remote baseline")
PumpLibraryWrites()
Harness_Equal(m.libraryWriteTask.item.state.timeOffset,120000,"fresh cloud write carries the same checkpoint in milliseconds")
Harness_Equal(m.libraryWriteTask.item.state.duration,600000,"wire duration uses milliseconds too")
Harness_Equal(m.accountWrites.Count(),0,"building wire packet does not duplicate the pending item")
Harness_Equal(m.inFlightLibraryWrite.payload.position,120,"wire conversion never mutates the seconds-valued outbox")
wireItem=m.libraryWriteTask.item
m.storeHost.library.SyncFromStremio([wireItem])
Harness_Equal(m.storeHost.library.Position("resume"),120,"API write/pull round trip returns native seconds")
m.storeHost.library.RemoveSaved("resume")
m.storeHost.library.AddSaved("resume","movie","Resume","")
Harness_Equal(m.storeHost.library.Position("resume"),120,"re-adding cached account title converts its checkpoint too")

Harness_Suite("Held A workers and publishers cannot reach account B")
ReliabilitySetup():m.accountLibraryReady=true
QueueAccountEdit("libraryChange",ReliabilityChange("A")):PumpLibraryWrites():oldPut=m.libraryWriteTask
oldPull={id:"oldPull",accountGeneration:0,result:{ok:true,items:[{_id:"private-A"}],revokedSession:false}}
oldAddons={id:"oldAddons",accountGeneration:0,result:{ok:true,descriptors:[]}}
m.librarySyncTask=oldPull:m.addonSyncTask=oldAddons:m.storeHost.watch={metaId:"A"}
oldEdit=ReliabilityChange("A")
ResetAccountWork()
m.storeHost.authKey="fixture-B":m.storeHost.library.SwitchSession("stremio",String(64,"b"))
m.librarySyncTask={id:"newPull",accountGeneration:1,result:{ok:true,items:[],revokedSession:false}}
m.addonSyncTask={id:"newAddons",accountGeneration:1,result:{ok:true,descriptors:[]}}
onLibrarySyncResult(ReliabilityEvent(oldPull)):onAddonSyncResult(ReliabilityEvent(oldAddons))
oldPut.result={ok:true}:onLibraryWriteResult(ReliabilityEvent(oldPut))
Harness_Equal(m.librarySyncTask.id,"newPull","old pull cannot consume B's current task")
Harness_Equal(m.addonSyncTask.id,"newAddons","old addon snapshot cannot consume B's task")
Harness_Equal(m.storeHost.addonCalls,0,"A snapshot never reconciles into B")
Harness_Equal(m.storeHost.watch,invalid,"account switch clears shared watch publisher")
Harness_Ok(not QueueAccountEdit("libraryChange",oldEdit),"late A publisher rejected")
Harness_Equal(m.accountWrites.Count(),0,"A pending edits quarantined on account change")
m.import={task:{id:"newImport",accountGeneration:1,result:{ok:true}},added:0}
oldImport={id:"oldImport",accountGeneration:0,result:{ok:true,record:{id:"privateA"}}}
onImportTaskResult(ReliabilityEvent(oldImport))
Harness_Equal(m.import.task.id,"newImport","old manifest import cannot consume B's task")
Harness_Equal(m.import.added,0,"old manifest import cannot register into B")
m.accountLibraryReady=true:QueueAccountEdit("libraryChange",ReliabilityChange("B")):PumpLibraryWrites()
Harness_Equal(m.libraryWriteTask.authKey,"fixture-B","only B edit uses B authentication")
Harness_Equal(m.libraryWriteTask.item._id,"B","A title never sent under B's credentials")
Harness_Equal(oldPut.authKey,"fixture-A","already-running A worker retains its original identity")

Harness_Suite("Periodic checkpoints acknowledge durable progress and preserve guards")
ReliabilitySetup():m.stores={library:m.storeHost,watch:m.storeHost}
m.video={position:60,duration:600,state:"playing",HasField:function(name as string) as boolean
    return m.DoesExist(name)
end function}
m.playParams={metaId:"movie",metaType:"movie",videoId:"movie",name:"Movie",position:0}
m.playbackActive=true:m.sourceAccepted=true:m.hasPlayed=true:m.retryPending=false:m.saved=false:m.naturalEnd=false
m.lastPlaybackPosition=0:m.lastPlaybackDuration=0:m.lastDurablePosition=invalid:m.lastDurableDuration=invalid
onLocalCheckpoint()
Harness_Equal(m.storeHost.library.Position("movie"),60,"uninterrupted playback checkpoints locally")
Harness_Equal(m.lastDurablePosition,60,"durable acknowledgement recorded")
snapshot=m.storeHost.native.durable[m.storeHost.library.RegistryKey()]
onLocalCheckpoint()
Harness_Equal(m.storeHost.native.durable[m.storeHost.library.RegistryKey()],snapshot,"unchanged playback does not rewrite checkpoint")
m.video.position=90:m.storeHost.native.failFlushes=true:onLocalCheckpoint()
Harness_Equal(m.lastDurablePosition,60,"failed flush cannot advance acknowledged checkpoint")
m.storeHost.native.failFlushes=false:onLocalCheckpoint()
Harness_Equal(m.lastDurablePosition,90,"next checkpoint retries dirty progress")
reboot=MockRegistry():reboot.values[m.storeHost.library.RegistryKey()]=m.storeHost.native.durable[m.storeHost.library.RegistryKey()]
Harness_Equal(LibraryStore(reboot,"stremio",String(64,"a")).Position("movie"),90,"process restart restores last durable checkpoint")
m.video.position=120:m.sourceAccepted=false:onLocalCheckpoint()
Harness_Equal(m.storeHost.library.Position("movie"),90,"unaccepted source cannot overwrite checkpoint")
m.sourceAccepted=true:m.playParams.diagnostic=true:onLocalCheckpoint()
Harness_Equal(m.storeHost.library.Position("movie"),90,"diagnostic cannot write progress")
m.playParams.diagnostic=false:m.playParams.metaType="channel":onLocalCheckpoint()
Harness_Equal(m.storeHost.library.Position("movie"),90,"live channels excluded")

m.playParams.metaType="movie":m.video.position=0:onLocalCheckpoint()
Harness_Equal(m.lastDurablePosition,0,"intentional active seek to zero is checkpointed")
m.video.position=90:onLocalCheckpoint()

Harness_Suite("Old screen exit after a switch cannot save into the new local store")
m.video.position=150:m.playParams.metaType="movie":m.saved=false
m.top={scene:{accountGeneration:1},GetScene:function() as object
    return m.scene
end function}
m.top.scene.HasField=function(name as string) as boolean
    return m.DoesExist(name)
end function
m.accountGeneration=0
SavePosition():PublishWatchState()
Harness_Equal(m.storeHost.library.Position("movie"),90,"A's deferred exit cannot overwrite B/guest local state")
Harness_Equal(m.lastDurablePosition,90,"old epoch cannot claim a durable checkpoint")

Harness_Suite("Bounded fields, candidate totals and subtitle floods")
raw=[]
for i=1 to 2000
    raw.Push({url:"https://example.invalid/"+i.ToStr(),title:String(5000,"x"),unknown:{large:String(5000,"x")}})
end for
limited=CinemaBudgetStreams(raw,128,65536)
Harness_Ok(limited.Count()<=128,"provider candidate count bounded")
Harness_Ok(Len(FormatJson(limited))<=66048,"provider retained bytes bounded including array overhead")
Harness_Equal(Len(limited[0].title),512,"giant label bounded before rendering")
Harness_Equal(limited[0].unknown,invalid,"unneeded nested fields discarded")
Harness_Equal(CinemaBudgetStreams([{url:"https://example.invalid/"+String(9000,"x")}]).Count(),0,"oversized signed URL rejected rather than corrupted")
Harness_Ok(CinemaProviderCountBudget(64)*64<=1024,"active-title count shared across all providers")
Harness_Ok(CinemaProviderByteBudget(64)*64<=1048576,"active-title byte budget shared across all providers")
tracks=[]
for i=1 to 2000
    tracks.Push({url:"https://example.invalid/sub"+i.ToStr(),lang:"en",langName:String(4000,"x")})
end for
subs=SubtitlesStore(ScriptedTransport([{ok:true,status:200,json:{subtitles:tracks},error:""}])).Subtitles("https://example.invalid","movie","A")
Harness_Equal(subs.subtitles.Count(),64,"thousands of subtitle tracks reduced in worker")
Harness_Equal(Len(subs.subtitles[0].langName),128,"subtitle labels bounded")

Harness_Suite("Early pool recovery resumes discovery without changing accepted playback")
m.params={videoId:"A",position:0}:m.pendingCount=1:m.selectionRevision=1:m.autoPlaySent=true:m.reloadNeeded=false
request={videoId:"A",position:123,excludedUrls:["https://example.invalid/fails"],round:1,manual:false}
Harness_Ok(PrepareSourceRecovery(request),"failed early pool can prepare queued discovery")
Harness_Ok(not m.reloadNeeded,"queued provider B is resumed without re-fetching A first")
Harness_Equal(m.params.position,123,"recovery retains checkpoint")
Harness_Ok(m.autoPlayEnabled and not m.autoPlaySent,"automatic selection can run for newly completed providers")
m.top={providerGroups:[[{url:"https://example.invalid/fails",title:"2160p"}],[{url:"https://example.invalid/works",title:"2160p"}]],excludedUrls:m.recoveryExcluded,audioMode:"surround",fourKOnly:true,videoId:"A"}
ReliabilityChoose()
Harness_Equal(m.top.result.streams.Count(),1,"already failed exact delivery identities excluded by selection worker")
Harness_Equal(m.top.result.streams[0].url,"https://example.invalid/works","slower provider B can reach the next playback handoff")
Harness_Suite("Deferred failure request follows the real Scene recovery route")
m.top={}:m.accountGeneration=0:m.playParams={videoId:"A",position:123,recoveryRound:0,excludedUrls:[]}
m.sourceQueue=[{url:"https://example.invalid/fails"}]:m.sourceIndex=0
m.playbackActive=true:m.sourceAccepted=false:m.retryTimer={control:"stop"}:m.status={text:""}
QueueSourceDiscovery(false):m.retryGuard.clock.elapsed=500
onAutoSourceRetry()
Harness_Ok(Type(m.top.sourceRecoveryRequest)="roAssociativeArray","exhaustion crosses a timer before emitting Scene request")
Harness_Equal(m.top.sourceRecoveryRequest.excludedUrls.Count(),1,"attempted delivery retained only in private memory")
m.playerScreen={sourceRecoveryRequest:m.top.sourceRecoveryRequest,callFunc:function(name as string,id as string) as dynamic
    return CanRecoverSources(id)
end function}
m.streamsScreen={callFunc:function(name as string,payload as object) as dynamic
    return PrepareSourceRecovery(payload)
end function}
m.stack={shown:"playerScreen",popCalls:0,top:function() as object
    return {id:m.shown}
end function,pop:function() as boolean
    m.popCalls=m.popCalls+1:m.shown="streamsScreen"
    return true
end function}
m.pendingCount=1:m.params={videoId:"A",position:0}
onSourceRecoveryRequest()
Harness_Equal(m.stack.popCalls,1,"Scene resumes source discovery without a manual Back press")
Harness_Equal(m.params.position,123,"actual route retains checkpoint")
onSourceRecoveryRequest()
Harness_Equal(m.stack.popCalls,1,"duplicate recovery event cannot pop a source screen")
m.stack.shown="playerScreen":m.discoveryPending=false
onSourceRecoveryRequest()
Harness_Equal(m.stack.popCalls,1,"late recovery cannot disturb successful playback")

request.round=3:Harness_Ok(not PrepareSourceRecovery(request),"automatic recovery has a hard round ceiling")
m.playParams={videoId:"A",recoveryRound:2}:m.playbackActive=true:m.discoveryPending=false:m.retryTimer={control:"stop"}:m.status={text:""}
Harness_Ok(not QueueSourceDiscovery(false),"exhausted recovery budget cannot loop")
Harness_Ok(QueueSourceDiscovery(true),"explicit retry requests fresh discovery")
Harness_Ok(CanRecoverSources("A"),"current failed playback owns deferred recovery")
m.discoveryPending=false
Harness_Ok(not CanRecoverSources("A"),"late request cannot change successful playback")

print "Assertions passed: ";m.passed;" failed: ";m.failed
if m.failed=0 then print "RESULT: PASS" else print "RESULT: FAIL":stop
