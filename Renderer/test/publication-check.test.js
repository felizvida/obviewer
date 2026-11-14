// Tests for scripts/publication-check.mjs. Every "prohibited" term is a random
// synthetic string generated at runtime, so no real policy term ever appears in
// a tracked file. Binary fixtures (Mach-O, fonts, archives) are built in memory.
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { brotliCompressSync, deflateSync, gzipSync, inflateSync } from 'node:zlib';
import {
  DEFAULT_POLICY, Scanner, classify, compilePolicy, fingerprint, flattenedPNG, fontText, icnsRenditions, imageMetadataText,
  strictRGBAPNG,
  loadPolicy, machOText, scanText, tarEntries, wordParts, zipEntries,
} from '../../scripts/publication-check.mjs';

function randomWord(length) {
  const letters = 'bcdfghjklmnpqrstvwxz';
  let word = '';
  for (let i = 0; i < length; i += 1) word += letters[Math.floor(Math.random() * letters.length)];
  return word;
}

const SHORT = randomWord(3); // like a three-letter acronym
const FIVE = randomWord(5); // like a five-letter institute acronym
const NAME_WORDS = [randomWord(6), randomWord(5), randomWord(7)];
const NAME = NAME_WORDS.join('');
const DOMAIN = `${SHORT}org`;

const policy = compilePolicy({
  rules: [
    { id: 'A', mode: 'token', length: 3, sha256: fingerprint(SHORT) },
    { id: 'F', mode: 'token', length: 5, sha256: fingerprint(FIVE) },
    { id: 'N', mode: 'stream', length: NAME.length, sha256: fingerprint(NAME) },
    { id: 'D', mode: 'stream', length: DOMAIN.length, sha256: fingerprint(DOMAIN) },
  ],
});
const rules = (text) => [...new Set(scanText(text, policy).map((f) => f.rule))].sort();

function scanBuffer(buffer, label, tools) {
  const scanner = new Scanner(policy, { tools });
  scanner.scanBuffer(buffer, label);
  return scanner;
}

// ---------------------------------------------------------------------------

test('the committed policy loads and stores only fingerprints', () => {
  const raw = JSON.parse(readFileSync(DEFAULT_POLICY, 'utf8'));
  assert.ok(raw.rules.length >= 40, 'covers the full family, not a few terms');
  assert.ok(raw.rules.some((r) => r.mode === 'token' && r.length === 5), 'five-letter acronyms are covered');
  for (const rule of raw.rules) {
    assert.match(rule.sha256, /^[0-9a-f]{64}$/);
    assert.deepEqual(Object.keys(rule).sort(), ['id', 'length', 'mode', 'sha256']);
  }
  loadPolicy();
});

test('word parts split identifiers; random base64-like runs stay whole', () => {
  assert.deepEqual(wordParts('fooBar ABCDefg x2y'), ['foo', 'bar', 'foobar', 'abc', 'defg', 'abcdefg', 'x', '2', 'y', 'x2y']);
  const noise = `lfab8x0Bj0UO7SNsY8dZSb${SHORT.toUpperCase()}6ipbkE3X0NG9nqjCu6CfCHZ`;
  assert.deepEqual(wordParts(noise), [noise.toLowerCase()]);
  assert.deepEqual(rules(noise), []);
});

test('token rules: any case, identifier styles; not inside unrelated words', () => {
  assert.deepEqual(rules(`plain ${SHORT} word`), ['A']);
  assert.deepEqual(rules(`${SHORT.toUpperCase()}Portal and is${SHORT[0].toUpperCase()}${SHORT.slice(1)}User`), ['A']);
  assert.deepEqual(rules(`snake_${SHORT}_case`), ['A']);
  assert.deepEqual(rules(`un${SHORT}able ${SHORT}ification`), []);
});

test('counterexample 1: a standalone five-letter acronym in a text file', () => {
  const scanner = scanBuffer(Buffer.from(`See the ${FIVE.toUpperCase()} page.\n`), 'example.txt');
  assert.deepEqual(scanner.findings.map((f) => f.rule), ['F']);
  assert.equal(scanner.exitCode, 1);
});

