# SF-AUTHORING-068 — Native Elements catalogue search

## Implemented bounded behavior

Under bounded `SF-0205-002/003/004/006/008` and supporting `SF-0405-002/006`,
the native Elements catalogue filters its stable item list by title or
category. The query is trimmed, limited to 256 characters, and case/diacritic
insensitive. Original category/source order and the existing availability
contract remain authoritative: searching for a future/unavailable item cannot
enable it or bypass its insertion command. Search is local view state, never a
document node, history command, package property, or renderer input. The
catalogue shows a count, explicit no-result state, and Clear Search/Escape.

## Batch verification (2026-09-30)

- `SiteForgeTests/InsertionModelTests/testElementCatalogSearchPreservesOrderCategoriesAndAvailability`.
- `SiteForgeUITests/SiteForgeLaunchTests/testElementsSearchFindsAndInsertsSupportedItemWithoutEnablingUnavailableJourney`.

Both named selectors passed in the 585-test batch run. The retained original-
resolution Elements search, unavailable, and empty-state window attachments
were inspected: labels remain readable, unavailable items stay visible but
disabled, and the blank canvas has no sample objects. The batch run recorded
504/504 unit/integration passes and 79/81 UI passes; its two unrelated UI
failures were corrected and passed by exact focused reruns.

Node/action command search, fuzzy ranking, saved queries, large-project search
performance, broad accessibility/localization matrices, and release acceptance
remain deferred. `SF-0205` stays Partial.
