// Entry for Quick Look previews. Runs in a bare JavaScriptCore context inside
// the Quick Look extension: no DOM, no WebKit, no network. Produces static HTML
// (raw HTML in notes is shown as text, math is MathML, diagrams stay as source).

import hljs from 'highlight.js/lib/common';
import { buildPage } from './core/page.js';

globalThis.ObviewerQuickLook = {
  version: 1,
  render(payloadJSON) {
    const payload = JSON.parse(payloadJSON);
    payload.options = { ...(payload.options ?? {}), staticMode: true };
    const page = buildPage(payload, { hljs });
    return `${page.headerHTML}<article class="note-body">${page.bodyHTML}</article>`;
  },
};
