# SF-AUTHORING-012 — Design Inspector solid-fill evidence

## Bounded contract

`CanonicalSolidColor` resolves a solid authored fill from four finite,
normalized `style.fill.red`, `.green`, `.blue`, and `.alpha` numeric canonical
properties.  The display hex value is scene-local input only.  Schema-v4
`style.fill = "surface"` resolves deterministically to the documented v1
neutral surface until a user authors a color; it remains backwards-readable.
`style.opacity` stores a finite normalized value from zero through one.

The native Design inspector offers a color picker, hexadecimal RGBA entry,
remove action, and precise percentage opacity field/stepper.  Each completed
operation creates its own existing-property batch transaction and inverse;
draft/cancel state remains outside canonical documents, history, package,
recovery, preview, and editor overlays.

## Evidence and limits

### Window-owned command-target correction (2026-08-24)

The hosted failure was a state-ownership defect, not a persistence or renderer
timing failure. `WorkspaceWindowTabRouterHostView` previously changed its weak
`WorkspaceShellState` reference without rebinding the existing AppKit window.
The target registry could consequently retain the replaced lifecycle during
native menu tracking, while the visible shell continued to display a newer
document. The host now atomically unbinds the prior state/window pair, assigns
the replacement, binds it to that same window, and updates last-active window
ownership. Stale, hidden, and dismantling window bindings are pruned before
command resolution; a focused-object fallback is allowed only when no live
binding exists.

Focused native UI evidence passed individually and together for
`testDesignInspectorNativeSaveCloseReopenPersistsFillAndOpacityJourney`,
`testGeometryTransformPointerKeyboardNumericUndoRedoAndAccessibilityJourney`,
and `testSupportedElementsShareSelectedRenderGeometryJourney` (3/3). The
complete UI target passed 38/38, and the authoritative local `./sf verify`
passed 323 unit/integration plus 38 UI tests (361 total), all with zero
failures. The full result bundle was retained in the configured local
test-results root and is intentionally not a repository artifact. Hosted CI
remains the external confirmation for this correction.

- Focused registry/migration acceptance passed 3/3 on 2026-08-13:
  `testDesignInspectorRegistryNormalizesValuesAndKeepsNoOpsNeutral`,
  `testDesignInspectorRegistryRejectsAllBoundariesAndReportsMixedApplicableSubset`,
  and
  `testImmutableSchemaFourLegacySurfaceFixtureResolvesAuthorsAndRemovesFillDeterministically`.
  The immutable real-package fixture is
  `Tests/Fixtures/Legacy/schema-v4-legacy-surface.siteforge.b64`.
- Focused production-tile/color and coordinate checks passed 4/4:
  `testAuthoredSolidFillAndOpacityUseExactTilePixelsWithoutEditorOverlayContamination`,
  `testNativeTileFrameNamePixelsStayWithinItsAuthoredFrame`,
  `testFrameAndTextUseOneUprightTopLeftTileConventionAcrossViewportMatrix`,
  and `testSharedTextLayoutKeepsGlyphsInsideOneViewportRectAcrossMatrix`.
  The pixel test covers opaque, 50%-opaque, and transparent authored fills at
  25/100/800% zoom, both backing scales, and positive/negative origins. It
  compares inside/outside pixels against the production tile with an explicit
  device-RGB premultiplication tolerance; editor overlays are not in that
  authored tile subtree.
- The fresh-process native control journey
  `testDesignInspectorSolidFillOpacityKeyboardUndoRedoJourney` passed 1/1.
  Original-resolution screenshots from its result bundle were reviewed at
  `/tmp/siteforge-authoring-012-design-fixed.NUfe6W/` during development:
  `A2D365C3-E2B3-4A45-9420-56667B0089B3.png` (authored fill) and
  `33D75F8A-2EE7-4E23-91DF-0FDA0B9222E7.png` (invalid-draft cancel/undo).
  They show an upright Frame label, contained authored surface, matching blue
  editor-only outline, visible controls, and no ghost preview. These paths
  are local inspection evidence, not repository artifacts.
