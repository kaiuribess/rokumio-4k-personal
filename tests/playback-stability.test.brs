sub SavePosition()
    m.positionSaves = 1
end sub
function StabilityClock() as dynamic
    if m.noClock = true then return invalid
    return {elapsed:0,Mark:sub()
        m.elapsed=0
    end sub,TotalMilliseconds:function() as integer
        return m.elapsed
    end function}
end function

sub StabilitySetup()
    m.noClock=false
    m.top={SetFocus:sub(value as boolean)
    end sub}
    m.video={state:"buffering",position:0,duration:3600,control:"none",mute:true,content:{title:"Current"},HasField:function(name as string) as boolean
        return m.DoesExist(name)
    end function}
    m.playTimer={control:"stop"}:m.retryTimer={control:"stop"}:m.startupLimit={control:"stop"}:m.audioGuardTimer={control:"stop"}
    m.playArmed=false:m.retryPending=false:m.startupLimitArmed=false:m.audioGuardBlocked=false:m.audioGuardActive=true
    m.playbackActive=true:m.sourceAccepted=false:m.sourceIndex=0
    m.sourceQueue=[{url:"https://example.invalid/first"},{url:"https://example.invalid/next"}]
    m.playParams={stream:m.sourceQueue[0],position:0,serverAddress:"",season:0,episode:0}
    m.status={text:""}:m.launched=0:m.failures=0:m.lastPlaybackPosition=0:m.lastPlaybackDuration=0
end sub
sub StopAudioRecoveryTimers()
end sub
sub RememberSourceFailure()
    m.failures=m.failures+1
end sub
sub CancelResolve()
end sub
sub ResetVideoNode()
    m.video.control="stop"
end sub
sub StartResolve(stream as object,server as dynamic,season as integer,episode as integer)
    m.launched=m.launched+1
end sub
function ResolveOrdinal(value as dynamic) as integer
    return 0
end function
function CurrentEnglishAudioCheck() as object
    return {verified:false,reason:"waiting-rendered-audio",englishTracks:[]}
end function
function QueueAudioTrackRepair() as boolean
    return false
end function
sub onEnglishAudioFactsChanged()
end sub
sub AudioRecovery_SyncState()
end sub
sub ShowEnglishAudioChoice(tracks as object)
end sub
function AudioRecovery_Alternatives() as object
    return [{id:"english"}]
end function
sub AudioRecovery_MarkTried(id as string)
end sub
sub ClearAudioProgress()
end sub
sub ArmAudioProgress()
end sub

Harness_Suite("Queued playback timers cannot act before the current operation's deadline")
StabilitySetup()
m.playArmed=true
m.playGuard=TimerGuard_Start(m.playTimer,250)
onPlayKickFire()
Harness_Equal(m.video.control,"none","old play kick cannot adopt new content in the wrong tick")
Harness_Ok(m.playArmed,"current play kick remains owned")
m.playGuard.clock.elapsed=249:onPlayKickFire()
Harness_Equal(m.video.control,"none","sub-millisecond boundary is not rounded into ready")
m.playGuard.clock.elapsed=250:onPlayKickFire()
Harness_Equal(m.video.control,"play","current play starts after its own handoff interval")
Harness_Ok(not m.playArmed,"one play kick only")
m.video.control="paused":onPlayKickFire()
Harness_Equal(m.video.control,"paused","duplicate play kick cannot resume a user's pause")

StabilitySetup()
ScheduleNextSource("fixture")
onAutoSourceRetry()
Harness_Equal(m.launched,0,"old retry event cannot launch another resolver early")
Harness_Equal(m.sourceIndex,0,"old retry cannot skip the selected candidate")
m.retryGuard.clock.elapsed=500:onAutoSourceRetry()
Harness_Equal(m.launched,1,"current retry launches exactly one resolver")
Harness_Equal(m.sourceIndex,1,"current retry advances one candidate")
onAutoSourceRetry()
Harness_Equal(m.launched,1,"duplicate retry cannot advance twice")

