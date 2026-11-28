# Lane V13 review — lane I (document model depth), 2026-11-26

Reviewer: lane V13 (lane V verification). Start state: RP-2026-11-26-V00. No Swift toolchain on this PC:
every change was read against the real declarations it calls, and re-read after writing.
Still document schema 27, persisted-history schema 4, WebsiteMetadata version 3. No new `CanonicalDocument`
or `DocumentNode` key, no new Swift file, no Xcode project change. Decision record: ADR-0133 (new).

## Scope

| Batch | Decision | Module | Code verified (current text, call sites and declarations) |
|---|---|---|---|
| I01 migration framework | ADR-0130 | SF-0309 | `DocumentMigrationStep/Refusal/Report/Candidate/DiagnosticRecord`, `DocumentMigrations` (registry, `validateRegistry`, `path(from:)`, `dryRun`, `storedIdentifiers`) against `DocumentSerializer` (min/current schema, `schemaVersion(in:)`, `decode` schema switch, `StableIdentifier.description`); `ProjectPackageStore.storedDocument(in:)` (`ArchiveCodec`, `Manifest`, `pageMemberPaths`, `ProjectPackagePageSplit.join`); `ProjectSnapshots.migrationBackupName/creatingMigrationBackup`; `DocumentLifecycleBackend.read/migrationCandidate/map`; controller `adoptMigration`, `migrationReport/Notice/Diagnostics`; status bar |
| I02 coalesced, named, bounded transactions | ADR-0131 | SF-0306 | `TransactionCoalescingKey`, `DocumentSession.executeCoalescing/endCoalescing/transactionName/flattenedCommands/trimUndoJournal`, every `coalescing = nil` boundary, `PersistedHistoryStore.removingOldest/maximumEntryCount`, lifecycle `endCoalescing()` before save/autosave capture, `commitTransform` keyboard path |
| I03 history list, jump, page-following Undo | ADR-0132 | SF-0307 | `HistoryListItem`, `historyList()`, `nextUndoPageIDs/nextRedoPageIDs`, `pageIDs(affectedBy:)`, `jump(toStateAfter:)`; workspace `jumpToHistory`, `followHistoryPage`, `historyJumpPageIDs`, `undo/redo`, `adoptSelectedPage`, `adoptSelectionCommand`; `HistoryListButton`, `HistoryListContent` |
| Lane RI fixes 1–12 | — | all three | Re-verified each (access-control move of `storedDocument`, `persistsOnSave` arithmetic vs `removingOldest`, jump page set, definition-page guard, page/selection coalescing boundaries, announcement name, step summaries, narrowed requirement IDs, duplicate cancellation check, VoiceOver row value, moved doc comments, ADR paragraphs). All correct as written. |

