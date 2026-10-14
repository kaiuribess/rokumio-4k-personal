sub init()
    m.top.functionName = "checkAddons"
end sub

sub checkAddons()
    results = []
    http = Transport()
    if Type(m.top.addons) <> "roArray"
        m.top.result = {done:true,results:results}
        return
    end if
    for index = 0 to m.top.addons.Count() - 1
        if m.top.cancelRequested then return
        results.Push(AddonDiagnostics_Check(m.top.addons[index],index,http))
        m.top.result = {done:false,results:results}
    end for
    m.top.result = {done:true,results:results}
end sub
