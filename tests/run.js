// node tests/run.js — transpile BSL sources and run the brs test suite.
//
// The brs interpreter cannot parse BrighterScript `class` syntax, so the BSL
// class under test is transpiled to BrightScript first (brighterscript API,
// createPackage:false) into a throwaway staging dir, then handed to brs along
// with the plain-BrightScript harness and suites. The process exit code is the
// brs exit code, so `npm test` fails when any assertion fails.
const path = require('path');
const { spawnSync } = require('child_process');
const { ProgramBuilder } = require('brighterscript');

const projectRoot = path.resolve(__dirname, '..');
const stagingDir = path.join(projectRoot, 'out-test');

// The brs interpreter gives every file its own module scope, so top-level
// harness state would not be shared across files. The harness + suites + runner
// are concatenated into one script (functions are hoisted within a program) so
// the tally lives in a single scope.
const combinedPath = path.join(stagingDir, 'tests', '_combined.brs');
async function writeCombinedScript() {
    const fs = require('fs');
    const parts = [
        'tests/harness.brs',
        'tests/mocks.brs',
        'components/NetDiagTask.brs',
        'tests/screenstack.test.brs',
        'tests/transport.test.brs',
        'tests/settingsstore.test.brs',
        'tests/authstore.test.brs',
        'tests/addonsstore.test.brs',
        'tests/addonsync.test.brs',
        'tests/stremioauthstore.test.brs',
        'tests/catalogstore.test.brs',
        'tests/deeplinkstore.test.brs',
        'tests/episodesstore.test.brs',
        'tests/librarystore.test.brs',
        'tests/librarysync.test.brs',
        'tests/watchstatepush.test.brs',
        'tests/librarywritepush.test.brs',
        'tests/logouttask.test.brs',
        'tests/stremioapistore.test.brs',
        'tests/linkcode.test.brs',
        'tests/playbackstore.test.brs',
        'tests/subtitlesstore.test.brs',
        'tests/netdiagverdict.test.brs',
        'tests/setuppage.test.brs',
        'tests/nativeaddons.test.brs',
        'tests/watchedcodec.fixtures.brs',
        'tests/watchedcodec.test.brs',
        'tests/videoidcodec.test.brs',
        'tests/timeutil.test.brs',
        'tests/emojilabel.test.brs',
        'tests/watchstatebuffer.test.brs',
        'tests/stremiolibrarycodec.test.brs',
        'source/core/TileSize.bs',
        'tests/tilesize.test.brs',
        'tests/_run.brs'
    ].map(rel => fs.readFileSync(path.join(projectRoot, rel), 'utf8'));
    fs.mkdirSync(path.dirname(combinedPath), { recursive: true });
    fs.writeFileSync(combinedPath, parts.join('\n'));
}

const transpiled = [
    path.join(stagingDir, 'source', 'bslib.brs'),
    path.join(stagingDir, 'source', 'core', 'ScreenStack.brs'),
    path.join(stagingDir, 'source', 'stores', 'Transport.brs'),
    path.join(stagingDir, 'source', 'stores', 'SettingsStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'AuthStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'AddonsStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'CatalogStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'DeepLinkStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'VideoIdCodec.brs'),
    path.join(stagingDir, 'source', 'stores', 'EpisodesStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'TimeUtil.brs'),
    path.join(stagingDir, 'source', 'stores', 'WatchStateBuffer.brs'),
    path.join(stagingDir, 'source', 'stores', 'StremioLibraryCodec.brs'),
    path.join(stagingDir, 'source', 'stores', 'LibraryStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'StremioApiStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'PlaybackStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'SubtitlesStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'WatchedCodec.brs'),
    path.join(stagingDir, 'source', 'util', 'Regex.brs'),
    path.join(stagingDir, 'source', 'util', 'SetupPage.brs'),
    path.join(stagingDir, 'source', 'util', 'Utilities.brs')
];

function checkDeferredVideoPlayContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'PlayerScreen.xml'), 'utf8');
    const src = fs.readFileSync(path.join(projectRoot, 'components', 'PlayerScreen.brs'), 'utf8');
    const code = src.split('\n').map((line) => line.split("'")[0]).join('\n');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    if (!/<Timer\s+id="playKick"/.test(xml)) {
        err('PlayerScreen.xml declares no <Timer id="playKick" /> — StartPlayback defers `control = "play"` across it, so without it the player is never asked to play at all');
    }
    if (!/FindNode\(\s*"playKick"\s*\)/.test(code)) {
        err('PlayerScreen.brs never looks up the playKick Timer — the node exists in the XML but nothing holds it, so nothing can start it');
    }
    if (!/ObserveField\(\s*"fire"\s*,\s*"onPlayKickFire"\s*\)/.test(code)) {
        err('PlayerScreen.brs does not ObserveField("fire", "onPlayKickFire") on the playKick Timer — an unobserved Timer fires into nothing and the deferred play never happens');
    }
    const kick = new RegExp('^[ \\t]*sub\\s+onPlayKickFire\\s*\\(', 'm').exec(code);
    if (!kick) {
        err('PlayerScreen.brs has no onPlayKickFire() — the field observer names a handler that does not exist, which is a no-op, so the deferred play never happens');
    } else {
        const rest = code.slice(kick.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+sub\b/m);
        const body = end === -1 ? rest : rest.slice(0, end + 1);
        if (!/m\.video\.control\s*=\s*"play"/.test(body)) {
            err('PlayerScreen.brs onPlayKickFire() never sets m.video.control = "play" — the timer fires and does nothing');
        }
    }

    // And the assignment must not still be sitting in the same tick, which is
    // the thing being fixed. A play inside StartPlayback is only allowed as the
    // fallback for a missing Timer, and only after the timer has been offered.
    const start = new RegExp('^[ \\t]*sub\\s+StartPlayback\\s*\\(', 'm').exec(code);
    if (!start) {
        err('PlayerScreen.brs has no StartPlayback()');
    } else {
        const rest = code.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+sub\b/m);
        const body = end === -1 ? rest : rest.slice(0, end + 1);
        const contentAt = body.indexOf('m.video.content =');
        const kickAt = body.indexOf('m.playTimer.control = "start"');
        for (const hit of body.matchAll(/m\.video\.control\s*=\s*"play"/g)) {
            if (kickAt === -1) {
                err('PlayerScreen.brs StartPlayback plays without ever starting the playKick timer — remove the deferral entirely or restore it, but do not leave a play that only runs in some paths');
            } else if (hit.index < kickAt) {
                err('PlayerScreen.brs StartPlayback sets m.video.control = "play" before the playKick timer is started — the play is back on the same tick as the content assignment, which is the race this was split to remove');
            }
        }
        if (contentAt === -1) {
            err('PlayerScreen.brs StartPlayback never assigns m.video.content — the deferral guard has nothing to protect');
        }
        // The other way this can rot silently: with the kick gone AND the
        // fallback play gone, there is no `control = "play"` left in StartPlayback
        // at all and the loop above has nothing to complain about — but nothing
        // ever asks the node to play. Either the timer carries the play or
        // StartPlayback does; never neither.
        if (kickAt === -1 && !/m\.video\.control\s*=\s*"play"/.test(body)) {
            err('PlayerScreen.brs StartPlayback neither starts the playKick timer nor sets control = "play" itself — the video is never asked to play by any path');
        }
    }
    return ok;
}