Tests re-read: `CommandKernelTests/testHistoryListMarksStepsSavingDropsAndJumpMovesBothWays`,
`CommandKernelTests/testCoalescedTransactionsAreOneUndoStepNamedBoundedAndPersistable`,
`DocumentLifecycleTests/testHistoryListJumpsAndUndoRedoFollowTheChangedPage`,
`DocumentLifecycleTests/testLegacyOpenKeepsOriginalAsSnapshotBeforeUpgradedSaveAndBackupRestoresUndoably`,
`ProjectPackageTests/testDocumentMigrationRegistryIsContiguousAndDryRunReportsWithoutContent` — index arithmetic,
golden identities, counts and expected strings all match the implementation. UI tests that read `toolbar.undo`/`toolbar.redo`
values or drive Inspector steppers/sliders (`SiteForgeLaunchTests` ~126, ~2946–2984, ~3048–3086, ~3116) were
checked against the new behaviour (see "Suggested first checks").

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/WorkspaceShellModel.swift` | `finishDesignStylePreview(owner:)`, `DesignStylePreview.field`, new `designStyleFieldName(_:)` | Every Inspector stepper click / slider release was its own undo step (SF-0306-005 "coalescing MUST follow gesture boundaries"). | Commits through `executeCoalescing` with key `design-style.<case path>` + preview owner + selection; field name from enum case labels only (Mirror), never values. | Repeated adjustments of one field are one step; another field, selection/page change, Undo/Redo, save end the run. |
| 2 | `SiteForge/CommandKernel.swift`, `WorkspaceShellModel.swift`, `WorkspaceShellView.swift` | `DocumentSession.nextUndoDescription/nextRedoDescription`, state proxies, toolbar `accessibilityValue` | Toolbar Undo/Redo value read "Grouped Edit" for merged steps (not meaningful, SF-0306-006). | Value keeps the registry title and adds the ADR-0131 name: "Grouped Edit: Move Node (3 changes)"; ordinary steps unchanged. | Meaningful labels; UI test `containing: "Grouped Edit"` still holds. |
| 3 | `SiteForge/WorkspaceShellView.swift` | `HistoryListContent` | Every row had identifier `history.item` (not addressable, SF-0307-006). | `history.item.<transaction id>`. | Stable unique identifiers. |
| 4 | `SiteForge/CommandKernel.swift` | new `TransactionHistoryDiagnosticRecord`, `transactionDiagnostics`, `recordTransactionDiagnostic`, `transactionFailureCategory` | Merges, journal trims and jumps left only counters, no redacted record with a requirement ID (SF-0306-008, SF-0307-008). | Bounded buffer; coalesce/trim → SF-0306-008, jump (success, rollback failure, unknown id) → SF-0307-008; counts, duration, category only. | Spec diagnostics. |
| 5 | `SiteForge/DocumentLifecycle.swift` | `LifecycleReadOutcome.refused`, backend `lastMigrationRefusal/takeMigrationRefusal(for:)`, controller `migrationRefusal/migrationRefusalText`, `statusText`, `setFailure` | A refused upgrade reached the user only as "The project could not be validated…" (SF-0309-004 "specific recovery action"). | Backend keeps the refusal of the failed open and hands it over once; failed status text is the refusal's description + recovery step; cleared by any later failure or a successful open. Test seam `LifecycleBackendFault.migrationRefusal`. | Specific reason and next step. |
| 6 | `SiteForge/DocumentLifecycle.swift` | new-document failure path in `requestNewDocument` | Set `failure`/`phase` directly instead of `setFailure`, so state cleared by `setFailure` (now the refusal text) could survive into the next failure. | `setFailure(.malformedPackage)` (same phase and failure as before). | One failure path. |
| 7 | `docs/architecture-decisions/ADR-0130/0131/0132` | limits sections | Limits described gaps closed by ADR-0133. | One bullet each updated. | Records match code. |

## Features finished (ADR-0133)

- **I3 — menu command + keyboard shortcut for the history list:** Edit > Show History… (Command-Y; no other ⌘Y in the
  tree) and the status-bar History button call `WorkspaceShellState.presentHistoryList()` (workspace edit boundary,
  then `isHistoryListPresented`); the popover binds to the shared state. Test
  `DocumentLifecycleTests/testShowHistoryCommandPresentsTheSharedHistoryList`.
- **I2 — Inspector coalescing:** fix 1 plus `coalescingNow` (shared clock for nudges and Inspector runs, pinned by
  tests). Typed Inspector fields already commit once per Return/focus change, so typing is one step per committed
  field by design. Test `InsertionModelTests/testFastStyleRepeatedFieldAdjustmentsCoalesceIntoOneUndoStep`
  (run of three radius values = one step, another field = new step, pause > window = new step, undo/redo, round trip).
- **I1 — migration details sheet:** the status notice is now a button (same identifier `status.migrationNotice`, label,
  value, hint) and File > Project Upgrade Details… opens `MigrationDetailsSheet`: summary, one line per step
  (`MigrationStepList`), backup status, Snapshots status, Restore Original (`restoreMigrationOriginal()` → the Snapshots
  restore path: one undoable change, variant guard, announcement), Done (Return). Controller `migrationBackupID`,
  `isMigrationDetailsPresented`. Test `DocumentLifecycleTests/testMigrationDetailsRestoreOriginalUndoablyAndRefusedUpgradeShowsItsReason`
  (unchanged right after open, restore after an edit, undo/redo, refusal text, later failure clears it).
- **RI remaining gaps 1–7:** 1 = fix 2, 2 = fix 3, 3 = fix 4, 4 = fix 5, 5 = I3, 6 = I1, 7 = I2. Gap 8 and 9: see
  Remaining work.

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-0306-001 Authoritative state | Met | `HistoryEntry`; merged step = one revision with flat `.batch`; key/clock never persisted. `CommandKernelTests/testCoalescedTransactionsAreOneUndoStepNamedBoundedAndPersistable`. |
| SF-0306-002 Create/modify (recover unsaved work) | Met | ADR-0024 recovery; `endCoalescing()` before save/autosave capture. |
| SF-0306-003 Resolution rules | Met (bounded) | Deterministic rule (same key, ≤ 1 s, nothing between, ≤ 256 commands); the result is named in the history row and the Undo/Redo value ("… (n changes)") and recorded as a `coalesce` diagnostic. |
| SF-0306-004 Failure and recovery | Met | Failed command commits nothing and ends the run; bounded journal advances the boundary. |
| SF-0306-005 History and persistence | Met | Keyboard nudges and Inspector stepper/slider runs coalesce per field and selection; boundaries at save, autosave, Undo/Redo, other edits, baseline, installed history, page switch, selection change. `InsertionModelTests/testFastStyleRepeatedFieldAdjustmentsCoalesceIntoOneUndoStep`, `DocumentLifecycleTests/testHistoryListJumpsAndUndoRedoFollowTheChangedPage`. |
| SF-0306-006 Accessible operation | Met | Toolbar values name grouped steps (`nextUndoDescription`); Undo/Redo menu + shortcuts unchanged. `CommandKernelTests/testGroupedStepDescriptionsAndTransactionDiagnosticsStayRedacted`. |
| SF-0306-007 Performance and scale | Partial (blocked) | 1,000-entry bound; no timing on large/stress fixtures — needs a Mac to measure. |
| SF-0306-008 Diagnostics and tests | Partial (blocked) | `TransactionHistoryDiagnosticRecord` (coalesce, trim) + per-command records; unit tests. UI/performance coverage needs the macOS runner. |
| SF-0307-001 Authoritative state | Met | `HistoryListItem` derived from the stacks; nothing new persisted. |
| SF-0307-002 Create/modify (inspect history) | Met | Popover, menu command, jump. `DocumentLifecycleTests/testShowHistoryCommandPresentsTheSharedHistoryList`. |
| SF-0307-003 Resolution (revert to checkpoint) | Met (bounded) | Ordered list, applied/current/persists flags, jump through ordinary steps. |
| SF-0307-004 Failure and recovery | Met | Unknown id refused; mid-jump failure rolled back; failure shown and recorded (`jump`, category). |
| SF-0307-005 History and persistence | Met (bounded) | Page-following Undo/Redo/jump; persisted limit per row. |
| SF-0307-006 Accessible operation | Met | Edit > Show History… (Command-Y), labels/values/hints, unique row identifiers, announcements. |
| SF-0307-007 Performance and scale | Partial (blocked) | A jump replays ≤ 1,000 steps on the main actor; batching publication and timing need a Mac. |
| SF-0307-008 Diagnostics and tests | Partial (blocked) | `jump` records (steps, duration, category); unit + lifecycle tests; UI test blocked as above. |
| SF-0309-001 Authoritative state | Partial | Closed versioned upgrade registry; external importer not approved (proposed OD-130). |
| SF-0309-002 Create/modify (preview mappings) | Partial | Upgrade preview = dry-run report + details sheet; import mapping preview not approved (OD-130). |
| SF-0309-003 Resolution (migrate old projects) | Met | `validateRegistry`, `path(from:)`, serializer-checked summaries. `ProjectPackageTests/testDocumentMigrationRegistryIsContiguousAndDryRunReportsWithoutContent`. |
| SF-0309-004 Failure and recovery | Met | Typed refusal before adoption, file unchanged, refusal reason + recovery step shown; backup; Restore Original. |
| SF-0309-005 History and persistence | Met | Backup durable with the next save; restore is one undoable change; open stays clean. |
| SF-0309-006 Accessible operation | Partial | Upgrade notice button + menu command + sheet (keyboard, labels, identifiers); importer UI not approved (OD-130). |
| SF-0309-007 Performance and scale | Partial | Dry run off the main actor, legacy files only; importer and scale fixture not built (OD-130 / Mac timing). |
| SF-0309-008 Diagnostics and tests | Met (bounded) | `DocumentMigrationDiagnosticRecord` (dry run, backup); refusal through lifecycle diagnostics; unit + lifecycle tests. |

Totals: Met 16, Partial 8, Missing 0.

## Remaining work (blocked only)

1. SF-0306-007 / SF-0307-007: timing on the large (10,000 objects) and stress fixtures, and jump batching (apply steps
   without per-step publication) — blocked: no Swift toolchain or Mac here, a performance change cannot be measured or
   verified safely.
2. UI tests for the history popover, Show History… and the upgrade details sheet, plus `scripts/ci-ui-timings.txt` —
   blocked: needs the macOS UI runner to record timings; an unrun UI test would put CI at risk.
3. External markup and asset importer (rest of SF-0309-001/002/006/007) — blocked: not approved; proposed OD-130 below.

## Intended plan / OD status-line changes (for the coordinator)

- Plan, lane I table: `I01–I03 + lane RI fixes: verified by lane V13 (2026-11-26); I1 migration details sheet, I2 Inspector stepper/slider coalescing, I3 Show History… (Command-Y) finished under ADR-0133; remaining: performance timing and UI tests (Mac needed), importer pending OD-130.`
- Activity log (newest first): `2026-11-26 lane V13 — verified lane I (I01–I03, RI fixes); 6 fixes; finished migration details sheet, Inspector field coalescing, Show History… command, refusal reasons, transaction diagnostics (ADR-0133). Report docs/reviews/LANE-V13-review-2026-11-26.md.`
- New OD (AGENTS.md format):

  ## OD-130 — External markup and asset import (SF-0309 importer)

  Status: Open — raised by Code Forge lane V13, 2026-11-26. Implementation status: not started; schema upgrades of
  SiteForge projects (ADR-0130, ADR-0133) are done.

  - Affected requirements: SF-0309-001, SF-0309-002, SF-0309-006, SF-0309-007.
  - Context: SF-0309 also asks for importing external markup and assets with a staged preview of mappings before
    commit. Which formats (static HTML/CSS, images, fonts), how unsupported markup maps, and how much of it becomes
    editable canonical content are product decisions.
  - Recommended default: a first importer for images, fonts and media only (already canonical asset kinds), staged in a
    preview sheet and committed as one undoable transaction; HTML/CSS markup import deferred.
  - Alternative: include a static HTML/CSS importer that maps a supported subset to frames, text and styles.
  - Tradeoff: assets-only ships safely on today's model; markup import is far larger and needs mapping rules and
    fidelity limits.
  - Safe temporary assumption: no importer; SF-0309 covers schema upgrades only.

## New/changed test selectors

```
SiteForgeTests/CommandKernelTests/testGroupedStepDescriptionsAndTransactionDiagnosticsStayRedacted            (new)
SiteForgeTests/CommandKernelTests/testCoalescedTransactionsAreOneUndoStepNamedBoundedAndPersistable           (changed: trim records asserted)
SiteForgeTests/DocumentLifecycleTests/testShowHistoryCommandPresentsTheSharedHistoryList                      (new)
SiteForgeTests/DocumentLifecycleTests/testMigrationDetailsRestoreOriginalUndoablyAndRefusedUpgradeShowsItsReason (new)
SiteForgeTests/InsertionModelTests/testFastStyleRepeatedFieldAdjustmentsCoalesceIntoOneUndoStep               (new)
```

## Suggested first checks for Codex

1. `WorkspaceShellState.designStyleFieldName(_:)`: `outer.flatMap { child -> String? in … }` and
   `[outer?.label ?? String(describing: edit), inner].compactMap { $0 }.joined(separator: ".")`.
2. `InsertionModelTests/testFastStyleRepeatedFieldAdjustmentsCoalesceIntoOneUndoStep`: `var now` captured by
   `state.coalescingNow = { now }` and mutated by the nested `async` func `adjust` (Swift 6 strict concurrency);
   `XCTAssertEqual(try radius(), 14)` with `Double?`; that `.box(.cornerRadius(…))` and `.fill(.replaceSolid(…))`
   previews apply to the fixture header (the existing fast-style test uses both).
3. `LifecycleBackendFault` gained `migrationRefusal(DocumentMigrationRefusal)`; `throwFault()` switch; the
   `[LifecycleBackendFault.permission, .staleScope, .io]` loop in `DocumentLifecycleTests`.
4. `loadAndAdopt` read task: `await backend.takeMigrationRefusal(for: identity.id)` inside the
   `catch let error as DocumentLifecycleFailure` of a main-actor `Task<LifecycleReadOutcome, Never>`; the outcome switch
   handles `.refused`.
5. `DocumentLifecycleController.migrationRefusalText`: nested `$0` in `[$0.errorDescription, $0.recoverySuggestion].compactMap { $0 }`.
6. Bindings `$state.isHistoryListPresented` (HistoryListButton) and `$lifecycle.isMigrationDetailsPresented`
   (MigrationNoticeButton); the `.saveItem` CommandGroup now has 15 children (it already had 14) and `.undoRedo` adds
   Divider + Show History… (⌘Y).
7. `DocumentSession.nextUndoDescription`: `undoStack.last.map { historyDescription($0) }` (implicit self, non-escaping).
8. UI journeys: `toolbar.undo` value now "Grouped Edit: …" for grouped steps (`SiteForgeLaunchTests` ~126 uses
   `containing: "Grouped Edit"`); fast-style journeys that click a stepper or drag a slider of the same field twice
   within 1 s and then Undo once now revert both (checked: the current journeys put Undo/Redo or another field between
   repeats); the status-bar upgrade notice is a borderless Button instead of a Label.
9. `executeCoalescing` records `coalesce` with `Self.flattenedCommands(forward).count`; `trimUndoJournal` records one
   `trim` per trimmed append (the bounded test expects `[1, 1, 1, 1, 1]`).
10. `restoreMigrationOriginal()` → `prepareForWorkspaceAction(.context)` → `reloadSnapshots()` →
    `restoreSnapshot(id, keepingCurrentAs: nil)`; right after opening it must report `ProjectSnapshotError.unchanged`.

## Files changed by this lane

`SiteForge/CommandKernel.swift`, `SiteForge/WorkspaceShellModel.swift`, `SiteForge/DocumentLifecycle.swift`,
`SiteForge/WorkspaceShellView.swift`, `Tests/SiteForgeTests/CommandKernelTests.swift`,
`Tests/SiteForgeTests/DocumentLifecycleTests.swift`, `Tests/SiteForgeTests/InsertionModelTests.swift`,
`docs/architecture-decisions/ADR-0130-document-migration-framework.md`,
`docs/architecture-decisions/ADR-0131-coalesced-named-bounded-transactions.md`,
`docs/architecture-decisions/ADR-0132-history-list-and-page-following-undo.md`,
`docs/architecture-decisions/ADR-0133-field-coalescing-history-command-upgrade-details.md` (new), and this report.
`check([...])` returned `[]` for every changed Swift file after the last edit; `icloud_duplicates()` and
`foreign_changes(30)` returned `[]`. Write notes: two forge_io calls hit the 65 s sandbox timeout / a device
disconnect but had completed their write (verified by re-reading before retrying); one anchor was rebuilt after
another lane added `capacity:` to `LoadedProject` in `DocumentLifecycleBackend.read`. No ICloudRenameError.
