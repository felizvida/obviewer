import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizePath, parseWikiTarget, slugify, stripFrontmatter, stripObsidianComments, vaultAssetURL, parseSizeHint } from '../src/core/util.js';

test('normalizePath resolves dot segments and keeps escaping parents visible', () => {
  assert.equal(normalizePath('a/./b/../c.png'), 'a/c.png');
  assert.equal(normalizePath('../../etc/passwd'), '../../etc/passwd');
  assert.equal(normalizePath('a/../../x'), '../x');
});

test('parseWikiTarget splits target, anchor and alias', () => {
  assert.deepEqual(parseWikiTarget('Note#Heading|Alias'), { raw: 'Note#Heading', note: 'Note', anchor: 'Heading', alias: 'Alias' });
  assert.deepEqual(parseWikiTarget('#Local'), { raw: '#Local', note: '', anchor: 'Local', alias: null });
  assert.equal(parseWikiTarget('Note#H1#H2').anchor, 'H2');
  assert.equal(parseWikiTarget('Glossary\\|the glossary').alias, 'the glossary');
  assert.equal(parseWikiTarget('Note#^block').anchor, '^block');
});

test('vaultAssetURL resolves relative to the note folder and records the raw path', () => {
  const url = new URL(vaultAssetURL('../images/My Pic.png', { folder: 'notes/sub', noteID: 'notes/sub/a.md' }));
  assert.equal(url.protocol, 'obviewer-asset:');
  assert.equal(url.host, 'vault');
  assert.equal(decodeURIComponent(url.pathname), '/notes/images/My Pic.png');
  assert.equal(url.searchParams.get('from'), 'notes/sub/a.md');
  assert.equal(url.searchParams.get('raw'), '../images/My Pic.png');
  const rooted = new URL(vaultAssetURL('/assets/x.png', { folder: 'deep/er' }));
  assert.equal(rooted.pathname, '/assets/x.png');
});

test('frontmatter and comments are stripped, code is preserved', () => {
  assert.equal(stripFrontmatter('---\na: 1\n---\nBody'), 'Body');
  assert.equal(stripFrontmatter('No frontmatter\n---\n'), 'No frontmatter\n---\n');
  const source = 'keep %%drop%% this\n```\n%%in code%%\n```\n`%%inline%%`';
  assert.equal(stripObsidianComments(source), 'keep  this\n```\n%%in code%%\n```\n`%%inline%%`');
});

test('slugs and size hints', () => {
  assert.equal(slugify('Hello, World!'), 'hello-world');
  assert.equal(slugify('Über Größe'), 'über-größe');
  assert.deepEqual(parseSizeHint('200x100'), { width: 200, height: 100 });
  assert.equal(parseSizeHint('caption'), null);
});
