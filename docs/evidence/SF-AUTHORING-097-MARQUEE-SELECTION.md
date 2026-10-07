# SF-AUTHORING-097 — Directional canvas marquee selection

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**

Requirements: bounded `SF-0402-002`, `SF-0402-003`, `SF-0402-004`,
`SF-0402-006`, and `SF-0402-008`. The normative module remains Partial.

## Implemented contract

- Blank-canvas pointer-down creates a scene-owned draft tied to the exact
  document/revision/scene/renderer identity already used by selection.
- Left-to-right drags select only visible clipped frames fully contained by the
  marquee. Right-to-left drags select every visible clipped frame intersecting
  it. Results retain deterministic paint order.
- Shift adds and Command toggles through `SelectionCommandRegistry`; no second
  selection state or direct document mutation exists.
- The live accent rectangle and candidate count are editor presentation only.
  They are not canonical, undoable, serialized, recoverable, rendered into
  authored tiles, or exposed to Preview/static output.
- Escape, cancellation, invalid geometry, or stale scene identity retain the
  last valid selection. A successful commit continues through the existing
  canvas overlay, Layers, Inspector, status, and accessibility projections.

## Added source evidence

- `SelectionModelTests.testMarqueeSelectionUsesDirectionalContainmentClippingAndPaintOrder`
- `SelectionModelTests.testMarqueeSelectionModifiersAndRejectedGesturesAreStateNeutral`
- `SiteForgeLaunchTests.testCanvasMarqueeDirectionalMultiSelectionJourney`

These selectors have not run under the current owner pause. No visual pass,
performance measurement, full verification, commit, or hosted result is
claimed.

## Explicit exclusions

Freeform lasso shapes, touch gestures, component-instance drill-in, canonical
selection persistence, cross-container selection, release-scale performance,
and OS-level VoiceOver/Full Keyboard Access acceptance remain deferred.
