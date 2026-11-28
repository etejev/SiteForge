# Lane RI review — batches I01–I03 (2026-11-26, unverified)

Reviewer: lane-RI (lane R). Review freeze in force; restore point before the review: RP-2026-11-26-R01.
No Swift compiler was available: every change below was re-read against the declarations it calls.
Still document schema 27, persisted-history schema 4, WebsiteMetadata version 3; no new
`CanonicalDocument` or `DocumentNode` key; no new Swift files.

## Scope

| Batch | Decision | Module | Code reviewed |
|---|---|---|---|
| I01 document migration framework | ADR-0130 | SF-0309 | `DocumentModel.swift` (`DocumentMigrationStep`, `DocumentMigrationRefusal`, `DocumentMigrationReport`, `DocumentMigrationCandidate`, `DocumentMigrationDiagnosticRecord`, `DocumentMigrations`); `ProjectPackage.swift` (`ProjectPackageStore.storedDocument(in:)`, `ProjectSnapshots.migrationBackupName(for:)`, `creatingMigrationBackup`); `DocumentLifecycle.swift` (`LoadedProject.migration`, `DocumentLifecycleBackend.migrationCandidate(for:)`, failure `map`, controller `migrationReport`/`migrationNotice`/`migrationDiagnostics`/`adoptMigration`); `WorkspaceShellView.swift` (`status.migrationNotice`); tests in `ProjectPackageTests` and `DocumentLifecycleTests` |
| I02 coalesced, named, bounded transactions | ADR-0131 | SF-0306 | `CommandKernel.swift` (`TransactionCoalescingKey`, `DocumentSession.executeCoalescing`, `endCoalescing`, `transactionName(for:)`, `flattenedCommands`, `trimUndoJournal`, boundaries in `execute`/`undo`/`redo`/`establishBaseline`/`installValidatedHistory`); `DocumentLifecycle.swift` (`endCoalescing` before save/autosave capture); `WorkspaceShellModel.commitTransform`; test in `CommandKernelTests` |
| I03 history list, jump, page-following Undo | ADR-0132 | SF-0307 | `CommandKernel.swift` (`HistoryListItem`, `historyList()`, `nextUndoPageIDs`, `nextRedoPageIDs`, `pageIDs(affectedBy:)`, `jump(toStateAfter:)`); `WorkspaceShellModel.swift` (`historyJumpFailure`, `historyItems`, `jumpToHistory`, `followHistoryPage`, `undo`, `redo`); `WorkspaceShellView.swift` (`HistoryListButton`, `HistoryListContent`); tests in `CommandKernelTests` and `DocumentLifecycleTests` |

