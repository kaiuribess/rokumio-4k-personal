// Run the real Details/Episodes completion handlers with controlled event nodes.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
function extract(file, name) {
    const match = new RegExp(`\\b(?:sub|function) ${name}\\([^]*?\\nend (?:sub|function)`, 'i').exec(read(file));
    assert.ok(match, name);
    return match[0];
}
const functions = [extract('components/DetailsScreen.brs', 'onMetaLoaded'), ...['onSeriesLoaded', 'EpisodesVisibleRows', 'SetEpisodeHelp', 'PushEpisode', 'EpisodePrefetchParams', 'onKeyEvent'].map(name => extract('components/EpisodesScreen.brs', name))];
assert.match(read('components/DetailsScreen.brs'), /"detailsMetaLoader"\s*\+\s*m\.metaTaskSequence\.ToStr\(\)/);
assert.match(read('components/EpisodesScreen.brs'), /"episodesLoader"\s*\+\s*m\.seriesTaskSequence\.ToStr\(\)/);
const combined = path.join(root, 'out-test', 'meta-tests', '_meta.brs');
fs.mkdirSync(path.dirname(combined), { recursive: true });
fs.writeFileSync(combined, [read('tests/harness.brs'),read('source/util/ProviderPriority.brs'),read('source/util/MetadataOrigin.brs'), read('source/util/SourcePrefetch.brs'), ...functions, read('tests/meta-ui.test.brs')].join('\n'));
const result = spawnSync(process.execPath, [path.join(root, 'node_modules', '@rokucommunity', 'brs', 'bin', 'cli.js'), '--root', path.dirname(combined), combined], { cwd: path.dirname(combined), encoding: 'utf8' });
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
process.exit(result.status === 0 && !(result.stderr || '').trim() && /RESULT: PASS/.test(result.stdout || '') ? 0 : 1);
