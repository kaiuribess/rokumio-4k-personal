// Execute the production native stream-info callback and PlaybackStatus
// boundary with deterministic native events. No network, URLs in output or
// native playback speed claims.
const fs = require('fs');
const os = require('os');
const path = require('path');
const {spawnSync} = require('child_process');
const root = path.resolve(__dirname, '..');
const staging = fs.mkdtempSync(path.join(os.tmpdir(), 'crimson-delivery-info-'));
try {
  const read = name => fs.readFileSync(path.join(root, name), 'utf8');
  const player = read('components/PlayerScreen.brs');
  const status = /^function PlaybackStatus\([^]*?^end function/mi.exec(player);
  if (!status) throw new Error('Missing production PlaybackStatus boundary');
  if (!status[0].includes('delivery:DeliveryInfo_Status()')) throw new Error('Native delivery status is not wired into PlaybackStatus');
  const combined = [read('tests/harness.brs'), read('source/util/PlaybackInfo.brs'),
    read('components/PlayerDeliveryInfo.brs'), status[0], read('tests/delivery-info.test.brs')].join('\n');
  const file = path.join(staging, 'delivery-info.brs');
  fs.writeFileSync(file, combined);
  const result = spawnSync(process.execPath, [path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'), '--root', staging, file], {cwd:staging,encoding:'utf8'});
  process.stdout.write(result.stdout || '');
  if (result.stderr) process.stderr.write(result.stderr);
  process.exitCode = result.status === 0 && !result.stderr?.trim() && /RESULT: PASS/.test(result.stdout || '') ? 0 : 1;
} finally {
  const resolved = path.resolve(staging);
  if (path.dirname(resolved) !== path.resolve(os.tmpdir()) || !path.basename(resolved).startsWith('crimson-delivery-info-')) throw new Error('Unexpected test staging directory');
  fs.rmSync(resolved,{recursive:true,force:true});
}
