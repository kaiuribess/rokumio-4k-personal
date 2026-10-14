// node scripts/gen-watched-icons.js — writes images/check.png and
// images/diamond.png, the watched-state overlays used by PosterTile /
// EpisodeTile.
//
// Both are 240x240 RGBA PNGs on a transparent background with a mint check /
// diamond glyph (the app's #46e0a3), anti-aliased along the glyph edges. The
// encoder is dependency-free: IHDR/IDAT/IEND chunks, zlib for the scanlines,
// a hand-rolled CRC32.

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const MINT = [0x46, 0xe0, 0xa3];
const SIZE = 240;

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

function encodePng(alphaMap) {
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(SIZE, 0);
    ihdr.writeUInt32BE(SIZE, 4);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 6; // color type: RGBA
    const rowLength = SIZE * 4 + 1;
    const raw = Buffer.alloc(rowLength * SIZE);
    for (let y = 0; y < SIZE; y++) {
        raw[y * rowLength] = 0; // filter: none
        for (let x = 0; x < SIZE; x++) {
            const off = y * rowLength + 1 + x * 4;
            const a = alphaMap[y][x];
            raw[off] = MINT[0];
            raw[off + 1] = MINT[1];
            raw[off + 2] = MINT[2];
            raw[off + 3] = a;
        }
    }
    return Buffer.concat([
        Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
        chunk('IHDR', ihdr),
        chunk('IDAT', zlib.deflateSync(raw)),
        chunk('IEND', Buffer.alloc(0))
    ]);
}

// Squared distance from (x,y) to the segment a-b.
function distSqToSegment(x, y, ax, ay, bx, by) {
    const vx = bx - ax;
    const vy = by - ay;
    const wx = x - ax;
    const wy = y - ay;
    const c1 = vx * wx + vy * wy;
    if (c1 <= 0) return (x - ax) * (x - ax) + (y - ay) * (y - ay);
    const c2 = vx * vx + vy * vy;
    if (c2 <= c1) return (x - bx) * (x - bx) + (y - by) * (y - by);
    const t = c1 / c2;
    const px = ax + t * vx;
    const py = ay + t * vy;
    return (x - px) * (x - px) + (y - py) * (y - py);
}

// Coverage for a thick polyline: 1 inside the stroke, 0 outside, a one-pixel
// gradient across the edge.
function strokeCoverage(x, y, segments, halfWidth) {
    let best = Infinity;
    for (const [ax, ay, bx, by] of segments) {
        const d = Math.sqrt(distSqToSegment(x + 0.5, y + 0.5, ax, ay, bx, by));
        if (d < best) best = d;
    }
    if (best <= halfWidth - 1) return 1;
    if (best >= halfWidth + 1) return 0;
    return (halfWidth + 1 - best) / 2;
}

function makeCheck() {
    const alpha = [];
    const segments = [
        [86, 126, 108, 148],
        [108, 148, 170, 86]
    ];
    for (let y = 0; y < SIZE; y++) {
        const row = [];
        for (let x = 0; x < SIZE; x++) {
            row.push(Math.round(255 * strokeCoverage(x, y, segments, 9)));
        }
        alpha.push(row);
    }
    return encodePng(alpha);
}

function makeDiamond() {
    const alpha = [];
    const cx = 120;
    const cy = 120;
    const rx = 66;
    const ry = 58;
    // Corners of the diamond outline.
    const corners = [
        [cx, cy - ry],
        [cx + rx, cy],
        [cx, cy + ry],
        [cx - rx, cy]
    ];
    const segments = [];
    for (let i = 0; i < 4; i++) {
        const [ax, ay] = corners[i];
        const [bx, by] = corners[(i + 1) % 4];
        segments.push([ax, ay, bx, by]);
    }
    for (let y = 0; y < SIZE; y++) {
        const row = [];
        for (let x = 0; x < SIZE; x++) {
            row.push(Math.round(255 * strokeCoverage(x, y, segments, 7)));
        }
        alpha.push(row);
    }
    return encodePng(alpha);
}

const imagesDir = path.join(__dirname, '..', 'images');
fs.writeFileSync(path.join(imagesDir, 'check.png'), makeCheck());
fs.writeFileSync(path.join(imagesDir, 'diamond.png'), makeDiamond());
console.log('wrote ' + path.join(imagesDir, 'check.png') + ' and ' + path.join(imagesDir, 'diamond.png'));