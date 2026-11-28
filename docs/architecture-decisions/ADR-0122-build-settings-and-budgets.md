# ADR-0122 — Build settings, per-file build report and budget/policy findings (SF-1208, SF-1211)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-042 (approved by the owner 2026-11-26 1:30 PM EST: static export only); lane H item H3.
  Default budget values and the default release policy are OD-120 (open; recommended default in use).
- Builds on: ADR-0120 (CSS size report), ADR-0121 (`LocalBuildReport.outputFiles`, integrity manifest)
- Requirements: SF-1208-001/002/003/004/005/008, SF-1211-001/002/003/004/008

## Context

Check Website already had two built-in profiles (Development, Static Release) chosen per check, typed
findings with repair text and Show Object, and (H01/H02) a CSS size report and a record of every written
file. Missing: a saved, versioned build-settings model (SF-1208-001), budgets and a release policy that
decides whether warnings block writing (SF-1211 critical invariant), a per-file report, and one-step
repairs.

## Decision

- Model (`SiteForge/DocumentModel.swift`): `BuildProfileSettings` (version 1; optional `profile`,
  `pageBudgetKilobytes`, `assetBudgetKilobytes`, `totalBudgetKilobytes`, `releasePolicy`; strict keys, null
  rejected, omitted when unset; 0 = no limit; valid budgets 0…10,485,760 KB), `BuildReleasePolicy`
  (`errors-only`, `warnings-block-release`), `BuildSettingID` (diagnostic identities), `BuildBudgetKind`
  (finding codes `budget-page-exceeded`, `budget-asset-exceeded`, `budget-total-exceeded`) and
  `BuildSettingsResolver` (project value → SiteForge default; an invalid stored budget resolves as
  `invalidProjectValue` with the default and is retained).
- Storage: a new optional `build` key inside `ProjectPreferences` (schema 22+), not a new
  `CanonicalDocument` key. It therefore reuses `document.projectPreferences.set` (one undoable command with an
  exact inverse, persisted history schema 4), snapshot restore, `ProjectComparer`, document validation and
  the schema-22 serializer gate. `ProjectPreferences.currentVersion` stays 1; files without the key are
  unchanged byte for byte. `ProjectPreferenceID` is unchanged (Settings' grid pane and its tests).
- Commands (`TransformModel.swift`): `ProjectPreferencesEdit.build(_:)` replaces only the build record
  (grid preferences kept; an empty record is normalized away). A new invalid budget is refused with
  `ProjectPreferencesError.invalidBuildBudget`; an untouched stored invalid value is retained.
- Compiler (`CanvasRendererCore.swift`, section "SF-1208/SF-1211 build settings"): `BuildSettingsResolution`,
  `StaticOutputFileKind`, `StaticBuildOutputSummary` (rows with kind, size, cache policy and budget flag;
  totals by kind), `StaticBuildBudgetAudit` (warnings per over-budget page or asset naming the output path and,
  for images/media, the first object that shows it; one site-total warning), `releasePolicyFinding`
  (`release-policy-warnings`, error, only for Static Release under `warnings-block-release` while warnings
  remain), `StaticBuildRepairAction` (`raiseBudget` to the smallest whole-KB value that fits,
  `allowWarnings`, `useProfile(.development)` for `css-optimization-skipped`) and `BuildSettingsDiagnostic`.
  `StaticBuildCompiler.compile` adds budget findings after the reference audit and the policy finding last;
  the plan and report are still returned, so the per-file report stays visible while writing is blocked.
- Workspace (`WorkspaceShellModel.swift`): `saveBuildSettings(_:reviewed:)` (stale review, running build,
  invalid value and no change leave the project unchanged; value-free diagnostics), `buildRepairAction(for:)`,
  `applyBuildRepair(_:)`. `synchronizeProjectPreferences` applies a saved profile as Check Website's starting
  profile on open and when the saved value changes (Save, Undo, Redo); choosing a profile for one check never
  writes the project.
- UI (`WorkspaceShellView.swift`, `BrowserPreview.swift`): Check Website gains "Build settings" (draft →
  Save to Project / Revert / Use SiteForge Defaults; each value states the rule that supplies it and
  "· Draft"), "Output files" (summary, totals by kind, disclosure with every file: path, size, cache policy,
  over-budget mark) and a repair button on findings that have a one-step repair.

## Alternatives considered

- A new `CanonicalDocument` key: needs template copy, comparer, serializer gate, strict-key and snapshot
  changes (plan rule 8) for no extra capability; project preferences already have all of these.
- Making the profile picker itself write the project: every check would create an undo entry; rejected.

## Consequences

- Output files are byte-identical with and without build settings (tested). Findings can now include the
  three budget warnings with the OD-120 defaults (256 KB page, 5 MB asset, 50 MB site), so a large site that
  wrote cleanly before may now show warnings; it is still written unless the project chooses
  `warnings-block-release`.
- Not built: profile comparison, a staging profile, cache keys / incremental builds, browser target matrix,
  portability grades and chosen degradations, link checks beyond H02's reference audit.
