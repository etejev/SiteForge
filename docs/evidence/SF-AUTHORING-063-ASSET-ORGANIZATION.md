# SF-AUTHORING-063 — Native Asset Library organization foundation v1

Status: local checkpoint verified; uncommitted for owner review. Bounded evidence for SF-0801-001–008; the normative
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

## Prompt-ten verification interruption

The full-gate unit/integration target passed **486/486** on 2026-09-28.
Ten historical schema/sizing test expectations were then reconciled with
schema eleven and current minimum-size clamping; their exact focused rerun
passed **10/10**. A prior full UI attempt exposed an Inspector scrolling-test
defect: XCTest considered an off-viewport Shadow control hittable, so its click
did not commit. The test now checks its bounds against the visible scroll
viewport before clicking. The affected Border/Shadow and local-color-token
journeys passed together **3/3** after that repair. The subsequent full-gate
unit/integration target again passed **486/486**, but its UI target was
interrupted before a final result.

On 2026-09-29, a UI-target-only continuation did not launch any test: the
managed xcodebuild process exited 133 when macOS denied its connection to
`com.apple.testmanagerd.control` with sandbox error 159. That attempt was an
environment/authorization failure, not a SiteForge assertion result. A later
direct macOS UI run executed 70 tests (68 passed, two failed) and exposed a
shared selection-adoption defect when a selected Frame became off-artboard at
Mobile. The focused product correction passed one new model test and both
affected UI journeys (2/2), with original-resolution Tablet/Mobile/Reveal
evidence reviewed; see `SF-RESPONSIVE-SELECTION-RECOVERY.md`. A final
post-repair `./sf verify` passed **486/486 unit/integration** and **70/70 UI**
tests (**556 total, zero failures**) on 2026-09-29. Its retained result bundle
is `full-4cb096f9-35f2-49ef-956e-1a6887212d48.xcresult`. This closes the
local checkpoint only; no commit, push, hosted CI, or release claim is recorded.

## Deferred

Filesystem folders, remote/cloud libraries, smart collections, bulk edits,
drag reordering, media beyond local raster images, browser runtime, broad
assistive-technology/performance matrices, and release acceptance.
