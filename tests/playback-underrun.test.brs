' Real state/status/timer/recovery callbacks. Only the native video, clock,
' renderer and resolver are substituted; English acceptance is pre-established.
sub StopResolvePulse()
end sub
sub HidePlaybackInfo()
end sub
sub ShowPlaybackInfo()
end sub
sub HideBuffering()
end sub
sub onPlaybackFactsChanged()
end sub
sub PublishWatchState()
end sub
sub CancelNextEpisode()
end sub

sub UnderrunSetup()
    StabilitySetup()
    m.rebufferTimer = {control:"stop"}
    ResetBufferingRecovery()
    m.playParams.metaType = "movie"
    m.playParams.videoId = "tt12345"
    m.playParams.autoSourceRetry = true
    m.sourceAccepted = true
    m.audioGuardActive = false
    m.video.state = "playing"
    m.video.position = 420
    m.video.mute = false
    m.logoFront = invalid
    m.logoBack = invalid
    m.nextEpisodePending = false
    onPlaybackPositionChanged()
end sub

sub UnderrunAdvance(ms as integer)
    if m.rebufferClock <> invalid then m.rebufferClock.elapsed = m.rebufferClock.elapsed + ms
    if Type(m.rebufferGuard) = "roAssociativeArray" then m.rebufferGuard.clock.elapsed = m.rebufferGuard.clock.elapsed + ms
end sub

sub UnderrunBegin(confirmed = true as boolean)
    m.video.state = "buffering"
    m.video.position = 0
    m.video.bufferingStatus = {isUnderrun:confirmed,percentage:20}
    onVideoStateChanged()
    onBufferingStatusChanged()
end sub

sub UnderrunFinish(ms as integer)
    UnderrunAdvance(ms)
    m.video.state = "playing"
    m.video.position = 421
    m.video.bufferingStatus = invalid
    onVideoStateChanged()
    onBufferingStatusChanged()
end sub

Harness_Suite("Repeated real underruns recover without replacing healthy playback")
UnderrunSetup()
m.video.bufferingStatus = {isUnderrun:true,percentage:10}
onBufferingStatusChanged()
Harness_Equal(BufferingRecovery_Status().underruns,0,"status-before-state does not count while native state is still playing")
Harness_Equal(BufferingRecovery_Status().isUnderrun,invalid,"retained buffer status is not exposed as current while playing")
m.video.state = "buffering"
onVideoStateChanged()
Harness_Equal(BufferingRecovery_Status().underruns,1,"later buffering state consumes current native underrun facts")
UnderrunSetup()
m.video.state = "buffering"
m.video.bufferingStatus = invalid
onVideoStateChanged()
Harness_Equal(BufferingRecovery_Status().underruns,0,"state-before-status does not invent an underrun")
m.video.bufferingStatus = {isUnderrun:true,percentage:10}
onBufferingStatusChanged()
Harness_Equal(BufferingRecovery_Status().underruns,1,"later native status starts the same bounded episode")
UnderrunSetup()
UnderrunBegin()
for i = 0 to 9
    onBufferingStatusChanged()
    onVideoStateChanged()
end for
Harness_Equal(BufferingRecovery_Status().underruns,1,"duplicate native state/status events count one continuous underrun")
UnderrunFinish(5000)
UnderrunAdvance(1000)
UnderrunBegin()
UnderrunFinish(5000)
UnderrunAdvance(1000)
UnderrunBegin()
UnderrunAdvance(4000)
onRebufferHealthTick()
Harness_Equal(m.failures,0,"three underruns below the 15-second budget retain the current file")
UnderrunAdvance(1000)
onRebufferHealthTick()
Harness_Equal(m.failures,1,"third confirmed underrun crosses cumulative 15-second limit")
Harness_Ok(m.retryPending,"repeated buffering schedules bounded automatic source recovery")
Harness_Equal(m.playParams.position,421,"accepted position survives native zero while buffering")
Harness_Equal(m.launched,0,"health tick schedules existing deferred resolver instead of immediate network work")
onRebufferHealthTick()
Harness_Equal(m.failures,1,"duplicate health tick cannot fail one source twice")
m.retryGuard.clock.elapsed = 500
onAutoSourceRetry()
Harness_Equal(m.sourceIndex,1,"recovery proceeds to the next retained candidate")
Harness_Equal(m.launched,1,"exactly one replacement resolver starts")
Harness_Equal(m.positionSaves,1,"accepted progress is saved before replacement")

