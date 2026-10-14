#!/usr/bin/env node
// Generates tests/watchedcodec.fixtures.brs — the codec test corpus.
//
// The bitfield payload is compressed with Node's zlib (the same zlib the
// stremio-watched-bitfield library uses on the server), so the interpreter
// fixtures are the true byte-for-byte shape the codec must decode. Each
// fixture is self-checked here: the payload is re-inflated with the same zlib
// and the baked-in expected watched indices must match what the codec's
// anchor-rebase decode would read against the fixture's (decode) ids list.
//
// Fixtures carry the canonical anchor semantics: the field's anchor id is the
// last-watched episode of the writer's list and lastLength is that episode's
// index there + 1. The decode ids list may differ from the writer's list
// (season-0 specials prepended, episodes aired since) — decoding must rebase
// around the anchor, exactly like stremio-watched-bitfield's resize.
//
//   node scripts/gen-watched-fixtures.js
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

// Build the raw bit array (one bit per episode, LSB-first within a byte).
function bitsToBytes(nbits, watched) {
    const bytes = Buffer.alloc(Math.ceil(nbits / 8));
    for (const i of watched) {
        bytes[i >> 3] |= 1 << (i & 7);
    }
    return bytes;
}

// The codec's decode rule, mirrored here so the expected indices bake in the
// same anchor-rebase: bit at position `i + offset` lands on decodeIds[i],
// where `offset = lastLength - 1 - index(anchor)`. A missing anchor yields
// nothing (stremio-core blanks unalignable fields).
function rebaseExpected(anchor, lastLength, rawBytes, decodeIds) {
    const anchorIdx = decodeIds.indexOf(anchor);
    if (anchorIdx === -1) return [];
    const offset = lastLength - 1 - anchorIdx;
    const bitLimit = rawBytes.length * 8;
    const out = [];
    for (let i = 0; i < decodeIds.length; i++) {
        const src = i + offset;
        if (src >= 0 && src < bitLimit && ((rawBytes[src >> 3] >> (src & 7)) & 1) === 1) out.push(i);
    }
    return out;
}

// Compose a canonical field: payload = zlib.deflateSync over the writer's id
// list, anchor = the writer's last watched id, lastLength = its index + 1.
// Then prove the baked-in expectation matches the rebase decode of the payload.
function canonical(seriesId, authoringIds, watched, decodeIds, note) {
    const raw = bitsToBytes(authoringIds.length, watched);
    const compressed = zlib.deflateSync(raw);
    const lastIdx = watched.length ? Math.max.apply(null, watched) : 0;
    const anchor = authoringIds[lastIdx];
    const lastLength = lastIdx + 1;
    const bitfield = anchor + ':' + lastLength + ':' + compressed.toString('base64');
    return assemble(bitfield, raw, lastLength, decodeIds, note);
}

// Like canonical but lets a scenario lie about lastLength (malformed inputs
// must still decode safely, never crash, never trust stray positions).
function degenerate(seriesId, authoringIds, watched, lastLength, decodeIds, note) {
    const raw = bitsToBytes(authoringIds.length, watched);
    const compressed = zlib.deflateSync(raw);
    const anchor = authoringIds[watched.length ? Math.max.apply(null, watched) : 0];
    const bitfield = anchor + ':' + lastLength + ':' + compressed.toString('base64');
    return assemble(bitfield, raw, lastLength, decodeIds, note);
}

// Hand-assembled stored-block (BTYPE=00) coherent field.
function storedBlock(seriesId, authoringIds, watched, decodeIds, note) {
    const raw = bitsToBytes(authoringIds.length, watched);
    const len = raw.length;
    const nlen = 0xffff - len;
    const stream = [];
    stream.push(0x01); // BFINAL=1, BTYPE=00, then pad bits 0
    stream.push(len & 0xff, (len >> 8) & 0xff);
    stream.push(nlen & 0xff, (nlen >> 8) & 0xff);
    for (const b of raw) stream.push(b);
    const wrapped = Buffer.concat([Buffer.from([0x78, 0x01]), Buffer.from(stream), Buffer.from([0, 0, 0, 0])]);
    const lastIdx = watched.length ? Math.max.apply(null, watched) : 0;
    const anchor = authoringIds[lastIdx];
    const lastLength = lastIdx + 1;
    const bitfield = anchor + ':' + lastLength + ':' + wrapped.toString('base64');
    return assemble(bitfield, raw, lastLength, decodeIds, note);
}

