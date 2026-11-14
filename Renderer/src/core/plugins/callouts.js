// Obsidian callouts and GitHub alerts:
//   > [!warning]- Optional title
//   > body
// Rendered as <div class="callout"> (or <details> when foldable).

const CALLOUT_ALIASES = {
  summary: 'abstract', tldr: 'abstract',
  hint: 'tip', important: 'important',
  check: 'success', done: 'success',
  help: 'question', faq: 'question',
  caution: 'caution', attention: 'warning',
  fail: 'failure', missing: 'failure',
  error: 'danger',
  cite: 'quote',
};

const CALLOUT_LABELS = {
  note: 'Note', abstract: 'Abstract', info: 'Info', todo: 'To-do', tip: 'Tip',
  important: 'Important', success: 'Success', question: 'Question', warning: 'Warning',
  caution: 'Caution', failure: 'Failure', danger: 'Danger', bug: 'Bug',
  example: 'Example', quote: 'Quote',
};

const MARKER = /^\[!([A-Za-z][\w-]*)\]([+-]?)[ \t]*([^\n]*)(?:\n([\s\S]*))?$/;

export function normalizeCalloutType(type) {
  const lower = String(type).toLowerCase();
  return CALLOUT_ALIASES[lower] ?? lower;
}

export function calloutPlugin(md) {
  md.core.ruler.after('block', 'ob_callouts', (state) => {
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i += 1) {
      const open = tokens[i];
      if (open.type !== 'blockquote_open') continue;
      const paragraph = tokens[i + 1];
      const inline = tokens[i + 2];
      if (paragraph?.type !== 'paragraph_open' || inline?.type !== 'inline') continue;
      const match = MARKER.exec(inline.content);
      if (!match) continue;

      const rawType = match[1];
      const type = normalizeCalloutType(rawType);
      const fold = match[2];
      const title = match[3].trim() || CALLOUT_LABELS[type] || capitalize(rawType);
      const rest = match[4] ?? '';

      open.meta = { callout: { type, rawType: rawType.toLowerCase(), fold, title } };
      const close = findClose(tokens, i);
      if (close) close.meta = { callout: open.meta.callout };

      if (rest.trim()) {
        inline.content = rest;
      } else {
        // Drop the now-empty first paragraph.
        tokens.splice(i + 1, 3);
      }
    }
  });

  const defaultOpen = md.renderer.rules.blockquote_open
    ?? ((tokens, idx, options, env, self) => self.renderToken(tokens, idx, options));
  const defaultClose = md.renderer.rules.blockquote_close
    ?? ((tokens, idx, options, env, self) => self.renderToken(tokens, idx, options));

  md.renderer.rules.blockquote_open = (tokens, idx, options, env, self) => {
    const callout = tokens[idx].meta?.callout;
    if (!callout) return defaultOpen(tokens, idx, options, env, self);
    // Render the title without the document's footnote state: markdown-it-footnote
    // appends its footnote list to every inline render that can see env.footnotes.
    const titleHtml = md.renderInline(callout.title, { ...env, footnotes: undefined });
    const typeAttr = md.utils.escapeHtml(callout.type);
    const rawAttr = md.utils.escapeHtml(callout.rawType);
    if (callout.fold) {
      const openAttr = callout.fold === '+' ? ' open' : '';
      return `<details class="callout" data-callout="${typeAttr}" data-callout-raw="${rawAttr}"${openAttr}>`
        + `<summary class="callout-title"><span class="callout-icon" aria-hidden="true"></span>`
        + `<span class="callout-title-text">${titleHtml}</span></summary><div class="callout-content">\n`;
    }
    return `<div class="callout" data-callout="${typeAttr}" data-callout-raw="${rawAttr}" role="note">`
      + `<div class="callout-title"><span class="callout-icon" aria-hidden="true"></span>`
      + `<span class="callout-title-text">${titleHtml}</span></div><div class="callout-content">\n`;
  };

  md.renderer.rules.blockquote_close = (tokens, idx, options, env, self) => {
    const callout = tokens[idx].meta?.callout;
    if (!callout) return defaultClose(tokens, idx, options, env, self);
    return callout.fold ? '</div></details>\n' : '</div></div>\n';
  };
}

function findClose(tokens, openIndex) {
  let depth = 0;
  for (let j = openIndex; j < tokens.length; j += 1) {
    if (tokens[j].type === 'blockquote_open') depth += 1;
    if (tokens[j].type === 'blockquote_close') {
      depth -= 1;
      if (depth === 0) return tokens[j];
    }
  }
  return null;
}

function capitalize(text) {
  return text.charAt(0).toUpperCase() + text.slice(1);
}
