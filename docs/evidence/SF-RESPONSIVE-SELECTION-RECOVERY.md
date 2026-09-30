# Responsive selection across artboard presets — focused recovery

Requirements: bounded `SF-0402-005`, `SF-0601-003`, and `SF-0602-003`.
This is a correction to existing selection/preset behavior, not a new
responsive-authoring milestone or a claim of full module acceptance.

## Failure and first divergence

The direct macOS UI target executed 70 tests: 68 passed and two failed after
Desktop/Tablet → Mobile. The responsive geometry journey failed while waiting
for the selected Frame's inherited Mobile width. The grid/artboard journey
failed while waiting for Frame in `status.selectionPath`. Its retained AX
snapshot reported `Home / No selection`, `0 selected`, even though Mobile was
active and the renderer still reported one object.

`WorkspaceScenePreparer` retained the same canonical node and resolved frame
in the new render scene. The first incorrect boundary was
`SelectionCommandRegistry.adopt`: it classified a target wholly outside the
new artboard clip as invalid and cleared its existing scene-local selection.
Clipping is a paint/hit-test boundary, not a document removal or page change.

## Correction and focused proof

Adoption now retains an otherwise valid selected NodeID across artboard
clipping. A new pointer selection of that fully clipped target remains
rejected; keyboard traversal, accessibility virtualization, raster content,
and selection overlay planning remain bounded to visible geometry. State
validation permits retaining that already-selected ID through subsequent
scene commands without making the clipped node a new canvas hit target.

- `./sf test focused SiteForgeTests/SelectionModelTests/testBreakpointClipRetainsExistingSelectionButRejectsNewCanvasHit`: **1/1 passed**. The test covers Desktop → partially clipped Tablet → fully off-artboard Mobile → Desktop, stable NodeID/primary/provenance, and rejection of a fresh off-artboard pointer selection.
- Three adjacent selection regressions also passed **3/3**: lifecycle repair for actual removal/page/document changes, hidden-at-breakpoint Layers inspection, and off-artboard overlay suppression. The new test additionally checks that Mobile has neither a selection overlay nor a virtualized accessibility object for the clipped Frame.
- `./sf test focused SiteForgeUITests/SiteForgeLaunchTests/testResponsiveBreakpointGeometryAuthoringUndoResetAndAccessibilityJourney SiteForgeUITests/SiteForgeLaunchTests/testWorldGridArtboardHierarchyVisualJourney`: **2/2 passed**, zero failures. Both journeys re-query the live `status.selectionPath` accessibility value and assert one selected primary Frame with truthful Mobile off-artboard status. Responsive width editing/reset and Reveal Selection remain operative.

The successful focused UI result bundle is
`focused-ea2affb4-6c23-4c5d-86a0-3f68a9342a72.xcresult` under the local
SiteForge TestResults root. The prior failing direct UI bundle is
`ui-retry-418B1508-8240-46CA-9571-0B50135FF84B.xcresult`.
Original-resolution retained UI attachments were inspected: `SF-GRID tablet
fitted` shows the partially clipped Frame and badge within the Tablet
artboard; `SF-GRID mobile fitted off-artboard` shows the centered Mobile
artboard, visible surrounding grid, no ghost Frame/handles, and the explicit
outside-artboard status plus Reveal Selection; `SF-GRID reveal selection` and
`SF-GRID fit document` show the same Frame selected and aligned on Desktop.
`SF-AUTHORING-016 Mobile authored override` shows authored X/width and the
selected Frame within Mobile bounds; reset returns to truthful inheritance
without moving the canonical Desktop geometry.

No broad verification was rerun for this focused selection-lifecycle change.
SF-AUTHORING-063 and its interrupted prompt-ten full checkpoint remain open;
the prior 486/486 unit/integration result does not substitute for a fresh
complete gate.
