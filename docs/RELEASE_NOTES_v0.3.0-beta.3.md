<!-- release-channel: prerelease -->
# Obviewer v0.3.0-beta.3 (pre-release)

A security and platform update: a patched KaTeX (the math renderer), Mermaid 12.3 for diagrams, and **macOS 26 or later only**. This build is for Apple silicon Macs.

This is a **pre-release**. It was verified on one Mac (Apple silicon, macOS 26). Installing on other Macs hasn't been verified yet. See [STATUS](https://github.com/felizvida/obviewer/blob/main/docs/STATUS.md) for exactly what was checked and what wasn't.

## Why update

- **Security.** beta.1 and beta.2 ship KaTeX 0.16.47, both in the reader and inside Mermaid. That version is affected by [GHSA-238p-pmpm-9mq7](https://github.com/advisories/GHSA-238p-pmpm-9mq7), a low-severity issue: KaTeX before 0.18.2 could treat polluted `Object.prototype` properties, such as `trust`, as options. This release uses **KaTeX 0.19.1** everywhere, and `npm audit` reports no known vulnerabilities. Exploiting the issue in the earlier betas needed prior prototype pollution, and their reader already passed `trust: false` and sanitized KaTeX's output, but there's no reason to keep it.
- **Diagrams.** **Mermaid 12.3**, keeping the classic layout and look. Mermaid's optional ELK layout engine isn't included; a diagram that asks for ELK layout shows an error.

## Install

Download `Obviewer-v0.3.0-beta.3-macOS-adhoc.dmg` and follow [INSTALL](https://github.com/felizvida/obviewer/blob/main/docs/INSTALL.md). The app is **ad-hoc signed and not notarized by Apple**, so macOS asks you to approve it in System Settings › Privacy & Security. Managed Macs may not allow it. You can compare the DMG against the published SHA-256 checksum.

**The requirements changed:** macOS 26 or later, on Apple silicon. Earlier betas declared macOS 14 but were only ever run on macOS 26.

If you're updating from an earlier beta, macOS may ask again to approve the app and to let it access its own data, and it may forget folder access. Reopen your vault with ⌘O.

## Other changes

- The app's list of third-party licences is now generated from everything the reader bundle actually contains.

## Known bugs

- **Math inside diagrams is drawn off-centre.** A formula in a flowchart node sits against the node's top edge, and a formula in a sequence-diagram participant name appears near the box's top left. This is how Safari's engine paints KaTeX inside diagrams: the label is measured and placed correctly, but drawn offset. The rest of each diagram, and all math outside diagrams, are unaffected. (Math in sequence-diagram participant names was blank in Mermaid 12.3; this release makes it appear.)

## Known limitations

As in beta.2:

- Slack flattens pasted formatting.
- The print dialog's "Save as PDF" can't work in a read-only app; use ⌥⌘P instead.
- The Quick Look preview is static.
- Remote images never load, and plugin queries aren't run.

## Checks for this release

- **Automated:**
  - the Swift tests (133) and renderer tests (114) on macOS 26;
  - a renderer bundle reproducibility check;
  - a build gate that refuses any KaTeX older than 0.18.2;
  - entitlement, architecture and icon-payload gates;
  - the publication check on the source tree, the notes, the history and every uploaded file, with the DMG mounted.
- **Manual,** on the maintainer's Mac (macOS 26):
  - the reader with math, diagrams (flowchart, sequence, class, state, ER), dark mode, Open as PDF and the hostile-content fixture;
  - a Release-build signature, entitlement and arm64 review.
- **Not verified for this build:**
  - Quick Look of this build (Finder kept using an older registered copy);
  - the Web Inspector console;
  - copying a note with a diagram;
  - the smallest Finder icon and the Dock icon;
  - VoiceOver speech;
  - a second Mac.

Full changes: [CHANGELOG](https://github.com/felizvida/obviewer/blob/main/CHANGELOG.md).
