// DokuWiki markup -> HTML. Covers the syntax people actually use:
// headings, emphasis, links (namespaces, interwiki, sections), media, lists,
// tables (with colspan), code/file blocks, preformatted text, quotes, rules,
// footnotes, nowiki and the {{tag>...}} plugin. Unknown plugin tags are shown
// as text rather than dropped.
//
// Link targets are resolved to absolute DokuWiki IDs ("ns:sub:page") here so
// the Swift side only has to map an ID to a file.

import { escapeAttr, escapeHtml, isExternalUrl, uniqueSlug, vaultAssetURL } from './util.js';

const INTERWIKI = {
  wp: 'https://en.wikipedia.org/wiki/{NAME}',
  wpde: 'https://de.wikipedia.org/wiki/{NAME}',
  wpfr: 'https://fr.wikipedia.org/wiki/{NAME}',
  wpes: 'https://es.wikipedia.org/wiki/{NAME}',
  doku: 'https://www.dokuwiki.org/{NAME}',
  google: 'https://www.google.com/search?q={NAME}',
  phpfn: 'https://www.php.net/{NAME}',
  github: 'https://github.com/{NAME}',
  doi: 'https://doi.org/{NAME}',
};

// ---------------------------------------------------------------------------
// IDs

export function cleanID(id) {
  return String(id)
    .trim()
    .toLowerCase()
    .replace(/[\s]+/g, '_')
    .replace(/[/;]/g, ':')
    .replace(/:{2,}/g, ':')
    .replace(/^:|:$/g, '');
}

/** Namespace parts of the page with vault-relative path `noteID`. */
export function namespaceOf(noteID, pagesBase = '') {
  let path = String(noteID || '');
  if (pagesBase && path.startsWith(`${pagesBase}/`)) path = path.slice(pagesBase.length + 1);
  const parts = path.replace(/\.txt$/i, '').split('/').filter(Boolean);
  parts.pop();
  return parts;
}

/** Resolves a DokuWiki link target relative to the current namespace. */
export function resolveID(target, currentNamespace) {
  let raw = String(target).trim();
  if (!raw) return '';
  let parts;
  if (raw.startsWith(':')) {
    parts = raw.slice(1).split(':');
  } else if (raw.startsWith('..:') || raw.startsWith('.:') || raw === '.' || raw === '..') {
    parts = [...currentNamespace];
    const segments = raw.split(':');
    for (const segment of segments) {
      if (segment === '..') parts.pop();
      else if (segment === '.') continue;
      else parts.push(segment);
    }
  } else if (raw.includes(':')) {
    parts = raw.split(':');
  } else {
    parts = [...currentNamespace, raw];
  }
  if (raw.endsWith(':')) parts.push('start');
  return cleanID(parts.filter((p) => p !== '').join(':'));
}

// ---------------------------------------------------------------------------
// Inline

const INLINE_PATTERN = new RegExp([
  '(<nowiki>[\\s\\S]*?<\\/nowiki>)', // 1 nowiki
  '(%%[\\s\\S]*?%%)', // 2 %% literal
  "(''[\\s\\S]+?'')", // 3 monospace
  '(\\[\\[[\\s\\S]+?\\]\\])', // 4 link
  '(\\{\\{[\\s\\S]+?\\}\\})', // 5 media
  '(\\(\\([\\s\\S]+?\\)\\))', // 6 footnote
  '(\\*\\*[\\s\\S]+?\\*\\*)', // 7 bold
  '((?<![:\\w])\\/\\/[\\s\\S]+?(?<!:)\\/\\/)', // 8 italic (not in URLs)
  '(__[\\s\\S]+?__)', // 9 underline
  '(<del>[\\s\\S]*?<\\/del>)', // 10
  '(<sub>[\\s\\S]*?<\\/sub>)', // 11
  '(<sup>[\\s\\S]*?<\\/sup>)', // 12
  '(\\\\\\\\(?=\\s|$))', // 13 forced line break
  '(\\b(?:https?|ftp):\\/\\/[^\\s<>\\[\\]"\']+[^\\s<>\\[\\]"\'.,;:!?)])', // 14 bare URL
  '(<[\\w.+-]+@[\\w-]+\\.[\\w.-]+>)', // 15 email
  '(~~[A-Z]+~~)', // 16 macro
].join('|'), 'g');

