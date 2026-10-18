// Production outcome queue -> worker -> acknowledged registry -> result callback.
// Only native timer/task/registry I/O are injected; no device or media is used.
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const {ProgramBuilder}=require('brighterscript');
const root=path.resolve(__dirname,'..'),dir=path.join(root,'out-test/source-memory-persistence');
const read=file=>fs.readFileSync(path.join(root,file),'utf8');
async function main(){
 const builder=new ProgramBuilder();
 await builder.run({project:null,rootDir:root,files:['source/stores/RegistryIO.bs','bslib'],stagingDir:dir,createPackage:false,copyToStaging:true,deploy:false,emitDefinitions:false});
 if(builder.getDiagnostics().some(d=>d.severity===1))throw new Error('Registry compilation failed');
 const worker=/^sub save\(\)[^]*?^end sub/mi.exec(read('components/SourceMemoryWriteTask.brs'))?.[0];
 if(!worker)throw new Error('Missing production source-memory worker');
 const productionWorker=worker.replace('sub save()','sub MemoryRunWorker()').replace('SourceMemory_Now()','MemoryTestNow()').replace('RegistryIO(CreateObject("roRegistrySection", "playbackMemory"),"playbackMemory")','RegistryIO(m.nativeRegistry,"playbackMemory",MemoryFits)');
 const code=[read('tests/harness.brs'),read('tests/mocks.brs'),read('source/util/SourceMemory.brs'),read('source/util/TimerGuard.brs').replaceAll('CreateObject("roTimespan")','MemoryTestClock()'),read('components/PlayerSourceMemory.brs'),productionWorker,read('tests/source-memory-persistence.test.brs')].join('\n');
 const file=path.join(dir,'tests.brs');fs.writeFileSync(file,code);
 const run=spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',dir,path.join(dir,'source/bslib.brs'),path.join(dir,'source/stores/RegistryIO.brs'),file],{cwd:root,encoding:'utf8'});
 process.stdout.write(run.stdout||'');process.stderr.write(run.stderr||'');
 process.exitCode=run.status===0&&!(run.stderr||'').trim()&&/RESULT: PASS/.test(run.stdout||'')?0:1;
}
main().catch(e=>{process.stderr.write(e.stack+'\n');process.exitCode=1;});
