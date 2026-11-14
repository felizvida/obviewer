// Markdown -> HTML for Obviewer. Pure: runs in Node (tests) and in WebKit.
//
// Flavors:
//   "markdown" - CommonMark + GitHub Flavored Markdown (+ [[wiki links]], math)
//   "obsidian" - everything above + embeds, callouts, ==highlight==, %%comments%%,
//                #tags, ^block-ids, soft line breaks as <br>

import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import katex from 'katex';
import hljs from 'highlight.js/lib/common';

import { obsidianInlinePlugin, wikilinkOnlyPlugin } from './plugins/obsidian.js';
import { calloutPlugin } from './plugins/callouts.js';
import { mathPlugin, renderMath } from './plugins/math.js';
import { taskListPlugin, headingAnchorPlugin } from './plugins/structure.js';
import {
  attachmentKindForPath,
  escapeAttr,
  escapeHtml,
  extensionOf,
  folderOf,
  hasScheme,
  isExternalUrl,
  normalizeHeadingText,
  parseSizeHint,
  sizeAttrs,
  stripFrontmatter,
  stripObsidianComments,
  vaultAssetURL,
} from './util.js';

export const MAX_EMBED_DEPTH = 4;

const instances = new Map();

/**
 * @param {string} flavor  "markdown" | "obsidian"
 * @param {boolean} staticMode  Static previews (Quick Look): raw HTML is shown as text, no scripts run later.
 */
export function getMarkdownIt(flavor, staticMode = false) {
  const base = flavor === 'obsidian' ? 'obsidian' : 'markdown';
  const key = staticMode ? `${base}:static` : base;
  if (!instances.has(key)) instances.set(key, createMarkdownIt(base, staticMode));
  return instances.get(key);
}

function createMarkdownIt(flavor, staticMode) {
  const obsidian = flavor === 'obsidian';
  const md = new MarkdownIt({
    // The live reader sanitizes with DOMPurify; static previews have no DOM, so raw HTML stays text.
    html: !staticMode,
    linkify: true,
    typographer: false,
    breaks: obsidian,
    highlight: null,
  });
  md.linkify.set({ fuzzyLink: false, fuzzyEmail: false });

  md.use(footnote);
  md.use(mathPlugin, { katex });
  md.use(calloutPlugin);
  md.use(taskListPlugin);
  if (obsidian) md.use(obsidianInlinePlugin, { tags: true });
  else md.use(wikilinkOnlyPlugin);
  md.use(headingAnchorPlugin);

  installRenderers(md);
  return md;
}

function installRenderers(md) {
  md.renderer.rules.fence = (tokens, idx, options, env) => renderFence(tokens[idx], env);
  md.renderer.rules.code_block = (tokens, idx) => `<pre class="code-block"><code>${escapeHtml(tokens[idx].content)}</code></pre>\n`;

  md.renderer.rules.ob_wikilink = (tokens, idx, options, env) => renderWikilink(tokens[idx].meta, env);
  md.renderer.rules.ob_embed = (tokens, idx, options, env) => renderEmbed(tokens[idx].meta, env);
  md.renderer.rules.ob_tag = (tokens, idx) => {
    const tag = tokens[idx].content;
    return `<a class="tag" href="#" data-tag="${escapeAttr(tag)}">#${escapeHtml(tag)}</a>`;
  };

  const defaultLinkOpen = md.renderer.rules.link_open
    ?? ((tokens, idx, options, env, self) => self.renderToken(tokens, idx, options));
  md.renderer.rules.link_open = (tokens, idx, options, env, self) => {
    const token = tokens[idx];
    const href = token.attrGet('href') || '';
    if (href.startsWith('#')) {
      token.attrJoin('class', 'anchor-link');
    } else if (isExternalUrl(href)) {
      token.attrJoin('class', 'external-link');
      token.attrSet('data-external', 'true');
    } else if (hasScheme(href)) {
      // Unknown schemes (javascript:, file:, vbscript:, ...) never become live links.
      token.attrs = (token.attrs || []).filter(([name]) => name !== 'href');
      token.attrJoin('class', 'inert-link');
    } else {
      const kind = attachmentKindForPath(href);
      token.attrJoin('class', kind === 'note' ? 'internal-link' : 'attachment-link');
      token.attrSet('data-href', href);
      token.attrSet('data-from', env.ctx?.noteID ?? '');
    }
    return defaultLinkOpen(tokens, idx, options, env, self);
  };

  md.renderer.rules.image = (tokens, idx, options, env, self) => {
    const token = tokens[idx];
    const src = token.attrGet('src') || '';
    let alt = self.renderInlineAsText(token.children ?? [], options, env);
    let size = null;
    const pipe = alt.lastIndexOf('|');
    if (pipe >= 0) {
      size = parseSizeHint(alt.slice(pipe + 1));
      if (size) alt = alt.slice(0, pipe).trim();
    }
    const title = token.attrGet('title');
    const titleAttr = title ? ` title="${escapeAttr(title)}"` : '';
    if (env.ctx?.staticMode) return staticImage(alt || src);
    if (hasScheme(src) && !src.startsWith('data:')) {
      // Remote images are blocked by the reader's network policy; show a placeholder link.
      return `<a class="remote-image external-link" data-external="true" href="${escapeAttr(src)}">`
        + `<span class="remote-image-label">Remote image not loaded</span> ${escapeHtml(alt || src)}</a>`;
    }
    const url = src.startsWith('data:') ? src : vaultAssetURL(src, env.ctx ?? {});
    return `<img class="note-image" src="${escapeAttr(url)}" alt="${escapeAttr(alt)}"${titleAttr}${sizeAttrs(size)} loading="lazy" data-ob-asset="1">`;
  };
}

