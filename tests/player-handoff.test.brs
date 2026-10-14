' Exercises the actual PlayerScreen functions. Only native factories, device
' capabilities, and task/UI services are replaced at the interpreter boundary.
function MockNativeObject(kind as string, nodeType = "" as string) as object
    if kind = "roHttpAgent"
        m.agentSerial = m.agentSerial + 1
        return { serial: m.agentSerial }
    end if
    if kind = "roSGNode" and nodeType = "ContentNode"
        m.contentHandoffs.Push({control:m.video.control,audioTrack:m.video.audioTrack,seamless:m.video.seamlessAudioTrackSelection})
        return {}
    end if
    if kind = "roSGNode" and nodeType = "StandardMessageDialog"
        return { buttonSelected: -1, close: false, ObserveField: sub(fieldName as string, callback as string)
        end sub }
    end if
    return invalid
end function

function MockVideoNode() as object
    video = { content: invalid, control: "none", autoplayAfterSeek: false, visible: false, globalCaptionMode: "Off", subtitleTrack: "", audioTrack: "native-choice", seek:0 }
    video.HasField = function(field as string) as boolean
        return m.DoesExist(field)
    end function
    video.SetHttpAgent = sub(agent as object)
        m.httpAgent = agent
    end sub
    video.SetFocus = sub(focused as boolean)
        m.focused = focused
    end sub
    return video
end function

function PlayerTest_ProviderKey(stream as dynamic) as string
    return String(64,"c")
end function

sub SetupPlayerFixture()
    m.lastPlaybackPosition = 0
    m.lastPlaybackDuration = 0
    m.video = MockVideoNode()
    m.contentHandoffs = []
    m.playTimer = { control: "stop" }
    m.playArmed = false
    m.playbackActive = true
    m.sourceAccepted = false
    m.retryPending = false
    m.sourceQueue = []
    m.sourceIndex = 0
    m.retryTimer = { control: "stop" }
    m.startupLimit = { control: "stop" }
    m.audioGuardActive = false
    m.audioGuardArmed = false
    m.audioGuardBlocked = false
    m.audioDialog = invalid
    m.audioGuardTimer = { control: "stop" }
    m.audioProgressTimer = { control: "stop" }
    m.audioRecoveryTimer = { control: "stop" }
    ResetAudioRecovery()
    m.playParams = { name: "Test movie", position: 900.5 }
    m.resolvedPlayback = { mode: "direct", streamFormat: "mkv", headers: ["Authorization:Bearer fixture"] }
    m.agentSerial = 0
    m.subtitleTracks = invalid
    m.subtitleIndex = -1
    m.subtitleNodesApplied = false
    m.subtitleSelectionApplied = false
    m.hasPlayed = false
    m.status = { text: "old error" }
    m.bufferingGroup = { visible: false }
    m.logoBack = { uri: "" }
    m.logoFront = { uri: "", clippingRect: [0, 0, 0, 506] }
    m.top = { scene: { dialog: invalid }, SetFocus: sub(value as boolean)
        m.focused = value
    end sub, getScene: function() as object
        return m.scene
    end function }
    m.toastFade = invalid
    m.toastHideTimer = invalid
    m.toastGroup = invalid
    m.reaped = 0
    m.reapedIds = []
    m.launched = []
    m.workerSequence = 0
    m.resolveTask = invalid
    m.subtitleTask = invalid
    m.subtitleParams = invalid
    m.subtitleCandidates = []
    m.subtitleCursor = 0
    m.subtitleReached = 0
    m.subtitleTried = 1
    m.subtitleAsked = ""
    m.subtitlePicker = {
        PickTrack: function(tracks as object, locale as string) as integer
            if tracks.Count() = 0 then return -1
            return 0
        end function
        TrackLang: function(track as object) as string
            return LCase(track.lang)
        end function
    }
end sub

function ReadDevicePlaybackInfo() as object
    return {}
end function

function PlayerTest_Fingerprint(stream as object, videoId as string, audioMode as string) as string
    return "fixture-identity"
end function

