# SF-AUTHORING-013 — Ordered Fill Layers Checkpoint

Date: 2026-08-24  
Requirements: bounded continuation of `SF-0508-001` through `SF-0508-008`.

## Achieved behavior

- `style.fill.layers.v1` is the canonical ordered fill representation for
  Frame, Section, Stack, and Grid once a style edit occurs. Its stable layer
  and gradient-stop IDs, enabled state, kind, ordered stops, normalized RGBA,
  positions, and angle travel in one atomic document transaction.
- Legacy schema-v4 solid properties are read only as a deterministic first
  resolution and are retired atomically when the v1 layer set is written.
- Renderer preparation captures immutable v1 layers; native tile drawing
  composites enabled solid/linear-gradient layers in authored order, clips to
  the authored object rect, and applies object opacity once. Selection, grid,
  handles, badges, accessibility geometry, and preview/editor chrome are not
  fill layers and are not included in preview snapshots.
- The Design Inspector exposes a single-selection, accessible Fill Layers
  list with Add Solid, Add Linear Gradient, enable, reorder, delete, angle,
  add-stop, remove-stop, and stop-position controls. The existing colour well
  and hexadecimal path now compile through the v1 layer registry.

## Focused results

All selectors below passed individually on macOS on 2026-08-24 (6 tests, zero
failures):

1. `SiteForgeTests/TransformModelTests/testCanonicalFillLayerFoundationValidatesStableOrderAndGradientDefaults`
2. `SiteForgeTests/TransformModelTests/testDesignFillLayerRegistryCommitsOrderedLayersWithExactHistoryAndPersistence`
3. `SiteForgeTests/TransformModelTests/testDesignFillLayerRegistryRejectsInvalidStaleCancelAndAllInapplicableEdits`
4. `SiteForgeTests/CanvasRendererTests/testAuthoredFillLayerCompositorPreservesOrderDisabledLayersStopsAnglesAndOpacity`
5. `SiteForgeTests/CanvasRendererTests/testFillLayersAreImmutablePlanDataAndExcludeEditorOverlays`
6. `SiteForgeUITests/SiteForgeLaunchTests/testDesignInspectorOrderedFillLayersAccessibilityJourney`

The UI journey retained the named XCTest attachment `SF-AUTHORING-013 ordered
fill layers`; it exercised the visible Design Inspector list, adding a linear
gradient, committing a 90-degree angle, toggling the layer, and deleting that
same layer by its stable accessibility identifier.

## Deliberately unfinished

This is a checkpoint, not SF-AUTHORING-013 completion. Individual layer and
gradient-stop native colour editing, full multi-selection presentation,
gradient-stop reordering UI, exact raster pixel matrices, historical package
fixtures for v1 layers, recovery coverage, full UI/verification gates, and
visual evidence review remain. Image fills, blend/filter effects, borders,
shadows, tokens, broad colour-profile behavior, responsive overrides,
preview/export parity, and release acceptance remain outside this bounded
slice.
