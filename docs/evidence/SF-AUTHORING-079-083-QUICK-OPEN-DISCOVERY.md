# SF-AUTHORING-079–083 Source checkpoint

Status: implementation and test source written, UI acceptance unverified. The
deferred gate began on 2026-10-04 and passed 513/513 non-UI tests. The macOS
console locked at 12:58:32 EDT during the first UI journey, preventing app
activation. After unlock, exact
`testQuickOpenInsertActionsCreateOneObjectAndExposeImageRecoveryJourney`
could not start: XCTest timed out enabling automation mode before launching the
app. Result bundles are in the local SiteForge TestResults directory. This is
not completion evidence for the UI journey or the full gate.

## Bounded contract

- `SF-AUTHORING-079` (`SF-0205-002/003/004/006/008`, `SF-0303-002/004/005/006`): Quick Open's New Page action dismisses its own sheet before presenting the existing native page editor. It checks live document identity and page-editor availability. Apply/Cancel still use the established page transaction and scene-local draft.
- `SF-AUTHORING-080` (`SF-0205-002/003/004/006/008`, `SF-0901-002/003/006`): Components search filters current-document definition PageIDs by name in canonical order. Return reveals the first matching definition; Escape/clear and no-result state do not mutate component data.
- `SF-AUTHORING-081` (`SF-0205-003/004/006/008`, `SF-0801-002/003/006`): Assets All/Used/Unused composes with existing name, folder, tag, and favorite filters. Usage is derived once from current page nodes' Image and image-fill AssetID references, never persisted as another property.
- `SF-AUTHORING-082` (`SF-0205-002/003/004/006/008`, `SF-0801-002/003/006`, `SF-0802-002/006`): Quick Open searches at most the first 100 current-project assets by display name or original filename; selecting a result clears scene-only filters, selects that AssetID, and reveals the real Assets row. It does not insert an Image or retain a local path.
- `SF-AUTHORING-083` (`SF-0205-002/003/004/006/008`, `SF-0901-002/003/006`, `SF-0902-002/006`): Quick Open searches current-document component-definition names/IDs and reveals the corresponding Components row with an explicit Insert button. It never creates an instance merely by navigating to a result.

All search/filter/highlight state is window-local. Canonical page, asset, and
component mutations retain their existing identity-gated command, history,
save/reopen, and recovery boundaries. Missing IDs are revalidated immediately
before navigation. Cross-project indexing, arbitrary command execution,
predictive ranking, persistent searches, and release acceptance remain outside
this bounded cycle.

## Source assertions awaiting executable UI acceptance

- `SelectionModelTests.testQuickOpenNewPageActionIsClosedAndQueryDeterministic`
- `SelectionModelTests.testComponentSearchPreservesDefinitionIdentityOrderAndEmptyRecovery`
- `SelectionModelTests.testAssetUsageFilterSeparatesUsedUnusedWithoutChangingIdentity`
- `SelectionModelTests.testQuickOpenImageAssetResultsUseStableIDsAndBoundedNameProjection`
- `SelectionModelTests.testQuickOpenComponentResultsKeepDefinitionIDsAndActionScopeSeparate`
- `SiteForgeLaunchTests.testQuickOpenNewPageOpensNativeEditorAndPreservesCancelJourney`
- `SiteForgeLaunchTests.testComponentsSearchAndQuickOpenRevealDefinitionJourney`
- Existing `testNativeAssetOrganizationSearchFavoriteUndoAndReopenJourney` now exercises usage filtering and Quick Open AssetID reveal.

No UI journey, visual screenshot, hosted CI, commit, or push is claimed by this
note. The approved `SF-0201-009` publication-copy paragraph
and acceptance wording were synchronized and rendered for page-local visual
review separately from executable verification.
