# SF-LOCAL-BUILDER-007–011 — Focused acceptance manifest

## 2026-10-30 resumed native acceptance

### Frozen targeted title receipt — before usability/language source work

The residual fixed-height title repair is accepted for the measured current
Safari/native path, not the whole static-output specification. Six exact code
methods pass across `focused-7e7bf33b-4045-4d09-a6cd-29f330b4e26b` (five pass,
one invalid multiline-title fixture), the failed diagnostic retry
`focused-8d7ed749-5472-4f3b-8be2-ad16277c26b5`, and final
`focused-4cb5a055-d0fc-4c60-b300-8c405153fef0` (two changed code methods and the
new UI method pass3/3,0 failures/0 skips). Final native journey205.263s.

New code methods:
- `InsertionModelTests.testManagedChromeTitleStaticOverflowRetainsSemanticIdentityAndResponsiveHeight`
- `CanvasTextRenderingTests.testManagedTitleNativeLineCapacityAndInsetsShareResolvedTypography`
- `CanvasRendererTests.testManagedTitleOverflowLeavesOrdinaryMultilineAndControlsUnchanged`

Direct existing neighbors passed:
- `CanvasRendererTests.testStaticTypographyOutputEscapesTextAndUsesAllowlistedCanonicalValues`
- `InsertionModelTests.testHeaderDefaultAndAuthoredTitleUseSameResolutionInInspectorRendererAndOutput`
- `CanvasTextRenderingTests.testCanonicalTypographySharesRendererAndInlineMetricsAcrossZoomAndAlignment`

New public-control journey:
`SiteForgeLaunchTests.testManagedChromeTitleMatchedSafariWidthsAndOverflowJourney`.
Native canvas100%; measured browser CSS widths exactly1440/430/320,
visualViewport.scale1,DPR1. The RDM field needs1441/431/321 in this Safari
version because it includes a border pixel; outer-window size is never evidence.
The same title NodeID persists across all samples; long-title width changes do
not mutate the document. Native and emitted title use default200×24 allocation
(browser320 gives199×24, within1device pixel),14/17 typography and4-point insets.
Browser readouts prove1 visible line,17px visible block,centerDelta0 and full
canonical text. Short and hidden cases pass; hidden title has display:none and
zero paint bounds. Ordinary body retains both authored hard lines and no title
helper. Footer and existing menu remain ordinary authored content.

All15 originals inspected at original resolution:
`siteforge-title-final-4cb5a055/` (manifest maps five native, five Safari and
five console captures). Measured records:
`siteforge-title-final-metrics-4cb5a055/` (five records+manifest).
Long-title pairs: native/Safari1440 `A24A18F6-25B9-4E05-8EA1-BDB207339D5B.png` /
`11A25A6B-B425-4D03-BD5C-4B793C1670AB.png`;430
`35EE30B3-F75D-42CF-8A07-2D81A240AA16.png` /
`A976841D-DFD3-4831-816F-46132CE11529.png`;320
`C0E457D7-BAA2-440C-AB5B-EB9639433787.png` /
`785E7D33-B371-4BD1-AD6F-B10987035CFF.png`.
Short pair `3AF3A6F6-6E49-42DC-B43E-98F491DF3655.png` /
`CB8854DF-9D02-468D-924D-B2BB01CBE531.png`; hidden pair
`1F03EF17-15FE-43F3-8C66-C181233BF924.png` /
`AF016AC2-D903-42BA-92DB-3C51DD6E9275.png`.
No clipped second title line remains; no editor chrome enters Safari output.

Production correction: derive managed-title role from existing validated chrome
references; retain the real semantic/anchor node and full text, with one neutral
non-focusable span for line-budget clipping. Current resolved height and CSS1lh
derive complete-line capacity without baking width-specific glyph positions.
Shared native inset/capacity policy remains render-only. Existing body/control
paths, canonical data, typography intent, IDs and compiler/Preview/export bytes
remain shared. Matching hidden-text specificity prevents layout chrome rules
from accidentally revealing a hidden title. No new persistent preference/schema.
The title command rejects hard-line-break control characters; the corrected
test proves neutrality instead of assuming that unsupported UI input is valid.
Canonical whitespace/escaping and ordinary multiline content are tested separately.
The short-title UI fixture uses one space because macOS's normal double-space
substitution authored a period; no OS setting or title text was silently changed.

