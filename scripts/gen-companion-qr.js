// node scripts/gen-companion-qr.js — writes images/qr-companion.png, the code on
// the Add-ons screen that points a phone at the Android companion app.
//
// The URL is a constant rather than an argument so the asset in images/ can be
// regenerated from source instead of being an untraceable blob (which is how the
// two donation codes in SupportDialog came to be — nothing in the repo records
// what they encode). Change the URL, re-run, commit the PNG.
//
// The encoder is dependency-free for the same reason gen-watched-icons.js is:
// package.json carries two devDependencies and adding a QR library to produce
// one static asset is not worth the install. That means the QR spec itself is
// implemented here — GF(256) Reed-Solomon, byte mode, the version/EC block
// tables, matrix construction, the eight data masks and the penalty scoring.
//
// Correctness is the whole risk here: a QR that looks right but does not scan is
// worse than none. So encode twice, by two independent paths, and compare:
//   - this encoder, and
//   - libqrencode, if it is on the machine (verify-companion-qr.js does this).
// Both must agree on the decoded payload, which is what a scanner reads.

// The companion app release. GitHub release asset for rokumio-service.
const URL = 'https://github.com/gpratoe/rokumio-service/releases/download/v0.1.0/Rokumio-0.1.0.apk';

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const OUT = path.join(__dirname, '..', 'images', 'qr-companion.png');
const SIZE = 700; // matches images/qr-buymeacoffee.png
const QUIET = 4; // modules of light margin, required by the spec
const EC_LEVEL_M = 0b00; // 00 = L, 01 = M, 10 = Q, 11 = H (the *format* field)

// --- GF(256) -----------------------------------------------------------------

// Primitive polynomial 0x11d (x^8 + x^4 + x^3 + x^2 + 1), the QR standard one.
const EXP = new Uint8Array(512);
const LOG = new Uint8Array(256);
(function buildTables() {
    let x = 1;
    for (let i = 0; i < 255; i++) {
        EXP[i] = x;
        LOG[x] = i;
        x <<= 1;
        if (x & 0x100) x ^= 0x11d;
    }
    for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255];
})();

function gfMul(a, b) {
    if (a === 0 || b === 0) return 0;
    return EXP[LOG[a] + LOG[b]];
}

// Generator polynomial for `degree` error-correction codewords, as coefficients
// from the highest power down: g(x) = prod (x - a^i).
function generatorPoly(degree) {
    let poly = [1];
    for (let i = 0; i < degree; i++) {
        const next = new Array(poly.length + 1).fill(0);
        for (let j = 0; j < poly.length; j++) {
            next[j] ^= poly[j];
            next[j + 1] ^= gfMul(poly[j], EXP[i]);
        }
        poly = next;
    }
    return poly;
}

// Remainder of data * x^degree divided by the generator: the EC codewords.
function ecCodewords(data, degree) {
    const gen = generatorPoly(degree);
    const res = new Array(degree).fill(0);
    for (const byte of data) {
        const factor = byte ^ res[0];
        res.shift();
        res.push(0);
        for (let i = 0; i < degree; i++) res[i] ^= gfMul(gen[i + 1], factor);
    }
    return res;
}

// --- version tables ----------------------------------------------------------

// Versions 1..10 is plenty: byte mode at level M carries 213 bytes by v10, and
// the URL is 85. Each entry is
//   [totalCodewords, ecCodewordsPerBlock, group1Blocks, group2Blocks]
// where group1 has (totalCodewords / blocks) data codewords and group2 one more.
//
// These are the *level M* figures specifically. The EC codewords per block differ
// between levels, so this is not a level-independent table — mixing them up
// silently picks a version one step too small (level M at v5 holds 84 bytes while
// v5-L holds 106), which produces a QR that will not decode at all.
const VERSIONS = {
    1:  [26, 10, 1, 0],
    2:  [44, 16, 1, 0],
    3:  [70, 26, 1, 0],
    4:  [100, 18, 2, 0],
    5:  [134, 24, 2, 0],
    6:  [172, 16, 4, 0],
    7:  [196, 18, 4, 0],
    8:  [242, 22, 2, 2],
    9:  [292, 22, 3, 2],
    10: [346, 26, 4, 1]
};

// Alignment-pattern centre coordinates, per version (index 1 == version 1).
const ALIGN = {
    1: [],
    2: [6, 18],
    3: [6, 22],
    4: [6, 26],
    5: [6, 30],
    6: [6, 34],
    7: [6, 22, 38],
    8: [6, 24, 42],
    9: [6, 26, 46],
    10: [6, 28, 50]
};

const dataCodewords = (version) => {
    const [total, ec, g1, g2] = VERSIONS[version];
    const blocks = g1 + g2;
    return total - ec * blocks;
};

