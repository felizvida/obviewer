// The same expectations are checked by the Swift indexer
// (Tests/ObviewerCoreTests/SharedFixtureLinkTests.swift).
import test from 'node:test';
import assert from 'node:assert/strict';
import { extractLinks } from '../src/core/markdown.js';
import { extractDokuWikiLinks } from '../src/core/dokuwiki.js';
import { expectations, fixture, normalizeLinkTarget } from './helpers.js';

for (const [name, expected] of Object.entries(expectations())) {
  test(`shared fixture links: ${name}`, () => {
    const source = fixture(name);
    const links = expected.flavor === 'dokuwiki'
      ? extractDokuWikiLinks(source, { noteID: name, pagesBase: expected.pagesBase })
      : extractLinks(source, { flavor: expected.flavor });
    assert.deepEqual(
      [...new Set(links.map(normalizeLinkTarget))].sort(),
      [...new Set(expected.links.map(normalizeLinkTarget))].sort(),
    );
  });
}
