# ADR-0131: Coalesced, named and bounded transactions

- Status: Proposed
- Date: 2026-11-26
- Requirements: SF-0306-002, SF-0306-003, SF-0306-004, SF-0306-005 (bounded)
- Related: ADR-0003 (bounded persisted history), ADR-0008 (save/autosave ordering), ADR-0024 (recovery offers)

## Context

Every command was its own undo step, so ten arrow-key nudges needed ten Undos.
History entries were labelled only with the registry title, and the in-memory
undo journal had no bound (persisted history is already limited to 128 entries
and 512 KiB). Persisted history validates each entry strictly: exactly one
revision, `label == registry title`, `affectedIdentifiers == forward.targets`,
and forward/inverse round trips.

## Decision

- `DocumentSession.executeCoalescing(_:key:at:)` commits one transaction and, when
  the previous entry was committed with the same `TransactionCoalescingKey` at
  most `coalescingWindow` (1 s) earlier and nothing came between, replaces that
  entry with one merged entry: forward = flat batch of both forwards, inverse =
  flat batch of the new inverse followed by the old inverse. The merged entry
  spans exactly one revision (parent = revision before the new edit), its
  command name is `.batch` and its label is the batch registry title, so the
  existing persisted-history validator accepts it without a schema change. One
  Undo returns to the state before the first merged edit.
- Coalescing ends on any other `execute`, Undo, Redo, new baseline, installed
  history, failed command, and `endCoalescing()`, which the lifecycle calls
  before Save, Save As and autosave capture history. A merge never crosses the
  history boundary, and at most 256 flattened commands are merged into one entry.
  The workspace also ends coalescing on a page switch (`adoptSelectedPage`) and
  on any selection change made through a selection command (review RI,
  2026-11-26).
- The workspace coalesces keyboard moves of the same selection
  (`TransformProvenance.keyboard`, `.move`). Pointer drags were already one
  transaction per gesture.
- `transactionName(for:)` gives a non-content display name: a batch made of one
  kind of command is "<title> (N changes)"; everything else keeps its label.
  The persisted label is unchanged.
- The in-memory undo journal keeps at most `maximumUndoEntries` (1,000) entries.
  The oldest are dropped first and `historyBoundaryRevision` advances to the last
  dropped result revision (the ADR-0003 retention rule), so Undo never reaches a
  state without its entry. `coalescedTransactionCount` and
  `droppedTransactionCount` are exposed for diagnostics and tests.

## Consequences and limits

- No document, package or history schema change.
- Typed Inspector fields commit once per Return or focus change. Repeated
  stepper clicks and slider adjustments of one field coalesce since ADR-0133.
- The crash recovery choice (Restore, Discard, Inspect, Review later) already
  exists (ADR-0024, LaunchExperience) and is unchanged by this batch.
