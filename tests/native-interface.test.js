// Native callFunc rejects the long positional resume call even though the
// desktop interpreter accepts it. Enforce a conservative component boundary.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const {Parser, ParseMode, createVisitor, WalkMode} = require('brighterscript');
const root = path.resolve(__dirname, '..');
let calls = 0, resumeCalls = 0;
for (const directory of ['components', 'source']) {
    for (const name of fs.readdirSync(path.join(root, directory), {recursive:true})) {
        if (!/\.(bs|brs)$/.test(name)) continue;
        const file = path.join(directory, name);
        const parsed = Parser.parse(fs.readFileSync(path.join(root, file), 'utf8'), {mode:ParseMode.BrighterScript});
        parsed.ast.walk(createVisitor({CallExpression(node) {
            if (node.callee.name?.text?.toLowerCase() !== 'callfunc') return;
            calls++;
            assert.ok(node.args.length <= 7, `${file}:${node.range.start.line+1}: use a record instead of a long callFunc argument list`);
            if (node.args[0]?.token?.text === '"LibrarySetPosition"') {
                resumeCalls++;
                assert.equal(node.args.length, 2, `${file}: resume must use one data record`);
            }
        }}), {walkMode:WalkMode.visitAllRecursive});
    }
}
assert.ok(resumeCalls >= 2, 'Both player checkpoint and account replay boundaries were inspected');
assert.match(fs.readFileSync(path.join(root,'components/StoreHost.brs'),'utf8'), /function LibrarySetPosition\(packet as dynamic\)/);
const player = fs.readFileSync(path.join(root,'components/PlayerScreen.brs'),'utf8');
assert.match(player, /subtitlePrefs\.onlineSubtitles = true then StartSubtitles/);
assert.match(player, /ObserveField\("streamingSegment", "onStreamingSegmentChanged"\)/);
assert.doesNotMatch(player, /\bm\.video\.streamingSegment\b/, 'Do not poll a cached previous-file segment in codec/state callbacks');
console.log(`Native component contract: ${calls} calls checked; ${resumeCalls} resume boundaries use one record; online captions require opt-in.`);
