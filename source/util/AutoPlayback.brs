' Bounded, private in-memory source queue. Never log or persist source URLs.
function AutoPlayback_Candidates(first as dynamic, candidates as dynamic) as object
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
    for each stream in pool
        if CinemaIsHttpsStream(stream) and not CinemaIs4KLabel(stream) then hasFallback = true
    end for
    for each stream in pool
        if CinemaIsHttpsStream(stream) and CinemaSourceBlockReason(stream) = ""
            duplicate = false
            for each added in result
                if added.url = stream.url then duplicate = true
            end for
            fourK = CinemaIs4KLabel(stream)
            include = not duplicate and result.Count() < 64
            if fourK and hasFallback and fourKCount >= 16 then include = false
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
    text = CinemaStreamText(stream)
    if CinemaIs4KLabel(stream) then quality = "4K source" else if text.InStr("1080") >= 0 then quality = "1080p source"
    return "Finding English audio — trying " + quality + " " + (index + 1).ToStr() + " of " + total.ToStr()
end function
