# Lane R review H (lane-RH) — lane H batches H01–H03 — 2026-11-26

Reviewer: Code Forge lane R, reviewer H. Review freeze in force (REVIEW_BRIEF.md). Every edit went through
`forge_io.edit(owner="lane-RH")`; `check()` returned `[]` after each edit, and every changed region was re-read
against the declarations it calls. No compiler or test run was available on Windows, so nothing here is
verified by compilation. Schemas unchanged: document 27, persisted history 4, WebsiteMetadata 3, no new
`CanonicalDocument` key, no new Swift file, no new command.

## Scope

| Batch | Decision | Modules | What it added |
|---|---|---|---|
| H01 | ADR-0120 (OD-042) | SF-1204 | `StaticCSSOptimizer` (parser, cleaner, minifier, `trace`), `StaticCSSOptimizationReport`, `LocalBuildReport.cssReports`, `css-optimization-skipped`, "Stylesheet size" box |
| H02 | ADR-0121 (OD-042) | SF-1206 | `StaticOutputCachePolicy`, `StaticOutputFileRecord`, `StaticOutputManifest` (`siteforge-integrity.json`), `StaticOutputReferenceAudit`, `output-reference-unresolved`, `assets-unused`, `asset-oversized` split, folder-writer read-back |
| H03 | ADR-0122, OD-120 | SF-1208, SF-1211 | `ProjectPreferences.build` / `BuildProfileSettings` and friends, `ProjectPreferencesEdit.build`, `StaticBuildOutputSummary`, `StaticBuildBudgetAudit`, `StaticBuildRepairAction`, `BuildSettingsDiagnostic`, workspace save/repair API, "Build settings" and "Output files" boxes, repair button on `StaticBuildFindingRepairRow` |

