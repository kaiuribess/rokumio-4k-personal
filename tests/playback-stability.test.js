// Real timer/controller/position logic. Only monotonic time and native task
// services are scripted; no device, movie URL or acoustic test is performed.
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..'), read=file=>fs.readFileSync(path.join(root,file),'utf8');
const functions=['QueueSourceDiscovery','CanRecoverSources','onPlayKickFire','onAutoSourceRetry','ArmSourceStartupLimit','StopSourceStartupLimit','onSourceStartupTimeout','onEnglishAudioTimeout','ScheduleNextSource','onAudioTrackRepair','onVideoStateChanged','onBufferingStatusChanged','HasLogo'];
const production=read('components/PlayerProgressRecovery.brs').replaceAll('CreateObject("roTimespan")','StabilityClock()')+'\n'+functions.map(name=>{
 const match=new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi').exec(read(name==='onAudioTrackRepair'?'components/PlayerAudioRecovery.brs':'components/PlayerScreen.brs'));
 if(!match)throw new Error('Missing production function '+name);
 return match[0];
}).join('\n');
const dir=path.join(root,'out-test/playback-stability');fs.mkdirSync(dir,{recursive:true});
const file=path.join(dir,'tests.brs');
fs.writeFileSync(file,[read('tests/harness.brs'),read('source/util/PlaybackInfo.brs'),read('source/util/EnglishAudio.brs'),read('source/util/CinemaStreams.brs'),read('source/util/AutoPlayback.brs'),read('source/util/TimerGuard.brs').replace('CreateObject("roTimespan")','StabilityClock()'),read('components/PlayerPosition.brs'),read('components/PlayerDeliveryInfo.brs'),read('components/PlayerBufferingRecovery.brs').replace('CreateObject("roTimespan")','StabilityClock()'),production,read('tests/playback-stability.test.brs').replace('Harness_Finish()',''),read('tests/playback-underrun.test.brs')].join('\n'));
const run=spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',dir,file],{cwd:root,encoding:'utf8'});
process.stdout.write(run.stdout||'');process.stderr.write(run.stderr||'');
process.exitCode=run.status===0&&!(run.stderr||'').trim()&&/RESULT: PASS/.test(run.stdout||'')?0:1;
