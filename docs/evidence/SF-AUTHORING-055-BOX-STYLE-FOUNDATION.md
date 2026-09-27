# SF-AUTHORING-055 — Native box-style authoring foundation

## Bounded result

Frame and Section now author uniform content padding and explicit content
clipping through the established native Design Inspector and the sole typed
`style.box.v1` transaction path. `nil` retains default provenance (zero
padding and visible overflow); reset removes the owned property. Explicit
`false` for clipping remains authored so undo, redo, package reopen, and
recovery preserve intent.

The document validator accepts the two new keys only on Frame/Section and
rejects malformed, duplicate, non-finite, or out-of-range values. Resolved
structural child geometry uses Frame/Section padding. The scene-preparation
worker applies a parent content clip to descendants consistently for raster,
selection projection, hit testing, and accessibility. The immutable static
projection maps only the typed values to closed `padding` and `overflow:
hidden` declarations.

## Focused evidence — 2026-09-27

- `TransformModelTests.testDesignBoxStyleContentPaddingAndClipAreTypedReversibleAndScoped` — passed.
  Proves typed set/reset, cancellation, invalid-value neutrality, malformed
  persisted-value protection, exact undo/redo, and serialization.
- `CommandKernelTests.testMultiPageStaticBuildPlanProjectsClosedFrameBoxStyle` — passed.
  Proves deterministic closed static declarations for border, radius, padding,
  and clipping.
- `SiteForgeLaunchTests.testDesignInspectorBorderRadiusShadowUndoRedoAccessibilityJourney` — passed.
  The native Inspector journey now exercises readable/hittable padding and
  clipping controls alongside existing border/radius/shadow controls.

## Requirement coverage

Bounded evidence applies to `SF-0506-001`–`008`, `SF-0701-001`–`005`,
`SF-0702-001`–`005`, `SF-0305-001`–`005`, `SF-0306-001`–`005`,
`SF-0407-003`–`005`, and `SF-1204-003`–`004` only where the shared typed
model, native Inspector, canvas/static projection, history, package, and
accessibility paths are exercised. These normative modules remain Partial.

## Explicit exclusions

Independent or logical sides, margin, per-corner radii, corner smoothing,
layered/inner shadows, arbitrary CSS, browser runtime, export parity, and
release acceptance remain deferred.
