# Practical responsive sizing — source-focused checkpoint

Current accumulated acceptance inventory: `SF-LOCAL-BUILDER-005-INTEGRATION.md`.
005 extends the same compiled journey: a user context switch now pauses until
invalid input is cancelled. Results below remain historical 003 code evidence.

## Scope

SF-LOCAL-BUILDER-003 remains IN PROGRESS. Bounded SF-0501-003/005/006,
SF-0502-003/005/006, SF-0505-002/003/004/005/006,
SF-0601-002/003/004/005/006, SF-0602-003/005/006 and SF-0604-003/005/006
remain Partial. Native accessible-operation clauses are source/compile coverage,
not new observed acceptance. Reuse ADR-0025 and the existing canonical sizing,
responsive/fluid resolvers, registries, history and immutable output projection.
No schema, default, cascade, component architecture or resource-store change.

## Concrete source improvements

- Layout groups size modes, numeric geometry and container controls adjacently
  with existing card styling. Bounds/aspect constraints move into a native
  disclosure; existing identifiers and all five Inspector destinations remain.
- The shared sizing resolution reports declared mode, effective mode, numeric
  winner and mode provenance. Inspector labels modes as Base and explains an
  effective Fixed breakpoint/fluid winner instead of concealing it behind Fill.
  Mixed/incompatible state never borrows the primary object's values.
- Exact width/height reset delegates to the existing geometry or fluid registry.
  It removes only the winning source and preserves sibling dimensions, base
  geometry, PropertyIDs and provenance through Undo/Redo. A hidden lower-priority
  fluid value cannot be removed under a winning breakpoint reset by mistake.
- Mode eligibility and conversion share registry policies. Width Hug/Image Hug
  stay unsupported. Confirmation discloses affected/skipped object counts and
  dimension-property removal count; conversion retains its existing single atomic
  command and exact inverse. Desktop/base opt-in remains deliberate.
- Matching geometry, sizing-bound and container numeric editors use scene-local
  drafts. Stable view identity excludes document revision. Unrelated adoption
  preserves valid and incomplete text; temporary absence of a current computed
  number is not a conflicting edit. Canonical and render-plan adoption, plus a
  final event-boundary check, reject changed values or document/page/selection/
  scene/breakpoint/free-width scope. Escape cancels; Return and valid blur use
  the same existing transactions. No per-keystroke canonical writes or new Apply.
- Sizing diagnostics reuse the bounded command diagnostic buffer with sanitized
  identifiers/requirement/category only, not dimensions, content or user paths.

## Shared layout/output defects corrected

Grid track allocation previously overwrote deliberate numeric child widths;
fixed track fitting could also overwrite explicit dimensions. Preserve winning
breakpoint/fluid dimensions while leaving default track behavior unchanged.
The CSS path had two later stretch rules: both now respect the same winner.
The connected Grid regression reached a real failing CSS assertion after its
fixture was corrected, then passed after the remaining override was removed.

Connected CSS is emitted after generic fluid CSS and previously pinned winning
fluid dimensions/gap/padding to sampled preset numbers. It now uses a continuous
expression built from the existing two clamp segments, subtracting their shared
anchor. The same resolver decides whether fluid, a breakpoint literal, or an
authored padding override wins. This is intended projection-rule alignment,
not an actual Safari observation or universal browser parity claim.

## Focused results

**23 unique affected code tests pass**, zero failures/skips. Application and both
test targets compile. Final group:
`focused-7779b049-d5a0-4e69-ac39-9fc47895f287.xcresult`.
Two existing new selectors were then strengthened for height reset and legacy
fixed-Grid dimension preservation and pass 2/2:
`focused-d010efd8-de22-4223-ba93-f5a29639018f.xcresult`.
Those are not two additional unique tests. Result bundles are retained under
ignored `.codex-loop/responsive-workflow-focused/`; execution logs are under
ignored `.codex-loop/component-reuse-focused/responsive-*.log`.
Initial fixture failures were corrected by supplying complete existing Grid/Image
contracts, not weakening validation. Incremental reruns are not additional totals.
Repository/security/hygiene, architecture boundaries, foundation evidence,
tooling checks and 425-record traceability pass; `git diff --check` passes.
No build/test/collector remains active. Final diff review retains prior dirty
work, adds no hidden controls or alternate mutation path, and leaves generated
results in ignored local directories. No new runtime-warning-free UI claim.

Eleven new tests:

`SiteForgeTests/TransformModelTests/`:

