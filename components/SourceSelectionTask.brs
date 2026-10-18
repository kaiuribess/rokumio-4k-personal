sub init()
    m.top.functionName = "choose"
end sub
sub choose()
    streams = []
    remembered = false
    data = invalid
    try
        pool = []
        groups = m.top.providerGroups
        if Type(groups) <> "roArray" or groups.Count() = 0 then groups = [m.top.streams]
        for each group in groups
            if Type(group) <> "roArray" then continue for
            for each stream in group
                excluded = false
                if Type(m.top.excludedUrls) = "roArray"
                    for each url in m.top.excludedUrls
                        if stream.url = url then excluded = true:exit for
                    end for
                end if
                if not excluded then pool.Push(stream)
                if pool.Count() >= 1024 then exit for
            end for
            if pool.Count() >= 1024 then exit for
        end for
        streams = CinemaChooseStreams(pool, m.top.fourKOnly, m.top.audioMode,false)
    catch e
        streams = []
    end try
    try
        now = SourceMemory_Now()
        data = SourceMemory_Load(CreateObject("roRegistrySection", "playbackMemory"),now)
        streams = SourceMemory_Order(streams,data,m.top.videoId,m.top.audioMode,now,invalid,m.top.skipRecentFailures <> false)
        streams = CinemaPreferUhdFirst(streams)
    catch e
        ' Memory is an optimization. Keep fresh provider results if it fails.
    end try
    ' Automatic startup samples a small ranked pool, then asks the coordinator
    ' for remaining/fresh providers. Manual browsing keeps its full source list.
    if streams.Count() > 0 then streams = AutoPlayback_Candidates(streams[0],streams,6,3,true,true)
    ' The practical-UHD policy may defer the previously remembered first file.
    ' Describe the actual handoff, not the pre-budget/preference candidate.
    try
        if streams.Count() > 0 and Type(data) = "roAssociativeArray"
            key = SourceMemory_Fingerprint(streams[0],m.top.videoId,m.top.audioMode)
            for each entry in data.entries
                if entry.key = key and entry.outcome = "working" then remembered = true
            end for
        end if
    catch e
        remembered = false
    end try
    m.top.result = {streams:streams,rememberedSource:remembered}
end sub
