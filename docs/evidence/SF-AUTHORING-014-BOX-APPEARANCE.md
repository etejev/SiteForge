# SF-AUTHORING-014 Box Appearance Evidence

## Scope

This bounded slice implements uniform border colour/width/style, uniform
corner radius, and one drop shadow for Frame, Section, Stack, and Grid through
the existing canonical property, transaction, renderer, history, and package
boundaries. It supplies partial evidence for SF-0506-001 through SF-0506-008.

## Contract

- `style.box.v1.*` is the only authored representation for this slice.
- Inspector drafts are scene-local. Return or focus loss commits one operation;
  Escape and invalid input preserve the last committed document.
- Paint order is exterior shadow, radius-clipped fill stack, then authored
  border. Object opacity remains owned by the existing authored fill stack.
- Shadow pixels enlarge raster tile adoption and dirty regions only. Selection,
  hit testing, Inspector, and accessibility retain the exact authored frame.
- Editor selection, focus, grid, handles, and badges are never serialized or
  painted into authored tiles.

## Focused evidence

- `TransformModelTests/testDesignBoxStyleRegistryCommitsValidatesMixesPersistsAndUndoRedo`
- `CanvasTextRenderingTests/testBorderRadiusAndShadowUseProductionTileCompositionWithoutGeometryDrift`
- `CanvasRendererTests/testAuthoredShadowExpandsRasterTilesAndDirtyRegionsWithoutExpandingInteractionGeometry`
- `ProjectPackageTests/testBoxAppearancePersistsAcrossPackageReopenAndOwnedRecovery`
- `SiteForgeLaunchTests/testDesignInspectorBorderRadiusShadowUndoRedoAccessibilityJourney`
- `SiteForgeLaunchTests/testDesignInspectorBoxAppearanceControlsRemainReachableAtPracticalMinimum`

These selectors cover identity validation, mixed/applicable subsets, invalid
and cancelled neutrality, one-command exact inverse, serializer round trip,
production pixel composition, shadow tile boundaries, semantic geometry
isolation, accessible native controls, practical-minimum Inspector layout, and
real Undo/Redo. The focused selectors passed 7/7. Final `./sf verify` passed 360
unit/integration plus 43 actual-app UI tests (403 total), zero failures, on
2026-08-26, with repository, security, traceability, architecture, migration,
evidence, and fixture-hygiene gates green.

Original-resolution XCTest attachments named `SF-AUTHORING-014 unstyled`,
`SF-AUTHORING-014 border radius`, `SF-AUTHORING-014 shadow`,
`SF-AUTHORING-014 undo redo`, and `SF-AUTHORING-014 practical minimum` were
reviewed. They show a normal maximized workspace, readable and unclipped native
controls, aligned authored/selection geometry, visible radius/border/shadow,
and no ghost, fixture, or debug content.

Hosted Actions `32931557907` and `32933185609` passed all repository/unit gates
and 42/43 UI journeys. The latter retained exact frame and screenshot evidence:
the supported 1100-point compact window was left-aligned on the 1024-point
hosted screen, while the Inspector's trailing Add control occupied x=1041…1090.
Vertical scrolling therefore could not make the real pointer target hittable.
The explicitly named compact journey now requests the established right-edge
test placement, re-queries the shipping control, and derives vertical scrolling
from its live frame. Production and generic test-window behavior are unchanged.
Actions `32934689112` passed the complete 360 unit/integration plus 43 UI test
gate (403 total) at `65571dc`, closing hosted acceptance.

## Explicit limitations

Margin and padding authoring, independent/logical border edges, per-corner
radii, ordered or inner shadows, clipping controls, corner smoothing,
responsive overrides, preview/export parity, OS-level VoiceOver/settings
acceptance, cross-hardware performance budgets, and release acceptance remain
deferred. SF-0506 therefore remains Partial overall.
