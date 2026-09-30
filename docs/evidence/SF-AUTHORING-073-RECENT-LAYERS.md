# SF-AUTHORING-073 — Quick Open recent Layers

## Implemented bounded behavior

Under bounded `SF-0205-003/004/006/008`, successful Layers selection records
a stable NodeID in an eight-entry deduplicated scene-local list. Quick Open
shows recent Layers for the current page only after revalidating each ID
against the existing authorized Layers projection. A different document
identity invalidates the prior list; hidden, removed, wrong-page, and
unavailable nodes cannot be surfaced through the recent projection. Opening
a recent Layer reuses `selectLayer`. No visit history is written into project
packages, authored history, renderer snapshots, or diagnostics.

## Batch verification (2026-09-30)

- `SiteForgeTests/SelectionModelTests/testQuickOpenRecentLayersBoundDeduplicateAndProjectOnlyAuthorizedNodes`.
- `SiteForgeUITests/SiteForgeLaunchTests/testQuickOpenRecentLayersUseLiveSelectedNodeJourney`.

Both named selectors passed in the batch run. Retained Quick Open current-page
Layers attachments were inspected at original resolution; the result label and
selected row remain legible and are not clipped. Persistent
and cross-page/project recents, predictive ranking, telemetry/cloud sync,
large-fixture performance, and release acceptance remain deferred.
