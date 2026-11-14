// Obsidian-specific inline syntax for markdown-it:
//   [[wikilinks]], ![[embeds]], ==highlights==, #tags and ^block-ids.

import { parseWikiTarget } from '../util.js';

const BANG = 0x21;
const OPEN_BRACKET = 0x5b;
const EQUALS = 0x3d;
const HASH = 0x23;

function wikilinkRule(state, silent) {
  const { src } = state;
  let pos = state.pos;
  let embed = false;

  if (src.charCodeAt(pos) === BANG) {
    if (src.charCodeAt(pos + 1) !== OPEN_BRACKET || src.charCodeAt(pos + 2) !== OPEN_BRACKET) return false;
    embed = true;
    pos += 1;
  } else if (src.charCodeAt(pos) !== OPEN_BRACKET || src.charCodeAt(pos + 1) !== OPEN_BRACKET) {
    return false;
  }

  const contentStart = pos + 2;
  const end = src.indexOf(']]', contentStart);
  if (end < 0 || end > state.posMax) return false;
  const inner = src.slice(contentStart, end);
  if (!inner.trim() || inner.includes('\n') || inner.includes('[[')) return false;

  if (!silent) {
    const token = state.push(embed ? 'ob_embed' : 'ob_wikilink', '', 0);
    token.content = inner;
    token.meta = parseWikiTarget(inner);
  }
  state.pos = end + 2;
  return true;
}

function highlightRule(state, silent) {
  const { src } = state;
  const start = state.pos;
  if (src.charCodeAt(start) !== EQUALS || src.charCodeAt(start + 1) !== EQUALS) return false;
  if (src.charCodeAt(start + 2) === EQUALS) return false;
  const next = src.charAt(start + 2);
  if (!next || /\s/.test(next)) return false;

  let search = start + 2;
  let end = -1;
  for (;;) {
    const found = src.indexOf('==', search);
    if (found < 0 || found + 2 > state.posMax) return false;
    if (!/\s/.test(src.charAt(found - 1))) {
      end = found;
      break;
    }
    search = found + 1;
  }
  if (end <= start + 2) return false;
  if (silent) return true;

  const oldMax = state.posMax;
  state.push('mark_open', 'mark', 1);
  state.pos = start + 2;
  state.posMax = end;
  state.md.inline.tokenize(state);
  state.push('mark_close', 'mark', -1);
  state.pos = end + 2;
  state.posMax = oldMax;
  return true;
}

const TAG_BODY = /^[\p{L}\p{N}_\-/]+/u;

function tagRule(state, silent) {
  const { src } = state;
  const start = state.pos;
  if (src.charCodeAt(start) !== HASH) return false;
  if (start > 0 && !/[\s(\[{,;]/.test(src.charAt(start - 1))) return false;
  const match = TAG_BODY.exec(src.slice(start + 1, state.posMax));
  if (!match) return false;
  const tag = match[0].replace(/[/-]+$/, '');
  if (!tag || /^\d+$/.test(tag)) return false;
  if (!silent) {
    const token = state.push('ob_tag', '', 0);
    token.content = tag;
  }
  state.pos = start + 1 + tag.length;
  return true;
}

// Moves a trailing " ^block-id" from paragraph/list text onto the block.
function blockIdRule(state) {
  const tokens = state.tokens;
  for (let i = 0; i < tokens.length; i += 1) {
    const inline = tokens[i];
    if (inline.type !== 'inline' || !inline.children?.length) continue;
    const children = inline.children;
    const last = children[children.length - 1];
    if (last.type !== 'text') continue;
    const match = /(^|\s)\^([A-Za-z0-9-]+)\s*$/.exec(last.content);
    if (!match) continue;
    last.content = last.content.slice(0, match.index).replace(/\s+$/, '');
    const blockId = match[2];
    const opener = findBlockOpener(tokens, i);
    if (opener) opener.attrSet('id', `^${blockId}`);
    if (opener) opener.attrJoin('class', 'ob-block-ref');
  }
}

function findBlockOpener(tokens, inlineIndex) {
  const previous = tokens[inlineIndex - 1];
  if (!previous) return null;
  if (previous.type === 'paragraph_open' && previous.hidden) {
    for (let j = inlineIndex - 2; j >= 0; j -= 1) {
      if (tokens[j].type === 'list_item_open' && tokens[j].level === previous.level - 1) return tokens[j];
    }
  }
  return previous.nesting === 1 ? previous : null;
}

export function obsidianInlinePlugin(md, { tags = true } = {}) {
  md.inline.ruler.before('link', 'ob_wikilink', wikilinkRule);
  md.inline.ruler.before('emphasis', 'ob_highlight', highlightRule);
  if (tags) md.inline.ruler.push('ob_tag', tagRule);
  md.core.ruler.push('ob_block_ids', blockIdRule);
}

// Wiki links without the rest of the Obsidian syntax (used by plain Markdown
// folders, which commonly contain [[links]] from Foam, Logseq, Zettlr, etc.).
export function wikilinkOnlyPlugin(md) {
  md.inline.ruler.before('link', 'ob_wikilink', wikilinkRule);
}
