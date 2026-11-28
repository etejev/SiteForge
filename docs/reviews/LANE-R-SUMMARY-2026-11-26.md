# Lane R review summary — November 26, 2026 (Code Forge, unverified)

Review of every Code Forge batch after batch 17: batch 18 part 1, lanes A–I (A02–A04, B01–B04, C01–C04,
D01–D05, E01–E08, F01, H01–H03, I01–I03). Seven reviewers, one per lane group; per-lane reports:

| Report | Batches | Modules | Defects fixed |
|---|---|---|---|
| [LANE-RA](LANE-RA-review-2026-11-26.md) | 18 part 1, E01, A02–A04 | SF-1301, SF-1306, SF-0906, SF-1803 (flags) | 4 (+1 fixed by RE), 1 accessibility gap |
| [LANE-RB](LANE-RB-review-2026-11-26.md) | B01, B02, B04, F01 | SF-0803, SF-0804, SF-0805 | 5 |
| [LANE-RC](LANE-RC-review-2026-11-26.md) | C01–C04 | SF-1101, SF-1103–SF-1106 | 4 fixed, 1 reported as a new warning, 4 listed |
| [LANE-RD](LANE-RD-review-2026-11-26.md) | D01–D05 | SF-1001–SF-1005 | 13 |
| [LANE-RE](LANE-RE-review-2026-11-26.md) | E02–E08 | SF-1007, SF-1506 | 5 |
| [LANE-RH](LANE-RH-review-2026-11-26.md) | H01–H03 | SF-1204, SF-1206, SF-1208, SF-1211 | 6 |
| [LANE-RI](LANE-RI-review-2026-11-26.md) | I01–I03 | SF-0306, SF-0307, SF-0309 | 12 |

Nothing has been compiled or run (no Swift toolchain on the Windows PC). Every fix was re-read against the
declarations it calls. Restore point before the review: `RP-2026-11-26-R01`; pre-lane baseline: `RP-2026-11-26-11`.
Document schema 27, persisted-history schema 4, website metadata version 3; no new `CanonicalDocument` key,
command or Swift file in the review.

## Facts that affect verification

- `SiteForge.xcodeproj` (restore-point copy) builds in Swift 6 language mode with complete concurrency checking:
  `Sendable` and actor-isolation problems are compile errors.
- `Tests/SiteForgeTests/SupportSettingsTests.swift` is an iCloud placeholder on Windows and was never read. The
  feature-flag registry now has 5 entries (`export.zip-archive`, `versions.named-snapshots`,
  `localization.site-languages`, `versions.compare`, `components.shared-libraries`).
- Undo/Redo now switch to the page an edit changed (I03); opening the schema-4 legacy fixture now shows a migration
  notice and, after a save, a "Before upgrade from schema 4" snapshot (I01); the status bar has a History button.
  UI journeys in `Tests/SiteForgeUITests` that depend on these were not re-run.
- Neither generated browser runtime (motion, interactions) has been run in a browser.
- Each report ends with "Suggested first checks" naming the expressions most likely to fail compilation.

## All 60 test methods added since batch 17

