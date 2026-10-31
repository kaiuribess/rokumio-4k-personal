'use strict';
// No resolver service, credentials, SDK or runtime dependency. Publish only
// operator-authorized, public, non-expiring media URLs. Video stays on its CDN.
const fs = require('node:fs');
const path = require('node:path');
const net = require('node:net');

function fail(message) { const error = new Error(message); error.safe = true; throw error; }
function text(value, max, field) {
  if (typeof value !== 'string' || !value.trim() || value.length > max || /[\x00-\x1f]/.test(value)) fail('Invalid ' + field);
  return value.trim();
}
function publicUrl(value, media = false) {
  let url;
  try { url = new URL(text(value, 2048, 'public URL')); } catch { fail('Invalid public URL'); }
  const host = url.hostname.toLowerCase();
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash ||
      url.port || net.isIP(host.replace(/[\[\]]/g, '')) || !host.includes('.') ||
      /(?:^|\.)(?:localhost|local|internal|home|invalid)$/.test(host)) fail('Only public HTTPS URLs without credentials, queries, fragments or ports are accepted');
  if (media && !/\.(m3u8|mpd)$/i.test(url.pathname)) fail('Expected a direct HLS .m3u8 or DASH .mpd URL, not a web player');
  return url.href;
}
function build(feed, now = new Date()) {
  if (!feed || !Array.isArray(feed.events) || feed.events.length > 100) fail('Expected at most 100 events');
  if (!Number.isFinite(+now)) fail('Invalid build clock');
  const name = text(feed.name, 64, 'provider name');
  const id = text(feed.id, 96, 'provider ID');
  if (!/^[a-z][a-z0-9.-]+$/.test(id)) fail('Invalid provider ID');
  const files = new Map();
  const seen = new Set();
  const metas = [];
  let excluded = 0;
  for (const event of feed.events) {
    if (!event || typeof event !== 'object') fail('Invalid event');
    const eventId = text(event.id, 120, 'event ID');
    // Names are portable filenames, including on Windows. No path separators.
    if (!/^(?:espn_[a-z0-9.-]+_[a-z0-9.-]+_[0-9]{1,24}|sports_[a-z0-9][a-z0-9.-]{0,80})$/.test(eventId)) fail('Invalid event ID');
    if (seen.has(eventId)) fail('Duplicate event ID');
    seen.add(eventId);
    const title = text(event.name, 160, 'event name');
    const permission = event.permission;
    if (!permission || permission.publicPlayback !== true || permission.redistribution !== true) fail('Public playback and redistribution permission must be explicitly established');
    const owner = text(permission.owner, 120, 'rights owner');
    const evidence = publicUrl(permission.url);
    const expiresAt = new Date(event.expiresAt);
    if (!event.expiresAt || !Number.isFinite(+expiresAt)) fail('Each event needs an explicit expiry');
    if (+expiresAt > +now + 7 * 86400000) fail('Expiry must be within seven days; rebuild after rechecking availability');
    if (!Array.isArray(event.sources) || event.sources.length > 8) fail('Expected at most eight sources per event');
    const streams = [];
    const sourceUrls = new Set();
    for (const source of event.sources) {
      const url = publicUrl(source.url, true);
      if (source.drm || source.headers || source.cookies) fail('DRM, cookies and custom request headers are not supported');
      if (sourceUrls.has(url)) continue;
      sourceUrls.add(url);
      const label = text(source.name, 64, 'source name');
      const quality = source.quality || 'Quality unknown';
      if (!['2160p', '1080p', '720p', 'SD', 'Quality unknown'].includes(quality)) fail('Invalid declared quality');
      if (!Array.isArray(source.languages) || !source.languages.includes('eng')) fail('This feed requires operator-declared English audio; the player still verifies it');
      streams.push({
        name: name, title: quality + ' · English · ' + label,
        url, behaviorHints: {notWebReady: false, crimsonExpiresAt: expiresAt.toISOString()},
        description: 'Provider-declared quality/audio; native playback remains unverified. Authorized by ' + owner
      });
    }
    const meta = {
      id: eventId, type: 'tv', name: title,
      description: text(event.description || 'Live sports broadcast', 600, 'description') +
        '\nRights: ' + owner + ' · ' + evidence + '\nFeed expires: ' + expiresAt.toISOString(),
      genres: ['Sports']
    };
    if (event.poster) meta.poster = publicUrl(event.poster);
    // ID grammar is portable; no decoding/rewrite service is needed.
    const encoded = encodeURIComponent(eventId);
    files.set('meta/tv/' + encoded + '.json', {meta});
    const active = +expiresAt > +now && streams.length > 0;
    files.set('stream/tv/' + encoded + '.json', {streams: active ? streams : []});
    if (active) metas.push(meta); else excluded++;
  }
  files.set('manifest.json', {
    id, version: '1.0.0', name, description: 'Operator-authorized sports feeds. No accounts or video are bundled.',
    types: ['tv'], idPrefixes: ['espn_', 'sports_'],
    resources: ['catalog', 'meta', {name: 'stream', types: ['tv'], idPrefixes: ['espn_', 'sports_']}],
    catalogs: [{type: 'tv', id: 'crimson-sports', name: 'Live sports', genres: ['Sports']}]
  });
  files.set('catalog/tv/crimson-sports.json', {metas, hasMore: false});
  files.set('catalog/tv/crimson-sports/skip=0.json', {metas, hasMore: false});
  return {files, included: metas.length, excluded};
}

function writeBuild(result, directory) {
  // Never delete arbitrary output trees or replace an existing deployment.
  fs.mkdirSync(directory, {recursive: false});
  fs.writeFileSync(path.join(directory, '.nojekyll'), '', {flag: 'wx'});
  for (const [relative, data] of result.files) {
    const target = path.join(directory, relative);
    fs.mkdirSync(path.dirname(target), {recursive: true});
    fs.writeFileSync(target, JSON.stringify(data), {flag: 'wx'});
  }
}
if (require.main === module) {
  try {
    const [input, output] = process.argv.slice(2);
    if (!input || !output) fail('Usage: node tools/sports-addon/build.js feed.json NEW_OUTPUT_DIRECTORY');
    const data = fs.readFileSync(input);
    if (data.byteLength > 262144) fail('Feed exceeds 256 KiB');
    const result = build(JSON.parse(data.toString('utf8')));
    writeBuild(result, path.resolve(output));
    console.log('Built ' + result.included + ' playable feed entries; excluded ' + result.excluded + '. Provider declarations are not hardware verification.');
  } catch (error) {
    // Errors deliberately omit feed values and source URLs.
    console.error('Sports add-on build failed: ' + (error.safe === true ? error.message : 'Check the JSON input and choose a new output directory.'));
    process.exitCode = 1;
  }
}
module.exports = {build, writeBuild, publicUrl};
