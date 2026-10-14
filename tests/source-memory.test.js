// Pure policy tests. The brs interpreter lacks roEVPDigest; the digest seam
// supplies Node SHA-256 for a finite set of expected, length-prefixed identities.
// Native roEVPDigest/UTC-time behavior must additionally be checked on Roku.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const root = path.resolve(__dirname, '..');
const hash = value => crypto.createHash('sha256').update(value, 'utf8').digest('hex');
const quote = value => '"' + value.replace(/"/g, '""') + '"';
const canonical = (video, mode, provider, host, kind, file) =>
    'source-memory-v1:' + [video, mode, provider, host, kind, file]
        .map(part => `${part.length}:${part}`).join('');
const digests = new Map();
const add = (...parts) => {
    const identity = canonical(...parts);
    const key = hash(identity);
    digests.set(identity, key);
    return key;
};
const base = ['tt100001', 'projector', 'addon.public|addon.example', 'cdn.example', 'mkv'];
const keyA = add(...base, 'file:A.2160p.mkv');
const keyB = add(...base, 'file:B.1080p.mkv');
const keyC = add(...base, 'file:C.1080p.mkv');
const keyD = add(...base, 'file:D.2160p.mkv');
const keyE = add(...base, 'file:E.1080p.mkv');
const keyLower = add(...base, 'file:a.2160p.mkv');
const keySurround = add('tt100001', 'surround', ...base.slice(2), 'file:A.2160p.mkv');
const keyEpisode1 = add('tt100001:1:1', ...base.slice(1), 'file:A.2160p.mkv');
const keyEpisode2 = add('tt100001:1:2', ...base.slice(1), 'file:A.2160p.mkv');
const keyProvider2 = add('tt100001', 'projector', 'addon.other|addon.example', 'cdn.example', 'mkv', 'file:A.2160p.mkv');
const keyHost2 = add('tt100001', 'projector', 'addon.public|addon.example', 'other-cdn.example', 'mkv', 'file:A.2160p.mkv');
const keyMp4 = add(...base.slice(0, 4), 'mp4', 'file:A.2160p.mkv');
const keySized = add(...base, 'file:A.2160p.mkv:size:999');
const torrentHash = '0123456789abcdef0123456789abcdef01234567';
const keyHash0 = add(...base, `hash:${torrentHash}:0`);
const keyHash1 = add(...base, `hash:${torrentHash}:1`);
const keyHls = add(...base.slice(0, 4), 'hls', 'file:A.m3u8');
const keyDeliveredHls = add(...base.slice(0, 4), 'hls', 'file:A.2160p.mkv');
const keyDeliveredDash = add(...base.slice(0, 4), 'dash', 'file:A.2160p.mkv');
const keyIpv6 = add(...base.slice(0, 3), '[2001:db8::1]', 'mkv', 'file:A.2160p.mkv');
const boundKeys = Array.from({ length: 40 }, (_, i) => hash('source-memory-bound-slot-' + i));

let code = [
    fs.readFileSync(path.join(root, 'tests/harness.brs'), 'utf8'),
    fs.readFileSync(path.join(root, 'tests/mocks.brs'), 'utf8'),
    fs.readFileSync(path.join(root, 'source/util/SourceMemory.brs'), 'utf8'),
    `m.sourceMemoryDigests = [${[...digests].map(([text, key]) => `{text:${quote(text)},key:${quote(key)}}`).join(',')}]`,
    `function TestSourceDigest(value as string) as string
        for each fixture in m.sourceMemoryDigests
            if fixture.text = value then return fixture.key
        end for
        return ""
    end function
    function TestBadDigest(value as string) as string
        return value
    end function
    function TestSource(filename as string, name as string) as object
        return {url:"https://cdn.example/config-fixture-secret/file?token=fixture-secret-DO-NOT-SAVE",name:name,behaviorHints:{filename:filename},sourceMemoryProvider:"addon.public|addon.example"}
    end function
    now = 1760000000#
    a = TestSource("A.2160p.mkv","A")
    b = TestSource("B.1080p.mkv","B")
    c = TestSource("C.1080p.mkv","C")
    d = TestSource("D.2160p.mkv","D")
    e = TestSource("E.1080p.mkv","E")
    keyA = ${quote(keyA)}
    keyB = ${quote(keyB)}
    keyC = ${quote(keyC)}
    keyD = ${quote(keyD)}
    keyE = ${quote(keyE)}
    Harness_Suite("Source memory fingerprints exclude signed credentials and isolate files")
    Harness_Equal(SourceMemory_Fingerprint(a,"tt100001","projector","",TestSourceDigest),keyA,"length-prefixed SHA-256 identity matches expected schema")
    rotated = TestSource("A.2160p.mkv","A")
    rotated.url = "HTTPS://CDN.EXAMPLE.:443/brand-new-path?signature=new-secret#fragment-secret"
    Harness_Equal(SourceMemory_Fingerprint(rotated,"tt100001","projector","",TestSourceDigest),keyA,"rotated signed URL does not change file identity")
    Harness_Equal(SourceMemory_Hostname(rotated.url),"cdn.example","hostname normalization removes standard port and terminal dot")
    Harness_Equal(SourceMemory_Fingerprint(a,"tt100001","surround","",TestSourceDigest),${quote(keySurround)},"surround audio policy has separate outcomes")
    Harness_Equal(SourceMemory_Fingerprint(a,"tt100001:1:1","projector","",TestSourceDigest),${quote(keyEpisode1)},"episode one is independently scoped")
    Harness_Equal(SourceMemory_Fingerprint(a,"tt100001:1:2","projector","",TestSourceDigest),${quote(keyEpisode2)},"episode two is independently scoped")
    Harness_Equal(SourceMemory_Fingerprint(a,"tt100001","projector","addon.other|addon.example",TestSourceDigest),${quote(keyProvider2)},"providers on the same CDN stay isolated")
    host2 = TestSource("A.2160p.mkv","A")
    host2.url = "https://other-cdn.example/file?token=fixture-secret"
    Harness_Equal(SourceMemory_Fingerprint(host2,"tt100001","projector","",TestSourceDigest),${quote(keyHost2)},"different origin hosts stay isolated")
    lower = TestSource("a.2160p.mkv","lower")
    Harness_Equal(SourceMemory_Fingerprint(lower,"tt100001","projector","",TestSourceDigest),${quote(keyLower)},"file identity stays case-sensitive")
    mp4 = TestSource("A.2160p.mkv","mp4")
    mp4.streamFormat = "mp4"
    Harness_Equal(SourceMemory_Fingerprint(mp4,"tt100001","projector","",TestSourceDigest),${quote(keyMp4)},"declared file format is part of identity")
    sized = TestSource("A.2160p.mkv","size")
    sized.behaviorHints.videoSize = 999
    Harness_Equal(SourceMemory_Fingerprint(sized,"tt100001","projector","",TestSourceDigest),${quote(keySized)},"changed file size invalidates stale metadata outcome")
    torrent0 = TestSource("A.2160p.mkv","torrent")
    torrent0.infoHash = UCase(${quote(torrentHash)})
    torrent0.fileIdx = 0
    Harness_Equal(SourceMemory_Fingerprint(torrent0,"tt100001","projector","",TestSourceDigest),${quote(keyHash0)},"valid hash and exact index identify content independent of filename")
    torrent0.fileIdx = 1
    Harness_Equal(SourceMemory_Fingerprint(torrent0,"tt100001","projector","",TestSourceDigest),${quote(keyHash1)},"distinct files within one torrent remain distinct")
    hls = TestSource("A.m3u8","HLS")
    Harness_Equal(SourceMemory_Fingerprint(hls,"tt100001","projector","",TestSourceDigest),${quote(keyHls)},"manifest extension is normalized to HLS type")
    deliveredHls = TestSource("A.2160p.mkv","HLS delivery")
    deliveredHls.streamFormat = "mkv"
    deliveredHls.url = "https://cdn.example/private-path/main.m3u8?token=fixture-secret"
    Harness_Equal(SourceMemory_Fingerprint(deliveredHls,"tt100001","projector","",TestSourceDigest),${quote(keyDeliveredHls)},"actual HLS endpoint separates delivery from old filename codec failure")
    deliveredHls.url = "https://cdn.example/private-path/main.mpd?token=fixture-secret"
    Harness_Equal(SourceMemory_Fingerprint(deliveredHls,"tt100001","projector","",TestSourceDigest),${quote(keyDeliveredDash)},"actual DASH endpoint is only a canonical type, not stored path")
    ipv6 = TestSource("A.2160p.mkv","ipv6")
    ipv6.url = "https://[2001:DB8::1]:443/file?token=fixture-secret"
    Harness_Equal(SourceMemory_Fingerprint(ipv6,"tt100001","projector","",TestSourceDigest),${quote(keyIpv6)},"IPv6 authorities are supported without storing URL")
    unnamed = {url:"https://cdn.example/private-path?token=fixture-secret",name:"looks like filename.mkv"}
    Harness_Equal(SourceMemory_Fingerprint(unnamed,"tt100001","projector","",TestSourceDigest),"","a displayed release title or signed path is not a reliable identity")
    Harness_Equal(SourceMemory_Fingerprint(a,"tt100001","projector","https://addon.example/private-config?key=fixture-secret",TestSourceDigest),"","configured secret-bearing provider URL is refused")
    Harness_Equal(SourceMemory_Fingerprint(a,"tt100001","obsolete","",TestSourceDigest),"","unknown audio policy cannot reuse outcomes")
    Harness_Equal(SourceMemory_Fingerprint(a,"","projector","",TestSourceDigest),"","blank video cannot merge unrelated titles")
    Harness_Equal(SourceMemory_Fingerprint(a,"tt100001","projector","",TestBadDigest),"","digest seam cannot persist clear identity")
    Harness_Equal(SourceMemory_Hostname("https://user:password@cdn.example/file"),"","credential userinfo rejected")
    Harness_Equal(SourceMemory_Hostname("https://cdn.example:bad/file"),"","malformed port has no fingerprint")
    Harness_Equal(SourceMemory_Hostname("https://cdn.example/file with spaces"),"","whitespace URL has no fingerprint")
    Harness_Equal(SourceMemory_Hostname("http://cdn.example/file"),"","unencrypted source has no persistent identity")

    Harness_Suite("Policy version two preserves legacy verified files without stale audio rejections")
    legacy = {version:1,entries:[
        {key:keyD,outcome:"working",touched:now-100,expires:now+12000},
        {key:keyD,outcome:"network",touched:now-50,expires:now+300},
        {key:keyB,outcome:"incompatible",touched:now-40,expires:now+2000},
        {key:keyA,outcome:"network",touched:now-30,expires:now+200},
        {key:keyE,outcome:"working",touched:now-1000,expires:now},
        {key:keyC,outcome:"working",touched:now+1,expires:now+2000}
    ]}
    migrated = SourceMemory_Normalize(legacy,now)
    Harness_Equal(SourceMemory_Empty().version,2,"new memory uses the revised audio policy version")
    Harness_Equal(SourceMemory_RegistryKey(),"sourceMemoryV1","policy migration keeps the existing registry location")
    Harness_Equal(migrated.version,2,"valid legacy data becomes the current schema in memory")
    Harness_Equal(migrated.entries.Count(),1,"only a live valid legacy success survives migration")
    Harness_Equal(migrated.entries[0].key,keyD,"verified file fingerprint is unchanged by policy migration")
    Harness_Equal(migrated.entries[0].expires,now+12000,"migration does not refresh a legacy success expiry")
    Harness_Equal(SourceMemory_Outcome(migrated,keyD),"working","a newer legacy network mark cannot suppress the older proven success")
    Harness_Equal(SourceMemory_Outcome(migrated,keyB),"","legacy incompatibility no longer excludes newly eligible native audio")
    Harness_Equal(SourceMemory_Outcome(migrated,keyA),"","legacy temporary failures do not bias the revised policy")
    Harness_Equal(legacy.version,1,"migration leaves the caller's legacy snapshot unchanged")
    Harness_Equal(legacy.entries.Count(),6,"migration does not mutate the caller's outcome list")
    legacyOrder = SourceMemory_Order([a,b,c,d,e],legacy,"tt100001","projector",now,TestSourceDigest)
    Harness_Equal(legacyOrder.Count(),5,"old incompatibility and network marks keep all fresh files eligible")
    Harness_Equal(legacyOrder[0].name,"D","legacy verified success remains the fastest replay candidate")
    Harness_Equal(legacyOrder[1].name,"A","old network source returns to its original unknown rank")
    Harness_Equal(legacyOrder[2].name,"B","old incompatible source returns to its original unknown rank")
    current = {version:2,entries:legacy.entries}
    current = SourceMemory_Normalize(current,now)
    Harness_Equal(current.entries.Count(),3,"current policy still accepts valid working, incompatible and network outcomes")
    Harness_Equal(SourceMemory_Outcome(current,keyD),"network","newer version-two failure supersedes same-file success normally")
    Harness_Equal(SourceMemory_Outcome(current,keyB),"incompatible","new policy's complete incompatibility facts remain excluded")
    Harness_Equal(SourceMemory_Outcome(current,keyA),"network","new policy's short-lived delivery failure remains deprioritized")
    currentOrder = SourceMemory_Order([a,b,c,d,e],current,"tt100001","projector",now,TestSourceDigest)
    Harness_Equal(currentOrder.Count(),4,"version-two incompatibility retains the ordinary exclusion behavior")
    Harness_Equal(currentOrder[0].name,"C","version-two temporary failures still follow unknown sources")
    Harness_Equal(currentOrder[2].name,"A","version-two temporary failure stays eligible")
    upgraded = SourceMemory_Record(legacy,keyB,"incompatible",now)
    Harness_Equal(upgraded.version,2,"new outcomes after legacy migration use current policy")
    Harness_Equal(SourceMemory_Outcome(upgraded,keyD),"working","recording new policy data retains legacy proof of playback")
    Harness_Equal(SourceMemory_Outcome(upgraded,keyB),"incompatible","new policy rejection survives rather than being mistaken for a legacy mark")
    for each version in [invalid,"1","2",0,3,2.5,true]
        rejected = SourceMemory_Normalize({version:version,entries:legacy.entries},now)
        Harness_Equal(rejected.entries.Count(),0,"missing, wrong-type or unsupported policy version cannot carry outcomes")
        Harness_Equal(rejected.version,2,"invalid policy version returns an empty current schema")
    end for
    migrationRegistry = MockRegistry()
    migrationRegistry.Write(SourceMemory_RegistryKey(),FormatJson(legacy))
    loadedLegacy = SourceMemory_Load(migrationRegistry,now)
    Harness_Equal(loadedLegacy.entries.Count(),1,"reading old registry data applies the migration before source selection")
    Harness_Equal(loadedLegacy.version,2,"registry load exposes current policy without a device migration write")
    Harness_Equal(ParseJson(migrationRegistry.Read(SourceMemory_RegistryKey())).version,1,"read-only migration does not rewrite the saved snapshot")
    Harness_Ok(SourceMemory_Save(migrationRegistry,legacy,now),"later normal runtime save serializes migrated data")
    savedMigration = ParseJson(migrationRegistry.Read(SourceMemory_RegistryKey()))
    Harness_Equal(savedMigration.version,2,"ordinary save persists the revised policy version at the same key")
    Harness_Equal(savedMigration.entries.Count(),1,"ordinary save cannot reintroduce discarded legacy negatives")
    Harness_Equal(savedMigration.entries[0].key,keyD,"saved migration preserves the verified fingerprint")

    Harness_Suite("Source memory orders working and unknown candidates without discarding temporary failures")
    memory = SourceMemory_Empty()
    memory = SourceMemory_Record(memory,keyD,"working",now)
    memory = SourceMemory_Record(memory,keyB,"incompatible",now)
    memory = SourceMemory_Record(memory,keyA,"network",now)
    ordered = SourceMemory_Order([a,b,c,d,e,unnamed],memory,"tt100001","projector",now,TestSourceDigest)
    Harness_Equal(ordered.Count(),5,"only completed incompatible file is excluded from automatic candidates")
    Harness_Equal(ordered[0].name,"D","known working candidate moves before quality-ranked unknowns")
    Harness_Equal(ordered[1].name,"C","first unknown retains relative rank")
    Harness_Equal(ordered[2].name,"E","second unknown retains relative rank")
    Harness_Equal(ordered[3].name,"looks like filename.mkv","source with no fingerprint remains usable")
    Harness_Equal(ordered[4].name,"A","recent network failure stays eligible at end")
    Harness_Equal(SourceMemory_Order([a,b,c,d,e],memory,"tt100001","surround",now,TestSourceDigest).Count(),5,"projector rejections never affect surround selection")
    Harness_Equal(SourceMemory_Order([a,b,c,d,e],memory,"tt100001:1:1","projector",now,TestSourceDigest).Count(),5,"movie outcomes never affect episode")
    old = SourceMemory_Order([a,b,c,d,e],memory,"tt100001","projector",now+600,TestSourceDigest)
    Harness_Equal(old[1].name,"A","network failure returns to ordinary rank exactly at expiry")
    allExpired = SourceMemory_Order([a,b,c,d,e],memory,"tt100001","projector",now+1209600,TestSourceDigest)
    Harness_Equal(allExpired.Count(),5,"working and incompatibility TTLs eventually allow all new attempts")
    Harness_Equal(allExpired[0].name,"A","expired memory preserves original rank")
    permanentExpired = SourceMemory_Order([a,b,c,d,e],memory,"tt100001","projector",now+604800,TestSourceDigest)
    Harness_Equal(permanentExpired.Count(),5,"known incompatible exclusion ends at seven-day expiry")
    Harness_Equal(permanentExpired[0].name,"D","working memory survives incompatible TTL")
    Harness_Equal(SourceMemory_Order([a,b],memory,"tt100001","projector",invalid,TestSourceDigest).Count(),2,"unavailable clock fails open")

    Harness_Suite("Source memory replaces failure after verified success")
    memory = SourceMemory_Record(memory,keyB,"working",now+1)
    Harness_Equal(memory.entries.Count(),3,"success replaces the same-key failure without duplicate record")
    Harness_Equal(SourceMemory_Outcome(memory,keyB),"working","new native success overrides previous incompatibility")
    ordered = SourceMemory_Order([a,b,c,d],memory,"tt100001","projector",now+1,TestSourceDigest)
    Harness_Equal(ordered[0].name,"B","replacement success is immediately usable")
    Harness_Equal(ordered[1].name,"D","working candidates retain provider rank relative to one another")
    Harness_Equal(SourceMemory_Record(memory,keyB,"untrusted-native-error",now+2).entries.Count(),3,"unknown outcome enum cannot become a permanent exclusion")
    Harness_Equal(SourceMemory_Record(memory,"plain-secret-key","working",now+2).entries.Count(),3,"a raw identifier cannot enter records")
    Harness_Equal(SourceMemory_Record(memory,keyE,"network",now+2).entries[0].expires,now+602,"temporary failure has bounded expiry")

    Harness_Suite("Source memory sanitation limits storage and rejects corrupted outcomes")
    poisoned = {version:2,entries:[
        {key:keyA,outcome:"working",touched:now-100,expires:now+999999999,url:"fixture-secret",filename:"A.2160p.mkv",token:"fixture-secret"},
        {key:keyA,outcome:"network",touched:now-200,expires:now+300},
        {key:keyB,outcome:"incompatible",touched:now+1,expires:now+2000},
        {key:keyC,outcome:"incompatible",touched:now-10,expires:now},
        {key:"fixture-secret",outcome:"working",touched:now-10,expires:now+100},
        {key:keyD,outcome:"anything",touched:now-10,expires:now+100},
        {key:keyE,outcome:"network",touched:"not-time",expires:now+100}
    ],privateURL:"fixture-secret"}
    clean = SourceMemory_Normalize(poisoned,now)
    Harness_Equal(clean.entries.Count(),1,"future, expired, unknown and malformed records are dropped; duplicate newest wins")
    Harness_Equal(clean.entries[0].expires,now-100+1209600,"stored expiry cannot extend trusted maximum TTL")
    Harness_Equal(clean.entries[0].Count(),4,"entry whitelist contains only key, outcome and timestamps")
    Harness_Equal(clean.Count(),2,"root whitelist contains only version and entries")
    Harness_Equal(SourceMemory_Normalize({version:3,entries:poisoned.entries},now).entries.Count(),0,"unrecognized schema safely disables memory")
    Harness_Equal(SourceMemory_Normalize(memory,now-500).entries.Count(),0,"clock rollback cannot create an effectively permanent ban")
    bounded = SourceMemory_Empty()
    keys = [${boundKeys.map(quote).join(',')}]
    for i = 0 to keys.Count()-1
        bounded = SourceMemory_Record(bounded,keys[i],"working",now+i)
    end for
    Harness_Equal(bounded.entries.Count(),SourceMemory_MaxEntries(),"entry count remains bounded across many new files")
    Harness_Equal(bounded.entries[0].key,keys[39],"latest file outcome is retained")
    Harness_Equal(SourceMemory_Outcome(bounded,keys[0]),"","oldest file outcome is evicted")
    Harness_Equal(SourceMemory_Outcome(bounded,keys[8]),"working","newest 32 outcomes remain")

    Harness_Suite("Source memory protects proven replay files from an incompatible-title flood")
    replay = SourceMemory_Record(SourceMemory_Empty(),keyA,"working",now)
    for i = 0 to keys.Count()-1
        replay = SourceMemory_Record(replay,keys[i],"incompatible",now+100+i)
    end for
    Harness_Equal(replay.entries.Count(),32,"success reserve still obeys total 32-entry cap")
    Harness_Equal(SourceMemory_Outcome(replay,keyA),"working","older verified source survives more than 32 incompatible files")
    Harness_Equal(SourceMemory_Outcome(replay,keys[39]),"incompatible","latest incompatible fact is retained")
    Harness_Equal(SourceMemory_Outcome(replay,keys[0]),"","oldest incompatible facts are evicted before proven replay")
    Harness_Equal(replay.entries[0].key,keys[39],"retained snapshot keeps global recency order")
    manyWorks = SourceMemory_Empty()
    for i = 0 to 8
        manyWorks = SourceMemory_Record(manyWorks,keys[i],"working",now+i)
    end for
    for i = 9 to keys.Count()-1
        manyWorks = SourceMemory_Record(manyWorks,keys[i],"incompatible",now+100+i)
    end for
    Harness_Equal(manyWorks.entries.Count(),32,"many successes and failures still fit total cap")
    Harness_Equal(SourceMemory_Outcome(manyWorks,keys[0]),"","only eight newest working files have guaranteed reserve")
    Harness_Equal(SourceMemory_Outcome(manyWorks,keys[1]),"working","eighth newest verified file remains reserved")
    Harness_Equal(SourceMemory_Outcome(manyWorks,keys[8]),"working","newest verified file remains reserved")
    Harness_Equal(manyWorks.entries[24].key,keys[8],"working reserve retains recent-success order")
    manyWorks = SourceMemory_Record(manyWorks,keys[8],"network",now+200)
    Harness_Equal(SourceMemory_Outcome(manyWorks,keys[8]),"network","latest same-file failure supersedes old reserved success")
    Harness_Equal(manyWorks.entries[0].key,keys[8],"replacement failure remains latest event")
    protectedExpired = SourceMemory_Normalize(replay,now+1209600)
    Harness_Equal(SourceMemory_Outcome(protectedExpired,keyA),"","working reserve never extends fourteen-day TTL")

    Harness_Suite("Source memory registry round-trip is credential-free and write failures are recoverable")
    registry = MockRegistry()
    Harness_Ok(SourceMemory_Save(registry,poisoned,now),"sanitized data is saved through registry seam")
    stored = registry.Read(SourceMemory_RegistryKey())
    Harness_Ok(stored.InStr("fixture-secret") < 0,"credentials and URLs cannot survive persisted serialization")
    Harness_Ok(stored.InStr("A.2160p.mkv") < 0,"filenames are absent from registry payload")
    Harness_Ok(stored.InStr("cdn.example") < 0,"hostname and provider are hashed, never persisted in clear")
    restored = SourceMemory_Load(registry,now)
    Harness_Equal(restored.entries.Count(),1,"valid records survive relaunch")
    Harness_Equal(restored.entries[0].key,keyA,"opaque identity survives relaunch")
    Harness_Ok(SourceMemory_Save(registry,bounded,now+40),"full bounded memory fits registry budget")
    Harness_Ok(Len(registry.Read(SourceMemory_RegistryKey())) < 6144,"serialized maximum stays below explicit byte budget for ASCII records")
    registry.failWrites = true
    Harness_Ok(not SourceMemory_Save(registry,memory,now),"refused write reports failure without affecting playable sources")
    registry.failWrites = false
    Harness_Ok(SourceMemory_Save(registry,memory,now+1),"later successful save recovers")
    Harness_Ok(SourceMemory_Save(invalid,memory,now),"missing registry permits memory-only use")
    Harness_Equal(SourceMemory_Load(invalid,now).entries.Count(),0,"missing registry is empty, not a playback error")
    registry.Write(SourceMemory_RegistryKey(),"[]")
    Harness_Equal(SourceMemory_Load(registry,now).entries.Count(),0,"wrong JSON root safely yields empty memory")
    beforeBadClock = registry.Read(SourceMemory_RegistryKey())
    Harness_Ok(not SourceMemory_Save(registry,SourceMemory_Empty(),0),"invalid clock cannot overwrite existing playback memory")
    Harness_Equal(registry.Read(SourceMemory_RegistryKey()),beforeBadClock,"unavailable clock preserves stored bytes")
    Harness_Finish()`
].join('\n');

const staging = path.join(root, 'out-test', 'source-memory');
fs.mkdirSync(staging, { recursive: true });
const script = path.join(staging, 'source-memory-tests.brs');
fs.writeFileSync(script, code);
const result = spawnSync(process.execPath, [
    path.join(root, 'node_modules', '@rokucommunity', 'brs', 'bin', 'cli.js'),
    '--root', staging, script
], { cwd: root, encoding: 'utf8' });
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
process.exit(result.status === 0 && !(result.stderr || '').trim() && /RESULT: PASS/.test(result.stdout || '') ? 0 : 1);
