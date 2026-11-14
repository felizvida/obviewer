import test from 'node:test';
import assert from 'node:assert/strict';
import { renderDokuWiki, resolveID, cleanID } from '../src/core/dokuwiki.js';
import { dom, fixture } from './helpers.js';

const noteID = 'dokuwiki/data/pages/lab/protocols.txt';
const options = { noteID, pagesBase: 'dokuwiki/data/pages', mediaBase: 'dokuwiki/data/media' };

test('IDs resolve relative to the current namespace', () => {
  assert.equal(resolveID('start', ['lab']), 'lab:start');
  assert.equal(resolveID(':start', ['lab']), 'start');
  assert.equal(resolveID('..:other', ['lab', 'sub']), 'lab:other');
  assert.equal(resolveID('.:x', ['lab']), 'lab:x');
  assert.equal(resolveID('ns:', []), 'ns:start');
  assert.equal(cleanID(' My Page '), 'my_page');
});

test('the DokuWiki fixture renders headings, lists, tables, code and media', () => {
  const result = renderDokuWiki(fixture('dokuwiki/data/pages/lab/protocols.txt'), options);
  const root = dom(result.html);
  assert.equal(result.startsWithH1, true);
  assert.deepEqual(result.headings.map((h) => [h.level, h.text]), [[1, 'Lab Protocols'], [2, 'Equipment']]);
  assert.ok(root.querySelector('p strong'));
  assert.ok(root.querySelector('ul li ul li'));
  assert.ok(root.querySelector('ol li'));
  assert.equal(root.querySelectorAll('th').length, 2);
  assert.ok(root.querySelector('code.language-bash'));
  const image = root.querySelector('img');
  assert.equal(new URL(image.getAttribute('src')).pathname, '/dokuwiki/data/media/lab/gel.png');
  assert.equal(image.getAttribute('width'), '200');
  assert.ok(image.classList.contains('media-center'));
  const links = [...root.querySelectorAll('a.wikilink')].map((a) => [a.getAttribute('data-wikilink'), a.getAttribute('data-anchor')]);
  assert.deepEqual(links, [['lab:start', null], ['safety:training', 'ppe'], ['lab:reagents', null], ['lab:storage', null]]);
  assert.ok(root.querySelector('a.interwiki[href^="https://en.wikipedia.org/wiki/"]'));
  assert.ok(root.querySelector('.footnotes li'));
  assert.deepEqual([...root.querySelectorAll('a.tag')].map((a) => a.getAttribute('data-tag')), ['lab', 'sop']);
});

test('italic markers inside URLs are left alone', () => {
  const root = dom(renderDokuWiki('See http://example.com/a//b and //real italic//.', options).html);
  assert.equal(root.querySelectorAll('em').length, 1);
  assert.equal(root.querySelector('em').textContent, 'real italic');
});

test('nowiki and %% keep markup literal; HTML is escaped', () => {
  const root = dom(renderDokuWiki('<nowiki>**not bold**</nowiki> %%//nor this//%% <script>x</script>', options).html);
  assert.equal(root.querySelector('strong'), null);
  assert.equal(root.querySelector('script'), null);
  assert.match(root.textContent, /\*\*not bold\*\*/);
});