**Bounded limitations:** at320, pre-existing exhausted navigation space still
shows cramped Safari menu/title chrome while native has no visible menu. It was
present before this repair and is not certified as general navigation parity.
Safari/native may choose a different final glyph before ellipsis. Older-browser
CSS support, custom/fluid typography browser matrices, other engines, compact
browser certification and full verification remain deferred. No broad parity
or module completion is claimed. The earlier70/70, compositor3/3,HTTP3/3 and
eight distinct native receipts are preserved, not rerun by this correction.

No runner remains. Diff whitespace and JSON checks passed at this boundary.
Owner now pauses **all** subsequent execution during012 usability source work:
no tests/builds/checks/lints/collectors/app/browser/verification or automatic final
cycle. Future012 wording/workflow source is UNVERIFIED by this frozen receipt.
No commit/push/install/sign/schedule or owner-package/recovery mutation.

### Owner-scoped residual title repair — in progress

Bounded SF-0507-003/004/006/008, SF-0604-003/006, supporting SF-0806-003/006,
SF-1202-003/004, SF-1203-003/006, SF-1204-003/004, SF-1211-003/004/008.
The prior Safari deviation is an active correction, not accepted parity.
Native title reaches `CanvasAuthoredTextLayerFactory`, with `CanvasTextLayout`
word wrapping, full text and CATextLayer end truncation. The generic tile
`drawCommittedPlainText` byTruncatingTail helper is not this node's paint path.
Default title identity is the Header's `page.chrome.v1.titleID`,200×24 resolved
points,14/17 System typography and4-point horizontal insets. Static title had
200×24 bounds and14/17 System but pre-wrap text directly inside an overflow-hidden
centered flex box, no complete-line limit and no native horizontal inset.

First three new UI attempts isolated browser-inspection helper errors, not product
conclusions: `focused-5f94bb0e-6c45-4584-b019-ad9cedf2891c` typed before console
focus; `focused-cb5dea4d-12f9-4878-9fed-b26dbbcfc9a1` encountered Web Inspector
prompt hit-point failure; `focused-f9b847db-4e2c-474a-9209-6d731927eb2d` incorrectly
expected contenteditable AXValue instead of its actual evaluated output. The
helper now uses the visible prompt's leading-edge coordinate and evaluated
readout, restoring pasteboard data around input. No delivered page is modified.

Baseline `focused-e79b94d4-61b4-4bf4-a71f-603937446149` passes the diagnostic
journey and captures all three native/browser states. Readouts at
`siteforge-title-matched-before-e79b94d4/` measure actual CSS widths1439,
429,319 (RDM fields1440/430/320), visualViewport.scale1 and DPR1. Title bounds
are200×24,200×24,198×24; same14/17 typography. Inspected all six native/browser
originals: native truncates, Safari clips a wrapped second line in each state.
Thus this is not a Desktop-versus-Mobile interpretation error. Final comparison
must compensate the measured RDM border pixel and assert actual CSS widths.

Source repair uses a derived managed-title render flag, neutral inline text
wrapper inside the same semantic/identity node, shared inset/complete-line
capacity, and connected height projection into CSS. Line capacity follows
resolved height/current CSS line-height (including fluid type), not preset
glyph positions. Ordinary paragraphs/controls keep their old paths. No schema,
canonical title edit, geometry mutation, global nowrap or generated-site patch.
Three new code regressions plus three changed neighbors are currently compiling;
no earlier70-method or eight-journey rerun.

### Final focused outcome (not a full gate)

All six distinct new native journeys and both justified existing neighbors now
pass8/8 across the retained serial focused runs. The preserved code group remains
70/70; no broad rerun occurred. Direct compositor coverage passes3/3 and the
HTTP named-page/security/route group passes3/3. Final invocation
`focused-daa8beb2-fec8-4330-a774-06f19775eaee` passes4/4 (three code methods plus
`testConnectedFluidPreflightSafariExportCancelAndReopenJourney`,214.856s),
0 failures/0 skips. Its native flow opens the real Safari page, cancels the
real export chooser, saves, terminates, reopens, and inspects retained fluid intent.
No runner remains. No full verification, commit/push/install or owner-data change.

Six final originals were extracted and inspected at original resolution in
`siteforge-focused-007-011-safari-daa8beb2/` (attachment manifest retained):

