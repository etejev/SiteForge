# Lane V10 review — lane D (data / CMS): expressions, collections, template and list pages, file import

- Reviewer: lane V10 (Code Forge lane V, verification), 2026-11-26, owner request 6:55 PM EST ("treat every batch as unverified … finish partial features too").
- Start state: `RP-2026-11-26-V00`. All writes through `forge_io.edit` / `write_new` (owner `lane-V10`). No compiler on this PC: every change was re-read against the declarations it calls.
- Still document schema 27, persisted-history schema 4, WebsiteMetadata version 3. No new `CanonicalDocument` keys, no new commands, no new Swift files, no stored-format change.

## Scope

| Batch | Feature | Decision / ADR | Modules | Diffed / read |
|---|---|---|---|---|
| D01 | Expression language | OD-036, ADR-0070 | SF-1004 | RP-D01 → V00; lexer, checker, evaluator decisions, limits, `numberText` re-read |
| D02 | Collections + Collections editor | OD-035, ADR-0071 | SF-1001, SF-1002 | model, rules, `CollectionEditing`, editor, command/history/snapshot/template/comparer paths |
| D03 | Template (item) pages and bindings | OD-035, ADR-0072 | SF-1003 | RP-D03 → V00; `CollectionTemplates`, planner output, compiler image export |
| D04 | List pages (filter, order, limit, pagination) | OD-035, ADR-0072 | SF-1003 | RP-D04 → V00; `CollectionLists`, list editing, Lists tab |
| D05 | CSV/JSON import engine | OD-037, ADR-0073 | SF-1005 | RP-D05 → V00 (in lane D regions only the engine insert + RD fixes changed) |
| RD | Lane R review fixes (13) | ADR-0073 | SF-1001…1005 | every RD fix re-read in current code; both D05 tests recomputed by hand |

Files read in the changed regions: `SiteForge/DocumentModel.swift` (expression engine; collections model, rules, templates, lists,
import, editing), `SiteForge/WorkspaceShellView.swift` (`CollectionsEditorView`), `SiteForge/WorkspaceShellModel.swift` (collections
section), `SiteForge/CanvasRendererCore.swift` (planner collection/list output, page-relative links and sources, compiler image export),
call sites in `CommandKernel.swift`, `PersistedHistory.swift`, `ProjectPackage.swift`, `PackagedSiteTemplate.swift`, `ProjectResources.swift`;
the 8 lane D tests in `Tests/SiteForgeTests/PersistedHistoryTests.swift`.

Files changed by V10: `SiteForge/DocumentModel.swift`, `SiteForge/WorkspaceShellView.swift`, `SiteForge/WorkspaceShellModel.swift`,
`Tests/SiteForgeTests/PersistedHistoryTests.swift`, `docs/architecture-decisions/ADR-0073-collection-file-import.md`;
new `docs/architecture-decisions/ADR-0074-collections-import-tab.md` and this report.

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `DocumentModel.swift` | `CollectionImport.preview` | An address made from a row's title was not claimed for the rest of the file, so a later row naming it (e.g. `spring-sale`) *updated the item this import had just added* and was counted as an update. | The generated address is inserted into `seenInFile` too; the later row is skipped as `duplicateSlug`. | SF-1005-003: deterministic, explainable row rules; an import never rewrites its own new rows. |
| 2 | `WorkspaceShellView.swift` | `CollectionsEditorView.parse(_:as:)` | Number fields accepted only `0-9 . -`, but the editor itself shows large or tiny numbers in exponent form (`SiteExpressionEngine.numberText(1e20)` = `1e+20`) and import accepts them: a shown value could not be typed back (silently kept the old value). Also built a `CharacterSet` per scalar. | Uses the new shared `CollectionImport.parseNumber` (digits, sign, point, exponent, finite). | SF-1002-004: the last valid value is kept only for genuinely invalid text. |
| 3 | `WorkspaceShellView.swift` | `CollectionsEditorView.issues` | `CanonicalCollections.issues(draft)` (every item of every collection, string sorts per item) was a computed property evaluated by the footer, fields, settings, template and lists panes on **every render**, including keystrokes in Search. | `@State issues`, set in `init` and in `.onChange(of: draft)`. Apply still re-validates in `CollectionEditing.prepare`. | SF-1001-007 / SF-1002-007 with the 10,000-item fixture. |
| 4 | `WorkspaceShellView.swift` | `CollectionsEditorView.expressionField` | `SiteExpressionError.recoverySuggestion` tells users to "choose a function from the list of available functions" and to check "the highlighted part", but the editor showed neither (RD gaps 1, SF-1004-006). | Function menu (`SiteExpressionEngine.functionSignatures`, appends the name) and the expression with the error's range underlined, its place for VoiceOver and the suggestion (`CollectionEditing.templatePreviewProblem`). | SF-1004-002 / -006: the UI now matches its own messages. |
| 5 | `docs/architecture-decisions/ADR-0073-collection-file-import.md` | Status / "Not built yet" / Consequences | Said the engine was unreachable and listed the Import tab as not built. | Points to ADR-0074; items 1–2 built, 3–4 in OD-080 / OD-037. | Dev doc matches code. |

