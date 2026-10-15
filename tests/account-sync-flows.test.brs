' Execute the production task, API store, StoreHost forwarders and scene callbacks.
function SyncHttp() as object
    return m.http
end function
function SyncClock() as object
    return {elapsed:0,Mark:sub()
        m.elapsed=0
    end sub,TotalMilliseconds:function() as integer
        m.elapsed=m.elapsed+3000
        return m.elapsed
    end function}
end function
sub SyncSleep()
end sub
function SyncScope(identity as string) as string
    if identity="account:A" then return String(64,"a")
    if identity="account:B" then return String(64,"b")
    return String(64,"c")
end function
function SyncBudget(sectionName as string,key as string,value as string) as boolean
    return true
end function
function SyncEvent(task as object) as object
    return {task:task,GetRoSGNode:function() as object
        return m.task
    end function}
end function
function AsyncTask_Launch(parent as object,kind as string,callback as string,fields as object,id as string,finished="" as string) as object
    fields.id=id:fields.kind=kind:fields.result=invalid:fields.finished=false
    m.launched.Push(fields)
    return fields
end function
sub AsyncTask_Reap(task as object,parent as object,stopped as boolean)
    task.reaped=true
end sub
sub ReportStoreFault(reason as string,active as boolean)
    if active then m.faults[reason]=true else m.faults.Delete(reason)
end sub
sub PumpPendingLibrarySync()
    m.libraryPumps=m.libraryPumps+1
end sub
sub StartLibrarySync()
    m.libraryRequested=true
end sub
sub CleanupStremioPairTask()
    m.linkStremioTask=invalid
end sub
sub RefreshLinkCode()
end sub
sub ScheduleWatchStatePush()
end sub
sub HandleRevokedSession()
    m.revoked=true
end sub
sub RestoreActiveScreenFocus()
end sub
sub BeginImport(urls as object,settings as dynamic)
    m.acceptedImports=m.acceptedImports+1
    m.importedUrls=urls
end sub
sub FlushPendingQuery()
    m.flushed=true
end sub
sub ReadySources()
    m.ready=true
end sub
sub ShowEmpty()
    m.empty=true
end sub
function NextSearchWorkerId(prefix as string) as string
    return prefix
end function
function NextDiscoverWorkerId(prefix as string) as string
    return prefix
end function
function DiscoverText(value as dynamic) as string
    if GetInterface(value,"ifString")<>invalid then return value
    return ""
end function
function SyncDialog() as object
    return {ObserveField:sub(field as string,callback as string)
    end sub}
end function
function SyncContent() as object
    return {children:[],CreateChild:function(kind as string) as object
        node=SyncContent():m.children.Push(node):return node
    end function}
end function
function SyncHost() as object
    auth=AuthStore(RegistryIO(MockRegistry(),"auth",SyncBudget),SyncScope)
    addons=AddonsStore(ScriptedTransport([]),RegistryIO(MockRegistry(),"addons",SyncBudget),"guest")
    library=LibraryStore(RegistryIO(MockRegistry(),"library",SyncBudget))
    settings=SettingsStore(RegistryIO(MockRegistry(),"settings",SyncBudget))
    return {stores:{auth:auth,addons:addons,library:library,settings:settings},sessionAware:[addons,library],Reconcile:AddonsReconcileAccount,All:AddonsGetAll,Login:AuthLoginStremio,Logout:AuthLogout,Switch:HostSwitchSession,Effective:HostEffectiveSessionType,Retry:RetryPersistence,callFunc:function(name as string,a=invalid as dynamic,b=invalid as dynamic) as dynamic
        if name="AuthGetSession" then return m.stores.auth.GetSession()
        if name="AuthGetAuthKey" then return m.stores.auth.GetAuthKey()
        if name="AuthLoginStremio" then return m.Login(a,b)
        if name="AuthLogout" then m.Logout():return invalid
        if name="EffectiveSessionType" then return m.Effective()
        if name="SwitchSession" then m.Switch(a):return true
        if name="AddonsReconcileAccount" then return m.Reconcile(a)
        if name="AddonsGetAll" then return m.All()
        if name="LibraryGetAccountOutbox" then return m.stores.library.GetAccountOutbox()
        if name="LibrarySetAccountOutbox" then return m.stores.library.SetAccountOutbox(a)
        if name="RetryPersistence" then return m.Retry()
        return invalid
    end function}
