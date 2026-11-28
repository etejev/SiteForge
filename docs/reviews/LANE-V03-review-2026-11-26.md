# Lane V03 review — batches 07–08 (2026-11-26)

Owner tag `lane-V03`. Verification by reading only (no Swift toolchain, no git). Assigned numbers: ADR-0142 (not
needed: the fixes stay inside OD-033 and are recorded as an amendment in ADR-0029), OD-142 (proposed below).

## Scope

- **Batch 07** — property-only component variants (OD-033, ADR-0029, SF-0904-001…008, document schema 26,
  clipboard v7).
- **Batch 08** — package v2 page members (OD-032, ADR-0030, SF-0301-001…008; SF-0206-007, SF-1702-004/008).
- Diff: `RP-2026-11-26-07 → RP-2026-11-26-08` (shared with batches 09–14; hunks attributed with the activity-log
  entries), then every attributed region re-read in the CURRENT tree with its call sites and declarations.
- Files read: `SiteForge/DocumentModel.swift` (variant types, `CanonicalComponentVariants`, reference/page validation
  hooks, schema gate, `CanonicalComponentOverrides.resolve`), `SiteForge/TransformModel.swift`
  (`ComponentVariantEdit`/`Error`/`CommandRegistry`, `previewCombination`, `presentedDocument`, `source`, `rewrite`),
  `SiteForge/CommandKernel.swift` (`authoringTransform` in `execute` and `executeCoalescing`, `DocumentCommand` cases),
  `SiteForge/InsertionModel.swift` (`ComponentGraphResolver.expand`), `SiteForge/ClipboardTransfer.swift` (v7),
  `SiteForge/WorkspaceShellModel.swift` (variant section, all `authoringDocument` call sites by function, undo/redo/jump,
  document publication sink), `SiteForge/WorkspaceShellView.swift` (`ComponentVariantEditingBar`, `…NameField`,
  `…Manager`, `…OverridesView`, `…ChoiceFields`), `SiteForge/ProjectPackage.swift` (`ProjectPackagePageSplit`,
  `ProjectPackageMeasurement`, `makeMeasuredContainer`, `encodedPages`, `parseContainer`, `pageMemberPaths`,
  `validatePayloads`/`validateDescriptors`, `ArchiveCodec`), `SiteForge/DocumentLifecycle.swift`
  (`ProjectFileCapacity`, `CompletedPackageWrite`, oversize mapping), tests in `CommandKernelTests`,
  `CanvasRendererTests` (fixture use), `ClipboardTransferTests`, `ProjectPackageTests`, `DocumentLifecycleTests`,
  `PersistedHistoryTests`, the UI journey in `SiteForgeLaunchTests`.