Defects found: 5; fixed: 5. (A defect in my own Import-tab draft — no preview when the suggested mapping equals the empty one, because the
`.task(id:)` key did not change — was caught on re-read and fixed with `ImportRequest.hasTable` before completion; not counted.)

Verified correct, no change: all 13 RD fixes (import address claiming, `Lookup`, per-base suffixes, 1,000-problem bound, empty address cell,
quoted CR/CRLF, JSON BOM, SF-1005-004 diagnostics, messages, ASCII number check, editor validation once per pane, field-row VoiceOver labels,
`../../` list test paths); both D05 tests recomputed value by value (problem kinds/rows/columns, summary strings, JSON column order and
`numberText(7)` = `7`, required-field rules, 10,000-row linear path); D01 lexer (`Unicode.Scalar` comparisons, 24-digit bound, escapes),
decision recording (`missingField` once, `if`/`default`/`??`); D02 strict decoding of every record (explicit nulls refused, empty lists
omitted), schema-27 gate in `DocumentSerializer`, `setCollections` command/history payload keys/descriptor, snapshot restore,
`PackagedSiteTemplate` copy, `ProjectComparer.compare` + `sameUncomparedContent`, unused-asset rule; D03/D04 `fileprivate`
`Compiled`/`Placement` use, `PropertyKey(rawValue:)` (non-failable) and `NodeProperty.origin`, language passes building item/list pages
per language (`passOutputPages`), compiler exporting images used only by item pages and list copies, `poster=` now rewritten for pages in
folders (fixed by another lane since RD). Collections store `PageID`/`NodeID` only at document level (template page, bindings, lists), never
as node properties, so none of the six node copy paths needs a remap; a deleted page/layer is kept and reported (`missingPage`, `missingNode`,
`listLayerMissing`).

## Features finished

