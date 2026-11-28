# Lane V17 review — undo-revision test defect and custom code under the strict release policy (2026-11-26)

Reviewer: Code Forge lane V17 (owner tag `lane-V17`). Verification by reading only:
no Swift toolchain, no compiler, no test run on this Windows copy. Every item
below is **unverified until Codex compiles and runs it**.

## Scope

- Out-of-area issues listed by lane V06 (`docs/reviews/LANE-V06-review-2026-11-26.md`,
  section "Out-of-area issues"): (1) whole-document equality right after Undo in
  `PersistedHistoryTests`; (2) lane H / SF-1211-003: custom code can never be
  released under `warnings-block-release`.
- Decisions: OD-041 (custom code, ADR-0037), OD-042 / OD-120 (build settings,
  budgets, release policy, ADR-0122).
- Files changed: `SiteForge/DocumentModel.swift`, `SiteForge/CanvasRendererCore.swift`,
  `SiteForge/WorkspaceShellModel.swift`, `SiteForge/WorkspaceShellView.swift`,
  `Tests/SiteForgeTests/PersistedHistoryTests.swift`, `Tests/SiteForgeTests/CanvasSettingsTests.swift`,
  `docs/architecture-decisions/ADR-0037-custom-code.md` (Amendment 1).
- Declarations read for every changed call: `DocumentSession.undo/redo/commit`
  (`CommandKernel.swift`), `CanonicalDocument` (synthesized `Equatable`, `var revision`),
  `BuildProfileSettings`, `BuildSettingID`, `ProjectPreferences`, `ProjectPreferencesCommandRegistry.prepare`,
  `BuildSettingsResolution`, `StaticBuildBudgetAudit.releasePolicyFinding`, `StaticBuildRepairAction`,
  `StaticBuildCompiler.compile`/`customCodeFindings`, `StaticBuildCompilation.canWrite/redactedSummary`,
  `StaticBuildFindingSeverity`, `WorkspaceShellState.saveBuildSettings/buildRepairAction/applyBuildRepair/recordBuildSettings/commitProjectPreferences/authoringDocument`,
  `StaticBuildFindingRepairRow`, the Check Website build-settings view, `WebsiteMetadata`,
  `PageWebsiteMetadata`, `CustomCodeBlock`, `ProjectComparer` (build settings compared whole),
  `PackagedSiteTemplate` and snapshot restore (project preferences copied whole),
  `ProjectSettingsStore` (keeps `build` on Apply/Reset).
