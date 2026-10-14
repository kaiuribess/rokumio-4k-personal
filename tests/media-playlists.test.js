'use strict';
const assert = require('node:assert/strict');
const { LIMITS, parseHlsManifest, parseDashManifest } = require('../scripts/media-playlists');
let checks = 0;
function check(condition, label) { checks++; assert.ok(condition, label); }
const base = 'https://media.example/private-path/movie/index.m3u8?token=fixture-secret';
const master = parseHlsManifest(`#EXTM3U
#EXT-X-VERSION:7
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="surround",NAME="English, 5.1",LANGUAGE="en",CHANNELS="6/JOC",DEFAULT=YES,AUTOSELECT=YES,URI="audio/main.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=1920x1080,CODECS="avc1.640028,ec-3",AUDIO="surround",VIDEO-RANGE=SDR
1080/main.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=20000000,RESOLUTION=3840x2160,CODECS="hvc1.2.4.L153.B0,ec-3",AUDIO="surround",VIDEO-RANGE=PQ
../2160/main.m3u8?sig=fixture-other
#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=200000,RESOLUTION=7680x4320,URI="preview.m3u8"
`, base);
check(master.ok && master.kind === 'master', 'master playlist parsed');
check(master.variants.length === 2, 'iframe-only preview excluded from normal variants');
check(master.variants[1].url === 'https://media.example/private-path/2160/main.m3u8?sig=fixture-other', 'relative variant URL uses final manifest base');
check(master.audio[0].name === 'English, 5.1' && master.audio[0].channelCount === 6, 'quoted comma and audio channel declaration retained');
check(master.variants[1].codecs.includes('hvc1') && master.variants[1].videoRange === 'PQ', 'codec and video range metadata retained');
check(master.summary.mixed1080And2160 && !master.summary.guaranteed2160Playback && !master.summary.sampleEntryVerified, 'mixed adaptive declarations are not a playback guarantee');
check(!JSON.stringify(master.summary).includes('fixture') && !JSON.stringify(master.summary).includes('http'), 'safe summary excludes private URL content');

const media = parseHlsManifest(`#EXTM3U
#EXT-X-VERSION:7
#EXT-X-TARGETDURATION:6
#EXT-X-MAP:URI="../movie.mp4?sig=fixture",BYTERANGE="1000@200"
#EXTINF:6,
#EXT-X-BYTERANGE:400@1200
../movie.mp4?sig=fixture
#EXT-X-MAP:URI="../movie.mp4?sig=fixture",BYTERANGE="200"
#EXTINF:6,
#EXT-X-BYTERANGE:400
../movie.mp4?sig=fixture
#EXT-X-ENDLIST
`, base);
check(media.ok && media.initializations[0].byteRange.offset === 200, 'explicit initialization range parsed');
check(media.initializations[1].byteRange.offset === 1600 && media.initializations[1].probeable, 'implicit map range derives from previous same-resource media segment');
const unknownMap = parseHlsManifest('#EXTM3U\n#EXT-X-MAP:URI="movie.mp4",BYTERANGE="200"\n#EXTINF:6,\nsegment.m4s\n', base);
check(unknownMap.ok && unknownMap.initializations[0].rangeUnknown && !unknownMap.initializations[0].probeable, 'missing range origin stays unknown instead of guessed zero');
const encrypted = parseHlsManifest('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x0000\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:6,\nsegment.m4s\n', base);
check(encrypted.ok && encrypted.summary.encrypted && !encrypted.initializations[0].probeable, 'encrypted initialization is not offered for an unencrypted sample-entry probe');
for (const text of [
    '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=3840x2160\n',
    '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,BANDWIDTH=2\na.m3u8\n',
    '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS="hvc1\na.m3u8\n',
    '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=4kx2160\na.m3u8\n',
    '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\na.m3u8\n#EXTINF:6,\na.ts\n',
    '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-VERSION:4\n#EXTINF:6,\na.ts\n',
    '#EXTM3U\n#EXT-X-BYTERANGE:10\n#EXTINF:6,\na.ts\n',
    '#EXTM3U\n#EXT-X-DEFINE:NAME="secret",VALUE="private"\n#EXTINF:6,\na.ts\n',
    '\ufeff#EXTM3U\n#EXTINF:6,\na.ts\n'
]) check(!parseHlsManifest(text, base).ok, 'malformed, truncated or unsupported HLS fails safely');
check(!parseHlsManifest('#EXTM3U\n' + 'x'.repeat(LIMITS.bytes), base).ok, 'HLS byte bound enforced');
check(!parseHlsManifest('#EXTM3U\n#EXTINF:6,\nx\ud800.ts\n', base).ok, 'invalid Unicode is not silently converted in a resource URL');
check(!parseHlsManifest('#EXTM3U\n#EXT-X-MAP:URI="init.mp4",BYTERANGE="2@9007199254740991"\n#EXTINF:6,\na.ts\n', base).ok, 'range end cannot overflow safe integers');
const trickPlay = parseHlsManifest('#EXTM3U\n#EXT-X-I-FRAMES-ONLY\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:6,\na.m4s\n', base);
check(trickPlay.ok && trickPlay.summary.trickPlayOnly && !trickPlay.initializations[0].probeable, 'direct trick-play playlist cannot masquerade as the normal movie probe');

