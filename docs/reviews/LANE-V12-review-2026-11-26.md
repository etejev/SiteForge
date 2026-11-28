# Lane V12 verification — lane H (static output) — 2026-11-26

Verifier: Code Forge lane V12 (owner tag `lane-V12`), under `_quick-scratch\review\VERIFY_BRIEF.md`. Every tree
write went through `forge_io.edit(owner="lane-V12")` or `write_new`; `check()` returned `[]` after each edit, and
every changed region was read again against the declarations it calls. `foreign_changes(30)` and
`icloud_duplicates()` were `[]` before the first write and afterwards. No compiler or test run is available on
Windows, so none of this is verified by compilation. Schemas unchanged: document 27, persisted history 4,
WebsiteMetadata 3, no new `CanonicalDocument` or `DocumentNode` key, no new command, no new Swift file.

## Scope

| Batch | Decision | Modules | Restore point used for the diff |
|---|---|---|---|
| H01 Static Release CSS optimizer | ADR-0120 (OD-042) | SF-1204 | RP-2026-11-26-H01 → H02 (lane H ledger rows 17:22) |
| H02 integrity manifest, cache policy, reference audit | ADR-0121 (OD-042) | SF-1206 | RP-2026-11-26-H02 → H03 (17:31) |
| H03 build settings, per-file report, budgets, repairs | ADR-0122, OD-120 | SF-1208, SF-1211 | RP-2026-11-26-H03 → R01 (17:44–17:51) |
| Lane RH fixes (6) | — | all four | RP-2026-11-26-R01 → V00 (18:27–18:40) |
| Partial items: H2 nested routes, RH gaps 1–6, H4 | OD-042, ADR-0123, OD-121 | SF-1208, SF-1211 | — |
| E2 one hashed runtime file (added by the owner at 7:40 PM) | OD-042 | SF-1205 | — (see Remaining work) |

Lane H rows in `WRITE_LEDGER.tsv` identified the lane's writes among the other lanes' concurrent edits; for
each file I read the current code of every lane H region in full, not only the diff:
`SiteForge/CanvasRendererCore.swift` (SF-1204 section: report, trace, optimizer, parser, cleaner, byte helpers;
SF-1206 section; SF-1208/SF-1211 section; `LocalBuildReport`, `LocalBuildProfileCompiler.compile`,
`StaticBuildCompilation`, `StaticBuildCompiler.compile`, `LocalStaticBuildWriter.write`,
`MultiPageStaticBuildPlanner.plan` nested-page rewriting, `SiteLanguageOutput.relativeRoutes`,
`StaticNavigationEmitter`, `InternalDocumentRenderTreeCompiler.control`/`staticNavigation`, `StaticSEOEmitter.head`,
the `SafeHTMLEmitter` image/media/control emitters), `SiteForge/DocumentModel.swift` (`ProjectPreferences`,
`BuildProfileSettings`, `BuildReleasePolicy`, `BuildSettingID`, `BuildBudgetKind`, `BuildSettingsResolver`,
`ProjectPreferenceResolution`), `SiteForge/TransformModel.swift` (`ProjectPreferencesEdit`, `ProjectPreferencesError`,
`ProjectPreferencesCommandRegistry.prepare`), `SiteForge/CanvasSettings.swift` (`category`, `reset`),
`SiteForge/WorkspaceShellModel.swift` (project preferences, build settings API, preflight task),
`SiteForge/WorkspaceShellView.swift` (`StaticBuildDiagnosticsView` and its boxes), `SiteForge/BrowserPreview.swift`
(`StaticBuildFindingRepairRow`), `SiteForge/DecorativeEffects.swift` (`EventGraphOutput.page`, glass CSS), the lane H
tests in `CanvasRendererTests`, `CanvasSettingsTests`, `TransformModelTests`, `ProjectResourceTests`, and the
collection item-page test in `PersistedHistoryTests`. I also reran `review\symcheck.py` and `review\labelcheck.py`
with base RP-2026-11-26-V00 over the lines lane V added: the only hits in my files are a second `let` binding
(`otherHash`, valid Swift the checker does not parse) and SwiftUI/stdlib false positives.

