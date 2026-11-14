// Builds the reader bundle into Sources/ObviewerReaderKit/Resources/Reader.
//   node build.mjs          build
//   node build.mjs --check  build to a temp dir and fail if the committed bundle differs
//
// The output is committed so the Mac app builds without Node installed.

import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, '..');
const committedOut = join(repoRoot, 'Sources/ObviewerReaderKit/Resources/Reader');
const nodeModules = join(here, 'node_modules');
const check = process.argv.includes('--check');

const esbuildSpecifier = process.env.OBVIEWER_ESBUILD
  ? pathToFileURL(process.env.OBVIEWER_ESBUILD).href
  : 'esbuild';
const esbuild = await import(esbuildSpecifier).then((module) => module.default ?? module);

const outDir = check ? mkdtempSync(join(tmpdir(), 'obviewer-reader-')) : committedOut;
if (!check) rmSync(outDir, { recursive: true, force: true });
mkdirSync(join(outDir, 'katex/fonts'), { recursive: true });

await esbuild.build({
  entryPoints: [join(here, 'src/reader.js')],
  outfile: join(outDir, 'reader.js'),
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: ['safari16'],
  minify: true,
  legalComments: 'none',
  charset: 'utf8',
  nodePaths: [nodeModules],
  logLevel: 'warning',
});

// Quick Look: a DOM-free bundle evaluated with JavaScriptCore (no WebKit in the extension).
await esbuild.build({
  entryPoints: [join(here, 'src/quicklook.js')],
  outfile: join(outDir, 'quicklook.js'),
  bundle: true,
  format: 'iife',
  platform: 'neutral',
  mainFields: ['browser', 'module', 'main'],
  target: ['safari16'],
  minify: true,
  legalComments: 'none',
  charset: 'utf8',
  nodePaths: [nodeModules],
  logLevel: 'warning',
});

cpSync(join(here, 'static/reader.html'), join(outDir, 'reader.html'));
cpSync(join(here, 'static/reader.css'), join(outDir, 'reader.css'));
cpSync(join(nodeModules, 'mermaid/dist/mermaid.min.js'), join(outDir, 'mermaid.min.js'));

// KaTeX: stylesheet plus WOFF2 fonts only (WebKit always picks WOFF2 first).
const katexDist = join(nodeModules, 'katex/dist');
cpSync(join(katexDist, 'katex.min.css'), join(outDir, 'katex/katex.min.css'));
for (const font of readdirSync(join(katexDist, 'fonts'))) {
  if (font.endsWith('.woff2')) cpSync(join(katexDist, 'fonts', font), join(outDir, 'katex/fonts', font));
}

// Third-party notices for everything shipped in the bundle.
const bundled = ['markdown-it', 'markdown-it-footnote', 'mdurl', 'uc.micro', 'linkify-it', 'punycode.js', 'entities', 'highlight.js', 'katex', 'dompurify', 'mermaid'];
let notices = 'Third-party software bundled in Obviewer\'s reader.\n';
for (const name of bundled) {
  const dir = join(nodeModules, name);
  if (!existsSync(dir)) continue;
  const pkg = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'));
  const licenseFile = readdirSync(dir).find((file) => /^licen[cs]e/i.test(file));
  notices += `\n\n=== ${name} ${pkg.version} (${pkg.license ?? 'see below'}) ===\n`;
  if (licenseFile) notices += readFileSync(join(dir, licenseFile), 'utf8').trim();
}
writeFileSync(join(outDir, 'THIRD_PARTY_NOTICES.txt'), `${notices}\n`);

// Manifest with hashes so Swift tests and CI can confirm the bundle is intact.
const files = listFiles(outDir).filter((file) => file !== 'manifest.json');
const manifest = {
  generatedBy: 'Renderer/build.mjs',
  versions: Object.fromEntries(['markdown-it', 'mermaid', 'katex', 'highlight.js', 'dompurify'].map((name) => [
    name,
    JSON.parse(readFileSync(join(nodeModules, name, 'package.json'), 'utf8')).version,
  ])),
  files: Object.fromEntries(files.map((file) => [file, sha256(join(outDir, file))])),
};
writeFileSync(join(outDir, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);

if (check) {
  const committedManifest = join(committedOut, 'manifest.json');
  const stale = !existsSync(committedManifest) || readFileSync(committedManifest, 'utf8') !== readFileSync(join(outDir, 'manifest.json'), 'utf8');
  rmSync(outDir, { recursive: true, force: true });
  if (stale) {
    console.error('The committed reader bundle is out of date. Run `npm run build` in Renderer/ and commit the result.');
    process.exit(1);
  }
  console.log('Reader bundle is up to date.');
} else {
  const total = files.reduce((sum, file) => sum + statSync(join(outDir, file)).size, 0);
  console.log(`Built reader bundle: ${files.length} files, ${(total / 1024 / 1024).toFixed(2)} MB -> ${relative(repoRoot, outDir)}`);
}

function listFiles(dir, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    return entry.isDirectory() ? listFiles(join(dir, entry.name), rel) : [rel];
  }).sort();
}

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}
