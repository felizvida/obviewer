# Modernization Plan

This document is the operational roadmap for taking Obviewer from a strong prototype to a modern shipping macOS product.

It is intentionally concrete. The goal is not just to describe desirable future qualities, but to sequence the work in a way that preserves the read-only guarantee while increasing product quality.

## Modernization Thesis

Obviewer should modernize as a macOS-first reader, not as a generic note platform.

That means:

- strengthen the trust boundary first
- deepen content fidelity second
- improve scale and responsiveness third
- refine graph, media, accessibility, and visual polish after the foundation is solid

## Baseline As Of March 23, 2026

The project already has:

- a split core/macOS architecture
- note parsing, lookup, search, and graph derivation
- live vault watching and incremental reload foundations
- persistent warm-start snapshot caching for unchanged parsed notes and attachment metadata
- reader and graph workspaces
- synthetic vault tooling
- large-vault benchmark tooling and index diagnostics
- smoke-profile benchmark budget enforcement in CI
- integration-profile benchmark reporting in CI
- benchmark summaries surfaced directly in CI job output
- documentation screenshot tooling
- local and CI verification
- tag-driven source releases

The project still lacks:

- signed/notarized end-user distribution
- full markdown and Obsidian fidelity
- deeper incremental indexing and persistent large-vault state beyond the current snapshot cache
- accessibility hardening
- UI regression coverage
- operational polish for real public distribution

## Guardrails

Every modernization step should honor these rules:

1. do not weaken the read-only boundary
2. do not add broad filesystem access without an explicit design decision
3. do not let feature breadth outrun rendering fidelity
4. do not let visual polish drift into generic utility-app design
5. keep the repo maintainable by a new contributor with the docs alone

## Phase 1: Production Distribution And Trust Boundary

Primary outcome:

- a signed, notarized, easy-to-install macOS build that preserves the sandboxed read-only story end to end

Work items:

- finish the XcodeGen-generated shipping app target path
- wire Developer ID signing and notarization into release automation
- publish a notarized GitHub `.dmg`
- document the exact distribution workflow and rollback path
- add first-run onboarding content that makes the read-only model legible to users
- verify entitlement presence in release validation, not just debug builds

Exit criteria:

- GitHub releases include a signed/notarized downloadable artifact
- the artifact opens cleanly on a fresh Mac
- the runtime entitlements remain read-only
- onboarding makes vault selection and trust posture clear

## Phase 2: Content Fidelity Architecture

Primary outcome:

- the app renders real Obsidian vault content far more faithfully without turning the codebase into a UI tangle

Work items:

- formalize the render pipeline so parser output is easier to extend safely
- decide whether to continue evolving the in-house parser or adopt a stronger markdown engine
- add the next missing structural constructs beyond the new footnote support
- deepen frontmatter handling beyond the current scalar and array extraction layer
- improve advanced inline formatting combinations
- add predictable fallback rendering for unsupported constructs

Exit criteria:

- representative real-world notes render acceptably without obvious structural loss
- unsupported content degrades gracefully instead of disappearing
- parser changes are covered by focused regression tests

## Phase 3: Scale, Indexing, And Live Refresh

Primary outcome:

- the app feels responsive on larger vaults and updates without full manual reload cycles

Work items:

- deepen the new watcher flow into broader change coverage and recovery behavior
- introduce more granular incremental indexing and caching beyond the current path-aware selective reloads
- add lightweight caching where it reduces repeated parse/index cost
- deepen the new benchmark tooling into tracked startup, reload, and graph baselines on large fixture vaults
- improve search ranking and large-result navigation

Exit criteria:

- vault reloads are perceptibly faster on large fixture vaults
- file changes can refresh the UI without a full reopen flow
- the app exposes enough profiling signals to reason about regressions and future budgets
- at least one benchmark profile is enforced automatically in CI

## Phase 4: Reader, Graph, And Media Polish

Primary outcome:

- the app feels intentionally designed across reader, graph, and attachment workflows

Work items:

- improve graph filtering, layout stability, and interaction affordances
- add richer attachment handling for PDFs and other common media
- strengthen image presentation and gallery-like flows where appropriate
- add quick switcher and more fluid note-to-note navigation
- tighten visual consistency across reader, graph, search, and loading states

Exit criteria:

- graph view is helpful rather than merely present
- attachment handling covers the most common non-image note companions
- navigation feels fast and unsurprising in larger vaults

## Phase 5: Accessibility, Quality, And Operations

Primary outcome:

- the app is safer to evolve and more respectful of real users

Work items:

- perform an accessibility pass with VoiceOver and keyboard navigation
- add UI snapshot or visual regression coverage for major reader surfaces
- add performance benchmarks for representative fixture vaults
- decide on crash reporting and privacy-safe diagnostics strategy
- add issue templates or labels aligned to parser, rendering, graph, and distribution workstreams

Exit criteria:

- keyboard and VoiceOver behavior are no longer unknowns
- major UI regressions are easier to catch automatically
- maintainers have observable signals for performance and release quality

## Suggested 90-Day Sequence

If one maintainer is driving the next serious push, this is the recommended order:

### Days 1-30

- complete signed/notarized distribution
- write the release/distribution docs
- validate the install path on a clean machine

### Days 31-60

- choose the parser/renderer evolution strategy
- land the first fidelity wave: ordered lists, task lists, nested lists, structured frontmatter
- add regression fixtures that cover those constructs

### Days 61-90

- deepen the new file-watching, selective reload, and warm-start cache foundations into broader indexed persistence
- improve graph interaction and layout quality
- begin accessibility and UI-regression work

## Success Metrics

Modernization is working if:

- a non-technical user can install the app without Xcode
- a real Obsidian vault renders with fewer obvious gaps
- larger vaults feel faster and more transparent during indexing
- graph and media features feel intentional rather than experimental
- maintainers can change the app without fear of invisible regressions

## Work That Should Wait

Avoid these until the earlier phases are complete:

- cross-platform ambitions
- editing features
- sync or collaboration
- plugin systems
- broad permissions or convenience shortcuts that weaken the safety story

## How To Use This Plan

When starting work:

1. choose the phase you are working in
2. make sure the change supports the stated exit criteria
3. add or update docs as soon as a milestone meaningfully changes
4. update `STATUS.md` when a milestone moves from partial to complete
