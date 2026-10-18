' A short underrun that recovers must not reset an unhealthy source forever.
' Count only Roku-confirmed underruns after English playback was accepted.
' Native pause/seek buffering, live channels and diagnostics are not failures.
' No URLs, native decoder mutations, registry writes or tasks live here.
sub InitBufferingRecovery()
    m.rebufferTimer = m.top.FindNode("rebufferHealthTick")
    if m.rebufferTimer <> invalid then m.rebufferTimer.ObserveField("fire","onRebufferHealthTick")
    ResetBufferingRecovery()
end sub

sub ResetBufferingRecovery()
    if m.rebufferTimer <> invalid then m.rebufferTimer.control = "stop"
    m.rebufferTickArmed = false
    m.rebufferGuard = invalid
    m.rebufferEpisodes = []
    m.rebufferCurrent = invalid
    m.rebufferRecoveryIssued = false
    m.rebufferClock = invalid
    try
        m.rebufferClock = CreateObject("roTimespan")
        if m.rebufferClock <> invalid then m.rebufferClock.Mark()
    catch e
        ' Without a monotonic clock, retain the ordinary 35-second limit.
    end try
end sub

function BufferingRecovery_Eligible() as boolean
    if m.playbackActive <> true or m.sourceAccepted <> true or m.retryPending = true or m.audioGuardBlocked = true then return false
    if m.video = invalid or m.rebufferTimer = invalid or m.rebufferClock = invalid or m.rebufferRecoveryIssued = true then return false
    if Type(m.playParams) <> "roAssociativeArray" then return false
    if m.playParams.autoSourceRetry = false then return false
    if m.playParams.diagnostic = true or m.playParams.diagnosticControl = true then return false
    kind = LCase(PlaybackInfo_Text(m.playParams.metaType))
    return kind <> "channel" and kind <> "tv"
end function

function BufferingRecovery_Now() as integer
    if m.rebufferClock = invalid then return -1
    try
        return m.rebufferClock.TotalMilliseconds()
    catch e
    end try
    return -1
end function

sub BufferingRecovery_Arm()
    if m.rebufferTickArmed = true or m.rebufferTimer = invalid then return
    m.rebufferTickArmed = true
    m.rebufferGuard = TimerGuard_Start(m.rebufferTimer,1000)
end sub

sub BufferingRecovery_StateChanged()
    if m.video = invalid then return
    state = m.video.state
    if state = "paused" or state = "stopped" or state = "finished" or state = "error"
        ' Pausing or using trick play starts a clean health window. An old
        ' queued callback cannot then replace the user's chosen playback.
        ResetBufferingRecovery()
        return
    end if
    if state <> "playing" or Type(m.rebufferCurrent) <> "roAssociativeArray" then return
    now = BufferingRecovery_Now()
    if now >= m.rebufferCurrent.start
        m.rebufferCurrent.finish = now
        if Type(m.rebufferEpisodes) <> "roArray" then m.rebufferEpisodes = []
        if m.rebufferEpisodes.Count() >= 32 then m.rebufferEpisodes.Shift()
        m.rebufferEpisodes.Push(m.rebufferCurrent)
    end if
    m.rebufferCurrent = invalid
end sub

sub BufferingRecovery_StatusChanged(status as dynamic)
    if not BufferingRecovery_Eligible() or m.video.state <> "buffering" then return
    if Type(status) <> "roAssociativeArray" then return
    if not BufferingRecovery_IsUnderrun(status)
        ' Explicit seek/startup buffering cannot inherit an underrun episode.
        m.rebufferCurrent = invalid
        return
    end if
    now = BufferingRecovery_Now()
    if now < 0 then return
    if Type(m.rebufferCurrent) <> "roAssociativeArray" then m.rebufferCurrent = {start:now,finish:-1}
    BufferingRecovery_Arm()
end sub

function BufferingRecovery_IsUnderrun(status as dynamic) as boolean
    if Type(status) <> "roAssociativeArray" then return false
    kind = Type(status.isUnderrun)
    if kind <> "Boolean" and kind <> "roBoolean" then return false
    return status.isUnderrun
end function

function BufferingRecovery_Stats(now as integer) as object
    stats = {count:0,milliseconds:0}
    if now < 0 then return stats
    cutoff = now - 120000
    retained = []
    if Type(m.rebufferEpisodes) = "roArray"
        for each episode in m.rebufferEpisodes
            if episode.finish > cutoff
                retained.Push(episode)
                start = episode.start
                if start < cutoff then start = cutoff
                stats.count = stats.count + 1
                stats.milliseconds = stats.milliseconds + episode.finish - start
            end if
        end for
    end if
    m.rebufferEpisodes = retained
    if Type(m.rebufferCurrent) = "roAssociativeArray"
        start = m.rebufferCurrent.start
        if start < cutoff then start = cutoff
        if now >= start
            stats.count = stats.count + 1
            stats.milliseconds = stats.milliseconds + now - start
        end if
    end if
    return stats
end function

sub onRebufferHealthTick()
    if m.rebufferTickArmed <> true then return
    if not TimerGuard_Ready(m.rebufferTimer,m.rebufferGuard) then return
    m.rebufferTickArmed = false
    if not BufferingRecovery_Eligible() then return
    now = BufferingRecovery_Now()
    stats = BufferingRecovery_Stats(now)
    ' Recover only while another real underrun is in progress. Healthy resumed
    ' playback, a pause and a seek never get replaced by a delayed health tick.
    underrun = false
    if m.video.state = "buffering" and m.video.HasField("bufferingStatus")
        status = m.video.bufferingStatus
        underrun = BufferingRecovery_IsUnderrun(status)
    end if
    if underrun and Type(m.rebufferCurrent) = "roAssociativeArray" and stats.count >= 3 and stats.milliseconds >= 15000
        m.rebufferRecoveryIssued = true
        ScheduleNextSource("repeated-buffering")
        return
    end if
    ' Expired windows stop their timer rather than polling for a whole movie.
    if stats.count > 0 then BufferingRecovery_Arm()
end sub

function BufferingRecovery_Status() as object
    stats = BufferingRecovery_Stats(BufferingRecovery_Now())
    snapshot = {underruns:stats.count,bufferedSeconds:Int(stats.milliseconds/1000),windowSeconds:120,recoveryIssued:m.rebufferRecoveryIssued = true,isUnderrun:invalid,percentage:invalid}
    if m.video = invalid or m.video.state <> "buffering" or not m.video.HasField("bufferingStatus") then return snapshot
    status = m.video.bufferingStatus
    if Type(status) <> "roAssociativeArray" then return snapshot
    kind = Type(status.isUnderrun)
    if kind = "Boolean" or kind = "roBoolean" then snapshot.isUnderrun = status.isUnderrun
    kind = Type(status.percentage)
    if kind = "Integer" or kind = "roInt" or kind = "roInteger" or kind = "Float" or kind = "roFloat" or kind = "Double" or kind = "roDouble"
        if status.percentage >= 0 and status.percentage <= 100 then snapshot.percentage = status.percentage
    end if
    return snapshot
end function
