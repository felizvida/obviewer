import test from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown, extractLinks } from '../src/core/markdown.js';
import { dom, fixture } from './helpers.js';

const obsidian = (source, options = {}) => renderMarkdown(source, { flavor: 'obsidian', noteID: 'note.md', ...options });
const gfm = (source, options = {}) => renderMarkdown(source, { flavor: 'markdown', noteID: 'README.md', ...options });

test('bold can contain a link (structural nesting the old parser lacked)', () => {
  const root = dom(obsidian('**bold with a [[Glossary|glossary link]] inside**').html);
  const link = root.querySelector('strong a.wikilink');
  assert.ok(link, 'wikilink nested in <strong>');
  assert.equal(link.getAttribute('data-wikilink'), 'Glossary');
  assert.equal(link.textContent, 'glossary link');
});

test('callouts can contain lists and fold', () => {
  const root = dom(obsidian('> [!warning]- Check\n> - one\n> - **two**').html);
  const callout = root.querySelector('details.callout[data-callout="warning"]');
  assert.ok(callout, 'foldable callout');
  assert.equal(callout.hasAttribute('open'), false);
  assert.equal(callout.querySelector('.callout-title-text').textContent, 'Check');
  assert.equal(callout.querySelectorAll('.callout-content li').length, 2);
  assert.ok(callout.querySelector('li strong'));
});

test('callout aliases, default titles and GitHub alerts', () => {
  const root = dom(gfm('> [!NOTE]\n> GitHub alert.\n\n> [!faq] Why?\n> Because.').html);
  const [note, faq] = root.querySelectorAll('.callout');
  assert.equal(note.getAttribute('data-callout'), 'note');
  assert.equal(note.querySelector('.callout-title-text').textContent, 'Note');
  assert.equal(note.querySelector('.callout-content p').textContent, 'GitHub alert.');
  assert.equal(faq.getAttribute('data-callout'), 'question');
  assert.equal(faq.getAttribute('data-callout-raw'), 'faq');
});

test('a stray asterisk does not italicize the rest of the paragraph', () => {
  const root = dom(gfm(fixture('tricky-emphasis.md')).html);
  assert.equal(root.querySelectorAll('em').length, 0, root.innerHTML);
  assert.match(root.textContent, /2 \* 3 \* 4/);
  assert.match(root.textContent, /snake_case_name/);
});

test('dollar amounts stay text while real math renders', () => {
  const root = dom(obsidian('Price $5 and $10. Math $x^2$ here.\n\n$$\n\\frac{1}{2}\n$$').html);
  assert.match(root.textContent, /\$5 and \$10/);
  assert.equal(root.querySelectorAll('.math-inline').length, 1);
  assert.equal(root.querySelectorAll('.math-display').length, 1);
  assert.ok(root.querySelector('.katex'), 'KaTeX output present');
});

test('mermaid fences become diagram placeholders and code is highlighted', () => {
  const root = dom(gfm('```mermaid\ngraph TD; A-->B\n```\n\n```python\ndef f():\n    return 1\n```').html);
  const diagram = root.querySelector('figure.mermaid-block pre.mermaid');
  assert.ok(diagram);
  assert.match(diagram.textContent, /A-->B/);
  assert.ok(root.querySelector('code.language-python .hljs-keyword'));
});

test('task lists including custom statuses', () => {
  const root = dom(obsidian('- [ ] open\n- [x] done\n- [/] doing').html);
  const items = root.querySelectorAll('li.task-list-item');
  assert.equal(items.length, 3);
  assert.equal(items[0].querySelector('input').hasAttribute('checked'), false);
  assert.equal(items[1].querySelector('input').hasAttribute('checked'), true);
  assert.equal(items[2].getAttribute('data-task'), '/');
  assert.ok(root.querySelector('ul.contains-task-list'));
});

test('highlights, comments, tags and block ids', () => {
  const root = dom(obsidian('A ==marked== word %%secret%% with #tag and #123 and C#.\n\nParagraph text ^abc-1').html);
  assert.equal(root.querySelector('mark').textContent, 'marked');
  assert.doesNotMatch(root.textContent, /secret/);
  const tags = [...root.querySelectorAll('a.tag')].map((a) => a.getAttribute('data-tag'));
  assert.deepEqual(tags, ['tag']);
  const block = root.querySelector('[id="^abc-1"]');
  assert.ok(block);
  assert.doesNotMatch(block.textContent, /\^abc-1/);
});

test('wiki links: anchors, unresolved state and code spans', () => {
  const root = dom(obsidian('[[Note#Part]] [[#Local]] [[Missing]] `[[Not]]`', { resolvedLinks: { Note: true, Missing: false } }).html);
  const links = root.querySelectorAll('a.wikilink');
  assert.equal(links.length, 3);
  assert.equal(links[0].getAttribute('data-anchor'), 'Part');
  assert.equal(links[0].textContent, 'Note › Part');
  assert.equal(links[1].getAttribute('data-wikilink'), '');
  assert.ok(links[2].classList.contains('is-unresolved'));
  assert.equal(root.querySelector('code').textContent, '[[Not]]');
});

test('images go through the asset scheme; remote images are not loaded', () => {
  const root = dom(gfm('![Alt|200](<img/a b.png>) ![remote](https://example.com/x.png)', { relativePath: 'docs/README.md' }).html);
  const image = root.querySelector('img');
  const url = new URL(image.getAttribute('src'));
  assert.equal(decodeURIComponent(url.pathname), '/docs/img/a b.png');
  assert.equal(image.getAttribute('width'), '200');
  assert.equal(image.getAttribute('alt'), 'Alt');
  assert.equal(root.querySelectorAll('img').length, 1);
  assert.ok(root.querySelector('a.remote-image'));
});