| State | Original filename |
| --- | --- |
| Desktop authoring | `1755C685-6627-422A-A54E-554F5E945AB6.png` |
| Current430 native intent | `B033B723-0D4D-42D4-AA17-FE0F2A6208DF.png` |
| Successful preflight | `43FEE9F7-E537-4901-8622-3F245D7BDA54.png` |
| Real Safari output | `1179BA23-3E13-458A-A9B4-ECCA125D7BE0.png` |
| Export chooser cancelled | `1E51C45A-5782-4341-8BD0-F2EEF8893D04.png` |
| Saved/reopened fluid intent | `AFF430C7-2277-42A2-8D5B-13433A0D73ED.png` |

Observed native controls are readable, selected Stack paint and outline align,
text is upright, artboard/grid gutters remain distinct, saved status is truthful,
and browser output contains no editor selection/grid chrome. Safari's screenshot
is1709 points wide, not proof of430CSS-pixel browser rendering or browser zoom.
**Remaining visual deviation:** the long fixed-height header title wraps/clips
in Safari while native canvas truncates it. No claim of typography/overflow
parity or complete browser visual acceptance is made. Broader measured-width,
compact browser and cross-engine review remain deferred. This deviation is
retained as follow-up evidence, not hidden by shortening the authored test text.
Final exported app stdout contains neither publish-during-view-update nor invalid
view geometry warnings; that is scoped evidence for this run, not a global audit.

All five workflows stay IN PROGRESS and modules Partial. Mandatory full
verification remains deferred, not waived or authorized by this focused result.
Historical failures and in-flight notes below are retained as a chronological
record; this final outcome supersedes their current-state wording.

### Preview startup diagnosis (current)

`focused-63c3998a-706e-46b4-9c39-275c2ad34a3b` executed the Safari method and
failed at the address assertion173.690s. App stdout (exported under
`siteforge-preview-diagnostics-63c3998a/`) proves native menu target equals
the active state, both revision13, and the Preview presentation flag is set.
The hierarchy contains the actual Preview sheet with startup failure status;
the window-only screenshot had omitted it. No command-routing change is justified.

`focused-277f5e8e-218e-43c5-b66c-71ba655f816e` also failed the Safari method;
redacted trace identifies `loopback-start`, `WebsitePreviewError` code0
(`invalidOutput`), before listener startup. The immutable historical fixture has
one valid standard page at `/legacy-surface`, not a home route. Its compiler
output is `legacy-surface.html`; the HTTP adapter incorrectly demanded index.html.
The adapter now requires real HTML output without inventing a home document.
Traversal, duplicate-path, rebinding and resource-only rejection remain intact.
All temporary tracing has been removed. New exact named-page regression, the
two existing HTTP boundary methods and the failed Safari journey only are running
in `focused-daa8beb2-fec8-4330-a774-06f19775eaee`. No70-method rerun.

That invocation's code boundary has passed3/3:
`CanvasRendererTests.testBrowserPreviewNamedPageWithoutHomePreservesExactRouteAndBytes`,
`testBrowserPreviewHTTPRoutesExactExportBytesAndHead`, and
`testBrowserPreviewHTTPRejectsTraversalRebindingAndInvalidArtifacts`.
Safari is still running; code success alone does not accept the browser journey.
Failure-screen original `siteforge-preview-failure-277f5e8e/141FB470-1BD3-4CC6-8D68-140E3E387FB0.png`
was inspected and confirms the actual sheet/status, fitted gutters, upright
native content and visible menu bar/Dock rather than a missing command action.

Current visual review: latest width originals in
`siteforge-focused-007-011-native-4e1c4de4/` (seven), formatting originals
in that same directory (six), both chrome-copy journeys (nine), responsive-review
originals in `siteforge-focused-007-011-final-17a511ec/` (six), and inline
editing originals in `siteforge-focused-007-011-native-ddde49e4/` (three)
have been inspected at original resolution. Readable native controls, explicit
comparison limits, truthful source/skip feedback, upright text, fitted gutters
and aligned selected surfaces are observed. Corrected review capture has no
off-artboard raster sliver. Sheet content scrolls inside its bounded viewport;
this is not a claim that every card is visible simultaneously. Small inline
text at fitted32% remains small; these images are not typography-scale certification.
Safari has not passed and is not visually accepted. All five workflows remain
IN PROGRESS; no broad gate or owner-data mutation is authorized.

