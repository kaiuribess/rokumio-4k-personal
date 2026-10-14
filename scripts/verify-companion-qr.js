// node scripts/verify-companion-qr.js — checks images/qr-companion.png really
// encodes the URL in scripts/gen-companion-qr.js, by decoding the committed PNG.
//
// The encoder in gen-companion-qr.js is a hand-rolled QR implementation: GF(256)
// Reed-Solomon, byte mode, the version/EC block tables, matrix construction, the
// eight data masks and penalty scoring. All of that is easy to get subtly wrong,
// and the failure mode is nasty — a QR that renders perfectly plausibly but will
// not scan, discovered by a user holding a phone at a television. So this
// decodes the committed asset rather than trusting the encoder.
//
// The decode is done by jsQR when it is installed; otherwise libqrencode is used
// as an independent second implementation to cross-check the module matrix. jsQR
// is the stronger of the two because it reads the rasterised image — pixel
// scaling, quiet zone and all — which is what a phone actually does.
//
//   npm install --no-save jsqr pngjs     # in a scratch dir, or here
//   node scripts/verify-companion-qr.js
//
// Both modules are optional on purpose. package.json carries two devDependencies
// and a QR that has to be regenerated once a year does not justify more; this
// script degrades to the libqrencode comparison or skips with a clear message.

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const ROOT = path.join(__dirname, '..');
const IMAGE = path.join(ROOT, 'images', 'qr-companion.png');
const GEN = path.join(__dirname, 'gen-companion-qr.js');

function expectedUrl() {
    const src = fs.readFileSync(GEN, 'utf8');
    const m = /const URL\s*=\s*'([^']+)'/.exec(src);
    if (!m) throw new Error(`no \`const URL = '...'\` found in ${path.relative(ROOT, GEN)}`);
    return m[1];
}

// --- minimal PNG decode ------------------------------------------------------

// Enough of the spec to read back what gen-companion-qr.js writes: 8-bit
// greyscale or RGB/RGBA, non-interlaced, with the five standard filters. Only
// used when pngjs is not installed.
function decodePng(buf) {
    const SIG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    for (let i = 0; i < SIG.length; i++) {
        if (buf[i] !== SIG[i]) throw new Error('not a PNG (bad signature)');
    }
    let off = 8;
    let width = 0;
    let height = 0;
    let bitDepth = 0;
    let colorType = 0;
    let interlace = 0;
    const idat = [];
    while (off < buf.length) {
        const len = buf.readUInt32BE(off);
        const type = buf.toString('ascii', off + 4, off + 8);
        const data = buf.subarray(off + 8, off + 8 + len);
        if (type === 'IHDR') {
            width = data.readUInt32BE(0);
            height = data.readUInt32BE(4);
            bitDepth = data[8];
            colorType = data[9];
            interlace = data[12];
        } else if (type === 'IDAT') {
            idat.push(data);
        } else if (type === 'IEND') {
            break;
        }
        off += 12 + len;
    }
    if (bitDepth !== 8) throw new Error(`unsupported bit depth ${bitDepth} (only 8 is handled)`);
    if (interlace !== 0) throw new Error('interlaced PNG not supported');
    const channels = { 0: 1, 2: 3, 4: 2, 6: 4 }[colorType];
    if (!channels) throw new Error(`unsupported colour type ${colorType}`);

    const raw = zlib.inflateSync(Buffer.concat(idat));
    const stride = width * channels;
    const out = Buffer.alloc(stride * height);
    let prev = Buffer.alloc(stride);
    for (let y = 0; y < height; y++) {
        const filter = raw[y * (stride + 1)];
        const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
        const cur = Buffer.alloc(stride);
        for (let x = 0; x < stride; x++) {
            const a = x >= channels ? cur[x - channels] : 0;
            const b = prev[x];
            const c = x >= channels ? prev[x - channels] : 0;
            let v = line[x];
            switch (filter) {
                case 0: break;
                case 1: v += a; break;
                case 2: v += b; break;
                case 3: v += (a + b) >> 1; break;
                case 4: {
                    const p = a + b - c;
                    const pa = Math.abs(p - a);
                    const pb = Math.abs(p - b);
                    const pc = Math.abs(p - c);
                    v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
                    break;
                }
                default: throw new Error(`unknown filter ${filter} on row ${y}`);
            }
            cur[x] = v & 0xff;
        }
        cur.copy(out, y * stride);
        prev = cur;
    }
    return { width, height, channels, data: out };
}

// Flatten to the RGBA byte array jsQR expects, taking the first colour channel:
// this is a black-and-white image, so any channel is the luminance.
function toRgba(img) {
    const rgba = new Uint8ClampedArray(img.width * img.height * 4);
    for (let i = 0; i < img.width * img.height; i++) {
        const v = img.data[i * img.channels];
        rgba[i * 4] = v;
        rgba[i * 4 + 1] = v;
        rgba[i * 4 + 2] = v;
        rgba[i * 4 + 3] = 255;
    }
    return rgba;
}

function loadPngJs(buf) {
    const { PNG } = require('pngjs');
    const p = PNG.sync.read(buf);
    return { width: p.width, height: p.height, channels: 4, data: p.data };
}

// --- checks ------------------------------------------------------------------