export function renderInline(text, ctx) {
  let out = '';
  let last = 0;
  INLINE_PATTERN.lastIndex = 0;
  const source = String(text);
  const pattern = new RegExp(INLINE_PATTERN.source, 'g');
  let match;
  while ((match = pattern.exec(source))) {
    out += escapeHtml(source.slice(last, match.index));
    last = match.index + match[0].length;
    const [whole] = match;
    if (match[1]) out += escapeHtml(whole.slice(8, -9));
    else if (match[2]) out += escapeHtml(whole.slice(2, -2));
    else if (match[3]) out += `<code>${escapeHtml(whole.slice(2, -2))}</code>`;
    else if (match[4]) out += renderLink(whole.slice(2, -2), ctx);
    else if (match[5]) out += renderMedia(whole.slice(2, -2), ctx);
    else if (match[6]) out += renderFootnote(whole.slice(2, -2), ctx);
    else if (match[7]) out += `<strong>${renderInline(whole.slice(2, -2), ctx)}</strong>`;
    else if (match[8]) out += `<em>${renderInline(whole.slice(2, -2), ctx)}</em>`;
    else if (match[9]) out += `<u>${renderInline(whole.slice(2, -2), ctx)}</u>`;
    else if (match[10]) out += `<del>${renderInline(whole.slice(5, -6), ctx)}</del>`;
    else if (match[11]) out += `<sub>${renderInline(whole.slice(5, -6), ctx)}</sub>`;
    else if (match[12]) out += `<sup>${renderInline(whole.slice(5, -6), ctx)}</sup>`;
    else if (match[13]) out += '<br>';
    else if (match[14]) out += `<a class="external-link" data-external="true" href="${escapeAttr(whole)}">${escapeHtml(whole)}</a>`;
    else if (match[15]) {
      const email = whole.slice(1, -1);
      out += `<a class="external-link" data-external="true" href="mailto:${escapeAttr(email)}">${escapeHtml(email)}</a>`;
    } else if (match[16]) out += '';
  }
  out += escapeHtml(source.slice(last));
  return out;
}

function renderLink(inner, ctx) {
  const pipe = inner.indexOf('|');
  const target = (pipe < 0 ? inner : inner.slice(0, pipe)).trim();
  const labelSource = pipe < 0 ? null : inner.slice(pipe + 1).trim();
  const label = labelSource ? renderInline(labelSource, ctx) : null;

  if (isExternalUrl(target) || /^(ftp|file):/i.test(target)) {
    return `<a class="external-link" data-external="true" href="${escapeAttr(target)}">${label ?? escapeHtml(target)}</a>`;
  }
  if (/^\\\\/.test(target)) {
    return `<span class="windows-share" title="Windows share links aren’t opened">${label ?? escapeHtml(target)}</span>`;
  }
  const interwiki = /^([a-zA-Z0-9.-_]+)>(.*)$/.exec(target);
  if (interwiki) {
    const template = INTERWIKI[interwiki[1].toLowerCase()];
    if (template) {
      const url = template.replace('{NAME}', encodeURIComponent(interwiki[2]).replace(/%2F/g, '/'));
      return `<a class="external-link interwiki" data-external="true" data-interwiki="${escapeAttr(interwiki[1])}" href="${escapeAttr(url)}">${label ?? escapeHtml(interwiki[2])}</a>`;
    }
    return `<span class="interwiki-unknown" title="Unknown interwiki shortcut">${label ?? escapeHtml(target)}</span>`;
  }

  const hash = target.indexOf('#');
  const pageTarget = hash < 0 ? target : target.slice(0, hash);
  const section = hash < 0 ? null : target.slice(hash + 1).trim();
  if (!pageTarget) {
    return `<a class="anchor-link" href="#${escapeAttr(sectionID(section ?? ''))}">${label ?? escapeHtml(section ?? '')}</a>`;
  }
  const id = resolveID(pageTarget, ctx.namespace);
  const anchorAttr = section ? ` data-anchor="${escapeAttr(section)}"` : '';
  const unresolved = ctx.resolvedLinks && ctx.resolvedLinks[id] === false ? ' is-unresolved' : '';
  const shown = label ?? escapeHtml(labelSource ?? pageTarget.replace(/^[.:]+/, '').split(':').pop());
  return `<a class="wikilink${unresolved}" href="#" data-wikilink="${escapeAttr(id)}"${anchorAttr} data-from="${escapeAttr(ctx.noteID)}" title="${escapeAttr(id)}">${shown}</a>`;
}

function sectionID(text) {
  return String(text).trim().toLowerCase().replace(/\s+/g, '_').replace(/[^\p{L}\p{N}_-]/gu, '');
}

export function mediaPath(target, ctx) {
  const id = resolveID(target, ctx.namespace);
  const path = id.split(':').join('/');
  return ctx.mediaBase ? `/${ctx.mediaBase}/${path}` : `/${path}`;
}