Temporary redacted Preview tracing first failed to compile in
`focused-374db771-21ea-49d5-99a4-3bf5851d98d4` because the model referenced a
private view registry. No UI method executed. Trace moved to the native command
boundary; exact Safari journey only is running in `focused-63c3998a-706e-46b4-9c39-275c2ad34a3b`.

Owner readiness triggered one isolated width journey, existing SiteForge scheme /
app.siteforge.SiteForge identity and temporary DerivedData outside Documents.
Selected Xcode is now27.2(27B52), so the existing targets rebuilt. CoreSimulator
version mismatch warning did not block this native macOS destination. No runtime,
privacy/security setting, installation or owner data was changed.

`focused-d9c686be-1d59-4255-87c5-a6905a115237`: automation initialized;
1 UI method executed,0 passed,1 failed,0 skips. It failed at the1023 width
assertion, not authentication. AX exposed `1,023; uncommitted draft; Tablet
breakpoint`. The numeric test assertion ignored locale grouping; the shipping
binding also treated AppKit's formatted committed-value echo as another draft.
The binding now ignores an unchanged echo only when no draft exists. The real
journey now parses localized width and additionally requires no uncommitted
draft; identity, breakpoint, focus, cancellation and comparison assertions stay.
Minimal parser regression plus failed journey are rerunning; no70-method rerun.

Subsequent `focused-d731079b-7c7a-4621-b700-7e91fcd506b8`: parser passed1/1;
width journey failed1/1 at comparison status discovery after Return/blur/Escape/
validation succeeded. The sheet now has an explicit native accessibility child
container and named status value. `focused-eac362e5-0957-4213-bc54-50248b68446e`
then passed the complete width journey1/1 in115.351s,0 failures/0 skips.
Seven originals were exported to `siteforge-focused-007-011-width-eac362e5/`
and inspected: readable controls/cards, fitted gutters and stable Frame identity.
The invalid-width original shows a small surface/selection displacement after
the validation row resizes the canvas; investigate that shared native layer
resize boundary before visual acceptance. A green assertion alone is not enough.
The other five new journeys plus the two named native neighbors are now running
serially in one exact-selector invocation; no full target or code70 rerun.

Original attachments extracted to `siteforge-focused-007-011-width-d9c686be/`.
Inspected original `35FBA793-41B1-43B5-AC72-FE64849CB1C8.png` (430Mobile
insertion): readable header/pane labels, visible fitted grid gutters and page
boundary, selected Frame surface/outline aligned, no ghost object. This is one
observed state, not acceptance of the later failed journey or Safari output.

### Serial native group and directly scoped repairs

`focused-ddde49e4-d2f5-493a-abc5-6d53a56e31bc`: seven distinct native methods
executed serially,3 passed (responsive review, inline editing, keyboard traversal),
4 failed (fluid Preview address, both chrome-copy sheet journeys, formatting
feedback). XCTest restarted after failures; its final3-test sub-run is not the
whole invocation total. Originals/manifest: `siteforge-focused-007-011-native-ddde49e4/`.

Chrome sheet now explicitly contains its accessibility children and names the
source value. Formatting's real Inspector Tools disclosure is revealed before
inspecting its contained feedback. No hidden control or model shortcut. Retry
`focused-4e1c4de4-24f2-4619-92b2-57229d12aaad`:5 methods,4 passed (both chrome
journeys, width, formatting),1 failed (fluid Preview). Full chrome journey
passed155.645s, compact24.593s, formatting172.597s, width114.753s. All0 skips.
Original screenshots and matching attachment manifest are retained at
`siteforge-focused-007-011-native-4e1c4de4/`; redacted failure hierarchy at
`siteforge-focused-007-011-diagnostics-4e1c4de4/`.

Preview failure capture shows the workspace, not a failed browser build. The
new journey used Build as parent of Preview Website in Safari, which is actually
under the native Preview menu. Corrected that real menu interaction, preserving
URL/loopback, Safari content, export cancellation and reopen assertions. The
address query also permits the native selectable-text AX role without dropping
the identifier or actual URL check. No speculative command/persistence change.