```
SiteForgeTests/BlankProjectTests/testExpressionLanguageTransformsTextNumbersDatesAndExplainsWhichRuleWon
SiteForgeTests/BlankProjectTests/testExpressionLanguageRejectsInvalidInputWithLocatedErrorsAndStaysBounded
SiteForgeTests/BlankProjectTests/testStoredExpressionRoundTripsExactKeysAndKeepsIntentWhenAFieldIsRemoved
SiteForgeTests/CanvasRendererTests/testStaticReleaseCSSOptimizerMinifiesDeduplicatesAndKeepsBlocksWhole
SiteForgeTests/CanvasRendererTests/testStaticOutputIntegrityManifestCachePolicyAndReferenceAudit
SiteForgeTests/CanvasRendererTests/testBuildSettingsResolveBudgetsPerFileReportAndReleasePolicy
SiteForgeTests/CanvasSettingsTests/testBuildSettingsSaveUndoRedoRepairsAndStaleReview
SiteForgeTests/CommandKernelTests/testHistoryListMarksStepsSavingDropsAndJumpMovesBothWays
SiteForgeTests/CommandKernelTests/testCoalescedTransactionsAreOneUndoStepNamedBoundedAndPersistable
SiteForgeTests/DocumentLifecycleTests/testSnapshotRestoreCommandIsOneNewUndoableTransaction
SiteForgeTests/DocumentLifecycleTests/testNamedSnapshotsSaveReopenRestoreToANewHeadUndoAndRecover
SiteForgeTests/DocumentLifecycleTests/testCompareVersionsRunsOffTheMainActorIgnoresStaleRunsAndNeverEditsTheDocument
SiteForgeTests/DocumentLifecycleTests/testComponentLibraryImportIsOneUndoableStepAndCopiesStayReadOnlyUntilDetached
SiteForgeTests/DocumentLifecycleTests/testSnapshotsSheetCreatesRenamesRestoresKeepingCurrentHandsOffCompareAndRecoversDamagedStorage
SiteForgeTests/DocumentLifecycleTests/testHistoryListJumpsAndUndoRedoFollowTheChangedPage
SiteForgeTests/DocumentLifecycleTests/testLegacyOpenKeepsOriginalAsSnapshotBeforeUpgradedSaveAndBackupRestoresUndoably
SiteForgeTests/PersistedHistoryTests/testCollectionsAreStrictSchemaGatedUndoableAndPersistedInHistory
SiteForgeTests/PersistedHistoryTests/testSiteLanguagesAreStrictSchemaGatedUndoableAndPersistedInHistory
SiteForgeTests/PersistedHistoryTests/testSiteLanguageRulesResolveFallbacksDirectionAndAddresses
SiteForgeTests/PersistedHistoryTests/testSiteTranslationsAreStrictUndoablePersistedAndResolvedPerLanguage
SiteForgeTests/PersistedHistoryTests/testSiteTranslationReportAndLanguageChangesKeepTranslationsConsistent
SiteForgeTests/PersistedHistoryTests/testSiteLanguagesSheetCommitsDraftsUndoablyAndCountsRemovedTranslations
SiteForgeTests/PersistedHistoryTests/testSiteTranslationInspectorEditsOneElementUndoablyAndListsItsMissingTranslations
SiteForgeTests/PersistedHistoryTests/testSiteRightToLeftCanvasLayoutMirrorsLaidOutChildrenLikeExportDirection
SiteForgeTests/PersistedHistoryTests/testSiteCanvasLanguageShowsALanguageAsExportedWithoutChangingTheDocument
SiteForgeTests/PersistedHistoryTests/testSiteLanguagesExportOneTreePerLanguageWithAlternatesAndTranslations
SiteForgeTests/PersistedHistoryTests/testCollectionRulesProtectDataAndEditorOperationsAreDeterministic
SiteForgeTests/PersistedHistoryTests/testCollectionTemplatePageBuildsOneEscapedPagePerPublishedItem
SiteForgeTests/PersistedHistoryTests/testCollectionTemplateRecordIsStrictUndoableAndPreviewedLive
SiteForgeTests/PersistedHistoryTests/testCollectionListRepeatsALayerPerItemFilteredOrderedAndPaginated
SiteForgeTests/PersistedHistoryTests/testCollectionListRecordIsStrictBoundedAndUndoable
SiteForgeTests/PersistedHistoryTests/testCollectionImportReadsCSVAndJSONMapsFieldsAndChecksEveryRow
SiteForgeTests/PersistedHistoryTests/testCollectionImportRefusesBrokenFilesAndStaysBounded
SiteForgeTests/ProjectPackageTests/testNamedSnapshotsAreStrictBoundedAndRoundTripThroughThePackage
SiteForgeTests/ProjectPackageTests/testComponentLibrariesExportImportReadOnlyUpdateCompareAndDetach
SiteForgeTests/ProjectPackageTests/testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded
SiteForgeTests/ProjectPackageTests/testDocumentMigrationRegistryIsContiguousAndDryRunReportsWithoutContent
SiteForgeTests/ProjectResourceTests/testSVGSanitizerRemovesScriptsExternalReferencesAndEventAttributes
SiteForgeTests/ProjectResourceTests/testSVGRecolorRewritesEveryPaintAndRefusesIncompatibleIcons
SiteForgeTests/ProjectResourceTests/testSVGAssetImportRecolorUndoSaveReopenExportAndSchemaGate
SiteForgeTests/ProjectResourceTests/testProjectFontModelIsStrictValidatedOmittedWhenEmptyAndUndoable
SiteForgeTests/ProjectResourceTests/testProjectFontResolutionFollowsCSSWeightMatchingAndFallbackRule
SiteForgeTests/ProjectResourceTests/testProjectFontsExportOnlyWithDeclaredWebRightsAndUseFallbackStacks
SiteForgeTests/ProjectResourceTests/testFontImportKeepsOriginalBytesAndReadsFaceFacts
SiteForgeTests/ProjectResourceTests/testProjectFontEditsAreUndoableAndFontBytesSurviveSaveAndReopen
SiteForgeTests/ProjectResourceTests/testMediaModelIsStrictValidatedOmittedWhenEmptyAndUndoable
SiteForgeTests/ProjectResourceTests/testMediaPlaybackRulesProvenanceAndOneUndoableEditPerChange
SiteForgeTests/ProjectResourceTests/testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound
SiteForgeTests/ProjectResourceTests/testMediaImportKeepsOriginalBytesAndMediaSurvivesSaveAndReopen
SiteForgeTests/ProjectResourceTests/testProjectCreationResourcesRequireEveryFontAndMediaFile
SiteForgeTests/ProjectResourceTests/testFontAndMediaEditsRestoreFromPersistedHistory
SiteForgeTests/ProjectResourceTests/testMediaAssetCommandsShareStateAndRecordContentFreeDiagnostics
SiteForgeTests/TransformModelTests/testCopiedInteractionsFollowCopiedTargetsAndKeepOutsideTargets
SiteForgeTests/TransformModelTests/testMotionTypedValidationHistoryPropertyIdentityAndSchemaGate
SiteForgeTests/TransformModelTests/testEventGraphTypedValidationHistoryClickPolicyAndSchemaGate
SiteForgeTests/TransformModelTests/testEventGraphOutputCompilesFixedActionsStartHiddenAndDiagnostics
SiteForgeTests/TransformModelTests/testRuntimeVariablesOverlaysAndVisibilityTypedValidationHistoryAndSchemaGate
SiteForgeTests/TransformModelTests/testRuntimeVariablesOverlaysOutputHydrationRuntimeAndDiagnostics
SiteForgeTests/TransformModelTests/testInteractionOutputHiddenRuleFirstRenderOverlayConditionsAndStaticLayoutContainers
SiteForgeTests/TransformModelTests/testMotionOutputIsReducedMotionSafeProgressiveDeterministicAndReleaseStable
```

