// Exercise real Home refresh/cancel callbacks; native task and node boundaries are mocked.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const source = read('components/HomeScreen.brs');
const functions = ['StartCatalogLoad','CatalogSignature','onCatalogState','FinishCatalogLoad',
  'RebuildRows','onKeyEvent','CancelOpen','onContinueWatchingLoaded','NextHomeWorkerId'].map(name => {
    const match = new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`, 'mi').exec(source);
    assert.ok(match, `Home callback ${name} exists`);
    return match[0];
  });
assert.match(read('components/HomeScreen.xml'), /Play\/Pause\s+Refresh/);
const out = path.join(root, 'out-test', 'home-refresh');
fs.mkdirSync(out, { recursive:true });
const file = path.join(out, 'home.brs');
fs.writeFileSync(file, [read('tests/harness.brs'), ...functions, read('tests/home-refresh.test.brs')].join('\n'));
const result = spawnSync(process.execPath, [path.join(root,'node_modules/@rokucommunity/brs/bin/cli.js'), '--root', out, file], { cwd:out, encoding:'utf8' });
process.stdout.write(result.stdout || ''); process.stderr.write(result.stderr || '');
process.exit(result.status === 0 && !(result.stderr || '').trim() && /RESULT: PASS/.test(result.stdout || '') ? 0 : 1);
