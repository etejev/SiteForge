# Lane V16 review — OD-143 and OD-144 builds (2026-11-26)

Owner tag `lane-V16`. Follow-up lane that builds the two decisions the owner approved at
8:06 PM EST with their recommended defaults (`_quick-scratch/review/OWNER_DECISIONS_LANE_V.md`).
Verification was by careful reading on the Windows PC (no Swift toolchain, git or subprocess).
Nothing was built or run; everything below is **unverified until Codex builds and runs the listed
selectors**. Document schema 27, persisted-history schema 4 and WebsiteMetadata version 3 are
unchanged; no `CanonicalDocument` key and no Swift file was added.

## Scope

- OD-143 (LANE-V04, ADR-0143, ADR-0031): container-query width basis — SF-0605 (and SF-1204-003
  canvas/export agreement).
- OD-144 (LANE-V05, ADR-0144, ADR-0034, batch 14 SEO emitter/audit): schema.org structured data —
  SF-1207.
- Files read: `SiteForge/InsertionModel.swift` (`CanonicalContainerQueries` extension,
  `StaticLayoutOutputEmitter`, `ConnectedPageOutput.css`, `fluidFlowRules`,
  `automaticSizingDeclarations`, `ResolvedContainerLayoutPolicy`, `ConnectedPageLayoutSnapshot`,
  `ConnectedFluidOutputPolicy`, `StaticFluidValueOutputEmitter`), `SiteForge/CanvasRendererCore.swift`
  (`StaticBoxStyleOutputEmitter`, `InternalDocumentRenderTreeCompiler` box style and `connected`,
  stylesheet assembly order, `StaticContainerQueryOutputEmitter`, `StaticSEOEmitter`,
  `StaticSEOAudit`, `MultiPageStaticBuildPlanner.plan` page loop, `SiteLanguageOutputPass`,
  `StaticOutputManifest`, `StaticRuntimeBundle`, `LocalBuildProfileCompiler`),
  `SiteForge/TransformModel.swift` (`DesignBoxStyleCommandRegistry`, `CanonicalBoxStyle`,
  `LocalColorTokenResolver`, `CanonicalLinkedBoxStyleResolver`, value trace),
  `SiteForge/DocumentModel.swift` (`CanonicalContainerQueries`, `CanonicalSizingConstraints`,
  `CanonicalBoxStyleNamespaceValidator`, `WebsiteMetadata`, `WebsiteMetadataResolver`,
  `CollectionTemplates.outputPages`), `SiteForge/WorkspaceShellModel.swift` (scene preparation,
  `ResponsiveAuditRunner`, `containerQueryEvaluation`), `SiteForge/WorkspaceShellView.swift`
  (`ContainerQueryRuleView`), the container-query, SEO, language-tree and custom-code tests, and
  the UI journey `testContainerQueryContainerRuleStatusAndUndoJourney`.
- Every in-app evaluator of container queries goes through one function,
  `CanonicalContainerQueries.evaluated`: canvas and in-app Preview (scene preparation,
  `WorkspaceScenePreparationWorker`), responsive audit (`ResponsiveAuditRunner`, which also
  prepares scenes through the worker) and the Inspector (`containerQueryEvaluation`, which also
  feeds value traces). `rule.matches(width:)` has no other caller. All of them changed together.

## Features finished

