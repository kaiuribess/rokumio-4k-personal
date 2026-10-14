' Static SceneGraph timers can deliver queued events after stop/restart. Check
' the current elapsed interval before a callback may affect the new operation.
function TimerGuard_Start(timer as dynamic, delayMs as integer) as dynamic
    if timer = invalid then return invalid
    guard = invalid
    try
        clock = CreateObject("roTimespan")
        if clock <> invalid
            clock.Mark()
            guard = {clock:clock,delayMs:delayMs}
        end if
    catch e
        ' Missing clock support retains normal timer/cancellation semantics.
    end try
    timer.control = "stop"
    timer.duration = delayMs / 1000.0
    timer.control = "start"
    return guard
end function

function TimerGuard_Ready(timer as dynamic, guard as dynamic) as boolean
    if timer = invalid or Type(guard) <> "roAssociativeArray" then return true
    try
        remaining = guard.delayMs - guard.clock.TotalMilliseconds()
        if remaining > 0
            timer.duration = remaining / 1000.0
            timer.control = "start"
            return false
        end if
    catch e
    end try
    return true
end function
