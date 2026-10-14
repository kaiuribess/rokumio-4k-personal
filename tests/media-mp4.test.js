'use strict';
const assert = require('node:assert/strict');
const { parseMp4Metadata: inspect, Mp4MetadataError } = require('../scripts/media-mp4');
let checks = 0;
function test(name, fn) { fn(); checks++; console.log(`ok ${name}`); }
function box(type, ...parts) {
    const payload = Buffer.concat(parts), header = Buffer.alloc(8);
    header.writeUInt32BE(payload.length + 8); header.write(type, 4, 4, 'latin1');
    return Buffer.concat([header, payload]);
}
function extended(type, payload) {
    const head = Buffer.alloc(16); head.writeUInt32BE(1); head.write(type, 4);
    head.writeBigUInt64BE(BigInt(payload.length + 16), 8);
    return Buffer.concat([head, payload]);
}
function hvcc({ profile = 2, level = 153, tier = 0, depth = 10, arrays = false } = {}) {
    const data = Buffer.alloc(23); data[0] = 1; data[1] = profile | (tier << 5); data[12] = level;
    data[13] = 0xf0; data[15] = 0xfc; data[16] = 0xfd;
    data[17] = data[18] = 0xf8 | (depth - 8); data[21] = 3;
    if (arrays) { data[22] = 1; return Buffer.concat([data, Buffer.from([0xa1, 0, 1, 0, 2, 0x42, 1])]); }
    return data;
}
function visual(width, height, type = 'hvc1', extensions = [box('hvcC', hvcc())]) {
    const fields = Buffer.alloc(78); fields.writeUInt16BE(1, 6);
    fields.writeUInt16BE(width, 24); fields.writeUInt16BE(height, 26);
    return box(type, fields, ...extensions);
}
function audio(type, extensions = [], genericCount = 2, version = 0) {
    const fields = Buffer.alloc(28); fields.writeUInt16BE(1, 6); fields.writeUInt16BE(version, 8);
    fields.writeUInt16BE(genericCount, 16); fields.writeUInt32BE(48000 * 65536, 24);
    return box(type, fields, ...extensions);
}
function tkhd(width, height, version = 0) {
    const data = Buffer.alloc(version ? 96 : 84); data[0] = version;
    data.writeUInt32BE(width * 65536, data.length - 8); data.writeUInt32BE(height * 65536, data.length - 4);
    return box('tkhd', data);
}
function track(entry, handler = 'vide', display = null) {
    const hdlr = Buffer.alloc(12); hdlr.write(handler, 8);
    const stsd = Buffer.alloc(8); stsd.writeUInt32BE(1, 4);
    return box('trak', ...(display ? [display] : []), box('mdia', box('hdlr', hdlr),
        box('minf', box('stbl', box('stsd', stsd, entry)))));
}
function movie(...tracks) { return box('moov', ...tracks); }
const uhd = () => movie(track(visual(3840, 2160)));
function bad(fn, pattern = undefined) { assert.throws(fn, error => error instanceof Mp4MetadataError && (!pattern || pattern.test(error.message))); }

