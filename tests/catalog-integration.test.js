const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const source = read('components/DiscoverScreen.brs');
const names = ['ReadySources', 'TypeKey', 'CatalogSignature', 'EnsureSources', 'onSourcesLoaded', 'onDiscoverLoaded',
  'NextDiscoverWorkerId', 'DiscoverText', 'DiscoverUsableMetas', 'DiscoverVisibleRows',
  'FetchDiscover', 'LoadMore', 'ResetDiscover', 'UpdateGrid', 'AppendRestorePosition',
  'onResultSelected', 'onGridFocused', 'onKeyEvent', 'LandingChipsFocus', 'CancelLoad', 'CancelSources'];
const methods = names.map(name => new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`, 'mi').exec(source)[0]
  .replace(/CreateObject\(/gi, 'MockDiscoverNativeObject('));
const fixtures = read('tests/discover-ui.test.brs').split('Harness_Suite(')[0]
  .replace(/^sub ReadySources\([^]*?^end sub\s*/mi, '');
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
Harness_Finish()
if m.failed > 0 then fail=invalid:ignored=fail.assertion
`;
const staging = path.join(root,'out-test','catalog-integration');fs.mkdirSync(staging,{recursive:true});
const file = path.join(staging, 'tests.brs');
fs.writeFileSync(file, [read('tests/harness.brs'), read('source/core/TileSize.bs'), read('out-test/source/stores/CatalogStore.brs'), worker, ...methods, fixtures, cases].join('\n'), 'utf8');
const run = spawnSync(process.execPath, [path.join(root, 'node_modules/@rokucommunity/brs/bin/cli.js'), '--root', staging, file], {cwd:staging,encoding:'utf8'});
process.stdout.write(run.stdout||''); process.stderr.write(run.stderr||'');
process.exitCode=run.status===0 && !(run.stderr||'').trim() && /RESULT: PASS/.test(run.stdout||'') ? 0 : 1;
