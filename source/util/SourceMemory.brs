' A small on-device memory of verified file outcomes, not a saved stream URL.
' Caller records "incompatible" only for complete file/header facts. Native
' transport, decoder-start and language-unknown errors are temporary "network"
' outcomes. Manual source selection may bypass this automatic ordering.
'
' Persisted schema is deliberately only opaque SHA-256 key, outcome and UTC
' timestamps. Source URLs, headers, filenames and provider configuration never
' enter the registry. The injected hash/clock seams are for host-side tests.
function SourceMemory_Empty() as object
    return {version:2,entries:[]}
end function

function SourceMemory_MaxEntries() as integer
    return 32
end function

function SourceMemory_RegistryKey() as string
    return "sourceMemoryV1"
end function

function SourceMemory_Ttl(outcome as string) as integer
    if outcome = "working" then return 1209600 ' 14 days, still reverified at play.
    if outcome = "incompatible" then return 604800 ' 7 days, file facts only.
    if outcome = "network" then return 600 ' 10 minutes, never excluded.
    return 0
end function

function SourceMemory_Text(value as dynamic) as string
    kind = Type(value)
    if kind = "String" or kind = "roString" then return value.Trim()
    return ""
end function

function SourceMemory_IsNumber(value as dynamic) as boolean
    kind = Type(value)
    return kind = "Integer" or kind = "roInt" or kind = "roInteger" or kind = "LongInteger" or kind = "roLongInteger" or kind = "Float" or kind = "roFloat" or kind = "Double" or kind = "roDouble"
end function

function SourceMemory_Double(value as dynamic) as double
    ' Preserve epoch seconds and large file sizes. A double literal also keeps
    ' the host interpreter's historical CDbl single-precision shim out of TTLs.
    return value * 1.0#
end function

function SourceMemory_Now() as double
    try
        clock = CreateObject("roDateTime")
        return SourceMemory_Double(clock.AsSeconds())
    catch e
        return 0
    end try
end function

' Only the authority's hostname contributes identity. A changing path, signed
' query, token, userinfo or fragment never does. Invalid/userinfo URLs have no
' identity and remain ordinary candidates instead of acquiring a failure mark.
function SourceMemory_Hostname(value as dynamic) as string
    url = SourceMemory_Text(value)
    if LCase(Left(url,8)) <> "https://" then return ""
    if CreateObject("roRegex","\s","").IsMatch(url) then return ""
    authority = Mid(url,9).Split("/")[0].Split("?")[0].Split("#")[0]
    if authority = "" or authority.InStr("@") >= 0 then return ""
    authority = LCase(authority)
    if Left(authority,1) = "["
        close = authority.InStr("]")
        if close < 2 then return ""
        host = Left(authority,close+1)
        rest = Mid(authority,close+2)
        if rest <> "" and not CreateObject("roRegex","^:[0-9]+$","").IsMatch(rest) then return ""
        if not CreateObject("roRegex","^\[[0-9a-f:]+\]$","").IsMatch(host) then return ""
        return host
    end if
    parts = authority.Split(":")
    if parts.Count() > 2 then return ""
    if parts.Count() = 2 and not CreateObject("roRegex","^[0-9]+$","").IsMatch(parts[1]) then return ""
    host = parts[0]
    if Right(host,1) = "." then host = Left(host,Len(host)-1)
    if host = "" or not CreateObject("roRegex","^[a-z0-9.-]+$","").IsMatch(host) then return ""
    return host
end function

function SourceMemory_FileIdentity(stream as object) as string
    hash = LCase(SourceMemory_Text(stream.infoHash))
    hashKnown = CreateObject("roRegex","^[0-9a-f]{40}$","").IsMatch(hash)
    index = stream.fileIdx
    if hashKnown and SourceMemory_IsNumber(index)
        if index >= 0 and index < 2147483647 and index = Int(index) then return "hash:" + hash + ":" + Int(index).ToStr()
    end if
    hints = stream.behaviorHints
    if Type(hints) <> "roAssociativeArray" then return ""
    filename = SourceMemory_Text(hints.filename)
    ' A title/name is not a file identity. No fallback to a signed URL path.
    if filename = "" or Len(filename) > 512 then return ""
    identity = "file:" + filename
    if hashKnown then identity = "hashfile:" + hash + ":" + filename
    size = hints.videoSize
    if SourceMemory_IsNumber(size)
        if size > 0 and size < 9007199254740991# then identity = identity + ":size:" + SourceMemory_Double(size).ToStr()
    end if
    return identity
end function