The invalid-width original reproduced native layer drift. New exact regression
`CanvasTextRenderingTests.testNativeViewportResizePreservesReprojectedRasterAndTextCoordinates`
failed48 coordinate assertions in `focused-4f06a3b6-1c84-4d2c-be01-4a4d1e38122d`.
Resetting authored/text layer transforms before assigning frame, then restoring
the shared reprojection, fixes the first divergence. It and existing
`testNativeViewportRetainsWorldAlignedRasterDuringZoomAndClearsAtArtboardChange`
passed2/2 in `focused-d7b22397-e07b-4ddb-9dba-74054b2b2f8c`. Inspected corrected
invalid-state original `9D3CF573-5B06-4592-AFA7-BCBF7BB759A5.png`: surface and
selection now coincide without moving canonical geometry.

Review original `F53683F2-6EAE-4FDB-9900-8F227BEC5A42.png` also exposed a
retained-raster sliver outside the artboard during pan. New exact regression
`CanvasTextRenderingTests.testNativeViewportArtboardMaskSharesLiveViewportDuringReprojection`
failed56 coordinate assertions in `focused-751350c4-9d49-4cde-b79f-5e05a2f86409`.
The live viewport mask was transformed again with its raster container. Convert
it into each container's local coordinates and refresh on immutable-plan adoption;
no clipping inflation or authored offsets. Initial three-method regression group
passed3/3 in `focused-38ac3fee-e734-43bc-84e2-9407141dc436`. Strengthened it to
assert mask identity both during reprojection and after fresh-plan adoption.
Only those3 exact code methods plus affected Safari/review journeys are running
for final targeted evidence. The70-method code result is preserved, not rerun.

Owner-approved focused acceptance supersedes the source-only execution hold for these exact methods only. No full verification, whole-target/class execution, commit, push, installation, signing, or owner-document mutation is authorized. All five workflows remain IN PROGRESS pending observed acceptance. Historical receipts are retained.

## Plan

Compile the current source using existing SiteForge scheme and temporary DerivedData outside Documents; run all 56 new model/integration methods before changing assertions. Diagnose failures, repair their production/fixture boundary, and rerun only affected selectors. Run six new native journeys serially, inspect retained original screenshots, and distinguish infrastructure failures from assertions. Add only explicitly justified neighboring regressions. Full verification remains deferred, not waived.

## New model/integration selectors (56)

