# Lane RD review — lane D (data): expressions, collections, template and list pages, file import

- Reviewer: lane RD (Code Forge lane R, reviewer D), 2026-11-26, during the review freeze.
- Restore point before the review: `RP-2026-11-26-R01`. All writes through `forge_io.edit` / `write_new` (owner `lane-RD`).
- Still document schema 27, persisted-history schema 4, WebsiteMetadata version 3. No new `CanonicalDocument` keys, no new commands, no new Swift files.
- Unverified: no Swift compiler on this PC. Every change was re-read against the declarations it calls.

## Scope

| Batch | Feature | Decision / ADR | Modules |
|---|---|---|---|
| D01 | Expression language | OD-036, ADR-0070 | SF-1004 |
| D02 | CMS collections + Collections editor | OD-035, ADR-0071 | SF-1001, SF-1002 |
| D03 | Template (item detail) pages and bindings | OD-035, ADR-0072 | SF-1003 |
| D04 | Collection list pages (filter, order, limit, pagination) | OD-035, ADR-0072 | SF-1003 |
| D05 | CSV/JSON import engine (partial, no activity entry before this review) | OD-037, ADR-0073 (new) | SF-1005 |

Files reviewed: `SiteForge/DocumentModel.swift` (expression engine 7865–9013; collections, templates, lists, import, editing 10216–12545),
`SiteForge/CanvasRendererCore.swift` (`MultiPageStaticBuildPlanner.plan` collection/list output, relative links and image sources,
`StaticBuildCompiler` item/list image export, `StaticOutputReferenceAudit` interplay), `SiteForge/WorkspaceShellView.swift`
(`CollectionsEditorView`, lines 7–1000), `SiteForge/WorkspaceShellModel.swift` (collections presentation/commit),
`SiteForge/BrowserPreview.swift` (template preview), `SiteForge/CommandKernel.swift` (`setCollections`, image-removal refusal),
`SiteForge/ProjectPackage.swift` (snapshot restore, `ProjectComparer.compare` / `sameUncomparedContent`),
`SiteForge/PackagedSiteTemplate.swift`, `SiteForge/ProjectResources.swift`; tests in `Tests/SiteForgeTests/BlankProjectTests.swift`
(3 D01 tests) and `Tests/SiteForgeTests/PersistedHistoryTests.swift` (6 D02–D04 tests, 2 new D05 tests).

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `Tests/SiteForgeTests/PersistedHistoryTests.swift` | `testCollectionListRepeatsALayerPerItemFilteredOrderedAndPaginated` | Expected `href="../blog.html"` and `href="../posts/charlie.html"` from `blog/page/2.html`. That file is two folders deep; `SiteLanguageOutput.relativePath(from: ["blog","page"], to:)` correctly gives `../../…` (and the image rewrite gives `../../assets/`). The test would fail. | Expect `../../blog.html` and `../../posts/charlie.html`. | Test was wrong, implementation right (and consistent with the E04 language-tree test, which is one folder deep and expects `../`). |
| 2 | `SiteForge/DocumentModel.swift` | `CollectionImport.preview` | A row skipped for a bad cell still reserved its address (`seenInFile.insert` ran before the skip), so a later valid row with that address was wrongly refused as a duplicate. | Address is claimed only by a row that is used (update or add). | SF-1005-003/004: a skipped row must not change the outcome of other rows. |
| 3 | `DocumentModel.swift` | `CollectionImport.preview` | Update lookup `result.items.firstIndex(where:)` per row, reference lookup `collections.first`/`items.first` per cell, image lookup per cell: O(rows × items) — up to 10⁸ comparisons at the 10,000-item bound. | Private `CollectionImport.Lookup` built once (asset names, referenced item addresses); `indexBySlug` dictionary for updates. | SF-1005-007: bounded, linear import at the documented maximum. |
| 4 | `DocumentModel.swift` | `CollectionImport.preview` | `CollectionSlug.unique` restarts at suffix 2 for every row, so 10,000 rows with one title cost ~5·10⁷ set probes. | Local `uniqueSlug` keeps the next suffix per base; same result as `CollectionSlug.unique`. | SF-1005-007 (covered by the new 10,000-row test). |
| 5 | `DocumentModel.swift` | `CollectionImport.preview`, `CollectionImportPreview.maximumProblems` | Problem list unbounded (10,000 rows × 128 columns = 1.28 M records). | List the first 1,000 problems; `skipped` still counts every skipped row. | SF-1005-007 memory bound. |
| 6 | `DocumentModel.swift` | `CollectionImport.preview` | With an address column, an empty address cell skipped the row as an invalid address, contradicting the documented "own address or one made from its title". | Empty address cell → new item with an address made from its title. | Matches the engine's own doc comment and the ADR. |
| 7 | `DocumentModel.swift` | `CollectionImport.parseCSV` | A CRLF or CR inside a quoted cell was stored verbatim (CR in item text) and a lone CR inside quotes did not advance the line counter. | Line breaks inside quoted cells are stored as LF; line counting follows. | Rich text stores LF line breaks; error lines stay correct. |
| 8 | `DocumentModel.swift` | `CollectionImport.parse` (`.json`) | A UTF-8 byte order mark was stripped for CSV but not JSON. | BOM ignored for JSON too. | Spreadsheet/Windows exports often add a BOM. |
| 9 | `DocumentModel.swift` | `CollectionImport.diagnostic` | Failure records used SF-1005-002. | SF-1005-004 when an error is recorded (mirrors `CollectionEditing.diagnostic`). | SF-1005-008 requirement IDs. |
| 10 | `DocumentModel.swift` | `CollectionImportError.ragged` message, `CollectionImportProblem` doc | "different number of cells than the first row" (ambiguous: row 1 is the first data row); doc said column is 1-based while it is stored 0-based. | "…than the header row"; doc states 0-based storage, 1-based messages. | Precise, testable messages. |
| 11 | `DocumentModel.swift` | `CollectionImport.convert` | `CharacterSet(charactersIn:)` built for every scalar of every number cell. | ASCII byte check (same accepted characters). | Cost per cell; no behaviour change. |
| 12 | `SiteForge/WorkspaceShellView.swift` | `CollectionsEditorView.fieldsPane` / `fieldRow` / `footer` | `issues` (a full validation of every item of every collection) was recomputed 3× per field row and 3× in the footer on every render. | Computed once per pane / footer; `fieldRow` takes the field's `issue` (now also filtered by collection). | SF-1001-007 / SF-1002-007 with large collections. |
| 13 | `WorkspaceShellView.swift` | `CollectionsEditorView.fieldRow` | Label, Name and Required controls of every field row had the same VoiceOver label ("Label", "Name", "Required"). | `accessibilityLabel` names the field ("Price label", "Price name in expressions", "Price required"). Identifiers unchanged. | SF-1001-006. |