function SourceMemory_FileType(stream as object) as string
    ' Endpoint extension can prove delivery changed from a file to a playlist.
    ' Only its type is kept; its path/configuration are never fingerprint data.
    url = SourceMemory_Text(stream.url)
    if LCase(Left(url,8)) = "https://"
        path = LCase(Mid(url,9).Split("?")[0].Split("#")[0])
        if path.InStr("/") >= 0
            if Right(path,5) = ".m3u8" then return "hls"
            if Right(path,4) = ".mpd" then return "dash"
        end if
    end if
    kind = LCase(SourceMemory_Text(stream.streamFormat))
    if kind = "mkv" or kind = "mp4" or kind = "hls" or kind = "dash" or kind = "ism" or kind = "ts" or kind = "mov" or kind = "m4v" or kind = "webm" then return kind
    if Type(stream.behaviorHints) = "roAssociativeArray"
        filename = LCase(SourceMemory_Text(stream.behaviorHints.filename))
        for each extension in ["mkv","mp4","m3u8","mpd","ts","mov","m4v","webm"]
            if Right(filename,Len(extension)+1) = "." + extension
                if extension = "m3u8" then return "hls"
                if extension = "mpd" then return "dash"
                return extension
            end if
        end for
    end if
    return "unknown"
end function

' Length-prefix fields so opaque video IDs/filenames cannot collide by moving
' a separator from one field to the next. This string only exists in memory.
function SourceMemory_Identity(stream as dynamic, videoId as string, audioMode as string, providerId = "" as string) as string
    if Type(stream) <> "roAssociativeArray" then return ""
    if videoId = "" or Len(videoId) > 256 then return ""
    if audioMode <> "projector" and audioMode <> "surround" then return ""
    host = SourceMemory_Hostname(stream.url)
    if host = "" then return ""
    file = SourceMemory_FileIdentity(stream)
    if file = "" then return ""
    provider = providerId.Trim()
    if provider = "" then provider = SourceMemory_Text(stream.sourceMemoryProvider)
    ' Integration supplies a public add-on ID and hostname, not its configured
    ' manifest URL. Refuse accidentally supplied secret-bearing URL syntax.
    if Len(provider) > 256 or provider.InStr("://") >= 0 or provider.InStr("?") >= 0 or provider.InStr("#") >= 0 or provider.InStr("@") >= 0 then return ""
    identity = "source-memory-v1:"
    for each part in [videoId,audioMode,provider,host,SourceMemory_FileType(stream),file]
        identity = identity + Len(part).ToStr() + ":" + part
    end for
    return identity
end function

function SourceMemory_IsKey(value as dynamic) as boolean
    key = SourceMemory_Text(value)
    if Len(key) <> 64 then return false
    return CreateObject("roRegex","^[0-9a-f]{64}$","").IsMatch(key)
end function

' SHA-256 is a documented Roku EVP digest. An unavailable digest disables
' memory for that source; it never downgrades to persisting the clear identity.
function SourceMemory_Hash(identity as string, hashFn = invalid as dynamic) as string
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
    result = LCase(SourceMemory_Text(result))
    if not SourceMemory_IsKey(result) then return ""
    return result
end function

function SourceMemory_Fingerprint(stream as dynamic, videoId as string, audioMode as string, providerId = "" as string, hashFn = invalid as dynamic) as string
    return SourceMemory_Hash(SourceMemory_Identity(stream,videoId,audioMode,providerId),hashFn)
end function

