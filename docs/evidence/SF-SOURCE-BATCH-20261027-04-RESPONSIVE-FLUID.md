# SF-SOURCE-BATCH-20261027-04 — Responsive visibility and fluid styling

Current receipt: the listed new model methods and actual-app journey have passed
current-source affected acceptance. Final full verification passes:785 non-UI,
151 UI,0 failures,3 intentional owner-session skips; full-e7ee511e is the
authoritative939-method result. The bounded local slice is accepted.
The implementation-time UNRUN/owner-hold text below is historical and superseded
by approved local acceptance. Exact correction results and inspected screenshots
are indexed in [the integration receipt](SF-SOURCE-BATCH-20261027-10-INTEGRATION.md).
Normative modules remain Partial; no push or installation is authorized.

**IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.**

Queue IN PROGRESS. All relevant modules remain Partial. Static source/diff
inspection only: no tests, builds/build-for-testing, check/lint scripts, UI
automation, readiness, app/browser acceptance launches or visual review. No new
screenshot/result bundle exists; prior partial passes do not cover this source.

## Bounded contracts / preserved implementation

- SF-0602-003/006: explain the current winning numeric/fluid source and provide
  native access to its existing editing surface.
- SF-0603-002/003/005/006: captured visibility event ownership; preserve existing
  base/device cascade, hidden descendant exclusion, Layers inspection, history.
- SF-0604-002/003/005/006: usable single/mixed range drafts, strict context,
  effective projection, explicit removal, neutral cancellation and native input.
- Supporting SF-0507-003/006: effective rendered typography readout and navigation
  to existing fluid font-size/line-height controls, not new typography semantics.

ADR-0020/0025 remain governing. Existing stable Desktop/Tablet/Mobile identities,
supplied-width resolver inputs, responsive geometry/container overrides and reset, fluid clamp
anchors/curve, visibility cascade, width-first/Hug layout, shared text metrics and
immutable renderer/static compiler were inspected and preserved. Content-responsive
conversion retains its existing explicit confirmation and exact inverse; no
project is converted or rewritten merely by changing a preset.
The inspected native preset selector contains three presets, not a custom-width
authoring control. Arbitrary/intermediate widths are exercised in unrun resolver/
worker source matrices; this slice does not claim a new custom-width UI.

## Concrete findings and source changes

### Identity and noncanonical draft lifecycle

`SiteForge/TransformModel.swift` adds scene-only
`ResponsiveInspectorEditContext`: existing LayoutInspectorDraftScope plus opening
revision. It contains no canonical property or serialized preference.

`SiteForge/WorkspaceShellModel.swift` checks that captured context and current
renderer adoption before forwarding fluid/visibility UI actions to the existing
typed registries. Previously those callbacks created fresh identity at execution,
which could accept an old UI action against a different current context. A stale
action now returns bounded useful status without a canonical command/mutation.
Existing registry validation/diagnostics still own issued transactions.

`SiteForge/WorkspaceShellView.swift` captures context when a fluid draft starts
or a native visibility control is constructed. Delayed focus-loss work checks the
same target, context and draft strings before attempting commit. Apply/Remove/
visibility/reset routes use the guarded existing state entry points. Escape
clears the local draft and cannot trigger a queued replacement commit. Blank and
invalid drafts remain editable; context changes require cancellation/review, not
silent retargeting. No blanket dispatch, test detection or direct property write.

### Fluid target and mixed-value usability

The fluid card previously used a revision-bearing view identity; every successful
commit could recreate it and reset its property picker to Width. It now retains
identity across revision/preset updates for the same document/page/scene/selection,
while captured revision guards retained drafts. Selection/page replacement still
creates a new local editor. Prompt-3 native scroll navigation uses that same ID.

Make Fluid was disabled when selected fixed values differed, and mixed-range
fields could lack a draft context. Mixed fallbacks now open blank native fields
with explicit guidance; the user supplies all three numbers. No primary number
is borrowed or canonical value silently coerced. Common fixed values retain the
existing reversible seed, bounded to the target's accepted upper range.

Fluid Inspector range equality previously compared stable IDs, so equivalent
per-object ranges could falsely appear Mixed. Presentation now compares the
three numbers, curve and origin only. Registry mutations still retain distinct
FluidValueIDs/PropertyIDs and use one atomic transaction with exact inverses.
Different ranges/provenance remain Mixed. This is not an ID or schema migration.

