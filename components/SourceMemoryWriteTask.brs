sub init()
    m.top.functionName = "save"
end sub
sub save()
    ok = false
    try
        now = SourceMemory_Now()
        registry = RegistryIO(CreateObject("roRegistrySection", "playbackMemory"),"playbackMemory")
        data = SourceMemory_Load(registry,now)
        if Type(m.top.events) = "roArray"
            for each entry in m.top.events
                if Type(entry) = "roAssociativeArray" then data = SourceMemory_Record(data,entry.key,entry.outcome,now)
            end for
        end if
        ok = SourceMemory_Save(registry,data,now)
    catch e
        ' Remembering a result must never become a playback failure.
    end try
    m.top.result = {saved:ok}
end sub
