#!/usr/bin/env node
// Publication policy check.
//
// Fails when content that is about to be published contains a reference the
// project's publication policy prohibits. The policy (Configuration/
// publication-policy.json) stores only SHA-256 fingerprints of normalized
// terms, never the terms themselves, so neither this script nor its policy
// publishes what it guards against.
//
// Fail-closed by design: every file is classified by content, and only formats
// with a real inspector pass. Anything else (unknown binaries, unsupported image
// or archive formats, Git LFS pointers, encrypted or unsafe archive members,
// missing OCR/PDF tools) makes the run INCOMPLETE, which fails it.
//
// Inspectors:
//   text           UTF-8 text (source, docs, JSON, plists in XML). SVG is refused:
//                  text drawn as paths can't be inspected.
//   PNG / JPEG     OCR (tesseract) of the pixels + structured metadata chunks
//   ICNS           Apple icons that hold only PNG renditions, one per known slot,
//                  each the slot's exact size; every rendition goes through the PNG
//                  inspector. Anything else in the container (JPEG 2000, legacy
//                  RLE/ARGB data, TOC, version, name or info chunks, nested dark
//                  variants, duplicates, bad lengths) is refused. Compiled asset
//                  catalogs (Assets.car) are not supported and fail closed.
//   PDF            text layer (pdftotext), metadata (pdfinfo), and OCR of every
//                  rendered page (pdftoppm + tesseract)
//   Mach-O         string sections, symbol table, load-command strings and code
//                  signature blobs (entitlements, identifier, team, certificates),
//                  thin or universal
//   fonts          TTF/OTF/WOFF/WOFF2 name and glyph-name tables, WOFF metadata
//   binary plist   converted with plutil (macOS)
//   zip, tar, gzip parsed in-process; members are validated (no absolute paths,
//                  "..", links, devices, encryption) and size/depth-capped, then
//                  scanned in memory. Nothing is extracted to disk except single
//                  members handed to OCR/PDF tools in a private temp directory.
//   DMG            mounted read-only (macOS) and scanned as a directory
//   git metadata   commit messages, author and committer identities (--git-range)
//
// Matching (case-insensitive, Unicode NFKC):
//   token rules  - every word and every camelCase/acronym/digit part of a word
//   stream rules - separator-free text, starting at each word boundary, so spaced
//                  names, domains and e-mail addresses match
//
// Known limits: compiled code can carry short string literals inside machine
// instructions (e.g. Swift small strings); those are covered by the source scan.
// Glyph outlines in fonts are shapes, not text.
//
// Usage:
//   node scripts/publication-check.mjs --tracked            # git-tracked files
//   node scripts/publication-check.mjs <path>...            # files, directories, archives, DMGs
//   node scripts/publication-check.mjs --git-range A..B     # commit metadata
//   node scripts/publication-check.mjs --text "<string>"    # e.g. a tag name or release title
//   node scripts/publication-check.mjs --fingerprint --mode token|stream < terms.txt
// Options: --policy <file>
// Exit codes: 0 clean, 1 prohibited reference found, 2 scan incomplete or usage error.

import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, lstatSync, mkdtempSync, readdirSync, readFileSync, readlinkSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { brotliDecompressSync, gunzipSync, inflateRawSync, inflateSync } from 'node:zlib';

const here = dirname(fileURLToPath(import.meta.url));
export const DEFAULT_POLICY = join(here, '..', 'Configuration', 'publication-policy.json');

export const LIMITS = {
  maxFileBytes: 1024 * 1024 * 1024,
  maxArchiveExpandedBytes: 4 * 1024 * 1024 * 1024,
  maxArchiveEntries: 200_000,
  maxArchiveDepth: 4,
  maxPdfPages: 300,
};

// ---------------------------------------------------------------------------
// Normalization, fingerprints and matching

export function fingerprint(term) {
  return createHash('sha256').update(normalizeStream(term), 'utf8').digest('hex');
}

/** Lowercase, NFKC-folded, alphanumerics only. */
export function normalizeStream(text) {
  return String(text).normalize('NFKC').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');
}

/**
 * Word parts: separators, camelCase, acronym runs and letter/digit changes.
 * Long mixed-case alphanumeric runs that split into many tiny pieces (base64,
 * hashes, minified identifiers) are random data, not words: they are matched
 * only as a whole, so chance letter triples inside them don't count.
 */
export function wordParts(text) {
  const parts = [];
  for (const word of String(text).normalize('NFKC').split(/[^\p{L}\p{N}]+/u)) {
    if (!word) continue;
    const pieces = word.match(/\p{Lu}+(?=\p{Lu}\p{Ll})|\p{Lu}?\p{Ll}+|\p{Lu}+|\p{N}+|[\p{L}\p{N}]/gu) ?? [word];
    if (isOpaqueRun(word, pieces)) {
      parts.push(word.toLowerCase());
      continue;
    }
    for (const piece of pieces) parts.push(piece.toLowerCase());
    if (pieces.length > 1) parts.push(word.toLowerCase());
  }
  return parts;
}

export function isOpaqueRun(word, pieces) {
  return word.length >= 24 && pieces.length * 4 > word.length;
}

export function loadPolicy(path = DEFAULT_POLICY) {
  return compilePolicy(JSON.parse(readFileSync(path, 'utf8')));
}

export function compilePolicy(policy) {
  if (!policy || !Array.isArray(policy.rules) || policy.rules.length === 0) {
    throw new Error('Publication policy has no rules.');
  }
  const token = new Map();
  const stream = new Map();
  for (const rule of policy.rules) {
    if (!/^[0-9a-f]{64}$/.test(rule.sha256 ?? '') || !Number.isInteger(rule.length) || rule.length < 1) {
      throw new Error(`Invalid policy rule ${rule.id ?? '(no id)'}.`);
    }
    const target = rule.mode === 'token' ? token : rule.mode === 'stream' ? stream : null;
    if (!target) throw new Error(`Policy rule ${rule.id} has unknown mode ${rule.mode}.`);
    if (!target.has(rule.length)) target.set(rule.length, new Map());
    target.get(rule.length).set(rule.sha256, rule.id ?? rule.sha256.slice(0, 8));
  }
  return { token, stream };
}

