# SF-SOURCE-BATCH-20261027-07 — Local assets and image usability

Current receipt: the listed new model methods and actual-app journey have passed
current-source affected acceptance. Final full verification passes:785 non-UI,
151 UI,0 failures,3 intentional owner-session skips; full-e7ee511e is the
authoritative939-method result. The bounded local slice is accepted.
The implementation-time UNRUN/owner-hold text below is historical and superseded
by approved local acceptance. Exact correction results and inspected screenshots
are indexed in [the integration receipt](SF-SOURCE-BATCH-20261027-10-INTEGRATION.md).
Normative modules remain Partial; no push or installation is authorized.

**IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.**

IN PROGRESS; normative modules remain Partial. Static source/diff inspection and
ordinary editing only. No tests, builds/build-for-testing, checks/lints, full gate,
UI/readiness/authentication work, app/browser launches, visual acceptance,
installation, signing, cleanup, commit or GitHub mutation. No new screenshots.
Historical 004 results and the cancelled integrated gate do not cover this source.

## Bounded requirements and actual gaps

SF-0802-002/003/005/006: practical image fit/focal/semantics, resolution, atomic
history/persistence and native accessible operation. SF-0807-002/003/004/005/006:
selected-use versus shared replacement, reference safety, cancellation/recovery.
Supporting SF-0801-004/005: corrupt-input neutrality and retained original bytes.
SF-0806 URL capabilities are not newly implemented or claimed by this slice.

Inspected existing 004 delivery rather than reconstructing it: Assets already
has import, search/folder/tag/favorite/usage filters, rename, organization,
dependency reveal and safe deletion; scoped reuse/import and explicit global
replacement already share canonical resources and native panels. Placement,
fit geometry, security-scoped import, off-main decoding/thumbnail budgets,
component/fill/favicon inventory and immutable output already exist.

Actual remaining gaps: mixed Images hide all controls; focal/alt drafts can be
overwritten during adoption or commit using a later selection's identity;
unchanged edits create history; missing resources lack a selected-image recovery
status; reuse sheets inherit unrelated navigator filters. Displayed rounded
focal percentages must not coerce an untouched canonical coordinate.

## Source implementation

- `SiteForge/TransformModel.swift`: ephemeral per-property Image selection/draft
  projection, exact canonical fallback for an untouched focal coordinate, and a
  typed details intent compiled by the existing Image registry into one atomic
  property batch. A mixed coordinate requires explicit input. Invalid partial
  pairs, nonfinite/range errors and invalid descriptions reject before mutation.
  Lifecycle/identity/kind/subset gates and exact property inverses remain central.
  Repeated already-authored values return an empty neutral prepared command.
- `SiteForge/WorkspaceShellModel.swift`: optional captured scope/revision and
  current-renderer guard, neutral state handling, cancellation announcements,
  per-property projection and resource status from the current immutable plan.
  Off-breakpoint objects are not called missing solely for lacking a painted
  object. No resource-byte reads or decoding were added to the main actor.
  Reuse search spans canonical project assets without changing navigator filters;
  clear filters is noncanonical scene state.
- `SiteForge/WorkspaceShellView.swift`: mixed native fit/focal/alt/decorative
  controls, explicit mixed meaning choice, accessible draft/committed values,
  non-destructive fit explanation and selected-use/global recovery guidance.
  Real text editing captures opening scope/revision. Return/valid blur/Apply
  commit pending Image details once; Save/context requests reject invalid/stale
  drafts. Escape/Cancel discards drafts without property changes. The two focal
  fields can be traversed before committing their pair. Other image operations
  require pending drafts to be applied/cancelled first. Shared actions remain
  explicitly scoped, and absent metadata no longer offers a dead global action.
  Component media pickers and reference names likewise read the canonical asset
  catalogue, not filtered navigator rows, so filters cannot falsely report a
  valid inherited/overridden image as missing or disable its picker.

No schema, resource store, renderer, selection system or import pipeline was
added. Native render preparation, image fit geometry and static compiler consume
the same existing `content.image.v1` properties. AssetID/NodeID, responsive/layout
intent and source bytes remain unchanged by fit/focal/alt edits. Header/Footer
image visibility, Page/site favicon references and component overrides are not
rewritten. Approved Dark Flow gradient and all owner packages/evidence untouched.

## New acceptance source — all UNRUN

`SiteForgeTests/ProjectResourceTests/`:

1. `testImageInspectorProjectsEachMixedPropertyWithoutPrimaryBorrowing` —
   different assets, common versus mixed properties, exact unedited focal
   precision, explicit mixed pair and unsupported subset.
2. `testImageDetailsDraftBatchIsAtomicNeutralAndExactlyReversible` — combined
   metadata commit, PropertyIDs, geometry/reference preservation, invalid/cancel
   neutrality, exact undo/redo and serialization.
3. `testImageDraftOwnershipMissingRecoveryAndOutputPreserveOriginalResource` —
   unavailable-resource snapshot, restore through existing resource lifecycle,
   stale draft rejection, neutral repeats, renderer identity/focal values,
   escaped static alt and fit output, exact original bytes and package reopen.
4. `testImageReuseSearchIsIndependentAndClearFiltersIsNoncanonical` — search by
   metadata despite navigator filters, no document/history changes, corrupt
   native import candidate rejection.

`SiteForgeUITests/SiteForgeLaunchTests/`:

5. `testImageMixedFitAltDraftAndIndependentAssetReuseJourney` — fresh normal
   maximized app, native import/two uses, Fit/Fill/Stretch with stable bounds,
   alt blur, invalid focal/Escape, real Layers mixed selection/atomic alt,
   Undo/Redo and reuse chooser independent of navigator filters. Future named
   `SF-SOURCE-07` attachments are instructions, not existing visual evidence.

Existing future regression dependencies: `testSelectedImageImportIsAtomicLocalDeduplicatedAndReopensWithOriginalBytes`,
`testSelectedImageDecodeCompletionRejectsStaleSelectionAndCancellation`,
`testSelectedMediaAssetUseAndGlobalReferenceInventoryPreserveScope`,
`testImageImportPreservesExactBytesMetadataAndRejectsCorruptInput`,
`testFrameImageFillPaintsInsideAuthoredBoundsAtNativeScale`, and
`testPracticalImageReuseScopedReplacementAndTypographyJourney`.
Do not attribute historical passes to this modified tree.

## Remaining acceptance and exclusions

Requires explicit owner approval before compilation, exact focused selectors,
original-resolution normal/compact/200%-scale review, VoiceOver/keyboard,
interruption/recovery and integrated verification. The source depends on the
existing captured-context mechanism from source batch 04, not a second cascade.
No new owner architecture decision or irreversible migration is needed.
Remote providers, SVG/code execution, audio/video, new crop/rendition/import
systems, new font work, broad output parity and release acceptance remain out
of scope. Testing hold and deleted-schedule boundary remain unchanged.
