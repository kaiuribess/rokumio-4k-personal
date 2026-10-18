// Execute production orchestration. Only SG tasks, registry and native timers
// are doubled: no account, provider credential, movie or Roku is contacted.
const fs = require('node:fs'), path = require('node:path');
const {spawnSync} = require('node:child_process');
const {ProgramBuilder} = require('brighterscript');
const root = path.resolve(__dirname, '..'), dir = path.join(root,'out-test/reliability-flows');
const assert = require('node:assert/strict');
assert.match(fs.readFileSync(path.join(root,'components/PlayerScreen.xml'),'utf8'),/<Timer id="localCheckpoint" duration="30" repeat="true"/);
const read = file => fs.readFileSync(path.join(root,file),'utf8');
const extract = (file,names) => names.map(name => {
    const found = new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi').exec(read(file));
    if (!found) throw new Error('Missing production method '+name);
    return found[0];
}).join('\n');
async function main() {
    const builder = new ProgramBuilder();
    await builder.run({project:null,rootDir:root,files:['source/**/*.bs','source/**/*.brs','bslib'],stagingDir:dir,createPackage:false,copyToStaging:true,deploy:false,emitDefinitions:false});
    if (builder.getDiagnostics().some(d=>d.severity===1)) throw new Error('Store compilation failed');
    const code = [read('tests/harness.brs'),read('source/util/AccountEpoch.brs'),read('tests/mocks.brs'),read('components/AccountWork.brs'),read('components/AccountAddons.brs'),
        extract('components/MainScene.brs',['onLibrarySyncResult','onAddonSyncResult','onImportTaskResult','onSourceRecoveryRequest']),
        read('source/util/CinemaStreams.brs'),read('source/util/PlaybackInfo.brs'),read('source/util/AutoPlayback.brs'),
        read('source/util/TimerGuard.brs').replace('CreateObject("roTimespan")','ReliabilityClock()'),read('components/PlayerPosition.brs'),
        extract('components/StoreHost.brs',['LibrarySetPosition']),
        extract('components/PlayerScreen.brs',['SavePosition','PublishWatchState','onLocalCheckpoint','CheckpointTiming_Reset','CheckpointTiming_Start','CheckpointTiming_Finish','CheckpointTiming_Status','QueueSourceDiscovery','CanRecoverSources','onAutoSourceRetry']).replace('CreateObject("roTimespan")','ReliabilityCheckpointClock()'),
        extract('components/StreamsScreen.brs',['PrepareSourceRecovery']),
        // Native digest/time/registry unavailable here; fresh ranking itself is real.
        extract('components/SourceSelectionTask.brs',['choose']).replace('sub choose()','sub ReliabilityChoose()').replace('SourceMemory_Now()','ReliabilityNoMemory()').replace('CreateObject("roRegistrySection", "playbackMemory")','invalid'),
        read('tests/reliability-flows.test.brs')].join('\n');
    const file=path.join(dir,'tests.brs');fs.writeFileSync(file,code);
    const files=['bslib','stores/RegistryIO','stores/Transport','stores/SettingsStore','stores/AuthStore','stores/WatchedCodec','stores/TimeUtil','stores/VideoIdCodec','stores/StremioLibraryCodec','stores/LibraryStore','stores/AddonsStore','stores/SubtitlesStore'].map(f=>path.join(dir,'source',f+'.brs'));
    const result=spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',dir,...files,file],{cwd:root,encoding:'utf8'});
    const diagnostics=(result.stderr||'').split(/\r?\n/).filter(line=>line.trim()&&!/^BRIGHTSCRIPT: ERROR: Runtime: unknown classname "roUrlTransfer": .*Transport\.brs\(\d+\)$/.test(line));
    process.stdout.write(result.stdout||'');if(diagnostics.length)process.stderr.write(diagnostics.join('\n')+'\n');
    process.exitCode=result.status===0&&diagnostics.length===0&&/RESULT: PASS/.test(result.stdout||'')?0:1;
}
main().catch(e=>{process.stderr.write(e.stack+'\n');process.exitCode=1;});