| Item | ADR / OD | What was built | Tests |
|---|---|---|---|
| D4 Import tab (SF-1005) | ADR-0074 (new), OD-037 | `Pane.fileImport` "Import"; Choose File… (`NSOpenPanel`, `.commaSeparatedText`/`.json`); `CollectionImport.read(_:)` (format from extension, size checked from metadata before reading, `.unreadable` / `.unsupportedFormat`) run in `Task.detached`; preview in `Task.detached` from `.task(id: ImportRequest)` with a generation counter (stale results dropped, Cancel Import); per-column picker Skip / Address / field (`CollectionImportColumnTarget`, `CollectionImportMapping.target(ofColumn:)` / `assign(_:toColumn:)` that moves a field or the address instead of duplicating it); per-column example from the first rows (`CollectionImportTable.example(column:)`); New items Draft/Published; Update matching items; summary + first 50 problems; **Add to Draft** via `CollectionImport.merge` (refuses a stale preview with `.stale`), then Apply = one undoable `setCollections`; announcements; identifiers `collections.import.*`; diagnostics via `WorkspaceShellState.recordCollectionsDiagnostic(_:)`. | `testCollectionImportTabReadsAFileMapsColumnsAndAddsToTheDraftAsOneUndoableChange` (read, formats, examples, mapping moves, preview incl. fix 1, merge + stale, execute/undo/redo/reopen, read failures and size bound, messages without paths, shared number rule, diagnostics) |
| D1 follow-ups (SF-1004-002/003/006) | ADR-0074, OD-036 | Function menu on every expression field; under the first-item preview, which rule won and why (`CollectionEditing.templatePreviewExplanation`: evaluator decisions then runtime findings, each once); error range underlined with place and recovery suggestion (`CollectionEditing.templatePreviewProblem`). | `testCollectionExpressionPreviewExplainsWhichRuleWonForTheFirstItem` |
| RD gap 3/4 (SF-1003-007, SF-1001-007) | ADR-0074, OD-035 | Editor validation cached per draft change (fix 3). List resolution evidence at the large fixture (filter, descending order with stable ties, 50 pages of 100). `CollectionLists.placements` is still computed by four build steps per build; each is linear and bounded, so this is a constant factor, not a scale defect (not changed: the planner in `CanvasRendererCore.swift` is being edited by other lanes). | `testCollectionListResolutionStaysFastAndOrderedForTenThousandItems` |

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-1001-001 | Met | Strict `ContentCollection`/`CollectionField`/`CollectionItem` Codable, stable IDs, omitted keys, schema-27 gate; D02 tests |
| SF-1001-002 | Met | `CollectionEditing.newCollection/addField/removeField/changeType/moveField/removeCollection`; Fields tab; draft vs committed |
| SF-1001-003 | Partial (blocked: OD-080) | Deterministic expression schema/context and list resolution; **field defaults and localized field values** are outside OD-035 |
| SF-1001-004 | Met | `CollectionIssue` by identity; type change/removal refuse data loss; `prepare` errors; D02 test |
| SF-1001-005 | Met | One `setCollections` transaction; history restore; undo/redo/reopen in D02 and V10 tests |
| SF-1001-006 | Partial (blocked: no UI test) | Labels, identifiers, announcements, keyboard default/cancel; a UI test needs a Mac run and `scripts/ci-ui-timings.txt` |
| SF-1001-007 | Met | Bounds (100/64/10,000); validation cached per draft change; 10,000-item import and list tests |
| SF-1001-008 | Met | `CollectionEditDiagnostic` (ids and counts only); D02 tests |
| SF-1002-001 | Met | Draft separate from the document; Apply/Cancel |
| SF-1002-002 | Met | New, duplicate, delete with confirmation, status, search, status filter, Publish Ready Drafts, Import |
| SF-1002-003 | Partial (blocked: OD-080) | Deterministic search/filter/order; **scheduling metadata and authors** need an owner decision |
| SF-1002-004 | Met | Invalid draft kept, Apply disabled with the first rule; last valid number/date kept (fix 2) |
| SF-1002-005 | Met | Whole draft = one undoable transaction (D02, D05, V10 tests) |
| SF-1002-006 | Partial (blocked: no UI test) | Labels, identifiers, keyboard, announcements; UI test as SF-1001-006 |
| SF-1002-007 | Met | Lazy `List`; cached validation (fix 3); 10,000-item fixtures |
| SF-1002-008 | Met | `CollectionEditing.diagnostic`; D02 tests |
| SF-1003-001 | Met | Strict `CollectionTemplate`/`CollectionList`/`CollectionBinding`; D03/D04 tests |
| SF-1003-002 | Met | Template and Lists tabs; `CollectionEditing` template/list operations |
| SF-1003-003 | Met | `CollectionListResolution.explanation`, `??` fallbacks, first-item preview with rule explanations |
| SF-1003-004 | Met | `CollectionTemplateFinding` keeps intent and reports by identity |
| SF-1003-005 | Met | Through `setCollections`; D03/D04 undo/redo/reopen tests |
| SF-1003-006 | Partial (blocked: OD-080 + no UI test) | Pickers/fields labelled, findings as text; **binding inspection on the canvas** is outside OD-035 |
| SF-1003-007 | Met | Linear, bounded resolution; 10,000-item list test; per-build recomputation is a constant factor (see Features) |
| SF-1003-008 | Met | `CollectionTemplates.diagnostic`, `CollectionLists.diagnostic`; D03/D04 tests |
| SF-1004-001 | Met | `SiteExpression` stored record (version 1, exact keys); D01 tests |
| SF-1004-002 | Met | Expression fields with live preview and the function menu |
| SF-1004-003 | Met | `templatePreviewExplanation` shown under the preview; V10 test |
| SF-1004-004 | Met | Located `SiteExpressionError`s, runtime findings, total evaluation; last valid expression kept |
| SF-1004-005 | Met | Expressions persist inside collections via `setCollections` |
| SF-1004-006 | Met | Error text + underlined range + place for VoiceOver + suggestion (`templatePreviewProblem`); V10 test |
| SF-1004-007 | Met | Byte/token/node/depth limits; 10,000-evaluation test |
| SF-1004-008 | Met | `SiteExpressionDiagnostic`; D01 tests |
| SF-1005-001 | Partial (deferred by OD-037) | No stored data source by design (files only, nothing about the file stored); connectors deferred |
| SF-1005-002 | Met | Import tab: choose file, map columns, preview, Add to Draft; V10 test |
| SF-1005-003 | Met | Deterministic row rules; summary, problems, per-column examples; fix 1 |
| SF-1005-004 | Met | `CollectionImportError` / `CollectionImportProblem` by line/row/column; stale and unreadable refusals; nothing changes |
| SF-1005-005 | Met | Add to Draft + Apply = one undoable `setCollections` (V10 test executes, undoes, redoes, reopens) |
| SF-1005-006 | Partial (blocked: no UI test) | Labels, identifiers, announcements, keyboard-reachable controls; UI test needs a file hook (OD-080) and a Mac |
| SF-1005-007 | Met | 5 MB checked before reading, 128 columns, 10,000 rows, 1,000 problems; off the main actor; 10,000-row test |
| SF-1005-008 | Met | `CollectionImport.diagnostic` recorded for reads and Add to Draft; tests |

