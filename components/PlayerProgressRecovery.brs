' Native state can remain "playing" after all reported playback positions stop.
' This watchdog proves only an absence of reported progress, never its cause.
' Accepted English VOD receives 45 seconds of continuous, closely sampled
' eligibility. Any movement or playback discontinuity starts a fresh window.
' Recovery runs on a timer through the existing bounded source coordinator.
sub InitProgressRecovery()
    m.progressTimer = m.top.FindNode("progressHealthTick")
    ResetProgressRecovery()
    if m.progressTimer <> invalid
        if not m.progressTimer.HasField("crimsonProgressGeneration")
            if not m.progressTimer.AddField("crimsonProgressGeneration","integer",false)
                m.progressTimer = invalid
                return
            end if
        end if
        m.progressTimer.crimsonProgressGeneration = m.progressGeneration
        if not m.progressTimer.ObserveField("fire","onProgressHealthTick",["crimsonProgressGeneration"])
            m.progressTimer = invalid
            return
        end if
    end if
    if m.video = invalid
        m.progressTimer = invalid
        return
    end if
    if not m.video.HasField("crimsonDeliveryGeneration")
        m.progressTimer = invalid
        return
    end if
    ' Event snapshots also catch a queued pause/buffer/seek that has already
    ' returned to playing by the time the current native fields are read.
    for each field in ["state","seek"]
        if not m.video.HasField(field)
            m.progressTimer = invalid
            return
        end if
        if not m.video.ObserveField(field,"onProgressNativeChanged",["crimsonDeliveryGeneration"])
            m.progressTimer = invalid
            return
        end if
    end for
end sub

' Source/lifecycle reset. Ordinary pause/seek resets only the observation
' window, keeping the at-most-one recovery latch for the current source.
sub ResetProgressRecovery()
    m.progressRecoveryIssued = false
    m.progressClock = invalid
    try
        m.progressClock = CreateObject("roTimespan")
        if m.progressClock <> invalid then m.progressClock.Mark()
    catch e
        m.progressClock = invalid
    end try
    ProgressRecovery_ClearWindow()
end sub

sub ProgressRecovery_ClearWindow()
    if m.progressTimer <> invalid then m.progressTimer.control = "stop"
    m.progressTickArmed = false
    m.progressGuard = invalid
    m.progressSourceGeneration = invalid
    m.progressSnapshot = invalid
    m.progressStableSince = invalid
    m.progressObservedAt = invalid
    if m.progressGeneration = invalid then m.progressGeneration = 0
    if m.progressGeneration >= 2147483646 then m.progressGeneration = 0
    m.progressGeneration = m.progressGeneration + 1
    if m.progressTimer <> invalid
        if m.progressTimer.HasField("crimsonProgressGeneration") then m.progressTimer.crimsonProgressGeneration = m.progressGeneration
    end if
end sub

function ProgressRecovery_Number(value as dynamic) as dynamic
    kind = Type(value)
    if kind <> "Integer" and kind <> "roInt" and kind <> "roInteger" and kind <> "LongInteger" and kind <> "roLongInteger" and kind <> "roInt64" and kind <> "Float" and kind <> "roFloat" and kind <> "Double" and kind <> "roDouble" then return invalid
    value = value + 0#
    if value >= 0 and value <= 2147483647 then return value
    return invalid
end function

function ProgressRecovery_Now() as dynamic
    if m.progressClock <> invalid
        try
            return ProgressRecovery_Number(m.progressClock.TotalMilliseconds())
        catch e
        end try
    end if
    return invalid
end function

function ProgressRecovery_Eligible() as boolean
    if m.playbackActive <> true or m.sourceAccepted <> true or m.retryPending = true or m.playArmed = true then return false
    if m.audioGuardBlocked = true or m.audioRecoveryPending = true or m.resolveTask <> invalid then return false
    if m.progressRecoveryIssued = true or m.progressTimer = invalid or m.progressClock = invalid or m.video = invalid then return false
    if m.video.state <> "playing" then return false
    if Type(m.playParams) <> "roAssociativeArray" then return false
    if m.playParams.autoSourceRetry = false or m.playParams.diagnostic = true or m.playParams.diagnosticControl = true then return false
    kind = LCase(PlaybackInfo_Text(m.playParams.metaType))
    if kind = "channel" or kind = "tv" then return false
    if Type(m.sourceQueue) <> "roArray" or m.sourceQueue.Count() = 0 then return false
    generation = ProgressRecovery_Number(m.deliveryGeneration)
    if generation = invalid then return false
    if Int(generation) <> generation then return false
    if not m.video.HasField("crimsonDeliveryGeneration") then return false
    if m.video.crimsonDeliveryGeneration <> generation then return false
    ' Exact current content ownership is checked privately, never retained in
    ' diagnostics or treated as evidence that a remote host caused the stall.
    if GetInterface(m.deliveryExpectedUrl,"ifString") = invalid or m.deliveryExpectedUrl = "" then return false
    content = m.video.content
    if content = invalid then return false
    if content.url <> m.deliveryExpectedUrl then return false
    return true
end function

