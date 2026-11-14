// Behavior tests for scripts/release_common.sh, run against mock tools.
//
// These gates decide what ships, so they are tested for both directions:
// a good bundle must pass (no false failures, e.g. from SIGPIPE in pipelines),
// and every bad bundle must fail even when the helper is called from a
// conditional context where bash disables errexit.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const releaseCommon = join(repoRoot, 'scripts', 'release_common.sh');

const APP_ENTITLEMENTS = ['com.apple.security.app-sandbox', 'com.apple.security.files.user-selected.read-only', 'com.apple.security.print', 'com.apple.security.network.client'];
const EXT_ENTITLEMENTS = ['com.apple.security.app-sandbox', 'com.apple.security.files.user-selected.read-only'];

const plist = (keys) => `<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>${keys.map((k) => `<key>${k}</key><true/>`).join('')}</dict></plist>\n`;

function setup(options = {}) {
  // The prefix holds option-like words and a space on purpose, so any helper or mock
  // that matches on paths or forgets to quote them fails every run, not at random.
  const root = mkdtempSync(join(tmpdir(), 'release common -dv --verify --entitlements -mountpoint Print -'));
  const bin = join(root, 'bin');
  mkdirSync(bin);
  const app = join(root, 'content', 'Obviewer.app');
  mkdirSync(join(app, 'Contents', 'MacOS'), { recursive: true });
  mkdirSync(join(app, 'Contents', 'PlugIns', 'ObviewerQuickLook.appex', 'Contents', 'MacOS'), { recursive: true });
  writeFileSync(join(app, 'Contents', 'MacOS', 'Obviewer'), 'binary');
  writeFileSync(join(app, 'Contents', 'PlugIns', 'ObviewerQuickLook.appex', 'Contents', 'MacOS', 'ObviewerQuickLook'), 'binary');
  mkdirSync(join(app, 'Contents', 'Resources'), { recursive: true });
  writeFileSync(join(root, 'source.icns'), 'icns committed icon bytes');
  if (options.icon !== 'missing' && !options.iconLink) {
    writeFileSync(join(app, 'Contents', 'Resources', 'AppIcon.icns'), options.icon === 'different' ? 'icns some other bytes' : 'icns committed icon bytes');
  }
  if (options.assetsCar) writeFileSync(join(app, 'Contents', 'Resources', 'Assets.car'), 'BOMStore');
  if (options.extensionAssetsCar) {
    mkdirSync(join(app, 'Contents', 'PlugIns', 'ObviewerQuickLook.appex', 'Contents', 'Resources'), { recursive: true });
    writeFileSync(join(app, 'Contents', 'PlugIns', 'ObviewerQuickLook.appex', 'Contents', 'Resources', 'Assets.car'), 'BOMStore');
  }
  if (options.iconLink) symlinkSync(join(root, 'source.icns'), join(app, 'Contents', 'Resources', 'AppIcon.icns'));
  if (options.framework) mkdirSync(join(app, 'Contents', 'Frameworks', 'Bad.framework'), { recursive: true });
  if (options.applicationsLink !== false) symlinkSync('/Applications', join(root, 'content', 'Applications'));
  if (options.readme !== false) writeFileSync(join(root, 'content', 'Read Me First - How to Install.md'), 'guide');
  if (options.fseventsd) {
    mkdirSync(join(root, 'content', '.fseventsd'));
    for (const [name, data] of Object.entries(options.fseventsd)) writeFileSync(join(root, 'content', '.fseventsd', name), data);
  }
  for (const [name, data] of Object.entries(options.extraRootFiles ?? {})) writeFileSync(join(root, 'content', name), data);
  writeFileSync(join(root, 'app.plist'), plist(options.appEntitlements ?? APP_ENTITLEMENTS));
  writeFileSync(join(root, 'ext.plist'), plist(options.extEntitlements ?? EXT_ENTITLEMENTS));

  const tool = (name, body) => {
    const path = join(bin, name);
    writeFileSync(path, `#!/usr/bin/env bash\n${body}\n`);
    chmodSync(path, 0o755);
    return path;
  };

  // codesign: dispatch on the option arguments only, never on "$*": temp paths are random
  // and once contained "-dv", which sent an entitlements request down the -dv branch.
  tool('codesign', `
target="\${@: -1}"
case "$1 $2" in
  --verify*) [ "\${MOCK_VERIFY_FAIL:-0}" = 1 ] && { echo "simulated strict signature failure" >&2; exit 1; }; exit 0 ;;
  "-dv "*)
    [ "\${MOCK_DV_FAIL:-0}" = 1 ] && exit 1
    echo "Executable=$target" >&2
    if [ "\${MOCK_NO_RUNTIME:-0}" = 1 ]; then echo "CodeDirectory v=20500 size=1 flags=0x2(adhoc) hashes=1" >&2
    else echo "CodeDirectory v=20500 size=1 flags=0x10002(adhoc,runtime) hashes=1" >&2; fi
    # Long trailing output: a 'grep -q' pipeline would SIGPIPE here.
    for i in $(seq 1 20000); do echo "Hash line $i 0123456789abcdef0123456789abcdef" >&2; done
    exit 0 ;;
  "-d --entitlements")
    case "$target" in */ObviewerQuickLook.appex) cat "${join(root, 'ext.plist')}" ;; *) cat "${join(root, 'app.plist')}" ;; esac
    exit 0 ;;
esac
echo "mock codesign: unexpected arguments: $*" >&2
exit 2`);
  tool('plutil', '[ "${MOCK_PLIST_INVALID:-0}" = 1 ] && exit 1; exit 0');
  // PlistBuddy: "Print" lists keys like the real tool; "Print :key" prints a value.
  tool('PlistBuddy', `
file="\${@: -1}"
case "$2" in
  Print)
    echo "Dict {"
    grep -o '<key>[^<]*</key>' "$file" | sed -e 's#<key>##' -e 's#</key>##' -e 's#^#    #' -e 's#$# = true#'
    echo "}" ;;
  "Print :"*)
    key="\${2#Print :}"
    grep -q "<key>$key</key>" "$file" && { echo true; exit 0; }
    echo "Print: Entry, \\":$key\\", Does Not Exist" >&2; exit 1 ;;
esac`);
  tool('otool', `
[ "\${MOCK_OTOOL_FAIL:-0}" = 1 ] && { echo "otool: broken" >&2; exit 1; }
echo "$2 (architecture x86_64):"
echo "	/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit (compatibility version 45.0.0)"
echo "	/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)"
[ "\${MOCK_OTOOL_RPATH:-0}" = 1 ] && echo "	@rpath/Internal.framework/Versions/A/Internal (compatibility version 1.0.0)"
echo "$2 (architecture arm64):"
echo "	/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)"
exit 0`);
  tool('xattr', `
[ "\${MOCK_XATTR_FAIL:-0}" = 1 ] && exit 1
echo "$2/Contents/MacOS/Obviewer: com.apple.provenance:"
[ "\${MOCK_FINDERINFO:-0}" = 1 ] && echo "$2/Contents/Info.plist: com.apple.FinderInfo: 62726F6B"
exit 0`);
  // cmp: compares two files like 'cmp -s' (0 same, 1 different, 2 trouble).
  tool('cmp', `
[ "$1 $2" = "-s --" ] || { echo "mock cmp: expected -s --" >&2; exit 2; }
[ "\${MOCK_CMP_FAIL:-0}" = 1 ] && exit 2
[ -f "$3" ] && [ -f "$4" ] || exit 2
[ "$(cat "$3")" = "$(cat "$4")" ] && exit 0
exit 1`);
  // git: only 'diff --quiet HEAD -- App/AppIcon.icns' is expected; MOCK_GIT_DIFF sets its exit.
  tool('git', `
case "$*" in
  *"diff --quiet HEAD -- App/AppIcon.icns") exit "\${MOCK_GIT_DIFF:-0}" ;;
esac
echo "mock git: unexpected arguments: $*" >&2
exit 2`);
  // mdutil: records its arguments; a unit test must never reach the real Spotlight service.
  tool('mdutil', `echo "$*" >> "${join(root, 'mdutil.log')}"; exit 0`);
  // hdiutil: "attach" populates the mount point from the content folder.
  tool('hdiutil', `
case "$1" in
  attach) [ "\${MOCK_ATTACH_FAIL:-0}" = 1 ] && exit 1
    mp=""; while [ $# -gt 0 ]; do [ "$1" = -mountpoint ] && mp="$2"; shift; done
    cp -R "${join(root, 'content')}/." "$mp/" ;;
  detach) rm -rf "$2"/* "$2"/.[!.]* 2>/dev/null; exit 0 ;;
esac
exit 0`);

  return { root, bin, app, dmg: join(root, 'fake.dmg') };
}