StabilitySetup()
ArmSourceStartupLimit(true)
onSourceStartupTimeout()
Harness_Equal(m.failures,0,"old startup deadline does not mark fresh source as failed")
Harness_Ok(m.startupLimitArmed,"fresh startup retains its limit")
m.startupGuard.clock.elapsed=35000:onSourceStartupTimeout()
Harness_Equal(m.failures,1,"mature startup deadline still records one failure")
Harness_Ok(m.retryPending,"mature startup deadline still recovers automatically")

StabilitySetup()
m.video.state="playing"
m.audioGuard=TimerGuard_Start(m.audioGuardTimer,10000)
onEnglishAudioTimeout()
Harness_Ok(not m.retryPending,"queued earlier audio timeout cannot reject a new source")
m.audioGuard.clock.elapsed=10000:onEnglishAudioTimeout()
Harness_Ok(m.retryPending,"new source keeps a bounded English audio check")
StabilitySetup()
m.audioGuard=TimerGuard_Start(m.audioGuardTimer,10000)
m.sourceAccepted=true:m.video.state="playing":m.video.mute=false
m.audioGuard.clock.elapsed=10000:onEnglishAudioTimeout()
Harness_Ok(not m.video.mute and not m.retryPending,"old audio timeout cannot interrupt accepted playback")

StabilitySetup():m.video.state="playing":m.video.audioTrack="original"
m.audioRecoveryPending=true:m.audioRecoveryGeneration=1:m.audioRecoveryQueuedGeneration=1:m.audioRecoveryTrack="english"
m.audioRecoveryTimer={control:"stop"}
m.audioRepairGuard=TimerGuard_Start(m.audioRecoveryTimer,100)
onAudioTrackRepair()
Harness_Equal(m.video.audioTrack,"original","old repair event cannot switch new source audio early")
Harness_Ok(m.audioRecoveryPending,"new audio repair remains pending")
m.audioRepairGuard.clock.elapsed=100:onAudioTrackRepair()
Harness_Equal(m.video.audioTrack,"english","current delayed repair switches the intended track")
Harness_Ok(not m.audioRecoveryPending,"repair is applied only once")
m.audioRecoveryPending=true:m.audioRecoveryQueuedGeneration=0
onAudioTrackRepair()
Harness_Ok(m.audioRecoveryPending,"previous source generation cannot consume a new repair")

Harness_Suite("Measured progress survives terminal reset without leaking across sources")
StabilitySetup()
m.sourceAccepted=true:m.video.state="playing":m.video.position=123
onPlaybackPositionChanged()
m.video.state="error":m.video.position=0:m.video.duration=0
observed=PlaybackPosition_Snapshot()
Harness_Equal(observed.position,123,"terminal position reset retains measured resume")
Harness_Equal(observed.duration,3600,"terminal duration reset retains current duration")
ScheduleNextSource("fixture")
Harness_Equal(m.playParams.position,123,"automatic replacement resumes after the interruption")
StabilitySetup()
m.sourceAccepted=true:m.video.state="paused":m.video.position=0:m.lastPlaybackPosition=123
Harness_Equal(PlaybackPosition_Snapshot().position,0,"deliberate seek to beginning is preserved")
onPlaybackPositionChanged()
Harness_Equal(m.lastPlaybackPosition,0,"paused seek updates cached position")
m.playbackActive=false:m.video.position=999:onPlaybackPositionChanged()
Harness_Equal(m.lastPlaybackPosition,0,"late exit position cannot update cache")
StabilitySetup()
m.video.state="playing":m.video.position=50:onPlaybackPositionChanged()
Harness_Equal(m.lastPlaybackPosition,0,"unaccepted source cannot establish watched progress")

Harness_Suite("Clock-unavailable fallback still starts the normal timer safely")
StabilitySetup():m.noClock=true
guard=TimerGuard_Start(m.playTimer,250)
Harness_Equal(guard,invalid,"missing clock capability remains unavailable")
Harness_Equal(m.playTimer.control,"start","ordinary timer remains available")
Harness_Ok(TimerGuard_Ready(m.playTimer,guard),"ordinary callback can proceed without invented elapsed facts")
Harness_Equal(TimerGuard_Start(invalid,250),invalid,"missing optional timer remains safe")
Harness_Finish()
