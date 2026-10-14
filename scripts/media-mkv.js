'use strict';

// Bounded metadata inspection only. No filesystem, network or media decoder.
// IDs follow Matroska's Segment/Tracks/TrackEntry/Video/Audio element hierarchy.
const MAX_BYTES = 16 * 1024 * 1024;
const MAX_ELEMENTS = 20000;
const IDS = {
  EBML: 0x1a45dfa3, DOC_TYPE: 0x4282, SEGMENT: 0x18538067,
  TRACKS: 0x1654ae6b, TRACK_ENTRY: 0xae, CLUSTER: 0x1f43b675,
  NUMBER: 0xd7, TYPE: 0x83, CODEC: 0x86, CODEC_PRIVATE: 0x63a2, ENABLED: 0xb9, DEFAULT: 0x88,
  VIDEO: 0xe0, WIDTH: 0xb0, HEIGHT: 0xba, DISPLAY_WIDTH: 0x54b0,
  DISPLAY_HEIGHT: 0x54ba, DISPLAY_UNIT: 0x54b2, COLOUR: 0x55b0,
  MATRIX: 0x55b1, BITS_PER_CHANNEL: 0x55b2, CHROMA_H: 0x55b3,
  CHROMA_V: 0x55b4, RANGE: 0x55b9, TRANSFER: 0x55ba,
  PRIMARIES: 0x55bb, MAX_CLL: 0x55bc, MAX_FALL: 0x55bd,
  AUDIO: 0xe1, SAMPLE_RATE: 0xb5, OUTPUT_RATE: 0x78b5,
  CHANNELS: 0x9f, AUDIO_DEPTH: 0x6264,
};

class MkvParseError extends Error {
  constructor(message, code = 'INVALID_MKV') {
    super(message);
    this.name = 'MkvParseError';
    this.code = code;
  }
}

function fail(message, code) { throw new MkvParseError(message, code); }

function readVint(data, offset, end, id = false) {
  if (!(Buffer.isBuffer(data) || data instanceof Uint8Array) || !Number.isInteger(offset)
      || !Number.isInteger(end) || offset < 0 || end > data.length || offset >= end) {
    fail('Incomplete EBML variable integer', 'TRUNCATED_METADATA');
  }
  const first = data[offset];
  if (!first) fail('Invalid zero-leading EBML variable integer');
  let marker = 0x80, length = 1;
  while (!(first & marker)) { marker >>= 1; length += 1; }
  if (length > (id ? 4 : 8)) fail('Unsupported EBML variable integer length');
  if (offset + length > end) fail('Incomplete EBML variable integer', 'TRUNCATED_METADATA');
  let value = BigInt(id ? first : first & (marker - 1));
  for (let index = 1; index < length; index += 1) {
    value = (value << 8n) | BigInt(data[offset + index]);
  }
  const unknown = !id && value === (1n << BigInt(7 * length)) - 1n;
  if (id) {
    const mask = (1n << BigInt(7 * length)) - 1n;
    if ((value & mask) === 0n || (value & mask) === mask) fail('Reserved EBML identifier');
  }
  if (!unknown && value > BigInt(Number.MAX_SAFE_INTEGER)) fail('EBML value exceeds safe numeric inspection', 'NUMERIC_LIMIT');
  return {value: unknown ? null : Number(value), length, unknown};
}

function unsigned(data, element, positive = false) {
  const size = element.end - element.payload;
  if (size < 1 || size > 8) fail('Invalid unsigned Matroska metadata integer');
  let value = 0n;
  for (let index = element.payload; index < element.end; index += 1) value = (value << 8n) | BigInt(data[index]);
  if (value > BigInt(Number.MAX_SAFE_INTEGER)) fail('Metadata integer exceeds safe numeric inspection', 'NUMERIC_LIMIT');
  const number = Number(value);
  if (positive && number === 0) fail('Required Matroska metadata value is zero');
  return number;
}

function frequency(data, element) {
  const size = element.end - element.payload;
  const value = size === 4 ? data.readFloatBE(element.payload) : size === 8 ? data.readDoubleBE(element.payload) : NaN;
  if (!Number.isFinite(value) || value <= 0) fail('Invalid audio sampling frequency');
  return value;
}

function ascii(data, element, maximum = 256) {
  const size = element.end - element.payload;
  if (size < 1 || size > maximum) fail('Invalid Matroska identifier length');
  const value = data.subarray(element.payload, element.end);
  if (value.some(byte => byte < 0x20 || byte > 0x7e)) fail('Invalid ASCII Matroska identifier');
  return value.toString('ascii');
}

