const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const isolated = path.join(root, 'out-test', 'cinema-tests');
fs.mkdirSync(isolated, { recursive: true });
const combined = path.join(isolated, '_cinema.brs');
const production = fs.readFileSync(path.join(root, 'source/util/CinemaStreams.brs'), 'utf8')
  .replace(/(function CinemaStreamRank\([^\n]*\n)/, '$1    m.cinemaRankCalls = m.cinemaRankCalls + 1\n');
fs.writeFileSync(combined, production + '\n' + fs.readFileSync(path.join(root, 'tests/cinema-streams.test.brs'), 'utf8'));
const result = spawnSync(process.execPath, [
  path.join(root, 'node_modules/@rokucommunity/brs/bin/cli.js'),
  '--root', isolated, combined
], { cwd: isolated, encoding: 'utf8' });
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
if (result.status !== 0 || (result.stderr || '').trim() || !/Cinema stream policy: \d+ assertions passed/.test(result.stdout)) process.exit(1);
