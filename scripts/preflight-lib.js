'use strict';

// Read-only add-on checks. Configured URLs stay in memory and never enter reports.
const TIMEOUT_MS = 20000;
const MAX_JSON_BYTES = 2 * 1024 * 1024;

function manifestAddress(value) {
  const url = new URL(String(value).trim());
  if (url.protocol !== 'https:' || !url.hostname || url.username || url.password || url.hash)
    throw new Error('Use an HTTPS manifest URL without a fragment or embedded login.');
  if (!/\/manifest\.json$/.test(url.pathname))
    throw new Error('Paste the complete configured URL ending in /manifest.json. A query after it is allowed.');
  return url;
}

function resourceUrl(manifest, resource, type, id, extra) {
  const url = new URL(manifest.href);
  const tail = [resource, type, id].map(encodeURIComponent).join('/');
  url.pathname = url.pathname.replace(/manifest\.json$/, tail + (extra ? '/' + extra : '') + '.json');
  return url;
}

async function readJson(url, fetchImpl = fetch, timeoutMs = TIMEOUT_MS) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    let target = new URL(url), response;
    for (let hop = 0; hop <= 5; hop++) {
      if (target.protocol !== 'https:' || target.username || target.password) throw new Error('HTTPS required');
      response = await fetchImpl(target, { signal: controller.signal, redirect: 'manual',
        headers: { Accept: 'application/json' } });
      if (![301, 302, 303, 307, 308].includes(response.status)) break;
      const location = response.headers.get('location');
      if (response.body && response.body.cancel) await response.body.cancel();
      if (!location || hop === 5) throw new Error('Redirect limit');
      target = new URL(location, target);
    }
    if (!response.ok) throw new Error('HTTP ' + response.status);
    if (response.url && new URL(response.url).protocol !== 'https:') throw new Error('HTTPS redirect required');
    const chunks = []; let size = 0;
    for await (const chunk of response.body) {
      size += chunk.length;
      if (size > MAX_JSON_BYTES) { controller.abort(); throw new Error('Response too large'); }
      chunks.push(chunk);
    }
    const json = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!json || typeof json !== 'object' || Array.isArray(json)) throw new Error('JSON object required');
    return json;
  } finally { clearTimeout(timer); }
}

function supports(manifest, resource, type, id = '') {
  if (!Array.isArray(manifest.resources)) return false;
  return manifest.resources.some(entry => {
    const rule = typeof entry === 'string' ? { name: entry, types: manifest.types, idPrefixes: manifest.idPrefixes } : entry;
    if (!rule || rule.name !== resource) return false;
    const types = rule.types;
    const prefixes = rule.idPrefixes;
    return Array.isArray(types) && types.includes(type) &&
      (!Array.isArray(prefixes) || prefixes.some(prefix => typeof prefix === 'string' && prefix && id.startsWith(prefix)));
  });
}

function directHttps(stream) {
  if (!stream || typeof stream.url !== 'string' || /\s/.test(stream.url)) return false;
  try { const url = new URL(stream.url); return url.protocol === 'https:' && !!url.hostname && !url.username && !url.password; }
  catch { return false; }
}

