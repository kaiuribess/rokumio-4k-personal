// Execute production timer/native callbacks through the real recovery and
// persistence controller. Only native objects, clock and store I/O are fakes.
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..'),read=file=>fs.readFileSync(path.join(root,file),'utf8');
const screen=read('components/PlayerScreen.brs');
const names=['ScheduleNextSource','onAutoSourceRetry','QueueSourceDiscovery','ArmSourceStartupLimit','StopSourceStartupLimit','SavePosition','PublishWatchState','ResolveOrdinal'];
const production=names.map(name=>{
 const match=new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi').exec(screen);
 if(!match)throw new Error('Missing production function '+name);
 return match[0];
}).join('\n');
const xml=read('components/PlayerScreen.xml');
if(!xml.includes('pkg:/components/PlayerProgressRecovery.brs')||!/<Timer id="progressHealthTick" duration="3" repeat="false"\s*\/>/.test(xml))throw new Error('Progress watchdog production timer/script not wired');
const dir=path.join(root,'out-test/playback-progress');fs.mkdirSync(dir,{recursive:true});
const file=path.join(dir,'tests.brs');
fs.writeFileSync(file,[read('tests/harness.brs'),read('source/util/PlaybackInfo.brs'),read('source/util/CinemaStreams.brs'),read('source/util/AutoPlayback.brs'),read('source/util/MetadataOrigin.brs'),read('source/util/AccountEpoch.brs'),read('source/util/TimerGuard.brs').replaceAll('CreateObject("roTimespan")','ProgressClock()'),read('components/PlayerPosition.brs'),read('components/PlayerProgressRecovery.brs').replaceAll('CreateObject("roTimespan")','ProgressClock()'),production,read('tests/playback-progress.test.brs')].join('\n'));
const run=spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',dir,file],{cwd:root,encoding:'utf8'});
process.stdout.write(run.stdout||'');process.stderr.write(run.stderr||'');
process.exitCode=run.status===0&&!(run.stderr||'').trim()&&/RESULT: PASS/.test(run.stdout||'')?0:1;
