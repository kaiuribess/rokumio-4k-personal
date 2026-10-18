' Bounded, private in-memory source queue. Never log or persist source URLs.
function AutoPlayback_Candidates(first as dynamic, candidates as dynamic, maxCandidates = 64 as integer, maxUhd = 16 as integer, diversifyHosts = false as boolean) as object
    if maxCandidates < 1 or maxCandidates > 64 then maxCandidates = 64
    if maxUhd < 1 or maxUhd > maxCandidates then maxUhd = maxCandidates
    result = []
    pool = []
    if Type(first) = "roAssociativeArray" then pool.Push(first)
    if Type(candidates) = "roArray"
        for each stream in candidates
            pool.Push(stream)
        end for
    end if
    fourKCount = 0
    hasFallback = false
    patterns = CinemaSourcePatterns()
    if diversifyHosts then return AutoPlayback_DiverseCandidates(pool,maxCandidates,maxUhd,patterns)
    for each stream in pool
        if CinemaIsHttpsStream(stream,patterns) and CinemaSourceBlockReason(stream,patterns) = "" and not CinemaIs4KLabel(stream,patterns) then hasFallback = true
    end for
    for each stream in pool
        if CinemaIsHttpsStream(stream,patterns) and CinemaSourceBlockReason(stream,patterns) = ""
            duplicate = false
            for each added in result
                if added.url = stream.url then duplicate = true
            end for
            fourK = CinemaIs4KLabel(stream,patterns)
            include = not duplicate and result.Count() < maxCandidates
            if fourK and hasFallback and fourKCount >= maxUhd then include = false
            if include
                result.Push(stream)
                if fourK then fourKCount = fourKCount + 1
            end if
        end if
    end for
    return result
end function

' Automatic selection supplies a ranked pool. Keep its best candidate in each
' quality tier first, then try different delivery hosts before another file
' from the same host. Provider order and remembered successes still determine
' each host's first choice. Manual queues retain the original ordered policy.
' All work stays on SourceSelectionTask; host keys are transient and never
' attached to a returned stream, logged, or written to source memory.
function AutoPlayback_DiverseCandidates(pool as object, maxCandidates as integer, maxUhd as integer, patterns as object) as object
    tiers = []
    byRank = {}
    hasFallback = false
    for each stream in pool
        if not CinemaIsHttpsStream(stream,patterns) then continue for
        if CinemaSourceBlockReason(stream,patterns) <> "" then continue for
        height = CinemaResolutionHint(stream,patterns)
        uhd = height = 2160
        if not uhd then hasFallback = true
        rank = CinemaQualityRank(height)
        rankKey = rank.ToStr()
        if not byRank.DoesExist(rankKey)
            tier = {rank:rank,uhd:uhd,hosts:[],byHost:{}}
            byRank[rankKey] = tier
            tiers.Push(tier)
        end if
        tier = byRank[rankKey]
        host = AutoPlayback_DeliveryBucket(stream)
        if not tier.byHost.DoesExist(host)
            bucket = {streams:[],cursor:0}
            tier.byHost[host] = bucket
            tier.hosts.Push(bucket)
        end if
        bucket = tier.byHost[host]
        ' No host can contribute more than the final pool. Deduplicate before
        ' applying this bound so repeated descriptors cannot hide later files.
        if bucket.streams.Count() >= maxCandidates then continue for
        duplicate = false
        for each previous in bucket.streams
            if previous.url = stream.url then duplicate = true:exit for
        end for
        if not duplicate then bucket.streams.Push(stream)
    end for
    tiers.SortBy("rank","r")
    result = []
    fourKCount = 0
    for each tier in tiers
        advanced = true
        while advanced
            if tier.uhd and hasFallback and fourKCount >= maxUhd then exit while
            advanced = false
            for each bucket in tier.hosts
                if result.Count() >= maxCandidates then return result
                if tier.uhd and hasFallback and fourKCount >= maxUhd then exit for
                found = false
                while bucket.cursor < bucket.streams.Count() and not found
                    stream = bucket.streams[bucket.cursor]
                    bucket.cursor = bucket.cursor + 1
                    duplicate = false
                    for each previous in result
                        if previous.url = stream.url then duplicate = true:exit for
                    end for
                    if not duplicate
                        result.Push(stream)
                        if tier.uhd then fourKCount = fourKCount + 1
                        found = true
                        advanced = true
                    end if
                end while
            end for
        end while
    end for
    return result
end function

function AutoPlayback_DeliveryBucket(stream as object) as string
    ' Only the delivery hostname defines a normal bucket: multiple providers,
    ' ports, paths and signed query strings can still use the same file host.
    url = CinemaOptionalText(stream.url)
    authority = LCase(Mid(url,9).Split("/")[0].Split("?")[0].Split("#")[0])
    host = ""
    if Left(authority,1) = "["
        closing = authority.InStr("]")
        if closing > 1 then host = Left(authority,closing+1)
    else
        host = authority.Split(":")[0]
        if Right(host,1) = "." then host = Left(host,Len(host)-1)
    end if
    if host <> "" then return "host:" + host
    ' A malformed/unknown authority stays eligible for the existing native
    ' validation path. Its provider may distinguish it without persisting it.
    provider = CinemaOptionalText(stream.sourceMemoryProvider)
    if provider <> "" then return "provider:" + provider
    return "unknown"
end function

function AutoPlayback_Status(index as integer, total as integer, stream as dynamic) as string
    quality = "source"
    height = CinemaResolutionHint(stream)
    if height = 2160 then quality = "4K source" else if height > 0 then quality = height.ToStr() + "p source"
    return "Finding English audio — trying " + quality + " " + (index + 1).ToStr() + " of " + total.ToStr()
end function
