// Execute production coordinator and screen handlers with deterministic task
// completions. No sleeps, network, media access, or device calls.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const extract = (file, name) => {
  const match = new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`, 'mi').exec(read(file));
  assert.ok(match, `${file}: ${name}`);
  return match[0];
};
const coordinatorNames = ['Prepare','Adopt','SetPriority','PrefetchWarmQueue','Suspend','Resume','Snapshot','Cancel','PrefetchClear','PrefetchPump','PrefetchNextQueuedIndex','onPrefetchExpired','onPrefetchLoaded'];
let coordinator = coordinatorNames.map(name => extract('components/SourcePrefetchCoordinator.brs', name)).join('\n').replace(/\bm\./g,'m.prefetchState.');
for (const name of coordinatorNames) coordinator = coordinator.replace(new RegExp(`\\b${name}\\b`, 'g'), `PrefetchTest_${name}`);
const screenNames = ['OnEnter','LoadStreams','LaunchProviderSources','ApplyProviderSources','onSourcePrefetchChanged',
  'CancelStreamsLoad','onStreamsLoaded','RefreshStreams','CurrentAudioMode','EpisodeKey','ParamString','isTaskPending',
  'UpdateStreamsStatus','UpdateProviderStatus','MaybeStartAutomaticPlayback','ProviderRequestState','ResetSourcePagination','ChangeSourcePage','DisableAutomaticForManualBrowse','CancelAutomaticGrace','onAutomaticGrace','SuspendSourceLoading','PumpProviderSources','onKeyEvent','BlurFocus','onStreamSelected','onAutomaticSourcesReady'];
const screen = screenNames.map(name => extract('components/StreamsScreen.brs', name)).join('\n');
const details = ['ScheduleDetailsPrefetch','DetailsPrefetchParams','onDetailsPrefetch','BlurFocus'].map(name => extract('components/DetailsScreen.brs', name)).join('\n').replace(/\bBlurFocus\b/g,'DetailsTest_BlurFocus');
const episodes = ['ScheduleEpisodePrefetch','EpisodePrefetchParams','onEpisodePrefetch','PushEpisode','BlurFocus'].map(name => extract('components/EpisodesScreen.brs', name)).join('\n').replace(/\bBlurFocus\b/g,'EpisodesTest_BlurFocus');
const task = ['SourcePrefetch_LimitStreams','load'].map(name => extract('components/SourcePrefetchTask.brs', name)).join('\n').replace(/\bsub load\(/g,'sub PrefetchTest_Load(').replace('CreateObject("roRegistrySection", "playbackMemory")','PrefetchTest_Registry()');
const normalLoader = extract('components/StreamsLoaderTask.brs', 'load').replace(/\bsub load\(/g,'sub StreamsTest_Load(');
assert.equal((read('components/SourcePrefetchTask.brs').match(/playback\.Streams\(/g)||[]).length,1);
for (const file of ['components/SourcePrefetchTask.brs','components/SourcePrefetchCoordinator.brs','source/util/SourcePrefetch.brs']) {
  assert.doesNotMatch(read(file).replace(/^\s*'.*$/gm,''), /NativeMedia_|MediaProbe|\.Resolve\(|\.Head\(|SavePosition|PublishWatchState|CreateObject\("roVideo|WriteAsciiFile|SourceMemory_Save|SourceMemory_Record|\.Write\(|\.Flush\(|print\s/i, file);
}
assert.match(read('components/SourcePrefetchCoordinator.xml'), /id="revision" type="integer"/);
assert.match(read('components/SourcePrefetchTask.xml'), /id="providerIndex" type="integer"/);
const isolated = path.join(root,'out-test','source-prefetch');
fs.mkdirSync(isolated,{recursive:true});
const file = path.join(isolated,'source-prefetch.brs');
fs.writeFileSync(file,[read('tests/harness.brs'),read('source/util/AccountEpoch.brs'),read('source/util/CinemaStreams.brs') + '\n' + read('source/util/AddonDiagnostics.brs'), read('source/util/PlaybackPreferences.brs'),read('source/util/SourceMemory.brs'),read('source/util/ProviderPriority.brs'),read('source/util/SourcePrefetch.brs').replace('ProviderPriority_Key(addon, hashFn)', 'ProviderPriority_Key(addon, PrefetchTest_PriorityHash)'),coordinator,screen,details,episodes,task,normalLoader,read('tests/source-prefetch.test.brs')].join('\n'));
const result = spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',isolated,file],{cwd:isolated,encoding:'utf8'});
process.stdout.write(result.stdout||''); process.stderr.write(result.stderr||'');
process.exit(result.status===0 && !(result.stderr||'').trim() && /RESULT: PASS/.test(result.stdout||'') ? 0 : 1);
