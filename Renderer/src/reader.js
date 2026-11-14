// Browser entry for Obviewer's reader page. Loaded from obviewer-asset://app/.
// Swift drives it through window.obviewer.* (callAsyncJavaScript) and receives
// events through webkit.messageHandlers.obviewer. Nothing here can write files:
// the only outputs are messages that Swift chooses how to handle.

import DOMPurify from 'dompurify';
import hljs from 'highlight.js/lib/common';

import { buildPage, composePage } from './core/page.js';
import { normalizeHeadingText, slugify } from './core/util.js';
import { toClipboardHTML, toSlackText } from './core/export.js';
import { enforceInputPolicy } from './core/sanitize-policy.js';

const state = {
  noteID: null,
  mermaidPromise: null,
  renderToken: 0,
};

function post(message) {
  try {
    window.webkit?.messageHandlers?.obviewer?.postMessage(message);
  } catch {
    // Not running inside Obviewer (e.g. opened in a browser for debugging).
  }
}

// Diagnostics: report page errors and CSP blocks to Swift (they're logged, never acted on).
window.addEventListener('error', (event) => {
  post({ type: 'jsError', message: `${event.message} (${event.filename || 'page'}:${event.lineno || 0})` });
});
window.addEventListener('unhandledrejection', (event) => {
  post({ type: 'jsError', message: `Unhandled rejection: ${String(event.reason?.stack || event.reason)}` });
});
document.addEventListener('securitypolicyviolation', (event) => {
  post({ type: 'cspViolation', message: `${event.effectiveDirective} blocked ${event.blockedURI || 'inline'}` });
});

