// Execute production screen callbacks; mock only native SG nodes/task disposal.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const isolated = path.join(root, 'out-test', 'streams-screen');
fs.mkdirSync(isolated, { recursive: true });
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const screen = read('components/StreamsScreen.brs').replaceAll('CreateObject("roSGNode", "ContentNode")', 'TestContent()');
const library = ['BuildRows','TileWatchFields','LibraryLabel','TypeLabel','SortLabel'].map(name => {
  const match = new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`, 'mi').exec(read('components/LibraryScreen.brs'));
  if (!match) throw new Error('Missing Library entry point: ' + name);
  return match[0].replaceAll('CreateObject("roSGNode", "ContentNode")','TestContent()');
}).join('\n');
const settings = ['onTestServerResult','onNetDiagResult','NextSettingsWorkerId'].map(name => {
  const match = new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`, 'mi').exec(read('components/SettingsScreen.brs'));
  if (!match) throw new Error('Missing Settings entry point: ' + name);
  return match[0];
}).join('\n');
const tile = ['stopScroll', 'UpdateLook', 'onItemContentChanged', 'onMeasureTick',
  'onScrollTick', 'EstimateContentWidth', 'EstimateLineWidth'].map(name => {
  const match = new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`, 'mi').exec(read('components/StreamTile.brs'));
  if (!match) throw new Error('Missing StreamTile entry point: ' + name);
  return match[0];
}).join('\n');
const file = path.join(isolated, 'streams-tests.brs');
const streamPolicy = read('source/util/CinemaStreams.brs')
  .replace(/(function CinemaStreamRank\([^\n]*\n)/, '$1    m.cinemaRankCalls = m.cinemaRankCalls + 1\n');
fs.writeFileSync(file, [read('tests/harness.brs'), streamPolicy, read('source/util/AddonDiagnostics.brs'), read('source/util/PlaybackPreferences.brs'), read('source/util/SourcePrefetch.brs'), read('source/util/ProviderPriority.brs'), read('source/core/TileSize.bs'), screen, library, settings, tile, read('tests/streams-screen.test.brs')].join('\n'));
const result = spawnSync(process.execPath, [path.join(root, 'node_modules/@rokucommunity/brs/bin/cli.js'), '--root', isolated, file], { cwd: isolated, encoding: 'utf8' });
process.stdout.write(result.stdout || ''); process.stderr.write(result.stderr || '');
process.exit(result.status === 0 && !(result.stderr || '').trim() && /RESULT: PASS/.test(result.stdout || '') ? 0 : 1);