sub Test_SourceProofMemory()
    Harness_Suite("Only fresh advancing English playback becomes a remembered source")
    SetupPlayerFixture()
    m.sourceProofTimer = {control:"start"}
    m.sourceMemoryPump = {control:"stop"}
    m.sourceMemoryPending = []
    m.sourceAttemptKey = "fixture-identity"
    ResetSourceProof()
    m.video.state = "playing"
    m.video.availableAudioTracks = [{Language:"eng",Track:"current",Name:"English"}]
    m.video.currentAudioTrack = "current"
    m.video.audioFormat = "aac"
    m.video.mute = false
    m.sourceAccepted = true
    m.playParams.stream = {sourceMemoryProvider:"fixture|example.test"}
    m.stores = {settings:{calls:[],callFunc:function(name as string,key as string) as boolean
        m.calls.Push({name:name,key:key}):return true
    end function}}
    m.video.positionInfo = {audio:100,video:100}
    onSourceProofTick()
    onSourceProofTick()
    Harness_Equal(m.sourceMemoryPending.Count(),0,"static inherited samples never prove a working source")
    m.video.positionInfo = {audio:105,video:105}
    onSourceProofTick()
    Harness_Equal(m.sourceMemoryPending.Count(),0,"one fresh interval is insufficient")
    Harness_Equal(m.stores.settings.calls.Count(),0,"provider priority is not saved before sustained progress")
    m.video.positionInfo = {audio:110,video:110}
    onSourceProofTick()
    Harness_Equal(m.sourceMemoryPending.Count(),1,"two fresh advancing audio/video intervals prove the source")
    Harness_Equal(m.sourceMemoryPending[0].outcome,"working","verified playback is remembered as working")
    Harness_Equal(m.stores.settings.calls.Count(),1,"verified progress remembers one provider")
    Harness_Equal(m.stores.settings.calls[0].key,String(64,"c"),"only an opaque provider key crosses the settings boundary")
    Harness_Equal(m.sourceProofTimer.control,"stop","proof timer stops after recording")
    onSourceProofTick()
    Harness_Equal(m.sourceMemoryPending.Count(),1,"later ticks cannot duplicate successful memory")
    Harness_Equal(m.stores.settings.calls.Count(),1,"later proof ticks do not repeat provider writes")
    m.playParams.diagnostic = true:RememberWorkingProvider()
    Harness_Equal(m.stores.settings.calls.Count(),1,"diagnostic playback cannot affect preferred scheduling")
    m.playParams.diagnostic = false
    ResetSourceProof()
    m.sourceMemoryPending = []
    m.video.positionInfo = {audio:500,video:500}
    onSourceProofTick()
    m.video.positionInfo = {audio:650,video:650}
    onSourceProofTick()
    Harness_Equal(m.sourceProofSeconds,0,"seek jumps do not count as stable rendered progress")
    m.retryPending = true
    m.video.positionInfo = {audio:655,video:655}
    onSourceProofTick()
    Harness_Equal(m.sourceMemoryPending.Count(),0,"pending retry cannot remember the failed source")
    m.retryPending = false
    m.video.state = "paused"
    onSourceProofTick()
    Harness_Equal(m.sourceProofTimer.control,"stop","pause disarms proof until active playback resumes")
    ResetSourceProof()
    m.resolvedPlayback = {audioPolicy:{known:true,compatible:false}}
    RememberSourceFailure()
    RememberSourceFailure()
    Harness_Equal(m.sourceMemoryPending.Count(),1,"duplicate errors write one outcome per attempt")
    Harness_Equal(m.sourceMemoryPending[0].outcome,"incompatible","complete file incompatibility is remembered separately")
    ResetSourceProof()
    m.sourceMemoryPending = []
    m.resolvedPlayback = {audioPolicy:{known:false,compatible:true}}
    RememberSourceFailure()
    Harness_Equal(m.sourceMemoryPending[0].outcome,"network","unknown/native errors are temporary rather than permanent exclusions")
end sub
sub AsyncTask_Reap(task as object, parent as object, doStop as boolean)
    m.reaped = m.reaped + 1
    m.reapedIds.Push(task.id)
end sub
function AsyncTask_Launch(parent as object, taskType as string, callback as string, fields as object, id as string) as object
    task = { id: id, result: invalid }
    for each key in fields
        task[key] = fields[key]
    end for
    m.launched.Push(task)
    return task
end function
function PlayerTest_Event(task as object, data as dynamic) as object
    return {
        task: task
        data: data
        GetRoSGNode: function() as object
            return m.task
        end function
        GetData: function() as dynamic
            return m.data
        end function
    }
end function
sub StopResolvePulse()
end sub
sub HidePlaybackInfo()
end sub
sub ShowPlaybackInfo()
end sub
sub HideBuffering()
    m.bufferingGroup.visible = false
end sub
sub StartResolvePulse()
end sub
sub StartSubtitles(params as object)
end sub
sub PublishWatchState()
end sub
sub LogVideoError()
end sub