Met 33, Partial 7 (all blocked, reasons above), Missing 0.

## Remaining work (blocked only)

1. UI tests for the Collections editor and the Import journey (SF-1001-006, SF-1002-006, SF-1005-006): need a Mac to run and time them
   (`scripts/ci-ui-timings.txt`), and the Import journey needs a test-only way to hand the editor a file because the system open panel runs
   out of process. Proposed in OD-080 (item 5).
2. Field defaults, localized field values and schema-change previews (SF-1001-003), scheduling and authors (SF-1002-003), binding
   inspection on the canvas (SF-1003-006), collection export (ADR-0073 item 3): outside OD-035/OD-037 → OD-080.
3. Connected data sources (SF-1005-001 beyond files): deferred by OD-037.

### Proposed OD-080 (AGENTS.md format)

## OD-080 — CMS scope after local collections and file import

Status: Open — proposed by lane V10, 2026-11-26.

- Affected requirements: SF-1001-003, SF-1002-003, SF-1003-006, SF-1001-006/SF-1002-006/SF-1005-006 (UI tests), SF-1002 (export content).
- Recommended default: Approve one follow-up lane D batch with (1) CSV/JSON export of a collection from the Import tab, the mirror of
  import (same columns, round-trip tested); (2) an optional default value per field (`CollectionField.defaultValue`, optional key, still
  schema 27) used for new and imported items; (3) a "Bound to" badge on bound layers in the Layers panel and the canvas; (4) a test-only
  launch argument that hands the Collections editor a fixture file, so a UI test covers Import and its cancellation. Defer localized
  field values until translations (OD-038) cover collections, and defer publish scheduling and authors until after release.
- Alternative: keep the CMS at OD-035/OD-037 scope for the first release.
- Tradeoff: each item adds schema/UI/test surface Codex must verify; deferring leaves the listed requirements Partial.
- Safe temporary assumption: none of these exist; no partial UI or storage for them.

## Intended plan / OD status-line changes (for the coordinator)

- OD-037 (replace its lane R sentence): "Implementation status: local CSV/JSON import complete in source, not verified — engine (Code Forge
  batch D05, ADR-0073, reviewed by lane RD) and the Import tab of the Collections editor (lane V10 2026-11-26, ADR-0074); connectors stay deferred."
- OD-035 (append): "Lane V10 verification 2026-11-26: editor validation cached per draft change, numbers accept the exponent forms the
  editor shows, list resolution tested at 10,000 items; remaining scope proposed in OD-080. Still unverified."
- OD-036 (append): "Lane V10 2026-11-26: authoring UI shows the function list, which rule won for the first item, and the error's
  highlighted range (ADR-0074). Still unverified."