function ProgressRecovery_Snapshot() as dynamic
    if m.video = invalid then return invalid
    if not m.video.HasField("position") then return invalid
    position = ProgressRecovery_Number(m.video.position)
    if position = invalid then return invalid
    samples = {}
    if m.video.HasField("positionInfo")
        if Type(m.video.positionInfo) = "roAssociativeArray" then samples = m.video.positionInfo
    end if
    return {position:position,audio:ProgressRecovery_Number(samples.audio),video:ProgressRecovery_Number(samples.video),clip:ProgressRecovery_Number(samples.clip_id),epoch:ProgressRecovery_Number(samples.epoch)}
end function

sub ProgressRecovery_Arm()
    if m.progressTickArmed = true or m.progressTimer = invalid then return
    m.progressTickArmed = true
    m.progressGuard = TimerGuard_Start(m.progressTimer,3000)
end sub

' Called after native state handling and English acceptance. No task, native
' playback control or registry write is performed from these observer hooks.
sub ProgressRecovery_Update()
    if not ProgressRecovery_Eligible()
        ProgressRecovery_ClearWindow()
        return
    end if
    now = ProgressRecovery_Now()
    snapshot = ProgressRecovery_Snapshot()
    if now = invalid
        ProgressRecovery_ClearWindow()
        return
    end if
    if snapshot = invalid
        ProgressRecovery_ClearWindow()
        m.progressSourceGeneration = m.deliveryGeneration
        ProgressRecovery_Arm()
        return
    end if
    if m.progressSourceGeneration <> m.deliveryGeneration or Type(m.progressSnapshot) <> "roAssociativeArray"
        ProgressRecovery_ClearWindow()
        m.progressSourceGeneration = m.deliveryGeneration
        m.progressSnapshot = snapshot
        m.progressStableSince = now
        m.progressObservedAt = now
    end if
    ProgressRecovery_Arm()
end sub

sub onProgressNativeChanged(event as object)
    if m.video = invalid then return
    source = event.GetRoSGNode()
    if source = invalid then return
    if not source.IsSameNode(m.video) then return
    context = event.GetInfo()
    if Type(context) <> "roAssociativeArray" then return
    generation = ProgressRecovery_Number(context.crimsonDeliveryGeneration)
    if generation = invalid or generation <> m.deliveryGeneration then return
    field = LCase(PlaybackInfo_Text(event.GetField()))
    if field = "seek"
        ProgressRecovery_ClearWindow()
        ProgressRecovery_Update()
    else if field = "state"
        if PlaybackInfo_Text(event.GetData()) <> "playing" then ProgressRecovery_ClearWindow()
        ProgressRecovery_Update()
    end if
end sub

sub onProgressHealthTick(event as object)
    if m.progressTickArmed <> true or m.progressTimer = invalid then return
    source = event.GetRoSGNode()
    if source = invalid then return
    if not source.IsSameNode(m.progressTimer) then return
    if LCase(PlaybackInfo_Text(event.GetField())) <> "fire" then return
    context = event.GetInfo()
    if Type(context) <> "roAssociativeArray" then return
    generation = ProgressRecovery_Number(context.crimsonProgressGeneration)
    if generation = invalid or generation <> m.progressGeneration then return
    if not TimerGuard_Ready(m.progressTimer,m.progressGuard) then return
    m.progressTickArmed = false
    if not ProgressRecovery_Eligible() or m.progressSourceGeneration <> m.deliveryGeneration
        ProgressRecovery_ClearWindow()
        return
    end if
    now = ProgressRecovery_Now()
    snapshot = ProgressRecovery_Snapshot()
    if now = invalid or snapshot = invalid
        ProgressRecovery_ClearWindow()
        ProgressRecovery_Update()
        return
    end if
    reset = Type(m.progressSnapshot) <> "roAssociativeArray"
    if m.progressObservedAt = invalid or m.progressStableSince = invalid
        reset = true
    else if now < m.progressObservedAt or now - m.progressObservedAt > 9000
        ' A delayed render thread is not proof of a continuously stalled Video.
        reset = true
    end if
    if not reset
        for each field in snapshot
            ' Movement in either native media clock protects a still-running
            ' source even if Video.position is stale. Backward jumps, missing
            ' samples and clip/epoch changes are discontinuities, not stalls.
            if snapshot[field] <> m.progressSnapshot[field] then reset = true
        end for
    end if
    if reset then m.progressStableSince = now
    m.progressSnapshot = snapshot
    m.progressObservedAt = now
    if now - m.progressStableSince >= 45000
        m.progressRecoveryIssued = true
        ProgressRecovery_ClearWindow()
        ScheduleNextSource("playback-no-progress")
        return
    end if
    ProgressRecovery_Arm()
end sub

function ProgressRecovery_Status() as object
    result = {monitoring:false,stableMilliseconds:0,thresholdSeconds:45,recoveryIssued:m.progressRecoveryIssued = true}
    if not ProgressRecovery_Eligible() or m.progressSourceGeneration <> m.deliveryGeneration then return result
    if m.progressStableSince = invalid or m.progressObservedAt = invalid then return result
    result.monitoring = m.progressTickArmed = true
    ' Only the last checked interval is reported; a pending timer is not proof
    ' that the native player remained eligible since the previous observation.
    result.stableMilliseconds = m.progressObservedAt - m.progressStableSince
    return result
end function