- `SiteForgeTests/CanvasViewportTests/testResponsiveLayoutReviewDeterministicWidthMatrixAndScope`
- `SiteForgeTests/CanvasViewportTests/testResponsiveLayoutReviewUsesCanvasClipsAndAllowsVisibleOverflow`
- `SiteForgeTests/CanvasViewportTests/testResponsiveLayoutReviewConnectedChromeUsesSharedScene`
- `SiteForgeTests/CanvasViewportTests/testResponsiveLayoutReviewReportsFixedFluidAndOverrideWinnersWithoutAuthoredChanges`
- `SiteForgeTests/CanvasViewportTests/testResponsiveLayoutReviewStandardAndLargeSnapshotsHaveBoundedRows`
- `SiteForgeTests/CanvasViewportTests/testResponsiveLayoutReviewCancellationAndBoundedPresentation`
- `SiteForgeTests/CanvasViewportTests/testResponsiveLayoutReviewNavigatesExactNodeWidthWithoutHistoryOrPackageMutation`
- `SiteForgeTests/CanvasViewportTests/testResponsiveLayoutReviewRejectsStaleDraftIMEAndReplacement`
- `SiteForgeTests/CanvasViewportTests/testResponsiveLayoutReviewRefreshesAfterAtomicEditUndoRedo`
- `SiteForgeTests/CanvasViewportTests/testResponsiveLayoutReviewRedactsDiagnosticsAndRejectsForeignOrigin`
- `SiteForgeTests/CanvasViewportTests/testCustomViewportWidthValidationLocaleAndHalfOpenRanges`
- `SiteForgeTests/CanvasViewportTests/testCustomViewportWidthIsSceneLocalAcrossZoomWindowScaleAndPresetActions`
- `SiteForgeTests/CanvasViewportTests/testCustomWidthSharedLayoutRenderInspectorHitSelectionAndTextMatrix`
- `SiteForgeTests/CanvasViewportTests/testCustomWidthRejectsInvalidStaleAndPendingContextsWithoutMutation`
- `SiteForgeTests/CanvasViewportTests/testCustomWidthPendingIMERejectsThenAllowsExplicitRetry`
- `SiteForgeTests/CanvasViewportTests/testCustomWidthTargetsEffectiveOverrideAndKeepsExactUndoRedo`
- `SiteForgeTests/CanvasViewportTests/testCustomWidthComparisonCoalescesRapidChangesAndRejectsReplacement`
- `SiteForgeTests/CanvasViewportTests/testCustomWidthInsertionPreviewPackageAndStaticOutputRemainTruthful`
- `SiteForgeTests/CanvasViewportTests/testCustomWidthConnectedFlowAndReferenceComparisonShareActualSample`
- `SiteForgeTests/TransformModelTests/testFormattingTextBundlePreservesRawTypographyForegroundAndFluidIntent`
- `SiteForgeTests/TransformModelTests/testFormattingAppearanceTransfersCompleteLayersEffectsAndKeepsTargetGeometry`
- `SiteForgeTests/TransformModelTests/testFormattingCodecRejectsUnknownDuplicateOversizedNestedAndInvalidValues`
- `SiteForgeTests/TransformModelTests/testFormattingCommonSourceDoesNotBorrowMixedPrimaryOrLayerIDs`
- `SiteForgeTests/TransformModelTests/testFormattingPasteReportsApplicableSubsetAndSkipsLockedAndIncompatible`
- `SiteForgeTests/TransformModelTests/testFormattingMultipleTargetsKeepIndependentLayerIDsAndOneHistoryEntry`
- `SiteForgeTests/TransformModelTests/testFormattingPasteAtomicInverseUndoRedoBranchAndRepeatedNoOp`
- `SiteForgeTests/TransformModelTests/testFormattingPasteRejectsStaleCancelledMissingAndMalformedAtomically`
- `SiteForgeTests/TransformModelTests/testFormattingReferencesStayLinkedAndForeignOrMissingDependenciesReject`
- `SiteForgeTests/TransformModelTests/testFormattingOmittedExplicitNoneLegacyDefaultsAndNamedInheritanceRemainDistinct`
- `SiteForgeTests/TransformModelTests/testFormattingImageFillValidatesExistingResourceBytesAndSkipsUnsupportedKinds`
- `SiteForgeTests/TransformModelTests/testFormattingDoesNotTransferLayoutContentOrStateAndRollsBackInvalidBundle`
- `SiteForgeTests/TransformModelTests/testFormattingPackageRecoveryAndSharedRendererCompilerRetainCommittedIntent`
- `SiteForgeTests/TransformModelTests/testFormattingComponentInstancesAreNotArbitraryPropertyTargets`
- `SiteForgeTests/TransformModelTests/testFormattingCopyCleanGateRejectsPendingIMEWithoutClipboardOrHistoryMutation`
- `SiteForgeTests/InsertionModelTests/testConnectedFluidClampCoefficientsMatchAnchorsFractionalWidthsAndClamping`
- `SiteForgeTests/InsertionModelTests/testConnectedFluidContainersCompileSemanticHierarchyWithoutSampledOffsets`
- `SiteForgeTests/InsertionModelTests/testConnectedFluidCascadeCustomWidthsResetAndHiddenGridParticipation`
- `SiteForgeTests/InsertionModelTests/testConnectedFluidManagedRoleWidthAndBoxPaddingPrecedenceRemainTruthful`
- `SiteForgeTests/InsertionModelTests/testConnectedFluidHugFillAndBoundedSizingUseSharedScopeWithoutMutation`
- `SiteForgeTests/InsertionModelTests/testConnectedFluidUnsupportedCasesRetainPreciseCompleteMultipageFindings`
- `SiteForgeTests/InsertionModelTests/testConnectedFluidLegacyAndFixedOutputRemainDeterministicWithoutWrappers`
- `SiteForgeTests/InsertionModelTests/testConnectedFluidFreeRootsLegacyNavigationAspectAndFillStayExplicitlyBlocked`
- `SiteForgeTests/InsertionModelTests/testConnectedFluidCompileCloneHistoryPackageRecoveryAndSanitizedContentStayNeutral`
- `SiteForgeTests/InsertionModelTests/testConnectedFluidOriginalImageBytesAndMissingResourcesBlockWholePlan`
- `SiteForgeTests/InsertionModelTests/testConnectedFluidBrowserExportSnapshotStaleCancelAndDestinationSafety`
- `SiteForgeTests/InsertionModelTests/testPageChromeReuseHeaderFooterBothMissingRoleAndEmptyTargets`
- `SiteForgeTests/InsertionModelTests/testPageChromeReuseSkipsExistingProtectedAndComponentPagesWithoutReplacement`
- `SiteForgeTests/InsertionModelTests/testPageChromeReuseClonesFreshOwnedIDsAndPreservesConnectedBodyAndRoutes`
- `SiteForgeTests/InsertionModelTests/testPageChromeReuseInternalAndExternalSectionDestinationsRemainTruthful`
- `SiteForgeTests/InsertionModelTests/testPageChromeReuseAtomicUndoRedoCancellationBranchAndRepeatNoOp`
- `SiteForgeTests/InsertionModelTests/testPageChromeReuseRejectsStaleDeletedRoleInvalidTargetAndCancelWithoutPartialWrites`
- `SiteForgeTests/InsertionModelTests/testPageChromeReuseIndependentTargetEditDoesNotPropagateOrChangeSource`
- `SiteForgeTests/InsertionModelTests/testPageChromeReusePackageRecoveryAndOrdinaryHistoryRoundTrip`
- `SiteForgeTests/InsertionModelTests/testPageChromeReuseResourceTokenComponentIdentityAndMissingDependencyRejection`
- `SiteForgeTests/InsertionModelTests/testPageChromeReuseSheetSelectionRaceAndPreparationCancellationAreNeutral`
- `SiteForgeTests/InsertionModelTests/testPageChromeReuseResponsiveSharedLayoutRendererAndCompilerGraph`

