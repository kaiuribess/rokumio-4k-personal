// Execute the production Details -> Episodes handoff and request lifecycle.
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..'),read=p=>fs.readFileSync(path.join(root,p),'utf8');
const extract=(file,name)=>{const m=new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi').exec(read(file));if(!m)throw Error(name);return m[0].replaceAll('CreateObject(','NavigationObject(');};
const methods=[extract('components/DetailsScreen.brs','OpenEpisodes'),...['OnEnter','LoadSeries','CancelLoad','onSeriesLoaded','OnExit'].map(n=>extract('components/EpisodesScreen.brs',n))];
const dir=path.join(root,'out-test/navigation-flow');fs.mkdirSync(dir,{recursive:true});const file=path.join(dir,'tests.brs');fs.writeFileSync(file,[read('tests/harness.brs'),...methods,read('tests/navigation-flow.test.brs')].join('\n'));
const r=spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',dir,file],{cwd:root,encoding:'utf8'});process.stdout.write(r.stdout||'');process.stderr.write(r.stderr||'');process.exitCode=r.status===0&&!(r.stderr||'').trim()&&/RESULT: PASS/.test(r.stdout||'')?0:1;
