const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const source = read('components/DiscoverScreen.brs');
const names = ['ReadySources', 'TypeKey', 'CatalogSignature', 'EnsureSources', 'onSourcesLoaded', 'onDiscoverLoaded',
  'NextDiscoverWorkerId', 'DiscoverText', 'DiscoverUsableMetas', 'DiscoverVisibleRows',
  'FetchDiscover', 'DiscoverPageSize', 'DiscoverBoundedCount', 'LoadMore', 'ResetDiscover', 'UpdateGrid', 'AppendRestorePosition',
  'onResultSelected', 'onGridFocused', 'onKeyEvent', 'LandingChipsFocus', 'CancelLoad', 'CancelSources'];
const methods = names.map(name => new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`, 'mi').exec(source)[0]
  .replace(/CreateObject\(/gi, 'MockDiscoverNativeObject('));
const fixtures = read('tests/discover-ui.test.brs').split('Harness_Suite(')[0]
  .replace(/^sub ReadySources\([^]*?^end sub\s*/mi, '');
assert.match(read('components/DiscoverLoaderTask.xml'), /<field id="pageSize" type="integer" value="100"\s*\/>/, 'Native worker must declare its validated page-size field');
const worker = read('components/DiscoverLoaderTask.brs').replace(/^sub init\([^]*?^end sub\s*/mi,'').replace('sub discover()', 'sub DiscoverWorker()');
const cases = `
function Transport() as object
  return m.testHttp
end function
function SelectDefaults() as boolean
  m.selectedCatalog.title = "Selected catalog"
  return true
end function
sub SetChips()
end sub
sub SelectGenreCatalog()
end sub
function GenreOptions() as object
  return []
end function
Harness_Suite("Regression: Discover Home shortcut re-entry")
DiscoverTest_Reset()
FetchDiscover()
onDiscoverLoaded(DiscoverTest_Event(m.loadTask,{ok:true,metas:[{id:"movie1",type:"movie",name:"Movie One"}],hasMore:false}))
Harness_Equal(m.nextPageOffset,1,"first movie catalog consumed one record")
m.entryRequest = {metaType:"series",addonAddress:"https://shows.example",catalogId:"popular"}
ReadySources()
Harness_Equal(m.loadTask.pageOffset,0,"new preset always requests first page")
Harness_Equal(m.nextPageOffset,0,"new preset resets page offset")
onDiscoverLoaded(DiscoverTest_Event(m.loadTask,{ok:true,metas:[{id:"series1",type:"series",name:"Series One"}],hasMore:false}))
Harness_Equal(m.metas[0].id,"series1","valid new response replaces previous titles")
Harness_Equal(m.status.text,"","completed shortcut load clears loading label")
m.grid.rowItemSelected = [0,0]
onResultSelected()
Harness_Equal(m.top.pushRequest.params.addonAddress,"https://shows.example","new series uses requested provider")
Harness_Equal(m.top.pushRequest.params.meta.id,"series1","new series is selected")

Harness_Suite("Regression: short valid catalog pages never paginate")
DiscoverTest_Reset()
FetchDiscover()
rows = []
for i=0 to 9
  rows.Push({id:"movie"+i.ToStr(),type:"movie",name:"Movie"})
end for
onDiscoverLoaded(DiscoverTest_Event(m.loadTask,{ok:true,metas:rows,hasMore:true}))
m.grid.itemFocused=1
onGridFocused()
Harness_Ok(not m.allLoaded,"provider explicitly says more pages exist")
Harness_Ok(m.loadTask <> invalid,"small hasMore page requests next page")
Harness_Equal(m.launched.Count(),2,"short page can advance")

Harness_Suite("Regression: actual CatalogStore and worker lose raw offset")
DiscoverTest_Reset()
raw = []
for i=0 to 99
  if i<10 then raw.Push({name:"Missing id"}) else raw.Push({id:"movie"+i.ToStr(),type:"movie",name:"Movie"})
end for
m.testHttp = {
  response: {ok:true,status:200,json:{metas:raw},error:""}
  Get: function(url as string) as object
    return m.response
  end function
  EndpointUrl: function(base as string,suffix as string) as string
    return base+suffix
  end function
  EncodeQueryValue: function(value as string) as string
    return value
  end function
}
m.top.addonAddress="https://catalog.example":m.top.metaType="movie":m.top.catalogId="top":m.top.genre="":m.top.pageOffset=0
DiscoverWorker()
packet=m.top.result
Harness_Equal(packet.metas.Count(),90,"actual store removes 10 malformed raw records")
Harness_Ok(packet.hasMore,"100 raw records imply another page")
FetchDiscover()
onDiscoverLoaded(DiscoverTest_Event(m.loadTask,packet))
LoadMore()
Harness_Equal(m.loadTask.pageOffset,100,"next skip consumes all raw records including rejected rows")
function CatalogTest_Rows(count as integer, first = 0 as integer) as object
  rows = []
  for index=first to first+count-1
    rows.Push({id:"tt"+(1000000+index).ToStr(),type:"movie",name:"Title "+index.ToStr()})
  end for
  return rows
end function
function CatalogTest_Response(raw as object, more = invalid as dynamic, countBox = "" as string) as object
  task=m.loadTask
  m.testHttp={response:{ok:true,status:200,json:{metas:raw},error:""},lastUrl:"",Get:function(url as string) as object
    m.lastUrl=url
    return m.response
  end function,EndpointUrl:function(base as string,suffix as string) as string
    return base+suffix
  end function,EncodeQueryValue:function(value as string) as string
    return value
  end function}
  if more<>invalid then m.testHttp.response.json.hasMore=more
  for each field in ["addonAddress","metaType","catalogId","genre","pageOffset","pageSize"]
    m.top[field]=task[field]
  end for
  DiscoverWorker()
  response=m.top.result
  if countBox="roInt"
    boxed=CreateObject("roInt"):boxed.SetInt(response.rawCount):response.rawCount=boxed
  else if countBox="roLongInteger"
    boxed=CreateObject("roLongInteger"):boxed.SetLongInt(response.rawCount):response.rawCount=boxed
  end if
  onDiscoverLoaded(DiscoverTest_Event(task,response))
  return response
end function

Harness_Suite("Advertised 20-item page travels through screen, native task fields, store and callback")
DiscoverTest_Reset()
m.selectedCatalog.catalog={pageSize:20}
FetchDiscover()
Harness_Equal(m.loadTask.pageSize,20,"screen sends the manifest page size through task fields")
raw=CatalogTest_Rows(20)
raw[0]={name:"Missing id"}:raw[1]={name:"Missing id"}
answer=CatalogTest_Response(raw)
Harness_Ok(answer.hasMore,"a complete 20-record provider page advertises another page without hasMore")
Harness_Equal(answer.rawCount,20,"worker preserves the unfiltered response count")
Harness_Equal(m.metas.Count(),18,"screen excludes malformed rows without affecting the skip offset")
Harness_Equal(m.nextPageOffset,20,"twenty raw records advance the screen offset by twenty")
LoadMore()
Harness_Ok(m.loadTask<>invalid,"the first twenty-record page is not mistaken for the last page")
if m.loadTask<>invalid
  Harness_Equal(m.loadTask.pageOffset,20,"next task skips twenty provider records")
  Harness_Equal(m.loadTask.pageSize,20,"pagination keeps the provider page-size hint")
  answer=CatalogTest_Response(CatalogTest_Rows(20,20))
  Harness_Ok(m.testHttp.lastUrl.InStr("skip=20")>=0,"actual transport endpoint requests skip=20")
  Harness_Equal(m.metas.Count(),38,"second page appends twenty distinct titles")
  Harness_Equal(m.nextPageOffset,40,"two pages consume forty raw records")
  LoadMore()
  answer=CatalogTest_Response(CatalogTest_Rows(3,40))
  Harness_Ok(m.allLoaded,"short final page stops further pagination")
  Harness_Equal(m.metas.Count(),41,"short final page remains selectable")
  LoadMore()
  Harness_Equal(m.loadTask,invalid,"final page cannot trigger an empty request chain")
end if

Harness_Suite("Explicit final page, empty page and repeated provider page terminate safely")
DiscoverTest_Reset():m.selectedCatalog.catalog={pageSize:20}:FetchDiscover()
answer=CatalogTest_Response(CatalogTest_Rows(20),false)
Harness_Ok(m.allLoaded and not answer.hasMore,"explicit hasMore=false overrides a full advertised page")
LoadMore():Harness_Equal(m.loadTask,invalid,"explicit final page starts no second request")
DiscoverTest_Reset():m.selectedCatalog.catalog={pageSize:20}:FetchDiscover()
answer=CatalogTest_Response(CatalogTest_Rows(20))
LoadMore()
if m.loadTask<>invalid
  answer=CatalogTest_Response([],true)
  Harness_Ok(m.allLoaded,"even hasMore=true cannot make an empty page loop")
  Harness_Equal(m.metas.Count(),20,"empty page preserves existing titles")
end if
DiscoverTest_Reset():m.selectedCatalog.catalog={pageSize:20}:FetchDiscover()
answer=CatalogTest_Response(CatalogTest_Rows(20))
LoadMore()
if m.loadTask<>invalid
  repeated=m.loadTask
  answer=CatalogTest_Response(CatalogTest_Rows(20),true)
  Harness_Ok(m.allLoaded,"provider ignoring skip stops after its first duplicate-only page")
  Harness_Equal(m.metas.Count(),20,"repeated page does not create duplicate poster rows")
  onDiscoverLoaded(DiscoverTest_Event(repeated,answer))
  Harness_Equal(m.nextPageOffset,40,"duplicate callback cannot advance the raw offset twice")
  LoadMore():Harness_Equal(m.loadTask,invalid,"duplicate-only pages cannot launch unbounded follow-up requests")
end if
DiscoverTest_Reset():m.selectedCatalog.catalog={pageSize:20}:FetchDiscover()
answer=CatalogTest_Response(CatalogTest_Rows(20))
LoadMore()
if m.loadTask<>invalid
  malformed=[]
  for index=0 to 19
    malformed.Push({name:"Missing id"})
  end for
  answer=CatalogTest_Response(malformed,true)
  Harness_Equal(m.nextPageOffset,40,"invalid-only page still consumes all raw records")
  Harness_Ok(m.allLoaded,"unusable-only page cannot repeatedly expand requests")
end if

Harness_Suite("Opaque catalog IDs remain case-sensitive across first page and append")
DiscoverTest_Reset():m.selectedCatalog.catalog={pageSize:2}:FetchDiscover()
answer=CatalogTest_Response([{id:"custom:AbC",type:"movie",name:"Upper"},{id:"custom:abc",type:"movie",name:"Lower"}])
Harness_Equal(m.metas.Count(),2,"case-only distinct identifiers both survive first-page normalization")
LoadMore()
if m.loadTask<>invalid
  answer=CatalogTest_Response([{id:"custom:ABC",type:"movie",name:"Caps"},{id:"custom:aBc",type:"movie",name:"Mixed"}])
  Harness_Equal(m.metas.Count(),4,"case-only distinct identifiers append as different catalog entries")
  Harness_Ok(not m.allLoaded,"case-only distinct page is not mistaken for a repeated page")
end if

Harness_Suite("Native boxed counts preserve page hints and raw offsets")
for each wrapper in ["roInt","roLongInteger"]
  boxed=CreateObject(wrapper)
  if wrapper="roInt" then boxed.SetInt(20) else boxed.SetLongInt(20&)
  DiscoverTest_Reset():m.selectedCatalog.catalog={pageSize:boxed}:FetchDiscover()
  Harness_Equal(m.loadTask.pageSize,20,"native boxed page size is converted before entering integer task field")
  raw=CatalogTest_Rows(20):raw[0]={name:"Missing id"}:raw[1]={name:"Missing id"}
  answer=CatalogTest_Response(raw,invalid,wrapper)
  Harness_Ok(answer.hasMore,"boxed page size retains the complete-page inference")
  Harness_Equal(m.nextPageOffset,20,"native boxed raw count includes records removed by the store")
  direct=CatalogStore(m.testHttp).Catalog("https://catalog.example","movie","top","skip=0",boxed)
  Harness_Ok(direct.hasMore,"store also accepts the native boxed page-size value")
end for

Harness_Suite("Malformed page sizes never change the standard bounded fallback")
for each value in [invalid,"20",0,-20,101,1000000,20.5,true,{}]
  DiscoverTest_Reset():m.selectedCatalog.catalog={pageSize:value}:FetchDiscover()
  Harness_Equal(m.loadTask.pageSize,100,"invalid declaration becomes a safe integer field")
  answer=CatalogTest_Response(CatalogTest_Rows(20))
  Harness_Ok(not answer.hasMore,"invalid page size cannot turn a short page into more work")
  direct=CatalogStore(m.testHttp).Catalog("https://catalog.example","movie","top","skip=0",value)
  Harness_Ok(not direct.hasMore,"store independently validates the hint at its own boundary")
end for
DiscoverTest_Reset():m.selectedCatalog.catalog={pageSize:20.0}:FetchDiscover()
Harness_Equal(m.loadTask.pageSize,20,"an integral JSON float remains a valid bounded page size")
answer=CatalogTest_Response(CatalogTest_Rows(20))
Harness_Ok(answer.hasMore,"integral numeric declaration retains the twenty-item behavior")
DiscoverTest_Reset():FetchDiscover()
answer=CatalogTest_Response(CatalogTest_Rows(100))
Harness_Ok(answer.hasMore,"legacy catalogs retain the standard hundred-record inference")
LoadMore():Harness_Equal(m.loadTask.pageOffset,100,"legacy catalog next offset remains one hundred")

Harness_Finish()
if m.failed > 0 then fail=invalid:ignored=fail.assertion
`;
const staging = path.join(root,'out-test','catalog-integration');fs.mkdirSync(staging,{recursive:true});
const file = path.join(staging, 'tests.brs');
fs.writeFileSync(file, [read('tests/harness.brs'), read('source/core/TileSize.bs'), read('out-test/source/stores/CatalogStore.brs'), worker, ...methods, fixtures, cases].join('\n'), 'utf8');
const run = spawnSync(process.execPath, [path.join(root, 'node_modules/@rokucommunity/brs/bin/cli.js'), '--root', staging, file], {cwd:staging,encoding:'utf8'});
process.stdout.write(run.stdout||''); process.stderr.write(run.stderr||'');
process.exitCode=run.status===0 && !(run.stderr||'').trim() && /RESULT: PASS/.test(run.stdout||'') ? 0 : 1;
