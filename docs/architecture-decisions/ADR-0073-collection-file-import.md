# ADR-0073 — CSV and JSON import into collections

- Status: Proposed (engine implemented as an unverified Code Forge candidate; the Import tab is ADR-0074; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-037 (approved by the owner 2026-11-26 1:30 PM EST: "only local collections and file import (CSV/JSON) until a connector permission model and credential storage design is approved")
- Builds on: ADR-0071 (collections), ADR-0070 (expression language: number text, dates)
- Requirements: SF-1005-001 … SF-1005-008 (local file import only; connectors, credentials, caching and refresh stay deferred by OD-037)

## Context

OD-037 defers connected data sources and allows one thing now: importing a
local CSV or JSON file into a collection. Collections (ADR-0071) already have a
draft-based editor whose Apply commits the whole draft as one undoable
`setCollections` transaction. Import therefore needs no new stored state: it is
a pure function from a file and a mapping to a new collection value.

## Decision

- Engine: `CollectionImport` in `DocumentModel.swift` (pure, no I/O, no
  stored state, no document schema change; still document schema 27 and
  persisted-history schema 4). Types: `CollectionImportFormat` (`csv`,
  `json`), `CollectionImportError`, `CollectionImportTable`,
  `CollectionImportMapping`, `CollectionImportProblem`,
  `CollectionImportPreview`.
- Reading (`parse`, `parseCSV`, `parseJSON`):
  - at most 5,000,000 bytes, 128 columns and `ContentCollection.maximumItems`
    (10,000) rows; checked before or while reading, so nothing large is kept;
  - CSV is RFC 4180: comma separated, first row names the columns, double
    quotes for cells with commas, quotes or line breaks, `""` for a quote;
    LF, CRLF or CR line ends (line breaks inside a quoted cell are stored as
    LF); a leading UTF-8 byte order mark and blank lines are ignored; every row
    must have as many cells as the header; CSV must be UTF-8;
  - JSON is an array of objects whose values are text, numbers, true, false or
    null; nested values are refused; a byte order mark is ignored; columns are
    every key used, sorted, so key order never changes the result; a missing
    key or null is an absent cell;
  - column names must be non-empty and unique ignoring case;
  - failures are `CollectionImportError` values whose messages name the rule
    and the line or row, never file contents, and say that nothing changed.
- Mapping (`suggestedMapping`, `validate`): a column named `slug` or `address`
  (ignoring case, spaces and punctuation) holds item addresses; any other column
  fills the field whose name or label it matches; each field is filled by at
  most one column. The mapping is never stored. New items default to Draft;
  rows whose address matches an item update it (switchable).
- Per-row checks and resolution (`preview`, SF-1005-003): rows in file order.
  A row with any unusable cell (text over 64 KB or with NUL, a non-number, a
  non-`YYYY-MM-DD` date, an unknown image file name, an unknown referenced
  address, an invalid or repeated address) is skipped whole and reported by row
  and column; the first 1,000 problems are listed and every skipped row is
  counted. Empty cells clear a value; absent cells keep it. An update keeps the
  item's identity and status and is refused when it would leave a required
  field of a published item empty. A new item gets the chosen status, but stays
  a draft when a required field is empty; its address is its own or one made
  from its title, made unique. A skipped row never claims an address. Images
  match by file name, display name or identity ignoring case; references match
  the referenced item's address in the collections passed in (as they were
  before the import). Lookups are built once, so 10,000 rows stay linear.
- Preview and commit: `CollectionImportPreview` holds the resulting collection
  and counts (`summary`, e.g. "Adds 1 item, updates 1, skips 2 rows."). Nothing
  is committed by the engine; the Collections editor is expected to replace the
  collection in its draft, and Apply commits the draft through
  `CollectionEditing.prepare` as one `setCollections` transaction, so undo,
  redo, autosave, history, snapshots and comparison already cover an import.
- Diagnostics (SF-1005-008): `CollectionImport.diagnostic` returns a
  `CollectionEditDiagnostic` with the requirement ID (SF-1005-002, or
  SF-1005-004 on failure), operation, collection identity, item count,
  duration and failure category; never names, file paths or values.
- Security and privacy (SF-1005 critical invariant): no data source, path,
  URL or credential is stored; the file is read once by the user's choice.

## Not built yet (remaining work)

Items 1 and 2 were built by lane V10 on 2026-11-26 (ADR-0074); items 3 and 4
are proposed in OD-080 / deferred by OD-037.

1. **Import tab in the Collections editor** (`CollectionsEditorView`, a new
   `Pane` case): an Import… button using an open panel limited to `.csv` and
   `.json` (`UniformTypeIdentifiers`), reading and previewing off the main
   actor with `Task.detached` (inputs are `Sendable`) and ignoring stale
   results by a generation counter, a column → field picker per column (Skip,
   Address, or a field), New items Draft/Published, Update matching items,
   the preview summary and problem list, and **Add to Draft**, which replaces
   the selected collection in the editor draft and announces the result. Apply
   then commits as one undoable change; Cancel discards it. Accessibility
   identifiers `collections.import.*`. A UI test for the primary journey and
   cancellation.
2. Showing the first rows of the file in the preview (needs the UI).
3. Export of a collection to CSV/JSON (SF-1002 "export content").
4. Connected data sources, credentials, caching, pagination, rate limits and
   refresh (SF-1005 beyond local files): deferred by OD-037 until a connector
   permission model and credential storage design are approved.

## Consequences

- No new stored keys or commands, so no migration and no new copy paths.
- The engine is fully unit-tested without UI
  (`testCollectionImportReadsCSVAndJSONMapsFieldsAndChecksEveryRow`,
  `testCollectionImportRefusesBrokenFilesAndStaysBounded`).
- The Import tab (ADR-0074) makes the capability reachable; see the lane V10
  review for the requirement table.
