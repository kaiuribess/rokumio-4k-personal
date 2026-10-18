' Bounded, private in-memory source queue. Never log or persist source URLs.
function AutoPlayback_Candidates(first as dynamic, candidates as dynamic, maxCandidates = 64 as integer, maxUhd = 16 as integer) as object
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

function AutoPlayback_Status(index as integer, total as integer, stream as dynamic) as string
    quality = "source"
    height = CinemaResolutionHint(stream)
    if height = 2160 then quality = "4K source" else if height > 0 then quality = height.ToStr() + "p source"
    return "Finding English audio — trying " + quality + " " + (index + 1).ToStr() + " of " + total.ToStr()
end function