test('HEVC Main10 4K dimensions and level come from sample entry/configuration', () => {
    const result = inspect(uhd()), item = result.tracks[0];
    assert.equal(result.complete, true); assert.equal(item.type, 'video'); assert.equal(item.codec, 'hevc');
    assert.equal(item.width, 3840); assert.equal(item.height, 2160); assert.equal(item.displayDimensions, null);
    assert.deepEqual([item.hevcConfiguration.profile, item.hevcConfiguration.level, item.hevcConfiguration.bitDepthLuma,
        item.hevcConfiguration.chromaSubsampling], ['Main 10', 5.1, 10, '4:2:0']);
});
test('cropped UHD retains actual 3840x1600 dimensions', () => {
    const item = inspect(movie(track(visual(3840, 1600)))).tracks[0];
    assert.deepEqual([item.width, item.height], [3840, 1600]);
});
test('1080 source with 4K tkhd display geometry stays 1080', () => {
    const item = inspect(movie(track(visual(1920, 1080), 'vide', tkhd(3840, 2160)))).tracks[0];
    assert.deepEqual([item.width, item.height], [1920, 1080]);
    assert.deepEqual([item.displayDimensions.width, item.displayDimensions.height], [3840, 2160]);
    assert.match(item.displayDimensions.provenance, /not encoded/);
});
test('version-one tkhd stays separate from encoded dimensions', () => {
    const item = inspect(movie(track(visual(1920, 1080), 'vide', tkhd(3840, 2160, 1)))).tracks[0];
    assert.equal(item.width, 1920); assert.equal(item.displayDimensions.width, 3840);
});
test('AVC configuration is identified without inventing bit depth', () => {
    const avcc = Buffer.from([1, 100, 0, 41, 0xff, 0xe1, 0, 2, 0x67, 0x64, 1, 0, 1, 0x68]);
    const item = inspect(movie(track(visual(1920, 1080, 'avc1', [box('avcC', avcc)])))).tracks[0];
    assert.equal(item.codec, 'h264'); assert.equal(item.avcConfiguration.profile, 'High');
    assert.equal(item.avcConfiguration.level, 4.1); assert.equal(item.avcConfiguration.bitDepthLuma, null);
});
test('extended AVC depth is reported only when explicitly present', () => {
    const avcc = Buffer.from([1, 110, 0, 41, 0xff, 0xe1, 0, 1, 0x67, 1, 0, 1, 0x68, 0xfd, 0xfa, 0xfa, 0]);
    const item = inspect(movie(track(visual(1920, 1080, 'avc3', [box('avcC', avcc)])))).tracks[0];
    assert.equal(item.avcConfiguration.bitDepthLuma, 10); assert.equal(item.avcConfiguration.chromaFormatIdc, 1);
});
test('HEVC high tier is explicit and parameter arrays are bounded', () => {
    const item = inspect(movie(track(visual(3840, 2160, 'hev1', [box('hvcC', hvcc({ tier: 1, arrays: true }))])))).tracks[0];
    assert.equal(item.hevcConfiguration.tier, 'High');
    assert.deepEqual(item.hevcConfiguration.parameterArrays, [{ nalUnitType: 33, count: 1 }]);
});
test('PQ/BT2020 color signalling is kept separate from HDR10 playback claims', () => {
    const colr = Buffer.alloc(11); colr.write('nclx'); colr.writeUInt16BE(9, 4);
    colr.writeUInt16BE(16, 6); colr.writeUInt16BE(9, 8);
    const item = inspect(movie(track(visual(3840, 2160, 'hvc1', [box('hvcC', hvcc()), box('colr', colr)])))).tracks[0];
    assert.equal(item.hdrSignalling, 'PQ'); assert.equal(item.color.primaries, 9); assert.equal(item.color.fullRange, false);
    assert.equal(item.dolbyVisionSignalling, false); assert.equal(item.hdr10, undefined);
});
test('Dolby Vision descriptor does not certify HDR10 fallback', () => {
    const item = inspect(movie(track(visual(3840, 2160, 'dvhe', [box('hvcC', hvcc()), box('dvcC', Buffer.alloc(5))])))).tracks[0];
    assert.equal(item.dolbyVisionSignalling, true); assert.equal(item.hdrSignalling, undefined);
});
test('sample entry without decoder config reports a limitation', () => {
    const result = inspect(movie(track(visual(3840, 2160, 'hvc1', []))));
    assert.equal(result.tracks[0].width, 3840); assert.equal(result.tracks[0].hevcConfiguration, undefined);
    assert.ok(result.warnings.some(message => /lacks its decoder/.test(message)));
});
test('late moov after mdat is located without scanning media contents', () => {
    const prefix = Buffer.concat([box('ftyp', Buffer.from('isom0000')), box('mdat', Buffer.alloc(512 * 1024))]);
    const result = inspect(Buffer.concat([prefix, uhd()]));
    assert.equal(result.tracks[0].width, 3840); assert.ok(result.tracks[0].sampleEntryOffset > prefix.length);
});
test('absolute range offset is reflected in sample-entry location', () => {
    const local = inspect(uhd()).tracks[0].sampleEntryOffset;
    assert.equal(inspect(uhd(), { absoluteOffset: 9000000 }).tracks[0].sampleEntryOffset, local + 9000000);
});
test('extended size boxes are supported without unsafe integer conversion', () => {
    const regular = uhd(); const result = inspect(extended('moov', regular.subarray(8)));
    assert.equal(result.tracks[0].height, 2160);
});
test('fake moov/stsd inside mdat is never evidence', () => {
    const result = inspect(box('mdat', uhd()));
    assert.equal(result.tracks.length, 0); assert.equal(result.complete, false);
});
test('misplaced stsd in moov is ignored rather than recursively scanned', () => {
    const description = Buffer.alloc(8); description.writeUInt32BE(1, 4);
    assert.equal(inspect(box('moov', box('stsd', description, visual(3840, 2160)))).tracks.length, 0);
});
test('truncated top-level media is accepted only with explicit partial option', () => {
    const mediaHeader = Buffer.alloc(8); mediaHeader.writeUInt32BE(999999); mediaHeader.write('mdat', 4);
    const prefix = Buffer.concat([uhd(), mediaHeader]); bad(() => inspect(prefix), /exceeds/);
    const result = inspect(prefix, { allowPartialMdat: true });
    assert.equal(result.tracks[0].width, 3840); assert.match(result.warnings[0], /no samples/);
});
test('truncated moov stays invalid even when partial media is allowed', () => {
    const broken = uhd().subarray(0, uhd().length - 1);
    bad(() => inspect(broken, { allowPartialMdat: true }), /exceeds/);
});
test('invalid sizes and extended headers are rejected', () => {
    const small = box('free'); small.writeUInt32BE(7); bad(() => inspect(small), /size/);
    const extendedOnly = box('free'); extendedOnly.writeUInt32BE(1); bad(() => inspect(extendedOnly), /extended/);
    const huge = Buffer.alloc(16); huge.writeUInt32BE(1); huge.write('moov', 4); huge.writeBigUInt64BE(2n ** 60n, 8);
    bad(() => inspect(huge), /integer/); bad(() => inspect(Buffer.alloc(7)), /header/);
});
test('stsd count and visual fixed fields must be complete', () => {
    const data = uhd(); const location = data.indexOf(Buffer.from('stsd')) - 4;
    const badCount = Buffer.from(data); badCount.writeUInt32BE(2, location + 12);
    bad(() => inspect(badCount), /count mismatch/);
    bad(() => inspect(movie(track(box('hvc1', Buffer.alloc(20))))), /visual/);
    bad(() => inspect(movie(track(visual(0, 2160)))), /dimensions/);
});
test('HEVC/AVC truncated configuration and duplicate config cannot certify metadata', () => {
    bad(() => inspect(movie(track(visual(3840, 2160, 'hvc1', [box('hvcC', hvcc().subarray(0, 22))])))), /hvcC/);
    bad(() => inspect(movie(track(visual(3840, 2160, 'hvc1', [box('hvcC', hvcc()), box('hvcC', hvcc())])))), /duplicate/);
    bad(() => inspect(movie(track(visual(1920, 1080, 'avc1', [box('avcC', Buffer.from([1, 100, 0, 41, 0xff, 0xe1, 0]))])))), /AVC/);
    const reserved = hvcc(); reserved[17] = 2;
    bad(() => inspect(movie(track(visual(3840, 2160, 'hvc1', [box('hvcC', reserved)])))), /HEVC/);
});
test('known four-zero HEVC sample-entry padding is narrow and documented', () => {
    const result = inspect(movie(track(visual(3840, 2160, 'hvc1', [box('hvcC', hvcc()), Buffer.alloc(4)]))));
    assert.equal(result.tracks[0].width, 3840); assert.ok(result.warnings.some(message => /padding/.test(message)));
    bad(() => inspect(movie(track(visual(3840, 2160, 'hvc1', [Buffer.alloc(4)])))), /header/);
});
test('EAC3 5.1 comes from dec3 despite a generic stereo count', () => {
    const item = inspect(movie(track(audio('ec-3', [box('dec3', Buffer.from('0800200f00', 'hex'))], 2), 'soun'))).tracks[0];
    assert.equal(item.sampleEntryChannelCount, 2); assert.equal(item.channelCount, 6); assert.equal(item.channelLayout, '5.1');
    assert.equal(item.audioConfiguration.sampleRateHz, 48000); assert.equal(item.audioConfiguration.dataRateKbps, 256);
});
test('AC3 stereo configuration overrides a generic six-channel field', () => {
    const item = inspect(movie(track(audio('ac-3', [box('dac3', Buffer.from('101140', 'hex'))], 6), 'soun'))).tracks[0];
    assert.equal(item.channelCount, 2); assert.equal(item.channelLayout, null); assert.equal(item.sampleEntryChannelCount, 6);
});
test('dependent EAC3 does not invent a simple 5.1 layout', () => {
    const item = inspect(movie(track(audio('ec-3', [box('dec3', Buffer.from('0800200f020000', 'hex'))]), 'soun'))).tracks[0];
    assert.equal(item.channelCount, null); assert.equal(item.channelLayout, null);
    assert.equal(item.audioConfiguration.independentSubstreams[0].dependentSubstreams, 1);
});
test('unknown audio and unsupported versions do not claim surround', () => {
    const generic = inspect(movie(track(audio('mp4a', [], 6), 'soun'))).tracks[0];
    assert.equal(generic.channelCount, null); assert.equal(generic.codec, 'unknown');
    const version = inspect(movie(track(audio('ec-3', [], 6, 1), 'soun'))).tracks[0];
    assert.equal(version.channelCount, null);
});
test('truncated or invalid Dolby configuration remains unknown through a parse failure', () => {
    for (const bytes of ['0800200f', '0800000f00'])
        bad(() => inspect(movie(track(audio('ec-3', [box('dec3', Buffer.from(bytes, 'hex'))]), 'soun'))));
    bad(() => inspect(movie(track(audio('ac-3', [box('dac3', Buffer.from('1011', 'hex'))]), 'soun'))));
});
test('conflicting handlers cannot relabel video as audio', () => {
    bad(() => inspect(movie(track(visual(3840, 2160), 'soun'))), /handler/);
});
test('bounds cannot be increased, and small limits reject excess work', () => {
    bad(() => inspect(uhd(), { maxBytes: 10 }), /byte limit/);
    bad(() => inspect(uhd(), { maxBoxes: 2 }), /box count/);
    bad(() => inspect(uhd(), { maxDepth: 2 }), /depth/);
    bad(() => inspect(uhd(), { maxBytes: 999999999 }), /Invalid/);
    bad(() => inspect(uhd(), { absoluteOffset: -1 }), /offset/);
    bad(() => inspect('not bytes'), /buffer/);
});
test('typed-array input honors its slice boundaries', () => {
    const source = Buffer.concat([Buffer.alloc(4), uhd(), Buffer.alloc(4)]);
    const view = new Uint8Array(source.buffer, source.byteOffset + 4, source.length - 8);
    assert.equal(inspect(view).tracks[0].width, 3840);
});
console.log(`MP4 metadata checks passed: ${checks}`);
