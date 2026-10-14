'use strict';
// Bounded reads of existing HTTPS media. No debrid API or torrent resolver calls.
const MAX_BYTES = 6 * 1024 * 1024;
const MAX_REQUESTS = 36;
const MAX_METADATA = 2 * 1024 * 1024;
const PLAYLIST_LIMIT = 256 * 1024;
const MKV_LIMIT = 1024 * 1024;

class ProbeError extends Error {
  constructor(code) { super(code); this.code = code; }
}
function mediaAddress(value) {
  let url;
  try { url = new URL(value); } catch { throw new ProbeError('invalid-url'); }
  if (url.protocol !== 'https:' || !url.hostname || url.username || url.password || url.hash)
    throw new ProbeError('invalid-url');
  // These are account/resolver operations, not existing media files. GET can mutate.
  const host = url.hostname.toLowerCase();
  const path = decodeURIComponent(url.pathname).toLowerCase();
  if (host === 'api.torbox.app' || host === 'api.real-debrid.com' || host === 'rest.real-debrid.com' ||
      host === 'torrentio.strem.fun' || host === 'torrentio.elfhosted.com' ||
      /\/(?:resolve|createtorrent|unrestrict|requestdl)(?:\/|$)/.test(path))
    throw new ProbeError('account-resolver');
  return url;
}
const safeHeaderNames = new Set(['accept','user-agent','referer','origin','authorization','cookie']);
function cleanHeaders(input) {
  const headers = {};
  if (!input || typeof input !== 'object' || Array.isArray(input)) return headers;
  for (const [name,value] of Object.entries(input)) {
    if (!safeHeaderNames.has(name.toLowerCase()) || typeof value !== 'string' ||
        value.length > 8192 || /[\r\n\0]/.test(value)) continue;
    headers[name.toLowerCase()] = value;
  }
  return headers;
}
function createReader(fetchImpl = fetch, suppliedHeaders, options = {}) {
  const stats = { bytesRead:0, requests:0 };
  const timeoutMs = options.timeoutMs || 20000;
  const totalTimeoutMs = options.totalTimeoutMs || 60000;
  const started = Date.now();
  const originalHeaders = cleanHeaders(suppliedHeaders);
  let sourceOrigin;
  async function request(value, range, maxBytes) {
    let target = mediaAddress(value);
    if (!sourceOrigin) sourceOrigin = target.origin;
    const controller = new AbortController();
    const remaining = totalTimeoutMs - (Date.now() - started);
    if (remaining <= 0) throw new ProbeError('deadline');
    const timer = setTimeout(() => controller.abort(), Math.min(timeoutMs, remaining));
    let response;
    try {
      for (let hop=0; hop<=5; hop++) {
        target = mediaAddress(target.href);
        if (++stats.requests > MAX_REQUESTS) throw new ProbeError('request-budget');
        const headers = target.origin === sourceOrigin ? {...originalHeaders} : {};
        if (range) headers.Range = 'bytes=' + range.offset + '-' + (range.offset + range.length - 1);
        headers['Accept-Encoding'] = 'identity';
        response = await fetchImpl(target, {method:'GET',headers,redirect:'manual',signal:controller.signal});
        if (![301,302,303,307,308].includes(response.status)) break;
        const location = response.headers.get('location');
        if (response.body) await response.body.cancel();
        if (!location || hop===5) throw new ProbeError('redirect');
        target = mediaAddress(new URL(location,target).href);
      }
      if (!response.ok) { if (response.body) await response.body.cancel(); throw new ProbeError('http'); }
      if (response.url && new URL(response.url).origin !== target.origin)
        throw new ProbeError('redirect');
      let fileSize = null, start = null, expected = null;
      if (range) {
        const match = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(response.headers.get('content-range') || '');
        if (response.status !== 206 || !match) {
          if (response.body) await response.body.cancel();
          throw new ProbeError('range-required');
        }
        start = Number(match[1]); const end = Number(match[2]); fileSize = Number(match[3]);
        if (![start,end,fileSize].every(Number.isSafeInteger) || start !== range.offset ||
            end < start || end >= fileSize || end - start + 1 > range.length)
          throw new ProbeError('invalid-range');
        expected = end - start + 1;
      }
      if ((response.headers.get('content-encoding') || 'identity').toLowerCase() !== 'identity')
        throw new ProbeError('compressed-response');
      const pieces=[]; let size=0;
      for await (const piece of response.body) {
        size += piece.length;
        stats.bytesRead += piece.length;
        if (size > maxBytes || stats.bytesRead > MAX_BYTES) {
          controller.abort(); throw new ProbeError('byte-budget');
        }
        pieces.push(piece);
      }
      if (expected !== null && size !== expected) throw new ProbeError('truncated-range');
      return {buffer:Buffer.concat(pieces),url:target.href,fileSize,start,
        contentType:(response.headers.get('content-type') || '').toLowerCase()};
    } finally {
      clearTimeout(timer);
      if (response && response.body && !response.bodyUsed) await response.body.cancel().catch(()=>{});
    }
  }
  return {stats,range:(url,offset,length) => {
    if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(length) ||
        length <= 0 || length > MAX_METADATA) throw new ProbeError('invalid-range');
    return request(url,{offset,length},length);
  },text:url=>request(url,null,PLAYLIST_LIMIT)};
}
function boxHeader(buffer, offset, total) {
  if (buffer.length < 8) throw new ProbeError('truncated-container');
  let size = buffer.readUInt32BE(0), headerSize = 8;
  const type = buffer.toString('latin1',4,8);
  if (size===1) {
    if (buffer.length < 16) throw new ProbeError('truncated-container');
    const wide=buffer.readBigUInt64BE(8);
    if (wide > BigInt(Number.MAX_SAFE_INTEGER)) throw new ProbeError('oversized-container');
    size=Number(wide); headerSize=16;
  } else if (size===0) size=total-offset;
  if (!Number.isSafeInteger(size) || size < headerSize || offset + size > total)
    throw new ProbeError('truncated-container');
  return {type,size,headerSize};
}
async function inspectMp4Url(url, reader) {
  const {parseMp4Metadata} = require('./media-mp4');
  let offset=0, total, moov=null;
  for (let boxes=0; boxes<28; boxes++) {
    const head=await reader.range(url,offset,16);
    total=head.fileSize;
    const box=boxHeader(head.buffer,offset,total);
    if (box.type === 'moov') {
      if (box.size > MAX_METADATA) throw new ProbeError('metadata-budget');
      moov=await reader.range(head.url,offset,box.size);
      break;
    }
    // Skip media payload by declared top-level size; never search mdat for fake boxes.
    offset += box.size;
    if (offset >= total) break;
  }
  if (!moov) throw new ProbeError('metadata-not-found');
  return parseMp4Metadata(moov.buffer);
}
async function inspectFile(url, reader, format) {
  if (format === 'mkv') {
    const data=await reader.range(url,0,MKV_LIMIT);
    return require('./media-mkv').inspectMkv(data.buffer);
  }
  return inspectMp4Url(url,reader);
}
function dimensions(track) {
  const width=track.width ?? track.pixelWidth;
  const height=track.height ?? track.pixelHeight;
  return Number.isInteger(width) && Number.isInteger(height) && width > 0 && height > 0 &&
    width <= 16384 && height <= 16384 ? {width,height} : null;
}
function safeTrack(track) {
  const dim=dimensions(track);
  const codec=String(track.codec || track.codecId || track.sampleEntry || '').toLowerCase();
  const videoCodecs={'hvc1':'HEVC','hev1':'HEVC','v_mpegh/iso/hevc':'HEVC','hevc':'HEVC',
    'avc1':'H.264','avc3':'H.264','v_mpeg4/iso/avc':'H.264','h264':'H.264',
    'vp09':'VP9','v_vp9':'VP9','av01':'AV1','v_av1':'AV1'};
  const audioCodecs={'ec-3':'DD+','eac3':'DD+','a_eac3':'DD+','ac-3':'Dolby Digital','ac3':'Dolby Digital',
    'a_ac3':'Dolby Digital','mp4a':'AAC','a_aac':'AAC','a_truehd':'TrueHD','a_dts':'DTS','a_flac':'FLAC','opus':'Opus','a_opus':'Opus'};
  const entry={kind:track.type==='video' || dim?'video':track.type==='audio'?'audio':'unknown',
    codec:videoCodecs[codec] || audioCodecs[codec] || 'Other / unverified'};
  if (dim) Object.assign(entry,dim);
  const config=track.hevcConfiguration || track.hevc || {};
  if ([1,2].includes(config.profileIdc)) entry.hevcProfile=config.profileIdc===2?'Main 10':'Main';
  if (Number.isFinite(Number(config.level)) && Number(config.level)>0) entry.hevcLevel=Number(config.level);
  if (['Main','High'].includes(config.tier)) entry.hevcTier=config.tier;
  const conflictingDepth=Object.hasOwn(track,'bitDepth') && track.bitDepth===null;
  const bitDepth=conflictingDepth?null:config.bitDepthLuma || track.bitDepth;
  if (Number.isInteger(bitDepth) && bitDepth>=8 && bitDepth<=16) entry.bitDepth=bitDepth;
  // Channel fields are parser-proven values; raw labels or source title are never copied.
  const audio=track.audioConfiguration || track.audio || {};
  const channels=audio.channelCount ?? track.channelCount ?? audio.channels;
  if (Number.isInteger(channels) && channels>0 && channels<=32) entry.channels=channels;
  if (audio.channelLayout==='5.1' || track.channelLayout==='5.1') entry.channelLayout='5.1';
  const color=track.colour || track.color;
  const transfer=color && (color.transfer ?? color.transferCharacteristics);
  if (transfer===16) entry.transfer='PQ';
  if (transfer===18) entry.transfer='HLG';
  if (track.colour || track.color) entry.colorMetadataPresent=true;
  return entry;
}
function classify(tracks) {
  if (tracks.some(track=>track.kind==='video' && (!track.width || !track.height)))
    return {status:'UNVERIFIED',verdict:'Some video track dimensions were unavailable, so default track resolution remains unverified.'};
  const video=tracks.filter(track=>track.kind==='video' && track.width && track.height);
  if (!video.length) return {status:'UNVERIFIED',verdict:'Encoded video dimensions were not available.'};
  const uhd=video.filter(track=>track.width===3840 && track.height===2160);
  const cropped=video.filter(track=>track.width===3840 && track.height<2160);
  if (uhd.length && video.some(track=>track.width!==3840 || track.height!==2160))
    return {status:'MIXED_VIDEO_RESOLUTIONS',verdict:'A 3840 × 2160 video track is present alongside another resolution. The default playback track is unverified.'};
  if (uhd.length) return {status:'ENCODED_2160P_CONFIRMED',verdict:'Inspected video track metadata declares encoded dimensions of 3840 × 2160. This does not establish original camera/master detail or prove it was not upscaled before encoding.'};
  if (cropped.length) return {status:'UHD_WIDTH_BELOW_2160',verdict:'3840-pixel-wide video is present with height below 2160, consistent with cropped cinema. Cropping and source provenance are unverified.'};
  return {status:'NOT_3840x2160',verdict:'The inspected video tracks are not encoded at 3840 × 2160. A filename or HDMI 4K output does not change this.'};
}
const messages={
  'account-resolver':'This is an account or torrent resolver, which can create downloads. It was not contacted. An existing direct CDN media link is needed.',
  'invalid-url':'Use an existing direct HTTPS media URL without embedded login or a fragment.',
  'range-required':'The server did not honor bounded byte-range reads. Inspection stopped without downloading the full file.',
  'http':'The media request was refused or unavailable.',
  'redirect':'The redirect could not be checked safely.',
  'deadline':'Inspection reached its time limit.',
  'metadata-not-found':'Video metadata was not found within the inspection limits.',
  'metadata-budget':'The metadata exceeded the bounded inspection limit.',
  'byte-budget':'The response exceeded the bounded inspection limit.',
  'request-budget':'Too many requests were needed for bounded inspection.',
  'invalid-range':'The byte-range response was inconsistent.',
  'truncated-range':'The byte-range response was incomplete.',
  'truncated-container':'Container metadata was incomplete.',
  'oversized-container':'The container declared an unsupported size.',
  'compressed-response':'Compressed transport did not permit reliable byte-range inspection.',
};
async function inspectMedia(value, options={}) {
  const reader=createReader(options.fetchImpl,options.headers,options);
  const report={checkedAt:new Date().toISOString(),status:'UNVERIFIED',
    scope:'Bounded metadata reads of an existing media URL; no full movie download or playback.',
    sourceProvenance:'UNVERIFIED: encoded dimensions cannot prove that the master was not upscaled.',
    physicalRokuPlayback:'UNVERIFIED',providerMovieDelivery:'UNVERIFIED'};
  try {
    const url=mediaAddress(value);
    const path=url.pathname.toLowerCase();
    let parsed;
    if (path.endsWith('.m3u8') || path.endsWith('.mpd')) {
      const playlists=require('./media-playlists');
      const data=await reader.text(url.href);
      const parse=path.endsWith('.mpd')?playlists.parseDashManifest:playlists.parseHlsManifest;
      const list=parse(data.buffer.toString('utf8'),data.url);
      if (!list.ok) throw new ProbeError('metadata-not-found');
      report.playlist={declaredResolutions:list.summary.declaredResolutions,
        has2160:list.summary.has2160,has1080:list.summary.has1080,
        mixed1080And2160:list.summary.mixed1080And2160,guaranteed2160Playback:false};
      let initialization;
      if (list.variants && list.variants.length) {
        const sorted=[...list.variants].sort((a,b)=>(b.width || 0)-(a.width || 0));
        const selected=sorted.find(item=>item.width===3840 && item.height===2160) || sorted[0];
        initialization=selected.initialization;
        if (!initialization && list.format==='hls' && selected.url) {
          const child=await reader.text(selected.url);
          const media=playlists.parseHlsManifest(child.buffer.toString('utf8'),child.url);
          if (media.ok) initialization=(media.initializations || [])[0];
        }
      }
      if (!initialization) initialization=(list.initializations || [])[0];
      if (!initialization || !initialization.url || initialization.probeable===false) {
        report.verdict='Playlist declarations alone do not confirm the encoded video. No inspectable initialization metadata was available.';
        return {...report,...reader.stats};
      }
      const range=initialization.byteRange;
      const init=range ? await reader.range(initialization.url,range.offset,range.length) :
        await reader.range(initialization.url,0,MAX_METADATA);
      parsed=require('./media-mp4').parseMp4Metadata(init.buffer);
      report.adaptivePlayback='A confirmed 4K rendition does not force Roku to remain on it during adaptive playback.';
    } else if (path.endsWith('.mkv') || path.endsWith('.mp4') || path.endsWith('.m4v') || path.endsWith('.mov')) {
      parsed=await inspectFile(url.href,reader,path.endsWith('.mkv')?'mkv':'mp4');
    } else {
      // Detect the container from a small prefix; do not trust URL extensions.
      const prefix=await reader.range(url.href,0,32);
      const isMkv=prefix.buffer.length>=4 && prefix.buffer.readUInt32BE(0)===0x1a45dfa3;
      const isMp4=prefix.buffer.length>=8 && ['ftyp','moov','free','styp'].includes(prefix.buffer.toString('latin1',4,8));
      if (!isMkv && !isMp4) throw new ProbeError('metadata-not-found');
      parsed=await inspectFile(prefix.url,reader,isMkv?'mkv':'mp4');
    }
    report.container=parsed.container;
    report.tracks=(parsed.tracks || []).filter(track=>track.enabled!==false).map(safeTrack);
    Object.assign(report,classify(report.tracks));
    if (report.playlist && report.status==='ENCODED_2160P_CONFIRMED') {
      report.status='ENCODED_2160P_RENDITION_CONFIRMED';
      report.verdict='The inspected rendition’s initialization metadata declares 3840 × 2160. Other renditions, later initialization changes and actual adaptive selection are separate.';
    }
    if (report.tracks.some(track=>track.hevcTier==='High'))
      report.rokuEncodingAssessment='High-tier HEVC support is not specified in Roku documentation. This source is not certified for your Roku.';
    else if (report.tracks.some(track=>track.hevcLevel>5.1 || track.bitDepth>10))
      report.rokuEncodingAssessment='An inspected encoding field exceeds the conservative Roku HEVC target. Choose another source.';
    else
      report.rokuEncodingAssessment='Resolution/profile metadata alone cannot certify Roku playback. Frame rate, bitrate, audio selection and delivery may remain unverified.';
  } catch (error) {
    report.status='UNVERIFIED';
    report.verdict=messages[error.code] || 'The metadata could not be inspected reliably. No source URL or private error text was retained.';
  }
  return {...report,...reader.stats};
}
module.exports={inspectMedia,mediaAddress,createReader,boxHeader,classify,safeTrack,ProbeError};
