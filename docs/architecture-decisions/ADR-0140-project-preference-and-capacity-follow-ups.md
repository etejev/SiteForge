# ADR-0140 — Project-preference and capacity follow-ups from the batch 01–03 verification

- Status: Proposed (unverified Code Forge candidate, lane V01; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Requirements: SF-0206-002, SF-0206-004, SF-0206-005, SF-0206-006, SF-0206-007, SF-0206-008, SF-0301-007

## Context

Lane V01 re-verified batches 01–03 (first candidate, tests and browser harness,
project-scoped preferences, ADR-0027) against the current tree. Two later changes
meet batch 03 code:

1. Lane H (ADR-0122) stores the project's build settings inside the same
   `ProjectPreferences` record that the Settings › Project pane edits, but
   Check Website edits them. The pane does not show them. A Check Website save
   while a grid draft was pending made that draft stale, so the only way forward
   was Cancel, which discarded the user's grid choice (SF-0206-004: "Recovery
   MUST preserve user intent"). Reset stayed enabled when the draft held only
   build settings, although Reset then changed nothing.
2. Batch 03's save-limit fix measured project-file capacity on every save and
   autosave but left it unknown after Open ("capacity is unknown after Open until
   the first save/autosave"). Batch 08 (OD-032, ADR-0030) later added the 4 MiB
   per-page limit. A project opened near either limit showed no warning until the
   next save.

## Decision drivers

- The user's draft is never lost because of a change to values the pane does not show.
- A real concurrent change to a value the pane shows still blocks a stale Apply.
- Reset and status text describe what the pane actually removes.
- The capacity warning is truthful as soon as a project is open, without
  slowing the open of ordinary projects and without work on the main actor.
- No schema, package, history or persisted-format change.

## Considered options

1. Leave the pane as is and document the stale-on-build-change behavior.
   Rejected: it discards intent for an unrelated change.
2. Rebase a pending grid draft when only the stored build settings changed;
   treat any change to a grid preference as stale (chosen).
3. Split build settings into their own `CanonicalDocument` key. Rejected: needs
   a new key, a schema gate and a migration for a UI-only problem (ADR-0122
   chose one record on purpose).
4. For capacity: re-encode the whole package on open to measure it exactly.
   Rejected: doubles the open cost of every project.
5. For capacity: measure the bytes that were read; measure pages only when the
   file is near one package member or larger, as a save does (chosen).

## Decision

- `ProjectSettingsStore.documentChanged`: when the pane is dirty and the new
  document's grid preferences (`gridVisibleOnOpen`, `gridSpacing`) equal the
  ones the draft was based on, the draft keeps its grid values, takes the new
  build settings, the committed baseline moves to the new record, the stale flag
  clears, the status names Check Website, and a value-free `rebase-draft`
  diagnostic (SF-0206-002, SF-0206-008) is recorded. Any other change keeps the
  existing stale behavior.
- `ProjectSettingsStore.draftHasGridPreferences` gates the Reset button and its
  accessibility value. `begin()` and `apply()` status text depend on whether a
  grid preference is set, not on whether any record exists.
- `ProjectFileCapacity.opened(fileBytes:document:)` measures an opened file:
  `fileBytes` is the validated file read; the largest page is measured with
  `ProjectPackageStore.encodedPages(of:)` only when the file is at least 85% of
  one package member (`warningFraction` × `maximumMemberBytes`).
  `DocumentLifecycleBackend.read(from:identity:progress:)` computes it on the
  backend actor and returns it in `LoadedProject.capacity`; the controller adopts
  it on Open and Revert. Recovery restore still starts unmeasured, and the next
  save or autosave replaces the value with what it wrote.
- Unrelated, same review: the `CanvasWorldGridPolicy` doc comment is attached to
  the declaration it describes, and the Settings pending-drafts notice is labelled
  "Unsaved preference drafts" (it also lists Project drafts).

## Consequences

### Positive

- A Check Website save no longer costs the user a pending grid draft; Apply then
  writes both values as one undoable transaction.
- The status bar warns near the 8 MB file or 4 MB page limit as soon as such a
  project opens.
- No data-format, schema or history change.

### Negative or risky

- An opened file's measurement reflects the stored file (possibly an older
  document schema). The next save can differ slightly; it then replaces the value.
- Opening a file of at least about 3.4 MiB now encodes its pages once more on the
  backend actor (the same work a save does).
- Not compiled or run (Windows, no Swift toolchain).

## Verification

- `SiteForgeTests/CanvasSettingsTests/testProjectSettingsPaneKeepsGridDraftAcrossBuildSettingChanges`
- `SiteForgeTests/DocumentLifecycleTests/testProjectFileCapacityIsMeasuredWhenAProjectIsOpened`
- Existing batch 03 selectors must stay green, in particular
  `CanvasSettingsTests/testProjectSettingsStoreDraftApplyCancelStaleResetAndNoProject`,
  `CanvasSettingsTests/testBuildSettingsSaveUndoRedoRepairsAndStaleReview` and
  `DocumentLifecycleTests/testProjectFileCapacityIsMeasuredOnSaveAndAutosaveAndWarnsNearTheLimit`.

## Reversal

If build settings move to their own canonical key, remove the rebase branch (the
pane would no longer see them). If open-time page measurement proves too slow on
named hardware, measure only `fileBytes` on open and leave the page to the next
save; the struct and the status bar already handle a missing page measurement.