const PURIFY_CONFIG = {
  ALLOWED_URI_REGEXP: /^(?:obviewer-asset:|https?:|mailto:|tel:|obsidian:|data:image\/(?:png|jpe?g|gif|webp|svg\+xml);|#|[^a-z]|[a-z+.-]+(?:[^a-z+.\-:]|$))/i,
  FORBID_TAGS: ['form', 'button', 'textarea', 'select', 'option', 'iframe', 'frame', 'frameset', 'object', 'embed', 'applet', 'base', 'link', 'meta', 'style', 'script'],
  FORBID_ATTR: ['srcset', 'action', 'formaction', 'ping'],
  ADD_ATTR: ['open'],
  ADD_TAGS: ['semantics', 'annotation'],
  ALLOW_DATA_ATTR: true,
};

// DOMPurify returns its input unchanged when it considers the environment
// unsupported. Never let that happen silently: fall back to plain text.
const purifierWorks = (() => {
  try {
    return DOMPurify.isSupported === true
      && !DOMPurify.sanitize('<img src=x onerror=alert(1)><script>x</script>').match(/onerror|<script/i);
  } catch {
    return false;
  }
})();

function escapeAsText(html) {
  const pre = document.createElement('pre');
  pre.className = 'code-block sanitizer-unavailable';
  pre.textContent = html.replace(/<[^>]*>/g, '');
  return pre.outerHTML;
}

DOMPurify.addHook?.('uponSanitizeElement', (node) => {
  if (!enforceInputPolicy(node)) node.parentNode?.removeChild(node);
});

function sanitize(html) {
  if (!purifierWorks) return escapeAsText(html);
  return DOMPurify.sanitize(html, PURIFY_CONFIG);
}

// ---------------------------------------------------------------------------
// Rendering

async function render(payload) {
  try {
    return await renderUnchecked(payload);
  } catch (error) {
    post({ type: 'jsError', message: `render failed: ${String(error?.stack || error)}` });
    throw error;
  }
}

async function renderUnchecked(payload) {
  const token = ++state.renderToken;
  const root = document.getElementById('ob-root');
  const sameNote = state.noteID === payload.noteID;
  const preserve = sameNote && payload.options?.preserveScroll !== false;
  const previousScroll = preserve ? window.scrollY : 0;

  const page = buildPage(payload, { hljs });
  root.innerHTML = composePage(page, sanitize);
  root.dataset.flavor = payload.flavor ?? 'markdown';
  document.title = payload.title ?? '';
  state.noteID = payload.noteID;

  postProcess(root, payload);

  if (payload.options?.anchor) {
    requestAnimationFrame(() => scrollToAnchor(payload.options.anchor));
  } else {
    window.scrollTo(0, previousScroll);
  }

  // Diagrams render asynchronously; keep the scroll position stable while they do.
  renderDiagrams(root).then(() => {
    if (token !== state.renderToken) return;
    if (preserve && !payload.options?.anchor) window.scrollTo(0, previousScroll);
    post({ type: 'diagramsRendered', noteID: payload.noteID });
  });

  post({ type: 'rendered', noteID: payload.noteID, headings: page.headings });
  return { headings: page.headings };
}

function postProcess(root, payload) {
  // Raw HTML images with relative paths go through the asset scheme too.
  for (const image of root.querySelectorAll('img:not([data-ob-asset])')) {
    const src = image.getAttribute('src') || '';
    if (!src || /^(data:|obviewer-asset:)/i.test(src)) continue;
    if (/^[a-z][a-z0-9+.-]*:/i.test(src)) {
      image.replaceWith(Object.assign(document.createElement('span'), {
        className: 'remote-image-label',
        textContent: `Remote image not loaded: ${image.getAttribute('alt') || src}`,
      }));
      continue;
    }
    const folder = (payload.relativePath ?? payload.noteID ?? '').split('/').slice(0, -1).join('/');
    const url = new URL(`obviewer-asset://vault/${encodePath(folder ? `${folder}/${src}` : src)}`);
    url.searchParams.set('from', payload.noteID ?? '');
    url.searchParams.set('raw', src);
    image.setAttribute('src', url.toString());
    image.dataset.obAsset = '1';
  }

  for (const image of root.querySelectorAll('img')) {
    image.addEventListener('error', () => {
      image.classList.add('is-missing');
      post({ type: 'assetError', src: image.getAttribute('src') });
    }, { once: true });
  }

  // Raw HTML links: mark external ones so the click handler treats them consistently.
  for (const link of root.querySelectorAll('a[href]:not([data-wikilink]):not([data-tag]):not([data-note-id])')) {
    const href = link.getAttribute('href');
    if (/^(https?:|mailto:|tel:|obsidian:)/i.test(href)) link.dataset.external = 'true';
    else if (/^[a-z][a-z0-9+.-]*:/i.test(href)) {
      // Any other scheme (javascript:, file:, data:, vbscript:, ...) is inert.
      link.removeAttribute('href');
      delete link.dataset.href;
      link.classList.add('inert-link');
    } else if (!href.startsWith('#') && !link.dataset.href) {
      link.dataset.href = href;
      link.dataset.from = payload.noteID ?? '';
    }
  }

  // Copy buttons on code blocks.
  for (const wrapper of root.querySelectorAll('.code-wrapper')) {
    const button = document.createElement('span');
    button.className = 'copy-button';
    button.setAttribute('role', 'button');
    button.setAttribute('tabindex', '0');
    button.setAttribute('aria-label', 'Copy code');
    button.textContent = 'Copy';
    wrapper.appendChild(button);
  }

  // Wide tables scroll horizontally instead of overflowing the page.
  for (const table of root.querySelectorAll('.note-body table')) {
    if (table.parentElement?.classList.contains('table-wrapper')) continue;
    const wrapper = document.createElement('div');
    wrapper.className = 'table-wrapper';
    table.replaceWith(wrapper);
    wrapper.appendChild(table);
  }
}

function encodePath(path) {
  const parts = [];
  for (const segment of path.split('/')) {
    if (segment === '' || segment === '.') continue;
    if (segment === '..') parts.length ? parts.pop() : parts.push('..');
    else parts.push(segment);
  }
  return parts.map((part) => encodeURIComponent(safeDecode(part))).join('/');
}

function safeDecode(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

// ---------------------------------------------------------------------------
// Mermaid

function isDark() {
  const forced = document.documentElement.dataset.theme;
  if (forced === 'dark') return true;
  if (forced === 'light') return false;
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ?? false;
}

function loadMermaid() {
  if (!state.mermaidPromise) {
    state.mermaidPromise = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'mermaid.min.js';
      script.onload = () => (window.mermaid ? resolve(window.mermaid) : reject(new Error('Mermaid failed to initialise')));
      script.onerror = () => reject(new Error('Mermaid bundle missing'));
      document.head.appendChild(script);
    });
  }
  return state.mermaidPromise;
}

let diagramCounter = 0;