end function
function SyncScreen() as object
    return {calls:[],callFunc:function(name as string) as dynamic
        m.calls.Push(name)
        return true
    end function}
end function
function SyncDescriptor(id as string,resource as string) as object
    catalogs=[]
    if resource="meta" then catalogs=[{type:"movie",id:"top",extra:[{name:"search"}]}]
    return {transportUrl:"https://"+id+".example/manifest.json",manifest:{id:id,name:id,version:"1",types:["movie","series"],resources:[resource],catalogs:catalogs}}
end function
sub SyncSetup()
    m.top={dialog:invalid,FindNode:function(id as string) as dynamic
        return invalid
    end function}
    m.stack={active:{id:"homeScreen"},top:function() as object
        return m.active
    end function,count:function() as integer
        return 1
    end function,push:sub(id as string)
        m.active={id:id}
    end sub,pop:sub()
        m.active={id:"homeScreen"}
    end sub}
    m.faults={}:m.launched=[]:m.libraryPumps=0:m.loginFromSettings=false:m.acceptedImports=0
    m.storeHost=SyncHost():m.homeScreen=SyncScreen():m.searchScreen=SyncScreen():m.discoverScreen=SyncScreen():m.playerScreen=SyncScreen():m.addonsScreen=SyncScreen()
    InitAccountWork()
end sub
sub SyncLogin(identity as string)
    m.linkStremioTask={id:"pair-"+identity}
    m.linkStremioScreen={pushRequest:{action:"completeLogin",taskIdentity:m.linkStremioTask.id,authKey:"fixture-"+identity,user:{_id:identity}}}
    onLinkCodeAction()
end sub
sub RunSync(task as object,descriptors as dynamic,ok=true as boolean)
    worker={top:task,http:ScriptedTransport([{ok:ok,status:200,json:{result:{addons:descriptors}}}]),Run:SyncWorker}
    worker.Run()
end sub
Harness_Suite("Fresh production login imports catalog, stream and subtitle add-ons automatically")
SyncSetup():SyncLogin("A")
Harness_Equal(m.launched.Count(),1,"login launches account collection worker without manual installation")
Harness_Equal(m.addonSyncStatus.state,"loading","sync progress visible from start")
held=m.addonSyncTask
onAddonSyncResult(SyncEvent(held)):onAddonSyncFinished(SyncEvent(held))
Harness_Equal(m.addonSyncTask.id,held.id,"empty result and false finished notifications do not consume slow worker")
collection=[SyncDescriptor("catalog","meta"),SyncDescriptor("streams","stream"),SyncDescriptor("captions","subtitles")]
RunSync(held,collection)
onAddonSyncFinished(SyncEvent(held))
Harness_Equal(m.storeHost.stores.addons.GetAll().Count(),3,"worker/API/scene/StoreHost import entire valid collection")
Harness_Equal(m.addonSyncStatus.state,"complete","complete only after collection reconciliation")
Harness_Equal(m.addonSyncStatus.catalogProviders,1,"catalogs are discovered even without catalog in resource list")
Harness_Equal(m.addonSyncStatus.streamProviders,1,"stream provider imported")
Harness_Equal(m.addonSyncStatus.subtitleProviders,1,"subtitle provider imported")
Harness_Ok(held.reaped,"finished-before-result dispatch consumes available result exactly once")
pumps=m.libraryPumps:onAddonSyncResult(SyncEvent(held)):onAddonSyncFinished(SyncEvent(held))
Harness_Equal(m.libraryPumps,pumps,"duplicate completion events are harmless")
Harness_Equal(m.searchScreen.calls[0],"EnsureCurrentSources","search is invalidated after account import")
Harness_Equal(m.discoverScreen.calls[0],"EnsureCurrentSources","Discover is invalidated after account import")

