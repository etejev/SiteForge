# ADR-0133: Field coalescing, history command, upgrade details and refusal reasons

- Status: Proposed
- Date: 2026-11-26
- Requirements: SF-0306-005, SF-0306-006, SF-0306-008, SF-0307-002, SF-0307-006, SF-0307-008,
  SF-0309-002, SF-0309-004, SF-0309-006
- Related: ADR-0130 (document migration framework), ADR-0131 (coalesced, named, bounded
  transactions), ADR-0132 (history list and page-following Undo), ADR-0038/ADR-0039 (named snapshots)
- Decision owner: lane V13 (verification of lane I), within the scope of ADR-0130 to ADR-0132.
  No new open decision.

## Context

Lane I (ADR-0130 to ADR-0132) left gaps that its review (LANE-RI) listed: Inspector steppers and
sliders committed one undo step per click or drag, the history list had no menu command or
shortcut, the toolbar Undo/Redo values read "Grouped Edit" for merged steps, coalescing, journal
trims and jumps left no diagnostic record, the upgrade notice had no details surface, and a refused
upgrade reached the user only as the generic "could not be validated" text.

## Decision

- **Field coalescing (SF-0306-005).** `WorkspaceShellState.finishDesignStylePreview(owner:)` commits
  through `DocumentSession.executeCoalescing` with the key `design-style.<field>` plus the preview
  owner and the selected node ids. `<field>` is the enum case path of the edit (for example
  `box.cornerRadius`, `fill.replaceSolid`), never a value. Repeated stepper clicks or slider
  adjustments of one field of one selection within the one-second window are one undo step; another
  field, a selection or page change, Undo/Redo, another edit, a save or autosave end the run (the
  ADR-0131 boundaries). Typed Inspector fields already commit once per Return or focus change, so
  typing stays one step per committed field. `coalescingNow` is the clock for both this and keyboard
  nudges; tests pin it.
- **History command (SF-0307-006).** Edit > Show History… (Command-Y) and the status-bar History
  button call `presentHistoryList()`, which applies the usual workspace edit boundary and sets the
  shared `isHistoryListPresented`; the popover binds to it. Rows have unique identifiers
  `history.item.<transaction id>`.
- **Undo/Redo values (SF-0306-006).** `DocumentSession.nextUndoDescription` / `nextRedoDescription`
  keep the registry title and add the ADR-0131 name for grouped steps
  ("Grouped Edit: Move Node (3 changes)"); ordinary steps read as before. The toolbar uses them.
- **Diagnostics (SF-0306-008, SF-0307-008).** `TransactionHistoryDiagnosticRecord` (operation
  coalesce, trim or jump; step count; duration; failure category) in a bounded buffer on
  `DocumentSession` (`transactionDiagnosticRecords`). No names, identifiers or content.
- **Upgrade details (SF-0309-002/006).** The status notice is a button (same identifier
  `status.migrationNotice`) and File > Project Upgrade Details… opens a sheet with the summary, one
  line per step, the backup status, and Restore Original. Restore Original uses the Snapshots restore
  path (`restoreMigrationOriginal()` -> `restoreSnapshot(_:keepingCurrentAs:)`): one new undoable
  change; right after opening it reports "unchanged" because the kept original reads back as the open
  document. The controller exposes `migrationBackupID`.
- **Refusal reasons (SF-0309-004).** The backend remembers the `DocumentMigrationRefusal` of a failed
  open and hands it to the controller once (`takeMigrationRefusal(for:)`); the controller publishes
  `migrationRefusal`, and the failed status text is the refusal's description and recovery step.
  Any later failure or a successful open clears it. `LifecycleBackendFault.migrationRefusal` is the
  test seam, because no valid fixture makes the dry run refuse on purpose.

## Consequences and limits

- Still document schema 27, persisted-history schema 4, WebsiteMetadata version 3. No new
  `CanonicalDocument` key, no new Swift file. Merged steps validate as ADR-0131 describes.
- A history jump still replays up to 1,000 ordinary steps on the main actor and publishes each one;
  measuring it on the large and stress fixtures needs a Mac (SF-0307-007 stays partial).
- No UI test covers the popover, the menu command or the details sheet yet; they need the macOS UI
  runner and an update of `scripts/ci-ui-timings.txt`.
- External markup and asset import (the rest of SF-0309) is not part of this decision.
