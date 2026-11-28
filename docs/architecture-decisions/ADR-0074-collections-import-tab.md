# ADR-0074 — Import tab of the Collections editor

- Status: Proposed (implemented as an unverified Code Forge candidate by lane V10, 2026-11-26; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-037 (approved 2026-11-26 1:30 PM EST: local collections and file import only) and OD-035 (Collections editor)
- Builds on: ADR-0073 (import engine), ADR-0071 (collections, draft editor), ADR-0070 (expressions)
- Requirements: SF-1005-002, -003, -004, -005, -006, -007, -008; SF-1001-007; SF-1002-004; SF-1004-002, -003, -006

## Context

ADR-0073 built a pure CSV/JSON import engine but left it unreachable: the
Collections editor had no Import tab. Users must be able to choose a file,
see what it would do, choose what each column fills and add the result to
the editor draft, which Apply commits as one undoable change.

## Decision

- **Tab.** `CollectionsEditorView.Pane.fileImport` ("Import"), between Lists
  and Settings, for the selected collection. Changing the selected
  collection resets the import.
- **Reading (`CollectionImport.read(_:)`, `DocumentModel.swift`).** The
  engine's only file access. The format comes from the extension
  (`CollectionImportFormat(fileExtension:)`, `.csv` / `.json`, ignoring
  case); the size is checked from file metadata *before* reading, then the
  bytes are parsed by `parse`. Failures are `CollectionImportError`
  values: new `.unreadable` and `.unsupportedFormat`. Messages never name the
  path. The URL is used once and never stored.
- **Off the main actor.** Choose File… runs an `NSOpenPanel` limited to
  `.commaSeparatedText` and `.json`, then reads in `Task.detached`. Previews
  run in `Task.detached` from `.task(id: ImportRequest)`, where the request
  is (generation, mapping, collection): any change restarts the preview and
  SwiftUI cancels the old task. Every new file, Cancel Import and Add to
  Draft bumps `importGeneration`, so a late result is ignored. All inputs
  are `Sendable` values (table, mapping, collections, image assets).
- **Columns.** One picker per column: Skip, Address or a field
  (`CollectionImportColumnTarget`). `CollectionImportMapping.assign(_:toColumn:)`
  moves a field or the address from any other column, so the editor can
  never build a mapping that fills a field twice; `target(ofColumn:)` reads it
  back. Each column shows an example from the first five rows
  (`CollectionImportTable.example(column:)`, one line, at most 60
  characters). The suggested mapping (ADR-0073) is the starting point.
- **Options.** New items Draft (default) or Published; Update items with the
  same address (default on).
- **Preview.** The engine summary (`CollectionImportPreview.summary`) and the
  first 50 problem messages with a count of the rest; Add to Draft is
  disabled while working or when nothing would be added or updated.
- **Add to Draft (`CollectionImport.merge`).** Replaces the collection in the
  draft with the preview's result only when the draft still holds the exact
  collection the preview was made from; otherwise `.stale` and nothing
  changes. The editor then resets the import, shows Items and announces the
  summary. Apply commits the draft through `CollectionEditing.prepare` as
  one `setCollections` transaction (undo, redo, autosave, history,
  comparison as for any collection edit); Cancel discards it.
- **Address rule fix.** An address the engine makes from a title is now
  claimed for the rest of the file, so a later row naming it is a duplicate
  instead of updating the item this import just added.
- **Numbers.** `CollectionImport.parseNumber` is shared by import and the
  editor's number fields, so every number the editor shows (including
  exponent forms that `SiteExpressionEngine.numberText` writes, such as
  `1e+20`) can be typed back. Previously the editor accepted only digits,
  `.` and `-`.
- **Diagnostics.** `WorkspaceShellState.recordCollectionsDiagnostic(_:)`
  stores `CollectionImport.diagnostic` for reads that fail
  (`import-read`, SF-1005-004) and for Add to Draft (`import`, SF-1005-002):
  identities and counts only.
- **Accessibility.** Identifiers `collections.import`, `.choose`, `.file`,
  `.cancel`, `.error`, `.size`, `.column.<n>`, `.status`, `.updates`,
  `.summary`, `.problems`, `.add`. Column pickers are labelled
  "<column> fills"; progress is labelled; results are announced.
- **Editor responsiveness (SF-1001-007).** The draft's rule check
  (`CanonicalCollections.issues`) is kept in `@State` and recomputed in
  `onChange(of: draft)` instead of on every render.
- **Expressions (SF-1004-002/003).** Every expression field has a function
  menu (`SiteExpressionEngine.functionSignatures`; choosing one appends its
  name) and, under the first-item preview, which rule won and why
  (`CollectionEditing.templatePreviewExplanation`: the evaluator's
  decisions, then runtime findings, each once). When the expression cannot
  be used, the editor shows it with the error's range underlined, the place
  in words for VoiceOver and the error's recovery suggestion
  (`CollectionEditing.templatePreviewProblem`, SF-1004-006); the
  suggestions already referred to "the highlighted part" and "the list of
  available functions".

## Not built (blocked)

- A UI test for the Import journey: the system open panel runs out of
  process, so the test needs a test-only way to hand the editor a file and a
  Mac to time it for `scripts/ci-ui-timings.txt`. Proposed in OD-080.
- Collection export, field defaults, localized field values, schema-change
  previews, scheduling and authors, and binding inspection on the canvas are
  outside OD-035/OD-037; proposed in OD-080.
- Connected data sources stay deferred by OD-037.

## Consequences

- No stored keys, commands or schema changes: still document schema 27,
  persisted-history schema 4, WebsiteMetadata version 3.
- New `CollectionImportError` cases (`unreadable`, `unsupportedFormat`,
  `stale`); every `switch` over the type is inside the type.
- Tests: `testCollectionImportTabReadsAFileMapsColumnsAndAddsToTheDraftAsOneUndoableChange`,
  `testCollectionExpressionPreviewExplainsWhichRuleWonForTheFirstItem`,
  `testCollectionListResolutionStaysFastAndOrderedForTenThousandItems`
  (all in `PersistedHistoryTests`).