Harness_Suite("Imported production descriptors reach actual Search and Discover source controllers")
m.stores={addons:m.storeHost}:m.sources=[]:m.sourcesSignature="":m.sourcesTask=invalid:m.status={text:""}
SearchEnsureSources()
Harness_Equal(m.sources.Count(),1,"Search accepts declared catalogs without catalog resource")
Harness_Ok(m.flushed=true,"pending query flushes after sources become available")
m.sources=[]:m.sourcesSignature="":DiscoverEnsureSources()
Harness_Equal(m.sources.Count(),3,"Discover receives real imported provider descriptors")
Harness_Ok(m.ready=true,"Discover source-ready callback runs")

Harness_Suite("Manifest changes and order invalidate all three screen signatures")
for each fn in [Signature0,Signature1,Signature2]
    m.Signature=fn
    before=m.Signature()
    m.storeHost.stores.addons.installed.catalog.catalogs[0].id="changed"
    Harness_Ok(before<>m.Signature(),"same URL with changed catalog invalidates signature")
    before=m.Signature():m.storeHost.stores.addons.order=[m.storeHost.stores.addons.order[1],m.storeHost.stores.addons.order[2],m.storeHost.stores.addons.order[0]]
    Harness_Ok(before<>m.Signature(),"remote order affects catalog signature")
    m.storeHost.stores.addons.installed.catalog.catalogs[0].id="top"
end for

Harness_Suite("Partial, malformed and failed snapshots remain distinct from an empty account")
StartAddonSync():partial=m.addonSyncTask
RunSync(partial,[collection[0],42,collection[1]])
onAddonSyncResult(SyncEvent(partial))
Harness_Equal(m.addonSyncStatus.state,"partial","malformed neighbour does not fake complete sync")
Harness_Equal(m.addonSyncStatus.invalid,1,"invalid count reported")
Harness_Ok(m.storeHost.stores.addons.Get("captions")<>invalid,"partial snapshot cannot remove previous providers")
StartAddonSync():failed=m.addonSyncTask:RunSync(failed,[],false):onAddonSyncResult(SyncEvent(failed))
Harness_Equal(m.addonSyncStatus.state,"failed","transport failure is not empty success")
Harness_Equal(m.storeHost.stores.addons.GetAll().Count(),3,"failure retains usable snapshot")
StartAddonSync():empty=m.addonSyncTask:RunSync(empty,[]):onAddonSyncResult(SyncEvent(empty))
Harness_Equal(m.addonSyncStatus.state,"empty","confirmed empty account is explicit")
Harness_Equal(m.storeHost.stores.addons.GetAll().Count(),0,"no unsolicited catalogs or providers seeded for empty account")
StartAddonSync():bad=m.addonSyncTask:RunSync(bad,42):onAddonSyncResult(SyncEvent(bad))
Harness_Equal(m.addonSyncStatus.state,"failed","malformed API envelope fails without throwing")

StartAddonSync():rejected=m.addonSyncTask
RunSync(rejected,[{transportUrl:"stremio://unsupported",manifest:{}},42]):onAddonSyncResult(SyncEvent(rejected))
Harness_Equal(m.addonSyncStatus.state,"failed","entirely rejected collection is not empty success")
Harness_Ok(m.addonSyncStatus.text.InStr("1 unsupported, 1 invalid")>=0,"all-rejected outcome exposes actionable exact rejection counts")
Harness_Ok(m.addonSyncStatus.text.InStr("stremio://")<0,"all-rejected summary contains no private transport URL")

Harness_Suite("Account switch rejects a delayed old task through actual login and store boundaries")
StartAddonSync():old=m.addonSyncTask
RunSync(old,collection):SyncLogin("B"):current=m.addonSyncTask
onAddonSyncFinished(SyncEvent(old))
Harness_Equal(m.addonSyncTask.id,current.id,"A completion cannot consume B worker")
Harness_Equal(m.storeHost.stores.addons.GetAll().Count(),0,"A private providers cannot appear for B")
RunSync(current,[SyncDescriptor("Bsource","stream")]):onAddonSyncResult(SyncEvent(current))
Harness_Equal(m.storeHost.stores.addons.GetAll()[0].id,"Bsource","B receives only B collection")
Harness_Equal(m.addonSyncStatus.catalogProviders,0,"stream-only account is distinguished from failed import")