- Read-checks run: forge_io `check()` (balance + duplicate members) on every changed
  file after every edit: `[]`; `symcheck.py` and `labelcheck.py` adapted to the diff
  `RP-2026-11-26-V00 → now` of the six Swift files: no finding in lane V17 lines (all
  reported items are Foundation/SwiftUI false positives in other lanes' lines);
  `icloud_duplicates()` `[]`; `foreign_changes(30)` `[]` before the first write and
  before this report.

## Item 1 — Undo/Redo give the document a new revision (test defect)

Confirmed in the implementation: `DocumentSession.undo()` calls
`commit(entry.inverse, diagnosticName: .undo, …)`, and `commit` always sets
`draft.revision = committedDocument.revision + 1` (redo the same). `CanonicalDocument`
has a synthesized `Equatable` that includes `revision`. So
`XCTAssertEqual(session.document, X)` after an Undo/Redo can never pass when `X` was
captured before that Undo/Redo, however exact the restore is.

Fix (copied from V06's batch 17 fix in
`testCustomCodeIsStrictVersionedSchemaGatedUndoableAndRemovedWithItsPage`):
`var undone = session.document; undone.revision = <reference>.revision` then
`XCTAssertEqual(undone, <reference>)`. The assertion stays whole-document; only the
revision, which Undo is required to advance, is normalized. Variable names are unique
per test (`undone`, `undoneRemoval`, `undoneSwap`, `undonePromotion`, `undoneLanguagesOff`).

Whole `Tests/` tree searched (all `.swift` files): every whole-document
`XCTAssertEqual` whose reference was captured before an `undo()`/`redo()` (one-line,
multi-line and two-variable forms). Only `PersistedHistoryTests.swift` has the defect;
all other hits already normalize the revision (`ClipboardTransferTests`,
`CommandKernelTests` 2177–2184/5009–5171, `TransformModelTests` `withRevision`) or
compare a reopened copy of the current document. No localization test had been fixed
by lane V11 when the edit was applied (read and edited in one locked call).

| Test (`PersistedHistoryTests`) | Assertion(s) fixed |
|---|---|
| `testCollectionsAreStrictSchemaGatedUndoableAndPersistedInHistory` | after Undo vs `blank` |
| `testSiteLanguagesAreStrictSchemaGatedUndoableAndPersistedInHistory` | after Undo vs `blank` |
| `testSiteTranslationsAreStrictUndoablePersistedAndResolvedPerLanguage` | after Undo vs `localized` |
| `testSiteTranslationReportAndLanguageChangesKeepTranslationsConsistent` | 4 × after Undo vs `translated` (removal, new default swap, promotion, languages off) |
| `testSiteLanguagesSheetCommitsDraftsUndoablyAndCountsRemovedTranslations` | after Undo vs `blank`; after Undo vs `translated`; **two more found by the tree search**: the invalid and unchanged drafts compared with `translated` after that Undo (now `let restored = session.document` right after the Undo and exact equality with `restored`, which also proves refused drafts do not advance the revision); after Undo vs `edited` |
| `testSiteTranslationInspectorEditsOneElementUndoablyAndListsItsMissingTranslations` | after Undo vs `localized` |
| `testCollectionTemplateRecordIsStrictUndoableAndPreviewedLive` | after Undo vs `document` |
| `testCollectionListRecordIsStrictBoundedAndUndoable` | after Undo vs `document` |
| `testCollectionImportReadsCSVAndJSONMapsFieldsAndChecksEveryRow` | after Undo vs `document` |
| `testCollectionImportTabReadsAFileMapsColumnsAndAddsToTheDraftAsOneUndoableChange` | after Undo vs `document` |

17 assertion lines in 10 tests; none removed or weakened.

## Item 2 — custom code under "Block Static Release on warnings" (code defect)

Defect: `custom-code-unvalidated` and `custom-code-script` are warnings that cannot be
repaired (custom code is never checked), so under `warnings-block-release` the
`release-policy-warnings` error stopped Static Release for every project with custom
code unless the code was deleted.

Fix (ADR-0037 Amendment 1; inside OD-041 and OD-042/OD-120; schema 27, WebsiteMetadata
v3, persisted history v4, no `CanonicalDocument` key):

- `BuildProfileSettings.reviewedCustomCodeDigest` (in `ProjectPreferences.build`;
  strict key, omitted when unset, null refused; record version stays 1, older files
  unchanged) + `BuildSettingID.customCodeReview` (`project.build.customCodeReview`) +
  `keepingCustomCodeReview`.
- `CustomCodeReview.digest(_:)` (SHA-256 of site and page blocks with page identity,
  field names and byte lengths; never stores code) and `status(_:)`
  (`noCustomCode`/`notReviewed`/`reviewed`/`changedSinceReview`). A change to any block
  changes the digest, so the review ends without rewriting the project.
- `StaticBuildCompiler.customCodeFindings`: while reviewed, both findings keep their
  codes/outputs but have severity `information` (still shown; explanation says it is
  marked as reviewed) and so no longer count for `release-policy-warnings`; changed
  code is a warning again with "It changed after it was marked as reviewed."
- Existing H03 repair mechanism: `StaticBuildRepairAction.acknowledgeCustomCode(digest:)`
  ("Mark Custom Code as Reviewed", identifier `acknowledge-custom-code`, accessibility
  hint) offered on an unreviewed `custom-code-unvalidated` finding;
  `action(for:report:settings:profile:customCodeDigest:)` (new defaulted parameter);
  `WorkspaceShellState.buildRepairAction(for:)` passes the checked document's digest;
  `applyBuildRepair` refuses a digest that no longer matches (`stale-context`, status
  names the repair, announced) and otherwise saves one undoable
  `document.projectPreferences.set` via `saveBuildSettings` (operation
  `review-custom-code`, value-free `BuildSettingsDiagnostic`).
- Check Website → Build settings: review state text (`build.settings.customCodeReview`)
  and **Clear Custom Code Review** (`build.settings.customCodeReview.clear`, a draft);
  **Use SiteForge Defaults** keeps the review and is disabled when nothing else is set.

| # | File | Symbol | Defect | Fix |
|---|---|---|---|---|
| 1 | `Tests/SiteForgeTests/PersistedHistoryTests.swift` | 10 tests above | Whole-document equality after Undo can never pass (new revision) | Normalize `revision` before comparing (V06 approach) |
| 2 | `SiteForge/CanvasRendererCore.swift` | `StaticBuildCompiler.customCodeFindings` | Custom code warnings block strict Static Release forever | Reviewed code reported as information |
| 3 | `SiteForge/DocumentModel.swift` | `BuildProfileSettings`, `BuildSettingID`, new `CustomCodeReview` | No way to record a review | Digest in build settings; status helper |
| 4 | `SiteForge/CanvasRendererCore.swift` | `StaticBuildRepairAction` | No repair for unrepairable custom code warnings | `.acknowledgeCustomCode(digest:)` |
| 5 | `SiteForge/WorkspaceShellModel.swift` | `buildRepairAction(for:)`, `applyBuildRepair(_:)` | — | Digest passed; stale review refused; one undoable save |
| 6 | `SiteForge/WorkspaceShellView.swift` | build settings view | Review not visible; defaults reset would drop it | Review row, Clear button, defaults keep the review |

Requirement status (this item):

| Requirement | Status | Evidence |
|---|---|---|
| SF-1107-001 Authoritative state | Met | Code stays in WebsiteMetadata v3; review is a digest in project build settings. |
| SF-1107-004 Failure and recovery | Met | Findings always named; reviewed → information; changed → warning with reason. |
| SF-1107-005 History and persistence | Met | One undoable preferences edit; reopen; snapshots/comparison carry build settings. |
| SF-1107-006 Accessible operation | Partial | Labeled buttons with identifiers and hints, Tab/Space like other repairs; no UI test (no Mac). |
| SF-1107-008 Diagnostics and tests | Partial | Value-free diagnostic and unit test; no UI test. |
| SF-1211-002 One-step repair | Met | Repair action beside the finding. |
| SF-1211-003 Release policy | Met | Reviewed code no longer blocks; unreviewed/changed still does; Development never blocked. |
| SF-1211-008 Diagnostics | Met | `review-custom-code`, `project.build.customCodeReview`, no values. |

Totals: Met 6, Partial 2, Missing 0.

## Remaining work (blocked only)

1. UI test for **Mark Custom Code as Reviewed** and the Build settings review row /
   **Clear Custom Code Review**: blocked — no Mac to run UI tests and record
   `scripts/ci-ui-timings.txt` (same blocker as V06 remaining item 1).

## Intended doc changes for the coordinator

- OD-041 status line, append: `Lane V17 (2026-11-26): reviewed custom code can be released under Block Static Release on warnings — Mark Custom Code as Reviewed stores a SHA-256 of the code in ProjectPreferences.build (reviewedCustomCodeDigest), findings stay as information, any change to the code ends the review (ADR-0037 Amendment 1). Still unverified.`
- OD-042 status line, append: `Lane V17 (2026-11-26): release-policy repair acknowledgeCustomCode (H03 mechanism) and BuildSettingID project.build.customCodeReview (ADR-0037 Amendment 1). Still unverified.`
- ADR-0122: add under Decision → Model: "`reviewedCustomCodeDigest` (ADR-0037 Amendment 1)" and under repairs: "`acknowledgeCustomCode(digest:)`".
- DEVELOPMENT_PLAN lane V table, V17 row: `done (V17; undo-revision assertions fixed in 10 PersistedHistoryTests tests (17 lines); custom code review for the strict release policy, ADR-0037 Amendment 1; remaining blocked: UI test (no Mac))`.
- Activity log: lane V17 entry with the two items above.

## New and changed test selectors

New:

```
SiteForgeTests/CanvasSettingsTests/testCustomCodeReviewUnblocksStrictStaticReleaseUntilTheCodeChanges
```

Changed (assertions corrected, none removed):

```
SiteForgeTests/PersistedHistoryTests/testCollectionsAreStrictSchemaGatedUndoableAndPersistedInHistory
SiteForgeTests/PersistedHistoryTests/testSiteLanguagesAreStrictSchemaGatedUndoableAndPersistedInHistory
SiteForgeTests/PersistedHistoryTests/testSiteTranslationsAreStrictUndoablePersistedAndResolvedPerLanguage
SiteForgeTests/PersistedHistoryTests/testSiteTranslationReportAndLanguageChangesKeepTranslationsConsistent
SiteForgeTests/PersistedHistoryTests/testSiteLanguagesSheetCommitsDraftsUndoablyAndCountsRemovedTranslations
SiteForgeTests/PersistedHistoryTests/testSiteTranslationInspectorEditsOneElementUndoablyAndListsItsMissingTranslations
SiteForgeTests/PersistedHistoryTests/testCollectionTemplateRecordIsStrictUndoableAndPreviewedLive
SiteForgeTests/PersistedHistoryTests/testCollectionListRecordIsStrictBoundedAndUndoable
SiteForgeTests/PersistedHistoryTests/testCollectionImportReadsCSVAndJSONMapsFieldsAndChecksEveryRow
SiteForgeTests/PersistedHistoryTests/testCollectionImportTabReadsAFileMapsColumnsAndAddsToTheDraftAsOneUndoableChange
```

Also affected without edits (assert codes only, still valid):
`SiteForgeTests/CanvasRendererTests/testCustomCodeIsWrittenVerbatimToBuildsAndLeftOutOfPreview`,
`SiteForgeTests/CanvasRendererTests/testBuildSettingsResolveBudgetsPerFileReportAndReleasePolicy`
(the exact JSON string omits the new key when unset),
`SiteForgeTests/CanvasSettingsTests/testBuildSettingsSaveUndoRedoRepairsAndStaleReview`
(settingIDs list unchanged; new case is last in `allCases`). No UI tests added.

## Suggested first checks for Codex

1. The new test's precondition `plain.canWrite` (a blank project + About page with
   `allowsIndexing: false` under `warnings-block-release` must produce no warning); if
   another warning appears, the printed codes name it.
