function ProgressClock() as dynamic
    if m.noProgressClock = true then return invalid
    return {elapsed:0,Mark:sub()
        m.elapsed = 0
    end sub,TotalMilliseconds:function() as dynamic
        return m.elapsed
    end function}
end function

function ProgressNode(id as integer) as object
    return {fixtureId:id,observations:[],control:"stop",failField:false,failObserve:false,HasField:function(name as string) as boolean
        return m.DoesExist(name)
    end function,AddField:function(name as string,kind as string,notify as boolean) as boolean
        if m.failField then return false
        m[name] = 0
        return true
    end function,ObserveField:function(field as string,callback as string,context as object) as boolean
        if m.failObserve then return false
        m.observations.Push({field:field,callback:callback,context:context})
        return true
    end function,IsSameNode:function(other as object) as boolean
        return m.fixtureId = other.fixtureId
    end function}
end function

function ProgressEvent(node as object,field as string,data as dynamic,info as object) as object
    return {node:node,field:field,data:data,info:info,GetRoSGNode:function() as object
        return m.node
    end function,GetField:function() as string
        return m.field
    end function,GetData:function() as dynamic
        return m.data
    end function,GetInfo:function() as object
        return m.info
    end function}
end function

function ProgressTimerEvent() as object
    return ProgressEvent(m.progressTimer,"fire",true,{crimsonProgressGeneration:m.progressGeneration})
end function

function ProgressNativeEvent(field as string,data as dynamic) as object
    return ProgressEvent(m.video,field,data,{crimsonDeliveryGeneration:m.deliveryGeneration})
end function

sub ProgressSetup()
    m.noProgressClock = false
    m.progressTimer = invalid
    m.timerFixture = ProgressNode(1)
    m.video = ProgressNode(2)
    m.video.state = "playing":m.video.position = 1136.63:m.video.duration = 7200
    m.video.positionInfo = {audio:966.997,video:1136.63,epoch:0,clip_id:1}
    m.video.seek = 0:m.video.mute = false:m.video.visible = true
    m.deliveryGeneration = 1:m.video.crimsonDeliveryGeneration = 1
    m.deliveryExpectedUrl = "https://example.invalid/private?token=fixture-secret"
    m.video.content = {url:m.deliveryExpectedUrl}
    m.top = {timer:m.timerFixture,FindNode:function(id as string) as object
        return m.timer
    end function,SetFocus:sub(value as boolean)
    end sub}
    m.playbackActive = true:m.sourceAccepted = true:m.retryPending = false:m.playArmed = false
    m.audioGuardBlocked = false:m.audioGuardActive = true:m.audioRecoveryPending = false:m.resolveTask = invalid
    m.sourceQueue = [{url:m.deliveryExpectedUrl},{url:"https://example.invalid/next"}]:m.sourceIndex = 0
    m.playParams = {autoSourceRetry:true,metaType:"movie",metaId:"tt123",videoId:"tt123",stream:m.sourceQueue[0],position:0,serverAddress:"",season:0,episode:0,recoveryRound:0}
    m.retryTimer = {control:"stop"}:m.playTimer = {control:"stop"}:m.audioGuardTimer = {control:"stop"}:m.startupLimit = {control:"stop"}
    m.status = {text:""}:m.failures = 0:m.launched = 0:m.lastPlaybackPosition = 1136.63:m.lastPlaybackDuration = 7200
    m.accountGeneration = invalid:m.hasPlayed = true:m.saved = false:m.naturalEnd = false
    m.discoveryPending = false:m.startupLimitArmed = false
    m.stores = {library:{checkpoints:[],callFunc:function(name as string,arg1 = invalid as dynamic,arg2 = invalid as dynamic,arg3 = invalid as dynamic,arg4 = invalid as dynamic) as dynamic
        if name = "LibraryIsChannelType" then return false
        if name = "LibrarySetPosition"
            m.checkpoints.Push(arg1)
            return true
        end if
        return invalid
    end function},watch:{records:[],callFunc:function(name as string,packet as object) as dynamic
        m.records.Push(packet)
        return true
    end function}}
    InitProgressRecovery()
    ProgressRecovery_Update()
end sub

sub StopAudioRecoveryTimers()
end sub
sub RememberSourceFailure()
    m.failures = m.failures + 1
end sub
sub CancelResolve()
end sub
sub ResetVideoNode()
    ResetProgressRecovery()
    m.video.control = "stop"
end sub
sub StartResolve(stream as object,server as dynamic,season as integer,episode as integer)
    m.launched = m.launched + 1
