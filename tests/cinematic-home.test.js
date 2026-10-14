// Execute the actual home worker, rendering coordinator and shortcuts.
// Network, SceneGraph content nodes and monotonic clock are boundary doubles.
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..'),read=f=>fs.readFileSync(path.join(root,f),'utf8');
const dir=path.join(root,'out-test/cinematic-home');fs.mkdirSync(dir,{recursive:true});
const home=read('components/HomeScreen.brs').replace(/^sub init\([^]*?^end sub\s*/mi,'').replace(/CreateObject\("roSGNode",\s*"ContentNode"\)/g,'CinemaContent()');
const cinema=read('components/HomeCinema.brs').replace(/CreateObject\("roSGNode",\s*"ContentNode"\)/g,'CinemaContent()');
const worker=read('components/HomeCatalogsTask.brs').replace(/^sub init\([^]*?^end sub\s*/mi,'');
const ready=/^sub ReadySources\([^]*?^end sub/mi.exec(read('components/DiscoverScreen.brs'))[0].replace('sub ReadySources()','sub DiscoveryReadySources()');
const file=path.join(dir,'tests.brs');
fs.writeFileSync(file,[read('tests/harness.brs'),read('source/core/Theme.bs'),read('source/core/TileSize.bs'),read('source/util/HomeCatalogPolicy.brs'),read('source/util/TimerGuard.brs').replace('CreateObject("roTimespan")','CinemaClock()'),home,cinema,worker,ready,read('tests/cinematic-home.test.brs')].join('\n'));
const run=spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',dir,file],{cwd:root,encoding:'utf8'});
process.stdout.write(run.stdout||'');process.stderr.write(run.stderr||'');
process.exitCode=run.status===0&&!(run.stderr||'').trim()&&/RESULT: PASS/.test(run.stdout||'')?0:1;