function run(env, script) {
  const result = spawnSync('bash', ['-c', `set -euo pipefail\nsource "${releaseCommon}"\n${script}`], {
    env: {
      ...process.env,
      PATH: `${env.bin}:${process.env.PATH}`,
      CODESIGN: join(env.bin, 'codesign'),
      OTOOL: join(env.bin, 'otool'),
      XATTR: join(env.bin, 'xattr'),
      PLISTBUDDY: join(env.bin, 'PlistBuddy'),
      PLUTIL: join(env.bin, 'plutil'),
      HDIUTIL: join(env.bin, 'hdiutil'),
      MDUTIL: join(env.bin, 'mdutil'),
      CMP: join(env.bin, 'cmp'),
      GIT: join(env.bin, 'git'),
      OBVIEWER_SOURCE_ICON: join(env.root, 'source.icns'),
      OBVIEWER_CODE_SIGN_IDENTITY: '-',
      TMPDIR: env.root,
      ...(env.extra ?? {}),
    },
    encoding: 'utf8',
  });
  return result;
}

// Call the helpers the way the bug hid failures: inside conditionals, where errexit is off.
const conditionalApp = (env) => run(env, `if verify_signed_app_bundle "${env.app}"; then echo RESULT=pass; else echo RESULT=fail; fi`);
const conditionalDMG = (env) => run(env, `verify_dmg "${env.dmg}" && echo RESULT=pass || echo RESULT=fail`);
const result = (r) => (/RESULT=(\w+)/.exec(r.stdout) ?? [])[1];

