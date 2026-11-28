# Lane V06 review — batches 15–17 (2026-11-26)

Reviewer: Code Forge lane V06 (owner tag `lane-V06`). Verification by reading only:
no Swift toolchain, no compiler, no test run on this Windows copy. Every item
below is **unverified until Codex compiles and runs it**.

## Scope

- Batch 15 — zip export target (OD-042, SF-1209, ADR-0035), diff
  `RP-2026-11-26-08 → -09`: `CanvasRendererCore.swift`, `BrowserPreview.swift`,
  `WorkspaceShellModel.swift`, `WorkspaceShellView.swift`, `CanvasRendererTests.swift`.
- Foundation check entry and batch 16 — feature flags (OD-047, SF-1803,
  ADR-0036), diff `-09 → -10`: `SupportSettings.swift`, `BrowserPreview.swift`,
  `WorkspaceShellView.swift`, `CanvasSettingsTests.swift`.
- Batch 17 — custom code (OD-041, SF-1107, ADR-0037), diff `-10 → -11`:
  `DocumentModel.swift`, `CanvasRendererCore.swift`, `BrowserPreview.swift`,
  `WorkspaceShellView.swift`, `PersistedHistoryTests.swift`, `CanvasRendererTests.swift`.
- Owner decisions 1:30 PM (OD-041, OD-042, OD-047 status lines), ADR-0035/36/37.
- Every changed region was read in the CURRENT tree (other lanes have since
  edited the same files: the flag registry now has 5 entries; the static planner
  gained per-language passes, fonts and media), with its call sites and
  declarations: `CooperativeCancellationCheckpoint`, `LocalStaticBuildWriter.write`,
  `DebugTestComposition`, `requireExactKeys`, `StaticBuildFinding.init`,
  `BuildSettingsResolution.warningsBlock`, `LocalBuildProfileCompiler.compile`,
  `MultiPageStaticBuildPlanner.plan/outputPath`, `PageCommandRegistry.prepare`,
  `DocumentSession.undo/commit`, `SiteForgeChromePalette`, `SettingsDraftNotice`,
  every switch over `LocalStaticBuildWriteError` (2, both exhaustive) and every
  use of `FeatureFlagID` / `FeatureFlagStore` (no `switch` over flags exists;
  `FeatureFlagID` is a struct).
- Never reviewed before: no `docs/reviews/` entry and no Nov 25 review covers
  batches 15–17, so there were no earlier review fixes to re-verify.

## Where batch 16's flag tests are (orchestrator request, 7:55 PM)

