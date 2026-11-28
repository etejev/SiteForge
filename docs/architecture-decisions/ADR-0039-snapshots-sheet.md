# ADR-0039 — Snapshots sheet (named snapshots UI)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-043 (approved by the owner 2026-11-26 1:30 PM EST)
- Builds on: ADR-0038 (storage and lifecycle API). Works with ADR-0040 (Compare Versions, SF-1306).
- Requirements: SF-1301-001 … SF-1301-008 (UI part)

## Context

ADR-0038 added named snapshots to the project package and the
`DocumentLifecycleController` API, with no UI. SF-1301 needs a primary
journey for create, inspect, rename, delete and restore, with cancel and
recovery paths, announcements, keyboard operation, and compare from the same
place without an unrelated context switch.

## Decision

- Entry: File > Snapshots… (before Compare Versions…), shown when the new
  feature flag `versions.named-snapshots` (default on, remove by 2027-03-31)
  is on, and disabled when the workspace is not visible or the lifecycle is
  unavailable.
- State lives in `WorkspaceShellState`: `isSnapshotsPresented`,
  `snapshotEntries` (as read from the lifecycle), `snapshotStorageFailure`,
  `snapshotsStatus`; actions `presentSnapshots`, `reloadSnapshots`,
  `createSnapshot`, `renameSnapshot`, `deleteSnapshot`, `deleteAllSnapshots`,
  `restoreSnapshot(_:keepingCurrentAs:)`, `compareSnapshotWithCurrent`,
  `completeSnapshotsDismissal`; helpers `suggestedSnapshotName(base:)`,
  `snapshotNameIssue(_:renaming:)`, `snapshotDetail(_:)`, `snapshotRows`
  (newest first). Every action calls the lifecycle, re-reads the list and
  posts one announcement. The sheet holds only drafts, so it cannot become a
  second source of truth.
- Sheet (`ProjectSnapshotsSheet`, private, in `WorkspaceShellView.swift`):
  name field with live validation and Create Snapshot; newest-first rows
  with creation time, revision and size; per-row Restore…, Compare, Rename…
  (inline field) and Delete… (confirmation). Restore opens an inline panel
  with "Keep the current version as a snapshot first" (on by default unless
  the limit is reached) and a suggested free name ("Before restoring <name>").
  If the stored list cannot be read (damaged, other document or newer
  version) the sheet shows the reason, Try Again and Delete All Snapshots…
  (the recovery action from ADR-0038). Done/Escape closes; drafts are
  discarded and the document is unchanged.
- Compare: the row button closes the sheet and, from the sheet's dismissal,
  opens Compare Versions with that snapshot as the baseline and the current
  document as the other side (two sheets are never presented at once). The
  restore panel's Review Changes… opens it the other way round (current
  document → snapshot), which is exactly what the restore would change
  (`previewSnapshotRestore`, SF-1301-003). Both follow the `versions.compare`
  flag, which the sheet observes. Restore is disabled, with the reason, while
  a component variant is being edited (`canReplaceProjectContent`; ADR-0042).
- Keyboard: every control is a standard button or field; Return submits the
  focused name field, Escape closes the open rename/restore draft first,
  then the sheet.

## Consequences

- Snapshot changes still become durable only with Save; the status text says
  so after each action.
- The flag hides only the menu entry; the state API stays available to tests
  and to Compare Versions.
- No UI test was added (no UI timing change); the journey is covered by a
  state-level test on a real lifecycle, save, reopen and damaged package.

## Reversal

Turn the flag off (menu hidden) or remove the sheet and state block; storage
and the lifecycle API from ADR-0038 are unaffected.