function withEnv(options, extra, work) {
  const env = setup(options);
  env.extra = extra;
  try {
    return work(env);
  } finally {
    rmSync(env.root, { recursive: true, force: true });
  }
}

test('a correct bundle and DMG pass, despite long codesign output (no SIGPIPE false failure)', () => {
  withEnv({}, {}, (env) => {
    const app = conditionalApp(env);
    assert.equal(result(app), 'pass', app.stderr.slice(-500));
    const dmg = conditionalDMG(env);
    assert.equal(result(dmg), 'pass', dmg.stderr.slice(-500));
    assert.match(dmg.stdout, /Verified mounted DMG/);
  });
});

test('a failed strict signature fails the bundle and the DMG, even inside conditionals', () => {
  withEnv({}, { MOCK_VERIFY_FAIL: '1' }, (env) => {
    const app = conditionalApp(env);
    assert.equal(result(app), 'fail');
    assert.match(app.stderr, /Strict code signature verification failed/);
    const dmg = conditionalDMG(env);
    assert.equal(result(dmg), 'fail');
    assert.match(dmg.stderr, /Strict code signature verification failed/);
    assert.doesNotMatch(dmg.stdout, /Verified mounted DMG/);
  });
});

// Each case must fail for its own reason (asserted on the message), not by accident.
const failures = [
  ['missing hardened runtime', {}, { MOCK_NO_RUNTIME: '1' }, /hardened runtime flag is missing/],
  ['codesign -dv tool failure', {}, { MOCK_DV_FAIL: '1' }, /codesign -dv failed/],
  ['debugger entitlement', { appEntitlements: [...APP_ENTITLEMENTS, 'com.apple.security.get-task-allow'] }, {}, /Forbidden entitlement com\.apple\.security\.get-task-allow/],
  ['library-validation exception', { appEntitlements: [...APP_ENTITLEMENTS, 'com.apple.security.cs.disable-library-validation'] }, {}, /Forbidden entitlement com\.apple\.security\.cs\.disable-library-validation/],
  ['unknown extra entitlement', { appEntitlements: [...APP_ENTITLEMENTS, 'com.example.unreviewed'] }, {}, /com\.example\.unreviewed is not allowed/],
  ['read-write files', { appEntitlements: [...APP_ENTITLEMENTS, 'com.apple.security.files.user-selected.read-write'] }, {}, /Forbidden entitlement com\.apple\.security\.files\.user-selected\.read-write/],
  ['network on the extension', { extEntitlements: [...EXT_ENTITLEMENTS, 'com.apple.security.network.client'] }, {}, /network\.client is not allowed in the signed Quick Look extension/],
  ['missing sandbox', { appEntitlements: APP_ENTITLEMENTS.slice(1) }, {}, /App Sandbox \(app\) entitlement is missing/],
  ['invalid entitlements plist', {}, { MOCK_PLIST_INVALID: '1' }, /not a valid property list/],
  ['non-system library dependency', {}, { MOCK_OTOOL_RPATH: '1' }, /non-system library: @rpath/],
  ['otool failure', {}, { MOCK_OTOOL_FAIL: '1' }, /otool failed/],
  ['bundled framework', { framework: true }, {}, /ships frameworks or dylibs/],
  ['Finder information', {}, { MOCK_FINDERINFO: '1' }, /Finder information or resource forks/],
  ['xattr failure', {}, { MOCK_XATTR_FAIL: '1' }, /Could not list extended attributes/],
  ['compiled asset catalog shipped', { assetsCar: true }, {}, /Compiled asset catalog found/],
  ['asset catalog inside the extension', { extensionAssetsCar: true }, {}, /Compiled asset catalog found[\s\S]*ObviewerQuickLook\.appex/],
  ['app icon is a link', { iconLink: true }, {}, /App icon not found .*or it is a link/],
  ['app icon missing', { icon: 'missing' }, {}, /App icon not found/],
  ['app icon differs from the committed file', { icon: 'different' }, {}, /differs from the committed/],
  ['icon comparison tool failure', {}, { MOCK_CMP_FAIL: '1' }, /Could not compare .*cmp exit 2/],
  ['committed icon missing', {}, { OBVIEWER_SOURCE_ICON: '/nonexistent/AppIcon.icns' }, /Source icon not found/],
  ['default source icon: uncommitted icon edits', {}, { OBVIEWER_SOURCE_ICON: '', MOCK_GIT_DIFF: '1' }, /uncommitted changes/],
  ['default source icon: git failure', {}, { OBVIEWER_SOURCE_ICON: '', MOCK_GIT_DIFF: '128' }, /Could not confirm App\/AppIcon\.icns matches HEAD/],
  // With the default path (no test hook), the real repository icon is the reference;
  // the fake bundle's icon differs from it, which proves the default path is used.
  ['default source icon: shipped icon differs from the repository icon', {}, { OBVIEWER_SOURCE_ICON: '' }, /differs from the committed .*\/App\/AppIcon\.icns/],
];

