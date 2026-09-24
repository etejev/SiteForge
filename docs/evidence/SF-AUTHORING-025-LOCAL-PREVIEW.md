# SF-AUTHORING-025 — Local Preview v1

## Bounded scope

Implements bounded `SF-1201-001`–`008` and `SF-1202-001`–`008` evidence:
an explicit local Preview/Refresh captures an immutable adopted authored
render-plan snapshot. The SwiftUI preview surface contains no authoring
selection, grid, guides or insertion chrome and has no canonical/history write
path. Empty and unavailable snapshots report a bounded recovery message.

## Focused evidence

- `CanvasRendererTests.testLocalPreviewStateFreezesRevisionAndRejectsStaleRefreshes`
  passed, covering revision identity, immutable objects, neutral same-revision
  refresh, unavailable state and close.
- `SiteForgeLaunchTests.testLocalPreviewRefreshesOnlyOnExplicitRequestJourney`
  passed with the retained original-resolution attachment
  `SF-AUTHORING-025 local preview authored snapshot`; it covers real toolbar
  open, authored Frame snapshot, Refresh and focus restoration.
- `SiteForgeLaunchTests.testNarrowDisplayPointerAlignmentPreservesWindowAndRevealsBothEdges`
  passed after correcting target-relative native-window placement for the
  approved 1100-point production window.
- `SiteForgeLaunchTests.testComponentTextPropertiesTwoInstancesResetHistoryAndReopenJourney`
  passed after the same live-target reveal correction, retaining its strict
  enabled/hittable assertion.

## Final local gate

`./sf verify` passed repository checks, 430 unit/integration tests, and 63 UI
tests (493 total, zero failures). The result bundle records the preview and
grid-window attachments; it is intentionally not checked into the repository.
Hosted confirmation for the pending checkpoint remains separate.

## Explicit exclusions

No browser runtime, HTML/CSS/JS generation, routing, remote data/CMS,
publishing, export files, preview/export parity, or SF-1203/SF-1204 behavior
is claimed by this slice.