sub Test_PlayerLoadingFeedback()
    Harness_Suite("Actual player feedback without artwork and safe buffering values")
    SetupPlayerFixture()
    m.logoBack.uri = "https://artwork.example/previous-title.png"
    m.logoFront.uri = m.logoBack.uri
    OnEnter({ stream: { url: "https://media.example/movie.mkv" }, logo: "", poster: "" })
    Harness_Ok(m.status.text.InStr("Opening selected source") >= 0, "artwork-free source opening has visible feedback")
    Harness_Ok(m.status.text.InStr("Back") >= 0, "loading screen gives its remote exit control")
    Harness_Ok(not m.bufferingGroup.visible, "missing artwork is not rendered as an empty poster")
    Harness_Equal(m.logoBack.uri, "", "artwork-free title cannot reuse the previous film logo")
    m.lastPlaybackPosition=123:m.lastPlaybackDuration=3600
    StartPlayback("https://media.example/movie.mkv", "mkv")
    Harness_Equal(m.lastPlaybackPosition,0,"new source cannot inherit previous resume observations")
    Harness_Equal(m.lastPlaybackDuration,0,"new source cannot inherit previous duration")
    OnEnter({stream:{url:"https://media.example/selected.mkv"},candidates:[{url:"https://media.example/alternate.mkv"}],autoSourceRetry:false})
    Harness_Equal(m.sourceQueue.Count(),1,"disabled recovery limits playback to the selected source")
    OnEnter({stream:{url:"https://media.example/selected.mkv"},candidates:[{url:"https://media.example/alternate.mkv"}]})
    Harness_Equal(m.sourceQueue.Count(),2,"default recovery retains compatible alternatives")
    StartPlayback("https://media.example/movie.mkv","mkv")
    Harness_Ok(m.status.text.InStr("Starting playback") >= 0, "native content handoff keeps startup feedback")
    m.video.state = "buffering"
    onVideoStateChanged()
    Harness_Ok(m.status.text.InStr("Buffering") >= 0, "buffering is visible without a logo")
    m.video.bufferingStatus = { percentage: 42.8 }
    onBufferingStatusChanged()
    Harness_Ok(m.status.text.InStr("42%") >= 0, "platform buffer percentage is displayed")
    Harness_Equal(m.logoFront.clippingRect[2], 385, "artwork fill matches platform percentage")
    m.video.bufferingStatus = { percentage: 140 }
    onBufferingStatusChanged()
    Harness_Ok(m.status.text.InStr("100%") >= 0, "percentage cannot exceed a full buffer")
    m.video.bufferingStatus = { percentage: -20 }
    onBufferingStatusChanged()
    Harness_Ok(m.status.text.InStr("0%") >= 0, "negative percentage is clamped")
    m.video.bufferingStatus = { percentage: "provider-value" }
    onBufferingStatusChanged()
    Harness_Ok(m.status.text.InStr("0%") >= 0, "malformed percentage cannot break playback feedback")
    m.video.bufferingStatus = false
    onBufferingStatusChanged()
    Harness_Ok(m.status.text.InStr("Buffering") >= 0, "non-object buffer notification is harmless")
    m.video.state = "playing"
    m.video.currentAudioTrack = "english-aac"
    m.video.availableAudioTracks = [{Language:"eng",Track:"english-aac",Name:"English AAC"}]
    m.video.audioFormat = "aac"
    onVideoStateChanged()
    Harness_Ok(m.status.text.InStr("Checking English") >= 0,"first video frame keeps audio verification visible")
    for sample = 1 to 3
        m.video.positionInfo = {audio:sample,video:sample}
        onAudioProgressTick()
    end for
    Harness_Equal(m.status.text, "", "rendered English audio clears startup and buffering copy")
    m.video.bufferingStatus = { percentage: 13 }
    onBufferingStatusChanged()
    Harness_Equal(m.status.text, "", "late buffer notification cannot place text over a playing movie")
    m.video.state = "finished"
    onVideoStateChanged()
    Harness_Ok(m.status.text.InStr("Press Back") >= 0, "completed playback has a clear return action")
    m.toastFade = { control: "start" }
    m.toastHideTimer = { control: "start" }
    m.toastGroup = { visible: true, opacity: 0.4 }
    m.bufferingGroup.visible = true
    m.video = invalid
    ResetVideoNode()
    Harness_Equal(m.toastFade.control, "stop", "missing native Video still tears down the toast animation")
    Harness_Equal(m.toastHideTimer.control, "stop", "missing native Video still tears down the toast timer")
    Harness_Ok(not m.toastGroup.visible, "missing native Video leaves no stale toast on return")
    Harness_Ok(not m.bufferingGroup.visible, "missing native Video leaves no stale loading artwork")
    SetupPlayerFixture()
    OnEnter({stream:{url:"https://media.example/selected.mkv"},candidates:[{url:"https://media.example/alternate.mkv"}]})
    OnExit()
    Harness_Equal(m.sourceQueue.Count(),0,"exit releases old candidate URLs")
    Harness_Equal(m.playParams,invalid,"exit releases old title/source metadata")
    Harness_Ok(not m.playbackActive and not m.retryPending,"exit cannot restart an old stream")
end sub

sub Test_PlayerResolutionAndFormatError()
    Harness_Suite("Only fresh segment events can establish adaptive resolution")
    SetupPlayerFixture()
    m.video.state = "playing"
    m.video.streamingSegment = { width: 3840, height: 2160 }
    m.resolvedPlayback.streamFormat = "mp4"
    m.playingSegment = invalid
    onPlaybackFactsChanged()
    onStreamingSegmentChanged(PlayerTest_Event(m.video,{width:3840,height:2160}))
    Harness_Equal(m.playingSegment, invalid, "MP4 never treats an old HLS segment as its own resolution")
    m.resolvedPlayback.streamFormat = "hls"
    onPlaybackFactsChanged()
    Harness_Equal(m.playingSegment, invalid, "a new HLS file cannot inherit cached 4K facts through a codec notification")
    onStreamingSegmentChanged(PlayerTest_Event(m.video,{width:3840,height:2160,hdrModeStr:"hdr10"}))
    Harness_Equal(m.playingSegment.height, 2160, "a fresh adaptive segment establishes UHD")
    Harness_Equal(m.playingSegment.hdrModeStr, "hdr10", "HDR belongs to the fresh segment")
    onStreamingSegmentChanged(PlayerTest_Event(m.video,{width:1920,height:1080}))
    Harness_Equal(m.playingSegment.height, 1080, "an adaptive downgrade is recorded as 1080p")
    onPlaybackFactsChanged()
    Harness_Equal(m.playingSegment.height, 1080, "codec notifications cannot replace fresh HD with the cached native UHD field")
    onStreamingSegmentChanged(PlayerTest_Event(m.video,invalid))
    Harness_Equal(m.playingSegment, invalid, "a segment without dimensions clears the current resolution claim")
    m.video.state = "stopped"
    onStreamingSegmentChanged(PlayerTest_Event(m.video,{width:3840,height:2160}))
    Harness_Equal(m.playingSegment, invalid, "late stopped-playback segment events are ignored")
    m.video.state = "playing"
    m.playbackActive = false
    onStreamingSegmentChanged(PlayerTest_Event(m.video,{width:3840,height:2160}))
    Harness_Equal(m.playingSegment, invalid, "an exited player cannot acquire segment evidence")
    m.playbackActive = true
    m.playArmed = true
    onStreamingSegmentChanged(PlayerTest_Event(m.video,{width:3840,height:2160}))
    Harness_Equal(m.playingSegment, invalid, "old notifications before the deferred handoff cannot establish UHD")
    m.playArmed = false
    m.resolvedPlayback.streamFormat = "dash"
    onStreamingSegmentChanged(PlayerTest_Event(m.video,{width:1280,height:720}))
    Harness_Equal(m.playingSegment.height, 720, "fresh DASH video events remain supported")
    m.video.errorStr = "No playable tracks"
    Harness_Ok(NotPlayableOnDevice(), "format failure at the beginning of a native message is recognized")