test('stream rules: spaced names, domains and e-mail addresses across lines', () => {
  assert.deepEqual(rules(`the ${NAME_WORDS[0]} ${NAME_WORDS[1]}\n${NAME_WORDS[2]} team`), ['N']);
  assert.deepEqual(rules(`https://www.${SHORT}.org/page`), ['A', 'D']);
  assert.deepEqual(rules(`someone@mail.${SHORT}.org`), ['A', 'D']);
});

test('findings report locations, never the matched text', () => {
  assert.deepEqual(scanText(`one\ntwo ${SHORT}\n`, policy), [{ rule: 'A', line: 2 }]);
});

test('counterexamples 2 and 3: unknown binaries fail closed instead of passing', () => {
  const metadata = scanBuffer(Buffer.concat([Buffer.from([0]), Buffer.from(SHORT.toUpperCase()), Buffer.from([0, 0xff])]), 'metadata.bin');
  assert.equal(metadata.exitCode, 2);
  assert.match(metadata.incomplete[0].reason, /unsupported binary/);
  const opaque = scanBuffer(Buffer.from([0x13, 0xfe, 0x00, 0x88, 0x01, 0xc7]), 'opaque.bin');
  assert.equal(opaque.exitCode, 2);
});

test('counterexample 4: image-only PDF pages are OCRed', () => {
  const pdf = Buffer.from('%PDF-1.4\n% synthetic\n');
  const pages = [];
  const scanner = scanBuffer(pdf, 'scanned.pdf', {
    pdfText: () => '',
    pdfInfo: () => 'Title: Report',
    pdfPages: (file, dir) => {
      const page = join(dir, 'page-1.png');
      writeFileSync(page, 'fake');
      pages.push(page);
      return [page];
    },
    ocr: () => `LARGE ${SHORT.toUpperCase()} TEXT`,
  });
  assert.equal(pages.length, 1);
  assert.deepEqual(scanner.findings.map((f) => [f.where, f.rule]), [['scanned.pdf (page 1 image text)', 'A']]);
});

test('missing OCR or PDF tools make the scan incomplete', () => {
  const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const noOCR = scanBuffer(png, 'shot.png', { ocr: () => { throw new Error('tesseract missing'); } });
  assert.equal(noOCR.exitCode, 2);
  const noRender = scanBuffer(Buffer.from('%PDF-1.4\n'), 'a.pdf', { pdfText: () => '', pdfInfo: () => '', pdfPages: () => [] });
  assert.equal(noRender.exitCode, 2, 'a PDF that renders no pages is not silently clean');
});