`Tests/SiteForgeTests/SupportSettingsTests.swift` (now readable, 25 tests) has
no feature-flag references. Batch 16 put its two flag tests in
`CanvasSettingsTests` (`testFeatureFlagRegistryIdentifiersOwnersAndRemovalDatesAreValid`,
`testFeatureFlagStoreDraftApplyCancelPersistenceLaunchOverrideAndCorruptRecovery`).
They validate every registry entry (identifier, owner, requirement, removal date
not passed) but exercise the store only with a synthetic `test.sample` flag.
`PersistedHistoryTests` (lane E) asserts the `siteLanguages` definition's
requirement IDs and summary. Missing: per shipped flag default, toggling,
persistence and launch-argument precedence. Added
`testFeatureFlagRegistryEveryShippedFlagDefaultsTogglesPersistsAndYieldsToLaunchArguments`
(all 5 flags: default on, off and back on independently, reopen, launch
argument for its own flag only, Restore Defaults stores nothing, unknown
identifier off and not draftable; the test fails if a flag is added without
being listed). Gating: `presentProjectComparison` and `presentComponentLibraries`
read `FeatureFlagStore.shared` (not injectable, and changing it in a unit test
would write the host's standard UserDefaults); the other gates
(`export.zip-archive`, `versions.named-snapshots`, `localization.site-languages`,
the menu items) are SwiftUI view conditions. Those can only be proven by UI
tests (see Remaining work 1). The pending-draft notice now covers feature
drafts (fix 10) with an assertion in
`SupportSettingsTests/testGlobalSettingsNavigationAndDraftNoticeHaveNoProjectScope`.

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/CommandKernel.swift` | `PageCommandRegistry.prepare` (`.duplicate` / `.duplicateNamed`) | The copy's website metadata entry was rebuilt from title/description/indexing only, so duplicating a page silently dropped its custom code. | Pass `customCode: original.customCode`. | SF-1107-005: duplication preserves the result. |
| 2 | `SiteForge/WorkspaceShellView.swift` | `WebsiteSettingsView.pageForm` (**Use website defaults**) | Replaced the page draft with `PageDraft()`, which since batch 17 also erased the page's custom code (another section). | Keep `headHTML`/`bodyHTML`/`css`; reset search fields only. | Draft data loss. |
| 3 | `SiteForge/WorkspaceShellView.swift` | `customCodeSection` notice | Page notice read "added to this page, after the website's code, of the built site". | Scope strings carry "of the built site". | Wording. |
| 4 | `SiteForge/CanvasRendererCore.swift` | `StaticBuildCompiler.customCodeFindings` | One project-level `custom-code-script`; did not identify which block holds the script. | One finding per affected block: site without output path, page with its output file; sorted. | SF-1107-004 stable identity. |
| 5 | `SiteForge/SupportSettings.swift` | `FeatureFlagID.init?(_:)` | Pattern ended with `$`, which in ICU also matches before a final line break: `"export.zip\n"` was valid (also when decoding the saved record). | End anchor `\z`. | SF-1803-001/004. |
| 6 | `SiteForge/CanvasRendererCore.swift` | `StaticExportTarget`, `StaticSiteZipArchive`, `writeZipArchive` | "Unsupported capabilities are reported before build" not met; oversized plans were refused only after assembling the archive. | `unsupportedReason(for:)`, `canArchive(_:)`, `archivedByteCount(_:)`; writer refuses before allocating. | Partial feature finished. |
| 7 | `SiteForge/WorkspaceShellModel.swift`, `SiteForge/BrowserPreview.swift` | `writeStaticBuild`, `BrowserPreviewController.export` | No export diagnostics (SF-1209-001/008). | `StaticExportDiagnostic` on success and failure of the current request. | Partial feature finished. |
| 8 | `SiteForge/WorkspaceShellModel.swift` | `writeStaticBuild` message switch | A zip over a folder said "Choose a safe local folder…". | Target-aware `.unsafeDestination` message. | Specific recovery (SF-1209-004). |
| 9 | `Tests/SiteForgeTests/CanvasSettingsTests.swift` | `testFeatureFlagStoreDraftApplyCancel…` | "Release ignores launch arguments" passed no argument, proving nothing. | Passes `-SiteForgeFeature.test.sample NO` with `enabled: false`. | Strengthened. |
| 10 | `SiteForge/SupportSettings.swift` | `SettingsDraftNotice`, `SiteForgeSettingsRootView` | Unapplied feature choices were not a pending draft: no window notice, **Cancel Drafts** left them. | `featuresDirty:` (default false) lists Advanced; root passes `features.isDirty`; Cancel Drafts cancels a dirty feature draft. Built by appends, not a 4-term literal chain. | SF-1803-002 previews distinct from committed state. |
| 11 | `Tests/SiteForgeTests/PersistedHistoryTests.swift` | `testCustomCodeIsStrictVersionedSchemaGatedUndoableAndRemovedWithItsPage` | `try session.undo(); XCTAssertEqual(session.document, before)` cannot pass: `DocumentSession.commit` gives the undo a new revision. | Compare with the revision normalized (`var undone = session.document; undone.revision = before.revision`). | Test was wrong; assertion is still whole-document. |

Checked and found correct (no change): ZIP header layout, CRC-32 table and check
value, little-endian writer (`Swift.withUnsafeBytes(of:)`), bounds-checked reader,
`catch StaticSiteZipArchive.ArchiveError.tooLarge`, stage → verify → promote with
cleanup on every path, both switches over `LocalStaticBuildWriteError`,
`@MainActor` test classes for every `FeatureFlagStore` / `WorkspaceShellState` use,
`@ObservedObject var features: FeatureFlagStore = .shared` (same pattern as
`ExperimentalTestingStore.shared`), `FeatureFlagOverrides` exact keys and versions,
`FeatureFlagDate` leap years, `CustomCodeBlock` exact keys and validation,
`PageWebsiteMetadata` optional key and null refusal, `WebsiteMetadata` v1/v2/v3 key
sets and page-code-only-in-v3, schema-27 gate condition, custom code in every
language pass and item/list page, Browser Preview `includesCustomCode: false` on
both overloads, default release policy `errorsOnly` (custom code test `canWrite`
holds), Static Release minifies CSS only, page removal / snapshot restore /
version comparison carry `websiteMetadata` whole.

## Features finished

- **SF-1209 export target adapter contract and diagnostics (OD-042, ADR-0145).**
  Model `StaticExportTarget.unsupportedReason(for:)` with
  `StaticSiteZipArchive.canArchive/archivedByteCount`; writer refuses oversized
  plans before allocating; **Build Zip Archive…** (`build.writeZip`) and
  **Export Zip…** (`preview.website.exportZip`) disabled with the reason as help
  and accessibility hint (still behind `export.zip-archive`);
  `StaticExportDiagnostic` + `LocalStaticBuildWriteError.diagnosticCategory`,
  published as `WorkspaceShellState.lastStaticExportDiagnostic` and
  `BrowserPreviewController.lastExportDiagnostic`. Tests: success, oversized
  refusal with nothing staged, refused replacement leaves the archive unchanged,
  project and history unchanged, diagnostics value-free. Export never mutates
  the project, so no undo/redo applies (asserted).
- **SF-1803 feature drafts in the Settings pending-draft notice (OD-047, ADR-0145).**
- Not finished here: one hashed runtime script (plan E2, SF-1205, blocked:
  `Tests/Tooling/flow_runtime_browser.py`, `test_flow_runtime_browser.py`,
  `docs/TESTING.md` unreadable; lane E item); publishing/domains/rollback
  (SF-1210, deferred by OD-042).

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-1209-001 Authoritative state | Partial | Typed `StaticExportTarget`, stable raw values, explicit default `.folder`; project never rewritten (tests). Not saved in the project → OD-145. |
| SF-1209-002 Create and modify | Met | Export Zip… / Build Zip Archive…, zip-only save panel; `testBrowserPreviewZipExportUsesTheSuccessfulPreviewPlan`, `testCheckWebsiteZipArchiveTargetWritesThePlanAndLeavesTheProjectUnchanged`. |
| SF-1209-003 Resolution rules | Met | Same immutable plan per target; deterministic stored ZIP; `unsupportedReason(for:)` before writing; `testZipExportArchiveIsDeterministicStoredAndRoundTripsEveryPlanFile`, `testZipExportTargetReportsUnsupportedPlansBeforeWritingWithValueFreeDiagnostics`. |
| SF-1209-004 Failure and recovery | Met | Stage/verify/promote, stale, cancelled, unsafe, existing destination, permission/space, target-specific messages; writer test + new tests. |
| SF-1209-005 History and persistence | Met | No content mutation; document and history unchanged after export. |
| SF-1209-006 Accessible operation | Partial | Identifiers, keyboard-reachable buttons, announced Check Website status, reason as hint. No menu/command-registry entry; no UI test. |
| SF-1209-007 Performance and scale | Partial | Actor workers, per-entry cancellation, oversized plans refused without allocation; archive still assembled in memory, no progress fraction or large-fixture timing test. |
| SF-1209-008 Diagnostics and tests | Partial | `StaticExportDiagnostic` + unit/integration tests; no UI test. |
| SF-1803-001 Authoritative state | Met | App-scoped by ADR-0036 (flags must not fork project schema); typed `\z`-anchored IDs, owner and removal date, versioned exact-key record; omitted vs explicit distinct. |
| SF-1803-002 Create and modify | Met | Draft/Apply/Cancel/Use Default/Restore Defaults, "not applied yet", window pending-draft notice (fix 10). |
| SF-1803-003 Resolution rules | Met | Launch argument (debug) → this Mac → default with source shown; per-flag test. |
| SF-1803-004 Failure and recovery | Met | Unreadable/other-version record ignored with a finding; unknown valid IDs kept; unknown IDs off. |
| SF-1803-005 History and persistence | Met | Not content; one atomic record per Apply; reopen tests for every shipped flag. |
| SF-1803-006 Accessible operation | Partial | Labeled toggles with identifiers, Escape cancels; no UI test. |
| SF-1803-007 Performance and scale | Met | Five flags, linear resolution. |
| SF-1803-008 Diagnostics and tests | Partial | `FeatureFlagDiagnostic`; 3 unit tests + notice assertion; gating of each menu/command needs UI tests. |
| SF-1107-001 Authoritative state | Met | `CustomCodeBlock` exact keys; website metadata v3; schema-27 gate; page key only when set. |
| SF-1107-002 Create and modify | Partial | Site and page Custom Code in the Website Settings draft; "use approved runtime APIs" has no API surface (OD-041 approves none). |
| SF-1107-003 Resolution rules | Met | Site then page in head/style/body, stated in the notice; Preview exclusion finding. |
| SF-1107-004 Failure and recovery | Met | Invalid code refused with explanation; findings name the block (fix 4). |
| SF-1107-005 History and persistence | Met | One undoable `setWebsiteMetadata`; page removal; page duplicate copies (fix 1); snapshots and comparison. |
| SF-1107-006 Accessible operation | Partial | Labeled monospaced editors with identifiers; no UI test. |
| SF-1107-007 Performance and scale | Met | 64 KiB per field; linear emission. |
| SF-1107-008 Diagnostics and tests | Partial | Value-free findings; unit tests (strictness, undo, removal, duplicate, output, preview exclusion); no UI test. |

Totals: Met 15, Partial 9, Missing 0.

## Remaining work (blocked only)

1. UI tests for Export Zip…, Build Zip Archive…, Settings → Advanced → Features
   (including that each of the 5 flags hides its menu item or sheet when off) and
   the Custom Code sections. Blocked: no Mac to run them and record timings in
   `scripts/ci-ui-timings.txt`; `.github/workflows/ci.yml` and `docs/TESTING.md`
   are unreadable, so CI selection rules cannot be checked.
2. Saving a preferred export target in the project and a File-menu command for
   zip export (SF-1209-001/006). Blocked on OD-145.
3. One hashed runtime script (OD-042, SF-1205, plan E2). Blocked: harness files
   unreadable (lane E item).
4. Publishing, domains, rollback (SF-1210). Deferred by OD-042.

### OD-145 — Saving the export target (proposed)

- Status: Open (proposed by Code Forge lane V06, 2026-11-26).
- Affected requirements: SF-1209-001, SF-1209-006.
- Recommended default: keep the export target a per-export choice (folder or zip
  button), never stored in the project, so core project data is not rewritten for
  a target; revisit with publishing adapters (SF-1210), which need saved target
  configuration.
- Alternative: store a preferred target in `ProjectPreferences.build` and add a
  File ▸ Export Website as Zip… command bound to it.
- Tradeoff: storing it is a project-preferences schema change with migration and
  UI-test surface; not storing it leaves SF-1209-001 partial.
- Safe temporary assumption: per-export choice; no stored field.

## Intended plan / OD status-line changes (for the coordinator)

- OD-042 status line, append: `Lane V06 review (2026-11-26): zip adapter re-read against declarations; capability check before export (StaticExportTarget.unsupportedReason(for:); the writer refuses oversized plans before allocating), value-free export diagnostics (StaticExportDiagnostic, SF-1209-008) and a Check Website zip test added (ADR-0145). Saving a preferred target is OD-145. Still unverified.`
- OD-041 status line, append: `Lane V06 review (2026-11-26): page duplicate now copies page custom code; Use website defaults keeps custom code; custom-code-script names the page output file; undo assertion fixed for the new revision (ADR-0145). Still unverified.`
- OD-047 status line, append: `Lane V06 review (2026-11-26): FeatureFlagID end anchor fixed (\z); feature drafts shown in the Settings pending-draft notice and cancelled by Cancel Drafts; per-flag test for all 5 shipped flags; release-build launch-argument test strengthened (ADR-0145). Still unverified.`
- New OD-145 as above (Status: Open; recommended default: per-export choice, not stored).
- DEVELOPMENT_PLAN lane V table, V06 row: `done (V06, ADR-0145, OD-145 proposed; 11 fixes; SF-1209 capability check + export diagnostics and SF-1803 draft notice finished; remaining blocked: UI tests (no Mac), OD-145, E2, SF-1210)`.

## New and changed test selectors

New:

```
SiteForgeTests/CanvasRendererTests/testZipExportTargetReportsUnsupportedPlansBeforeWritingWithValueFreeDiagnostics
SiteForgeTests/InsertionModelTests/testCheckWebsiteZipArchiveTargetWritesThePlanAndLeavesTheProjectUnchanged
SiteForgeTests/PersistedHistoryTests/testCustomCodeIsCopiedWithADuplicatedPageInOneUndoableStep
SiteForgeTests/CanvasSettingsTests/testFeatureFlagRegistryEveryShippedFlagDefaultsTogglesPersistsAndYieldsToLaunchArguments
```

Changed (assertions added or corrected, none removed):

```
SiteForgeTests/CanvasRendererTests/testBrowserPreviewZipExportUsesTheSuccessfulPreviewPlan
SiteForgeTests/CanvasRendererTests/testCustomCodeIsWrittenVerbatimToBuildsAndLeftOutOfPreview
SiteForgeTests/CanvasSettingsTests/testFeatureFlagRegistryIdentifiersOwnersAndRemovalDatesAreValid
SiteForgeTests/CanvasSettingsTests/testFeatureFlagStoreDraftApplyCancelPersistenceLaunchOverrideAndCorruptRecovery
SiteForgeTests/PersistedHistoryTests/testCustomCodeIsStrictVersionedSchemaGatedUndoableAndRemovedWithItsPage
SiteForgeTests/SupportSettingsTests/testGlobalSettingsNavigationAndDraftNoticeHaveNoProjectScope
```

No UI tests were added, so `scripts/ci-ui-timings.txt` is unchanged. Test names
are unique per class (checked for all 5 touched test files).

## Suggested first checks for Codex

1. `StaticExportDiagnostic(target:documentID:plan:duration:failure:)` inside the
   `Task` closures of `WorkspaceShellState.writeStaticBuild` and
   `BrowserPreviewController.export` (`started.duration(to: .now)`, main-actor capture).
2. `let zipIssue = state.staticBuildCompilation?.plan.flatMap { … }` inside the
   `InspectorActionLayout` builder and `controller.plan.flatMap` in
   `BrowserPreviewPanel` (`let` in a result builder; optional-chain type `String?`).
3. `FeatureFlagID` pattern `#"…+\z"#` with `.regularExpression` (ICU `\z`); every
   registered literal still valid.
4. `Set<String?>` and `.sorted(by:)` in `StaticBuildCompiler.customCodeFindings`;
   About page output path `about.html`.
5. `PageWebsiteMetadata.init(pageID:title:description:allowsIndexing:customCode:)`
   in the `CommandKernel` page duplicate.
6. `SettingsDraftNotice(appearanceDirty:canvasDirty:projectDirty:featuresDirty:)`
   and `features.isDirty` / `features.cancel()` in `SiteForgeSettingsRootView`.
7. Runtime of the 65,536-file plan in the new zip capability test.
8. `PageDraft(headHTML:bodyHTML:css:)` memberwise call in `WebsiteSettingsView.pageForm`.
9. Carried over: `TextEditor` modifiers on the deployment target; Settings →
   Advanced layout in UI tests (`settings.experimental.enabled`).

## Out-of-area issues (not fixed)

- `PersistedHistoryTests`: whole-document `XCTAssertEqual(session.document, X)`
  right after `session.undo()`, which cannot pass because `DocumentSession.commit`
  gives the undo a new revision (the Codex-repaired tree at `RP-2026-11-26-07` has
  no such assertion). Tests: `testCollectionImportReadsCSVAndJSONMapsFieldsAndChecksEveryRow`,
  `testCollectionImportTabReadsAFileMapsColumnsAndAddsToTheDraftAsOneUndoableChange`,
  `testCollectionListRecordIsStrictBoundedAndUndoable`,
  `testCollectionTemplateRecordIsStrictUndoableAndPreviewedLive`,
  `testCollectionsAreStrictSchemaGatedUndoableAndPersistedInHistory`,
  `testSiteLanguagesAreStrictSchemaGatedUndoableAndPersistedInHistory`,
  `testSiteLanguagesSheetCommitsDraftsUndoablyAndCountsRemovedTranslations`,
  `testSiteTranslationInspectorEditsOneElementUndoablyAndListsItsMissingTranslations`,
  `testSiteTranslationReportAndLanguageChangesKeepTranslationsConsistent`,
  `testSiteTranslationsAreStrictUndoablePersistedAndResolvedPerLanguage`.
  Same fix as fix 11 (normalize `revision`). Left to the owning lanes (collections,
  localization) to avoid editing their tests concurrently.
- Lane H / SF-1211-003: under `warningsBlockRelease`, `custom-code-unvalidated` is a
  warning that can only be cleared by deleting the custom code, so a project with
  custom code can never be written with Static Release under that policy.
- Plan E2 (hashed runtime script) remains blocked on unreadable harness files.
