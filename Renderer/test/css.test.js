// Stylesheet rules that have broken rendering before.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const css = readFileSync(join(dirname(fileURLToPath(import.meta.url)), '../static/reader.css'), 'utf8');

test('display-math spacing is scoped, so it cannot reach MathML inside diagram labels', () => {
  // An unscoped `math[display="block"] { margin: … }` pushed Mermaid's math labels
  // against the top of their boxes (Mermaid renders labels as block MathML).
  assert.doesNotMatch(css, /(^|[,}]\s*)math\[display="block"\]\s*\{/m);
  assert.match(css, /\.mermaid-block math \{ margin: 0; \}/);
});

test('Mermaid math labels are measured and drawn with the same font size and margins', () => {
  assert.match(css, /#katex-temp \{ font-size: 16px; line-height: 1\.5; \}/);
  assert.match(css, /#katex-temp \.katex-display, \.mermaid-block \.katex-display \{ margin: 0; \}/);
});
