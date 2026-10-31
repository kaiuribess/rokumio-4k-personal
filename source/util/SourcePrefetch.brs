' Source-list prefetch is RAM-only. This helper never requests a movie URL,
' opens a decoder, or publishes a watch position. Exact configured addresses
' belong in the private context key; never print or persist this key.
function SourcePrefetch_Text(value as dynamic) as string
    if GetInterface(value, "ifString") <> invalid then return value
    kind = Type(value)
    if kind = "Integer" or kind = "roInt" or kind = "roInteger" or kind = "LongInteger" or kind = "roLongInteger" or kind = "Float" or kind = "roFloat" or kind = "Double" or kind = "roDouble" then return value.ToStr()
    return ""
end function

function SourcePrefetch_Context(stores as dynamic, params as dynamic, hashFn = invalid as dynamic) as dynamic
    if stores = invalid or stores.addons = invalid or Type(params) <> "roAssociativeArray" then return invalid
    kind = SourcePrefetch_Text(params.metaType)
    videoId = SourcePrefetch_Text(params.videoId)
    if kind = "" or videoId = "" then return invalid
    mode = "projector"
    if stores.settings <> invalid
        if stores.settings.callFunc("SettingsGetAudioMode") = "surround" then mode = "surround"
    end if
    priority = ProviderPriority_Snapshot(invalid)
    if stores.settings <> invalid
        try
            priority = ProviderPriority_Snapshot(stores.settings.callFunc("SettingsGetProviderPriority"))
        catch e
            ' Older isolated store doubles have no priority bridge.
        end try
    end if
    installed = stores.addons.callFunc("AddonsGetAll")
    if Type(installed) <> "roArray" then return invalid
    signature = []
    providers = []
    for each addon in installed
        if Type(addon) <> "roAssociativeArray" then continue for
        if params.livePlayback = true and addon.address <> params.addonAddress then continue for
        signature.Push({id:addon.id, name:addon.name, address:addon.address, resources:addon.resources, types:addon.types, idPrefixes:addon.idPrefixes})
        if stores.addons.callFunc("AddonsSupportsResource", addon.resources, addon.types, addon.idPrefixes, "stream", kind, videoId)
            address = SourcePrefetch_Text(addon.address)
            if address <> ""
                name = SourcePrefetch_Text(addon.name)
                if name = "" then name = "Source provider"
                providerKey = ProviderPriority_Key(addon, hashFn)
                providers.Push({name:name, id:SourcePrefetch_Text(addon.id), address:address, priorityKey:providerKey, priority:ProviderPriority_Rank(providerKey, priority)})
            end if
        end if
    end for
    key = FormatJson({livePlayback:params.livePlayback = true,addons:signature, audioMode:mode, metaType:kind, metaId:SourcePrefetch_Text(params.metaId), videoId:videoId, season:SourcePrefetch_Text(params.season), episode:SourcePrefetch_Text(params.episode), addonAddress:SourcePrefetch_Text(params.addonAddress)})
    return {key:key, livePlayback:params.livePlayback = true, audioMode:mode, metaType:kind, videoId:videoId, providers:providers, providerPriority:priority}
end function

function SourcePrefetch_Node(top as dynamic) as dynamic
    if top = invalid then return invalid
    try
        scene = top.GetScene()
        if scene <> invalid then return scene.FindNode("sourcePrefetch")
    catch e
        ' Isolated screens and tests may have no Scene; ordinary loading remains.
    end try
    return invalid
end function

function SourcePrefetch_Prepare(top as dynamic, context as dynamic) as dynamic
    if Type(context) <> "roAssociativeArray" then return invalid
    node = SourcePrefetch_Node(top)
    if node = invalid then return invalid
    return node.callFunc("Prepare", context)
end function

sub SourcePrefetch_Cancel(top as dynamic, context as dynamic)
    if Type(context) <> "roAssociativeArray" then return
    node = SourcePrefetch_Node(top)
    if node <> invalid then node.callFunc("Cancel", context.key)
end sub

function SourcePrefetch_DelayReady(timer as dynamic, clock as dynamic, deadline as dynamic) as boolean
    if timer = invalid or clock = invalid or deadline = invalid then return true
    remaining = deadline - clock.TotalMilliseconds()
    if remaining <= 0 then return true
    timer.duration = remaining / 1000.0
    timer.control = "start"
    return false
end function

