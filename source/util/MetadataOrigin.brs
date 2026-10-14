' Library/history store an opaque provider key, never a configured URL.
' Resolve it against the current installed manifests, including older entries
' whose compatible metadata provider must be found by type/id-prefix instead.
function MetadataOrigin_Key(stores as dynamic, address as dynamic) as string
    if stores = invalid or stores.addons = invalid then return ""
    if GetInterface(address,"ifString") = invalid or address = "" then return ""
    addons = stores.addons.callFunc("AddonsGetAll")
    if Type(addons) <> "roArray" then return ""
    for each addon in addons
        if Type(addon) = "roAssociativeArray" and addon.address = address then return ProviderPriority_Key(addon)
    end for
    return ""
end function

function MetadataOrigin_Address(stores as dynamic, key as dynamic, kind as string, id as string, fallback = "" as string) as string
    if stores = invalid or stores.addons = invalid then return fallback
    addons = stores.addons.callFunc("AddonsGetAll")
    if Type(addons) <> "roArray" then return fallback
    first = ""
    specificity = -1
    cinemeta = ""
    for each addon in addons
        if Type(addon) <> "roAssociativeArray" or GetInterface(addon.address,"ifString") = invalid then continue for
        ' An exact remembered provider can be restored even when its built-in
        ' seed has not yet fetched resource descriptors.
        if ProviderPriority_IsKey(key) and ProviderPriority_Key(addon) = key then return addon.address
        imdb = CreateObject("roRegex","^tt[0-9]+$", "").IsMatch(id)
        ' The built-in seed has no idPrefixes until its manifest loads. That
        ' does not make Cinemeta an authority for every custom identifier.
        if addon.id = "com.linvo.cinemeta" and not imdb then continue for
        supported = stores.addons.callFunc("AddonsSupportsResource",addon.resources,addon.types,addon.idPrefixes,"meta",kind,id)
        if supported <> true then continue for
        rank = MetadataOrigin_PrefixLength(addon,id)
        if rank > specificity
            first = addon.address
            specificity = rank
        end if
        if addon.id = "com.linvo.cinemeta" and imdb then cinemeta = addon.address
    end for
    if cinemeta <> "" then return cinemeta
    return first
end function

function MetadataOrigin_PrefixLength(addon as object, id as string) as integer
    prefixes = addon.idPrefixes
    if Type(addon.resources) = "roArray"
        for each entry in addon.resources
            if Type(entry) = "roAssociativeArray" and entry.name = "meta" and entry.short <> true
                prefixes = entry.idPrefixes
                exit for
            end if
        end for
    end if
    best = 0
    if Type(prefixes) = "roArray"
        for each prefix in prefixes
            if GetInterface(prefix,"ifString") <> invalid and prefix <> ""
                if Left(id,Len(prefix)) = prefix and Len(prefix) > best then best = Len(prefix)
            end if
        end for
    end if
    return best
end function
