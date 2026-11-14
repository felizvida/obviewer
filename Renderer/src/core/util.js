// Small helpers shared by the Markdown and DokuWiki renderers.
// Everything here is pure so it can run in Node tests and inside WebKit.

export const ASSET_SCHEME = 'obviewer-asset:';
export const VAULT_ASSET_BASE = 'obviewer-asset://vault/';

const HTML_ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };

export function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (ch) => HTML_ESCAPES[ch]);
}

export function escapeAttr(value) {
  return escapeHtml(value);
}

// Returns the folder part of a vault-relative note path ("a/b/note.md" -> "a/b").
export function folderOf(relativePath) {
  if (!relativePath) return '';
  const index = relativePath.lastIndexOf('/');
  return index < 0 ? '' : relativePath.slice(0, index);
}

// Normalizes a POSIX-ish relative path, resolving "." and "..".
// Leading ".." segments that would escape the root are preserved so the
// Swift side can reject them explicitly instead of silently clamping.
export function normalizePath(path) {
  const parts = [];
  for (const segment of String(path).split('/')) {
    if (segment === '' || segment === '.') continue;
    if (segment === '..') {
      if (parts.length > 0 && parts[parts.length - 1] !== '..') parts.pop();
      else parts.push('..');
      continue;
    }
    parts.push(segment);
  }
  return parts.join('/');
}

export function hasScheme(url) {
  return /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(url);
}

export function isExternalUrl(url) {
  return /^(https?:|mailto:|tel:|obsidian:|x-devonthink-item:|zotero:)/i.test(url);
}

export function safeDecodeURI(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

// Builds the custom-scheme URL for a local file referenced from a note.
// `rawPath` is what the note wrote; `fromNoteID` lets Swift fall back to
// Obsidian-style "shortest path" resolution if the literal path is missing.
export function vaultAssetURL(rawPath, ctx) {
  const decoded = safeDecodeURI(String(rawPath).split('#')[0].split('?')[0]);
  const resolved = decoded.startsWith('/')
    ? normalizePath(decoded.slice(1))
    : normalizePath(ctx.folder ? `${ctx.folder}/${decoded}` : decoded);
  const encodedPath = resolved.split('/').map(encodeURIComponent).join('/');
  const query = new URLSearchParams();
  if (ctx.noteID) query.set('from', ctx.noteID);
  query.set('raw', decoded);
  return `${ctx.assetBase || VAULT_ASSET_BASE}${encodedPath}?${query.toString()}`;
}

const IMAGE_EXTENSIONS = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'svg', 'bmp', 'avif', 'tif', 'tiff']);
const AUDIO_EXTENSIONS = new Set(['mp3', 'm4a', 'wav', 'ogg', 'flac', 'aac']);
const VIDEO_EXTENSIONS = new Set(['mp4', 'mov', 'webm', 'm4v']);

export function extensionOf(path) {
  const clean = String(path).split('#')[0].split('?')[0];
  const base = clean.slice(clean.lastIndexOf('/') + 1);
  const dot = base.lastIndexOf('.');
  return dot <= 0 ? '' : base.slice(dot + 1).toLowerCase();
}

export function attachmentKindForPath(path) {
  const ext = extensionOf(path);
  if (IMAGE_EXTENSIONS.has(ext)) return 'image';
  if (AUDIO_EXTENSIONS.has(ext)) return 'audio';
  if (VIDEO_EXTENSIONS.has(ext)) return 'video';
  if (ext === 'pdf') return 'pdf';
  if (ext === '' || ext === 'md' || ext === 'markdown' || ext === 'mdown' || ext === 'txt') return 'note';
  return 'file';
}

// Obsidian size hints: "200" or "200x100".
export function parseSizeHint(value) {
  const match = /^\s*(\d{1,5})(?:\s*x\s*(\d{1,5}))?\s*$/.exec(String(value ?? ''));
  if (!match) return null;
  return { width: Number(match[1]), height: match[2] ? Number(match[2]) : null };
}