Defects found: 13; fixed: 13. Files changed: `SiteForge/DocumentModel.swift`, `SiteForge/WorkspaceShellView.swift`,
`Tests/SiteForgeTests/PersistedHistoryTests.swift`; new `docs/architecture-decisions/ADR-0073-collection-file-import.md` and this report.

Checked and found correct (no change): D01 lexer/parser/checker/evaluator against all three D01 tests (every asserted value
recomputed by hand, including precedence, `round`/`format` output, missing-value rules, token/node/depth limits); D02 strict
decoding, schema-27 gate, `setCollections` command/inverse/history, snapshot restore (`ProjectPackage` restore command),
template copy (`PackagedSiteTemplate`), `ProjectComparer.compare` and `sameUncomparedContent` both list `collections`,
image-in-use refusal and unused-asset rule; D03/D04 `fileprivate` `CollectionTemplates.Compiled` / `CollectionLists.Placement`
use within the file, nested `report`/`control` functions, `CanonicalEventGraph.remappingTargets(_:nodeMap:freshIdentity:)`
call, `DocumentNode` memberwise init labels, `OutputPage` default `listPageNumber`; exhaustive switches over
`DocumentCommand`/`CommandName` include `setCollections`; `ModelValidationError.invalidCollections` has its message;
`CollectionIssue.Kind` and `CollectionTemplateFinding.Kind` messages cover every case.
Lane H's `output-reference-unresolved` check (`StaticOutputReferenceAudit.resolves`) resolves `../` from the file's folder, so
page-relative links and `src` on item pages and later list pages resolve; no lane D test asserts on compiler warnings
(`testCollectionTemplatePageBuildsOneEscapedPagePerPublishedItem` only unwraps `compiled.plan` and checks binaries).
The D03 test's `contains("assets/<hash>.png")` assertions still hold with `src="../assets/…"`.

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-1001-001 | Met | `ContentCollection`/`CollectionField`/`CollectionItem` strict Codable, stable IDs, omitted keys, schema-27 gate; `testCollectionsAreStrictSchemaGatedUndoableAndPersistedInHistory` |
| SF-1001-002 | Met | `CollectionEditing.newCollection/addField/removeField/changeType/moveField/removeCollection`; Fields tab |
| SF-1001-003 | Partial | Expression schema/context rules (`expressionSchema(in:)`); no field defaults or localized values yet |
| SF-1001-004 | Met | `CollectionIssue` by identity; type change and collection removal refuse data loss; `testCollectionRulesProtectDataAndEditorOperationsAreDeterministic` |
| SF-1001-005 | Met | One `setCollections` transaction; persisted history restore in the D02 test |
| SF-1001-006 | Partial | Labels/identifiers (`collections.*`), announcements; field-row labels fixed here; no UI test |
| SF-1001-007 | Partial | Bounds (100 collections, 64 fields, 10,000 items); validation linear; editor still validates the whole draft per render |
| SF-1001-008 | Met | `CollectionEditDiagnostic` (ids and counts only); D02 tests |
| SF-1002-001 | Met | Editor draft separate from the document; Apply/Cancel |
| SF-1002-002 | Met | Items: new, duplicate, delete with confirmation, status, search, status filter, Publish Ready Drafts |
| SF-1002-003 | Partial | Deterministic search/filter; no scheduling metadata or author |
| SF-1002-004 | Met | Invalid draft kept, Apply disabled with the first rule; busy/stale/unchanged errors; last valid number/date kept |
| SF-1002-005 | Met | Whole draft = one undoable transaction (D02 test) |
| SF-1002-006 | Partial | Labels, identifiers, keyboard default/cancel actions; no UI test |
| SF-1002-007 | Partial | `List` is lazy; whole-draft validation per render (reduced here) |
| SF-1002-008 | Met | `CollectionEditing.diagnostic`; D02 tests |
| SF-1003-001 | Met | `CollectionTemplate`, `CollectionList`, `CollectionBinding` strict records; D03/D04 record tests |
| SF-1003-002 | Met | Template and Lists tabs; `CollectionEditing` template/list operations |
| SF-1003-003 | Met | `CollectionListResolution.explanation`, `??` fallbacks, live first-item preview |
| SF-1003-004 | Met | `CollectionTemplateFinding` keeps intent (missing page/layer/field/expression) and the page is written as designed |
| SF-1003-005 | Met | Through `setCollections`; D03/D04 undo/redo/reopen tests |
| SF-1003-006 | Partial | Pickers/fields labelled; findings shown as text; no binding inspection on the canvas; no UI test |
| SF-1003-007 | Partial | Deterministic output; `CollectionLists.placements` is recomputed by `outputPages`, `stylePages`, `linkRoutes` and the compiler per build |
| SF-1003-008 | Met | `CollectionTemplates.diagnostic`, `CollectionLists.diagnostic`; four D03/D04 tests |
| SF-1004-001 | Met | `SiteExpression` stored record (version 1, exact keys); D01 tests |
| SF-1004-002 | Partial | Expression fields in Template/Lists tabs; `functionSignatures` not shown in the UI |
| SF-1004-003 | Partial | `SiteExpressionDecision` provenance in the engine; UI shows only the first-item result |
| SF-1004-004 | Met | Located `SiteExpressionError`s, runtime findings, total evaluation |
| SF-1004-005 | Met | Expressions persist inside collections via `setCollections` |
| SF-1004-006 | Partial | Error text in notes; no source-range highlighting |
| SF-1004-007 | Met | Byte/token/node/depth limits; 10,000 evaluations test |
| SF-1004-008 | Met | `SiteExpressionDiagnostic`; D01 tests |
| SF-1005-001 | Partial (by OD-037) | No stored data source by design; import is a pure transform; no secrets stored |
| SF-1005-002 | Partial | Engine: parse, suggested mapping, preview; **no Import tab yet** |
| SF-1005-003 | Partial | Deterministic row rules and `CollectionImportPreview.summary`/problems; not surfaced in UI |
| SF-1005-004 | Met (engine) | `CollectionImportError`/`CollectionImportProblem` by line/row/column, nothing changes; new tests |
| SF-1005-005 | Met (engine) | Result applied through `CollectionEditing.prepare` → one undoable `setCollections` (new test executes, undoes, redoes, reopens) |
| SF-1005-006 | Missing | No UI |
| SF-1005-007 | Met | 5 MB / 128 columns / 10,000 rows / 1,000 listed problems; linear lookups; 10,000-row test |
| SF-1005-008 | Met | `CollectionImport.diagnostic` (SF-1005-002 / -004); new tests |