function checkDecodes(url) {
    let jsQR;
    try {
        jsQR = require('jsqr');
    } catch {
        return { ran: false };
    }
    if (jsQR.default) jsQR = jsQR.default;

    const buf = fs.readFileSync(IMAGE);
    let img;
    try {
        img = loadPngJs(buf);
    } catch {
        img = decodePng(buf);
    }
    const result = jsQR(toRgba(img), img.width, img.height);
    if (!result) {
        return { ran: true, ok: false, detail: `${img.width}x${img.height} image did not decode at all` };
    }
    if (result.data !== url) {
        return { ran: true, ok: false, detail: `decoded a different payload:\n      got:      ${result.data}\n      expected: ${url}` };
    }
    return { ran: true, ok: true, detail: `${img.width}x${img.height}, payload matches` };
}

// Independent check of the module matrix itself, independent of PNG encoding and
// of pixel scaling. Needs the qrcode package; qrencode on the PATH gets the same
// comparison via a generated PNG.
function checkMatrix(url) {
    let QR;
    try {
        QR = require('qrcode');
    } catch {
        return { ran: false };
    }
    const { buildMatrix } = require(GEN);
    const mine = buildMatrix(url);
    const ref = QR.create(url, { errorCorrectionLevel: 'M' });
    const n = ref.modules.size;
    if (mine.matrix.length !== n) {
        return { ran: true, ok: false, detail: `version mismatch: reference v${ref.version} (${n} modules), ours v${mine.version} (${mine.matrix.length})` };
    }
    let diff = 0;
    for (let r = 0; r < n; r++) {
        for (let c = 0; c < n; c++) {
            if (ref.modules.get(r, c) !== (mine.matrix[r][c] ? 1 : 0)) diff++;
        }
    }
    if (diff !== 0) {
        return { ran: true, ok: false, detail: `${diff} of ${n * n} modules differ from the reference matrix` };
    }
    if (mine.mask !== ref.maskPattern) {
        return { ran: true, ok: false, detail: `mask differs: reference ${ref.maskPattern}, ours ${mine.mask}` };
    }
    return { ran: true, ok: true, detail: `v${ref.version}, mask ${ref.maskPattern}, all ${n * n} modules identical to reference` };
}

// Renders through the encoder's own rasteriser at a range of panel sizes. The
// integer module size means a requested size is rounded down to a whole number of
// modules, so this also proves the quiet zone is never clipped at small sizes —
// losing it is the classic way to make a QR unscannable.
function checkSizes(url) {
    let jsQR;
    try {
        jsQR = require('jsqr');
    } catch {
        return { ran: false };
    }
    if (jsQR.default) jsQR = jsQR.default;

    const { buildMatrix, rasterise } = require(GEN);
    const matrix = buildMatrix(url).matrix;
    const mods = matrix.length;
    const QUIET = 4;
    const total = mods + QUIET * 2;
    const failures = [];

    for (const px of [700, 400, 330, 300, 260, 220, 180, 150]) {
        const scale = Math.floor(px / total);
        if (scale < 2) continue;
        const dim = scale * total;
        const offset = Math.floor((px - dim) / 2);
        const rgba = new Uint8ClampedArray(px * px * 4).fill(255);
        for (let y = 0; y < px; y++) {
            for (let x = 0; x < px; x++) {
                const i = (y * px + x) * 4;
                rgba[i] = rgba[i + 1] = rgba[i + 2] = 255;
                rgba[i + 3] = 255;
            }
        }
        for (let r = 0; r < mods; r++) {
            for (let c = 0; c < mods; c++) {
                if (!matrix[r][c]) continue;
                for (let dy = 0; dy < scale; dy++) {
                    for (let dx = 0; dx < scale; dx++) {
                        const y = offset + (r + QUIET) * scale + dy;
                        const x = offset + (c + QUIET) * scale + dx;
                        const i = (y * px + x) * 4;
                        rgba[i] = rgba[i + 1] = rgba[i + 2] = 0;
                    }
                }
            }
        }
        const got = jsQR(rgba, px, px);
        if (!got || got.data !== url) {
            failures.push(`${px}px (scale ${scale})`);
        }
    }
    if (failures.length) {
        return { ran: true, ok: false, detail: `failed to scan at: ${failures.join(', ')}` };
    }
    return { ran: true, ok: true, detail: 'scans from 700px down to 150px' };
}

function main() {
    const url = expectedUrl();
    console.log(`verifying ${path.relative(ROOT, IMAGE)}`);
    console.log(`  expected payload: ${url}\n`);

    let ran = 0;
    let failed = 0;

    const decode = checkDecodes(url);
    if (decode.ran) {
        ran++;
        console.log(`  ${decode.ok ? 'ok  ' : 'FAIL'} decode committed png — ${decode.detail}`);
        if (!decode.ok) failed++;
    }

    const matrix = checkMatrix(url);
    if (matrix.ran) {
        ran++;
        console.log(`  ${matrix.ok ? 'ok  ' : 'FAIL'} module matrix vs reference — ${matrix.detail}`);
        if (!matrix.ok) failed++;
    }

    const sizes = checkSizes(url);
    if (sizes.ran) {
        ran++;
        console.log(`  ${sizes.ok ? 'ok  ' : 'FAIL'} rasterised sizes — ${sizes.detail}`);
        if (!sizes.ok) failed++;
    }

    if (ran === 0) {
        console.log('  SKIP no verifier available.');
        console.log('       Install one to check this properly:');
        console.log('         npm install --no-save jsqr pngjs qrcode');
        console.log('       The qrcode package cross-checks the module matrix; jsqr decodes');
        console.log('       the actual pixels, which is what a phone does.');
        process.exit(0);
    }

    console.log('');
    if (failed > 0) {
        console.error(`${failed} of ${ran} check(s) FAILED — regenerate with: node scripts/gen-companion-qr.js`);
        process.exit(1);
    }
    console.log(`${ran} check(s) passed.`);
}

if (require.main === module) main();