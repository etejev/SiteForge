# SF-LOCAL-BUILDER-009 — Formatting reuse source receipt

Current focused acceptance supersedes the historical source-only hold below:
all 15 new code methods pass in the focused 007–011 group. The real formatting
journey passes172.597s after revealing the actual Inspector Tools disclosure;
six original screenshots were inspected. Keep IN PROGRESS;
full verification is deferred, not waived. No commit/push/install or owner-data
change. [Current focused results](SF-LOCAL-BUILDER-007-011-FOCUSED-ACCEPTANCE.md).

Status: IN PROGRESS. Bounded source implementation, NOT compiled, tested or
visually accepted. The renewed owner execution hold applies to builds, tests,
checks, UI/app/browser launches, verification, commits, pushes and installation.
No earlier checkpoint execution validates this changed source.

## Requirement scope

Bounded SF-0702-002/003/004/005/006/008,
SF-0703-002/003/004/005/006/008 and SF-0308-002/003/004/005/006/008.
Existing SF-0506/0507/0508/0509/0510 resolution is reused only for supported
transferred fields. All modules remain Partial. No specification, schema,
renderer, resource store or responsive cascade is replaced.

## Implemented source behavior

- Native Edit and existing Inspector expose Copy/Paste Text Style and
  Copy/Paste Appearance. Inspector uses a compact Reuse Formatting menu,
  context actions, bounded status, subset guidance and pending-preparation
  cancellation. Ordinary Command-C/V is not intercepted.
- Text Style owns canonical family, weight, size, line height, tracking,
  alignment, text foreground/token reference and fluid font-size/line-height
  intent. Appearance owns ordered fill layers/stops, opacity, supported
  border/radius/shadow properties, fill/border/shadow token references,
  reusable appearance links and supported image-fill references. Padding,
  content clipping, layout, authored content, responsive overrides, state
  variants, component references and unrelated families are excluded.
- Copy requires compatible ordinary elements with one common complete family
  bundle. Mixed values are unavailable, never borrowed from the primary node.
  Omitted properties, explicit None and defaulted/authored origins remain
  distinct. Raw canonical literals and references transfer, not computed values.
- Legacy surface/RGBA/token intent is adapted on read; retired fill keys are
  removed atomically when a different bundle is pasted. Equivalent legacy
  intent is a no-op, not a migration-only history entry. Existing target-owned
  PropertyIDs are retained. Fill/stop/fluid identities are normalized solely
  for common-intent comparison, then mapped to existing target identities or
  deterministically allocated in the target namespace. Source identities are
  not transplanted into another element.
- The private versioned clipboard envelope has an exact key allowlist, strict
  canonical encoding, duplicate/unknown/depth/size/type/value rejection,
  1 MiB wire limit, 4096 properties and 1000-target selection limit. It contains
  no image bytes or local paths. Ordinary clipboard text is not executed.
- Same-project references remain linked. Missing tokens/styles/image resources
  reject without flattening. Existing package resource identity, descriptor/
  hash/size and bytes are checked off the main actor for image fills.
  Cross-project transfer is explicitly unavailable in this slice.
- The existing Design registry validates document/page/revision/scene/renderer/
  exact selection identity, cancellation, live availability and breakpoint
  visibility. Missing targets reject atomically; unsupported/locked/hidden
  targets are explicitly skipped. Image fills and explicit shadow flags retain
  existing Frame/Section restrictions; fill-token bindings retain supported-kind
  restrictions. Component instances and managed navigation use owner controls.
- One existing property batch is one history transaction with the existing
  exact inverse. Repeat paste is neutral. Pending drafts/IME must finish or
  cancel first. Worker results are guarded by request, scene, selection,
  document revision, viewport and clipboard identity, including teardown
  cancellation. Success waits for matching renderer adoption. Diagnostics
  contain sanitized identity, family/count/category and timing, never values,
  content or paths.

## Added acceptance source — all UNRUN

Fifteen methods in `Tests/SiteForgeTests/TransformModelTests.swift`:

1. `testFormattingTextBundlePreservesRawTypographyForegroundAndFluidIntent`
2. `testFormattingAppearanceTransfersCompleteLayersEffectsAndKeepsTargetGeometry`
3. `testFormattingCodecRejectsUnknownDuplicateOversizedNestedAndInvalidValues`
4. `testFormattingCommonSourceDoesNotBorrowMixedPrimaryOrLayerIDs`
5. `testFormattingPasteReportsApplicableSubsetAndSkipsLockedAndIncompatible`
6. `testFormattingMultipleTargetsKeepIndependentLayerIDsAndOneHistoryEntry`
7. `testFormattingPasteAtomicInverseUndoRedoBranchAndRepeatedNoOp`
8. `testFormattingPasteRejectsStaleCancelledMissingAndMalformedAtomically`
9. `testFormattingReferencesStayLinkedAndForeignOrMissingDependenciesReject`
10. `testFormattingOmittedExplicitNoneLegacyDefaultsAndNamedInheritanceRemainDistinct`
11. `testFormattingImageFillValidatesExistingResourceBytesAndSkipsUnsupportedKinds`
12. `testFormattingDoesNotTransferLayoutContentOrStateAndRollsBackInvalidBundle`
13. `testFormattingPackageRecoveryAndSharedRendererCompilerRetainCommittedIntent`
14. `testFormattingComponentInstancesAreNotArbitraryPropertyTargets`
15. `testFormattingCopyCleanGateRejectsPendingIMEWithoutClipboardOrHistoryMutation`

One native journey in `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift`:
`testFormattingReuseNativeAppearanceTextStyleAndAtomicUndoJourney`.
It uses shipping fields/native Edit actions, requests normal-window assertions,
appearance and typography transfers, one-Undo restoration, Redo, repeat neutrality,
stable selected frame and invalid-draft Escape. Named screenshot attachments are
source only; no screenshots were collected or reviewed.

Future acceptance must compile first, execute these focused selectors, then
inspect normal/compact and increased-text Inspector/menu states at original
resolution. Additional live mixed/subset, pending-draft, standard text clipboard,
cancellation and teardown exercises remain required before acceptance; model
source coverage is not a substitute. Mandatory final `./sf verify` is deferred,
not waived. No current pass totals or runtime budgets are claimed.

## Preserved prerequisites and exclusions

007 historical initial focused run passed 3/9; fixture rerun passed 4/6 with two
failed methods. Latest viewport initialization corrections remain unverified.
008 has ten code methods and one native journey UNRUN. Prior ba342938 owns only
the historical 936-pass baseline. Owner revision245, resources/recovery and
OD-018/019 remain untouched. No next prompt, commit, push or installation.

Deferred: cross-project dependency import/retargeting, arbitrary property-family
transfer, component-instance overrides, state-variant transfer, responsive
formatting overrides, missing-resource repair, broad browser/export parity and
release acceptance. No new ADR is needed for reusing the approved private
clipboard, canonical-property registry and existing transaction pipeline.
