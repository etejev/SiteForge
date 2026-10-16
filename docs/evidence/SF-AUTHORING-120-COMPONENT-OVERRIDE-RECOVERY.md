# SF-AUTHORING-120 — Retained component override recovery

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED. Development Prompt 7/10,
2026-10-13. Seven new selectors are written; none executed. No build/compiler/
parser/linter/script/check/automation/verification/GitHub/commit/push action.

## Contract and bounded semantics

SF-0902-004/005/006/008; SF-0905-003/004/005/006/008; supporting SF-0901-004,
SF-0308-004/008, SF-1201-003 and SF-1203-003. Dependencies: 113 guards, 117
action/transfer, 119 grouping, ADR-0018 and SF-PRODUCT-UI-008. Modules remain
Partial, and source implementation is not verified completion.

The specification requires stable/migrated intent, recovery and history but
does not define target selection, collision resolution, tombstones or cross-
type conversion. OD-019 records that unresolved policy. This independent slice
implements explicit reset/reveal/original-data restoration only. It does not
retarget by label, rewrite property types, invent original source locations or
waive transition guards. OD-018 and childless/fallback slot ownership remain
unchanged; supplied slots, broad migration/runtime certification are excluded.

## Delivered source behavior

- `CanonicalComponentOverrides.conflicts` derives stable instance/definition/
  binding/PropertyID findings, typed retained values, available source paths and
  missing-definition/property/action-destination reasons. No recovery state is
  stored canonically. Original values, origins and IDs survive unavailable data.
- Native grouped Inspector shows non-color-only summaries, exact retained
  text/Boolean/Image Fit/media/action intent, reason and repair guidance. Original
  definition/source navigation validates the captured document/page/revision/
  scene/renderer/selection before changing only scene navigation. Unknown sources
  cannot be guessed or revealed. Existing valid action controls can edit a new
  destination on the same binding; this is not override retargeting.
- Reset-one/reset-all-retained-conflicts disclose removal/default consequences
  and require a native confirmation with Cancel/Escape. The central registry
  validates confirmed state, stable expected PropertyIDs, live conflict subset,
  identity/lifecycle/selection/availability/locks and duplicate/missing targets.
  One existing property batch removes only the chosen conflicts; exact inverses
  restore IDs, values, origin and ordering. Healthy overrides, definitions,
  organization, selection identity and canonical geometry remain unchanged.
- Undo restores removed binding metadata with its original source/identity when
  that removal is the history item being undone. Reopening original definition
  data can also restore original IDs. No fake Restore or Convert button claims
  to recover a source absent from both history and saved data. Reset on a missing
  definition removes the chosen value but retains the missing definition ref.
- Dependency details expose the same reason/identity findings and usage reveal.
  Copy and paste preflight reject unresolved bindings without mutation. Valid
  internal action mapping still uses existing transfer ownership checks rather
  than guessing destination identity across projects. Diagnostics use categories
  and stable sanitized identifiers, never retained text, destinations or paths.
- Preview open/refresh/runtime compiler and static build fail closed on retained
  conflicts or missing original definitions. A previous valid Preview is kept
  with an explicit blocked status; conflicted current content is not published.
  Authoring still retains/inspects canonical content and editor placeholders.
- Schema remains v15. Encode/decode use the shared bounded projection validation
  while permitting valid retained conflicts. Earlier supported packages remain
  readable; no new storage, serialized UI request or incompatible migration.

## Exact unrun Prompt-10 selectors — seven

CommandKernelTests:

- testComponentConflictRecoveryAllTypesResetOneAllExactHistoryAndPersistence
- testComponentConflictRecoveryMissingDefinitionAndOriginalBindingRestoration
- testComponentConflictRecoveryRejectsUnconfirmedCancelledStaleHealthyAndDuplicateTargets
- testComponentConflictRecoveryPreviewAndStaticOutputFailClosedWithoutDisclosingValues
- testComponentConflictMissingActionDestinationSharesDependencyFindingAndPreservesHealthyOverrides

ClipboardTransferTests:

- testRetainedComponentConflictCopyPastePreflightIsRedactedAndNeutral

SiteForgeLaunchTests:

- testComponentRetainedOverrideRecoveryConfirmationUndoAndReopenJourney

Source covers all five authored override types, single/all-conflict reset,
restoration, exact history and serializer round-trip, missing definitions and
action destinations, healthy value preservation, invalid/unconfirmed/cancel/
stale identities, dependency findings, redacted output/transfer blocking, native
cancel, original definition reveal/Undo, save/relaunch and confirmed reset history.
Four named screenshot attachments are source only; no screenshots were captured
or inspected. Existing focused 113/117/119 selectors are also Prompt-10 targets.

## Changed source and remaining verification

DocumentModel, TransformModel, WorkspaceShellModel, WorkspaceShellView,
ClipboardTransfer and CanvasRendererCore; CommandKernelTests,
ClipboardTransferTests and SiteForgeLaunchTests; queue/status/changelog/handoff/
requirement evidence/visual contract/ADR-0018/OPEN_DECISIONS and this note.

Prompt 10 must compile native alert/SwiftUI paths, execute the seven selectors,
check disabled/unavailable/locked/mixed selection behavior, native focus/AX
replacement and exact selected identity, original-resolution compact/maximized
light/dark screenshots, large-project projection/serialization budgets, recovery
and output/transfer regression matrices, repository/privacy checks and the final
gate. Missing image bytes retain existing image-resource recovery; this slice
does not introduce new asset-replacement or licensing workflows. Broader
retargeting/conversion/tombstones need OD-019. No verified completion is claimed.
