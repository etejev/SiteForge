# Lane V12b verification — E2 one hashed runtime file and the complete asset manifest — 2026-11-26

Verifier: Code Forge lane V12b (owner tag `lane-V12b`), follow-up to lane V12 (static output), under
`_quick-scratch\review\VERIFY_BRIEF.md`. Every tree write went through `forge_io.edit(owner="lane-V12b")` or
`write_new`; `check([...])` returned `[]` after each edit and every changed region was read again against the
declarations it calls. `foreign_changes(30)` and `icloud_duplicates()` were `[]` before the first write (20:16),
at 20:31 and at the end. No Swift compiler or test run is available on Windows: nothing here is verified by
compilation. Schemas unchanged: document 27, persisted history 4, WebsiteMetadata 3; no new `CanonicalDocument` or
node key, no new command, no new Swift file.

## Scope

| Item | Decision | Modules | Files |
|---|---|---|---|
| E2 — one content-hashed runtime script file (plan row E2, re-assigned from lane E by the owner at 7:55 PM) | OD-042 (approved), ADR-0124 (new) | SF-1205 | `SiteForge/CanvasRendererCore.swift` (`StaticRuntimeBundle`, `LocalBuildProfileCompiler.compile`, `StaticOutputCachePolicy`), `Tests/SiteForgeTests/CanvasRendererTests.swift`, `Tests/SiteForgeTests/SupportSettingsTests.swift`, `Tests/Tooling/flow_runtime_browser.py`, `Tests/Tooling/test_flow_runtime_browser.py` |
| Lane V08 finding — `assets.manifest.txt` listed only images | OD-042 / OD-045, ADR-0124 | SF-1206-001 | `SiteForge/ProjectResources.swift` (`StaticAssetManifestEmitter`), the planner call in `CanvasRendererCore.swift`, `Tests/SiteForgeTests/ProjectResourceTests.swift` |
| ADR consistency | — | SF-1204, SF-1206 | ADR-0120 and ADR-0121 (update notes), ADR-0124 (new) |

Read before writing: lane V12's report, ADR-0120…0123, plan row E2, `docs/TESTING.md`, `.github/workflows/ci.yml`,
both Flow harness files, `SupportSettingsTests.swift` (readable since 7:55 PM; lines 52–131 and the
`FlowRuntimeBrowserFixtures` enum), the planner's script emission (`MultiPageStaticBuildPlanner.plan`, the
`script` tags and the four `files.append` sites), the four runtime sources (`ConnectedPageOutput.menuScript`,
`DecorativeEffectRuntime.javascript`, `MotionRuntime.javascript`, `EventGraphRuntime.javascript`), every consumer
of Static Release output (`StaticBuildCompiler.compile`, profile comparison, browser support, reference audit,
budgets, `BrowserPreview` / Export from Preview — both Development) and every test that names a runtime file
(TransformModelTests ×19, InsertionModelTests ×9, CanvasRendererTests ×2, LaunchExperienceTests ×1,
SupportSettingsTests ×1, SiteForgeLaunchTests ×1, `interaction_runtime_browser.py`). Lane V09 (lane C) had finished
(report 20:06) and its runtime emitter lines were not touched.

## Design (why Static Release only)

ADR-0120 established the split this follows: Development writes readable generated output, Static Release writes
the optimized form. The planner is therefore unchanged and still writes `siteforge-navigation.js`,
`siteforge-effects.js`, `siteforge-motion.js` and `siteforge-events.js`; Local Preview, Export from Preview,
Development builds, the interaction/motion browser harness and the ~40 planner-level assertions in other lanes'
tests (TransformModelTests, InsertionModelTests, LaunchExperienceTests, the UI test's `siteforge-navigation.js`
probe, which runs Preview) keep their exact bytes. Static Release (`LocalBuildProfileCompiler.compile`) runs
`StaticRuntimeBundle.bundle` first:

- the runtime files the site uses become one `siteforge-runtime.<sha256>.js` (fixed part order navigation,
  effects, motion, events; named by the SHA-256 of its bytes);
