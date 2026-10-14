// Execute the actual screen's pure import/capability functions with a scene API
// double. SceneGraph rendering and Roku OS keyboards still need device checks.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'components/AddonsScreen.brs'), 'utf8');
const functions = ['StartInstall', 'RefreshInstalledRows', 'AddonAdvertises', 'AddonCapabilityText'].map(name => {
    const match = new RegExp('(?:sub|function) ' + name + '\\([^]*?\\nend (?:sub|function)', 'i').exec(source);
    assert.ok(match, name + ' exists');
    return match[0];
});
assert.doesNotMatch(source, /value\s*=\s*addon\.address/, 'configured address must never appear as a row value');
assert.doesNotMatch(source, /AsyncTask_Launch/, 'screen must use the scene import slot');
assert.match(source, /editor\.voiceEnabled\s*=\s*false/, 'setup links do not enter voice dictation');
const runner = `
sub BuildRows()
    m.rebuilds = m.rebuilds + 1
end sub
sub Test_AddonsScreen()
    Harness_Suite("Add-ons keyboard shares the scene import slot")
    m.scene = { active: false, requests: 0, address: "" }
    m.scene.callFunc = function(name as string, address as string) as boolean
        if name <> "ImportFromSetup" or m.active then return false
        m.active = true
        m.requests = m.requests + 1
        m.address = address
        return true
    end function
    m.top = { scene: m.scene }
    m.top.getScene = function() as object
        return m.scene
    end function
    m.stores = {}
    m.status = { text: "" }
    m.rebuilds = 0
    StartInstall("  https://source.example/fixture-private/manifest.json  ")
    Harness_Equal(m.scene.requests, 1, "manual URL goes through scene API once")
    Harness_Equal(m.scene.address, "https://source.example/fixture-private/manifest.json", "paste whitespace removed")
    Harness_Ok(m.status.text.InStr("Installing") >= 0, "accepted import has progress feedback")
    Harness_Ok(m.status.text.InStr("fixture-private") < 0, "status does not show configured path")
    StartInstall("https://other.example/manifest.json")
    Harness_Equal(m.scene.requests, 1, "busy scene rejects another install without another request")
    Harness_Ok(m.status.text.InStr("already installing") >= 0, "busy import explains how to recover")
    RefreshInstalledRows()
    Harness_Equal(m.rebuilds, 1, "completed browser import refreshes open list")
    Harness_Equal(m.status.text, "", "completion clears obsolete installing feedback")
    source = { address: "https://source.example/fixture-private?token=fixture", resources: ["catalog", { name: "stream" }] }
    label = AddonCapabilityText(source)
    Harness_Ok(label.InStr("Streams") >= 0 and label.InStr("Catalogs") >= 0, "configured source shows its usable capabilities")
    Harness_Ok(label.InStr("fixture") < 0 and label.InStr("https") < 0, "capability label contains no configured URL")
    Harness_Ok(not AddonAdvertises({ resources: ["meta"] }, "stream"), "metadata-only addon is not described as a stream source")
    Harness_Finish()
end sub
Test_AddonsScreen()
`;
const isolated = path.join(root, 'out-test/nativeaddons-screen');
fs.mkdirSync(isolated, { recursive: true });
const combined = path.join(isolated, '_addons.brs');
fs.writeFileSync(combined, [fs.readFileSync(path.join(root, 'tests/harness.brs'), 'utf8'), ...functions, runner].join('\n'));
const result = spawnSync(process.execPath, [path.join(root, 'node_modules/@rokucommunity/brs/bin/cli.js'), '--root', isolated, combined], { cwd: isolated, encoding: 'utf8' });
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
process.exit(result.status === 0 && !(result.stderr || '').trim() && /RESULT: PASS/.test(result.stdout || '') ? 0 : 1);