const mpd = inner => `<MPD xmlns="urn:mpeg:dash:schema:mpd:2011">${inner}</MPD>`;
const dash = parseDashManifest(mpd(`<BaseURL>https://cdn.example/signed-path/</BaseURL><Period><AdaptationSet mimeType="video/mp4" width="1920" height="1080" codecs="avc1.640028"><SegmentTemplate initialization="$RepresentationID$/$Bandwidth$/init.mp4"/><Representation id="hd" bandwidth="8000000"/><Representation id="uhd" bandwidth="20000000" width="3840" height="2160" codecs="hvc1.2.4.L153.B0"><BaseURL>private/</BaseURL></Representation></AdaptationSet><AdaptationSet mimeType="audio/mp4" codecs="ec-3" lang="en"><SegmentTemplate initialization="audio-$RepresentationID$.mp4"/><Representation id="en51" bandwidth="640000"/></AdaptationSet></Period>`), base.replace('m3u8', 'mpd'));
check(dash.ok && dash.variants.length === 2 && dash.audio.length === 1, 'strict XML DASH separates video and audio');
check(dash.variants[0].width === 1920 && dash.variants[0].codecs === 'avc1.640028', 'representation inherits adaptation dimensions and codec');
check(dash.variants[1].initialization.url === 'https://cdn.example/signed-path/private/uhd/20000000/init.mp4', 'single BaseURL hierarchy and deterministic initialization template resolved');
check(dash.summary.mixed1080And2160 && !dash.summary.sampleEntryVerified, 'DASH declarations remain metadata evidence');
check(!JSON.stringify(dash.summary).includes('signed-path') && !JSON.stringify(dash.summary).includes('http'), 'DASH safe summary excludes internal URLs');
const segmentBase = parseDashManifest(mpd('<Period><AdaptationSet contentType="video"><Representation id="v" width="3840" height="2160" bandwidth="1"><BaseURL>movie.mp4?sig=fixture</BaseURL><SegmentBase><Initialization range="100-199"/></SegmentBase></Representation></AdaptationSet></Period>'), base);
check(segmentBase.ok && segmentBase.initializations[0].byteRange.offset === 100 && segmentBase.initializations[0].byteRange.length === 100, 'DASH inclusive initialization range converted correctly');
for (const initialization of ['$Number$/init.mp4', '$Time$/init.mp4', '$Unknown$/init.mp4', '$Bandwidth%05d$/init.mp4', '$Unclosed']) {
    const result = parseDashManifest(mpd(`<Period><AdaptationSet contentType="video"><SegmentTemplate initialization="${initialization}"/><Representation id="v" bandwidth="1"/></AdaptationSet></Period>`), base);
    check(result.ok && result.variants[0].initialization === null, 'unsupported initialization substitution stays unknown');
}
const noRepId = parseDashManifest(mpd('<Period><AdaptationSet id="wrong-id" contentType="video"><SegmentTemplate initialization="$RepresentationID$/init.mp4"/><Representation bandwidth="1"/></AdaptationSet></Period>'), base);
check(noRepId.ok && !noRepId.variants[0].initialization, 'adaptation ID cannot masquerade as representation ID');
const alternatives = parseDashManifest(mpd('<BaseURL>https://one.example/</BaseURL><BaseURL>https://two.example/</BaseURL><Period><AdaptationSet contentType="video"><SegmentTemplate initialization="init.mp4"/><Representation id="v"/></AdaptationSet></Period>'), base);
check(alternatives.ok && !alternatives.variants[0].initialization && alternatives.variants[0].initializationUnknownReason === 'multiple_base_urls', 'multiple CDN alternatives do not select an arbitrary initialization');
const override = parseDashManifest(mpd('<Period><AdaptationSet contentType="video"><SegmentTemplate initialization="parent.mp4"/><Representation id="v"><SegmentList><Initialization sourceURL="child.mp4"/></SegmentList></Representation></AdaptationSet></Period>'), base);
check(override.ok && !override.variants[0].initialization, 'unsupported child addressing does not reuse unrelated parent template');
for (const text of [
    '<MPD><Period><AdaptationSet></MPD>',
    '<MPD><Period><AdaptationSet>',
    '<!DOCTYPE MPD [<!ENTITY private SYSTEM "file:///secret">]><MPD><Period/></MPD>',
    '<MPD><Period><AdaptationSet contentType="video"><Representation id="v" width="4k"/></AdaptationSet></Period></MPD>',
    '<MPD/><MPD/>',
    '<MPD xmlns="urn:incorrect"><Period/></MPD>',
    '<MPD><Period><AdaptationSet contentType="video"><Representation width="3840" width="1920"/></AdaptationSet></Period></MPD>',
    '<MPD><Period><AdaptationSet contentType="video"><Representation id="v"/></AdaptationSet></Period>&private;</MPD>'
]) {
    const result = parseDashManifest(text, base);
    check(!result.ok && !JSON.stringify(result).includes('file:///secret'), 'invalid XML/DASH fails without source text in errors');
}
check(!parseDashManifest(mpd('<X>'.repeat(60) + '</X>'.repeat(60)), base).ok, 'XML nesting depth bounded');
const qualified = parseDashManifest('<d:MPD xmlns:d="urn:mpeg:dash:schema:mpd:2011"><d:Period><d:AdaptationSet contentType="video" width="3840" height="2160"><d:SegmentTemplate initialization="init.mp4?one=1&amp;two=2"/><d:Representation id="v"/></d:AdaptationSet></d:Period></d:MPD>', base);
check(qualified.ok && qualified.initializations[0].url.endsWith('init.mp4?one=1&two=2'), 'real XML namespaces and entity decoding affect resource URLs correctly');
const xmlBase = parseDashManifest(mpd('<Period xml:base="https://other.example/"><AdaptationSet contentType="video"><SegmentTemplate initialization="init.mp4"/><Representation id="v"/></AdaptationSet></Period>'), base);
check(xmlBase.ok && !xmlBase.variants[0].initialization, 'unsupported xml:base cannot silently resolve the wrong initialization');
const tooManyVariants = parseDashManifest(mpd('<Period><AdaptationSet contentType="video">' + Array.from({ length: LIMITS.variants + 1 }, (_, index) => `<Representation id="v${index}"/>`).join('') + '</AdaptationSet></Period>'), base);
check(!tooManyVariants.ok, 'representation count bound enforced');
console.log(checks + ' media playlist assertions passed');