end sub

sub ProgressAdvance(ms as integer)
    if m.progressClock <> invalid then m.progressClock.elapsed = m.progressClock.elapsed + ms
    if Type(m.progressGuard) = "roAssociativeArray" then m.progressGuard.clock.elapsed = m.progressGuard.clock.elapsed + ms
end sub
sub ProgressTick(ms = 3000 as integer)
    ProgressAdvance(ms)
    onProgressHealthTick(ProgressTimerEvent())
end sub
sub ProgressTicks(count as integer)
    for i = 1 to count
        ProgressTick()
    end for
end sub

Harness_Suite("Production native callbacks register once and fail closed")
ProgressSetup()
Harness_Equal(m.timerFixture.observations.Count(),1,"one guarded timer observer is installed")
Harness_Equal(m.timerFixture.observations[0].callback,"onProgressHealthTick","real timer callback is registered")
Harness_Equal(m.timerFixture.observations[0].context[0],"crimsonProgressGeneration","queued timer events capture watchdog generation")
Harness_Equal(m.video.observations.Count(),2,"state and native seek each receive one observer")
Harness_Equal(m.video.observations[1].field,"seek","native and voice seek changes reset proof")
Harness_Equal(m.video.observations[1].context[0],"crimsonDeliveryGeneration","native events capture source ownership")
Harness_Ok(ProgressRecovery_Status().monitoring,"accepted owned playback starts monitoring")
Harness_Equal(m.timerFixture.duration,3,"watchdog samples at a three-second cadence")
ProgressSetup():m.timerFixture.Delete("crimsonProgressGeneration"):m.timerFixture.failField = true
InitProgressRecovery():ProgressRecovery_Update()
Harness_Equal(m.progressTimer,invalid,"failed generation field registration disables the watchdog")
ProgressSetup():m.timerFixture.failObserve = true
InitProgressRecovery():ProgressRecovery_Update()
Harness_Equal(m.progressTimer,invalid,"failed timer observer registration disables the watchdog")
ProgressSetup():m.video.failObserve = true
InitProgressRecovery():ProgressRecovery_Update()
Harness_Equal(m.progressTimer,invalid,"failed native observer registration disables the watchdog")

Harness_Suite("Frozen accepted playback enters real deferred recovery after45 seconds")
ProgressSetup()
ProgressTicks(14)
Harness_Equal(m.failures,0,"42 seconds never triggers early fallback")
Harness_Equal(ProgressRecovery_Status().stableMilliseconds,42000,"diagnostic reports only completed observation intervals")
Harness_Equal(m.stores.library.checkpoints.Count(),0,"sampling never writes the registry")
ProgressTick(2999)
Harness_Equal(m.failures,0,"queued timer callback before its deadline cannot trigger recovery")
ProgressTick(1)
Harness_Equal(m.failures,1,"45 seconds of stable position and divergent but frozen native clocks triggers once")
Harness_Ok(m.retryPending,"existing source coordinator schedules deferred recovery")
Harness_Equal(m.playParams.position,1136.63,"accepted fractional resume point survives handoff scheduling")
Harness_Equal(m.stores.library.checkpoints.Count(),0,"watchdog does not save within the detection callback")
Harness_Equal(m.launched,0,"watchdog never starts network resolution directly")
Harness_Ok(ProgressRecovery_Status().recoveryIssued,"diagnostics expose the one-shot recovery latch")
ProgressRecovery_Update()
Harness_Ok(not m.progressTickArmed,"issued source cannot rearm without a source reset")
m.retryGuard.clock.elapsed = 500:onAutoSourceRetry()
Harness_Equal(m.stores.library.checkpoints.Count(),1,"real retry callback durably saves before replacement")
Harness_Equal(m.stores.library.checkpoints[0].position,1136,"actual checkpoint preserves accepted resume progress")
Harness_Equal(m.stores.watch.records.Count(),1,"real save publishes its accepted watch state")
Harness_Equal(m.sourceIndex,1,"real coordinator advances exactly one retained candidate")
Harness_Equal(m.launched,1,"real retry launches exactly one replacement resolver")
onAutoSourceRetry()
Harness_Equal(m.launched,1,"duplicate retry cannot skip more candidates")

