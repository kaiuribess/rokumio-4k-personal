function HealthTestContent() as object
    return {children:[],CreateChild:function(kind as string) as object
        child=HealthTestContent(): m.children.Push(child): return child
    end function}
end function

function HealthTestList() as object
    return {rowItemFocused:[0,0],callFunc:sub(name as string,index=0 as integer)
        if name="FocusRow" then m.rowItemFocused=[index,0]
    end sub,SetFocus:sub(value as boolean)
        m.focused=value
    end sub}
end function

function HealthTestEvent(node as object,result as dynamic) as object
    return {node:node,result:result,GetRoSGNode:function() as object
        return m.node
    end function,GetData:function() as dynamic
        return m.result
    end function}
end function

function AsyncTask_Launch(owner as object,kind as string,callback as string,params as object,id as string) as object
    m.launches=m.launches+1
    return {id:id,params:params,cancelRequested:false}
end function

sub AsyncTask_Reap(task as object,owner as object,cancel as boolean)
    m.reaps=m.reaps+1
    task.reaped=true
end sub

function HealthTestTransport() as object
    return m.workerHttp
end function

function HealthTestClock() as object
    return {elapsed:0,Mark:sub()
        m.elapsed=0
    end sub,TotalMilliseconds:function() as integer
        return m.elapsed
    end function}
end function

function HealthManifest(streams=true as boolean) as string
    resources=["catalog","meta"]
    if streams then resources.Push({name:"stream",types:["movie","series"]})
    return FormatJson({id:"fixture.provider",name:"Fixture provider",types:["movie","series"],resources:resources,catalogs:[]})
end function

function HealthHttp(body as string,status=200 as integer) as object
    return ScriptedTransport([{method:"GET",ok:status=200,status:status,body:body,error:"HTTP "+status.ToStr()+" https://provider.example/private-fixture?token=fixture-secret"}])
end function

function HealthAddon() as object
    return {id:"fixture.provider",name:"Fixture provider",address:"https://provider.example/private-fixture?token=fixture-secret",resources:["stream"]}
end function

sub TestHealthPolicy()
    Harness_Suite("Manifest checks distinguish reachability, roles and private failures")
    addon=HealthAddon()
    http=HealthHttp(HealthManifest())
    row=AddonDiagnostics_Check(addon,0,http)
    Harness_Equal(row.state,"ready","valid manifest is reachable")
    Harness_Equal(row.name,"Fixture provider","public name retained")
    Harness_Equal(row.label,"Manifest reachable","does not claim playback works")
    Harness_Ok(row.streams,"object-shaped stream capability recognized")
    Harness_Ok(row.detail.InStr("does not start playback")>=0,"check scope explicit")
    Harness_Equal(http.log.Count(),1,"one manifest request")
    Harness_Equal(http.log[0].timeoutMs,8000,"request budget bounded")
    Harness_Ok(http.log[0].url.InStr("/manifest.json?token=")>=0,"configured query retained for request")
    Harness_Equal(row.address,invalid,"configured address never returned")
    Harness_Ok(row.detail.InStr("fixture-secret")<0,"successful detail excludes credential")
    row=AddonDiagnostics_Check(addon,0,HealthHttp(HealthManifest(false)))
    Harness_Equal(row.state,"ready","catalog-only add-on is not failed")
    Harness_Ok(not row.streams,"catalog-only role explicit")
    Harness_Ok(row.detail.InStr("not a stream provider")>=0,"metadata-only distinction explained")
    for each status in [401,403,404,429,500,503]
        row=AddonDiagnostics_Check(addon,0,HealthHttp("",status))
        Harness_Equal(row.state,"failed","HTTP failure classified")
        Harness_Ok(row.detail.InStr("fixture-secret")<0 and row.detail.InStr("https")<0,"HTTP error cannot echo configured URL")
    end for
    Harness_Equal(AddonDiagnostics_Error("HTTP 401 private-data").label,"Access denied","source text yields safe HTTP category")
    Harness_Equal(AddonDiagnostics_Error("Timed out https://private.example/fixture").label,"Timed out","timeout category without raw error")
    Harness_Equal(AddonDiagnostics_Error("bad private-data",-7).label,"Connection failed","native network failure classified")
    Harness_Equal(AddonDiagnostics_Check(addon,0,HealthHttp("{}")).label,"Invalid manifest","missing manifest fields identified")
    wrong=HealthManifest().Replace("fixture.provider","changed.provider")
    Harness_Equal(AddonDiagnostics_Check(addon,0,HealthHttp(wrong)).label,"Add-on changed","identity change not mistaken for valid installed add-on")
    Harness_Equal(AddonDiagnostics_Check({name:"Missing"},2,http).label,"Missing setup","missing address explained")
    Harness_Equal(AddonDiagnostics_Name({name:"https://provider.example/private-fixture?token=fixture"},2),"Add-on 3","name containing URL never displayed")
    Harness_Equal(AddonDiagnostics_Name({name:"ABCDEF0123456789ABCDEF0123456789AB"},0),"Add-on 1","opaque secret-looking name withheld")
    Harness_Equal(AddonDiagnostics_ProviderLabel({streams:[],error:""},false,0),"No sources returned for this title · This alone does not mean the add-on is broken","empty title response not labelled broken")
    Harness_Ok(AddonDiagnostics_ProviderLabel({streams:[{}],error:""},false,0).InStr("filter")>=0,"filter emptiness differs from request failure")
    Harness_Ok(AddonDiagnostics_ProviderLabel({streams:[{}],error:""},false,0,{status:1,uncached:0}).InStr("account / service")>=0,"status clips identify provider-account issue")
    Harness_Ok(AddonDiagnostics_ProviderLabel({streams:[{}],error:""},false,0,{status:0,uncached:1}).InStr("pending")>=0,"uncached downloads identified")
    Harness_Ok(AddonDiagnostics_ProviderLabel({streams:[{}],error:""},false,1).InStr("checked when selected")>=0,"source choices are not playback certification")
    Harness_Ok(AddonDiagnostics_ProviderLabel({streams:[],error:""},"queued",0).InStr("Queued")=0,"waiting provider is labelled Queued")
    Harness_Ok(AddonDiagnostics_ProviderLabel({streams:[],error:""},"pending",0).InStr("Requesting")=0,"active provider is labelled Requesting")
