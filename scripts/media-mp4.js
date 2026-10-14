'use strict';

// Bounded ISO-BMFF metadata inspection, without reading/decoding media samples.
// VisualSampleEntry dimensions are kept separate from tkhd display dimensions.
// HEVC configuration follows ISO/IEC 14496-15; Dolby fields follow ETSI
// TS 102 366 annex F. Codec configuration is metadata, not decoder/output proof.
class Mp4MetadataError extends Error {
    constructor(message) { super(message); this.name = 'Mp4MetadataError'; }
}
const fail = message => { throw new Mp4MetadataError(message); };
const VIDEO = new Map([['hvc1', 'hevc'], ['hev1', 'hevc'], ['avc1', 'h264'],
    ['avc3', 'h264'], ['dvh1', 'hevc'], ['dvhe', 'hevc'], ['av01', 'av1'],
    ['vp09', 'vp9'], ['mp4v', 'mpeg4'], ['encv', 'encrypted']]);
const AUDIO = new Map([['ac-3', 'ac3'], ['ec-3', 'eac3'], ['mp4a', 'unknown'],
    ['enca', 'encrypted'], ['Opus', 'opus'], ['fLaC', 'flac'], ['alac', 'alac']]);
const AC3_CHANNELS = [2, 1, 2, 3, 3, 4, 4, 5];
const AC3_RATES = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224,
    256, 320, 384, 448, 512, 576, 640];