- Mechanical checks: undeclared-identifier scan of every batch 07/08 added line against the current tree (0 real
  findings; the 9 hits are `let a = …, b = …` locals and Foundation members); call-label check of the same lines
  (2,643 calls; every hit is a SwiftUI/stdlib false positive or a batch-09 container-query closure).

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/WorkspaceShellModel.swift` | `startBrowserPreviewBuild()`, `startStaticBuildPreflight()` | Both compiled `authoringDocument`. While a variant is edited that document presents the open definition as the variant with its override storage removed, so Website Preview, its Export and Check Website / local output would draw **every copy** of that component with the edited variant's values (wrong site written to disk; breaks the SF-0904 canvas/Preview/export parity the batch claims). | Compile `documentSession.document` (the stored project). The id/revision staleness guards are unchanged: both documents share id and revision. | Output must be the saved site; the variant presentation is editing state only. |
| 2 | `SiteForge/TransformModel.swift` | `CanonicalComponentVariants.rewrite` (+ new `isEditable(_:in:)`) | When Undo/Redo/a history jump/revert removed the variant being edited (e.g. undo "Add Value" while editing that value), `rewrite` found no set or an unknown target and passed edits through unchanged: edits silently landed in the **base** while the UI still said "Editing Size: Huge". | `rewrite` refuses commands that edit the open definition with `ComponentVariantError.stale` when the target is no longer editable; commands for other pages pass. | SF-0904-004: never corrupt intent; specific recovery. |
| 3 | `SiteForge/WorkspaceShellModel.swift` | new `reconcileVariantEditingTarget()`, called from the `documentSession.$document` sink | The stale target was never cleared after undo/redo/jump/revert. | On every document publication: if the target is no longer editable, end variant editing, announce "The variant you were editing no longer exists. Editing the base component.", record a diagnostic, re-prepare the scene. `editVariant` and `performVariantEdit` use the same `isEditable` rule (two duplicated switches removed). | Same requirement; one rule in one place. |
| 4 | `SiteForge/TransformModel.swift`, `SiteForge/WorkspaceShellModel.swift` | `ComponentVariantCommandRegistry.prepare(…, forCommit:)`, `setCommands(…, countingRepairs:)`, `variantEditAvailability` | Every control of the Variants popover (Make Default, ↑, ↓, Remove…, Add Value, Add Property, Move Up/Down per axis/value — dozens) ran the full commit path on each SwiftUI body evaluation: `CommandRegistry().availability` (whole-document validation) plus a scan of every page for copies needing repair, on the main actor. On the large/stress fixtures this stalls the popover. | `forCommit: false` keeps every registry rule (names, limits, defaults, stale, lifecycle) but skips the whole-document validation and the repair count; the commit path is unchanged (default `true`). | SF-0904-007 (no UI stalls), Quality bar (expensive work off the main actor). |
| 5 | `SiteForge/TransformModel.swift`, `SiteForge/WorkspaceShellModel.swift` | new `ComponentVariantDiagnostic`, `ComponentVariantError.diagnosticCategory`, `ComponentVariantEdit.requirementID`, `WorkspaceShellState.lastVariantDiagnostic`, `recordVariantDiagnostic` | No variant operation emitted diagnostics; `ComponentVariantEdit.diagnosticOperation` was declared and never used. SF-0904-001…008 require requirement ID, operation, sanitized identifiers, duration, failure category. | A sanitized record (hashed document and component identity via `DiagnosticStableIdentifier`, closed failure category, no names/values/keys) for every variant edit (success and failure), entering/leaving a variant, and the return to Base. | SF-0904-008. |
| 6 | `SiteForge/WorkspaceShellView.swift` | `ComponentVariantManager.button(…)`, `axisSection` | "Remove Property…" was the only manager control not disabled with the registry's reason; the ↑/↓ value buttons were spoken as "↑"/"↓". | Remove Property uses `variantEditAvailability` (disabled + help); `button` takes an optional spoken `label` ("Move Small up"). | SF-0904-006. |
| 7 | `docs/architecture-decisions/ADR-0029-property-only-component-variants.md` | Verification amendments | ADR did not record the stored-project rule for output, the stale-target rule or diagnostics. | Added a "Verification amendments (lane V03)" section; names OD-142. | Dev-doc coverage. |

Batch 08 (package v2): read in full; no defect found. Checked: `split` guards (marker absent, page list found exactly
once, page never split, member ≤ limit incl. brackets), `join` (marker once, `document.pages` is the marker string,
each member a non-empty array of objects, so no early close/injection), `pageMemberPaths` (canonical names, no gaps,
role ⇔ name), v1/v2 manifest agreement and minimum reader, page members excluded from optional members, optional
members may not use the page prefix/role, `ArchiveCodec` file cap (8 MiB) mapped to `projectTooLarge`,
`ProjectFileCapacity` arithmetic against every assertion in the three changed/new lifecycle tests, and the later
`ProjectPackageStore.storedDocument(in:)` (SF-0309) which reuses `pageMemberPaths`/`join` correctly.

## Features finished

None outstanding: OD-033 and OD-032 have no partial items (their "out of scope" items — transitions between
variants, per-breakpoint selection, structural variants — are scope decisions, not partial work). The only gap found
that needs an owner decision is OD-142 below.

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-0904-001 Authoritative state | Met | `CanonicalComponentVariants.variantSet/overrides/validate*`, schema-26 gate in `DocumentSerializer`; `testComponentVariantsUseOneStrictCanonicalEncodingWithinLimits`, `testComponentVariantsRoundTripAndRequireSchemaTwentySix` |
| SF-0904-002 Create and modify | Met | `ComponentVariantCommandRegistry`, `rewrite`, `ComponentVariantEditingBar/Manager/ChoiceFields`; `testVariantAxesValuesAndCombinationsAreEditedInOneUndoableTransactionEach`, `testEditingInsideAVariantStoresItsSettingsAndKeepsStructureShared`, `testCopyVariantChoiceIsOneUndoableStepAndFollowsTheVariantSize`, `testWorkspaceEditsInsideAVariantAndReturnsToBaseOnExit`, UI journey |
| SF-0904-003 Resolution rules | Met | `resolution(for:set:)` sources/findings, `source(of:on:set:combination:)`, `ComponentVariantOverridesView`; `testComponentVariantResolutionFollowsOnePrecedenceRuleAndKeepsUnavailableChoices` |
| SF-0904-004 Failure and recovery | Met (after fixes 2–3) | Kept choices + findings, `componentVariantResolvesInvalid`, stale target refused and reconciled; `testComponentVariantThatWouldBeInvalidIsRejectedWithItsReason`, new `testUndoThatRemovesTheEditedVariantReturnsToBaseAndRefusesStaleEdits` |
| SF-0904-005 History and persistence | Met | One `.batch` per edit; converted commands in history; clipboard v7; detach/duplicate; `testDetachPageAndDefinitionDuplicateKeepTheVariantACopyShows`, `testComponentVariantsTravelThroughClipboardAsVersionSevenAndCopiesKeepTheirChoice` |
| SF-0904-006 Accessible operation | Met (after fix 6) | Identifiers/labels/hints on every control, announcements via `announcementPoster`, Return/Escape on name fields |
| SF-0904-007 Performance and scale | Met (after fix 4) | `testComponentVariantsStayWithinBoundsOnStandardLargeAndStressFixtures`; availability without whole-document validation; new `testVariantControlAvailabilityUsesTheRegistryRulesWithoutCommitOnlyWork` |
| SF-0904-008 Diagnostics and tests | Met (after fix 5) | `ComponentVariantDiagnostic`; diagnostics asserted in the new undo test; unit, rendering, clipboard, UI coverage |
| SF-0301-001 Authoritative state | Met | Versioned package v1/v2, strict manifest; `testPackageVersionTwoSplitsALargeDocumentIntoBoundedPageMembersAndRoundTrips` |
| SF-0301-002 Create and modify | Met | Save/Save As/autosave unchanged on top of `makeMeasuredContainer`; `testProjectAboveOneMemberSavesAsPackageVersionTwoAndReopensIdentically` |
| SF-0301-003 Resolution rules | Met | v1 when the document fits one member, v2 otherwise; ordered packing; `testPageSplitPacksWholePagesInOrderAndRefusesTamperedMembers` |
| SF-0301-004 Failure and recovery | Met | Specific refusals, last saved file unchanged; `testPackageVersionTwoReaderRefusesMalformedPageMembers`, `testProjectTooLargeSaveAndAutosaveAreRefusedTruthfullyWithoutWriting` |
| SF-0301-005 History and persistence | Met | Same write path for save, autosave and recovery; `testProjectPreferencesPersistAtLargeFixtureAndRespectPackageLimitAtStress` |
| SF-0301-006 Accessible operation | Met | Capacity status text names the closer limit ("Largest page N% full"); no new controls |
| SF-0301-007 Performance and scale | Met | Large and stress fixtures saved/measured; `testProjectFileCapacityIsMeasuredOnSaveAndAutosaveAndWarnsNearTheLimit` |
| SF-0301-008 Diagnostics and tests | Met | Existing package write/read diagnostics wrap the new path; 4 new + 3 changed tests |

Totals: 16 Met, 0 Partial, 0 Missing (all "Met in source, unverified": nothing has been compiled or run).

## Remaining work

- **Blocked on owner decision — OD-142 (proposed below):** a variant's own text is not translatable. Localized output
  (`SiteLanguageOutput.translatedDocument`) translates the base `content.text` / control label of definition nodes,
  but a variant override (`component.variant.v1.override.<target>.content.text`) holds default-language text and is
  applied on top during `expand`, so a copy showing that variant prints the default language in every language tree,
  and `SiteTranslationReport` does not count it as missing. Fixing it needs a new translation key shape for variant
  targets (model + Inspector + report) — an owner decision.

## Known behavior flagged for Codex (in my area, by design, not changed)

- The in-app Preview while a definition is open compiles `canvasDisplayedDocument` (the presented variant), so it
  starts on the definition showing the variant being edited, as the canvas does. If that Preview follows a link to a
  page that contains copies of the same component, those copies also show the edited variant. Website Preview and
  export (fix 1) are not affected.

## Intended plan / OD status-line changes (exact text, for lane V15)

OD-033, replace the "Implementation status" bullet with:

> - Implementation status: complete in source, not verified (Code Forge batch 07, 2026-11-26; document schema 26,
>   clipboard v7, ADR-0029). Re-verified by reading and fixed by lane V03, 2026-11-26 (Website Preview, export and
>   Check Website compile the stored project; an edited variant removed by Undo is refused and editing returns to
>   Base; variant diagnostics; control availability without whole-document validation). Owner choice 2026-11-26:
>   edit inside the variant; structure only in Base. Out of scope: transitions between variants and per-breakpoint
>   variant selection. Open: OD-142 (translating a variant's own text).

OD-032, replace the "Implementation status" bullet with:

> - Implementation status: complete in source, not verified (Code Forge batch 08, 2026-11-26; ADR-0030); re-read in
>   full by lane V03 2026-11-26, no defects found. Package v1 is still written when the document fits one member;
>   larger documents are written as package v2 with ordered page members. The refuse-and-warn behavior below now
>   applies to the 8 MiB file limit and the 4 MiB per-page limit.

New entry to add to `docs/OPEN_DECISIONS.md`:

> ## OD-142 — Translating a component variant's own text (SF-0904 × SF-1007)
>
> Status: Proposed by Code Forge lane V03 — 2026-11-26. Needs an owner decision.
>
> - Context: OD-033 variants may override `content.text` and the control label per variant
>   (`component.variant.v1.override.<target>.<key>`). OD-038 translations are stored per node and field for the base
>   value only. In each language tree the base text is translated, but a copy that shows a variant with its own text
>   prints the default language, and the translation report does not list it.
> - Recommended default: make variant text translatable like base text — one translation per (node, field, variant
>   target, language), stored next to the override in the definition, shown in the Translations Inspector while that
>   variant is edited, counted by the translation report, applied by `SiteLanguageOutput.translatedDocument` to the
>   override; clipboard and remove/re-key of variant targets carry them like overrides.
> - Alternative 1: in a language tree, ignore a variant's text override and show the translated base text (loses the
>   variant's wording in other languages). Alternative 2: keep today's behavior and report each untranslated variant
>   text as missing.
> - Tradeoff: the default needs a new translation key shape (document schema 27 optional keys, rule-8 checklist) and
>   Inspector work; alternatives are smaller but visibly wrong in translated sites.
> - Affected requirements: SF-0904-002/003, SF-1007-002/003/007.
> - Deadline: before any localized site that uses text variants is published.
> - Safe temporary assumption: today's behavior (default-language variant text in every tree); no data change.

Plan (lane V03 row):

> V03 (batches 07–08): done — 6 code fixes in variants (output compiles the stored project; stale variant target
> refused and reconciled; diagnostics; availability without whole-document validation; accessibility), package v2
> re-read with no defect; 2 tests added; ADR-0029 amended; OD-142 proposed. Report:
> docs/reviews/LANE-V03-review-2026-11-26.md.

## New/changed test selectors

- New: `SiteForgeTests/CommandKernelTests/testUndoThatRemovesTheEditedVariantReturnsToBaseAndRefusesStaleEdits`
- New: `SiteForgeTests/CommandKernelTests/testVariantControlAvailabilityUsesTheRegistryRulesWithoutCommitOnlyWork`

## Suggested first checks for Codex

1. `ComponentVariantCommandRegistry.prepare(_:definitionID:expectedDocumentID:expectedRevision:document:isLifecycleAvailable:lifecycleDisabledReason:forCommit:)`
   default argument and the private `setCommands(…, countingRepairs:)`; all existing callers omit `forCommit`.
2. `CanonicalComponentVariants.rewrite`: the recursive local `func editsDefinition(_:) -> Bool` (switch-expression
   body, used as `commands.contains(where: editsDefinition)`), and `guard let set = try variantSet(in: page),
   isEditable(target, in: set) else { … }`.
3. `CanonicalComponentVariants.isEditable(_:in:)` — switch expression as the function body.
4. `reconcileVariantEditingTarget()` is called inside the `documentSession.$document` sink's
   `DispatchQueue.main.async` block, with the same isolation as `synchronizeIsolationRoot`.
5. `testUndoThatRemovesTheEditedVariantReturnsToBaseAndRefusesStaleEdits` (async): two publications (Undo, then the
   rename) are queued before the expectation; the first is skipped by the sink's revision guard, the second
   reconciles. If it is flaky, drain the main queue twice.
6. `.accessibilityLabel(label ?? title)` in `ComponentVariantManager.button`.
7. Original Batch 07 checks still apply: Swift 6 isolation of `DocumentSession.authoringTransform` and its closure;
   `@Published private(set) var editingComponentID { didSet }`; SwiftUI type-check time of `ComponentVariantManager`
   (the axis `HStack` now has two more `let`s) and `ComponentVariantChoiceFields`.
8. Batch 08: `ProjectPackagePageSplit.split` relies on `encodedPages` matching `DocumentSerializer.encode` byte for
   byte (same encoder settings); `join` slices `Data` from `ArchiveCodec.decode` (non-zero `startIndex`) — only
   `range(of:)`/`dropFirst()`/`dropLast()` are used, which are index-safe.

## Out-of-area issues (not fixed)

- `ContainerQueryEdit.diagnosticOperation` (`SiteForge/TransformModel.swift`, batch 09/SF-0605) is declared but never
  recorded — the same diagnostics gap fixed here for variants (lane owning batch 09).
- OD-142 localization interplay (SF-1007 lane).

## Write problems

None (no AnchorError, no ICloudRenameError, `foreign_changes(30)` empty before every write, `icloud_duplicates()`
empty, `check()` empty for every changed Swift file). The device went offline once during verification; work resumed
after it reconnected.