function renderMedia(inner, ctx) {
  if (/^tag>/i.test(inner.trim())) {
    const tags = inner.trim().slice(4).trim().split(/\s+/).filter(Boolean);
    return `<span class="tag-list">${tags.map((tag) => `<a class="tag" href="#" data-tag="${escapeAttr(tag)}">#${escapeHtml(tag)}</a>`).join(' ')}</span>`;
  }
  const leftPad = /^\s/.test(inner);
  const rightPad = /\s$/.test(inner.split('|')[0]);
  const align = leftPad && rightPad ? 'center' : leftPad ? 'right' : rightPad ? 'left' : null;

  const pipe = inner.indexOf('|');
  const ref = (pipe < 0 ? inner : inner.slice(0, pipe)).trim();
  const caption = pipe < 0 ? '' : inner.slice(pipe + 1).trim();
  const [target, query = ''] = ref.split('?');
  const sizeMatch = /(?:^|&)(\d+)(?:x(\d+))?(?:&|$)/.exec(query);
  const size = sizeMatch ? ` width="${sizeMatch[1]}"${sizeMatch[2] ? ` height="${sizeMatch[2]}"` : ''}` : '';
  const alignClass = align ? ` media-${align}` : '';

  if (isExternalUrl(target)) {
    return `<a class="remote-image external-link" data-external="true" href="${escapeAttr(target)}"><span class="remote-image-label">Remote image not loaded</span> ${escapeHtml(caption || target)}</a>`;
  }
  if (ctx.staticMode) return `<span class="static-image">Image: ${escapeHtml(caption || target.split(':').pop())}</span>`;
  const path = mediaPath(target, ctx);
  const url = vaultAssetURL(path, { ...ctx, folder: '' });
  const ext = target.split('.').pop().toLowerCase();
  if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'heic', 'bmp'].includes(ext)) {
    return `<img class="note-image${alignClass}" src="${escapeAttr(url)}" alt="${escapeAttr(caption)}"${caption ? ` title="${escapeAttr(caption)}"` : ''}${size} loading="lazy" data-ob-asset="1">`;
  }
  const name = caption || target.split(':').pop();
  return `<a class="attachment-link" href="#" data-href="${escapeAttr(path)}" data-from="${escapeAttr(ctx.noteID)}" data-asset-url="${escapeAttr(url)}">${escapeHtml(name)}</a>`;
}

function renderFootnote(text, ctx) {
  ctx.footnotes.push(renderInline(text, ctx));
  const n = ctx.footnotes.length;
  return `<sup class="footnote-ref"><a href="#fn${n}" id="fnref${n}" class="anchor-link">${n}</a></sup>`;
}

// ---------------------------------------------------------------------------
// Blocks

function headingLevel(line) {
  const match = /^[ \t]*(={2,6})(.+?)(={2,6})[ \t]*$/.exec(line);
  if (!match) return null;
  const level = Math.max(1, 7 - Math.min(match[1].length, match[3].length));
  return { level, text: match[2].trim() };
}

function listMatch(line) {
  const match = /^( {2,}|\t+)([*-])[ \t]?(.*)$/.exec(line);
  if (!match) return null;
  const indent = match[1].replace(/\t/g, '  ').length;
  return { depth: Math.max(1, Math.floor(indent / 2)), ordered: match[2] === '-', text: match[3] };
}

function isTableLine(line) {
  return /^[\^|]/.test(line);
}

function renderTable(lines, ctx) {
  const rows = lines.map((line) => {
    const cells = [];
    const trimmed = line.replace(/[ \t]+$/, '');
    let i = 0;
    let current = null;
    while (i < trimmed.length) {
      const ch = trimmed[i];
      if (ch === '^' || ch === '|') {
        if (current) cells.push(current);
        current = { header: ch === '^', text: '' };
        i += 1;
        continue;
      }
      // Don't split on separators inside links/media.
      if (trimmed.startsWith('[[', i) || trimmed.startsWith('{{', i)) {
        const close = trimmed.indexOf(trimmed.startsWith('[[', i) ? ']]' : '}}', i + 2);
        const end = close < 0 ? trimmed.length : close + 2;
        current.text += trimmed.slice(i, end);
        i = end;
        continue;
      }
      current.text += ch;
      i += 1;
    }
    // The trailing separator opens an empty "cell" that isn't real.
    return cells;
  });

  let html = '<div class="table-wrapper"><table>';
  for (const row of rows) {
    html += '<tr>';
    for (let c = 0; c < row.length; c += 1) {
      const cell = row[c];
      let colspan = 1;
      while (row[c + colspan] && row[c + colspan].text === '') colspan += 1;
      const raw = cell.text;
      if (raw.trim() === ':::') {
        c += colspan - 1;
        continue;
      }
      const left = /^ {2,}/.test(raw);
      const right = / {2,}$/.test(raw);
      const align = left && right ? 'center' : left ? 'right' : null;
      const tag = cell.header ? 'th' : 'td';
      const attrs = `${colspan > 1 ? ` colspan="${colspan}"` : ''}${align ? ` style="text-align:${align}"` : ''}`;
      html += `<${tag}${attrs}>${renderInline(raw.trim(), ctx)}</${tag}>`;
      c += colspan - 1;
    }
    html += '</tr>';
  }
  return `${html}</table></div>`;
}

