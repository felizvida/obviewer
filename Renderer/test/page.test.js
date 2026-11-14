import test from 'node:test';
import assert from 'node:assert/strict';
import { buildPage } from '../src/core/page.js';
import { dom } from './helpers.js';

const base = { noteID: 'a.md', relativePath: 'a.md', title: 'My Note', flavor: 'markdown' };

test('the header title is skipped when the note starts with its own H1', () => {
  const withH1 = buildPage({ ...base, source: '# My Note\n\nBody' });
  assert.doesNotMatch(withH1.headerHTML, /note-title/);
  const withoutH1 = buildPage({ ...base, source: 'Body only' });
  assert.match(withoutH1.headerHTML, /<h1 class="note-title">My Note<\/h1>/);
});

test('header shows metadata, tags and properties; backlinks list linked notes', () => {
  const page = buildPage({
    ...base,
    source: 'Body',
    header: { path: 'Projects/Alpha/a.md', readingTime: 3, modified: 'Nov 14, 2026', tags: ['lab'], properties: [{ key: 'status', value: 'draft' }] },
    backlinks: [{ noteID: 'b.md', title: 'B', path: 'b.md' }],
  });
  const header = dom(page.headerHTML);
  assert.equal(header.querySelector('.note-meta').textContent, 'In Projects / Alpha. Edited Nov 14, 2026. 3 min read.');
  assert.equal(header.querySelector('a.tag').getAttribute('data-tag'), 'lab');
  assert.equal(header.querySelector('.note-properties td').textContent, 'draft');
  const backlinks = dom(page.backlinksHTML);
  assert.equal(backlinks.querySelector('a').getAttribute('data-note-id'), 'b.md');
});

test('header and backlinks can be hidden (Quick Look)', () => {
  const page = buildPage({ ...base, source: 'x', backlinks: [{ noteID: 'b', title: 'B' }], options: { showHeader: false, showBacklinks: false } });
  assert.equal(page.headerHTML, '');
  assert.equal(page.backlinksHTML, '');
});

test('titles and properties are escaped', () => {
  const page = buildPage({ ...base, title: '<img src=x onerror=alert(1)>', source: 'x', header: { properties: [{ key: '<b>', value: '<script>' }] } });
  assert.doesNotMatch(page.headerHTML, /<img|<script>|<b>/);
});

test('DokuWiki payloads use the DokuWiki renderer', () => {
  const page = buildPage({ ...base, flavor: 'dokuwiki', source: '====== Title ======\n**x**' });
  assert.equal(page.startsWithH1, true);
  assert.match(page.bodyHTML, /<strong>x<\/strong>/);
});

test('composePage puts the metadata under the note\'s own H1, or first when there is none', async () => {
  const { composePage } = await import('../src/core/page.js');
  const header = { path: 'a.md', modified: 'Nov 14, 2026' };
  const withH1 = dom(composePage(buildPage({ ...base, source: '# My Note\n\nBody', header })));
  const article = withH1.querySelector('article.note-body');
  assert.equal(article.children[0].tagName, 'H1');
  assert.equal(article.children[1].className, 'note-header');
  assert.equal(article.children[2].tagName, 'P');
  const withoutH1 = dom(composePage(buildPage({ ...base, source: 'Body', header })));
  assert.equal(withoutH1.querySelector('header.note-header h1.note-title').textContent, 'My Note');
});