## New native selectors (6)

- `SiteForgeUITests/SiteForgeLaunchTests/testCustomResponsiveViewportWidthEntryComparisonAndCancellationJourney`
- `SiteForgeUITests/SiteForgeLaunchTests/testResponsiveLayoutReviewJumpsToExactElementAndRefreshesAfterFixJourney`
- `SiteForgeUITests/SiteForgeLaunchTests/testFormattingReuseNativeAppearanceTextStyleAndAtomicUndoJourney`
- `SiteForgeUITests/SiteForgeLaunchTests/testCopyHeaderFooterToPagesIndependentAtomicUndoAndReopenJourney`
- `SiteForgeUITests/SiteForgeLaunchTests/testCopyHeaderFooterSheetAtPracticalMinimumKeepsMissingRolesTruthful`
- `SiteForgeUITests/SiteForgeLaunchTests/testConnectedFluidPreflightSafariExportCancelAndReopenJourney`

## Results

Directly affected existing regressions (14, no class selectors): focus order and
native tab routing; both edited half-open CSS assertions and both edited static
build assertions; shared clone fluid identities; private property clipboard and
None/token inverse; no-change layer feedback; inline draft duplicate publication;
named-page clone; preexisting continuous connected fluid and positioned/clipped
menu rejection. Exact selectors:

- `SiteForgeTests/AppMetadataTests/testShellFocusTraversalIsCompleteBidirectionalAndSceneLocal`
- `SiteForgeTests/AppMetadataTests/testWindowNativeTabPolicyRoutesOnlyBothMixedFrameworkBoundaries`
- `SiteForgeTests/CanvasRendererTests/testResponsiveStaticCSSEmitterUsesOnlyTypedProductBreakpoints`
- `SiteForgeTests/CanvasRendererTests/testStaticLayoutOutputUsesStableRoundingAndExplicitVisibilityOverrides`
- `SiteForgeTests/CommandKernelTests/testMultiPageStaticBuildPlanIncludesTypedLayoutStylesheet`
- `SiteForgeTests/CommandKernelTests/testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference`
- `SiteForgeTests/CommandKernelTests/testPageDuplicateRemapsFluidValueIdentityAndPreservesFixedFallback`
- `SiteForgeTests/TransformModelTests/testInspectorPropertyClipboardStrictTypedRoundTripAndInvalidNeutrality`
- `SiteForgeTests/TransformModelTests/testReusableResetProtectsNoneAndTokensAndRestoresGradientIdentities`
- `SiteForgeTests/TransformModelTests/testWorkspaceFillLayerUnchangedAngleIsSuccessfulAndHistoryNeutral`
- `SiteForgeTests/TransformModelTests/testDuplicateInlineDraftNotificationsDoNotRepublishOrMutateCanonicalState`
- `SiteForgeTests/InsertionModelTests/testNamedPageReusePreservesStructureMetadataHistoryAndSerialization`
- `SiteForgeTests/InsertionModelTests/testConnectedResponsiveFluidDimensionsAndGapRemainContinuousBetweenPresets`
- `SiteForgeTests/InsertionModelTests/testConnectedOutputRejectsPositionedOrClippedMenusWithoutDroppingIntent`

