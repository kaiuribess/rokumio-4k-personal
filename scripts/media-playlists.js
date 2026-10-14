'use strict';

// Metadata only: no network or media playback. URLs are internal probe inputs;
// only `summary` and constant error codes are suitable for a saved report.
const sax = require('sax');
const LIMITS = Object.freeze({ bytes: 512 * 1024, lines: 8192, lineLength: 16384, nodes: 8192, depth: 48, variants: 128, audio: 128 });
const DASH_NS = 'urn:mpeg:dash:schema:mpd:2011';
const fail = code => { const error = new Error(code); error.playlistCode = code; throw error; };

function boundedText(text) {
    if (typeof text !== 'string' || !text.length) fail('empty_playlist');
    if (Buffer.byteLength(text, 'utf8') > LIMITS.bytes) fail('playlist_too_large');
    if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffd]/u.test(text)) fail('invalid_playlist_text');
    for (let at = 0; at < text.length; at++) {
        const code = text.charCodeAt(at);
        if (code >= 0xd800 && code <= 0xdbff) {
            const next = text.charCodeAt(++at);
            if (!(next >= 0xdc00 && next <= 0xdfff)) fail('invalid_playlist_text');
        } else if (code >= 0xdc00 && code <= 0xdfff) fail('invalid_playlist_text');
    }
    return text;
}

function resolveHttpUri(value, base) {
    if (typeof value !== 'string' || !value || /[\s\\\u0000-\u001f\u007f]/u.test(value)) fail('invalid_playlist_uri');
    const url = new URL(value, base);
    if (!['https:', 'http:'].includes(url.protocol) || !url.hostname || url.username || url.password || url.hash) fail('unsupported_playlist_uri');
    return url.href;
}

function uint(value, positive = false) {
    if (value == null) return null;
    if (!/^\d+$/.test(value)) fail('invalid_numeric_attribute');
    const number = Number(value);
    if (!Number.isSafeInteger(number) || (positive && number === 0)) fail('invalid_numeric_attribute');
    return number;
}

function rangeLength(value) {
    const match = /^(\d+)(?:@(\d+))?$/.exec(value);
    if (!match) fail('invalid_byte_range');
    const range = { length: uint(match[1], true), offset: match[2] == null ? null : uint(match[2]) };
    if (range.offset != null && range.length - 1 > Number.MAX_SAFE_INTEGER - range.offset) fail('invalid_byte_range');
    return range;
}

function rangeInclusive(value) {
    if (value == null) return null;
    const match = /^(\d+)-(\d+)$/.exec(value);
    if (!match) fail('invalid_byte_range');
    const offset = uint(match[1]), end = uint(match[2]);
    if (end < offset || !Number.isSafeInteger(end - offset + 1)) fail('invalid_byte_range');
    return { offset, length: end - offset + 1 };
}

