# SF-AUTHORING-108 — Canvas focus, isolation, and presentation modes

Verification checkpoint (2026-10-08): repository/build gates and the complete
non-UI target ran; corrected non-UI coverage is green. The actual-app journey
remains unexecuted because XCTest timed out before enabling automation mode.

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**

Requirements: `SF-0409-001`–`SF-0409-008` (bounded source slice).

## Delivered source contract

- One authored `editor.isolation.v1.root` property identifies exactly one
  eligible Frame, Section, Stack, Grid, or Form by stable NodeID. Strict
  validation rejects duplicate, false, leaf, or geometry-free roots.
- `IsolationCommandRegistry` gates document/page/revision/scene/renderer/
  selection identity and moves or removes the marker as one exact-inverse
  batch. Cancellation and stale inputs are neutral.
- Immutable workspace preparation projects only the resolved root subtree into
  rendering, selection, hit testing, Layers, and accessibility.
- The native canvas exposes an isolation breadcrumb and exits. A scene-local
  stack restores valid selection, viewport, and pane context. Focus mode hides
  side/status chrome; Presentation uses immutable read-only Preview without a
  native full-screen Space.
- Focus, presentation, and restoration state are noncanonical.

## Test source added (not executed)

- `SelectionModelTests.testIsolationRegistryMovesSingleCanonicalRootAndUndoRestoresOmission`
- `SelectionModelTests.testIsolationRegistryRejectsCancellationAndStaleIdentityWithoutMutation`
- `CanvasRendererTests.testWorkspacePreparationProjectsOnlyIsolatedCanonicalSubtree`
- `SiteForgeLaunchTests.testCanvasIsolationFocusAndPresentationJourney`

No build, XCTest, UI automation, full verification, commit, push, or hosted
result is claimed under the owner testing pause.

## Deferred scope

Native full-screen ownership, multi-window presentation synchronization,
component-definition isolation changes, comparison panes, remote Preview,
output/export parity, collaboration, broad localization/assistive-technology/
performance matrices, and release acceptance remain deferred. SF-0409 remains
Partial.