// Re-inflate the payload, compare to the raw bytes, and bake in the rebase
// decode's expected indices.
function assemble(bitfield, rawBytes, lastLength, decodeIds, note) {
    const parts = bitfield.split(':');
    const payloadB64 = parts[parts.length - 1];
    const stream = Buffer.from(payloadB64, 'base64');
    const deflateOnly = stream.slice(2, stream.length - 4); // zlib header + trailing adler
    let rawBack;
    try {
        rawBack = zlib.inflateRawSync(deflateOnly);
    } catch (e) {
        throw new Error(`fixture inflate failed for ${note}: ${e.message}`);
    }
    if (!rawBack.equals(rawBytes)) {
        throw new Error(`fixture mismatch for ${note}: got ${rawBack.toString('hex')} want ${rawBytes.toString('hex')}`);
    }
    const anchor = parts.slice(0, parts.length - 2).join(':');
    const expected = rebaseExpected(anchor, lastLength, rawBytes, decodeIds);
    return { bitfield, lastLength, ids: decodeIds, expected, note };
}

function makeIds(seriesId, n) {
    const ids = [];
    for (let i = 0; i < n; i++) {
        ids.push(seriesId + ':' + (Math.floor(i / 12) + 1) + ':' + (i % 12 + 1));
    }
    return ids;
}

const fixtures = [];

// Real fixture from stremio-core's watched-bitfield tests. The zlib payload
// (eJyT...) inflates to bytes 1f 00 — bits 0..4 set, 5 episodes. The anchor
// (the last watched, index 4) and length 5 are already coherent.
fixtures.push(assemble(
    'tt2934286:1:5:5:eJyTZwAAAEAAIA==',
    Buffer.from([0x1f, 0x00]),
    5,
    ['tt2934286:1:1', 'tt2934286:1:2', 'tt2934286:1:3', 'tt2934286:1:4', 'tt2934286:1:5'],
    'stremio-core sample'
));

// One-episode series, single bit set.
{
    const n = 1;
    fixtures.push(canonical('tt1110001', makeIds('tt1110001', n), [0], makeIds('tt1110001', n), 'single episode watched'));
}

// Degenerate zero-length claim: lastLength 0 with a real anchor at index 0
// gives offset -1, so every bit is read before the payload starts — nothing.
{
    const n = 5;
    fixtures.push(degenerate('tt2220002', makeIds('tt2220002', n), [], 0, makeIds('tt2220002', n), 'zero-length bitfield'));
}

// 64-bit (8-byte) payload, sparse set across byte boundaries.
{
    const n = 64;
    fixtures.push(canonical('tt3330003', makeIds('tt3330003', n), [3, 7, 40, 63], makeIds('tt3330003', n), 'sparse 64-bit payload'));
}

// 81-bit (11-byte) payload — crosses byte + a nonzero last byte.
{
    const n = 81;
    fixtures.push(canonical('tt4440004', makeIds('tt4440004', n), [0, 1, 5, 11, 43, 80], makeIds('tt4440004', n), '81-bit block-boundary payload'));
}

// 24 episodes, every bit set.
{
    const n = 24;
    const all = [];
    for (let i = 0; i < n; i++) all.push(i);
    fixtures.push(canonical('tt5550005', makeIds('tt5550005', n), all, makeIds('tt5550005', n), 'all 24 episodes watched'));
}

// 200 unwatched episodes = a run of zero bytes (length/distance match path).
// An empty set anchors on the first id with length 1, per the writer contract.
{
    const n = 200;
    fixtures.push(canonical('tt6660006', makeIds('tt6660006', n), [], makeIds('tt6660006', n), '200 zero bits (run of zeros)'));
}

// Malformed overstated claim: lastLength 200 over data that only holds 24
// bits. The rebase offset lands every read past the payload end, so the
// decodable window is empty — no trusting stray positions, no crash.
{
    const n = 24;
    fixtures.push(degenerate('tt7770007', makeIds('tt7770007', n), [0, 5, 23], 200, makeIds('tt7770007', 200), 'bitfield shorter than its claimed length'));
}

// Episode list shorter than the bitfield: exposed bits clamp to the ids. The
// decode list still holds the anchor (a coherent subset), so the rebase reads
// within the data and only the two ids the list exposes come out watched.
{
    const n = 5;
    fixtures.push(canonical('tt8880008', makeIds('tt8880008', n), [0, 1, 2, 3, 4], ['tt8880008:1:4', 'tt8880008:1:5'], 'exposed bits clamp to episode list'));
}

// Hand-built stored block (BTYPE=00) with a 24-bit payload.
{
    const n = 24;
    fixtures.push(storedBlock('tt9990009', makeIds('tt9990009', n), [0, 14, 17], makeIds('tt9990009', n), 'stored block payload'));
}

