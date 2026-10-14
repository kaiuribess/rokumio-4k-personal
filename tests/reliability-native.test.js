// Script native I/O boundaries, execute the actual acquisition/retry/budget code.
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..'),dir=path.join(root,'out-test/reliability-native');
fs.mkdirSync(dir,{recursive:true});
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const transport=read('out-test/source/stores/Transport.brs');
const factory=/^function CreateSyncHttpClient\([^]*?^end function/mi.exec(transport)[0]
    .replace('CreateSyncHttpClient','AcquisitionClient').replaceAll('CreateObject(','AcquisitionObject(')
    .replace(/\bWait\(/g,'AcquisitionWait(').replace('Type(event) = "roUrlEvent"','AcquisitionEventType(event) = "roUrlEvent"')
    .replaceAll('ReadAsciiFile(','AcquisitionRead(').replaceAll('WriteAsciiFile(','AcquisitionWrite(');
const registry=read('out-test/source/stores/RegistryIO.brs').replaceAll('CreateObject(','RegistryBoundaryObject(');
const ioFile=path.join(dir,'RegistryIO.brs');fs.writeFileSync(ioFile,registry);
const file=path.join(dir,'tests.brs');fs.writeFileSync(file,[read('tests/harness.brs'),read('tests/mocks.brs'),factory,read('tests/reliability-native.test.brs')].join('\n'));
const result=spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',dir,path.join(root,'out-test/source/bslib.brs'),path.join(root,'out-test/source/stores/Transport.brs'),ioFile,file],{cwd:root,encoding:'utf8'});
process.stdout.write(result.stdout||'');process.stderr.write(result.stderr||'');
process.exitCode=result.status===0&&!(result.stderr||'').trim()&&/RESULT: PASS/.test(result.stdout||'')?0:1;
