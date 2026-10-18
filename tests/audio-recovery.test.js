// Production audio handlers, with deterministic native fields and timer fires.
// No network, device access, sleeps, or acoustic-output claim.
const fs = require('fs');
const os = require('os');
const path = require('path');
const {spawnSync} = require('child_process');
const root = path.resolve(__dirname, '..');
const staging = fs.mkdtempSync(path.join(os.tmpdir(), 'rokumio-audio-recovery-'));
try {
  const player = fs.readFileSync(path.join(root, 'components/PlayerScreen.brs'), 'utf8');
  const names = ['StartPlayback','CreateVideo','CustomizeVideoNode','onPlayKickFire',
    'ResetVideoNode','ClearSubtitleTrack','ApplySubtitleIndex','SelectedSubtitleTrack',
    'CurrentContent','CurrentEnglishAudioFacts','CurrentEnglishAudioCheck',
    'onEnglishAudioFactsChanged','onEnglishAudioTimeout','ScheduleNextSource',
    'ShowEnglishAudioChoice','onEnglishAudioChoice','CloseEnglishAudioChoice',
    'onVideoStateChanged','onPlaybackFactsChanged','HasLogo','ArmSourceStartupLimit',
    'StopSourceStartupLimit','NotPlayableOnDevice','SavePosition','PublishWatchState','onAutoSourceRetry','StartResolve','CancelResolve','ResolveOrdinal','NextPlayerWorkerId'];
  const selected = names.map(name => {
    const match = new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`, 'mi').exec(player);
    if (!match) throw new Error(`Missing production audio handler: ${name}`);
    return match[0].replace(/CreateObject\(/gi, 'MockNativeObject(');
  }).join('\n');
  const read = name => fs.readFileSync(path.join(root, name), 'utf8');
  const memory = read('components/PlayerSourceMemory.brs')
    .replace(/SourceMemory_Fingerprint\(/g,'PlayerTest_Fingerprint(')
    .replace(/ProviderPriority_StreamKey\(/g,'PlayerTest_ProviderKey(')
    .replace(/CreateObject\(/gi,'MockNativeObject(');
  const fixtures = `
sub RecoverySetup()
    SetupPlayerFixture()
    m.playParams = {name:"Movie",position:120,videoId:"tt1234567",metaId:"tt1234567",metaType:"movie",audioMode:"projector",diagnostic:false}
    m.video.position = 123
    m.video.duration = 7200
    m.sourceQueue = [{url:"https://example.test/first.mkv"},{url:"https://example.test/next.mkv"}]
    m.sourceProofTimer = {control:"stop"}
    m.sourceMemoryPump = {control:"stop"}
    m.sourceMemoryPending = []
    m.sourceAttemptKey = ""
    ResetSourceProof()
    m.stores = {library:{calls:[],callFunc:function(name as string,a=invalid as dynamic,b=invalid as dynamic,c=invalid as dynamic,d=invalid as dynamic,e=invalid as dynamic,f=invalid as dynamic,g=invalid as dynamic,h=invalid as dynamic,i=invalid as dynamic,j=invalid as dynamic,k=invalid as dynamic) as dynamic
        m.calls.Push(name)
        return false
    end function},watch:{calls:[],callFunc:function(name as string,packet as object) as dynamic
        m.calls.Push(name)
        return invalid
    end function}}
    StartPlayback("https://example.test/first.mkv","mkv")
    m.video.state = "playing"
    m.video.audioFormat = "aac"
    m.video.currentAudioTrack = "english"
    m.video.availableAudioTracks = [{Track:"english",Language:"eng",Name:"English AAC 2.0"}]
end sub
sub RecoveryAccept()
    onEnglishAudioFactsChanged()
    for sample=1 to 3
        m.video.positionInfo = {audio:120+sample,video:120+sample}
        onAudioProgressTick()
    end for
end sub

Harness_Suite("Actual English decoder facts precede provisional sound and rendered acceptance")
RecoverySetup()
onEnglishAudioFactsChanged()
Harness_Ok(not m.video.mute,"English native codec permits provisional sound without a mute/render dependency")
Harness_Ok(not m.sourceAccepted and not m.hasPlayed,"native language and codec alone cannot authorize history or source memory")
m.video.positionInfo = {audio:0,video:123}
onAudioProgressTick()
onAudioProgressTick()
Harness_Ok(not m.sourceAccepted,"moving video with no audio samples remains unaccepted")
m.video.positionInfo = {audio:100,video:1}
onAudioProgressTick()
m.video.positionInfo = {audio:101,video:2}
onAudioProgressTick()
m.video.positionInfo = {audio:102,video:3}
onAudioProgressTick()
Harness_Ok(not m.sourceAccepted,"different audio and video timelines cannot prove coherent startup")
m.video.positionInfo = {audio:100,video:100}
onAudioProgressTick()
onAudioProgressTick()
Harness_Ok(not m.sourceAccepted,"duplicate retained samples cannot prove audio progress")
m.video.positionInfo = {audio:200,video:200}
onAudioProgressTick()
Harness_Equal(m.audioProgressIntervals,0,"a seek jump resets rather than proves progress")
m.video.positionInfo = {audio:201,video:201}
onAudioProgressTick()
Harness_Ok(not m.sourceAccepted,"one fresh audio interval remains insufficient")
m.video.positionInfo = {audio:202,video:202}
onAudioProgressTick()
Harness_Ok(m.sourceAccepted and m.hasPlayed,"two new rendered audio/video intervals accept the source")
Harness_Equal(m.audioProgressTimer.control,"stop","accepted playback stops startup audio monitoring")

Harness_Suite("Muted startup samples cannot change local or linked watch state")
RecoverySetup()
m.video.audioFormat = "none"
m.hasPlayed = true
onEnglishAudioFactsChanged()
SavePosition()
PublishWatchState()
Harness_Equal(m.stores.library.calls.Count(),0,"unaccepted audio testing never calls the watch library")
Harness_Ok(not m.top.DoesExist("watchStateUpdate"),"unaccepted audio testing never publishes linked history")
Harness_Ok(m.video.mute,"an unavailable decoder never enables provisional sound")

Harness_Suite("English dialogue alternatives are actual native IDs and repair only on timer fires")
RecoverySetup()
m.video.currentAudioTrack = "foreign"
m.video.availableAudioTracks = [{Track:"foreign",Language:"por",Name:"AAC 2.0"},{Track:"six",Language:"eng",Name:"AAC 5.1"},{Track:"stereo",Language:"eng",Name:"AAC 2.0"},{Track:"comment",Language:"eng",Name:"Director Commentary AAC 2.0"},{Track:"description",Language:"eng",Name:"AAC 2.0",HasAccessibilityDescription:true}]
onEnglishAudioFactsChanged()
onEnglishAudioTimeout()
Harness_Ok(m.audioRecoveryPending,"wrong default schedules automatic native-track repair")
Harness_Equal(m.video.audioTrack,"","a Video observer never assigns a replacement track immediately")
Harness_Equal(m.audioRecoveryTrack,"stereo","stereo AAC name is only the first attempt ranking hint")
onAudioTrackRepair()
Harness_Equal(m.video.audioTrack,"stereo","the timer selects the supplied English dialogue Track ID")
Harness_Equal(m.video.seek,120,"failed startup track tests retain the initial resume position")
m.video.currentAudioTrack = "stereo"
m.video.audioFormat = "none"
onEnglishAudioFactsChanged()
Harness_Ok(not m.sourceAccepted,"a stereo name does not prove actual decoding")
onEnglishAudioTimeout()
onAudioTrackRepair()
Harness_Equal(m.video.audioTrack,"six","other English native IDs remain attempts instead of inferred channel proofs")
m.video.currentAudioTrack = "six"
onEnglishAudioTimeout()
Harness_Ok(m.retryPending,"failed native English alternatives advance to the next source")
Harness_Equal(m.audioRecoveryTried.Count(),2,"foreign and commentary choices are never attempted")

Harness_Suite("Repair is bounded to four unique English native choices")
RecoverySetup()
m.video.audioFormat = "none"
m.video.currentAudioTrack = "id0"
m.video.availableAudioTracks = []
for index=0 to 7
    m.video.availableAudioTracks.Push({Track:"id"+index.ToStr(),Language:"eng",Name:"English"})
end for
for attempt=1 to 4
    onEnglishAudioTimeout()
    if attempt < 4
        Harness_Ok(m.audioRecoveryPending,"bounded English alternative is queued")
        onAudioTrackRepair()
        m.video.currentAudioTrack = m.video.audioTrack
    end if
end for
Harness_Equal(m.audioRecoveryTried.Count(),4,"only four unique English IDs are attempted per file")
Harness_Ok(m.retryPending,"unrendered audio cannot trap startup forever")
Harness_Equal(m.video.audioTrack,"id3","fifth and later native IDs are not cycled")

Harness_Suite("Pause, Back and a new source defeat queued progress or repair")
RecoverySetup()
onEnglishAudioFactsChanged()
m.video.positionInfo = {audio:121,video:121}
onAudioProgressTick()
m.video.positionInfo = {audio:122,video:122}
onAudioProgressTick()
m.video.state = "paused"
onVideoStateChanged()
onEnglishAudioTimeout()
Harness_Equal(m.audioProgressTimer.control,"stop","pause stops startup progress sampling")
Harness_Equal(m.audioGuardTimer.control,"stop","pause has no stale English timeout")
Harness_Ok(not m.retryPending,"a user pause does not move to another source")
m.video.state = "playing"
onVideoStateChanged()
m.video.positionInfo = {audio:500,video:500}
onAudioProgressTick()
m.video.positionInfo = {audio:501,video:501}
onAudioProgressTick()
Harness_Ok(not m.sourceAccepted,"pre-pause progress is not reused after resume or seek")
m.video.positionInfo = {audio:502,video:502}
onAudioProgressTick()
Harness_Ok(m.sourceAccepted,"fresh resumed audio can be accepted")
RecoverySetup()
m.video.currentAudioTrack = "foreign"
m.video.availableAudioTracks.Push({Track:"foreign",Language:"por",Name:"Foreign"})
onEnglishAudioTimeout()
oldGeneration = m.audioRecoveryGeneration
ResetVideoNode()
onAudioTrackRepair()
onAudioProgressTick()
Harness_Equal(m.video.audioTrack,"","Back clears the old selection and a queued repair cannot select any track")
Harness_Equal(m.audioRecoveryTimer.control,"stop","Back stops the repair timer")
Harness_Equal(m.audioProgressTimer.control,"stop","Back stops the progress timer")
Harness_Ok(m.audioRecoveryGeneration > oldGeneration,"source reset invalidates the prior recovery generation")
StartPlayback("https://example.test/new.mkv","mkv")
onAudioTrackRepair()
Harness_Equal(m.video.audioTrack,"","an old timer cannot select a previous movie's track")

Harness_Suite("Accepted movies preserve source and seek position through temporary native gaps")
RecoverySetup()
m.video.audioTrack = "english"
RecoveryAccept()
m.video.seek = 500
originalChoice = m.video.audioTrack
m.video.state = "buffering"
m.video.audioFormat = "none"
m.video.availableAudioTracks = invalid
m.video.currentAudioTrack = ""
onVideoStateChanged()
onEnglishAudioTimeout()
Harness_Ok(not m.video.mute and not m.retryPending,"buffering metadata gaps do not mute or replace accepted video")
m.video.state = "paused"
onVideoStateChanged()
Harness_Ok(not m.video.mute and not m.retryPending,"pause keeps the previously verified audio choice")
m.video.audioFormat = "unknown"
onEnglishAudioFactsChanged()
Harness_Equal(m.lastEnglishCodec,"aac","an unknown paused codec cannot replace the verified codec provenance")
m.video.state = "playing"
m.video.audioFormat = "none"
onEnglishAudioFactsChanged()
Harness_Ok(m.video.mute,"actual missing decoder while playing cannot be called audible audio")
m.video.audioFormat = "aac"
onEnglishAudioFactsChanged()
Harness_Ok(not m.video.mute,"restored same codec with blank transient track facts restores accepted audio")
Harness_Equal(m.video.audioTrack,originalChoice,"accepted metadata gaps never cycle audio tracks")
Harness_Equal(m.video.seek,500,"accepted metadata gaps never rewind the movie")
Harness_Ok(not m.retryPending and not m.audioRecoveryPending,"accepted metadata gaps never queue source or track changes")
m.video.currentAudioTrack = "changed-id"
m.video.availableAudioTracks = []
onEnglishAudioFactsChanged()
Harness_Ok(m.video.mute,"an explicit changed nonempty ID without language facts is blocked")
m.video.currentAudioTrack = ""
onEnglishAudioFactsChanged()
Harness_Ok(m.video.mute,"blank metadata after explicit rejection cannot inherit old English proof")
m.video.currentAudioTrack = "foreign"
m.video.availableAudioTracks = [{Track:"foreign",Language:"por",Name:"Foreign"}]
onEnglishAudioFactsChanged()
Harness_Ok(m.video.mute and not m.retryPending,"explicit foreign audio is rejected without replacing the accepted movie")
m.video.currentAudioTrack = "english"
m.video.availableAudioTracks = [{Track:"english",Language:"eng",Name:"English AAC"}]
onEnglishAudioFactsChanged()
Harness_Ok(not m.video.mute,"explicitly restored English native metadata clears rejection")

Harness_Suite("Inspected audio, rather than a filename, controls codec filtering and missing-track fallback")
RecoverySetup()
m.playParams.stream = {name:"AAC stereo foreign alternate"}
m.resolvedPlayback.audioPolicy = {known:true,compatible:true,hasStereoEnglishAac:false,englishOnlyAac:false,englishOnlyMp3:true}
StartPlayback("https://example.test/mp3.mkv","mkv")
Harness_Ok(not m.video.content.DoesExist("preferredAudioCodec"),"an AAC filename cannot suppress inspected English MP3")
m.video.state = "playing"
m.video.audioFormat = "mp3"
m.video.availableAudioTracks = []
m.video.currentAudioTrack = ""
onEnglishAudioFactsChanged()
Harness_Ok(CurrentEnglishAudioFacts().verified and not m.sourceAccepted,"strict English MP3 header authorizes provisional audio but still needs progress")
for sample=1 to 3
    m.video.positionInfo = {audio:sample,video:sample}
    onAudioProgressTick()
end for
Harness_Ok(m.sourceAccepted,"missing native IDs can be accepted only with strict inspected English audio and progress")
m.video.audioFormat = "none"
m.video.availableAudioTracks = invalid
onEnglishAudioFactsChanged()
m.video.audioFormat = "mp3"
onEnglishAudioFactsChanged()
Harness_Ok(not m.video.mute,"accepted header-only English audio also survives transient missing native fields")
RecoverySetup()
m.resolvedPlayback.audioPolicy = {known:false,compatible:true,hasStereoEnglishAac:true,englishOnlyAac:true}
StartPlayback("https://example.test/unverified.mkv","mkv")
Harness_Ok(not m.video.content.DoesExist("preferredAudioCodec"),"unknown inspection cannot force a codec even with a malformed hint flag")
m.video.state = "playing"
m.video.availableAudioTracks = []
m.video.currentAudioTrack = ""
Harness_Ok(not CurrentEnglishAudioFacts().verified,"unknown header metadata cannot authorize English fallback")

Harness_Suite("A failed English AAC decoder can recover to the same file's English MP3 or PCM")
RecoverySetup()
m.resolvedPlayback.audioPolicy = {known:true,compatible:true,hasStereoEnglishAac:true,englishOnlyAac:true,englishOnlyMp3:true}
StartPlayback("https://example.test/mixed-audio.mkv","mkv")
Harness_Ok(not m.video.content.DoesExist("preferredAudioCodec"),"inspected stereo AAC cannot hide the same file's alternate codec")
m.video.state = "playing"
m.video.audioFormat = "none"
m.video.currentAudioTrack = "aac-native"
m.video.availableAudioTracks = [{Track:"aac-native",Language:"eng",Name:"English AAC 2.0"},{Track:"mp3-native",Language:"eng",Name:"English MP3 stereo"},{Track:"foreign-native",Language:"por",Name:"MP3 stereo"}]
onEnglishAudioFactsChanged()
onEnglishAudioTimeout()
Harness_Equal(m.audioRecoveryTrack,"mp3-native","failed AAC leaves a supplied English MP3 choice available")
Harness_Ok(m.video.mute and not m.sourceAccepted,"failed AAC stays unaccepted before trying the alternate track")
onAudioTrackRepair()
Harness_Equal(m.video.audioTrack,"mp3-native","repair uses the alternate MP3 native ID without resolving a different movie")
m.video.currentAudioTrack = "mp3-native"
m.video.audioFormat = "mp3"
onEnglishAudioFactsChanged()
Harness_Ok(not m.video.mute and not m.sourceAccepted,"selected English MP3 permits sound but still needs actual rendered progress")
for sample=1 to 3
    m.video.positionInfo = {audio:120+sample,video:120+sample}
    onAudioProgressTick()
end for
Harness_Ok(m.sourceAccepted and not m.retryPending,"rendered English MP3 accepts the same source instead of replacing it")
Harness_Equal(m.sourceIndex,0,"successful alternate audio does not advance the source queue")

RecoverySetup()
m.video.currentAudioTrack = "aac-native"
m.video.audioFormat = "none"
m.video.availableAudioTracks = [{Track:"aac-native",Language:"eng",Name:"English AAC"},{Track:"pcm-native",Language:"eng",Name:"English PCM stereo"}]
onEnglishAudioTimeout()
onAudioTrackRepair()
Harness_Equal(m.video.audioTrack,"pcm-native","published English PCM remains an alternate after AAC fails")
m.video.currentAudioTrack = "pcm-native"
m.video.audioFormat = "pcm"
RecoveryAccept()
Harness_Ok(m.sourceAccepted and not m.retryPending,"native English PCM still requires and passes coherent sample progress")

Harness_Suite("Fresh explicit output capability rejection gates surround audio")
RecoverySetup()
m.playParams.audioMode = "surround"
m.video.availableAudioTracks = [{Track:"stereo",Language:"eng",Name:"AAC 2.0"},{Track:"dolby",Language:"eng",Name:"AC3 5.1"},{Track:"plus",Language:"eng",Name:"EAC3 5.1"}]
surroundChoices = AudioRecovery_Alternatives()
Harness_Equal(surroundChoices[0].id,"plus","AX700 repair first tries a native English DD+ hint")
Harness_Equal(surroundChoices[1].id,"dolby","AX700 repair prefers English Dolby over stereo AAC")
for each plusName in ["DD+ 5.1", "DDP5.1", "Dolby Digital Plus 5.1", "E-AC-3 5.1"]
    m.video.availableAudioTracks = [{Track:"dolby",Language:"eng",Name:"AC3 5.1"},{Track:"stereo",Language:"eng",Name:"AAC 2.0"},{Track:"plus",Language:"eng",Name:plusName}]
    Harness_Equal(AudioRecovery_Alternatives()[0].id,"plus","DD+ alias " + plusName + " stays ahead of DD and stereo")
end for
m.playParams.audioMode = "projector"
Harness_Equal(AudioRecovery_Alternatives()[0].id,"stereo","projector repair retains AAC stereo preference")
RecoverySetup()
m.playParams.audioMode = "surround"
m.video.audioFormat = "eac3"
m.devicePlaybackInfo = {audioCapabilities:{codecs:{eac3:false}}}
onEnglishAudioFactsChanged()
Harness_Ok(m.video.mute and not m.sourceAccepted,"an explicit receiver rejection cannot be overridden by a surround preset")
Harness_Equal(CurrentEnglishAudioFacts().reason,"receiver-audio-unsupported","receiver rejection has a specific bounded failure reason")
m.devicePlaybackInfo = {audioCapabilities:{codecs:{}}}
onEnglishAudioFactsChanged()
Harness_Ok(not m.video.mute and not m.sourceAccepted,"unknown output facts still require native rendered progress rather than inventing support")
m.devicePlaybackInfo = {audioCapabilities:{codecs:{eac3:true}}}
RecoveryAccept()
Harness_Ok(m.sourceAccepted,"native English Dolby and rendered progress can accept a receiver-compatible candidate")

Harness_Suite("Projector alternatives reach usable MP3/PCM before repeated multichannel AAC")
RecoverySetup()
m.video.currentAudioTrack="failed"
m.video.availableAudioTracks=[{Track:"failed",Language:"eng",Name:"AAC 5.1"},{Track:"aac1",Language:"eng",Name:"AAC 5.1"},{Track:"aac2",Language:"eng",Name:"AAC 5.1"},{Track:"aac3",Language:"eng",Name:"AAC 5.1"},{Track:"mp3",Language:"eng",Name:"MP3 stereo"},{Track:"pcm",Language:"eng",Name:"PCM stereo"}]
choices=AudioRecovery_Alternatives()
Harness_Equal(choices[0].id,"mp3","MP3 is not crowded out by a limited queue of AAC 5.1 attempts")
Harness_Equal(choices[1].id,"pcm","PCM remains ahead of unsupported-looking multichannel AAC")
Harness_Ok(QueueAudioTrackRepair(),"same-file compatible alternative is attempted")
Harness_Equal(m.audioRecoveryTrack,"mp3","repair chooses the stronger projector fallback")
m.audioRecoveryPending=false
m.playParams.audioMode="surround"
m.devicePlaybackInfo={audioCapabilities:{codecs:{eac3:false,ac3:true}}}
m.video.availableAudioTracks=[{Track:"plus",Language:"eng",Name:"English DD+ 5.1"},{Track:"dd",Language:"eng",Name:"English Dolby Digital 5.1"},{Track:"aac",Language:"eng",Name:"English AAC stereo"}]
choices=AudioRecovery_Alternatives()
Harness_Equal(choices[0].id,"dd","receiver explicitly rejecting DD+ prefers supported Dolby")
Harness_Equal(choices[1].id,"aac","stereo fallback stays ahead of explicitly rejected DD+")
m.devicePlaybackInfo={audioCapabilities:{codecs:{}}}
Harness_Equal(AudioRecovery_Alternatives()[0].id,"plus","unknown receiver facts retain DD+ preference without claiming support")


Harness_Suite("Regression: accepted playback must resume its working proof after a pause")
RecoverySetup()
m.saved = false
RecoveryAccept()
Harness_Ok(m.sourceProofArmed,"accepted source starts proof")
m.video.positionInfo={audio:125,video:125}
onSourceProofTick()
m.video.state="paused"
onVideoStateChanged()
onSourceProofTick()
m.video.state="playing"
onVideoStateChanged()
Harness_Ok(m.sourceProofArmed and m.sourceProofTimer.control="start"," resume should rearm incomplete working-source proof")

Harness_Suite("Regression: an interrupted accepted source must preserve resume if replacement fails")
RecoverySetup()
m.saved=false
m.playParams.serverAddress=""
m.playParams.season=0
m.playParams.episode=0
m.playParams.stream=m.sourceQueue[0]
RecoveryAccept()
m.video.position=1800
onPlaybackPositionChanged()
m.video.state="error"
m.video.position=0
ScheduleNextSource("native-playback-error")
Harness_Equal(m.playParams.position,1800,"handoff retains position in volatile params")
onAutoSourceRetry()
Harness_Ok(not m.sourceAccepted,"replacement has not passed startup")
SavePosition()
savedResume=false
for each call in m.stores.library.calls
 if call="LibrarySetPosition" then savedResume=true
end for
Harness_Ok(savedResume," accepted 30-minute progress should survive exiting a failed replacement")

Harness_Finish()
`;
  const code = ['tests/harness.brs','tests/mocks.brs','tests/player-handoff.test.brs',
    'source/util/PlaybackInfo.brs','source/util/ProviderPriority.brs','source/util/MetadataOrigin.brs','source/util/AutoPlayback.brs','source/util/CinemaStreams.brs','source/util/EnglishAudio.brs','source/util/NativeMedia.brs','source/util/AudioCapabilities.brs']
    .map(name => name.endsWith('player-handoff.test.brs') ? read(name).replace(/^sub PublishWatchState\([^]*?^end sub\s*/mi,'') : read(name)).join('\n') + '\n' + selected + '\n' + memory + '\n' +
    read('source/util/TimerGuard.brs').replace(/CreateObject\(/gi,'MockNativeObject(') + '\n' + read('components/PlayerPosition.brs') + '\n' + read('components/PlayerDeliveryInfo.brs') + '\n' + read('components/PlayerAudioRecovery.brs') + '\n' + read('components/PlayerBufferingRecovery.brs').replace(/CreateObject\(/gi,'MockNativeObject(') + '\n' + read('source/util/NextEpisode.brs') + '\n' + read('components/PlayerNextEpisode.brs') + '\n' + fixtures;
  const file = path.join(staging,'audio-tests.brs');
  fs.writeFileSync(file, code);
  const run = spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',staging,file],{cwd:root,encoding:'utf8'});
  process.stdout.write(run.stdout || '');
  process.stderr.write(run.stderr || '');
  process.exitCode = run.status === 0 && !(run.stderr || '').trim() && /RESULT: PASS/.test(run.stdout || '') ? 0 : 1;
} finally {
  const resolved = path.resolve(staging);
  if (path.dirname(resolved) !== path.resolve(os.tmpdir()) || !path.basename(resolved).startsWith('rokumio-audio-recovery-')) throw new Error('Unexpected audio test directory');
  fs.rmSync(resolved,{recursive:true,force:true});
}