Changed by the review (assertions added or corrected; none weakened):
`ProjectPackageTests/testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded`,
`ProjectPackageTests/testComponentLibrariesExportImportReadOnlyUpdateCompareAndDetach`,
`ProjectResourceTests/testMediaAssetCommandsShareStateAndRecordContentFreeDiagnostics`,
`ProjectResourceTests/testMediaImportKeepsOriginalBytesAndMediaSurvivesSaveAndReopen`,
`ProjectResourceTests/testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound`,
`CanvasSettingsTests/testBuildSettingsSaveUndoRedoRepairsAndStaleReview`,
`PersistedHistoryTests/testCollectionListRepeatsALayerPerItemFilteredOrderedAndPaginated` (expected `../../` paths),
`PersistedHistoryTests/testSiteTranslationReportAndLanguageChangesKeepTranslationsConsistent`,
`PersistedHistoryTests/testSiteTranslationsAreStrictUndoablePersistedAndResolvedPerLanguage`,
`PersistedHistoryTests/testSiteRightToLeftCanvasLayoutMirrorsLaidOutChildrenLikeExportDirection`,
`CommandKernelTests/testHistoryListMarksStepsSavingDropsAndJumpMovesBothWays`,
`DocumentLifecycleTests/testHistoryListJumpsAndUndoRedoFollowTheChangedPage`.
Existing tests the review expects to now pass: `PersistedHistoryTests/testSiteLanguagesAreStrictSchemaGatedUndoableAndPersistedInHistory`
(duplicate comparison entry removed), `ProjectResourceTests/testMediaPlaybackRulesProvenanceAndOneUndoableEditPerChange`
(playback validated before commit). Existing UI test likely affected by H03 layout, now restored:
`testPreviewAndCheckWebsiteFindingRepairUsesExistingEditorJourney`.

## Not built (largest open items, details and plans in the reports)

Collections Import tab (SF-1005-006); overlay placement relative to the trigger (SF-1105-002); hide/show/overlay of
containers on static-layout pages (reported by `interaction-container-flat`); right-to-left default language on the
canvas; UI tests and 100/10,000-object performance fixtures for every lane; WOFF2 import may need an owner decision.