end sub
sub ShowToast(message as string)
end sub
function MoreSubtitleCandidates() as boolean
    return false
end function
function SubtitleProviderName(address as string) as string
    return ""
end function
function DeviceLocale() as string
    return "en_US"
end function
function RedactUrl(address as string) as string
    return "[endpoint]"
end function

sub Test_PlayerNativeHandoff()
    Harness_Suite("Actual native content handoff and deferred-play cancellation")
    SetupPlayerFixture()
    m.video.audioSelectionPreferences = invalid
    m.video.seamlessAudioTrackSelection = true
    signedUrl = "https://media.example/movie.mkv?signature=fixture"
    StartPlayback(signedUrl, "mkv")
    Harness_Ok(m.video.mute, "new playback remains muted until English metadata is verified")
    Harness_Equal(m.video.content.url, signedUrl, "exact signed URL reaches native content")
    Harness_Equal(m.video.content.streamFormat, "mkv", "MKV reaches native player without HLS conversion")
    Harness_Equal(m.video.content.playStart, 900.5, "fractional resume position reaches native playStart")
    Harness_Equal(m.video.content.httpCertificatesFile, "common:/certs/ca-bundle.crt", "HTTPS uses the platform trust bundle")
    Harness_Equal(m.video.content.httpSendClientCertificates, false, "documented plural metadata disables device client certificate")
    Harness_Equal(m.video.content.httpHeaders[0], "Authorization:Bearer fixture", "this item's application header reaches native content")
    Harness_Equal(m.video.control, "stop", "old native content is stopped before the new content handoff")
    Harness_Equal(m.contentHandoffs[0].control,"stop","native content is created only after the old source is stopped")
    Harness_Equal(m.contentHandoffs[0].audioTrack,"","stale explicit track is cleared before creating the next content")
    Harness_Ok(m.contentHandoffs[0].seamless = false,"progressive MKV disables a previous HLS seamless preference before handoff")
    Harness_Equal(m.playTimer.control, "start", "deferred playback is scheduled")
    Harness_Ok(m.video.autoplayAfterSeek, "a new movie resets paused voice-seek behavior")
    Harness_Equal(m.video.audioTrack, "", "new playback returns to native audio selection without a stale forced track")
    Harness_Equal(m.video.audioSelectionPreferences.values[0].language[0], "en-US", "native player prefers English when a matching playable track exists")
    Harness_Equal(m.video.audioSelectionPreferences.overrideSystem, true, "app English preference overrides an accidental foreign system preference")
    Harness_Equal(m.video.globalCaptionMode, "Off", "no add-on tracks do not alter Roku caption preference")
    onPlayKickFire()
    Harness_Equal(m.video.control, "play", "timer starts the assigned movie")
    m.video.control = "pause"
    onPlayKickFire()
    Harness_Equal(m.video.control, "pause", "duplicate timer notification cannot resume a user pause")

    firstAgent = m.video.httpAgent.serial
    m.video.audioTrack = "old-movie-track"
    ResetVideoNode()
    Harness_Equal(m.video.audioTrack,"","source reset clears an explicit previous-movie audio selection")
    m.resolvedPlayback = { mode: "direct", streamFormat: "mp4", headers: [] }
    m.playParams = { name: "Next movie", position: "invalid-provider-value" }
    StartPlayback("https://other.example/next.mp4", "mp4")
    Harness_Ok(m.video.httpAgent.serial <> firstAgent, "next item receives a fresh HTTP agent")
    Harness_Equal(m.video.content.httpHeaders.Count(), 0, "previous item authorization is not reused")
    Harness_Equal(m.video.content.playStart, invalid, "malformed resume value cannot break playback")
    Harness_Equal(m.contentHandoffs[1].audioTrack,"","reset followed by a new movie cannot reuse the prior track identifier")
    Harness_Ok(m.video.seamlessAudioTrackSelection = false,"MP4 never enables HLS seamless track selection")
    ResetVideoNode()
    Harness_Equal(m.playTimer.control, "stop", "Back cancels the queued timer")
    Harness_Ok(not m.playArmed, "Back disarms deferred playback")
    onPlayKickFire()
    Harness_Equal(m.video.control, "stop", "a queued fire after Back cannot restart playback")
    Harness_Equal(m.video.content, invalid, "exited movie content is detached")

    m.resolvedPlayback = {mode:"direct",streamFormat:"hls",headers:[]}
    m.video.audioTrack = "previous-track"
    StartPlayback("https://media.example/manifest.m3u8","hls")
    Harness_Ok(m.contentHandoffs[2].seamless = true,"HLS enables supported native seamless selection before content or playback")
    Harness_Equal(m.contentHandoffs[2].audioTrack,"","HLS also starts without an earlier file's explicit track")
    Harness_Equal(m.video.control,"stop","HLS preference configuration does not start the decoder before the play tick")
    ResetVideoNode()
    m.resolvedPlayback = {mode:"direct",streamFormat:"mkv",headers:[]}
    StartPlayback("https://media.example/new.mkv","mkv")
    Harness_Ok(m.contentHandoffs[3].seamless = false,"a new MKV clears the preceding HLS seamless setting")

    SetupPlayerFixture()
    StartPlayback("https://media.example/legacy.m3u8","hls")
    Harness_Ok(not m.video.DoesExist("seamlessAudioTrackSelection"),"a missing native seamless field is not created or written")
