# Lane V02 review — batches 04–06 (November 26, 2026, unverified)

Owner request (6:55 PM EST): analyze all completed SiteForge work, treat every batch as unverified, check dev-doc
and Codex code-quality gaps, fix them and reach a clean stopping point for Codex. Owner choice: finish partial
features too. Brief: `_quick-scratch/review/VERIFY_BRIEF.md`. Nothing was compiled or run here (no toolchain).

## Scope

- Batch 04 — linked border, corners and shadow in reusable styles (SF-0510, ADR-0028).
- Batch 05 — nested component instances (OD-034, SF-0901/SF-0905, ADR-0018 amendment).
- Batch 06 — instance-owned slot contents and slot rules (OD-018, SF-0902/SF-0903/SF-0905, ADR-0018 amendment).
- Diff: `RP-2026-11-25-04` → `RP-2026-11-26-07` (batches 04–06 plus Codex's integrity repair), then
  `RP-2026-11-26-07` → current tree for every region those batches own.
- Files of the batches: `SiteForge/{DocumentModel,TransformModel,InsertionModel,ClipboardTransfer,DragDropModel,
  CanvasRendererCore,WorkspaceShellModel,WorkspaceShellView}.swift`; tests in `CommandKernelTests`,
  `TransformModelTests`, `CanvasRendererTests`, `ClipboardTransferTests`, `InsertionModelTests`,
  `SelectionModelTests`, `CanvasSettingsTests`, `SiteForgeUITests/SiteForgeLaunchTests`; `scripts/ci-ui-timings.txt`;
  ADR-0018, ADR-0028, OD-018/019/033/034.
- Prior reviews re-checked: Nov 25 "batches 04 and 05 (M1–2)", "batch 05 (M3–4) and 06", "final review 01–06";
  Codex's `docs/evidence/SF-QUICK-BATCH-INTEGRITY.md`.

## What was verified (method and evidence)

1. **Compile evidence.** Codex's repair log (`.codex-loop/review-integrity/build-tests-final.log`) ends in
   `** TEST BUILD SUCCEEDED **` for the tree at `RP-2026-11-26-07`; its warnings (`build-tests-retry.log`) were mapped
   back to lines: none is in a line added by batches 04–06. Codex ran 20 selectors; 12 are batch 06 tests
   (`focused-selectors.txt`), all passing in the final replays.
2. **Drift since -07.** Every declaration name present at -07 still exists except three parameter names no code uses
   (`documentBytes`, `limitBytes`, `whitespaces`). A label check of every call in the 04–06 lines (4,598 calls) against
   the current declarations found only system-API / pattern-binding false positives.
3. **Tests of the batches.** All 55 test methods named in the 04–06 handoffs and reviews exist exactly once in their
   class. Since -07 only `testSuppliedSlotContentAndEmptyStateValidateResolveAndRequireSchemaTwentyFive` changed
   (lane: schema ≥ 25 assertions; correct). Every expected string in their assertions that is not an assertion
   message was matched against the producing source (graph messages, slot-rule summaries, provenance captions,
   box sample text, CSS strings). Exact CSS strings still come from the development (readable) output: Static
   Release minification (H01) applies only in `LocalBuildProfileCompiler` for `.staticRelease`.
4. **UI journeys.** Every accessibility identifier used by the four 04–06 journeys exists in the app source.
5. **Cross-lane copy paths for 04–06 data.** Slot membership and markers (slot property IDs) are remapped in the
   definition graph copy (`ComponentDefinitionGraphCopy.remap` `slotMap`), clipboard (`slotPropertyMap`), Customize
   (`customizedSlotContents`, new membership; event-graph and link targets remapped), page duplicate and page chrome
   (graph clone, identities kept), expansion (`projectSlots`). Applied reusable style IDs are remapped by paste and
   definition copy. Variant resolution (OD-033) is applied inside `ComponentGraphResolver.expand`, so projection,
   Customize and detach all see the variant. Localized output passes `reusableStyleIndex` to every tree it compiles.

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/CommandKernel.swift` | `CommandDiagnostics.recordComponentOperation(pageID:nodeIDs:succeeded:durationMilliseconds:slotOperation:)` | Slot edits (expose/remove slot, rules, Customize, Make Empty, Use Default, Add, Move) were recorded only under SF-0901/0902/0905; SF-0903-008 requires the slot requirement ID in diagnostics. | New defaulted `slotOperation: Bool = false` appends `SF-0903-008`. Existing callers and the existing `requirementIDs.first == "SF-0901-008"` assertion are unchanged. | Spec gap SF-0903-008. |
| 2 | `SiteForge/TransformModel.swift` | `ComponentEdit.isSlotEdit` | (part of 1) no single place classified slot edits. | Computed property: the eight slot cases → `true`, everything else `false`. | Keeps the rule next to the enum. |
| 3 | `SiteForge/WorkspaceShellModel.swift` | `performComponentEdit(_:draftIdentity:successAnnouncement:)` | (part of 1) | Passes `slotOperation: edit.isSlotEdit`. | |
| 4 | `SiteForge/WorkspaceShellModel.swift` | `performSlotEdit(_:)`, `performComponentEdit` | Every successful slot edit posted two VoiceOver announcements ("Component change committed", then the specific text); the second interrupts the first (SF-0903-006). | `performComponentEdit` gains `successAnnouncement: String? = nil`; `performSlotEdit` passes its specific text, so one announcement is posted. A no-op edit still says "No component value changed". | Accessibility quality; no test reads the generic text for slots. |
| 5 | `docs/architecture-decisions/ADR-0018-local-component-definition-graphs.md` | OD-034 and OD-018 amendments | Status lines said "nothing compiled or run" (Codex compiled and ran selectors); "Every save writes schema 24" (now 27); the slot amendment did not record Codex's slot-origin / coordinate-conversion repair and had no Consequences. | Status lines cite the integrity repair and the pending full gate; consequences say "24 or later" / "25 or later"; new "Slot origin" and "Diagnostics" paragraphs. | Dev-doc accuracy. |
| 6 | `docs/architecture-decisions/ADR-0028-linked-box-appearance-in-reusable-styles.md` | Status | Said unverified/uncompiled. | "compiled by Codex's integrity repair on 2026-11-25, its tests not yet run". | Dev-doc accuracy. |

Every edit was re-read against the real declarations: `ComponentEdit` case names/labels (`exposeSlot(nodeID:label:)`,
`removeSlotProperty(NodeID)`, `setSlotRules(nodeID:rules:)`, `customizeSlot/makeSlotEmpty/useSlotDefault(instanceID:slotID:)`,
`addToSlot(instanceID:slotID:kind:)`, `moveSlotItem(nodeID:offset:)`), `CanonicalSlotRules.unrestricted`,
`SlotItemKind.frame`, `CommandDiagnosticRecord` fields, `DiagnosticResult` / `DiagnosticFailureCategory` (Equatable).
`check()` is [] for all four Swift files.

## Features finished

None were partial in scope: batches 04, 05 and 06 are recorded complete, and Codex's repair closed the one known
limitation (slot origin under differently sized copies). The items left out by the approved decisions need a new
owner decision (proposed below as OD-141); nothing was built past them.

## Requirement table (source evidence; tests unrun unless noted)

| Requirement | Status | Evidence |
|---|---|---|
| SF-0510-001 | Met | `CanonicalReusableBoxAppearance` strict grouped codec, schema-23 gate; `TransformModelTests/testReusableStyleLinkedBoxAppearanceUsesOneStrictGroupedCodec`, `…/testLinkedBoxStylesValidateInTheDocumentAndRequireSchemaTwentyThree` |
| SF-0510-002 | Met | Create Box Style, Update Box, Use Linked Border/Corners/Shadow; `…/testSetReusableStyleBoxReplacesLinkedValuesInOneUndoableTransaction`, `…/testCreateAndUpdateReusableStyleCarryBoxValuesInOneTransaction`, UI `testReusableBoxStyleLinkOverrideAndUseLinkedBorderJourney` |
| SF-0510-003 | Met | `CanonicalLinkedBoxStyleResolver` (local, then last linked style); source captions; `…/testLinkedBoxResolutionIsLocalFirstThenLastLinkedStyleWithProvenance`, `CanvasRendererTests/testLinkedBoxStylesDrawOnCanvasAndExportIdentically` |
| SF-0510-004 | Met | Partial groups, token-bound groups, linked-only removal refused/disabled with reasons; `…/testUseLinkedBoxHandsEachGroupBackToLinkedStylesAtomically`, `…/testInspectorReportsLinkedBoxSourcesAndGuardsLinkedOnlyRemoval` |
| SF-0510-005 | Met | One transaction per edit, undo/redo, clipboard v5; `ClipboardTransferTests/testLinkedBoxStylesTravelThroughClipboardAsVersionFive` |
| SF-0510-006 | Met | Identifiers + `accessibilityValue` on captions/sample, confirmations, keyboard journey |
| SF-0510-007 | Met | One-pass style index, cached index per document; `…/testLinkedBoxStylesStayResponsiveOnStandardLargeAndStressFixtures`, `…/testReusableStyleIndexGroupsManyDefinitionsOnOneOwnerIdentically`, `…/testPrebuiltStyleIndexGivesIdenticalRegistryAndCaptureResults` |
| SF-0510-008 | Met | `reusable.box.set`, `reusable.inherit.<group>` diagnostics with SF-0510 IDs; asserted in the tests above |
| SF-0901-001 | Met | `CanonicalComponentGraph`, schema-24 gate; `CommandKernelTests/testComponentGraphAllowsNestedInstancesWithDepthUsersAndExpandedSize`, `…/testNestedInstancesKeepOwnValuesAndRequireSchemaTwentyFour` |
| SF-0901-002 | Met | Insert inside a definition, Create from selection with an instance; `…/testInsertComponentInsideADefinitionIsUndoableAndRefusesCyclesAndDepth`, `…/testCreateComponentFromSelectionContainingAnInstanceKeepsItLinkedWithItsValue`, UI `testNestedComponentInsertInsideDefinitionRefusesSelfAndShowsUsageJourney` |
| SF-0901-003 | Met | `expandNested` with chained derived identities; `CanvasRendererTests/testNestedComponentDrawsExportsAndKeepsItsOwnValuesWithStableDerivedIdentity` |
| SF-0901-004 | Met | Cycle/depth/size refused with the chain; missing inner definition blocks Preview/export (`…/testNestedMissingDefinitionBlocksPreviewAndExportAndCyclesStillResolve`, **run and passed by Codex**) |
| SF-0901-005 | Met | Undoable insert/detach/rename/delete across definitions; clipboard v5 nested import; `…/testRenameAndDetachUsesAndDeleteIncludeUsesInsideOtherDefinitions`, `ClipboardTransferTests/testNestedComponentCopyImportsInnerDefinitionsFirstAndReusesThemOnRepeatPaste` |
| SF-0901-006 | Met | Components panel "Used inside"/"Contains" with accessibility values; journey above |
| SF-0901-007 | Met | Budget pre-count before allocation; `…/testNestedComponentExpansionStaysWithinBoundsOnStandardLargeAndStressFixtures`, `…/testOnePassInsertionAnswersMatchTheFullRebuildForEveryPairOnRandomGraphs`. Known limit (pre-existing class): a definition edit can push a page past 20,000 objects; the canvas then shows the object-limit error. |
| SF-0901-008 | Met | Graph categories `component-cycle` / `-nesting-too-deep` / `-expansion-too-large`; SF-0901-008 component diagnostic record |
| SF-0902-001 | Met | `ExposedComponentSlotProperty.rules`, strict `CanonicalSlotRules.decode`; `…/testSlotRulesConstrainDefaultAndSuppliedContentAndRefuseWithTheReason` |
| SF-0902-002 | Met | `ComponentSlotRulesFields` (Apply Rules, Escape resets the draft) |
| SF-0902-003 | Met | Canonical kind order, rules caption `component.slot.rules.<slot>` |
| SF-0902-004 | Met | Refusal names the rule and the number of copies (test above) |
| SF-0902-005 | Met | Rules undo/redo and round trip (test above) |
| SF-0902-006 | Met | Checkboxes, stepper and identifiers in the rules editor |
| SF-0902-007 | Met | `slotEditAvailability` cache per revision/scene/selection |
| SF-0902-008 | Met | SF-0902-008 on every component record; slot edits now also SF-0903-008 |
| SF-0903-001 | Met | Markers, membership, `CanonicalSlotState`, schema-25 gate; `…/testSuppliedSlotContentAndEmptyStateValidateResolveAndRequireSchemaTwentyFive` (**run, passed**) |
| SF-0903-002 | Met | Customize / Make Empty / Use Default / Add / Move Up-Down / Paste into Slot; `…/testCustomizeMakeEmptyAndUseDefaultReplaceOneSlotStateInOneUndoableStepEach`, `…/testAddToSlotFollowsTheRulesAndMoveSlotItemReordersWithinTheSlot`, UI `testComponentSlotCustomizeAddReorderEmptyAndDefaultJourney` |
| SF-0903-003 | Met | `projectSlots` at every level, provenance captions; `CanvasRendererTests/testSuppliedSlotContentDrawsInItsSlotWithCanonicalIdentityOnCanvasExportAndPreview` (**run, passed**), `…/testSlotOriginsMatchRenderedLayoutForDifferentlySizedCopies` (**run, passed**) |
| SF-0903-004 | Met | Removed slot keeps contents as a conflict; rules refusals; `…/testRemovedSlotKeepsSuppliedContentAsAConflictAndResetRemovesItInOneUndoableStep` |
| SF-0903-005 | Met | Clipboard v6, page duplicate, page chrome; `ClipboardTransferTests/testCopyOwningSlotContentsPastesWithItsOwnObjectsAndRequiresVersionSix` (**run, passed**), `InsertionModelTests/testPageChromeReuseCopiesAComponentCopysOwnSlotContents` (**run, passed**) |
| SF-0903-006 | Met | Item list, Move Up/Down, Layers caption/value; one announcement per slot edit (fix 4) |
| SF-0903-007 | Met | `CanvasRendererTests/testSuppliedSlotProjectionStaysWithinBoundsOnStandardLargeAndStressFixtures`; 256-item / 64-marker bounds |
| SF-0903-008 | Met (fixed here) | Slot edits now record SF-0903-008 (fix 1); `CommandKernelTests/testSlotEditDiagnosticsNameTheSlotRequirementAndOtherComponentEditsDoNot` |
| SF-0905-001 | Met | `.slotEmpty` / `.slotSupplied` override values; inner-instance values (one level) validated like page values |
| SF-0905-002 | Met | Reset one/all, Reset conflicts removes a removed slot's contents in one step |
| SF-0905-003 | Partial (blocked) | Precedence and provenance are defined for page values and values on inner instances authored inside the outer definition. Values on an inner instance from the page (nested override paths) and filling an inner instance's slot from the page are not specified: OD-034 and OD-018 leave them out. Needs OD-141. |
| SF-0905-004 | Met | Missing slot/definition → retained `missingProperty`/`missingDefinition` conflict; `CanvasRendererTests/testNestedMissingDefinitionBlocksPreviewAndExportAndCyclesStillResolve` (**run, passed**) |
| SF-0905-005 | Met | Undo/redo of every value edit; persisted with schemas 24/25 |
| SF-0905-006 | Met | Inspector value controls and conflict recovery (pre-existing), slot provenance |
| SF-0905-007 | Met | Slot markers count toward `maximumOverridesPerInstance` |
| SF-0905-008 | Met | SF-0905-005/008 on the component record |

Totals: 39 Met, 1 Partial (blocked by a decision), 0 Missing.

## Remaining work (blocked only)

1. **SF-0905-003 nested override paths and nested slot filling** — blocked: needs an owner decision (proposed
   OD-141 below). OD-034 says "overrides on nested instances stay one level deep until nested override paths are
   specified"; OD-018 lists "filling slots of nested instances from the page" as out of scope.
2. **Execution evidence** — blocked: no Swift toolchain here. Batch 04 and most batch 05 selectors have never run;
   the UI timing rows (90 / 60 / 160 s) are estimates.
3. `IMPLEMENTATION_STATUS.md`, `CHANGELOG.md`, `REQUIREMENT_EVIDENCE.json`, `CODEX_HANDOFF.md`, `CODEX_QUEUE.md` —
   left to Codex by the owner's standing instruction (unchanged).

### Proposed OD-141 — Nested override paths and slot filling of inner instances (SF-0905, SF-0903)

- Status: Open — raised by Code Forge lane V02, 2026-11-26.
- Needed by: SF-0905-003 for instances nested inside definitions (OD-034) and SF-0903-002 for their slots (OD-018).
- Context: a page copy can set values only on its own definition's exposed properties. Values on an inner instance
  are authored inside the outer definition and are the same for every copy. Users cannot change, from the page, the
  label of the Button inside one Card, or fill a slot of that Button.
- Recommended default: an override path is the ordered list of stable instance node IDs from the outer definition
  down to the inner instance (at most `CanonicalComponentGraph.maximumNestingDepth` − 1 steps), stored on the page
  copy as `component.path.v1.<path>.<typed property key>`. The deepest authored value wins: page path value, then
  the value authored inside the outer definition, then the inner default. A path that stops resolving becomes the
  existing retained conflict (reset / restore / navigate, OD-019). Slot markers and membership of inner instances use
  the same path. Needs a document schema bump, clipboard version and ADR-0018 amendment; no change before approval.
- Alternatives: keep one level (current); or expose inner properties by promotion (the outer definition re-exposes
  chosen inner properties as its own), which needs no path format but more authoring work.
- Tradeoffs: paths give full control but add a key format, migration and transfer remapping for every copy path;
  promotion is simpler and safer but less flexible.
- Affected requirements: SF-0905-001/003/004/005, SF-0903-002/003, SF-0901-003, SF-0308-003/004.
- Decision deadline: before any page-level editing of inner instances.
- Safe temporary assumption: current behavior (one level; inner values authored in the outer definition).

## Intended plan / OD status-line changes (for the coordinator, exact text)

- `docs/OPEN_DECISIONS.md` OD-018, append to the Implementation status line: "Lane V02 verification
  (2026-11-26): re-checked against the current tree; slot edits now record SF-0903-008 and post one announcement;
  ADR-0018 amendment updated. Filling slots of nested instances from the page stays out of scope (proposed OD-141)."
- `docs/OPEN_DECISIONS.md` OD-034, append to the Implementation status line: "Lane V02 verification (2026-11-26):
  re-checked against the current tree, no defect found; compiled by Codex 2026-11-25, one selector run. Nested
  override paths: proposed OD-141."
- `docs/OPEN_DECISIONS.md`: add OD-141 exactly as proposed above (Status Open).
- `DEVELOPMENT_PLAN.md`, lane V table, V02 row: "done (unverified) — batches 04–06 verified; 4 fixes
  (SF-0903-008 diagnostics, single slot announcement, ADR-0018/0028 status); OD-141 proposed; report
  docs/reviews/LANE-V02-review-2026-11-26.md".
- `docs/coordination/CODE_FORGE_ACTIVITY.md`: entry "## Lane V02 review — November 26, 2026 (batches 04–06,
  OD-018 / OD-034 / ADR-0028, unverified, complete)" summarizing the fixes table and the new selector.

## New / changed test selectors

- New: `SiteForgeTests/CommandKernelTests/testSlotEditDiagnosticsNameTheSlotRequirementAndOtherComponentEditsDoNot`
- Changed: none.

## Out-of-area issues (not fixed)

1. **Component library export with reusable styles (lane A, OD-046 / SF-0906).** `ComponentLibraries.exporting`
   builds a carrier document with only the definitions and their color tokens. A definition that applies a reusable
   style (fill or the linked box values of ADR-0028) whose definition is stored on a website page node makes
   `DocumentSerializer.encode(carrier)` fail validation (`CanonicalReusableStyleIndex` refuses applied IDs without a
   definition), so the user gets the generic "The components could not be stored in a library." Suggested fix: refuse
   up front with a specific `ComponentLibraryError` (like `usesImages`) naming the component, or carry the used style
   definitions in the carrier and import them.

## Suggested first checks for Codex

1. `ComponentEdit.isSlotEdit` (`TransformModel.swift`): `switch` expression as the computed property body with a
   multi-pattern `case .exposeSlot, …, .moveSlotItem: true` (no bindings).
2. `CommandDiagnostics.recordComponentOperation` (`CommandKernel.swift`): `[…] + (slotOperation ? ["SF-0903-008"] : [])`
   as the `requirementIDs:` argument.
3. `performSlotEdit` → `performComponentEdit(edit, successAnnouncement: announcement)` (skips the defaulted
   `draftIdentity:`); `let announcement: String` assigned in every non-returning `case`.
4. Never-run 04–05 tests most likely to fail on expectations: `CanvasRendererTests/testLinkedBoxStylesDrawOnCanvasAndExportIdentically`
   (exact CSS strings, `0.251` alpha), `TransformModelTests/testInspectorReportsLinkedBoxSourcesAndGuardsLinkedOnlyRemoval`
   (caption strings), `CommandKernelTests/testOnePassInsertionAnswersMatchTheFullRebuildForEveryPairOnRandomGraphs`
   (offline-computed counts 757 / 9 / 20 / 859 and runtime), `CanvasRendererTests/testNestedComponentDrawsExportsAndKeepsItsOwnValuesWithStableDerivedIdentity`
   (`StaticBuildCompiler` plan non-nil for a blank document after later lanes' findings).
5. UI journeys `testReusableBoxStyleLinkOverrideAndUseLinkedBorderJourney`,
   `testNestedComponentInsertInsideDefinitionRefusesSelfAndShowsUsageJourney`,
   `testComponentSlotCustomizeAddReorderEmptyAndDefaultJourney` (identifiers verified present; never run).
