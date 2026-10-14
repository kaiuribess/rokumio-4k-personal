' Provider scheduling stores only opaque keys. Configured paths, queries and
' userinfo never enter the identity. No successful provider guarantees a file
' or language will work; the key only chooses the next waiting lookup.
function ProviderPriority_Text(value as dynamic) as string
    if GetInterface(value, "ifString") <> invalid then return value.Trim()
    return ""
end function

function ProviderPriority_IsKey(value as dynamic) as boolean
    if GetInterface(value, "ifString") = invalid then return false
    key = value
    if Len(key) <> 64 then return false
    return CreateObject("roRegex", "^[0-9a-f]{64}$", "").IsMatch(key)
end function

function ProviderPriority_Hostname(value as dynamic) as string
    url = ProviderPriority_Text(value)
    if CreateObject("roRegex", "\s", "").IsMatch(url) then return ""
    prefix = 0
    if LCase(Left(url,8)) = "https://" then prefix = 9
    if LCase(Left(url,7)) = "http://" then prefix = 8
    if prefix = 0 then return ""
    authority = Mid(url,prefix).Split("/")[0].Split("?")[0].Split("#")[0]
    if authority = "" or authority.InStr("@") >= 0 then return ""
    authority = LCase(authority)
    if Left(authority,1) = "["
        close = authority.InStr("]")
        if close < 2 then return ""
        host = Left(authority,close+1)
        rest = Mid(authority,close+2)
        if rest <> "" and not CreateObject("roRegex","^:[0-9]+$", "").IsMatch(rest) then return ""
        if not CreateObject("roRegex","^\[[0-9a-f:]+\]$", "").IsMatch(host) then return ""
        return host
    end if
    parts = authority.Split(":")
    if parts.Count() > 2 then return ""
    if parts.Count() = 2 and not CreateObject("roRegex","^[0-9]+$", "").IsMatch(parts[1]) then return ""
    host = parts[0]
    if Right(host,1) = "." then host = Left(host,Len(host)-1)
    if host = "" or Len(host) > 253 then return ""
    if not CreateObject("roRegex","^[a-z0-9.-]+$", "").IsMatch(host) then return ""
    for each label in host.Split(".")
        if label = "" or Len(label) > 63 then return ""
        if Left(label,1) = "-" or Right(label,1) = "-" then return ""
    end for
    return host
end function

function ProviderPriority_PartsIdentity(id as dynamic, hostname as dynamic) as string
    publicId = ProviderPriority_Text(id)
    host = ProviderPriority_Text(hostname)
    if publicId = "" or Len(publicId) > 256 or host = "" then return ""
    if CreateObject("roRegex", "[\s/\\?@#|]", "").IsMatch(publicId) then return ""
    ' Validate a bare hostname through the same parser, never accepting a path.
    normalized = ProviderPriority_Hostname("https://" + host)
    if normalized = "" or host <> normalized then return ""
    return "provider-priority-v1:" + Len(publicId).ToStr() + ":" + publicId + Len(host).ToStr() + ":" + host
end function

function ProviderPriority_Identity(addon as dynamic) as string
    if Type(addon) <> "roAssociativeArray" then return ""
    return ProviderPriority_PartsIdentity(addon.id, ProviderPriority_Hostname(addon.address))
end function

function ProviderPriority_Hash(identity as string, hashFn = invalid as dynamic) as string
    if identity = "" then return ""
    result = ""
    try
        if hashFn <> invalid
            result = hashFn(identity)
        else
            bytes = CreateObject("roByteArray")
            bytes.FromAsciiString(identity)
            digest = CreateObject("roEVPDigest")
            if digest = invalid then return ""
            if digest.Setup("sha256") <> 0 then return ""
            result = digest.Process(bytes)
        end if
    catch e
        return ""
    end try
    result = LCase(ProviderPriority_Text(result))
    if not ProviderPriority_IsKey(result) then return ""
    return result
end function

function ProviderPriority_Key(addon as dynamic, hashFn = invalid as dynamic) as string
    return ProviderPriority_Hash(ProviderPriority_Identity(addon), hashFn)
end function

function ProviderPriority_StreamKey(stream as dynamic, hashFn = invalid as dynamic) as string
    if Type(stream) <> "roAssociativeArray" then return ""
    parts = ProviderPriority_Text(stream.sourceMemoryProvider).Split("|")
    if parts.Count() <> 2 then return ""
    host = LCase(parts[1])
    ' Loader identities may include a port; normalize it just as the manifest.
    normalized = ProviderPriority_Hostname("https://" + host)
    if normalized = "" then return ""
    if host.InStr("/") >= 0 or host.InStr("?") >= 0 or host.InStr("#") >= 0 or host.InStr("@") >= 0 then return ""
    return ProviderPriority_Hash(ProviderPriority_PartsIdentity(parts[0], normalized), hashFn)
end function

function ProviderPriority_Snapshot(value as dynamic) as object
    priority = {preferredProviderKey:"",lastWorkingProviderKey:""}
    if Type(value) <> "roAssociativeArray" then return priority
    if ProviderPriority_IsKey(value.preferredProviderKey) then priority.preferredProviderKey = value.preferredProviderKey
    if ProviderPriority_IsKey(value.lastWorkingProviderKey) then priority.lastWorkingProviderKey = value.lastWorkingProviderKey
    return priority
end function

function ProviderPriority_Rank(providerKey as dynamic, priority as dynamic) as integer
    if not ProviderPriority_IsKey(providerKey) or Type(priority) <> "roAssociativeArray" then return 0
    if providerKey = priority.preferredProviderKey then return 2
    if providerKey = priority.lastWorkingProviderKey then return 1
    return 0
end function

function ProviderPriority_Order(providers as dynamic, priority as dynamic) as object
    order = []
    if Type(providers) <> "roArray" then return order
    for rank = 2 to 0 step -1
        for index = 0 to providers.Count() - 1
            if Type(providers[index]) = "roAssociativeArray"
                if ProviderPriority_Rank(providers[index].priorityKey, priority) = rank then order.Push(index)
            else if rank = 0
                order.Push(index)
            end if
        end for
    end for
    return order
end function
