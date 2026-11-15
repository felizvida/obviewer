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

// Security floor for KaTeX: versions before 0.18.2 can treat inherited (polluted)
// Object.prototype properties such as `trust` as options (GHSA-238p-pmpm-9mq7).
// Every installed copy must be at or above the floor, including any nested under
// other packages, or the build stops.
const KATEX_FLOOR = [0, 18, 2];
function installedCopies(name, dir = nodeModules, found = []) {
  if (!existsSync(dir)) return found;
  for (const entry of readdirSync(dir)) {
    if (entry.startsWith('.')) continue;
    const path = join(dir, entry);
    if (entry.startsWith('@')) { installedCopies(name, path, found); continue; }
    if (entry === name && existsSync(join(path, 'package.json'))) {
      found.push({ path, version: JSON.parse(readFileSync(join(path, 'package.json'), 'utf8')).version });
    }
    installedCopies(name, join(path, 'node_modules'), found);
  }
  return found;
}
const katexCopies = installedCopies('katex');
const belowFloor = katexCopies.filter(({ version }) => {
  const parts = version.split(/[.-]/).map(Number);
  for (let i = 0; i < 3; i += 1) if (parts[i] !== KATEX_FLOOR[i]) return parts[i] < KATEX_FLOOR[i];
  return false;
});
if (katexCopies.length === 0 || belowFloor.length > 0) {
  console.error(`KaTeX below ${KATEX_FLOOR.join('.')} is installed: ${belowFloor.map((c) => `${c.version} at ${relative(here, c.path)}`).join(', ') || 'none found'}. Run npm ci.`);
  process.exit(1);
}

const outDir = check ? mkdtempSync(join(tmpdir(), 'obviewer-reader-')) : committedOut;
if (!check) rmSync(outDir, { recursive: true, force: true });
mkdirSync(join(outDir, 'katex/fonts'), { recursive: true });

// Every input file of every bundle, so the notices list exactly what ships.
const bundledInputs = new Set();
const collectInputs = (result) => { for (const file of Object.keys(result.metafile.inputs)) bundledInputs.add(file); return result; };

// Mermaid 12 ships the ELK layout engine (elkjs, licensed EPL-2.0 OR GPL-3.0-or-later,
// about 1.6 MB). The reader always lays diagrams out with dagre, so ELK is replaced by
// a stub: a diagram that asks for an ELK layout shows an error instead.
const withoutELK = {
  name: 'without-elk',
  setup(build) {
    build.onResolve({ filter: /^elkjs(\/|$)/ }, () => ({ path: 'elkjs-stub', namespace: 'obviewer-stub' }));
    build.onLoad({ filter: /.*/, namespace: 'obviewer-stub' }, () => ({
      contents: "export default class ELK { constructor() { throw new Error('The ELK layout is not included in Obviewer. Remove the layout setting to use the default.'); } }",
      loader: 'js',
    }));
  },
};

collectInputs(await esbuild.build({
  entryPoints: [join(here, 'src/reader.js')],
  outfile: join(outDir, 'reader.js'),
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: ['safari18'],
  minify: true,
  legalComments: 'none',
  charset: 'utf8',
  nodePaths: [nodeModules],
  logLevel: 'warning',
  metafile: true,
}));

// Quick Look: a DOM-free bundle evaluated with JavaScriptCore (no WebKit in the extension).
collectInputs(await esbuild.build({
  entryPoints: [join(here, 'src/quicklook.js')],
  outfile: join(outDir, 'quicklook.js'),
  bundle: true,
  format: 'iife',
  platform: 'neutral',
  mainFields: ['browser', 'module', 'main'],
  target: ['safari18'],
  minify: true,
  legalComments: 'none',
  charset: 'utf8',
  nodePaths: [nodeModules],
  logLevel: 'warning',
  metafile: true,
}));

cpSync(join(here, 'static/reader.html'), join(outDir, 'reader.html'));
cpSync(join(here, 'static/reader.css'), join(outDir, 'reader.css'));
// Mermaid is bundled here from its ES module build rather than copied from
// mermaid/dist/mermaid.min.js, which embeds its own (older, vulnerable) KaTeX. Bundling
// resolves Mermaid's KaTeX import to the single, patched copy checked above.
collectInputs(await esbuild.build({
  stdin: {
    contents: "import mermaid from 'mermaid';\nglobalThis.mermaid = mermaid;\n",
    resolveDir: here,
    sourcefile: 'mermaid-entry.js',
  },
  outfile: join(outDir, 'mermaid.min.js'),
  plugins: [withoutELK],
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: ['safari18'],
  minify: true,
  legalComments: 'none',
  charset: 'utf8',
  nodePaths: [nodeModules],
  logLevel: 'warning',
  metafile: true,
}));

// KaTeX: stylesheet plus WOFF2 fonts only (WebKit always picks WOFF2 first).
const katexDist = join(nodeModules, 'katex/dist');
cpSync(join(katexDist, 'katex.min.css'), join(outDir, 'katex/katex.min.css'));
for (const font of readdirSync(join(katexDist, 'fonts'))) {
  if (font.endsWith('.woff2')) cpSync(join(katexDist, 'fonts', font), join(outDir, 'katex/fonts', font));
}

// Third-party notices for everything shipped in the bundle: every npm package with a
// file in any bundle, plus KaTeX (its stylesheet and fonts are copied as files).
const packageOf = (file) => {
  const parts = file.split('node_modules/');
  if (parts.length < 2) return null;
  const rest = parts[parts.length - 1].split('/');
  return { name: rest[0].startsWith('@') ? `${rest[0]}/${rest[1]}` : rest[0], dir: join(here, parts.slice(0, -1).join('node_modules/'), 'node_modules') };
};
const shipped = new Map([['katex', join(nodeModules, 'katex')]]);
for (const file of bundledInputs) {
  const pkg = packageOf(file);
  if (pkg && !shipped.has(pkg.name)) shipped.set(pkg.name, join(pkg.dir, pkg.name));
}
if ([...shipped.keys()].some((name) => name === 'elkjs')) {
  console.error('elkjs ended up in a bundle; the ELK stub is not working.');
  process.exit(1);
}
let notices = 'Third-party software bundled in Obviewer\'s reader.\n';
for (const name of [...shipped.keys()].sort()) {
  const dir = shipped.get(name);
  const pkg = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'));
  // Licence texts and any NOTICE file (Apache-2.0 requires passing NOTICE files on).
  const licenseFiles = readdirSync(dir).filter((file) => /^(licen[cs]e|copying|notice)/i.test(file)).sort();
  const declared = typeof pkg.license === 'string' ? pkg.license : null;
  if (licenseFiles.length === 0 && !declared) {
    console.error(`No license information found for bundled package ${name}.`);
    process.exit(1);
  }
  notices += `\n\n=== ${name} ${pkg.version} (${declared ?? 'see below'}) ===\n`;
  notices += licenseFiles.length
    ? licenseFiles.map((file) => readFileSync(join(dir, file), 'utf8').trim()).join('\n\n')
    : `Licensed under ${declared}.`;
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
