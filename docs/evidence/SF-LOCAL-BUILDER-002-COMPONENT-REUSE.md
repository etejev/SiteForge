# Practical component reuse — focused source checkpoint

Current accumulated acceptance inventory: `SF-LOCAL-BUILDER-005-INTEGRATION.md`.
Results below remain historical 002 source evidence, not integrated/native acceptance.

## Scope and authority

SF-LOCAL-BUILDER-002, IN PROGRESS. Bounded SF-0901-003/005/006,
SF-0902-003/005/006, SF-0905-003/005/006 and inspection-oriented
SF-0907-003/006 remain Partial. Reuse ADR-0018's canonical definition graphs,
the existing six property types, dependency inspection, immutable expansion,
command history and package/recovery paths. No new schema or component store.
OD-018 supplied slots and OD-019 retarget/conversion remain excluded.

## Delivered source behavior

- Components offers named creation with native Cancel/validation, using the
  existing identity-gated component registry. Supported authored containers
  preserve their original NodeID and placement as the first instance. Definition
  cloning and conversion form one atomic undoable operation. Name collision,
  cancellation, stale identity, managed page structure, nested components and
  inbound child-link restrictions do not bypass the established preflight.
- Eligibility and commit share that preflight. The empty pane explains what to
  select and offers ordinary Insert Frame, not fixture content or a hidden hook.
- Definition editing captures a typed, scene-local origin: document, page,
  ordered selection, primary/anchor/container and component reference identities.
  Return to Instance/Page restores it through existing adopted-scene validation.
  Deleted/locked/retargeted nodes are not replaced by arbitrary selections;
  missing pages use an existing website page with truthful recovery feedback.
  Layers inspection of hidden nodes remains distinct from canvas hit targets.
- Design and Content reuse the same organized exposed-property controls,
  discovery and retained-conflict recovery. No exposed properties has a real
  Edit Definition entry. Reset All with retained conflicts requires confirmation;
  canonical removal and exact inverses remain in the existing registry.
- Text fields retain instance/property identity across renderer revisions instead
  of rebuilding the focused editor. Scene-local drafts accept Return or valid
  focus loss, cancel on Escape, and clear before explicit Reset. A successful
  event is clean before possible blur; a fresh renderer identity is required for
  the next command. Unrelated adoption preserves unfinished typing; changed
  committed values/context retain the draft with explicit conflict feedback.
  Other existing property editors retain their established revision-reset policy.

## Focused results

Final changed-source group: **17/17 code tests passed**, zero failures/skips.
The application and both test targets compiled, including the new native journey.
Repository checks pass, including security/hygiene, architecture boundaries,
425-record traceability, foundation evidence and tooling checks. `git diff --check`
passes. No build, test or collector remains active. Apple service-connection
diagnostics remain in the test log; no warning-free-runtime claim is made.
Result bundle `focused-f103d520-b2ea-48ce-8250-248caa257d04.xcresult` and
`final-focused.log` are retained owner-locally under ignored
`.codex-loop/component-reuse-focused/`.
Earlier incremental groups passed 6/6 and 11/11; they are not additional unique
coverage. The final 17 include seven new tests:

`SiteForgeTests/CommandKernelTests/`:

- `testComponentNamedCreationIsAtomicAndPreservesSourceIdentity`
- `testComponentNamedCreationCancelledStaleDuplicateAndUnsupportedAreNeutral`
- `testComponentDefinitionReturnContextRestoresOrderedSelectionAndRejectsReplacement`
- `testComponentDefinitionReturnContextDoesNotSelectRetargetedLockedOrHiddenInstances`
- `testComponentTextDraftAdoptionPreservesTypingAndRejectsConflictingContext`
- `testComponentConnectedReusePropagationResetHistoryAndImmutableOutput`

`SiteForgeTests/PersistedHistoryTests/`:

- `testComponentReuseSaveReopenRecoveryAndExactResetHistory`

Ten existing regressions also passed in that final group:

- `testComponentDefinitionContextUsesAuthoringGraphWithoutWebsiteNavigation`
- `testComponentTextIndependentEmptyOverridesDefaultPropagationAndExactResetHistory`
- `testComponentTextStaleCancelledInvalidAndVirtualTargetsAreNeutral`
- `testComponentImageFitChoiceOverrideResetHistoryRendererAndPersistence`
- `testComponentImageMediaOverrideResetHistoryRendererPersistenceAndValidation`
- `testComponentActionOverrideResetHistoryRendererPersistenceAndValidation`
- `testComponentSlotFallbackDefinitionUpdatesDetachAndOutputKeepChildIdentity`
- `testComponentPropertyOrganizationAllTypesOrderGroupsAndContentNeutrality`
- `testComponentConflictRecoveryAllTypesResetOneAllExactHistoryAndPersistence`
- `testComponentTextImmutableRendererAndAccessibilityUseEffectiveRevision`

The connected regression verifies two independent instances, definition default
propagation, an authored text override, visibility, reset-all removal, exact
undo/redo, stable virtual IDs, immutable old snapshots, current revision, static
output and canonical round-trip. The lifecycle regression performs actual local
package save/open and autosave recovery with retained history and reset inverses.
No original Aurora package or recovery directory was used.

## Native and visual acceptance pending

New compiled but **not executed**:
`SiteForgeUITests/SiteForgeLaunchTests/testPracticalComponentNamedCreationDesignDraftAndReturnJourney`.
It uses real pane/menu/field controls for empty-state insertion, named creation
and cancellation, exposed text, Return to Instance, Design editing, Return,
focus loss, Escape and native save/reopen. Its screenshot names are planned
attachments, not retained/passing evidence. Existing two-instance/media/action/
fallback/recovery journeys passed in the historical 815-test baseline, but that
does not prove the changed native composition.

Native inspection remains unavailable as recorded in OD-025; do not repeat the
failed binding or known automation-mode timeout. No new live inspection,
screenshots, pointer-action comparison, VoiceOver certification, Safari run,
installed refresh or full changed-tree gate is claimed. No permission change,
force quit, original project conversion or genuine recovery action occurred.
The earlier 682 code + 133 UI = 815 pass verifies the pre-package fingerprint,
not this source. The regular installed app remains that verified version; its
current saved/modified owner work is unknown and must not be overwritten.

## Exact continuation

After native access is restored, run the new exact journey above plus the existing
two-instance text and retained-conflict recovery journeys; inspect original
captures for readable grouped controls, persistent focus, exact return selection,
no clipping/wrapping/ghosts, and maximized windowed presentation. Exercise the
same resolved content in actual Safari; do not substitute model-only output for
browser acceptance. Record a matched public-control action audit only if observed.
Then perform one final accumulated changed-tree gate, reconcile evidence, and
refresh the installed app only after normal saved/quit proof. Leave work
uncommitted and do not use GitHub. Variants, nested/supplied slots, retargeting,
remote libraries, release and broad export/browser parity remain excluded.