function chooseVersion(byteLength) {
    for (let v = 1; v <= 10; v++) {
        // 4 bits mode + the character-count field + payload. The count field is
        // 8 bits up to version 9 and 16 bits from version 10.
        const countBits = v < 10 ? 8 : 16;
        const needed = Math.ceil((4 + countBits + byteLength * 8) / 8);
        if (needed <= dataCodewords(v)) return v;
    }
    throw new Error(`payload too long: ${byteLength} bytes exceeds version 10`);
}

const matrixSize = (version) => version * 4 + 17;

// --- bit stream --------------------------------------------------------------

class BitBuffer {
    constructor() {
        this.bits = [];
    }
    put(value, length) {
        for (let i = length - 1; i >= 0; i--) this.bits.push((value >> i) & 1);
    }
    get length() {
        return this.bits.length;
    }
    toBytes() {
        const out = new Uint8Array(Math.ceil(this.bits.length / 8));
        this.bits.forEach((bit, i) => {
            if (bit) out[i >> 3] |= 0x80 >> (i & 7);
        });
        return out;
    }
}

// Byte mode: mode indicator 0100, then the count, then the payload. This encoder
// only emits byte mode, which is correct for a URL — the spec's alphanumeric mode
// is far more compact for uppercase text but does not cover `:` or `/`.
function encodeData(text, version) {
    const bytes = Buffer.from(text, 'utf8');
    const bb = new BitBuffer();
    bb.put(0b0100, 4);
    bb.put(bytes.length, version < 10 ? 8 : 16);
    for (const b of bytes) bb.put(b, 8);

    const capacityBits = dataCodewords(version) * 8;
    // Terminator: up to four zero bits, truncated if the block is nearly full.
    bb.put(0, Math.min(4, capacityBits - bb.length));
    // Pad to a byte boundary, then alternate 0xEC / 0x11 to the capacity.
    while (bb.length % 8 !== 0) bb.put(0, 1);
    const out = Array.from(bb.toBytes());
    const pads = [0xec, 0x11];
    for (let i = 0; out.length < dataCodewords(version); i++) out.push(pads[i % 2]);
    return out;
}

// Split into blocks, compute EC per block, then interleave data then EC — the
// order a scanner reassembles in.
function interleave(data, version) {
    const [total, ecPerBlock, g1, g2] = VERSIONS[version];
    const blocks = g1 + g2;
    const shortLen = Math.floor(total / blocks) - ecPerBlock;
    const dataBlocks = [];
    const ecBlocks = [];
    let offset = 0;
    for (let b = 0; b < blocks; b++) {
        const len = b < g1 ? shortLen : shortLen + 1;
        const chunk = data.slice(offset, offset + len);
        offset += len;
        dataBlocks.push(chunk);
        ecBlocks.push(ecCodewords(chunk, ecPerBlock));
    }

    const out = [];
    const maxData = Math.max(...dataBlocks.map((b) => b.length));
    for (let i = 0; i < maxData; i++) {
        for (const block of dataBlocks) if (i < block.length) out.push(block[i]);
    }
    for (let i = 0; i < ecPerBlock; i++) {
        for (const block of ecBlocks) out.push(block[i]);
    }
    return out;
}

// --- matrix ------------------------------------------------------------------

function blankMatrix(size) {
    return Array.from({ length: size }, () => new Array(size).fill(null));
}

function placeFinder(m, row, col) {
    // 7x7 finder plus its one-module separator, drawn as a ring.
    for (let r = -1; r <= 7; r++) {
        for (let c = -1; c <= 7; c++) {
            const rr = row + r;
            const cc = col + c;
            if (rr < 0 || cc < 0 || rr >= m.length || cc >= m.length) continue;
            const inRing = (r >= 0 && r <= 6 && (c === 0 || c === 6)) ||
                (c >= 0 && c <= 6 && (r === 0 || r === 6));
            const inCore = r >= 2 && r <= 4 && c >= 2 && c <= 4;
            m[rr][cc] = inRing || inCore ? 1 : 0;
        }
    }
}

function placeAlignment(m, version) {
    const centres = ALIGN[version];
    for (const r of centres) {
        for (const c of centres) {
            // Skip the three corners: the finders already own those cells.
            if ((r === 6 && c === 6) ||
                (r === 6 && c === centres[centres.length - 1]) ||
                (r === centres[centres.length - 1] && c === 6)) continue;
            for (let dr = -2; dr <= 2; dr++) {
                for (let dc = -2; dc <= 2; dc++) {
                    const edge = Math.max(Math.abs(dr), Math.abs(dc));
                    m[r + dr][c + dc] = edge === 1 ? 0 : 1;
                }
            }
        }
    }
}