Special checks done: the 1,000-entry in-memory cap against `PersistedHistoryStore` (128 entries / 512 KiB,
`removingOldest`, `recoverySnapshot`, `validateEntries` ordering and boundary rules) and every existing test that
loops over transactions (none commits more than 1,000 and undoes all); coalescing boundaries; `jump(toStateAfter:)`
index arithmetic and rollback; page-following Undo against every unit test that calls a workspace `undo()`/`redo()`
and every UI test in `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift` that navigates pages before Undo (the
Header/Footer copy journey undoes on a page the command targets, so it keeps the page); the registry against the
real `DocumentSerializer.decode` schema switch, the schema gates and ADR-0015 / SF-AUTHORING-057/059; the four legacy
goldens (decoded on Windows: page and node identities, counts, names); backup-before-migrate through
`ProjectSnapshots.document(for:)` and `restoreCommand`; lane A's `DocumentSession.commitGuard` (passed to `commit` by
both `execute` and `executeCoalescing`, so merged steps are checked per edit; Undo/Redo stay unchecked as ADR-0041 says).

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/ProjectPackage.swift` | `ProjectPackageStore.storedDocument(in:)` | Declared inside `private extension ProjectPackageStore`, so it was fileprivate; `DocumentLifecycleBackend.migrationCandidate` (DocumentLifecycle.swift) and four test call sites could not compile. | Moved unchanged into a new internal `extension ProjectPackageStore` placed just before the private extension (same file, so the fileprivate `Manifest`, `pageMemberPaths(in:)` and private `manifestPath`/`documentPath` stay reachable). | Compile error (access control). |
| 2 | `SiteForge/CommandKernel.swift` | `DocumentSession.historyList()` | `persistsOnSave` assumed saving drops the first rows of the list. `PersistedHistoryStore.removingOldest` drops the oldest Undo entries first, then `redo.removeFirst()` (the farthest Redo entry, i.e. the list's tail), so rows were mislabelled whenever the overflow exceeded the Undo count. | Computes `droppedUndo` and `keptEnd` exactly like `removingOldest`; typed the `ordered` tuple array. Doc comment on `HistoryListItem.persistsOnSave` updated. | Wrong user-visible "Not kept after saving" note. |
| 3 | `SiteForge/WorkspaceShellModel.swift` | `jumpToHistory(_:)`, new private `historyJumpPageIDs(to:)` | Followed the pages of the target row only. Jumping back to a row keeps that row applied; the pages changed are those of the later rows that were undone (and for a forward jump, every redone row). | Collects the pages of every step the jump takes, last step first, de-duplicated. | SF-0307-005 "the change is never invisible". |
| 4 | `SiteForge/WorkspaceShellModel.swift` | `followHistoryPage(_:)` | While a component definition is open, `effectiveSelectedPageID` is the definition; following a website-page change set `selectedPageID` underneath and cleared the selection without showing anything. | Guard `editingComponentID == nil`. | Avoids an invisible page switch (ADR-0132 says definition pages do not switch). |
| 5 | `SiteForge/WorkspaceShellModel.swift` | `adoptSelectedPage(_:)`, `adoptSelectionCommand(...)` | Coalescing ended at save, autosave, Undo/Redo, another edit, new baseline and installed history, but not at a page switch or a selection change (a run could continue after the user came back to the same selection within 1 s). | `documentSession.endCoalescing()` on every page adoption and when a selection command changes the selection. | SF-0306-005 "MUST follow gesture boundaries". |
| 6 | `SiteForge/WorkspaceShellModel.swift` | `jumpToHistory(_:)` | Announced `nextUndoLabel`, which reads "Grouped Edit" for merged nudges. | Announces the current row's display name (`transactionName`). | Meaningful announcement (SF-0307-006). |
| 7 | `SiteForge/DocumentModel.swift` | `DocumentMigrations.steps` | Step summaries did not match the serializer: 3→4 said "Records the template identity explicitly" (schemas 2–4 already required `templateID`; schema 4 added Section/Stack/Grid, ADR-0015); 8→9 said it moves bindings to the fill key (schema 9 *added* local color tokens with `style.fill.token.v1.id`; the move to per-target keys is what reading schema 9 does, i.e. 9→10); 20→21 omitted dark token colors (`darkColor` needs source schema ≥ 21). | Corrected the four summaries. Ordering, counts and the contiguity proof were already right. | Migration report must describe the real upgrade (SF-0309-003). |
| 8 | `SiteForge/DocumentModel.swift` | `DocumentMigrations.requirementIDs` | Claimed all eight SF-0309 requirements although external markup/asset import (002/006/007) is not built. | Narrowed to 001, 003, 004, 005, 008 with a comment. Nothing reads the set. | No over-claimed traceability. |
| 9 | `SiteForge/DocumentLifecycle.swift` | `DocumentLifecycleBackend.read` | Duplicated `try Task.checkCancellation()` after the dry run. | Removed the duplicate. | Clean code. |
| 10 | `SiteForge/WorkspaceShellView.swift` | `HistoryListContent` | VoiceOver did not hear the visible "Not kept after saving" note (the row's label/value override it); `Button { state.jumpToHistory(…) }` relied on a Bool single-expression closure in a Void action. | New private `historyRowValue(_:)` adds ", not kept after saving" to the value; actions are `_ = state.jumpToHistory(…)`. | Accessibility parity; type-checker safety. |
| 11 | `SiteForge/CommandKernel.swift`, `Tests/SiteForgeTests/CommandKernelTests.swift`, `Tests/SiteForgeTests/ProjectPackageTests.swift` | doc comments | Insertions split doc comments from their declarations: `TransactionCoalescingKey`'s comment sat on `HistoryListItem`; the SF-0902/0905 comment of `testComponentDefinitionTextDraftRetainsPairedEditsAndDetectsBindingReplacement` sat on the I03 test; the SF-0301-003/SF-1702-001 comment of `testUnknownOptionalMemberIsPreservedByteForByteAcrossRoundTrip` sat on the I01 test. | Moved each comment back above its declaration. | Comments say why, at the right place. |
| 12 | `docs/architecture-decisions/ADR-0130…, ADR-0131…, ADR-0132…` | — | ADRs did not describe fixes 2–5 and 7. | One short paragraph each. | Decision records match the code. |

Checked without change (correct as written): `coalescing = (key, now)` into the labelled optional tuple;
`commands.flatMap(flattenedCommands)`; `if provenance == .keyboard, case .move = preview.operation`
(`TransformProvenance` is a raw-value enum; `.move` has associated values, matched without bindings); merged entries
pass `PersistedHistoryStore.validateEntries` (one revision, `commandName == forward.name == .batch`, label "Grouped
Edit" = registry title, `affectedIdentifiers == forward.targets`, ordering `result <= next parent`, inverse/forward
round trip); `trimUndoJournal` moves `historyBoundaryRevision` to the last dropped result revision, which is ≤ the
next entry's parent, so the validator's boundary rule holds and `recoverySnapshot` stays valid; the 1,000 cap is
far above the persisted 128, so saved history is unaffected; `jump(toStateAfter:)` index arithmetic for Undo and
Redo sides; `(try? documentSession.undo()) != nil`; `ordered.enumerated().map { index, row in … }`;
`catch DocumentSerializationError.unsupportedSchema(let version)` (case exists with `Int`); `DocumentMigrationRefusal`
switch in the lifecycle failure `map` is exhaustive; `LoadedProject` is built only in `DocumentLifecycle.swift` (twice)
and `migration` has a default; `ContinuousClock.now`/`duration(to: .now)` as in lane A's code; the snapshot index
accepts `documentSchemaVersion` 1…27 and `ProjectSnapshots.document(for:)` decodes older schemas through the
migrating decoder; `restoreCommand` throws `.unchanged` for the freshly opened legacy document (the lifecycle test
relies on it); the four legacy goldens match the test expectations (v1 rootless: page `31000000-…-000000000002`,
no nodes, "Legacy Landing"; v2 minimum: 1 page, 1 node; v4: identities preserved, so the dry run never refuses the
UI fixtures); `DocumentPage(id:name:)` creates a minimum root; `renamePage` of a missing page throws `.disabled`;
the default document has Home and Not Found (the lifecycle test's `pages.count == 2`).

## Requirement table

Evidence names are symbols; "test" names the selector.

| Requirement | Status | Evidence |
|---|---|---|
| SF-0306-001 Authoritative state | Met | `HistoryEntry`; merged entry is one revision with flat `.batch` forward/inverse; key not persisted. Test `CommandKernelTests/testCoalescedTransactionsAreOneUndoStepNamedBoundedAndPersistable`. |
| SF-0306-002 Create/modify (recover unsaved work) | Met | Existing recovery offers (ADR-0024); `endCoalescing()` before autosave capture. |
| SF-0306-003 Resolution rules | Partial | Deterministic rule (same key, ≤ 1 s, nothing between, ≤ 256 commands); `transactionName(for:)`. No surface explains why steps merged. |
| SF-0306-004 Failure and recovery | Met | Failed command commits nothing and ends the run; bounded journal moves the boundary. Same test. |
| SF-0306-005 History and persistence | Partial | Keyboard nudges coalesced; boundaries at save, autosave, Undo/Redo, baseline, installed history, page switch and selection change (fix 5). Inspector typing and slider drags are not coalesced (they commit once per field). Test `DocumentLifecycleTests/testHistoryListJumpsAndUndoRedoFollowTheChangedPage` (page-switch boundary). |
| SF-0306-006 Accessible operation | Partial | No new UI; the Undo button/menu value still reads the registry label ("Grouped Edit") for merged steps. |
| SF-0306-007 Performance and scale | Partial | 1,000-entry bound; no large/stress fixture timing. |
| SF-0306-008 Diagnostics and tests | Partial | Per-commit `CommandDiagnostics`; `coalescedTransactionCount`, `droppedTransactionCount` counters only (no redacted record with the requirement ID); unit tests, no UI test. |
| SF-0307-001 Authoritative state | Met | `HistoryListItem` is derived from the stacks; nothing new persisted. |
| SF-0307-002 Create/modify (inspect history) | Met | `HistoryListButton`/`HistoryListContent` popover, `jumpToHistory`. Tests `CommandKernelTests/testHistoryListMarksStepsSavingDropsAndJumpMovesBothWays`, `DocumentLifecycleTests/testHistoryListJumpsAndUndoRedoFollowTheChangedPage`. |
| SF-0307-003 Resolution (revert to checkpoint) | Partial | Ordered list, applied/current flags, exact `persistsOnSave` (fix 2); jump through ordinary steps. No per-step detail of what changed. |
| SF-0307-004 Failure and recovery | Met | Unknown id refused; a failing step mid-jump reverses the steps taken (new assertions); `historyJumpFailure` shown as `history.failure`. |
| SF-0307-005 History and persistence | Met (bounded) | Page-following Undo/Redo/jump (fixes 3, 4); persisted limit noted per row and in the popover. |
| SF-0307-006 Accessible operation | Partial | Labels, values (now including the save note), hint, announcements. No menu command or keyboard shortcut through the central command registry; row identifiers are not unique. |
| SF-0307-007 Performance and scale | Partial | A jump replays up to 1,000 steps synchronously on the main actor, each fully validated and published. No stress timing. |
| SF-0307-008 Diagnostics and tests | Partial | Each step records an Undo/Redo command diagnostic; no jump-level record; unit and lifecycle tests, no UI test. |
| SF-0309-001 Authoritative state | Partial | Closed, typed, versioned registry; external importer not built. |
| SF-0309-002 Create/modify (preview mappings) | Partial | Dry-run report (counts and step lines) as status-bar help and accessibility value; no details sheet; no import preview. |
| SF-0309-003 Resolution (migrate old projects) | Met | `validateRegistry`, `path(from:)`, summaries checked against the serializer (fix 7). Test `ProjectPackageTests/testDocumentMigrationRegistryIsContiguousAndDryRunReportsWithoutContent`. |
| SF-0309-004 Failure and recovery (cancel safely) | Met (bounded) | Typed refusal before adoption, file unchanged; backup snapshot; "no backup kept, use Save As" branch. The refusal reaches the user only as the generic lifecycle failure text. |
| SF-0309-005 History and persistence | Met | Backup durable with the next save; restore is one undoable transaction; open stays `.clean`. Test `DocumentLifecycleTests/testLegacyOpenKeepsOriginalAsSnapshotBeforeUpgradedSaveAndBackupRestoresUndoably`. |
| SF-0309-006 Accessible operation | Partial | `status.migrationNotice` label/value; no keyboard-reachable details; no importer UI. |
| SF-0309-007 Performance and scale | Partial | Dry run runs in the lifecycle backend actor, legacy files only (extra decode, encode, decode); no scale fixture. |
| SF-0309-008 Diagnostics and tests | Met (bounded) | Redacted `DocumentMigrationDiagnosticRecord` (dry run, backup) with requirement ID, schema numbers, duration, failure category; unit and lifecycle tests. A refusal is recorded only by the lifecycle's own failure diagnostic. |

## Remaining gaps (easiest → hardest, with plan)

1. Undo/Redo value for merged steps: add `nextUndoName`/`nextRedoName` (via `transactionName`) to `WorkspaceShellState` and use them in the toolbar/menu value; first check UI tests that read `toolbar.undo` values (they use `containing:` "Move Node"/"Set Property", which "Move Node (3 changes)" still satisfies).
2. Unique row identifiers `history.item.<transaction id>` plus a UI test for the popover (then update `scripts/ci-ui-timings.txt`).
3. Redacted diagnostic records for coalesced merges, dropped entries and jumps (requirement IDs SF-0306-008 / SF-0307-008), following `DocumentMigrationDiagnosticRecord`.
4. Show `DocumentMigrationRefusal.errorDescription` and `recoverySuggestion` in the open-failure UI instead of the generic text (SF-0309-004).
5. Edit-menu "Show History…" command through `CommandRegistry` with a shortcut, opening the same popover state (SF-0307-006).
6. Migration details sheet (summary, step lines, backup status, "Restore original") reachable from the status notice (SF-0309-002/006).
7. Coalesce Inspector typing and slider drags with a key per field and selection (SF-0306-005).
8. Jump performance: apply steps without per-step publication and refresh the scene once; stress test with 1,000 steps on the large fixture (SF-0307-007).
9. External markup and asset importer with a staged preview (rest of SF-0309); needs an OD in lane I's range (OD-130–139) before work starts.

## Intended OD status-line changes

None. Lane I has no OD (batches I01–I03 were not OD-gated). `docs/OPEN_DECISIONS 2.md` was not touched.

## New/changed test selectors

No new selectors. Changed (assertions added; nothing weakened):

```
SiteForgeTests/CommandKernelTests/testHistoryListMarksStepsSavingDropsAndJumpMovesBothWays
SiteForgeTests/DocumentLifecycleTests/testHistoryListJumpsAndUndoRedoFollowTheChangedPage
```

- The kernel test now checks which rows saving drops when most rows are on the Redo side, and that a step failing
  part-way through `jump(toStateAfter:)` is rolled back (history installed with a deliberately broken inverse).
- The lifecycle test now checks the page a jump shows (back, forward, to the oldest state) and that a page switch
  ends a coalescing run.

Unchanged selectors in scope: `CommandKernelTests/testCoalescedTransactionsAreOneUndoStepNamedBoundedAndPersistable`,
`ProjectPackageTests/testDocumentMigrationRegistryIsContiguousAndDryRunReportsWithoutContent` (comment moved only),
`DocumentLifecycleTests/testLegacyOpenKeepsOriginalAsSnapshotBeforeUpgradedSaveAndBackupRestoresUndoably`.

## Suggested first checks for Codex

1. `extension ProjectPackageStore { static func storedDocument(in:) }` (ProjectPackage.swift, just before `private extension ProjectPackageStore`): body uses the fileprivate `Manifest`, `pageMemberPaths(in:)` and the actor's `private static let manifestPath/documentPath` from a nonisolated static method in another extension of the same file.
2. `historyList()`: `let ordered: [(entry: HistoryEntry, applied: Bool)] = undoStack.map { (entry: $0, applied: true) } + redoStack.reversed().map { … }`.
3. `historyJumpPageIDs(to:)`: `Array(items[(target + 1)...current])`, `Array(items[(current + 1)...target].reversed())`, `changed.flatMap(\.pageIDs).filter { seen.insert($0).inserted }`.
4. `jumpToHistory`: `documentSession.historyList().last(where: \.isCurrent)?.name` and the nested string literal in the interpolation.
5. Kernel test: `HistoryEntry(…)` memberwise init and `PersistedHistorySnapshot(documentID:documentRevision:boundaryRevision:undoEntries:redoEntries:)` with a broken inverse; that `registry.apply` throws for `renamePage` of a missing page inside `commit`.
6. Lifecycle test: `state.selectPage(notFound)` is accepted (`prepareForWorkspaceAction(.context)`), so the run ends; `executeCoalescing(_:key:at:)` with fixed `Date(timeIntervalSince1970: 2_000)` offsets.
7. UI tests that open `schema-v4-legacy-surface` now get a migration notice and a History button in the status bar (width, `status.*` hit-testing) and, after a save, a "Before upgrade from schema 4" snapshot in the package.
8. Undo/Redo of an edit on another page now switches pages; re-run UI journeys that undo after navigating (Header/Footer copy, static page management, Quick Open).
9. Runtime of the 1,005-command bounded-journal loop and the 130-entry history loops (each commit validates the whole document).
10. The I02/I03 popover and status bar: `HistoryListContent.body` (`let items` then `VStack`) and `.accessibilityValue(historyRowValue(item))`.

## Files changed by this review

`SiteForge/CommandKernel.swift`, `SiteForge/ProjectPackage.swift`, `SiteForge/DocumentLifecycle.swift`,
`SiteForge/WorkspaceShellModel.swift`, `SiteForge/WorkspaceShellView.swift`, `SiteForge/DocumentModel.swift`,
`Tests/SiteForgeTests/CommandKernelTests.swift`, `Tests/SiteForgeTests/ProjectPackageTests.swift`,
`Tests/SiteForgeTests/DocumentLifecycleTests.swift`,
`docs/architecture-decisions/ADR-0130-document-migration-framework.md`,
`docs/architecture-decisions/ADR-0131-coalesced-named-bounded-transactions.md`,
`docs/architecture-decisions/ADR-0132-history-list-and-page-following-undo.md`, and this report.
`check([...])` returned `[]` after the last edit; `foreign_changes(30)` returned `[]`.
`docs/IMPLEMENTATION_STATUS.md`, `docs/CHANGELOG.md`, the plan and the activity log were not edited (coordinator).