export function sizeAttrs(size) {
  if (!size) return '';
  let attrs = ` width="${size.width}"`;
  if (size.height) attrs += ` height="${size.height}"`;
  return attrs;
}

// GitHub-compatible heading slug.
export function slugify(text) {
  return String(text)
    .trim()
    .toLowerCase()
    .replace(/<[^>]*>/g, '')
    .replace(/[^\p{L}\p{N}\s_-]/gu, '')
    .replace(/\s/g, '-');
}

export function normalizeHeadingText(text) {
  return String(text)
    .toLowerCase()
    .replace(/[\s ]+/g, ' ')
    .replace(/[*_`~=[\]]/g, '')
    .trim();
}

export function uniqueSlug(text, registry) {
  const base = slugify(text) || 'section';
  const count = registry.get(base) ?? 0;
  registry.set(base, count + 1);
  return count === 0 ? base : `${base}-${count}`;
}

// Splits "Note#Heading|Alias" into its parts. Escaped pipes (used inside
// tables) are accepted as separators too.
export function parseWikiTarget(inner) {
  const text = String(inner).replace(/\\\|/g, '|');
  const pipe = text.indexOf('|');
  const targetPart = (pipe < 0 ? text : text.slice(0, pipe)).trim();
  const alias = pipe < 0 ? null : text.slice(pipe + 1).trim();
  const hash = targetPart.indexOf('#');
  const note = (hash < 0 ? targetPart : targetPart.slice(0, hash)).trim();
  const anchorChain = hash < 0 ? '' : targetPart.slice(hash + 1);
  const anchors = anchorChain.split('#').map((part) => part.trim()).filter(Boolean);
  const anchor = anchors.length ? anchors[anchors.length - 1] : null;
  return { raw: targetPart, note, anchor, alias };
}

// Removes a leading YAML (---) or TOML (+++) frontmatter block.
export function stripFrontmatter(source) {
  const text = String(source).replace(/^﻿/, '');
  const match = /^(---|\+\+\+)[ \t]*\r?\n([\s\S]*?)\r?\n(---|\.\.\.|\+\+\+)[ \t]*(\r?\n|$)/.exec(text);
  if (!match) return text;
  return text.slice(match[0].length);
}

// Applies `transform` to every part of `source` that is outside fenced code
// blocks and inline code spans. Used for Obsidian %%comments%%.
export function transformOutsideCode(source, transform) {
  const lines = String(source).split('\n');
  const out = [];
  let buffer = [];
  let fence = null;
  const flush = () => {
    if (buffer.length) {
      out.push(transformOutsideInlineCode(buffer.join('\n'), transform));
      buffer = [];
    }
  };
  for (const line of lines) {
    const fenceMatch = /^\s{0,3}(`{3,}|~{3,})/.exec(line);
    if (fence) {
      out.push(line);
      if (fenceMatch && fenceMatch[1][0] === fence[0] && fenceMatch[1].length >= fence.length && line.trim() === fenceMatch[1]) {
        fence = null;
      }
      continue;
    }
    if (fenceMatch) {
      flush();
      fence = fenceMatch[1];
      out.push(line);
      continue;
    }
    buffer.push(line);
  }
  flush();
  return out.join('\n');
}

function transformOutsideInlineCode(text, transform) {
  const parts = text.split(/(`+[^`]*?`+)/g);
  // Re-join non-code parts so a transform can span multiple lines,
  // then splice code spans back in using placeholders.
  const placeholders = [];
  const joined = parts
    .map((part, index) => {
      if (index % 2 === 1) {
        placeholders.push(part);
        return `\u0000${placeholders.length - 1}\u0000`;
      }
      return part;
    })
    .join('');
  return transform(joined).replace(/\u0000(\d+)\u0000/g, (_, n) => placeholders[Number(n)]);
}

export function stripObsidianComments(source) {
  return transformOutsideCode(source, (text) => text.replace(/%%[\s\S]*?%%/g, ''));
}