### Effective values / typography / visibility

`FluidValueCommandRegistry.effectiveValue` projects existing geometry/container/
typography resolvers; it does not implement another cascade. It validates the
inspection width and target, and returns the effective value plus source.
Workspace readouts distinguish a device override, fluid value, fixed Desktop
fallback or mixed values/sources, including applicable/skipped counts. Geometry
source inspection now supplies viewport width too. Fluid removal still removes
only its record: device overrides and fixed fallback are preserved. Feedback no
longer unconditionally promises that fixed geometry becomes active. Fluid
feedback is scoped to current context/property rather than leaking another
selection/property's result.

Typography retains explicitly labeled fixed fallback controls. An effective
readout uses the same resolved family/size/line-height path as rendering at the
current width; compatible/mixed selections remain truthful. A native Fluid
Typography in Layout button uses the existing context-transition command and
property picker. It does not create responsive typography overrides or remove
fluid intent via a fixed edit. Native visibility controls retain existing reset
and Layers recovery semantics; hidden content is never represented by a ghost.

Existing renderer, inline text metrics and shared output emission are reused,
not rewritten. Fluid typography follows fixed CSS through the production emitter;
explicit geometry/container overrides retain their established precedence. No
owner export or generated website was patched.

## New acceptance source — six methods, all UNRUN

1. `TransformModelTests/testEffectiveFluidTypographyAndGeometryResolveAtBreakpointBoundaries`
2. `TransformModelTests/testFluidTypographyInvalidStaleAndCancelledRangesPreserveCanonicalIntent`
3. `InsertionModelTests/testResponsiveInspectorCapturedContextRejectsSelectionPageRevisionAndBreakpointRetargeting`
4. `InsertionModelTests/testHiddenResponsiveFluidTextKeepsRendererOutputAndLayoutParticipationConsistent`
5. `SiteForgeLaunchTests/testFluidTypographyScopeEffectiveValuesVisibilityResetAndCancelJourney`
6. `SiteForgeLaunchTests/testMixedFluidFallbacksAcceptExplicitRangeWithoutBorrowingPrimaryValuesJourney`

Intended coverage: 320/390/599/600/767/768/1023/1024/1440 widths, continuous type
metrics and device override winners, invalid inspection widths and range bounds,
common/mixed/partial presentation, separate per-object fluid identity, atomic
history, exact Undo/Redo, strict serializer reopen and unchanged authored fallback.
Captured UI tests exercise breakpoint, selection, revision, page and document
replacement without mutation. Hidden connected flow excludes descendants from
native authored render objects/layout participation while retaining data/resources;
surviving text metrics/frames and the production compiler stylesheet agree with
the canonical ranges. Visibility reset removes only the current override.

Future native journeys use real menus, fields, property picker, preset and
visibility controls; assert current metrics and retained target, invalid/Escape,
no hidden ghost, Layers recovery, mixed blank-range entry and Undo/Redo. Named
Desktop/Design/Mobile/mixed screenshot attachments are source instructions only,
not captured or visually accepted evidence. After separate approval, use these
exact selectors plus the directly affected existing
`testFluidResponsiveValueAuthoringPreviewResetAndAccessibilityJourney` and
`testResponsiveContainerLayoutAndBreakpointVisibilityJourney`. These names were
confirmed by static source inspection; no selector has been executed.

## Limits / next acceptance boundary

No responsive content-swap/source-set model exists in this bounded workflow;
visibility remains the supported adaptive-content mechanism. No custom breakpoint
management, fluid typography token binding, responsive fills, wrapping/distribution,
new track model or schema was added. Full normative coverage, scale, native visual
conformity, output/browser parity, runtime health and release acceptance remain
unproven. Editor 01/05 compact controls/cards/scrolling are reused; Settings12
does not become a competing Inspector layout.

OD-018/019 and remote/security/legal/Apple decisions remain unchanged. Owner
packages, the approved Dark Flow gradient, resources, recovery and retained
evidence are untouched. No credentials, cleanup, signing, install, commit, push,
GitHub/external mutation or scheduled follow-up. The deleted schedule remains
deleted. Required owner-approved focused/visual/full verification is deferred,
not waived; no completion or green gate is claimed.
