// Turns a rendered note (DOM) into clipboard-friendly formats:
//   - Slack: mrkdwn-style plain text + simplified HTML that Slack's composer keeps
//   - Rich text: self-contained HTML with inline styles for Mail, Word, Teams
// Works with any DOM implementation (WebKit at runtime, linkedom in tests).

const BLOCK_TAGS = new Set(['P', 'DIV', 'SECTION', 'ARTICLE', 'HEADER', 'FOOTER', 'FIGURE', 'DETAILS', 'SUMMARY', 'MAIN']);

function textOf(node) {
  return (node.textContent ?? '').replace(/\s+/g, ' ').trim();
}

function texSource(mathElement) {
  const annotation = mathElement.querySelector?.('annotation[encoding="application/x-tex"]');
  if (annotation) return annotation.textContent.trim();
  return textOf(mathElement);
}

// ---------------------------------------------------------------------------
// Slack mrkdwn

function inlineSlack(node) {
  let out = '';
  for (const child of node.childNodes) {
    if (child.nodeType === 3) {
      out += child.textContent.replace(/\s+/g, ' ');
      continue;
    }
    if (child.nodeType !== 1) continue;
    const tag = child.tagName;
    const cls = child.getAttribute('class') || '';
    if (cls.includes('math')) {
      const tex = texSource(child);
      out += cls.includes('math-display') ? `$$${tex}$$` : `$${tex}$`;
      continue;
    }
    if (tag === 'INPUT' && child.getAttribute('type') === 'checkbox') {
      out += child.hasAttribute('checked') ? '☑ ' : '☐ ';
      continue;
    }
    const inner = inlineSlack(child);
    switch (tag) {
      case 'STRONG': case 'B':
        out += wrapSlack(inner, '*');
        break;
      case 'EM': case 'I':
        out += wrapSlack(inner, '_');
        break;
      case 'DEL': case 'S': case 'STRIKE':
        out += wrapSlack(inner, '~');
        break;
      case 'CODE':
        out += `\`${child.textContent}\``;
        break;
      case 'MARK':
        out += wrapSlack(inner, '*');
        break;
      case 'BR':
        out += '\n';
        break;
      case 'IMG':
        out += `[image: ${child.getAttribute('alt') || 'image'}]`;
        break;
      case 'SUP':
        out += child.getAttribute('class')?.includes('footnote-ref') ? `[${inner}]` : `^${inner}`;
        break;
      case 'A': {
        const href = child.getAttribute('href') || '';
        if (/^(https?:|mailto:)/i.test(href)) {
          const label = inner.trim();
          const shown = href.replace(/^mailto:/i, '');
          out += !label || label === href || label === shown ? shown : `${label} (${shown})`;
        } else {
          out += inner;
        }
        break;
      }
      default:
        out += inner;
    }
  }
  return out;
}

function wrapSlack(text, marker) {
  const trimmed = text.trim();
  if (!trimmed) return text;
  const lead = text.match(/^\s*/)[0];
  const trail = text.match(/\s*$/)[0];
  return `${lead}${marker}${trimmed}${marker}${trail}`;
}

function listSlack(list, depth) {
  const lines = [];
  let index = Number(list.getAttribute('start') || 1);
  for (const item of list.children) {
    if (item.tagName !== 'LI') continue;
    const nested = [];
    const clone = item.cloneNode(true);
    for (const sub of [...clone.children]) {
      if (sub.tagName === 'UL' || sub.tagName === 'OL') {
        nested.push(sub);
        sub.remove();
      }
    }
    const isTask = clone.querySelector?.('input[type="checkbox"]');
    const marker = list.tagName === 'OL' ? `${index}.` : (isTask ? '' : '•');
    const text = blockTextForListItem(clone);
    lines.push(`${'    '.repeat(depth)}${marker ? `${marker} ` : ''}${text}`);
    for (const sub of nested) lines.push(...listSlack(sub, depth + 1));
    index += 1;
  }
  return lines;
}

function blockTextForListItem(item) {
  const paragraphs = [...item.children].filter((child) => child.tagName === 'P');
  if (paragraphs.length) return paragraphs.map((p) => inlineSlack(p).trim()).join(' ');
  return inlineSlack(item).trim();
}

function tableSlack(table) {
  const rows = [...table.querySelectorAll('tr')].map((row) => [...row.children].map((cell) => textOf(cell)));
  if (!rows.length) return '';
  const widths = [];
  for (const row of rows) row.forEach((cell, i) => { widths[i] = Math.max(widths[i] ?? 0, cell.length); });
  const lines = rows.map((row) => row.map((cell, i) => cell.padEnd(widths[i])).join(' | ').trimEnd());
  if (table.querySelector('th') && lines.length > 1) {
    lines.splice(1, 0, widths.map((w) => '-'.repeat(Math.max(3, w))).join('-|-'));
  }
  return `\`\`\`\n${lines.join('\n')}\n\`\`\``;
}

