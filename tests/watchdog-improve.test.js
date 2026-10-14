// Runs the production startup/rebuffer handlers, without device or network use.
// Timer semantics: https://developer.roku.com/dev/docs/timer
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const root = path.resolve(__dirname, '..');
const staging = fs.mkdtempSync(path.join(os.tmpdir(), 'rokumio-watchdog-test-'));
try {
    const player = fs.readFileSync(path.join(root, 'components/PlayerScreen.brs'), 'utf8');
    const entryPoints = ['ArmSourceStartupLimit', 'StopSourceStartupLimit',
        'onSourceStartupTimeout', 'onVideoStateChanged', 'onBufferingStatusChanged', 'HasLogo'];
    const production = entryPoints.map(name => {
        const match = new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`, 'mi').exec(player);
        if (!match) throw new Error(`Missing production watchdog handler: ${name}`);
        return match[0];
    }).join('\n');
    const playbackInfo = fs.readFileSync(path.join(root, 'source/util/PlaybackInfo.brs'), 'utf8');
    const resume = /^function PlaybackInfo_ResumeOffset\([^]*?^end function/mi.exec(playbackInfo);
    if (!resume) throw new Error('Missing production resume number validator');
    const fixtures = `
function WatchdogVideo() as object
    return {state:"buffering",mute:false,HasField:function(name as string) as boolean
        return m.DoesExist(name)
    end function}
end function
sub WatchdogSetup()
    m.top = {screenActive:true}
    m.nextEpisodePending = false
    m.hasPlayed = false
    m.video = WatchdogVideo()
    m.playbackActive = true
    m.retryPending = false
    m.audioGuardBlocked = false
    m.audioGuardActive = false
    m.audioGuardArmed = false
    m.sourceAccepted = false
    m.startupLimit = {control:"stop"}
    m.startupLimitArmed = false
    m.audioGuardTimer = {control:"stop"}
    m.playParams = {diagnostic:true}
    m.resolveTask = invalid
    m.playArmed = false
    m.status = {text:"before"}
    m.logoBack = {uri:""}
    m.logoFront = {clippingRect:[0,0,0,506]}
    m.bufferingGroup = {visible:false}
    m.retries = []
end sub
sub ScheduleNextSource(reason as string)
    m.retries.Push(reason)
end sub
sub StopResolvePulse()
end sub
sub HidePlaybackInfo()
end sub
sub ShowPlaybackInfo()
end sub
sub HideBuffering()
    m.bufferingGroup.visible = false
end sub
sub onPlaybackFactsChanged()
end sub
sub onEnglishAudioFactsChanged()
end sub
sub PublishWatchState()
end sub
sub LogVideoError()
end sub
function NotPlayableOnDevice() as boolean
    return false
end function
function PlaybackInfo_ErrorMessage(code as dynamic, category as dynamic, unsupported as dynamic) as string
    return "error"
end function

Harness_Suite("Startup and continuous rebuffer deadlines stay bounded")
WatchdogSetup()
ArmSourceStartupLimit(true)
Harness_Equal(m.startupLimit.control,"start","a fresh attempt starts its deadline")
m.startupLimit.control = "deadline-in-progress"
onVideoStateChanged()
onVideoStateChanged()
Harness_Equal(m.startupLimit.control,"deadline-in-progress","repeated buffering events never restart an armed deadline")
m.video.bufferingStatus = {percentage:13}
onBufferingStatusChanged()
Harness_Equal(m.startupLimit.control,"deadline-in-progress","buffer progress cannot extend the source deadline")
Harness_Ok(m.status.text.InStr("13%") >= 0,"active buffer percentage remains visible")
onSourceStartupTimeout()
Harness_Equal(m.retries.Count(),1,"one deadline failure schedules one replacement source")
Harness_Equal(m.retries[0],"startup-or-buffering-timeout","timeout carries a fixed safe failure category")
Harness_Equal(m.startupLimit.control,"stop","expired deadline is disarmed")
onSourceStartupTimeout()
Harness_Equal(m.retries.Count(),1,"a duplicate or queued fire cannot schedule twice")

Harness_Suite("Pause, accepted playback, finished playback, and Back defeat stale fires")
WatchdogSetup()
ArmSourceStartupLimit(true)
m.video.state = "paused"
onVideoStateChanged()
onSourceStartupTimeout()
Harness_Equal(m.retries.Count(),0,"paused playback cannot be retried by the startup deadline")
Harness_Equal(m.startupLimit.control,"stop","pause cancels its rebuffer deadline")
WatchdogSetup()
ArmSourceStartupLimit(true)
m.sourceAccepted = true
m.video.state = "playing"
onSourceStartupTimeout()
Harness_Equal(m.retries.Count(),0,"a stale fire cannot interrupt accepted playing video")
WatchdogSetup()
ArmSourceStartupLimit(true)
m.playbackActive = false
onSourceStartupTimeout()
Harness_Equal(m.retries.Count(),0,"Back or exit prevents a queued timeout from restarting playback")
m.video.bufferingStatus = {percentage:99}
onBufferingStatusChanged()
Harness_Equal(m.status.text,"before","late buffering updates cannot repaint an exited player")

Harness_Suite("A new continuous rebuffer gets one new deadline")
WatchdogSetup()
m.sourceAccepted = true
onVideoStateChanged()
Harness_Ok(m.startupLimitArmed,"first rebuffer after accepted playback arms the deadline")
m.startupLimit.control = "rebuffer-in-progress"
onVideoStateChanged()
Harness_Equal(m.startupLimit.control,"rebuffer-in-progress","later rebuffer events retain the same deadline")
onSourceStartupTimeout()
Harness_Equal(m.retries.Count(),1,"an accepted stream stalled in buffering still gets automatic recovery")

Harness_Suite("Previous-source stop notifications do not cancel current resolution")
WatchdogSetup()
ArmSourceStartupLimit(true)
m.resolveTask = {id:"currentResolve"}
m.video.state = "stopped"
onVideoStateChanged()
Harness_Ok(m.startupLimitArmed,"stopped native state during current resolution keeps its deadline")
onSourceStartupTimeout()
Harness_Equal(m.retries.Count(),1,"a resolver can still time out while the static Video reports stopped")
WatchdogSetup()
ArmSourceStartupLimit(true)
m.playArmed = true
m.video.state = "stopped"
onVideoStateChanged()
Harness_Ok(m.startupLimitArmed,"a pending native play kick keeps its startup deadline")
WatchdogSetup()
ArmSourceStartupLimit(true)
m.video.state = "stopped"
onVideoStateChanged()
Harness_Ok(not m.startupLimitArmed,"a fully stopped player has no leftover startup timer")

Harness_Suite("Retry overlays cannot be overwritten by old buffering events")
WatchdogSetup()
m.retryPending = true
m.status.text = "Trying another source"
m.video.bufferingStatus = {percentage:13}
onVideoStateChanged()
onBufferingStatusChanged()
Harness_Equal(m.status.text,"Trying another source","queued retry owns its status until the next attempt")
WatchdogSetup()
m.audioGuardBlocked = true
ArmSourceStartupLimit(true)
onSourceStartupTimeout()
Harness_Equal(m.retries.Count(),0,"already rejected audio cannot schedule another timeout failure")

Harness_Suite("Only measured early endings can restart an accepted movie")
WatchdogSetup()
m.sourceAccepted = true
m.video.state = "finished"
m.video.duration = 3600
m.video.position = 0
ArmSourceStartupLimit(true)
onVideoStateChanged()
Harness_Equal(m.retries.Count(),0,"a reset terminal position does not imply an interrupted movie")
Harness_Ok(m.status.text.InStr("Playback finished") >= 0,"reset-position completion retains its finished screen")
Harness_Ok(not m.startupLimitArmed,"completion cancels the deadline")
WatchdogSetup()
m.sourceAccepted = true
m.video.state = "finished"
m.video.duration = 3600
m.video.position = 120
onVideoStateChanged()
Harness_Equal(m.retries[0],"unexpected-end","a measured mid-movie finish still recovers automatically")
WatchdogSetup()
m.video.state = "finished"
onVideoStateChanged()
Harness_Equal(m.retries[0],"ended-before-audio","an unaccepted source finishing early remains a failure")
WatchdogSetup()
m.startupLimit = invalid
ArmSourceStartupLimit(true)
StopSourceStartupLimit()
Harness_Ok(not m.startupLimitArmed,"missing optional timer is safe")
Harness_Finish()
`;
    const combined = path.join(staging, 'watchdog-tests.brs');
    fs.writeFileSync(combined, fs.readFileSync(path.join(__dirname, 'harness.brs'), 'utf8') + '\n' +
        resume[0] + '\n' + production + '\n' + fs.readFileSync(path.join(root,'source/util/NextEpisode.brs'),'utf8') + '\n' + fs.readFileSync(path.join(root,'components/PlayerNextEpisode.brs'),'utf8') + '\n' + fixtures);
    const result = spawnSync(process.execPath, [
        path.join(root, 'node_modules/@rokucommunity/brs/bin/cli.js'), '--root', staging, combined
    ], { cwd: root, encoding: 'utf8' });
    process.stdout.write(result.stdout || '');
    if (result.stderr) process.stderr.write(result.stderr);
    process.exitCode = result.status === 0 && !(result.stderr || '').trim() &&
        /RESULT: PASS/.test(result.stdout || '') ? 0 : 1;
} finally {
    if (path.dirname(path.resolve(staging)) !== path.resolve(os.tmpdir()) ||
        !path.basename(staging).startsWith('rokumio-watchdog-test-')) throw new Error('Unexpected watchdog staging directory');
    fs.rmSync(staging, { recursive: true, force: true });
}