- `SF-0508-001` through `SF-0508-008` remain Partial overall.  This slice does
  not implement fill stacks, gradients, image fills, borders, shadows,
  blending/filters, typography, tokens, color-management/export parity,
  responsive overrides, or release acceptance.

## In-progress canvas composition correction (2026-08-13)

Owner-provided physical photos exposed two production rendering failures: a
Frame surface could remain at a prior viewport position after a preset/Fit
transition, and a named insertion left an armed dashed preview after its
canonical transaction had committed. The correction keeps canonical geometry
unchanged. `CanvasRenderPlan` carries its immutable viewport snapshot, and
native adoption rebuilds a compositor-only plan whenever that snapshot differs
from the tiles currently displayed. Tiles, overlays, hit testing,
accessibility, and Inspector geometry therefore derive from the same resolved
world-to-viewport rectangle. Named header/menu/accessibility insertion now
deactivates the editor-only insertion session and returns to Select; pointer
placement remains explicitly armed.

Focused results:

- `SiteForgeTests/TransformModelTests/testResolvedGeometryIsSharedAcrossRendererSelectionAccessibilityAndStyles`: 1/1 passed.
- `SiteForgeTests/InsertionModelTests/testEmptyCanvasAvailabilityEnablesHeaderActionBeforeArmingAndAdoptsFrameAndText`: 1/1 passed.
- `SiteForgeUITests/SiteForgeLaunchTests/testWorldGridArtboardHierarchyVisualJourney`: 1/1 passed in a fresh process (34.424 s).

The following original-resolution XCTest attachments were extracted from the
focused result bundle and visually inspected (the local extraction directory
is intentionally not retained in repository evidence):

- `45BEFA34-7941-4569-86E8-B2FB7119F7D9.png` — Desktop, Grid on.
- `9E4A267C-2BCF-4693-8628-04C847296039.png` — Tablet, Grid on.
- `A77CF6B7-03CF-41B6-AAD1-98322B7483C1.png` — Mobile, Grid on.
- `9B778E93-554A-42FC-BEE5-9EF00C490F42.png` — Grid off.
- `A94FA818-068B-41EA-9346-BF35022F9B09.png` — Grid restored, positive pan/zoom.
- `AEB0E40B-CA42-44B2-A8C1-533A72ED52AA.png` — Desktop Fit Document.

Visual review found one authored Frame, its pale/dark surface fully enclosed by
the blue editor-only outline, no dashed post-insertion preview, labeled
viewport/zoom controls, grid behind the artboard at Tablet/Mobile and Fit
views, and a clear page boundary in the Fit view. Grid-off removed marks only.
This is focused visual evidence. The later native-control and lifecycle
acceptance is recorded below; the remaining completion gate is the
documentation-inclusive `./sf verify`.

## Artboard-fit and clipping correction (2026-08-21)

The focused visual journey was rerun after two production corrections. Native
canvas adoption now withholds a mismatched raster generation rather than
transforming it into a newer viewport. Separately, transform outlines and
handles use the same active-artboard intersection as authored pixels and the
selection overlay. A node outside a narrower preset retains its canonical ID
and Desktop geometry, but it does not paint or leave selection/transform
chrome on pasteboard; the UI truthfully reports the state and offers Reveal
Selection. Preset changes use Fit Document with a 48-point surrounding gutter
instead of presenting the artboard at an initial 100% fill.

Focused results:

- `SelectionModelTests/testOffArtboardSelectionRetainsIdentityAndSuppressesGhostOverlay`: 1/1 passed.
- `SelectionModelTests/testPartialArtboardClipLimitsTransformChromeToVisibleAuthoredGeometry`: 1/1 passed.
- `TransformModelTests`: 22/22 passed.
- `SiteForgeLaunchTests/testWorldGridArtboardHierarchyVisualJourney`: 1/1 passed in a fresh process (42.407 s). Its result log contained no `Publishing changes from within view updates` or invalid-negative-geometry diagnostic.

Original-resolution attachments were exported locally from
`focused-82d45701-a69e-4c67-a6c4-40d2381dd29d.xcresult` for inspection:

