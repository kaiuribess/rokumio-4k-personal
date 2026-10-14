const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..');
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const method=(file,name)=>new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi').exec(read(file))[0];
const methods=[
  method('components/DetailsScreen.brs','ToggleLibrary'),
  method('components/DetailsScreen.brs','LibraryActionLabel'),
  method('components/DetailsScreen.brs','OpenEpisodes'),
  method('out-test/source/stores/LibraryStore.brs','__LibraryStore_method_AddSaved'),
  method('out-test/source/stores/LibraryStore.brs','__LibraryStore_method_HasKey'),
  method('out-test/source/stores/LibraryStore.brs','__LibraryStore_method_SafeProviderKey'),
  method('components/LibraryScreen.brs','OnEnter').replace('OnEnter(', 'LibraryOnEnter(').replace('SetChips()','LibrarySetChips()').replace('BuildRows()','LibraryBuildRows()'),
  method('components/LibraryScreen.brs','onResultSelected').replace('onResultSelected(', 'LibrarySelect('),
  method('components/EpisodesScreen.brs','LoadSeries').replace('LoadSeries()', 'EpisodeLoadSeries()').replace('CancelLoad()', 'CancelEpisodeLoad()').replace('CreateObject("roSGNode", "ContentNode")','{}'),
  method('components/EpisodesScreen.brs','onSeriesLoaded')
];
const fixture=`
sub LibrarySetChips()
end sub
sub LibraryBuildRows()
  m.items=[]
  for each key in m.stores.library.data.saved
    m.items.Push(m.stores.library.data.saved[key])
  end for
end sub
sub CancelEpisodeLoad()
end sub
sub SetEpisodeHelp(value as string)
  m.help=value
end sub
function AsyncTask_Launch(parent as object,kind as string,callback as string,fields as object,id as string) as object
  fields.id=id
  return fields
end function
sub AsyncTask_Reap(task as object,parent as object,doStop as boolean)
end sub
function AuditEvent(task as object) as object
  return {task:task,GetRoSGNode:function() as object
    return m.task
  end function}
end function
Harness_Suite("Saved custom series restores its metadata provider")
data={saved:{},savedOrder:[],sessionType:"guest",AddSaved:__LibraryStore_method_AddSaved,HasKey:__LibraryStore_method_HasKey,SafeProviderKey:__LibraryStore_method_SafeProviderKey,
  ReSeedPositionFromAccount:sub(id as string)
  end sub,
  Save:sub()
    m.serialized=FormatJson(m.saved)
  end sub}
host={data:data,callFunc:function(name as string,a=invalid as dynamic,b=invalid as dynamic,c=invalid as dynamic,d=invalid as dynamic,e=invalid as dynamic,f=invalid as dynamic) as dynamic
  if name="LibraryIsSaved" then return m.data.saved.DoesExist(a)
  if name="LibraryAddSaved" then return m.data.AddSaved(a,b,c,d,e,f)
  if name="LibrarySessionType" then return "guest"
  return invalid
end function}
m.stores={library:host,addons:{records:[{id:"com.linvo.cinemeta",address:"https://v3-cinemeta.strem.io",resources:["meta"],types:["series","movie"]},{id:"custom.meta",address:"https://custom-provider.example.test/private/config",resources:["meta"],types:["series"],idPrefixes:["example:"]}],callFunc:function(name as string,a=invalid as dynamic,b=invalid as dynamic,c=invalid as dynamic,d=invalid as dynamic,e=invalid as dynamic,f=invalid as dynamic) as dynamic
  if name="AddonsGetAll" then return m.records
  if name="AddonsGet" then return m.records[0]
  if name="AddonsSupportsResource"
    if c=invalid then return true
    return f.Left(8)="example:" and c[0]="example:"
  end if
  return invalid
end function}}

m.top={}:m.meta={id:"example:series:abc",type:"series",name:"Example provider-only series",poster:"",posterShape:""}
m.addonAddress="https://custom-provider.example.test/private/config":m.chips=[]
ToggleLibrary()
Harness_Ok(data.saved.DoesExist("example:series:abc"),"actual Details producer and LibraryStore save the custom series")
saved=ParseJson(data.serialized)["example:series:abc"]
Harness_Equal(saved.metadataProviderKey,String(64,"a"),"saved record keeps opaque metadata provider key")
Harness_Ok(data.serialized.InStr("https://")<0 and data.serialized.InStr("private/config")<0,"configured provider URL is not persisted in library")
m.chunk=5:m.grid={rowItemSelected:[0,0],SetFocus:sub(value as boolean)
end sub}
m.filterBar={callFunc:function(name as string) as boolean
  return false
end function}
LibraryOnEnter(invalid)
LibrarySelect()
request=m.top.pushRequest
Harness_Equal(request.params.meta.id,"example:series:abc","saved tile retains the provider-specific identifier")
Harness_Equal(request.params.addonAddress,"https://custom-provider.example.test/private/config","My list restores the originating provider")
m.meta=request.params.meta:m.addonAddress=request.params.addonAddress:m.resume=invalid
OpenEpisodes()
Harness_Equal(m.top.pushRequest.params.addonAddress,"https://custom-provider.example.test/private/config","episode handoff preserves restored metadata provider")
m.epList={}:m.epHeaderLine={}:m.epDesc={}:m.seriesTaskSequence=0
EpisodeLoadSeries()
Harness_Equal(m.loadTask.addonAddress,"https://custom-provider.example.test/private/config","episode loader requests original provider")
Harness_Equal(MetadataOrigin_Address(m.stores,invalid,"series","example:series:abc"),"https://custom-provider.example.test/private/config","legacy/account record resolves matching custom metadata provider")
m.stores.addons.records[1].address="https://custom-provider.example.test/rotated/config"
Harness_Equal(MetadataOrigin_Address(m.stores,saved.metadataProviderKey,"series","example:series:abc"),"https://custom-provider.example.test/rotated/config","configured path changes preserve origin identity")
Harness_Equal(data.SafeProviderKey("https://private.example.test/key"),"","unsafe origin value is rejected")
m.stores.addons.records.Unshift({id:"generic.meta",address:"https://generic.example.test",resources:["meta"],types:["series"]})
Harness_Equal(MetadataOrigin_Address(m.stores,invalid,"series","example:series:abc"),"https://custom-provider.example.test/rotated/config","specific custom prefix wins over generic metadata provider")
Harness_Equal(MetadataOrigin_PrefixLength({idPrefixes:["example:"],resources:[{name:"meta",idPrefixes:["example:series:"]}]},"example:series:abc"),15,"resource-specific prefix determines restoration rank")
Harness_Finish()
if m.failed>0 then bad=invalid:ignored=bad.assertion
`;
const staging=path.join(root,'out-test','library-origin');fs.mkdirSync(staging,{recursive:true});
const file=path.join(staging,'tests.brs');
fs.writeFileSync(file,[read('tests/harness.brs'),read('source/util/ProviderPriority.brs'),read('source/util/MetadataOrigin.brs').replaceAll('ProviderPriority_Key(addon)','ProviderPriority_Key(addon,OriginTestHash)'),...methods,`function OriginTestHash(identity as string) as string\n if identity.InStr("custom.meta")>=0 then return String(64,"a")\n return String(64,"b")\nend function`,fixture].join('\n'),'utf8');
const run=spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',staging,file],{cwd:staging,encoding:'utf8'});
process.stdout.write(run.stdout||'');process.stderr.write(run.stderr||'');process.exitCode=run.status===0 && !(run.stderr||'').trim() && /RESULT: PASS/.test(run.stdout||'') ? 0 : 1;
