# SF-AUTHORING-119 — Component-property grouping and ordering

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED. Development Prompt 6/10,
2026-10-13. Six new selectors; zero test/build/check/automation executions.
No screenshots were produced, no visual result is claimed, no commit/push.

## Contract and scope

Specification §9.2 explicitly includes labels and grouping. Bounded requirements:
SF-0902-001–008, SF-0905-003/004/005/006; supporting SF-0308-003/004/005/008,
SF-1201-003 and SF-1203-003. All modules remain Partial. Dependencies:
111/113–118, ADR-0018 and the shared SF-PRODUCT-UI-008 visual components.
Flat named presentation groups are reversible metadata, not a new content
store. Nested/collapsible groups, conditional visibility, bulk organization,
supplied slots and broad release/output certification are excluded. OD-018
remains open; no linked instance children or slot ownership are introduced.

## Delivered source behavior

- Schema v15 optional `component.organization.v1.<binding-kind>.binding/group/order`
  properties live on definition source nodes. Existing typed bindings supply
  stable references; defaults, values, labels, instance overrides and childIDs
  remain the single original sources. The binding field is a strict typed
  reference to the existing ID, not a new identity or value store; raw binding
  replacement cannot inherit stale organization by matching only a type.
  No duplicated group/entity/property store.
- Group names are exact case-sensitive trimmed labels, 1–64 UTF-8 bytes without
  control characters; empty UI draft removes membership. Equal names share one
  flat group. Orders are finite integral 0–63 with unique authored ranks across
  the definition. Metadata requires a live binding of its matching type and
  authored origin; unknown keys, doubled separators and orphan state fail.
- Untouched definitions use type plus canonical root/child ownership order,
  with stable-ID final tie-breaking; transfer-generated UUIDs cannot reshuffle
  defaults. Authored order wins. Groups appear at first occurrence and maintain
  member order. Reset removes only the selected binding's group/order metadata,
  revealing default presentation; it does not renumber children or reset values.
- Central component registry validates document/page/revision/scene/renderer,
  lifecycle, selection, availability and locks before one property batch. Reorder
  compiles the complete bounded rank set atomically with existing PropertyIDs
  retained and exact inverses. No-op values emit no property changes. Invalid,
  stale or cancelled edits produce no mutation and contain no draft diagnostics.
  Binding rename retains organization; removal deletes its organization only,
  leaving surviving authored overrides as recoverable conflicts.
- Native definition fields show group, position and authored/default provenance;
  Apply/Return, Cancel/Escape and Reset use captured identity. One linked instance
  uses grouped text, Boolean, Image Fit, media, action and fallback-slot fields,
  their existing provenance and reset routes. Multiple selection remains truthful
  inspection-only. Missing values retain explicit conflict/reset explanation.
- Dependency details include ordered labels/groups. Clipboard validates metadata;
  structural equivalence normalizes binding references and includes group/order;
  mapped source nodes/binding IDs
  retain metadata, existing property-ID regeneration owns copies/imports.
  Immutable component expansion and detach strip presentation metadata, so
  renderer/Preview/output values, geometry and canonical instance overrides do
  not change. Older schema headers reject forged new namespaces; supported
  old documents decode without authored organization.

## Unrun Prompt-10 targets — six selectors

CommandKernelTests:

- testComponentPropertyOrganizationAllTypesOrderGroupsAndContentNeutrality
- testComponentPropertyOrganizationAtomicHistoryResetRemovalAndSchemaRoundTrip
- testComponentPropertyOrganizationRenameRemovalConflictAndDetachPreserveIntent
- testComponentPropertyOrganizationRejectsInvalidDuplicateMissingStaleAndCancelledState

ClipboardTransferTests:

- testComponentPropertyOrganizationTransferRemapsBindingsAndPreservesGroupsOrder

SiteForgeLaunchTests:

- testComponentPropertyOrganizationNativeKeyboardCancelHistoryAndReopenJourney

Source covers all six kinds, renderer-neutral resolved graphs at all presets,
schema round-trip and forged old headers, stable metadata inverses/reset,
rename/removal/conflict intent, detach cleanup, malformed/duplicate/out-of-range
state, cancellation/stale identity/mixed selection, transfer ID remapping and
native keyboard/group/history/save-relaunch. Named screenshot attachment source
exists but no image has been captured or inspected.

## Files and pending risks

Production: DocumentModel, TransformModel, ClipboardTransfer, InsertionModel,
WorkspaceShellModel and WorkspaceShellView. Tests: CommandKernelTests,
ClipboardTransferTests, SiteForgeLaunchTests plus current/future-schema assertion
updates in LinkAuthoringTests, ProjectResourceTests, InsertionModelTests and
SnappingGuideModelTests. Queue/status/changelog/handoff/ADR/visual/traceability
records describe source coverage only.

Prompt 10 must compile SwiftUI grouped fields, validate native focus/Escape and
actual accessibility replacement, inspect original-resolution compact/maximized
light/dark screenshots, execute recovery and all accumulated migration/output
regressions, run hygiene/privacy checks and the final authoritative gate. The
prior runtime evidence is historical and not proof of schema-v15 or this UI.
No source implementation is marked verified or released.
