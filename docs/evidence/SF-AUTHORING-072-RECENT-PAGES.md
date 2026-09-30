# SF-AUTHORING-072 — Quick Open recent pages

## Implemented bounded behavior

Under bounded `SF-0205-003/004/006/008`, explicit page navigation updates
an eight-entry deduplicated scene-local PageID list. Quick Open shows these
before broad results when the query is empty. IDs are revalidated against
current website pages, and a different document identity invalidates the
scene's previous recent projection. Selecting a recent entry uses the same
`selectPage` path as the Pages navigator. No visits or queries are saved in
project packages, authored history, renderer snapshots, or diagnostics.

## Batch verification (2026-09-30)

- `SiteForgeTests/BlankProjectTests/testQuickOpenRecentPagesDeduplicateBoundAndDiscardMissingIDs`.
- `SiteForgeUITests/SiteForgeLaunchTests/testQuickOpenRecentPagesPreserveIDsAndOpenThroughNativeJourney`.

Both named selectors passed in the batch run. The retained Quick Open recent-
pages screenshot was inspected at original resolution; page names and routes
are readable, and the scene-local recent section does not overlap the query.
Persistent
usage history, cross-project recents, predictive ranking, telemetry/cloud
sync, large-fixture performance, and release acceptance remain deferred.
