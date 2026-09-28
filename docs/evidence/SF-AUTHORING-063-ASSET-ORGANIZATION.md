# SF-AUTHORING-063 — Native Asset Library organization foundation v1

Status: IN PROGRESS. Bounded evidence for SF-0801-001–008; the normative
asset module remains Partial.

## Implemented contract

- Schema 11 adds optional version-one organization metadata to the existing
  `ImageAsset`: up to four project-local folder segments, at most twelve
  distinct normalized tags, and a favorite flag. These are labels, not disk
  locations. Stable AssetID, ResourceID, content hash, bytes, and use counts
  are unchanged. Schema-ten assets decode with organization omitted; older
  schema data cannot smuggle organization fields.
- The Assets pane exposes name/folder/tag search, favorite/folder/tag filters,
  a selected-asset organization sheet, and row metadata. Filters and drafts
  are scene-local. The registry checks live document revision, scene, and
  asset identity before one existing `updateImageAsset` transaction; the
  command kernel supplies an exact inverse. Invalid/cancelled/no-op input
  does not mutate content. Diagnostics use categories, not entered labels.
- Native image decoding, renderer, Preview, static output, asset references,
  replacement, and safe deletion continue to use the same asset identity and
  resource bytes. Organization does not change authored pixels or output.

## Focused evidence

- `ProjectResourceTests/testAssetOrganizationNormalizesAndRejectsInvalidFoldersAndTags`
- `ProjectResourceTests/testAssetOrganizationRegistryGuardsIdentityAndPreservesExactHistory`
- `ProjectResourceTests/testSchemaTenAssetOrganizationMigrationAndVersionGuard`
- `ProjectResourceTests/testStaticImageOutputReferenceUsesOnlyVerifiedContentAddressedEntry`

The four focused model/migration/static-reference selectors passed 4/4 after
strengthening the stale-scene and strict-key assertions. The exact native journey
`SiteForgeLaunchTests/testNativeAssetOrganizationSearchFavoriteUndoAndReopenJourney`
passed 1/1 in an unlocked console session. It imported through the native
Open panel, authored folder/tags/favorite through the visible sheet, searched
and filtered, undid/redid, saved, terminated, and reopened the package. Earlier
two launches could not activate while the macOS console was locked; they were
external launch attempts, not product results. A later UI-test timing/AX-role
correction retained the same native import and checkbox assertions.

Five named original-resolution attachments from the passing result bundle
were inspected: `SF-AUTHORING-063 unorganized asset`, `organization draft`,
`organized asset`, `favorite filtered`, and `reopened asset`. The maximized
window remained windowed with visible pasteboard/artboard, the sheet fields
and actions were readable, the favorite/filter state was clear, and the saved
folder and both tags remained visible after reopen. The selected row's tag
summary initially truncated the second tag; two-line metadata fixed it and
the exact journey was rerun before visual acceptance. No fixture object or
authored-pixel change appeared on the blank canvas. Full gate and hosted CI
remain pending.

Repository checks passed after aligning the headless architecture source
closure with renderer dependencies and repairing stale pre-existing
traceability anchors/duplicate IDs. No product assertion was removed.

## Deferred

Filesystem folders, remote/cloud libraries, smart collections, bulk edits,
drag reordering, media beyond local raster images, browser runtime, broad
assistive-technology/performance matrices, and release acceptance.
