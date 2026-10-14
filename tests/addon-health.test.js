// Production check policy, progressive controller, worker cancellation and
// explicit audio choices. Native network/SceneGraph boundaries are scripted.
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const root=path.resolve(__dirname,'..');
const read=name=>fs.readFileSync(path.join(root,name),'utf8');
const extract=(file,names)=>names.map(name=>{
 const match=new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi').exec(read(file));
 if(!match) throw new Error('Missing entry point '+name);
 return match[0];
}).join('\n');
const controller=read('components/AddonHealthScreen.brs').replace(/^sub init\([^]*?^end sub\s*/mi,'').replace(/CreateObject\("roSGNode","ContentNode"\)/g,'HealthTestContent()').replace(/CreateObject\("roTimespan"\)/g,'HealthTestClock()');
const worker=extract('components/AddonHealthTask.brs',['checkAddons']).replace('Transport()','HealthTestTransport()');
const audio=read('components/SettingsAudio.brs').replace(/CreateObject\("roSGNode","StandardMessageDialog"\)/g,'HealthTestDialog()');
const scene=extract('components/MainScene.brs',['onAddonsAction']);
const dir=path.join(root,'out-test/addon-health'); fs.mkdirSync(dir,{recursive:true});
const file=path.join(dir,'tests.brs');
fs.writeFileSync(file,[read('tests/harness.brs'),read('tests/mocks.brs'),read('source/util/AddonDiagnostics.brs'),read('source/util/AudioSetup.brs'),controller,worker,audio,scene,read('tests/addon-health.test.brs')].join('\n'));
const run=spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',dir,file],{cwd:root,encoding:'utf8'});
process.stdout.write(run.stdout || ''); process.stderr.write(run.stderr || '');
process.exitCode=run.status===0 && !(run.stderr || '').trim() && /RESULT: PASS/.test(run.stdout || '') ? 0 : 1;
