# SF-AUTHORING-058 — Native sizing constraints foundation v1

Bounded evidence for SF-0505-001–008 (Partial), with existing fixed geometry,
renderer, and closed static-output integration. Development Prompt 5 of 10;
the reset policy reserves full verification and hosted CI for Prompt 10.

## Delivered

- `layout.sizing.v1.*` is the one base-only typed property namespace for
  Frame/Image min/max width/height, aspect ratio and aspect lock. Omission means
  unconstrained; authored properties retain stable PropertyIDs and origins.
  Document validation rejects unknown, duplicate, malformed, nonfinite,
  contradictory, and unsupported-kind sizing data.
- The identity-gated sizing registry commits one existing-property batch with
  an exact inverse. The same clamp policy governs Desktop numeric width/height
  and pointer resize. A ratio lock derives the current frame ratio when first
  enabled; explicit ratio edits remain bounded from 0.01 to 100. Reset removes
  the sizing properties rather than writing equivalent literals. Mixed
  Frame/Text selection edits only the Frame and names the skipped subset.
- Native Layout Inspector fields keep incomplete drafts scene-local; Return
  and focus loss commit, Escape discards, and controls announce authored,
  defaulted, mixed, unavailable, or invalid state. Closed static output emits
  only validated min/max and aspect declarations from the immutable typed tree.

## Focused results

All four exact new selectors passed locally on 2026-09-27:

1. `TransformModelTests.testSizingNamespaceRejectsMalformedUnsupportedAndContradictoryProperties`
2. `TransformModelTests.testSizingConstraintsSetClampAspectResetAndExactHistory`
3. `TransformModelTests.testSizingConstraintMixedSelectionSkipsTextAndPreservesIdentity`
4. `CommandKernelTests.testClosedStaticSizingProjectsOnlyValidatedFrameAndImageConstraints`

`SiteForgeLaunchTests.testNativeSizingConstraintsClampResetAndAccessibilityJourney`
also passed (one focused actual-app journey; five exact new selectors total).
The journey retained three original-resolution window captures in its
focused result bundle, named `SF-AUTHORING-058 minimum width authored`,
`SF-AUTHORING-058 aspect locked`, and `SF-AUTHORING-058 reset`. The extracted
images were reviewed at original resolution. The normal window, readable Layout controls,
upright Frame label, selected surface/bounds alignment, page/grid separation,
and absence of ghost objects were visible in all three.

No `./sf verify`, complete UI suite, push, or hosted gate was run in this
prompt. This is a focused local checkpoint, not full SF-0505 acceptance.

## Deferred

Responsive constraint overrides, automatic/intrinsic/hug/fill/percentage
sizing, container constraints, complete size-mode semantics, stress-scale and
broad VoiceOver/localization matrices, dedicated diagnostic retention,
actual-app save/reopen/recovery, browser runtime, and release acceptance.