end sub

sub Test_PlayerEnglishOnlyAudio()
    Harness_Suite("English-only audio and projector compatibility use actual native track facts")
    SetupPlayerFixture()
    StartPlayback("https://media.example/movie.mkv", "mkv")
    m.video.state = "playing"
    m.video.availableAudioTracks = [{Language:"rus",Track:"r",Name:"Russian AAC"},{Language:"eng",Track:"e",Name:"English AAC"}]
    m.video.currentAudioTrack = "r"
    m.video.audioFormat = "aac"
    onEnglishAudioFactsChanged()
    Harness_Ok(m.video.mute, "AAC in another language is never unmuted")
    Harness_Equal(m.audioGuardTimer.control, "start", "unconfirmed language has a bounded verification wait")
    onEnglishAudioTimeout()
    Harness_Ok(m.audioRecoveryPending, "English alternative queues bounded automatic repair")
    Harness_Equal(m.audioDialog, invalid, "automatic repair needs no manual track dialog")
    Harness_Equal(m.video.audioTrack, "", "track assignment waits for the timer boundary after clearing stale selection")
    onAudioTrackRepair()
    Harness_Equal(m.video.audioTrack, "e", "automatic repair selects a native English dialogue ID")
    Harness_Equal(m.video.seek,900.5,"pre-acceptance track repair preserves the intended resume offset")
    Harness_Ok(m.video.mute, "track change stays muted while selected-track facts update")
    m.video.currentAudioTrack = "e"
    onEnglishAudioFactsChanged()
    Harness_Ok(not m.video.mute, "native English AAC permits provisional sound without assuming mute renders samples")
    Harness_Ok(not m.sourceAccepted,"language and codec metadata alone do not accept playback")
    for sample = 1 to 3
        m.video.positionInfo = {audio:sample,video:sample}
        onAudioProgressTick()
    end for
    Harness_Ok(m.sourceAccepted and m.hasPlayed,"two advancing audio/video intervals accept the source")
    Harness_Equal(m.audioGuardTimer.control, "stop", "rendered audio stops the verification deadline")
    m.video.audioFormat = "eac3"
    onEnglishAudioFactsChanged()
    Harness_Ok(m.video.mute, "actual Dolby codec is blocked even when source label said AAC")
    onEnglishAudioTimeout()
    Harness_Ok(m.status.text.InStr("Audio") >= 0, "explicit incompatible change offers audio control without replacing the movie")
    Harness_Equal(m.audioDialog, invalid, "failed manual choice cannot loop more track dialogs")
    ResetVideoNode()
    Harness_Ok(not m.audioGuardActive, "leaving prevents stale facts from unmuting the next movie")
    Harness_Equal(m.audioGuardTimer.control, "stop", "leaving stops the verification timer")
    SetupPlayerFixture()
    StartPlayback("https://media.example/movie.mkv", "mkv")
    m.video.state = "playing"
    m.video.availableAudioTracks = [{Language:"por",Track:"p",Name:"Portuguese AAC"}]
    m.video.currentAudioTrack = "p"
    m.video.audioFormat = "aac"
    onEnglishAudioTimeout()
    Harness_Ok(m.video.mute and m.audioDialog = invalid, "foreign-only file stays silent and offers no foreign selection")
    Harness_Ok(m.status.text.InStr("Press Back") >= 0, "foreign-only source has a clear exit")
    Harness_Ok(not EnglishAudio_Check([{Language:"",Track:"x",Name:"English AAC"}],"x","aac","projector").verified, "English in a track name cannot replace missing language metadata")
    Harness_Ok(not EnglishAudio_Check(invalid,invalid,"aac","projector").verified, "missing track metadata cannot be called English")
    Harness_Ok(not EnglishAudio_Check([{Language:"eng",Track:"x"}],"x","none","projector").verified, "no-playable-audio is not treated as compatible English")
    Harness_Ok(EnglishAudio_Check([{Language:"en-US",Track:"x"}],"x","eac3","surround").verified, "AX700 mode permits English Dolby audio")
    Harness_Ok(EnglishAudio_IsEnglish("en_GB"), "English language variants are recognized")
    Harness_Ok(not EnglishAudio_Check([{Language:"eng",Track:"x",Name:"Director commentary"}],"x","aac","projector").verified, "English commentary does not substitute for movie dialogue")
    Harness_Ok(not EnglishAudio_IsEnglish("english-title"), "arbitrary words are not English language tags")
    m.video.state = "buffering"
    m.video.availableAudioTracks = [{Language:"eng",Track:"old",Name:"English"}]
    m.video.currentAudioTrack = "old"
    m.video.audioFormat = "aac"
    Harness_Ok(not CurrentEnglishAudioCheck().verified, "stale native facts during startup cannot authorize English audio")
    m.video.state = "stopped"
    Harness_Ok(not CurrentEnglishAudioCheck().verified, "stopped previous-source facts cannot be called current English audio")
end sub