function blocksSlack(container, out) {
  for (const node of container.childNodes) {
    if (node.nodeType === 3) {
      const text = node.textContent.trim();
      if (text) out.push(text);
      continue;
    }
    if (node.nodeType !== 1) continue;
    const tag = node.tagName;
    const cls = node.getAttribute('class') || '';

    if (cls.includes('backlinks') || cls.includes('note-header') || cls.includes('code-lang') || cls.includes('copy-button')) continue;
    if (/^H[1-6]$/.test(tag)) {
      out.push(`*${inlineSlack(node).trim()}*`);
      continue;
    }
    if (tag === 'P') {
      const text = inlineSlack(node).trim();
      if (text) out.push(text);
      continue;
    }
    if (tag === 'UL' || tag === 'OL') {
      out.push(listSlack(node, 0).join('\n'));
      continue;
    }
    if (tag === 'PRE') {
      out.push(`\`\`\`\n${node.textContent.replace(/\n$/, '')}\n\`\`\``);
      continue;
    }
    if (tag === 'BLOCKQUOTE') {
      const inner = [];
      blocksSlack(node, inner);
      out.push(inner.join('\n\n').split('\n').map((line) => `> ${line}`).join('\n'));
      continue;
    }
    if (tag === 'TABLE') {
      out.push(tableSlack(node));
      continue;
    }
    if (tag === 'HR') {
      out.push('———');
      continue;
    }
    if (cls.includes('mermaid-block')) {
      out.push('[diagram]');
      continue;
    }
    if (cls.includes('math-display')) {
      out.push(`$$${texSource(node)}$$`);
      continue;
    }
    if (cls.includes('callout')) {
      const title = node.querySelector('.callout-title-text');
      const content = node.querySelector('.callout-content');
      const inner = [];
      if (content) blocksSlack(content, inner);
      const lines = [`*${title ? inlineSlack(title).trim() : 'Note'}*`, ...inner.join('\n\n').split('\n')];
      out.push(lines.map((line) => `> ${line}`).join('\n'));
      continue;
    }
    if (tag === 'IMG') {
      out.push(`[image: ${node.getAttribute('alt') || 'image'}]`);
      continue;
    }
    if (BLOCK_TAGS.has(tag) || tag === 'SECTION' || tag === 'OL') {
      blocksSlack(node, out);
      continue;
    }
    const text = inlineSlack(node).trim();
    if (text) out.push(text);
  }
}

/** Slack-flavored plain text for the given rendered container. */
export function toSlackText(container) {
  const out = [];
  blocksSlack(container, out);
  return out.filter((block) => block && block.trim()).join('\n\n').replace(/\n{3,}/g, '\n\n').trim();
}

// ---------------------------------------------------------------------------
// Clipboard HTML (rich text and Slack)

const INLINE_STYLES = {
  H1: 'font-size:1.6em;font-weight:700;margin:0.8em 0 0.4em;',
  H2: 'font-size:1.35em;font-weight:700;margin:0.8em 0 0.4em;',
  H3: 'font-size:1.15em;font-weight:700;margin:0.8em 0 0.3em;',
  H4: 'font-size:1em;font-weight:700;margin:0.8em 0 0.3em;',
  PRE: 'font-family:Menlo,Consolas,monospace;font-size:0.9em;background:#f4f4f2;border:1px solid #e2e2dc;border-radius:6px;padding:10px;white-space:pre-wrap;',
  CODE: 'font-family:Menlo,Consolas,monospace;font-size:0.9em;background:#f4f4f2;border-radius:4px;padding:0 3px;',
  BLOCKQUOTE: 'border-left:3px solid #c9c9c0;margin:0.6em 0;padding:0 0 0 12px;color:#555;',
  TABLE: 'border-collapse:collapse;margin:0.6em 0;',
  TH: 'border:1px solid #d0d0c8;padding:4px 8px;background:#f4f4f2;text-align:left;',
  TD: 'border:1px solid #d0d0c8;padding:4px 8px;vertical-align:top;',
  MARK: 'background:#fff2a8;',
  IMG: 'max-width:100%;',
};

function removeAll(root, selector) {
  for (const element of [...root.querySelectorAll(selector)]) element.remove();
}

function replaceWith(document, element, tag, html) {
  const replacement = document.createElement(tag);
  if (html != null) replacement.innerHTML = html;
  element.replaceWith(replacement);
  return replacement;
}

/**
 * Produces portable HTML from a rendered note.
 * @param {Element} source   The rendered note container (not modified).
 * @param {object}  options  { target: 'rich' | 'slack', diagramImages: Map<Element,string>, includeHeader }
 */