function renderList(items, ctx) {
  let html = '';
  const stack = [];
  for (const item of items) {
    while (stack.length > item.depth || (stack.length === item.depth && stack[stack.length - 1] !== item.ordered)) {
      if (stack.length === item.depth && stack[stack.length - 1] !== item.ordered) {
        html += stack.pop() ? '</li></ol>' : '</li></ul>';
        break;
      }
      html += stack.pop() ? '</li></ol>' : '</li></ul>';
    }
    if (stack.length === item.depth) {
      html += '</li>';
    }
    while (stack.length < item.depth) {
      stack.push(item.ordered);
      html += item.ordered ? '<ol>' : '<ul>';
    }
    html += `<li>${renderInline(item.text, ctx)}`;
  }
  while (stack.length) html += stack.pop() ? '</li></ol>' : '</li></ul>';
  return html;
}

function highlightBlock(code, lang, hljs) {
  if (hljs && lang && hljs.getLanguage(lang)) {
    try {
      return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
    } catch {
      // fall through
    }
  }
  return escapeHtml(code);
}

/**
 * Renders a DokuWiki page.
 * @param {string} source
 * @param {object} options { noteID, pagesBase, mediaBase, resolvedLinks, assetBase, hljs }
 */
export function renderDokuWiki(source, options = {}) {
  const ctx = {
    noteID: options.noteID ?? '',
    namespace: namespaceOf(options.noteID ?? '', options.pagesBase ?? ''),
    mediaBase: options.mediaBase ?? '',
    resolvedLinks: options.resolvedLinks ?? null,
    assetBase: options.assetBase,
    staticMode: Boolean(options.staticMode),
    footnotes: [],
    folder: '',
  };
  const hljs = options.hljs ?? null;
  const lines = String(source).replace(/\r\n?/g, '\n').split('\n');
  const headings = [];
  const registry = new Map();
  let html = '';
  let paragraph = [];
  let firstBlockIsH1 = null;

  const flushParagraph = () => {
    if (!paragraph.length) return;
    const text = paragraph.join('\n');
    if (text.trim()) {
      html += `<p>${renderInline(text, ctx)}</p>\n`;
      if (firstBlockIsH1 === null) firstBlockIsH1 = false;
    }
    paragraph = [];
  };

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];

    if (!line.trim()) {
      flushParagraph();
      continue;
    }

    const blockOpen = /^\s*<(code|file)(?:\s+([^\s>]+))?(?:\s+([^>]+))?>(.*)$/.exec(line);
    if (blockOpen) {
      flushParagraph();
      const tag = blockOpen[1];
      const lang = blockOpen[2] && blockOpen[2] !== '-' ? blockOpen[2].toLowerCase() : '';
      const fileName = tag === 'file' ? (blockOpen[3] ?? '').trim() : '';
      const body = [];
      let rest = blockOpen[4];
      const closeTag = `</${tag}>`;
      if (rest.includes(closeTag)) {
        body.push(rest.slice(0, rest.indexOf(closeTag)));
      } else {
        if (rest) body.push(rest);
        for (i += 1; i < lines.length; i += 1) {
          const index = lines[i].indexOf(closeTag);
          if (index >= 0) {
            body.push(lines[i].slice(0, index));
            break;
          }
          body.push(lines[i]);
        }
      }
      const code = body.join('\n').replace(/^\n+|\n+$/g, '');
      const label = fileName || lang;
      html += `<div class="code-wrapper">${label ? `<span class="code-lang">${escapeHtml(label)}</span>` : ''}`
        + `<pre class="code-block"><code class="hljs${lang ? ` language-${escapeAttr(lang)}` : ''}">${highlightBlock(code, lang, hljs)}</code></pre></div>\n`;
      if (firstBlockIsH1 === null) firstBlockIsH1 = false;
      continue;
    }

    const heading = headingLevel(line);
    if (heading) {
      flushParagraph();
      const id = uniqueSlug(heading.text, registry);
      const text = heading.text;
      html += `<h${heading.level} id="${escapeAttr(id)}" data-heading="${escapeAttr(text)}" data-doku-section="${escapeAttr(sectionID(text))}">${renderInline(text, ctx)}</h${heading.level}>\n`;
      headings.push({ level: heading.level, text, id });
      if (firstBlockIsH1 === null) firstBlockIsH1 = heading.level === 1;
      continue;
    }

    if (/^\s*-{4,}\s*$/.test(line)) {
      flushParagraph();
      html += '<hr>\n';
      continue;
    }

    if (isTableLine(line)) {
      flushParagraph();
      const tableLines = [];
      while (i < lines.length && isTableLine(lines[i])) {
        tableLines.push(lines[i]);
        i += 1;
      }
      i -= 1;
      html += `${renderTable(tableLines, ctx)}\n`;
      if (firstBlockIsH1 === null) firstBlockIsH1 = false;
      continue;
    }

    if (listMatch(line)) {
      flushParagraph();
      const items = [];
      while (i < lines.length && listMatch(lines[i])) {
        items.push(listMatch(lines[i]));
        i += 1;
      }
      i -= 1;
      html += `${renderList(items, ctx)}\n`;
      if (firstBlockIsH1 === null) firstBlockIsH1 = false;
      continue;
    }

    if (/^>/.test(line)) {
      flushParagraph();
      const quoteLines = [];
      while (i < lines.length && /^>/.test(lines[i])) {
        quoteLines.push(lines[i]);
        i += 1;
      }
      i -= 1;
      html += renderQuote(quoteLines, ctx);
      if (firstBlockIsH1 === null) firstBlockIsH1 = false;
      continue;
    }

    if (/^( {2,}|\t)/.test(line) && paragraph.length === 0) {
      const pre = [];
      while (i < lines.length && (/^( {2,}|\t)/.test(lines[i]) && !listMatch(lines[i]))) {
        pre.push(lines[i].replace(/^( {2}|\t)/, ''));
        i += 1;
      }
      i -= 1;
      html += `<pre class="code-block"><code>${escapeHtml(pre.join('\n'))}</code></pre>\n`;
      if (firstBlockIsH1 === null) firstBlockIsH1 = false;
      continue;
    }

    paragraph.push(line);
  }
  flushParagraph();

  if (ctx.footnotes.length) {
    html += '<section class="footnotes"><hr><ol class="footnotes-list">';
    ctx.footnotes.forEach((note, index) => {
      const n = index + 1;
      html += `<li id="fn${n}" class="footnote-item">${note} <a href="#fnref${n}" class="footnote-backref anchor-link">↩︎</a></li>`;
    });
    html += '</ol></section>\n';
  }

  return {
    html,
    headings,
    startsWithH1: firstBlockIsH1 === true,
    firstHeading: firstBlockIsH1 === true ? headings[0]?.text ?? null : null,
  };
}