sub Test_PlayerPendingTaskNotifications()
    Harness_Suite("Actual task handlers preserve in-flight answers")
    SetupPlayerFixture()
    task = { id: "fixtureResolve1", result: invalid }
    m.resolveTask = task
    onResolveResult(PlayerTest_Event(task, task.result))
    Harness_Ok(m.resolveTask <> invalid, "empty resolve notification keeps the pending task")
    Harness_Equal(m.reaped, 0, "pending resolver remains observed")
    task.result = { ok: true, url: "https://media.example/movie.mkv", streamFormat: "mkv", mode: "direct", headers: [] }
    onResolveResult(PlayerTest_Event(task, task.result))
    Harness_Equal(m.reaped, 1, "completed resolve task is reaped once")
    Harness_Equal(m.resolveTask, invalid, "completed resolver is cleared")
    Harness_Equal(m.video.content.url, task.result.url, "eventual resolve answer reaches actual StartPlayback")

    task = { id: "fixtureSubtitles2", result: invalid }
    m.subtitleTask = task
    onSubtitleResult(PlayerTest_Event(task, task.result))
    Harness_Ok(m.subtitleTask <> invalid, "empty subtitle notification keeps the pending task")
    Harness_Equal(m.reaped, 1, "pending caption fetch remains observed")
    task.result = { ok: true, subtitles: [], reached: true, status: 200 }
    onSubtitleResult(PlayerTest_Event(task, task.result))
    Harness_Equal(m.reaped, 2, "eventual caption answer is reaped")
    Harness_Equal(m.subtitleTask, invalid, "completed caption task is cleared")
end sub

sub Test_PlayerExplicitFourKPolicy()
    Harness_Suite("Measured 4K-only preference is enforced before native playback")
    for each fixture in [
        {fourKOnly:true,media:{complete:true,tracks:[{kind:1,enabled:true,width:1920,height:1080}]},reject:true},
        {fourKOnly:false,media:{complete:true,tracks:[{kind:1,enabled:true,width:1920,height:1080}]},reject:false},
        {fourKOnly:true,media:{complete:true,tracks:[{kind:1,enabled:true,width:3840,height:1600}]},reject:false},
        {fourKOnly:true,media:{complete:false,reason:"uninspected"},reject:false},
        {fourKOnly:true,media:invalid,reject:false}
    ]
        SetupPlayerFixture()
        ResetSourceProof()
        m.sourceMemoryPending = []
        m.sourceAttemptKey = "quality-fixture"
        selected = {name:"2160p source label",url:"https://media.example/labelled-uhd.mkv"}
        m.playParams = {stream:selected,videoId:"tt0000001",audioMode:"projector",fourKOnly:fixture.fourKOnly,name:"test",position:0}
        m.sourceQueue = [selected,{url:"https://media.example/next-source.mkv"}]
        result = {ok:true,url:selected.url,streamFormat:"mkv",mode:"direct",headers:[],media:fixture.media,audioPolicy:{known:true,compatible:true}}
        task = {id:"qualityResolve",result:result}
        m.resolveTask = task
        onResolveResult(PlayerTest_Event(task,result))
        if fixture.reject
            Harness_Equal(m.video.content,invalid,"mislabeled measured HD never reaches native content in 4K-only mode")
            Harness_Ok(m.retryPending,"measured HD queues the next source automatically")
            Harness_Equal(m.retryTimer.control,"start","quality retry crosses the existing deferred timer")
            Harness_Equal(m.sourceMemoryPending.Count(),0,"quality preference does not record a broken-file or network verdict")
            Harness_Ok(m.resolvedPlayback.audioPolicy.compatible,"4K-only rejection does not mutate the valid audio policy")
            Harness_Ok(m.status.text.InStr("4K") >= 0,"quality-specific retry feedback retains the requested resolution")
        else
            Harness_Equal(m.video.content.url,selected.url,"ordinary HD, cropped UHD and uninspected candidates preserve native handoff")
            Harness_Ok(not m.retryPending,"only known measured lower video under explicit 4K-only causes a quality retry")
        end if
    end for
    SetupPlayerFixture()
    ResetSourceProof()
    m.sourceMemoryPending = []
    m.sourceAttemptKey = "quality-last-fixture"
    m.playParams = {fourKOnly:true,position:0}
    m.sourceQueue = [{url:"https://media.example/last.mkv"}]
    ScheduleNextSource("below-UHD")
    Harness_Ok(m.status.text.InStr("English 4K") >= 0,"exhaustion reports the active 4K preference")
    Harness_Equal(m.sourceMemoryPending.Count(),0,"quality-only exhaustion leaves normal source memory untouched")
end sub

sub Test_PlayerLateSubtitleChoice()
    Harness_Suite("Late provider results preserve native caption choices")
    SetupPlayerFixture()
    StartPlayback("https://media.example/movie.mkv", "mkv")
    m.subtitleTask = { id: "fixtureSubtitles1", result: { ok: true, reached: true, status: 200, subtitles: [
        { url: "https://sub.example/english.srt", lang: "eng", langName: "English" }
        { url: 42, lang: 42 }
        { url: "javascript:invalid", lang: "eng" }
    ] } }
    onSubtitleResult(PlayerTest_Event(m.subtitleTask, m.subtitleTask.result))
    Harness_Equal(m.subtitleTracks.Count(), 1, "malformed and non-HTTP caption entries are omitted")
    Harness_Equal(m.video.content.subtitleTracks.Count(), 1, "only usable captions reach native content")
    Harness_Equal(m.video.subtitleTrack, "https://sub.example/english.srt", "initial default is selected")
    Harness_Equal(m.video.globalCaptionMode, "Off", "initial caption result before first frame preserves global Off")
    m.hasPlayed = true
    m.video.subtitleTrack = "mkv/user-selected-embedded"
    m.video.globalCaptionMode = "Off"
    m.subtitleTask = { id: "fixtureSubtitles2", result: { ok: true, reached: true, status: 200, subtitles: [
        { url: "https://other-sub.example/english.srt", lang: "eng", langName: "English" }
    ] } }
    onSubtitleResult(PlayerTest_Event(m.subtitleTask, m.subtitleTask.result))
    Harness_Equal(m.video.content.subtitleTracks.Count(), 2, "later provider extends the native choices")
    Harness_Equal(m.video.subtitleTrack, "mkv/user-selected-embedded", "late provider does not overwrite native track selection")
    Harness_Equal(m.video.globalCaptionMode, "Off", "late provider does not turn user-disabled captions back on")