function sha(text) {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

/** Rule ids that match `text`, with the 1-based line of each match. Never returns matched text. */
export function scanText(text, policy) {
  const findings = [];
  const seen = new Set();
  const add = (rule, line) => {
    const key = `${rule}:${line}`;
    if (!seen.has(key)) {
      seen.add(key);
      findings.push({ rule, line });
    }
  };
  const lines = String(text).split(/\r\n|\r|\n/);
  for (let index = 0; index < lines.length; index += 1) {
    if (!lines[index]) continue;
    for (const part of wordParts(lines[index])) {
      const id = policy.token.get(part.length)?.get(sha(part));
      if (id) add(id, index + 1);
    }
  }
  if (policy.stream.size > 0) {
    const lengths = [...policy.stream.keys()];
    const { stream, starts, lineOf } = boundaryStream(String(text));
    for (const start of starts) {
      for (const length of lengths) {
        if (start + length > stream.length) continue;
        const id = policy.stream.get(length).get(sha(stream.slice(start, start + length)));
        if (id) add(id, lineOf[start]);
      }
    }
  }
  return findings;
}

function boundaryStream(text) {
  let stream = '';
  const starts = [];
  const lineOf = [];
  let line = 1;
  let previous = '';
  for (const char of text.normalize('NFKC')) {
    if (char === '\n') line += 1;
    if (!/[\p{L}\p{N}]/u.test(char)) {
      previous = '';
      continue;
    }
    const isBoundary = previous === ''
      || (/\p{Ll}/u.test(previous) && /\p{Lu}/u.test(char))
      || (/\p{L}/u.test(previous) !== /\p{L}/u.test(char));
    const lower = char.toLowerCase();
    if (isBoundary) starts.push(stream.length);
    for (let i = 0; i < lower.length; i += 1) lineOf.push(line);
    stream += lower;
    previous = char;
  }
  return { stream, starts, lineOf };
}

// ---------------------------------------------------------------------------
// Byte helpers

/** Printable runs (ASCII, UTF-16LE, UTF-16BE) of at least `minLength`, for structured metadata only. */
export function extractStrings(buffer, minLength = 3) {
  const out = [];
  const collect = (step, read) => {
    let run = '';
    for (let i = 0; i + step - 1 < buffer.length; i += step) {
      const code = read(i);
      if (code >= 0x20 && code < 0x7f) run += String.fromCharCode(code);
      else {
        if (run.length >= minLength) out.push(run);
        run = '';
      }
    }
    if (run.length >= minLength) out.push(run);
  };
  collect(1, (i) => buffer[i]);
  if (buffer.length >= 2) {
    collect(2, (i) => buffer[i] | (buffer[i + 1] << 8));
    collect(2, (i) => (buffer[i] << 8) | buffer[i + 1]);
  }
  return out.join('\n');
}

/** NUL-separated strings (C string tables), any length. */
function splitCStrings(buffer) {
  return buffer.toString('latin1').split('\0').filter(Boolean).join('\n');
}

function cString(buffer, offset) {
  if (offset < 0 || offset >= buffer.length) return '';
  const end = buffer.indexOf(0, offset);
  return buffer.toString('utf8', offset, end < 0 ? buffer.length : end);
}

function decodeUTF16BE(buffer) {
  const swapped = Buffer.from(buffer.subarray(0, buffer.length - (buffer.length % 2)));
  swapped.swap16();
  return swapped.toString('utf16le');
}

function isUTF8Text(buffer) {
  if (buffer.subarray(0, 65536).includes(0)) return false;
  try {
    new TextDecoder('utf-8', { fatal: true }).decode(buffer);
    return true;
  } catch {
    return false;
  }
}

export class Unsupported extends Error {}

// ---------------------------------------------------------------------------
// Format inspectors (pure; return text to scan, or throw Unsupported)

/** PNG text chunks and JPEG APPn/COM segments. Pixel data is left to OCR. */
export function imageMetadataText(buffer) {
  const texts = [];
  if (buffer.length > 8 && buffer.readUInt32BE(0) === 0x89504e47) {
    let offset = 8;
    while (offset + 12 <= buffer.length) {
      const length = buffer.readUInt32BE(offset);
      const type = buffer.toString('latin1', offset + 4, offset + 8);
      const data = buffer.subarray(offset + 8, offset + 8 + length);
      if (type === 'tEXt') texts.push(data.toString('latin1').replace(/\0/g, '\n'));
      else if (type === 'eXIf') texts.push(extractStrings(data));
      else if (type === 'iTXt') {
        let cursor = data.indexOf(0);
        const keyword = data.toString('latin1', 0, cursor);
        const compressed = data[cursor + 1] === 1;
        cursor += 3;
        const parts = [];
        for (let i = 0; i < 2; i += 1) {
          const end = data.indexOf(0, cursor);
          parts.push(data.toString('utf8', cursor, end));
          cursor = end + 1;
        }
        const body = data.subarray(cursor);
        texts.push(keyword, ...parts, compressed ? inflateSync(body).toString('utf8') : body.toString('utf8'));
      } else if (type === 'zTXt') {
        const nul = data.indexOf(0);
        texts.push(data.toString('latin1', 0, nul), inflateSync(data.subarray(nul + 2)).toString('latin1'));
      }
      if (type === 'IEND') break;
      offset += 12 + length;
    }
    return texts.join('\n');
  }
  if (buffer.length > 4 && buffer[0] === 0xff && buffer[1] === 0xd8) {
    let offset = 2;
    while (offset + 4 <= buffer.length && buffer[offset] === 0xff) {
      const marker = buffer[offset + 1];
      if (marker === 0xda || marker === 0xd9) break;
      const length = buffer.readUInt16BE(offset + 2);
      if ((marker >= 0xe0 && marker <= 0xef) || marker === 0xfe) {
        texts.push(extractStrings(buffer.subarray(offset + 4, offset + 2 + length)));
      }
      offset += 2 + length;
    }
    return texts.join('\n');
  }
  throw new Unsupported('image metadata format not supported (only PNG and JPEG)');
}

// ICNS slot type -> pixel size. Only these slots, and only PNG payloads, are accepted.
const ICNS_PNG_SLOTS = new Map([
  ['icp4', 16], ['icp5', 32], ['icp6', 64], ['ic07', 128], ['ic08', 256], ['ic09', 512], ['ic10', 1024],
  ['ic11', 32], ['ic12', 64], ['ic13', 256], ['ic14', 512],
]);

/**
 * Apple icon (.icns) container. Returns its PNG renditions for the PNG inspector,
 * or throws Unsupported for anything that can't be inspected completely.
 */
export function icnsRenditions(buffer) {
  if (buffer.length < 8 || buffer.toString('latin1', 0, 4) !== 'icns') throw new Unsupported('not an ICNS file');
  if (buffer.readUInt32BE(4) !== buffer.length) throw new Unsupported('ICNS length does not match the file size');
  const renditions = [];
  const seen = new Set();
  let offset = 8;
  while (offset < buffer.length) {
    if (offset + 8 > buffer.length) throw new Unsupported('truncated ICNS chunk header');
    const type = buffer.toString('latin1', offset, offset + 4);
    const length = buffer.readUInt32BE(offset + 4);
    const label = JSON.stringify(type);
    if (length < 8 || offset + length > buffer.length) throw new Unsupported(`ICNS chunk ${label} has a bad length`);
    const size = ICNS_PNG_SLOTS.get(type);
    if (size === undefined) throw new Unsupported(`ICNS chunk ${label} cannot be inspected (only PNG icon slots are supported)`);
    if (seen.has(type)) throw new Unsupported(`ICNS chunk ${label} appears more than once`);
    seen.add(type);
    const data = buffer.subarray(offset + 8, offset + length);
    const isPNG = data.length >= 33
      && data.readUInt32BE(0) === 0x89504e47 && data.readUInt32BE(4) === 0x0d0a1a0a
      && data.readUInt32BE(8) === 13 && data.toString('latin1', 12, 16) === 'IHDR';
    if (!isPNG) throw new Unsupported(`ICNS chunk ${label} is not a PNG (JPEG 2000 and raw icon data cannot be inspected)`);
    const width = data.readUInt32BE(16);
    const height = data.readUInt32BE(20);
    if (width !== size || height !== size) {
      throw new Unsupported(`ICNS chunk ${label} is ${width}x${height}, expected ${size}x${size}`);
    }
    renditions.push({ type, data });
    offset += length;
  }
  if (renditions.length === 0) throw new Unsupported('ICNS file has no icon renditions');
  return renditions;
}

const MACHO_TEXT_SECTIONS = new Set([
  '__cstring', '__oslogstring', '__objc_methname', '__objc_classname', '__objc_methtype',
  '__swift5_reflstr', '__info_plist', '__entitlements',
]);

/** Text from a thin or universal Mach-O binary. */
export function machOText(buffer) {
  const magicBE = buffer.readUInt32BE(0);
  if (magicBE === 0xcafebabe || magicBE === 0xcafebabf) {
    const is64 = magicBE === 0xcafebabf;
    const count = buffer.readUInt32BE(4);
    if (count === 0 || count > 32) throw new Unsupported('implausible universal binary header');
    const texts = [];
    for (let i = 0; i < count; i += 1) {
      const entry = 8 + i * (is64 ? 32 : 20);
      const offset = is64 ? Number(buffer.readBigUInt64BE(entry + 8)) : buffer.readUInt32BE(entry + 8);
      const size = is64 ? Number(buffer.readBigUInt64BE(entry + 16)) : buffer.readUInt32BE(entry + 12);
      if (offset + size > buffer.length) throw new Unsupported('truncated universal binary');
      texts.push(machOText(buffer.subarray(offset, offset + size)));
    }
    return texts.join('\n');
  }
  const magic = buffer.readUInt32LE(0);
  const is64 = magic === 0xfeedfacf;
  if (!is64 && magic !== 0xfeedface) throw new Unsupported('unsupported Mach-O variant');
  const ncmds = buffer.readUInt32LE(16);
  let offset = is64 ? 32 : 28;
  const texts = [];
  const readSection = (fileOffset, size, name) => {
    if (fileOffset === 0 || size === 0) return;
    if (fileOffset + size > buffer.length) throw new Unsupported('truncated Mach-O section');
    const data = buffer.subarray(fileOffset, fileOffset + size);
    texts.push(name === '__ustring' ? data.toString('utf16le').split('\0').join('\n') : splitCStrings(data));
  };
  for (let i = 0; i < ncmds; i += 1) {
    if (offset + 8 > buffer.length) throw new Unsupported('truncated Mach-O load commands');
    const cmd = buffer.readUInt32LE(offset) >>> 0;
    const size = buffer.readUInt32LE(offset + 4);
    if (size < 8) throw new Unsupported('invalid Mach-O load command');
    if (cmd === 0x19 || cmd === 0x1) {
      const sixtyFour = cmd === 0x19;
      const nsects = buffer.readUInt32LE(offset + (sixtyFour ? 64 : 48));
      let section = offset + (sixtyFour ? 72 : 56);
      for (let s = 0; s < nsects; s += 1) {
        const sectname = buffer.toString('latin1', section, section + 16).replace(/\0.*$/s, '');
        if (MACHO_TEXT_SECTIONS.has(sectname) || sectname === '__ustring') {
          const sectSize = sixtyFour ? Number(buffer.readBigUInt64LE(section + 40)) : buffer.readUInt32LE(section + 36);
          const fileOffset = buffer.readUInt32LE(section + (sixtyFour ? 48 : 40));
          readSection(fileOffset, sectSize, sectname);
        }
        section += sixtyFour ? 80 : 68;
      }
    } else if (cmd === 0x2) { // LC_SYMTAB
      readSection(buffer.readUInt32LE(offset + 16), buffer.readUInt32LE(offset + 20), '__strtab');
    } else if (cmd === 0x1d) { // LC_CODE_SIGNATURE
      const dataoff = buffer.readUInt32LE(offset + 8);
      const datasize = buffer.readUInt32LE(offset + 12);
      texts.push(codeSignatureText(buffer.subarray(dataoff, dataoff + datasize)));
    } else if ([0xc, 0xd, 0xe, 0xf, 0x80000018, 0x8000001f, 0x8000001c, 0x80000023].includes(cmd)) {
      // dylib / dylinker / rpath / reexport: lc_str offset at +8
      texts.push(cString(buffer.subarray(offset, offset + size), buffer.readUInt32LE(offset + 8)));
    }
    offset += size;
  }
  return texts.join('\n');
}

function codeSignatureText(blob) {
  if (blob.length < 12 || blob.readUInt32BE(0) !== 0xfade0cc0) return '';
  const count = blob.readUInt32BE(8);
  const texts = [];
  for (let i = 0; i < count; i += 1) {
    const offset = blob.readUInt32BE(12 + i * 8 + 4);
    if (offset + 8 > blob.length) continue;
    const magic = blob.readUInt32BE(offset);
    const length = blob.readUInt32BE(offset + 4);
    const body = blob.subarray(offset, offset + length);
    if (magic === 0xfade7171) texts.push(body.toString('utf8', 8)); // entitlements (XML)
    else if (magic === 0xfade7172 || magic === 0xfade0c01) texts.push(extractStrings(body.subarray(8))); // DER entitlements, requirements
    else if (magic === 0xfade0c02 && body.length >= 24) { // code directory: identifier and team
      texts.push(cString(body, body.readUInt32BE(20)));
      const version = body.readUInt32BE(8);
      if (version >= 0x20200 && body.length >= 52) {
        const team = body.readUInt32BE(48);
        if (team) texts.push(cString(body, team));
      }
    } else if (magic === 0xfade0b01) texts.push(extractStrings(body.subarray(8), 4)); // CMS: certificate names
  }
  return texts.join('\n');
}

const WOFF2_TAGS = ['cmap', 'head', 'hhea', 'hmtx', 'maxp', 'name', 'OS/2', 'post', 'cvt ', 'fpgm', 'glyf', 'loca', 'prep', 'CFF ', 'VORG', 'EBDT', 'EBLC', 'gasp', 'hdmx', 'kern', 'LTSH', 'PCLT', 'VDMX', 'vhea', 'vmtx', 'BASE', 'GDEF', 'GPOS', 'GSUB', 'EBSC', 'JSTF', 'MATH', 'CBDT', 'CBLC', 'COLR', 'CPAL', 'SVG ', 'sbix', 'acnt', 'avar', 'bdat', 'bloc', 'bsln', 'cvar', 'fdsc', 'feat', 'fmtx', 'fvar', 'gvar', 'hsty', 'just', 'lcar', 'mort', 'morx', 'opbd', 'prop', 'trak', 'Zapf', 'Silf', 'Glat', 'Gloc', 'Feat', 'Sill'];

/** Text-bearing font tables: names, glyph names, WOFF metadata. Glyph outlines are shapes, not text. */
export function fontText(buffer) {
  const signature = buffer.toString('latin1', 0, 4);
  const tables = new Map();
  const texts = [];
  if (signature === 'wOF2') {
    if (buffer.toString('latin1', 4, 8) === 'ttcf') throw new Unsupported('WOFF2 font collections are not supported');
    const numTables = buffer.readUInt16BE(12);
    const compressedSize = buffer.readUInt32BE(20);
    const metaOffset = buffer.readUInt32BE(28);
    const metaLength = buffer.readUInt32BE(32);
    const privLength = buffer.readUInt32BE(44);
    let offset = 48;
    const readBase128 = () => {
      let value = 0;
      for (let i = 0; i < 5; i += 1) {
        const byte = buffer[offset];
        offset += 1;
        value = value * 128 + (byte & 0x7f);
        if ((byte & 0x80) === 0) return value;
      }
      throw new Unsupported('invalid WOFF2 table directory');
    };
    const directory = [];
    for (let i = 0; i < numTables; i += 1) {
      const flags = buffer[offset];
      offset += 1;
      let tag;
      if ((flags & 0x3f) === 0x3f) {
        tag = buffer.toString('latin1', offset, offset + 4);
        offset += 4;
      } else tag = WOFF2_TAGS[flags & 0x3f];
      const version = (flags >> 6) & 3;
      const origLength = readBase128();
      const transformed = (tag === 'glyf' || tag === 'loca') ? version === 0 : version !== 0;
      const length = transformed ? readBase128() : origLength;
      directory.push({ tag, length });
    }
    const stream = brotliDecompressSync(buffer.subarray(offset, offset + compressedSize));
    let cursor = 0;
    for (const { tag, length } of directory) {
      tables.set(tag, stream.subarray(cursor, cursor + length));
      cursor += length;
    }
    if (cursor > stream.length) throw new Unsupported('WOFF2 table data is truncated');
    if (metaLength) texts.push(brotliDecompressSync(buffer.subarray(metaOffset, metaOffset + metaLength)).toString('utf8'));
    if (privLength) throw new Unsupported('WOFF2 private data block is not inspected');
  } else if (signature === 'wOFF') {
    const numTables = buffer.readUInt16BE(12);
    const metaOffset = buffer.readUInt32BE(24);
    const metaLength = buffer.readUInt32BE(28);
    const privLength = buffer.readUInt32BE(40);
    for (let i = 0; i < numTables; i += 1) {
      const entry = 44 + i * 20;
      const tag = buffer.toString('latin1', entry, entry + 4);
      const off = buffer.readUInt32BE(entry + 4);
      const compLength = buffer.readUInt32BE(entry + 8);
      const origLength = buffer.readUInt32BE(entry + 12);
      const data = buffer.subarray(off, off + compLength);
      tables.set(tag, compLength < origLength ? inflateSync(data) : data);
    }
    if (metaLength) texts.push(inflateSync(buffer.subarray(metaOffset, metaOffset + metaLength)).toString('utf8'));
    if (privLength) throw new Unsupported('WOFF private data block is not inspected');
  } else if (signature === 'OTTO' || signature === 'true' || buffer.readUInt32BE(0) === 0x00010000) {
    const numTables = buffer.readUInt16BE(4);
    for (let i = 0; i < numTables; i += 1) {
      const entry = 12 + i * 16;
      const tag = buffer.toString('latin1', entry, entry + 4);
      const off = buffer.readUInt32BE(entry + 8);
      const length = buffer.readUInt32BE(entry + 12);
      tables.set(tag, buffer.subarray(off, off + length));
    }
  } else {
    throw new Unsupported('unsupported font format');
  }

  const name = tables.get('name');
  if (name && name.length >= 6) {
    const count = name.readUInt16BE(2);
    const storage = name.readUInt16BE(4);
    for (let i = 0; i < count; i += 1) {
      const record = 6 + i * 12;
      if (record + 12 > name.length) break;
      const platform = name.readUInt16BE(record);
      const length = name.readUInt16BE(record + 8);
      const start = storage + name.readUInt16BE(record + 10);
      const bytes = name.subarray(start, start + length);
      texts.push(platform === 1 ? bytes.toString('latin1') : decodeUTF16BE(bytes));
    }
  }
  const post = tables.get('post');
  if (post && post.length >= 34 && post.readUInt32BE(0) === 0x00020000) {
    const glyphs = post.readUInt16BE(32);
    let cursor = 34 + glyphs * 2;
    while (cursor < post.length) {
      const length = post[cursor];
      texts.push(post.toString('latin1', cursor + 1, cursor + 1 + length));
      cursor += 1 + length;
    }
  }
  return texts.join('\n');
}

// ---------------------------------------------------------------------------
// Archives (parsed in-process; members validated, then scanned in memory)

export function validateMemberPath(name) {
  if (!name || name.includes('\0')) throw new Unsupported('archive member with empty or NUL name');
  if (name.startsWith('/') || name.startsWith('\\') || /^[A-Za-z]:[\\/]/.test(name)) {
    throw new Unsupported('archive member with an absolute path');
  }
  if (name.split(/[\\/]/).includes('..')) throw new Unsupported('archive member escaping its root');
  return name.replace(/\\/g, '/');
}

export class ArchiveBudget {
  constructor() {
    this.bytes = 0;
    this.entries = 0;
  }

  take(size) {
    this.bytes += size;
    this.entries += 1;
    if (this.bytes > LIMITS.maxArchiveExpandedBytes) throw new Unsupported('archive expands beyond the size limit');
    if (this.entries > LIMITS.maxArchiveEntries) throw new Unsupported('archive has too many entries');
  }
}

/** Entries of a ZIP archive: { name, data, text? } (directories omitted). */
export function zipEntries(buffer, budget = new ArchiveBudget()) {
  let eocd = -1;
  for (let i = buffer.length - 22; i >= Math.max(0, buffer.length - 22 - 65535); i -= 1) {
    if (buffer.readUInt32LE(i) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new Unsupported('ZIP end record not found');
  const count = buffer.readUInt16LE(eocd + 10);
  const cdOffset = buffer.readUInt32LE(eocd + 16);
  const commentLength = buffer.readUInt16LE(eocd + 20);
  if (count === 0xffff || cdOffset === 0xffffffff) throw new Unsupported('ZIP64 archives are not supported');
  const entries = [{ name: '(zip comment)', data: buffer.subarray(eocd + 22, eocd + 22 + commentLength), text: true }];
  let offset = cdOffset;
  for (let i = 0; i < count; i += 1) {
    if (offset + 46 > buffer.length || buffer.readUInt32LE(offset) !== 0x02014b50) throw new Unsupported('corrupt ZIP central directory');
    const flags = buffer.readUInt16LE(offset + 8);
    const method = buffer.readUInt16LE(offset + 10);
    const compressedSize = buffer.readUInt32LE(offset + 20);
    const size = buffer.readUInt32LE(offset + 24);
    const nameLength = buffer.readUInt16LE(offset + 28);
    const extraLength = buffer.readUInt16LE(offset + 30);
    const entryCommentLength = buffer.readUInt16LE(offset + 32);
    const external = buffer.readUInt32LE(offset + 38);
    const localOffset = buffer.readUInt32LE(offset + 42);
    const rawName = buffer.toString('utf8', offset + 46, offset + 46 + nameLength);
    const commentStart = offset + 46 + nameLength + extraLength;
    const entryComment = buffer.toString('utf8', commentStart, commentStart + entryCommentLength);
    offset = commentStart + entryCommentLength;

    const name = validateMemberPath(rawName);
    if (entryComment) entries.push({ name: `${name} (comment)`, data: Buffer.from(entryComment), text: true });
    const type = (external >>> 16) & 0o170000;
    if (type === 0o120000) throw new Unsupported('ZIP member is a symbolic link');
    if (type && type !== 0o100000 && type !== 0o040000) throw new Unsupported('ZIP member of a special type');
    if (flags & 1) throw new Unsupported('ZIP member is encrypted');
    if (name.endsWith('/')) continue;
    if (size === 0xffffffff || compressedSize === 0xffffffff) throw new Unsupported('ZIP64 members are not supported');
    budget.take(size);
    if (localOffset + 30 > buffer.length || buffer.readUInt32LE(localOffset) !== 0x04034b50) throw new Unsupported('corrupt ZIP local header');
    const start = localOffset + 30 + buffer.readUInt16LE(localOffset + 26) + buffer.readUInt16LE(localOffset + 28);
    const compressed = buffer.subarray(start, start + compressedSize);
    let data;
    if (method === 0) data = compressed;
    else if (method === 8) data = inflateRawSync(compressed, { maxOutputLength: Math.max(size, 1) });
    else throw new Unsupported(`ZIP compression method ${method} is not supported`);
    if (data.length !== size) throw new Unsupported('ZIP member size mismatch');
    entries.push({ name, data });
  }
  return entries;
}

/** Entries of a (ustar/pax/GNU) TAR archive: { name, data, text? }. */
export function tarEntries(buffer, budget = new ArchiveBudget()) {
  const entries = [];
  let offset = 0;
  let longName = null;
  let paxPath = null;
  const field = (start, length) => buffer.toString('utf8', offset + start, offset + start + length).replace(/\0.*$/s, '');
  while (offset + 512 <= buffer.length) {
    if (buffer.subarray(offset, offset + 512).every((b) => b === 0)) break;
    const size = parseInt(field(124, 12).trim() || '0', 8);
    if (!Number.isFinite(size) || size < 0) throw new Unsupported('corrupt TAR header');
    const type = String.fromCharCode(buffer[offset + 156] || 48);
    const prefix = field(345, 155);
    let name = longName ?? paxPath ?? (prefix ? `${prefix}/${field(0, 100)}` : field(0, 100));
    const data = buffer.subarray(offset + 512, offset + 512 + size);
    offset += 512 + Math.ceil(size / 512) * 512;

    if (type === 'L') {
      longName = data.toString('utf8').replace(/\0.*$/s, '');
      continue;
    }
    if (type === 'x' || type === 'g') {
      const text = data.toString('utf8');
      entries.push({ name: '(pax header)', data, text: true });
      if (type === 'x') {
        const match = /\d+ path=([^\n]*)\n/.exec(text);
        paxPath = match ? match[1] : null;
        if (/\d+ linkpath=/.test(text)) throw new Unsupported('TAR member is a link');
      }
      continue;
    }
    longName = null;
    paxPath = null;
    name = validateMemberPath(name);
    if (type === '5') continue;
    if (type === '1' || type === '2') throw new Unsupported('TAR member is a link');
    if (type !== '0' && type !== '7') throw new Unsupported(`TAR member of special type ${type}`);
    budget.take(size);
    entries.push({ name, data });
  }
  return entries;
}

// ---------------------------------------------------------------------------
// External tools (injectable for tests)

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', maxBuffer: 512 * 1024 * 1024, ...options });
  if (result.error) throw new Unsupported(`${command} unavailable (${result.error.code ?? result.error.message})`);
  if (result.status !== 0) throw new Unsupported(`${command} failed (${String(result.stderr ?? '').trim().split('\n')[0] || `exit ${result.status}`})`);
  return result.stdout;
}

export const defaultTools = {
  ocr: (imagePath) => run('tesseract', [imagePath, 'stdout', '--psm', '3']),
  pdfText: (pdfPath) => run('pdftotext', ['-q', pdfPath, '-']),
  pdfInfo: (pdfPath) => `${run('pdfinfo', [pdfPath])}\n${run('pdfinfo', ['-meta', pdfPath])}`,
  pdfPages: (pdfPath, outputDir) => {
    run('pdftoppm', ['-r', '150', '-l', String(LIMITS.maxPdfPages + 1), '-png', pdfPath, join(outputDir, 'page')]);
    return readdirSync(outputDir).filter((f) => f.endsWith('.png')).sort().map((f) => join(outputDir, f));
  },
  plistToXML: (plistPath) => {
    if (process.platform !== 'darwin') throw new Unsupported('binary plists need plutil (macOS)');
    return run('plutil', ['-convert', 'xml1', '-o', '-', plistPath]);
  },
  mountDMG: (dmgPath, mountPoint) => {
    if (process.platform !== 'darwin') throw new Unsupported('DMG inspection needs macOS (hdiutil)');
    run('hdiutil', ['attach', '-readonly', '-nobrowse', '-noautoopen', '-mountpoint', mountPoint, dmgPath]);
  },
  unmountDMG: (mountPoint) => run('hdiutil', ['detach', mountPoint, '-force']),
};

// ---------------------------------------------------------------------------
// Scanner

export function classify(buffer, name = '') {
  if (name.toLowerCase().endsWith('.dmg')) return 'dmg';
  if (buffer.length >= 8 && buffer.readUInt32BE(0) === 0x89504e47) return 'png';
  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return 'jpeg';
  if (buffer.length >= 5 && buffer.toString('latin1', 0, 5) === '%PDF-') return 'pdf';
  if (buffer.length >= 8 && buffer.toString('latin1', 0, 4) === 'icns') return 'icns';
  if (buffer.length >= 4 && buffer.readUInt32LE(0) === 0x04034b50) return 'zip';
  if (buffer.length >= 22 && buffer.readUInt32LE(0) === 0x06054b50) return 'zip';
  if (buffer.length >= 2 && buffer[0] === 0x1f && buffer[1] === 0x8b) return 'gzip';
  if (buffer.length >= 262 && buffer.toString('latin1', 257, 262) === 'ustar') return 'tar';
  if (buffer.length >= 8 && buffer.toString('latin1', 0, 8) === 'bplist00') return 'bplist';
  if (buffer.length >= 8) {
    const be = buffer.readUInt32BE(0);
    const le = buffer.readUInt32LE(0);
    if (be === 0xcafebabe && buffer.readUInt32BE(4) > 0 && buffer.readUInt32BE(4) < 32) return 'macho';
    if (be === 0xcafebabf || le === 0xfeedfacf || le === 0xfeedface) return 'macho';
    const sig = buffer.toString('latin1', 0, 4);
    if (sig === 'wOF2' || sig === 'wOFF' || sig === 'OTTO' || sig === 'true' || be === 0x00010000) return 'font';
  }
  if (buffer.length === 0 || isUTF8Text(buffer)) {
    if (buffer.toString('utf8', 0, 200).startsWith('version https://git-lfs.github.com/spec/')) return 'lfs-pointer';
    return 'text';
  }
  return 'unknown';
}

export class Scanner {
  constructor(policy, options = {}) {
    this.policy = policy;
    this.tools = { ...defaultTools, ...(options.tools ?? {}) };
    this.findings = [];
    this.incomplete = [];
    this.fileCount = 0;
    this.commitCount = 0;
  }

  report(where, results) {
    for (const result of results) this.findings.push({ where, ...result });
  }

  scanString(where, text) {
    this.report(where, scanText(text, this.policy));
  }

  scanName(label) {
    this.report(`${label} (name)`, scanText(label, this.policy).map(({ rule }) => ({ rule, line: 0 })));
  }

  scanPath(path, label = path) {
    let stat;
    try {
      stat = lstatSync(path);
    } catch (error) {
      this.incomplete.push({ where: label, reason: `unreadable (${error.code})` });
      return;
    }
    this.scanName(basename(label));
    if (stat.isSymbolicLink()) {
      this.scanString(`${label} (link target)`, readlinkSync(path));
      return;
    }
    if (stat.isDirectory()) {
      for (const entry of readdirSync(path).sort()) {
        if (entry === '.git') continue;
        this.scanPath(join(path, entry), `${label}/${entry}`);
      }
      return;
    }
    if (!stat.isFile()) {
      this.incomplete.push({ where: label, reason: 'special file' });
      return;
    }
    if (stat.size > LIMITS.maxFileBytes) {
      this.incomplete.push({ where: label, reason: 'file too large to inspect' });
      return;
    }
    if (label.toLowerCase().endsWith('.dmg')) {
      this.fileCount += 1;
      this.guard(label, () => this.scanDMG(path, label));
      return;
    }
    this.scanBuffer(readFileSync(path), label, 0, path);
  }

  guard(label, work) {
    try {
      work();
    } catch (error) {
      this.incomplete.push({ where: label, reason: error instanceof Unsupported ? error.message : `inspection failed (${error.message})` });
    }
  }

  /** Scans content; `diskPath` is set when the bytes already live in a file tools can read. */
  scanBuffer(buffer, label, depth = 0, diskPath = null) {
    this.fileCount += 1;
    this.guard(label, () => {
      const kind = classify(buffer, label);
      switch (kind) {
        case 'text':
          this.scanString(label, buffer.toString('utf8'));
          if (label.toLowerCase().endsWith('.svg')) {
            throw new Unsupported('SVG can draw text as paths, which cannot be inspected; publish a PNG instead');
          }
          return;
        case 'png':
        case 'jpeg':
          this.scanString(`${label} (metadata)`, imageMetadataText(buffer));
          this.withFile(buffer, diskPath, kind === 'png' ? '.png' : '.jpg', (file) => this.scanString(`${label} (image text)`, this.tools.ocr(file)));
          return;
        case 'icns':
          for (const { type, data } of icnsRenditions(buffer)) this.scanBuffer(data, `${label}#${type}`, depth + 1);
          return;
        case 'pdf':
          this.withFile(buffer, diskPath, '.pdf', (file) => {
            this.scanString(`${label} (pdf text)`, this.tools.pdfText(file));
            this.scanString(`${label} (pdf metadata)`, this.tools.pdfInfo(file));
            const pagesDir = mkdtempSync(join(tmpdir(), 'publication-check-pages-'));
            try {
              const pages = this.tools.pdfPages(file, pagesDir);
              if (pages.length === 0) throw new Unsupported('PDF rendered no pages');
              if (pages.length > LIMITS.maxPdfPages) throw new Unsupported('PDF has too many pages to OCR');
              pages.forEach((page, index) => this.scanString(`${label} (page ${index + 1} image text)`, this.tools.ocr(page)));
            } finally {
              rmSync(pagesDir, { recursive: true, force: true });
            }
          });
          return;
        case 'macho':
          this.scanString(`${label} (Mach-O strings)`, machOText(buffer));
          return;
        case 'font':
          this.scanString(`${label} (font names)`, fontText(buffer));
          return;
        case 'bplist':
          this.withFile(buffer, diskPath, '.plist', (file) => this.scanString(`${label} (plist)`, this.tools.plistToXML(file)));
          return;
        case 'zip':
        case 'tar':
        case 'gzip':
          this.scanArchive(buffer, label, kind, depth);
          return;
        case 'lfs-pointer':
          throw new Unsupported('Git LFS pointer: the referenced content is not in the tree and cannot be inspected');
        default:
          throw new Unsupported('unsupported binary format');
      }
    });
  }

  withFile(buffer, diskPath, extension, work) {
    if (diskPath) return work(diskPath);
    const dir = mkdtempSync(join(tmpdir(), 'publication-check-member-'));
    try {
      const file = join(dir, `member${extension}`);
      writeFileSync(file, buffer);
      return work(file);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }

  scanArchive(buffer, label, kind, depth) {
    if (depth >= LIMITS.maxArchiveDepth) throw new Unsupported('archives nested too deeply');
    const budget = new ArchiveBudget();
    let entries;
    if (kind === 'zip') {
      entries = zipEntries(buffer, budget);
    } else {
      let tar = buffer;
      if (kind === 'gzip') {
        tar = gunzipSync(buffer, { maxOutputLength: LIMITS.maxArchiveExpandedBytes });
        if (!(tar.length >= 262 && tar.toString('latin1', 257, 262) === 'ustar')) {
          this.scanBuffer(tar, `${label}!(gunzipped)`, depth + 1);
          return;
        }
      }
      entries = tarEntries(tar, budget);
    }
    for (const entry of entries) {
      const memberLabel = `${label}!/${entry.name}`;
      this.scanName(entry.name);
      if (entry.text) this.scanString(memberLabel, entry.data.toString('utf8'));
      else this.scanBuffer(entry.data, memberLabel, depth + 1);
    }
  }

  scanDMG(path, label) {
    const mountPoint = mkdtempSync(join(tmpdir(), 'publication-check-dmg-'));
    this.tools.mountDMG(path, mountPoint);
    try {
      this.scanPath(mountPoint, `${label}!`);
    } finally {
      try {
        this.tools.unmountDMG(mountPoint);
      } catch (error) {
        this.incomplete.push({ where: label, reason: `could not detach (${error.message})` });
      }
    }
  }

  scanGitRange(range, cwd = process.cwd()) {
    const separator = '\u001e';
    const log = run('git', ['log', `--format=%H%n%an <%ae>%n%cn <%ce>%n%B${separator}`, range], { cwd });
    for (const entry of log.split(separator)) {
      const text = entry.trim();
      if (!text) continue;
      const hash = text.split('\n', 1)[0];
      this.commitCount += 1;
      this.scanString(`commit ${hash.slice(0, 12)}`, text.slice(hash.length));
    }
  }

  get exitCode() {
    if (this.incomplete.length > 0) return 2;
    return this.findings.length > 0 ? 1 : 0;
  }
}

export function trackedFiles(cwd = process.cwd()) {
  return execFileSync('git', ['ls-files', '-z'], { cwd, encoding: 'utf8' }).split('\0').filter(Boolean);
}

// ---------------------------------------------------------------------------
// CLI

function main(argv) {
  const args = [...argv];
  let policyPath = DEFAULT_POLICY;
  let mode = 'token';
  const targets = [];
  const texts = [];
  let tracked = false;
  let gitRange = null;
  let fingerprintMode = false;

  while (args.length) {
    const arg = args.shift();
    if (arg === '--policy') policyPath = resolve(args.shift() ?? '');
    else if (arg === '--tracked') tracked = true;
    else if (arg === '--git-range') gitRange = args.shift();
    else if (arg === '--text') texts.push(args.shift() ?? '');
    else if (arg === '--fingerprint') fingerprintMode = true;
    else if (arg === '--mode') mode = args.shift();
    else if (arg === '--help' || arg === '-h') {
      console.log('See the header of scripts/publication-check.mjs for usage.');
      return 0;
    } else targets.push(arg);
  }

  if (fingerprintMode) {
    if (mode !== 'token' && mode !== 'stream') {
      console.error('--mode must be token or stream');
      return 2;
    }
    const terms = readFileSync(0, 'utf8').split('\n').map((t) => t.trim()).filter(Boolean);
    console.log(JSON.stringify(terms.map((term, i) => ({
      id: `R${i + 1}`, mode, length: normalizeStream(term).length, sha256: fingerprint(term),
    })), null, 2));
    return 0;
  }

  let policy;
  try {
    policy = loadPolicy(policyPath);
  } catch (error) {
    console.error(`publication-check: cannot load policy: ${error.message}`);
    return 2;
  }
  const scanner = new Scanner(policy);

  if (tracked) {
    const root = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
    for (const file of trackedFiles(root)) {
      const absolute = join(root, file);
      if (!existsSync(absolute) && !lstatSync(absolute, { throwIfNoEntry: false })) {
        scanner.incomplete.push({ where: file, reason: 'tracked file missing from working tree' });
        continue;
      }
      scanner.scanPath(absolute, file);
    }
  }
  for (const target of targets) {
    const absolute = resolve(target);
    const shown = relative(process.cwd(), absolute);
    scanner.scanPath(absolute, shown && !shown.startsWith('..') ? shown : absolute);
  }
  texts.forEach((text, index) => scanner.scanString(`--text #${index + 1}`, text));
  if (gitRange) {
    try {
      scanner.scanGitRange(gitRange);
    } catch (error) {
      scanner.incomplete.push({ where: `git range ${gitRange}`, reason: error.message });
    }
  }
  if (!tracked && targets.length === 0 && texts.length === 0 && !gitRange) {
    console.error('publication-check: nothing to scan (use --tracked, paths, --text or --git-range)');
    return 2;
  }

  for (const finding of scanner.findings) {
    console.error(`PROHIBITED  ${finding.where}${finding.line ? `:${finding.line}` : ''}  rule ${finding.rule}`);
  }
  for (const problem of scanner.incomplete) {
    console.error(`INCOMPLETE  ${problem.where}  ${problem.reason}`);
  }
  const commits = gitRange ? `, ${scanner.commitCount} commits` : '';
  const summary = `publication-check: ${scanner.fileCount} items${commits}, ${scanner.findings.length} prohibited references, ${scanner.incomplete.length} incomplete`;
  if (scanner.exitCode === 0) console.log(`${summary}. OK`);
  else console.error(`${summary}. FAILED (matched text is never printed).`);
  return scanner.exitCode;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
