'use strict';
const http=require('node:http');
const crypto=require('node:crypto');
const fs=require('node:fs');
const path=require('node:path');
const {checkAddon,labels,readJson}=require('./preflight-lib');
const {inspectMedia}=require('./media-probe');
const secret=crypto.randomBytes(24).toString('hex');
const page=fs.readFileSync(path.join(__dirname,'source-checker.html'),'utf8').replace('__CHECK_KEY__',secret);
const scriptHash=crypto.createHash('sha256').update(/<script>([\s\S]+)<\/script>/.exec(page)[1]).digest('base64');
const csp="default-src 'none'; script-src 'sha256-"+scriptHash+"'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'";
const PUBLIC_SAMPLE='https://test.playready.microsoft.com/media/profficialsite/tearsofsteel_4k_60s_24fps.12000kbps.3840x2160.h265-10b.2ch.128kbps.aac.mp4';
const PUBLIC_ADAPTIVE='https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8';
const PUBLIC_SURROUND='https://ott.dolby.com/OnDelKits/DDP/Dolby_Digital_Plus_Online_Delivery_Kit_v1.4.1/Test_Signals/muxed_streams/MP4/Example/ChID_voices_1920x1080p_25fps_h265_6ch_256kbps_ddp.mp4';
let busy=false;
const candidates=new Map();
function candidateLabels(stream,index){
  const hints=labels(stream);
  const parts=['Source '+(index+1)];
  if(hints.fourKLabel)parts.push('4K label');
  if(hints.fullHdLabel)parts.push('1080p label');
  if(hints.hevcLabel)parts.push('HEVC label');
  if(hints.ddPlusLabel)parts.push('DD+ label');
  return parts.join(' · ');
}
const server=http.createServer(async(req,res)=>{
  const origin='http://127.0.0.1:'+server.address().port;
  const reply=(status,data,type='application/json')=>{
    res.writeHead(status,{'Content-Type':type+'; charset=utf-8','Cache-Control':'no-store',
      'X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','X-Frame-Options':'DENY','Content-Security-Policy':csp});
    res.end(type==='application/json'?JSON.stringify(data):data);
  };
  if(req.headers.host!==new URL(origin).host)return reply(403,{error:'Local access only.'});
  if(req.method==='GET'&&req.url==='/')return reply(200,page,'text/html');
  if(req.method!=='POST'||!['/check','/media','/candidate','/titles'].includes(req.url))return reply(404,{error:'Not found.'});
  if(req.headers.origin!==origin||req.headers['x-check-key']!==secret||
    req.headers['sec-fetch-site']&&req.headers['sec-fetch-site']!=='same-origin')
    return reply(403,{error:'Open this checker in its local browser window.'});
  if(busy)return reply(409,{error:'A check is already running.'});
  busy=true;
  try{
    req.setTimeout(10000,()=>req.destroy());
    let size=0;const parts=[];
    for await(const part of req){size+=part.length;if(size>32768)return reply(413,{error:'Input too large.'});parts.push(part);}
    req.setTimeout(0); // The input deadline must not interrupt a longer bounded media inspection.
    const body=JSON.parse(Buffer.concat(parts).toString('utf8'));
    if(req.url==='/check'){
      candidates.clear();
      const report=await checkAddon(body.url,undefined,{movieId:body.movieId,onStreams:streams=>{
        for(const [index,stream] of streams.slice(0,40).entries()){
          const id=crypto.randomBytes(16).toString('hex');
          candidates.set(id,{stream,label:candidateLabels(stream,index),expires:Date.now()+15*60*1000});
          setTimeout(()=>candidates.delete(id),15*60*1000).unref();
        }
      }});
      report.candidates=[...candidates].map(([id,entry])=>({id,label:entry.label}));
      return reply(200,report);
    }
    if(req.url==='/titles'){
      const query=typeof body.query==='string'?body.query.trim().slice(0,150):'';
      if(!query)return reply(400,{error:'Enter a movie title.'});
      const url='https://v3-cinemeta.strem.io/catalog/movie/top/search='+encodeURIComponent(query)+'.json';
      const data=await readJson(url);
      const movies=(Array.isArray(data.metas)?data.metas:[]).filter(meta=>
        meta&&/^tt\d{5,12}$/.test(meta.id)&&typeof meta.name==='string').slice(0,20)
        .map(meta=>({id:meta.id,name:meta.name.slice(0,250)}));
      return reply(200,{movies});
    }
    if(req.url==='/candidate'){
      const entry=candidates.get(body.id);
      if(!entry||entry.expires<Date.now())return reply(400,{error:'Source expired. Load the movie’s sources again.'});
      const hints=entry.stream.behaviorHints;
      const headers=hints&&hints.proxyHeaders&&hints.proxyHeaders.request;
      return reply(200,await inspectMedia(entry.stream.url,{headers}));
    }
    const media=body.publicSample===true?PUBLIC_SAMPLE:body.publicAdaptive===true?PUBLIC_ADAPTIVE:
      body.publicSurround===true?PUBLIC_SURROUND:body.url;
    return reply(200,await inspectMedia(media));
  }catch{
    reply(400,{error:'The check could not be completed. Verify the input and service availability. No private URL or error text was logged.'});
  }finally{busy=false;}
});
server.requestTimeout=15000;
server.headersTimeout=10000;
server.maxRequestsPerSocket=4;
server.listen(0,'127.0.0.1',()=>{
  const url='http://127.0.0.1:'+server.address().port+'/';
  console.log('Private source checker: '+url);
  console.log('No configured URLs are logged. Close this terminal to stop.');
  if(process.platform==='win32'&&!process.argv.includes('--no-open'))
    require('node:child_process').spawn('explorer.exe',[url],{stdio:'ignore',windowsHide:true}).unref();
});
