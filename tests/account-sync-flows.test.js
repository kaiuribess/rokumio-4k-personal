const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),dir=path.join(root,'out-test/account-sync-flows');
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const extract=(file,names)=>names.map(name=>{
 const hit=new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi').exec(read(file));assert.ok(hit,name);return hit[0];
}).join('\n');
fs.mkdirSync(dir,{recursive:true});
const host=extract('components/StoreHost.brs',['AddonsReconcileAccount','AddonsGetAll','AuthLoginStremio','AuthLogout','SwitchSession','EffectiveSessionType','RetryPersistence']).replace('function EffectiveSessionType','function HostEffectiveSessionType').replace('sub SwitchSession','sub HostSwitchSession');
const worker=extract('components/AddonSyncTask.brs',['sync']).replace('sub sync()','sub SyncWorker()').replace('Transport()','m.http');
const login=extract('components/LinkStremioTask.brs',['startAuth']).replace('sub startAuth()','sub LoginWorker()').replace('Transport()','m.http').replace('CreateObject("roTimespan")','SyncClock()').replace('Sleep(3000)','SyncSleep()');
const signatures=['HomeScreen','SearchScreen','DiscoverScreen'].map((s,i)=>extract('components/'+s+'.brs',['CatalogSignature']).replace('function CatalogSignature','function Signature'+i));
const search=extract('components/SearchScreen.brs',['EnsureSources','CancelSources']).replace('sub EnsureSources','sub SearchEnsureSources').replace('CatalogSignature()','Signature1()');
const discover=extract('components/DiscoverScreen.brs',['EnsureSources']).replace('sub EnsureSources','sub DiscoverEnsureSources').replace('CatalogSignature()','Signature2()');
const setup=extract('components/SetupImport.brs',['RequestSetupImport','onSetupImportChoice','ExpireSetupImport']).replace('CreateObject("roTimespan")','SyncClock()').replace('CreateObject("roSGNode","StandardMessageDialog")','SyncDialog()');
const addonsUI=extract('components/AddonsScreen.brs',['BuildRows','AddonAdvertises','AddonCapabilityText','onRowSelected','StartInstall']).replace('CreateObject("roSGNode", "ContentNode")','SyncContent()');
const code=[read('tests/harness.brs'),read('tests/mocks.brs'),read('source/util/AccountEpoch.brs'),read('components/AccountWork.brs'),read('components/AccountAddons.brs'),host,worker,login,...signatures,search,discover,setup,addonsUI,
 extract('components/MainScene.brs',['StartAddonSync','onAddonSyncResult','onAddonSyncFinished','ClearAddonSyncFaults','AddAddonSyncFault','onLinkCodeAction','ReconcileSession','EffectiveSessionType','ImportFromSetup','DoLogout','ResetToAuthGate']),read('tests/account-sync-flows.test.brs')].join('\n');
const file=path.join(dir,'flows.brs');fs.writeFileSync(file,code);
const stores=['bslib','stores/Transport','stores/RegistryIO','stores/AuthStore','stores/AddonsStore','stores/LibraryStore','stores/SettingsStore','stores/StremioApiStore','stores/StremioLibraryCodec','stores/WatchedCodec','stores/TimeUtil','stores/VideoIdCodec'].map(s=>path.join(root,'out-test/source',s+'.brs'));
const result=spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',dir,...stores,file],{cwd:root,encoding:'utf8'});
process.stdout.write(result.stdout||'');process.stderr.write(result.stderr||'');
process.exitCode=result.status===0&&!(result.stderr||'').trim()&&/RESULT: PASS/.test(result.stdout||'')?0:1;