test('PNG metadata is read structurally, including very short values', () => {
  const chunk = (type, data) => {
    const length = Buffer.alloc(4);
    length.writeUInt32BE(data.length);
    return Buffer.concat([length, Buffer.from(type, 'latin1'), data, Buffer.alloc(4)]);
  };
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', Buffer.alloc(13)),
    chunk('tEXt', Buffer.from(`Author\0${SHORT.toUpperCase()}`, 'latin1')),
    chunk('zTXt', Buffer.concat([Buffer.from('Comment\0\0', 'latin1'), deflateSync(Buffer.from(NAME_WORDS.join(' ')))])),
    chunk('IDAT', Buffer.from(`zz ${SHORT} zz`)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  const text = imageMetadataText(png);
  assert.deepEqual(rules(text), ['A', 'N']);
  assert.ok(!text.includes('zz '), 'pixel data is left to OCR');
});

// ---------------------------------------------------------------------------
// Mach-O

function machO({ cstrings, noise }) {
  const sectionData = Buffer.from(cstrings);
  const header = Buffer.alloc(32);
  header.writeUInt32LE(0xfeedfacf, 0);
  header.writeUInt32LE(1, 16); // ncmds
  header.writeUInt32LE(152, 20);
  const segment = Buffer.alloc(152);
  segment.writeUInt32LE(0x19, 0);
  segment.writeUInt32LE(152, 4);
  segment.write('__TEXT', 8, 'latin1');
  segment.writeUInt32LE(1, 64); // nsects
  segment.write('__cstring', 72, 'latin1');
  segment.write('__TEXT', 88, 'latin1');
  segment.writeBigUInt64LE(BigInt(sectionData.length), 72 + 40);
  const noiseBytes = Buffer.from(noise);
  segment.writeUInt32LE(32 + 152 + noiseBytes.length, 72 + 48);
  return Buffer.concat([header, segment, noiseBytes, sectionData]);
}

test('Mach-O: short C strings are found; machine-code noise is ignored', () => {
  const binary = machO({ cstrings: `\0${SHORT.toUpperCase()}\0other\0`, noise: `#${SHORT}#padding#${SHORT}#` });
  assert.equal(classify(binary), 'macho');
  assert.match(machOText(binary), new RegExp(SHORT.toUpperCase()));
  const scanner = scanBuffer(binary, 'Obviewer');
  assert.deepEqual(scanner.findings.map((f) => f.rule), ['A']);

  const clean = scanBuffer(machO({ cstrings: '\0hello\0world\0', noise: `#${SHORT}#` }), 'Clean');
  assert.equal(clean.exitCode, 0, 'bytes outside string sections are not text');
});

test('Mach-O: universal binaries scan every slice', () => {
  const slice = machO({ cstrings: `\0${FIVE}\0`, noise: '' });
  const fat = Buffer.alloc(8 + 20);
  fat.writeUInt32BE(0xcafebabe, 0);
  fat.writeUInt32BE(1, 4);
  fat.writeUInt32BE(28, 8 + 8);
  fat.writeUInt32BE(slice.length, 8 + 12);
  const scanner = scanBuffer(Buffer.concat([fat, slice]), 'Universal');
  assert.deepEqual(scanner.findings.map((f) => f.rule), ['F']);
});

// ---------------------------------------------------------------------------
// Fonts

function nameTable(text) {
  const string = Buffer.from(text, 'utf16le').swap16();
  const table = Buffer.alloc(6 + 12);
  table.writeUInt16BE(1, 2); // count
  table.writeUInt16BE(18, 4); // string storage offset
  table.writeUInt16BE(3, 6); // platform: Windows (UTF-16BE)
  table.writeUInt16BE(1, 8);
  table.writeUInt16BE(1, 12); // name id
  table.writeUInt16BE(string.length, 14);
  return Buffer.concat([table, string]);
}

test('fonts: TTF and WOFF2 name tables are inspected', () => {
  const name = nameTable(`Copyright ${SHORT.toUpperCase()} Foundry`);
  const ttfHeader = Buffer.alloc(12 + 16);
  ttfHeader.writeUInt32BE(0x00010000, 0);
  ttfHeader.writeUInt16BE(1, 4);
  ttfHeader.write('name', 12, 'latin1');
  ttfHeader.writeUInt32BE(28, 12 + 8);
  ttfHeader.writeUInt32BE(name.length, 12 + 12);
  const ttf = Buffer.concat([ttfHeader, name]);
  assert.equal(classify(ttf), 'font');
  assert.deepEqual(rules(fontText(ttf)), ['A']);

  const compressed = brotliCompressSync(name);
  const header = Buffer.alloc(48);
  header.write('wOF2', 0, 'latin1');
  header.writeUInt32BE(0x00010000, 4);
  header.writeUInt16BE(1, 12);
  header.writeUInt32BE(compressed.length, 20);
  const directory = Buffer.from([5, name.length]); // table index 5 = name, untransformed; length < 128
  const woff2 = Buffer.concat([header, directory, compressed]);
  const scanner = scanBuffer(woff2, 'font.woff2');
  assert.deepEqual(scanner.findings.map((f) => f.rule), ['A']);
});

// ---------------------------------------------------------------------------
// Archives

function zip(entries) {
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const { name, data = Buffer.alloc(0), mode = 0o100644 } of entries) {
    const nameBytes = Buffer.from(name);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt32LE(data.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(nameBytes.length, 26);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(0x0314, 4);
    central.writeUInt32LE(data.length, 20);
    central.writeUInt32LE(data.length, 24);
    central.writeUInt16LE(nameBytes.length, 28);
    central.writeUInt32LE((mode << 16) >>> 0, 38);
    central.writeUInt32LE(offset, 42);
    locals.push(local, nameBytes, data);
    centrals.push(central, nameBytes);
    offset += 30 + nameBytes.length + data.length;
  }
  const cd = Buffer.concat(centrals);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(cd.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, cd, end]);
}

