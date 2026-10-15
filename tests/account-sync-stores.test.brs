function SyncFixture(id as string, address as string, resources as object, catalogs as object) as object
    return {transportUrl:address,manifest:{id:id,name:id,version:"1",types:["movie","series"],resources:resources,catalogs:catalogs}}
end function
function SyncDigestFixture(address as string) as string
    if address.InStr("second")>=0 then return String(64,"b")
    return String(64,"a")
end function
sub Test_AccountSync_StoreBoundaries()
    Harness_Suite("Account collection imports usable entries without disguising partial sync")
    registry=MockRegistry()
    store=AddonsStore(ScriptedTransport([]),registry,"stremio",String(64,"a"))
    catalog=SyncFixture("catalog","https://catalog.example/manifest.json",["catalog","meta"],[{type:"movie",id:"top",name:"Movies"}])
    stream=SyncFixture("streams","https://stream.example/first/manifest.json?option=fixture",["stream"],[])
    captions=SyncFixture("captions","https://captions.example/manifest.json",["subtitles"],[])
    outcome=store.ReconcileAccount([catalog,stream,captions])
    Harness_Ok(outcome.ok,"complete collection imports")
    store=AddonsStore(ScriptedTransport([]),MockRegistry(),"stremio",String(64,"a"))
    outcome=store.ReconcileAccount([catalog,stream,captions,SyncFixture("legacy","https://legacy.example/stremio/v1",["stream"],[])])
    Harness_Equal(store.GetAll().Count(),3,"one unsupported transport cannot discard supported providers")
    Harness_Equal(outcome.imported,3,"partial import exposes exact accepted count")
    Harness_Equal(outcome.unsupported,1,"unsupported descriptor is distinguished")
    Harness_Ok(outcome.applied=true and outcome.complete<>true and outcome.ok<>true,"partial adoption is never reported as a complete sync")
    outcome=store.ReconcileAccount([catalog,42,captions])
    Harness_Equal(outcome.invalid,1,"malformed descriptor is counted without throwing")
    Harness_Ok(store.Get("streams")<>invalid,"partial snapshot cannot infer a provider removal")
    outcome=store.ReconcileAccount([catalog,captions])
    Harness_Ok(outcome.complete=true,"fully valid snapshot can reconcile removals")
    Harness_Equal(store.Get("streams"),invalid,"confirmed account removal applies")
    Harness_Equal(outcome.removed,1,"removal count is accurate")

    Harness_Suite("Exact duplicates and configured instances have separate identities")
    store=AddonsStore(ScriptedTransport([]),MockRegistry(),"stremio",String(64,"a"))
    store.descriptorDigest=SyncDigestFixture
    second=SyncFixture("streams","https://stream.example/second/manifest.json?option=other-fixture",["stream"],[])
    outcome=store.ReconcileAccount([stream,stream,second])
    Harness_Ok(outcome.complete=true,"exact duplicate is benign while separate configurations remain usable")
    Harness_Equal(outcome.duplicates,1,"exact duplicate count is visible")
    Harness_Equal(outcome.imported,2,"both configured instances import")
    Harness_Equal(store.GetAll().Count(),2,"same manifest id does not collapse different configured URLs")
    if store.GetAll().Count()=2
        Harness_Equal(store.GetAll()[1].address,"https://stream.example/second?option=other-fixture","second configuration path and query survive privately")
    end if

    before=store.GetAll()[1].id
    outcome=store.ReconcileAccount([second,stream])
    Harness_Equal(store.GetAll()[0].id,before,"configured identity remains stable across account reorder")
    reopened=AddonsStore(ScriptedTransport([]),store.registry,"stremio",String(64,"a"))
    Harness_Equal(reopened.GetAll().Count(),2,"distinct configurations survive registry reload")
    Harness_Equal(reopened.GetAll()[0].address,store.GetAll()[0].address,"configuration order and private query survive reload")

    Harness_Suite("Local ownership survives an account collision and later removal")
    store=AddonsStore(ScriptedTransport([]),MockRegistry(),"stremio",String(64,"a"))
    store.descriptorDigest=SyncDigestFixture
    local=store.InstallFromDescriptor(second.transportUrl,second.manifest)
    Harness_Ok(local.ok,"local provider installs")
    outcome=store.ReconcileAccount([stream])
    Harness_Equal(store.GetAll().Count(),2,"remote same-id configuration cannot delete local-only provider")
    outcome=store.ReconcileAccount([])
    Harness_Equal(store.GetAll().Count(),1,"empty remote collection removes only account ownership")
    if store.GetAll().Count()=1 then Harness_Equal(store.GetAll()[0].address,"https://stream.example/second?option=other-fixture","local-only configuration survives empty account snapshot")

    Harness_Suite("Account adoption distinguishes in-memory import from durable persistence")
    native=MockRegistry()
    store=AddonsStore(ScriptedTransport([]),RegistryIO(native,"addons",ReliabilityBudget),"stremio",String(64,"a"))
    outcome=store.ReconcileAccount([stream])
    Harness_Ok(outcome.persisted=true,"first account snapshot is durably acknowledged")
    native.failFlushes=true
    outcome=store.ReconcileAccount([stream,captions])
    Harness_Ok(outcome.applied=true and outcome.persisted<>true and outcome.ok<>true,"failed device save cannot report successful durable sync")
    Harness_Ok(store.SaveFailed(),"partial persistence remains dirty for bounded retry")
    native.failFlushes=false
    Harness_Ok(store.Save(),"retained provider state is recoverable after storage failure")

    Harness_Suite("Catalog-only manifests and invalid catalog entries stay distinguishable")
    store=AddonsStore(ScriptedTransport([]),MockRegistry(),"stremio",String(64,"a"))
    catalogOnly=SyncFixture("catalog-only","https://catalog.example/manifest.json",[],[{type:"movie",id:"top",extra:[{name:"search"}]}])
    outcome=store.ReconcileAccount([catalogOnly])
    Harness_Ok(outcome.complete=true,"declared catalogs are usable even with an empty resource list")
    Harness_Equal(outcome.catalogProviders,1,"catalog-only provider counts as browsing/search capability")
    broken=SyncFixture("broken","https://broken.example/manifest.json",["catalog"],[42])
    outcome=store.ReconcileAccount([catalogOnly,broken])
    Harness_Equal(outcome.invalid,1,"malformed catalog cannot silently become complete success")
    Harness_Ok(outcome.complete<>true,"invalid catalog descriptor makes snapshot explicitly incomplete")
end sub