Harness_Suite("An exhausted early pool resumes bounded provider discovery")
ProgressSetup():m.sourceQueue = [m.sourceQueue[0]]
ProgressTicks(15)
Harness_Ok(m.discoveryPending,"no-progress recovery reaches the existing rediscovery path")
m.retryGuard.clock.elapsed = 500:onAutoSourceRetry()
Harness_Equal(m.top.sourceRecoveryRequest.videoId,"tt123","rediscovery retains the title identity")
Harness_Equal(m.top.sourceRecoveryRequest.position,1136.63,"rediscovery retains accepted fractional progress")
Harness_Equal(m.top.sourceRecoveryRequest.excludedUrls.Count(),1,"failed pool is excluded from later discovery")
Harness_Equal(m.top.sourceRecoveryRequest.round,1,"automatic discovery stays inside its existing round budget")
Harness_Equal(m.stores.library.checkpoints.Count(),1,"rediscovery saves through the real deferred boundary")
ProgressSetup():m.sourceQueue = [m.sourceQueue[0]]:m.playParams.recoveryRound = 2
ProgressTicks(15)
Harness_Ok(not m.discoveryPending and not m.retryPending,"exhausted recovery budget cannot rediscover forever")

Harness_Suite("Any real media progress or discontinuity restarts the full proof window")
for each field in ["position","audio","video","clip_id","epoch"]
    ProgressSetup():ProgressTicks(14)
    if field = "position"
        m.video.position = m.video.position + 0.01
    else
        m.video.positionInfo[field] = m.video.positionInfo[field] + 1
    end if
    ProgressTick()
    Harness_Equal(m.failures,0,"movement in " + field + " prevents false fallback")
    Harness_Equal(ProgressRecovery_Status().stableMilliseconds,0,"movement in " + field + " starts a new full window")
end for
ProgressSetup():ProgressTicks(14):m.video.position = 30:ProgressTick()
Harness_Equal(m.failures,0,"backward position jump is a seek discontinuity")
ProgressSetup():ProgressTicks(14):m.video.positionInfo.audio = invalid:ProgressTick()
Harness_Equal(ProgressRecovery_Status().stableMilliseconds,0,"disappearing native samples cannot carry old proof")
ProgressSetup()
for i = 1 to 40
    m.video.positionInfo.audio = m.video.positionInfo.audio + 0.01
    ProgressTick()
end for
Harness_Equal(m.failures,0,"advancing audio protects playback despite a stale Video position")
ProgressSetup():ProgressTicks(14):ProgressTick(9001)
Harness_Equal(m.failures,0,"a long callback scheduling gap is not continuous stall evidence")
Harness_Equal(ProgressRecovery_Status().stableMilliseconds,0,"long callback gap starts a fresh45-second window")
ProgressSetup():ProgressTicks(14)
m.progressClock.elapsed = 1:m.progressGuard.clock.elapsed = 3000:onProgressHealthTick(ProgressTimerEvent())
Harness_Equal(m.failures,0,"monotonic clock reset cannot trigger recovery")

Harness_Suite("Pause, buffering, seek and queued events respect user controls")
for each state in ["paused","buffering","stopped","finished","error"]
    ProgressSetup():ProgressTicks(14)
    m.video.state = state:onProgressNativeChanged(ProgressNativeEvent("state",state))
    Harness_Ok(not m.progressTickArmed,"native " + state + " stops the timer")
    Harness_Equal(m.timerFixture.control,"stop","native " + state + " stops scheduled native timer work")
    m.video.state = "playing":onProgressNativeChanged(ProgressNativeEvent("state","playing"))
    ProgressTick()
    Harness_Equal(m.failures,0,"resumed " + state + " playback receives a new full window")
end for
ProgressSetup():ProgressTicks(14)
queued = ProgressNativeEvent("state","paused")
onProgressNativeChanged(queued):ProgressTick()
Harness_Equal(m.failures,0,"queued pause snapshot resets proof even when current native state is already playing")
ProgressSetup():ProgressTicks(14):ProgressAdvance(3000)
oldTick = ProgressTimerEvent()
onProgressNativeChanged(ProgressNativeEvent("seek",0))
onProgressHealthTick(oldTick)
Harness_Equal(m.failures,0,"seek exactly at recovery boundary invalidates the queued timer")
Harness_Equal(ProgressRecovery_Status().stableMilliseconds,0,"explicit seek to zero resets progress proof")
ProgressSetup():ProgressTicks(14)
onProgressNativeChanged(ProgressNativeEvent("state","playing")):ProgressTick()
Harness_Equal(m.failures,1,"duplicate playing notifications do not conceal a stable45-second stall")

