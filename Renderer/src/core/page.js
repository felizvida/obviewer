// Builds the full reader page (header + body + backlinks) from a render payload.
// Pure string building so it can be tested in Node.

import { renderMarkdown } from './markdown.js';
import { renderDokuWiki } from './dokuwiki.js';
import { escapeAttr, escapeHtml } from './util.js';

/**
 * @typedef {object} RenderPayload
 * @property {string} noteID           Vault-relative path, used as the note's identity.
 * @property {string} relativePath
 * @property {string} title
 * @property {'markdown'|'obsidian'|'dokuwiki'} flavor
 * @property {string} source           Raw file contents.
 * @property {object} [header]         { path, tags[], properties[{key,value}], readingTime, wordCount, modified }
 * @property {object} [embeds]         Pre-resolved ![[embeds]] keyed by raw target.
 * @property {object} [resolvedLinks]  target -> boolean
 * @property {Array}  [backlinks]      [{ noteID, title, path }]
 * @property {object} [dokuwiki]       { pagesBase, mediaBase }
 * @property {object} [options]        { showHeader, showBacklinks }
 */

export function renderBody(payload, deps = {}) {
  if (payload.flavor === 'dokuwiki') {
    return renderDokuWiki(payload.source ?? '', {
      noteID: payload.noteID,
      pagesBase: payload.dokuwiki?.pagesBase ?? '',
      mediaBase: payload.dokuwiki?.mediaBase ?? '',
      resolvedLinks: payload.resolvedLinks,
      assetBase: payload.assetBase,
      staticMode: payload.options?.staticMode,
      hljs: deps.hljs,
    });
  }
  return renderMarkdown(payload.source ?? '', {
    flavor: payload.flavor,
    noteID: payload.noteID,
    relativePath: payload.relativePath ?? payload.noteID,
    embeds: payload.embeds,
    resolvedLinks: payload.resolvedLinks,
    assetBase: payload.assetBase,
    staticMode: payload.options?.staticMode,
  });
}

export function renderHeader(payload, body) {
  const options = payload.options ?? {};
  if (options.showHeader === false) return '';
  const header = payload.header ?? {};
  const parts = [];
  if (!body.startsWithH1 && payload.title) {
    parts.push(`<h1 class="note-title">${escapeHtml(payload.title)}</h1>`);
  }

  // One quiet sentence: where the note lives, when it was edited, how long it takes.
  // The file name itself is left out; the title already names the note.
  const meta = [];
  const folder = header.path?.includes('/') ? header.path.slice(0, header.path.lastIndexOf('/')) : '';
  if (folder) meta.push(`<span class="note-path">In ${escapeHtml(folder.split('/').join(' / '))}</span>`);
  if (header.modified) meta.push(`<span>Edited ${escapeHtml(header.modified)}</span>`);
  if (header.readingTime) meta.push(`<span>${escapeHtml(String(header.readingTime))} min read</span>`);
  if (meta.length) parts.push(`<p class="note-meta">${meta.join('. ')}.</p>`);

  if (header.tags?.length) {
    parts.push(`<p class="note-tags">${header.tags
      .map((tag) => `<a class="tag" href="#" data-tag="${escapeAttr(tag)}">#${escapeHtml(tag)}</a>`)
      .join(' ')}</p>`);
  }

  if (header.properties?.length) {
    const rows = header.properties
      .map((entry) => `<tr><th scope="row">${escapeHtml(entry.key)}</th><td>${escapeHtml(entry.value)}</td></tr>`)
      .join('');
    parts.push(`<details class="note-properties"><summary>Properties <span class="count">${header.properties.length}</span></summary><table>${rows}</table></details>`);
  }

  if (!parts.length) return '';
  return `<header class="note-header">${parts.join('')}</header>`;
}

export function renderBacklinks(payload) {
  const options = payload.options ?? {};
  const backlinks = payload.backlinks ?? [];
  if (options.showBacklinks === false || !backlinks.length) return '';
  const items = backlinks
    .map((link) => `<li><a href="#" data-note-id="${escapeAttr(link.noteID)}">${escapeHtml(link.title)}</a>`
      + `${link.path ? ` <span class="backlink-path">${escapeHtml(link.path)}</span>` : ''}</li>`)
    .join('');
  return `<section class="backlinks" aria-label="Mentioned in"><h2 class="backlinks-title">Mentioned in</h2><ul>${items}</ul></section>`;
}

/**
 * Joins the parts of a built page into the reader's markup. When the note opens
 * with its own H1, the metadata goes directly under that title, the way a book
 * sets a subtitle; otherwise the header (with the generated title) comes first.
 * Each part is passed through `clean` separately (DOMPurify in the live reader).
 */
export function composePage(page, clean = (html) => html, { backlinks = true } = {}) {
  const tail = backlinks ? clean(page.backlinksHTML ?? '') : '';
  const split = page.startsWithH1 && page.headerHTML ? page.bodyHTML.indexOf('</h1>') : -1;
  if (split < 0) {
    return `${clean(page.headerHTML)}<article class="note-body">${clean(page.bodyHTML)}</article>${tail}`;
  }
  const end = split + '</h1>'.length;
  return `<article class="note-body">${clean(page.bodyHTML.slice(0, end))}${clean(page.headerHTML)}`
    + `${clean(page.bodyHTML.slice(end))}</article>${tail}`;
}

/** Returns { headerHTML, bodyHTML, backlinksHTML, headings }. Body HTML is unsanitized. */
export function buildPage(payload, deps = {}) {
  const body = renderBody(payload, deps);
  return {
    headerHTML: renderHeader(payload, body),
    bodyHTML: body.html,
    backlinksHTML: renderBacklinks(payload),
    headings: body.headings,
    startsWithH1: body.startsWithH1,
  };
}