function tar(entries) {
  const blocks = [];
  for (const { name, data = Buffer.alloc(0), type = '0', link = '' } of entries) {
    const header = Buffer.alloc(512);
    header.write(name, 0, 'utf8');
    header.write('0000644\0', 100);
    header.write('0000000\0', 108);
    header.write('0000000\0', 116);
    header.write(`${data.length.toString(8).padStart(11, '0')}\0`, 124);
    header.write('00000000000\0', 136);
    header.write('        ', 148);
    header.write(type, 156);
    header.write(link, 157);
    header.write('ustar\0', 257);
    header.write('00', 263);
    let sum = 0;
    for (const byte of header) sum += byte;
    header.write(`${sum.toString(8).padStart(6, '0')}\0 `, 148);
    blocks.push(header, data, Buffer.alloc((512 - (data.length % 512)) % 512));
  }
  return Buffer.concat([...blocks, Buffer.alloc(1024)]);
}

test('archives: members are scanned in memory, including nested archives', () => {
  const inner = tar([{ name: 'deep/note.md', data: Buffer.from(`${NAME_WORDS.join(' ')}\n`) }]);
  const outer = zip([
    { name: 'clean.txt', data: Buffer.from('nothing here\n') },
    { name: `docs/${SHORT}-report.txt`, data: Buffer.from('body\n') },
    { name: 'bundle.tar.gz', data: gzipSync(inner) },
  ]);
  assert.equal(zipEntries(outer).length, 4); // comment pseudo-entry + 3 files
  const scanner = scanBuffer(outer, 'release.zip');
  const where = scanner.findings.map((f) => `${f.where}:${f.rule}`);
  assert.ok(where.some((w) => w.includes('-report.txt (name):A')), 'member names');
  assert.ok(where.some((w) => w.includes('bundle.tar.gz!/deep/note.md:N')), 'nested tar.gz contents');
  assert.equal(scanner.incomplete.length, 0);
});

test('archives: traversal, absolute paths and links are refused, never extracted', () => {
  for (const bad of ['../escape.txt', '/etc/passwd', 'a/../../b']) {
    const scanner = scanBuffer(zip([{ name: bad, data: Buffer.from('x') }]), 'bad.zip');
    assert.equal(scanner.exitCode, 2, bad);
  }
  const link = scanBuffer(zip([{ name: 'link', data: Buffer.from('/tmp'), mode: 0o120777 }]), 'link.zip');
  assert.equal(link.exitCode, 2);
  assert.throws(() => tarEntries(tar([{ name: 'evil', type: '2', link: '../../outside' }])), /link/);
  assert.throws(() => tarEntries(tar([{ name: 'dev', type: '3' }])), /special type/);
  assert.equal(tarEntries(tar([{ name: 'ok.txt', data: Buffer.from('fine') }])).length, 1);
});

// ---------------------------------------------------------------------------
// ICNS (app icons)

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc32 = (buffer) => {
  let c = 0xffffffff;
  for (const byte of buffer) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};

function pngChunk(type, data, { badCRC = false } = {}) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(badCRC ? 0 : crc32(body));
  return Buffer.concat([length, body, crc]);
}

