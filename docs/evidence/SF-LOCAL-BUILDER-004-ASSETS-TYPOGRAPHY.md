# Practical image reuse and typography — source-focused checkpoint

Current accumulated acceptance inventory: `SF-LOCAL-BUILDER-005-INTEGRATION.md`.
005 extends this package's existing native selector, not a duplicate long journey.
Results below remain historical 004 source evidence, not current native/full acceptance.

## Scope

SF-LOCAL-BUILDER-004 remains IN PROGRESS. Bounded SF-0801-002/003/004/005/006,
SF-0802-003/004/005/006, SF-0807-002/003/004/005/006,
SF-0507-002/003/004/005/006 and font-fallback SF-0805-003/004/006 remain Partial.
Accessible operation is implemented/compiled, not newly observed native acceptance.
Reuse existing resources/import, Image/fill/component registries, history,
organization, typography metrics and immutable output. No new schema, resource
store, renderer, font import/distribution or licensing policy.

## Delivered source behavior

- Image, image-fill and organized component-media controls share Choose from
  Assets, search, current thumbnails, scoped Import Image, usage and explicit
  Replace Asset Everywhere actions. Definition editing explains propagation;
  instance edits remain overrides. Cancel does not mutate the project.
- Selected-use import captures document/page/revision/scene/renderer/selection
  identity before the native panel. Existing registries validate the decoded
  result. New asset metadata plus reference replacement is one atomic command;
  existing content hashes reuse AssetID/resources. The lifecycle retains staged
  resource ownership/rollback. Other uses, organization, geometry, fit, focal
  point, alt, sizing intent and responsive overrides are preserved.
- Global replacement explicitly confirms canonical reference counts/categories
  and offers Review Uses or Cancel. Document/revision/asset identity is checked
  around panel/decode. AssetID and organization remain stable; no-op/duplicate
  results do not silently overwrite another asset. Original resource bytes remain.
- One derived reference inventory covers Image nodes, image fills, component
  defaults/instance media overrides and website favicon. Counts are canonical
  references, not expanded rendered instances. Reveal Uses waits for actual
  page adoption, then delegates to existing Layers selection; no guessed parent
  path or delayed selection overwrite. Definition-exit restrictions remain.
- Thumbnail cache invalidation includes document and ResourceID, not just
  AssetID. Request identity guards cancellation and Undo/Redo ABA replacement;
  old completion cannot erase or publish over a newer request.
- Installed-family search reads local CoreText metadata off-main, omits private
  names and offers discovered upright faces matching the model's four supported
  weight traits. System retains its existing supported weights. No font download,
  registration, licensing or packaging is implied. Explicit family choice does
  not silently rewrite other typography properties.
- Mixed family/weight/alignment and missing-family fallback remain truthful.
  Missing authored intent is preserved; the live current snapshot reports its
  fallback. Matching family/size/line-height/tracking drafts survive unrelated
  adoption, including incomplete input. Changed selection/breakpoint/value
  retains a conflict and rejects commit. Return/valid blur use existing commands;
  Escape cancels. Base typography edits retain fluid rules and disclose that
  scope. Native rendering/editor metrics continue through the shared resolver.

## Focused results

Final group: **22/22 code tests passed**, zero failures/skips. Seven new tests
plus fifteen existing affected regressions. Application and UI-test targets
compile. Final bundle:
`focused-1146daad-7f40-4a3e-9443-67150f51a8ad.xcresult`, under ignored
`.codex-loop/asset-type-workflow-focused/`; log under ignored
`.codex-loop/component-reuse-focused/asset-type-isolated-final.log`.
Earlier 5/5, 21/21 and 3/3 incremental groups are not additional unique coverage.
Apple service-connection diagnostics remain in logs; no warning-free native
runtime claim. New state-based regressions explicitly use fixture-owned recovery
directories. No recovery-directory cleanup outside those fixtures is authorized.

Repository/security/hygiene, architecture boundaries, tooling and foundation
evidence checks pass, including 425-record traceability. `git diff --check`
passes. All focused processes started for this package have completed; no new
native/UI/full collector was launched. Final scoped review adds no alternate
canonical write path or schema, no hidden automation controls and no generated
artifacts to source. Existing unrelated dirty work is preserved, not certified
by this focused result. Work remains uncommitted and unpushed.

New `SiteForgeTests/ProjectResourceTests/` selectors:

- `testSelectedImageImportIsAtomicLocalDeduplicatedAndReopensWithOriginalBytes`
- `testSelectedImageDecodeCompletionRejectsStaleSelectionAndCancellation`
- `testAssetUsageRevealWaitsForActualFillReferencePageAdoption`
- `testSharedAssetThumbnailTracksReplacementUndoAndRedoResourceIdentity`