Earlier review fixes re-verified (all correct): RH 1 nested-page posters (`assetFolder` and the chained
`.replacingOccurrences` belong to the `else` branch of the ternary), RH 2 `ProjectSettingsStore.reset()` keeping build
settings, RH 3 findings first in Check Website, RH 4 repair button `.focusable()` + Space, RH 5 binary units,
RH 6 `EventGraphOutput.overlayCSS` comment.

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/CanvasRendererCore.swift` | `LocalBuildProfileCompiler.compile` | `LocalBuildReport.outputFiles` left out `siteforge-integrity.json` in Static Release, so "Output files", the per-kind totals and the site budget undercounted the written bytes (RH gap 2). | The report adds a record for the manifest file (size and SHA-256 of the written JSON, `revalidate`); the JSON is encoded once. The manifest still does not list itself. | SF-1208-003 / SF-1211-003: budgets must count what is written. |
| 2 | `SiteForge/CanvasRendererCore.swift`, `SiteForge/WorkspaceShellView.swift` | `StaticBuildCompilation.buildSettings`, "Output files" | "Output files" judged rows with the current document's settings while the findings used the settings of the check, so after an Undo of a budget the warning marks and the findings disagreed (RH gap 3). | The compilation keeps the `BuildSettingsResolution` it used (new defaulted member); "Output files" uses it (fallback: current document). | One check, one set of rules (SF-1208-003). |
| 3 | `SiteForge/WorkspaceShellModel.swift` | `buildRepairAction(for:)` | Same mismatch for repair values. | Uses `compilation.buildSettings` (same revision, so equal to the current ones; fallback kept). | Repair values match the finding. |
| 4 | `Tests/SiteForgeTests/TransformModelTests.swift` | motion Static Release test comment | Said "release de-duplication of identical lines cannot break a block", which ADR-0120 replaced (RH gap 1). | Comment now states that Static Release minifies whole rules and keeps each line's minified form. | Comments must be true. |
| 5 | `docs/architecture-decisions/ADR-0121-static-asset-integrity-manifest.md` + `Tests/SiteForgeTests/PersistedHistoryTests.swift` | H2 "nested-route references reported, not fixed" | The planner already writes every generated reference of a page in a folder relative to that page (fixed by another lane between H01 and H02; RH fixed posters), but the ADR and plan still said "not fixed" and no regression fixture covered collection item pages. | Traced every reference kind (links and navigation via `relativeRoutes`, `src`/`poster`/`<source>`/`<track>` via the folder prefix, stylesheet/scripts/favicon via `prefix`, interactions via `EventGraphOutput.page(…prefix:)`; canonical/hreflang stay site-root and are not checked). Added assertions to the collection item-page test: `posts/hello.html` uses `src="../assets/…"`, `StaticOutputReferenceAudit.unresolved(in:) == [:]`, no `output-reference-unresolved`. ADR-0121 gained an "Update (lane V12)" section. | SF-1206 critical invariant "all output references resolve"; regression fixture for an escaped defect class. |
| 6 | `SiteForge/WorkspaceShellView.swift` | `StaticBuildDiagnosticsView.body` | The sheet body was large (8 children, two report boxes with inline logic) and would grow to 10 with H4. | The reports after the findings move into the new private `StaticBuildOutputReportsView` (one child); findings stay first, no identifier, binding or order changed. | Keeps the body small enough to type-check; keeps the UI-test geometry RH restored. |

## Features finished

| Item | Decision | What was built |
|---|---|---|
| H4 profile comparison (SF-1208-003) | ADR-0123 (OD-042) | `StaticBuildProfileComparison` (rows per path with both sizes and `identical/changed/only-development/only-static-release`, totals, `differingRows`, summary); `StaticBuildCompiler.compile` builds the other profile of the same plan on the worker; `StaticBuildCompilation.profileComparison`; Check Website "Profile comparison" box (`build.profileComparison`, lazy list `build.profileComparison.list`). |
| H4 cache keys / incremental rebuild (SF-1208) | ADR-0123 (OD-042) | `StaticOutputChangeSummary` (added/changed/removed/unchanged by SHA-256 cache key); `WorkspaceShellState.staticBuildChanges` compares each completed check with the previous one of the same document and profile; "Output files" shows it (`build.outputFiles.changes`). Incremental *writing* deliberately not built: every write stays a complete staged, read-back, atomically promoted build (SF-1208-001 "cancel leaves no publishable partial output"); recorded in ADR-0123. |
| H4 browser target matrix (SF-1211-003) | ADR-0123, OD-121 (new, open; recommended default in use) | `StaticBrowserVersion`, `StaticBrowserTarget` (Safari 17, Chrome 120, Edge 120, Firefox 121), `StaticOutputFeature` (container size rules, glass blur, menu panel layout, reveal on scroll) with first supporting versions and the generator's written fallback, `StaticBrowserSupportReport` (per-target grade `full`/`degraded`, never unsupported); `StaticBuildCompilation.browserSupport`; "Browser support" box (`build.browserSupport`). No new finding, so finding lists and the release policy are unchanged. |
| Diagnostics for CSS / manifest / audit / budgets (RH gap 4; SF-1204/1206/1208/1211-008) | ADR-0123 | `StaticOutputDiagnostic` (requirement IDs, operation, sanitized document ID, profile, counts, sizes, duration, failure category; no paths or content); `WorkspaceShellState.lastStaticOutputDiagnostic` recorded with the measured duration for every completed check. |
| Performance fixtures (RH gap 6; SF-1204/1206/1208/1211-007) | ADR-0120–0123 | 100 and 10,000-object fixtures through the optimizer, reference audit, per-file summary, profile comparison and change summary with safety bounds (existing style of `testResponsiveAuditStaysWithinBoundsOnStandardAndLargeFixtures`). |
| H2 nested-route references | ADR-0121 update | See fix 5. |

## Requirement table

| Requirement | Status | Evidence / gap |
|---|---|---|
| SF-1204-001 state | Partial | Generated CSS only; no authored CSS-rule model (needs its own owner decision; outside OD-042). |
| SF-1204-002 trace declarations | Partial | `StaticCSSOptimizer.trace(_:nodeID:)` tested; no Inspector surface (same decision). |
| SF-1204-003 resolution | Partial | Cascade order never changes; trace with conditions; "Stylesheet size"; no "which rule wins" UI (same decision). |
| SF-1204-004 failure | Met | Fail-closed optimizer, `css-optimization-skipped` + repair; six inputs and regression tested. |
| SF-1204-005 history | Met (n/a) | Output only. |
| SF-1204-006 accessible | Partial | `build.cssSize` combined element; no UI test (blocked, see Remaining 2). |
| SF-1204-007 performance | Met | Linear passes on the worker; 10,000-object fixture (new). |
| SF-1204-008 diagnostics/tests | Partial | `StaticOutputDiagnostic` (new) + unit/regression tests; UI test blocked. |
| SF-1206-001 asset manifest | Partial | `StaticOutputManifest` v1 (output record, not project state; assets themselves are canonical). |
| SF-1206-002 deduplicate | Partial | Content-addressed names; manifest UI is "Output files" only. |
| SF-1206-003 resolution | Met | Cache policy, `assets-unused`, originals byte-for-byte. |
| SF-1206-004 failure | Met | Asset/media findings, read-back before promotion, every nested reference resolves (fix 5 fixtures). |
| SF-1206-005 history | Met (n/a) | Output only. |
| SF-1206-006 accessible | Partial | Accessible elements; UI test blocked. |
| SF-1206-007 performance | Met | Linear audit; 10,000-object fixture (new). |
| SF-1206-008 diagnostics/tests | Partial | Diagnostic record (new); UI test blocked. |
| SF-1208-001 build profile | Met | `BuildProfileSettings` v1 strict keys, omitted vs authored vs default (tested). |
| SF-1208-002 cancel | Partial | Draft/Save/Revert/Defaults and build Cancel, model tested; UI test blocked. |
| SF-1208-003 resolution | Met | Resolver with provenance; check keeps its settings (fix 2); profile comparison and rebuild changes (new, tested). |
| SF-1208-004 failure | Met | Stale/running/invalid/no change leave the project unchanged (tested). |
| SF-1208-005 history | Met | One `document.projectPreferences.set` transaction, undo/redo, persisted, serializer round trip (tested). |
| SF-1208-006 accessible | Partial | Labels, identifiers, hints, announcements; UI test blocked. |
| SF-1208-007 performance | Met | Lazy lists; 10,000-record summary/comparison/change fixture (new). |
| SF-1208-008 diagnostics/tests | Partial | `BuildSettingsDiagnostic`, `StaticOutputDiagnostic`; UI test blocked. |
| SF-1211-001 finding state | Partial | Findings are derived per check by design; the policy and budgets are persisted. |
| SF-1211-002 navigate findings | Partial | Show Object + one-step repair, keyboard-reachable; UI test blocked. |
| SF-1211-003 resolution | Met | Budget warnings name output and object; release policy; browser target matrix with chosen degradations (new, tested; targets per OD-121). |
| SF-1211-004 failure | Met | Plan and report stay visible while blocked; repairs (tested). |
| SF-1211-005 history | Met | Settings repairs undoable; profile repair changes only the check (tested). |
| SF-1211-006 accessible | Partial | Hints and identifiers; UI test blocked. |
| SF-1211-007 performance | Met | Lazy repair computation; 10,000 fixture (new). |
| SF-1211-008 diagnostics/tests | Partial | Redacted findings, diagnostic records; UI test blocked. |

Totals: 16 Met, 16 Partial, 0 Missing.

## Remaining work (blocked only)

1. **E2 — one content-hashed runtime script file (OD-042, SF-1205).** Harness files are now readable and were read
   (`Tests/Tooling/flow_runtime_browser.py` requires `'siteforge-effects.js'` in a page's script sources and
   `window.SiteForgeDecorativeEffects.version == 1`; `test_flow_runtime_browser.py` checks only helpers and the
   11-case list). Blocked by `Tests/SiteForgeTests/SupportSettingsTests.swift`, still an unreadable placeholder that
   must not be touched: its last readable copy (RP-2026-11-25-06, line 61) asserts
   `plan.files.contains { $0.path == "siteforge-effects.js" && $0.contents == DecorativeEffectRuntime.javascript }`
   for every harness fixture and then runs the harness. Renaming or combining the runtime breaks that test, and
   keeping the old files beside a hashed copy would write unused duplicate runtimes. Exact change set for whoever can
   edit `SupportSettingsTests.swift` (on the Mac): emit `siteforge-runtime.<sha256-prefix>.js` (immutable cache policy:
   widen `StaticOutputCachePolicy.policy(for:)`), point every page's `<script>` at it with the folder prefix, update the
   harness check (line 416) and its helper test in the same change, `SupportSettingsTests` line 61, 17 assertions in
   `TransformModelTests`, 9 in `InsertionModelTests`, 1 in `CanvasRendererTests`, 1 in `LaunchExperienceTests`, 1 in
   `SiteForgeUITests/SiteForgeLaunchTests`, and the 12 emitting sites in `CanvasRendererCore.swift`. Lane C's runtime
   code (V09) was not touched.
2. **UI tests** for Build settings draft → Save → Undo, the repair button (click and Space), Output files / Profile
   comparison disclosures and Browser support. Blocked: CI shards UI selectors with `scripts/ci-test-accounting.py`
   from measured durations in `scripts/ci-ui-timings.txt` ("UI selector durations in whole seconds" from an
   `.xcresult`), which only a Mac run produces; a guessed entry would make the accounting false.
3. **OD-121** (browser targets) needs the owner's decision; the recommended default is in use (below).
4. **SF-1204-001/002/003 authored CSS-rule model and Inspector "which rule wins"**: outside OD-042 (static export
   only); needs a new owner decision in lane H's OD range. Recommended default: keep CSS generated-only and expose
   `StaticCSSOptimizer.trace` in a later Inspector item.

## New open decision (for the coordinator to add to `docs/OPEN_DECISIONS.md`)

```
## OD-121 — Browser targets for Check Website's browser support report

