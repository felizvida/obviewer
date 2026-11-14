import test from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown } from '../src/core/markdown.js';
import { toClipboardHTML, toSlackText } from '../src/core/export.js';
import { dom } from './helpers.js';

const render = (source) => dom(`<article class="note-body">${renderMarkdown(source, { flavor: 'obsidian', noteID: 'n.md' }).html}</article>`);

test('Slack text uses mrkdwn conventions', () => {
  const root = render('# Title\n\nSome **bold**, *italic*, ~~gone~~ and `code` with [a link](https://example.org).\n\n- one\n  - nested\n- [x] done\n\n1. first\n2. second\n\n> quoted\n\n```\nblock\n```');
  const text = toSlackText(root.querySelector('.note-body'));
  assert.match(text, /^\*Title\*/);
  assert.match(text, /\*bold\*/);
  assert.match(text, /_italic_/);
  assert.match(text, /~gone~/);
  assert.match(text, /`code`/);
  assert.match(text, /a link \(https:\/\/example\.org\)/);
  assert.match(text, /• one\n {4}• nested/);
  assert.match(text, /☑ done/);
  assert.match(text, /1\. first\n2\. second/);
  assert.match(text, /> quoted/);
  assert.match(text, /```\nblock\n```/);
});

test('Slack text flattens callouts, tables, math and diagrams', () => {
  const root = render('> [!tip] Remember\n> Hydrate.\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nMath $x^2$.\n\n```mermaid\ngraph TD; A-->B\n```');
  const text = toSlackText(root.querySelector('.note-body'));
  assert.match(text, /> \*Remember\*\n> Hydrate\./);
  assert.match(text, /```\na \| b\n/);
  assert.match(text, /\$x\^2\$/);
  assert.match(text, /\[diagram\]/);
});

test('rich clipboard HTML is portable', () => {
  const root = render('## Heading\n\nText with [[Wiki]] and [web](https://example.org).\n\n> [!note] Callout\n> Body\n\n![img](a.png)\n\n```mermaid\ngraph TD; A-->B\n```');
  const html = toClipboardHTML(root.querySelector('.note-body'), { target: 'rich' });
  const out = dom(html);
  assert.ok(out.querySelector('h2[style]'));
  assert.equal(out.querySelectorAll('a').length, 1, 'only external links remain links');
  assert.match(out.textContent, /Wiki/);
  assert.ok(out.querySelector('blockquote strong'));
  assert.match(out.textContent, /\[image: img\]/);
  assert.match(out.textContent, /\[diagram\]/);
  assert.doesNotMatch(html, /data-|class=|obviewer-asset/);
});

test('Slack clipboard HTML turns headings into bold paragraphs', () => {
  const root = render('# Big\n\n- [ ] todo');
  const out = dom(toClipboardHTML(root.querySelector('.note-body'), { target: 'slack' }));
  assert.equal(out.querySelector('h1'), null);
  assert.equal(out.querySelector('p b').textContent, 'Big');
  assert.match(out.textContent, /☐ todo/);
});

test('rich clipboard HTML turns task checkboxes into ballot boxes (Word drops inputs)', () => {
  const root = render('- [ ] open\n- [x] done');
  const out = dom(toClipboardHTML(root.querySelector('.note-body'), { target: 'rich' }));
  assert.equal(out.querySelector('input'), null);
  assert.match(out.textContent, /☐ open/);
  assert.match(out.textContent, /☑ done/);
});