end sub

sub Test_PlayerPreplayCaptionPreference()
    Harness_Suite("Pre-play caption tracks preserve every native caption mode")
    for each mode in ["Off", "Instant replay", "On"]
        SetupPlayerFixture()
        m.video.globalCaptionMode = mode
        m.subtitleTracks = [{ url: "https://sub.example/english.srt", lang: "eng", langName: "English" }]
        m.subtitleIndex = 0
        StartPlayback("https://media.example/movie.mkv", "mkv")
        Harness_Equal(m.video.globalCaptionMode, mode, "pre-play track handoff preserves " + mode)
        Harness_Equal(m.video.content.subtitleTracks.Count(), 1, "pre-play caption remains available in native Options for " + mode)
        Harness_Equal(m.video.content.subtitleConfig.TrackName, "https://sub.example/english.srt", "default caption is configured without changing " + mode)
        Harness_Equal(m.video.subtitleTrack, "https://sub.example/english.srt", "native track selector receives the default while preserving " + mode)
    end for
end sub

sub Test_PlayerQueuedPreviousMovie()
    Harness_Suite("Queued previous-movie events cannot claim replacement tasks")
    SetupPlayerFixture()
    StartResolve({ url: "https://media.example/old.mkv" }, "")
    oldResolve = m.resolveTask
    CancelResolve()
    StartResolve({ url: "https://media.example/new.mkv" }, "")
    currentResolve = m.resolveTask
    Harness_Equal(oldResolve.id, "playerResolve1", "first real resolver gets a unique id")
    Harness_Equal(currentResolve.id, "playerResolve2", "new movie cannot reuse old resolver identity")
    oldData = { ok: true, url: "https://media.example/old.mkv", streamFormat: "mkv", mode: "direct", headers: [] }
    onResolveResult(PlayerTest_Event(oldResolve, oldData))
    Harness_Equal(m.resolveTask.id, currentResolve.id, "old movie callback leaves current resolver intact")
    Harness_Equal(m.video.content, invalid, "old movie URL never reaches native playback")
    Harness_Equal(m.reaped, 1, "old callback does not reap the new resolver")
    currentResolve.result = { ok: true, url: "https://media.example/new.mkv", streamFormat: "mkv", mode: "direct", headers: [] }
    onResolveResult(PlayerTest_Event(currentResolve, invalid))
    Harness_Equal(m.resolveTask.id, currentResolve.id, "queued empty snapshot is not replaced by a later task field value")
    onResolveResult(PlayerTest_Event(currentResolve, currentResolve.result))
    Harness_Equal(m.video.content.url, "https://media.example/new.mkv", "only current movie answer starts playback")
    Harness_Equal(m.reapedIds[1], currentResolve.id, "completion reaps the worker that sent it")

    m.subtitleParams = { metaType: "movie", videoId: "new" }
    m.subtitleCandidates = ["https://old-sub.example"]
    m.subtitleCursor = 0
    LaunchSubtitleFetch()
    oldSubtitles = m.subtitleTask
    CancelSubtitles()
    m.subtitleParams = { metaType: "movie", videoId: "new" }
    m.subtitleCandidates = ["https://current-sub.example"]
    m.subtitleCursor = 0
    LaunchSubtitleFetch()
    currentSubtitles = m.subtitleTask
    Harness_Equal(oldSubtitles.id, "playerSubtitles3", "subtitle ids share the monotonic player sequence")
    Harness_Equal(currentSubtitles.id, "playerSubtitles4", "new caption request has a distinct identity")
    oldCaptionData = { ok: true, reached: true, subtitles: [{ url: "https://old-sub.example/old.srt", lang: "eng" }] }
    onSubtitleResult(PlayerTest_Event(oldSubtitles, oldCaptionData))
    Harness_Equal(m.subtitleTask.id, currentSubtitles.id, "old caption event leaves current request intact")
    Harness_Equal(m.subtitleTracks, invalid, "old movie captions are not merged into the new movie")
    Harness_Equal(m.reaped, 3, "old caption callback cannot reap replacement provider")
    onSubtitleResult(PlayerTest_Event(currentSubtitles, { ok: true, reached: true, subtitles: [{ url: "https://current-sub.example/new.srt", lang: "eng" }] }))
    Harness_Equal(m.subtitleTracks.Count(), 1, "current provider contributes exactly its own caption")
    Harness_Equal(m.subtitleTracks[0].url, "https://current-sub.example/new.srt", "new movie keeps only its matching caption")
end sub

