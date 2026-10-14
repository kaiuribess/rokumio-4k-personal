// Native Roku hardware is required to test dictation. These tests exercise
// playback state/seek policy in BrightScript and guard the integration points.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const source = read('source/main.brs');
assert.match(source, /input\.EnableTransportEvents\(\)/);
assert.match(source, /info\.type\s*=\s*"transport"/);
assert.match(source, /callFunc\("HandleVoiceTransport",\s*info\)/);
assert.match(source, /input\.EventResponse\(response\)/);
assert.match(source, /callFunc\("HandleDeepLink",\s*info\)/);
assert.match(read('components/MainScene.xml'), /<function name="HandleVoiceTransport"\s*\/>/);
assert.match(read('components/MainScene.brs'), /active\.id\s*<>\s*"playerScreen"/);
assert.match(read('components/MainScene.brs'), /active\.id\s*<>\s*"addonsScreen"/);
const scene = read('components/MainScene.brs');
const transport = /function HandleVoiceTransport\([^]*?\nend function/.exec(scene);
assert.ok(transport, 'the native voice handler exists');
assert.ok(transport[0].indexOf('video.autoplayAfterSeek =') < transport[0].indexOf('video.seek ='), 'autoplay setting is applied before native seek');
const search = read('components/SearchScreen.brs');
assert.match(search, /dialog\.keyboardDomain\s*=\s*"generic"/);
assert.match(search, /editor\.voiceEntryType\s*=\s*"generic"/);
assert.match(search, /editor\.voiceEnabled\s*=\s*true/);
assert.match(search, /if dialog = invalid then dialog = CreateObject\("roSGNode", "KeyboardDialog"\)/);
const combined = path.join(root, 'out-test', 'tests', '_voice.brs');
fs.mkdirSync(path.dirname(combined), { recursive: true });
fs.writeFileSync(combined, [read('tests/harness.brs'), read('source/util/VoiceTransport.brs'), transport[0], read('tests/voice.test.brs')].join('\n'));
// An isolated interpreter root avoids loading the real SceneGraph components
// and their untranspiled .bs files, which this pure policy test does not need.
const result = spawnSync(process.execPath, [path.join(root, 'node_modules', '@rokucommunity', 'brs', 'bin', 'cli.js'), '--root', path.dirname(combined), combined], { cwd: path.dirname(combined), encoding: 'utf8' });
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
// This interpreter can report parser failures on stderr yet return zero.
// A pure isolated suite must complete without diagnostics as well as pass.
const passed = result.status === 0 && !(result.stderr || '').trim() && /RESULT: PASS/.test(result.stdout || '');
process.exit(passed ? 0 : 1);