async function renderDiagrams(root) {
  const blocks = [...root.querySelectorAll('.mermaid-block')];
  if (!blocks.length) return;
  let mermaid;
  try {
    mermaid = await loadMermaid();
  } catch (error) {
    for (const block of blocks) showDiagramError(block, error);
    return;
  }
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    theme: isDark() ? 'dark' : 'neutral',
    fontFamily: '-apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif',
    flowchart: { htmlLabels: false },
    suppressErrorRendering: true,
  });
  for (const block of blocks) {
    const pre = block.querySelector('pre.mermaid');
    const code = block.dataset.source ?? pre?.textContent ?? '';
    block.dataset.source = code;
    diagramCounter += 1;
    try {
      const { svg } = await mermaid.render(`ob-mermaid-${diagramCounter}`, code);
      block.innerHTML = svg;
      block.dataset.state = 'rendered';
      block.setAttribute('role', 'img');
      block.setAttribute('aria-label', 'Diagram');
    } catch (error) {
      showDiagramError(block, error);
    }
  }
}

function showDiagramError(block, error) {
  const code = block.dataset.source ?? block.textContent;
  block.dataset.state = 'error';
  block.innerHTML = '';
  const caption = document.createElement('figcaption');
  caption.className = 'diagram-error';
  caption.textContent = `Diagram couldn’t be drawn: ${String(error?.message ?? error).split('\n')[0]}`;
  const pre = document.createElement('pre');
  pre.className = 'code-block';
  pre.textContent = code;
  block.append(caption, pre);
}

window.matchMedia?.('(prefers-color-scheme: dark)').addEventListener?.('change', () => {
  rerenderDiagrams();
});

function rerenderDiagrams() {
  const root = document.getElementById('ob-root');
  for (const block of root.querySelectorAll('.mermaid-block[data-source]')) {
    block.innerHTML = '';
    block.dataset.state = 'pending';
  }
  renderDiagrams(root);
}

// ---------------------------------------------------------------------------
// Navigation

