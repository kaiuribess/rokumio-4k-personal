// Run the production episode batching and cancellation against native doubles.
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..'),read=p=>fs.readFileSync(path.join(root,p),'utf8');
const source=read('components/EpisodesScreen.brs');
const names=['BuildList','CancelEpisodeBuild','BeginEpisodeBuild','onEpisodeBuildTick','RefreshWatchedMarks'];
const methods=names.map(n=>{const m=new RegExp(`^(?:sub|function) ${n}\\([^]*?^end (?:sub|function)`,'mi').exec(source);if(!m)throw Error(n);return m[0].replaceAll('CreateObject(','BatchObject(');});
const dir=path.join(root,'out-test/episodes-batch');fs.mkdirSync(dir,{recursive:true});const file=path.join(dir,'tests.brs');
fs.writeFileSync(file,[read('tests/harness.brs'),...methods,read('tests/episodes-batch.test.brs')].join('\n'));
const r=spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',dir,file],{cwd:dir,encoding:'utf8'});
process.stdout.write(r.stdout||'');process.stderr.write(r.stderr||'');process.exitCode=r.status===0&&!(r.stderr||'').trim()&&/RESULT: PASS/.test(r.stdout||'')?0:1;