for (const [name, options, extra, reason] of failures) {
  test(`fails closed: ${name}`, () => {
    withEnv(options, extra, (env) => {
      const app = conditionalApp(env);
      assert.equal(result(app), 'fail', `bundle should fail: ${name}`);
      assert.match(app.stderr, reason);
      const dmg = conditionalDMG(env);
      assert.equal(result(dmg), 'fail', `DMG should fail: ${name}`);
      assert.match(dmg.stderr, reason);
    });
  });
}

test('DMG layout problems fail; a failed mount fails', () => {
  const check = (options, extra, reason) => withEnv(options, extra, (env) => {
    const dmg = conditionalDMG(env);
    assert.equal(result(dmg), 'fail');
    assert.match(dmg.stderr, reason);
  });
  check({ applicationsLink: false }, {}, /missing its Applications link/);
  check({ readme: false }, {}, /missing its install guide/);
  check({}, { MOCK_ATTACH_FAIL: '1' }, /Could not mount/);
});

test('called directly under set -e, a failing helper stops the script', () => {
  withEnv({}, { MOCK_VERIFY_FAIL: '1' }, (env) => {
    const r = run(env, `verify_signed_app_bundle "${env.app}"\necho SHOULD_NOT_PRINT`);
    assert.notEqual(r.status, 0);
    assert.doesNotMatch(r.stdout, /SHOULD_NOT_PRINT/);
  });
});

test('the image root is an allow-list: OS metadata and stray files fail, markers pass', () => {
  const pass = (options) => withEnv(options, {}, (env) => {
    const dmg = conditionalDMG(env);
    assert.equal(result(dmg), 'pass', dmg.stderr.slice(-400));
  });
  const fail = (options, reason) => withEnv(options, {}, (env) => {
    const dmg = conditionalDMG(env);
    assert.equal(result(dmg), 'fail');
    assert.match(dmg.stderr, reason);
  });
  pass({ fseventsd: { no_log: '' }, extraRootFiles: { '.metadata_never_index': '' } });
  pass({ fseventsd: {} });
  fail({ fseventsd: { no_log: '', '000000004cce95e9': 'journal' } }, /file-event logs/);
  fail({ extraRootFiles: { '.DS_Store': 'x' } }, /Unexpected entry in the release image: \.DS_Store/);
  fail({ extraRootFiles: { 'notes.txt': 'x' } }, /Unexpected entry in the release image: notes\.txt/);
});

test('staging volume cleanup removes OS metadata but keeps the markers', () => {
  withEnv({}, {}, (env) => {
    const volume = join(env.root, 'content');
    mkdirSync(join(volume, '.fseventsd'));
    writeFileSync(join(volume, '.fseventsd', 'no_log'), '');
    writeFileSync(join(volume, '.fseventsd', '0000000012345678'), 'journal');
    mkdirSync(join(volume, '.Spotlight-V100'));
    writeFileSync(join(volume, '.metadata_never_index'), '');
    const r = run(env, `clean_staging_volume "${volume}" && verify_volume_layout "${volume}" && echo RESULT=pass || echo RESULT=fail`);
    assert.equal(result(r), 'pass', r.stderr);
  });
});

test('prepare_staging_volume writes the no-index and no-log markers', () => {
  withEnv({}, {}, (env) => {
    const volume = join(env.root, 'fresh');
    mkdirSync(volume);
    const r = run(env, `prepare_staging_volume "${volume}" && ls -A "${volume}" "${volume}/.fseventsd"`);
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /\.metadata_never_index/);
    assert.match(r.stdout, /no_log/);
    // Indexing is switched off only for the staging volume, via the injected tool.
    assert.equal(readFileSync(join(env.root, 'mdutil.log'), 'utf8'), `-i off ${volume}\n`);
  });
});