/** A valid strict-profile PNG: 8-bit RGBA, transparent except one opaque white pixel. */
function iconPNG(size, { colorType = 6, interlace = 0, before = [], after = [], trailing = null, badCRC = false, idat = null } = {}) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;
  ihdr[9] = colorType;
  ihdr[12] = interlace;
  const rows = Buffer.alloc((size * 4 + 1) * size);
  rows.fill(255, 1, 5); // first pixel opaque white
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk('IHDR', ihdr), ...before,
    ...(idat ? idat(deflateSync(rows)) : [pngChunk('IDAT', deflateSync(rows), { badCRC })]), ...after,
    pngChunk('IEND', Buffer.alloc(0)), ...(trailing ? [trailing] : []),
  ]);
}

function icns(chunks, { declaredLength } = {}) {
  const body = Buffer.concat(chunks.map(({ type, data, length }) => {
    const header = Buffer.alloc(8);
    header.write(type, 0, 'latin1');
    header.writeUInt32BE(length ?? data.length + 8, 4);
    return Buffer.concat([header, data]);
  }));
  const header = Buffer.alloc(8);
  header.write('icns', 0, 'latin1');
  header.writeUInt32BE(declaredLength ?? body.length + 8, 4);
  return Buffer.concat([header, body]);
}

const cleanOCR = () => 'nothing here';

test('ICNS: every rendition is decoded and OCRed three ways', () => {
  const ocrCalls = [];
  const file = icns([
    { type: 'icp4', data: iconPNG(16) },
    { type: 'ic07', data: iconPNG(128) },
    { type: 'ic12', data: iconPNG(64) },
  ]);
  assert.equal(classify(file, 'AppIcon.icns'), 'icns');
  assert.deepEqual(icnsRenditions(file).map((r) => r.type), ['icp4', 'ic07', 'ic12']);
  const scanner = scanBuffer(file, 'AppIcon.icns', { ocr: (path) => { ocrCalls.push(readFileSync(path)); return cleanOCR(); } });
  assert.equal(scanner.exitCode, 0, JSON.stringify(scanner.incomplete));
  assert.equal(ocrCalls.length, 9, 'each rendition is OCRed three times, not only the largest');
  assert.equal(scanner.fileCount, 4);

  const drawn = scanBuffer(icns([{ type: 'icp4', data: iconPNG(16) }, { type: 'ic08', data: iconPNG(256) }]), 'AppIcon.icns', {
    ocr: (path) => (readFileSync(path).length > 0 ? `DRAWN ${FIVE.toUpperCase()}` : ''),
  });
  assert.deepEqual(drawn.findings.map((f) => f.where), [
    'AppIcon.icns#icp4 (image text on white)', 'AppIcon.icns#icp4 (image text on black)', 'AppIcon.icns#icp4 (image text ignoring transparency)',
    'AppIcon.icns#ic08 (image text on white)', 'AppIcon.icns#ic08 (image text on black)', 'AppIcon.icns#ic08 (image text ignoring transparency)',
  ]);
});

test('ICNS: transparency is flattened on both backgrounds, and small renditions are enlarged', () => {
  const image = strictRGBAPNG(iconPNG(16));
  assert.equal(image.width, 16);
  assert.deepEqual([...image.pixels.subarray(0, 8)], [255, 255, 255, 255, 0, 0, 0, 0]);
  for (const [background, expected] of [[255, 255], [0, 0]]) {
    const flat = flattenedPNG(image, background);
    assert.equal(flat.readUInt32BE(16), 512, 'enlarged for OCR');
    const ihdrEnd = 8 + 25;
    const idatLength = flat.readUInt32BE(ihdrEnd);
    const rows = inflateSync(flat.subarray(ihdrEnd + 8, ihdrEnd + 8 + idatLength));
    const lastPixel = rows.subarray(rows.length - 3);
    assert.deepEqual([...lastPixel], [expected, expected, expected], 'a transparent pixel takes the background');
  }
});