- `testSizingDimensionWinnerAndExactResetPreserveOtherOverridesAndHistory`
- `testSizingExactDimensionResetRejectsStaleLockedMixedAndCancelledWithoutMutation`
- `testSizingModeEligibilityAndConversionScopeUseTheSameSupportedSubset`
- `testLayoutNumericDraftRetainsInvalidInputAndRejectsContextChanges`
- `testSizingDiagnosticsRemainBoundedAndExcludeRawObjectIdentity`
- `testHugFlowContainerRejectsFillHeightCycleWithoutChangingCanonicalIntent`

`SiteForgeTests/InsertionModelTests/`:

- `testResponsiveCardSubtreeReflowsAtFreeWidthsWithoutRewritingIntent`
- `testResponsiveGridNumericDimensionWinnerIsNotReplacedByTrackWidth`
- `testSizingInspectorShowsWinningOverrideAndRejectsDraftFromPreviousBreakpoint`
- `testConnectedResponsiveFluidDimensionsAndGapRemainContinuousBetweenPresets`

`SiteForgeTests/PersistedHistoryTests/`:

- `testResponsiveSizingSaveReopenRecoveryPreservesComponentOverridesAndPageIdentity`

The card fixture includes two Sections, Grid, nested card Stacks, wrapped text,
fixed Image/Button intent and breakpoint visibility, at 320/375/390/430/574/768/
1024/1440 widths. It verifies containing widths, intrinsic heights, padding/gap
propagation, child-order independence, immutable prior snapshots and production
render frames without rewriting canonical geometry. Its image metadata is a
generated missing-resource fixture, not a real decoded-image visual acceptance.
Real local package/open/recovery/history checks retain existing component
overrides and website page/route identities.

Twelve existing affected regressions in the 23-test group:

- `testSizingNamespaceRejectsMalformedUnsupportedAndContradictoryProperties`
- `testResponsiveContentConversionIsExplicitAtomicAndRestoresOverridesAndIDs`
- `testSizingModesCommitSeparatelyPreserveFallbackAndExactInverse`
- `testSizingConstraintsSetClampAspectResetAndExactHistory`
- `testSizingConstraintMixedSelectionSkipsTextAndPreservesIdentity`
- `testFluidValueFeedsLayoutTypographyContainerAndSafeStaticOutputWithOverridePrecedence`
- `testResponsiveFillAndHugUseContainingWidthAndPropagateWrappedHeightWithoutMutatingIntent`
- `testHugStackBreakpointOutputResetsFlexBasisAndPreservesButtonLabelAlignment`
- `testConnectedPageFlowSceneRenderSelectionAndHitFramesShareResolvedGeometryAtScale`
- `testIntrinsicSizingAndLiveCanvasUseSameFontAndWrappingBounds`
- `testComponentConnectedReusePropagationResetHistoryAndImmutableOutput`
- `testComponentReuseSaveReopenRecoveryAndExactResetHistory`

## Native, visual, installed and full acceptance pending

Compiled, **not executed**:
`SiteForgeUITests/SiteForgeLaunchTests/testPracticalResponsiveSizingConversionWinnerResetAndDraftJourney`.
It uses real native pane/menu/field controls for opt-in conversion/cancel, Mobile
numeric winner/reset, Undo/Redo, context-switch invalid-draft cancellation and
save/reopen. The existing native bounds journey now expands the real disclosure;
it also needs execution. Screenshot attachment names are planned, not retained
or inspected evidence. No visual/action-count/Safari claim follows from code tests.

OD-025 remains independent. No retry of the closed native pipe or known-hanging
automation route was made. SF-LOCAL-BUILDER-002 stays IN PROGRESS: its 17-test
focused group and compiled new journey do not replace native acceptance. Retain
the component two-instance/recovery journeys and all seven Settings destinations
in the pending inventory. The pre-package 815-test gate is historical, not
verification of these changed sources. No full gate or installed refresh ran.

Owner Aurora packages/resource sidecars, genuine recovery and the regular
installed app were not altered. Current owner saved/modified state is unknown.
All work remains uncommitted; no GitHub, signing or release operation.

## Exact continuation

When native access genuinely returns, run the new responsive journey, native
bounds journey, component reuse/two-instance/conflict recovery journeys and
pending Settings review. Inspect original-resolution captures for readable
cards/tabs, focus, numeric provenance, exact reset, no clipping/ghosts and
maximized windowed presentation. Inspect actual Safari output at matching free
widths; do not accept CSS-string checks as browser proof. Record matched action
counts only when observed. Then one final accumulated changed-tree verification
gate, with no edits under its collector. Installed refresh additionally requires
normal save/quit proof and matching provision/source fingerprint checks.

Width Hug, Image Hug, general circular intrinsic dependencies, automatic legacy
conversion, arbitrary layout/style combinations, supplied slots/retargeting
(OD-018/019), variants, CMS/cloud/publishing and broad output/release parity
remain excluded. No new package begins from this source-only checkpoint.