test('links are classified for Swift-side navigation', () => {
  const root = dom(gfm('[ext](https://example.org) [doc](docs/guide.md#install) [pdf](files/a.pdf) [top](#intro)').html);
  const [ext, doc, pdf, top] = root.querySelectorAll('a');
  assert.equal(ext.getAttribute('data-external'), 'true');
  assert.ok(doc.classList.contains('internal-link'));
  assert.equal(doc.getAttribute('data-href'), 'docs/guide.md#install');
  assert.ok(pdf.classList.contains('attachment-link'));
  assert.ok(top.classList.contains('anchor-link'));
});

test('headings get unique ids and are reported for the outline', () => {
  const result = gfm('# Title\n\n## Setup\n\n## Setup\n\n### Details `x`');
  assert.equal(result.startsWithH1, true);
  assert.equal(result.firstHeading, 'Title');
  assert.deepEqual(result.headings.map((h) => h.id), ['title', 'setup', 'setup-1', 'details-x']);
});

test('frontmatter is not rendered', () => {
  const result = obsidian('---\ntitle: X\n---\nBody');
  assert.doesNotMatch(result.html, /title: X/);
  assert.equal(result.startsWithH1, false);
});

test('note embeds render resolved content, sections and problems', () => {
  const embeds = {
    'Plan#Timeline': {
      status: 'ok', kind: 'note', noteID: 'folder/Plan.md', relativePath: 'folder/Plan.md', title: 'Plan',
      markdown: '# Plan\n\nIntro\n\n## Timeline\n\n- Q1 ![[chart.png]]\n\n## Later\n\nNot included',
      embeds: { 'chart.png': { status: 'ok', kind: 'image', path: 'assets/chart.png', name: 'chart.png' } },
    },
    Loop: { status: 'cycle' },
    Gone: { status: 'missing' },
  };
  const root = dom(obsidian('![[Plan#Timeline]]\n\n![[Loop]]\n\n![[Gone]]', { embeds }).html);
  const embed = root.querySelector('section.embed-note');
  assert.ok(embed);
  assert.match(embed.textContent, /Q1/);
  assert.doesNotMatch(embed.textContent, /Not included/);
  assert.doesNotMatch(embed.textContent, /Intro/);
  const image = embed.querySelector('img');
  assert.equal(new URL(image.getAttribute('src')).pathname, '/assets/chart.png');
  assert.equal(new URL(image.getAttribute('src')).searchParams.get('from'), 'folder/Plan.md');
  const problems = [...root.querySelectorAll('.embed-problem')].map((el) => el.getAttribute('data-status'));
  assert.deepEqual(problems, ['cycle', 'missing']);
  // Embedded headings must not collide with the host note's ids.
  assert.ok(embed.querySelector('h2').id.startsWith('embed'));
});

test('block embeds select a single block', () => {
  const embeds = {
    'Plan#^decision-1': {
      status: 'ok', kind: 'note', noteID: 'Plan.md', title: 'Plan',
      markdown: 'Before.\n\n- Option A\n- We chose B ^decision-1\n\nAfter.',
    },
  };
  const root = dom(obsidian('![[Plan#^decision-1]]', { embeds }).html);
  const body = root.querySelector('.embed-body');
  assert.match(body.textContent, /We chose B/);
  assert.doesNotMatch(body.textContent, /Before|After|Option A/);
});

test('unresolved image embeds fall back to a path relative to the note', () => {
  const root = dom(obsidian('![[pic.png|300]]', { relativePath: 'a/b.md', noteID: 'a/b.md' }).html);
  const image = root.querySelector('img');
  assert.equal(new URL(image.getAttribute('src')).pathname, '/a/pic.png');
  assert.equal(image.getAttribute('width'), '300');
});

test('extractLinks ignores code and external links', () => {
  const links = extractLinks('[[A]] [b](b.md) [c](https://x.y) `[[D]]`\n\n```\n[[E]]\n```', { flavor: 'obsidian' });
  assert.deepEqual(links, ['A', 'b']);
});

test('the full Obsidian fixture renders without losing structure', () => {
  const result = obsidian(fixture('obsidian-basics.md'));
  const root = dom(result.html);
  assert.ok(root.querySelector('details.callout'));
  assert.ok(root.querySelector('.callout[data-callout="tip"]'));
  assert.ok(root.querySelector('.mermaid-block'));
  assert.ok(root.querySelector('.math-display .katex'));
  assert.ok(root.querySelector('.footnotes'));
  assert.ok(root.querySelector('[id="^para-1"]'));
  assert.equal(root.querySelectorAll('li.task-list-item').length, 3);
  assert.deepEqual(result.headings.map((h) => h.text), ['Obsidian Basics', 'Tasks', 'Math and diagrams']);
});

test('the GitHub README fixture keeps tables, alerts and raw HTML', () => {
  const root = dom(gfm(fixture('gfm-readme.md')).html);
  assert.equal(root.querySelectorAll('.callout').length, 2);
  assert.ok(root.querySelector('table td code'));
  assert.equal(root.querySelector('table td code').textContent, 'a | b');
  assert.ok(root.querySelector('details summary'));
  assert.ok(root.querySelector('a[href="https://example.org"]'));
  assert.ok(root.querySelector('.footnotes'));
});

test('callout titles do not pick up the document footnote list', () => {
  const root = dom(obsidian('> [!warning]- Check\n> - item\n\n> [!tip]\n> Body\n\nText with a note[^1].\n\n[^1]: The note.').html);
  for (const title of root.querySelectorAll('.callout-title')) {
    assert.equal(title.querySelector('.footnotes, ol, hr'), null, title.innerHTML);
  }
  assert.equal(root.querySelectorAll('section.footnotes').length, 1);
});