test('ICNS: anything not completely inspectable fails closed', () => {
  const jpeg2000 = Buffer.from([0, 0, 0, 0x0c, 0x6a, 0x50, 0x20, 0x20, 0x0d, 0x0a, 0x87, 0x0a, ...Buffer.alloc(40)]);
  const one = (data, type = 'ic07') => icns([{ type, data }]);
  const containers = {
    'empty container': icns([]),
    'legacy RLE data': icns([{ type: 'is32', data: Buffer.alloc(64) }]),
    'info plist chunk': icns([{ type: 'ic07', data: iconPNG(128) }, { type: 'info', data: Buffer.from('<plist/>') }]),
    'table of contents': icns([{ type: 'TOC ', data: Buffer.alloc(8) }, { type: 'ic07', data: iconPNG(128) }]),
    'version chunk': icns([{ type: 'icnV', data: Buffer.alloc(4) }, { type: 'ic07', data: iconPNG(128) }]),
    'JPEG 2000 in a PNG slot': icns([{ type: 'ic10', data: jpeg2000 }]),
    'wrong size for the slot': one(iconPNG(16)),
    '@2x slot at 1x size': one(iconPNG(16), 'ic11'),
    'duplicate slot': icns([{ type: 'icp4', data: iconPNG(16) }, { type: 'icp4', data: iconPNG(16) }]),
    'chunk runs past the end': icns([{ type: 'icp4', data: iconPNG(16), length: 4096 }]),
    'chunk length below 8': icns([{ type: 'icp4', data: iconPNG(16), length: 4 }]),
  };
  const truncated = Buffer.concat([icns([{ type: 'icp4', data: iconPNG(16) }]), Buffer.alloc(3)]);
  truncated.writeUInt32BE(truncated.length, 4);
  containers['trailing partial header'] = truncated;
  for (const [name, file] of Object.entries(containers)) {
    const scanner = scanBuffer(file, 'AppIcon.icns', { ocr: cleanOCR });
    assert.equal(scanner.exitCode, 2, name);
    assert.ok(scanner.incomplete.some((i) => i.where === 'AppIcon.icns'), name);
  }
  // A declared length that doesn't match the file means it isn't treated as ICNS at all.
  const mismatch = scanBuffer(icns([{ type: 'icp4', data: iconPNG(16) }], { declaredLength: 9999 }), 'AppIcon.icns', { ocr: cleanOCR });
  assert.equal(mismatch.exitCode, 2);
  assert.match(mismatch.incomplete[0].reason, /unsupported binary/);

  // Inside a rendition, only IHDR/IDAT/IEND in the strict profile are accepted.
  const hidden = Buffer.from(`hidden ${SHORT}`);
  const renditions = {
    'data after IEND': iconPNG(128, { trailing: hidden }),
    'private ancillary chunk': iconPNG(128, { before: [pngChunk('prVt', hidden)] }),
    'text chunk': iconPNG(128, { before: [pngChunk('tEXt', Buffer.concat([Buffer.from('Comment\0'), hidden]))] }),
    'ICC profile chunk': iconPNG(128, { before: [pngChunk('iCCP', Buffer.concat([hidden, Buffer.from([0, 0])]))] }),
    'animation frames': iconPNG(128, { before: [pngChunk('acTL', Buffer.alloc(8))], after: [pngChunk('fdAT', Buffer.alloc(30))] }),
    'bad CRC': iconPNG(128, { badCRC: true }),
    'palette image': iconPNG(128, { colorType: 3 }),
    'interlaced image': iconPNG(128, { interlace: 1 }),
    'bytes after the zlib stream, inside IDAT': iconPNG(128, { idat: (z) => [pngChunk('IDAT', Buffer.concat([z, hidden]))] }),
    'bytes after the zlib stream, in an extra IDAT': iconPNG(128, { idat: (z) => [pngChunk('IDAT', z), pngChunk('IDAT', hidden)] }),
    'a second zlib stream': iconPNG(128, { idat: (z) => [pngChunk('IDAT', Buffer.concat([z, deflateSync(hidden)]))] }),
  };
  for (const [name, png] of Object.entries(renditions)) {
    const scanner = scanBuffer(one(png), 'AppIcon.icns', { ocr: cleanOCR });
    assert.equal(scanner.exitCode, 2, name);
    assert.ok(scanner.incomplete.some((i) => i.where === 'AppIcon.icns#ic07'), name);
  }
});