function need(data, bytes, label) {
    if (data.length < bytes) fail(`Truncated ${label}`);
}
class Bits {
    constructor(data) { this.data = data; this.position = 0; }
    take(count) {
        if (this.position + count > this.data.length * 8) fail('Truncated Dolby configuration');
        let value = 0;
        for (let n = 0; n < count; n++, this.position++)
            value = value * 2 + ((this.data[this.position >> 3] >> (7 - (this.position & 7))) & 1);
        return value;
    }
}
function parseDac3(data) {
    need(data, 3, 'dac3');
    if (data.length !== 3) fail('Invalid dac3 size');
    const bits = new Bits(data);
    const fscod = bits.take(2), bsid = bits.take(5), bsmod = bits.take(3);
    const acmod = bits.take(3), lfe = bits.take(1), rate = bits.take(5);
    if (bits.take(5) !== 0 || fscod === 3 || bsid > 10 || rate >= AC3_RATES.length)
        fail('Unsupported or invalid AC3 configuration');
    const channelCount = AC3_CHANNELS[acmod] + lfe;
    return { configuration: 'dac3', bsid, bsmod, acmod, lfe: !!lfe,
        channelCount, channelLayout: acmod === 7 && lfe === 1 ? '5.1' : null,
        sampleRateHz: [48000, 44100, 32000][fscod], dataRateKbps: AC3_RATES[rate] };
}
function parseDec3(data) {
    need(data, 5, 'dec3');
    const bits = new Bits(data), dataRateKbps = bits.take(13), count = bits.take(3) + 1;
    const substreams = [];
    for (let n = 0; n < count; n++) {
        const fscod = bits.take(2), bsid = bits.take(5), bsmod = bits.take(5);
        const acmod = bits.take(3), lfe = bits.take(1), reserved = bits.take(3);
        const dependentSubstreams = bits.take(4);
        const dependentChannelLocations = dependentSubstreams ? bits.take(9) : null;
        const reservedTail = dependentSubstreams ? 0 : bits.take(1);
        if (fscod === 3 || bsid < 11 || bsid > 16 || reserved || reservedTail)
            fail('Unsupported or invalid EAC3 configuration');
        substreams.push({ sampleRateHz: [48000, 44100, 32000][fscod], bsid, bsmod,
            acmod, lfe: !!lfe, baseChannelCount: AC3_CHANNELS[acmod] + lfe,
            dependentSubstreams, dependentChannelLocations });
    }
    // Dependent/multiple streams and optional JOC extensions need richer parsing.
    // Never infer their complete layout or Atmos output from the base alone.
    const simple = count === 1 && substreams[0].dependentSubstreams === 0;
    return { configuration: 'dec3', dataRateKbps, independentSubstreams: substreams,
        channelCount: simple ? substreams[0].baseChannelCount : null,
        channelLayout: simple && substreams[0].acmod === 7 && substreams[0].lfe ? '5.1' : null,
        sampleRateHz: simple ? substreams[0].sampleRateHz : null,
        unparsedExtensionBytes: data.length - Math.ceil(bits.position / 8) };
}
function parameterSets(data, cursor, count, label, limit) {
    if (count > limit) fail(`${label} parameter count exceeds inspection limit`);
    for (let n = 0; n < count; n++) {
        if (cursor + 2 > data.length) fail(`Truncated ${label} parameter length`);
        const size = data.readUInt16BE(cursor); cursor += 2;
        if (!size || cursor + size > data.length) fail(`Truncated ${label} parameter payload`);
        cursor += size;
    }
    return cursor;
}
function parseHvcc(data, limit) {
    need(data, 23, 'hvcC');
    if (data[0] !== 1 || (data[13] & 0xf0) !== 0xf0 ||
        (data[15] & 0xfc) !== 0xfc || (data[16] & 0xfc) !== 0xfc ||
        (data[17] & 0xf8) !== 0xf8 || (data[18] & 0xf8) !== 0xf8)
        fail('Unsupported or invalid HEVC configuration');
    let cursor = 23, total = 0;
    const parameterArrays = [];
    for (let n = 0; n < data[22]; n++) {
        if (cursor + 3 > data.length) fail('Truncated HEVC parameter array');
        const nalUnitType = data[cursor] & 63, count = data.readUInt16BE(cursor + 1);
        if (data[cursor] & 64) fail('Invalid HEVC parameter array reserved bit');
        cursor += 3; total += count;
        if (total > limit) fail('HEVC parameter count exceeds inspection limit');
        cursor = parameterSets(data, cursor, count, 'HEVC', limit);
        parameterArrays.push({ nalUnitType, count });
    }
    if (cursor !== data.length) fail('Unexpected trailing HEVC configuration data');
    const profileIdc = data[1] & 31;
    return { configuration: 'hvcC', profileIdc,
        profile: ({ 1: 'Main', 2: 'Main 10', 3: 'Main Still Picture' })[profileIdc] || 'Other / unverified',
        tierFlag: (data[1] >> 5) & 1, tier: data[1] & 32 ? 'High' : 'Main',
        levelIdc: data[12], level: data[12] / 30, profileSpace: data[1] >> 6,
        chromaFormatIdc: data[16] & 3,
        chromaSubsampling: ['monochrome', '4:2:0', '4:2:2', '4:4:4'][data[16] & 3],
        bitDepthLuma: 8 + (data[17] & 7), bitDepthChroma: 8 + (data[18] & 7),
        parameterArrays, provenance: 'HEVC decoder configuration record' };
}
function parseAvcc(data, limit) {
    need(data, 7, 'avcC');
    if (data[0] !== 1 || (data[4] & 0xfc) !== 0xfc || (data[5] & 0xe0) !== 0xe0)
        fail('Unsupported or invalid AVC configuration');
    let cursor = parameterSets(data, 6, data[5] & 31, 'AVC SPS', limit);
    if (cursor >= data.length) fail('Truncated AVC PPS count');
    cursor = parameterSets(data, cursor + 1, data[cursor], 'AVC PPS', limit);
    const result = { configuration: 'avcC', profileIdc: data[1], profileCompatibility: data[2],
        profile: ({ 66: 'Baseline', 77: 'Main', 88: 'Extended', 100: 'High', 110: 'High 10',
            122: 'High 4:2:2', 244: 'High 4:4:4 Predictive' })[data[1]] || 'Other / unverified',
        levelIdc: data[3], level: data[3] / 10, bitDepthLuma: null, bitDepthChroma: null,
        provenance: 'AVC decoder configuration record' };
    if (cursor < data.length) {
        if (![100, 110, 122, 144, 244].includes(data[1])) fail('Unexpected trailing AVC configuration data');
        if (cursor + 4 > data.length) fail('Truncated extended AVC configuration');
        if ((data[cursor] & 0xfc) !== 0xfc || (data[cursor + 1] & 0xf8) !== 0xf8 ||
            (data[cursor + 2] & 0xf8) !== 0xf8) fail('Invalid extended AVC configuration');
        result.chromaFormatIdc = data[cursor] & 3;
        result.bitDepthLuma = 8 + (data[cursor + 1] & 7);
        result.bitDepthChroma = 8 + (data[cursor + 2] & 7);
        cursor = parameterSets(data, cursor + 4, data[cursor + 3], 'AVC extension', limit);
    }
    if (cursor !== data.length) fail('Unexpected trailing AVC configuration data');
    return result;
}
function parseColor(data) {
    need(data, 4, 'colr');
    const type = data.toString('latin1', 0, 4);
    if (type !== 'nclx' && type !== 'nclc') return { type, interpretation: 'Unknown / unverified' };
    need(data, type === 'nclx' ? 11 : 10, 'colr');
    if (data.length !== (type === 'nclx' ? 11 : 10)) fail('Invalid colr size');
    if (type === 'nclx' && (data[10] & 127)) fail('Invalid colr reserved bits');
    return { type, primaries: data.readUInt16BE(4), transfer: data.readUInt16BE(6),
        matrix: data.readUInt16BE(8), fullRange: type === 'nclx' ? !!(data[10] & 128) : null,
        provenance: 'colr sample-entry metadata' };
}