// RFC 8216 attribute lists: quoted commas are data, duplicate attributes and
// unterminated/empty values are rejected. Quoted strings do not use escapes.
function hlsAttributes(text) {
    const attrs = Object.create(null);
    const quoted = new Set();
    let at = 0;
    while (at < text.length) {
        const start = at;
        while (at < text.length && /[A-Z0-9-]/.test(text[at])) at++;
        const name = text.slice(start, at);
        if (!name || text[at++] !== '=' || Object.hasOwn(attrs, name)) fail('invalid_hls_attributes');
        let value;
        if (text[at] === '"') {
            quoted.add(name); at++;
            const begin = at;
            while (at < text.length && text[at] !== '"') at++;
            if (at === text.length) fail('invalid_hls_attributes');
            value = text.slice(begin, at++);
        } else {
            const begin = at;
            while (at < text.length && text[at] !== ',') at++;
            value = text.slice(begin, at);
            if (/\s|"/.test(value)) fail('invalid_hls_attributes');
        }
        if (!value) fail('invalid_hls_attributes');
        attrs[name] = value;
        if (at < text.length && text[at++] !== ',') fail('invalid_hls_attributes');
        if (at === text.length && text[at - 1] === ',') fail('invalid_hls_attributes');
    }
    if (!at) fail('invalid_hls_attributes');
    return { attrs, quoted };
}

function summary(format, kind, variants, audio, encrypted = false) {
    const resolutions = [...new Map(variants.filter(v => v.width && v.height).map(v => [v.width + 'x' + v.height, { width: v.width, height: v.height }])).values()];
    const has2160 = resolutions.some(r => r.height === 2160), has1080 = resolutions.some(r => r.height === 1080);
    return { format, kind, basis: 'playlist-metadata', variantCount: variants.length, audioCount: audio.length,
        declaredResolutions: resolutions, has2160, has1080, mixed1080And2160: has2160 && has1080,
        encrypted, guaranteed2160Playback: false, sampleEntryVerified: false };
}

function invalidResult(format, error) {
    return { ok: false, format, kind: 'unknown', error: error.playlistCode || 'invalid_playlist', variants: [], audio: [], initializations: [],
        summary: summary(format, 'unknown', [], []) };
}

function parseHlsManifest(text, finalManifestUrl) {
    try {
        boundedText(text);
        const base = resolveHttpUri(finalManifestUrl);
        const lines = text.split('\n').map(line => line.endsWith('\r') ? line.slice(0, -1) : line);
        if (lines.length > LIMITS.lines || lines.some(line => line.length > LIMITS.lineLength || line.includes('\r'))) fail('playlist_limits_exceeded');
        if (lines[0] !== '#EXTM3U') fail('invalid_hls_header');
        const variants = [], audio = [], initializations = [];
        let pendingVariant = null, pendingSegment = false, pendingRange = null, previousSegment = null;
        let master = false, media = false, encrypted = false, currentEncryption = false, versionSeen = false, segmentCount = 0, trickPlayOnly = false;
        for (const line of lines.slice(1)) {
            if (!line) continue;
            if (line.startsWith('#EXT-X-STREAM-INF:')) {
                if (pendingVariant) fail('missing_variant_uri');
                master = true;
                const { attrs: a, quoted } = hlsAttributes(line.slice(18));
                if (a.CODECS && !quoted.has('CODECS')) fail('invalid_hls_attributes');
                if (a.AUDIO && !quoted.has('AUDIO')) fail('invalid_hls_attributes');
                let width = null, height = null;
                if (a.RESOLUTION) {
                    const dimensions = /^(\d+)x(\d+)$/.exec(a.RESOLUTION);
                    if (!dimensions) fail('invalid_hls_resolution');
                    width = uint(dimensions[1], true); height = uint(dimensions[2], true);
                }
                if (a['VIDEO-RANGE'] && !['SDR', 'PQ', 'HLG'].includes(a['VIDEO-RANGE'])) fail('invalid_hls_video_range');
                pendingVariant = { width, height, bandwidth: uint(a.BANDWIDTH, true), codecs: a.CODECS || '', videoRange: a['VIDEO-RANGE'] || '', audioGroup: a.AUDIO || '', url: null };
                if (pendingVariant.bandwidth == null) fail('missing_hls_bandwidth');
            } else if (line.startsWith('#EXT-X-MEDIA:')) {
                master = true;
                const { attrs: a, quoted } = hlsAttributes(line.slice(13));
                if (!a.TYPE || !a['GROUP-ID'] || !a.NAME || !quoted.has('GROUP-ID') || !quoted.has('NAME')) fail('invalid_hls_audio');
                if (!['AUDIO', 'VIDEO', 'SUBTITLES', 'CLOSED-CAPTIONS'].includes(a.TYPE)) fail('invalid_hls_audio');
                for (const key of ['DEFAULT', 'AUTOSELECT', 'FORCED']) if (a[key] && !['YES', 'NO'].includes(a[key])) fail('invalid_hls_audio');
                if (a.TYPE === 'AUDIO') {
                    if (a.URI && !quoted.has('URI')) fail('invalid_hls_audio');
                    if (audio.length >= LIMITS.audio) fail('playlist_limits_exceeded');
                    audio.push({ groupId: a['GROUP-ID'], name: a.NAME, language: a.LANGUAGE || '', channels: a.CHANNELS || '',
                        channelCount: a.CHANNELS ? uint(a.CHANNELS.split('/')[0], true) : null,
                        default: a.DEFAULT === 'YES', autoselect: a.AUTOSELECT === 'YES', url: a.URI ? resolveHttpUri(a.URI, base) : null });
                }
            } else if (line.startsWith('#EXT-X-MAP:')) {
                media = true;
                const { attrs: a, quoted } = hlsAttributes(line.slice(11));
                if (!a.URI || !quoted.has('URI') || (a.BYTERANGE && !quoted.has('BYTERANGE'))) fail('invalid_hls_map');
                const url = resolveHttpUri(a.URI, base);
                const byteRange = a.BYTERANGE ? rangeLength(a.BYTERANGE) : null;
                // An omitted offset refers to a preceding ranged media segment,
                // never an invented offset zero or a previous initialization.
                if (byteRange && byteRange.offset == null && previousSegment && previousSegment.url === url && previousSegment.byteRange) {
                    byteRange.offset = previousSegment.byteRange.offset + previousSegment.byteRange.length;
                    if (!Number.isSafeInteger(byteRange.offset)) fail('invalid_byte_range');
                }
                const rangeUnknown = !!(byteRange && byteRange.offset == null);
                if (byteRange && !rangeUnknown && byteRange.length - 1 > Number.MAX_SAFE_INTEGER - byteRange.offset) fail('invalid_byte_range');
                if (initializations.length >= LIMITS.variants) fail('playlist_limits_exceeded');
                initializations.push({ url, byteRange, rangeUnknown, encrypted: currentEncryption, probeable: !rangeUnknown && !currentEncryption });
            } else if (line.startsWith('#EXT-X-BYTERANGE:')) {
                media = true;
                if (pendingRange) fail('invalid_byte_range');
                pendingRange = rangeLength(line.slice(17));
            } else if (line.startsWith('#EXTINF:')) {
                media = true;
                if (pendingSegment) fail('missing_segment_uri');
                const duration = line.slice(8).split(',')[0];
                if (!/^\d+(?:\.\d+)?$/.test(duration) || !Number.isFinite(Number(duration))) fail('invalid_hls_duration');
                pendingSegment = true;
            } else if (line.startsWith('#EXT-X-KEY:')) {
                media = true;
                const { attrs: a } = hlsAttributes(line.slice(11));
                if (!a.METHOD) fail('invalid_hls_key');
                currentEncryption = a.METHOD !== 'NONE';
                encrypted ||= currentEncryption;
            } else if (line.startsWith('#EXT-X-VERSION:')) {
                if (versionSeen) fail('duplicate_hls_version');
                uint(line.slice(15), true); versionSeen = true;
            } else if (line === '#EXT-X-I-FRAMES-ONLY') {
                media = true; trickPlayOnly = true;
            } else if (/^#EXT-X-(TARGETDURATION|MEDIA-SEQUENCE|DISCONTINUITY-SEQUENCE|ENDLIST|PLAYLIST-TYPE|I-FRAMES-ONLY)(:|$)/.test(line)) {
                media = true;
            } else if (line.startsWith('#EXT-X-I-FRAME-STREAM-INF:')) {
                master = true; // Trick-play images are not full video variants.
                hlsAttributes(line.slice(26));
            } else if (line.startsWith('#EXT-X-SESSION-DATA:') || line.startsWith('#EXT-X-SESSION-KEY:')) {
                master = true;
            } else if (line.startsWith('#EXT-X-DEFINE:')) {
                fail('hls_variable_substitution_not_supported');
            } else if (!line.startsWith('#')) {
                const url = resolveHttpUri(line, base);
                if (pendingVariant) {
                    if (variants.length >= LIMITS.variants) fail('playlist_limits_exceeded');
                    variants.push({ ...pendingVariant, url }); pendingVariant = null;
                } else {
                    media = true;
                    if (!pendingSegment) fail('missing_hls_segment_duration');
                    if (pendingRange && pendingRange.offset == null) {
                        if (!previousSegment || previousSegment.url !== url || !previousSegment.byteRange) fail('unknown_segment_byte_range');
                        pendingRange.offset = previousSegment.byteRange.offset + previousSegment.byteRange.length;
                        if (!Number.isSafeInteger(pendingRange.offset)) fail('invalid_byte_range');
                    }
                    if (pendingRange && pendingRange.length - 1 > Number.MAX_SAFE_INTEGER - pendingRange.offset) fail('invalid_byte_range');
                    previousSegment = { url, byteRange: pendingRange };
                    segmentCount++; pendingSegment = false; pendingRange = null;
                }
            }
        }
        if (pendingVariant || pendingSegment || pendingRange) fail('truncated_hls_playlist');
        if (master && media) fail('mixed_hls_playlist_types');
        const kind = master ? 'master' : media ? 'media' : 'unknown';
        if (kind === 'unknown') fail('empty_hls_playlist');
        if (trickPlayOnly) for (const init of initializations) init.probeable = false;
        return { ok: true, format: 'hls', kind, variants, audio, initializations, segmentCount,
            summary: { ...summary('hls', kind, variants, audio, encrypted), trickPlayOnly } };
    } catch (error) { return invalidResult('hls', error); }
}

function xmlTree(text) {
    const parser = sax.parser(true, { xmlns: true, strictEntities: true });
    let root = null, count = 0, attributeNames = new Set(); const stack = [];
    parser.ondoctype = () => fail('xml_doctype_not_supported');
    parser.onerror = () => fail('invalid_xml');
    parser.onopentagstart = () => { attributeNames = new Set(); };
    parser.onattribute = attribute => {
        // sax is strict about syntax but silently overwrites duplicate attrs;
        // reject duplicate expanded XML names before its final tag object.
        const name = (attribute.uri || '') + '|' + (attribute.local || attribute.name);
        if (attributeNames.has(name)) fail('duplicate_xml_attribute');
        if (attributeNames.size >= 128 || attribute.value.length > LIMITS.lineLength) fail('playlist_limits_exceeded');
        attributeNames.add(name);
    };
    parser.onopentag = tag => {
        if (++count > LIMITS.nodes || stack.length >= LIMITS.depth) fail('playlist_limits_exceeded');
        const node = { name: tag.local, namespace: tag.uri, attrs: Object.create(null), children: [], text: '', unsupportedBase: false };
        for (const attr of Object.values(tag.attributes)) {
            if (!attr.uri) node.attrs[attr.local] = attr.value;
            if ((attr.uri === 'http://www.w3.org/XML/1998/namespace' && attr.local === 'base') ||
                (attr.uri === 'http://www.w3.org/1999/xlink' && attr.local === 'href')) node.unsupportedBase = true;
        }
        if (stack.length) stack.at(-1).children.push(node); else if (!root) root = node; else fail('multiple_xml_roots');
        stack.push(node);
    };
    const append = text => { if (stack.length) stack.at(-1).text += text; };
    parser.ontext = append; parser.oncdata = append;
    parser.onclosetag = () => stack.pop();
    parser.write(text).close();
    if (!root || stack.length) fail('truncated_xml');
    return root;
}

function children(node, name) { return node.children.filter(child => child.name === name && child.namespace === node.namespace); }

function dashBase(scopes, manifest) {
    let url = manifest, explicit = false;
    for (const scope of scopes) {
        if (scope.unsupportedBase) return { reason: 'xml_base_or_xlink_not_supported' };
        const bases = children(scope, 'BaseURL');
        if (bases.length > 1) return { reason: 'multiple_base_urls' };
        if (bases.length) {
            if (bases[0].unsupportedBase || bases[0].children.length) return { reason: 'complex_base_url_not_supported' };
            url = resolveHttpUri(bases[0].text.trim(), url); explicit = true;
        }
    }
    return { url, explicit };
}

function expandInitialization(template, attrs) {
    let value = '';
    for (let at = 0; at < template.length;) {
        if (template[at] !== '$') { value += template[at++]; continue; }
        if (template[at + 1] === '$') { value += '$'; at += 2; continue; }
        const end = template.indexOf('$', at + 1);
        if (end < 0) return null;
        const name = template.slice(at + 1, end);
        if (name === 'RepresentationID' && attrs.id) value += attrs.id;
        else if (name === 'Bandwidth' && attrs.bandwidth != null) value += attrs.bandwidth;
        else return null; // Number/Time/formatted/unknown templates stay unknown.
        at = end + 1;
    }
    return value;
}

function dashInitialization(scopes, attrs, base) {
    if (base.reason) return { initialization: null, reason: base.reason };
    let mode = null, spec = null, init = null;
    for (const scope of scopes) {
        const addressing = scope.children.filter(node => node.namespace === scope.namespace && ['SegmentTemplate', 'SegmentBase', 'SegmentList'].includes(node.name));
        if (addressing.length > 1) return { initialization: null, reason: 'ambiguous_segment_addressing' };
        if (!addressing.length) continue;
        const node = addressing[0];
        if (node.unsupportedBase) return { initialization: null, reason: 'xml_base_or_xlink_not_supported' };
        if (mode !== node.name) { spec = {}; init = null; }
        mode = node.name; Object.assign(spec, node.attrs);
        const inits = children(node, 'Initialization');
        if (inits.length > 1) return { initialization: null, reason: 'ambiguous_initialization' };
        if (inits.length) {
            if (inits[0].unsupportedBase) return { initialization: null, reason: 'xml_base_or_xlink_not_supported' };
            init = inits[0].attrs;
        }
    }
    if (mode === 'SegmentTemplate' && spec.initialization) {
        const expanded = expandInitialization(spec.initialization, attrs);
        if (expanded == null) return { initialization: null, reason: 'unresolved_initialization_template' };
        return { initialization: { url: resolveHttpUri(expanded, base.url), byteRange: null, probeable: true }, reason: null };
    }
    if (mode === 'SegmentBase' && init) {
        if (!init.sourceURL && !base.explicit) return { initialization: null, reason: 'missing_initialization_url' };
        return { initialization: { url: init.sourceURL ? resolveHttpUri(init.sourceURL, base.url) : base.url,
            byteRange: rangeInclusive(init.range), probeable: true }, reason: null };
    }
    return { initialization: null, reason: mode === 'SegmentList' ? 'segment_list_not_supported' : 'missing_initialization' };
}

function parseDashManifest(text, finalManifestUrl) {
    try {
        boundedText(text);
        const manifest = resolveHttpUri(finalManifestUrl), root = xmlTree(text);
        if (root.name !== 'MPD' || (root.namespace && root.namespace !== DASH_NS)) fail('invalid_dash_root');
        const variants = [], audio = [], initializations = []; let encrypted = false;
        const periods = children(root, 'Period');
        if (!periods.length) fail('missing_dash_period');
        for (let periodIndex = 0; periodIndex < periods.length; periodIndex++) {
            const period = periods[periodIndex];
            for (const adaptation of children(period, 'AdaptationSet')) {
                for (const representation of children(adaptation, 'Representation')) {
                    const scopes = [root, period, adaptation, representation];
                    const attrs = { ...adaptation.attrs, ...representation.attrs,
                        id: representation.attrs.id, bandwidth: representation.attrs.bandwidth };
                    const codecs = attrs.codecs || '', mimeType = attrs.mimeType || '';
                    const contentType = attrs.contentType || (mimeType.startsWith('video/') ? 'video' : mimeType.startsWith('audio/') ? 'audio' : '');
                    const width = uint(attrs.width, true), height = uint(attrs.height, true), bandwidth = uint(attrs.bandwidth, true);
                    const isVideo = contentType === 'video' || (!contentType && (width || height || /^(avc[13]|hev1|hvc1|vp09|av01)(\.|,|$)/.test(codecs)));
                    const isAudio = contentType === 'audio' || (!contentType && /^(mp4a|ac-3|ec-3|opus|flac)(\.|,|$)/.test(codecs));
                    if (!isVideo && !isAudio) continue;
                    encrypted ||= scopes.some(node => children(node, 'ContentProtection').length > 0);
                    const base = dashBase(scopes, manifest);
                    const resolved = attrs.dependencyId ? { initialization: null, reason: 'dependent_representation' } : dashInitialization(scopes, attrs, base);
                    const item = { id: attrs.id || '', periodIndex, width, height, bandwidth, codecs, mimeType,
                        language: attrs.lang || '', initialization: resolved.initialization, initializationUnknownReason: resolved.reason };
                    const list = isVideo ? variants : audio;
                    if (list.length >= (isVideo ? LIMITS.variants : LIMITS.audio)) fail('playlist_limits_exceeded');
                    list.push(item);
                    if (item.initialization && !initializations.some(init => init.url === item.initialization.url && JSON.stringify(init.byteRange) === JSON.stringify(item.initialization.byteRange))) initializations.push(item.initialization);
                }
            }
        }
        if (!variants.length && !audio.length) fail('missing_dash_representations');
        return { ok: true, format: 'dash', kind: 'mpd', variants, audio, initializations,
            summary: summary('dash', 'mpd', variants, audio, encrypted) };
    } catch (error) { return invalidResult('dash', error); }
}

module.exports = { LIMITS, parseHlsManifest, parseDashManifest };
