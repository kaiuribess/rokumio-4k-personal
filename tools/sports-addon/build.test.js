const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const {build, writeBuild, publicUrl} = require('./build');
const now = new Date('2099-01-01T00:00:00Z');
const fixture = () => ({
  id: 'org.example.sports', name: 'Fixture Sports', events: [{
    id: 'espn_football_nfl_123', name: 'Example game', expiresAt: '2099-01-02T00:00:00Z',
    permission: {owner: 'Fixture broadcaster', publicPlayback: true, redistribution: true, url: 'https://example.com/permission'},
    sources: [{name: 'Primary', quality: '1080p', languages: ['eng'], url: 'https://example.com/live.m3u8'},
      {name: 'Backup', quality: '720p', languages: ['eng'], url: 'https://example.com/backup.m3u8'}]
  }]
});
test('standalone manifest, catalog, meta and stream endpoints over actual HTTP', async () => {
  const root = path.resolve(__dirname, '../../out-test'); fs.mkdirSync(root, {recursive:true});
  const dir = fs.mkdtempSync(path.join(root, 'sports-static-'));
  const output = path.join(dir, 'public');
  writeBuild(build(fixture(), now), output);
  // Local test fixture only; media URLs are not fetched. This is not a proxy.
  const server = http.createServer((req, res) => {
    const relative = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).slice(1);
    const filename = path.resolve(output, relative);
    if (!filename.startsWith(output + path.sep) || !fs.existsSync(filename)) {res.writeHead(404);res.end();return;}
    res.setHeader('Content-Type', 'application/json'); res.end(fs.readFileSync(filename));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const base = 'http://127.0.0.1:' + server.address().port;
    const manifest = await (await fetch(base + '/manifest.json')).json();
    assert.equal(manifest.types[0], 'tv');
    for (const suffix of ['/catalog/tv/crimson-sports.json', '/catalog/tv/crimson-sports/skip=0.json']) {
      const catalog = await (await fetch(base + suffix)).json();
      assert.equal(catalog.metas.length, 1); assert.equal(catalog.hasMore, false);
    }
    const meta = await (await fetch(base + '/meta/tv/espn_football_nfl_123.json')).json();
    assert.equal(meta.meta.name, 'Example game');
    const streams = await (await fetch(base + '/stream/tv/espn_football_nfl_123.json')).json();
    assert.equal(streams.streams.length, 2);
    assert.equal(streams.streams[0].behaviorHints.crimsonExpiresAt, '2099-01-02T00:00:00.000Z');
    assert.equal((await fetch(base + '/stream/tv/espn_football_nfl_999.json')).status, 404);
    assert.throws(() => writeBuild(build(fixture(), now), output), /EEXIST/);
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});
test('empty account-free feed does not invent playable matches', () => {
  const feed = fixture(); feed.events = [];
  assert.equal(build(feed, now).included, 0);
});
test('expired and unavailable entries disappear from catalog and return empty streams', () => {
  const feed = fixture(); feed.events[0].expiresAt = '2098-12-31T23:59:59Z';
  const result = build(feed, now);
  assert.equal(result.included, 0); assert.equal(result.excluded, 1);
  assert.deepEqual(result.files.get('stream/tv/espn_football_nfl_123.json'), {streams:[]});
  feed.events[0].expiresAt = '2099-01-02T00:00:00Z'; feed.events[0].sources = [];
  assert.equal(build(feed, now).included, 0);
});
test('authorization is explicit and cannot be implied by a working URL', () => {
  for (const field of ['publicPlayback', 'redistribution']) {
    const feed = fixture(); delete feed.events[0].permission[field];
    assert.throws(() => build(feed, now), /permission/);
  }
});
test('credentials, signed query URLs, unsafe URLs and embed pages rejected', () => {
  for (const url of ['http://example.com/a.m3u8','https://u:p@example.com/a.m3u8',
    'https://example.com/a.m3u8?token=fixture','https://example.com/a.m3u8#x',
    'https://127.0.0.1/a.m3u8','https://[::1]/a.m3u8','https://router.local/a.m3u8',
    'https://localhost/a.m3u8','https://example.com:8080/a.m3u8','https://example.com/embed/game']) {
    assert.throws(() => publicUrl(url, true));
  }
});
test('bounded events, sources and fields; duplicates are deterministic', () => {
  let feed = fixture(); feed.events = Array(101).fill(feed.events[0]);
  assert.throws(() => build(feed, now), /100/);
  feed = fixture(); feed.events[0].sources = Array(9).fill(feed.events[0].sources[0]);
  assert.throws(() => build(feed, now), /eight/);
  feed = fixture(); feed.events[0].name = 'x'.repeat(161);
  assert.throws(() => build(feed, now), /event name/);
  feed = fixture(); feed.events.push(feed.events[0]);
  assert.throws(() => build(feed, now), /Duplicate/);
  feed = fixture(); feed.events[0].sources.push(feed.events[0].sources[0]);
  assert.equal(build(feed, now).files.get('stream/tv/espn_football_nfl_123.json').streams.length, 2);
});
test('DRM, header spoofing and undeclared audio are not treated as native playback', () => {
  for (const field of ['drm', 'headers', 'cookies']) {
    const feed = fixture(); feed.events[0].sources[0][field] = {};
    assert.throws(() => build(feed, now), /DRM/);
  }
  const feed = fixture(); feed.events[0].sources[0].languages = ['spa'];
  assert.throws(() => build(feed, now), /English/);
});
test('expiry must be finite and periodically renewed after review', () => {
  for (const value of ['', 'bad', '2100-01-01T00:00:00Z']) {
    const feed = fixture(); feed.events[0].expiresAt = value;
    assert.throws(() => build(feed, now), /expiry|Expiry/);
  }
});
test('portable IDs cannot traverse output directories', () => {
  for (const value of ['../escape','sports_x/../escape','espn:football:nfl:1','sports_x%2fescape']) {
    const feed = fixture(); feed.events[0].id = value;
    assert.throws(() => build(feed, now), /event ID/);
  }
});
test('DASH is supported as a direct format without assuming DRM or 4K', () => {
  const feed = fixture(); feed.events[0].sources[0].url = 'https://example.com/live.mpd';
  delete feed.events[0].sources[0].quality;
  const source = build(feed, now).files.get('stream/tv/espn_football_nfl_123.json').streams[0];
  assert.match(source.title, /^Quality unknown/); assert.match(source.url, /\.mpd$/);
});
