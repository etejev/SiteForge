# Lane V01 review — batches 01–03 — 2026-11-26 (unverified)

Owner request (6:55 PM EST): treat every Code Forge batch and edit as unverified, check dev-doc
gaps and Codex code quality, fix everything, finish partial features and leave a clean stopping
point for Codex. Brief: `_quick-scratch\review\VERIFY_BRIEF.md`. Owner tag `lane-V01`,
ADR-0140, OD-140 (not needed). Nothing was compiled or run (Windows PC, no Swift toolchain).

## Scope

| Batch | Restore points diffed | Files | Modules |
|---|---|---|---|
| 01 (first candidate) | RP-2026-11-25-01 → -02 | `SiteForge/LaunchExperience.swift`, `SiteForge/PackagedSiteTemplate.swift`, `Tests/SiteForgeTests/LaunchExperienceTests.swift`, `scripts/ci-ui-timings.txt`, `.github/workflows/ci.yml` (unreadable placeholder) | SF-0204 (Aurora Flow template slice); recipe evidence for SF-0508, SF-1101, SF-1204, SF-0502, SF-0602, SF-0604, SF-0802, SF-1102 |
| 02 (tests and browser harness) | RP-2026-11-25-02 → -03 | `Tests/SiteForgeTests/TransformModelTests.swift`, `CanvasRendererTests.swift`, `SupportSettingsTests.swift` (unreadable), `Tests/Tooling/flow_runtime_browser.py`, `test_flow_runtime_browser.py` (unreadable) | test evidence only (glass, Flow, dark token variants, premultiplied interpolation, Flow browser runtime) |
| 03 (project-scoped preferences, ADR-0027) + save-limit fix, stress fixture, refinement | RP-2026-11-25-03 → -04 | 14 source files, 6 test files, `scripts/ci-ui-timings.txt`, ADR-0027 | SF-0206 (all 8), SF-0301-007 (capacity) |

Method: per-batch unified diffs from the restore points; then every batch-added line located in
the current tree and re-read with its call sites and declarations. Codex compiled batches 01–06
and ran their affected selectors before RP-2026-11-26-07 (`docs/evidence/SF-QUICK-BATCH-INTEGRITY.md`:
both architectures built; final affected replay 4/4), so the highest risk is what later lanes changed
around these regions. I diffed RP-2026-11-26-07 → current for every batch file and read every hunk that
touches batch 01–03 symbols (batch 08 package v2 capacity, lane H build settings in
`ProjectPreferences`, lane A comparison/snapshot restore, schema 22 → 27 key set). Mechanical checks
over the 3,000+ batch lines in the current tree: argument labels against current declarations (adapted
`labelcheck.py`: 1,618 calls, 21 hits, all stdlib/SwiftUI or multi-name `let` false positives) and
identifiers that no longer exist anywhere else in the tree (126 hits, all declared by the batch lines
themselves: no removed dependency).

