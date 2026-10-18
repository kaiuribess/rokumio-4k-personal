// Runs the actual Discover callbacks, launch/cancel flow, grid and selection.
// Native factories and task/store/UI services are boundary mocks. This is not
// device rendering or a claim about Roku hardware behavior.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const source = read('components/DiscoverScreen.brs');
const names = ['CatalogSignature', 'EnsureSources', 'onSourcesLoaded', 'onDiscoverLoaded',
    'OnEnter', 'RefreshDiscoverIfStale', 'BlurFocus',
    'NextDiscoverWorkerId', 'DiscoverText', 'DiscoverUsableMetas', 'DiscoverVisibleRows',
    'FetchDiscover', 'DiscoverPageSize', 'DiscoverBoundedCount', 'LoadMore', 'ResetDiscover', 'UpdateGrid', 'AppendRestorePosition',
    'onResultSelected', 'onGridFocused', 'onKeyEvent', 'LandingChipsFocus', 'CancelLoad', 'CancelSources'];
const functions = names.map(name => {
    const match = new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`, 'mi').exec(source);
    assert.ok(match, `Discover entry point ${name} exists`);
    return match[0].replace(/CreateObject\(/gi, 'MockDiscoverNativeObject(');
});
assert.match(source, /m\.workerSequence\s*=\s*0/);
assert.doesNotMatch(source, /},\s*"(?:catalogSources|discoverLoader|discoverLoaderMore)"\)/);
const xml = read('components/DiscoverScreen.xml');
const grid = /<RowList\s+id="discoverGrid"[^]*?\/>/.exec(xml)[0];
const y = Number(/translation="\[\d+, (\d+)\]"/.exec(grid)[1]);
assert.ok(y + 650 <= 1080, 'Discover viewport budget fits the existing screen');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'rokumio-discover-test-'));
try {
    const combined = path.join(temporary, 'discover.brs');
    fs.writeFileSync(combined, [read('tests/harness.brs'), read('source/core/TileSize.bs'),
        ...functions, read('tests/discover-ui.test.brs')].join('\n'));
    const result = spawnSync(process.execPath, [path.join(root, 'node_modules', '@rokucommunity', 'brs', 'bin', 'cli.js'),
        '--root', temporary, combined], { cwd: temporary, encoding: 'utf8' });
    process.stdout.write(result.stdout || '');
    process.stderr.write(result.stderr || '');
    process.exitCode = result.status === 0 && !(result.stderr || '').trim() && /RESULT: PASS/.test(result.stdout || '') ? 0 : 1;
} finally {
    const resolved = path.resolve(temporary);
    assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
    assert.ok(path.basename(resolved).startsWith('rokumio-discover-test-'));
    fs.rmSync(resolved, { recursive: true, force: true });
}