- each page's first generated runtime tag becomes
  `<script src="<prefix>siteforge-runtime.<sha256>.js" data-siteforge-runtime="<parts>" defer></script>` with the
  page's own folder prefix (language trees, collection item and list pages, nested routes — the planner's formula),
  its other runtime tags are removed, and the interaction state element stays in place;
- the bundle runs only the parts the page names (`document.currentScript`), so every page runs exactly the code it
  ran before, and runs each part in its own `try` (error reported with `reportError`, or rethrown asynchronously),
  so one failing part never stops another — the SF-1205 isolation invariant that separate files gave before;
- `manifest.txt` lists the bundle instead of the replaced files; the integrity manifest and the per-file report list
  it (kind `script`); `StaticOutputCachePolicy` marks it `immutable`.

Checked outside the app (Node, the four real runtime texts extracted from the Swift sources): the bundle parses, a
page naming no part runs nothing, a page naming `navigation` runs only the menu code, a throwing part is reported
and the next part still runs, and `'use strict'` inside a part still applies.

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/ProjectResources.swift`, `SiteForge/CanvasRendererCore.swift` | `StaticAssetManifestEmitter.emit`, planner call | `assets.manifest.txt` listed only images; exported fonts, video, audio and captions were missing (lane V08 out-of-area finding). | The emitter takes the planner's verified `fontPaths`/`mediaPaths` (defaulted parameters) and lists every exported asset in asset-identity order: images unchanged (`<id>\t<path>\t<w>x<h>`, SVG and posters included), fonts/media `<id>\t<path>\t<media type>`. Only exported files; no names. | SF-1206-001: the asset manifest covers every exported asset type, deterministically. |
| 2 | `Tests/SiteForgeTests/SupportSettingsTests.swift`, `Tests/Tooling/flow_runtime_browser.py` | `testFlowRuntimeActualBrowserDeformationFallbacksAndLifecycle`, `available()` | The only real-browser test of the Flow runtime ran Development output, so the output users publish (Static Release) was never exercised in a browser; the harness hard-coded `siteforge-effects.js`. | The test writes the Static Release site (and asserts one bundle containing the Flow runtime, no `siteforge-effects.js`, no unresolved reference); the harness accepts the Flow runtime from Development's file or a content-hashed bundle naming `effects` (`loads_effects_runtime`, unit-tested). | SF-1205-004/008: the shipped bundle is what the browser cases verify. |
| 3 | ADR-0120, ADR-0121 | update notes | ADR-0120 said every non-CSS Static Release file is unchanged; ADR-0121 said generated scripts are not hashed (E2 blocked). | "Update — lane V12b (ADR-0124)" sections. | Docs must match the code. |

## Features finished

| Item | Decision | What was built |
|---|---|---|
| E2 — one hashed runtime script file | OD-042, ADR-0124 | `StaticRuntimeBundle` (`parts`, `sourcePath`, `sourceTag`, `path(for:)`, `isBundlePath`, `bundleText`, `bundle`, `page`), Static Release bundling in `LocalBuildProfileCompiler.compile`, immutable cache policy, manifest/report listing, browser harness on Static Release output, unit + integration + performance tests. |
| Complete asset manifest | OD-042 / OD-045, ADR-0124 | `StaticAssetManifestEmitter.emit(assets:entries:fonts:fontPaths:media:mediaPaths:)` and the planner call; tests in the media and font export tests. |

## Requirement table

| Requirement | Status | Evidence / gap |
|---|---|---|
| SF-1205-001 authoritative state | Partial | The bundle is derived output, deterministic and versionless by design; there is no canonical bundle/module model because OD-042 approved generated runtime only (authored modules: proposed OD below). |
| SF-1205-002 create/modify, split routes | Partial | Routes are split per page: each page names and runs only its parts (`data-siteforge-runtime`), from one cached file. No authoring of modules (same OD). |
| SF-1205-003 resolution rules | Partial | Deterministic part order and content hash; reproducible (tested); provenance per page in the output and in Output files / Profile comparison (bundle vs the four Development files). No Check Website line listing the parts of each page and no source maps (proposed OD). |
| SF-1205-004 failure and recovery | Met | Each part isolated in `try` and reported; a plan without runtime files is unchanged; the reference audit finds no unresolved reference (tests: synthetic nested/localized plan, real localized Flow site, the three browser fixtures). |
| SF-1205-005 history | Met (n/a) | Output only; no content mutation. |
| SF-1205-006 accessible operation | Partial | No new UI; the bundle appears in the existing accessible Output files list. UI test blocked (measured CI timings, as for lane V12). |
| SF-1205-007 performance | Met | Linear pass over pages; 100 and 10,000-page fixture in `testStaticOutputReportsStayWithinBoundsOnStandardAndLargeFixtures`. |
| SF-1205-008 diagnostics and tests | Partial | Unit, integration, performance and browser (Static Release) coverage; the per-file report and integrity manifest record the bundle; no SF-1205-specific diagnostic record and no UI test (blocked). |
| SF-1206-001 asset manifest (manifest part) | Met | `assets.manifest.txt` lists images, SVG, posters, fonts, video, audio and captions, sorted by asset identity, content-free (ProjectResourceTests media and font tests; CommandKernelTests image format unchanged). The module requirement as a whole stays Partial for lane V12's reason (output record, not canonical state). |
| SF-1206-003 cache policy (runtime part) | Met | `siteforge-runtime.<64 hex>.js` → `immutable`; Development scripts and look-alike names → `revalidate` (tested). |
| SF-1206-004 references resolve (runtime part) | Met | Every page's bundle reference resolves from root, `posts/`, `fr/` and `fr/posts/` (tested); `manifest.txt` never names a file that is not written. |

Totals for this lane's rows: 6 Met, 5 Partial, 0 Missing.

## Remaining work (blocked only)

1. **Authored runtime modules, per-page part list in Check Website, source maps (SF-1205-001/002/003).** Outside
   OD-042's approved scope (generated static runtime only). Proposed OD below; recorded as Open (the 8:00 PM approval
   does not cover lane V12b).
2. **UI tests** for the Output files entry of the bundle: blocked like lane V12's (each UI test needs a measured
   `scripts/ci-ui-timings.txt` entry that only a Mac run produces).
3. **Running the browser harness** on the new Static Release sites needs the Mac with Google Chrome (no subprocess or
   browser on this PC); the helper test (`loads_effects_runtime`) was exercised in Python here.

## Proposed open decision (coordinator: next free lane H number, OD-123 unless taken)

```
## OD-123 — Authored runtime modules and runtime provenance in Check Website

