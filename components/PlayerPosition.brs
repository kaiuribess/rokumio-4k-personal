' Last observed position is scoped to the current source. Terminal native
' states may reset position/duration before recovery or watch-state saving.
sub onPlaybackPositionChanged()
    if m.playbackActive <> true or m.sourceAccepted <> true or m.retryPending = true or m.video = invalid then return
    state = m.video.state
    if state <> "playing" and state <> "paused" then return
    if not m.video.HasField("position") or m.video.position = invalid then return
    m.lastPlaybackPosition = PlaybackInfo_ResumeOffset(m.video.position)
    if m.video.HasField("duration")
        duration = PlaybackInfo_ResumeOffset(m.video.duration)
        if duration > 0 then m.lastPlaybackDuration = duration
    end if
end sub

function PlaybackPosition_Snapshot() as object
    snapshot = {position:0,duration:0}
    if m.video = invalid then return snapshot
    if m.video.HasField("position") then snapshot.position = PlaybackInfo_ResumeOffset(m.video.position)
    if m.video.HasField("duration") then snapshot.duration = PlaybackInfo_ResumeOffset(m.video.duration)
    if snapshot.duration <= 0 then snapshot.duration = PlaybackInfo_ResumeOffset(m.lastPlaybackDuration)
    state = m.video.state
    terminal = state = "finished" or state = "error" or state = "stopped" or state = "buffering"
    if terminal and snapshot.position <= 0 then snapshot.position = PlaybackInfo_ResumeOffset(m.lastPlaybackPosition)
    return snapshot
end function
