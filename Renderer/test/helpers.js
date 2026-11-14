import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseHTML } from 'linkedom';

export const fixturesDir = join(dirname(fileURLToPath(import.meta.url)), '../../Fixtures/notes');

export function fixture(name) {
  return readFileSync(join(fixturesDir, name), 'utf8');
}

export function expectations() {
  return JSON.parse(fixture('expectations.json'));
}

/** Parses an HTML fragment and returns its container element. */
export function dom(html) {
  const { document } = parseHTML(`<!doctype html><html><body><div id="root">${html}</div></body></html>`);
  return document.getElementById('root');
}

export function normalizeLinkTarget(target) {
  let value = String(target);
  try { value = decodeURIComponent(value); } catch { /* keep */ }
  return value.replace(/\.(md|markdown)$/i, '').trim().toLowerCase();
}
