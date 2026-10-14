// Saved settings, real modal callbacks and the actual source-to-player handoff.
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const {ProgramBuilder}=require('brighterscript');
const root=path.resolve(__dirname,'..'),dir=path.join(root,'out-test/playback-options');
const read=file=>fs.readFileSync(path.join(root,file),'utf8');
function extract(file,names){return names.map(name=>{
 const found=new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi').exec(read(file));
 if(!found)throw new Error('Missing production callback '+name);return found[0];
}).join('\n');}
async function main(){
 const builder=new ProgramBuilder();await builder.run({project:null,rootDir:root,files:['source/stores/SettingsStore.bs','bslib'],stagingDir:dir,createPackage:false,copyToStaging:true,deploy:false,emitDefinitions:false});
 if(builder.getDiagnostics().some(d=>d.severity===1))throw new Error('Settings compilation failed');
 const file=path.join(dir,'tests.brs');
 fs.writeFileSync(file,[read('tests/harness.brs'),read('tests/mocks.brs'),read('source/util/PlaybackPreferences.brs'),read('components/SettingsAudio.brs').replace('CreateObject("roSGNode","StandardMessageDialog")','OptionsDialog()'),extract('components/StreamsScreen.brs',['PushAutomaticPlayer','CurrentAudioMode']),read('tests/playback-options.test.brs')].join('\n'));
 const run=spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',dir,path.join(dir,'source/bslib.brs'),path.join(dir,'source/stores/SettingsStore.brs'),file],{cwd:root,encoding:'utf8'});
 process.stdout.write(run.stdout||'');process.stderr.write(run.stderr||'');
 process.exitCode=run.status===0&&!(run.stderr||'').trim()&&/RESULT: PASS/.test(run.stdout||'')?0:1;
}
main().catch(e=>{process.stderr.write(e.stack+'\n');process.exitCode=1;});