test('ICNS: one zlib stream split across several IDAT chunks is fine', () => {
  const split = iconPNG(128, { idat: (z) => [pngChunk('IDAT', z.subarray(0, 5)), pngChunk('IDAT', z.subarray(5, 9)), pngChunk('IDAT', z.subarray(9))] });
  const scanner = scanBuffer(icns([{ type: 'ic07', data: split }]), 'AppIcon.icns', { ocr: cleanOCR });
  assert.equal(scanner.exitCode, 0, JSON.stringify(scanner.incomplete));
});

test('text and tar archives that merely start with "icns" are not taken for icons', () => {
  assert.equal(classify(Buffer.from('icns are small pictures\n'), 'notes.txt'), 'text');
});

test('compiled asset catalogs (Assets.car) stay unsupported', () => {
  const car = Buffer.concat([Buffer.from('BOMStore', 'latin1'), Buffer.from([0, 0, 0, 1, 0xff, 0xfe, 0x80, 0x00]), Buffer.alloc(64)]);
  const scanner = scanBuffer(car, 'Assets.car', { ocr: cleanOCR });
  assert.equal(scanner.exitCode, 2);
  assert.match(scanner.incomplete[0].reason, /unsupported binary/);
});

test('the committed app icon is a fully inspectable PNG-only ICNS', () => {
  const file = readFileSync(join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'App', 'AppIcon.icns'));
  const renditions = icnsRenditions(file);
  assert.equal(renditions.length, 10);
  const scanner = scanBuffer(file, 'App/AppIcon.icns', { ocr: cleanOCR });
  assert.equal(scanner.exitCode, 0);
  assert.equal(scanner.fileCount, 11);
});

test('git LFS pointers and SVG files are refused as uninspectable', () => {
  const lfs = scanBuffer(Buffer.from('version https://git-lfs.github.com/spec/v1\noid sha256:abc\nsize 12\n'), 'big.bin');
  assert.equal(lfs.exitCode, 2);
  const svg = scanBuffer(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0"/></svg>'), 'logo.svg');
  assert.equal(svg.exitCode, 2);
});

test('directories: names, files and link targets', () => {
  const dir = mkdtempSync(join(tmpdir(), 'pubcheck-test-'));
  try {
    writeFileSync(join(dir, 'clean.md'), '# Nothing to see\n');
    writeFileSync(join(dir, `${FIVE}.md`), 'clean body\n');
    const scanner = new Scanner(policy);
    scanner.scanPath(dir, 'root');
    assert.deepEqual(scanner.findings.map((f) => f.rule), ['F']);
    assert.match(scanner.findings[0].where, /\(name\)$/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('git ranges scan commit messages and identities, and count commits', () => {
  const dir = mkdtempSync(join(tmpdir(), 'pubcheck-git-'));
  try {
    const git = (...args) => execFileSync('git', args, { cwd: dir, encoding: 'utf8' });
    const commit = (message, email) => git('-c', 'user.name=T', '-c', `user.email=${email}`,
      'commit', '-q', '--allow-empty', '-m', message);
    git('init', '-q');
    commit('base', 'a@example.invalid');
    commit('clean change', 'a@example.invalid');
    let scanner = new Scanner(policy);
    scanner.scanGitRange('HEAD~1..HEAD', dir);
    assert.equal(scanner.commitCount, 1);
    assert.equal(scanner.findings.length, 0);

    commit(`fix for the ${FIVE} team`, 'a@example.invalid');
    commit('identity only', `me@${SHORT}.org`);
    scanner = new Scanner(policy);
    scanner.scanGitRange('HEAD~3..HEAD', dir);
    assert.equal(scanner.commitCount, 3);
    assert.deepEqual([...new Set(scanner.findings.map((f) => f.rule))].sort(), ['A', 'D', 'F']); // the identity's domain also matches the stream rule
    assert.ok(scanner.findings.every((f) => f.where.startsWith('commit ')));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
