// Native-player resolution and header handling tests, independent of device UI.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { ProgramBuilder } = require('brighterscript');

async function main() {
    const root = path.resolve(__dirname, '..');
    const staging = fs.mkdtempSync(path.join(os.tmpdir(), 'rokumio-playback-test-'));
    try {
    const builder = new ProgramBuilder();
    await builder.run({ project: null, rootDir: root,
        files: ['source/stores/PlaybackStore.bs', 'source/stores/Transport.bs', 'source/util/PlaybackInfo.brs', 'bslib'],
        stagingDir: staging, createPackage: false, copyToStaging: true,
        deploy: false, emitDefinitions: false, showDiagnosticsInConsole: true });
    if (builder.getDiagnostics().some(d => d.severity === 1)) throw new Error('Native playback test compilation failed');
    const combined = path.join(staging, 'native-tests.brs');
    // Run the real screen handoff/handlers. Replace only Roku's native object
    // factory at the interpreter boundary; no copy of the handoff logic lives
    // in the fixtures, and the production screen still uses native APIs.
    const player = fs.readFileSync(path.join(root, 'components', 'PlayerScreen.brs'), 'utf8');
    const functions = ['StartPlayback', 'CreateVideo', 'CustomizeVideoNode', 'onPlayKickFire',
        'ResetVideoNode', 'ClearSubtitleTrack', 'ApplySubtitleIndex', 'SelectedSubtitleTrack',
        'CurrentContent', 'SelectSubtitleTrack', 'BuildSubtitleTracks',
        'TrackDisplayName', 'onResolveResult', 'onSubtitleResult', 'ClearSubtitles',
        'onPlaybackFactsChanged', 'onStreamingSegmentChanged', 'NotPlayableOnDevice', 'NextPlayerWorkerId',
        'StartResolve', 'CancelResolve', 'LaunchSubtitleFetch', 'CancelSubtitles',
        'OnEnter', 'OnExit', 'SavePosition', 'ResolveOrdinal', 'onVideoStateChanged', 'onBufferingStatusChanged', 'HasLogo',
        'CurrentEnglishAudioFacts', 'CurrentEnglishAudioCheck', 'onEnglishAudioFactsChanged', 'onEnglishAudioTimeout',
        'QueueSourceDiscovery', 'CanRecoverSources', 'ScheduleNextSource', 'onAutoSourceRetry', 'onSourceStartupTimeout', 'ArmSourceStartupLimit', 'StopSourceStartupLimit', 'PlaybackStatus', 'ShowEnglishAudioChoice', 'onEnglishAudioChoice', 'CloseEnglishAudioChoice'];
    const screen = functions.map(name => {
        const match = new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`, 'mi').exec(player);
        if (!match) throw new Error(`Missing PlayerScreen test entry point: ${name}`);
        return match[0].replace(/CreateObject\(/gi, 'MockNativeObject(');
    }).join('\n');
    const memoryScreen = fs.readFileSync(path.join(root,'components/PlayerSourceMemory.brs'),'utf8').replace(/SourceMemory_Fingerprint\(/g,'PlayerTest_Fingerprint(').replace(/ProviderPriority_StreamKey\(/g,'PlayerTest_ProviderKey(').replace(/CreateObject\(/gi,'MockNativeObject(');
    const support = fs.readFileSync(path.join(root,'source/util/TimerGuard.brs'),'utf8').replace(/CreateObject\(/gi,'MockNativeObject(') + '\n' + fs.readFileSync(path.join(root,'components/PlayerPosition.brs'),'utf8');
    const audioRecovery = fs.readFileSync(path.join(root,'components/PlayerAudioRecovery.brs'),'utf8');
    fs.writeFileSync(combined, ['harness.brs', 'mocks.brs', 'player-handoff.test.brs']
        .map(f => fs.readFileSync(path.join(__dirname, f), 'utf8')).join('\n') + '\n' + ['AccountEpoch.brs', 'ProviderPriority.brs', 'MetadataOrigin.brs', 'EnglishAudio.brs', 'AudioCapabilities.brs', 'AutoPlayback.brs', 'CinemaStreams.brs', 'NativeMedia.brs'].map(f => fs.readFileSync(path.join(root, 'source/util', f), 'utf8')).join('\n') + '\n' + screen + '\n' +
        memoryScreen + '\n' + support + '\n' + audioRecovery + '\n' + fs.readFileSync(path.join(root, 'source/util/NextEpisode.brs'), 'utf8') + '\n' + fs.readFileSync(path.join(root, 'components/PlayerNextEpisode.brs'), 'utf8') + '\n' + fs.readFileSync(path.join(__dirname, 'playback-native.test.brs'), 'utf8'));
    const result = spawnSync(process.execPath, [
        path.join(root, 'node_modules', '@rokucommunity', 'brs', 'bin', 'cli.js'),
        '--root', staging, path.join(staging, 'source', 'bslib.brs'),
        path.join(staging, 'source', 'stores', 'Transport.brs'),
        path.join(staging, 'source', 'stores', 'PlaybackStore.brs'),
        path.join(staging, 'source', 'util', 'PlaybackInfo.brs'), combined
    ], { cwd: root, encoding: 'utf8' });
    process.stdout.write(result.stdout || '');
    // roUrlTransfer is unavailable in this interpreter. PercentEncode catches
    // that and exercises its real pure fallback; this one diagnostic is expected.
    const diagnostics = (result.stderr || '').split(/\r?\n/).filter(line =>
        line.trim() && !/^BRIGHTSCRIPT: ERROR: Runtime: unknown classname "roUrlTransfer": .*Transport\.brs\(\d+\)$/.test(line));
    if (diagnostics.length) process.stderr.write(diagnostics.join('\n') + '\n');
    // The interpreter can emit a parse error while returning status zero.
    const passed = result.status === 0 && diagnostics.length === 0 && /RESULT: PASS/.test(result.stdout || '');
    process.exitCode = passed ? 0 : 1;
    } finally {
        const resolved = path.resolve(staging);
        if (path.dirname(resolved) !== path.resolve(os.tmpdir()) || !path.basename(resolved).startsWith('rokumio-playback-test-')) throw new Error('Unexpected test staging directory');
        fs.rmSync(resolved, { recursive: true, force: true });
    }
}
main().catch(error => { console.error(error); process.exit(1); });