Harness_Suite("Stream-only account gets explicit local catalog onboarding, not a hidden remote mutation")
m.stores={addons:m.storeHost,auth:m.storeHost}:m.rows=[]:m.status={text:""}:m.sub={text:""}:m.list={}:m.companionCaption={}
m.top.scene={status:m.addonSyncStatus,callFunc:function(name as string,url=invalid as dynamic) as dynamic
    if name="ReadAddonSyncStatus" then return m.status
    if name="ImportFromSetup" then return ImportFromSetup(url)
    return invalid
end function}
m.top.getScene=function() as object
    return m.scene
end function
savedStatus=m.top.scene.status
m.top.scene.status={state:"failed",complete:false,text:"Account sync failed"}
BuildRows()
for each row in m.rows
    Harness_Ok(row.action<>"catalog","failed sync cannot be disguised by local catalog onboarding")
end for
m.top.scene.status=savedStatus
BuildRows()
Harness_Equal(m.storeHost.stores.addons.GetAll().Count(),1,"rendering onboarding cannot silently add a provider")
found=-1
for index=0 to m.rows.Count()-1
    if m.rows[index].action="catalog" then found=index
end for
Harness_Ok(found>=0,"no-catalog account receives local-only catalog action")
if found>=0
    m.stack.active={id:"addonsScreen"}:m.list.rowItemSelected=[found,0]
    onRowSelected()
    Harness_Equal(m.importedUrls[0],"https://v3-cinemeta.strem.io/manifest.json","remote choice queues only requested local Cinemeta manifest")
    Harness_Equal(m.storeHost.stores.addons.GetAll().Count(),1,"onboarding does not call remote account collection setter")
end if
m.acceptedImports=0

Harness_Suite("Real link-code task verifies identity before it can report login success")
for each ok in [true,false]
    worker={top:{control:"RUN"},Run:LoginWorker,http:ScriptedTransport([
        {method:"GET",url:"https://link.stremio.com/api/v2/create?type=Create",ok:true,status:200,json:{result:{code:"FIXTURE",link:"https://link.stremio.com/FIXTURE"}}},
        {method:"GET",url:"https://link.stremio.com/api/v2/read?type=Read&code=FIXTURE",ok:true,status:200,json:{result:{authKey:"fixture-A"}}},
        {method:"POST",url:"https://api.strem.io/api/getUser",ok:ok,status:200,json:{result:{_id:"A"}}}
    ])}
    worker.Run()
    Harness_Equal(worker.top.result.ok,ok,"failed user lookup cannot become a successful login")
    if not ok then Harness_Equal(worker.top.result.authKey,"","unverified key not published to scene")
end for

Harness_Suite("Sync fault cleanup cannot restore an older durable edit over current intent")
oldPayload={accountGeneration:AccountGeneration(),metaId:"B-title",metaType:"movie",name:"B title",added:false}
m.storeHost.stores.library.SetAccountOutbox([{kind:"libraryChange",metaId:"B-title",payload:oldPayload}])
newPayload={accountGeneration:AccountGeneration(),metaId:"B-title",metaType:"movie",name:"B title",added:true}
QueueAccountEdit("libraryChange",newPayload):ClearAddonSyncFaults()
Harness_Equal(m.accountWrites[0].payload.added,true,"clearing sync status cannot overwrite newer in-memory intent")
m.accountWrites=[]:m.storeHost.stores.library.SetAccountOutbox([])

Harness_Suite("Relaunch restores account ownership and explicitly resyncs instead of seeding catalogs")
for iteration=1 to 6
    native=m.storeHost.stores.auth.registry.section
    reboot=MockRegistry()
    for each key in native.durable
        reboot.values[key]=native.durable[key]
    end for
    restored=AuthStore(RegistryIO(reboot,"auth",SyncBudget),SyncScope)
    Harness_Equal(restored.GetSession(),"stremio","saved session survives relaunch")
    Harness_Equal(restored.GetCacheScope(),String(64,"b"),"relaunch retains B namespace")
    StartAddonSync():task=m.addonSyncTask:RunSync(task,[SyncDescriptor("Bsource","stream")]):onAddonSyncFinished(SyncEvent(task))
    Harness_Equal(m.storeHost.stores.addons.GetAll().Count(),1,"relaunch sync does not accumulate duplicates")