1. **OD-143 — content-box width basis (ADR-0143 "Implemented (lane V16)", ADR-0031 updated).**
   New `CanonicalContainerQueries.contentInset(of:on:breakpoint:viewportWidth:visibleIDs:nodesByID:reusableStyles:)`
   is the one shared inset helper: the left-plus-right space export's CSS puts between the
   container's border edge and its content box, read from the resolvers the emitters use —
   static-layout pages: 2 × border width (own or linked reusable style) + 2 × box padding, with
   the emitter's gates (`applicableKinds`, `hasWellFormedContentBoxProperties`, `style.isValid`)
   and 0.001 px rounding; connected pages: box border is an `outline` (0), CSS padding only for a
   horizontal Stack or a Hug-height Stack/Section/Grid/padded Frame (resolved layout padding at the
   breakpoint's preset width), or a winning fluid padding at the viewport width; fluid-flow-adapter
   pages: 0 (padding is on the inner wrapper). `evaluated(…, styleSource:)` subtracts it once per
   container (memoized, never below 0); the reusable-style index is built only for static pages
   that have rules. Deterministic: pure functions of the page, breakpoint and width.
2. **OD-144 — schema.org structured data (ADR-0144 "Implemented (lane V16)", ADR-0034 updated).**
   New `StaticSEOEmitter.structuredData(_:route:siteRoot:isHome:siteURL:)` and
   `StaticSEOEmitter.jsonEscape(_:)`. One `<script type="application/ld+json">` per written page
   (after the search/social tags, before hreflang alternates), only when the site address is set,
   built from the same `StaticSEOMetadata` as the head: `WebPage` (`@id`, `url`, `name`,
   `description` when present, `inLanguage`, `isPartOf` → the tree's `WebSite` `@id`) on every
   page; the home page of each language tree (`/`, `/fr/`, not a list's later pages) also carries
   the `WebSite` (`@id`, `url`, `name`, `inLanguage`). Collection item pages use the item's
   resolved title and address; the template page is never written; Not Found pages get none.
   Keys in one fixed order (deterministic bytes). `<`, `>`, `&`, U+2028/U+2029 and control
   characters are `\uXXXX`-escaped, so nothing authored can close the script. Static Release
   writes it unchanged (only CSS minification and the exact runtime-tag swap of
   `StaticRuntimeBundle.page` touch output); the integrity manifest and Output files report hash
   the page with its block. No new document keys; no new Check Website finding (the approved
   default does not call for one, and a written block cannot be invalid — see ADR-0144).

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/InsertionModel.swift` | `CanonicalContainerQueries.evaluated`, new `contentInset` | Rules queried the container's frame; browsers query the content box of `container-type: inline-size`, so padded or bordered containers switched at a different width on canvas, in Preview, the Inspector and the audit than in the exported site. | Content width = frame − `contentInset` (OD-143). New optional `styleSource:` argument (last, defaulted). | SF-0605-003, SF-1204-003 (OD-143 approved). |
| 2 | `SiteForge/WorkspaceShellModel.swift` | scene preparation (`WorkspaceScenePreparationWorker`), `ResponsiveAuditRunner.run`, `containerQueryEvaluation` | The three evaluators must use the same basis, including borders from linked reusable styles. | Pass `styleSource: request.document` / `document`. | Canvas = Preview = audit = Inspector. |
| 3 | `SiteForge/WorkspaceShellView.swift` | `ContainerQueryRuleView.statusText` | `Int(width.rounded())` could show a width the rule's boundary seems to reach when it does not (e.g. 447.6 shown as 448 for "at least 448"); text did not say which width is queried. | Shows the content width to a tenth, rounded down; text "… is N pt wide inside its padding and border here …" (keeps "panel is" and "Applies" that the UI journey reads). | SF-0605-003 provenance, SF-0605-006. |
| 4 | `SiteForge/CanvasRendererCore.swift` | `MultiPageStaticBuildPlanner.plan` page head, `StaticSEOEmitter` | SF-1207 scope "structured data" was not produced (OD-144). | `seoMetadata` shared by `head` and new `structuredData`; block inserted in the head. | SF-1207-003 (OD-144 approved). |
| 5 | `docs/architecture-decisions/ADR-0031-container-queries.md` | Consequences | Said the canvas measures the frame and OD-143 is open. | Canvas measures the content box (OD-143 approved, ADR-0143). | Dev-doc accuracy. |
| 6 | ADR-0143, ADR-0144, ADR-0034 | Open question / Implemented / Reversal / Consequences | Decisions were recorded as proposed. | Marked approved; "Implemented (lane V16)" sections; reversal steps; ADR-0034 consequence. | Dev-doc accuracy. |

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-0605-001 Authoritative state | Met | Unchanged (lane V04): strict `CanonicalContainerQueries` encoding, schema-27 gate; OD-143 adds no state. |
| SF-0605-002 Create and modify | Met | Unchanged (lane V04): registry edits, value rows, Add Setting. |
| SF-0605-003 Resolution rules | Met (after OD-143) | `contentInset` + `evaluated`; `CommandKernelTests/testContainerQueriesMeasureTheContentBoxInsidePaddingAndBorderLikeBrowsers` (448 applies / 449 not, max 448 applies / 447 not, against the exported `border-box` width, border and padding; connected horizontal Stack padding; frame unchanged without padding/border); status text names the queried width. |
| SF-0605-004 Failure and recovery | Met | Unchanged; Hug fallback and no-container findings (see out-of-area note on the Hug fixture). |
| SF-0605-005 History and persistence | Met | No new state; edits unchanged (one transaction each). |
| SF-0605-006 Accessible operation | Met | Status text remains the labeled `inspector.containerQuery.rule.status.N` element; UI journey strings kept. |
| SF-0605-007 Performance and scale | Met | Inset memoized per container per evaluation; reusable-style index built only for static pages with rules; `testContainerQueriesStayWithinBoundsOnStandardLargeAndStressFixtures` covers the same path. |
| SF-0605-008 Diagnostics and tests | Met | Unchanged diagnostics (lane V04); new unit test. |
| SF-1207-001 Authoritative state | Met | No new keys; WebsiteMetadata v3, schema 27; structured data is derived output only. |
| SF-1207-002 Create and modify | Met | Unchanged (Website Settings, previews). |
| SF-1207-003 Resolution rules | Met (after OD-144) | `StaticSEOEmitter.structuredData` from resolved typed metadata (item pages via `ignoresPageTitle`); `CanvasRendererTests/testStructuredDataDescribesEachPageOnlyWithASiteAddress`, `…/testStructuredDataFollowsEveryLanguageTreeAndCollectionItemPages`; existing duplicate/missing/long audit. |
| SF-1207-004 Failure and recovery | Met | Invalid data cannot be written (inputs validated by `head`, which fails the build first); `testStructuredDataEscapesTextSoItCannotCloseItsScript`; no block without an address. |
| SF-1207-005 History and persistence | Met | Unchanged; output follows Undo because it is derived. |
| SF-1207-006 Accessible operation | Met | Unchanged UI. |
| SF-1207-007 Performance and scale | Partial | One string per page, linear in written pages; no stress fixture (blocked: needs executed timing on the macOS harness; no toolchain here). |
| SF-1207-008 Diagnostics and tests | Met | Three new tests; integrity-manifest hash checked in Static Release. |

Totals: 15 Met, 1 Partial, 0 Missing.

## Remaining work (blocked only)

1. Build and run every listed selector — blocked: no Swift toolchain / macOS on this PC.
2. SF-1207-007 stress-fixture timing — blocked: needs executed evidence on named hardware.
3. `docs/REQUIREMENT_EVIDENCE.json` records for SF-0605-003 / SF-1207-003 — blocked on executed
   evidence (lane V policy: records are added after Codex runs the tests).

## Intended plan / OD status-line changes (for the coordinator, lane V15)

- `docs/OPEN_DECISIONS.md` — OD-143: `Status: Approved by the owner 2026-11-26 8:06 PM EST (recommended default).`
  `Implementation status: Built (lane V16, ADR-0143, unverified): the canvas, Preview, the Inspector and the responsive audit query a container's content box (inside the padding and border export writes) through CanonicalContainerQueries.contentInset, so they switch at the exported width; no schema, clipboard or export change.`
- `docs/OPEN_DECISIONS.md` — OD-144: `Status: Approved by the owner 2026-11-26 8:06 PM EST (recommended default).`
  `Implementation status: Built (lane V16, ADR-0144, unverified): one schema.org JSON-LD block per written page (WebPage; WebSite on each language tree's home page) from typed metadata only, only when the site address is set; Not Found pages excluded; every language tree and collection item page covered; no new document keys (schema 27, WebsiteMetadata 3); no new Check Website finding.`
- `docs/coordination/CODE_FORGE_ACTIVITY.md` — Batch 09 heading: replace `OD-143 open` with `OD-143 built by lane V16`;
  Batch 14 heading: append `; structured data (OD-144) built by lane V16 — ADR-0144`.
- `DEVELOPMENT_PLAN.md` lane V table: `V16 | OD-143 + OD-144 (follow-up) | done 2026-11-26 — 2 features built (ADR-0143, ADR-0144), 4 tests added, 15 Met / 1 Partial (SF-1207-007 stress evidence) / 0 Missing; report docs/reviews/LANE-V16-review-2026-11-26.md`.

## New / changed test selectors

- New `SiteForgeTests/CommandKernelTests/testContainerQueriesMeasureTheContentBoxInsidePaddingAndBorderLikeBrowsers`
- New `SiteForgeTests/CanvasRendererTests/testStructuredDataDescribesEachPageOnlyWithASiteAddress`
- New `SiteForgeTests/CanvasRendererTests/testStructuredDataEscapesTextSoItCannotCloseItsScript`
- New `SiteForgeTests/CanvasRendererTests/testStructuredDataFollowsEveryLanguageTreeAndCollectionItemPages`
- Re-run (behavior touched): `SiteForgeTests/CommandKernelTests/testContainerQueryEvaluationIsOrderedNearestFirstAndBeatsBreakpointValues`
  (containerWidth 500: Panel has no padding/border), `…/testValueTraceMatchesEnginePrecedenceAndClearsTheWinnerInOneStep`,
  `SiteForgeTests/CanvasRendererTests/testContainerQueriesFollowEachCopysContainerOnCanvasPreviewAndExport`,
  `…/testContainerQueriesStayWithinBoundsOnStandardLargeAndStressFixtures`,
  `…/testSocialPreviewTagsSitemapRobotsAndSEOWarningsInExport`, `…/testCustomCodeIsWrittenVerbatimToBuildsAndLeftOutOfPreview`,
  `SiteForgeTests/PersistedHistoryTests/testSiteLanguagesExportOneTreePerLanguageWithAlternatesAndTranslations`,
  `SiteForgeUITests/SiteForgeLaunchTests/testContainerQueryContainerRuleStatusAndUndoJourney` (status text changed; still contains "panel is" and "Applies").

## Suggested first checks for Codex

1. `CanonicalContainerQueries.contentInset` (InsertionModel.swift): `[.stack, .section, .grid].contains(container.kind)`;
   `LocalColorTokenResolver.resolvedBoxStyle(for:tokens: [], reusableStyles:)`; the nested `written(_:)` func inside the
   `guard … else` block; `ResolvedContainerLayoutPolicy.resolve(_:children:breakpoint:viewportWidth:)`.
2. `CanonicalContainerQueries.evaluated`: nested `contentWidth(of:)` mutating the captured `contentWidths` and called from
   `container.flatMap { contentWidth(of: $0) }`; `let styles: CanonicalReusableStyleIndex? = connected ? nil : styleSource.flatMap { try? CanonicalReusableStyleIndex(document: $0) }`.
3. `StaticSEOEmitter.jsonEscape`: `switch scalar` over `Unicode.Scalar` with literal patterns (`"\""`, `"\\"`, `"\u{2028}"`),
   `String(format: "\\u%04x", scalar.value)`; `structuredData` string interpolations with nested quotes.
4. Planner page loop (CanvasRendererCore.swift): `seoMetadata` (memberwise `StaticSEOMetadata` init), `structuredData` local
   (`entry.listPageNumber ?? 1`), head string `\(metadataHead)\(structuredData)\(alternates)…`.
5. `testContainerQueriesMeasureTheContentBoxInsidePaddingAndBorderLikeBrowsers` assumptions: `MultiPageStaticBuildPlanner.plan`
   succeeds on `containerQueryFixture()` plus box border/padding (static page with a horizontal Stack); the layout line starts
   `"<sel> { box-sizing: border-box;"`; the box rule is exactly `"<sel> { border: 2.0px solid rgba(0.0, 0.0, 0.0, 1.0); padding: 24.0px; }"`;
   on the connected variant (Row `heightMode` hug) the Row's resolved width stays 300 and its `ConnectedPageOutput` line contains
   `;padding:16.0px;`.
6. `testStructuredDataDescribesEachPageOnlyWithASiteAddress`: exact JSON-LD strings (`WebsiteMetadataResolver.resolve(...).title`
   for names, default description on About), Static Release `release.report?.outputFiles` hash of `about.html`.
7. `testStructuredDataFollowsEveryLanguageTreeAndCollectionItemPages`: `fr/about.html`, `fr/index.html`, `fr/404.html` paths;
   item pages found by `"url":"https://studio.example/blog/first"`.

## Out-of-area issues (not fixed)

- `CanvasRendererTests.containerQueryCardDocument(hugRoot: true)` sets `layout.sizing.v1.widthMode = "hug"` on the
  definition root and then calls `try document.validate()`, but `CanonicalSizingConstraints.isValid` starts with
  `guard widthMode != .hug` and `CanonicalSizingNamespaceValidator.validate` runs for every node, so validation most likely
  throws `invalidSizingConstraints` and `testContainerQueriesFollowEachCopysContainerOnCanvasPreviewAndExport` fails at the
  fixture (batch 09 / lane V04 area). It also means the SF-0605 "Hug container is skipped" fallback cannot occur in a valid
  document (`isActiveContainer` is always true there). Needs a decision on how a Hug-width container can arise (or the
  fallback test should build its document without `validate()` and without the planner). Sent to V14/Codex.

## Write problems

None. All writes through `forge_io.edit`/`write_new` with owner `lane-V16`; `check([...]) == []` after every edit;
`foreign_changes(30)` empty before the first write and at each later check; `icloud_duplicates()` empty.