function hevcConfiguration(bytes) {
  if (bytes.length < 23 || bytes.length > 1024 * 1024 || bytes[0] !== 1) fail('Incomplete or unsupported HEVC CodecPrivate', 'INCOMPLETE_TRACK');
  let cursor = 23, nalUnits = 0;
  const parameterArrays = [];
  for (let index = 0; index < bytes[22]; index += 1) {
    if (cursor + 3 > bytes.length) fail('Truncated HEVC parameter array', 'TRUNCATED_METADATA');
    const type = bytes[cursor] & 63;
    const count = bytes.readUInt16BE(cursor + 1);
    cursor += 3;
    nalUnits += count;
    if (nalUnits > 10000) fail('Too many HEVC parameter units', 'INSPECTION_LIMIT');
    for (let unit = 0; unit < count; unit += 1) {
      if (cursor + 2 > bytes.length) fail('Truncated HEVC parameter length', 'TRUNCATED_METADATA');
      const length = bytes.readUInt16BE(cursor);
      cursor += 2;
      if (!length || cursor + length > bytes.length) fail('Truncated HEVC parameter payload', 'TRUNCATED_METADATA');
      cursor += length;
    }
    parameterArrays.push({nalUnitType: type, count});
  }
  if (cursor !== bytes.length) fail('Unexpected trailing HEVC CodecPrivate bytes');
  const profileIdc = bytes[1] & 31;
  return {profileIdc, profile: ({1: 'Main', 2: 'Main 10'})[profileIdc] ?? 'Other / unverified',
    tier: bytes[1] & 32 ? 'High' : 'Main', tierFlag: (bytes[1] >> 5) & 1,
    levelIdc: bytes[12], level: bytes[12] / 30, chromaFormatIdc: bytes[16] & 3,
    chromaSubsampling: ['monochrome', '4:2:0', '4:2:2', '4:4:4'][bytes[16] & 3],
    bitDepthLuma: 8 + (bytes[17] & 7), bitDepthChroma: 8 + (bytes[18] & 7), parameterArrays};
}

