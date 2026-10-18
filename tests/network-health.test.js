// Execute the production passive reader with deterministic native responses.
// No device, media transfer, identifiers in output, or speed interpretation.
const fs = require('fs');
const os = require('os');
const path = require('path');
const {spawnSync} = require('child_process');
const root = path.resolve(__dirname, '..');
const staging = fs.mkdtempSync(path.join(os.tmpdir(), 'crimson-network-health-'));
try {
  const read = name => fs.readFileSync(path.join(root, name), 'utf8');
  const production = read('source/util/NetworkHealth.brs');
  // A passive diagnostic must never grow an active transfer or raw logger.
  if (/ForceInternetStatusCheck|roUrlTransfer|AsyncGet|\bprint\b|FormatJson\s*\(/i.test(production)) {
    throw new Error('Passive network reader contains active transfer or logging code');
  }
  const diagnostics = read('components/PlaybackDiagnostics.brs');
  const boundary = /^function ReadPlaybackDiagnostic\([^]*?^end function/mi.exec(diagnostics);
  if (!boundary || !boundary[0].includes('NetworkHealth_Read(device)')) throw new Error('Passive network facts are not wired into the production status boundary');
  if (!read('components/MainScene.xml').includes('pkg:/source/util/NetworkHealth.brs')) throw new Error('MainScene is missing the production network helper dependency');
  // Replace only platform factories, not the production callback logic. The
  // status reader, cache, sanitizer and native-method calls run unchanged.
  const injectedBoundary = boundary[0]
    .replace('CreateObject("roDeviceInfo")', 'NetworkFixtureReadDevice()')
    .replace('CreateObject("roAppInfo")', 'NetworkFixtureAppInfo()');
  const file = path.join(staging, 'network-health.brs');
  fs.writeFileSync(file, [read('tests/harness.brs'), production, injectedBoundary, read('tests/network-health.test.brs')].join('\n'));
  const result = spawnSync(process.execPath, [path.join(root, 'node_modules/@rokucommunity/brs/bin/cli.js'), '--root', staging, file], {cwd:staging, encoding:'utf8'});
  process.stdout.write(result.stdout || '');
  if (result.stderr) process.stderr.write(result.stderr);
  process.exitCode = result.status === 0 && !result.stderr?.trim() && /RESULT: PASS/.test(result.stdout || '') ? 0 : 1;
} finally {
  const resolved = path.resolve(staging);
  if (path.dirname(resolved) !== path.resolve(os.tmpdir()) || !path.basename(resolved).startsWith('crimson-network-health-')) throw new Error('Unexpected test staging directory');
  fs.rmSync(resolved, {recursive:true, force:true});
}