Files reviewed: `SiteForge/CanvasRendererCore.swift` (sections SF-1204, SF-1206, SF-1208/SF-1211, `LocalBuildProfileCompiler`,
`StaticBuildCompiler.compile`, `LocalStaticBuildWriter.write`, the multi-page planner's nested-page rewriting),
`SiteForge/DocumentModel.swift` (`ProjectPreferences`, `BuildProfileSettings`, `BuildReleasePolicy`, `BuildSettingID`,
`BuildBudgetKind`, `BuildSettingsResolver`), `SiteForge/TransformModel.swift` (`ProjectPreferencesEdit`,
`ProjectPreferencesError`, `ProjectPreferencesCommandRegistry.prepare`), `SiteForge/CanvasSettings.swift`
(`ProjectSettingsStore`), `SiteForge/ProjectResources.swift` (`StaticAssetExportPlanner.plan`),
`SiteForge/WorkspaceShellModel.swift` (build settings API, `synchronizeProjectPreferences`),
`SiteForge/WorkspaceShellView.swift` (`StaticBuildDiagnosticsView`, `StaticBuildOutputFilesBox`, `StaticBuildSettingsBox`),
`SiteForge/BrowserPreview.swift` (`StaticBuildFindingRepairRow`), the three lane H tests in `CanvasRendererTests`, the
H03 test in `CanvasSettingsTests`, the two H01-updated assertions in `TransformModelTests`, and cross-lane users
(`ProjectComparer.compare`/`sameUncomparedContent`, snapshot restore, `PackagedSiteTemplate`, `PersistedHistory`,
UI tests that open Check Website).

How the CSS optimizer was checked: I ported `CSSParser`, `clean`, `deduplicated`, `isUnused`, `scan`, `split`,
`firstIndex`, `minifyValue`/`minifyPrelude`/`minifySelector` and `identifiers(in:)` line by line to Python and ran
(a) the H01 test's input — the port reproduces the test's exact expected string, counts (1 duplicate rule,
1 repeated declaration, 1 unused rule, 2 empty), idempotence, the dropped-brace regression and all six
fail-closed inputs; (b) every CSS shape the renderer emits: glass `@supports not ((…) or (…))` with nested
`@media`, `@media (width < 600px)` with several rules, `@supports selector(details::details-content)` with nested
`@media`, `:where(…)`, `::details-content`, `[data-siteforge-overlay="modal"]:not([hidden])`, `!important`,
`grid-area:1 / 1`, `var(--x,start)`, `@font-face` with quoted `url("…") format("…")`, `@keyframes`, `@container`,
the dark-mode wrapper, `url(data:…;base64,…)` and strings containing `;`, `{` and `}`. All parse; nothing is
reordered; only exact earlier duplicates, empty rules/blocks and rules whose every selector names an id absent
from every `.html`/`.js` file are removed; `:not(…)`, `:where(…)`, `:nth-child(…)` and substring attribute operators
are never removed. Ids are compared exactly as written; CSS selectors and HTML attributes both use the lowercase
`NodeID`/`PageID` description (`sf-node-`, `data-siteforge-node`, `data-siteforge-nav-link`, `sf-page-`), and item
pages, list pages and every language tree are `.html` files of the same plan, so their ids count as used.

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/CanvasRendererCore.swift` | `MultiPageStaticBuildPlanner.plan` (nested-page body rewrite, `assetFolder`) | Pages in a folder (language trees `fr/…`, collection item pages, a list's later pages, nested routes) rewrote only ` src="assets/` to `../assets/`. A video's ` poster="assets/…"` stayed site-root relative, so the poster image was broken on every nested page and H02's audit reported a real `output-reference-unresolved` there. | The same folder prefix is applied to ` poster="assets/`; the prefix is computed once (`assetFolder`). Root pages are byte-identical. | SF-0803 / SF-1206-004 critical invariant "all output references resolve". |
| 2 | `SiteForge/CanvasSettings.swift` | `ProjectSettingsStore.reset()` | H03 put build settings inside `ProjectPreferences`; Settings › Project "Reset" drafted `nil`, so Apply silently removed build settings (budgets, release policy, start profile) that the pane does not show. | Reset drafts `ProjectPreferences(build: committed.build)` when build settings exist (status names that they stay and where they are edited); otherwise unchanged (`nil`). | No hidden data loss (SF-0206-004 / SF-1208-004, AGENTS "preserve user intent"). Existing reset tests have no build settings, so their behavior is unchanged. |
| 3 | `SiteForge/WorkspaceShellView.swift` | `StaticBuildDiagnosticsView.body` | H01/H03 inserted "Build settings" (~5 pickers, provenance lines, 3 buttons), "Stylesheet size" and "Output files" between Status and "Compatibility findings" inside the ScrollView. The findings `LazyVStack` moved below the 560–640 pt sheet's visible area, so `testPreviewAndCheckWebsiteFindingRepairUsesExistingEditorJourney` (`repairButton("build.finding").waitForExistence` / `waitForHittable`) would very likely fail (lazy rows off screen are not created, off-screen buttons are not hittable). | Findings and the reveal status come first again (pre-lane geometry); "Stylesheet size", "Output files" and "Build settings" follow. No identifier, binding or behavior changed; the VStack still has 8 children. | Cross-lane UI-test breakage; findings and their repairs are the sheet's primary actions. |
| 4 | `SiteForge/BrowserPreview.swift` | `StaticBuildFindingRepairRow` repair button | The new repair button lacked the `.focusable()` + single Space activation that the row's Show Object button uses so Tab reaches it regardless of the system "all controls" preference. | Same two modifiers as Show Object (`onKeyPress(.space, phases: .down) { _ in applyRepair(repairAction); return .handled }`). Preview never passes a repair action, so its focus order is unchanged. | SF-1211-006 keyboard parity. |
| 5 | `SiteForge/CanvasRendererCore.swift` | `StaticCSSOptimizationReport.summary` | Used `ByteCountFormatter` `.file` (1 KB = 1,000 bytes) while "Output files", budget findings and budget labels use `.binary` (1 KB = 1,024 bytes): the same `styles.css` showed two different sizes in one sheet. | `.binary` in both calls, with a why-comment. Tests do not assert these strings. | Consistent, budget-matching units (SF-1204-003 / SF-1208-003). |
| 6 | `SiteForge/DecorativeEffects.swift` | `EventGraphOutput.overlayCSS` doc comment | Said "release de-duplication is line based", which H01 replaced (ADR-0120 listed it as out of date). | Comment now states that Static Release minifies whole rules, so a line's minified form appears in release CSS (what `TransformModelTests` relies on). | Comments must say why and be true. |

Tests changed (no test weakened):

- `ProjectResourceTests.testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound`: the root video build
  has no `output-reference-unresolved`; a copy with the media Image moved to a new page `/media/tour` writes
  `media/tour.html` whose poster, `<source>` and `<track>` start with `../assets/` and has no unresolved reference
  (regression fixture for fix 1).
- `CanvasSettingsTests.testBuildSettingsSaveUndoRedoRepairsAndStaleReview`: Settings › Project Reset + Apply keeps the
  build settings and removes only the grid preference (regression fixture for fix 2).

Reviewed and found correct (no change): `StaticCSSOptimizer` access levels (fileprivate nested types only used by
`private`/`fileprivate` members or inside the enum; `trace` uses `CSSStatement` only locally), the `scan(_:_:)`
closure type with `_ index:` labels and the non-escaping closures that mutate captured locals, `guard let found = try
read(until:)` with the labeled tuple, the report memberwise inits that skip defaulted members, the multi-statement
`map { file -> LocalStaticBuildPlan.File in … }` appending to `cssReports`; `StaticOutputManifest` synthesized
`Decodable` beside its two custom inits; `text.range(of:range:)` (options defaulted); `guard try Data(contentsOf:
safeOutputURL(…)) == …` (the one `try` covers both throwing calls) and read-back of text and binary files before
promotion, with any mismatch mapped to `writeFailed` and the stage removed; `Dictionary(_:uniquingKeysWith:)`;
`StaticAssetExportPlanner` order (type → negative size `corrupt` → over limit `oversized` → bytes), which matches
both H02 assertions and the lane F media tests (no test expects `.unsupported` for an over-limit file);
`ProjectPreferences`/`BuildProfileSettings` exact-key decoding, null rejection, omit-when-empty encoding and the
schema-22 gate; `ProjectPreferencesCommandRegistry.prepare` (`.build` keeps grid values; a new invalid budget is
refused, an untouched stored one retained); every `switch` over `ProjectPreferencesError` (two, both include
`.invalidBuildBudget`), `StaticAssetExportError`, `StaticBuildRepairAction`, `BuildBudgetKind`, `BuildSettingID`,
`ProjectPreferenceSource`; `.raiseBudget(let kind, let kilobytes)` patterns; `StaticBuildFindingRepairRow` memberwise
init (two defaulted `var`s after `reveal`; Preview's call unchanged); explicit inits of the two private views
(`self.state = state` on `@ObservedObject`, `@State private var draft` with a private nested type);
`.tag(LocalBuildProfile?.none)` / `.tag(Int?.some(…))` against optional bindings; `var values: [Int] = switch kind`;
`LocalBuildReport(…, deferredCapabilities: [], outputFiles: …)` skipping `cssReports`; `affectedOutputNodes` declared
before both asset loops and used in the same `do` scope; `ByteCountFormatter` `.binary`; `ProjectComparer.compare`
and `sameUncomparedContent`, snapshot restore (`setProjectPreferences` when `projectPreferences` differ),
`PackagedSiteTemplate` and persisted history all carry `build` through `projectPreferences`; the H03 test's
expectations (totals order `[.page, .stylesheet, .asset]`, finding order, repair values 300 KB / 6,144 KB, undo
counts 2 → 4, diagnostic setting IDs) against the implementation. Existing tests that compile sites with assets use
tiny fixtures (no file near 5 MB, no page near 256 KB), and no existing test asserts the absence of all warnings, so
the new budget warnings break none; `testConnectedFluidPreflightSafariExportCancelAndReopenJourney` still gets an
enabled Build button because warnings block only under `warnings-block-release`.

## Requirement table

| Requirement | Status | Evidence / gap |
|---|---|---|
| SF-1204-001 state | Partial | Generated CSS only, emitted in a deterministic order; no authored CSS-rule model (ADR-0120 "not built"). |
| SF-1204-002 create/modify (trace declarations) | Partial | `StaticCSSOptimizer.trace(_:nodeID:)` (tested); no Inspector surface. |
| SF-1204-003 resolution/provenance | Partial | Cascade order never changes; trace lists rules with conditions in cascade order; "Stylesheet size" report. No "which rule wins" UI. |
| SF-1204-004 failure/recovery | Met | Fail closed on unknown at-rules, nesting, unbalanced text, malformed declarations; stylesheet written unchanged; `css-optimization-skipped` with repair `useProfile(.development)`; six fail-closed inputs and the dropped-brace regression tested. |
| SF-1204-005 history | Met (n/a) | Output-only; no content mutation. |
| SF-1204-006 accessible | Partial | `build.cssSize` combined element; no announcement, no UI test. |
| SF-1204-007 performance | Partial | Single byte-level pass per stylesheet, set-based de-duplication; runs in the compile worker. No 10,000-object performance test. |
| SF-1204-008 diagnostics/tests | Partial | Report carries sizes/counts only (asserted); unit test plus regression fixture. No diagnostic record with duration/category. |
| SF-1206-001 state (asset manifest) | Partial | `StaticOutputManifest` v1, sorted, deterministic, Codable (tested); an output record, not project state (assets themselves are canonical). |
| SF-1206-002 create/modify (deduplicate) | Partial | Content-addressed names dedupe identical bytes; no manifest UI beyond "Output files". |
| SF-1206-003 resolution (preserve originals) | Met | Originals written byte-for-byte; cache policy rule (`immutable` only for `assets/<sha256>.<ext>`); `assets-unused` information (tested). |
| SF-1206-004 failure/recovery | Met | `asset-missing/-corrupt/-oversized/-unsupported`, `media-*`, `output-reference-unresolved` per file, read-back before promotion, nested-page poster fixed (fix 1, tested). |
| SF-1206-005 history | Met (n/a) | Output-only. |
| SF-1206-006 accessible | Partial | Findings and the per-file list are accessible elements; no UI test. |
| SF-1206-007 performance | Partial | Linear audits; folder build reads every file back once (deliberate); no performance test. |
| SF-1206-008 diagnostics/tests | Partial | Manifest and findings carry no content (asserted); unit tests; no diagnostic record. |
| SF-1208-001 state (build profile) | Met | `BuildProfileSettings` v1: optional fields, omitted vs authored vs default, strict keys, null rejected, invalid stored budget retained (tested). |
| SF-1208-002 create/modify (cancel) | Partial | Draft → Save to Project / Revert / Use SiteForge Defaults, build Cancel; model tested, no UI test. |
| SF-1208-003 resolution | Met | `BuildSettingsResolver` precedence; each value's source shown ("Set in this project", "SiteForge default", invalid-value rule) (tested). |
| SF-1208-004 failure/recovery | Met | Stale review, running build, invalid budget, no change leave the project unchanged with a specific status (tested); Settings › Project reset no longer drops build settings (fix 2, tested). |
| SF-1208-005 history | Met | One `document.projectPreferences.set` transaction, undo/redo, persisted history, serializer round trip (tested); comparer/snapshot/template via `projectPreferences`. |
| SF-1208-006 accessible | Partial | Labeled pickers, identifiers, hints, announcements on save/failure; no UI test, no menu command. |
| SF-1208-007 performance | Partial | File list is lazy and behind a disclosure; the summary is rebuilt in the view body (sort per render). No performance test. |
| SF-1208-008 diagnostics/tests | Partial | `BuildSettingsDiagnostic` value-free (tested); no UI/performance tests. |
| SF-1211-001 state (compatibility finding) | Partial | Findings are typed and derived per check (not persisted, by design); the policy and budgets that produce them are persisted. |
| SF-1211-002 navigate findings | Partial | Show Object and one-step repair per finding; repair button now keyboard-reachable (fix 4); no UI test for the repair button. |
| SF-1211-003 resolution | Met | Budget warnings name output and object; release policy blocks only Static Release while warnings remain; Development never blocked (tested end to end). |
| SF-1211-004 failure/recovery | Met | Plan and per-file report stay visible while blocked; repairs raise a budget to the smallest fitting whole KB, allow warnings, or check with Development (tested). |
| SF-1211-005 history | Met | Settings repairs are undoable project-preferences edits; the profile repair changes only the check (tested). |
| SF-1211-006 accessible | Partial | Hints and identifiers; keyboard parity fixed; no UI test. |
| SF-1211-007 performance | Partial | Repair action computed only for rendered rows (lazy); recomputes a summary per budget finding. No performance test. |
| SF-1211-008 diagnostics/tests | Partial | Findings redacted (tested); `BuildSettingsDiagnostic`; no UI test. |

## Remaining gaps (easiest → hardest)

1. Stale comment in `TransformModelTests` motion test ("release de-duplication of identical lines cannot break a
   block"): reword to the ADR-0120 behavior when that file is next touched (comment only; left alone to avoid touching
   another lane's test during the freeze).
2. `LocalBuildReport.outputFiles` (and so "Output files" and the site total budget) does not include
   `siteforge-integrity.json` itself, because H02's test pins `outputFiles == manifest.files`. Plan: decide whether
   the report should add a record for the manifest file (size known after encoding) and update that assertion.
3. "Output files" builds `StaticBuildOutputSummary` with the current document's settings, while findings use the
   settings of the compilation; after an Undo of a budget the over-budget marks and findings can disagree until the
   next check. Plan: keep the `BuildSettingsResolution` used by the compile on `StaticBuildCompilation` and use it.
4. Diagnostic records for CSS optimization and manifest/reference audit (requirement IDs, duration, failure
   category), like `BuildSettingsDiagnostic`. Plan: one value-free record per compile in the build worker.
5. UI tests: Build settings draft → Save → Undo; repair button (click and Space); Output files disclosure; plus
   `scripts/ci-ui-timings.txt` entries.
6. Performance fixtures: 10,000-object stylesheet through `StaticCSSOptimizer.optimize`, 10,000-file summary.
7. H4 (plan): profile comparison, cache keys/incremental rebuild, browser target matrix (ADR-0123, OD-121).
8. SF-1204 authored CSS-rule model and Inspector provenance ("which rule wins") — needs its own decision.

## Intended OD status-line changes (do not apply here; `docs/OPEN_DECISIONS 2.md` is frozen)

- OD-042, lane H line: append "Lane R review (RH, 2026-11-26): H01–H03 reviewed against declarations; nested-page
  video posters now start at the page's folder; Settings › Project Reset keeps build settings; Check Website shows
  findings before reports and build settings; repair buttons keyboard-reachable. Unverified (no compiler)."
- OD-120: no change (open; recommended defaults 256 KB / 5 MB / 50 MB and "Block on errors only" in use).

## New/changed test selectors

Changed:

```
SiteForgeTests/ProjectResourceTests/testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound
SiteForgeTests/CanvasSettingsTests/testBuildSettingsSaveUndoRedoRepairsAndStaleReview
```

Run with them (unchanged, but they exercise the reviewed code):

```
SiteForgeTests/CanvasRendererTests/testStaticReleaseCSSOptimizerMinifiesDeduplicatesAndKeepsBlocksWhole
SiteForgeTests/CanvasRendererTests/testStaticOutputIntegrityManifestCachePolicyAndReferenceAudit
SiteForgeTests/CanvasRendererTests/testBuildSettingsResolveBudgetsPerFileReportAndReleasePolicy
SiteForgeTests/CanvasSettingsTests/testProjectSettingsStoreDraftApplyCancelStaleResetAndNoProject
SiteForgeTests/TransformModelTests (the overlay and motion Static Release assertions)
SiteForgeTests/PersistedHistoryTests (language-tree image sources `src="../…"`)
SiteForgeUITests/SiteForgeLaunchTests/testPreviewAndCheckWebsiteFindingRepairUsesExistingEditorJourney
SiteForgeUITests/SiteForgeLaunchTests/testStaticBuildDiagnosticsPreflightProfileCancelAndAccessibilityJourney
SiteForgeUITests/SiteForgeLaunchTests/testConnectedFluidPreflightSafariExportCancelAndReopenJourney
```

No accessibility identifiers were added or removed; no UI test was added, so `scripts/ci-ui-timings.txt` is unchanged.

## Suggested first checks for Codex

1. `MultiPageStaticBuildPlanner.plan`: `let pageBody = !output.contains("/") ? body : body` followed by two chained
   `.replacingOccurrences(of:with:)` lines with a comment between them (ternary precedence; the chain belongs to the
   else branch).
2. The new block in `testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound`: `nodes.remove(at:)` into a
   `var`, `moved.parent = .node(tour.rootNodeIDs[0])`, `try nestedDocument.validate()` with a second standard page at
   `/media/tour`, and the expected `media/tour.html` path; and that the nested page gets no other unresolved reference
   (generated navigation `../index.html`, stylesheet/script prefixes).
3. `ProjectSettingsStore.reset()`: `draft = committed?.build.map { ProjectPreferences(build: $0) }` then
   `status = draft == nil ? … : …`; and the added end of `testBuildSettingsSaveUndoRedoRepairsAndStaleReview`
   (`ProjectSettingsStore(defaults:resolveTarget: { state })`, `begin()`, `reset()`, `apply()` inside a synchronous
   `@MainActor` test, `defer` removing the suite).
4. `StaticBuildFindingRepairRow`: `.focusable()` + `.onKeyPress(.space, phases: .down) { _ in applyRepair(repairAction); return .handled }`.
5. Everything H01 listed for the optimizer still applies; the Python port agrees with the H01 test byte for byte, but a
   Swift run is the real check, especially `trace` (lowercase ids) and the fail-closed list.
6. `testPreviewAndCheckWebsiteFindingRepairUsesExistingEditorJourney` with the restored layout (findings first).
7. H03 end-to-end precondition: a blank site's written files exceed 1 KB (`XCTAssertGreaterThan(…, 1_024, "Precondition")`);
   it should (two pages with full heads plus robots/manifest), but it was not measured.
8. `SupportSettingsTests.swift` is unreadable on Windows and was not checked for `ProjectPreferencesError` switches,
   Settings › Project reset or Static Release CSS assertions.