export function scrollToAnchor(anchor) {
  if (!anchor) return false;
  const raw = String(anchor).replace(/^#/, '');
  const root = document.getElementById('ob-root');
  const candidates = [
    () => document.getElementById(raw),
    () => document.getElementById(raw.startsWith('^') ? raw : `^${raw}`),
    () => document.getElementById(slugify(raw)),
    () => {
      const wanted = normalizeHeadingText(raw);
      return [...root.querySelectorAll('[data-heading]')].find((el) => normalizeHeadingText(el.dataset.heading) === wanted);
    },
    () => root.querySelector(`[data-doku-section="${CSS.escape(raw.toLowerCase().replace(/\s+/g, '_'))}"]`),
  ];
  for (const find of candidates) {
    const element = find();
    if (element && !element.closest('.embed-note')) {
      element.scrollIntoView({ block: 'start', behavior: 'instant' });
      window.scrollBy(0, -16);
      element.classList.remove('anchor-flash');
      void element.offsetWidth;
      element.classList.add('anchor-flash');
      return true;
    }
  }
  return false;
}

document.addEventListener('click', (event) => {
  const copy = event.target.closest?.('.copy-button');
  if (copy) {
    event.preventDefault();
    const code = copy.parentElement.querySelector('pre')?.textContent ?? '';
    post({ type: 'copy', text: code });
    copy.textContent = 'Copied';
    setTimeout(() => { copy.textContent = 'Copy'; }, 1200);
    return;
  }

  const image = event.target.closest?.('.note-body img');
  if (image && !event.target.closest('a')) {
    image.classList.toggle('is-zoomed');
    return;
  }

  const link = event.target.closest?.('a');
  if (!link) return;
  event.preventDefault();
  const newWindow = event.metaKey;

  if (link.dataset.tag) {
    post({ type: 'link', kind: 'tag', target: link.dataset.tag });
    return;
  }
  if (link.dataset.noteId) {
    post({ type: 'link', kind: 'noteID', target: link.dataset.noteId, newWindow });
    return;
  }
  if ('wikilink' in link.dataset) {
    const target = link.dataset.wikilink;
    const anchor = link.dataset.anchor ?? null;
    if (!target && anchor) {
      scrollToAnchor(anchor);
      return;
    }
    post({ type: 'link', kind: 'wiki', target, anchor, from: link.dataset.from ?? state.noteID, newWindow });
    return;
  }
  const href = link.getAttribute('href') || '';
  if (href.startsWith('#') && href.length > 1) {
    scrollToAnchor(safeDecode(href.slice(1)));
    return;
  }
  if (link.dataset.external === 'true') {
    post({ type: 'link', kind: 'external', href });
    return;
  }
  if (link.dataset.href) {
    const [path, anchor] = link.dataset.href.split('#');
    post({ type: 'link', kind: 'path', target: safeDecode(path), anchor: anchor ? safeDecode(anchor) : null, from: link.dataset.from ?? state.noteID, newWindow });
  }
});

document.addEventListener('keydown', (event) => {
  if ((event.key === 'Enter' || event.key === ' ') && event.target.classList?.contains('copy-button')) {
    event.preventDefault();
    event.target.click();
  }
});

// ---------------------------------------------------------------------------
// Appearance

function setAppearance({ textScale, lineWidth, theme } = {}) {
  const style = document.documentElement.style;
  if (typeof textScale === 'number') style.setProperty('--ob-text-scale', String(Math.min(Math.max(textScale, 0.8), 1.5)));
  if (typeof lineWidth === 'number') style.setProperty('--ob-measure', `${Math.min(Math.max(lineWidth, 52), 96)}ch`);
  if (theme === 'light' || theme === 'dark') document.documentElement.dataset.theme = theme;
  else if (theme === 'system') delete document.documentElement.dataset.theme;
  if (theme) rerenderDiagrams();
}

// ---------------------------------------------------------------------------
// Export

async function rasterizeDiagrams(root) {
  const images = new Map();
  for (const block of root.querySelectorAll('.mermaid-block[data-state="rendered"]')) {
    const svg = block.querySelector('svg');
    if (!svg) continue;
    try {
      images.set(block, await svgToPNG(svg));
    } catch {
      // Leave it out; the export shows "[diagram]" instead.
    }
  }
  return images;
}

function svgToPNG(svg) {
  return new Promise((resolve, reject) => {
    const box = svg.getBoundingClientRect();
    const width = Math.max(1, Math.ceil(box.width));
    const height = Math.max(1, Math.ceil(box.height));
    const clone = svg.cloneNode(true);
    clone.setAttribute('width', String(width));
    clone.setAttribute('height', String(height));
    clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
    const data = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(new XMLSerializer().serializeToString(clone))}`;
    const image = new Image();
    image.onload = () => {
      const scale = 2;
      const canvas = document.createElement('canvas');
      canvas.width = width * scale;
      canvas.height = height * scale;
      const context = canvas.getContext('2d');
      context.fillStyle = '#ffffff';
      context.fillRect(0, 0, canvas.width, canvas.height);
      context.scale(scale, scale);
      context.drawImage(image, 0, 0, width, height);
      try {
        resolve(canvas.toDataURL('image/png'));
      } catch (error) {
        reject(error);
      }
    };
    image.onerror = reject;
    image.src = data;
  });
}

function imageToDataURL(image) {
  try {
    if (!image.complete || !image.naturalWidth) return null;
    const canvas = document.createElement('canvas');
    const maxWidth = 1400;
    const scale = Math.min(1, maxWidth / image.naturalWidth);
    canvas.width = Math.round(image.naturalWidth * scale);
    canvas.height = Math.round(image.naturalHeight * scale);
    canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
    return canvas.toDataURL('image/png');
  } catch {
    return null;
  }
}

function exportRoot() {
  return document.getElementById('ob-root');
}

async function exportRich() {
  const root = exportRoot();
  const diagramImages = await rasterizeDiagrams(root);
  // Inline local images as data URLs so they survive pasting into Mail/Word.
  const restore = [];
  for (const image of root.querySelectorAll('img[data-ob-asset]')) {
    const data = imageToDataURL(image);
    if (data) {
      restore.push([image, image.getAttribute('src')]);
      image.setAttribute('src', data);
    }
  }
  try {
    const html = toClipboardHTML(root, { target: 'rich', diagramImages, includeHeader: true });
    return { html, text: toSlackText(root.querySelector('.note-body') ?? root) };
  } finally {
    for (const [image, src] of restore) image.setAttribute('src', src);
  }
}

function exportSlack() {
  const root = exportRoot();
  const body = root.querySelector('.note-body') ?? root;
  return { html: toClipboardHTML(body, { target: 'slack' }), text: toSlackText(body) };
}

// ---------------------------------------------------------------------------

window.obviewer = {
  version: 1,
  render,
  scrollToAnchor,
  setAppearance,
  exportRich,
  exportSlack,
};

post({ type: 'ready', version: 1 });
