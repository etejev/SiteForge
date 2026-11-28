# ADR-0132: Named history list, jump to a state, and page-following Undo

- Status: Proposed
- Date: 2026-11-26
- Requirements: SF-0307-001 through SF-0307-006 (bounded)
- Related: ADR-0003 (bounded persisted history), ADR-0131 (coalesced and named transactions)

## Context

Undo and Redo moved one step at a time, with only the next label visible. An
Undo of an edit on another page changed a page the user could not see, and
nothing told the user that saving keeps only the newest history entries.

## Decision

- `DocumentSession.historyList()` returns `HistoryListItem`s: applied entries
  oldest first, then the entries Redo would apply, nearest first. Each item has
  the transaction id, the ADR-0131 display name, timestamp, applied/current
  flags, the pages it changes (from the entry's page targets) and
  `persistsOnSave`, false for the items saving drops beyond
  `PersistedHistoryStore.maximumEntryCount`: the oldest Undo items first, then
  the farthest Redo items, exactly as `PersistedHistoryStore.removingOldest`
  does (the byte limit can drop more).
- `jump(toStateAfter:)` moves to the state after an entry (nil: the oldest
  reachable state) with ordinary Undo/Redo steps, so the history boundary and
  validation rules are unchanged. If a step fails, the steps taken are reversed
  and the error is thrown; an unknown id is refused without changes. Jumping
  deletes nothing, so the user can always come back.
- Workspace: `historyItems`, `jumpToHistory(_:)` (same edit boundaries as Undo,
  announced, failure in `historyJumpFailure`), and Undo, Redo and jumps follow
  the changed page (`followHistoryPage`) when the change is on another website
  page that still exists. Edits on the shown page keep the page. A jump uses
  the pages of every step it undoes or redoes, the last step taken first
  (`historyJumpPageIDs`). Nothing switches while a component definition is open
  (review RI, 2026-11-26).
- UI: a History button in the status bar (`status.history`) opens a popover
  listing the steps (`history.item`, `history.oldest`, `history.failure`), with
  VoiceOver labels, values (Current state / Done / Undone) and a hint, and a
  note on how many changes saving keeps.

## Consequences and limits

- No document, package or history schema change; persisted history remains
  limited to 128 entries and 512 KiB.
- History entries for component-definition pages do not switch pages (those
  pages are not website pages).
- Edit > Show History… (Command-Y) opens the same list since ADR-0133; rows
  are identified as `history.item.<transaction id>`. There is no UI test yet.