function staticImage(label) {
  return `<span class="static-image">Image: ${escapeHtml(label)}</span>`;
}

function renderFence(token, env) {
  const info = (token.info || '').trim();
  const lang = info.split(/\s+/)[0].toLowerCase();
  const code = token.content;

  if (lang === 'mermaid' && env.ctx?.staticMode) {
    return `<figure class="plugin-block" data-plugin="mermaid"><figcaption>Diagram — open in Obviewer to see it drawn</figcaption>`
      + `<pre class="code-block"><code>${escapeHtml(code)}</code></pre></figure>\n`;
  }
  if (lang === 'mermaid') {
    return `<figure class="mermaid-block" data-state="pending"><pre class="mermaid">${escapeHtml(code)}</pre></figure>\n`;
  }
  if (lang === 'math' || lang === 'latex' || lang === 'katex') {
    return `${renderMath(katex, code, true)}\n`;
  }
  if (lang === 'dataview' || lang === 'dataviewjs' || lang === 'query' || lang === 'tasks') {
    return `<figure class="plugin-block" data-plugin="${escapeAttr(lang)}">`
      + `<figcaption>${escapeHtml(lang)} block — queries aren't run in Obviewer</figcaption>`
      + `<pre class="code-block"><code>${escapeHtml(code)}</code></pre></figure>\n`;
  }

  let highlighted = null;
  if (lang && hljs.getLanguage(lang)) {
    try {
      highlighted = hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
    } catch {
      highlighted = null;
    }
  }
  const langClass = lang ? ` language-${escapeAttr(lang)}` : '';
  const label = lang ? `<span class="code-lang">${escapeHtml(lang)}</span>` : '';
  return `<div class="code-wrapper">${label}<pre class="code-block"><code class="hljs${langClass}">${highlighted ?? escapeHtml(code)}</code></pre></div>\n`;
}

function renderWikilink(meta, env) {
  const ctx = env.ctx ?? {};
  const label = meta.alias || (meta.note
    ? (meta.anchor ? `${meta.note} › ${meta.anchor.replace(/^\^/, '')}` : meta.note)
    : (meta.anchor ?? '').replace(/^\^/, ''));
  const classes = ['wikilink'];
  if (meta.note && ctx.resolvedLinks && ctx.resolvedLinks[meta.note] === false) classes.push('is-unresolved');
  const anchorAttr = meta.anchor ? ` data-anchor="${escapeAttr(meta.anchor)}"` : '';
  return `<a class="${classes.join(' ')}" href="#" data-wikilink="${escapeAttr(meta.note)}"${anchorAttr}`
    + ` data-from="${escapeAttr(ctx.noteID ?? '')}" title="${escapeAttr(meta.raw)}">${escapeHtml(label)}</a>`;
}

// ---------------------------------------------------------------------------
// Embeds

function renderEmbed(meta, env) {
  const ctx = env.ctx ?? {};
  const entry = ctx.embeds?.[meta.raw];
  const size = parseSizeHint(meta.alias);

  if (entry?.status === 'ok' && entry.kind === 'note') {
    return renderNoteEmbed(meta, entry, env);
  }
  if (entry?.status === 'ok' && entry.kind && entry.kind !== 'note') {
    return renderAttachmentEmbed(entry.path, entry.kind, meta, size, { ...ctx, folder: '' }, entry);
  }
  if (entry && entry.status !== 'ok') {
    return embedProblem(meta, entry.status);
  }

  // No resolution from Swift (e.g. Quick Look or a lone file): guess from the extension.
  const kind = attachmentKindForPath(meta.note);
  if (kind !== 'note') return renderAttachmentEmbed(meta.note, kind, meta, size, ctx, null);
  return embedProblem(meta, 'unavailable');
}