UnderrunSetup()
m.sourceQueue = [m.sourceQueue[0]]
UnderrunBegin():UnderrunFinish(5000)
UnderrunBegin():UnderrunFinish(5000)
UnderrunBegin():UnderrunAdvance(5000):onRebufferHealthTick()
Harness_Ok(m.discoveryPending,"exhausted early pool requests remaining providers")
Harness_Equal(m.playParams.position,421,"rediscovery retains accepted playback offset")
m.retryGuard.clock.elapsed = 500
onAutoSourceRetry()
Harness_Equal(m.top.sourceRecoveryRequest.videoId,"tt12345","deferred rediscovery targets the same title")
Harness_Equal(m.top.sourceRecoveryRequest.position,421,"coordinator receives accepted offset for a new provider")
Harness_Equal(m.top.sourceRecoveryRequest.excludedUrls.Count(),1,"failed pool is excluded from rediscovery")
Harness_Equal(m.top.sourceRecoveryRequest.round,1,"new discovery remains inside the bounded recovery count")

UnderrunSetup()
UnderrunBegin():UnderrunFinish(8000)
UnderrunBegin():UnderrunFinish(8000)
onRebufferHealthTick()
Harness_Equal(m.failures,0,"two longer but completed underruns alone do not meet the episode count")
UnderrunBegin():UnderrunFinish(2000)
onRebufferHealthTick()
Harness_Equal(m.failures,0,"a delayed timer does not interrupt healthy resumed video")

Harness_Suite("Native pause, seek, startup and excluded playback are untouched")
UnderrunSetup()
UnderrunBegin():UnderrunFinish(6000)
UnderrunBegin():UnderrunFinish(6000)
UnderrunBegin()
UnderrunAdvance(5000)
m.video.state = "paused"
onVideoStateChanged()
onRebufferHealthTick()
Harness_Equal(m.failures,0,"queued recovery cannot replace an explicit native pause")
Harness_Equal(m.rebufferTimer.control,"stop","pause stops the health timer")
Harness_Equal(BufferingRecovery_Status().underruns,0,"pause starts a clean future health window")
Harness_Equal(m.video.control,"none","native paused playback is never automatically resumed")

UnderrunSetup()
UnderrunBegin():UnderrunFinish(7000)
UnderrunBegin():UnderrunFinish(7000)
UnderrunBegin(false)
UnderrunAdvance(6000)
onRebufferHealthTick()
Harness_Equal(m.failures,0,"native seek buffering with isUnderrun=false cannot trigger fallback")
Harness_Equal(BufferingRecovery_Status().underruns,2,"seek buffering is not counted as a network episode")
m.video.bufferingStatus = {percentage:50}
onBufferingStatusChanged()
Harness_Equal(BufferingRecovery_Status().underruns,2,"missing native underrun fact remains unknown")

UnderrunSetup()
m.sourceAccepted = false
UnderrunBegin():UnderrunAdvance(20000):onRebufferHealthTick()
Harness_Equal(BufferingRecovery_Status().underruns,0,"initial source buffering is owned by the existing startup deadline")
UnderrunSetup():m.playParams.autoSourceRetry = false
UnderrunBegin():UnderrunAdvance(20000):onRebufferHealthTick()
Harness_Equal(m.failures,0,"manual source with automatic recovery disabled is not proactively stopped")
Harness_Equal(BufferingRecovery_Status().underruns,0,"disabled automatic recovery does not accumulate a replacement budget")
for each kind in ["channel","tv"]
    UnderrunSetup():m.playParams.metaType = kind
    UnderrunBegin():UnderrunAdvance(20000):onRebufferHealthTick()
    Harness_Equal(BufferingRecovery_Status().underruns,0,"live channel is excluded from movie fallback health")
