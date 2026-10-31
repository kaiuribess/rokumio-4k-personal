const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const {ProgramBuilder} = require('brighterscript');
const {build} = require('../tools/sports-addon/build');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const dir = path.join(root, 'out-test', 'sports');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const extract = (file, name) => new RegExp('^(?:sub|function) ' + name + '\\([^]*?^end (?:sub|function)', 'mi').exec(read(file))[0];
const fixture = {
  id: 'org.example.sports', name: 'Fixture Sports', events: [{
    id: 'espn_football_nfl_123', name: 'Example game', expiresAt: '2099-01-02T00:00:00Z',
    permission: {owner: 'Fixture broadcaster', publicPlayback: true, redistribution: true, url: 'https://example.com/permission'},
    sources: [{name: 'Primary', quality: '1080p', languages: ['eng'], url: 'https://example.com/live.m3u8'},
      {name: 'Backup', quality: '720p', languages: ['eng'], url: 'https://example.com/backup.m3u8'}]
  }]
};
async function main() {
  // Check the actual XML geometry against ChevronList's layout contract. The
  // previous settings-style row overlapped the footer and squeezed provider
  // information into a narrow right-hand value column.
  const xml = read('components/SportsScreen.xml');
  const rowXml = read('components/SportsRow.xml');
  const tag = (text, id) => text.match(new RegExp('<[^>]+id="' + id + '"[^>]*>'))[0];
  const attr = (node, key) => node.match(new RegExp('\\b' + key + '="([^"]+)"'))[1];
  const y = node => JSON.parse(attr(node, 'translation'))[1];
  const list = tag(xml, 'sportsList');
  const height = Number(attr(list, 'rowHeight')), rows = Number(attr(list, 'numRows'));
  assert.equal(attr(list, 'rowComponent'), 'SportsRow');
  assert.ok(y(list) + rows * (height + 8) + (rows - 1) * 8 + 8 + 28 <= y(tag(xml, 'sportsStatus')), 'rows and bottom chevron must clear status');
  const title = tag(rowXml, 'rowTitle'), subtitle = tag(rowXml, 'rowValue'), face = tag(rowXml, 'rowFace');
  assert.ok(y(title) + Number(attr(title, 'height')) <= y(subtitle), 'title and subtitle must not overlap');
  assert.ok(y(subtitle) + Number(attr(subtitle, 'height')) <= height, 'subtitle must fit row');
  assert.ok(y(face) + Number(attr(face, 'height')) <= height, 'face must fit row');
  assert.ok(Number(attr(subtitle, 'width')) >= 900, 'provider/status text uses the full row');
  console.log('Sports XML layout: 6 checks passed');
  const builder = new ProgramBuilder();
  await builder.run({cwd: root, rootDir: root, files: ['source/**/*.bs', 'source/**/*.brs', 'bslib'], stagingDir: dir, createPackage: false, copyToStaging: true});
  if (builder.getDiagnostics().some(d => d.severity === 1)) throw new Error('Sports test transpilation failed');
  const generated = Object.fromEntries(build(fixture, new Date('2099-01-01T00:00:00Z')).files);
  const fixtureCode = 'function SportsFeedFixture() as object\nreturn ParseJson("' + JSON.stringify(generated).replaceAll('"', '""') + '")\nend function';
  const controller = read('components/SportsScreen.brs').replace(/^sub init\([^]*?^end sub\s*/mi, '')
    .replaceAll('CreateObject("roSGNode","ContentNode")', 'SportsTestContent()')
    .replaceAll('CreateObject("roTimespan")', 'SportsTestClock()');
  const worker = extract('components/SportsScheduleTask.brs', 'loadSchedule').replace('Transport()', 'SportsTestTransport()');
  const generatedRead = file => fs.readFileSync(path.join(dir, file), 'utf8');
  const code = [read('tests/harness.brs'), read('tests/mocks.brs'),
    generatedRead('source/bslib.brs'), generatedRead('source/core/ScreenStack.brs'), generatedRead('source/stores/Transport.brs').replaceAll('CreateObject("roUrlTransfer")', 'invalid'),
    generatedRead('source/stores/AddonsStore.brs'), generatedRead('source/stores/CatalogStore.brs'),
    generatedRead('source/stores/PlaybackStore.brs'), generatedRead('source/stores/EpisodesStore.brs'),
    read('source/util/CinemaStreams.brs'), read('source/util/Sports.brs'), read('source/util/SportsCatalog.brs'), read('source/util/AccountEpoch.brs'), read('components/SportsBrowser.brs').replaceAll('CreateObject("roSGNode","ContentNode")', 'SportsTestContent()').replaceAll('CreateObject("roTimespan")', 'SportsTestClock()'), controller, worker, extract('components/SportsCatalogTask.brs','loadSportsCatalog').replace('Transport()', 'SportsTestTransport()'),
    extract('components/MainScene.brs', 'onStreamsAction'), extract('components/MainScene.brs', 'onSportsAction'), extract('components/DiscoverScreen.brs', 'onResultSelected').replace('sub onResultSelected()', 'sub SportsDiscoverSelected()'), fixtureCode, read('tests/sports.test.brs').replace('Harness_Finish()', ''), read('tests/sports-catalog.test.brs')].join('\n');
  const file = path.join(dir, 'tests.brs'); fs.writeFileSync(file, code);
  const run = spawnSync(process.execPath, [path.join(root, 'node_modules/@rokucommunity/brs/bin/cli.js'), '--root', dir, file], {cwd: root, encoding: 'utf8'});
  process.stdout.write(run.stdout || ''); process.stderr.write(run.stderr || '');
  if (run.status !== 0 || (run.stderr || '').trim() || !/RESULT: PASS/.test(run.stdout || '')) process.exitCode = 1;
}
main().catch(error => {console.error(error); process.exitCode = 1;});
