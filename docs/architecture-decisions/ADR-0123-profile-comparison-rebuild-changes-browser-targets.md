# ADR-0123 — Profile comparison, rebuild changes by cache key, browser target matrix (SF-1208, SF-1211)

- Status: Proposed (implemented as an unverified Code Forge candidate by lane V12; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-042 (approved by the owner 2026-11-26 1:30 PM EST: static export only); lane H item H4.
  Browser targets: OD-121 (open; recommended default in use, like OD-120).
- Builds on: ADR-0120 (CSS optimization), ADR-0121 (integrity manifest), ADR-0122 (build settings and budgets)
- Requirements: SF-1208-003 (profile provenance, incremental and clean builds), SF-1208-008, SF-1211-003
  (compatibility findings per target), SF-1211-008, SF-1204-008, SF-1206-008 (diagnostics)

## Context

After H01–H03, Check Website showed one profile's per-file report. The rest of SF-1208/SF-1211 (plan item H4)
was missing: comparing Development with Static Release file by file, telling what a rebuild changes (cache
keys / incremental rebuild), and grading the output for browser targets with the fallbacks SiteForge chose.
Lane R (RH) also left three gaps inside OD-042: the "Output files" report and the site budget did not count
`siteforge-integrity.json`; "Output files" judged rows with the *current* document's settings while the findings
used the settings of the check (they disagreed after an Undo); and no value-free diagnostic record existed for a
check.

## Decision

All code is in `SiteForge/CanvasRendererCore.swift`, section "SF-1208/SF-1211 profile comparison, rebuild
changes, browser support", plus `StaticBuildCompilation`, `LocalBuildProfileCompiler.compile` and
`StaticBuildCompiler.compile`; the workspace and Check Website changes are listed below.

- `StaticBuildCompilation` gains three optional, defaulted members (existing memberwise calls are unchanged):
  `buildSettings` (the `BuildSettingsResolution` the check used), `profileComparison` and `browserSupport`.
  They are filled only when a plan was produced. "Output files" and `buildRepairAction(for:)` use
  `buildSettings`, so marks, findings and repairs always agree.
- `LocalBuildReport.outputFiles` now lists every written file. In Static Release that includes a record for
  `siteforge-integrity.json` itself (size and SHA-256 of the written JSON, `revalidate`); the manifest file still
  does not list itself. The site budget therefore counts every written byte.
- `StaticBuildProfileComparison(development:staticRelease:)`: rows per path (sorted) with both sizes and a
  `Difference` (`identical`, `changed`, `only-development`, `only-static-release`) from the output records'
  hashes; totals; `differingRows`; a counts-and-sizes summary. `StaticBuildCompiler.compile` builds the other
  profile of the same plan with `LocalBuildProfileCompiler.compile` (the CSS optimizer and hashing run once more
  on the build worker), so the comparison is the same whichever profile is checked. No file contents are kept.
- `StaticOutputChangeSummary(previous:current:)`: added, changed and removed paths and the unchanged count,
  keyed by each file's SHA-256 (its cache key; content-addressed assets also change name when bytes change).
  `WorkspaceShellState.staticBuildChanges` compares a completed check with the previous one of the same
  document and profile; "Output files" shows it ("Since the previous check: …").
- Incremental *writing* is deliberately not built: every write stays a complete build that is staged, read back
  and promoted atomically (ADR-0121), so cancel or failure never leaves partial or mixed output (SF-1208-001
  "cancel leaves no publishable partial output"). Skipping unchanged files would require trusting bytes already
  at the destination. The incremental part is change detection by cache key, which tells the user and any host
  exactly which files a rebuild changes.
- Browser target matrix: `StaticBrowserVersion` (major.minor, `Comparable`), `StaticBrowserTarget` (Safari 17,
  Chrome 120, Edge 120, Firefox 121 — OD-121 recommended default), `StaticOutputFeature` (container size rules,
  glass blur, menu panel layout via `::details-content`, reveal on scroll via `IntersectionObserver`) with each
  engine's first supporting version and the fallback the generator already writes, and
  `StaticBrowserSupportReport(plan:targets:)` (features found in generated `.css`/`.js` files only; per-target
  grade `full` or `degraded`; never "unsupported", because every listed feature has a written fallback). With
  the default targets only the menu panel layout degrades (all four targets predate `::details-content`).
  No finding is added, so existing finding lists and the release policy are unchanged.
- `StaticOutputDiagnostic(compilation:durationMilliseconds:operation:)`: requirement IDs SF-1204-008,
  SF-1206-008, SF-1208-008, SF-1211-008, operation, sanitized document identity (`DiagnosticStableIdentifier`,
  domain `staticBuild`), profile, file count, total bytes, skipped-stylesheet, unresolved-reference and budget
  counts, duration and failure category (`none`, `cancelled`, `preflight-blocked`). No paths, selectors,
  contents or authored names. The workspace records `lastStaticOutputDiagnostic` for every completed check.
- Check Website (`SiteForge/WorkspaceShellView.swift`): the reports after the findings move into a new private
  view `StaticBuildOutputReportsView` (keeps the sheet body small): "Stylesheet size" (unchanged), "Output files"
  (now with the check's settings and the change line, `build.outputFiles.changes`), new "Profile comparison"
  (`build.profileComparison`, lazy list of differing files `build.profileComparison.list`) and new "Browser
  support" (`build.browserSupport`). Findings stay first, so the existing UI tests' geometry is unchanged.

## Consequences

- One more profile compile per successful check (on the worker). Output bytes of both profiles are unchanged.
- Static Release's report, Output files total and site budget now include the integrity manifest's size.
- Browser targets are a recommended default until the owner decides OD-121; the targets are code constants,
  not project settings, so no schema changes (document 27, persisted history 4, WebsiteMetadata 3 unchanged).
- Not built: per-project browser targets (needs OD-121), incremental writing (rejected above), UI tests for the
  new boxes (each UI test needs a measured entry in `scripts/ci-ui-timings.txt`, which only a Mac run produces).

## Verification

`SiteForgeTests/CanvasRendererTests/testBuildProfileComparisonRebuildChangesBrowserSupportAndDiagnostics`,
`SiteForgeTests/CanvasRendererTests/testStaticOutputIntegrityManifestCachePolicyAndReferenceAudit` (manifest
record), `SiteForgeTests/PersistedHistoryTests` (collection item pages: every reference resolves). Not compiled
or run by Code Forge.