Initial group: `focused-07947a41-f9ed-4a0e-9dd5-f4f21b763a26.xcresult`
and matching log in the external temporary TestResults directory. Build succeeded;
56 methods executed, 46 passed and 10 failed (15 assertion/unexpected failure
records, including four unexpected fixture errors). No native journey executed.

Failure inventory: custom-width IME neutrality; formatting component fixture
duplicate PropertyIDs; three fixture attempts to remove non-leaf nodes; chrome
scene request omitted its breakpoint; sibling-breakpoint expectation incorrectly
inherited Tablet at Mobile; two CSS assertions mixed baseline paint declarations
with the overriding connected-flow declarations; no-fluid comparison omitted
the ordinary development profile compilation step. Corrections are being tested,
not yet accepted. Assertions remain strict at their intended production boundary.

Production correction: width changes now check the retained inline draft's marked
range as well as AppKit's current responder, so missing/replaced native focus
cannot commit composition. Removed the duplicate unreachable no-change catch in
the existing Design fill-layer command handler. No owner data changed.

Targeted rerun: the ten failed methods only, after these concrete changes.

`focused-5b7672e4-a657-4312-8461-2c063276265f`: 10 methods,
9 passed; the IME method still failed two assertions. The width guard alone
could not repair an already-ended draft. Strengthening the draft/selection
preconditions in `focused-01d9817c-c370-48fc-b9a3-121ec71783d1`
proved activation also needed the nested node's existing selection scope.
That diagnostic run executed 1 method and failed 5 assertions. The production
activation now adopts the same scope used by Layers and selects before creating
the draft, preventing the selection edit boundary from immediately committing it.
No timing/timeout relaxation or test-only control was added. Its focused rerun
also includes the existing duplicate-draft publication regression.

Native neighboring selectors justified by the activation/focus changes:

- `SiteForgeUITests/SiteForgeLaunchTests/testKeyboardFocusTraversesWorkspaceForwardAndReverse`
- `SiteForgeUITests/SiteForgeLaunchTests/testInlinePlainTextEditingCommitCancelUndoRedoAndAccessibilityJourney`

These will run serially alongside, not instead of, the six new native journeys.

`focused-4b14ef4c-ff0a-4635-966c-006a28643dab`: IME regression and
duplicate-draft publication regression passed 2/2. Final focused code group
`focused-f67a28d0-7755-4373-8e69-dce4904dc9d4` executed 70 methods:
all 56 new methods passed; 13/14 existing regressions passed. The single failure
required retaining the established exact no-change announcement while removing
the duplicate catch; that message is restored without changing its test.
The isolated regression passed 1/1 in
`focused-3ffd3675-fe21-4621-b103-99688380ec8e`. The UI runner executed zero
methods: current coreauthd logs requested XCTest “Enable UI Automation” at
18:03:28-0400; the runner timed out enabling automation mode at18:04:28.
The owner was notified during that one active request. No settings change,
lock-screen inference, duplicate runner or unchanged retry followed. This is
infrastructure failure, not a SiteForge assertion failure or screenshot evidence.
All six new native journeys and the two named native regressions remain pending;
no screenshots were captured or visually accepted in this attempt.

Final focused code group after the announcement correction:
`focused-e9ba0e1d-6657-444c-9e5b-4ebd7d85d2c7.xcresult` and matching log.
Exit0,70 executed,70 passed,0 failures,0 skips (all56 new plus14 existing).
No full verification, native visual acceptance or workflow completion is claimed.
Preserve this source and rerun only the exact native width selector when the
owner can complete a fresh macOS authentication request; continue the other
manifest journeys serially only after automation initializes.