function inspectMkv(input) {
  if (!(Buffer.isBuffer(input) || input instanceof Uint8Array)) fail('Expected a bounded byte buffer');
  const data = Buffer.isBuffer(input) ? input : Buffer.from(input.buffer, input.byteOffset, input.byteLength);
  if (!data.length || data.length > MAX_BYTES) fail('Inspection buffer is empty or exceeds 16 MiB', 'INSPECTION_LIMIT');
  let elementCount = 0;
  const warnings = [];

  function header(offset, end) {
    elementCount += 1;
    if (elementCount > MAX_ELEMENTS) fail('Too many metadata elements', 'INSPECTION_LIMIT');
    const id = readVint(data, offset, end, true);
    const size = readVint(data, offset + id.length, end);
    const payload = offset + id.length + size.length;
    return {id: id.value, beginning: offset, payload,
      unknown: size.unknown, size: size.value,
      end: size.unknown ? null : payload + size.value};
  }

  function children(start, end, visitor) {
    let cursor = start;
    while (cursor < end) {
      const element = header(cursor, end);
      if (element.unknown) fail('Unknown-sized nested metadata element is not supported', 'UNKNOWN_SIZE');
      if (!Number.isSafeInteger(element.end) || element.end > end) fail('Metadata element is truncated or exceeds its parent', 'TRUNCATED_METADATA');
      visitor(element);
      cursor = element.end;
    }
  }

  function collect(start, end, allowed) {
    const values = new Map();
    children(start, end, element => {
      if (!allowed.has(element.id)) return;
      if (values.has(element.id)) fail('Duplicate metadata element makes the source ambiguous');
      values.set(element.id, element);
    });
    return values;
  }

  function getUnsigned(values, id, positive = false) {
    return values.has(id) ? unsigned(data, values.get(id), positive) : null;
  }

  function parseColour(element) {
    const fields = new Map([
      [IDS.MATRIX, 'matrixCoefficients'], [IDS.BITS_PER_CHANNEL, 'bitsPerChannel'],
      [IDS.CHROMA_H, 'chromaSubsamplingHorizontal'], [IDS.CHROMA_V, 'chromaSubsamplingVertical'],
      [IDS.RANGE, 'range'], [IDS.TRANSFER, 'transferCharacteristics'],
      [IDS.PRIMARIES, 'primaries'], [IDS.MAX_CLL, 'maxCLL'], [IDS.MAX_FALL, 'maxFALL'],
    ]);
    const values = collect(element.payload, element.end, new Set(fields.keys()));
    const result = {};
    for (const [id, name] of fields) {
      if (values.has(id)) result[name] = getUnsigned(values, id);
    }
    // Zero explicitly means unspecified, and does not establish 8/10-bit video.
    if (result.bitsPerChannel === 0) result.bitsPerChannel = null;
    return result;
  }

  function parseVideo(element) {
    const values = collect(element.payload, element.end, new Set([
      IDS.WIDTH, IDS.HEIGHT, IDS.DISPLAY_WIDTH, IDS.DISPLAY_HEIGHT, IDS.DISPLAY_UNIT, IDS.COLOUR,
    ]));
    const width = getUnsigned(values, IDS.WIDTH, true);
    const height = getUnsigned(values, IDS.HEIGHT, true);
    if (width === null || height === null) fail('Video metadata lacks encoded pixel dimensions', 'INCOMPLETE_TRACK');
    const displayUnit = getUnsigned(values, IDS.DISPLAY_UNIT) ?? 0;
    const colour = values.has(IDS.COLOUR) ? parseColour(values.get(IDS.COLOUR)) : null;
    return {width, height, displayWidth: getUnsigned(values, IDS.DISPLAY_WIDTH, true),
      displayHeight: getUnsigned(values, IDS.DISPLAY_HEIGHT, true), displayUnit,
      displayDimensionsArePixels: displayUnit === 0,
      bitDepth: colour?.bitsPerChannel ?? null, colour};
  }

  function parseAudio(element) {
    const values = collect(element.payload, element.end, new Set([
      IDS.SAMPLE_RATE, IDS.OUTPUT_RATE, IDS.CHANNELS, IDS.AUDIO_DEPTH,
    ]));
    return {channels: getUnsigned(values, IDS.CHANNELS, true),
      channelsDeclared: values.has(IDS.CHANNELS),
      sampleRateHz: values.has(IDS.SAMPLE_RATE) ? frequency(data, values.get(IDS.SAMPLE_RATE)) : null,
      outputSampleRateHz: values.has(IDS.OUTPUT_RATE) ? frequency(data, values.get(IDS.OUTPUT_RATE)) : null,
      bitDepth: getUnsigned(values, IDS.AUDIO_DEPTH, true)};
  }

  function parseTrack(element) {
    const values = collect(element.payload, element.end, new Set([
      IDS.NUMBER, IDS.TYPE, IDS.CODEC, IDS.CODEC_PRIVATE, IDS.ENABLED, IDS.DEFAULT, IDS.VIDEO, IDS.AUDIO,
    ]));
    const number = getUnsigned(values, IDS.NUMBER, true);
    const typeId = getUnsigned(values, IDS.TYPE, true);
    if (number === null || typeId === null || !values.has(IDS.CODEC)) fail('Track metadata lacks number, type or codec', 'INCOMPLETE_TRACK');
    const codecId = ascii(data, values.get(IDS.CODEC));
    const enabled = getUnsigned(values, IDS.ENABLED) ?? 1;
    const defaultFlag = getUnsigned(values, IDS.DEFAULT) ?? 1;
    if (![0, 1].includes(enabled) || ![0, 1].includes(defaultFlag)) fail('Invalid Track enabled/default flag');
    const result = {number, typeId, type: ({1: 'video', 2: 'audio', 17: 'subtitle'})[typeId] ?? 'other', codecId,
      enabled: enabled === 1, default: defaultFlag === 1};
    if (typeId === 1) {
      if (!values.has(IDS.VIDEO) || values.has(IDS.AUDIO)) fail('Video track lacks an unambiguous Video element', 'INCOMPLETE_TRACK');
      Object.assign(result, parseVideo(values.get(IDS.VIDEO)));
      if (codecId === 'V_MPEGH/ISO/HEVC' && values.has(IDS.CODEC_PRIVATE)) {
        const item = values.get(IDS.CODEC_PRIVATE);
        result.hevcConfiguration = hevcConfiguration(data.subarray(item.payload, item.end));
        const depth = result.hevcConfiguration.bitDepthLuma;
        if (result.bitDepth !== null && result.bitDepth !== depth) {
          warnings.push('Video Colour bit depth disagrees with HEVC CodecPrivate; bit depth remains unverified.');
          result.bitDepth = null;
        } else result.bitDepth = depth;
      }
    } else if (typeId === 2) {
      if (!values.has(IDS.AUDIO) || values.has(IDS.VIDEO)) fail('Audio track lacks an unambiguous Audio element', 'INCOMPLETE_TRACK');
      result.audio = parseAudio(values.get(IDS.AUDIO));
    }
    return result;
  }

  const ebml = header(0, data.length);
  if (ebml.id !== IDS.EBML || ebml.unknown) fail('Missing finite EBML header');
  if (ebml.end > data.length) fail('Truncated EBML header', 'TRUNCATED_METADATA');
  const document = collect(ebml.payload, ebml.end, new Set([IDS.DOC_TYPE]));
  if (!document.has(IDS.DOC_TYPE)) fail('Missing Matroska document type');
  const documentType = ascii(data, document.get(IDS.DOC_TYPE), 32);
  if (!['matroska', 'webm'].includes(documentType)) fail('Unsupported EBML document type');

  let cursor = ebml.end, segment = null;
  while (cursor < data.length) {
    const element = header(cursor, data.length);
    if (element.id === IDS.SEGMENT) { segment = element; break; }
    if (element.unknown) fail('Unknown-sized top-level element before Segment', 'UNKNOWN_SIZE');
    if (element.end > data.length) fail('Truncated element before Segment', 'TRUNCATED_METADATA');
    cursor = element.end;
  }
  if (!segment) fail('No Segment in inspected bytes', 'TRUNCATED_METADATA');
  if (segment.end !== null && !Number.isSafeInteger(segment.end)) fail('Segment end exceeds numeric inspection limits', 'NUMERIC_LIMIT');
  const segmentEnd = Math.min(segment.end ?? data.length, data.length);
  let tracks = null, stoppedAtCluster = false, clusterHeaderComplete = null;
  cursor = segment.payload;
  while (cursor < segmentEnd) {
    // Cluster payload is never inspected. A truncated first cluster still
    // leaves an earlier complete Tracks element usable as metadata evidence.
    const id = readVint(data, cursor, segmentEnd, true);
    if (id.value === IDS.CLUSTER) {
      stoppedAtCluster = true;
      try { readVint(data, cursor + id.length, segmentEnd); clusterHeaderComplete = true; }
      catch (error) {
        if (!(error instanceof MkvParseError) || error.code !== 'TRUNCATED_METADATA') throw error;
        clusterHeaderComplete = false;
      }
      break;
    }
    const element = header(cursor, segmentEnd);
    if (element.unknown) fail('Unknown-sized Segment child is not a supported master', 'UNKNOWN_SIZE');
    if (!Number.isSafeInteger(element.end)) fail('Segment child end exceeds numeric inspection limits', 'NUMERIC_LIMIT');
    if (element.end > segmentEnd) {
      if (element.id === IDS.TRACKS) fail('Tracks element exceeds inspected prefix', 'TRUNCATED_METADATA');
      warnings.push('Inspected prefix ends before a complete Segment child.');
      break;
    }
    if (element.id === IDS.TRACKS) {
      if (tracks !== null) fail('Multiple Tracks elements make metadata ambiguous');
      tracks = [];
      children(element.payload, element.end, child => {
        if (child.id === IDS.TRACK_ENTRY) tracks.push(parseTrack(child));
      });
      const numbers = tracks.map(track => track.number);
      if (new Set(numbers).size !== numbers.length) fail('Duplicate track numbers');
    }
    cursor = element.end;
  }
  if (!tracks?.length) warnings.push('No complete Tracks metadata was present before media data or the inspection limit.');
  if (tracks?.filter(track => track.type === 'video' && track.enabled).length > 1) {
    warnings.push('Multiple enabled video tracks: metadata does not establish which the Roku player selects.');
  }
  return {container: documentType === 'webm' ? 'webm' : 'mkv', documentType,
    tracks: tracks ?? [], metadataComplete: Boolean(tracks?.length),
    fileComplete: !segment.unknown && segment.end <= data.length && !stoppedAtCluster && cursor === segmentEnd,
    stoppedAtCluster, clusterHeaderComplete, inspectionBytes: data.length, warnings,
    evidence: 'Encoded track dimensions and codec/audio declarations from validated Matroska Tracks metadata.',
    notVerified: 'No media frames decoded. Metadata does not prove an original 4K master, absence of prior upscaling, Roku playback, HDR negotiation, surround output or sustained delivery.'};
}

module.exports = {inspectMkv, MkvParseError, readVint, hevcConfiguration, MAX_BYTES};