Status: Open (recommended default in use). Implementation status: one generated content-hashed runtime file complete
in source, not verified (lane V12b, 2026-11-26, ADR-0124, SF-1205).

- Affected requirements: SF-1205-001, SF-1205-002, SF-1205-003, SF-1205-008.
- Recommended default: keep the runtime generated-only (menus, Flow, motion, interactions) in one content-hashed file
  per site; authors add their own scripts through Custom Code (SF-1107); Check Website keeps showing the bundle in
  Output files and Profile comparison; no source maps.
- Alternative: an authored module model (project scripts with dependencies, ordering and per-page inclusion),
  a per-page "runtime parts" list in Check Website and source maps for the bundle.
- Tradeoff: the alternative adds a canonical model, schema change, UI and security review of author code; the default
  keeps the critical invariants (reproducible builds, isolated failures) with no new state.
- Safe temporary assumption: the recommended default; no state is stored.
```

## Intended plan / OD status-line changes (exact text; not applied here)

- DEVELOPMENT_PLAN.md, lane E row E2 status:
  `done by lane V12b (ADR-0124, unverified; Static Release writes one content-hashed siteforge-runtime.<sha256>.js referenced from every page that uses a runtime — language trees, item/list pages, nested routes — and lists it in manifest.txt, the integrity manifest and the report (immutable); Development and Preview keep the readable per-runtime files; the Flow browser test runs Static Release output)`
- DEVELOPMENT_PLAN.md, lane H row H2 status (replaces lane V12's intended text):
  `done (H02, ADR-0121, RP-2026-11-26-H02, unverified; generated runtime hashed in Static Release (E2, ADR-0124), pages and stylesheets keep their names, no renditions; nested-route references resolve (lane V12); assets.manifest.txt lists images, SVG, posters, fonts, video, audio and captions (lane V12b, ADR-0124))`
- OPEN_DECISIONS.md, OD-042 Status line: replace `Still open: one hashed runtime script file (separate batch); publishing deferred.`
  with `Still open: publishing deferred.` and append:
  `Lane V12b (2026-11-26, ADR-0124): one hashed runtime script file complete in source, not verified — Static Release writes siteforge-runtime.<sha256>.js (immutable) in place of the per-runtime files, each page names the parts it runs and every reference resolves; Development and Preview unchanged; assets.manifest.txt lists every exported asset type.`
- OPEN_DECISIONS.md: add the proposed OD above as Open (lane H number assigned by the coordinator).
- No change to OD-045, OD-120, OD-121.

## New/changed test selectors

New:

```
SiteForgeTests/CanvasRendererTests/testStaticReleaseWritesOneContentHashedRuntimeEveryPageReferences
SiteForgeTests/SupportSettingsTests/testStaticReleaseFlowRuntimeIsOneHashedFileInEveryLanguageTree
Tests/Tooling/test_flow_runtime_browser.py: FlowRuntimeBrowserHelperTests.test_runtime_script_check_accepts_development_file_and_release_bundle
```

Changed:

```
SiteForgeTests/SupportSettingsTests/testFlowRuntimeActualBrowserDeformationFallbacksAndLifecycle   (writes Static Release sites)
SiteForgeTests/CanvasRendererTests/testStaticOutputReportsStayWithinBoundsOnStandardAndLargeFixtures   (bundle fixture)
SiteForgeTests/ProjectResourceTests/testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound   (asset manifest)
SiteForgeTests/ProjectResourceTests/testProjectFontsExportOnlyWithDeclaredWebRightsAndUseFallbackStacks   (asset manifest)
```

Run with them (unchanged, exercise the changed code):

```
SiteForgeTests/CanvasRendererTests/testStaticOutputIntegrityManifestCachePolicyAndReferenceAudit
SiteForgeTests/CanvasRendererTests/testStaticReleaseCSSOptimizerMinifiesDeduplicatesAndKeepsBlocksWhole
SiteForgeTests/CanvasRendererTests/testBuildProfileComparisonRebuildChangesBrowserSupportAndDiagnostics
SiteForgeTests/CanvasRendererTests/testBuildSettingsResolveBudgetsPerFileReportAndReleasePolicy
SiteForgeTests/CanvasRendererTests/testStaticBuildCompilerProfilesAreDeterministicRedactedAndCancellationNeutral
SiteForgeTests/CommandKernelTests/testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference
SiteForgeTests/TransformModelTests/testInteractionAndMotionRuntimesActualBrowserFocusTrapEscapePlacementAndReveal
SiteForgeTests/TransformModelTests/testMotionOutputIsReducedMotionSafeProgressiveDeterministicAndReleaseStable
SiteForgeTests/LaunchExperienceTests
```

## Exact commands for Codex (harness included)

```
/bin/zsh scripts/setup-verification-runtime.sh
/bin/zsh scripts/check-repository.sh
python3 Tests/Tooling/test_flow_runtime_browser.py
./sf test focused SiteForgeTests/CanvasRendererTests/testStaticReleaseWritesOneContentHashedRuntimeEveryPageReferences SiteForgeTests/CanvasRendererTests/testStaticOutputReportsStayWithinBoundsOnStandardAndLargeFixtures SiteForgeTests/CanvasRendererTests/testStaticOutputIntegrityManifestCachePolicyAndReferenceAudit SiteForgeTests/CanvasRendererTests/testBuildProfileComparisonRebuildChangesBrowserSupportAndDiagnostics SiteForgeTests/CanvasRendererTests/testStaticReleaseCSSOptimizerMinifiesDeduplicatesAndKeepsBlocksWhole
./sf test focused SiteForgeTests/ProjectResourceTests/testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound SiteForgeTests/ProjectResourceTests/testProjectFontsExportOnlyWithDeclaredWebRightsAndUseFallbackStacks SiteForgeTests/CommandKernelTests/testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference
./sf test focused SiteForgeTests/SupportSettingsTests/testStaticReleaseFlowRuntimeIsOneHashedFileInEveryLanguageTree SiteForgeTests/SupportSettingsTests/testFlowRuntimeActualBrowserDeformationFallbacksAndLifecycle
./sf test focused SiteForgeTests/TransformModelTests/testInteractionAndMotionRuntimesActualBrowserFocusTrapEscapePlacementAndReveal
./sf test half
```

The Flow browser test needs Google Chrome (or `SITEFORGE_CHROME`); hosted CI installs it. `docs/TESTING.md` and
`.github/workflows/ci.yml` name no runtime file and need no change. `Tests/Tooling/*.py` changes are
test-orchestration changes for `./sf test changed`, so use the explicit selectors above.

## Suggested first checks for Codex

1. `StaticRuntimeBundle.bundle`: `parts.compactMap { part -> (part: String, javascript: String)? in … }`, the
   labeled-tuple parameter of `bundleText(_:)`, and the `files.filter { … }.map { file -> LocalStaticBuildPlan.File in … }`
   closure that calls the static `page(_:path:parts:bundlePath:)` (internal parameter name `available`).
2. `StaticRuntimeBundle.page`: nested `removingTags(_ text: Substring)` with `used.reduce(String(text)) { result, part in … }`
   and `html[..<range.lowerBound]` / `html[range.upperBound...]`.
3. `StaticOutputCachePolicy.policy(for:)`: `a != nil || StaticRuntimeBundle.isBundlePath(path) ? .immutable : .revalidate`
   (ternary binds last, as intended).
4. `LocalBuildProfileCompiler.compile`: `sourceFiles` replaces `plan.files` in `usedIdentifiers` and the file map only;
   `testStaticReleaseCSSOptimizerMinifiesDeduplicatesAndKeepsBlocksWhole` must still see `index.html` unchanged
   (its plan has no runtime file).
5. `StaticAssetManifestEmitter.emit`: closures returning `(id: String, line: String)?`, `images + faces + files`, and
   `.sorted { ($0.id, $0.line) < ($1.id, $1.line) }` (tuple `<`); the planner call passes `fontPaths`/`mediaPaths`.
6. `testStaticReleaseWritesOneContentHashedRuntimeEveryPageReferences`: exact expected tags (`<p>Home</p><script …></script></body>`,
   `<body><script src="../…" data-siteforge-runtime="motion events" defer></script><div hidden data-siteforge-state="[]"></div></body>`),
   and the `contents.contains(source.path)` negative check (no runtime source names any `siteforge-*.js` file; checked).
7. `testStaticReleaseFlowRuntimeIsOneHashedFileInEveryLanguageTree`: `fr/index.html` uses `../siteforge-effects.js` in the
   plan (precondition) and `data-siteforge-runtime="effects"` in Static Release; `unresolved(in:) == [:]` covers the
   French tree's navigation links and alternates (site-root, not checked).
8. The Flow browser cases now load the Static Release site: `navigate()` waits for `window.SiteForgeDecorativeEffects`, which
   the bundle's `effects` part defines only when the page names it — a failure here means the page tag or the gating is wrong.
9. ProjectResourceTests media manifest: the order assertion compares `id.description` values sorted as strings, the same
   key the emitter sorts by.

## Write problems

None: no `AnchorError`, no `ICloudRenameError`; `foreign_changes(30)` and `icloud_duplicates()` stayed empty.
