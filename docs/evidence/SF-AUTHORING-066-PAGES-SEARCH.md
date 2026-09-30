# SF-AUTHORING-066 — Native Pages navigator search

## Bounded contract

This scene-local slice covers page-name and route search under bounded
`SF-0205-002/003/004/006/008`, with existing page identity/navigation under
`SF-0303-002/006`. It does not claim the complete search/command module.

The query is a view projection of current in-memory website pages. It trims
surrounding whitespace, considers at most 256 characters, folds case and
diacritics with a deterministic POSIX locale, and preserves canonical page
order. Return opens the first match through the existing page-selection path.
Escape and Clear Search clear only the query. Filtering cannot change the
selected PageID, canonical revision, package, history, or renderer. When the
selected page is filtered out, Show Selected Page clears the query and returns
the visible list to that page. A no-result state is explicit and recoverable.

## Focused evidence — 2026-09-29

- `SiteForgeTests/BlankProjectTests/testPagesSearchMatchesNameAndRouteWithoutChangingDocumentOrSelection` — passed 1/1.
- `SiteForgeUITests/SiteForgeLaunchTests/testPagesSearchFiltersRoutesOpensFirstAndPreservesSelectionJourney` — passed 1/1 in a fresh app process.
- `SiteForgeUITests/SiteForgeLaunchTests/testPagesNavigatorExposesApprovedOrderLabelsSelectionAndArrowNavigation` — affected existing journey passed 1/1.
- Total affected focused selectors: 3/3; no broad gate was run for this isolated navigator projection.

Original-resolution retained window captures inspected:

- Route result: `1FB0F238-CE34-47E7-9545-948C645BE658.png`.
- No result and recovery action: `014FD10E-9673-4C5E-A15A-3C39D795DEB5.png`.
- Cleared query with selected page: `987F53F7-9D9D-4012-A429-BA2F1FD34E2C.png`.

These were extracted to a local temporary evidence directory, not added to
project content or a machine-specific repository path.

The search field, count, page rows, and no-result recovery remain visible and
readable in the normal maximized window. The centered artboard, pasteboard
grid, and empty-canvas state remain unchanged; no ghost content appeared.
The existing compact navigator tab strip truncates the far-right Components
label in these captures; that is outside this Pages-search slice and must not
be mistaken for search acceptance. Its keyboard navigation remained covered
by the existing focused journey.

## Deferred

Node/action indexing, object-type filters, cross-project search, fuzzy ranking,
persisted recent queries, large-fixture performance, broad VoiceOver and
localization matrices, and release acceptance remain deferred. The combined
working tree is uncommitted; no post-SF-AUTHORING-063 full or hosted gate is
claimed.