Status: Open (recommended default in use, like OD-120). Implementation status: browser target matrix complete in
source, not verified (lane V12, 2026-11-26, ADR-0123, SF-1211-003).

- Affected requirements: SF-1211-003, SF-1208-003, SF-1205.
- Recommended default: grade generated output for Safari 17, Chrome 120, Edge 120 and Firefox 121 (each engine's
  release from the end of 2023); every feature SiteForge uses keeps a written fallback, so older targets degrade
  visibly and never break. Targets are app constants, not project settings.
- Alternative: let each project choose its targets (a new optional `BuildProfileSettings` field, version stays 1),
  or track a rolling "last two years" baseline.
- Tradeoff: fixed targets need no schema or UI and keep reports comparable; per-project targets add a setting,
  validation and migration that Codex must verify.
- Safe temporary assumption: the recommended default targets; no setting is stored.
```

## Intended plan / OD status-line changes (exact text; not applied here)

- DEVELOPMENT_PLAN.md, lane H row H2 status: `done (H02, ADR-0121, RP-2026-11-26-H02, unverified; generated pages/scripts not hashed (E2), no renditions; nested-route references resolve (verified by lane V12, regression fixtures in PersistedHistoryTests and ProjectResourceTests))`
- DEVELOPMENT_PLAN.md, lane H row H4 status: `done by lane V12 (ADR-0123, OD-121 open with recommended default, unverified; profile comparison, rebuild changes by cache key, browser target matrix, check diagnostics; incremental writing rejected in ADR-0123; UI tests blocked on measured CI timings)`
- DEVELOPMENT_PLAN.md, lane E row E2 status: `blocked: SupportSettingsTests.swift (unreadable) pins siteforge-effects.js name and contents; harness files now readable (lane V12 change list in LANE-V12 report)`
- OPEN_DECISIONS.md, OD-042 implementation status, append: `Lane V verification (V12, 2026-11-26): H01–H03 and RH fixes re-verified; Output files and budgets count siteforge-integrity.json; the check keeps the build settings it used; nested-route references resolve; H4 profile comparison, rebuild change summary, browser target matrix and check diagnostics complete in source (ADR-0123, OD-121), not verified. One hashed runtime script still blocked by SupportSettingsTests.swift.`
- OPEN_DECISIONS.md: add the OD-121 section above. OD-120 unchanged.

## New/changed test selectors

New:

```
SiteForgeTests/CanvasRendererTests/testBuildProfileComparisonRebuildChangesBrowserSupportAndDiagnostics
SiteForgeTests/CanvasRendererTests/testStaticOutputReportsStayWithinBoundsOnStandardAndLargeFixtures
```

Changed:

```
SiteForgeTests/CanvasRendererTests/testStaticOutputIntegrityManifestCachePolicyAndReferenceAudit
SiteForgeTests/PersistedHistoryTests/testCollectionTemplatePageBuildsOneEscapedPagePerPublishedItem
SiteForgeTests/TransformModelTests (motion Static Release test: comment only)
```

Run with them (unchanged, exercise the changed code):

```
SiteForgeTests/CanvasRendererTests/testBuildSettingsResolveBudgetsPerFileReportAndReleasePolicy
SiteForgeTests/CanvasRendererTests/testStaticReleaseCSSOptimizerMinifiesDeduplicatesAndKeepsBlocksWhole
SiteForgeTests/CanvasRendererTests/testStaticBuildCompilerProfilesAreDeterministicRedactedAndCancellationNeutral
SiteForgeTests/CanvasSettingsTests/testBuildSettingsSaveUndoRedoRepairsAndStaleReview
SiteForgeTests/ProjectResourceTests/testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound
SiteForgeUITests/SiteForgeLaunchTests/testPreviewAndCheckWebsiteFindingRepairUsesExistingEditorJourney
SiteForgeUITests/SiteForgeLaunchTests/testStaticBuildDiagnosticsPreflightProfileCancelAndAccessibilityJourney
```

Exact commands for Codex (from `docs/TESTING.md` and `.github/workflows/ci.yml`):

```
/bin/zsh scripts/setup-verification-runtime.sh
/bin/zsh scripts/check-repository.sh
python3 scripts/test-ci-test-accounting.py
python3 Tests/Tooling/test_flow_runtime_browser.py
./sf test focused SiteForgeTests/CanvasRendererTests/testBuildProfileComparisonRebuildChangesBrowserSupportAndDiagnostics SiteForgeTests/CanvasRendererTests/testStaticOutputReportsStayWithinBoundsOnStandardAndLargeFixtures SiteForgeTests/CanvasRendererTests/testStaticOutputIntegrityManifestCachePolicyAndReferenceAudit SiteForgeTests/CanvasRendererTests/testBuildSettingsResolveBudgetsPerFileReportAndReleasePolicy SiteForgeTests/CanvasSettingsTests/testBuildSettingsSaveUndoRedoRepairsAndStaleReview SiteForgeTests/ProjectResourceTests/testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound
./sf test focused SiteForgeTests/PersistedHistoryTests SiteForgeTests/TransformModelTests SiteForgeTests/InsertionModelTests
./sf test focused SiteForgeTests/SupportSettingsTests/testFlowRuntimeActualBrowserDeformationFallbacksAndLifecycle
./sf test half
./sf test focused SiteForgeUITests/SiteForgeLaunchTests/testPreviewAndCheckWebsiteFindingRepairUsesExistingEditorJourney SiteForgeUITests/SiteForgeLaunchTests/testStaticBuildDiagnosticsPreflightProfileCancelAndAccessibilityJourney
```

The Flow browser test needs Google Chrome (or `SITEFORGE_CHROME`). No accessibility identifiers were removed. New
identifiers: `build.outputFiles.changes`, `build.profileComparison`, `build.profileComparison.list`,
`build.browserSupport`. No UI test was added, so `scripts/ci-ui-timings.txt` is unchanged.

## Suggested first checks for Codex

1. `StaticBrowserVersion: Comparable, Hashable` with a custom `<` over the tuple `(major, minor)` (synthesized `==`).
2. `StaticOutputFeature.firstSupportedVersion(_:)`: a switch *expression* over `(self, target)` with multi-pattern
   cases and comments between cases; exhaustive over 4 × 4.
3. `StaticBuildProfileComparison.init`: `if let developmentFile, let releaseFile { … }` inside the `map` closure,
   ternary after `&&`, `Set(…keys).union(…keys).sorted()`.
4. `StaticOutputChangeSummary.init`: stored lets assigned from locals (no read of `self` before initialization).
5. `StaticBuildCompilation` memberwise init with three new defaulted `var`s after `findings`; the one call that passes
   them (`buildSettings:profileComparison:browserSupport:`) in `StaticBuildCompiler.compile`; every other call omits them.
6. `StaticBuildCompiler.compile`: `LocalBuildProfileCompiler.compile(withAssets, profile: otherProfile).1`; check
   `testStaticBuildCompilerProfilesAreDeterministicRedactedAndCancellationNeutral` (`XCTAssertEqual(first, second)`
   now also compares the comparison and browser report).
7. `LocalBuildProfileCompiler.compile`: `var records = manifest.files` + manifest record + sort; the H02 test's new
   assertions (`outputFiles.map(\.path) == filePaths`).
8. `startStaticBuildPreflight`: `let started = ContinuousClock.now` captured by the `Task`; `staticBuildChanges` and
   `lastStaticOutputDiagnostic` assigned with implicit `self` after `guard let self`.
9. `StaticBuildOutputReportsView`, `StaticBuildProfileComparisonBox` (`let differing = …` inside a `VStack` builder),
   `StaticBuildBrowserSupportBox` (`ForEach` over `StaticBrowserTarget`/`Entry`, both `Identifiable`).
10. The PersistedHistoryTests assertion `StaticOutputReferenceAudit.unresolved(in: compiledPlan) == [:]`: if it fails,
    it names a real unresolved generated reference on item pages (the safety net working), not a test error.
11. `SupportSettingsTests.swift` (unreadable): still asserts `siteforge-effects.js` and the runtime contents; nothing
    here changed either. Its last readable copy (RP-2026-11-25-06) names none of `StaticBuildCompilation`,
    `LocalBuildReport`, `outputFiles`, `ProjectPreferencesEdit/Error` or `StaticCSSOptimizer`; check the current copy.
12. Browser support facts used: container queries Safari 16 / Chrome 105 / Firefox 110; `backdrop-filter` (with
    `-webkit-`) Safari 9 / Chrome 76 / Firefox 103; `::details-content` Safari 18.4 / Chrome 131 / Firefox 143;
    `IntersectionObserver` Safari 12.1 / Chrome 58 / Firefox 55. Please double-check Firefox 143.

## Write problems

None: no `AnchorError`, no `ICloudRenameError`; `foreign_changes(30)` and `icloud_duplicates()` were empty. One
on-device call returned a network error after it ran (ADR-0123 and the ADR-0121 update), and I confirmed both writes
on disk before going on. The device went offline once during the final checks.
