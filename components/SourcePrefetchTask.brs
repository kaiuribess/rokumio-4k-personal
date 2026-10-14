sub init()
    m.top.functionName = "load"
end sub

' Bound retained candidates without treating audio/quality filenames as proof.
' Audio hint exclusion stays disabled so usable alternate tracks survive.
function SourcePrefetch_LimitStreams(streams as dynamic, audioMode as string, videoId = "" as string, memory = invalid as dynamic, now = invalid as dynamic, hashFn = invalid as dynamic) as object
    ranked = CinemaChooseStreams(streams, false, audioMode, false)
    ' Warm reopen must retain a previously verified file even if its label rank
    ' would fall outside the memory cap. Existing memory holds opaque hashes,
    ' outcomes and expiry only; this browse worker never records a new outcome.
    if videoId <> "" and memory <> invalid
        try
            ranked = SourceMemory_Order(ranked, memory, videoId, audioMode, now, hashFn)
        catch e
            ' Outcome memory is optional; fresh candidates remain usable.
        end try
    end if
    bounded = []
    fourKFlags = []
    fourKCount = 0
    patterns = CinemaSourcePatterns()
    for each stream in ranked
        fourK = patterns.fourK.IsMatch(CinemaStreamText(stream))
        ' HD stereo hints can outrank an unknown 4K layout. Keep a minimum
        ' reserve of up to 64 unique 4K labels so a later explicit 4K filter
        ' does not become empty merely because browsing used a bounded cache.
        if bounded.Count() >= 256
            if fourKCount >= 64 then exit for
            if not fourK then continue for
        end if
        duplicate = false
        ' Match the player's exact URL equality, including case and signatures.
        ' AA keys are case-insensitive and could merge distinct delivery paths.
        for each retained in bounded
            if retained.url = stream.url
                duplicate = true
                exit for
            end if
        end for
        if duplicate then continue for
        if bounded.Count() >= 256
            ' Remove the latest lower-priority non-4K record, then append this
            ' later 4K record. The retained array remains a subsequence of the
            ' original priority order; remembered early successes stay first.
            for index = fourKFlags.Count() - 1 to 0 step -1
                if not fourKFlags[index]
                    bounded.Delete(index)
                    fourKFlags.Delete(index)
                    exit for
                end if
            end for
        end if
        bounded.Push(stream)
        fourKFlags.Push(fourK)
        if fourK then fourKCount = fourKCount + 1
    end for
    return bounded
end function

sub load()
    try
        playback = PlaybackStore(Transport())
        ' Only /stream/{type}/{id}.json. No source URL resolution or media read.
        answer = playback.Streams(m.top.addonAddress, m.top.metaType, m.top.videoId)
        if answer.ok <> true or Type(answer.streams) <> "roArray"
            m.top.result = {ok:false}
            return
        end if
        raw = []
        host = LCase(m.top.addonAddress).Split("://")
        providerHost = ""
        if host.Count() > 1 then providerHost = host[1].Split("/")[0].Split("?")[0].Split("#")[0]
        for each stream in answer.streams
            if Type(stream) <> "roAssociativeArray" then continue for
            stream.sourceMemoryProvider = m.top.providerId + "|" + providerHost
            raw.Push(stream)
        end for
        memory = invalid
        now = invalid
        try
            now = SourceMemory_Now()
            memory = SourceMemory_Load(CreateObject("roRegistrySection", "playbackMemory"), now)
        catch e
            ' No writes or history during prefetch, even when memory is absent.
        end try
        streams = SourcePrefetch_LimitStreams(raw, m.top.audioMode, m.top.videoId, memory, now)
        ' Preserve bounded diagnostic facts, not an unlimited private response.
        diagnostics = CinemaSkippedSources(raw)
        diagnostics.rawCount = raw.Count()
        m.top.result = {ok:true, streams:streams, readyStreams:CinemaChooseStreams(streams, false, m.top.audioMode, false), sourceDiagnostics:diagnostics, error:""}
    catch e
        m.top.result = {ok:false}
    end try
end sub
