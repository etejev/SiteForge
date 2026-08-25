# SF-AUTHORING-013 — Ordered Fill Layers Evidence

Date: 2026-08-25
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
- The Design Inspector exposes an accessible Fill Layers list with Add Solid,
  Add Linear Gradient, enable, reorder, delete, angle,
  add-stop, remove-stop, and stop-position controls. The existing colour well
  and hexadecimal path now compile through the v1 layer registry.
- Each solid layer and gradient stop now has its own native colour control,
  and gradient stops expose accessible Up and Down ordering actions. The
  production tile composites the completed fill stack in a transparency group
  so object opacity is applied exactly once rather than once per source layer.
- Multiple selection is identity-truthful: exact shared stacks expose their
  shared rows and commit through the registry to every compatible object;
  differing stacks show a mixed state without exposing the primary object's
  rows; incompatible objects are counted, announced, and remain unchanged.

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

On 2026-08-25,
`testAuthoredFillLayerStackAndGradientUseExactProductionTilePixels` and its
two neighboring compositor/raster regressions passed 3/3. This proves
disabled-layer neutrality, authored source-over ordering, gradient sampling,
exact object clipping, and group opacity through the production tile.

The retained `schema-v4-legacy-surface.siteforge` package drives
`testHistoricalSurfaceMigratesToOrderedLayersAcrossSaveReopenAndRecovery`.
It proves the first v1 write retires every legacy fill key, then preserves
exact layer and stop identities, authored ordering, colours, normalized angle,
enabled state, and deterministic bytes through save/reopen and owned recovery.
That selector and two adjacent historical/recovery regressions passed 3/3.

`testFillLayerMultipleSelectionDistinguishesSharedMixedAndSkippedStacks`
passed within the complete 331-test unit/integration suite. It covers exact
shared stacks, mixed values, incompatible-object counting, and one real
stable-ID registry edit across two selected Frames.

## Final closure

After macOS Automation Mode was configured to permit XCTest without repeated
authentication, the complete UI target first passed 38/39. Its only failure
was an obsolete expectation that adding a solid layer would replace the
migrated default solid. The assertion was corrected to preserve the product
contract: deleting the temporary gradient leaves one solid, and Add Solid
appends a second distinct solid. The corrected focused journey then passed
1/1.

The retained original-resolution `SF-AUTHORING-013 ordered fill layers`
attachment was reviewed. It shows a normal maximized macOS window, readable
viewport controls, a clear grid and artboard boundary, centered selected Frame
geometry, and two distinct accessible solid-layer rows with appropriate
ordering availability.

Final `./sf verify` passed on 2026-08-25: repository/security/traceability/
architecture/migration/evidence checks, 331 unit/integration tests, and all 39
UI tests (370 total), with zero failures. This closes SF-AUTHORING-013's
bounded solid/linear-gradient slice.

Image fills, blend/filter effects, borders, shadows, tokens, broad
colour-profile behavior, responsive overrides, preview/export parity,
OS-level VoiceOver/settings acceptance, cross-hardware performance budgets,
and release acceptance remain outside this bounded slice; SF-0508 remains
Partial overall.