- `/tmp/siteforge-grid-final-proof.H166tP/615F9E36-EBFF-4A8B-BFC1-024FF59B43A5.png` — Desktop fitted/Grid on.
- `/tmp/siteforge-grid-final-proof.H166tP/03A73918-2F55-4F57-A271-C0E6168B7B1D.png` — Tablet fitted with the selected Frame clipped to the artboard.
- `/tmp/siteforge-grid-final-proof.H166tP/35A026E2-A984-4664-BF06-E11B4915F19C.png` — Mobile off-artboard selection status and Reveal Selection.
- `/tmp/siteforge-grid-final-proof.H166tP/79DABCB7-6DF9-4785-92B2-568754C33A18.png` — Reveal Selection.
- `/tmp/siteforge-grid-final-proof.H166tP/5315337E-D8C9-4392-8C7C-EC36B9CC9F11.png` — Grid off.
- `/tmp/siteforge-grid-final-proof.H166tP/A87F2F40-62B4-4089-8AB7-3CF4A001ADB4.png` — Grid on after pan/zoom.
- `/tmp/siteforge-grid-final-proof.H166tP/512C9AB6-956E-4419-B412-CDC1D6F2B742.png` — Fit Document.

Visual review: the Desktop/Tablet/Mobile artboard boundary, surrounding
pasteboard/grid, authored Frame, and editor-only selection are distinguishable;
Grid Off removes only grid marks. The Frame surface and outline coincide at
Desktop/Fit, Tablet exposes only the painted in-artboard intersection, and the
Mobile state has no authored or editor ghost outside its artboard.

## Selection chrome boundary correction (2026-08-21)

Selection context badges now use the actual native monospaced-font measurement
rather than a character-width estimate. The resulting badge is repositioned
inside the active artboard intersection and clips its own glyph layer as a
defensive boundary. The complete context remains exposed through the shipping
accessibility label/help even if a future narrow artboard requires compact text.
Frame names now choose a contrasting editor-only foreground for their resolved
surface. Canonical NodeID and geometry are unchanged.

Focused results:

- `CanvasViewportTests/testSelectionBadgePlacementRemainsInsideAllArtboardEdges`
- `CanvasViewportTests/testSelectionBadgePlacementUsesCompactFallbackAndSuppressesOffArtboard`
- `SelectionModelTests/testOffArtboardSelectionRetainsIdentityAndSuppressesGhostOverlay`
- `SelectionModelTests/testPartialArtboardClipLimitsTransformChromeToVisibleAuthoredGeometry`

ran 4/4 passing. `SiteForgeLaunchTests/testWorldGridArtboardHierarchyVisualJourney`
ran 1/1 passing. The test asserts that the actual Tablet selection context is
accessible and does not exceed the clipped Frame's pasteboard-facing edge.

Original-resolution visual review:

- `/tmp/siteforge-grid-badge-reviewed.nHaQCZ/3E38F666-EB3B-446C-A0A4-DD875C582EA7.png` — Desktop fitted/Grid on.
- `/tmp/siteforge-grid-badge-reviewed.nHaQCZ/D9CEE6EE-44F8-41C7-8EBB-51E248E02401.png` — Tablet fitted; partial Frame and context badge remain inside the artboard.
- `/tmp/siteforge-grid-badge-reviewed.nHaQCZ/CE7E2551-751A-417A-89E1-279044414A4D.png` — Mobile off-artboard selection with no content or chrome ghost.
- `/tmp/siteforge-grid-badge-reviewed.nHaQCZ/639D90FA-7204-4C59-919C-DEAEEF9A48BB.png` — Reveal Selection restores Desktop presentation without moving the node.
- `/tmp/siteforge-grid-badge-reviewed.nHaQCZ/7EC9E076-071D-429A-B1DB-B7058025C64B.png` — Grid off.
- `/tmp/siteforge-grid-badge-reviewed.nHaQCZ/6D0FD250-0A89-466D-87C4-B3C0B558D782.png` — Grid on after pan/zoom.
- `/tmp/siteforge-grid-badge-reviewed.nHaQCZ/AE0F8824-19B4-4F0E-8065-A56A76460CDA.png` — Fit Document.

