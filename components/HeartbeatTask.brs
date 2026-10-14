' HeartbeatTask — check the streaming server's reachability off the UI thread.
' The heartbeat rides the default request timeout, which can be the whole 15s
' when the server address points nowhere. The task builds its own store +
' transport inside the task scope so that wait never parks the render thread.
sub init()
    m.top.functionName = "heartbeat"
end sub
sub heartbeat()
    try
        http = Transport()
        store = PlaybackStore(http)
        m.top.result = store.Heartbeat(m.top.address)
    catch e
        m.top.result = { ok: false, alive: false, error: e.message }
    end try
end sub
