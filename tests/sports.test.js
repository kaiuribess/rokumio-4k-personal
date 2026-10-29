const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const {ProgramBuilder} = require('brighterscript');
const {build} = require('../tools/sports-addon/build');
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
    read('source/util/CinemaStreams.brs'), read('source/util/Sports.brs'), controller, worker,
    extract('components/MainScene.brs', 'onStreamsAction'), extract('components/MainScene.brs', 'onSportsAction'), extract('components/DiscoverScreen.brs', 'onResultSelected').replace('sub onResultSelected()', 'sub SportsDiscoverSelected()'), fixtureCode, read('tests/sports.test.brs')].join('\n');
  const file = path.join(dir, 'tests.brs'); fs.writeFileSync(file, code);
  const run = spawnSync(process.execPath, [path.join(root, 'node_modules/@rokucommunity/brs/bin/cli.js'), '--root', dir, file], {cwd: root, encoding: 'utf8'});
  process.stdout.write(run.stdout || ''); process.stderr.write(run.stderr || '');
  if (run.status !== 0 || (run.stderr || '').trim() || !/RESULT: PASS/.test(run.stdout || '')) process.exitCode = 1;
}
main().catch(error => {console.error(error); process.exitCode = 1;});
