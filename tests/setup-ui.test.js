// Run production setup callbacks with native row/editor boundary doubles.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const source = read('components/SettingsScreen.brs');
const callbacks = ['OnEnter', 'BuildRows', 'SessionValue', 'ServerValue', 'AudioSetupValue', 'ToggleAudioSetup', 'ReportSaveFault', 'ApplyServerKeyboard', 'TestServer'].map(name => {
  const match = new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`, 'mi').exec(source);
  if (!match) throw new Error('Missing setup entry point: ' + name);
  return match[0].replaceAll('CreateObject("roSGNode", "ContentNode")', 'TestContent()');
}).join('\n');
const removeConfirm = /^(?:sub|function) ShowRemoveConfirm\([^]*?^end (?:sub|function)/mi.exec(read('components/AddonsScreen.brs'));
if (!removeConfirm) throw new Error('Missing add-on removal entry point');
const addonCallbacks = removeConfirm[0]
  .replaceAll('CreateObject("roSGNode", nodeType)', 'TestNativeDialog(nodeType)')
  .replaceAll('CreateObject("roSGNode", "Dialog")', 'TestNativeDialog("Dialog")');
const isolated = path.join(root, 'out-test', 'setup-ui');
fs.mkdirSync(isolated, { recursive: true });
const file = path.join(isolated, 'setup-tests.brs');
fs.writeFileSync(file, [read('tests/harness.brs'), read('source/util/AudioSetup.brs'), read('source/util/ProviderPriority.brs'), read('source/util/AddonDiagnostics.brs'), read('components/SettingsProvider.brs'), read('source/util/PlaybackPreferences.brs'), read('components/SettingsAudio.brs'), callbacks, addonCallbacks, read('tests/setup-ui.test.brs')].join('\n'));
const result = spawnSync(process.execPath, [path.join(root, 'node_modules/@rokucommunity/brs/bin/cli.js'), '--root', isolated, file], { cwd: isolated, encoding: 'utf8' });
process.stdout.write(result.stdout || ''); process.stderr.write(result.stderr || '');
process.exit(result.status === 0 && !(result.stderr || '').trim() && /RESULT: PASS/.test(result.stdout || '') ? 0 : 1);
