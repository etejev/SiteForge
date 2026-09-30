# SF-AUTHORING-070 — Native Quick Open

## Implemented bounded behavior

Under bounded `SF-0205-002/003/004/006/008`, the editor has a visible
Quick Open action and a native View-menu Command-Shift-O command. Both target
the active workspace state; the sheet composes existing local page and
authorized current-page Layers projections. Pages appear before Layers in
canonical order. Every result retains its stable PageID or NodeID and opens
through `selectPage` or `selectLayer`, not a second mutation registry. The
query is scene-local and cancellation/no-match never edits project content,
history, persistence, renderer, or selection. Unsupported/hidden targets do
not become discoverable through this surface.

## Batch verification (2026-09-30)

- `SiteForgeTests/SelectionModelTests/testQuickOpenResultsKeepPageThenCurrentLayerIdentityWithoutMutation`.
- `SiteForgeUITests/SiteForgeLaunchTests/testQuickOpenMenuKeyboardPageLayerAndCancelJourney`.

Both named selectors passed in the batch run. The original-resolution Quick
Open sheet screenshots show readable labels, native focus, bounded results,
and Cancel without clipped controls in the maximized window. Arbitrary command
search/execution, cross-project indexing, persistent recents, fuzzy ranking,
large-fixture performance, and release acceptance
remain deferred. `SF-0205` stays Partial.
