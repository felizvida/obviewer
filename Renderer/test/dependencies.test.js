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
