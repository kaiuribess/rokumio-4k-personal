' Only public names and fixed result messages leave the check worker.
' Configured addresses, response bodies and arbitrary provider errors stay private.
function AddonDiagnostics_Text(value as dynamic) as string
    if Type(value) = "String" or Type(value) = "roString" then return value.Trim()
    return ""
end function

function AddonDiagnostics_Name(addon as dynamic, index = 0 as integer) as string
    fallback = "Add-on " + (index + 1).ToStr()
    if Type(addon) <> "roAssociativeArray" then return fallback
    name = AddonDiagnostics_Text(addon.name)
    if name = "" then return fallback
    secret = CreateObject("roRegex", "https?://|stremio://|api[ _-]?key|token[=:]|authkey|[a-z0-9_-]{32,}", "i")
    if secret.IsMatch(name) then return fallback
    name = name.Replace(Chr(10), " ").Replace(Chr(13), " ")
    return name.Left(64)
end function

function AddonDiagnostics_HasResource(manifest as dynamic, wanted as string) as boolean
    if Type(manifest) <> "roAssociativeArray" or Type(manifest.resources) <> "roArray" then return false
    for each resource in manifest.resources
        if Type(resource) = "roAssociativeArray"
            if resource.name = wanted then return true
        else if AddonDiagnostics_Text(resource) = wanted
            return true
        end if
    end for
    return false
end function

function AddonDiagnostics_Error(error as dynamic, status = 0 as integer) as object
    text = LCase(AddonDiagnostics_Text(error))
    if status = 0
        http = CreateObject("roRegex", "http[ :]+([1-5][0-9]{2})([^0-9]|$)", "i").Match(text)
        if http.Count() > 1 then status = Val(http[1])
    end if
    if status = 401 or status = 403 then return {label:"Access denied",detail:"The provider refused access (HTTP " + status.ToStr() + "). Recheck your private configured link and account."}
    if status = 404 then return {label:"Not found",detail:"The requested endpoint was not found (HTTP 404). A source request can also be unavailable for this title."}
    if status = 429 then return {label:"Rate limited",detail:"The provider is limiting requests (HTTP 429). Wait, then refresh."}
    if status >= 500 then return {label:"Provider unavailable",detail:"The provider returned HTTP " + status.ToStr() + ". Try again later."}
    if status >= 400 then return {label:"Request rejected",detail:"The request returned HTTP " + status.ToStr() + ". Recheck the configured add-on."}
    if text.InStr("timed out") >= 0 or text.InStr("timeout") >= 0 then return {label:"Timed out",detail:"The provider did not respond before the request deadline. Check the connection and try again."}
    if status < 0 then return {label:"Connection failed",detail:"Roku could not complete the network request (code " + status.ToStr() + ")."}
    return {label:"Request failed",detail:"The request could not be completed. Open Add-ons > Check add-ons, or refresh this provider."}
end function

function AddonDiagnostics_Check(addon as dynamic, index as integer, http as object) as object
    item = {index:index,name:AddonDiagnostics_Name(addon,index),state:"failed",label:"Missing setup",detail:"This add-on has no configured address. Add its manifest again.",streams:false}
    if Type(addon) <> "roAssociativeArray" then return item
    address = AddonDiagnostics_Text(addon.address)
    if address = "" then return item
    try
        reply = http.GetRaw(http.EndpointUrl(address,"/manifest.json"),8000)
        if Type(reply) <> "roAssociativeArray" then return item
        status = 0
        if reply.status <> invalid then status = Int(reply.status)
        if reply.ok <> true
            reason = AddonDiagnostics_Error(reply.error,status)
            item.label = reason.label
            item.detail = reason.detail
            return item
        end if
        body = AddonDiagnostics_Text(reply.body)
        if body.Len() > 2097152
            item.label = "Manifest too large"
            item.detail = "The manifest exceeded the check's size limit. It was not processed."
            return item
        end if
        manifest = ParseJson(body)
        if Type(manifest) <> "roAssociativeArray" or AddonDiagnostics_Text(manifest.id) = "" or AddonDiagnostics_Text(manifest.name) = "" or Type(manifest.types) <> "roArray" or Type(manifest.resources) <> "roArray"
            item.label = "Invalid manifest"
            item.detail = "The response was not a usable Stremio manifest. Recheck the configured manifest link."
            return item
        end if
        if AddonDiagnostics_Text(addon.id) <> "" and addon.id <> manifest.id
            item.label = "Add-on changed"
            item.detail = "The returned add-on identity differs from the installed one. Reimport the current configured manifest."
            return item
        end if
        item.state = "ready"
        item.streams = AddonDiagnostics_HasResource(manifest,"stream")
        item.label = "Manifest reachable"
        roles = []
        for each role in ["catalog","meta","stream","subtitles"]
            if AddonDiagnostics_HasResource(manifest,role) then roles.Push(role)
        end for
        item.detail = "Manifest loaded successfully. Advertises: " + roles.Join(", ") + "."
        if roles.Count() = 0 then item.detail = "Manifest loaded; it declares no catalog, title, stream or subtitle resource this client uses."
        if item.streams
            item.detail = item.detail + Chr(10) + Chr(10) + "Stream availability is checked for each selected title. This check does not start playback or verify account entitlement."
        else
            item.detail = item.detail + Chr(10) + Chr(10) + "This is not a stream provider. Catalog and subtitle add-ons normally need a separate source add-on for playback."
        end if
    catch e
        item.label = "Check failed"
        item.detail = "The manifest check could not complete. No configured link or provider response is shown."
    end try
    return item
end function

function AddonDiagnostics_ProviderLabel(provider as object, pending as dynamic, visibleCount as integer, skipped = invalid as dynamic) as string
    if Type(pending) = "String" or Type(pending) = "roString"
        if pending = "queued" then return "Queued · Waiting for a source request slot"
        if pending = "pending" then return "Requesting sources…"
    else if pending = true
        return "Requesting sources…"
    end if
    if AddonDiagnostics_Text(provider.error) <> "" then return AddonDiagnostics_Error(provider.error).label + " · Open Add-ons > Check add-ons"
    rawCount = 0
    if Type(provider.streams) = "roArray" then rawCount = provider.streams.Count()
    if Type(provider.sourceDiagnostics) = "roAssociativeArray"
        diagnostics = provider.sourceDiagnostics
        if Type(diagnostics.rawCount) = "Integer" or Type(diagnostics.rawCount) = "roInteger"
            if diagnostics.rawCount >= rawCount then rawCount = diagnostics.rawCount
        end if
        if Type(diagnostics.status) = "Integer" and Type(diagnostics.uncached) = "Integer" then skipped = diagnostics
    end if
    if rawCount = 0 then return "No sources returned for this title · This alone does not mean the add-on is broken"
    if visibleCount = 0 and Type(skipped) = "roAssociativeArray"
        if skipped.status > 0 then return "Provider reports an account / service problem · Check your private configuration"
        if skipped.uncached > 0 then return "Provider returned downloads still pending · Choose a cached source"
    end if
    if visibleCount = 0 then return rawCount.ToStr() + " sources listed · None match the current source filter"
    return visibleCount.ToStr() + " source choices · Availability and playback are checked when selected"
end function