Checked and correct (no change): `ProjectPreferences` strict coding (`requireKnownKeys`, null rejection,
version gate, omitted-when-empty, `build` key from ADR-0122); the `CanonicalDocument` strict optional-key
set for schemas 18–21 vs 22+; the post-decode schema-22 gate; `ModelValidationError.invalidProjectPreferences`;
`SetProjectPreferencesCommand` exact keys and the persisted-history v4 closed payload; every
`DocumentCommand` switch case (name, history schema 4, targets, descriptor, availability, mutation and
inverse); `ProjectPreferencesCommandRegistry` stale/busy/cancel/invalid/no-change handling including build
budgets; snapshot restore (`setProjectPreferences` in the restore command list) and comparison
(`ProjectComparer.compare` names "Project preferences" and "Build settings"; `sameUncomparedContent`
aligns the field); `PackagedSiteTemplate` copies `projectPreferences`; workspace adoption
(`synchronizeProjectPreferences`, `worldGridSpacing`, both canvas `configure`/`update` paths, `drawWorldGrid`);
grid density floor (minimum zoom 0.25, so the default grid's bands are unchanged); `SettingsDestination`
switches; `SettingsDraftNotice`; `ActiveWorkspaceResolver`; Settings window host; Swift 6 isolation of
`ProjectSettingsStore` (main-actor class, `nonisolated` static strings, selector observers on window
notifications, `deinit` only removes observers); Aurora Flow start choice (hidden until bundled, shared
`PackagedSiteTemplateLoader`, focus/identifier/hint, `CreationChoice` switches); timing manifest (181 UI
methods vs 180 rows; the extra name is the private helper `testVisibleFrame() -> CGRect?`); batch 02
production paths (DecorativeEffects/colour tokens changed after RP-07 only by additions for form fields,
motion and interactions).

## Fixes made

| File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|
| `SiteForge/CanvasSettings.swift` | `ProjectSettingsStore.documentChanged(_:)` | Since ADR-0122 stores build settings in the same record, a Check Website save (or its Undo) while a grid draft was pending made the draft stale; only Cancel was possible, discarding the user's grid choice. | When only the build settings changed (grid fields equal the reviewed ones), keep the grid draft on the new build settings, move the baseline, clear stale, explain in the status, record a value-free `rebase-draft` diagnostic. A changed grid preference is still stale. | SF-0206-004 "recovery MUST preserve user intent"; ADR-0140. |
| `SiteForge/CanvasSettings.swift` | `ProjectSettingsView` Reset button, new `ProjectSettingsStore.draftHasGridPreferences` | Reset was enabled (accessibility value "Reset available") when the draft held only build settings, but Reset then changed nothing. | Enabled and announced only while the draft sets a grid preference. | SF-0206-002/006: controls state what they do. |
| `SiteForge/CanvasSettings.swift` | `ProjectSettingsStore.begin()` status | A project with only build settings said "Project preferences loaded" while its grid follows this Mac and SiteForge. | Status depends on whether a grid preference is set. | SF-0206-003 provenance must be truthful. |
| `SiteForge/CanvasSettings.swift` | `ProjectSettingsStore.apply()` status | Reset that kept build settings reported "Project preferences saved in this project". | Says "Grid preferences removed… its build settings stay. Undo… restores them." (the full-removal and saved texts are unchanged; the UI journey's "saved in this project" still matches). | SF-0206-004/005. |
| `SiteForge/DocumentLifecycle.swift` | `ProjectFileCapacity.opened(fileBytes:document:)`, `LoadedProject.capacity`, `DocumentLifecycleBackend.read(from:identity:progress:)`, controller adoption | Batch 03 known gap: capacity was unknown after Open/Revert until the first save, so a project opened near the 8 MB file or 4 MB page limit showed no warning. | Measured on the backend actor from the validated bytes; pages are measured (as a save does) only when the file is ≥ 85% of one member; adopted on Open and Revert; recovery restore still starts unmeasured. | SF-0301-007, SF-0206-007; ADR-0140. |
| `SiteForge/CanvasViewport.swift` | `CanvasWorldGridPolicy` | The `minorInterval(for:base:)` doc comment was attached to `minimumScreenSpacing`, so both comments described the constant. | Comments reordered onto their declarations. | Comments must say why, on the right symbol. |
| `SiteForge/SupportSettings.swift` | `SiteForgeSettingsRootView.pendingDraftNotice`, `cancelDraftsAction` | Accessibility label "Unsaved application preferences" and help "Reload the latest saved application preferences" while the notice also lists Project drafts. | Label "Unsaved preference drafts"; help "Discard every draft and reload the saved preferences. Project files are not changed." No test references either string. | SF-0206-006 meaningful labels; scope is explicit. |

Earlier review fixes in this area (Nov 25 "Final review of batches 01–06", "Review of batches 02 and 03",
Codex integrity repair) were re-checked: `customizedSlotContents` throws instead of force-unwrapping;
the Code Forge test force-unwraps became `XCTUnwrap`; the recipe now requires frames for every visible
object; the Chrome prerequisite check (unreadable here). Codex's repair left no batch 01–03 work half-done
beyond what the batch entries already list.

## Features finished

| Item | ADR | State |
|---|---|---|
| Batch 03 save-limit gap: project-file capacity measured on Open and Revert (model + backend + controller + test) | ADR-0140 | complete in source, unverified |
| Batch 03 / ADR-0122 interplay: Project pane keeps a grid draft across build-setting changes; Reset only when it removes something; truthful status (model + UI + diagnostics + test with undo/redo) | ADR-0140 | complete in source, unverified |
| Batch 03 "Still open: version comparison" (SF-0206-001/005) | ADR-0040 (lane A) | already closed by lane A: `ProjectComparer.compare` and snapshot restore cover project preferences; no change needed |

## Requirement table

SF-0206 — Preferences and workspace customization (batch 03; source only, nothing executed):

| ID | Status | Evidence |
|---|---|---|
| SF-0206-001 | Met | `ProjectPreferences` (optional, versioned, strict, omitted vs authored), `ProjectPreferenceID`, schema-22 gate; `CanvasSettingsTests/testProjectPreferencesResolutionPrecedenceValidationAndStrictCoding`, `…DocumentSchemaGateAndBackwardCompatibleReopen`; comparison in `ProjectComparer.compare` + `ProjectPackageTests/testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded` ("Project preferences", "Build settings") |
| SF-0206-002 | Met | Draft → Apply/Cancel/Escape/Reset in `ProjectSettingsStore`/`ProjectSettingsView`; `…StoreDraftApplyCancelStaleResetAndNoProject`, new `…PaneKeepsGridDraftAcrossBuildSettingChanges`, UI journey `testProjectSettingsGridPreferenceDraftApplyUndoAndCancelJourney` |
| SF-0206-003 | Met | `ProjectPreferenceResolver` (project → this Mac → SiteForge, invalid fallback), provenance per control; `…ResolutionPrecedence…`, `testWorkspaceAdoptsAuthoredProjectGridAndKeepsSceneToggleLocal` |
| SF-0206-004 | Met | stale/different/closed/busy/invalid/repair, build-only rebase keeps intent; `…InvalidStoredValueIsRetainedRepairedAndNeverIntroduced`, `…StoreUnavailableInvalidRepairAndValueFreeDiagnostics`, new rebase test |
| SF-0206-005 | Met | one transaction per Apply, undo/redo, history v4 (v3 migration), save/reopen/autosave, snapshot restore; `…RegistryUndoRedoAndRejectionsWithoutMutation`, `PersistedHistoryTests/testProjectPreferencesSaveReopenRecoveryAndPersistedHistorySchema` |
| SF-0206-006 | Partial | Labels, identifiers, status announcements, ⌘, and sidebar arrow keys, default/cancel actions are in source; VoiceOver / Full Keyboard Access / 200% matrix is native exploratory QA on the Mac (blocked here) |
| SF-0206-007 | Met | Standard/large/stress fixtures (stress = 20,000-node budget), bounded grid density, capacity warning now from Open; `…StayResponsiveOnStandardLargeAndStressFixtures`, `testStressFixtureFillsTheDocumentedNodeBudgetExactly`, `PersistedHistoryTests/testProjectPreferencesPersistAtLargeFixtureAndRespectPackageLimitAtStress`, new `DocumentLifecycleTests/testProjectFileCapacityIsMeasuredWhenAProjectIsOpened`; named-hardware timings still need retained evidence |
| SF-0206-008 | Met | Value-free `ProjectSettingsStore.Diagnostic` (requirement IDs per operation, sanitized document ID, preference IDs, duration, failure category); unit/integration/history/migration/perf/UI coverage |

SF-0204 — Onboarding, templates and learning, batch 01 slice (Aurora Flow start choice):

| ID | Status | Evidence |
|---|---|---|
| SF-0204-001 | Met | Reserved `BundledSiteTemplates.auroraFlowID`, template provenance on load; recipe test |
| SF-0204-002 | Partial | `.auroraFlow` creation choice and Start card exist; the card is hidden until the reviewed sample is bundled (blocked, see below) |
| SF-0204-003 | Met | One validating `PackagedSiteTemplateLoader`, deterministic bundle lookup; `testAuroraFlowStartChoiceUsesSharedLifecycleWhetherOrNotSampleIsBundled` |
| SF-0204-004 | Met | Unbundled sample fails visibly without mutating the current document (same test) |
| SF-0204-005 | Met | Shared atomic creation lifecycle, clean template workspace (no undo, no file URL); recipe save/load round trip |
| SF-0204-006 | Partial | Card identifier `launch.newAuroraFlowProject`, label, hint, focus case; no UI journey until the card can appear |
| SF-0204-007 | Partial | Template is small; no template-specific scale evidence beyond the shared loader |
| SF-0204-008 | Met | `testAuroraFlowShowcaseRecipeBuildsCompilesSavesAndLoadsEditableTemplate` (passed in Codex replay `20261125-201323-26ef8307`), start-choice test |

Batch 02 adds tests only; module statuses are unchanged by it.

Totals: Met 12, Partial 4, Missing 0.

## Remaining work (blocked only)

1. Aurora Flow sample bytes, the visible Start card and a `launch.newAuroraFlowProject` UI journey with a
   timing row (SF-0204-002/006). Blocked: the bytes are produced by the recipe test on the Mac and may be
   copied into `Samples/Aurora/AuroraTemplate/` only after native and Safari visual acceptance
   (`QUICK_BATCH_01_HANDOFF.md` steps 3–4); a UI journey can only be written once the card shows.
2. Batch 02 `SupportSettingsTests.testFlowRuntimeActualBrowserDeformationFallbacksAndLifecycle` and
   `Tests/Tooling/*flow_runtime_browser*.py`. Blocked: unreadable iCloud placeholders on Windows; pixel
   thresholds need a real browser run.
3. SF-0206-006 exploratory QA (VoiceOver, Full Keyboard Access, 200% text). Blocked: needs the Mac.
4. A UI journey for the status-bar capacity warning (`status.projectCapacity`). Blocked: needs a ≥ 6.8 MB
   (or ≥ 3.4 MB single-page) package fixture generated by Swift on the Mac and a measured timing row; it
   cannot be produced or estimated here. Unit coverage exists (two save/autosave tests and the new open test).
5. By design, not a gap: an autosave refused above the limit means crash recovery does not cover edits made
   while over it; the refusal is surfaced (`projectTooLarge`), and the limits are security boundaries (ADR-0012).

## Intended plan / OD status-line changes (for lane V15)

- `docs/OPEN_DECISIONS.md` OD-032, append to "Implementation status": `Lane V01 (2026-11-26, ADR-0140): the opened file is measured too, so the capacity warning appears before the first save (unverified).`
- `docs/coordination/CODE_FORGE_ACTIVITY.md` entry title: `## Lane V01 — 2026-11-26 (verification of batches 01–03, ADR-0140, unverified, complete)` — 7 fixes in `CanvasSettings.swift`, `DocumentLifecycle.swift`, `CanvasViewport.swift`, `SupportSettings.swift`; 2 new tests; report `docs/reviews/LANE-V01-review-2026-11-26.md`.
- Same log, batch 03 "Known gaps": mark `capacity is unknown after Open` as `resolved by lane V01 (ADR-0140)` and `Version comparison: no comparison surface exists` as `resolved by lane A (ADR-0040)`.
- `DEVELOPMENT_PLAN.md` lane V row: `V01 | batches 01–03 | done (unverified) — 7 fixes, 2 tests, ADR-0140; blocked: Aurora Flow bytes/UI journey (Mac + visual acceptance), batch 02 browser harness (unreadable), SF-0206-006 exploratory QA, capacity UI journey`.

## New / changed test selectors

```
SiteForgeTests/CanvasSettingsTests/testProjectSettingsPaneKeepsGridDraftAcrossBuildSettingChanges
SiteForgeTests/DocumentLifecycleTests/testProjectFileCapacityIsMeasuredWhenAProjectIsOpened
```

No existing test was changed. No UI test was added, so `scripts/ci-ui-timings.txt` is unchanged.

## Suggested first checks for Codex

1. `ProjectFileCapacity.opened(fileBytes:document:)`: `(try? ProjectPackageStore.encodedPages(of: document))?.map(\.count).max()` must type-check as `Int?` (static method on the `ProjectPackageStore` actor, nonisolated).
2. `LoadedProject(... migration: migration, capacity: capacity)`: memberwise label order (`migration` before `capacity`).
3. `ProjectSettingsStore.documentChanged`: `Self.sameGridPreferences` / `Self.hasGridPreferences` (private static, main actor) and `record("rebase-draft", started: .now, …)`.
4. Run `CanvasSettingsTests/testProjectSettingsPaneKeepsGridDraftAcrossBuildSettingChanges`: it relies on one main-queue turn after `saveBuildSettings` delivering the store's `$document` sink (same pattern as `…StoreDraftApplyCancelStaleResetAndNoProject`).
5. Run `DocumentLifecycleTests/testProjectFileCapacityIsMeasuredWhenAProjectIsOpened`: compares the opened capacity with the writer's v2 page measurement.
6. Batch 03 selectors that have no recorded result yet (the full gate `20261125-201801-d8042c0e` is still pending): all 15 batch 03 core selectors listed in its activity-log entry plus `SiteForgeUITests/SiteForgeLaunchTests/testProjectSettingsGridPreferenceDraftApplyUndoAndCancelJourney`.
7. `CanvasSettingsTests/testProjectPreferencesDocumentSchemaGateAndBackwardCompatibleReopen`: decodes a current blank document relabelled schema 21; confirm nothing added since RP-07 makes the blank document carry a schema-27-only key.
