// The shipped reader bundle must not carry a KaTeX older than the security floor
// (GHSA-238p-pmpm-9mq7, fixed in 0.18.2), including the copy Mermaid uses.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const bundle = join(dirname(fileURLToPath(import.meta.url)), '../../Sources/ObviewerReaderKit/Resources/Reader');
const manifest = JSON.parse(readFileSync(join(bundle, 'manifest.json'), 'utf8'));
const atLeast = (version, floor) => {
  const parts = version.split(/[.-]/).map(Number);
  for (let i = 0; i < 3; i += 1) if (parts[i] !== floor[i]) return parts[i] > floor[i];
  return true;
};

test('the bundled KaTeX is at or above the security floor', () => {
  assert.ok(atLeast(manifest.versions.katex, [0, 18, 2]), `KaTeX ${manifest.versions.katex}`);
});

test('Mermaid and the reader embed that same KaTeX, not an older copy', () => {
  const literal = `"${manifest.versions.katex}"`;
  for (const file of ['mermaid.min.js', 'reader.js', 'quicklook.js']) {
    const source = readFileSync(join(bundle, file), 'utf8');
    assert.ok(source.includes(literal), `${file} should embed KaTeX ${manifest.versions.katex}`);
    assert.ok(!source.includes('"0.16.47"'), `${file} still embeds KaTeX 0.16.47`);
  }
});

test('the ELK layout engine is left out, and the notices cover what ships', () => {
  const mermaid = readFileSync(join(bundle, 'mermaid.min.js'), 'utf8');
  assert.ok(mermaid.includes('The ELK layout is not included in Obviewer'), 'elkjs is replaced by the stub');
  const notices = readFileSync(join(bundle, 'THIRD_PARTY_NOTICES.txt'), 'utf8');
  assert.ok(!notices.includes('=== elkjs '), 'elkjs must not be bundled');
  for (const name of ['mermaid', 'katex', 'dompurify', 'markdown-it', 'highlight.js', 'chevrotain', 'cytoscape']) {
    assert.match(notices, new RegExp(`^=== ${name.replace('.', '\\.')} `, 'm'), `notices list ${name}`);
  }
});