function sourceBlockReason(stream) {
  if (!stream || typeof stream !== 'object') return '';
  const name = typeof stream.name === 'string' ? stream.name.toLowerCase() : '';
  const providers = '(tb|rd|ad|dl|pm|oc|ed|hw|putio)';
  if (new RegExp('\\[' + providers + '[ ]+download\\]', 'i').test(name)) return 'uncached';
  if (name.includes('torrentio') && new RegExp('(^|[^a-z0-9])' + providers + '[ ]+error([^a-z0-9]|$)', 'i').test(name)) return 'provider-status';
  try {
    const url = new URL(stream.url);
    const clips = ['downloading_v3.mp4','download_failed_v3.mp4','failed_access_v3.mp4','failed_rar_v3.mp4',
      'failed_too_big_v2.mp4','failed_opening_v3.mp4','failed_unexpected_v3.mp4','failed_infringement_v3.mp4',
      'limits_exceeded_v2.mp4','blocked_access_v2.mp4','failed_unavailable_v1.mp4'];
    if (url.protocol === 'https:' && ['torrentio.strem.fun','torrentio.elfhosted.com'].includes(url.hostname.toLowerCase()) &&
        clips.includes(url.pathname.replace(/^\/videos\//,'')) && url.pathname.startsWith('/videos/')) return 'provider-status';
  } catch {}
  return '';
}

function labels(stream) {
  const hints = stream && typeof stream.behaviorHints === 'object' ? stream.behaviorHints : {};
  const text = [stream.name, stream.title, stream.description, stream.quality, hints.filename]
    .filter(value => typeof value === 'string').join(' ').toLowerCase();
  return {
    fourKLabel: /(^|[^a-z0-9])(2160p?|4k|uhd)([^a-z0-9]|$)/i.test(text),
    fullHdLabel: /(^|[^a-z0-9])1080p?([^a-z0-9]|$)/i.test(text),
    hevcLabel: /(^|[^a-z0-9])(hevc|h[ ._-]?265|x265)([^a-z0-9]|$)/i.test(text),
    hdr10Label: /hdr10/i.test(text),
    ddPlusLabel: /(ddp|dd\+|e[ ._-]?ac[ ._-]?3|dolby digital plus)/i.test(text),
    trueHdLabel: /truehd/i.test(text),
    requiresHeaders: !!(hints.proxyHeaders && hints.proxyHeaders.request && Object.keys(hints.proxyHeaders.request).length)
  };
}

async function checkAddon(value, fetchImpl = fetch, options = {}) {
  const manifest = manifestAddress(value);
  const report = { checkedAt: new Date().toISOString(), checks: [],
    scope: 'Read-only metadata and stream-list requests. No movie bytes downloaded. No Roku playback performed.',
    hardwarePlayback: 'UNVERIFIED', providerReliability: 'UNVERIFIED' };
  const add = (name, status, detail) => report.checks.push({ name, status, detail });
  let data;
  try { data = await readJson(manifest, fetchImpl); }
  catch { add('Manifest', 'FAIL', 'Could not read a valid HTTPS JSON manifest. Check the private URL, account and provider status.'); return report; }
  const nonempty = value => typeof value === 'string' && !!value.trim();
  if (!nonempty(data.id) || !nonempty(data.name) || !Array.isArray(data.types) || !data.types.every(nonempty) ||
      !Array.isArray(data.resources) || !data.resources.some(entry => nonempty(entry) || (entry && nonempty(entry.name))) ||
      (data.catalogs != null && !Array.isArray(data.catalogs))) {
    add('Manifest', 'FAIL', 'Required manifest fields are missing or malformed. The Roku installer would reject this response.'); return report;
  }
  add('Manifest', 'PASS', 'Required fields and HTTPS JSON response are valid.');
  const catalogs = Array.isArray(data.catalogs) ? data.catalogs.filter(item => item && typeof item.id === 'string' && typeof item.type === 'string') : [];
  add('Catalogs', catalogs.length ? 'PASS' : 'INFO', catalogs.length + ' declared catalogs. Stream-only add-ons can use Cinemeta search.');
  const searchable = catalogs.find(item => {
    const extras = Array.isArray(item.extra) ? item.extra : [];
    const hasSearch = extras.some(extra => extra === 'search' || (extra && extra.name === 'search')) ||
      (Array.isArray(item.extraSupported) && item.extraSupported.includes('search'));
    const blocked = extras.some(extra => extra && extra.isRequired && !['search','skip'].includes(extra.name)) ||
      (Array.isArray(item.extraRequired) && item.extraRequired.some(name => !['search','skip'].includes(name)));
    return hasSearch && !blocked;
  });
  if (searchable) {
    try {
      const result = await readJson(resourceUrl(manifest, 'catalog', searchable.type, searchable.id, 'search=Metropolis'), fetchImpl);
      const metas = Array.isArray(result.metas) ? result.metas.filter(meta => meta && typeof meta.id === 'string' && typeof meta.name === 'string') : [];
      add('Search', Array.isArray(result.metas) ? 'PASS' : 'FAIL', metas.length + ' valid metadata results for the diagnostic search. This does not establish playable availability.');
    } catch { add('Search', 'FAIL', 'Search request failed or returned invalid JSON.'); }
  } else add('Search', 'INFO', 'No search catalog advertised; the Roku app searches installed catalog add-ons separately.');
  const movieId = /^tt\d{5,12}$/.test(options.movieId || '') ? options.movieId : 'tt0017136';
  report.diagnosticMovieId = movieId;
  if (supports(data, 'stream', 'movie', movieId)) {
    try {
      // Torrentio can wait 30s for provider availability. Allow completion plus
      // transport margin; manifest/search keep their shorter deadline.
      const result = await readJson(resourceUrl(manifest, 'stream', 'movie', movieId), fetchImpl, 45000);
      if (!Array.isArray(result.streams)) throw new Error('Array required');
      const streams = result.streams.filter(item => item && typeof item === 'object' && !Array.isArray(item));
      const https = streams.filter(stream => directHttps(stream) && !sourceBlockReason(stream));
      if (typeof options.onStreams === 'function') options.onStreams(https);
      const facts = https.map(labels);
      const count = key => facts.filter(item => item[key]).length;
      add('Stream endpoint', 'PASS', streams.length + ' candidates returned for the diagnostic movie.');
      report.streamCounts = { candidates: streams.length, directHttps: https.length,
        skippedUncached: streams.filter(stream => sourceBlockReason(stream) === 'uncached').length,
        skippedProviderStatus: streams.filter(stream => sourceBlockReason(stream) === 'provider-status').length,
        fourKLabels: count('fourKLabel'),
        fullHdLabels: count('fullHdLabel'), hevcLabels: count('hevcLabel'), hdr10Labels: count('hdr10Label'),
        ddPlusLabels: count('ddPlusLabel'), trueHdLabels: count('trueHdLabel'), needsRequestHeaders: count('requiresHeaders') };
      add('Native candidates', https.length ? 'PASS' : 'UNVERIFIED', https.length + ' direct HTTPS candidates. Codec labels and reachable JSON do not prove decoding, 5.1 output or sustained delivery.');
    } catch { add('Stream endpoint', 'FAIL', 'Stream request failed or returned invalid JSON. Check provider configuration; no request URL was retained.'); }
  } else add('Stream endpoint', 'INFO', 'This add-on does not advertise streams for the standard diagnostic movie ID.');
  return report;
}

module.exports = { manifestAddress, resourceUrl, readJson, supports, directHttps, labels, sourceBlockReason, checkAddon };
