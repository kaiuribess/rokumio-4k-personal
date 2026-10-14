'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {inspectMedia,createReader,classify,safeTrack}=require('../scripts/media-probe');
function box(type,...parts){const data=Buffer.concat(parts),head=Buffer.alloc(8);head.writeUInt32BE(data.length+8);head.write(type,4);return Buffer.concat([head,data]);}
function video(width,height,tier=0){
  const fields=Buffer.alloc(78);fields.writeUInt16BE(1,6);fields.writeUInt16BE(width,24);fields.writeUInt16BE(height,26);
  const hvcc=Buffer.alloc(23);hvcc[0]=1;hvcc[1]=2|(tier<<5);hvcc[12]=150;hvcc[13]=0xf0;hvcc[15]=0xfc;hvcc[16]=0xfd;hvcc[17]=hvcc[18]=0xfa;hvcc[21]=3;
  const hdlr=Buffer.alloc(12);hdlr.write('vide',8);const stsd=Buffer.alloc(8);stsd.writeUInt32BE(1,4);
  return box('trak',box('mdia',box('hdlr',hdlr),box('minf',box('stbl',box('stsd',stsd,box('hvc1',fields,box('hvcC',hvcc)))))));
}
const movie=(width=3840,height=2160,tier=0)=>box('moov',video(width,height,tier));
function ranged(buffer,calls=[]){return async(url,options)=>{
  calls.push({url:String(url),headers:options.headers});
  const match=/^bytes=(\d+)-(\d+)$/.exec(options.headers.Range||'');
  assert.ok(match,'file metadata requests must be bounded ranges');
  const start=Number(match[1]),end=Math.min(Number(match[2]),buffer.length-1);
  return new Response(buffer.subarray(start,end+1),{status:206,headers:{'Content-Range':'bytes '+start+'-'+end+'/'+buffer.length}});
};}
test('actual 4K dimensions are inspected from a late moov without scanning media payload',async()=>{
  const fake=box('mdat',movie(1920,1080));
  const buffer=Buffer.concat([box('ftyp',Buffer.from('isom0000')),fake,movie()]);
  const calls=[],report=await inspectMedia('https://media.invalid/PRIVATE_TOKEN.mp4',{fetchImpl:ranged(buffer,calls)});
  assert.equal(report.status,'ENCODED_2160P_CONFIRMED');assert.equal(report.tracks[0].width,3840);
  assert.equal(report.tracks[0].hevcProfile,'Main 10');assert.equal(report.tracks[0].bitDepth,10);
  assert.ok(report.bytesRead<buffer.length);assert.ok(!JSON.stringify(report).includes('PRIVATE_TOKEN'));
  assert.equal(report.physicalRokuPlayback,'UNVERIFIED');
});
test('a 4K-named 1080 file fails the encoded 2160p check',async()=>{
  const report=await inspectMedia('https://media.invalid/FULL_4K_2160p.mp4',{fetchImpl:ranged(movie(1920,1080))});
  assert.equal(report.status,'NOT_3840x2160');assert.equal(report.tracks[0].height,1080);
});
test('cropped UHD and mixed video tracks have distinct verdicts',()=>{
  assert.equal(classify([{kind:'video',width:3840,height:1600}]).status,'UHD_WIDTH_BELOW_2160');
  assert.equal(classify([{kind:'video',width:3840,height:2160},{kind:'video',width:1920,height:1080}]).status,'MIXED_VIDEO_RESOLUTIONS');
  assert.equal(classify([{kind:'video',width:3840,height:2160},{kind:'video'}]).status,'UNVERIFIED');
  assert.equal(safeTrack({type:'video',width:3840,height:2160,codecId:'V_MPEGH/ISO/HEVC',bitDepth:null,
    hevcConfiguration:{bitDepthLuma:10}}).bitDepth,undefined);
});
test('account resolver URLs are never contacted and private input never enters errors',async()=>{
  for(const url of ['https://torrentio.strem.fun/resolve/torbox/PRIVATE_TOKEN/movie.mkv',
    'https://api.torbox.app/v1/api/torrents/requestdl?token=PRIVATE_TOKEN',
    'https://media.invalid/resolve/PRIVATE_TOKEN/file.mp4']){
    let calls=0;const report=await inspectMedia(url,{fetchImpl:async()=>{calls++;throw new Error('PRIVATE_TOKEN');}});
    assert.equal(calls,0);assert.equal(report.status,'UNVERIFIED');assert.ok(!JSON.stringify(report).includes('PRIVATE_TOKEN'));
  }
});
test('redirects are checked before account routes or cleartext are contacted',async()=>{
  for(const target of ['http://media.invalid/file.mp4','https://torrentio.strem.fun/resolve/torbox/PRIVATE_TOKEN/movie.mkv']){
    let calls=0;const report=await inspectMedia('https://media.invalid/file.mp4',{fetchImpl:async()=>{calls++;return new Response(null,{status:302,headers:{location:target}});}});
    assert.equal(calls,1);assert.equal(report.status,'UNVERIFIED');assert.equal(report.bytesRead,0);
  }
});
test('a server ignoring Range is canceled before a full file is read',async()=>{
  let canceled=false;const body=new ReadableStream({start(c){c.enqueue(new Uint8Array(20));},cancel(){canceled=true;}});
  const report=await inspectMedia('https://media.invalid/movie.mp4',{fetchImpl:async()=>new Response(body,{status:200})});
  assert.equal(report.status,'UNVERIFIED');assert.equal(report.bytesRead,0);assert.ok(canceled);
});
test('invalid and incomplete Content-Range cannot certify encoded dimensions',async()=>{
  for(const response of [
    ()=>new Response(movie(),{status:206,headers:{'Content-Range':'bytes 1-16/1000'}}),
    ()=>new Response(Buffer.alloc(4),{status:206,headers:{'Content-Range':'bytes 0-15/1000'}})]){
    const report=await inspectMedia('https://media.invalid/movie.mp4',{fetchImpl:async()=>response()});
    assert.equal(report.status,'UNVERIFIED');
  }
});
test('oversized moov metadata is rejected before fetching its body',async()=>{
  let calls=0;const head=Buffer.alloc(16);head.writeUInt32BE(3*1024*1024);head.write('moov',4);
  const report=await inspectMedia('https://media.invalid/movie.mp4',{fetchImpl:async()=>{calls++;return new Response(head,{status:206,headers:{'Content-Range':'bytes 0-15/3145728'}});}});
  assert.equal(calls,1);assert.equal(report.status,'UNVERIFIED');assert.equal(report.bytesRead,16);
});
test('private request headers are dropped on an origin-changing redirect',async()=>{
  const calls=[];const reader=createReader(async(url,options)=>{
    calls.push(options.headers);
    if(calls.length===1)return new Response(null,{status:302,headers:{location:'https://cdn.invalid/init.mp4'}});
    return new Response(Buffer.alloc(16),{status:206,headers:{'Content-Range':'bytes 0-15/100'}});
  },{Authorization:'PRIVATE_TOKEN',Cookie:'PRIVATE_TOKEN','User-Agent':'Provider app'});
  await reader.range('https://media.invalid/init.mp4',0,16);
  assert.equal(calls[0].authorization,'PRIVATE_TOKEN');assert.equal(calls[1].authorization,undefined);assert.equal(calls[1].cookie,undefined);
});
test('inspection deadline aborts a pending request and retains no raw error',async()=>{
  let aborted=false;
  const report=await inspectMedia('https://media.invalid/movie.mp4',{timeoutMs:5,fetchImpl:async(_,options)=>new Promise((resolve,reject)=>{
    options.signal.addEventListener('abort',()=>{aborted=true;reject(new Error('PRIVATE_TOKEN'));},{once:true});
  })});
  assert.ok(aborted);assert.equal(report.status,'UNVERIFIED');assert.ok(!JSON.stringify(report).includes('PRIVATE_TOKEN'));
});
test('HLS checks actual initialization metadata and keeps adaptive playback unverified',async()=>{
  const master='#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=20000000,RESOLUTION=3840x2160,CODECS="hvc1"\nuhd.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1"\nhd.m3u8\n';
  const child='#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:6,\nsegment.m4s\n#EXT-X-ENDLIST\n';
  const calls=[];
  const fetchImpl=async(url,options)=>{
    calls.push(new URL(url).pathname);
    if(new URL(url).pathname.endsWith('main.m3u8'))return new Response(master);
    if(new URL(url).pathname.endsWith('uhd.m3u8'))return new Response(child);
    if(new URL(url).pathname.endsWith('init.mp4'))return ranged(movie(3840,2160,1))(url,options);
    throw new Error('Must not download video segment or HD rendition');
  };
  const report=await inspectMedia('https://media.invalid/PRIVATE_TOKEN/main.m3u8',{fetchImpl});
  assert.equal(report.status,'ENCODED_2160P_RENDITION_CONFIRMED');assert.equal(report.playlist.mixed1080And2160,true);
  assert.equal(report.playlist.guaranteed2160Playback,false);assert.equal(report.tracks[0].hevcTier,'High');
  assert.ok(report.rokuEncodingAssessment.includes('not specified'));
  assert.ok(!JSON.stringify(report).includes('PRIVATE_TOKEN'));assert.equal(calls.length,3);
});
test('an encrypted HLS initialization is not fetched or called verified 4K',async()=>{
  let calls=0;
  const report=await inspectMedia('https://media.invalid/main.m3u8',{fetchImpl:async()=>{
    calls++;return new Response('#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:6,\nmovie.m4s\n');
  }});
  assert.equal(calls,1);assert.equal(report.status,'UNVERIFIED');
});
test('unknown container bytes remain unverified instead of trusting the URL',async()=>{
  const report=await inspectMedia('https://media.invalid/PRIVATE_TOKEN',{fetchImpl:ranged(Buffer.alloc(32))});
  assert.equal(report.status,'UNVERIFIED');assert.ok(!JSON.stringify(report).includes('PRIVATE_TOKEN'));
});