function placeTiming(m) {
    const size = m.length;
    for (let i = 8; i < size - 8; i++) {
        const bit = i % 2 === 0 ? 1 : 0;
        if (m[6][i] === null) m[6][i] = bit;
        if (m[i][6] === null) m[i][6] = bit;
    }
}

function reserveFormatAreas(m) {
    const size = m.length;
    // Around the top-left finder, plus the two copies.
    for (let i = 0; i <= 8; i++) {
        if (i !== 6) {
            if (m[8][i] === null) m[8][i] = 0;
            if (m[i][8] === null) m[i][8] = 0;
        }
    }
    for (let i = 0; i < 8; i++) {
        if (m[8][size - 1 - i] === null) m[8][size - 1 - i] = 0;
        if (m[size - 1 - i][8] === null) m[size - 1 - i][8] = 0;
    }
    m[size - 8][8] = 1; // the always-dark module
}

function buildFunctionPatterns(m, version) {
    placeFinder(m, 0, 0);
    placeFinder(m, 0, m.length - 7);
    placeFinder(m, m.length - 7, 0);
    placeAlignment(m, version);
    placeTiming(m);
    reserveFormatAreas(m);
}

// Zigzag placement: two-module-wide columns, right to left, skipping the
// vertical timing column, upward on even columns and downward on odd.
//
// Returns the [row, col] cells that received a data bit. The mask must be
// applied to exactly these and no others — function patterns are never masked —
// so the caller needs this list.
function placeData(m, codewords) {
    const size = m.length;
    let bitIndex = 0;
    const bits = [];
    for (const byte of codewords) {
        for (let i = 7; i >= 0; i--) bits.push((byte >> i) & 1);
    }
    const dataCells = [];
    let upward = true;
    for (let col = size - 1; col > 0; col -= 2) {
        if (col === 6) col = 5; // skip the vertical timing pattern
        for (let n = 0; n < size; n++) {
            const row = upward ? size - 1 - n : n;
            for (const c of [col, col - 1]) {
                if (m[row][c] !== null) continue;
                m[row][c] = bitIndex < bits.length ? bits[bitIndex] : 0;
                dataCells.push([row, c]);
                bitIndex++;
            }
        }
        upward = !upward;
    }
    return dataCells;
}

// BCH(15,5) format information: 5 data bits (2 EC level + 3 mask) with a
// generator of 0b10100110111, then XOR-masked with 0b101010000010010 so the
// all-zero format is never mistaken for "no format".
function formatBits(mask) {
    const data = (EC_LEVEL_M << 3) | mask;
    let value = data << 10;
    for (let i = 4; i >= 0; i--) {
        if (value & (1 << (i + 10))) value ^= 0b10100110111 << i;
    }
    return ((data << 10) | value) ^ 0b101010000010010;
}

function placeFormat(m, mask) {
    const size = m.length;
    const bits = formatBits(mask);
    for (let i = 0; i < 15; i++) {
        const bit = (bits >> i) & 1;
        // Copy 1: down the left column and along the top.
        if (i < 6) m[i][8] = bit;
        else if (i === 6) m[7][8] = bit;
        else if (i === 7) m[8][8] = bit;
        else if (i === 8) m[8][7] = bit;
        else m[8][14 - i] = bit;
        // Copy 2: along the bottom-left, split either side of the dark module.
        if (i < 8) m[8][size - 1 - i] = bit;
        else m[size - 15 + i][8] = bit;
    }
}

// Penalty rules 1-4 from the spec; the mask with the lowest total wins.
function penalty(m) {
    const size = m.length;
    let score = 0;

    // Rule 1: runs of five or more same-coloured modules in a line.
    for (let i = 0; i < size; i++) {
        for (const line of [m[i], m.map((row) => row[i])]) {
            let run = 1;
            for (let j = 1; j < size; j++) {
                if (line[j] === line[j - 1]) run++;
                else {
                    if (run >= 5) score += run - 2;
                    run = 1;
                }
            }
            if (run >= 5) score += run - 2;
        }
    }

    // Rule 2: every 2x2 block of one colour.
    for (let r = 0; r < size - 1; r++) {
        for (let c = 0; c < size - 1; c++) {
            const v = m[r][c];
            if (v === m[r][c + 1] && v === m[r + 1][c] && v === m[r + 1][c + 1]) score += 3;
        }
    }

    // Rule 3: the finder-like 1:1:3:1:1 pattern with four light modules beside it.
    const A = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0];
    const B = [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1];
    const matches = (line, start, pattern) => {
        for (let k = 0; k < 11; k++) {
            if (line[start + k] !== pattern[k]) return false;
        }
        return true;
    };
    for (let i = 0; i < size; i++) {
        const row = m[i];
        const col = m.map((r) => r[i]);
        for (let j = 0; j + 11 <= size; j++) {
            if (matches(row, j, A) || matches(row, j, B)) score += 40;
            if (matches(col, j, A) || matches(col, j, B)) score += 40;
        }
    }

    // Rule 4: deviation from an even split of dark and light.
    let dark = 0;
    for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) dark += m[r][c];
    const percent = (dark * 100) / (size * size);
    score += Math.floor(Math.abs(percent - 50) / 5) * 10;

    return score;
}