function embedProblem(meta, status) {
  const messages = {
    missing: 'Embedded note not found',
    cycle: 'Embed skipped: it would include itself',
    depth: 'Embed skipped: nested too deeply',
    unavailable: 'Embedded note isn’t available here',
    unreadable: 'Embedded file couldn’t be read',
    tooLarge: 'Embed skipped: content too large',
  };
  const message = messages[status] ?? 'Embed unavailable';
  return `<div class="embed embed-problem" data-status="${escapeAttr(status)}">`
    + `<span class="embed-problem-label">${escapeHtml(message)}</span> `
    + `<a class="wikilink${status === 'missing' ? ' is-unresolved' : ''}" href="#" data-wikilink="${escapeAttr(meta.note)}"`
    + `${meta.anchor ? ` data-anchor="${escapeAttr(meta.anchor)}"` : ''}>${escapeHtml(meta.raw)}</a></div>`;
}

function renderAttachmentEmbed(path, kind, meta, size, ctx, entry) {
  const name = entry?.name || path.split('/').pop();
  if (ctx.staticMode) return kind === 'image' ? staticImage(name) : `<span class="static-image">${escapeHtml(kind)}: ${escapeHtml(name)}</span>`;
  const url = vaultAssetURL(path, ctx);
  if (kind === 'image') {
    const alt = meta.alias && !size ? meta.alias : name;
    return `<img class="note-image embed-image" src="${escapeAttr(url)}" alt="${escapeAttr(alt)}"${sizeAttrs(size)} loading="lazy" data-ob-asset="1">`;
  }
  const icons = { pdf: 'PDF', audio: 'Audio', video: 'Video', file: 'File' };
  return `<div class="embed embed-attachment" data-kind="${escapeAttr(kind)}">`
    + `<span class="embed-attachment-kind">${icons[kind] ?? 'File'}</span>`
    + `<a class="attachment-link" href="#" data-href="${escapeAttr(path)}" data-from="${escapeAttr(ctx.noteID ?? '')}"`
    + ` data-asset-url="${escapeAttr(url)}">${escapeHtml(name)}</a>`
    + `<span class="embed-attachment-hint">Opens in its default app</span></div>`;
}

function renderNoteEmbed(meta, entry, env) {
  const ctx = env.ctx ?? {};
  const depth = (ctx.depth ?? 0) + 1;
  if (depth > MAX_EMBED_DEPTH) return embedProblem(meta, 'depth');

  const counter = env.embedCounter ?? (env.embedCounter = { value: 0 });
  counter.value += 1;
  const childCtx = {
    ...ctx,
    noteID: entry.noteID,
    folder: folderOf(entry.relativePath ?? entry.noteID ?? ''),
    embeds: entry.embeds ?? {},
    depth,
  };
  const childEnv = {
    ctx: childCtx,
    slugRegistry: env.slugRegistry,
    idPrefix: `embed${counter.value}`,
    embedCounter: counter,
  };
  const body = renderMarkdownBody(entry.markdown ?? '', ctx.flavor ?? 'obsidian', childEnv, meta.anchor);
  if (body == null) return embedProblem(meta, 'missing');

  const titleLabel = meta.anchor ? `${entry.title ?? meta.note} › ${meta.anchor.replace(/^\^/, '')}` : (entry.title ?? meta.note);
  return `<section class="embed embed-note" data-note-id="${escapeAttr(entry.noteID ?? '')}">`
    + `<header class="embed-header"><a class="wikilink embed-title" href="#" data-wikilink="${escapeAttr(meta.note)}"`
    + `${meta.anchor ? ` data-anchor="${escapeAttr(meta.anchor)}"` : ''} data-from="${escapeAttr(ctx.noteID ?? '')}">${escapeHtml(titleLabel)}</a></header>`
    + `<div class="embed-body">${body}</div></section>`;
}

// ---------------------------------------------------------------------------
// Sections (for ![[Note#Heading]] and ![[Note#^block]])

function topLevelBlocks(tokens) {
  const blocks = [];
  let i = 0;
  while (i < tokens.length) {
    const start = i;
    if (tokens[i].nesting === 1) {
      let depth = 0;
      for (; i < tokens.length; i += 1) {
        depth += tokens[i].nesting;
        if (depth === 0) break;
      }
    }
    blocks.push({ start, end: i + 1 });
    i += 1;
  }
  return blocks;
}