' Normalization is a whitelist clone. Unknown fields cannot survive a write,
' oversized/future/expired records cannot extend TTL, and duplicate newest
' outcomes replace older ones. Invalid clocks disable memory instead of hangs.
' Version 2 changes audio rejection policy, not file identity. Legacy successes
' still speed replay; legacy negatives must not exclude newly eligible sources.
function SourceMemory_Normalize(data as dynamic, now as dynamic) as object
    result = SourceMemory_Empty()
    if not SourceMemory_IsNumber(now) then return result
    if now <= 0 then return result
    if Type(data) <> "roAssociativeArray" then return result
    if not SourceMemory_IsNumber(data.version) then return result
    if (data.version <> 1 and data.version <> 2) or Type(data.entries) <> "roArray" then return result
    ordered = []
    count = 0
    for each entry in data.entries
        count = count + 1
        if count > 256 then exit for
        if Type(entry) = "roAssociativeArray"
            key = SourceMemory_Text(entry.key)
            outcome = SourceMemory_Text(entry.outcome)
            if data.version = 1 and outcome <> "working" then continue for
            ttl = SourceMemory_Ttl(outcome)
            if SourceMemory_IsKey(key) and ttl > 0 and SourceMemory_IsNumber(entry.touched) and SourceMemory_IsNumber(entry.expires)
                touched = SourceMemory_Double(entry.touched)
                expires = SourceMemory_Double(entry.expires)
                if expires > touched + ttl then expires = touched + ttl
                if touched > 0 and touched <= now and expires > now and expires > touched
                    ordered.Push({key:key,outcome:outcome,touched:touched,expires:expires})
                end if
            end if
        end if
    end for
    ordered.SortBy("touched","r")
    unique = []
    seen = {}
    for each entry in ordered
        if seen[entry.key] = invalid
            seen[entry.key] = true
            unique.Push(entry)
        end if
    end for
    ' Keep up to eight recent proven successes even when the next title has
    ' dozens of incompatible files. Newest outcome per key was chosen above,
    ' so an older success never hides a more recent failure of the same file.
    retained = {}
    retainedCount = 0
    workingCount = 0
    for each entry in unique
        if entry.outcome = "working" and workingCount < 8
            retained[entry.key] = true
            retainedCount = retainedCount + 1
            workingCount = workingCount + 1
        end if
    end for
    for each entry in unique
        if retained[entry.key] = invalid and retainedCount < SourceMemory_MaxEntries()
            retained[entry.key] = true
            retainedCount = retainedCount + 1
        end if
    end for
    ' Preserve recency order within the retained snapshot. In particular a
    ' newly recorded temporary failure remains the latest event, not a success.
    for each entry in unique
        if retained[entry.key] = true then result.entries.Push(entry)
    end for
    return result
end function

function SourceMemory_Outcome(data as object, key as string) as string
    if key = "" then return ""
    for each entry in data.entries
        if entry.key = key then return entry.outcome
    end for
    return ""
end function

' Apply before the automatic 64-source cap. Stable buckets preserve the source
' rank among unknown candidates; a temporary failure goes last, not away.
function SourceMemory_Order(streams as dynamic, data as dynamic, videoId as string, audioMode as string, now as dynamic, hashFn = invalid as dynamic) as object
    if Type(streams) <> "roArray" then return []
    data = SourceMemory_Normalize(data,now)
    working = []
    unknown = []
    transient = []
    for each stream in streams
        key = SourceMemory_Fingerprint(stream,videoId,audioMode,"",hashFn)
        outcome = SourceMemory_Outcome(data,key)
        if outcome = "working"
            working.Push(stream)
        else if outcome = "network"
            transient.Push(stream)
        else if outcome <> "incompatible"
            unknown.Push(stream)
        end if
    end for
    result = []
    for each bucket in [working,unknown,transient]
        for each stream in bucket
            result.Push(stream)
        end for
    end for
    return result
end function

function SourceMemory_Record(data as dynamic, key as string, outcome as string, now as dynamic) as object
    result = SourceMemory_Normalize(data,now)
    if not SourceMemory_IsKey(key) or SourceMemory_Ttl(outcome) = 0 then return result
    if not SourceMemory_IsNumber(now) then return result
    if now <= 0 then return result
    entries = [{key:key,outcome:outcome,touched:SourceMemory_Double(now),expires:SourceMemory_Double(now)+SourceMemory_Ttl(outcome)}]
    for each entry in result.entries
        if entry.key <> key then entries.Push(entry)
    end for
    result.entries = entries
    return SourceMemory_Normalize(result,now)
end function

' Registry helpers belong in one serialized worker/store, not a Video observer.
' No log statement here can reveal the source or persisted raw data.
function SourceMemory_Load(registry as dynamic, now as dynamic) as object
    if registry = invalid then return SourceMemory_Empty()
    try
        raw = registry.Read(SourceMemory_RegistryKey())
        if SourceMemory_Text(raw) = "" or Len(raw) > 6144 then return SourceMemory_Empty()
        return SourceMemory_Normalize(ParseJson(raw),now)
    catch e
        return SourceMemory_Empty()
    end try
end function

function SourceMemory_Save(registry as dynamic, data as dynamic, now as dynamic) as boolean
    if registry = invalid then return true
    if not SourceMemory_IsNumber(now) then return false
    if now <= 0 then return false
    try
        raw = FormatJson(SourceMemory_Normalize(data,now))
        if Len(raw) > 6144 then return false
        if not registry.Write(SourceMemory_RegistryKey(),raw) then return false
        registry.Flush()
        return true
    catch e
        return false
    end try
end function