function maskBit(mask, r, c) {
    switch (mask) {
        case 0: return (r + c) % 2 === 0;
        case 1: return r % 2 === 0;
        case 2: return c % 3 === 0;
        case 3: return (r + c) % 3 === 0;
        case 4: return (Math.floor(r / 2) + Math.floor(c / 3)) % 2 === 0;
        case 5: return ((r * c) % 2) + ((r * c) % 3) === 0;
        case 6: return (((r * c) % 2) + ((r * c) % 3)) % 2 === 0;
        case 7: return (((r + c) % 2) + ((r * c) % 3)) % 2 === 0;
    }
}

function buildMatrix(text) {
    const version = chooseVersion(Buffer.byteLength(text, 'utf8'));
    const size = matrixSize(version);
    const codewords = interleave(encodeData(text, version), version);

    let best = null;
    for (let mask = 0; mask < 8; mask++) {
        const m = blankMatrix(size);
        buildFunctionPatterns(m, version);
        // Data is laid down unmasked, then masked in place using only the cells
        // that actually carry a data bit.
        const dataCells = placeData(m, codewords);
        for (const [r, c] of dataCells) {
            if (maskBit(mask, r, c)) m[r][c] ^= 1;
        }
        placeFormat(m, mask);
        const score = penalty(m);
        if (!best || score < best.score) best = { matrix: m, score, mask };
    }
    return { version, matrix: best.matrix, mask: best.mask };
}

// --- PNG ---------------------------------------------------------------------

function crc32() {
    const table = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        table[n] = c;
    }
    let crc = -1;
    return (buf) => {
        for (const byte of buf) crc = table[(crc ^ byte) & 0xff] ^ (crc >>> 8);
        return (crc ^ -1) >>> 0;
    };
}

function chunk(type, data) {
    const crc = crc32();
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const checksum = Buffer.alloc(4);
    checksum.writeUInt32BE(crc(body));
    return Buffer.concat([len, body, checksum]);
}

// Grey-scale PNG (colour type 0). A QR needs a light background and dark
// modules; RGB would work too and grey keeps the file a third of the size.
function encodePng(darkMap) {
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(SIZE, 0);
    ihdr.writeUInt32BE(SIZE, 4);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 0; // colour type: greyscale
    const rowLength = SIZE + 1;
    const raw = Buffer.alloc(rowLength * SIZE);
    for (let y = 0; y < SIZE; y++) {
        raw[y * rowLength] = 0; // filter: none
        for (let x = 0; x < SIZE; x++) {
            raw[y * rowLength + 1 + x] = darkMap[y][x] ? 0x00 : 0xFF;
        }
    }
    return Buffer.concat([
        Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
        chunk('IHDR', ihdr),
        chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
        chunk('IEND', Buffer.alloc(0))
    ]);
}

function rasterise(matrix) {
    const mods = matrix.length;
    const total = mods + QUIET * 2;
    // Integer module size, centred. Truncating rather than rounding up keeps the
    // quiet zone from being clipped, which is what makes a QR unscannable.
    const scale = Math.floor(SIZE / total);
    const offset = Math.floor((SIZE - scale * total) / 2);
    const dark = Array.from({ length: SIZE }, () => new Array(SIZE).fill(false));
    for (let r = 0; r < mods; r++) {
        for (let c = 0; c < mods; c++) {
            if (!matrix[r][c]) continue;
            for (let dy = 0; dy < scale; dy++) {
                for (let dx = 0; dx < scale; dx++) {
                    dark[offset + (r + QUIET) * scale + dy][offset + (c + QUIET) * scale + dx] = true;
                }
            }
        }
    }
    return dark;
}

function main() {
    const { version, matrix, mask } = buildMatrix(URL);
    const png = encodePng(rasterise(matrix));
    fs.writeFileSync(OUT, png);
    console.log(`wrote ${path.relative(process.cwd(), OUT)}`);
    console.log(`  version ${version} (${matrix.length}x${matrix.length} modules), mask ${mask}, EC level M`);
    console.log(`  ${SIZE}x${SIZE} PNG, ${png.length} bytes`);
    console.log(`  encodes: ${URL}`);
}

if (require.main === module) main();

module.exports = { buildMatrix, chooseVersion, rasterise, encodePng, URL, SIZE, QUIET };