- New OD-080 as above.
- DEVELOPMENT_PLAN lane D table: D4 "Import tab — complete in source, unverified (lane V10, ADR-0074)"; D1 follow-ups "done (V10)"; RD gaps
  1–5 "done (V10)"; RD gaps 6–9 "→ OD-080"; gap 10 "deferred (OD-037)".

## New/changed test selectors

New (all in `PersistedHistoryTests`, before the custom-code test):
```
SiteForgeTests/PersistedHistoryTests/testCollectionImportTabReadsAFileMapsColumnsAndAddsToTheDraftAsOneUndoableChange
SiteForgeTests/PersistedHistoryTests/testCollectionExpressionPreviewExplainsWhichRuleWonForTheFirstItem
SiteForgeTests/PersistedHistoryTests/testCollectionListResolutionStaysFastAndOrderedForTenThousandItems
```
Run with them (unchanged): the 3 D01 tests in `BlankProjectTests`, and in `PersistedHistoryTests`
`testCollectionsAreStrictSchemaGatedUndoableAndPersistedInHistory`, `testCollectionRulesProtectDataAndEditorOperationsAreDeterministic`,
`testCollectionTemplatePageBuildsOneEscapedPagePerPublishedItem`, `testCollectionTemplateRecordIsStrictUndoableAndPreviewedLive`,
`testCollectionListRepeatsALayerPerItemFilteredOrderedAndPaginated`, `testCollectionListRecordIsStrictBoundedAndUndoable`,
`testCollectionImportReadsCSVAndJSONMapsFieldsAndChecksEveryRow`, `testCollectionImportRefusesBrokenFilesAndStaysBounded`.
No UI tests; `scripts/ci-ui-timings.txt` unchanged.

## Suggested first checks for Codex

1. `CollectionsEditorView` (`WorkspaceShellView.swift` top): `@State private var issues` initialised in `init`; `.onChange(of: draft) { _, collections in … }`;
   `.task(id: request) { await refreshImportPreview(request) }` with the private `ImportRequest: Equatable`; `Task { @MainActor in await readImportFile(…) }`;
   `Task.detached { Result { try … } }.value` (Sendable captures: `URL`, `CollectionImportTable`, `CollectionImportMapping`, `ContentCollection`, `[ImageAsset]`).
2. `ForEach(Array(table.columns.enumerated()), id: \.offset) { column, name in … }` and the `Picker` tags `CollectionImportColumnTarget.field(field.id)`.
3. `$importMapping.newItemStatus` / `$importMapping.updatesMatchingItems` bindings; `Menu { … } label: { Image(systemName: "function") }` with `.menuStyle(.borderlessButton)` + `.menuIndicator(.hidden)`.
4. `highlightedExpression` Text interpolation (`Text("\(Text(verbatim: …))\(Text(verbatim: …).underline().bold().foregroundStyle(…))…")`).
5. `CollectionImport.read`: `url.resourceValues(forKeys: [.fileSizeKey]).fileSize`; `CollectionImportMapping.assign` mutating `fields` while iterating a copy.
6. `CollectionEditing.templatePreviewProblem`: `catch let found as SiteExpressionError` then a bare `catch`, definite initialisation of `problem`; returned tuple labels.
7. New tests: `XCTAssertEqual(CollectionImportFormat(fileExtension: "CSV"), .csv)`, `preview.problems == [CollectionImportProblem(kind: .duplicateSlug, row: 2, column: 2)]`,
   `CollectionImport.parseNumber(SiteExpressionEngine.numberText(1e20)) == 1e20`, the explanation strings with curly quotes and `…`,
   `templatePreviewProblem("upper(titel)")` range `6..<11`, the 10,000-item list summary `"Shows 5000 of 10000 published items on 50 pages."`.

## Cross-lane observations (not changed)

- `MultiPageStaticBuildPlanner.plan` rewrites ` src="assets/` and ` poster="assets/` for pages in folders, but an inline `url(assets/…)`
  in a style attribute on an item page, a later list page or a language page would stay root-relative (carried over from RD; lane F/H).
- RD noted `ProjectComparer.compare` reporting a localization difference twice ("Languages" and "Site languages"); not re-checked here (lane E).
