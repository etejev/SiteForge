# SF-AUTHORING-067 — Native Layers navigator node search

## Bounded contract

This slice covers current-page Layers name search under bounded
`SF-0205-002/003/004/006/008` and the existing `SF-0402-002/006` selection
path. It uses the already-authorized `layerTargets` projection, so it cannot
reveal hidden or unavailable nodes beyond the existing Layers contract. The
query is scene-local, trimmed, capped at 256 characters, case/diacritic-
insensitive, and preserves paint order and NodeID. Filtering cannot mutate
project content, history, selection, hit targets, or renderer state. Return
selects the first match through `selectLayer`; Escape and Clear Search remove
only the query. A no-result state and Show Selected Layer action provide an
explicit recovery path.

## Focused evidence — 2026-09-29

- `SiteForgeTests/SelectionModelTests/testLayerSearchPreservesTargetIdentityPaintOrderAndSelectionSnapshot` — passed 1/1.
- `SiteForgeUITests/SiteForgeLaunchTests/testLayersSearchFiltersSelectsAndRecoversWithoutChangingDocumentJourney` — fresh-process app journey passed 1/1.
- `SiteForgeUITests/SiteForgeLaunchTests/testSelectionEmptySingleMultipleLayersKeyboardAndAccessibilityParity` — affected existing keyboard and additive-selection journey passed 1/1.
- Total affected focused selectors: 3/3; no broad gate was run for this isolated navigator projection.

Original-resolution actual-app screenshots were extracted to a temporary
evidence directory and inspected:

- Filtered result with prior selection intact: `D6AEEF27-A268-4405-867F-97E76CD64E8B.png`.
- No result, selected layer recoverable: `BF21D75D-3B28-4FED-B624-03B8582F07A7.png`.
- Cleared query and selected Layers row: `D16FF549-71DA-4C8D-BA87-0C14B38061FF.png`.

The search field, counts, selected row and recovery button are readable in the
normal maximized window. Canvas selection and Inspector identity match after
Return; no stale overlay appeared. The three visible pale rectangles belong
to the explicit multi-selection UI-test fixture, not a genuinely blank
project. The existing navigator overflow truncates the far-right Components
tab in this capture; it was not introduced by Layers search and remains a
separate visual-contract issue.

## Deferred

Cross-page/project indexing, hidden/unavailable target exposure, object-type
filters, fuzzy ranking, saved queries, command palette, large-fixture search
performance, broad VoiceOver/localization matrices, and release acceptance
remain deferred. The combined tree is uncommitted; no post-SF-AUTHORING-063
full or hosted gate is claimed.