2. `CustomCodeReview.digest`: nested `func append` mutating the captured `bytes`,
   `let fields: [(String, String?)]`, `Data(header.utf8)`, `SHA256.hash(data:).map { String(format: "%02x", $0) }`.
3. `let reviewNote: String = switch review { … }` and the `severity` ternary in
   `customCodeFindings`; exhaustive switches over `StaticBuildRepairAction` (title, hint,
   identifier, `applyBuildRepair`) and `BuildSettingID` (title, `changedSettingIDs`).
4. `guard digest == CustomCodeReview.digest(authoringDocument.websiteMetadata)` (String vs
   String?) and `recordBuildSettings("review-custom-code", started:failure:settings:)` in
   `applyBuildRepair`.
5. `@ViewBuilder private var customCodeReview` (if-let with two views) and
   `update { $0 = $0.keepingCustomCodeReview }` in the build settings view; its VStack
   now has 10 direct children.
6. `XCTAssertNotEqual(CustomCodeReview.digest(moved), digest)` (Optional vs non-optional).
7. The 17 `undone…` lines: `var` names unique per test.

## Out-of-area issues (not fixed)

- The `release-policy-warnings` repair text still lists only "Repair the warnings, choose
  the Development profile, or choose Block on errors only"; the custom code finding row
  carries its own button, so no change was made (wording owner: lane H).
