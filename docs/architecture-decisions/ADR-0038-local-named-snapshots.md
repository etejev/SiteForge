# ADR-0038 — Local named snapshots (storage, create, rename, delete, restore)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-043 (approved by the owner 2026-11-26 1:30 PM EST)
- Requirements: SF-1301-001 … SF-1301-008 (model, storage and lifecycle part; no UI yet)

## Context

OD-043 asks for local snapshots kept with the project (named, timestamped,
bounded count) with restore, and a later structural diff (SF-1306).
Collaboration, comments, roles and merge stay deferred. The spec's invariant:
restore never deletes the current head; retained versions stay readable after
schema migration.

## Decision

- Storage: optional members of the project package itself —
  `snapshots/index-v1.json` (closed `ProjectSnapshotIndex`, version 1, exact
  keys, document ID, entries oldest first) and one `snapshots/<id>.json` per
  snapshot holding the complete canonical document (`DocumentSerializer`
  encoding with its schema version). "Beside the project" is read as "in the
  same project file", so snapshots move, copy (Save As) and integrity-check with
  it and no new file-system code is needed. No document schema or package
  version change: older builds keep unknown optional members byte for byte.
- Entry: `ProjectSnapshotEntry` (`id`, `name`, `createdAt`, `documentRevision`,
  `documentSchemaVersion`, `byteCount`, `sha256`). Every `snapshots/` member
  must be listed and match its size and hash; anything else is `corrupt`, and
  the recovery action is Delete All Snapshots (`ProjectSnapshots.removingAll`),
  which removes only `snapshots/` members.
- Bounds: at most 10 named snapshots (never pruned automatically; creation is
  refused with `limitReached`), 2 MiB for all snapshot documents together, and
  document + other archived members + snapshots must stay within 75% of the
  8 MiB project file limit when a snapshot is created (`storageFull`).
- Names: trimmed, 1–256 UTF-8 bytes, no control characters, unique without
  regard to case. Rename keeps identity and content.
- Restore: `ProjectSnapshots.restoreCommand` builds one `batch` document
  command that replaces only changed parts (pages, guides, image assets, color
  tokens, website metadata, project preferences). It runs through
  `DocumentSession.execute`, so it is one new revision (never a rewind), one
  Undo step ("Grouped Edit"), and valid persisted history. Creation kind,
  template and revision stay with the current head. A snapshot whose image
  resource is no longer in the project is refused (`missingResource`).
  `keepingCurrentAs:` first keeps the current document as a named snapshot; if
  either step fails nothing changes.
- Lifecycle: `DocumentLifecycleController` gains `projectSnapshots()`,
  `createProjectSnapshot(named:)`, `renameProjectSnapshot(_:to:)`,
  `deleteProjectSnapshot(_:)`, `deleteAllProjectSnapshots()` and
  `restoreProjectSnapshot(_:keepingCurrentAs:)`. Snapshot changes edit the
  in-memory package and mark the project modified (like resource changes);
  the next save makes them durable. They are refused (`unavailable`) while a
  save, open or other transition is running.
- Diagnostics: `ProjectSnapshotDiagnosticRecord` (SF-1301-008, operation,
  sanitized snapshot ID, duration, result, failure category); no names or
  content.

## Consequences

- Snapshots count toward the project file size. A project near the file limit
  cannot take snapshots; very large documents (over 2 MiB) cannot be
  snapshotted in this slice.
- A restore of a large document produces a large history entry; persisted
  history retention (512 KiB) may drop older Undo steps at the next save.
- A snapshot-only change keeps the document revision, so crash recovery does
  not bring it back; it is saved with Save.
- Component transition rules can refuse a restore (for example when a
  component binding changed since the snapshot); the document is unchanged and
  the model's reason is reported.
- Not in this part: the Snapshots UI (next batch), automatic checkpoints and
  pruning, comparison (SF-1306, own batch).

## Reversal

Stop offering snapshot actions; existing `snapshots/` members are then just
preserved unknown optional members and can be removed with Delete All.
