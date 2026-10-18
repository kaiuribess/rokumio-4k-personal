// Execute the production header-total parser and sanitized file facts. The
// resolver/header acquisition boundary is separately exercised by playback-native.
const fs = require('fs');
const os = require('os');
const path = require('path');
const {spawnSync} = require('child_process');
const root = path.resolve(__dirname, '..');
const staging = fs.mkdtempSync(path.join(os.tmpdir(), 'crimson-file-facts-'));
try {
  const read = name => fs.readFileSync(path.join(root, name), 'utf8');
  const parser = /^function NativeMedia_DeclaredFileBytes\([^]*?^end function/mi.exec(read('source/util/NativeMedia.brs'));
  if (!parser) throw new Error('Missing production file-total parser');
  const file = path.join(staging, 'source-file-facts.brs');
  fs.writeFileSync(file, [read('tests/harness.brs'), parser[0], read('source/util/PlaybackInfo.brs'), read('tests/source-file-facts.test.brs')].join('\n'));
  const result = spawnSync(process.execPath, [path.join(root, 'node_modules/@rokucommunity/brs/bin/cli.js'), '--root', staging, file], {cwd:staging, encoding:'utf8'});
  process.stdout.write(result.stdout || '');
  if (result.stderr) process.stderr.write(result.stderr);
  process.exitCode = result.status === 0 && !result.stderr?.trim() && /RESULT: PASS/.test(result.stdout || '') ? 0 : 1;
} finally {
  const resolved = path.resolve(staging);
  if (path.dirname(resolved) !== path.resolve(os.tmpdir()) || !path.basename(resolved).startsWith('crimson-file-facts-')) throw new Error('Unexpected test staging directory');
  fs.rmSync(resolved, {recursive:true, force:true});
}