// Dynamic-Huffman block with back-references: a repetitive text payload.
{
    const text = Buffer.from(('episode ' + 'watched bitfield pattern '.repeat(20)).repeat(5));
    const n = 96; // decode ids only this long; the drive bits beyond it are ignored
    const watched = [];
    for (let i = 0; i < n; i++) watched.push(i); // first 96 bits all watched
    const lastIdx = Math.max.apply(null, watched);
    const anchor = makeIds('tt1010101', n)[lastIdx];
    const lastLength = lastIdx + 1;
    const compressed = zlib.deflateSync(text, { level: 9 });
    const decoded = assemble(anchor + ':' + lastLength + ':' + compressed.toString('base64'), text, lastLength, makeIds('tt1010101', n), 'dynamic block with length/distance matches');
    fixtures.push(decoded);
}

// THE regression scenario: the writer's list has three season-0 specials
// prepended (Cinemeta includes them); our decode list does not. A positional
// read would shift every mark down by 3 — the "everything shifted by N"
// symptom. Rebase on the anchor realigns the full season-one + season-two
// prefix back onto itself.
{
    const specials = ['tt1GOT00:0:1', 'tt1GOT00:0:2', 'tt1GOT00:0:3'];
    const s1 = [];
    for (let e = 1; e <= 21; e++) s1.push('tt1GOT00:1:' + e);
    const s2 = [];
    for (let e = 1; e <= 3; e++) s2.push('tt1GOT00:2:' + e);
    const authoring = specials.concat(s1).concat(s2);
    const watched = [];
    for (let i = specials.length; i < authoring.length; i++) watched.push(i); // every episode after the specials: the whole recorded prefix
    const decode = s1.concat(s2);
    fixtures.push(canonical('tt1GOT00', authoring, watched, decode, 'prepended specials rebase (writer list has season 0)'));
}

// The mirror direction: our list carries the specials and the writer's did
// not (offset < 0). Marks must land on the real episodes, specials unwatched.
{
    const s1 = [];
    for (let e = 1; e <= 21; e++) s1.push('tt2DNS11:1:' + e);
    const s2 = [];
    for (let e = 1; e <= 3; e++) s2.push('tt2DNS11:2:' + e);
    const decode = ['tt2DNS11:0:1', 'tt2DNS11:0:2', 'tt2DNS11:0:3'].concat(s1).concat(s2);
    const authoring = s1.concat(s2);
    const watched = [];
    for (let i = 0; i < authoring.length; i++) watched.push(i);
    fixtures.push(canonical('tt2DNS11', authoring, watched, decode, 'extra specials on our side (offset < 0)'));
}

// A field whose anchor is not in the decode list at all (fully divergent
// lists, e.g. a different catalog). stremio-core blanks it rather than trust
// stray positions; so do we.
{
    const visit = canonical('tt3AWAY', ['tt3AWAY:1:1', 'tt3AWAY:1:2'], [0, 1], ['tt3AWAY:9:1', 'tt3AWAY:9:2'], 'anchor absent from decode list');
    fixtures.push(visit);
}

const outPath = path.join(__dirname, '..', 'tests', 'watchedcodec.fixtures.brs');
const blocks = [];
blocks.push("' Auto-generated by scripts/gen-watched-fixtures.js - do not edit by hand.\n");
blocks.push("' The codec test corpus: real bitfield strings (ids:long:base64-zlib) plus\n");
blocks.push("' the ordered episode id list and the expected watched indices for each.\n");
blocks.push('function WatchedCodecFixtures() as object\n    return [');
for (const f of fixtures) {
    blocks.push('        {');
    blocks.push(`            note: "${f.note}"`);
    blocks.push(`            bitfield: "${f.bitfield}"`);
    blocks.push(`            lastLength: ${f.lastLength}`);
    blocks.push('            ids: [' + f.ids.map((id) => '"' + id + '"').join(', ') + ']');
    blocks.push('            expected: [' + f.expected.join(', ') + ']');
    blocks.push('        }');
}
blocks.push('    ]\nend function\n');

fs.writeFileSync(outPath, blocks.join('\n'));

// Quick side note on which DEFLATE block type each scenario exercises.
function blockTypeOf(bitfield) {
    const parts = bitfield.split(':');
    const stream = Buffer.from(parts[parts.length - 1], 'base64');
    const first = stream[2];
    const type = first & 0x6; // bits 1..2 of the first payload byte
    return type === 0 ? 'stored' : type === 2 ? 'fixed' : 'dynamic';
}
console.log(`wrote ${fixtures.length} fixtures -> ${path.relative(process.cwd(), outPath)}`);
for (const f of fixtures) {
    console.log(`  - ${f.note}: ${blockTypeOf(f.bitfield)} block`);
}