// Production metadata policy, native finish callback, timer controller,
// watch-state writes and Scene routing. Only native SG boundaries are mocked.
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const dir = path.join(root, 'out-test', 'next-episode');
fs.mkdirSync(dir, {recursive:true});
const read = file => fs.readFileSync(path.join(root,file),'utf8');
const extract = (file,names) => names.map(name => {
  const match = new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi').exec(read(file));
  if (!match) throw new Error('Missing production entry point '+name);
  return match[0];
}).join('\n');
const file = path.join(dir,'tests.brs');
fs.writeFileSync(file,[read('tests/harness.brs'),read('source/util/NextEpisode.brs'),read('source/util/PlaybackInfo.brs'),read('components/PlayerNextEpisode.brs'),extract('components/PlayerScreen.brs',['onVideoStateChanged','SavePosition','PublishWatchState']),extract('components/MainScene.brs',['onNextEpisodeRequest']),read('tests/next-episode.test.brs')].join('\n'));
const result = spawnSync(process.execPath,[path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'),'--root',dir,file],{cwd:root,encoding:'utf8'});
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
process.exitCode = result.status === 0 && !(result.stderr || '').trim() && /RESULT: PASS/.test(result.stdout || '') ? 0 : 1;