function renderQuote(lines, ctx) {
  let html = '';
  let depth = 0;
  for (const line of lines) {
    const match = /^(>+)\s?(.*)$/.exec(line);
    const level = match[1].length;
    while (depth < level) {
      html += '<blockquote>';
      depth += 1;
    }
    while (depth > level) {
      html += '</blockquote>';
      depth -= 1;
    }
    html += `<p>${renderInline(match[2], ctx)}</p>`;
  }
  while (depth > 0) {
    html += '</blockquote>';
    depth -= 1;
  }
  return `${html}\n`;
}

/** Outbound page IDs, resolved to absolute DokuWiki IDs. */
export function extractDokuWikiLinks(source, options = {}) {
  const namespace = namespaceOf(options.noteID ?? '', options.pagesBase ?? '');
  const links = new Set();
  const stripped = String(source)
    .replace(/<(code|file)[^>]*>[\s\S]*?<\/\1>/g, '')
    .replace(/<nowiki>[\s\S]*?<\/nowiki>/g, '')
    .replace(/%%[\s\S]*?%%/g, '');
  for (const match of stripped.matchAll(/\[\[([^\]|#]*)(?:#[^\]|]*)?(?:\|[\s\S]*?)?\]\]/g)) {
    const target = match[1].trim();
    if (!target || isExternalUrl(target) || /^[a-zA-Z0-9.-_]+>/.test(target) || /^\\\\/.test(target)) continue;
    links.add(resolveID(target, namespace));
  }
  return [...links];
}