end for

Harness_Suite("Repeated production logout and login keep guest and account namespaces separate")
for iteration=1 to 3
    old=m.addonSyncTask
    DoLogout()
    Harness_Equal(m.storeHost.stores.auth.GetSession(),"","logout clears persisted authentication")
    Harness_Equal(m.storeHost.stores.addons.Get("Bsource"),invalid,"logout drops account provider from guest view")
    Harness_Equal(m.stack.active.id,"authScreen","logout routes through auth gate")
    SyncLogin("B"):task=m.addonSyncTask:RunSync(task,[SyncDescriptor("Bsource","stream")]):onAddonSyncFinished(SyncEvent(task))
    Harness_Equal(m.storeHost.stores.addons.GetAll().Count(),1,"repeated login never inherits guest seeds or stale account data")
end for

Harness_Suite("Bounded persistence retries keep dirty state and support explicit retry")
native=m.storeHost.stores.addons.registry.section:native.failFlushes=true
m.storeHost.stores.addons.Save()
for attempt=1 to 8
    onPersistenceTick()
end for
Harness_Equal(m.persistenceRetryCount,3,"automatic retry rounds stop at the documented budget")
Harness_Ok(m.storeHost.stores.addons.SaveFailed(),"failed provider save remains dirty")
native.failFlushes=false:RetryDeviceSaves()
Harness_Ok(not m.storeHost.stores.addons.SaveFailed(),"manual retry recovers dirty provider state")
Harness_Equal(m.persistenceRetryCount,0,"successful persistence resets retry count")

Harness_Suite("Browser request uses the actual TV permission gate before installation")
m.top.dialog=invalid:m.pendingSetupImport=invalid:m.stack.active={id:"homeScreen"}
Harness_Ok(not RequestSetupImport("https://source.example/manifest.json"),"closed Add-ons screen rejects import before dialog")
m.stack.active={id:"addonsScreen"}
Harness_Ok(RequestSetupImport("https://source.example/manifest.json"),"open Add-ons queues TV confirmation")
Harness_Equal(m.acceptedImports,0,"browser acknowledgement does not start installation before consent")
Harness_Equal(m.top.dialog.buttons[0],"Cancel","first/default TV action is cancellation")
Harness_Ok(not RequestSetupImport("https://other.example/manifest.json"),"second request cannot replace pending confirmation")
m.top.dialog=invalid:m.pendingSetupImport=invalid

Harness_Suite("TV import confirmation rejects cancelled, expired and wrong-account requests")
m.stack.active={id:"addonsScreen"}
for each kind in ["cancel","expired","stale","allow"]
    selected=1:elapsed=0:generation=AccountGeneration()
    if kind="cancel" then selected=0
    if kind="expired" then elapsed=60000
    if kind="stale" then generation=generation-1
    m.top.dialog={id:"setupImportConfirm",buttonSelected:selected}
    m.pendingSetupImport={url:"https://source.example/manifest.json",accountGeneration:generation,clock:{elapsed:elapsed,TotalMilliseconds:function() as integer
        return m.elapsed
    end function}}
    onSetupImportChoice()
    expected=0
    if kind="allow" then expected=1
    Harness_Equal(m.acceptedImports,expected,"only current confirmed request can start local installation: "+kind)
    Harness_Equal(m.pendingSetupImport,invalid,"private pending URL cleared after choice")
end for
m.pendingSetupImport={url:"https://source.example/manifest.json",accountGeneration:AccountGeneration(),clock:{TotalMilliseconds:function() as integer
    return 60000
end function}}
m.top.dialog={id:"setupImportConfirm",close:false}
ExpireSetupImport()
Harness_Equal(m.pendingSetupImport,invalid,"abandoned confirmation URL expires without user interaction")
Harness_Ok(m.top.dialog.close=true,"expired confirmation is dismissed")
Harness_Finish()
if m.failed>0 then invalid.Poison()