end sub

sub HealthScreenFixture()
    m.launches=0: m.reaps=0: m.sequence=0: m.task=invalid
    m.list=HealthTestList(): m.status={text:""}: m.name={text:""}: m.detail={text:""}: m.limit={control:"stop"}
    m.top={screenActive:true}
    m.stores={addons:{callFunc:function(name as string) as object
        return [HealthAddon(),{id:"catalog",name:"Catalog",address:"https://catalog.example",resources:["catalog"]}]
    end function}}
end sub

sub TestHealthController()
    Harness_Suite("Health controller handles progressive results, cancellation and stale events")
    HealthScreenFixture(): StartHealthCheck()
    Harness_Equal(m.rows.Count(),2,"all installed add-ons receive named rows")
    Harness_Equal(m.launches,1,"one sequential worker prevents request bursts")
    Harness_Equal(m.limit.control,"start","whole-check deadline armed")
    first=m.task
    onHealthResult(HealthTestEvent({id:"old"},{done:true,results:[]}))
    Harness_Equal(m.reaps,0,"stale worker cannot end current check")
    onHealthResult(HealthTestEvent(first,invalid))
    Harness_Equal(m.reaps,0,"initial alwaysNotify has no result")
    m.list.rowItemFocused=[1,0]
    item={index:0,name:"Fixture provider",state:"ready",label:"Manifest reachable",detail:"Metadata valid"}
    onHealthResult(HealthTestEvent(first,{done:false,results:[item]}))
    Harness_Equal(m.rows[0].state,"ready","progressive result updates matching add-on")
    Harness_Equal(m.list.rowItemFocused[0],1,"progress update preserves focused add-on")
    Harness_Ok(m.status.text.InStr("1/2")>=0,"progress count shown")
    onHealthTimeout()
    Harness_Ok(m.task <> invalid and not first.cancelRequested,"queued earlier deadline cannot cancel fresh check")
    m.checkClock.elapsed=120000
    onHealthTimeout()
    Harness_Ok(first.cancelRequested,"deadline requests cancellation")
    Harness_Equal(m.rows[1].state,"incomplete","unchecked add-on is not falsely failed")
    Harness_Ok(m.detail.text.InStr("not proof")>=0,"unfinished check explains uncertainty")
    onHealthResult(HealthTestEvent(first,{done:true,results:[item]}))
    Harness_Equal(m.rows[1].state,"incomplete","timed-out callback cannot repaint")
    StartHealthCheck(): second=m.task
    Harness_Ok(first.id<>second.id,"rerun receives unique identity")
    bad={index:1,name:"Catalog",state:"failed",label:"Access denied",detail:"HTTP 403"}
    onHealthResult(HealthTestEvent(second,{done:true,results:[item,bad]}))
    Harness_Equal(m.task,invalid,"completed worker released")
    Harness_Equal(m.limit.control,"stop","completion stops deadline")
    Harness_Ok(m.status.text.InStr("1 need attention")>=0,"partial provider failure remains visible")
    StartHealthCheck(): active=m.task
    Harness_Ok(not OnBackPressed(),"Back returns through stack")
    Harness_Ok(active.cancelRequested,"Back cancels pending checks")
    m.top.screenActive=false
    onHealthResult(HealthTestEvent(active,{done:true,results:[item]}))
    Harness_Equal(m.task,invalid,"late Back callback cannot restart")
    m.stores.addons.callFunc=function(name as string) as object
        return []
    end function
    StartHealthCheck()
    Harness_Equal(m.rows.Count(),0,"empty installation safely represented")
    Harness_Ok(m.status.text.InStr("No add-ons")>=0,"empty state has useful next step")
end sub

