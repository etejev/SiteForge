# Source-only half-batch: approved icon and Quick Open insertions

Status: source implemented, UI acceptance unverified. The deferred local gate
began on 2026-10-04 but the console locked during the UI target; a later exact
UI attempt stopped before test launch when XCTest timed out enabling automation.

## Bounded requirements and work

- `SF-PRODUCT-UI-005` — `SF-0201-009`: preserve the approved gradient artwork at
  `docs/design-assets/siteforge-app-icon-sf-gradient-approved-v1.png`; remove
  only its edge-connected exterior white matte and package the ten standard
  macOS catalog PNGs with `scripts/package_app_icon.py`. The static artwork is
  not canonical project content or a runtime-generated image.
- `SF-AUTHORING-075` — bounded `SF-0205-002/003/004/006/008` and
  `SF-0405-002/004/005/006`: Quick Open Frame and Text one-shot insertion.
- `SF-AUTHORING-076` — the same bounded search/insertion contract plus
  `SF-0502-002` and `SF-0503-002`: Section, Stack, Grid insertion.
- `SF-AUTHORING-077` — the same bounded search/insertion contract: Button,
  Link, Form insertion.
- `SF-AUTHORING-078` — the same bounded search/insertion contract plus
  `SF-0801-002` and `SF-0802-002`: selected-asset Image insertion and native
  Import and Insert Image. A selected-asset action is absent without one.

The `QuickOpenInsertAction` list is a scene-local discovery projection. A
selection is revalidated against the active `WorkspaceShellState` immediately
before the existing `performDefaultInsertion`, `insertSelectedImage`, or
`importImages(insertFirst: true)` boundary. Canonical NodeIDs, AssetIDs,
history, renderer adoption, save/reopen, and recovery remain owned by those
pre-existing command paths. A disabled action does not dismiss the sheet or
mutate a project. File-panel cancellation remains noncanonical.

## Source and observed checks

- `AppMetadataTests.testAppIconCatalogCoversEveryMacSizeAndIsSelectedByBothAppConfigurations`
  passed 1/1 in the built app. Source/catalog integrity, ten RGBA PNG dimensions,
  approved 1024-pixel digest, and both target configurations are checked by
  `scripts/check-app-icon.py` from the repository checker. The original app-host
  test hung opening a repository file; a process sample located the blocked
  Foundation file-open call, so repository-file checks were moved out of XCTest.
- `SelectionModelTests.testQuickOpenBasicInsertActionsAreClosedAndSearchable`
- `SelectionModelTests.testQuickOpenStructuralInsertActionsPreserveCanonicalKindsAndOrder`
- `SelectionModelTests.testQuickOpenSiteControlsRouteOnlyToSupportedInsertionKinds`
- `SelectionModelTests.testQuickOpenImageInsertionRequiresSelectedAssetButImportRemainsDiscoverable`
- `SiteForgeLaunchTests.testQuickOpenInsertActionsCreateOneObjectAndExposeImageRecoveryJourney`

The interrupted full gate passed 513/513 non-UI tests and repository checks;
no UI acceptance or wholly green full gate is claimed. The old icon's
Finder/Dock cache question remains open until a fresh
build and direct visual review. `SF-0205` and the insertion/media modules stay
Partial; cross-project commands, arbitrary command execution, and release
acceptance remain excluded.