function checkScreenRuntimeHazards() {
    const fs = require('fs');
    const dir = path.join(projectRoot, 'components');
    let ok = true;
    for (const file of fs.readdirSync(dir).filter((f) => f.endsWith('.brs'))) {
        const src = fs.readFileSync(path.join(dir, file), 'utf8');
        const code = src.split('\n').map((line) => line.split("'")[0]).join('\n');

        // Members this same file assigns [] are arrays; anything else named m.x
        // is left alone rather than guessed at.
        const arrays = new Set([...code.matchAll(/\b(m\.[A-Za-z_][\w.]*)\s*=\s*\[\]/g)].map((hit) => hit[1]));
        for (const hit of code.matchAll(/\bLen\(\s*(m\.[A-Za-z_][\w.]*)/g)) {
            if (arrays.has(hit[1])) {
                console.error(`${file}: Len(${hit[1]}) — ${hit[1]} is assigned [] in this file, so it is an array. Len() on an array is a runtime type mismatch (&h18) that aborts the enclosing function; use ${hit[1]}.Count()`);
                ok = false;
            }
        }

        for (const hit of code.matchAll(/CreateObject\(\s*"(roFileSystem)"\s*\)/g)) {
            console.error(`${file}: creates ${hit[1]}, which is MAIN|TASK-only. Screen callbacks include the Video node's state and bufferingStatus handlers, which arrive on the RENDER thread, so this fails there and takes the handler down with it. Read the value you need from m, or hand the work to a Task.`);
            ok = false;
        }

        // An roSGNode Timer is driven through its `control` field ("start" /
        // "stop"); it has no Start()/Stop() methods, and calling one is a
        // runtime &hf4 "Member function not found". Both timers in PlayerScreen
        // are armed the same way, and the first version of the playKick deferral
        // called Start() on it, which threw inside StartPlayback and stopped the
        // player dead — the one function that must never throw. Resolve the
        // member back to the node it holds so a Timer is only flagged when it
        // really is one.
        const xmlPath = path.join(dir, file.replace(/\.brs$/, '.xml'));
        if (!fs.existsSync(xmlPath)) continue;
        const xml = fs.readFileSync(xmlPath, 'utf8');
        for (const bind of code.matchAll(/\b(m\.[A-Za-z_][\w]*)\s*=\s*m\.top\.FindNode\(\s*"([^"]+)"\s*\)/g)) {
            if (!new RegExp(`<Timer\\s+id="${bind[2]}"`).test(xml)) continue;
            for (const call of code.matchAll(new RegExp(`\\b${bind[1].replace('.', '\\.')}\\.(Start|Stop)\\s*\\(`, 'g'))) {
                console.error(`${file}: calls ${bind[1]}.${call[1]}() on the "${bind[2]}" Timer. An roSGNode Timer has no such methods — it is armed with \`control = "start"\` / \`control = "stop"\`, as this file's other Timer already is. Calling one is a runtime &hf4 that aborts whatever function it sits in.`);
                ok = false;
            }
        }
    }
    return ok;
}

function checkScreenContract() {
    const fs = require('fs');
    const contract = ['SetStores', 'OnEnter', 'OnExit', 'OnBackPressed', 'BlurFocus'];
    const screens = ['HomeScreen', 'DetailsScreen', 'EpisodesScreen', 'StreamsScreen', 'PlayerScreen', 'SettingsScreen', 'AddonsScreen', 'SearchScreen', 'DiscoverScreen', 'LibraryScreen', 'AuthScreen', 'LinkStremioScreen', 'AddonHealthScreen', 'AboutScreen'];
    const declaredSet = (name) => {
        const xml = fs.readFileSync(path.join(projectRoot, 'components', `${name}.xml`), 'utf8');
        return new Set([...xml.matchAll(/<function\s+name="([^"]+)"\s*\/?>/gi)].map(match => match[1]));
    };
    let ok = true;
    const base = declaredSet('Screen');
    for (const fn of contract) {
        if (!base.has(fn)) {
            console.error(`Screen.xml (the base) is missing <function name="${fn}" /> from its interface`);
            ok = false;
        }
    }
    for (const name of screens) {
        const xml = fs.readFileSync(path.join(projectRoot, 'components', `${name}.xml`), 'utf8');
        if (!/<component[^>]*extends="Screen"/.test(xml)) {
            console.error(`${name}.xml must extends="Screen" so it inherits the base contract`);
            ok = false;
        }
        const src = fs.readFileSync(path.join(projectRoot, 'components', `${name}.brs`), 'utf8');
        for (const fn of contract) {
            if (!declaredSet(name).has(fn)) continue;
            if (!new RegExp(`function\\s+${fn}\\s*\\(`).test(src)) {
                console.error(`${name}.xml declares <function name="${fn}" /> but ${name}.brs has no implementation`);
                ok = false;
            }
        }
    }
    return ok;
}

// Roku copies any associative array that crosses a component boundary — a
// callFunc argument, a callFunc return value, an interface field — and drops its
// function members. A bsc class instance IS such an array, so handing the store
// facade to a screen used to deliver a data-only copy: every method call died
// with &hf4 "Member function not found in BrightScript Component or interface"
// (this bit us on device at HomeScreen.brs `m.stores.addons.GetAll()`, and the
// data-only copy still satisfied every `m.stores = invalid` guard, so nothing
// upstream noticed). Only nodes cross by reference, so the Scene keeps the
// facade in an UNDECLARED field and hands each screen the SCENE NODE; the screen
// reads storeFacade off that node. Passing the facade itself is the same
// mistake, and so is declaring the field: a declared field marshals exactly like
// a callFunc argument.
// Two dead ends are pinned here so nobody walks them again. GetGlobalAA() is per
// component on this device, not app-wide, so every screen read back its own
// empty AA ("0 add-ons") while the Scene's own store kept working — the
// deep-link import installs through it. And m.top.getScene() is invalid at
// bind time: init() runs inside screen.CreateScene(), and roSGNode.GetScene()
// returns invalid until screen.Show() has put the tree in a scene, so the
// look-it-up-yourself variant bound invalid on every screen and hid behind the
// guards again. CreateObject("roGlobal") is a BrightSign component that does
// not exist on Roku: CreateObject returns invalid, which the compiler also
// rejects as BS1129.
// The interpreter models one flat scope and cannot catch any of this, so pin it
// statically — and pin the reporting, too: every way the hand-off fails looks
// the same from outside (empty grid, "0 add-ons", no crash, nothing in the log),
// so SetStores has to name the failure on screen. `print` cannot do that job, not
    // because it is invisible to an engineering session but because it is not
    // painting anything: it only reaches whoever is attached to the console at the
    // time, and by the time a bug is investigated that session is long gone.
function checkStoreHandoffContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    // Scan code, not prose: the files document this exact contract in their
    // headers, and a raw-text scan matches the documentation describing the bug.
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const readBr = (n) => code(fs.readFileSync(path.join(projectRoot, 'components', n), 'utf8'));
    const dir = path.join(projectRoot, 'components');
    const mainScene = readBr('MainScene.brs');
    const screenBrs = readBr('Screen.brs');
    const hostBrs = readBr('StoreHost.brs');
    const hostXml = fs.readFileSync(path.join(dir, 'StoreHost.xml'), 'utf8');
    const sceneXml = fs.readFileSync(path.join(dir, 'MainScene.xml'), 'utf8');
    const sceneScreenXml = fs.readFileSync(path.join(dir, 'Screen.xml'), 'utf8');
    const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
    const bodyOf = (src, header) => {
        const start = src.indexOf(header) + header.length;
        return src.slice(start, src.indexOf('\nend ', start));
    };
    // Split a BrightScript argument or parameter list on its TOP-LEVEL commas,
    // so `{ a: 1, b: 2 }` or `[[0, 10]]` counts as the one argument it is.
    const splitTop = (text) => {
        const out = [];
        let depth = 0, quote = false, cur = '';
        for (const ch of text) {
            if (quote) { cur += ch; if (ch === '"') quote = false; continue; }
            if (ch === '"') { quote = true; cur += ch; }
            else if ('[{('.includes(ch)) { depth++; cur += ch; }
            else if (']})'.includes(ch)) { depth--; cur += ch; }
            else if (ch === ',' && depth === 0) { out.push(cur.trim()); cur = ''; }
            else cur += ch; }
        if (cur.trim().length > 0) out.push(cur.trim());
        return out;
    };
    // The argument text of the callFunc whose "(" is at `from`, up to the paren
    // that closes it, or null if that paren is not on the same line. Bounded to
    // one line on purpose: the comment stripper above truncates at the first
    // apostrophe, so a three-line scan could be thrown off by a string literal
    // elsewhere in the file, and no call site in this codebase wraps a line.
    const callArgs = (src, from) => {
        let depth = 1, quote = false;
        for (let i = from; i < src.length; i++) {
            const ch = src[i];
            if (ch === '\n') return null;
            if (quote) { if (ch === '"') quote = false; continue; }
            if (ch === '"') quote = true;
            else if (ch === '(') depth++;
            else if (ch === ')' && --depth === 0) return src.slice(from, i);
        }
        return null;
    };

    // --- the host exists, and exists before anything binds to it -------------
    if (!/m\.storeHost\s*=\s*CreateObject\(\s*"roSGNode"\s*,\s*"StoreHost"\s*\)/.test(mainScene)) {
        err('MainScene.brs never creates the StoreHost node — screens would have nothing to read data through');
    }
    if (!/m\.top\.AppendChild\(m\.storeHost\)/.test(mainScene)) {
        err('MainScene.brs must attach the StoreHost to the Scene (m.top.AppendChild(m.storeHost)) — a node component nothing holds a reference to is not guaranteed to stay alive');
    }
    const create = mainScene.search(/m\.storeHost\s*=\s*CreateObject/);
    const firstBind = mainScene.search(/callFunc\(\s*"SetStores"/);
    if (create !== -1 && firstBind !== -1 && firstBind < create) {
        err('MainScene.brs binds a screen before creating the StoreHost — that screen would read invalid');
    }

    // --- every bind hands over two nodes, and every screen gets one ---------
    let binds = 0;
    for (const m of mainScene.matchAll(/callFunc\(\s*"SetStores"\s*,\s*([^)]*)\)/g)) {
        binds++;
        const args = m[1].split(',').map(a => a.trim()).filter(a => a.length > 0);
        if (args.length !== 2 || args[0] !== 'm.storeHost' || args[1] !== 'm.top') {
            err(`MainScene.brs passes "${m[1].trim()}" through callFunc("SetStores", ...) — only a node crosses a component boundary by reference, so the bind must pass m.storeHost (the data layer) and m.top (the Scene, which owns the fault strip)`);
        }
    }
    // Screen.xml is the base every screen extends, not an instance of one.
    const screens = fs.readdirSync(dir).filter(f => /Screen\.xml$/.test(f) && f !== 'Screen.xml');
    if (binds < screens.length) {
        err(`MainScene.brs makes ${binds} SetStores binds for ${screens.length} screen components — an unbound screen comes up with an empty grid and no way to tell why`);
    }

    // --- the host is a delegation layer, not a second MainScene -------------
    const STORES = ['addons', 'auth', 'episodes', 'library', 'settings', 'time', 'watch'];
    const defined = new Set([...hostBrs.matchAll(/^(?:function|sub)\s+(\w+)\s*\(/gm)].map(m => m[1]));
    const declared = new Set([...hostXml.matchAll(/<function\s+name="([^"]+)"/g)].map(m => m[1]));
    const own = new Set(['EffectiveSessionType', 'SwitchSession', 'LibrarySessionType']);
    for (const m of hostBrs.matchAll(/^function\s+(\w+)\s*\([^)]*\)(?: as \w+)?\s*$/gm)) {
        const name = m[1];
        if (own.has(name)) continue;
        const body = bodyOf(hostBrs, m[0]).split('\n').map(l => l.trim()).filter(l => l.length > 0);
        if (body.length !== 1) {
            err(`StoreHost.brs ${name} has ${body.length} statements — the host forwards, it does not decide. Logic belongs in the store class, where the store tests can reach it`);
            continue;
        }
        if (!/^(return )?m\.stores\.[a-z]+\.[A-Za-z_]+\(.*\)$/.test(body[0])) {
            err(`StoreHost.brs ${name} must be exactly "return m.stores.<store>.<Method>(...)" (no return for a void store method) — anything else is logic in the hand-off layer (got: ${body[0]})`);
            continue;
        }
        // The name says which store it answers for; the body has to agree, or a
        // copy-paste between two same-shaped forwarders hands a screen the
        // wrong store's data and nothing complains.
        const store = STORES.find(s => name.startsWith(cap(s)));
        if (!store) {
            err(`StoreHost.brs ${name} has no store prefix — entry points are named <Store><Method> so the call site says which store it is asking`);
        } else if (!new RegExp('^(return )?m\\.stores\\.' + store + '\\.[A-Za-z_]+\\(').test(body[0])) {
            err(`StoreHost.brs ${name} forwards to a different store than its name claims — screens reach it as m.stores.${store} and would be handed another store's data`);
        }
    }
    for (const n of declared) {
        if (!defined.has(n)) {
            err(`StoreHost.xml declares <function name="${n}" /> but StoreHost.brs does not define it — callFunc against an undefined function is a silent no-op that returns invalid`);
        }
    }
    for (const n of defined) {
        if (!declared.has(n) && n !== 'init') {
            err(`StoreHost.brs defines ${n} but StoreHost.xml does not declare it — callFunc only runs for interface functions, so every caller would get invalid back with nothing on screen to say so`);
        }
    }
    // Every script in a component shares one function namespace, and BrightScript
    // identifiers are case-insensitive, so an entry point whose name matches a
    // store's parameter makes the store's own signature ambiguous. bsc calls it
    // BS1104 and reports it in the store file, four files from the cause — so
    // the host's 48 new names have to be checked against the sources it pulls in.
    const sourceDir = path.join(projectRoot, 'source');
    const paramNames = new Set();
    const walk = (dir) => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) {
                walk(full);
            } else if (entry.name.endsWith('.bs')) {
                const src = fs.readFileSync(full, 'utf8');
                // Indented, because every store method sits inside a class block.
                for (const m of src.matchAll(/^[ \t]*(?:function|sub)\s+\w+\s*\(([^)]*)\)/gm)) {
                    for (const arg of m[1].split(',')) {
                        const name = arg.trim().split(/\s+as\s+/)[0].trim().toLowerCase();
                        if (name) paramNames.add(name);
                    }
                }
            }
        }
    };
    walk(sourceDir);
    for (const n of defined) {
        if (paramNames.has(n.toLowerCase())) {
            err(`StoreHost.brs defines ${n} and a store under source/ has a parameter by that name — one shared, case-insensitive function namespace, so the store's own signature becomes ambiguous (bsc: BS1104, reported in the store's file)`);
        }
    }

    // The name in a callFunc is a string, so nothing but a static check stands
    // between a typo and the device's &hf4 "Member function not found", and an
    // argument count the entry point does not take fails the same way one hop
    // later. Both are checked below, against the signatures the host actually
    // declares. This is the check that would have caught the four
    // Library Mark* calls EpisodesScreen made on a store that had no entry
    // points for them at all — those shipped to the TV and killed the debugger
    // on the first mark-as-watched press.
    const hostSigs = new Map();
    for (const m of hostBrs.matchAll(/^(?:function|sub)\s+(\w+)\s*\(([^)]*)\)/gm)) {
        hostSigs.set(m[1], splitTop(m[2]).map(p => ({ text: p, required: p.split(/\s+as\s+/)[0].indexOf('=') === -1 })));
    }
    // --- every store call resolves, and no store instance is ever in flight --
    for (const name of fs.readdirSync(dir).filter(f => f.endsWith('.brs'))) {
        if (name === 'StoreHost.brs') continue;
        const src = readBr(name);
        for (const m of src.matchAll(/\bm\.(stores\.[a-z]+|storeHost)\.callFunc\(\s*"([A-Za-z_]+)"/g)) {
            const [, alias, fn] = m;
            if (!defined.has(fn) || !declared.has(fn)) {
                err(`${name} calls callFunc("${fn}") but the StoreHost has no such entry point — the screen would read invalid and render nothing`);
                continue;
            }
            if (alias.startsWith('stores.')) {
                const store = alias.slice('stores.'.length);
                if (!fn.startsWith(cap(store))) {
                    err(`${name} reaches m.stores.${store} for "${fn}" — the name's store prefix must match the alias, or a screen can quietly be handed another store's data`);
                }
            }
            const sig = hostSigs.get(fn);
            // The match ends on the entry point's NAME, so the callFunc "(" is
            // the last paren inside it, not one past the end: step from there to
            // just inside the argument list, where the scan starts at depth 1.
            const argText = callArgs(src, m.index + m[0].lastIndexOf('(') + 1);
            const given = argText === null ? null : splitTop(argText).slice(1);
            if (given === null) {
                err(`${name} calls callFunc("${fn}") with an argument list that never closes — read it as unverified, not as correct`);
            } else if (given.length > sig.length) {
                err(`${name} calls callFunc("${fn}") with ${given.length} arguments but StoreHost.brs ${fn} takes ${sig.length} (${sig.map(p => p.text).join(', ')}) — the VM raises an arity error at runtime, after the call has already left the screen`);
            } else if (given.length < sig.length) {
                const missing = sig.slice(given.length).filter(p => p.required);
                if (missing.length > 0) {
                    err(`${name} calls callFunc("${fn}") without ${missing.map(p => p.text).join(', ')} — StoreHost.brs ${fn} requires ${sig.length} arguments, and a call that omits a required one raises a runtime error`);
                }
            }
        }
        // A store alias stashed in a local is how the Mark* crash got through:
        // the call on the NEXT line was spelled `<local>.Method(`, which no
        // rewrite pattern and no direct-call check above can see, because the
        // alias is a hop away. The alias has to be spelled at the call site,
        // where it is greppable and where the store prefix is checkable.
        for (const m of src.matchAll(/=\s*m\.stores\.[a-z]+\s*$/gm)) {
            err(`${name} assigns a store alias to a variable — spell it at the call site instead (m.stores.${m[0].match(/stores\.([a-z]+)/)[1]}.callFunc("<Store><Method>", ...)). A local hides the store behind a name nothing resolves, so a direct call on it compiles, ships, and dies with &hf4 on the device`);
        }
        if (/=\s*m\.storeHost\s*$/m.test(src)) {
            err(`${name} assigns m.storeHost to a variable — same reason: keep the host spelled at the call site so every store call stays checkable`);
        }
        for (const m of src.matchAll(/\bm\.stores\.[a-z]+\.(?!callFunc\b)([A-Za-z_]+)\s*\(/g)) {
            err(`${name} calls m.stores.${m[1]} directly — a store class instance cannot be handed to another component (Roku copies the associative array and drops its function members); ask the host instead: m.stores.<store>.callFunc("<Store><Method>", ...)`);
        }
        if (/CreateObject\(\s*"roGlobal"/i.test(src) || /GetGlobalAA\(\)/.test(src)) {
            err(`${name} reaches for a global singleton (roGlobal / GetGlobalAA) — neither is shared across components on this device; use the StoreHost node`);
        }
    }

    // --- print is a tracing tool here, not a reporting channel ----------------
    // There used to be a blanket ban on `print` in every component, on the stated
    // grounds that "Roku routes BrightScript print to the Dev Console, not to the
    // device console". That premise is wrong: telnet 8085 IS the device console
    // log, so a print is read live by whoever has an engineering session
    // attached — which is exactly how the [subs]/[addons]/[resolve] traces were
    // read to diagnose the caption failures. Screen.brs says as much in its own
    // header, and a lint that contradicts the file it guards is worse than no
    // lint, because it teaches you to distrust the comment.
    //
    // What the ban was really proxying — do not use print INSTEAD OF painting a
    // fault — is already pinned, and better, by the checks on SetStores above
    // (probe the host, report the fault) and on the strip below (declared, built
    // in init, attached, written through its own fields, sets m.faultText.text).
    // Those say what a short bind has to produce; a print cannot produce any of
    // it, so banning print never added coverage — it only cost us the traces.
    //
    // print stays legal in components/*.brs. Following a worker across a task
    // boundary, or a three-state status down a retry loop, is what it is for.
    // The abandoned carrier, in any file. The host included: a StoreHost that
    // published a facade would be the same split-brain one layer down.
    for (const name of fs.readdirSync(dir).filter(f => f.endsWith('.brs'))) {
        if (/\bstoreFacade\b/.test(readBr(name))) {
            err(`${name} still refers to storeFacade — the facade-on-the-Scene carrier is gone; the StoreHost node is the hand-off`);
        }
    }

    // --- one instance per store, in one place --------------------------------
    // The stores StoreHost owns. DeepLinkStore is deliberately absent: the Scene
    // builds one per deep link and throws it away (DeepLinkStore().Parse(args)),
    // so there is no state to diverge.
    for (const cls of ['AuthStore', 'SettingsStore', 'AddonsStore', 'CatalogStore', 'EpisodesStore', 'LibraryStore', 'PlaybackStore', 'SubtitlesStore', 'WatchStateBuffer', 'TimeUtil']) {
        if (new RegExp('=\\s*(m\\.stores\\.[a-z]+\\s*=\\s*)?' + cls + '\\s*\\(').test(mainScene)) {
            err(`MainScene.brs constructs ${cls} — the data layer belongs to StoreHost. A second instance is a second copy of that store's in-memory state, which is how two screens end up disagreeing about the same session`);
        }
    }
    for (const name of fs.readdirSync(dir).filter(f => f.endsWith('.brs'))) {
        if (name === 'StoreHost.brs' || name === 'MainScene.brs') continue;
        for (const cls of ['LibraryStore', 'WatchStateBuffer']) {
            if (new RegExp('=\\s*' + cls + '\\s*\\(').test(readBr(name))) {
                err(`${name} constructs ${cls} — that store holds in-memory state, so a private instance is a second copy of it; only the stateless per-request wrappers may be built by a task or screen`);
            }
        }
    }

    // --- SetStores takes two nodes and probes the whole path -----------------
    const setStores = screenBrs.match(/^function\s+SetStores\s*\(([^)]*)\)/m);
    if (!setStores) {
        err('Screen.brs no longer defines SetStores — every screen would come up with no stores');
        return ok;
    }
    const args = setStores[1].split(',').map(a => a.trim()).filter(a => a.length > 0);
    if (args.length !== 2) {
        err(`Screen.brs SetStores must take exactly two nodes — the StoreHost to read through and the Scene to report to (found "${setStores[1].trim()}")`);
    }
    const body = bodyOf(screenBrs, setStores[0]);
    if (!/callFunc\(\s*"AddonsGetAll"/.test(body)) {
        err('Screen.brs SetStores must probe the host (callFunc("AddonsGetAll")) — a bind that cannot say which hop failed is the silence that hid three shipping bugs');
    }
    if (!/callFunc\(\s*"ReportStoreFault"/.test(body)) {
        err('Screen.brs SetStores must report a failed bind to the Scene (callFunc("ReportStoreFault", reason, active)) — otherwise a broken store layer is indistinguishable from an empty catalog');
    }
    if (/getScene\(\)/.test(screenBrs)) {
        err('Screen.brs calls getScene() — roSGNode.GetScene() returns invalid until screen.Show() has put the tree in a scene, which is after init(); bind from the nodes MainScene passes instead');
    }
    // screenActive is the stack's, and the only field a screen may declare: a
    // declared field copies its value, so a store handed over that way arrives
    // without its methods. The hand-off is the node, in a callFunc argument.
    for (const m of sceneScreenXml.matchAll(/<field\s+id="([^"]+)"/g)) {
        if (m[1] !== 'screenActive') {
            err(`Screen.xml declares <field id="${m[1]}"> — a declared field copies the value it is given, so anything live handed over that way arrives stripped; the store hand-off is the StoreHost node passed to SetStores`);
        }
    }

    // --- a reported fault has to be painted ----------------------------------
    if (!/<function\s+name="ReportStoreFault"\s*\/>/.test(sceneXml)) {
        err('MainScene.xml must declare <function name="ReportStoreFault" /> — callFunc only runs for interface functions, so every screen\'s fault report would go nowhere');
    }
    const report = mainScene.match(/^sub\s+ReportStoreFault\s*\(/m);
    if (!report) {
        err('MainScene.brs no longer defines ReportStoreFault — every screen\'s fault report would hit a non-function');
    } else if (!/^\s*RefreshStoreFaultStrip\(\)\s*$/m.test(mainScene.slice(report.index))) {
        err('MainScene.brs ReportStoreFault must CALL RefreshStoreFaultStrip — a fault recorded but never shown is the bug, not the fix');
    }
    const paint = mainScene.match(/^sub\s+RefreshStoreFaultStrip\s*\(\)/m);
    if (!paint) {
        err('MainScene.brs no longer defines RefreshStoreFaultStrip — a reported fault would never reach the screen');
        return ok;
    }
    const paintBody = bodyOf(mainScene, paint[0]);
    const initHeader = mainScene.match(/^sub\s+init\s*\(\)\s*$/m);
    const initBody = initHeader ? bodyOf(mainScene, initHeader[0]) : '';
    for (const [field, node] of [['m.faultBar', 'Rectangle'], ['m.faultText', 'Label']]) {
        if (!new RegExp(field + '\\s*=\\s*CreateObject\\(\\s*"roSGNode"\\s*,\\s*"' + node + '"').test(initBody)) {
            err(`MainScene.brs init must create ${field} (${node}) — the strip is built once, up front`);
        }
        if (!new RegExp('m\\.top\\.AppendChild\\(' + field + '\\)').test(initBody)) {
            err(`MainScene.brs init must attach ${field} to the Scene — an unattached node renders nothing, which is the exact shape of the bug being fixed`);
        }
    }
    // What the first version actually shipped was one line, and it is worth
    // having on record because it is the shape that painted nothing:
    //     strip.FindNode("storeFaultText").text = reasons.Join("     ")
    // — a strip built lazily, a Label written through a FindNode after the
    // append, and the line joined from an array. On device the bar painted and
    // the label stayed blank. Which of the three was at fault was never
    // isolated, so all three stay pinned out: the strip is created in init,
    // written through the fields themselves, and the line is concatenated.
    if (/CreateObject\(/.test(paintBody) || /AppendChild\(/.test(paintBody)) {
        err('MainScene.brs RefreshStoreFaultStrip must only write to the strip nodes init() already built — creating or attaching a node at paint time is one of the three shapes that shipped as a blank label');
    }
    if (/FindNode\(/.test(paintBody)) {
        err('MainScene.brs RefreshStoreFaultStrip must write to m.faultBar / m.faultText directly, not look them up by id — m.linkLabel.text = link in LinkStremioScreen is the shape known to render here');
    }
    if (!/m\.faultText\.text\s*=/.test(paintBody)) {
        err('MainScene.brs RefreshStoreFaultStrip must set m.faultText.text — a bar with no text says nothing');
    }
    if (/\.Join\(/.test(paintBody)) {
        err('MainScene.brs RefreshStoreFaultStrip must build the line by concatenation, not Join() over an array — the third of the three shapes that shipped as a blank label');
    }
    return ok;
}

// Including the same script file twice in one component corrupts the shared
// function namespace at load time — a class that some other script then calls
// resolves to a non-function ("Function Call Operator ( ) attempted on
// non-function") on the device. This bit us with WatchedCodec.bs, so pin it:
// no component may repeat a script uri.
function checkNoDuplicateScripts() {
    const fs = require('fs');
    const components = fs.readdirSync(path.join(projectRoot, 'components')).filter(f => f.endsWith('.xml'));
    let ok = true;
    for (const name of components) {
        const xml = fs.readFileSync(path.join(projectRoot, 'components', name), 'utf8');
        const uris = [...xml.matchAll(/<script[^>]*uri="([^"]+)"/gi)].map(m => m[1]);
        const seen = new Set();
        for (const uri of uris) {
            if (seen.has(uri)) {
                console.error(`${name} includes <script uri="${uri}"> more than once — a duplicated script corrupts the component scope`);
                ok = false;
            }
            seen.add(uri);
        }
    }
    return ok;
}

// Roku scopes user-defined global functions per component, so a store method
// invoked from a screen's scope must never call a bare cross-file global —
// `WatchedCodec()` resolved to invalid at runtime inside EpisodeWatched that
// way. The interpreter cannot model this (run.js concatenates one scope), so
// pin it statically: LibraryStore may construct the codec exactly once, in
// new() (which runs under MainScene's scope), and must decode via the stored
// m.codec instance from then on.
function checkLibraryCodecContract() {
    const fs = require('fs');
    const src = fs.readFileSync(path.join(projectRoot, 'source', 'stores', 'LibraryStore.bs'), 'utf8');
    let ok = true;
    const constructors = [];
    for (const [i, line] of src.split('\n').entries()) {
        const code = line.split("'")[0];
        if (/\bWatchedCodec\s*\(/.test(code)) constructors.push(code.trim());
    }
    if (constructors.length !== 1) {
        console.error(`LibraryStore.bs must call WatchedCodec() exactly once, in new(); found ${constructors.length} call(s)`);
        ok = false;
    } else if (!/^m\.codec = WatchedCodec\(\)/.test(constructors[0])) {
        console.error(`LibraryStore.bs: the single WatchedCodec() call must be the m.codec capture in new() (found "${constructors[0]}")`);
        ok = false;
    }
    if (!/\bm\.codec\s*\.\s*WatchedDecode\s*\(/.test(src)) {
        console.error('LibraryStore.bs must decode account bitfields through m.codec.WatchedDecode (a bare global WatchedCodec() dies cross-component)');
        ok = false;
    }
    return ok;
}

// MarkupGrid only updates item components through interface fields named
// `itemContent` and `itemHasFocus` — never `content` or `focused`. This bit us:
// PosterTile observed the wrong fields and never rendered text or focus. Guard
// the interface so the tile's render contract stays pinned to the grid's API.
// Both tiles must keep their interfaces read-only-exclusive: no `content` /
// `focused` re-declaration may ever creep back in (it would silently shadow the
// list's own fields and break the recycle behavior).
function checkTileContract() {
    const fs = require('fs');
    const tiles = [
        { name: 'PosterTile', fields: ['itemContent', 'itemHasFocus', 'rowHasFocus'] },
        { name: 'EpisodeTile', fields: ['itemContent', 'itemHasFocus', 'rowHasFocus'] }
    ];
    let ok = true;
    for (const tile of tiles) {
        const xml = fs.readFileSync(path.join(projectRoot, 'components', `${tile.name}.xml`), 'utf8');
        const declared = new Set(
            [...xml.matchAll(/<field\s+id="([^"]+)"[\s>]/gi)].map(match => match[1])
        );
        for (const field of tile.fields) {
            if (!declared.has(field)) {
                console.error(`${tile.name}.xml is missing <field id="${field}" ... /> from its interface`);
                ok = false;
            }
        }
        for (const forbidden of ['content', 'focused']) {
            if (declared.has(forbidden)) {
                console.error(`${tile.name}.xml must not re-declare <field id="${forbidden}"> — the list drives items through itemContent/itemHasFocus only`);
                ok = false;
            }
        }
    }
    return ok;
}

// Group.visible defaults to true, and screens are declared children of the
// Scene, so an undisclosed screen paints over the stack's top screen (this bit
// us: DummyDetail covered HomeScreen from the first frame). Screens must start
// hidden; only the stack makes them visible. PlayerScreen is intentionally NOT
// here: it is built fresh per play in MainScene and destroyed on pop so the
// device releases the media player (a static child would survive and keep
// leaking audio). Its interface contract is still pinned by checkScreenContract.
// main.brs calls scene.callFunc('Start') and — for an ECP deep link —
// scene.callFunc('HandleDeepLink', args). callFunc only invokes functions
// declared in a component's interface, so a missing declaration would quietly
// no-op on device (Start exists today, so only HandleDeepLink is new). Pin
// both here so the bootstrap contract stays honest.
function checkMainSceneContract() {
    const fs = require('fs');
    const brs = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.brs'), 'utf8')
        .split('\n').map(line => line.split("'")[0]).join('\n');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.xml'), 'utf8');
    const declared = new Set(
        [...xml.matchAll(/<function\s+name="([^"]+)"\s*\/?>/gi)].map(match => match[1])
    );
    let ok = true;
    for (const fn of ['Start', 'HandleDeepLink']) {
        if (!declared.has(fn)) {
            console.error(`MainScene.xml is missing <function name="${fn}" /> from its interface`);
            ok = false;
        }
    }
    // Every dialog in the app — support, confirm-exit, logout, session-revoked,
    // deep-link import — is shown by assigning it to m.top.dialog. That slot is
    // NOT built into Scene: assign to it without declaring it and the write
    // lands in an undeclared dynamic field that nothing observes, so the dialog
    // simply never appears. No error, no log line, no crash — which is why
    // every dialog in the app was broken at once and looked like one component
    // misbehaving. `dialog` was never declared, here or at any earlier commit.
    const assigns = [...brs.matchAll(/\bm\.top\.dialog\s*=\s*(?!invalid\b)/g)];
    if (assigns.length > 0 && !/<field\s+id="dialog"\s+type="node"/.test(xml)) {
        console.error(`MainScene.brs shows ${assigns.length} dialog(s) through m.top.dialog but MainScene.xml does not declare <field id="dialog" type="node" /> — the Scene renders no dialog slot it has not been told about, so every one of these assignments writes an undeclared field and shows nothing`);
        ok = false;
    }
    // Dialogs are BUILT, not declared. Both custom dialogs used to be declared as
    // Scene children with visible="false". On device they dimmed the background
    // and took focus — blind OK on the Exit button still fired buttonSelected,
    // so they were alive, laid out and interactive — and painted nothing at all.
    // Their own code was never at fault; the CreateObject shape that the three
    // StandardMessageDialogs already use renders every one of them.
    // Comments describe the old shape by name, so strip them before matching.
    const dialogTags = [...xml.replace(/<!--[\s\S]*?-->/g, '').matchAll(/<([A-Za-z0-9_]*Dialog)\b/g)].map(m => m[1]);
    if (dialogTags.length > 0) {
        console.error(`MainScene.xml declares ${dialogTags.join(', ')} as a Scene child — a dialog declared in markup dims the background and takes focus but paints nothing on this device (verified on both the exit and support dialogs). Build it with CreateObject("roSGNode", "...") and show it through scene.dialog, the shape the three StandardMessageDialogs use`);
        ok = false;
    }
    // Every node handed to the dialog slot must have been built in code.
    // (Holding a reference is not the concern it looks like: assigning to
    // scene.dialog puts the node in the Scene's dialog group, and from there the
    // scene graph itself keeps it alive. The Scene keeps m.confirmExit and
    // m.supportDialog because it re-shows them and their observers are scoped.)
    const built = new Set([...brs.matchAll(/([\w.]+)\s*=\s*CreateObject\(\s*"roSGNode"\s*,\s*"[A-Za-z0-9_]*Dialog"/g)].map(m => m[1]));
    for (const m of brs.matchAll(/m\.top\.dialog\s*=\s*([^=\n]+)/g)) {
        const target = m[1].trim();
        if (target === 'invalid') continue;
        if (!built.has(target)) {
            console.error(`MainScene.brs shows "${target}" through m.top.dialog but nothing ever builds it with CreateObject — a dialog that is declared in markup, or reached any other way, dims the background and paints nothing`);
            ok = false;
        }
    }
    return ok;
}

// Poster.loadStatus is a string with four legal values. Guesses against it are
// invisible at build time and fail silently on the device, and three shipped:
// "ready" on the pairing screen's SUCCESS path, "<> error" in both tiles (always
// true, so a failed image was treated as having art), and then "loaded" in both
// tiles plus the pairing screen — a string that is not documented at all, which
// made every gate a no-op and left the artless face rendering behind its own
// artwork on every row. The literals are plain strings, so nothing but a static
// check stands between a guess and a device. That check used to carry the same
// wrong list it was meant to police, so it agreed with the bug; the set is now
// derived once, below, and the fallback contract asserts the tiles' gate matches.
const POSTER_LOAD_STATUS = {
    none: 'No loading or decoding taking place (the default)',
    loading: 'Being fetched and decoded',
    ready: 'Fetched and decoded, ready to be drawn',
    failed: 'Could not be loaded',
};
const POSTER_LOAD_STATUS_LEGAL = Object.keys(POSTER_LOAD_STATUS);
const POSTER_LOAD_STATUS_READY = 'ready';

function checkPosterStatusContract() {
    const fs = require('fs');
    const LEGAL = POSTER_LOAD_STATUS_LEGAL;
    let ok = true;
    for (const name of fs.readdirSync(path.join(projectRoot, 'components')).filter(f => f.endsWith('.brs'))) {
        const src = fs.readFileSync(path.join(projectRoot, 'components', name), 'utf8')
            .split('\n').map(line => line.split("'")[0]).join('\n');
        // Which locals hold a loadStatus in this file, then every string each of
        // them is compared against. Dataflow is one assignment wide on purpose:
        // the bug is a mistyped literal, not a mistyped variable.
        const vars = new Set([...src.matchAll(/(\w+)\s*=\s*[\w.]+\.loadStatus\b/g)].map(m => m[1]));
        for (const v of vars) {
            for (const m of src.matchAll(new RegExp('\\b' + v + '\\s*(?:<>|<|>|=)\\s*"([^"]+)"', 'g'))) {
                if (!LEGAL.includes(m[1])) {
                    console.error(`${name} compares ${v} (a Poster loadStatus) against "${m[1]}" — the only values are ${LEGAL.join(' / ')}; a status that can never occur makes the branch dead, silently`);
                    ok = false;
                }
            }
        }
    }

    // Police the police. The list above is the one thing standing between a
    // mistyped literal and a device, so it must be exactly the documented set:
    // admitting an invented value (it once admitted "loaded") silently restores
    // the class of bug this whole check exists to catch.
    const expected = ['none', 'loading', 'ready', 'failed'];
    if (LEGAL.length !== expected.length || expected.some((v, i) => LEGAL[i] !== v)) {
        console.error(`the Poster loadStatus allowlist is [${LEGAL.join(', ')}], but the documented set is [${expected.join(', ')}]. An allowlist that admits a value the OS never reports makes every comparison against it dead code`);
        ok = false;
    }

    // A success path must be reachable. Every surface that hides something
    // behind a poster needs the one value that means "a bitmap exists"; if that
    // literal is wrong the branch never runs and the fallback never goes away.
    // Both spellings count: the tiles compare m.poster.loadStatus directly, the
    // pairing screen copies it into a local first.
    for (const name of ['PosterTile.brs', 'EpisodeTile.brs', 'LinkStremioScreen.brs']) {
        const src = fs.readFileSync(path.join(projectRoot, 'components', name), 'utf8')
            .split('\n').map(line => line.split("'")[0]).join('\n');
        const held = [...new Set([...src.matchAll(/(\w+)\s*=\s*[\w.]+\.loadStatus\b/g)].map(m => m[1]))];
        const subjects = ['loadStatus', ...held].join('|');
        const compared = [...src.matchAll(new RegExp('\\b(?:' + subjects + ')\\s*(?:<>|<|>|=)\\s*"([^"]+)"', 'g'))].map(m => m[1]);
        if (!compared.includes(POSTER_LOAD_STATUS_READY)) {
            console.error(`${name} never tests a Poster loadStatus against "${POSTER_LOAD_STATUS_READY}" (${POSTER_LOAD_STATUS.ready}). Without the success value its load handling cannot tell artwork from no artwork, so the fallback renders over the image forever`);
            ok = false;
        }
    }
    return ok;
}

// A tile is one of two states and only ever one at a time: the artless unit (a
// face plus the title) or the poster. Four separate bugs came out of looser
// versions of this rule, so pin the shape it settled on:
//
//   * The gate must be loadStatus = "ready" — the documented success value, and
//     the only one that proves a bitmap exists. Treating any non-failed URL as
//     art left the tile a blank face for the whole download, and this file once
//     itself compared against a non-existent "loaded", which made the branch
//     dead on every row: the face kept rendering behind its own artwork. The
//     literal comes from POSTER_LOAD_STATUS_READY above, not a second guess.
//   * The two states swap as a unit. Gating the *title* alone let it paint over
//     artwork, and declaration order was the only thing hiding that — a recycled
//     tile reports "loading" for the uri it is being handed while still holding
//     the previous cell's bitmap, so the text went visible on top of it.
//   * The status is re-read where the uri is set, because an image that resolves
//     from cache can settle without the observer ever firing.
//   * The poster must never be hidden. Declaring it visible="false" and
//     unhiding it once the artwork arrived deadlocked the load against the gate
//     waiting on it — loadStatus never arrived, so every tile stayed artless. A
//     Poster with no bitmap paints nothing, so there is nothing to hide.
//   * The poster must never be hidden. Declaring it visible="false" and
//     unhiding it once the artwork arrived deadlocked the load against the gate
//     waiting on it — loadStatus never arrived, so every tile stayed artless. A
//     Poster with no bitmap paints nothing, so there is nothing to hide.
function checkPosterFallbackContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, 'components', f), 'utf8');
    const body = (src, sig) => {
        const start = src.indexOf(sig);
        if (start === -1) return null;
        const next = src.indexOf('\nsub ', start + 1);
        return next === -1 ? src.slice(start) : src.slice(start, next);
    };
    let ok = true;

    // Both tiles: the face and poster must be one hideable unit, nothing may
    // deadlock the poster's own load, and the success branch must be reachable.
    for (const name of ['PosterTile', 'EpisodeTile']) {
        const xml = read(`${name}.xml`);
        const src = read(`${name}.brs`).split('\n').map(line => line.split("'")[0]).join('\n');

        const open = xml.indexOf('<Group id="artless"');
        if (open === -1) {
            console.error(`${name}.xml has no <Group id="artless"> — the face and the title must be one unit that hides as one`);
            ok = false;
            continue;
        }
        const close = xml.indexOf('</Group>', open);
        const inner = close === -1 ? '' : xml.slice(open, close);
        if (!inner.includes('id="tileBg"') || !inner.includes('id="titleText"')) {
            console.error(`${name}.xml the artless group must contain both tileBg and titleText`);
            ok = false;
        }

        const art = xml.match(/<Poster\s+id="poster"[^>]*>/);
        if (art === null) {
            console.error(`${name}.xml has no <Poster id="poster">`);
            ok = false;
        } else {
            // Liveness, and the reason the deadlock happened: a Poster that is
            // not visible never loads, so gating its visibility on loadStatus
            // made the gate wait on the thing the gate prevented.
            if (/visible="false"/.test(art[0])) {
                console.error(`${name}.xml declares the poster visible="false" — it must be visible in order to load at all. Gating its visibility on loadStatus deadlocks the load against the gate waiting on it, leaving every tile artless`);
                ok = false;
            }
        }

        // The face must actually STOP rendering. Relying on the poster painting
        // over it left the face visible behind artwork on unfocused rows.
        for (const [sig, want] of [['sub ShowArtless()', 'true'], ['sub ShowPoster()', 'false']]) {
            const b = body(src, sig);
            if (b === null) {
                console.error(`${name}.brs has no ${sig} — the artless unit must be hidden once artwork paints, or the face renders behind the poster`);
                ok = false;
                continue;
            }
            if (!new RegExp(`m\\.artless\\.visible\\s*=\\s*${want}\\b`).test(b)) {
                console.error(`${name}.brs ${sig} must set m.artless.visible = ${want}`);
                ok = false;
            }
        }

        const handler = body(src, 'sub onPosterLoadStatus()');
        if (handler === null) {
            console.error(`${name}.brs has no onPosterLoadStatus() — nothing would ever hide the face once artwork lands`);
            ok = false;
        } else {
            // One shared source of truth for the success value, and one whole
            // shape rather than three loose greps: this file once hardcoded the
            // wrong literal in two places and agreed with itself, and a handler
            // that merely *mentions* the right status is not enough — "= ready
            // and false" or an inverted branch keeps the face on screen while
            // passing a substring check. The two states are mutually exclusive
            // by construction: exactly one of them, decided by exactly that
            // comparison.
            const shape = new RegExp(
                `if\\s+m\\.poster\\.loadStatus\\s*=\\s*"${POSTER_LOAD_STATUS_READY}"\\s+then\\s+ShowPoster\\(\\)\\s+else\\s+ShowArtless\\(\\)`,
            );
            if (!shape.test(handler)) {
                console.error(`${name}.brs onPosterLoadStatus() must be exactly 'if m.poster.loadStatus = "${POSTER_LOAD_STATUS_READY}" then ShowPoster() else ShowArtless()'. "${POSTER_LOAD_STATUS_READY}" is the documented success value (${POSTER_LOAD_STATUS.ready}); the full set is ${POSTER_LOAD_STATUS_LEGAL.join(' / ')} and there is no "loaded". Anything that merely mentions the right status can still leave the face rendering over the artwork, so pin the whole conditional`);
                ok = false;
            }
        }

        if (!/m\.poster\.ObserveField\("loadStatus"/.test(src)) {
            console.error(`${name}.brs never observes poster.loadStatus, so the face is never hidden when artwork lands`);
            ok = false;
        }
        // A uri can resolve from cache and settle before the observer fires, so
        // the status has to be re-read where the uri is set.
        if (!new RegExp(`m\\.poster\\.loadStatus\\s*=\\s*"${POSTER_LOAD_STATUS_READY}"[\\s\\S]{0,80}onPosterLoadStatus\\(\\)`).test(src)) {
            console.error(`${name}.brs does not re-read loadStatus after setting the uri — a cached image can settle before the observer fires, leaving the face showing over real artwork`);
            ok = false;
        }

        // Never hide the poster from code either: same deadlock, one layer down.
        if (/m\.poster\.visible\s*=/.test(src)) {
            console.error(`${name}.brs assigns poster.visible — the poster must stay visible to load. Only the artless unit is toggled`);
            ok = false;
        }
        if (/titleText\.visible/.test(src)) {
            console.error(`${name}.brs sets titleText.visible directly — visibility belongs to the artless Group, which hides as one unit with the face`);
            ok = false;
        }

        // Paint order still matters: the poster must be able to cover the face.
        if (xml.indexOf('<Group id="artless"') > xml.indexOf('<Poster id="poster"')) {
            console.error(`${name}.xml declares the poster BEFORE the artless group — the poster would paint under the face and title`);
            ok = false;
        }
    }

    return ok;
}

// Auth changes pivot the session-aware stores through a single ReconcileSession()
// (the type is derived from the auth authority, never a call-site literal). A
// stray store.SwitchSession(...) anywhere else means a flow — or a future 4th
// session-aware store — repointed stores by hand and the guest/stremio
// separation can silently drift. Pin it: SwitchSession may only be called
// inside ReconcileSession.
function checkSessionAuthorityContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, 'components', f), 'utf8');
    const brs = read('MainScene.brs');
    const host = read('StoreHost.brs');
    let ok = true;
    // The Scene may only ask for a pivot from ReconcileSession(), the one
    // authority — and it asks the HOST, which is where the session-aware
    // instances now live.
    const calls = [...brs.matchAll(/callFunc\(\s*"SwitchSession"/g)].map(match => match.index);
    if (calls.length === 0) {
        console.error('MainScene.brs no longer asks for a session pivot anywhere (callFunc("SwitchSession", type)) — the session-aware stores never move off the old session');
        return false;
    }
    const subStart = brs.indexOf('sub ReconcileSession()');
    const nextSub = brs.indexOf('\nsub ', subStart + 1);
    const body = nextSub === -1 ? brs.slice(subStart) : brs.slice(subStart, nextSub);
    for (const index of calls) {
        if (index < subStart || index > nextSub) {
            console.error(`MainScene.brs pivots the session at byte ${index}, outside sub ReconcileSession() — every pivot must go through the authority`);
            ok = false;
        }
    }
    // The host holds the instances, so the host does the fan-out, and it walks
    // one list — a hardcoded pair would silently skip the next session-aware
    // store that joins, which is the failure this rule exists to prevent.
    if (!/\.SwitchSession\s*\(/.test(host)) {
        console.error('StoreHost.brs no longer calls SwitchSession on its session-aware stores — nothing would pivot them');
        ok = false;
    } else if (!/sub\s+SwitchSession\s*\([^)]*\)\s*\n\s*for each store in m\.sessionAware\s*\n\s*store\.SwitchSession\(/.test(host)) {
        console.error('StoreHost.brs SwitchSession must walk m.sessionAware — a hardcoded pair silently leaves the next session-aware store on the old session');
        ok = false;
    }
    // A stray direct pivot anywhere else means some flow bypassed the authority.
    for (const name of fs.readdirSync(path.join(projectRoot, 'components')).filter(f => f.endsWith('.brs'))) {
        if (name === 'StoreHost.brs') continue;
        if (/\.SwitchSession\s*\(/.test(read(name))) {
            console.error(`${name} pivots a store's session directly — only StoreHost may, and only from its SwitchSession entry point, or guest and stremio drift apart`);
            ok = false;
        }
    }
    return ok;
}

// A stremio session's add-ons exist ONLY as whatever the account sync wrote to
// the stremio_addons registry key — AddonsStore deliberately shows no built-in
// seeds for that session type. So an empty key means no Cinemeta, which means
// every AddonsGet("com.linvo.cinemeta") caller gets invalid, including
// MetaAddress(), which is what the Continue Watching row's Details fetch needs.
//
// Three claims about that were carried by COMMENTS rather than by anything a
// test could contradict, and a single failed login-time sync made all of them
// false at once: the session went permanently catalog-less, the failure printed
// nothing, and the only recovery was logging out and re-pairing the account.
// Each is pinned here.
function checkStremioProvisioningContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const brs = read('components/MainScene.brs');
    const screen = read('components/Screen.brs');
    const api = read('source/stores/StremioApiStore.bs');
    let ok = true;

    const subBody = (source, name) => {
        const start = source.indexOf(`sub ${name}()`);
        if (start === -1) return '';
        const next = source.indexOf('\nsub ', start + 1);
        return next === -1 ? source.slice(start) : source.slice(start, next);
    };

    // 1. A relaunched stremio session must re-pull the collection, not trust
    //    that a past login left one behind.
    const start = subBody(brs, 'Start');
    if (!/EffectiveSessionType\(\)\s*=\s*"stremio"/.test(start)) {
        console.error('MainScene.brs sub Start() no longer branches on a stremio session — a relaunched account session would sync nothing at all');
        ok = false;
    } else if (!/StartAddonSync\(\)/.test(start)) {
        console.error('MainScene.brs sub Start() does not call StartAddonSync() for a relaunched stremio session — an empty stremio_addons key can never recover, and recovery used to mean re-pairing the account');
        ok = false;
    }
    if (!/StartLibrarySync\(\)/.test(start)) {
        console.error('MainScene.brs sub Start() no longer re-pulls the library on a relaunched stremio session');
        ok = false;
    }

    // 2. The collection is the one unbounded response in the client (whole
    //    collection, every manifest embedded, update:true on top), so it must
    //    ride the long-timeout path. On the default window it returned the same
    //    { ok: false } as a real refusal and the caller could not tell them apart.
    const collection = /function\s+AddonCollectionGet\(\)[\s\S]*?end\s+function/.exec(api);
    if (!collection) {
        console.error('StremioApiStore.bs has no AddonCollectionGet — the account collection pull is gone');
        ok = false;
    } else if (!/PostLong\(\s*"\/api\/addonCollectionGet"/.test(collection[0])) {
        console.error('StremioApiStore.bs AddonCollectionGet must use PostLong, not Post — the collection is the one unbounded response in the client and aborts on the default window');
        ok = false;
    }
    if (!/private\s+function\s+PostLong\s*\(/.test(api)) {
        console.error('StremioApiStore.bs has no PostLong helper — AddonCollectionGet cannot reach the long-timeout path');
        ok = false;
    }

    // 3. A sync that reports nothing must say so. A transport timeout, an HTTP
    //    error and an empty account all used to fall off the end of the sub
    //    identically, so Home kept rendering pre-login rows looking healthy.
    const result = subBody(brs, 'onAddonSyncResult');
    if (!/ClearAddonSyncFaults\(\)/.test(result)) {
        console.error('MainScene.brs onAddonSyncResult does not retract its previous fault lines — a retry that failed differently would leave stale errors up forever');
        ok = false;
    }
    if (!/if\s+not\s+result\.ok\s*\n[\s\S]{0,400}?AddAddonSyncFault\(/.test(result)) {
        console.error('MainScene.brs onAddonSyncResult still falls off the end when the sync fails — an unreported failed sync is indistinguishable from a healthy one');
        ok = false;
    }
    if (!/result\.error/.test(result)) {
        console.error('MainScene.brs onAddonSyncResult never reads result.error — the transport\'s own reason is discarded instead of shown');
        ok = false;
    }
    if (!/AddAddonSyncFault\(\s*"addon sync: the account reported no add-ons"/.test(result)) {
        console.error('MainScene.brs onAddonSyncResult must name the synced-but-empty outcome — that is the exact state that used to require re-pairing');
        ok = false;
    }

    // 4. The bind probe must not report a stremio session's pre-sync emptiness as
    //    a hand-off fault. It did, and it pointed the investigation at StoreHost
    //    instead of at the request that never arrived.
    const condition = /else\s+if\s+installed\.Count\(\)\s*=\s*0([^\n]*)\n/.exec(screen);
    if (!condition) {
        console.error('Screen.brs no longer reports an empty add-on list as a store fault — the probe lost its "the store answered with nothing" hop');
        ok = false;
    } else if (!/callFunc\(\s*"AuthGetSession"\s*\)\s*<>\s*"stremio"/.test(condition[1])) {
        console.error('Screen.brs raises the empty-add-ons fault for a stremio session — that state is normal between launch and the collection landing, and reporting it names the wrong subsystem');
        ok = false;
    }
    if (!/callFunc\(\s*"AuthGetSession"/.test(screen)) {
        console.error('Screen.brs reads the session through something other than callFunc("AuthGetSession") — the store alias must be spelled at the call site or the hand-off check cannot see it');
        ok = false;
    }
    return ok;
}

// FinishImport calls m.homeScreen.callFunc('RebuildRows') after a deep-link
// import lands new add-ons. Same callFunc interface-declaration trap as
// MainScene above — pin it or a missing declaration silently no-ops on device.
// The add-on sync worker is the one place in this app where a correct-looking
// handler destroys its own answer, and it did so on every first login.
//
// Every Task in this app declares its result as an alwaysNotify field with no
// value, and Roku delivers one notification for such a field at ObserveField time
// carrying whatever the field holds then. The subtlety that cost two deploys to
// pin down: that notification is NOT delivered at the attach. It is queued and
// dispatched on the event loop, so it arrives after AsyncTask_Launch has returned
// and after `control = "RUN"` has started the worker. The queued notification is
// therefore indistinguishable, by arrival, from the real one.
//
// Both handlers got this wrong, in opposite directions:
//
//   onAddonSyncResult read an empty result as "the task produced nothing" and
//   immediately AsyncTask_Reap — which unobserves the field and removes the node.
//   This file's own headers record that removing a running Task node does NOT kill
//   its worker thread, so the genuine result landed on a node nobody was watching.
//   The account's add-ons were silently dropped, `added` stayed 0, RebuildRows
//   never ran, and Home went on rendering its pre-login rows. On device that read
//   as "the catalog never updates when I log in" — a plausible-looking UI bug with
//   no cause anywhere in the UI. FIX: decline an empty result; let the sentinel
//   decide.
//
//   onAddonSyncFinished then arrived as the reporting path and treated the mere
//   ARRIVAL of a "finished" notification as proof the worker was done. It reaped
//   the node and published
//     addon sync: the worker finished with no result (stage: request-started)
//   on the first run of every sync, while the worker was still blocked inside its
//   HTTP call — stage read from a task in flight. FIX: test the sentinel's VALUE.
//   `true` is the only thing that means the worker ran sync() to completion.
//
// The general rule, which both handlers now follow and which the checks below pin:
// for an alwaysNotify field, the notification's arrival means nothing; only the
// value it carries does.
//
// The brs interpreter cannot execute a Task worker thread, so no test in this repo
// can observe any of this. It is the same blind spot as AA iteration order and the
// &h18 truthiness crash: a green suite is not evidence. So the invariant is pinned
// structurally here, and the worker narrates its own progress into a "stage" field
// so that if it ever fails again the fault text names the hop instead of costing
// another round of hypotheses.
// The engine warm-up is what makes the readiness wait possible at all, it spans
// three files, and no interpreter test can reach any of it: the Task's Wait()
// ABORTS the run, and a HEAD in a store is one line. So the invariants below are
// the only guard, and every one of them fails SILENTLY — still compiling, still
// green, still timing out exactly as before.
function checkEngineWarmupContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const task = code(read('components/StreamResolveTask.brs'));
    const store = code(read('source/stores/PlaybackStore.bs'));
    const transport = code(read('source/stores/Transport.bs'));
    const player = code(read('components/PlayerScreen.brs'));
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    // 1. HEAD has to reach roUrlTransfer AS a HEAD. Transport used to special-case
    //    only POST, so every other method fell through to AsyncGetToString() and
    //    a "HEAD" was quietly a GET — against a stream route advertising a
    //    Content-Length in the gigabytes, which is a request to buffer an entire
    //    feature into a string while believing it was asking for headers.
    if (!/request\.method\s*=\s*"HEAD"/.test(transport) || !/AsyncHead\(\)/.test(transport)) {
        err('Transport.bs does not dispatch HEAD to AsyncHead() — every method except POST falls through to AsyncGetToString(), so the warm-up would silently be a full GET of the stream route');
    }

    // 2. The warm-up must precede the playlist probe. Order IS the fix: a playlist
    //    request to a server that has not been told to make an engine is not a
    //    slow request, it is a hung one — which is what six timed-out probes and a
    //    44-second wait turned out to be.
    const warmAt = task.search(/WarmEngine\(/);
    const probeAt = task.search(/WaitForPlaylist\(/);
    if (warmAt === -1) {
        err('StreamResolveTask.brs never calls WarmEngine() — the engine is never asked for, so the probe is asking a server that was never told to make one');
    } else if (probeAt !== -1 && warmAt > probeAt) {
        err('StreamResolveTask.brs warms the engine AFTER probing for the playlist — the probe has to run first or it is still the request that hangs');
    }

    // 3. Both warm-up timeouts have to actually arrive, and they are two numbers
    //    because the two requests are not alike. The HEAD submits work and answers
    //    in 30-65ms (the server logs "Engine created" that far behind the
    //    request); the ranged GET is the one that blocks until the engine has
    //    torrent metadata, which is the entire cost of a DHT-only cold start.
    //
    //    They were one constant, and that is how a 40ms request ended up holding
    //    the same budget as the request meant to wait — which is how a cold engine
    //    outlived the cap that existed to notice it. The ceilings below are not
    //    "what the work needs", they are the two ways this can rot: the HEAD
    //    drifting up toward the readiness budget, and the readiness read drifting
    //    up toward a hang.
    const headTimeout = /const\s+ENGINE_HEAD_TIMEOUT_MS\s*=\s*(\d+)/.exec(store);
    const readyTimeout = /const\s+ENGINE_READY_TIMEOUT_MS\s*=\s*(\d+)/.exec(store);
    if (!headTimeout) {
        err('PlaybackStore.bs has no ENGINE_HEAD_TIMEOUT_MS — the warm-up HEAD pays the 15s default, and a default-sized budget on the request that only submits work is where the readiness budget came from in the first place');
    } else {
        if (Number(headTimeout[1]) > 8000) {
            err(`PlaybackStore.bs ENGINE_HEAD_TIMEOUT_MS is ${headTimeout[1]}ms — this request has answered in 30-65ms every time it has been logged, so a budget past 8s is not headroom, it is slack that will get spent on the readiness read instead`);
        }
        if (!/Head\(url,\s*ENGINE_HEAD_TIMEOUT_MS\)/.test(store)) {
            err('PlaybackStore.bs WarmEngine does not pass ENGINE_HEAD_TIMEOUT_MS to Head — the constant is declared but the warm-up still pays the default timeout');
        }
    }
    if (!readyTimeout) {
        err('PlaybackStore.bs has no ENGINE_READY_TIMEOUT_MS — the ranged metadata read falls back to the 15s default, which is the request whose whole job is to block until a cold engine is ready');
    } else {
        if (Number(readyTimeout[1]) > 20000) {
            err(`PlaybackStore.bs ENGINE_READY_TIMEOUT_MS is ${readyTimeout[1]}ms — past this the readiness read is no longer waiting out a cold engine, it is the thing deciding whether the stream is servable, and the probe loop behind it is what decides that`);
        }
    }

    // 3b. The pair is one budget, and only their sum is meaningful. Measured waits
    //     were 1.78s / 3.03s / 4.71s / and one over 8s, so the read needs real room
    //     — but the room does not come from the HEAD, and a pair that can creep up
    //     independently is how the warm-up ends up quietly longer than the probe
    //     loop it sits in front of.
    if (headTimeout && readyTimeout) {
        const warmBudget = Number(headTimeout[1]) + Number(readyTimeout[1]);
        if (warmBudget > 20000) {
            err(`the warm-up can spend ${warmBudget}ms before the probe loop even starts (${headTimeout[1]}ms HEAD + ${readyTimeout[1]}ms readiness read) — the readiness wait is measured in single-digit seconds, so a pair totalling over 20s means the split has drifted back toward one number`);
        }
    }

    // 4. It must be unable to fail the resolve. The warm-up is an optimisation, and
    //    sharing the probe's catch would report its fault as a probe that gave up
    //    — describing a request the server never received as one it refused.
    if (!/catch\s+e\s+resolved\.warmup\s*=/.test(task)) {
        err('StreamResolveTask.brs does not give the warm-up a catch that records it — a throw there would be reported as a failed resolve, or as the probe giving up');
    }

    // 5. A 2xx warm-up is deliberately NOT logged by the transport trace, so the
    //    record it rides back on is the only evidence the request happened at all.
    if (!/result\.warmup\s*<>\s*invalid/.test(player)) {
        err('PlayerScreen.brs never reads result.warmup — a warm-up that succeeded leaves no trace anywhere, so a stall would have nothing to rule it out with');
    }

    // 6. The record has to say WHAT the engine was handed. A timed-out warm-up is
    //    ambiguous on its own — a slow server and an engine with no trackers to
    //    bootstrap from produce the identical line — and those two call for
    //    opposite fixes, so the count is what makes the next run decidable.
    if (!/resolved\.warmup\.trackers\s*=/.test(task)) {
        err('StreamResolveTask.brs does not record how many trackers the engine was handed — a timed-out warm-up cannot otherwise be told apart from an engine bootstrapping over DHT alone');
    }
    if (!/warmup\.trackers\s*<>\s*invalid/.test(player)) {
        err('PlayerScreen.brs never prints the warm-up tracker count — the diagnostic that distinguishes a slow server from an engine with nothing to bootstrap from');

    }

    // 7. The warm-up is TWO requests, and the second is the one that matters. The
    //    HEAD gets the engine CREATED and returns in milliseconds, so it never said
    //    whether the engine could then ANSWER — the probe behind it kept finding
    //    that out the slow way, one timeout at a time. Stremio's client follows the
    //    HEAD with a ranged GET of the first 64KB and lets it block until the
    //    engine has torrent metadata, and the server's log for a device that
    //    starts cleanly shows exactly that request sitting between the HEAD and
    //    the /hls.m3u8.
    //
    //    Without it the warm-up creates an engine and walks away, which is the
    //    state the last unexplained timeout in this whole path came from: the
    //    server held our probe open for ~8.4s gathering metadata and a 4s
    //    deadline cancelled it. The Range header is also what keeps this from
    //    becoming the mistake check #1 describes — an unbounded GET on the torrent
    //    route is a request to buffer a whole feature into a string.
    if (!/bytes=0-65535/.test(store)) {
        err('PlaybackStore.bs WarmEngine no longer asks for a byte range — the HEAD creates the engine but never waits for its metadata, so the readiness probe is back to timing out against a server that was still legitimately working');
    }
    if (!/GetRaw\(\s*url\s*,\s*ENGINE_READY_TIMEOUT_MS\s*,\s*\{[^}]*"Range"/.test(store)) {
        err('PlaybackStore.bs WarmEngine does not pass a Range header to GetRaw — the forced-metadata read is either gone, or became an unbounded GET of the torrent route');
    }
    if (!/function\s+GetRaw\([^)]*headers/.test(transport)) {
        err('Transport.bs GetRaw does not accept headers — the forced-metadata read has nowhere to put its Range header, so it can only ever be a full-body GET');
    }

    // 8. And the result of it has to be readable, or the one thing this warm-up
    //    is for is invisible. HEAD 200 with a dead range means the engine was
    //    created and never became ready; both 200 means the engine was ready and
    //    anything after this belongs to the player.
    if (!/warmup\.range\s*<>\s*invalid/.test(player)) {
        err('PlayerScreen.brs never reads result.warmup.range — a warm-up whose engine was created but never became ready leaves no trace anywhere, which is the one distinction this second request exists to make');
    }

    return ok;
}

// The device refuses NEW concurrent connections past a low ceiling (~4-6):
// sequential soaks are perfect while 8-wide bursts drop transfers, and the
// app's parallel launch syncs collide the same way. Transport's bounded retry
// is what keeps a lost race from failing the fetch. None of this is reachable
// from the brs interpreter — every store test injects a fake client and the
// real one needs roUrlTransfer — so the invariants are pinned structurally.
function checkTransportRetryContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const transport = read('source/stores/Transport.bs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    if (!/const\s+MAX_TRANSPORT_ATTEMPTS\s*=\s*\d+/.test(transport)) {
        err('Transport.bs has no MAX_TRANSPORT_ATTEMPTS — a retry loop without a ceiling hammers a dead host, and no retry at all lets a connection collision fail the fetch');
    }
    const policy = /function\s+TransportFailureIsRetryable\s*\(\s*status\s+as\s+integer\s*\)\s*as\s+boolean\s*[\s\S]*?return\s+status\s*<\s*0[\s\S]*?end\s+function/.exec(transport);
    if (!policy) {
        err('Transport.bs TransportFailureIsRetryable must retry only negative (transport-level) statuses — an HTTP 404/500 is a real answer, and retrying a timeout (status 0) multiplies a full wait');
    }
    const exec = /client\._execute\s*=\s*function\s*\(request[\s\S]*?\n    end function/.exec(transport);
    if (!exec) {
        err('Transport.bs has no client._execute — the retry wrapper is gone and a connection collision fails the fetch outright');
    } else {
        const body = exec[0];
        if (!/m\._attempt\(request\)/.test(body)) {
            err('Transport.bs client._execute does not call m._attempt — the single round-trip is the thing being retried');
        }
        if (!/m\._retryable\(result\.status\)/.test(body) || !/m\._retryAfter\(attempt\)/.test(body)) {
            err('Transport.bs client._execute does not consult the retry policy and backoff — the retry is unconditional or absent');
        }
        if (!/MAX_TRANSPORT_ATTEMPTS/.test(body)) {
            err('Transport.bs client._execute does not cap attempts at MAX_TRANSPORT_ATTEMPTS — an unbounded retry can hammer a dead host');
        }
    }

    // The backoff has to DESYNCHRONISE, not merely delay. The failure being
    // ridden out is a refused connect, which the device answers in milliseconds
    // — which is exactly when a fixed backoff is worst. Every loser wakes at the
    // same instant, is refused again at the same instant, and keeps marching in
    // step. A fixed backoff reproduces the stampede it exists to break.
    if (!/const\s+TRANSPORT_RETRY_JITTER_MS\s*=\s*\d+/.test(transport)) {
        err('Transport.bs has no TRANSPORT_RETRY_JITTER_MS — retries share one fixed schedule, so the clients that lost the same race all retry at the same instant');
    }
    if (!/Rnd\(\s*TRANSPORT_RETRY_JITTER_MS\s*\)/.test(transport)) {
        err('Transport.bs never applies Rnd(TRANSPORT_RETRY_JITTER_MS) — the jitter is declared but the retries are still synchronised');
    }
    // Rnd is a Roku global and does not resolve in the brs interpreter, so it
    // must not reach TransportRetryBackoffMs: that file-scope function IS
    // exercised by the suite. It belongs on the client closure, which
    // CreateSyncHttpClient builds and no store test ever reaches (every one
    // injects a fake client).
    const backoff = /function\s+TransportRetryBackoffMs\s*\([^)]*\)([\s\S]*?)end\s+function/.exec(transport);
    if (backoff && /\bRnd\s*\(/.test(backoff[1])) {
        err('Transport.bs TransportRetryBackoffMs calls Rnd — that file-scope function is run by the brs interpreter, which has no Rnd global, and the unit tests for it would throw at runtime');
    }
    return ok;
}

// The two account pulls (add-on collection and library) are both launched in
// Start() and on login completion. Firing them together opens two NEW
// connections at the same instant — exactly the concurrency the device refuses
// past ~4-6. The library sync is therefore deferred behind the add-on sync and
// pumped when it settles. The interpreter cannot run either Task, so the
// ordering is pinned structurally.
function checkStaggeredSyncContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const brs = read('components/MainScene.brs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const body = (name) => {
        const start = new RegExp(`^[ \\t]*sub\\s+${name}\\s*\\(`, 'm').exec(brs);
        if (!start) return null;
        const rest = brs.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+sub\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    const start = body('StartLibrarySync');
    if (!start || !/m\.addonSyncTask\s*<>\s*invalid/.test(start) || !/m\.pendingLibrarySync\s*=\s*true/.test(start)) {
        err('MainScene.brs StartLibrarySync no longer defers behind an in-flight add-on sync — both launch-time pulls would open connections at once, the concurrency that loses transfers');
    }
    if (!/LaunchLibrarySync\(\)/.test(start || '')) {
        err('MainScene.brs StartLibrarySync no longer launches the library sync when it is free to do so');
    }
    const pump = body('PumpPendingLibrarySync');
    if (!pump || !/m\.pendingLibrarySync\s*<>\s*true\s+then\s+return/.test(pump) || !/LaunchLibrarySync\(\)/.test(pump)) {
        err('MainScene.brs PumpPendingLibrarySync must run only a deferred sync and launch it exactly once');
    }
    for (const name of ['onAddonSyncResult', 'onAddonSyncFinished']) {
        const b = body(name);
        if (!b || !/PumpPendingLibrarySync\(\)/.test(b)) {
            err(`MainScene.brs ${name} does not pump a deferred library sync — a launch that deferred it would never run it (a silent no-library-sync)`);
        }
    }
    const revoked = body('HandleRevokedSession');
    if (!revoked || !/m\.pendingLibrarySync\s*=\s*false/.test(revoked)) {
        err('MainScene.brs HandleRevokedSession must clear a deferred library sync — the session is gone and nothing should pull');
    }
    return ok;
}

// TEMPORARY, like the component it guards. NetDiagTask exists to locate the
// intermittent outbound-connect failures (status -7): DNS, the radio, or
// concurrency. Once that is known the component, the Settings row and this
// contract all go together. The first check is the one that matters:
// roUrlTransfer is Task-only, so a probe written as a plain Group would fail for
// a reason unrelated to the network and would send the whole investigation the
// wrong way.
function checkNetDiagContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const xml = read('components/NetDiagTask.xml');
    const raw = read('components/NetDiagTask.brs');
    const task = code(raw);
    const settings = code(read('components/SettingsScreen.brs'));
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    if (!/extends="Task"/.test(xml)) {
        err('NetDiagTask.xml does not extend Task — roUrlTransfer is Task-only, so every probe would fail for a reason unrelated to the network question');
    }

    // The ladder is a control experiment: each rung changes exactly one thing
    // from the one before it. Losing a rung does not just lose a data point, it
    // removes the control the adjacent rungs are read against.
    const tags = ['A', 'B', 'C', 'D', 'E'].filter(t => new RegExp(`tag:\\s*"${t}"`).test(task));
    if (tags.length !== 5) {
        err(`NetDiagTask.brs defines only probes ${tags.join(', ')} — the experiment is the A/B/C/D/E ladder, and dropping one removes the control it depends on`);
    }

    // B must be an IP literal with no DNS in the path; C the same request by
    // hostname. B vs C is the DNS comparison.
    if (!/tag:\s*"B"[^\n]*http:\/\/1\.1\.1\.1\//.test(task)) {
        err('NetDiagTask.brs probe B is not the bare http://1.1.1.1/ IP literal — without a DNS-free internet probe, B vs C cannot isolate name resolution');
    }
    if (!/tag:\s*"C"[^\n]*httpforever\.com/.test(task)) {
        err('NetDiagTask.brs probe C is not the httpforever.com hostname request — C is the DNS-using half of the B/C pair');
    }

    // D and E differ by exactly one call. If E stops asking for the bundle the
    // run silently becomes two copies of D, and "both failed" would be read as
    // evidence about certificates when certificates were never in the test.
    if (!/tag:\s*"E"[^\n]*certs:\s*true/.test(task)) {
        err('NetDiagTask.brs probe E does not set certs: true — without it E is an identical copy of D and the run cannot say anything about the CA bundle');
    }
    if (!/tag:\s*"D"[^\n]*certs:\s*false/.test(task)) {
        err('NetDiagTask.brs probe D sets certs — D must be the uncertificated control or there is nothing to compare E against');
    }

    // DNS is measured on its own, not only through HTTP: roSocketAddress does the
    // same lookup roUrlTransfer does, so a flaky result here is the resolver
    // failing before any socket opens.
    if (!/roSocketAddress/.test(task) || !/IsAddressValid\(\)/.test(task)) {
        err('NetDiagTask.brs no longer resolves hostnames through roSocketAddress/IsAddressValid — DNS would only be implied by HTTP failures instead of measured');
    }

    // Device facts decide the radio hypothesis and name the resolver in use.
    if (!/GetConnectionInfo\(\)/.test(task) || !/GetConnectionType\(\)/.test(task)) {
        err('NetDiagTask.brs no longer reads GetConnectionType()/GetConnectionInfo() — the Wi-Fi signal and the DNS servers actually in use would be invisible');
    }

    // The concurrency burst is the only section that puts several transfers in
    // flight at once, which is the pattern the production failures cluster in.
    if (!/RunBurst\(/.test(task)) {
        err('NetDiagTask.brs no longer issues a concurrency burst — a contention cause could not be distinguished from a DNS one');
    }

    // The three concurrency experiments escalate: the soak removes concurrency
    // entirely, the sweep finds the size at which it breaks, and the version
    // comparison tests Roku's documented "HTTP/2 sharing wants one thread"
    // constraint. Dropping any one leaves a plausible alternative unmeasured.
    if (!/report\.soak\s*=\s*RunSoak\(/.test(task)) {
        err('NetDiagTask.brs no longer runs the sequential soak — a link that drops under NO load would look identical to a concurrency problem');
    }
    if (!/report\.sweep\s*=\s*RunBurstSweep\(/.test(task)) {
        err('NetDiagTask.brs no longer sweeps burst sizes — the concurrency threshold would be a guess instead of a measurement');
    }
    if (!/report\.versions\s*=\s*RunHttpVersionComparison\(/.test(task) || !/SetHttpVersion\(/.test(task)) {
        err('NetDiagTask.brs no longer compares HTTP versions — the documented HTTP/2 same-thread sharing constraint would go untested');
    } else if (!/versions\s*=\s*\[[^\]]*"AUTO"[^\]]*"http2"[^\]]*"1\.1"/.test(task)) {
        err('NetDiagTask.brs HTTP-version comparison does not cover both "http2" and "1.1" — one of the two mechanisms would be unmeasured');
    } else if (!/h1Record\s*=\s*FindVersion\(/.test(task) || !/h1Record\.ok\s*=\s*h1Record\.count/.test(task)) {
        err('NetDiagTask.brs no longer interprets the 1.1 result — the wired run that identified the root cause printed AUTO 5/6, http2 5/6, 1.1 6/6 and the verdict said nothing about it, because the comparison only ever looked at AUTO vs http2');
    }

    // The verdict is what a reader acts on, and it has now been wrong twice in
    // ways that pointed real debugging effort at the wrong layer.
    //
    // `connected` was `status <> 0`, which counts CURLE_COULDNT_CONNECT (-7) as
    // connected. So a run where BOTH the IP-literal and hostname probes returned
    // -7 printed "Both IP and hostname reach the internet" and the DNS question
    // was closed on evidence that never tested it. A real HTTP response code is
    // always >= 100, so the comparison has to be `> 0`.
    if (/outcome\.connected\s*=\s*outcome\.status\s*<>\s*0/.test(task)) {
        err('NetDiagTask.brs computes connected as `status <> 0` — a negative status is a connect that never opened, so a -7 reads as connected and the DNS verdict closes itself on a probe that failed');
    }
    if (!/NetDiagConnected\(outcome\.status\)/.test(task) || !/function\s+NetDiagConnected[\s\S]*?return\s+status\s*>\s*0/.test(task)) {
        err('NetDiagTask.brs does not compute connected as `status > 0` via NetDiagConnected — reachability has to mean a response arrived, and a redirect answered on the way to a 2xx still counts');
    }
    if (!/neither IP nor hostname connected/i.test(task)) {
        err('NetDiagTask.brs has no both-red branch for the B/C pair — when neither the IP literal nor the hostname connects, that says nothing about DNS and must not be reported as if it did');
    }

    // A CA bundle is validated AFTER the TCP connect and TLS handshake. A -7 is
    // the connect refused before either, so "the bundle fixes HTTPS" cannot be
    // concluded from a rung that never connected — and following it would add
    // SetCertificatesFile to Transport for a connection that was never made.
    if (!/dTls\s*=\s*d\.status\s*>\s*0/.test(task) || !/eTls\s*=\s*e\.status\s*>\s*0/.test(task)) {
        err('NetDiagTask.brs does not gate the D/E certificate comparison on whether either rung got a response — a connect-level -7 cannot be a certificate result, so the comparison must report inconclusive instead of blaming or exonerating the bundle');
    }
    if (/CA bundle fixes HTTPS -> add SetCertificatesFile/.test(task)) {
        err('NetDiagTask.brs still emits an unconditional "CA bundle fixes HTTPS -> add SetCertificatesFile to Transport" — that fired off a rung which never connected, and acting on it adds a stall to every request for a connect that failed before TLS');
    }

    // The dev line printed all-empty on the first device run because it guessed
    // key names and values. The raw dump is what makes that impossible to
    // repeat silently, so it is the thing worth guarding.
    if (!/FormatJson\(info\)/.test(task)) {
        err('NetDiagTask.brs no longer dumps GetConnectionInfo() raw — the dev line silently printed all-empty on device once already');
    }

    // BoxStr stringifies platform values. A bare `"" + value` is a Type Mismatch
    // (&h18) on the booleans GetLinkStatus/GetInternetStatus/HasFeature return —
    // it crashed the whole task on device before a single probe ran, which is a
    // deploy spent to learn what this check now catches for free.
    if (!/Boolean/.test(task) || /return "" \+ value/.test(task)) {
        err('NetDiagTask.brs BoxStr no longer special-cases booleans (or reverted to `"" + value`) — GetLinkStatus/GetInternetStatus/HasFeature return booleans and that concat is a hard &h18');
    }
    if (!/CABundlePath\(\)/.test(task) || !/common:\/certs\/ca-bundle\.crt/.test(task)) {
        err('NetDiagTask.brs does not name common:/certs/ca-bundle.crt — Roku documents that path for public CAs, and probing anything else proves nothing about the documented fix');
    }
    const certAt = task.search(/SetCertificatesFile\(/);
    const issueAt = task.search(/AsyncGetToString\(\)/);
    if (certAt === -1) {
        err('NetDiagTask.brs never calls SetCertificatesFile() — the one call under test is missing');
    } else if (issueAt !== -1 && certAt > issueAt) {
        err('NetDiagTask.brs calls SetCertificatesFile() after issuing the request — the docs require it before, and a late call measures the wrong thing');
    }

    // The threshold is inlined in SettingsScreen.brs because standard
    // BrightScript has no file-scope const; assert it is still a deliberate,
    // repeated gesture rather than a single accidental press.
    if (!/m\.testServerTaps\s*>=\s*(\d+)/.test(settings)) {
        err('SettingsScreen.brs no longer gates the diagnostics row on a tap count — the hidden row cannot be reached deliberately');
    } else if (Number(/m\.testServerTaps\s*>=\s*(\d+)/.exec(settings)[1]) < 3) {
        err('SettingsScreen.brs reveals diagnostics on too few taps — few enough to fire by accident on a row users are meant to press');
    }
    if (!/action\s*=\s*"netdiag"/.test(settings) || !/RunNetDiag\(\)/.test(settings)) {
        err('SettingsScreen.brs never dispatches the netdiag row to RunNetDiag() — the row appears and does nothing');
    }
    if (!/AsyncTask_Launch\([^\n]*"NetDiagTask"/.test(settings)) {
        err('SettingsScreen.brs does not launch NetDiagTask — the diagnostic exists but nothing starts it');
    }

    // Both files say TEMPORARY in their own header. Cheap, but this is scaffolding
    // that is easy to build on by accident once it is committed.
    if (!/TEMPORARY/.test(raw) || !/TEMPORARY/.test(read('components/SettingsScreen.brs'))) {
        err('NetDiagTask.brs or SettingsScreen.brs has lost its TEMPORARY marker — scaffolding that stops announcing itself tends to stay');
    }

    return ok;
}

function checkStreamResolveTaskContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const taskXml = read('components/StreamResolveTask.xml');
    const taskBrs = code(read('components/StreamResolveTask.brs'));
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const body = (src, name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    // The whole readiness wait lives in a Task component, which the brs
    // interpreter never executes — Wait() there ABORTS the run and Ticks() does
    // not exist — so none of this is reachable by an interpreter test. These
    // checks are the only thing standing between a silent no-op and a fix that
    // reads as present. Every one of them is about the wait degenerating into
    // doing nothing while still looking correct.
    if (!/<field\s+id="result"\s+type="assocarray"[^>]*alwaysNotify="true"/.test(taskXml)) {
        err('StreamResolveTask.xml does not declare <field id="result" type="assocarray" ... alwaysNotify="true" /> — without it the screen never hears back');
    }

    const wait = body(taskBrs, 'WaitForPlaylist');
    if (!wait) {
        err('StreamResolveTask.brs has no WaitForPlaylist() — the readiness wait is gone, and the Video node is back to eating the cold-engine response itself');
        return ok;
    }

    // 1. NO CLOCK. The most expensive thing this file has ever contained was a
    //    clock reading: an earlier version bounded the wait with
    //    CreateObject("roDateTime").AsMilliseconds(), a method this codebase has
    //    never put on a device (the only two it does use are ToISOString() and
    //    GetYear()), and the device answered &hf4, member function not found.
    //    No interpreter test can catch a missing platform method, and the file is
    //    never executed by one, so refusing to use a clock here is the only
    //    defence there is. The bound is a count of attempts.
    const clock = /\broDateTime\b|\bTicks\s*\(|\bNowMs\b/.exec(taskBrs);
    if (clock) {
        err(`StreamResolveTask.brs references ${clock[0]} — the readiness wait is bounded by attempt count, and no platform clock is verified on this device (roDateTime.AsMilliseconds answered &hf4). A throw from one here shares resolve()'s catch and takes an already-resolved URL down with it`);
    }

    const interval = /Wait\(\s*(\d+)\s*,\s*invalid\s*\)/.exec(wait);
    if (!interval) {
        err('StreamResolveTask.brs WaitForPlaylist never pauses between attempts — a cold engine would be polled flat out');
    } else if (Number(interval[1]) < 1000) {
        err(`StreamResolveTask.brs WaitForPlaylist pauses ${interval[1]}ms between attempts — that is hammering a server that is still starting an engine`);
    }

    // 2. With no clock, attempts x (per-request timeout + interval) IS the
    //    ceiling — so the per-request timeout is now load-bearing, and it has to
    //    be a short one AND the one the probe actually passes. At Transport's
    //    default 15s, four attempts hold the player for over a minute, which is
    //    longer than the stall this whole mechanism exists to prevent.
    const store = read('source/stores/PlaybackStore.bs');
    const probeTimeout = /const\s+PROBE_TIMEOUT_MS\s*=\s*(\d+)/.exec(store);
    if (!probeTimeout) {
        err('PlaybackStore.bs has no PROBE_TIMEOUT_MS — without a probe-specific timeout the wait ceiling is attempts x the default 15s, over 90s of holding the player for a stream that may never start');
    } else {
        if (Number(probeTimeout[1]) > 8000) {
            err(`PlaybackStore.bs PROBE_TIMEOUT_MS is ${probeTimeout[1]}ms — a probe asks whether the server is up and the caller re-asks, so a request that can take this long is only delaying the next attempt`);
        }
        if (!/GetRaw\(url,\s*PROBE_TIMEOUT_MS\)/.test(store)) {
            err('PlaybackStore.bs ProbePlaylist does not pass PROBE_TIMEOUT_MS to GetRaw — the constant is declared but the probe still pays the default timeout');
        }
    }

    // 2. The retry must be a counted loop, not `while true`. A `while true`
    //    bounded only by a clock is unbounded to a reader, and to a future edit.
    const loop = /for\s+attempt\s*=\s*1\s+to\s+(\d+)/.exec(wait);
    if (!loop) {
        err('StreamResolveTask.brs WaitForPlaylist does not retry a counted number of times — an unbounded wait here is a render-thread-adjacent hang waiting for a bad edit');
    } else if (Number(loop[1]) < 2) {
        err(`StreamResolveTask.brs WaitForPlaylist tries ${loop[1]} time(s) — with one attempt the readiness wait is not a wait, it is the request that was always there`);
    }

    // 2b. The ceiling is attempts x probe timeout, plus the gaps BETWEEN them —
    //     which is one fewer than the attempt count, because the last attempt
    //     deliberately skips its sleep. That off-by-one is the whole reason this
    //     is computed rather than read off a constant: 4 x 8000 + 3 x 4000 is
    //     44s, and so was 6 x 4000 + 5 x 4000, which is how the probe timeout was
    //     raised to 8000 without lengthening the player's worst-case wait at all.
    //
    //     The three numbers involved live in two files and are independently
    //     editable, so pinning any one of them would pin today's arrangement
    //     rather than the property that matters. A future edit that moves either
    //     knob up without paying the other back down is the regression, whichever
    //     file it came through.
    const gapMs = interval ? Number(interval[1]) : 0;
    if (loop && probeTimeout && interval) {
        const ceiling = Number(loop[1]) * Number(probeTimeout[1]) + (Number(loop[1]) - 1) * gapMs;
        if (ceiling > 44000) {
            err(`the readiness wait can hold the player for ${ceiling}ms (${loop[1]} attempts x ${probeTimeout[1]}ms probe + ${Number(loop[1]) - 1} x ${gapMs}ms gap) — that ceiling is what this mechanism exists to cap, and it only stays capped while the attempt count and the probe timeout are moved together`);
        }
    }

    // 3. The pause has to be skipped on the final attempt. With no budget
    //    consulted mid-loop, an unconditional sleep costs a full interval of dead
    //    time after the loop has already decided to give up. Located by the line
    //    the sleep is on, since there are no constant names to find.
    const sleepLine = /^[ \t]*(.*Wait\(\s*\d+\s*,\s*invalid\s*\).*)$/m.exec(wait);
    if (sleepLine && !/if\s+attempt\s*<\s*\d+\s+then/.test(sleepLine[1])) {
        err('StreamResolveTask.brs WaitForPlaylist sleeps unconditionally — the final attempt then waits a whole interval after the loop has already decided to give up');
    }

    // 4. Handing over must not depend on the server having answered. If the give
    //    up path stopped returning a URL, the wait would have quietly become the
    //    thing that prevents playback instead of the thing that delays it.
    if (!/if\s+not\s+probe\.ok\s+then\s+probe\.gaveUp\s*=\s*true/.test(wait)) {
        err('StreamResolveTask.brs WaitForPlaylist does not mark gaveUp — "we stopped waiting" and "the server answered" would be indistinguishable in the record');
    }
    const resolveBody = body(taskBrs, 'resolve');
    if (!resolveBody) {
        err('StreamResolveTask.brs has no resolve() — the worker body is gone');
    } else {
        // 5. The probe is the diagnosis, so it has to be attached BEFORE the
        //    result is published, or it is never read by anyone.
        const probeAt = resolveBody.indexOf('resolved.probe =');
        const resultAt = resolveBody.indexOf('m.top.result =');
        if (probeAt === -1) {
            err('StreamResolveTask.brs resolve() never attaches a probe — "how long, and what did the server say" is the whole diagnosis when this is still wrong');
        } else if (resultAt === -1) {
            err('StreamResolveTask.brs resolve() never sets m.top.result — the screen would wait for a result that never lands');
        } else if (probeAt > resultAt) {
            err('StreamResolveTask.brs resolve() publishes the result before attaching the probe — the probe would never reach the screen');
        }
        if (!/store\.IsTorrent\(/.test(resolveBody)) {
            err('StreamResolveTask.brs resolve() probes unconditionally — a direct URL has no server to wait for, and waiting on one delays a stream that was ready immediately');
        }

        // 6. The probe has to run in its OWN try. Sharing resolve()'s catch is
        //    what turned a fault in a diagnostic into a broken player: the URL
        //    had already resolved correctly, the throw in the wait loop reached
        //    the outer catch, and the screen was told the stream had failed —
        //    "resolve FAILED: Member function not found" for a server that was
        //    never asked for anything. A diagnostic may only ever ADD what is
        //    known, so its failure has to be recorded and then ignored.
        if (!/resolved\.probe\s*=\s*WaitForPlaylist/.test(resolveBody)) {
            err('StreamResolveTask.brs resolve() no longer calls WaitForPlaylist — torrents get no readiness wait, and the Video node is back to eating the cold-engine response itself');
        } else if (!/resolved\.probe\s*=\s*\{/.test(resolveBody)) {
            err('StreamResolveTask.brs resolve() runs the probe in the same try as the resolve — a throw in a diagnostic then discards a URL that already resolved, which is how every torrent reported "Member function not found"');
        } else {
            // The inner catch has to come BEFORE the result is published, or the
            // fallback probe object is attached to nothing.
            const fallbackAt = /resolved\.probe\s*=\s*\{/.exec(resolveBody).index;
            if (resultAt !== -1 && fallbackAt > resultAt) {
                err('StreamResolveTask.brs resolve() publishes the result before the probe fallback — the record of a failed probe would never reach the screen');
            }
        }
    }

    // 7. The probe's account has to reach the log in the SUCCESS case too, and this
    //    one exists because that gap cost real diagnosis. A play that times out once
    //    and then recovers on attempt 2 IS a success — the failure-branch print was
    //    gated on gaveUp, so it stayed silent, and the only trace left was a stray
    //    [http] timeout line with nothing saying how many attempts ran or what the
    //    first one answered. That is precisely the pair of facts needed to tell a
    //    cold engine (first attempt expires while the engine is still coming up)
    //    from a flaky link (an engine already proven ready still loses a request),
    //    and without it the two were indistinguishable in the log.
    const player = code(read('components/PlayerScreen.brs'));
    if (!/probe gave up after/.test(player)) {
        err('PlayerScreen.brs no longer prints the probe give-up — a stream the server refused has nothing left to tell it apart from one that was never asked');
    }
    if (!/probe recovered after/.test(player)) {
        err('PlayerScreen.brs does not print the RECOVERED probe — a play that timed out once and then succeeded is a success, so with only the give-up path logged its timeout left nothing behind but a stray [http] line');
    } else {
        // ...and the recovered print must not be reachable only through the give-up
        // guard, which is what nesting it in that branch would look like. Walked line
        // by line to the first branch terminator rather than matched with one regex:
        // the regex forms of this are all subtly wrong — a lazy match runs straight
        // through an `else if` sibling and reports it as nested, and a tempered one
        // that stops at the `else` can then never reach the `end if` it is looking
        // for. A `^`-anchored lookahead also needs the `m` flag to mean "start of
        // line" at all, which is the sort of detail a contract should not be
        // resting on. Being two lines further down the sub is not nesting.
        const playerLines = player.split('\n');
        const gaveUpLine = playerLines.findIndex(l => /gaveUp\s*=\s*true/.test(l));
        if (gaveUpLine !== -1) {
            for (let i = gaveUpLine + 1; i < playerLines.length; i++) {
                if (/^\s*(else|end if|end while|end for)\b/.test(playerLines[i])) break;
                if (/probe recovered after/.test(playerLines[i])) {
                    err('PlayerScreen.brs prints the recovered probe from inside the gaveUp branch — that branch can never be reached when the probe succeeded, which is the one case that needed it');
                    break;
                }
            }
        }
    }

    return ok;
}

function checkAddonSyncTaskContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const taskXml = read('components/AddonSyncTask.xml');
    const taskBrs = code(read('components/AddonSyncTask.brs'));
    const main = code(read('components/MainScene.brs'));
    const async = code(read('source/core/AsyncTask.bs'));
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    // Body of a sub/function by name, from its header to the matching end at the
    // same indentation. Positions matter for the ordering checks below, so this
    // returns the source slice rather than a boolean.
    const body = (src, name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    // 1. The sentinel and the narration have to exist as declared interface
    //    fields. callFunc/ObserveField on an undeclared field is a no-op, and a
    //    write to an undeclared dynamic field notifies nobody.
    if (!/<field\s+id="finished"\s+type="boolean"[^>]*alwaysNotify="true"/.test(taskXml)) {
        err('AddonSyncTask.xml does not declare <field id="finished" type="boolean" ... alwaysNotify="true" /> — without the sentinel the handler cannot tell "not written yet" from "never written", which is the whole bug');
    }
    if (!/<field\s+id="stage"\s+type="string"/.test(taskXml)) {
        err('AddonSyncTask.xml does not declare a "stage" field — a failure names the hop only if the worker recorded how far it got');
    }

    // 2. The sentinel must be the last statement, and the result must be written
    //    before it. Reversed, the done-callback can conclude "no result" about a
    //    worker that is merely mid-write, which is the original bug wearing a fix.
    const sync = body(taskBrs, 'sync');
    if (!sync) {
        err('AddonSyncTask.brs has no sync() — the worker body is gone');
    } else {
        const resultAt = sync.indexOf('m.top.result =');
        const finishedAt = sync.indexOf('m.top.finished = true');
        if (finishedAt === -1) {
            err('AddonSyncTask.brs sync() never sets m.top.finished — the sentinel is what lets MainScene tell a finished worker from a pending one');
        } else {
            if (resultAt === -1) {
                err('AddonSyncTask.brs sync() sets finished without ever writing m.top.result — the sentinel would report success on a worker that produced nothing');
            } else if (resultAt > finishedAt) {
                err('AddonSyncTask.brs sync() writes m.top.finished BEFORE m.top.result — the done-callback can then fire on a worker whose result has not landed yet, which re-creates the very race the sentinel exists to settle');
            }
            const tail = sync.slice(finishedAt).split('\n').map(l => l.trim()).filter(l => l !== '');
            const last = tail[tail.length - 1];
            if (last !== 'm.top.finished = true') {
                err(`AddonSyncTask.brs sync() does not end on m.top.finished = true (last statement is "${last}") — the sentinel has to be the last thing the worker does, or it can assert completion while work remains`);
            }
        }
        if (!/catch[\s\S]*?m\.top\.result\s*=/.test(sync)) {
            err('AddonSyncTask.brs sync() no longer writes a result from its catch path — a thrown request would finish with the sentinel set and no result at all, which is unreportable');
        }
        // The stage ladder. A presence check is not enough — four of the five
        // rungs can be deleted and `/m.top.stage =/` still matches. What carries
        // the diagnosis is the rung AT THE REQUEST BOUNDARY: it is the one that
        // separates "the worker never got as far as the network" from "the request
        // went out", which is the first question anyone asks when a sync produces
        // nothing. So that specific rung is what gets pinned: a stage write on the
        // statement line immediately before the line that performs the request.
        // (Compared by line, not by character offset — the offset of the call
        // lands mid-line, so slicing "everything before it" ends on the tail of
        // the request line itself and the previous-line lookup silently compares
        // against `result = `.)
        if (!/m\.top\.stage\s*=/.test(sync)) {
            err('AddonSyncTask.brs sync() never writes m.top.stage — the fault strip can only name the failing hop if the worker records it');
        }
        const syncLines = sync.split('\n');
        const reqLine = syncLines.findIndex(l => l.includes('store.AddonCollectionGet()'));
        if (reqLine === -1) {
            err('AddonSyncTask.brs sync() no longer calls store.AddonCollectionGet() — the worker is not doing the job it exists for');
        } else {
            let prev = reqLine - 1;
            while (prev >= 0 && syncLines[prev].trim() === '') prev -= 1;
            if (prev < 0 || !/m\.top\.stage\s*=/.test(syncLines[prev])) {
                err('AddonSyncTask.brs sync() does not write m.top.stage immediately before the request call — that rung is what separates "the worker never reached the network" from "the request went out and never came back", and without it every sync failure reports one indistinguishable stage');
            }
        }
    }

    // 3. The defect itself: an empty result must be DECLINED, not reaped. This is
    //    an ordering check, not a presence check — the reap has to come after the
    //    bail, and there must be no reap before it.
    const onResult = body(main, 'onAddonSyncResult');
    if (!onResult) {
        err('MainScene.brs has no onAddonSyncResult — the sync result has no entry point');
    } else {
        const bailAt = /if\s+result\s*=\s*invalid\s+then\s+return/.exec(onResult);
        if (!bailAt) {
            err('MainScene.brs onAddonSyncResult no longer declines an empty result — an alwaysNotify result that notifies before the worker wrote one is indistinguishable from a real failure, and reaping on it destroys the answer (THE original bug)');
        }
        const reapAt = onResult.indexOf('AsyncTask_Reap(');
        if (reapAt === -1) {
            err('MainScene.brs onAddonSyncResult never reaps the task — a finished task node would stay in the tree for the life of the scene');
        } else if (bailAt && reapAt < bailAt.index) {
            err('MainScene.brs onAddonSyncResult reaps BEFORE it declines an empty result — the node is unobserved and removed while the worker is still running, so the real result can never land (THE original bug)');
        }
        // Reporting must have MOVED, not been duplicated. The old shape reported
        // the empty result from here; that text is the signature of the bug, so
        // its absence from this sub is what pins the authority. A presence check
        // alone would pass on a file that did both.
        if (/reported no result at all/.test(onResult)) {
            err('MainScene.brs onAddonSyncResult still reports the empty result itself — that report is premature by construction (it cannot know the worker is done) and it is the original bug; the done-callback owns this outcome');
        }
        if (!/if\s+result\.revokedSession\s*=\s*true/.test(onResult)) {
            err('MainScene.brs onAddonSyncResult truthiness-tests result.revokedSession — a result packet without the key reads back invalid, and `if invalid` is a hard &h18 crash on device');
        }
    }

    // 4. The done-callback is the only authority on "the worker finished with
    //    nothing", and it has to name the stage. Critically it must establish
    //    that from the sentinel's VALUE, before it reaps or clears anything.
    const onFinished = body(main, 'onAddonSyncFinished');
    if (!onFinished) {
        err('MainScene.brs has no onAddonSyncFinished — with the empty-result path now declining, the worker-finished-with-no-result outcome has no reporter at all and would be silent');
    } else {
        // Arrival means nothing. `finished` notifies once at ObserveField time
        // with value false, and that notification is dispatched on the event
        // loop, so it lands while the worker is mid-request. Treating arrival as
        // "done" reaps a live node and publishes a fault read off a task in
        // flight — which is exactly what shipped and produced
        //   (stage: request-started) on every first sync.
        const finTest = /if\s+task\.finished\s*<>\s*true\s+then\s+return/.exec(onFinished);
        if (!finTest) {
            err('MainScene.brs onAddonSyncFinished does not test task.finished\'s VALUE before acting — an alwaysNotify sentinel also notifies at ObserveField time with value false, and that notification is dispatched on the event loop (i.e. while the worker is still running), so arrival is not proof of completion. Reaping on it destroys the in-flight task and reports a stage read from a task that has not finished.');
        }
        // Ordering: the value test must precede every destructive action.
        const finAt = finTest ? finTest.index : -1;
        for (const [needle, what] of [['AsyncTask_Reap(', 'reaps the task'], ['m.addonSyncTask = invalid', 'clears the task slot'], ['AddAddonSyncFault(', 'publishes a fault']]) {
            const at = onFinished.indexOf(needle);
            if (at !== -1 && finAt !== -1 && at < finAt) {
                err(`MainScene.brs onAddonSyncFinished ${what} before testing task.finished — the spurious alwaysNotify notification would then reap a live worker and report a stage read from a task in flight`);
            }
        }
        if (!/AddAddonSyncFault\(/.test(onFinished)) {
            err('MainScene.brs onAddonSyncFinished does not report a fault — a worker that completes without a result would be indistinguishable from a healthy one');
        }
        if (!/task\.stage/.test(onFinished)) {
            err('MainScene.brs onAddonSyncFinished does not read task.stage into the fault text — the whole point of the stage field is that the failure names its own hop');
        }
        if (!/m\.addonSyncTask\s*=\s*invalid/.test(onFinished)) {
            err('MainScene.brs onAddonSyncFinished does not clear m.addonSyncTask — a stale node would be left in the tree and the next sync\'s result would be dropped as a duplicate');
        }
        if (!/AsyncTask_Reap\(/.test(onFinished)) {
            err('MainScene.brs onAddonSyncFinished never reaps the task — the finished worker\'s node would stay in the tree for the life of the scene');
        }
    }

    // 5. The wiring. Both observers must be attached before control = "RUN" —
    //    that assignment is the only point at which the worker can start, so an
    //    observer attached after it can miss its first notification entirely.
    const start = body(main, 'StartAddonSync');
    if (!start || !/AsyncTask_Launch\([\s\S]*?"onAddonSyncResult"[\s\S]*?"onAddonSyncFinished"\s*\)/.test(start)) {
        err('MainScene.brs StartAddonSync does not pass "onAddonSyncFinished" as AsyncTask_Launch\'s done-callback — the sentinel would be set with nothing observing it');
    }
    const launch = body(async, 'AsyncTask_Launch');
    if (!launch) {
        err('source/core/AsyncTask.bs has no AsyncTask_Launch');
    } else {
        if (!/ObserveField\(\s*"finished"\s*,\s*doneCallback\s*\)/.test(launch)) {
            err('AsyncTask_Launch does not observe the "finished" sentinel — the optional done-callback parameter exists but is never wired to anything');
        }
        const finAt = launch.indexOf('ObserveField("finished"');
        const runAt = launch.indexOf('control = "RUN"');
        if (finAt === -1 || runAt === -1 || finAt > runAt) {
            err('AsyncTask_Launch attaches the "finished" observer AFTER control = "RUN" — the worker can start before its observer exists, so the only notification that reports a failure can be the one that gets missed');
        }
    }
    const reap = body(async, 'AsyncTask_Reap');
    if (!reap || !/UnobserveField\(\s*"finished"\s*\)/.test(reap)) {
        err('AsyncTask_Reap does not unobserve "finished" — a done-callback left attached can fire against a node that has already been handed back or removed');
    }
    return ok;
}

// Home's catalog rows could be permanently stale, with nothing reporting it.
//
// The add-on sync gated its rebuild on `added > 0` — "at least one add-on was
// newly installed". That predicate is false on every run after the first: the
// account's add-ons are already in the registry, so none of them is "added". So
// Home was told to re-derive only on the very first sync of a fresh install and
// never again. Home kept whatever catalog set it walked at launch, which in a
// stremio session is usually just the built-in seeds because a session swap
// replaces what AddonsGetAll returns wholesale. Meanwhile the Add-ons screen,
// which reads the registry live, listed the account's add-ons correctly.
//
// The result was two views of the same registry permanently disagreeing, with no
// fault strip entry, because nothing had failed — the sync succeeded and simply
// told nobody. Device evidence: the Add-ons screen listed the stremio add-ons
// while Home showed only the built-ins, and leaving for Settings and back
// changed nothing.
//
// The fix is a set comparison rather than a count: Home records which add-on set
// its rows were derived from and re-derives when that set moves. This also
// subsumes the two cases a count can never see — a session swap (the set changes
// with nothing installed) and a walk that latched on an empty registry — which is
// why the fix is one mechanism and not three call-site patches.
//
// The brs interpreter can drive HomeScreen's subs, but it cannot run a
// HomeCatalogsTask worker, and the whole failure is about which predicate gates a
// call site. So the invariant is pinned structurally.
function checkTaskTeardownContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const body = (src, name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    // AsyncTask.bs states the contract both screens below used to break: removing
    // a running Task node frees the node WITHOUT killing the worker thread. So a
    // teardown that is only a RemoveChild leaves a thread running that can still
    // write its result into state the screen has already discarded.
    //
    // HomeScreen.RebuildRows did exactly that, unobserving the field and removing
    // the node while HomeCatalogsTask could still be walking the registry. It is
    // reached from a deep-link import, so the sequence is: a walk is in flight, an
    // import lands, RebuildRows throws the grid away and starts a second walk, and
    // the first one finishes and pushes its descriptors at the grid anyway — two
    // workers interleaving rows into one live grid.
    //
    // It had to be STOP-then-remove, not merely AsyncTask_Reap(.., true): the
    // reaper sends STOP to the task NODE, and the loop that reads that flag lives
    // on the task's own worker thread. A bare RemoveChild never reaches either.
    const home = code(read('components/HomeScreen.brs'));
    const rebuild = body(home, 'RebuildRows');
    if (!rebuild) {
        err('HomeScreen.brs has no RebuildRows() — the add-on-import rebuild path cannot be checked at all');
    } else {
        const reap = body(rebuild, 'AsyncTask_Reap') || rebuild;
        const stops = /(AsyncTask_Reap\s*\([^)]*,\s*[^,)]+,\s*true\s*\))|(task\.control\s*=\s*"STOP")/.test(reap);
        const removes = /RemoveChild\s*\(/.test(reap);
        if (!stops && removes) {
            err('HomeScreen.brs RebuildRows() removes m.catalogTask without sending STOP first. Removing a running Task node does not kill its worker thread (AsyncTask.bs says so explicitly), so a catalog walk already in flight finishes and applies its rows to a grid that was just discarded and rebuilt — two workers interleaving descriptors into one grid. Reap with doStop = true, as AsyncTask.bs prescribes for a possibly-still-running task.');
        }
    }

    // StreamsScreen is a static child that survives every pop, so CancelStreamsLoad
    // runs on the way out of an episode whose batch may still be fetching. STOP
    // does not reach an in-flight roUrlTransfer, so those workers keep their
    // sockets open and keep fetching after the screen has disowned them.
    //
    // onStreamsLoaded therefore has to tell "the task I launched is reporting" from
    // "an abandoned task of the same batch shape is reporting". providerIndex is
    // unique only WITHIN a batch: once a new episode launches its own batch, an
    // old worker whose index falls inside the new list would otherwise be
    // accepted, consume a live task's slot, and push the PREVIOUS episode's
    // streams into this episode's provider. The reporting node has to be the node
    // still being waited on.
    const streams = code(read('components/StreamsScreen.brs'));
    const loaded = body(streams, 'onStreamsLoaded');
    if (!loaded) {
        err('StreamsScreen.brs has no onStreamsLoaded() — a cancelled batch cannot be distinguished from the live one without it');
    } else {
        const identity = /task\.loadToken\s*<>\s*m\.loadToken/.test(loaded);
        const slot = /m\.loadTasks\[index\]\s*=\s*invalid/.test(loaded);
        if (slot && !identity) {
            err('StreamsScreen.brs onStreamsLoaded() clears m.loadTasks[index] on providerIndex alone. providerIndex is unique only within a batch, so a worker from a batch CancelStreamsLoad already STOPped can land here after the next episode has launched its own, take a live task\'s slot, and push the previous episode\'s streams into this one. Check the batch token first (`if m.loadToken = "" or task.loadToken <> m.loadToken then return`).');
        }
        // Neither of these node comparisons exists in BrightScript, and both were
        // written here and rejected by the device before the token replaced them:
        // `<>` between two roSGNodes is &h18 (Type Mismatch), and `.IsSame()` is
        // &hf4 — the roSGNode reference lists ifAssociativeArray, ifSGNodeChildren,
        // ifSGNodeField, ifSGNodeDict, ifSGNodeFocus, ifSGNodeBoundingRect and
        // ifSGNodeHttpAgentAccess, and no identity member among them. No static
        // check can catch either, because the brs interpreter has no node objects.
        if (/m\.loadTasks\[index\]\s*<>\s*task/.test(loaded)) {
            err('StreamsScreen.brs onStreamsLoaded() compares two roSGNodes with `<>`. BrightScript\'s comparison operators cannot be applied to node references — that is a runtime &h18 "Type Mismatch. Operator \\"<\\>" can\'t be applied to \\"roSGNode\\" and \\"roSGNode\\"" and it aborts the whole notification handler, so a provider that lands never renders. Compare the scalar loadToken instead.');
        }
        if (/m\.loadTasks\[index\]\s*\.\s*IsSame\s*\(/.test(loaded) || /\btask\s*\.\s*IsSame\s*\(/.test(loaded)) {
            err('StreamsScreen.brs onStreamsLoaded() calls IsSame() on a node. roSGNode has no such member — the documented interfaces are ifAssociativeArray, ifSGNodeChildren, ifSGNodeField, ifSGNodeDict, ifSGNodeFocus, ifSGNodeBoundingRect and ifSGNodeHttpAgentAccess — so this is a runtime &hf4 "Member function not found" that kills the handler. Compare the scalar loadToken instead.');
        }
        if (identity && /m\.loadTasks\[index\]\s*=\s*invalid\s+then\s+return/.test(loaded) === false) {
            err('StreamsScreen.brs onStreamsLoaded() never returns on an already-claimed `m.loadTasks[index] = invalid` slot. Without it a duplicate notification from the same provider re-applies its streams and decrements pendingCount a second time, so the count reaches zero early and the status line misreports while providers are still loading.');
        }
        // The token only separates batches if it is actually minted per batch and
        // stamped onto every task. Either half missing silently disables it.
        if (identity) {
            const launch = /loadToken\s*:\s*m\.loadToken/.test(streams);
            const mint = /m\.loadToken\s*=\s*m\.loadSeq\.ToStr\(\)/.test(streams);
            if (!launch) {
                err('StreamsScreen.brs LoadStreams() does not pass loadToken to AsyncTask_Launch — every task would carry the default "" from StreamsLoaderTask.xml, so the token in onStreamsLoaded compares equal for a stale batch and for the live one, which is exactly the collision it was added to prevent.');
            }
            if (!mint) {
                err('StreamsScreen.brs never mints a fresh m.loadToken per batch (m.loadToken = m.loadSeq.ToStr()) — a token that does not change between passes lets two passes over the same episode accept each other\'s reports.');
            }
        }
        // pendingCount is what OnEnter\'s same-episode guard reads to decide a
        // batch is genuinely in flight. Every terminal path must decrement it or
        // the count sticks above zero and the guard blocks a legitimate reload
        // forever, leaving an episode\'s stream list permanently empty.
        if (identity && slot) {
            const tail = loaded.slice(loaded.indexOf('m.loadTasks[index] = invalid'));
            const guard = /if\s+m\.providers\s*=\s*invalid\s+or\s+index\s*>=\s*m\.providers\.Count\(\)\s+then\s*\n\s*if\s+m\.pendingCount\s*>\s*0\s+then\s+m\.pendingCount\s*=\s*m\.pendingCount\s*-\s*1/.test(tail);
            if (!guard) {
                err('StreamsScreen.brs onStreamsLoaded() can return between claiming m.loadTasks[index] and writing into m.providers without decrementing m.pendingCount. OnEnter guards the same-episode reload on that count, so a stranded non-zero value makes the guard block every later visit and the list never fills. Count the task as landed on that path too.');
            }
        }
    }

    // The guard is only as good as the key it compares and the invalidation it
    // relies on. CancelStreamsLoad must clear BOTH, or a cancelled batch stays
    // "owned": pendingCount keeps its old value and loadKey keeps naming an
    // episode whose tasks were just reaped, so OnEnter matches, skips the reload,
    // and the list stays empty with the fetch that would fill it already cancelled.
    const cancel = body(streams, 'CancelStreamsLoad');
    if (cancel) {
        if (/m\.loadKey\s*=\s*""/.test(cancel) === false) {
            err('StreamsScreen.brs CancelStreamsLoad() does not clear m.loadKey — a reaped batch stays distinguishable from a live one, so OnEnter can treat a cancelled episode as still in flight and skip the reload that would refill the list');
        }
        if (/m\.pendingCount\s*=\s*0/.test(cancel) === false) {
            err('StreamsScreen.brs CancelStreamsLoad() does not zero m.pendingCount — OnEnter reads that count to decide a batch is in flight, so a stale non-zero value makes it skip the reload and the stream list stays empty');
        }
    }

    // The same-episode guard, and the reason it exists: OnEnter used to cancel
    // and re-launch the whole provider batch on every entry, so re-entering an
    // episode while its batch was still fetching sent a second identical request
    // per add-on. Four copies of one manifest in a single device log is this.
    const enter = body(streams, 'OnEnter');
    if (enter) {
        const guardAt = /EpisodeKey\(params\)\s*=\s*m\.loadKey/.exec(enter);
        const cancelAt = /CancelStreamsLoad\(\)/.exec(enter);
        if (guardAt && cancelAt && guardAt.index > cancelAt.index) {
            err('StreamsScreen.brs OnEnter() compares EpisodeKey only AFTER CancelStreamsLoad() — by then m.loadKey and m.pendingCount have been cleared by the cancel, so the guard can never match and every entry re-fans out the whole batch again');
        }
    }

    return ok;
}

function checkHomeCatalogStalenessContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const home = code(read('components/HomeScreen.brs'));
    const homeXml = read('components/HomeScreen.xml');
    const main = code(read('components/MainScene.brs'));
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const body = (src, name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    // 1. The predicate itself: freshness is the add-on SET, compared against
    //    what Home last derived from. A count cannot be substituted here.
    const sig = body(home, 'CatalogSignature');
    if (!sig) {
        err('HomeScreen.brs has no CatalogSignature() — nothing can tell that Home\'s rows were overtaken');
    } else if (!/m\.stores\.addons\.callFunc\(\s*"AddonsGetAll"\s*\)/.test(sig)) {
        err('HomeScreen.brs CatalogSignature() does not read the live add-on set — a signature derived from anything but the current registry cannot detect staleness');
    } else if (!/\.Sort\(/.test(sig) || !/\.Join\(/.test(sig)) {
        err('HomeScreen.brs CatalogSignature() does not sort and join — without that, two identical sets in a different order compare as different and every sync re-walks every catalog');
    }

    const ensure = body(home, 'EnsureCurrentRows');
    if (!ensure) {
        err('HomeScreen.brs has no EnsureCurrentRows() — the call sites have nothing to call, and a stale grid stays stale');
    } else {
        // Fresh must be a no-op, and the test must come BEFORE the rebuild.
        const fresh = /if\s+m\.catalogSignature\s*=\s*CatalogSignature\(\)\s+then\s+return/.exec(ensure);
        if (!fresh) {
            err('HomeScreen.brs EnsureCurrentRows() does not short-circuit when the add-on set is unchanged — every launch would re-walk every catalog over the network');
        }
        if (!/RebuildRows\(\)/.test(ensure)) {
            err('HomeScreen.brs EnsureCurrentRows() never re-derives the grid — it can detect staleness but does nothing about it');
        }
        const freshAt = fresh ? fresh.index : -1;
        const rebuildAt = ensure.indexOf('RebuildRows()');
        if (freshAt !== -1 && rebuildAt !== -1 && rebuildAt < freshAt) {
            err('HomeScreen.brs EnsureCurrentRows() rebuilds BEFORE the freshness test — the grid is re-derived on every call regardless of whether anything changed');
        }
    }

    // 2. The walk must record what it derived from, and must do so BEFORE the
    //    empty-registry early return. A walk that latched on an empty registry
    //    and left the signature at init-time "" is indistinguishable from a
    //    correct empty grid, which is precisely the state that must stay
    //    recognisable as stale once add-ons arrive.
    const start = body(home, 'StartCatalogLoad');
    if (!start) {
        err('HomeScreen.brs has no StartCatalogLoad()');
    } else {
        const setAt = /m\.catalogSignature\s*=\s*CatalogSignature\(\)/.exec(start);
        if (!setAt) {
            err('HomeScreen.brs StartCatalogLoad() never records m.catalogSignature — Home would have no record of what its rows were derived from, so nothing can ever be stale');
        }
        const emptyGate = /if\s+addons\.Count\(\)\s*=\s*0\s+then/.exec(start);
        if (emptyGate && setAt && setAt.index > emptyGate.index) {
            err('HomeScreen.brs StartCatalogLoad() records m.catalogSignature AFTER the empty-registry early return — a walk that latched on an empty registry then keeps the init-time signature, making it indistinguishable from a correct empty grid and permanently unrecoverable');
        }
    }

    // 3. Re-entry must repair it. StartCatalogLoad() is a no-op once the walk has
    //    latched, so OnEnter needs its own check or leaving and returning cannot
    //    fix a stale grid.
    const onEnter = body(home, 'OnEnter');
    if (!onEnter || !/EnsureCurrentRows\(\)/.test(onEnter)) {
        err('HomeScreen.brs OnEnter() no longer calls EnsureCurrentRows() — StartCatalogLoad() is a no-op once latched, so without this a stale grid can only be repaired by a relaunch (which is what it looked like: Settings-and-back changed nothing)');
    }

    // 4. The call sites must be UNCONDITIONAL. This is the defect itself: a
    //    rebuild gated on an install count is false on every re-sync.
    const onSync = body(main, 'onAddonSyncResult');
    if (!onSync) {
        err('MainScene.brs has no onAddonSyncResult()');
    } else {
        if (!/callFunc\(\s*"EnsureCurrentRows"\s*\)/.test(onSync)) {
            err('MainScene.brs onAddonSyncResult() no longer calls EnsureCurrentRows() — the sync is the authority on "the add-on set may have moved" and it now tells nobody');
        }
        if (/if\s+added\s*>/.test(onSync)) {
            err('MainScene.brs onAddonSyncResult() re-gates the rebuild on `added > 0` — an unchanged account installs nothing, so this is false on every run after the first and Home is never told to re-derive. That is the original bug.');
        }
    }
    const importSub = body(main, 'FinishImport');
    if (importSub) {
        if (!/callFunc\(\s*"EnsureCurrentRows"\s*\)/.test(importSub)) {
            err('MainScene.brs FinishImport() no longer calls EnsureCurrentRows() — an import that re-registers add-ons Home already has still leaves Home showing its pre-import catalog set');
        }
        if (/if\s+m\.import\.added\s*>/.test(importSub)) {
            err('MainScene.brs FinishImport() re-gates the rebuild on `m.import.added > 0` — same defect as the sync path: re-registering what is already installed adds nothing and leaves Home permanently stale');
        }
    }

    // 5. Reachable through callFunc at all.
    if (!/<function\s+name="EnsureCurrentRows"/.test(homeXml)) {
        err('HomeScreen.xml does not declare EnsureCurrentRows in its <interface> — callFunc against an undeclared name is a silent no-op, so the call sites would do nothing at all');
    }
    const init = body(home, 'init');
    if (!init || !/m\.catalogSignature\s*=\s*""/.test(init)) {
        err('HomeScreen.brs init() does not seed m.catalogSignature — an uninitialised field reads invalid, and invalid would never equal a real signature, so the very first EnsureCurrentRows() would rebuild unconditionally');
    }
    return ok;
}

// Subtitle providers are MERGED, not raced.
//
// It used to be first-hit-wins: the drain stopped at the first provider that
// returned tracks, and its list REPLACED whatever was there. So a user with two
// working subtitle add-ons saw only one provider's captions, ranked order decided
// which one got to answer at all, and a user with one flaky add-on and one good
// one got captions on some plays and not others with nothing on screen to say
// which. The fix is sequential merge: every ranked provider is asked, in rank
// order, and their tracks accumulate.
//
// Merge is only safe because of two properties, and both are invisible in the
// resulting track list — which is why they need pinning rather than eyeballing:
//
//   m.subtitleIndex is computed ONCE, on the first provider that yields tracks.
//   Re-picking per provider renumbers an append-only list underneath a selection
//   the user may already have made, silently switching them to another caption.
//
//   The append is genuinely append-only — no dedup, no re-sort, no replace. A
//   dedup would make the surviving track depend on provider order, which is the
//   device-dependent ordering this whole area was rebuilt to eliminate.
//
// The brs interpreter can run these subs, but the drain is driven by task
// callbacks the interpreter never fires, so the sequence is not observable from a
// test. Pinned structurally.
function checkSubtitleMergeContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const player = code(read('components/PlayerScreen.brs'));
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const member = (src, name) => {
        const start = src.search(new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm'));
        if (start === -1) return null;
        const rest = src.slice(start);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    const onResult = member(player, 'onSubtitleResult');
    if (!onResult) {
        err('PlayerScreen.brs has no onSubtitleResult — the merge has no entry point');
        return ok;
    }

    // 1. It must APPEND, not assign. `m.subtitleTracks = result.subtitles` is the
    //    exact first-hit-wins line this replaced, and it is the single most
    //    important thing to keep gone.
    if (/m\.subtitleTracks\s*=\s*result\.subtitles/.test(onResult)) {
        err('PlayerScreen.onSubtitleResult assigns m.subtitleTracks = result.subtitles — that REPLACES the merged list, which is first-hit-wins: the first provider to answer becomes the only one with a say');
    }
    if (!/m\.subtitleTracks\.Push\(\s*track\s*\)/.test(onResult)) {
        err('PlayerScreen.onSubtitleResult no longer appends with m.subtitleTracks.Push(track) — tracks must accumulate across providers, and the merge is the whole point');
    }

    // 2. The default pick happens once. A PickTrack call outside the firstTracks
    //    branch renumbers the list under the user on every provider that answers.
    const pick = /m\.subtitleIndex\s*=\s*m\.subtitlePicker\.PickTrack\(/.exec(onResult);
    if (!pick) {
        err('PlayerScreen.onSubtitleResult no longer picks a default track — nothing would ever be selected, only listed');
    } else {
        if (!/firstTracks/.test(onResult)) {
            err('PlayerScreen.onSubtitleResult re-picks the default on every provider — the pick must be gated on the first merge that yields tracks, or later providers renumber the list under the user\'s existing selection');
        } else {
            // The pick must be INSIDE the firstTracks guard, not merely near it.
            const guard = /if\s+firstTracks\s+then[^\n]*PickTrack\(/.test(onResult);
            if (!guard) {
                err('PlayerScreen.onSubtitleResult does not gate the PickTrack call on firstTracks — a pick per provider renumbers an append-only list and silently switches the user to a different caption');
            }
        }
    }

    // 3. The drain must continue after a provider SUCCEEDS, not only after one
    //    returns nothing. This is the difference between "one provider answered"
    //    and "every ranked provider answered".
    const lines = onResult.split('\n');
    const pushLine = lines.findIndex(l => /m\.subtitleTracks\.Push\(\s*track\s*\)/.test(l));
    const drainLine = lines.findIndex((l, i) => i > pushLine && /LaunchSubtitleFetch\(\)/.test(l));
    if (drainLine === -1) {
        err('PlayerScreen.onSubtitleResult does not launch the next provider after a SUCCESSFUL merge — first-hit-wins is back: the first provider to answer ends the search and the rest are never asked');
    }

    // 4. A merge is append-only, so it must start from nothing. Reusing the
    //    previous play's tracks mixes two videos' captions into one list and
    //    leaves the index pointing into the older half.
    const start = member(player, 'StartSubtitles');
    if (!start) {
        err('PlayerScreen.brs has no StartSubtitles');
    } else {
        if (!/m\.subtitleTracks\s*=\s*invalid/.test(start)) {
            err('PlayerScreen.StartSubtitles does not reset m.subtitleTracks — an append-only merge that starts from the previous play\'s list mixes two videos\' captions together and points m.subtitleIndex into the older half');
        }
        if (!/m\.subtitleIndex\s*=\s*-1/.test(start)) {
            err('PlayerScreen.StartSubtitles does not reset m.subtitleIndex — a stale index against a freshly reset track list selects whatever happens to sit at that position');
        }
    }

    // 5. The reap-before-check defect, in this handler. The result field is
    //    alwaysNotify with no value, so it also notifies while the request is
    //    still in flight; reaping on that unobserves the field and removes the
    //    node, and the real answer lands on a node nobody is watching.
    const resultAt = /result\s*=\s*(?:task\.result|event\.GetData\(\))/.exec(onResult);
    const reapAt = /AsyncTask_Reap\(/.exec(onResult);
    if (!resultAt) {
        err('PlayerScreen.onSubtitleResult does not read the worker result or its event snapshot');
    }
    if (!reapAt) {
        err('PlayerScreen.onSubtitleResult never reaps the subtitle task — a finished task node would stay in the tree for the life of the screen');
    } else if (resultAt && !/if\s+result\s*=\s*invalid\s+then\s+return/.test(onResult)) {
        err('PlayerScreen.onSubtitleResult reaps without declining an empty result — the alwaysNotify notification arrives while the request is in flight, so this destroys the real result (the same defect that ate the add-on sync result)');
    } else if (resultAt && reapAt) {
        const bail = /if\s+result\s*=\s*invalid\s+then\s+return/.exec(onResult);
        if (bail && reapAt.index < bail.index) {
            err('PlayerScreen.onSubtitleResult reaps BEFORE declining an empty result — the node is unobserved and removed while the worker is still running, so the real result can never land');
        }
    }
    return ok;
}

function checkHomeScreenContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'HomeScreen.xml'), 'utf8');
    const declared = new Set(
        [...xml.matchAll(/<function\s+name="([^"]+)"\s*\/?>/gi)].map(match => match[1])
    );
    let ok = true;
    for (const fn of ['RebuildRows']) {
        if (!declared.has(fn)) {
            console.error(`HomeScreen.xml is missing <function name="${fn}" /> from its interface`);
            ok = false;
        }
    }
    return ok;
}

// DiscoverScreen and LibraryScreen embed the shared FilterBar (chips + dropdown)
// and must talk to it only through its interface: callFunc handlers for the tag
// side and the chipActivated/optionPicked observers for the events. Pin the
// interface functions the component declares and that both screens observe the
// pick events.
function checkFilterBarContract() {
    const fs = require('fs');
    const root = projectRoot;
    const xml = fs.readFileSync(path.join(root, 'components', 'FilterBar.xml'), 'utf8');
    const declared = new Set(
        [...xml.matchAll(/<function\s+name="([^"]+)"\s*\/?>/gi)].map(match => match[1])
    );
    const expected = ['SetChips', 'ShowMenu', 'HideMenu', 'FocusChips', 'FocusIsOnChips', 'IsMenuOpen'];
    let ok = true;
    for (const fn of expected) {
        if (!declared.has(fn)) {
            console.error(`FilterBar.xml is missing <function name="${fn}" /> from its interface`);
            ok = false;
        }
    }
    for (const screen of ['DiscoverScreen', 'LibraryScreen']) {
        const brs = fs.readFileSync(path.join(root, 'components', `${screen}.brs`), 'utf8');
        if (!brs.includes(`m.filterBar = m.top.FindNode("filterBar")`)) {
            console.error(`${screen}.brs does not embed the shared FilterBar (FindNode "filterBar")`);
            ok = false;
        }
        for (const observe of ['"chipActivated"', '"optionPicked"']) {
            if (!brs.includes(`ObserveField(${observe}`)) {
                console.error(`${screen}.brs does not observe filterBar.${observe} — membership/deferred picks would silently no-op`);
                ok = false;
            }
        }
    }
    return ok;
}

// The account write-back worker must keep its contract (authKey + item in,
// result out with alwaysNotify) so MainScene's pump cannot silently mismatch a
// field the task never declared. One worker serves every write-back kind
// (position, watched marks, add/remove), so this pins its interface once.
function checkLibraryPutTaskContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'LibraryPutTask.xml'), 'utf8');
    const declared = {};
    for (const match of xml.matchAll(/<field\s+id="([^"]+)"([^>]*)>/gi)) {
        declared[match[1]] = match[2];
    }
    let ok = true;
    for (const field of ['authKey', 'item']) {
        if (!declared[field]) {
            console.error(`LibraryPutTask.xml is missing <field id="${field}" ... /> from its interface`);
            ok = false;
        }
    }
    if (!declared.result) {
        console.error('LibraryPutTask.xml is missing <field id="result" ... /> from its interface');
        ok = false;
    } else if (!/alwaysNotify\s*=\s*"true"/.test(declared.result)) {
        console.error('LibraryPutTask.xml: result field must be alwaysNotify="true"');
        ok = false;
    }
    return ok;
}

// The server-logout worker must keep its contract (authKey in, result out with
// alwaysNotify) so MainScene's fire-and-forget teardown cannot silently mismatch
// a field the Task never declared.
function checkLogoutTaskContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'LogoutTask.xml'), 'utf8');
    const declared = {};
    for (const match of xml.matchAll(/<field\s+id="([^"]+)"([^>]*)>/gi)) {
        declared[match[1]] = match[2];
    }
    let ok = true;
    if (!declared.authKey) {
        console.error(`LogoutTask.xml is missing <field id="authKey" ... /> from its interface`);
        ok = false;
    }
    if (!declared.result) {
        console.error('LogoutTask.xml is missing <field id="result" ... /> from its interface');
        ok = false;
    } else if (!/alwaysNotify\s*=\s*"true"/.test(declared.result)) {
        console.error('LogoutTask.xml: result field must be alwaysNotify="true"');
        ok = false;
    }
    return ok;
}

// The session rows report through SettingsScreen.pushRequest (the same
// one-action channel the other screens use). Pin the field or onSettingsAction
// can never fire to start the login flow / logout confirm.
function checkSettingsPushContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'SettingsScreen.xml'), 'utf8');
    const declared = new Set(
        [...xml.matchAll(/<field\s+id="([^"]+)"[\s>]/gi)].map(match => match[1])
    );
    if (declared.has('pushRequest')) return true;
    console.error('SettingsScreen.xml is missing <field id="pushRequest" ... /> from its interface');
    return false;
}

// onLibrarySyncResult calls m.libraryScreen.callFunc('RefreshRows') when the
// sync lands while the Library screen is top. Same callFunc interface trap as
// HomeScreen's RebuildRows — pin it.
function checkLibraryScreenContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'LibraryScreen.xml'), 'utf8');
    const declared = new Set(
        [...xml.matchAll(/<function\s+name="([^"]+)"\s*\/?>/gi)].map(match => match[1])
    );
    let ok = true;
    for (const fn of ['RefreshRows']) {
        if (!declared.has(fn)) {
            console.error(`LibraryScreen.xml is missing <function name="${fn}" /> from its interface`);
            ok = false;
        }
    }
    return ok;
}

// Two Poster/manifest facts that are invisible in review and produce a warning
// on the device console instead of a build error.
//
// 1. loadDisplayMode is an option string with a CLOSED set of values. An
//    unrecognised one is not ignored politely; it is undefined behaviour, and
//    the Poster docs warn that an oversized texture "may fail to load". Four
//    full-screen backgrounds shipped with loadDisplayMode="scaleToCrop" —
//    which reads like a real mode and is not one of the five legal values
//    (limitSize, noScale, scaleToFit, scaleToFill, scaleToZoom). Nothing in the
//    diff looked wrong, and no test failed; the only symptom was a device-console
//    warning nobody reads.
//
// 2. ui_resolutions must name EXACTLY ONE resolution. Declaring several makes
//    Roku treat each as a distinct design target and draw it natively instead of
//    scaling, so every coordinate has to be authored for each one. This app's
//    layout is entirely hardcoded 1920x1080 (43 width/height attributes, and no
//    GetUIResolution/GetDisplaySize anywhere), so the single-canvas
//    auto-scaling in ui_resolutions=fhd is the ONLY thing making it display
//    correctly on the 720p-UI devices that are most of the range. Adding "hd"
//    renders those same 1920x1080 coordinates 1:1 on a 1280x720 canvas and every
//    element comes out 1.5x oversized — a silent, total layout failure.
//
// The Poster load-size policy, which the earlier version of this comment got
// exactly backwards. It claimed capping loadWidth/loadHeight "visibly degrades
// the artwork, which is strictly worse" and that nothing should push toward
// downscaling. Measured on a real device, both halves of that are wrong:
//
//   1. UNCAPED is what degrades artwork. Home builds a tile for every meta in
//      every catalog row — a few hundred — and add-on posters arrive at 500x750,
//      costing 500*750*4 = 1.43MB of texture each to fill a 270x405 node. Total
//      demand ran ~570MB against a budget no device has, so the memory manager
//      evicted continuously and every evicted tile refetched. That is the
//      visible symptom: posters flashing while scrolling the grid, rail icons
//      vanishing under the same pressure, and a device log full of
//      "sg.scene.bitmap.big". Capped to the node, each tile is 0.42MB.
//
//   2. The size must come from the node's own canvas dimensions, never from the
//      UI resolution. ui_resolutions=fhd means the canvas is 1920x1080 on every
//      device and Roku scales the whole canvas to whatever panel it finds. On a
//      720p-UI device that means the canvas renders at 1280x720 and the panel
//      upscales. Capping the artwork to the UI resolution — which is what
//      "Loaded texture (1920 x 1080) larger than the UI resolution (1280 x 720)"
//      appears to ask for — made it worse, not better: Roku downsampled the
//      source at load, then the canvas upscale resampled it again, and the
//      backgrounds visibly degraded. A texture the size of its node is already
//      correct there. So sg.scene.bitmap.big is a false signal on 720p devices
//      and is deliberately NOT an error here; GetUIResolution/GetDisplaySize
//      must never feed a load size, which is why that pairing is rejected above.
//
// limitSize is the only mode that caps the texture at load — the others scale at
// draw time and leave the full bitmap resident — so it is the mode to reach for.
// It preserves aspect ratio, which is why an off-ratio source decodes smaller than
// its node and leaves an uncovered strip rather than being squashed. That is
// acceptable only because every capped tile here sits over something opaque
// rather than over bare artwork (see checkPosterScalingContract). Capped tiles:
// PosterTile (2:3 tile, 2:3 posters), EpisodeTile (16:9 cell, 16:9 stills), and
// the 1:1 glyphs. EpisodeTile used to be exempt on the theory that its crop was
// load-bearing; that was weighing a cosmetic edge case against ~25-30 uncapped
// cells per season row, which is the wrong side of the ledger.
// A Poster that crops (scaleToZoom) is a promise about its source: the node shows
// the centre of the image, scaled by max(nodeW/srcW, nodeH/srcH) so it covers the
// node. When the source's aspect ratio matches the node's, that is a near-identity
// and nothing is lost. When it does not, the crop silently throws most of the
// image away — and for a gradient the surviving slice can be the one part that
// looks completely wrong.
//
// This is not hypothetical. images/mask.png was a 1918x1079 vertical alpha ramp in
// a 1920x1080 node: aspects matched to within 0.1%, so scaleToZoom was effectively
// a fit and the scrim looked right. Shrinking it to an 8x256 ramp — 8KB of texture
// instead of 8.36MB — left scaleToZoom scaling it 240x, rendering 1920x61440, and
// cropping to source rows 125.8-130.2: alpha ~247, i.e. a flat opaque black
// Episodes background. Nothing in the diff looked wrong and nothing failed to
// build; the screen just went black.
//
// The lesson is not "don't shrink the mask", it is that an asset's aspect ratio is
// load-bearing whenever the display mode crops. Two ways out, and this pins both:
//   - Give the asset the node's aspect ratio so no crop can change what is shown
//     (mask.png is now 114x64, 16:9 to within 0.2%, at 29KB instead of 8.36MB).
//   - Or pick a display mode that does not crop, when the source has no aspect
//     worth preserving. A gradient uniform along x has nothing to preserve, so
//     scaleToFill is both correct and immune to this entire class of bug.
function checkPosterLoadSizePolicy() {
    const fs = require('fs');
    const path = require('path');
    let ok = true;
    const projectRoot = path.resolve(__dirname, '..');
    const dir = path.join(projectRoot, 'components');
    const attr = (src, name) => {
        const m = new RegExp('\\b' + name + '="([^"]*)"').exec(src);
        return m ? m[1] : null;
    };
    const num = (v) => (v === null ? null : parseInt(v, 10));

    let cappedHighVolumeTile = false;

    for (const name of fs.readdirSync(dir).filter(f => f.endsWith('.xml'))) {
        const xml = fs.readFileSync(path.join(dir, name), 'utf8');

        for (const m of xml.matchAll(/<Poster\b([^>]*?)\/?>/g)) {
            const id = attr(m[1], 'id') || '(anonymous)';
            const w = num(attr(m[1], 'width'));
            const h = num(attr(m[1], 'height'));
            const lw = num(attr(m[1], 'loadWidth'));
            const lh = num(attr(m[1], 'loadHeight'));

            // A hint with only half the pair leaves the other dimension
            // uncapped, which looks correct and does not work.
            if ((lw === null) !== (lh === null)) {
                console.error(`${name}: Poster "${id}" sets only one of loadWidth/loadHeight — the other dimension stays uncapped, so the bitmap is still oversized in that axis. Set both or neither`);
                ok = false;
                continue;
            }
            if (lw === null) continue;

            // The rule the old comment got backwards, stated as an invariant:
            // a load hint may only ever match or undercut its own node. A hint
            // derived from the UI resolution (or from GetDisplaySize) lands here
            // and is rejected, which is exactly the backgrounds regression.
            if ((w !== null && lw > w) || (h !== null && lh > h)) {
                console.error(`${name}: Poster "${id}" caps its load at ${lw}x${lh}, which is LARGER than its own ${w}x${h} node — a load hint must never exceed the node it fills. Deriving the hint from the UI resolution rather than the node is what downsamples artwork twice (once at load, once in the canvas upscale) and visibly degrades it`);
                ok = false;
            }

            if (name === 'PosterTile.xml' && id === 'poster') cappedHighVolumeTile = true;
        }
    }

    // The tile behind every Home catalog row. Without its hint the grid goes
    // back to ~570MB of texture demand and the eviction/refetch cycle returns,
    // and nothing in the diff would look wrong.
    if (!cappedHighVolumeTile) {
        console.error('PosterTile.xml: the "poster" node must set loadWidth/loadHeight/limitSize. It is the component behind every Home catalog tile, and it is the one whose uncapped texture size causes the eviction and refetch cycle');
        ok = false;
    }

    // PosterTile now resizes itself from the per-row cell RowList writes into
    // its width/height interface fields (channel/tv rows are 1:1 squares). The
    // load caps must ride the node, or a square cell decodes at the XML-only
    // 270x405 hint — still one cap, but for a node that is no longer that
    // shape. Declaring the fields is what lets the tile learn its size at all.
    const tileBrs = fs.readFileSync(path.join(projectRoot, 'components', 'PosterTile.brs'), 'utf8');
    const posterTileXml = fs.readFileSync(path.join(projectRoot, 'components', 'PosterTile.xml'), 'utf8');
    if (!/<field\s+id="width"\s+type="float"[^>]*onChange="ApplyTileSize"/.test(posterTileXml) ||
        !/<field\s+id="height"\s+type="float"[^>]*onChange="ApplyTileSize"/.test(posterTileXml)) {
        console.error('PosterTile.xml must declare the RowList width/height item fields (wired to ApplyTileSize) — without them the tile never learns its per-row cell size and a square row renders the fixed 2:3 slab');
        ok = false;
    }
    if (!/m\.poster\.loadWidth\s*=\s*w/.test(tileBrs) || !/m\.poster\.loadHeight\s*=\s*h/.test(tileBrs)) {
        console.error('PosterTile.brs ApplyTileSize must resize loadWidth/loadHeight WITH width/height — a dynamically resized tile that keeps the XML-only caps decodes a texture that no longer matches its node shape');
        ok = false;
    }

    return ok;
}

// The companion-app QR on AddonsScreen. Three things are invisible until someone
// looks at the TV — or, in the third case's absence, invisible until texture
// telemetry is pulled — which is exactly why they are pinned here:
//   1. The Poster's uri must name a file that exists. A typo'd or missing pkg path
//      simply paints nothing — the same silent failure that made the QR vanish on
//      LinkStremioScreen.
//   2. loadSync must NOT be set. It was originally required, on the reasoning
//      that a bundled image has no network to wait on so there is no reason to
//      paint a frame with a hole. Device testing showed the hole is not real —
//      the panel renders correctly without it — while the stall is: loadSync
//      blocks startup on decoding a 700x700 asset for a screen most sessions
//      never open.
//
//      One thing this does NOT do, which an earlier version of this comment got
//      wrong: removing loadSync does not free the texture. A fresh-start
//      r2d2-bitmaps with loadSync already removed still showed both QRs resident
//      at 700x700 / 1,982,464 bytes each while sitting on Home. Roku eagerly
//      decodes bundled Poster textures for nodes that exist in the scene graph,
//      and every static screen exists from app start. loadSync only controls
//      whether the app *blocks* on that decode, not whether it happens. Actually
//      reclaiming those ~3.96MB means clearing the Poster's uri when the screen
//      is hidden, which is a separate change and is not implemented here — do not
//      assume otherwise from this check passing.
//   3. The image must still decode to the URL the panel copy claims it offers.
//      The encoder in scripts/gen-companion-qr.js is a hand-rolled QR
//      implementation, and a QR that looks right but will not scan is worse than
//      none at all — the version/EC table is easy to get subtly wrong in a way
//      that renders plausibly. Rather than re-implement a decoder here, the
//      encoder round-trips through a reference implementation when one is
//      available (see verify-companion-qr.js), so this check covers what is
//      cheaply checkable and points at the rest.
function checkCompanionQrContract() {
    const fs = require('fs');
    let ok = true;
    const dir = path.join(projectRoot, 'components');
    const xml = fs.readFileSync(path.join(dir, 'AddonsScreen.xml'), 'utf8');

    const posters = [...xml.matchAll(/<Poster\b([^>]*)>/g)];
    if (posters.length === 0) {
        // The personal build uses the local browser setup form. A companion
        // Android application and its QR are optional, not a runtime contract.
        return true;
    }
    for (const m of posters) {
        const attrs = m[1];
        const id = (/\bid="([^"]*)"/.exec(attrs) || [, '(anonymous)'])[1];
        const uri = /\buri="([^"]*)"/.exec(attrs);
        if (!uri || !uri[1].trim()) {
            console.error(`AddonsScreen.xml: Poster "${id}" has no uri — it would paint nothing`);
            ok = false;
            continue;
        }
        if (!/\bpkg:\/images\//.test(uri[1])) {
            console.error(`AddonsScreen.xml: Poster "${id}" uri is not a bundled pkg:/images/ path (got "${uri[1]}"). The companion QR must ship with the app, not be fetched at runtime`);
            ok = false;
        }
        const rel = uri[1].replace(/^pkg:\//, '');
        if (!fs.existsSync(path.join(projectRoot, rel))) {
            console.error(`AddonsScreen.xml: Poster "${id}" uri "${uri[1]}" does not resolve to ${rel} on disk`);
            ok = false;
        }
        if (/\bloadSync="true"/.test(attrs)) {
            console.error(`AddonsScreen.xml: Poster "${id}" sets loadSync="true". Device testing showed the companion panel renders correctly without it, so loadSync only buys a startup stall on decoding a 700x700 asset for a screen most sessions never open. Note this does NOT reclaim texture memory either way — see the comment above for what actually would`);
            ok = false;
        }
    }

    // The generator has to keep existing alongside the image, or the asset becomes
    // an untraceable blob — the state the two donation QRs in SupportDialog are in.
    const genPath = path.join(projectRoot, 'scripts', 'gen-companion-qr.js');
    if (!fs.existsSync(genPath)) {
        console.error('scripts/gen-companion-qr.js is missing. It records what the QR encodes and regenerates it; without it images/qr-companion.png is an untraceable blob');
        ok = false;
    } else {
        const gen = fs.readFileSync(genPath, 'utf8');
        if (!/const URL\s*=\s*'https?:\/\//.test(gen)) {
            console.error('scripts/gen-companion-qr.js: expected a `const URL = \'https://...\'` holding the encoded target, so the encoded value stays greppable');
            ok = false;
        }
    }

    // The panel is decorative. If anything in it ever becomes focusable it stops
    // being an OK/Back no-op, which is the property AddonsScreen's key handling
    // depends on — so assert there is nothing there to focus.
    for (const bad of ['Button', 'RowList', 'PosterGrid', 'CheckBox', 'RadioButton', 'EditText']) {
        if (new RegExp(`<${bad}\\b`).test(xml)) {
            console.error(`AddonsScreen.xml: <${bad} /> inside the companion panel. The panel is decorative and must not add a focus stop to a screen that has exactly one (addonsList)`);
            ok = false;
        }
    }

    return ok;
}

function checkSetupServerContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const setup = fs.readFileSync(path.join(projectRoot, 'source', 'util', 'SetupPage.brs'), 'utf8');
    const main = fs.readFileSync(path.join(projectRoot, 'source', 'main.brs'), 'utf8');
    const sceneBrs = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.brs'), 'utf8')
        .split('\n').map(line => line.split("'")[0]).join('\n');
    const sceneXml = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.xml'), 'utf8');
    const addonsBrs = fs.readFileSync(path.join(projectRoot, 'components', 'AddonsScreen.brs'), 'utf8');
    const addonsXml = fs.readFileSync(path.join(projectRoot, 'components', 'AddonsScreen.xml'), 'utf8');

    // The pure helper layer and the socket lifecycle live in one file; the
    // socket layer is never exercised by tests, so its API surface has to stay
    // pinned here for main.brs to compile against.
    for (const fn of ['SetupServerStart', 'SetupServerPoll', 'SetupServerClose', 'SetupServerPort', 'SetupLanAddress']) {
        if (!new RegExp(`function ${fn}\\s*\\(|sub ${fn}\\s*\\(`).test(setup)) {
            err(`SetupPage.brs has no ${fn}() — source/main.brs calls it and the device has no fallback`);
        }
    }

    // The listener must register on the SCREEN's message port, or the Wait loop
    // would never receive a roSocketEvent for it.
    if (!/listener\.SetMessagePort\s*\(\s*port\s*\)/.test(setup)) {
        err('SetupPage.brs SetupServerStart must SetMessagePort(port) on the listener — the socket events have to land on the same port Wait() drains');
    }
    // ...and every exit path in Main() must close it. Three returns exist:
    // the exitApp poll fallback, the screen-closed event, and the exitApp node
    // event. A return with no close leaves the listener bound for the session.
    const exits = [...main.matchAll(/^[ \t]*return$/gm)];
    if (exits.length < 3) {
        err(`source/main.brs has only ${exits.length} return(s) in Main — expected the three exit paths`);
    } else {
        for (const m of exits) {
            const before = main.slice(0, m.index).trimEnd().split('\n').pop();
            if (!/SetupServerClose\s*\(/.test(before)) {
                err('source/main.brs returns without SetupServerClose(setup) on every exit path — the port stays bound and the loop is gone');
            }
        }
    }
    if (!/Type\(message\)\s*=\s*"roSocketEvent"/.test(main) || !/SetupServerPoll\s*\(/.test(main)) {
        err('source/main.brs must dispatch roSocketEvent into SetupServerPoll — without it accepted connections sit in the listen backlog forever');
    }

    // The Scene handoff is via callFunc, which only works for DECLARED
    // interface functions — an undeclared one silently no-ops on device while
    // passing the (mocked) interpreter. Pin the declarations to the calls.
    const declaredScene = new Set(
        [...sceneXml.matchAll(/<function\s+name="([^"]+)"\s*\/?>/gi)].map(m => m[1])
    );
    for (const fn of ['ShowSetupAddress', 'ImportFromSetup']) {
        if (!declaredScene.has(fn)) {
            err(`MainScene.xml is missing <function name="${fn}" /> from its interface`);
        }
    }
    if (!new RegExp(`sub ShowSetupAddress\\s*\\(`).test(sceneBrs) || !new RegExp(`function ImportFromSetup\\s*\\(`).test(sceneBrs)) {
        err('MainScene.brs must define ShowSetupAddress() and ImportFromSetup() — main() and the setup page call them');
    }
    if (!new RegExp(`ImportFromSetup\\s*\\([^)]*\\)\\s*[\\s\\S]*\\nend function`).test(sceneBrs) || !/BeginImport\s*\(/.test(sceneBrs)) {
        err('MainScene.brs ImportFromSetup no longer routes through BeginImport — the deep-link and setup-page paths must share the single import slot');
    }

    const declaredAddons = new Set(
        [...addonsXml.matchAll(/<function\s+name="([^"]+)"\s*\/?>/gi)].map(m => m[1])
    );
    if (!declaredAddons.has('SetSetupAddress')) {
        err('AddonsScreen.xml is missing <function name="SetSetupAddress" /> from its interface');
    }
    if (!/sub SetSetupAddress\s*\(/.test(addonsBrs)) {
        err('AddonsScreen.brs must define SetSetupAddress() — the Scene forwards the address into it');
    }
    for (const id of ['setupHint', 'setupUrl']) {
        if (!new RegExp(`id="${id}"[^>]*>`, 's').test(addonsXml)) {
            err(`AddonsScreen.xml has no label id="${id}" — the page address has nowhere to show`);
        }
    }

    // The port is one fact with two consumers (the TV that prints it, the
    // listener that binds it); a second literal anywhere would let the two
    // drift. And 8324 is verboten — that is the reference app's port.
    if (!/\b8744\b/.test(setup)) {
        err('SetupPage.brs must serve SetupServerPort()=8744 — see the comment there');
    }
    if (/\b8324\b/.test(setup) || /\b8324\b/.test(main)) {
        err('port 8324 is the reference app\'s port and must not be reused');
    }

    return ok;
}

// The details screen must hand the stream picker the add-on CONTENT type
// verbatim. channel/tv (and any future type) items only resolve when the
// stream request is keyed by the real type: a literal "movie"/"series" sends a
// live-TV add-on a /stream/movie/{id}.json it does not answer, and the user
// gets "No streams found". A literal here is a functional break, not cosmetics.
function checkDetailsMetaTypeContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const details = fs.readFileSync(path.join(projectRoot, 'components', 'DetailsScreen.brs'), 'utf8');

    const literal = details.match(/metaType:\s*"(movie|series)"/);
    if (literal) {
        err(`DetailsScreen.brs passes a literal metaType "${literal[1]}" — a considered-kind item of another type would resolve /stream/{wrongType}/{id}.json and an add-on that routes on type would answer nothing`);
    }

    const passThrough = details.match(/metaType:\s*m\.meta\.type/g);
    if (!passThrough || passThrough.length < 2) {
        err('DetailsScreen.brs must pass metaType: m.meta.type on every streamsScreen push (PlayMedia and ResumeEpisode) — the content type has to reach the /stream/ endpoint verbatim');
    }

    return ok;
}

// Stream format is resolved in PlaybackStore now, not sniffed in the player, so
// one path serves a direct URL and a torrent and the store tests can reach it.
// FormatFromUrl strips a URL's query before sniffing the path extension, and
// only then reads a filename hidden in the query itself. The method-form InStr
// is zero-based, so the correct chop is Left(queryIndex) (everything up to the
// '?'). Left(queryIndex - 1) would also eat the last path character: URLs like
// ".../stream.mp4?token=x" would lose their format and the Video node would
// start the classic format-less black screen.
function checkStreamFormatQueryContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const store = fs.readFileSync(path.join(projectRoot, 'source', 'stores', 'PlaybackStore.bs'), 'utf8');
    const player = fs.readFileSync(path.join(projectRoot, 'components', 'PlayerScreen.brs'), 'utf8');

    const block = /function FormatFromUrl[\s\S]*?end function/.exec(store);
    if (!block) {
        err('PlaybackStore.bs has no FormatFromUrl() — ResolvePlayback depends on the sniffed streamFormat');
        return ok;
    }
    if (block[0].includes('Left(queryIndex - 1)')) {
        err('PlaybackStore.bs FormatFromUrl chops the query one character early (Left(queryIndex - 1)) — the zero-based InStr index is where the "?" sits, so the correct chop is Left(queryIndex)');
    }
    if (!block[0].includes('Left(queryIndex)')) {
        err('PlaybackStore.bs FormatFromUrl no longer strips the query with Left(queryIndex) — query-bearing stream URLs get no streamFormat');
    }

    // The resolved format has to reach the Video node, and the player must not
    // re-sniff it: two detectors drift, and an unset streamFormat defaults to MP4.
    if (!/result\.streamFormat\s*=\s*m\.StreamFormat\(/.test(store)) {
        err('PlaybackStore.bs ResolvePlayback never sets result.streamFormat from StreamFormat() — the player is handed nothing to declare');
    }
    if (/function\s+DetectStreamFormat\s*\(/.test(player)) {
        err('PlayerScreen.brs still defines DetectStreamFormat() — PlaybackStore owns stream-format detection now, so the player must consume the resolved value');
    }
    if (!/StartPlayback\(\s*result\.url\s*,\s*result\.streamFormat\s*\)/.test(player)) {
        err('PlayerScreen.brs does not forward result.streamFormat into StartPlayback — the Video node would fall back to the default MP4 container');
    }

    return ok;
}

function checkChannelCwPolicyContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const store = fs.readFileSync(path.join(projectRoot, 'source', 'stores', 'LibraryStore.bs'), 'utf8');
    const host = fs.readFileSync(path.join(projectRoot, 'components', 'StoreHost.brs'), 'utf8');
    const player = fs.readFileSync(path.join(projectRoot, 'components', 'PlayerScreen.brs'), 'utf8');

    // A live channel has no resume point, so it must never become a
    // continue-watching entry: not from local playback, and not from the
    // account's library on a linked session. One shared predicate keeps every
    // gate honest; a stray literal at any one of the four gates resurrects the
    // entries through the others.
    const predicate = /function IsChannelType\(metaType as string\) as boolean[\s\S]*?(channel|tv)[\s\S]*?return true[\s\S]*?return false[\s\S]*?end function/.exec(store);
    if (!predicate) {
        err('LibraryStore.bs has no IsChannelType() predicate — the policy needs one shared test for "channel"/"tv" so the player gates and the sync filter cannot drift');
    }

    const setGate = store.includes('if m.IsChannelType(metaType) then return');
    if (!setGate) {
        err('LibraryStore.bs SetPosition does not early-return on channel/tv — local playback would push a live channel onto the continue-watching stack');
    }

    const syncFilter = /parsed\.cw and not m\.IsChannelType\(parsed\.metaType\)/.exec(store);
    if (!syncFilter) {
        err('LibraryStore.bs SyncFromStremio no longer excludes channel/tv items from the cw stack — a linked session would surface the account\'s live-channel entries in Continue Watching');
    }

    const bridge = host.includes('function LibraryIsChannelType(metaType as string) as boolean');
    if (!bridge) {
        err('StoreHost.brs has no LibraryIsChannelType bridge — the player cannot call the shared predicate through m.stores.library');
    }

    const gate = /LibraryIsChannelType", metaType\)\s+then return/;
    const save = /sub SavePosition[\s\S]*?end sub/.exec(player);
    const publish = /sub PublishWatchState[\s\S]*?end sub/.exec(player);

    // The gate reads params.metaType, so params must be assigned FIRST. Grepping
    // for the gate alone cannot catch the reverse order: reading .metaType off
    // an uninitialized local throws &hec ("Dot operator attempted with invalid
    // BrightScript Component or interface reference") BEFORE the gate runs, so
    // the guard never executes and the throw unwinds Back out of the handler —
    // the app freezes with no crash and no position ever saved. This is exactly
    // how a live channel "lost Back" after a play had really started.
    const paramsBeforeGate = (block) => {
        const assign = block.indexOf('params = m.playParams');
        const use = block.indexOf('LibraryIsChannelType');
        return assign !== -1 && use !== -1 && assign < use;
    };
    if (!save || !gate.test(save[0])) {
        err('PlayerScreen.brs SavePosition no longer returns early for channel/tv — leaving a live channel would record a meaningless resume point');
    } else if (!paramsBeforeGate(save[0])) {
        err('PlayerScreen.brs SavePosition references params before assigning it — reading params.metaType off an uninitialized local throws &hec and freezes the app before the channel gate can run (assign params = m.playParams first)');
    }
    if (!publish || !gate.test(publish[0])) {
        err('PlayerScreen.brs PublishWatchState no longer returns early for channel/tv — a paused live channel would publish a position the account push turns into a continue-watching entry');
    } else if (!paramsBeforeGate(publish[0])) {
        err('PlayerScreen.brs PublishWatchState references params before assigning it — same &hec trap seen in SavePosition (assign params = m.playParams first)');
    }

    return ok;
}

function checkMetaFieldCoercionContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const details = fs.readFileSync(path.join(projectRoot, 'components', 'DetailsScreen.brs'), 'utf8');
    const player = fs.readFileSync(path.join(projectRoot, 'components', 'PlayerScreen.brs'), 'utf8');

    // Roku refuses to cast an explicitly-passed invalid into a typed `as string`
    // parameter — a default only fills in when the argument is OMITTED. poster and
    // posterShape are absent on many add-ons, so feeding m.meta.<field> (or
    // params.<field>) straight across the typed LibraryAddSaved/LibrarySetPosition
    // boundary throws &h18 on device and freezes the tap. @rokucommunity/brs coerces
    // leniently and never reproduces it, so pin the call sites here: the optional
    // args must be pre-normalized locals, never raw field accesses.
    const addLine = (details.match(/.*callFunc\("LibraryAddSaved".*/) || [''])[0];
    if (addLine.includes('m.meta.poster')) {
        err('DetailsScreen.brs passes m.meta.poster/posterShape straight into LibraryAddSaved — an invalid (missing) field casts to a typed string param and throws &h18 on device');
    }
    if (!details.includes('if m.meta.poster <> invalid then')) {
        err('DetailsScreen.brs no longer normalizes m.meta.poster before LibraryAddSaved — an absent poster would crash the save');
    }
    if (!details.includes('if m.meta.posterShape <> invalid then')) {
        err('DetailsScreen.brs no longer normalizes m.meta.posterShape before LibraryAddSaved — the common no-shape case crashes the save');
    }
    // The play-param pushes carry m.meta.poster/posterShape inside an AA on purpose
    // (the player normalizes before its typed SetPosition), so only the write-back
    // packet is a typed boundary: MainScene feeds change.poster into
    // LibraryBuildLibraryChangeItem(poster as string), so it must be the local.
    const packet = (details.match(/m\.top\.libraryChange\s*=\s*\{[\s\S]*?\}/) || [''])[0];
    if (packet.includes('poster: m.meta.poster')) {
        err('DetailsScreen.brs publishes poster: m.meta.poster in the libraryChange packet — MainScene feeds it into the typed LibraryBuildLibraryChangeItem and a missing poster throws &h18 on device; send the normalized local instead');
    }

    const setLine = (player.match(/.*callFunc\("LibrarySetPosition".*/) || [''])[0];
    if (setLine.includes('params.poster')) {
        err('PlayerScreen.brs passes params.poster/posterShape straight into LibrarySetPosition — normalize a missing field to "" first');
    }
    if (!player.includes('if params.posterShape <> invalid then')) {
        err('PlayerScreen.brs no longer normalizes params.posterShape before LibrarySetPosition — a title with no shape crashes the position save');
    }

    return ok;
}

function checkStreamTypeGateContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const streams = fs.readFileSync(path.join(projectRoot, 'components', 'StreamsScreen.brs'), 'utf8');
    const store = fs.readFileSync(path.join(projectRoot, 'source', 'stores', 'AddonsStore.bs'), 'utf8');
    const host = fs.readFileSync(path.join(projectRoot, 'components', 'StoreHost.brs'), 'utf8');
    const hostXml = fs.readFileSync(path.join(projectRoot, 'components', 'StoreHost.xml'), 'utf8');

    // Provider selection must mirror Stremio's Manifest::is_resource_supported:
    // a single id-aware predicate checks the "stream" resource together with the
    // media type AND the video id against the add-on's declared types and
    // idPrefixes. The old two-step resource+type gate is gone — an id-agnostic
    // gate would ask "tt"/"kitsu" add-ons for YouTube ids and vice versa.
    const load = /sub LoadStreams[\s\S]*?end sub/.exec(streams);
    if (!load) {
        err('StreamsScreen.brs has no LoadStreams() — the provider build is where the resource match has to be applied');
        return ok;
    }
    const gate = /AddonsSupportsResource"\s*,\s*addon\.resources\s*,\s*addon\.types\s*,\s*addon\.idPrefixes\s*,\s*"stream"\s*,\s*ParamString\(params\.metaType\)\s*,\s*ParamString\(params\.videoId\)/.exec(load[0]);
    if (!gate) {
        err('StreamsScreen.brs LoadStreams does not gate providers on AddonsSupportsResource(addon.resources, addon.types, addon.idPrefixes, "stream", metaType, videoId) — add-ons that cannot serve this media would be queried');
    } else if (load[0].indexOf('providers.Push') !== -1 && load[0].indexOf('AddonsSupportsResource') > load[0].indexOf('providers.Push')) {
        err('StreamsScreen.brs LoadStreams evaluates the resource gate after providers.Push — a provider pushed before the check is still queried, so the filter has no effect');
    }

    // The predicate itself: it must distinguish short from full resources (short
    // inherits the manifest filters), apply the type gate, and defer the id match
    // to MatchesIdPrefixes — the three ways this could silently degrade to "ask
    // everyone".
    const supports = /function SupportsResource\([\s\S]*?end function/.exec(store);
    if (!supports) {
        err('AddonsStore.bs has no SupportsResource() — the resource/id matcher that mirrors stremio-core is missing');
    } else {
        if (!/m\.MatchesIdPrefixes\(/.test(supports[0])) {
            err('AddonsStore.bs SupportsResource() no longer matches ids against the add-on idPrefixes — a "tt"/"kitsu" add-on would be asked for any id');
        }
        if (!/short/.test(supports[0])) {
            err('AddonsStore.bs SupportsResource() no longer distinguishes short from full resources — a short "stream" would not inherit the manifest types/idPrefixes');
        }
        if (!/m\.HasType\(/.test(supports[0])) {
            err('AddonsStore.bs SupportsResource() no longer applies the type gate — a live-TV add-on would be asked for movie/series streams');
        }
    }
    const prefixes = /function MatchesIdPrefixes\([\s\S]*?end function/.exec(store);
    if (!prefixes || !/Left\(/.test(prefixes[0])) {
        err('AddonsStore.bs MatchesIdPrefixes() no longer compares by prefix — the id filter would never match anything');
    }

    // Both install paths must persist idPrefixes, or the matcher always sees
    // "any id" and the per-id filter is inert.
    if (!/idPrefixes: m\.DeclaredList\(json\.idPrefixes\)/.test(store)) {
        err('AddonsStore.bs Install no longer stores the manifest idPrefixes — the id filter would silently pass every id');
    }
    if (!/idPrefixes: m\.DeclaredList\(manifest\.idPrefixes\)/.test(store)) {
        err('AddonsStore.bs InstallFromDescriptor no longer stores the manifest idPrefixes — the id filter would silently pass every id');
    }

    const hasType = /function HasType\(types as dynamic, metaType as string\) as boolean[\s\S]*?channel[\s\S]*?tv[\s\S]*?return false[\s\S]*?end function/.exec(store);
    if (!hasType) {
        err('AddonsStore.bs HasType() no longer treats channel/tv as one family — a "tv"-typed live add-on would be dropped for channel media (and vice versa)');
    }

    if (!host.includes('function AddonsSupportsResource(resources as dynamic, types as dynamic, idPrefixes as dynamic, name as string, metaType as string, id as string) as boolean')) {
        err('StoreHost.brs has no AddonsSupportsResource bridge — StreamsScreen cannot reach the store predicate through m.stores.addons');
    }
    if (!/<function name="AddonsSupportsResource" \/>/.test(hostXml)) {
        err('StoreHost.xml is missing <function name="AddonsSupportsResource" /> — callFunc against an undeclared interface function is a silent no-op that returns invalid, which would read as "matches nothing"');
    }

    return ok;
}

// Discover browses every installed add-on, not just Cinemeta. The failure mode
// this guards is a silent regression to the built-in catalog: a hardcoded
// cinemeta id/address, a chart slotted back in, or a task fed a pre-built extra
// string that skips genre encoding. It also pins that the shared source
// resolution (CatalogSourcesTask + the AddonsCatalogCapabilities/Title bridges)
// is actually wired, since a missing StoreHost declaration is a silent no-op.
function checkDiscoverSourcesContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const read = (...p) => fs.readFileSync(path.join(projectRoot, ...p), 'utf8');

    const screen = read('components', 'DiscoverScreen.brs');
    const taskXml = read('components', 'DiscoverLoaderTask.xml');
    const task = read('components', 'DiscoverLoaderTask.brs');
    const sourcesTask = read('components', 'CatalogSourcesTask.brs');
    const sourcesXml = read('components', 'CatalogSourcesTask.xml');
    const host = read('components', 'StoreHost.brs');
    const hostXml = read('components', 'StoreHost.xml');

    if (/com\.linvo\.cinemeta/.test(screen)) {
        err('DiscoverScreen.brs still hardcodes the Cinemeta add-on id — Discover must browse every installed catalog add-on');
    }
    if (/\bCatalogId\s*\(/.test(screen) || /\bcatalogId\s*[:=]\s*"imdbRating"/.test(screen)) {
        err('DiscoverScreen.brs still maps a chart to a hardcoded catalog id — Discover takes its catalog from the selected source');
    }
    if (!/AsyncTask_Launch\(m\.top,\s*"CatalogSourcesTask"/.test(screen) || !/onSourcesLoaded/.test(screen)) {
        err('DiscoverScreen.brs does not resolve sources through CatalogSourcesTask/onSourcesLoaded');
    }
    if (!/AddonsCatalogCapabilities"\s*,\s*descriptor/.test(screen) || !/\.feed\b/.test(screen)) {
        err('DiscoverScreen.brs does not gate catalogs on AddonsCatalogCapabilities(...).feed');
    }
    if (!/m\.selectedCatalog\.address/.test(screen) || !/m\.selectedCatalog\.rawType/.test(screen)) {
        err('DiscoverScreen.brs does not fetch against the selected catalog (m.selectedCatalog.address/rawType)');
    }
    if (!/genre:\s*GenreFilter\(\)/.test(screen)) {
        err('DiscoverScreen.brs does not pass a raw genre to DiscoverLoaderTask');
    }

    if (!/<field id="genre" type="string"/.test(taskXml) || /<field id="extra"/.test(taskXml)) {
        err('DiscoverLoaderTask.xml must expose a raw genre field and no pre-built extra field');
    }
    if (!/http\.EncodeQueryValue\(m\.top\.genre\)/.test(task)) {
        err('DiscoverLoaderTask.brs must percent-encode the manifest-sourced genre before it becomes a URL segment');
    }

    if (!/for each addon in m\.top\.addons/.test(sourcesTask)) {
        err('CatalogSourcesTask.brs does not walk m.top.addons');
    }
    if (!/catalog\.Manifest\(addon\.address\)/.test(sourcesTask)) {
        err('CatalogSourcesTask.brs never fetches a manifest for add-ons whose registry entry has no catalogs');
    }
    if (!/<script[^>]*CatalogStore\.bs/.test(sourcesXml) || !/<script[^>]*Transport\.bs/.test(sourcesXml)) {
        err('CatalogSourcesTask.xml is missing the Transport/CatalogStore scripts it instantiates');
    }
    if (!/<field id="result" type="assocarray" alwaysNotify="true"\s*\/>/.test(sourcesXml)) {
        err('CatalogSourcesTask.xml result field must be assocarray alwaysNotify');
    }

    if (!host.includes('function AddonsCatalogCapabilities(catalog as dynamic) as object')) {
        err('StoreHost.brs has no AddonsCatalogCapabilities bridge');
    }
    if (!host.includes('function AddonsCatalogTitle(catalog as dynamic, addonName as dynamic) as string')) {
        err('StoreHost.brs has no AddonsCatalogTitle bridge');
    }
    if (!/<function name="AddonsCatalogCapabilities" \/>/.test(hostXml) || !/<function name="AddonsCatalogTitle" \/>/.test(hostXml)) {
        err('StoreHost.xml is missing the AddonsCatalogCapabilities/AddonsCatalogTitle declarations — an undeclared callFunc is a silent no-op returning invalid');
    }

    return ok;
}

// Search queries every installed add-on, not just Cinemeta. The failure mode
// this guards is a silent regression to the built-in single-address search: a
// hardcoded cinemeta id/address, rows keyed by media type instead of catalog
// descriptor, a Details push fed one shared address, or a task that only asks
// the default "top" catalog. It also pins the shared source resolution, the
// per-catalog task loop, and the dynamic rows: only catalogs that return
// results may occupy a row (nothing is premade for loading or empty catalogs).
function checkMultiAddonSearchContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const read = (...p) => fs.readFileSync(path.join(projectRoot, ...p), 'utf8');

    const screen = read('components', 'SearchScreen.brs');
    const screenXml = read('components', 'SearchScreen.xml');
    const task = read('components', 'SearchLoaderTask.brs');
    const taskXml = read('components', 'SearchLoaderTask.xml');
    const store = read('source', 'stores', 'CatalogStore.bs');

    if (/com\.linvo\.cinemeta|cinemetaAddress/.test(screen)) {
        err('SearchScreen.brs still hardcodes the Cinemeta add-on — Search must fan out to every installed search-capable catalog');
    }
    if (/metaType: "movie"|RowForType/.test(screen)) {
        err('SearchScreen.brs still builds rows by media type — Search is one row per search-capable catalog, not grouped by type');
    }

    if (!/AsyncTask_Launch\(m\.top,\s*"CatalogSourcesTask"/.test(screen) || !/onSourcesLoaded/.test(screen)) {
        err('SearchScreen.brs does not resolve sources through CatalogSourcesTask/onSourcesLoaded — sources would never resolve for add-ons the registry has no catalogs for');
    }
    if (!/m\.pendingQuery\s*=/.test(screen) || !/FlushPendingQuery/.test(screen)) {
        err('SearchScreen.brs does not hold a query that arrives before sources land (m.pendingQuery/FlushPendingQuery)');
    }

    if (!/caps = m\.stores\.addons\.callFunc\("AddonsCatalogCapabilities", descriptor\)/.test(screen) || !/not caps\.search then continue for/.test(screen)) {
        err('SearchScreen.brs does not gate rows on AddonsCatalogCapabilities(...).search — every catalog would be queried, including ones that declare no search extra');
    }
    if (!/AddonsCatalogTitle"\s*,\s*descriptor/.test(screen)) {
        err('SearchScreen.brs row titles no longer derive from the catalog descriptor (AddonsCatalogTitle)');
    }
    if (!/"\|"\s*\+\s*descriptor\.type\s*\+\s*"\|"\s*\+\s*descriptor\.id/.test(screen)) {
        err('SearchScreen.brs row keys no longer derive from addonKey|rawType|catalogId — a task result cannot be fanned into its row by key');
    }
    if (!/" - "\s*\+\s*TypeSearchLabel\(descriptor\.type\)/.test(screen)) {
        err('SearchScreen.brs row titles are no longer "{Catalog} - {mediaType}"');
    }
    if (!/return "Tv channel"/.test(screen)) {
        err('SearchScreen.brs does not spell the channel/tv media family "Tv channel" in search rows');
    }
    if (!/titleCounts\[c\.title\]\s*>\s*1/.test(screen)) {
        err('SearchScreen.brs no longer prefixes the add-on name when two catalogs would still collide after the title is built');
    }

    if (/loadState|PlaceholderTitle/.test(screen)) {
        err('SearchScreen.brs still builds placeholder/premade rows — empty or loading catalogs must not occupy a row; rows appear only with results');
    }
    if (!/m\.landed\[/.test(screen) || !/RebuildRows/.test(screen) || !/m\.searchOrder/.test(screen)) {
        err('SearchScreen.brs does not park landed metas by key and rebuild rows from the discovery order (m.landed/RebuildRows/m.searchOrder) — rows cannot be built dynamically from results');
    }

    if (!/addonAddress: target\.addonAddress/.test(screen)) {
        err('SearchScreen.brs onResultSelected does not push the row\'s own addonAddress — every result would open against one shared address');
    }

    if (!/AsyncTask_Launch\(m\.top,\s*"SearchLoaderTask"/.test(screen) || !/m\.searchTasks\[addonKey\] = task/.test(screen)) {
        err('SearchScreen.brs does not spawn one SearchLoaderTask per add-on keyed by addonKey');
    }

    if (!/for each cat in m\.top\.catalogs/.test(task)) {
        err('SearchLoaderTask.brs does not iterate the catalogs array it was handed — it would only ever search one catalog per add-on');
    }
    if (!/catalog\.Search\(m\.top\.addonAddress,\s*cat\.type,\s*m\.top\.query,\s*cat\.id\)/.test(task)) {
        err('SearchLoaderTask.brs does not pass each catalog\'s own id to CatalogStore.Search — every search would hit the default "top" catalog');
    }
    const catches = (task.match(/catch e/g) || []).length;
    if (catches < 2) {
        err('SearchLoaderTask.brs has no per-catalog try/catch — one bad catalog answer would kill the rest of that add-on\'s sections');
    }
    if (!/sections\.Push\(section\)/.test(task)) {
        err('SearchLoaderTask.brs no longer publishes a section per requested catalog');
    }

    if (!/<field id="catalogs" type="array"/.test(taskXml) || !/<field id="addonKey" type="string"/.test(taskXml)) {
        err('SearchLoaderTask.xml is missing the catalogs/addonKey fields the screen passes');
    }
    if (/<field id="metaType"/.test(taskXml)) {
        err('SearchLoaderTask.xml still exposes metaType — the task is per add-on, not per media type');
    }
    if (!/<field id="result" type="assocarray" alwaysNotify="true"\s*\/>/.test(taskXml)) {
        err('SearchLoaderTask.xml result field must be assocarray alwaysNotify — without it a second landing with the same shape is not observed');
    }

    if (!/function Search\(addonAddress as string, metaType as string, query as string, catalogId = "top" as string\)/.test(store)) {
        err('CatalogStore.Search no longer takes a catalogId argument defaulting to "top" — search fan-out cannot target a non-default catalog');
    }

    if (!/type="assocarray" alwaysNotify="true"/.test(screenXml)) {
        err('SearchScreen.xml pushRequest must be assocarray alwaysNotify');
    }

    return ok;
}

function checkPosterScalingContract() {
    const fs = require('fs');
    let ok = true;
    const LEGAL = ['limitSize', 'noScale', 'scaleToFit', 'scaleToFill', 'scaleToZoom'];
    const dir = path.join(projectRoot, 'components');

    for (const name of fs.readdirSync(dir).filter(f => f.endsWith('.xml'))) {
        const xml = fs.readFileSync(path.join(dir, name), 'utf8');
        for (const m of xml.matchAll(/<Poster\b([^>]*)>/g)) {
            const mode = /\bloadDisplayMode="([^"]*)"/.exec(m[1]);
            if (mode && !LEGAL.includes(mode[1])) {
                const id = (/\bid="([^"]*)"/.exec(m[1]) || [, '(anonymous)'])[1];
                console.error(`${name}: Poster "${id}" sets loadDisplayMode="${mode[1]}", which is not one of ${LEGAL.join(' / ')}. An unrecognised scaling option is undefined behaviour, and the Poster docs warn the image may then fail to load outright`);
                ok = false;
            }
        }
    }

    return ok;
}

// BrightScript exposes Left/Right/Mid/Trim/InStr as roString METHOD forms (the
// codebase relies on these, e.g. source/util/SetupPage.brs), but UCase/LCase are
// only GLOBAL functions — roString has no .UCase()/.LCase() member at all.
// DiscoverScreen's and SearchScreen's type-label fallbacks capitalized a declared
// catalog type with `key.Left(1).UCase() + key.Mid(1)`. Every known type
// (movie/series/channels) returned before that line, so it looked correct until an
// add-on declared a custom catalog type ("sports") and the line threw &hf4
// "Member function not found", killing DiscoverScreen on load. Pin the whole
// class: never chain a non-existent method onto a string.
function checkStringMethodContract() {
    const fs = require('fs');
    const path = require('path');
    let ok = true;
    const roots = [path.join(projectRoot, 'components'), path.join(projectRoot, 'source')];
    const bad = /\.\s*(UCase|LCase)\s*\(/i;

    const walk = (dir) => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) { walk(full); continue; }
            if (!/\.(brs|bs)$/.test(entry.name)) continue;
            const src = fs.readFileSync(full, 'utf8');
            const m = bad.exec(src);
            if (m) {
                const line = src.slice(0, m.index).split('\n').length;
                console.error(`${path.relative(projectRoot, full)}:${line} calls .${m[1]}(...) as a string method — roString has no UCase/LCase member; they are global functions, so this throws &hf4 the first time the line runs. Wrap the argument instead: ${m[1]}(value)`);
                ok = false;
            }
        }
    };
    for (const root of roots) walk(root);

    return ok;
}

// The theme migration moved every painted color into theme.reads in init()
// plus script includes, because XML color attributes cannot call code. One
// failure mode would slip past the interpreter: a component calling
// Theme()/AppPalette() without including Theme.bs — a bare-global lookup that
// dies at runtime, not at load. (Hardcoded colors are a style choice, not a
// bug, so they are deliberately not policed here.)
function checkThemeContract() {
    const fs = require('fs');
    const components = fs.readdirSync(path.join(projectRoot, 'components')).filter(f => f.endsWith('.xml'));
    let ok = true;
    for (const name of components) {
        const xml = fs.readFileSync(path.join(projectRoot, 'components', name), 'utf8');
        const brsPath = path.join(projectRoot, 'components', name.replace(/\.xml$/, '.brs'));
        if (fs.existsSync(brsPath)) {
            const brs = fs.readFileSync(brsPath, 'utf8');
            if (/Theme\(|AppPalette\(/.test(brs) && !/Theme\.bs/.test(xml)) {
                console.error(`${name}.xml must include <script uri="pkg:/source/core/Theme.bs"> — its .brs calls Theme()/AppPalette()`);
                ok = false;
            }
        }
    }
    return ok;
}

// The one bug class this repository cannot test its way out of.
//
// m.installed is an roAssociativeArray. "for each" over its keys has NO defined
// order: the brs interpreter yields declaration order, a Roku device yields the
// runtime's own hash order. So code that walks it to build a list — or that
// takes "the first entry that has property X" — produces a DIFFERENT list, and
// makes a DIFFERENT choice, on the device than under `npm test`. Every test in
// this repo passes against the broken version, permanently, because the
// interpreter only has one behaviour to exhibit.
//
// That is not hypothetical here. It shipped: Home's catalog rows came out in a
// different order on the device than in the simulator, and the subtitle
// provider picker asked whichever add-on the hash order happened to yield first
// — a provider the app could not drive, while the working one sat in the same
// registry. Guest sessions hid it because their list opens with the built-in
// seeds, so only the tail moved; a stremio session is hash-ordered end to end.
//
// The lesson belongs in the harness as much as in the code: a green suite is
// NOT evidence about anything that depends on iteration order. Pin order by
// construction — an explicit list, persisted as a JSON array — and pin the
// absence of the old shape here, where the interpreter cannot launder it.
function checkAddonOrderingContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const store = read('source/stores/AddonsStore.bs');
    const player = read('components/PlayerScreen.brs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    // Scan CODE, not prose: these files document the exact bug in their headers,
    // and a raw-text scan would match the documentation describing it.
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const storeCode = code(store);
    const playerCode = code(player);

    // Body of a `function Name(`/`sub Name(` member, found by depth counting so
    // it works for both indented BSL class methods and flat component subs.
    // Indexed by position, NOT lines.indexOf: every `end for` in a method body
    // is a duplicate line, and indexOf would cut the body at the first one.
    const member = (src, name) => {
        const head = new RegExp(`^[ \\t]*(?:private\\s+)?(?:function|sub)\\s+${name}\\s*\\(`, 'm');
        const m = head.exec(src);
        if (!m) return null;
        const lines = src.slice(m.index).split('\n');
        let depth = 0;
        for (let i = 0; i < lines.length; i++) {
            if (/^\s*(?:private\s+)?(?:function|sub)\s/.test(lines[i])) depth++;
            else if (/^\s*end\s+(?:function|sub)\b/.test(lines[i])) {
                depth--;
                if (depth === 0) return code(lines.slice(0, i + 1).join('\n'));
            }
        }
        return null;
    };

    // The body of the `for each` loop whose header is at `from`, matched on
    // indentation so a nested loop does not end it early.
    const loopBody = (src, from) => {
        const lines = src.split('\n');
        const start = src.slice(0, from).split('\n').length - 1;
        const indent = (lines[start].match(/^\s*/) || [''])[0];
        const out = [];
        for (let i = start + 1; i < lines.length; i++) {
            out.push(lines[i]);
            if (new RegExp(`^${indent}end\\s+for\\b`).test(lines[i])) return out.join('\n');
        }
        return out.join('\n');
    };
    // Every `for each` header matching a pattern, with the body of each loop.
    // More than one is normal (GetAll walks m.order twice: once to build a
    // lookup, once to emit), so a check has to say which of them it means.
    //
    // `[ \t]*` and the trailing `$`, never `\s*`: \s matches a newline, so a
    // pattern that can skip lines starts matching on the BLANK line above the
    // header, the captured indent comes out empty, and loopBody then runs to the
    // end of the member and reports pushes that belong to a later loop. That
    // silently disabled two of these checks once already.
    const walks = (src, pattern) => {
        const re = new RegExp(pattern, 'gm');
        const out = [];
        let m;
        while ((m = re.exec(src)) !== null) out.push({ header: m[0], body: loopBody(src, m.index) });
        return out;
    };
    const pushesTo = (w, list) => w.body.split('\n').some(line => new RegExp(`\\b${list}\\.Push\\s*\\(`).test(line));
    const anyPushes = (ws, list) => ws.some(w => pushesTo(w, list));

    // --- the ordered view is the only view ------------------------------------
    const getAll = member(storeCode, 'GetAll');
    if (!getAll) {
        err('AddonsStore has no GetAll — the one ordered view of the registry is gone');
    } else {
        // Every record that reaches the returned list must arrive through one of
        // these four walks, and no walk of the record map may push into the
        // result at all. Asserted per loop rather than as one regex so a push in
        // a later loop cannot be read as belonging to an earlier one.
        const mapWalks = walks(getAll, '^[ \\t]*for\\s+each\\s+\\w+\\s+in\\s+m\\.installed\\b[^\\n]*$');
        if (mapWalks.length === 0) {
            err('AddonsStore.GetAll no longer walks m.installed at all — records with no entry in the order list need somewhere to be collected and sorted');
        } else if (anyPushes(mapWalks, 'list')) {
            err('AddonsStore.GetAll pushes straight out of its m.installed walk again — that walk is roAssociativeArray key order, which is declaration order in the simulator and hash order on a device, so rows reorder and "first match" picks change per platform. Collect them and sort; append via m.order.');
        }
        const builtinWalks = walks(getAll, '^[ \\t]*for\\s+each\\s+\\w+\\s+in\\s+m\\.BuiltinIds\\(\\)[^\\n]*$');
        if (builtinWalks.length === 0) {
            err('AddonsStore.GetAll no longer walks BuiltinIds() — iterating the BuiltIns() associative array is the same undefined-order trap one level up');
        } else if (!anyPushes(builtinWalks, 'list')) {
            err('AddonsStore.GetAll walks BuiltinIds() but never appends what it yields — the built-in seeds would be missing from every ordered view');
        }
        const orderWalks = walks(getAll, '^[ \\t]*for\\s+each\\s+\\w+\\s+in\\s+m\\.order\\b[^\\n]*$');
        if (orderWalks.length === 0) {
            err('AddonsStore.GetAll does not walk the persisted m.order list — with no explicit order, the display order falls back to registry iteration');
        } else if (!anyPushes(orderWalks, 'list')) {
            err('AddonsStore.GetAll walks m.order but never appends what it yields — the explicit order would be computed and then ignored');
        }
        // The map walk has to be FILTERED by whatever the order walks build, or
        // every record counts as a leftover: the ordered pass emits it, then the
        // sorted leftovers emit it again. Caught here because nothing else in
        // the guard notices — the four walks are all still present and correct.
        if (mapWalks.length > 0 && orderWalks.length > 0) {
            const built = new Set();
            for (const w of orderWalks) {
                for (const m of w.body.matchAll(/^[ \t]*(\w+)(?:\[\w+\])?[ \t]*=/gm)) built.add(m[1]);
            }
            const filtered = built.size > 0 && mapWalks.some(w =>
                [...built].some(name => new RegExp(`\\b${name}\\b`).test(w.body)));
            if (!filtered) {
                err('AddonsStore.GetAll walks the record map without filtering it against the set the m.order walk builds — every record would be collected as a leftover and appended twice (ordered pass, then sorted leftovers)');
            }
        }
        // Anything appended outside a loop has no order behind it at all.
        const outside = getAll
            .replace(/^\s*for\s+each[^\n]*\n(?:^[^\n]*\n)*?^\s*end\s+for\b/gm, '')
            .replace(/^\s*(?:private\s+)?(?:function|sub)\s+[^\n]*$/gm, '');
        if (/\blist\.Push\s*\(/.test(outside)) {
            err('AddonsStore.GetAll appends to the result list outside every loop — an un-ordered append can only come from somewhere with no defined position');
        }
        if (!/m\.SortByNameThenId\(/.test(getAll)) {
            err('AddonsStore.GetAll does not sort its leftovers — records with no entry in the order list (a registry written before the order key existed) would land in map order');
        }
    }

    const sortBy = member(storeCode, 'SortByNameThenId');
    if (!sortBy || !/^\s*private\s+sub\s+SortByNameThenId/m.test(store)) {
        err('AddonsStore has no private SortByNameThenId — the leftover sort has to be one the store fully controls, not Sort() or map iteration');
    }
    const sortsAfter = member(storeCode, 'SortsAfter');
    if (!sortsAfter || !/a\.name/.test(sortsAfter) || !/a\.id/.test(sortsAfter)) {
        err('AddonsStore.SortsAfter must compare name AND id — name alone leaves two same-named add-ons in a platform-defined order');
    }

    // --- the order is persisted where it can survive --------------------------
    const orderKey = member(storeCode, 'OrderKey');
    if (!orderKey || !/m\.RegistryKey\(\)\s*\+\s*"_order"/.test(orderKey)) {
        err('AddonsStore.OrderKey must derive from RegistryKey() + "_order" so each session keeps its own order beside its own records');
    }
    if (!/^\s*order\s+as\s+object/m.test(store)) {
        err('AddonsStore has no `order as object` field — there is nowhere for the display order to live');
    }
    const save = member(storeCode, 'Save');
    if (!save || !/m\.registry\.Write\(\s*m\.OrderKey\(\)/.test(save)) {
        err('AddonsStore.Save does not write the order key — a record written without its order reloads with no order at all');
    }
    if (!/m\.registry\.Write\(\s*m\.RegistryKey\(\)/.test(save || '')) {
        err('AddonsStore.Save no longer writes the record map');
    }
    const load = member(storeCode, 'Load');
    if (!load || !/m\.registry\.Read\(\s*m\.OrderKey\(\)/.test(load)) {
        err('AddonsStore.Load does not read the order key — the order would be rebuilt from scratch on every launch');
    }
    // The reason a second key exists at all: FormatJson(m.installed) is a JSON
    // OBJECT, and ParseJson does not preserve object key order, so an order
    // stored there is silently gone by the next relaunch.
    if (/FormatJson\(\s*m\.order\s*\)/.test(storeCode.replace(/m\.registry\.Write\(\s*m\.OrderKey\(\)\s*,\s*FormatJson\(\s*m\.order\s*\)\s*\)/, ''))) {
        err('AddonsStore formats m.order somewhere other than its own array key — a JSON object does not round-trip key order, so the order cannot live in the record map');
    }

    // --- the order is kept truthful on every write ----------------------------
    const register = member(storeCode, 'Register');
    if (!register || !/m\.order\.Push\(\s*record\.id\s*\)/.test(register)) {
        err('AddonsStore.Register does not append the new id to m.order — a record with no order slot is a record the display order has to guess about');
    }
    const uninstall = member(storeCode, 'Uninstall');
    if (!uninstall || !/m\.DropFromOrder\(/.test(uninstall)) {
        err('AddonsStore.Uninstall does not drop the id from m.order — a re-install would inherit a slot it no longer owns');
    }
    const switchSession = member(storeCode, 'SwitchSession');
    if (!switchSession || !/m\.order\s*=\s*\[\]/.test(switchSession)) {
        err('AddonsStore.SwitchSession does not clear m.order — the other session\'s order would leak across the switch');
    }

    // --- provenance is the id, never the record's flag ------------------------
    // The account sync stamps every record it adopts with builtin: false, so on
    // a stremio session the flag is a constant and carries no information. The
    // one picker that consulted it could not tell the working built-in from the
    // providers that answer with nothing.
    const isBuiltin = member(storeCode, 'IsBuiltin');
    if (!isBuiltin || !/m\.BuiltIns\(\)/.test(isBuiltin)) {
        err('AddonsStore.IsBuiltin must resolve through BuiltIns() (by id) — resolving through a record\'s builtin flag is a constant false on every synced add-on');
    }

    // --- the subtitle provider is ranked, and the queue drains ---------------
    if (/FindSubtitlesAddress/.test(playerCode)) {
        err('PlayerScreen still has FindSubtitlesAddress — it returns the first add-on advertising subtitles, and "first" in an unordered registry is a different add-on on every device');
    }
    const ranked = member(playerCode, 'SubtitlesAddresses');
    if (!ranked) {
        err('PlayerScreen has no SubtitlesAddresses — subtitle provider choice is back to depending on registry order');
    } else {
        if (!/AddonsIsBuiltin/.test(ranked)) {
            err('PlayerScreen.SubtitlesAddresses does not consult AddonsIsBuiltin — ranking has to be by id, since a synced record\'s builtin flag is always false');
        }
        if (!/AddonsHasResource/.test(ranked)) {
            err('PlayerScreen.SubtitlesAddresses does not check AddonsHasResource — it would queue providers that cannot serve captions at all');
        }
        if (!/SortAddressesByName\(/.test(ranked)) {
            err('PlayerScreen.SubtitlesAddresses does not sort the non-built-in candidates — the tail is still registry order, so it is still device-dependent');
        }
    }
    // No check here that StoreHost forwards AddonsIsBuiltin: the callFunc
    // contract (forwarder AND the <function> declaration in StoreHost.xml) is
    // owned by checkStoreHandoffContract, which reports both halves. What is
    // specific to this bug — that ranking goes through the id path at all — is
    // the AddonsIsBuiltin consult asserted above.

    // A wrong pick must cost one round trip, not the whole search: that was the
    // difference between "no subtitles at all" and "this provider had none".
    const startSubs = member(playerCode, 'StartSubtitles');
    if (!startSubs || !/SubtitlesAddresses\(/.test(startSubs) || !/LaunchSubtitleFetch\(\)/.test(startSubs)) {
        err('PlayerScreen.StartSubtitles no longer drains a ranked candidate list — one unreachable provider would end the search the way it used to');
    }
    const onResult = member(playerCode, 'onSubtitleResult');
    const more = member(playerCode, 'MoreSubtitleCandidates');
    if (!more || !/m\.subtitleCursor\s*<\s*m\.subtitleCandidates\.Count\(\)/.test(more)) {
        err('PlayerScreen.MoreSubtitleCandidates no longer asks whether the ranked queue has anyone left — the drain has no terminator, so it either stops at the first provider or never stops');
    }
    if (!onResult || !/MoreSubtitleCandidates\(\)[\s\S]{0,120}?LaunchSubtitleFetch\(\)/.test(onResult)) {
        err('PlayerScreen.onSubtitleResult no longer falls through to the next candidate when a provider returns nothing — picking a provider that cannot answer is back to meaning "no subtitles"');
    }
    // A later provider coming back empty must not discard captions an earlier
    // one already contributed. Under a merge this is the difference between
    // "this add-on had nothing" and "the player lost its subtitles".
    if (onResult) {
        const emptyBranch = onResult.slice(onResult.indexOf('result.subtitles.Count() = 0'));
        const clearAt = emptyBranch.search(/ClearSubtitles\(\)/);
        if (clearAt !== -1) {
            const guard = emptyBranch.slice(0, clearAt);
            if (!/m\.subtitleTracks\s*=\s*invalid\s+or\s+m\.subtitleTracks\.Count\(\)\s*=\s*0/.test(guard)) {
                err('PlayerScreen.onSubtitleResult clears the subtitle list when a LATER provider returns nothing, discarding tracks an earlier provider already merged — under a merge, one flaky add-on would blank captions the user can already see');
            }
        }
    }
    const cancel = member(playerCode, 'CancelSubtitles');
    if (!cancel || !/m\.subtitleCandidates\s*=\s*\[\]/.test(cancel)) {
        err('PlayerScreen.CancelSubtitles does not drop the candidate queue — leaving the player would leave a stale provider queue to walk on the next play');
    }

    // --- an unusable track list never reaches the live content node ---------
    // BuildSubtitleTracks drops entries without a URL, so a non-empty raw list
    // can build to nothing. Writing that empty list onto a playing video blanks
    // its caption state mid-playback. A provider result must also preserve
    // the user's global Roku caption preference.
    const apply = member(playerCode, 'ApplySubtitleIndex');
    if (!apply) {
        err('PlayerScreen has no ApplySubtitleIndex');
    } else {
        // Scoped to AFTER the raw-empty guard: writing an empty array there is
        // the documented reset, not the defect. The defect is building the track
        // list after the content node has already been written.
        const rawGuard = apply.indexOf('m.subtitleTracks = invalid');
        if (rawGuard === -1) {
            err('PlayerScreen.ApplySubtitleIndex no longer has the raw-empty-track-list guard');
        } else {
            const guardEnd = apply.indexOf('end if', rawGuard);
            const after = guardEnd === -1 ? apply.slice(rawGuard) : apply.slice(guardEnd);
            const build = after.indexOf('BuildSubtitleTracks()');
            const write = after.indexOf('content.subtitleTracks');
            if (build === -1 || write === -1 || build > write) {
                err('PlayerScreen.ApplySubtitleIndex writes content.subtitleTracks before building the tracks — an empty result still lands on the live content node');
            }
        }
        if (!/tracks\.Count\(\)\s*=\s*0[\s\S]{0,200}?return/.test(apply)) {
            err('PlayerScreen.ApplySubtitleIndex has no empty-tracks bail-out — a provider can return entries that all fail to resolve to a URL');
        }
        if (!/if selected = ""/.test(apply)) {
            err('PlayerScreen.ApplySubtitleIndex must confirm a usable default track before selecting it');
        }
        if (/globalCaptionMode\s*=|SetCaptionMode\(/i.test(playerCode)) {
            err('PlayerScreen must preserve the global Roku caption preference; provider results must not enable or disable captions');
        }
    }

    return ok;
}

// The player used to wedge — app-wide, unrecoverable without killing the
// channel — and the cause was not media, not the stream, and not the server.
//
// The player publishes its position from INSIDE the Video node's "state"
// observer: pausing reports "paused", leaving reports through SavePosition.
// That write woke MainScene's onWatchStateUpdate, which built a
// push worker inline — CreateObject + AppendChild + control = "RUN" —
// on the render thread, underneath a Video node that was mid-transition into the
// OS's own pause screen. The SceneGraph stopped servicing input and never
// recovered. Back froze it, pause froze it, and the three separate theories
// offered for it (a hung stream server, the pendingStop teardown lockout, a
// leaked duplicate player) were all wrong; the same stream from the same server
// played fine, and it never happened in a guest session — because a guest
// session returns at the AuthGetSession gate before the launch, and only a
// stremio session got far enough to wedge.
//
// The invariant is not "be careful here", it is structural: the handler that a
// Video state observer feeds must not build a node. Pin it.
function checkWatchStatePushContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const main = read('components/MainScene.brs');
    const xml = read('components/MainScene.xml');
    const player = read('components/PlayerScreen.brs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const brs = code(main);
    const body = (name) => {
        const m = new RegExp(`^(?:sub|function) ${name}\\(\\)`, 'm').exec(brs);
        if (!m) return '';
        const lines = brs.slice(m.index).split('\n');
        for (let i = 0; i < lines.length; i++) {
            if (i > 0 && /^end (?:sub|function)\b/.test(lines[i])) return lines.slice(0, i + 1).join('\n');
        }
        return brs.slice(m.index);
    };

    // 1. The handler that the player's Video observer feeds must not build a
    //    node. This is the whole defect.
    const handler = body('onWatchStateUpdate');
    if (!handler) {
        err('MainScene.brs has no onWatchStateUpdate — the watch-state write-back has no entry point');
    } else {
        if (/AsyncTask_Launch\s*\(/.test(handler)) {
            err('MainScene.brs onWatchStateUpdate launches the push worker itself — this handler runs inside the player\'s Video "state" observer, and creating a node on that stack is what froze playback. Go through ScheduleWatchStatePush.');
        }
        if (/CreateObject\s*\(/.test(handler)) {
            err('MainScene.brs onWatchStateUpdate calls CreateObject — nothing on the Video state observer\'s stack may build a node');
        }
        if (!/ScheduleWatchStatePush\(\)/.test(handler)) {
            err('MainScene.brs onWatchStateUpdate does not defer through ScheduleWatchStatePush — the push would start on the Video state observer\'s stack');
        }
        // The gate that made this stremio-only, and the reason "works in guest"
        // proved nothing about it. Matched as a callFunc ARGUMENT — "AuthGet"
        // followed by a closing paren is a direct call, and this is a string
        // inside one.
        if (!/callFunc\(\s*"AuthGetSession"\s*\)\s*<>\s*"stremio"/.test(handler)) {
            err('MainScene.brs onWatchStateUpdate lost its stremio-session gate — a guest session would now do the write-back this bug lived in');
        }
    }

    // 2. The deferral has to be real: a one-shot timer, actually observed, and
    //    actually restarted per publish (a burst of pause/seek reports must not
    //    launch a worker per report).
    const schedule = body('ScheduleWatchStatePush');
    if (!schedule) {
        err('MainScene.brs has no ScheduleWatchStatePush — the deferral the player fix depends on is gone');
    } else {
        if (!/m\.watchStatePump\.control\s*=\s*"stop"[\s\S]{0,120}?m\.watchStatePump\.control\s*=\s*"start"/.test(schedule)) {
            err('MainScene.brs ScheduleWatchStatePush does not (re)start the one-shot pump timer — a timer that is never restarted pushes nothing, silently dropping every watch state');
        }
        if (!/m\.watchStatePump\s*=\s*invalid[\s\S]{0,200}?PumpLibraryWrites\(\)/.test(schedule)) {
            err('MainScene.brs ScheduleWatchStatePush has no inline fallback when the timer is missing — a wiring mistake would drop the user\'s watch state instead of pushing it');
        }
    }
    if (!/PumpLibraryWrites\(\)/.test(body('onWatchStatePumpFire') || '')) {
        err('MainScene.brs onWatchStatePumpFire does not pump — the deferral would resolve to nothing');
    }
    if (!/m\.watchStatePump\.ObserveField\(\s*"fire"\s*,\s*"onWatchStatePumpFire"\s*\)/.test(brs)) {
        err('MainScene.brs never observes the watchStatePump timer\'s fire field — the deferred push would never run');
    }
    if (!/<Timer\s+id="watchStatePump"[^>]*duration="1"/.test(xml)) {
        err('MainScene.xml has no <Timer id="watchStatePump" duration="1" ... /> — a FindNode miss means the deferral silently degrades to the inline push that froze the player');
    }
    if (!/<Timer\s+id="watchStatePump"[^>]*repeat="false"/.test(xml)) {
        err('MainScene.xml watchStatePump must be repeat="false" — a repeating one-shot pump would re-run forever and keep launching workers');
    }

    // 3. The deferred pump must carry the packet across the gap on state THIS
    //    scene owns, never on the player node: by the time a deferred pump
    //    runs, a Back-out may already have popped and destroyed the player.
    if (!/callFunc\(\s*"WatchLatest"\s*\)/.test(handler)) {
        err('MainScene.brs onWatchStateUpdate no longer reads the packet out of the shared watch buffer via WatchLatest() — the whole point of the buffer is that it outlives the player node that published it');
    }
    if (!/NextLibraryWrite\(\)/.test(body('PumpLibraryWrites') || '')) {
        err('MainScene.brs PumpLibraryWrites does not drain the pending edits through NextLibraryWrite — the three write-back kinds would have no single build path');
    }
    if (!/packet\s*=\s*m\.pendingWatchState\b/.test(body('NextLibraryWrite') || '')) {
        err('MainScene.brs NextLibraryWrite no longer takes its packet from m.pendingWatchState — a deferred pump cannot re-read the player node, it can only use the slot the handler left it');
    }

    // 4. The publisher itself must stay trivial. It runs on the Video observer's
    //    stack, so every line of it is a candidate for the same wedge.
    const publish = /sub PublishWatchState\(\)[\s\S]*?\nend sub/.exec(code(player));
    if (!publish) {
        err('PlayerScreen.brs has no PublishWatchState');
    } else {
        for (const forbidden of ['CreateObject', 'AppendChild', 'AsyncTask_Launch', 'Wait(']) {
            if (new RegExp(`\\b${forbidden.replace('(', '\\(')}`).test(publish[0])) {
                err(`PlayerScreen.brs PublishWatchState calls ${forbidden} — it runs inside the Video "state" observer, where anything but a local field write is what froze the player`);
            }
        }
        if (!/m\.top\.watchStateUpdate\s*=/.test(publish[0])) {
            err('PlayerScreen.brs PublishWatchState no longer publishes through the watchStateUpdate field — MainScene\'s deferred pump is fed by that write');
        }
    }

    return ok;
}

function checkScreensHidden() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.xml'), 'utf8');
    let ok = true;
    // Every screen the stack can show must exist as a child of the Scene. The
    // two custom dialogs are deliberately NOT here: they are built with
    // CreateObject (a dialog declared in markup dims the background and paints
    // nothing — see checkMainSceneContract), so there is nothing to expect.
    for (const name of ['HomeScreen', 'DetailsScreen', 'EpisodesScreen', 'StreamsScreen', 'SettingsScreen', 'AddonsScreen', 'SearchScreen', 'DiscoverScreen', 'LibraryScreen', 'AuthScreen', 'LinkStremioScreen']) {
        const element = xml.match(new RegExp(`<${name}[^>]*>`));
        if (!element) {
            console.error(`MainScene.xml is missing a <${name} ... /> child`);
            ok = false;
        }
    }
    return ok;
}

async function main() {
    const builder = new ProgramBuilder();
    await builder.run({
        project: null,
        rootDir: projectRoot,
        files: ['source/**/*.bs', 'source/**/*.brs', 'bslib'],
        stagingDir,
        createPackage: false,
        copyToStaging: true,
        deploy: false,
        emitDefinitions: false,
        showDiagnosticsInConsole: true
    });

    const failedDiagnostics = builder.getDiagnostics().filter(d => d.severity === 1);
    if (failedDiagnostics.length > 0) {
        console.error(`Transpile stopped with ${failedDiagnostics.length} error diagnostic(s).`);
        process.exit(1);
    }

    // callFunc only invokes functions declared in a component's interface, and
    // the suite mocks callFunc, so a missing declaration would pass tests but
    // silently no-op on device. Guard the contract here.
    if (!checkDeferredVideoPlayContract() || !checkScreenRuntimeHazards() || !checkScreenContract() || !checkScreensHidden() || !checkTileContract() || !checkPosterStatusContract() || !checkPosterFallbackContract() || !checkNoDuplicateScripts() || !checkStoreHandoffContract() || !checkLibraryCodecContract() || !checkMainSceneContract() || !checkSessionAuthorityContract() || !checkStremioProvisioningContract() || !checkAddonOrderingContract() || !checkAddonSyncTaskContract() || !checkStreamResolveTaskContract() || !checkEngineWarmupContract() || !checkTransportRetryContract() || !checkStaggeredSyncContract() || !checkNetDiagContract() || !checkHomeCatalogStalenessContract() || !checkTaskTeardownContract() || !checkSubtitleMergeContract() || !checkWatchStatePushContract() || !checkHomeScreenContract() || !checkFilterBarContract() || !checkLibraryScreenContract() || !checkLibraryPutTaskContract() || !checkLogoutTaskContract() || !checkSettingsPushContract() || !checkThemeContract() || !checkPosterScalingContract() || !checkPosterLoadSizePolicy() || !checkCompanionQrContract() || !checkSetupServerContract() || !checkDetailsMetaTypeContract() || !checkStreamFormatQueryContract() || !checkChannelCwPolicyContract() || !checkStreamTypeGateContract() || !checkDiscoverSourcesContract() || !checkMultiAddonSearchContract() || !checkStringMethodContract() || !checkMetaFieldCoercionContract()) {
        process.exit(1);
    }

    await writeCombinedScript();

    const result = spawnSync(
        process.execPath,
        [
            path.join(projectRoot, 'node_modules', '@rokucommunity', 'brs', 'bin', 'cli.js'),
            '--root', stagingDir,
            ...transpiled,
            combinedPath
        ],
        { cwd: stagingDir, stdio: 'inherit' }
    );
    process.exit(result.status === null ? 1 : result.status);
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});