sub TestHealthWorker()
    Harness_Suite("Production health worker never plays content or continues after cancellation")
    m.workerHttp=HealthHttp(HealthManifest())
    m.top={addons:[HealthAddon()],cancelRequested:false,result:invalid}
    checkAddons()
    Harness_Ok(m.top.result.done,"worker publishes terminal packet")
    Harness_Equal(m.top.result.results.Count(),1,"one add-on checked")
    Harness_Equal(m.workerHttp.log.Count(),1,"worker requested manifest only")
    m.workerHttp=HealthHttp(HealthManifest())
    m.top={addons:[HealthAddon()],cancelRequested:true,result:invalid}
    checkAddons()
    Harness_Equal(m.workerHttp.log.Count(),0,"pre-cancelled worker sends no request")
    Harness_Equal(m.top.result,invalid,"cancelled worker does not claim completion")
end sub

function AudioSetupValue() as string
    return "TV / projector speakers"
end function
sub ReportSaveFault()
end sub
sub BuildRows(preserve=false as boolean)
    m.rebuilds=m.rebuilds+1
end sub
function NextSettingsWorkerId(prefix as string) as string
    m.audioSequence=m.audioSequence+1
    return prefix+m.audioSequence.ToStr()
end function
function HealthTestDialog() as object
    return {buttonSelected:-1,ObserveFieldScoped:sub(field as string,callback as string)
    end sub}
end function

sub AudioScreenFixture()
    m.audioSequence=0: m.rebuilds=0
    m.list=HealthTestList(): m.status={text:""}
    m.top={scene:{dialog:invalid},getScene:function() as object
        return m.scene
    end function}
    m.stores={settings:{mode:"projector",writes:0,callFunc:function(name as string,value=invalid as dynamic) as dynamic
        if name="SettingsGetAudioMode" then return m.mode
        if name="SettingsSaveFailed" then return false
        if name="SettingsSetAudioMode"
            m.mode=value: m.writes=m.writes+1
        end if
        return true
    end function}}
    m.settingsAudioDialog=invalid
end sub

sub TestSpeakerSetup()
    Harness_Suite("Surround setup keeps unknown facts honest and requires an explicit choice")
    report=AudioSetup_Report({output:"Stereo",codecs:{eac3:true,ac3:true,aac:true}},"surround")
    Harness_Ok(report.advice.InStr("Stereo")>=0 and report.advice.InStr("Auto")>=0,"Stereo setting warning survives reported DD+ capability")
    report=AudioSetup_Report({output:"5.1 surround",codecs:{eac3:true}},"surround")
    Harness_Ok(report.advice.InStr("soundbar's input display")>=0,"surround capability still needs actual receiver input evidence")
    Harness_Ok(AudioSetup_Report(invalid,"surround").summary.InStr("Not reported")>=0,"missing hardware API stays unknown")
    Harness_Equal(AudioSetup_CodecStatus({codecs:{aac:"true"}},"aac"),"Not reported","wrong-type capability cannot become supported")
    Harness_Equal(AudioSetup_CodecStatus({codecs:{eac3:false}},"eac3"),"Not supported on this connection","explicit negative capability shown")
    Harness_Ok(AudioSetup_Guide("surround").InStr("HDMI IN")>=0,"receiver guide routes Roku into soundbar first")
    Harness_Ok(AudioSetup_Guide("projector").InStr("Stereo")>=0,"projector guide preserves stereo route")
    AudioScreenFixture(): ShowAudioSetup()
    dialog=m.settingsAudioDialog
    Harness_Equal(dialog.buttons.Count(),3,"speaker choice offers both modes and cancel")
    Harness_Equal(m.stores.settings.writes,0,"opening options changes no preference")
    onSettingsAudioChoice(HealthTestEvent(dialog,invalid))
    Harness_Equal(m.stores.settings.writes,0,"initial negative selection does not apply")
    dialog.buttonSelected=2
    onSettingsAudioChoice(HealthTestEvent(dialog,invalid))
    Harness_Equal(m.stores.settings.writes,0,"Cancel preserves mode")
    AudioScreenFixture(): ShowAudioSetup(): dialog=m.settingsAudioDialog
    onSettingsAudioChoice(HealthTestEvent({id:"old",buttonSelected:1},invalid))
    Harness_Equal(m.stores.settings.writes,0,"stale modal cannot change audio")
    dialog.buttonSelected=1
    onSettingsAudioChoice(HealthTestEvent(dialog,invalid))
    Harness_Equal(m.stores.settings.mode,"surround","explicit soundbar selection saved")
    Harness_Equal(m.rebuilds,1,"chosen mode updates screen")
    Harness_Ok(m.status.text.InStr("Auto")>=0,"system Auto requirement explained")
    ApplyAudioSetup("invalid")
    Harness_Equal(m.stores.settings.writes,1,"unsupported choice rejected")
end sub

TestHealthPolicy()
TestHealthController()
TestHealthWorker()
TestSpeakerSetup()
Harness_Finish()