export function toClipboardHTML(source, options = {}) {
  const target = options.target ?? 'rich';
  const document = source.ownerDocument;
  const root = source.cloneNode(true);

  removeAll(root, '.backlinks, .copy-button, .code-lang, script, style, .embed-attachment-hint');
  if (!options.includeHeader) removeAll(root, '.note-header');

  // Diagrams: use pre-rasterised PNGs if the caller made them; otherwise a note.
  const sourceDiagrams = [...source.querySelectorAll('.mermaid-block')];
  [...root.querySelectorAll('.mermaid-block')].forEach((block, index) => {
    const png = options.diagramImages?.get(sourceDiagrams[index]);
    if (png && target === 'rich') {
      replaceWith(document, block, 'p', `<img src="${png}" alt="Diagram" style="max-width:100%;">`);
    } else {
      replaceWith(document, block, 'p', '<em>[diagram]</em>');
    }
  });

  // Math: keep MathML for rich text (Mail/Word understand it), TeX for Slack.
  for (const math of [...root.querySelectorAll('.math')]) {
    const display = (math.getAttribute('class') || '').includes('math-display');
    const tex = texSource(math);
    const mathml = math.querySelector('math');
    if (target === 'rich' && mathml) {
      replaceWith(document, math, display ? 'div' : 'span', mathml.outerHTML);
    } else {
      replaceWith(document, math, 'code', null).textContent = display ? `$$${tex}$$` : `$${tex}$`;
    }
  }

  // Callouts -> blockquote with bold title.
  for (const callout of [...root.querySelectorAll('.callout')]) {
    const title = callout.querySelector('.callout-title-text');
    const content = callout.querySelector('.callout-content');
    const quote = document.createElement('blockquote');
    quote.innerHTML = `<p><strong>${title ? title.innerHTML : 'Note'}</strong></p>${content ? content.innerHTML : ''}`;
    callout.replaceWith(quote);
  }

  // Embedded notes -> their body.
  for (const embed of [...root.querySelectorAll('.embed-note')]) {
    const body = embed.querySelector('.embed-body');
    const title = embed.querySelector('.embed-title');
    const quote = document.createElement('blockquote');
    quote.innerHTML = `${title ? `<p><strong>${title.textContent}</strong></p>` : ''}${body ? body.innerHTML : ''}`;
    embed.replaceWith(quote);
  }

  // Internal links have no meaning outside Obviewer: keep their text.
  for (const link of [...root.querySelectorAll('a')]) {
    const href = link.getAttribute('href') || '';
    if (!/^(https?:|mailto:)/i.test(href)) {
      const span = document.createElement('span');
      span.innerHTML = link.innerHTML;
      link.replaceWith(span);
    }
  }

  // Local images can't travel as obviewer-asset:// URLs; the caller may have inlined them as data URLs.
  for (const image of [...root.querySelectorAll('img')]) {
    const src = image.getAttribute('src') || '';
    if (!src.startsWith('data:')) {
      const alt = image.getAttribute('alt') || 'image';
      replaceWith(document, image, 'em', null).textContent = `[image: ${alt}]`;
    }
  }

  // Task checkboxes don't survive pasting into Word or Slack; use ballot-box characters.
  for (const box of [...root.querySelectorAll('input[type="checkbox"]')]) {
    const span = document.createElement('span');
    span.textContent = box.hasAttribute('checked') ? '☑ ' : '☐ ';
    box.replaceWith(span);
  }

  if (target === 'slack') {
    // Slack ignores most styling; headings survive best as bold paragraphs.
    for (const heading of [...root.querySelectorAll('h1, h2, h3, h4, h5, h6')]) {
      replaceWith(document, heading, 'p', `<b>${heading.innerHTML}</b>`);
    }
    for (const mark of [...root.querySelectorAll('mark')]) {
      replaceWith(document, mark, 'b', mark.innerHTML);
    }
  } else {
    for (const element of [...root.querySelectorAll('*')]) {
      const style = INLINE_STYLES[element.tagName];
      if (style && !(element.tagName === 'CODE' && element.parentElement?.tagName === 'PRE')) {
        element.setAttribute('style', `${style}${element.getAttribute('style') || ''}`);
      }
    }
  }

  // Strip attributes that only make sense inside Obviewer.
  for (const element of [...root.querySelectorAll('*')]) {
    for (const attr of [...element.attributes]) {
      if (attr.name.startsWith('data-') || attr.name === 'class' || attr.name === 'id' || attr.name === 'loading') {
        element.removeAttribute(attr.name);
      }
    }
  }

  const body = root.innerHTML.trim();
  if (target === 'slack') return body;
  return `<meta charset="utf-8"><div style="font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:14px;line-height:1.5;color:#1d1f21;">${body}</div>`;
}