sub Test_AutomaticPlayback()
    Harness_Suite("Automatic source recovery and bounded English queue")
    pool = []
    for i = 1 to 20
        pool.Push({url:"https://media.example/" + i.ToStr() + ".mkv",name:"2160p AAC"})
    end for
    pool.Push({url:"https://media.example/stereo.mp4",name:"1080p AAC stereo"})
    pool.Push({url:"https://media.example/stereo.mp4",name:"duplicate"})
    pool.Push({url:"http://media.example/unsafe.mp4"})
    queue = AutoPlayback_Candidates(pool[0], pool)
    Harness_Equal(queue.Count(),17,"queue reserves attempts for a lower-resolution fallback")
    Harness_Equal(queue[16].url,pool[20].url,"1080p stereo survives a large 4K provider list")
    Harness_Equal(queue[0].url,pool[0].url,"selected source stays first")
    Harness_Equal(AutoPlayback_Candidates(invalid,invalid).Count(),0,"empty input is safe")
    Harness_Equal(AutoPlayback_Candidates({url:"https://media.example/Case.mkv"},[{url:"https://media.example/case.mkv"}]).Count(),2,"case-sensitive media paths are distinct")
    SetupPlayerFixture()
    m.sourceQueue = [pool[0],pool[20]]
    m.playParams = {stream:pool[0],position:0,serverAddress:""}
    m.video.position = 12
    m.playArmed = true
    m.audioGuardBlocked = invalid
    ScheduleNextSource("no-audio")
    Harness_Ok(m.retryPending,"silent source schedules retry")
    Harness_Equal(m.launched.Count(),0,"native observer never launches a replacement worker directly")
    Harness_Equal(m.retryTimer.control,"start","retry crosses deferred timer boundary")
    Harness_Equal(m.playParams.position,0,"muted failed attempts do not skip movie beginning")
    Harness_Equal(m.playTimer.control,"stop","pending native play cannot start a rejected source")
    ScheduleNextSource("duplicate-event")
    Harness_Equal(m.launched.Count(),0,"duplicate failure callback does not double advance")
    onAutoSourceRetry()
    Harness_Equal(m.sourceIndex,1,"deferred retry advances once")
    Harness_Equal(m.resolveTask.id,"playerResolve1","deferred retry launches a current resolver")
    Harness_Equal(m.playParams.stream.url,pool[20].url,"retry uses next compatible candidate")
    Harness_Equal(m.startupLimit.control,"start","each attempt has a startup deadline")
    m.sourceAccepted = true
    m.video.position = 120
    ScheduleNextSource("network-error")
    Harness_Equal(m.playParams.position,120,"accepted playback keeps resume point across failures")
    Harness_Ok(not m.retryPending,"exhausted queue does not loop")
    Harness_Equal(m.video.control,"stop","exhausted player releases native playback")
    Harness_Ok(m.status.text.InStr("2 attempts") >= 0,"exhaustion reports bounded outcome")
    m.playbackActive = false
    m.retryPending = true
    onAutoSourceRetry()
    Harness_Equal(m.sourceIndex,1,"Back/exit prevents queued retry")
    Harness_Equal(m.launched.Count(),1,"canceled retry cannot launch another provider request")
    SetupPlayerFixture()
    m.playParams = {stream:{name:"AAC stereo"},audioMode:"projector",name:"test",position:0}
    StartPlayback("https://media.example/audio.mp4","mp4")
    Harness_Equal(m.video.content.audioWhitelist,"en,eng","native language whitelist precedes playback")
    Harness_Ok(not m.video.content.DoesExist("preferredAudioCodec"),"filename AAC hint cannot hide a different English codec")
    m.resolvedPlayback.audioPolicy = {known:true,compatible:true,hasStereoEnglishAac:true}
    StartPlayback("https://media.example/audio.mkv","mkv")
    Harness_Ok(not m.video.content.DoesExist("preferredAudioCodec"),"even inspected AAC never hides other native English audio codecs")
    m.playParams.diagnosticControl = true
    StartPlayback("https://media.example/control.mp4","mp4")
    Harness_Ok(not m.video.content.DoesExist("audioWhitelist"),"public audio control is isolated from movie-language guard")
    m.video.audioFormat = "aac"
    m.video.state = "playing"
    Harness_Ok(CurrentEnglishAudioFacts().verified,"public fixed control has separate native metadata authorization")
    Harness_Ok(not CurrentEnglishAudioCheck().verified,"diagnostic control still requires advancing audio before acceptance")
end sub

sub Test_AudioTrackContinuity()
    Harness_Suite("Previously verified audio survives temporary native metadata gaps")
    SetupPlayerFixture()
    m.sourceAccepted = true
    m.lastEnglishTrack = "EnglishTrack"
    m.video.state = "playing"
    m.video.availableAudioTracks = []
    m.video.currentAudioTrack = "EnglishTrack"
    m.video.audioFormat = "aac"
    Harness_Ok(CurrentEnglishAudioCheck().verified,"same verified track keeps sound across temporary metadata gaps")
    m.video.currentAudioTrack = "DifferentTrack"
    Harness_Ok(not CurrentEnglishAudioCheck().verified,"changed track never inherits English confirmation")
    m.video.currentAudioTrack = "EnglishTrack"
    m.video.availableAudioTracks = [{Track:"EnglishTrack",Language:"por"}]
    Harness_Ok(not CurrentEnglishAudioCheck().verified,"explicit foreign language overrides earlier confirmation")
    m.video.availableAudioTracks = []
    m.video.audioFormat = "none"
    Harness_Ok(not CurrentEnglishAudioCheck().verified,"actual audio decoder failure cannot be hidden by continuity")
end sub