export function selectSection(tokens, anchor) {
  if (!anchor) return tokens;
  const blocks = topLevelBlocks(tokens);

  if (anchor.startsWith('^')) {
    const id = anchor;
    for (const block of blocks) {
      for (let j = block.start; j < block.end; j += 1) {
        if (tokens[j].attrGet && tokens[j].attrGet('id') === id) {
          // Prefer the innermost list item / paragraph that carries the id.
          if (tokens[j].type === 'list_item_open') {
            let depth = 0;
            let k = j;
            for (; k < block.end; k += 1) {
              depth += tokens[k].nesting;
              if (depth === 0) break;
            }
            return [
              Object.assign(new tokens[j].constructor('bullet_list_open', 'ul', 1), { block: true }),
              ...tokens.slice(j, k + 1),
              Object.assign(new tokens[j].constructor('bullet_list_close', 'ul', -1), { block: true }),
            ];
          }
          return tokens.slice(block.start, block.end);
        }
      }
    }
    return null;
  }

  const wanted = normalizeHeadingText(anchor);
  for (let b = 0; b < blocks.length; b += 1) {
    const open = tokens[blocks[b].start];
    if (open.type !== 'heading_open') continue;
    const text = normalizeHeadingText(open.attrGet('data-heading') ?? tokens[blocks[b].start + 1].content);
    if (text !== wanted) continue;
    const level = Number(open.tag.slice(1));
    let endIndex = tokens.length;
    for (let c = b + 1; c < blocks.length; c += 1) {
      const candidate = tokens[blocks[c].start];
      if (candidate.type === 'heading_open' && Number(candidate.tag.slice(1)) <= level) {
        endIndex = blocks[c].start;
        break;
      }
    }
    return tokens.slice(blocks[b].start, endIndex);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Public entry points

export function preprocessMarkdown(source, flavor) {
  let text = stripFrontmatter(source).replace(/\r\n?/g, '\n');
  if (flavor === 'obsidian') text = stripObsidianComments(text);
  return text;
}

function renderMarkdownBody(source, flavor, env, anchor) {
  const md = getMarkdownIt(flavor, env.ctx?.staticMode);
  const text = preprocessMarkdown(source, flavor);
  const tokens = md.parse(text, env);
  const selected = selectSection(tokens, anchor);
  if (selected == null) return null;
  return md.renderer.render(selected, md.options, env);
}

/**
 * Renders a note.
 * @param {string} source  Raw file contents.
 * @param {object} options { flavor, noteID, relativePath, embeds, resolvedLinks, assetBase }
 * @returns {{ html: string, headings: Array<{level:number,text:string,id:string}>, startsWithH1: boolean, firstHeading: string|null }}
 */
export function renderMarkdown(source, options = {}) {
  const flavor = options.flavor === 'obsidian' ? 'obsidian' : 'markdown';
  const ctx = {
    flavor,
    noteID: options.noteID ?? '',
    folder: folderOf(options.relativePath ?? options.noteID ?? ''),
    embeds: options.embeds ?? {},
    resolvedLinks: options.resolvedLinks ?? null,
    assetBase: options.assetBase,
    staticMode: Boolean(options.staticMode),
    depth: 0,
  };
  const env = { ctx, headings: [], slugRegistry: new Map() };
  const md = getMarkdownIt(flavor, ctx.staticMode);
  const text = preprocessMarkdown(source, flavor);
  const tokens = md.parse(text, env);
  const firstBlock = tokens.find((token) => token.type !== 'html_block' || token.content.trim());
  const startsWithH1 = Boolean(firstBlock && firstBlock.type === 'heading_open' && firstBlock.tag === 'h1');
  const html = md.renderer.render(tokens, md.options, env);
  return {
    html,
    headings: env.headings,
    startsWithH1,
    firstHeading: startsWithH1 ? firstBlock.attrGet('data-heading') : null,
  };
}

/** Extracts outbound link targets the way the Swift indexer should see them. */
export function extractLinks(source, options = {}) {
  const flavor = options.flavor === 'obsidian' ? 'obsidian' : 'markdown';
  const md = getMarkdownIt(flavor);
  const env = { ctx: { flavor, noteID: '', folder: '', embeds: {} } };
  const tokens = md.parse(preprocessMarkdown(source, flavor), env);
  const links = [];
  const visit = (list) => {
    for (const token of list) {
      if (token.type === 'ob_wikilink' || token.type === 'ob_embed') {
        if (token.meta.note && attachmentKindForPath(token.meta.note) === 'note') links.push(token.meta.note);
      } else if (token.type === 'link_open') {
        const href = token.attrGet('href') || '';
        if (!hasScheme(href) && !href.startsWith('#')) {
          const path = decodeURIComponentSafe(href.split('#')[0]);
          const ext = extensionOf(path);
          if (path && (ext === 'md' || ext === 'markdown' || ext === '')) links.push(path.replace(/\.(md|markdown)$/i, ''));
        }
      }
      if (token.children) visit(token.children);
    }
  };
  visit(tokens);
  return [...new Set(links)];
}

function decodeURIComponentSafe(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}
