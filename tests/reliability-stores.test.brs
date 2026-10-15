' Failure injection exercises the real stores and acknowledged registry wrapper.
function ReliabilityBudget(sectionName as string, key as string, value as string) as boolean
    return true
end function

function ReliabilityScope(identity as string) as string
    if identity = "account:A" then return String(64,"a")
    if identity = "account:B" then return String(64,"b")
    return String(64,"c")
end function

function ReliabilityDescriptor(id as string, config as string) as object
    return {transportUrl:"https://example.com/"+config+"/manifest.json",manifest:{id:id,name:id,version:"1",types:["movie"],resources:["stream"],catalogs:[]}}
end function

sub Test_Reliability_Stores()
    Harness_Suite("Durable acknowledgements, account ownership and account snapshots")
    native = MockRegistry()
    io = RegistryIO(native,"library",ReliabilityBudget)
    store = LibraryStore(io)
    Harness_Ok(store.AddSaved("A","movie","A",""),"initial save acknowledged")
    good = native.Read("library")
    native.failWrites = true
    Harness_Ok(not store.AddSaved("B","movie","B",""),"Write=false cannot report saved")
    Harness_Ok(store.SaveFailed(),"refused save remains dirty")
    Harness_Equal(native.Read("library"),good,"Write failure preserves previous buffer")
    native.failWrites = false
    native.failFlushes = true
    Harness_Ok(not store.Save(),"Flush=false cannot report saved")
    Harness_Equal(native.Read("library"),good,"Flush failure rolls back buffer")
    Harness_Equal(native.durable.library,good,"failed flush preserves durable snapshot")
    native.failFlushes = false
    Harness_Ok(store.Save(),"dirty edit can be retried")
    Harness_Ok(not store.SaveFailed(),"successful retry clears dirty")
    reboot = MockRegistry()
    for each key in native.durable
        reboot.values[key] = native.durable[key]
    end for
    reopened = LibraryStore(RegistryIO(reboot,"library",ReliabilityBudget))
    Harness_Ok(reopened.IsSaved("B"),"retry survives restart")
    io.Write("large",String(30721,"x"))
    Harness_Ok(not io.Flush(),"oversized app-registry write is refused")
    Harness_Equal(native.Read("large"),"","oversized data not buffered")

    authNative = MockRegistry()
    auth = AuthStore(RegistryIO(authNative,"auth",ReliabilityBudget),ReliabilityScope)
    authNative.failFlushes = true
    outcome = auth.LoginStremio("fixture-A",{_id:"A"})
    Harness_Equal(outcome.persisted,false,"authentication reports failed durable save")
    Harness_Ok(auth.SaveFailed(),"authentication remains dirty")
    Harness_Equal(auth.GetCacheScope(),String(64,"a"),"scope belongs to stable account identity")
    authNative.failFlushes = false
    Harness_Ok(auth.Save(),"authentication retry acknowledged")

    registry = MockRegistry()
    registry.Write("stremio_library",FormatJson({continueWatching:[{metaId:"legacy"}]}))
    library = LibraryStore(registry,"stremio",auth.GetCacheScope())
    Harness_Equal(library.positions.Count(),0,"unowned legacy cache is not adopted")
    library.SetPosition("A","A","movie",0,0,"A","",12,100)
    library.SetAccountOutbox([{kind:"libraryChange",metaId:"A",payload:{metaId:"A"}}])
    auth.LoginStremio("fixture-B",{_id:"B"})
    library.SwitchSession("stremio",auth.GetCacheScope())
    Harness_Equal(library.positions.Count(),0,"B cannot see A resume state")
    Harness_Equal(library.GetAccountOutbox().Count(),0,"B cannot inherit A pending writes")
    Harness_Equal(registry.Read("account_"+String(64,"a")+"_library"),"","leaving account purges previous owner cache")
    library.SetPosition("B","B","movie",0,0,"B","",34,100)
    library.SwitchSession("guest","")
    Harness_Equal(library.positions.Count(),0,"guest cannot inherit account positions")

    addons = AddonsStore(ScriptedTransport([]),MockRegistry(),"stremio",String(64,"a"))
    first = addons.ReconcileAccount([ReliabilityDescriptor("one","old"),ReliabilityDescriptor("two","old")])
    Harness_Ok(first.ok,"valid snapshot applies")
    reordered = addons.ReconcileAccount([ReliabilityDescriptor("two","old"),ReliabilityDescriptor("one","old")])
    Harness_Equal(addons.GetAll()[0].id,"two","changed remote order is applied")
    addons.Register({id:"local",name:"Local",address:"https://local.example",resources:["stream"]})
    updated = addons.ReconcileAccount([ReliabilityDescriptor("one","new")])
    Harness_Ok(updated.ok,"same-ID update applies")
    Harness_Equal(addons.Get("one").address,"https://example.com/new","new configured path replaces previous")
    Harness_Equal(addons.Get("two"),invalid,"removed account provider disappears")
    Harness_Ok(addons.Get("local") <> invalid,"intentional local addition retained")
    Harness_Equal(addons.GetAll()[0].id,"one","account order applied before local additions")
    invalidSnapshot = addons.ReconcileAccount([ReliabilityDescriptor("one","next"),{transportUrl:"bad",manifest:{}}])
    Harness_Ok(not invalidSnapshot.ok,"partially invalid snapshot rejected")
    Harness_Equal(addons.Get("one").address,"https://example.com/new","failed snapshot preserves prior configuration")
    Harness_Equal(addons.SanitizeUrl("http://public.example/manifest.json"),"","internet HTTP rejected before fetching")
    Harness_Equal(addons.SanitizeUrl("http://192.168.1.2/manifest.json"),"","local HTTP default off")
    Harness_Ok(not addons.Register({id:"unsafe",name:"Unsafe",address:"http://public.example"}),"cached/off-thread record admission cannot bypass HTTP policy")
    addons.SetLocalHttpAllowed(true)
    Harness_Equal(addons.SanitizeUrl("http://192.168.1.2/manifest.json"),"http://192.168.1.2/manifest.json","explicit private development exception")
    Harness_Equal(addons.SanitizeUrl("http://public.example/manifest.json"),"","exception cannot admit internet HTTP")
    Harness_Equal(addons.SanitizeUrl("https://public.example/a:b/manifest.json?option=1"),"https://public.example/a:b/manifest.json?option=1","HTTPS config path/query retained exactly")

    Harness_Ok(not TransportFailureIsRetryable(-56,"POST"),"receive error after possible write is not replayed")
    Harness_Ok(not TransportFailureIsRetryable(-52,"POST"),"empty reply POST is not replayed")
    Harness_Ok(not TransportFailureIsRetryable(-6,"POST"),"POST DNS failure cannot prove no earlier redirect hop applied a write")
    Harness_Ok(not TransportFailureIsRetryable(-7,"POST"),"POST connect error is not automatically replayed")
    api = StremioApiStore(ScriptedTransport([{ok:false,status:500,json:{result:{success:true}},error:"failed"}]),"fixture")
    Harness_Ok(not api.LibraryPut({_id:"A"},"failed").ok,"HTTP failure success-shaped envelope is not an acknowledgement")
    transport = Transport({})
    result = transport.Result({ok:true,status:200,body:String(1025,"x"),error:""},1024)
    Harness_Ok(not result.ok and result.json = invalid,"oversized body rejected before parsing")
    Harness_Ok(not TransportJsonDepthAllowed(String(33,"[")+String(33,"]")),"excessive nesting rejected")
    Harness_Ok(TransportJsonDepthAllowed(FormatJson({unicode:"日本語 — café",nested:[{ok:true}]})),"UTF-8 bytes preserve structural nesting")
    escapedJson = Chr(34)+Chr(92)+Chr(34)+Chr(92)+Chr(92)+"[{}]"+Chr(34)
    Harness_Ok(TransportJsonDepthAllowed(escapedJson),"escaped quotes and backslashes keep structural bytes inside strings")
    Harness_Ok(not TransportJsonDepthAllowed(Chr(34)+"unterminated"+Chr(92)),"unfinished escaped string is rejected")
    Harness_Ok(TransportJsonDepthAllowed(String(32,"[")+String(32,"]")),"existing 32-level budget is preserved")
    Harness_Ok(TransportJsonDepthAllowed(FormatJson({text:"[[[",a:[{b:true}]})),"quoted brackets do not count as nesting")
    Harness_Equal(TransportResponseLimit("https://example.com/subtitles/movie/A.json"),131072,"subtitle decoded response limit")
end sub