## Remaining gaps (easiest → hardest)

1. Show `SiteExpressionEngine.functionSignatures` as a help popover/menu next to expression fields (SF-1004-002). Small UI.
2. Show `SiteExpressionEvaluation.decisions` explanations under the first-item preview (SF-1004-003).
3. Compute `CollectionLists.placements` once per build and pass it to `outputPages`, `stylePages` and `linkRoutes` (SF-1003-007); keep the public functions as wrappers.
4. Editor: cache `CanonicalCollections.issues(draft)` per draft change (e.g. `onChange(of: draft)` into `@State`) instead of per render (SF-1001-007).
5. **Import tab** in `CollectionsEditorView` (SF-1005-002/003/006) — plan in ADR-0073 "Not built yet": open panel (`.csv`, `.json`), parse + preview in `Task.detached` with a generation counter, per-column picker (Skip / Address / field), Draft/Published, Update matching items, summary + problems, **Add to Draft** replacing the selected collection in the draft; Apply commits one undoable change. UI test for the journey and cancellation.
6. Collection export to CSV/JSON (SF-1002 "export content").
7. Field defaults, localized field values and schema migration previews (SF-1001 scope).
8. Binding inspection on the canvas (which layer is bound to what) and sample-record preview on the canvas (SF-1003 scope).
9. Scheduling metadata and authors (SF-1002 scope) — needs an owner decision (no OD yet).
10. Connected data sources (SF-1005 beyond files) — deferred by OD-037.

