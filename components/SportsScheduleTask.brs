sub init()
    m.top.functionName = "loadSchedule"
end sub

sub loadSchedule()
    result = {ok:false,events:[],error:"Schedule unavailable. Play/Pause retries; Back returns."}
    try
        url = Sports_Url(m.top.league,m.top.day)
        if url <> ""
            http = Transport()
            response = http.Get(url,invalid,10000)
            if response.ok = true then result = Sports_Normalize(response.json,m.top.league)
        end if
    catch e
        ' Do not echo remote bodies, request URLs or exception details into UI.
    end try
    m.top.result = result
    m.top.finished = true
end sub
