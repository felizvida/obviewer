// The Quick Look bundle runs in a bare JavaScriptCore context: no DOM, no URL,
// no console, no timers. An empty vm context is a close stand-in.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dom, fixture } from './helpers.js';

const bundlePath = join(dirname(fileURLToPath(import.meta.url)), '../../Sources/ObviewerReaderKit/Resources/Reader/quicklook.js');

function renderStatic(payload) {
  const context = vm.createContext({});
  vm.runInContext(readFileSync(bundlePath, 'utf8'), context);
  return context.ObviewerQuickLook.render(JSON.stringify(payload));
}

test('Quick Look bundle renders in a context without DOM or web APIs', () => {
  const html = renderStatic({
    noteID: 'obsidian-basics.md', relativePath: 'obsidian-basics.md', title: 'Obsidian Basics',
    flavor: 'markdown', source: fixture('obsidian-basics.md'), options: { showHeader: false, showBacklinks: false },
  });
  const root = dom(html);
  assert.ok(root.querySelector('.callout'));
  assert.ok(root.querySelector('math'), 'math rendered as MathML');
  assert.equal(root.querySelector('.katex-html'), null, 'no KaTeX HTML (fonts unavailable)');
  assert.match(root.querySelector('[data-plugin="mermaid"] figcaption').textContent, /open in Obviewer/);
  assert.ok(root.querySelector('code.language-python .hljs-keyword'));
  assert.equal(root.querySelectorAll('img').length, 0, 'no image loads in static previews');
});

test('Quick Look previews show raw HTML as text', () => {
  const html = renderStatic({
    noteID: 'h.md', relativePath: 'h.md', title: 'h', flavor: 'markdown', source: fixture('hostile-html.md'), options: {},
  });
  const root = dom(html);
  for (const tag of ['script', 'iframe', 'form', 'object', 'style', 'img', 'svg']) {
    assert.equal(root.querySelector(tag), null, `${tag} must not appear`);
  }
  assert.equal(root.querySelector('[onerror]'), null);
  assert.equal(root.querySelector('a[href^="javascript:"]'), null);
  assert.match(root.textContent, /<script>/, 'shown as literal text');
});

test('Quick Look renders DokuWiki pages statically', () => {
  const html = renderStatic({
    noteID: 'lab/protocols.txt', relativePath: 'lab/protocols.txt', title: 'Lab', flavor: 'dokuwiki',
    source: fixture('dokuwiki/data/pages/lab/protocols.txt'), options: { showHeader: false },
  });
  const root = dom(html);
  assert.ok(root.querySelector('h1'));
  assert.ok(root.querySelector('table'));
  assert.equal(root.querySelectorAll('img').length, 0);
  assert.match(root.textContent, /Image: Example gel/);
});
