# SF-PRODUCT-UI-003 Inspector navigation evidence

## Scope

This bounded product-UI slice establishes stable, scene-local Inspector tabs in
the order Design, Layout, Content, Interactions, and Accessibility. Design,
Layout, and Accessibility retain truthful read-only or previously verified
bounded controls. Content and Interactions are selectable native unavailable
surfaces: they state a specific reason and next step but expose no simulated
editor, interaction data, command, history, or persistence mutation. Fresh
Frames render an authored neutral surface/border/name; only the blue outline
and Frame/dimension/parent context are editor overlays.

## Reproducible review

Run from the repository root:

```sh
./sf test changed
./sf verify
```

Final local completion gate: `./sf verify` passed on 2026-08-12 with 297 unit
tests and 32 UI tests (329 total), zero failures. Repository, secret,
traceability, architecture, migration, retained-evidence, and fixture-hygiene
checks passed in that same gate.

`SiteForgeLaunchTests.testInspectorProvidesTruthfulUnavailableContentAndInteractionsDestinations`
captures Xcode-result attachments for Design, Layout, Content, Interactions,
and Accessibility using deterministic right-edge test placement.
`testInsertedFrameHasVisibleAuthoredSurfaceAndSeparateSelectionContext` retains
a selected Frame screenshot and exercises undo/redo. The existing selection
and transform journeys retain empty, single, multiple, and locked inspection
variants. Existing material journeys cover light/dark, Reduce Transparency,
increased contrast, and constrained-display composition. Normal visible-frame window policy
tests use an isolated preference suite; UI-test composition deliberately stays
constrained instead of changing the runner's display.

`testBlankProjectHasAnEmptyCanvasAndExplicitStartingActions` retains the normal
blank-project state: no authored/debug/sample rectangle is fabricated and the
only starting actions are the visible named Frame and Text controls.
`testViewportCommandsAreKeyboardAndAccessibilityOperable` exercises the real
Desktop/Tablet/Mobile preset, zoom out/value/in, Actual Size, Fit to Canvas,
and Fit to Document controls. The evidence is Xcode-result attachments from
these named actual-app journeys, not files provisioned into a Release project.

## Assertions and limitations

- `AppMetadataTests.testInspectorNavigationIsOrderedTruthfulAndNoncanonical`
  proves exact tab order, availability/reason contracts, and canonical/history
  neutrality.
- `SiteForgeLaunchTests.testKeyboardFocusTraversesWorkspaceForwardAndReverse`
  proves scene-local forward/reverse focus through all five tabs.
- `CanvasRendererTests.testExplicitBlankSceneAdoptsWithoutFabricatingRenderableObjects`
  proves that a structural blank root does not become a canvas object or hit
  target; `CanvasTextRenderingTests.testFrameAndTextUseOneUprightTopLeftTileConventionAcrossViewportMatrix`
  verifies the shared top-left convention at 25%, 100%, and 800% zoom, both
  pan directions, and 1×/2× backing scale.
- `InsertionModelTests.testFrameSurfaceDefaultsSurviveUndoRedoAndDeterministicRoundTripWithoutSelectionMetadata`
  proves deterministic canonical Frame defaults and nonserialization of
  selection metadata.
- `InsertionModelTests.testEmptyCanvasAvailabilityEnablesHeaderActionBeforeArmingAndAdoptsFrameAndText`
  deterministically traces the real named starting-action path: current
  availability, one revision-changing insertion transaction, matching
  render-plan revision and NodeID, Layers/selection adoption, redacted
  insertion diagnostic, and exact undo/redo for both Frame and Text.
- `SiteForgeLaunchTests.testWorkspaceChromeUsesNativeMaterialWithoutInterceptingCanvasInput`
  proves a normal blank project first exposes an empty Layers state and then
  creates a real rendered Frame through the visible named header action.
- `WorkspaceMaterialPolicyTests.testNormalWindowPresentationUsesUsableScreenAndSafelyRetainsRestoration`,
  `testNormalWindowPresentationRejectsUndersizedAndMalformedRestoration`, and
  `testReleaseCompositionIgnoresEveryWindowPlacementArgument` prove normal
  `NSScreen.visibleFrame` placement, safe restoration fallback, and Debug/UI-test
  window-composition isolation.
- The unavailable-state journey proves real identifiers, labels, reasons,
  selection, and absence of Layout transform controls on the Content surface.

This does not claim property editing, interaction authoring, responsive
controls, gradients/effects, OS-level VoiceOver/settings acceptance, export,
publishing, or release acceptance. The retained screenshots are Xcode-result
attachments from the named actual-app journeys; they do not claim manual
VoiceOver speech validation.
# Canvas coordinate correction

The retained focused UI attachment from the upright Frame journey verifies that
the authored `Frame` name is upright inside the Frame surface, independently
of the upright editor-only selection context chip. `CanvasTextRenderingTests`
also exercise the tile boundary at 25%, 100%, and 800% zoom with positive and
negative pan origins and 1×/2× backing-scale inputs. The canonical convention
is top-left origin with Y increasing down; `CanvasContentTileLayer` is the
sole AppKit/Core Graphics conversion boundary. This evidence does not claim
production typography, final export rendering, or hardware frame pacing.
