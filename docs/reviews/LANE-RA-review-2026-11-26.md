# Lane R review A (lane-RA) — 2026-11-26

Reviewer: Code Forge lane R, reviewer A. Static review only (no Swift compiler on this PC); every fix was
re-read against the declarations it calls. Project settings checked from the restore-point copy of
`SiteForge.xcodeproj/project.pbxproj`: **Swift 6.0 language mode, `SWIFT_STRICT_CONCURRENCY = complete`,
macOS 14.0** — so Sendable problems are errors, not warnings.

## Scope

| Batch | Feature | ADR | Modules |
|---|---|---|---|
| 18 part 1 (lane E) | Named snapshots model, `ProjectSnapshots`, `DocumentLifecycleController` snapshot API | ADR-0038 | SF-1301 |
| E01 (lane E) | Snapshots sheet, `WorkspaceShellState` snapshot block, flag `versions.named-snapshots` | ADR-0039 | SF-1301 |
| A02 | Version comparison: `ProjectComparisonSource`, `ProjectComparer`, `ProjectComparisonModel`, `ProjectComparisonSheet` | ADR-0040 | SF-1306 |
| A03 | Shared component libraries: `ComponentLibrar*` types, `ComponentLibraries`, lifecycle API, `DocumentSession.commitGuard`, `ComponentLibrariesSheet` | ADR-0041 | SF-0906 |
| A04 | Flags `versions.compare`, `components.shared-libraries` | ADR-0040/0041 | SF-1803 (flag part) |

