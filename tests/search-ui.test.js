// Executes the real Search callbacks/model with mocked nodes. This verifies
// stale events, result selection and focus policy without claiming Roku rendering.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
function extract(file, name) {
    const match = new RegExp(`\\b(?:sub|function) ${name}\\([^]*?\\nend (?:sub|function)`, 'i').exec(read(file));
    assert.ok(match, `${name} must exist`);
    return match[0];
}
const functions = ['onSourcesLoaded', 'onSearchLoaded', 'RebuildRows', 'SearchUsableMetas', 'SearchText', 'RestoreSearchFocus', 'NextSearchWorkerId', 'SearchVisibleRows', 'SearchCellSize', 'onSearchDialogClosed', 'onResultSelected']
    .map((name) => extract('components/SearchScreen.brs', name));
functions.push(extract('components/HomeScreen.brs', 'HomeVisibleRows'), extract('components/HomeScreen.brs', 'RowCellSize'));
const home = read('components/HomeScreen.brs');
assert.doesNotMatch(home, /m\.rail\.jumpToItem\s*=\s*0/);
assert.doesNotMatch(home, /m\.catalog\.numRows\s*=\s*m\.gridRows\.Count\(\)/);
assert.doesNotMatch(read('components/SearchScreen.brs'), /m\.results\.numRows\s*=\s*m\.rows\.Count\(\)/);
// Two portrait rows fit above Search's persistent controls, including one gap.
for (const component of ['HomeScreen', 'SearchScreen']) {
    const xml = read(`components/${component}.xml`);
    const grid = /<RowList\s+id="(?:catalog|searchResults)"[^]*?\/>/.exec(xml)[0];
    const y = Number(/translation="\[\d+, (\d+)\]"/.exec(grid)[1]);
    const height = Number(/itemSize="\[\d+, (\d+)\]"/.exec(grid)[1]);
    const gap = Number(/itemSpacing="\[\d+, (\d+)\]"/.exec(grid)[1]);
    assert.ok(y + height * 2 + gap <= 990, `${component} rows fit within viewport`);
}
const combined = path.join(root, 'out-test', 'ui-tests', '_search.brs');
fs.mkdirSync(path.dirname(combined), { recursive: true });
fs.writeFileSync(combined, [read('tests/harness.brs'), read('source/core/TileSize.bs'), ...functions, read('tests/search-ui.test.brs')].join('\n'));
const result = spawnSync(process.execPath, [path.join(root, 'node_modules', '@rokucommunity', 'brs', 'bin', 'cli.js'), '--root', path.dirname(combined), combined], { cwd: path.dirname(combined), encoding: 'utf8' });
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
process.exit(result.status === 0 && !(result.stderr || '').trim() && /RESULT: PASS/.test(result.stdout || '') ? 0 : 1);
