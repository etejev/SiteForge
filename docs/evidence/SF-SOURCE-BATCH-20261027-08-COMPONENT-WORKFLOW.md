# SF-SOURCE-BATCH-20261027-08 — Coherent reusable component workflow

Current receipt: the listed new model methods and actual-app journey have passed
current-source affected acceptance. Final full verification passes:785 non-UI,
151 UI,0 failures,3 intentional owner-session skips; full-e7ee511e is the
authoritative939-method result. The bounded local slice is accepted.
The implementation-time UNRUN/owner-hold text below is historical and superseded
by approved local acceptance. Exact correction results and inspected screenshots
are indexed in [the integration receipt](SF-SOURCE-BATCH-20261027-10-INTEGRATION.md).
Normative modules remain Partial; no push or installation is authorized.

**IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.**

IN PROGRESS; normative modules remain Partial. Static file/diff inspection and
source editing only. No tests/builds/check scripts, runtime inspection,
readiness/authentication, collectors, UI/app/browser launches, visual acceptance,
installation, signing, cleanup, commits or GitHub actions. No screenshots were
captured. Historical 002 passes and cancelled integrated verification do not
cover these changes. Deleted schedule and owner packages remain untouched.

## Contract and inspected baseline

Bounded SF-0901-002/003/005/006: named definition editing/navigation, linked
identity/history and native operation. SF-0902-002/003/005/006: existing typed
exposed properties and definition/instance edits. SF-0905-003/004/005/006:
defaults versus overrides, exact reset/history and missing-source safety.

002 already supplies named creation, exact definition return context, six exposed
property types, organized instance controls and conflict recovery. This source
does not reconstruct them. ADR-0018 remains authoritative: definitions use the
existing canonical graph, linked instances stay childless, and rendered virtual
children are never canonical edit targets. OD-018 supplied content and OD-019
retarget/conversion decisions remain open and unchanged.

Actual gaps found: definition text fields were rebuilt on every adopted revision,
discarding typing; ordinary properties lacked direct source navigation; recovery
source navigation queued a source even when entry was rejected; entry/return ran
editing preparation again after changing the active graph; Rename constructed
fresh context at commit. Clean instance fields also repeated inactive Apply/Cancel.

## Implemented source path

- `SiteForge/TransformModel.swift`: pure typed property-source destination resolves
  existing text/visibility/choice/media/action/fallback bindings by stable identity
  to their real definition node. Missing definitions/bindings/virtual targets do
  not guess substitutes. Paired definition label/default drafts reuse existing
  `ComponentInstanceTextDraft` adoption/conflict behavior and separately detect
  binding identity replacement. No serialized draft/source record or schema.
- `SiteForge/WorkspaceShellModel.swift`: captured scope/current-renderer guards
  source navigation and Rename. Definition entry reports acceptance; rejected
  entry cannot enqueue a different graph's source. Shared page-adoption logic is
  reused after one completed edit/IME boundary rather than asking old fields to
  commit again in the replacement graph. Existing Return context still restores
  ordered IDs, primary/anchor/container and checks actual lifecycle validity.
  Source entry opens Content/Layers on the actual binding and explains shared
  propagation. Empty prepared component commands are accepted without history;
  unchanged Rename retains the registry's existing truthful rejection.
- `SiteForge/WorkspaceShellView.swift`: native Edit Property Source actions on
  organized exposed fields, scoped shared-default explanation, automatic property
  disclosure on definition entry and retained definition text field identity.
  Typing remains enabled across renderer adoption while commits await a valid
  identity. Return/valid blur/Apply uses one existing `exposeText` transaction;
  first exposure remains explicit. Invalid/stale/conflicting drafts remain visible,
  Cancel/Escape reloads committed values, and context changes cannot resurrect a
  removed/replaced binding. Source navigation participates in existing edit-commit
  requests. Guarded blur avoids repeating a draft already handled by navigation.
  Instance Apply/Cancel appears only for a dirty/conflicting text draft; Reset
  remains explicit. Other definition property editors retain their established
  revision-reset/explicit-Apply policy; this is not a universal draft overhaul.

All content edits use existing component/property registry commands and exact
inverses. Stable definition/NodeID/property identities, independent instance
values, media resources, link targets, choice values, slot fallbacks and responsive
intent are preserved. Native graph resolution and static compiler remain the
consumers; no second renderer/store/cascade or direct property writes in views.
Draft/error feedback adds no authored text, filenames or paths to diagnostics.

## New acceptance source — five methods, all UNRUN

`SiteForgeTests/CommandKernelTests/`:

1. `testComponentDefinitionTextDraftRetainsPairedEditsAndDetectsBindingReplacement`
   — paired typing across pending/current adoption, binding replacement and
   external-value conflicts, explicit clean reload.
2. `testComponentPropertySourceDestinationsCoverExistingTypesAndRejectMissingDefinitions`
   — all six typed sources, stable source nodes, wrong graph, missing definition,
   unknown binding/instance and canonical serialization neutrality.
3. `testComponentPropertySourceTransitionReturnsExactInstanceAndGuardsRenameContext`
   — fixture-owned lifecycle, one edit boundary per entry/return, original
   instance/primary/history, rejected source/recovery entry, stale Rename and
   valid rename/undo preserving definition references.
4. `testComponentSourceDefaultEditsKeepOverridesAppearanceStatesAndCompilerParity`
   — repeated default/name edits retain binding/property IDs and independent
   text override; immutable preview snapshots and static output agree; existing
   hover appearance metadata/resolution survives; exact history/serialization.

`SiteForgeUITests/SiteForgeLaunchTests/`:

5. `testComponentDirectPropertySourceRetainsDefinitionDraftAndExactInstanceJourney`
   — real named creation, repeated exposed-default editing, Escape, independent
   instance text, one-click source layer, exact Return, explicit Reset and Undo/
   Redo. Planned `SF-SOURCE-08` screenshot names are not captured evidence.

Future affected dependencies include the existing named creation/cancel tests,
`testComponentConnectedReusePropagationResetHistoryAndImmutableOutput`,
`testComponentReuseSaveReopenRecoveryAndExactResetHistory`,
`testComponentPropertyOrganizationAllTypesOrderGroupsAndContentNeutrality`,
media/action/choice override regressions, and
`testPracticalComponentNamedCreationDesignDraftAndReturnJourney`.
Separate approval is required before compiling/running them and reviewing
original-resolution normal/compact/native keyboard/VoiceOver evidence.

## Limits

SF-0904 variant axes/combinations/instance switching are not implemented. Existing
Image Fit choices and reusable hover/focus/pressed/disabled appearance states do
not imply component variants. The new source test preserves existing appearance
resolution; it is not a native interactive-state or browser acceptance result.
Supplied slot ownership, retained-conflict retargeting, remote libraries, broad
browser/export parity, scale/localization and release acceptance remain deferred.
Package/recovery, IME, focus and visual behavior still require future execution;
no requirement or mandatory gate is waived by this source checkpoint.
