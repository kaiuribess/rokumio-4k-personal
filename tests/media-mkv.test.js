'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {inspectMkv, readVint, MkvParseError, MAX_BYTES} = require('../scripts/media-mkv');

function size(value, length) {
  value = BigInt(value);
  if (!length) {
    length = 1;
    while (value >= (1n << BigInt(7 * length)) - 1n) length += 1;
  }
  const output = Buffer.alloc(length);
  for (let index = length - 1; index >= 0; index -= 1) { output[index] = Number(value & 255n); value >>= 8n; }
  output[0] |= 1 << (8 - length);
  return output;
}
function element(id, bytes) { return Buffer.concat([Buffer.from(id, 'hex'), size(bytes.length), bytes]); }
function uint(value, length = 4) {
  value = BigInt(value);
  const output = Buffer.alloc(length);
  for (let index = length - 1; index >= 0; index -= 1) { output[index] = Number(value & 255n); value >>= 8n; }
  return output;
}
function u(id, value, length) { return element(id, uint(value, length)); }
function floating(id, value, length = 8) {
  const bytes = Buffer.alloc(length);
  if (length === 4) bytes.writeFloatBE(value); else bytes.writeDoubleBE(value);
  return element(id, bytes);
}
function video(width = 3840, height = 2160, extras = []) {
  return element('e0', Buffer.concat([u('b0', width), u('ba', height), ...extras]));
}
function track(type, codec, content, number = type, extras = []) {
  return element('ae', Buffer.concat([u('d7', number), u('83', type), element('86', Buffer.from(codec)), content, ...extras]));
}
function tracks(entries) { return element('1654ae6b', Buffer.concat(entries)); }
const ebml = element('1a45dfa3', element('4282', Buffer.from('matroska')));
function document(body, unknown = false) {
  const segment = unknown ? Buffer.concat([Buffer.from('18538067', 'hex'), Buffer.from('01ffffffffffffff', 'hex'), body]) : element('18538067', body);
  return Buffer.concat([ebml, segment]);
}
const hevc = (width, height, extras) => track(1, 'V_MPEGH/ISO/HEVC', video(width, height, extras));
function rejected(bytes, code) {
  assert.throws(() => inspectMkv(bytes), error => error instanceof MkvParseError && (!code || error.code === code));
}
function hevcPrivate() {
  const bytes = Buffer.alloc(23);
  bytes[0] = 1; bytes[1] = 2; bytes[12] = 153;
  bytes[16] = 253; bytes[17] = 250; bytes[18] = 250;
  return bytes;
}