New `SiteForgeTests/CommandKernelTests/` selector:

- `testSelectedMediaAssetUseAndGlobalReferenceInventoryPreserveScope`

New `SiteForgeTests/CanvasTextRenderingTests/` selectors:

- `testInstalledFontCatalogOffersOnlyDiscoveredWeightsAndPreservesMissingIntent`
- `testTypographyScopeGuardPreservesMissingFamilyFluidSizingAndExactHistory`

Existing affected selectors in the same group:

- `ProjectResourceTests/testImageImportPreservesExactBytesMetadataAndRejectsCorruptInput`
- `ProjectResourceTests/testImageCanonicalNamespaceAndMetadataRejectIncompleteUnknownAndOversizedValues`
- `ProjectResourceTests/testImageResourceSidecarRoundTripPreservesBytesAndMissingIntent`
- `ProjectResourceTests/testRejectedAssetMutationRollsBackStagedResourceBytes`
- `ProjectResourceTests/testImageAssetRenameAndReplacementPreserveIdentityWithExactUndoRedo`
- `ProjectResourceTests/testImageInspectorRejectsInvalidStaleAndInapplicableEditsWithoutMutation`
- `ProjectResourceTests/testComponentDefinitionResourcesSurviveLinkedDuplicationSaveAndRecovery`
- `CommandKernelTests/testComponentImageMediaOverrideResetHistoryRendererPersistenceAndValidation`
- `TransformModelTests/testTypographyRegistryValidatesMixesResetsPersistsAndUndoRedo`
- `TransformModelTests/testFrameSectionImageFillIsAtomicScopedAndMissingSafe`
- `CanvasTextRenderingTests/testCanonicalTypographySharesRendererAndInlineMetricsAcrossZoomAndAlignment`
- `CanvasTextRenderingTests/testTypographyRepeatedFocusReconciliationIsNeutralAndNotValidationFailure`
- `CanvasTextRenderingTests/testIntrinsicSizingAndLiveCanvasUseSameFontAndWrappingBounds`
- `CanvasTextRenderingTests/testFrameImageFillPaintsInsideAuthoredBoundsAtNativeScale`
- `CanvasRendererTests/testStaticTypographyOutputEscapesTextAndUsesAllowlistedCanonicalValues`

The import regression decodes actual fixture PNG bytes, saves/reopens a real
fixture package, restores its isolated autosave/recovery and checks exact undo
plus both original/new resource bytes. Thumbnail coverage checks real decoding
after replacement/Undo/Redo. Component coverage distinguishes all five reference
categories and per-instance changes. Font tests use real local descriptors and
existing renderer/static projection, not a new font resolver.

## Compiled native acceptance — NOT EXECUTED

`SiteForgeUITests/SiteForgeLaunchTests/testPracticalImageReuseScopedReplacementAndTypographyJourney`
uses native open panels, two real Image uses, selected-use import, chooser search/
cancel, explicit global confirmation, Undo/Redo, installed-font choice, missing
family, numeric Return/blur/Escape and Save/terminate/reopen. Existing image-fill
journey now opens the shared chooser and selects its real listed asset rather
than assuming an obsolete menu. Compilation is not proof of runtime behavior.

No new screenshots exist. Planned named captures cover scoped replacement,
global reference confirmation, installed font/cancelled draft and save/reopen.
Native pointer/keyboard/AX, original-resolution normal/compact visual review,
actual Safari and installed acceptance remain pending OD-025. Do not retry the
known-broken native connection or UI automation without restored access.

## Historical pending snapshot — superseded by 005's current inventory

Keep 002, 003 and 004 IN PROGRESS. After native access is genuinely restored:
run the new 004 journey and affected image-fill/media workflows, 002 component
journey, 003 responsive/bounds journeys, then all seven Settings destinations
(Appearance, Canvas, Accessibility, Defaults, Updates, Support, Advanced).
Inspect original-resolution captures and actual Safari, fix observed defects,
then run ONE accumulated changed-tree full gate. A safe installed refresh needs
normal owner Save/Quit proof and source/provision fingerprint checks first.

The historical 682 code +133 UI =815 pass verifies an older fingerprint only.
It is not current source/full acceptance. No app installation, genuine Aurora or
recovery manipulation, commit, GitHub, release, signing or privacy change occurs
in this package. Current owner work is unknown and must be preserved.

Font import/licensing, arbitrary weight axes, new resource organization systems,
rich typography, broad profile/export/browser parity and release acceptance are
not claimed. OD-018/019 component architecture choices remain excluded.