Cross-lane observations (not changed by RD):
- `ProjectComparer.compare` reports a localization difference twice ("Languages" and "Site languages", lines ~1849 and ~1858 of `ProjectPackage.swift`).
- `MultiPageStaticBuildPlanner.plan` rewrites only ` src="assets/` for pages in folders; a ` poster="assets/…"` (lane F media) or an inline `style="…url(assets/…)"` on an item page, later list page or language page would stay root-relative and be flagged by lane H's `output-reference-unresolved`.

## Intended OD status-line changes (not written: `OPEN_DECISIONS.md` is iCloud-renamed)

- OD-037: "Implementation status: local CSV/JSON import engine (SF-1005, files only) complete in source, not verified (Code Forge batch D05, reviewed by lane RD 2026-11-26, ADR-0073); the Import tab of the Collections editor is not built; connectors stay deferred."
- OD-035: append "Lane RD review 2026-11-26: list-page test paths corrected; editor validation and field accessibility labels improved."
- OD-036: unchanged.

## New/changed test selectors

New:
```
SiteForgeTests/PersistedHistoryTests/testCollectionImportReadsCSVAndJSONMapsFieldsAndChecksEveryRow
SiteForgeTests/PersistedHistoryTests/testCollectionImportRefusesBrokenFilesAndStaysBounded
```
Changed (expected relative links from `blog/page/2.html`):
```
SiteForgeTests/PersistedHistoryTests/testCollectionListRepeatsALayerPerItemFilteredOrderedAndPaginated
```
Unchanged, to run with them: the D01 tests in `BlankProjectTests` (`testExpressionLanguage…` ×2, `testStoredExpressionRoundTrips…`),
`testCollectionsAreStrictSchemaGatedUndoableAndPersistedInHistory`, `testCollectionRulesProtectDataAndEditorOperationsAreDeterministic`,
`testCollectionTemplatePageBuildsOneEscapedPagePerPublishedItem`, `testCollectionTemplateRecordIsStrictUndoableAndPreviewedLive`,
`testCollectionListRecordIsStrictBoundedAndUndoable`, and the E04 test `testSiteLanguagesExportOneTreePerLanguageWithAlternatesAndTranslations`.
No UI tests; `scripts/ci-ui-timings.txt` unchanged.

## Suggested first checks for Codex

1. `CollectionImport.parse`: `parseJSON(data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data)` (Data slice type, `starts(with:)` on `[UInt8]` literal).
2. `CollectionImport.preview`: nested `uniqueSlug` / `skip` capturing and mutating `slugs`, `nextSuffix`, `problems`, `skipped`; `problems += rowProblems.prefix(…)`; `skip([.init(kind: .requiredMissing, row: row)])` (memberwise init with defaulted `column`).
3. `CollectionImport.Lookup.init` mutating defaulted stored properties; `lookup.itemsBySlug[targetID]?[trimmed]`.
4. `CollectionImport.JSONScalar` decoding order (Bool before Double) on the macOS Foundation in use: `7` must become `"7"`, `true` must become `"true"`.
5. New tests: `[String?]` comparisons with string-array literals (`table.rows[1]`, `jsonTable.rows[1]` with `nil`s); `error: .ragged(row: 2)` passed to an optional parameter; `String(data:encoding: .utf8)` with a BOM (either behaviour passes); `Double("1e400")` (nil or infinity both give `.number`); the 10,000-row timing bound (10 s).
6. `CollectionsEditorView.footer`: `let found = issues` inside the `HStack` view builder; `fieldsPane` now `let …; return ScrollView`; `fieldRow(_:offset:count:issue:)` call site.
7. D04 test `href="../../blog.html"` / `href="../../posts/charlie.html"` from `blog/page/2.html`.
8. Carried over from D02–D04 (not re-verifiable here): fixture stack/link nodes in the D04 test passing `document.validate()`, the `styles.css` selector for a slot-1 copy, `List(…, selection:)` with an optional `CollectionItemID`, and `confirmationDialog(…, presenting:)`.
