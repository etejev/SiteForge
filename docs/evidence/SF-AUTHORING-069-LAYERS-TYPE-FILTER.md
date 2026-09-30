# SF-AUTHORING-069 — Layers object-type filter

## Implemented bounded behavior

Under bounded `SF-0205-003/004/006/008` and supporting `SF-0402-002/006`,
a native NodeKind picker filters only current Layers targets already authorized
by the selection snapshot. It composes with the scene-local name query,
preserves paint order and stable NodeIDs, and never changes the selected node,
document history, package, hit targets, or renderer. Show Selected Layer clears
both predicates when a selected row is filtered out. All Types restores the
unfiltered authorized target projection.

## Batch and focused verification (2026-09-30)

- `SiteForgeTests/SelectionModelTests/testLayerTypeFilterComposesWithNameAndRetainsCanonicalOrder`.
- `SiteForgeUITests/SiteForgeLaunchTests/testLayersTypeFilterKeepsSelectionAndRevealsSelectedNodeJourney`.

The policy selector passed in the 585-test batch. The UI selector initially
failed because an unscoped XCTest query found both Insert > Frame and the
Layer Type > Frame item. Scoping it to the picker exposed a second incorrect
fixture expectation: both the inserted Frame and structural Root are Frame-
kind rows. The exact journey then passed, proving `2 of 3 layers match`,
selection identity/reveal, and unchanged authored content. The filtered and
restored original-resolution screenshots were inspected; controls are readable
and the selected Text stays represented in the Inspector even while filtered.
Persisted filters, cross-page indexing, fuzzy ranking, command palette,
large-fixture search performance, and release acceptance remain deferred.