Files reviewed: `SiteForge/ProjectPackage.swift` (snapshots, comparison, libraries — lines ~1059–3020),
`SiteForge/CommandKernel.swift` (`DocumentSession.commitGuard`, `execute`, `executeCoalescing`, `commit`),
`SiteForge/DocumentLifecycle.swift` (init guard install, snapshot and library API), `SiteForge/WorkspaceShellModel.swift`
(`projectComparisonRequest`, `presentProjectComparison`, `presentComponentLibraries`, snapshot block),
`SiteForge/WorkspaceShellView.swift` (sheets, `ProjectComparisonModel`, `ProjectComparisonSheet`,
`ComponentLibrariesSheet`, `ProjectSnapshotsSheet`, `SiteForgeCommands` save group), `SiteForge/SupportSettings.swift`
(`FeatureFlagID`, `FeatureFlagRegistry.definitions`), and the tests: `ProjectPackageTests`
(`testNamedSnapshotsAreStrictBoundedAndRoundTripThroughThePackage`,
`testComponentLibrariesExportImportReadOnlyUpdateCompareAndDetach`,
`testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded`), `DocumentLifecycleTests` (the
six snapshot/compare/library tests), plus the other-lane tests that call this code
(`PersistedHistoryTests/testSiteLanguagesAreStrictSchemaGatedUndoableAndPersistedInHistory`,
`ProjectResourceTests/testMediaModelIsStrictValidatedOmittedWhenEmptyAndUndoable`).

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/ProjectPackage.swift` | `ProjectComparer.compare` | Site languages were reported twice ("Languages" and "Site languages"); `PersistedHistoryTests/testSiteLanguagesAreStrictSchemaGatedUndoableAndPersistedInHistory` asserts exactly `["Languages"]` and would fail. | The duplicate "Site languages" entry was removed — **by another reviewer (lane-RE/RI, 18:26–18:27) while this review ran**; verified in the current text, "Languages" kept. | Test/implementation mismatch. Counted as found, fixed by a parallel reviewer. |
| 2 | `SiteForge/ProjectPackage.swift` | `ProjectComparer.compare` | Lane H's `ProjectPreferences.build` was folded into "Project preferences"; build-settings-only changes were not named. | "Project preferences" now covers the grid choices; a separate "Build settings" entry when `build` differs. | Brief special check (lane H); clearer review report. |
| 3 | `SiteForge/ProjectPackage.swift` | `ProjectComparer.compare` | Two versions differing only in the order of images, guides or color tokens, or in a page's `provenance`, gave an empty change list → `isIdentical == true` ("These versions are identical") although the documents differ. `sameUncomparedContent` aligns those arrays, so "Other project data" never fired. | When nothing else was listed and the documents still differ (revision ignored), one "Other project data" entry is added. | ADR-0040's "never hide a difference"; SF-1306-001/003. |
| 4 | `SiteForge/WorkspaceShellView.swift` | `ProjectComparisonModel.compare()` / `finish` | The `Task.detached` run sent `Result<ProjectComparison, Error>` (not Sendable: `any Error`) to the main actor with `await self?.finish(outcome, …)`. Under Swift 6 complete checking this is a likely "sending risks data races" error. | The detached closure now returns only Sendable values: `ProjectComparison?` and `(message: String, category: String)?` (both nil = cancelled). `finish(_:failure:generation:started:)` handles the three cases exactly as before (same phases, records, announcements). | Swift 6 compile safety; behaviour unchanged (test expectations of 2 cancelled records, "not-found", "same-source" still hold). |
| 5 | `SiteForge/ProjectPackage.swift` | `ComponentLibraries.updating` | After an update that drops a component, the record kept only the new version's IDs. Undo of the update restores the dropped component, but `status(of:in:)` filters by the record IDs, so the digest never matched the earlier version → `.changed` instead of `.earlier`. `testComponentLibrariesExportImportReadOnlyUpdateCompareAndDetach` asserts `.earlier(.initial)` after Undo and would fail. The restored item was also no longer read-only. | The updated record keeps every identity any imported version delivered (`definitionIDs`/`tokenIDs` = previous ∪ new, previous order first). Status, preview, update removal and the read-only guard all use that set. | Test/implementation mismatch; ADR-0041 "earlier known version (an update was undone)"; read-only rule after Undo. No format change (same keys). |
| 6 | `SiteForge/WorkspaceShellView.swift` | `ComponentLibrariesSheet.importedSection` | Every row's buttons were announced only as "Update…"/"Detach…" (ambiguous with several libraries). | `.accessibilityLabel("Update <name>")` / `"Detach <name>"`, like the Snapshots sheet rows. | SF-0906-006 small gap. |
| 7 | `Tests/SiteForgeTests/ProjectPackageTests.swift` | `testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded` | No coverage for fixes 2–3. | Asserts `["Project preferences", "Build settings"]` for a grid+build change and `["Other project data"]` for a provenance-only change. | Regression coverage. |
| 8 | `Tests/SiteForgeTests/ProjectPackageTests.swift` | `testComponentLibrariesExportImportReadOnlyUpdateCompareAndDetach` | No direct assertion of the record identity set. | Asserts `Set(record2.definitionIDs)` = v1 ∪ v2 definition IDs. | Regression coverage for fix 5. |
| 9 | `docs/architecture-decisions/ADR-0040-version-comparison.md`, `ADR-0041-shared-component-libraries.md` | Decision text | Out of date after fixes 2, 3, 5. | One sentence each updated. | Docs match code. |

Counts: 5 code defects found (1 fixed concurrently by another reviewer, 4 fixed here), 1 accessibility gap closed,
2 test methods extended, 2 ADRs updated. All edits through `forge_io.edit(owner="lane-RA")`; `check()` returned `[]`
after each; `foreign_changes(30)` was empty throughout.

### Verified, no change needed (special checks)

- **ProjectComparer coverage of every `CanonicalDocument` key** (`id, revision, creationKind, templateID, pages, guides,
  imageAssets, colorTokens, websiteMetadata, projectPreferences(+build), collections, fontAssets, localization,
  mediaAssets`): each has its own entry or is aligned in `sameUncomparedContent`; `creationKind`/`templateID` reach
  "Other project data"; `revision` is ignored by design.
- **Snapshot restore** (`ProjectSnapshots.restoreCommand`) covers pages, guides, image assets, color tokens, website
  metadata, project preferences (including `build`), collections, font assets, media assets and localization; creation
  kind/template/revision stay with the head. Missing resources are checked for images, fonts and media. Batch
  sub-commands are applied with `mutate` and validated once at the end, so the remove-all/insert-all order is safe
  (indexes stay in range; guides and metadata are re-checked after pages return).
- **`DocumentSession.commitGuard`**: passed only by `execute` and `executeCoalescing` (lane I) to `commit(…, check:)`;
  undo, redo and `jump(toStateAfter:)` pass none, so Undo/Redo can never be blocked. It runs after model validation and
  the component transition checks and throws only `CommandExecutionError.disabled`, which `commit`'s catch handles
  (document restored, `lastError`, diagnostic). With no `libraries/index-v1.json` member it returns after one
  `first(where:)` scan, so all existing tests and sessions without a controller (guard `nil`) are unaffected. The
  closure is created in the `@MainActor` init (same shape as the existing `authoringTransform` installs).
- `ComponentLibraries.importing` runs the command before the record exists (guard sees the old record); `updating`
  bypasses the guard for exactly its own command via `libraryGuardBypassed` + `defer`.
- Flags: identifiers match `FeatureFlagID`'s pattern; `FeatureFlagRegistry.issues(in:today:)` is empty until
  2027-03-31; `CanvasSettingsTests/testFeatureFlagRegistryIdentifiersOwnersAndRemovalDatesAreValid` checks all
  definitions without counting them.

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-1301-001 state | Met | `ProjectSnapshotIndex`/`ProjectSnapshotEntry` (format, version 1, exact keys, stable `ProjectSnapshotID`; no index member when empty). `testNamedSnapshotsAreStrictBoundedAndRoundTripThroughThePackage`. |
| SF-1301-002 create/modify | Met | Create/rename/delete/restore + Compare from the sheet (`ProjectSnapshotsSheet`, `WorkspaceShellState.compareSnapshotWithCurrent`). `testSnapshotsSheetCreatesRenamesRestoresKeepingCurrentHandsOffCompareAndRecoversDamagedStorage`. |
| SF-1301-003 resolution | Partial | Restore rules deterministic and documented (only changed parts; creation kind/template stay; keep-current first). No pre-restore preview of what changes other than via Compare. |
| SF-1301-004 failure/recovery | Partial | `ProjectSnapshotError` (corrupt, unsupported, mismatch, missingResource, unavailable…), Delete All recovery, nothing changes on failure (tests). Automatic snapshots + pruning (the module topic) not built (OD-043 approved named snapshots only). |
| SF-1301-005 history/persistence | Partial | Restore = one new undoable transaction, valid persisted history after reopen (`testNamedSnapshotsSaveReopenRestoreToANewHeadUndoAndRecover`). Snapshot-only changes are not in crash recovery (ADR-0038). |
| SF-1301-006 accessibility | Partial | Labels, identifiers, announcements, Return/Escape. No UI/accessibility test. |
| SF-1301-007 performance | Partial | Bounded (10 snapshots, 2 MiB, 75% budget). Encode/decode on the main actor; no performance fixture. |
| SF-1301-008 diagnostics/tests | Partial | `ProjectSnapshotDiagnosticRecord` (no names/IDs), unit + integration tests; no UI/performance tests. |
| SF-1306-001 state | Met | Derived, deterministic value types; change IDs are positions; report export. Fix 3 removes the false "identical". |
| SF-1306-002 create/modify (filter) | Met | `ProjectComparison.filtered(area:kind:query:)`, sheet filters; tests. |
| SF-1306-003 resolution (before/after) | Met | Identity matching, LIS moves vs recreation, before → after values; `testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded`. |
| SF-1306-004 failure/recovery | Met | notFound/corrupt with Delete All, cancellation, stale labelling, Try Again; `testCompareVersionsRunsOffTheMainActorIgnoresStaleRunsAndNeverEditsTheDocument`. |
| SF-1306-005 history/persistence | Met | Comparing never edits document or package (asserted); results labelled stale on new revisions. |
| SF-1306-006 accessibility | Partial | Combined row labels, identifiers, announcements, Escape/Return; no UI test. |
| SF-1306-007 performance | Partial | Detached run, 5,000-change bound, cancellation per page/256 nodes; no performance fixture; library update preview compares on the main actor. |
| SF-1306-008 diagnostics/tests | Partial | `ProjectComparisonDiagnosticRecord`; unit + integration tests; no UI/performance tests; rendered/visual diff not built. |
| SF-0906-001 state | Met | `ComponentLibraryFile`/`ComponentLibraryIndex` (formats, version 1, exact keys, `published` written as null), stable identities kept. |
| SF-0906-002 create/modify | Met | Export/import/update/detach; update reviewed before Apply. Both tests. |
| SF-0906-003 resolution | Met (after fix 5) | Status current/earlier/changed/missing; update preview with comparison and removed-component warning. |
| SF-0906-004 failure/recovery | Partial | Specific refusals (own library, already imported, identity conflict, images, library dependency, too large, corrupt + Remove All). Components using video/audio, translations, collection bindings or outside interaction targets fail with the generic `invalidContent`. |
| SF-0906-005 history/persistence | Partial | Import/update = one undoable command, read-only rule survives save/reopen (lifecycle test). Record-only changes (detach, export record) are not undoable and saved only with Save. |
| SF-0906-006 accessibility | Partial | Labels (row buttons fixed here), announcements, Escape; no UI test. |
| SF-0906-007 performance | Partial | 4 MiB file bound, 32 libraries, 16 versions; file read/decode on the main actor; no fixture. |
| SF-0906-008 diagnostics/tests | Partial | `ComponentLibraryDiagnosticRecord`; unit + integration tests; no UI test. |
| SF-1803 (A04 flags only) | Met for the flag part | Two registry entries with owner, dates, requirement IDs; menu items, Snapshots Compare button and `present…` entry points gated; registry validity test covers them. `ProjectSnapshotsSheet` reads the flag without observing it (see gaps). |

## Remaining gaps (easiest → hardest)

1. `ProjectSnapshotsSheet`: observe `FeatureFlagStore.shared` (`@ObservedObject private var features = FeatureFlagStore.shared`) so the Compare button follows a flag change while the sheet is open.
2. Disable Restore… (and library Import/Update) while a component variant is being edited (`variantEditingTarget != nil`), like `canEditLanguages`; today `authoringTransform` refuses the batch with its own message.
3. Specific export refusals in `ComponentLibraries.exporting` for video/audio (`CanonicalMediaPlayback.resolve`), translations, collection bindings and interaction targets outside the component (new `ComponentLibraryError` cases + both exhaustive switches), instead of `invalidContent`.
4. `ComponentLibraries.replacing`: an index over 256 KiB maps to `tooManyLibraries`; add a dedicated "record too large" message.
5. UI tests for the Snapshots, Compare Versions and Component Libraries sheets (Mac only; update `scripts/ci-ui-timings.txt`).
6. Move snapshot encode/decode (create/restore) and library file decode off the main actor with the existing detached pattern; add 100 / 10,000 / stress fixtures for comparison and restore.
7. Automatic snapshots with pruning (SF-1301-004 topic) — needs an owner decision (OD-043 approved named snapshots only).
8. Rendered/visual comparison with declared viewport, data and font context (SF-1306) — own slice.
9. Images, fonts and nested library dependencies inside libraries; live linking (OD-046 later slices).

## Intended OD status-line changes (do not edit `docs/OPEN_DECISIONS 2.md`; coordinator to apply)

- OD-043: append "Lane R review 2026-11-26 (lane-RA): comparison names build settings on their own and never shows two different versions as identical; comparison run passes only Sendable values to the main actor. Still unverified."
- OD-046: append "Lane R review 2026-11-26 (lane-RA): an update's record keeps every identity its versions delivered, so Undo of an update shows the earlier version and keeps it read-only; library row buttons name their library for VoiceOver. Still unverified."

## New/changed test selectors

Changed (new assertions):

```
SiteForgeTests/ProjectPackageTests/testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded
SiteForgeTests/ProjectPackageTests/testComponentLibrariesExportImportReadOnlyUpdateCompareAndDetach
```

Run as well (behaviour they assert depends on fixes 1, 4, 5):

```
SiteForgeTests/PersistedHistoryTests/testSiteLanguagesAreStrictSchemaGatedUndoableAndPersistedInHistory
SiteForgeTests/ProjectResourceTests/testMediaModelIsStrictValidatedOmittedWhenEmptyAndUndoable
SiteForgeTests/ProjectPackageTests/testNamedSnapshotsAreStrictBoundedAndRoundTripThroughThePackage
SiteForgeTests/DocumentLifecycleTests/testSnapshotRestoreCommandIsOneNewUndoableTransaction
SiteForgeTests/DocumentLifecycleTests/testNamedSnapshotsSaveReopenRestoreToANewHeadUndoAndRecover
SiteForgeTests/DocumentLifecycleTests/testCompareVersionsRunsOffTheMainActorIgnoresStaleRunsAndNeverEditsTheDocument
SiteForgeTests/DocumentLifecycleTests/testComponentLibraryImportIsOneUndoableStepAndCopiesStayReadOnlyUntilDetached
SiteForgeTests/DocumentLifecycleTests/testSnapshotsSheetCreatesRenamesRestoresKeepingCurrentHandsOffCompareAndRecoversDamagedStorage
SiteForgeTests/CanvasSettingsTests/testFeatureFlagRegistryIdentifiersOwnersAndRemovalDatesAreValid
```

No UI tests added; `scripts/ci-ui-timings.txt` unchanged.

## Suggested first checks for Codex

1. `ProjectComparisonModel.compare()` (`WorkspaceShellView.swift`): the `Task.detached` closure — definite initialization of `let comparison` / `let failure` across `do` / `catch is CancellationError` / `catch`, unlabeled→labeled tuple assignment, and `await self?.finish(comparison, failure:generation:started:)` under Swift 6 complete checking.
2. `DocumentLifecycleController.init`: `session.commitGuard = { [weak self] old, new in try self?.checkLibraryCopies(from: old, to: new) }` — closure isolation inferred from the `@MainActor` init and the `Void?` single-expression body.
3. `testComponentLibrariesExportImportReadOnlyUpdateCompareAndDetach`: `updateSession.execute(updated.command)` with a page instance pointing at the dropped Badge definition (component transition validators with a missing definition), `withCopy.validate()` for the hand-built instance, and `.earlier(.initial)` after Undo (fix 5).
4. `ProjectComparer.compare`: `oldPreferences?.build != newPreferences?.build` (`BuildProfileSettings` Equatable) and the `else if collector.changes.isEmpty` fallback.
5. `confirmationDialog(_:isPresented:titleVisibility:presenting:actions:message:)` in `ProjectSnapshotsSheet` and `ComponentLibrariesSheet`; `.keyboardShortcut(cond ? KeyboardShortcut.cancelAction : nil)` on Done; type-checking time of both sheet bodies and of `WorkspaceShellView.body` with three more sheets.
6. Restore batches (`removePage` ×n, `insertPage` ×n, `setWebsiteMetadata`) passing `PersistedHistoryStore` validation on reopen (third controller in `testNamedSnapshotsSaveReopenRestoreToANewHeadUndoAndRecover`).
7. **`Tests/SiteForgeTests/SupportSettingsTests.swift` is unreadable on Windows (iCloud placeholder).** `FeatureFlagRegistry.definitions` now has **5** entries (`export.zip-archive`, `versions.named-snapshots`, `localization.site-languages`, `versions.compare`, `components.shared-libraries`). Any test there that counts definitions, lists identifiers, or snapshots the Settings > Advanced > Features layout needs updating. (The registry tests in `CanvasSettingsTests` do not count.)
8. `ComponentLibraryVersion`: custom `<` via tuple comparison plus synthesized `Hashable`/`Equatable`, and the string single-value `Codable`.
9. Snapshot document round trip (`DocumentSerializer.encode` → `decode`) giving an equal `CanonicalDocument`; the compare and restore tests rely on it.