function parseMp4Metadata(input, options = {}) {
    if (!Buffer.isBuffer(input) && !(input instanceof Uint8Array)) fail('MP4 input must be a byte buffer');
    const data = Buffer.isBuffer(input) ? input : Buffer.from(input.buffer, input.byteOffset, input.byteLength);
    const limits = { maxBytes: 8 * 1024 * 1024, maxBoxes: 10000, maxDepth: 12,
        maxTracks: 64, maxEntries: 64, maxParameterSets: 256 };
    for (const key of Object.keys(limits)) if (options[key] !== undefined) {
        if (!Number.isSafeInteger(options[key]) || options[key] < 1 || options[key] > limits[key]) fail(`Invalid ${key} limit`);
        limits[key] = options[key];
    }
    const absoluteOffset = options.absoluteOffset === undefined ? 0 : options.absoluteOffset;
    if (!Number.isSafeInteger(absoluteOffset) || absoluteOffset < 0 || absoluteOffset + data.length > Number.MAX_SAFE_INTEGER)
        fail('Invalid absolute byte offset');
    if (data.length > limits.maxBytes) fail('MP4 metadata exceeds inspection byte limit');
    let boxCount = 0, moovCount = 0;
    const result = { container: 'mp4', tracks: [], warnings: [], complete: false };
    function boxes(start, end, depth, partialMdat = false) {
        if (depth > limits.maxDepth) fail('MP4 nesting exceeds inspection depth limit');
        const answer = [];
        for (let cursor = start; cursor < end;) {
            if (++boxCount > limits.maxBoxes) fail('MP4 box count exceeds inspection limit');
            if (cursor + 8 > end) fail('Truncated MP4 box header');
            let size = data.readUInt32BE(cursor), header = 8;
            const type = data.toString('latin1', cursor + 4, cursor + 8);
            if (size === 1) {
                if (cursor + 16 > end) fail('Truncated extended MP4 box header');
                const large = data.readBigUInt64BE(cursor + 8);
                if (large > BigInt(Number.MAX_SAFE_INTEGER)) fail('MP4 box size exceeds safe integer limit');
                size = Number(large); header = 16;
            } else if (size === 0) size = end - cursor;
            if (size < header) fail('Invalid MP4 box size');
            if (cursor + size > end) {
                if (partialMdat && type === 'mdat') {
                    result.warnings.push('Media payload is outside the inspected prefix; no samples inspected.');
                    break;
                }
                fail('Declared MP4 box exceeds available metadata bytes');
            }
            answer.push({ type, start: cursor, payload: cursor + header, end: cursor + size, depth });
            cursor += size;
        }
        return answer;
    }
    const children = box => boxes(box.payload, box.end, box.depth + 1);
    function unique(list, type, required = false) {
        const matches = list.filter(box => box.type === type);
        if (matches.length > 1) fail(`Ambiguous duplicate ${type} box`);
        if (required && !matches.length) fail(`Missing ${type} box`);
        return matches[0];
    }
    function displayDimensions(tkhd) {
        if (!tkhd) return null;
        const payload = data.subarray(tkhd.payload, tkhd.end); need(payload, 4, 'tkhd');
        const version = payload[0], length = version === 0 ? 84 : version === 1 ? 96 : 0;
        if (!length) fail('Unsupported tkhd version');
        need(payload, length, 'tkhd');
        return { width: payload.readUInt32BE(length - 8) / 65536,
            height: payload.readUInt32BE(length - 4) / 65536,
            provenance: 'tkhd display dimensions; not encoded resolution' };
    }
    function entryChildren(entry, start, hevc) {
        try { return boxes(start, entry.end, entry.depth + 1); }
        catch (error) {
            // Apple's inspected hvc1 has four trailing zero bytes. This narrow
            // accommodation requires an independently valid HEVC child prefix.
            if (!(error instanceof Mp4MetadataError) || !hevc || entry.end - start < 12 ||
                !data.subarray(entry.end - 4, entry.end).equals(Buffer.alloc(4))) throw error;
            const parsed = boxes(start, entry.end - 4, entry.depth + 1);
            if (!parsed.some(child => child.type === 'hvcC')) throw error;
            result.warnings.push('HEVC sample entry contains four trailing zero padding bytes.');
            return parsed;
        }
    }
    function sampleEntry(entry, track, handler) {
        const payload = data.subarray(entry.payload, entry.end);
        const common = { sampleEntry: entry.type, sampleEntryOffset: absoluteOffset + entry.start,
            displayDimensions: track.displayDimensions };
        if (VIDEO.has(entry.type)) {
            if (handler !== null && handler !== 'vide') fail('Video sample entry conflicts with track handler');
            need(payload, 78, 'visual sample entry');
            const width = payload.readUInt16BE(24), height = payload.readUInt16BE(26);
            if (!width || !height) fail('Invalid visual sample-entry dimensions');
            const item = { ...common, type: 'video', codec: VIDEO.get(entry.type), width, height,
                dimensionsProvenance: 'stsd visual sample entry; not tkhd or HDMI output' };
            const exts = entryChildren(entry, entry.payload + 78, item.codec === 'hevc');
            const hvcc = unique(exts, 'hvcC'), avcc = unique(exts, 'avcC'), colr = unique(exts, 'colr');
            if (hvcc && item.codec !== 'hevc') fail('HEVC configuration conflicts with sample entry');
            if (avcc && item.codec !== 'h264') fail('AVC configuration conflicts with sample entry');
            if (hvcc) item.hevcConfiguration = parseHvcc(data.subarray(hvcc.payload, hvcc.end), limits.maxParameterSets);
            if (avcc) item.avcConfiguration = parseAvcc(data.subarray(avcc.payload, avcc.end), limits.maxParameterSets);
            if (item.codec === 'hevc' && !hvcc || item.codec === 'h264' && !avcc) result.warnings.push(`${entry.type} lacks its decoder configuration record.`);
            if (colr) {
                item.color = parseColor(data.subarray(colr.payload, colr.end));
                item.hdrSignalling = item.color.transfer === 16 ? 'PQ' : item.color.transfer === 18 ? 'HLG' : 'Not indicated by colr';
            }
            item.dolbyVisionSignalling = exts.some(ext => ['dvcC', 'dvvC'].includes(ext.type)) || ['dvhe', 'dvh1'].includes(entry.type);
            return item;
        }
        if (AUDIO.has(entry.type)) {
            if (handler !== null && handler !== 'soun') fail('Audio sample entry conflicts with track handler');
            need(payload, 28, 'audio sample entry');
            const item = { ...common, type: 'audio', codec: AUDIO.get(entry.type), channelCount: null,
                channelLayout: null, sampleEntryChannelCount: payload.readUInt16BE(16),
                channelCountProvenance: 'Unknown; generic sample-entry count is not Dolby layout proof' };
            const version = payload.readUInt16BE(8);
            if (version !== 0) {
                result.warnings.push('Unsupported audio sample-entry version; codec layout not inspected.'); return item;
            }
            const exts = entryChildren(entry, entry.payload + 28, false);
            const kind = item.codec === 'ac3' ? 'dac3' : item.codec === 'eac3' ? 'dec3' : null;
            const config = kind ? unique(exts, kind) : null;
            if (config) {
                item.audioConfiguration = (kind === 'dac3' ? parseDac3 : parseDec3)(data.subarray(config.payload, config.end));
                item.channelCount = item.audioConfiguration.channelCount;
                item.channelLayout = item.audioConfiguration.channelLayout;
                item.channelCountProvenance = item.channelCount === null ? 'Complex Dolby layout remains unverified' : `${kind} codec configuration`;
            } else result.warnings.push(`${entry.type} audio layout remains unverified.`);
            return item;
        }
        result.warnings.push(`Unsupported sample entry ${JSON.stringify(entry.type)}.`);
        return { ...common, type: handler === 'vide' ? 'video' : handler === 'soun' ? 'audio' : 'unknown', codec: 'unknown' };
    }
    for (const moov of boxes(0, data.length, 0, options.allowPartialMdat === true).filter(box => box.type === 'moov')) {
        if (++moovCount > 1) fail('Ambiguous duplicate moov box');
        const traks = children(moov).filter(box => box.type === 'trak');
        if (traks.length > limits.maxTracks) fail('MP4 track count exceeds inspection limit');
        for (const trak of traks) {
            const trakBoxes = children(trak), mdia = unique(trakBoxes, 'mdia');
            const track = { displayDimensions: displayDimensions(unique(trakBoxes, 'tkhd')) };
            if (!mdia) { result.warnings.push('Track lacks media metadata.'); continue; }
            const mediaBoxes = children(mdia), hdlr = unique(mediaBoxes, 'hdlr');
            let handler = null;
            if (hdlr) { need(data.subarray(hdlr.payload, hdlr.end), 12, 'hdlr'); handler = data.toString('latin1', hdlr.payload + 8, hdlr.payload + 12); }
            const minf = unique(mediaBoxes, 'minf');
            const stbl = minf ? unique(children(minf), 'stbl') : null;
            const stsd = stbl ? unique(children(stbl), 'stsd') : null;
            if (!stsd) { result.warnings.push('Track lacks sample descriptions.'); continue; }
            need(data.subarray(stsd.payload, stsd.end), 8, 'stsd');
            if (data.readUInt32BE(stsd.payload) !== 0) fail('Unsupported sample-description version or flags');
            const count = data.readUInt32BE(stsd.payload + 4);
            if (count > limits.maxEntries) fail('MP4 sample-description count exceeds inspection limit');
            const entries = boxes(stsd.payload + 8, stsd.end, stsd.depth + 1);
            if (entries.length !== count) fail('Sample-description count mismatch');
            for (const entry of entries) result.tracks.push(sampleEntry(entry, track, handler));
        }
    }
    result.complete = moovCount === 1;
    if (!moovCount) result.warnings.push('No complete moov metadata found in the inspected bytes.');
    return result;
}
module.exports = { parseMp4Metadata, inspectMp4: parseMp4Metadata, Mp4MetadataError };
