# SF-AUTHORING-074 — Quick Open result scopes

## Implemented bounded behavior

Under bounded `SF-0205-003/004/006/008`, native Quick Open offers All,
Pages, Layers, and Actions scopes. Each scope filters the same live
current-document page, authorized current-page layer, and closed View-action
projections. It also filters the scene-local recent sections; it cannot
change PageID, NodeID, source order, project history, packages, or renderer
content. Return opens only a result visible in the chosen scope. Cancel
remains neutral.

## Batch verification (2026-09-30)

- `SiteForgeTests/SelectionModelTests/testQuickOpenScopesFilterResultClassesDeterministically`.
- `SiteForgeUITests/SiteForgeLaunchTests/testQuickOpenScopesPagesLayersActionsAndCancelJourney`.

Both named selectors passed in the batch run. The exact UI journey also passed
after the sheet's accessibility containment was made explicit so child
identifiers remain individually discoverable. Original-resolution Actions and
Layers scope screenshots were inspected: the segmented choices, result
counts, result rows, and Cancel are readable without clipping. The batch run
recorded 504/504 unit/integration and 79/81 UI passes; its two UI failures
passed exact focused reruns without a second broad run. Persisted query
objects, cross-project search,
fuzzy ranking, arbitrary/destructive command execution, large-fixture
performance, and release acceptance remain deferred.