test('actual Tracks metadata confirms coded 3840x2160 without a filename', () => {
  const report = inspectMkv(document(tracks([hevc(3840, 2160)])));
  assert.equal(report.metadataComplete, true);
  assert.deepEqual([report.tracks[0].width, report.tracks[0].height, report.tracks[0].codecId], [3840, 2160, 'V_MPEGH/ISO/HEVC']);
  assert.equal(report.tracks[0].displayWidth, null);
  assert.equal(report.tracks[0].bitDepth, null);
  assert.match(report.notVerified, /prior upscaling/);
});
test('cropped UHD remains 3840x1600 rather than inventing 2160 rows', () => {
  const report = inspectMkv(document(tracks([hevc(3840, 1600)])));
  assert.deepEqual([report.tracks[0].width, report.tracks[0].height], [3840, 1600]);
});
test('1080 content with 4K display dimensions is still encoded 1080', () => {
  const report = inspectMkv(document(tracks([hevc(1920, 1080, [u('54b0', 3840), u('54ba', 2160)])])));
  assert.deepEqual([report.tracks[0].width, report.tracks[0].height], [1920, 1080]);
  assert.deepEqual([report.tracks[0].displayWidth, report.tracks[0].displayHeight], [3840, 2160]);
});
test('display aspect-ratio units are not pixel dimensions', () => {
  const report = inspectMkv(document(tracks([hevc(3840, 2160, [u('54b0', 16), u('54ba', 9), u('54b2', 3)])])));
  assert.equal(report.tracks[0].displayDimensionsArePixels, false);
});
test('colour metadata exposes 10-bit PQ/BT2020 raw declarations', () => {
  const colour = element('55b0', Buffer.concat([u('55b2', 10), u('55ba', 16), u('55bb', 9), u('55b1', 9), u('55bc', 1000)]));
  const item = inspectMkv(document(tracks([hevc(3840, 2160, [colour])]))).tracks[0];
  assert.equal(item.bitDepth, 10);
  assert.deepEqual(item.colour, {matrixCoefficients: 9, bitsPerChannel: 10, transferCharacteristics: 16, primaries: 9, maxCLL: 1000});
});
test('zero bits-per-channel remains unspecified', () => {
  const colour = element('55b0', u('55b2', 0));
  assert.equal(inspectMkv(document(tracks([hevc(3840, 2160, [colour])]))).tracks[0].bitDepth, null);
});
test('validated HEVC CodecPrivate establishes profile/tier/level/bit depth when Colour is absent', () => {
  const entry = track(1, 'V_MPEGH/ISO/HEVC', video(), 1, [element('63a2', hevcPrivate())]);
  const item = inspectMkv(document(tracks([entry]))).tracks[0];
  assert.equal(item.bitDepth, 10);
  assert.equal(item.hevcConfiguration.profile, 'Main 10');
  assert.equal(item.hevcConfiguration.tier, 'Main');
  assert.equal(item.hevcConfiguration.level, 5.1);
  assert.equal(item.hevcConfiguration.chromaSubsampling, '4:2:0');
});
test('HEVC private metadata preserves High tier without claiming Roku support', () => {
  const bytes = hevcPrivate(); bytes[1] |= 32;
  const entry = track(1, 'V_MPEGH/ISO/HEVC', video(), 1, [element('63a2', bytes)]);
  const item = inspectMkv(document(tracks([entry]))).tracks[0];
  assert.equal(item.hevcConfiguration.tier, 'High');
});
test('conflicting bit-depth declarations remain unverified', () => {
  const colour = element('55b0', u('55b2', 8));
  const entry = track(1, 'V_MPEGH/ISO/HEVC', video(3840, 2160, [colour]), 1, [element('63a2', hevcPrivate())]);
  const report = inspectMkv(document(tracks([entry])));
  assert.equal(report.tracks[0].bitDepth, null);
  assert.match(report.warnings.join(' '), /disagrees/);
});
test('truncated HEVC parameter arrays are rejected', () => {
  const bytes = hevcPrivate(); bytes[22] = 1;
  rejected(document(tracks([track(1, 'V_MPEGH/ISO/HEVC', video(), 1, [element('63a2', bytes)])])), 'TRUNCATED_METADATA');
});
test('HEVC parameter-array lengths are bounded and trailing garbage is rejected', () => {
  const bytes = hevcPrivate(); bytes[22] = 1;
  const bounded = Buffer.concat([bytes, Buffer.from('a1000100024201', 'hex')]);
  const entry = track(1, 'V_MPEGH/ISO/HEVC', video(), 1, [element('63a2', bounded)]);
  assert.deepEqual(inspectMkv(document(tracks([entry]))).tracks[0].hevcConfiguration.parameterArrays, [{nalUnitType: 33, count: 1}]);
  const truncated = bounded.subarray(0, bounded.length - 1);
  rejected(document(tracks([track(1, 'V_MPEGH/ISO/HEVC', video(), 1, [element('63a2', truncated)])])), 'TRUNCATED_METADATA');
  rejected(document(tracks([track(1, 'V_MPEGH/ISO/HEVC', video(), 1, [element('63a2', Buffer.concat([hevcPrivate(), Buffer.from([0])]))])])));
});
test('EAC3 six-channel audio and sample rate come from Audio metadata', () => {
  const audio = element('e1', Buffer.concat([u('9f', 6), floating('b5', 48000), u('6264', 16)]));
  const report = inspectMkv(document(tracks([hevc(3840, 2160), track(2, 'A_EAC3', audio)])));
  assert.equal(report.tracks[1].codecId, 'A_EAC3');
  assert.deepEqual(report.tracks[1].audio, {channels: 6, channelsDeclared: true, sampleRateHz: 48000, outputSampleRateHz: null, bitDepth: 16});
});
test('stereo AC3 remains stereo and missing channel metadata stays unknown', () => {
  const stereo = track(2, 'A_AC3', element('e1', Buffer.concat([u('9f', 2), floating('b5', 48000, 4)])));
  assert.equal(inspectMkv(document(tracks([stereo]))).tracks[0].audio.channels, 2);
  const unknown = track(2, 'A_EAC3', element('e1', floating('b5', 48000)));
  assert.equal(inspectMkv(document(tracks([unknown]))).tracks[0].audio.channels, null);
});
test('pixel-looking bytes outside Tracks provide no resolution evidence', () => {
  const fakeVideo = element('ec', hevc(3840, 2160));
  const report = inspectMkv(document(fakeVideo));
  assert.equal(report.metadataComplete, false);
  assert.deepEqual(report.tracks, []);
});
test('unknown-sized Segment parses finite metadata without declaring a complete file', () => {
  const report = inspectMkv(document(tracks([hevc(3840, 2160)]), true));
  assert.equal(report.metadataComplete, true);
  assert.equal(report.fileComplete, false);
});
test('first Cluster stops inspection and embedded metadata-like bytes are ignored', () => {
  const cluster = element('1f43b675', tracks([hevc(7680, 4320)]));
  const report = inspectMkv(document(Buffer.concat([tracks([hevc(1920, 1080)]), cluster])));
  assert.equal(report.stoppedAtCluster, true);
  assert.equal(report.tracks[0].width, 1920);
});
test('unknown-sized or truncated Cluster does not invalidate earlier complete Tracks', () => {
  const start = tracks([hevc(3840, 2160)]);
  for (const cluster of [Buffer.from('1f43b675ff', 'hex'), Buffer.from('1f43b675', 'hex'), Buffer.concat([Buffer.from('1f43b675', 'hex'), size(100000)])]) {
    const report = inspectMkv(document(Buffer.concat([start, cluster]), true));
    assert.equal(report.metadataComplete, true);
    assert.equal(report.stoppedAtCluster, true);
  }
});
test('Cluster before Tracks stays unverified even if later bytes contain Tracks', () => {
  const body = Buffer.concat([element('1f43b675', Buffer.alloc(0)), tracks([hevc(3840, 2160)])]);
  assert.equal(inspectMkv(document(body)).metadataComplete, false);
});
test('a finite large Segment can contain a complete bounded metadata prefix', () => {
  const body = tracks([hevc(3840, 2160)]);
  const input = Buffer.concat([ebml, Buffer.from('18538067', 'hex'), size(50_000_000_000), body]);
  const report = inspectMkv(input);
  assert.equal(report.metadataComplete, true);
  assert.equal(report.fileComplete, false);
});
test('unknown-sized Tracks and TrackEntry are rejected rather than guessed', () => {
  rejected(document(Buffer.from('1654ae6bff', 'hex')), 'UNKNOWN_SIZE');
  rejected(document(tracks([Buffer.from('aeff', 'hex')])), 'UNKNOWN_SIZE');
});
test('truncated Tracks and nested child lengths are rejected', () => {
  rejected(document(Buffer.concat([Buffer.from('1654ae6b', 'hex'), size(1000), Buffer.from('ae80', 'hex')])), 'TRUNCATED_METADATA');
  const badVideo = element('e0', Buffer.concat([Buffer.from('b0', 'hex'), size(20), Buffer.from('01', 'hex')]));
  rejected(document(tracks([track(1, 'V_MPEGH/ISO/HEVC', badVideo)])), 'TRUNCATED_METADATA');
});
test('metadata must include required positive encoded dimensions', () => {
  rejected(document(tracks([hevc(0, 2160)])));
  rejected(document(tracks([track(1, 'V_MPEGH/ISO/HEVC', element('e0', u('b0', 3840)))])), 'INCOMPLETE_TRACK');
});
test('duplicate dimension, track number and Tracks metadata are rejected', () => {
  rejected(document(tracks([hevc(3840, 2160, [u('b0', 1920)])])));
  rejected(document(tracks([hevc(3840, 2160), hevc(1920, 1080)])));
  rejected(document(Buffer.concat([tracks([hevc(3840, 2160)]), tracks([hevc(1920, 1080)])])));
});
test('multiple enabled video tracks produce an explicit selection warning', () => {
  const second = track(1, 'V_MPEGH/ISO/HEVC', video(1920, 1080), 3);
  assert.match(inspectMkv(document(tracks([hevc(3840, 2160), second]))).warnings.join(' '), /Multiple enabled video tracks/);
});
test('unsafe uint and finite EBML sizes are rejected without precision loss', () => {
  const bigWidth = element('e0', Buffer.concat([u('b0', 9007199254740992n, 8), u('ba', 2160)]));
  rejected(document(tracks([track(1, 'V_MPEGH/ISO/HEVC', bigWidth)])), 'NUMERIC_LIMIT');
  rejected(Buffer.concat([ebml, Buffer.from('18538067', 'hex'), size(9007199254740992n, 8)]), 'NUMERIC_LIMIT');
});
test('malformed variable integers and partial identifiers fail safely', () => {
  for (const bytes of [Buffer.from([0]), Buffer.from('1a45', 'hex'), Buffer.from('08ffffffff', 'hex')]) rejected(bytes);
  assert.throws(() => readVint(Buffer.from([0]), 0, 1), MkvParseError);
  assert.throws(() => readVint(Buffer.from([0x40]), 0, 1), MkvParseError);
  assert.throws(() => readVint(Buffer.from([0x80]), 0, 1, true), MkvParseError);
  assert.throws(() => readVint(Buffer.from([0xff]), 0, 1, true), MkvParseError);
});
test('invalid audio float and zero channels do not become surround confirmation', () => {
  for (const rate of [0, -48000, Infinity, NaN]) {
    const audio = element('e1', Buffer.concat([u('9f', 6), floating('b5', rate)]));
    rejected(document(tracks([track(2, 'A_EAC3', audio)])));
  }
  rejected(document(tracks([track(2, 'A_EAC3', element('e1', u('9f', 0)))])));
});
test('wrong document type, byte budget and non-byte inputs fail safely', () => {
  rejected(Buffer.concat([element('1a45dfa3', element('4282', Buffer.from('other'))), element('18538067', Buffer.alloc(0))]));
  rejected(Buffer.alloc(MAX_BYTES + 1), 'INSPECTION_LIMIT');
  assert.throws(() => inspectMkv('3840x2160'), MkvParseError);
});
test('excessive element count stops within a fixed inspection budget', () => {
  const body = Buffer.alloc(20010 * 2);
  for (let index = 0; index < body.length; index += 2) { body[index] = 0xec; body[index + 1] = 0x80; }
  rejected(document(body), 'INSPECTION_LIMIT');
});
test('Uint8Array view is read correctly and input is never modified', () => {
  const bytes = document(tracks([hevc(3840, 2160)]));
  const wrapped = Buffer.concat([Buffer.from([99]), bytes, Buffer.from([88])]);
  const before = Buffer.from(wrapped);
  const input = new Uint8Array(wrapped.buffer, wrapped.byteOffset + 1, bytes.length);
  assert.equal(inspectMkv(input).tracks[0].width, 3840);
  assert.deepEqual(wrapped, before);
});
