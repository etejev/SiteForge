# SF-AUTHORING-071 — Quick Open View actions

## Implemented bounded behavior

Under bounded `SF-0205-002/003/004/006/008`, Quick Open searches a closed,
stable-order list of three existing editor actions: Fit Document, Actual Size,
and Toggle Grid. Activation uses the same viewport/Grid state methods as
the native View controls. No authored document command, history entry, package
property, or renderer pixel is created. Unrecognized/destructive commands
cannot be found through this action list.

## Batch verification (2026-09-30)

- `SiteForgeTests/SelectionModelTests/testQuickOpenViewActionsAreClosedOrderedAndQueryDeterministic`.
- `SiteForgeUITests/SiteForgeLaunchTests/testQuickOpenViewActionsFitAndToggleGridWithoutDocumentMutationJourney`.

Both named selectors passed in the batch run. Original-resolution Quick Open
Actions scope shows three legible actions and current Grid state without
overlap; activation uses existing scene-local viewport controls. Arbitrary
content commands, connected actions, fuzzy ranking, persistent recents,
large-fixture performance, and release acceptance remain
deferred. `SF-0205` stays Partial.