end for
for each key in ["diagnostic","diagnosticControl"]
    UnderrunSetup():m.playParams[key] = true
    UnderrunBegin():UnderrunAdvance(20000):onRebufferHealthTick()
    Harness_Equal(BufferingRecovery_Status().underruns,0,"diagnostic playback is excluded from automatic health recovery")
end for

Harness_Suite("Health window is bounded and stale ticks cannot change a new source")
UnderrunSetup()
UnderrunBegin():UnderrunFinish(6000)
UnderrunBegin():UnderrunFinish(6000)
UnderrunAdvance(120001)
onRebufferHealthTick()
Harness_Equal(BufferingRecovery_Status().underruns,0,"old interruptions age out of the 120-second window")
Harness_Ok(not m.rebufferTickArmed,"expired history stops polling")
UnderrunBegin():UnderrunAdvance(5000):onRebufferHealthTick()
Harness_Equal(m.failures,0,"one current interruption cannot inherit expired failures")

UnderrunSetup()
UnderrunBegin():UnderrunFinish(10000)
UnderrunAdvance(115000)
UnderrunBegin():UnderrunAdvance(1000)
stats = BufferingRecovery_Stats(BufferingRecovery_Now())
Harness_Equal(stats.milliseconds,5000,"boundary episode contributes only the portion inside the rolling window")

UnderrunSetup()
UnderrunBegin():UnderrunFinish(5000)
UnderrunBegin():UnderrunFinish(5000)
UnderrunBegin():UnderrunAdvance(6000)
ResetBufferingRecovery()
UnderrunBegin()
onRebufferHealthTick()
Harness_Equal(m.failures,0,"old queued tick cannot consume a fresh source's new timer interval")
Harness_Equal(BufferingRecovery_Status().underruns,1,"new source owns independent underrun history")
m.playbackActive = false
UnderrunAdvance(20000):onRebufferHealthTick()
Harness_Equal(m.failures,0,"Back defeats any queued health callback")

UnderrunSetup()
m.noClock = true
ResetBufferingRecovery()
UnderrunBegin():onRebufferHealthTick()
Harness_Equal(m.failures,0,"missing clock disables optional cumulative recovery safely")
Harness_Ok(m.startupLimitArmed,"existing continuous-stall limit remains available without the health clock")
UnderrunSetup()
for i = 0 to 40
    UnderrunBegin():UnderrunFinish(1)
end for
Harness_Equal(m.rebufferEpisodes.Count(),32,"very short interruptions cannot grow retained history without bound")

Harness_Suite("Diagnostic health fields contain bounded scalars only")
UnderrunSetup():UnderrunBegin()
UnderrunAdvance(275)
snapshot = BufferingRecovery_Status()
Harness_Equal(snapshot.bufferedSeconds,0,"whole-second compatibility field may round down a short observed interval")
Harness_Equal(snapshot.bufferedMilliseconds,275,"millisecond field preserves short observed intervals")
Harness_Equal(snapshot.isUnderrun,true,"diagnostics expose native underrun fact")
Harness_Equal(snapshot.percentage,20,"diagnostics expose native completion percentage")
m.video.bufferingStatus = {isUnderrun:"private",percentage:"https://private.invalid/token",streamUrl:"https://private.invalid/token"}
onBufferingStatusChanged()
snapshot = BufferingRecovery_Status()
Harness_Equal(snapshot.isUnderrun,invalid,"malformed boolean is not echoed")
Harness_Equal(snapshot.percentage,invalid,"arbitrary native values are not echoed")
Harness_Ok(not snapshot.DoesExist("streamUrl"),"native response URL never enters diagnostics")
Harness_Equal(snapshot.underruns,0,"malformed native underrun fact cannot authorize recovery")
m.video.bufferingStatus = {isUnderrun:false,percentage:101}
Harness_Equal(BufferingRecovery_Status().percentage,invalid,"out-of-range percentage is not invented as valid")
Harness_Finish()
