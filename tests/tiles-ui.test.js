// Exercise production tile callbacks; only native SceneGraph fields are mocked.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
function scoped(file, prefix) {
    let source = read(file);
    const names = [...source.matchAll(/^(?:sub|function) (\w+)\(/gmi)].map(match => match[1]);
    for (const name of names) source = source.replace(new RegExp(`\\b${name}\\b`, 'g'), prefix + name);
    return source;
}
for (const file of ['components/ChipTile.xml', 'components/PosterTile.xml']) {
    assert.doesNotMatch(read(file), /vertAlign="middle"/, 'Native Label uses center for vertical alignment');
}
assert.match(read('components/PosterTile.xml'), /id="captionText"[^]*?maxLines="2"/);
const isolated = path.join(root, 'out-test', 'tiles-ui');
fs.mkdirSync(isolated, { recursive: true });
const combined = path.join(isolated, 'tiles-tests.brs');
fs.writeFileSync(combined, [read('tests/harness.brs'), read('source/core/Theme.bs'),
    scoped('components/ChipTile.brs', 'Chip_'), scoped('components/PosterTile.brs', 'Poster_'),
    read('tests/tiles-ui.test.brs')].join('\n'));
const result = spawnSync(process.execPath, [path.join(root, 'node_modules/@rokucommunity/brs/bin/cli.js'),
    '--root', isolated, combined], { cwd: isolated, encoding: 'utf8' });
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
process.exit(result.status === 0 && !(result.stderr || '').trim() && /RESULT: PASS/.test(result.stdout || '') ? 0 : 1);
