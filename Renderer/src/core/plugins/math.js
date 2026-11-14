// $inline$ and $$display$$ math, rendered with KaTeX when available.
// Delimiter rules follow GitHub/Pandoc so prices like "$5 and $10" stay text:
// the opening $ must not be followed by whitespace, the closing $ must not be
// preceded by whitespace or followed by a digit.

const DOLLAR = 0x24;

export function renderMath(katex, tex, displayMode, output = 'htmlAndMathml') {
  if (!katex) {
    const cls = displayMode ? 'math math-display' : 'math math-inline';
    return `<span class="${cls}">${escape(tex)}</span>`;
  }
  try {
    const html = katex.renderToString(tex, {
      displayMode,
      throwOnError: false,
      strict: 'ignore',
      trust: false,
      output,
    });
    return displayMode ? `<div class="math math-display">${html}</div>` : `<span class="math math-inline">${html}</span>`;
  } catch (error) {
    return `<code class="math-error" title="${escape(String(error?.message ?? error))}">${escape(tex)}</code>`;
  }
}

function escape(text) {
  return String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function inlineMath(state, silent) {
  const { src } = state;
  const start = state.pos;
  if (src.charCodeAt(start) !== DOLLAR) return false;

  // Inline $$...$$ (Obsidian allows display math mid-paragraph).
  if (src.charCodeAt(start + 1) === DOLLAR) {
    const end = src.indexOf('$$', start + 2);
    if (end < 0 || end + 2 > state.posMax) return false;
    const tex = src.slice(start + 2, end);
    if (!tex.trim()) return false;
    if (!silent) {
      const token = state.push('math_inline_display', 'math', 0);
      token.content = tex.trim();
    }
    state.pos = end + 2;
    return true;
  }

  const first = src.charAt(start + 1);
  if (!first || /\s/.test(first)) return false;

  let search = start + 1;
  while (search < state.posMax) {
    const end = src.indexOf('$', search);
    if (end < 0 || end >= state.posMax) return false;
    if (src.charCodeAt(end - 1) === 0x5c /* \ */) {
      search = end + 1;
      continue;
    }
    // The first unescaped $ decides: if it can't close, this isn't math.
    // That keeps prices like "$5 and $10" as text (Obsidian behaves the same).
    if (/\s/.test(src.charAt(end - 1)) || /\d/.test(src.charAt(end + 1) || '')) {
      return false;
    }
    const tex = src.slice(start + 1, end);
    if (!tex) return false;
    if (!silent) {
      const token = state.push('math_inline', 'math', 0);
      token.content = tex;
    }
    state.pos = end + 1;
    return true;
  }
  return false;
}

function blockMath(state, startLine, endLine, silent) {
  let pos = state.bMarks[startLine] + state.tShift[startLine];
  let max = state.eMarks[startLine];
  if (state.sCount[startLine] - state.blkIndent >= 4) return false;
  if (pos + 2 > max) return false;
  if (state.src.charCodeAt(pos) !== DOLLAR || state.src.charCodeAt(pos + 1) !== DOLLAR) return false;

  pos += 2;
  let firstLine = state.src.slice(pos, max);
  let lastLine = '';
  let next = startLine;
  let found = false;

  if (firstLine.trim().endsWith('$$')) {
    firstLine = firstLine.trim().slice(0, -2);
    found = true;
  }

  if (silent) return true;

  while (!found) {
    next += 1;
    if (next >= endLine) break;
    pos = state.bMarks[next] + state.tShift[next];
    max = state.eMarks[next];
    if (pos < max && state.sCount[next] < state.blkIndent) break;
    const line = state.src.slice(pos, max);
    if (line.trim().endsWith('$$')) {
      lastLine = line.trim().slice(0, -2);
      found = true;
    }
  }

  if (!found) return false;

  state.line = next + 1;
  const token = state.push('math_block', 'math', 0);
  token.block = true;
  token.content = [firstLine, next > startLine + 1 ? state.getLines(startLine + 1, next, state.tShift[startLine], true) : '', lastLine]
    .filter((part) => part && part.trim())
    .join('\n');
  token.map = [startLine, state.line];
  token.markup = '$$';
  return true;
}

export function mathPlugin(md, { katex } = {}) {
  md.inline.ruler.after('escape', 'math_inline', inlineMath);
  md.block.ruler.after('blockquote', 'math_block', blockMath, {
    alt: ['paragraph', 'reference', 'blockquote', 'list'],
  });
  // Static previews (Quick Look) can't load KaTeX fonts, so they use native MathML instead.
  const outputFor = (env) => (env?.ctx?.staticMode ? 'mathml' : 'htmlAndMathml');
  md.renderer.rules.math_inline = (tokens, idx, options, env) => renderMath(katex, tokens[idx].content, false, outputFor(env));
  md.renderer.rules.math_inline_display = (tokens, idx, options, env) => renderMath(katex, tokens[idx].content, true, outputFor(env));
  md.renderer.rules.math_block = (tokens, idx, options, env) => `${renderMath(katex, tokens[idx].content, true, outputFor(env))}\n`;
}