Visual review passed: badge, handles, authored surface, and label are legible
and artboard-contained; Grid Off changes only the grid; Mobile retains the
truthful off-artboard state without an editor ghost.

## Native-control automation resolution (2026-08-21)

The shipping `NativeDesignColorWell` and `NativeDesignOpacityStepper` AppKit
bridges retain the real `NSColorWell`/standard macOS Colors panel and
`NSStepper` controls, while exposing truthful labels, values, enabled state,
and help through their normal accessibility surfaces. They feed the same
scene-local draft and `DesignInspectorCommandRegistry` commit boundary as the
hexadecimal and percentage fields; no test-only control or direct model path
exists.

`testDesignInspectorSolidFillOpacityKeyboardUndoRedoJourney` drives a visible
Colors-panel slider through the native element's own frame, closes a no-change
panel history-neutrally, drives the visible upper/lower NSStepper affordances,
proves zero/100 boundaries are neutral, and covers Return, focus-loss, Escape,
validation, and Undo/Redo. `testDesignInspectorMixedAndInapplicableSelectionJourney`
proves a real Frame+Text Layers selection edits only the applicable structural
node and reports its skipped incompatible node; Text-only selection disables
the controls truthfully. `testDesignInspectorNativeSaveCloseReopenPersistsFillAndOpacityJourney`
opens the immutable schema-v4 package, preserves its geometry-less legacy
member as unrelated data, inserts one real visible Frame through the public
empty-canvas action, saves, terminates, reopens with a fresh recovery directory,
and proves the live renderer, Layers, Inspector, selection, and persisted
RGBA/opacity agree.

Focused native-control/save results passed 2/2; the documentation-sensitive
`./sf test changed` run passed 323 unit/integration and 38 UI tests, zero
failures, on 2026-08-21. Original-resolution saved and reopened evidence from
that fresh process was visually inspected: the authored surface remains inside
its editor-only selection outline, labels and controls are readable, the page,
grid, and pasteboard remain distinguishable, and no insertion ghost returns.

## Focused-test harness correction (2026-08-20)

`sf` now probes process-enumeration capability once per test invocation. On a
normal host it retains its existing narrow repository-derived-data stale-PID
cleanup and post-run orphan assertion. When a managed runtime denies `ps`, it
emits one warning and continues into `xcodebuild`; fixture cleanup and its EXIT
trap remain active. `scripts/test-sf-test-harness.sh` passed, covering the
enumeration-success path, permission-denied fallback, fixture lifecycle, and
unchanged propagation of a failing xcodebuild status.

The exact focused mixed-selection journey was then retried. XCTest could not
start because this managed runtime denies the `com.apple.testmanagerd.control`
connection with error 159 (Sandbox restriction), before the SiteForge test
body/application launched. This is distinct from the repaired `ps` issue. No
UI acceptance, screenshots, or persistence claims were advanced from that
failed launch.

## Completion verification (2026-08-21)

The later native-XCTest journey and the final deterministic command path
supersede the earlier managed-host limitation above. The complete native
control, mixed-selection, and save/reopen evidence was visually reviewed at
original resolution. The final documentation-inclusive `./sf verify` passed
all repository, security, traceability, architecture, migration, evidence,
and fixture-hygiene checks; 323 unit/integration tests and 38 actual macOS UI
tests passed with zero failures (361 total).

The screenshot review found a normal maximized visible-frame window with menu
bar and Dock available; readable Inspector controls and navigator labels;
upright text; an authored surface inside the matching editor-only selection
outline; a real standard Colors panel; and a saved/reopened visible Frame with
the same persisted RGBA/opacity. Grid/pasteboard/artboard evidence remained
clear at the desktop, tablet, mobile, pan/zoom, Fit, and off-artboard states.
No screenshot was used as a replacement for geometry, pixel, history, or
package assertions.

SF-AUTHORING-012 is complete only for the bounded solid-fill/opacity contract.
SF-0508 remains Partial: fill layers, gradients, images, borders, shadows,
blending/filtering, typography, tokens, broad color-management, responsive
overrides, preview/export parity, release acceptance, OS-level settings
exercise, and style-editing performance budgets remain future work.