Harness_Suite("Stale timer and native events cannot cross node or source ownership")
ProgressSetup()
staleTimer = ProgressTimerEvent():staleNative = ProgressNativeEvent("seek",100)
ResetProgressRecovery():m.deliveryGeneration = 2:m.video.crimsonDeliveryGeneration = 2:ProgressRecovery_Update()
ProgressTicks(14):ProgressAdvance(3000)
onProgressNativeChanged(staleNative)
Harness_Equal(ProgressRecovery_Status().stableMilliseconds,42000,"previous-source seek cannot reset new-source proof")
onProgressHealthTick(staleTimer)
Harness_Equal(m.failures,0,"previous watchdog generation cannot execute on a new source")
event = ProgressTimerEvent():event.node = ProgressNode(99):onProgressHealthTick(event)
Harness_Equal(m.failures,0,"another native timer cannot trigger recovery")
event = ProgressTimerEvent():event.info = {}:onProgressHealthTick(event)
Harness_Equal(m.failures,0,"missing timer generation is rejected")
event = ProgressTimerEvent():event.info.crimsonProgressGeneration = "1":onProgressHealthTick(event)
Harness_Equal(m.failures,0,"string timer generation is rejected")
event = ProgressTimerEvent():event.field = "position":onProgressHealthTick(event)
Harness_Equal(m.failures,0,"unexpected event type cannot trigger recovery")
onProgressHealthTick(ProgressTimerEvent())
Harness_Equal(m.failures,1,"valid current timer still recovers after stale events are ignored")
ProgressSetup():ProgressTicks(14):m.deliveryGeneration = 2:m.video.crimsonDeliveryGeneration = 2:ProgressTick()
Harness_Equal(m.failures,0,"source generation change without lifecycle callback still rejects old proof")
ProgressSetup():ProgressTicks(14):m.video.content = {url:"https://example.invalid/other"}:ProgressTick()
Harness_Equal(m.failures,0,"changed native content without source reset fails ownership closed")

Harness_Suite("Excluded and unknown playback never creates a recovery decision")
for each excluded in ["unaccepted","inactive","retry","armed","resolving","audio-repair","audio-blocked","manual","diagnostic","diagnosticControl","channel","tv"]
    ProgressSetup():ProgressTicks(14)
    if excluded = "unaccepted" then m.sourceAccepted = false
    if excluded = "inactive" then m.playbackActive = false
    if excluded = "retry" then m.retryPending = true
    if excluded = "armed" then m.playArmed = true
    if excluded = "resolving" then m.resolveTask = {id:"pending"}
    if excluded = "audio-repair" then m.audioRecoveryPending = true
    if excluded = "audio-blocked" then m.audioGuardBlocked = true
    if excluded = "manual" then m.playParams.autoSourceRetry = false
    if excluded = "diagnostic" then m.playParams.diagnostic = true
    if excluded = "diagnosticControl" then m.playParams.diagnosticControl = true
    if excluded = "channel" or excluded = "tv" then m.playParams.metaType = excluded
    ProgressTick()
    Harness_Equal(m.failures,0,excluded + " playback cannot trigger automatic recovery")
    Harness_Ok(not m.progressTickArmed,excluded + " playback stops monitoring")
end for
for each bad in [invalid,-1,"1136.63",true,{},2147483648#]
    ProgressSetup():ProgressTicks(14):m.video.position = bad:ProgressTick()
    Harness_Equal(m.failures,0,"invalid native position discards accumulated proof")
    Harness_Ok(not ProgressRecovery_Status().monitoring,"unknown position is not reported as a verified monitoring window")
    m.video.position = 50:ProgressTick()
    Harness_Equal(ProgressRecovery_Status().stableMilliseconds,0,"valid position can restart monitoring after missing facts")
end for
ProgressSetup():m.noProgressClock = true:ResetProgressRecovery():ProgressRecovery_Update()
Harness_Ok(not m.progressTickArmed,"missing monotonic clock disables the watchdog")
ProgressSetup():ProgressTicks(14):m.playbackActive = false:ResetProgressRecovery()
Harness_Equal(m.timerFixture.control,"stop","exit cancels the native timer")
Harness_Ok(not ProgressRecovery_Status().monitoring,"exit clears the observation window")
ProgressSetup()
json = FormatJson(ProgressRecovery_Status())
Harness_Equal(ProgressRecovery_Status().Count(),4,"diagnostic surface contains only fixed scalar facts")
Harness_Ok(json.InStr("example.invalid") < 0 and json.InStr("fixture-secret") < 0,"diagnostics never contain source URLs or tokens")
Harness_Finish()
