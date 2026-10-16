const { test } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const { once } = require('node:events');
const path = require('node:path');
const lib = require('../scripts/preflight-lib');
const manifest = { id:'fixture',name:'Fixture',types:['movie'],resources:['stream'],catalogs:[] };
const jsonResponse = data => new Response(JSON.stringify(data), { status:200,headers:{'Content-Type':'application/json'} });

test('Configured paths and query survive percent-encoded resource requests', () => {
  const url = lib.manifestAddress('https://example.invalid/private-config/manifest.json?key=private');
  const next = lib.resourceUrl(url,'stream','series','opaque/id:2 3');
  assert.equal(next.pathname, '/private-config/stream/series/opaque%2Fid%3A2%203.json');
  assert.equal(next.search, '?key=private');
  for (const value of ['http://example.invalid/manifest.json','https://user:pass@example.invalid/manifest.json','https://example.invalid/not-manifest','https://example.invalid/manifest.json#key'])
    assert.throws(() => lib.manifestAddress(value));
});
test('Resource object scope matches the native Stremio matcher', () => {
  assert.equal(lib.supports(manifest,'stream','movie','tt0017136'),true);
  assert.equal(lib.supports({...manifest,idPrefixes:[]},'stream','movie','tt0017136'),false);
  assert.equal(lib.supports({...manifest,idPrefixes:['']},'stream','movie','tt0017136'),false);
  assert.equal(lib.supports({...manifest,resources:[{name:'stream'}]},'stream','movie','tt0017136'),false);
  assert.equal(lib.supports({...manifest,idPrefixes:['other'],resources:[{name:'stream',types:['movie']}]},'stream','movie','tt0017136'),true);
});
test('Report includes only counts and fixed labels, never private URLs or headers', async () => {
  const marker = 'PRIVATE-SECRET-MARKER';
  const urls = [];
  const fetcher = async url => {
    urls.push(url.href);
    if (url.pathname.endsWith('manifest.json')) return jsonResponse(manifest);
    return jsonResponse({ streams:[
      {name:'2160p HEVC DDP HDR10',url:'https://example.invalid/' + marker,behaviorHints:{proxyHeaders:{request:{Authorization:marker}}}},
      {name:'1080p',url:'https://example.invalid/hd.mp4'},
      {name:'4K torrent',infoHash:marker}, null, 42] });
  };
  const report = await lib.checkAddon('https://example.invalid/' + marker + '/manifest.json?key=' + marker,fetcher);
  assert.equal(urls.length,2);
  assert.equal(report.streamCounts.candidates,3);
  assert.equal(report.streamCounts.directHttps,2);
  assert.equal(report.streamCounts.fourKLabels,1);
  assert.equal(report.streamCounts.needsRequestHeaders,1);
  assert.ok(!JSON.stringify(report).includes(marker));
  assert.equal(report.hardwarePlayback,'UNVERIFIED');
  assert.equal(report.providerReliability,'UNVERIFIED');
});
test('Invalid installer manifests fail before downstream requests', async () => {
  for (const data of [{}, {...manifest,types:'movie'}, {...manifest,resources:[]}, {...manifest,catalogs:{}}, {...manifest,name:' '}]) {
    let requests = 0;
    const report = await lib.checkAddon('https://example.invalid/manifest.json',async () => { requests++; return jsonResponse(data); });
    assert.equal(requests,1); assert.equal(report.checks[0].status,'FAIL');
  }
});
test('Read-only checker excludes Torrentio placeholders without fetching media resolvers', async () => {
  const calls=[];
  const response={streams:[
    {name:'[TB+] Torrentio\n4k',url:'https://torrentio.strem.fun/resolve/torbox/PRIVATE_KEY/movie.mkv'},
    {name:'[TB download] Torrentio\n4k',url:'https://torrentio.strem.fun/resolve/torbox/PRIVATE_KEY/uncached.mkv'},
    {name:'Torrentio\nTB error',url:'https://torrentio.strem.fun/videos/failed_access_v3.mp4'},
    {name:'1080p',url:'https://example.invalid/hd.mp4'}]};
  const report=await lib.checkAddon('https://example.invalid/manifest.json',async url=>{
    calls.push(url.href);return jsonResponse(calls.length===1 ? manifest : response);
  });
  assert.equal(calls.length,2);
  assert.ok(calls.every(url=>!url.includes('/resolve/')));
  assert.equal(report.streamCounts.directHttps,2);
  assert.equal(report.streamCounts.skippedUncached,1);
  assert.equal(report.streamCounts.skippedProviderStatus,1);
  assert.equal(report.streamCounts.fourKLabels,1);
  assert.ok(!JSON.stringify(report).includes('PRIVATE_KEY'));
  assert.equal(lib.sourceBlockReason({name:'Download Movie 4K',url:'https://example.invalid/file'}),'');
  assert.equal(lib.sourceBlockReason({url:'https://other.invalid/videos/downloading_v3.mp4'}),'');
});
test('Required unsupported catalog extras prevent invalid search requests', async () => {
  const data = {...manifest,resources:['catalog'],catalogs:[{id:'sample',type:'movie',extra:[{name:'search'},{name:'genre',isRequired:true}]}]};
  let requests = 0;
  const report = await lib.checkAddon('https://example.invalid/manifest.json',async () => {requests++; return jsonResponse(data);});
  assert.equal(requests,1); assert.equal(report.checks.find(c => c.name==='Search').status,'INFO');
});
test('Legacy search extras work while configured query remains intact', async () => {
  const data = {...manifest,resources:['catalog'],catalogs:[{id:'legacy/id',type:'movie',extraSupported:['search']}]};
  const urls=[];
  const report = await lib.checkAddon('https://example.invalid/manifest.json?private=1',async url => {
    urls.push(url); return jsonResponse(urls.length===1 ? data : {metas:[{id:'tt0017136',name:'Metropolis'},null]});
  });
  assert.equal(urls[1].pathname,'/catalog/movie/legacy%2Fid/search=Metropolis.json');
  assert.equal(urls[1].search,'?private=1');
  assert.equal(report.checks.find(c=>c.name==='Search').status,'PASS');
});
test('Every redirect is checked before any downgrade request', async () => {
  const visited=[];
  await assert.rejects(lib.readJson('https://example.invalid/start',async url => {
    visited.push(url.href); return new Response(null,{status:302,headers:{Location:'http://example.invalid/cleartext'}});
  }));
  assert.equal(visited.length,1);
  let requests=0;
  await assert.rejects(lib.readJson('https://example.invalid/start',async () => {requests++;return new Response(null,{status:302,headers:{Location:'/loop'}});}));
  assert.equal(requests,6);
});
test('Bounded JSON rejects huge responses and wrong shapes', async () => {
  await assert.rejects(lib.readJson('https://example.invalid/data',async()=>new Response('x'.repeat(2*1024*1024+1))));
  await assert.rejects(lib.readJson('https://example.invalid/data',async()=>jsonResponse([])));
  await assert.rejects(lib.readJson('https://example.invalid/data',async()=>new Response('not-json')));
  const result=await lib.readJson('https://example.invalid/data',async()=>jsonResponse({ok:true}));
  assert.equal(result.ok,true);
});
test('JSON request deadline is overridable and still aborts pending requests', async () => {
  let observedAbort = false;
  await assert.rejects(lib.readJson('https://example.invalid/data', async (_,options) => new Promise((resolve,reject) => {
    options.signal.addEventListener('abort',()=>{observedAbort=true;reject(new Error('Aborted'));},{once:true});
  }),5));
  assert.equal(observedAbort,true);
});
test('Malformed or non-native sources are never counted as native HTTPS', () => {
  for(const stream of [null,{}, {url:'http://example.invalid/file'}, {url:'https://user:pass@example.invalid/file'}, {url:'https://example.invalid/file extra'}, {externalUrl:'https://example.invalid/page'}]) assert.equal(lib.directHttps(stream),false);
  assert.equal(lib.labels({name:'384 kbps stereo'}).fourKLabel,false);
});
test('Selected movie ID is requested while candidate URLs remain in private callback memory', async () => {
  const calls=[];let candidates;
  const report=await lib.checkAddon('https://example.invalid/manifest.json',async url=>{
    calls.push(url.href);
    return jsonResponse(calls.length===1?manifest:{streams:[{name:'2160p',url:'https://media.invalid/PRIVATE_TOKEN.mp4'}]});
  },{movieId:'tt1234567',onStreams:streams=>{candidates=streams;}});
  assert.ok(calls[1].includes('/stream/movie/tt1234567.json'));
  assert.equal(report.diagnosticMovieId,'tt1234567');
  assert.equal(candidates[0].url,'https://media.invalid/PRIVATE_TOKEN.mp4');
  assert.ok(!JSON.stringify(report).includes('PRIVATE_TOKEN'));
});
test('Local browser boundary rejects cross-origin writes and handles bad input privately', async () => {
  const child=spawn(process.execPath,['scripts/preflight-server.js','--no-open'],{cwd:path.resolve(__dirname,'..'),stdio:['ignore','pipe','pipe'],windowsHide:true});
  try {
    const output=await new Promise((resolve,reject)=>{
      let text=''; const timer=setTimeout(()=>reject(new Error('Checker did not start')),5000);
      child.stdout.on('data',chunk=>{text+=chunk;const match=/http:\/\/127\.0\.0\.1:\d+\//.exec(text);if(match){clearTimeout(timer);resolve(match[0]);}});
      child.on('error',reject);
    });
    const origin=new URL(output).origin;
    const pageResponse=await fetch(output);
    const html=await pageResponse.text();
    const digest=require('node:crypto').createHash('sha256').update(/<script>([\s\S]+)<\/script>/.exec(html)[1]).digest('base64');
    assert.ok(pageResponse.headers.get('content-security-policy').includes("script-src 'sha256-"+digest+"'"));
    assert.ok(!pageResponse.headers.get('content-security-policy').includes('unsafe-eval'));
    assert.ok(html.includes('type="password"'));
    new (require('node:vm').Script)(/<script>([\s\S]+)<\/script>/.exec(html)[1]);
    const key=/'X-Check-Key':'([a-f0-9]+)'/.exec(html)[1];
    const request=(headers,body='{}')=>fetch(output+'check',{method:'POST',headers:{'Content-Type':'application/json',...headers},body});
    assert.equal((await request({'Origin':'https://unrelated.invalid','X-Check-Key':key})).status,403);
    assert.equal((await request({'Origin':origin,'X-Check-Key':'wrong'})).status,403);
    const bad=await request({'Origin':origin,'X-Check-Key':key},JSON.stringify({url:'http://invalid/private-secret'}));
    assert.equal(bad.status,400); assert.ok(!(await bad.text()).includes('private-secret'));
    assert.equal((await fetch(output+'other')).status,404);
    const foreignHost=await new Promise((resolve,reject)=>{
      const req=require('node:http').get(output,{headers:{Host:'unrelated.invalid'}},res=>{res.resume();resolve(res.statusCode);});
      req.on('error',reject);
    });
    assert.equal(foreignHost,403);
  } finally { child.kill(); await once(child,'exit'); }
});
