# Code Forge activity log (factual record for Codex)

This file lists what Code Forge (the AWS Quick coding assistant working for the
owner) changed in this working tree, so nothing has to be inferred. It holds facts
only: no instructions, rules or workflow for Codex. Newest batch first.

Code Forge has no Swift toolchain, Xcode or git. None of its Swift has been compiled
or run locally. It never commits or pushes; the owner reviews and Codex verifies.

## Lane V verification — November 26, 2026 7:00–11:29 PM EST (all Code Forge work since batch 01, unverified, stopped for Codex review)

Owner request: re-verify all Code Forge work as unverified, fix every issue, finish partial features, clean stopping point for Codex.
21 lane V agents (V01–V21, V12b, V14a–e) wrote 284 times to 93 files (31 Swift) through forge_io; nothing compiled or run.
Schema 27 / history schema 4 / website metadata 3; no new Swift files. Restore points RP-2026-11-26-V00 (before), -V14, -V19, -VFINAL (handoff).
Summary and Codex starting points: `docs/reviews/LANE-V-SUMMARY-2026-11-26.md`. Owner decisions: `docs/reviews/LANE-V-OWNER-DECISIONS-2026-11-26.md`
(not yet applied to OPEN_DECISIONS.md). Per-lane reports: `docs/reviews/LANE-V*-review-2026-11-26.md`. Suggested first checks: LANE-V14e, then V19–V21.
Owner handed the tree to Codex at 11:28 PM EST; Code Forge is paused.

## Lane R review — November 26, 2026 6:07–6:50 PM EST (all batches after batch 17, unverified, complete)

Review of batch 18 part 1 and lanes A–I by seven reviewers. Summary, the 60 test selectors and the per-lane reports:
`docs/reviews/LANE-R-SUMMARY-2026-11-26.md` and `docs/reviews/LANE-R{A,B,C,D,E,H,I}-review-2026-11-26.md`.
Restore point `RP-2026-11-26-R01` was taken before any review edit; the lane E schedule was off and no other lane
wrote during the review. Still document schema 27, persisted-history schema 4, website metadata version 3.

| File | Change (owner in the write ledger) |
|---|---|
| `SiteForge/DocumentModel.swift` | D05 `CollectionImport` fixes (skipped rows release their address, lookups built once, problem list capped at 1,000, empty address derived from the title, quoted line breaks stored as LF, JSON BOM) (RD); `SiteTranslationEditing.transitionCommands` handles Make Default + Remove (RE); `CanonicalGraphReferences.assets` includes translated images (RE); `MediaPlaybackEditing.prepare` validates the draft (RB); `DocumentMigrations` step summaries and requirement IDs (RI). |
| `SiteForge/ProjectPackage.swift` | `ProjectComparer.compare`: one "Languages" entry, "Build settings" entry, "Other project data" fallback (RA, RE); `ComponentLibraries.updating` keeps every delivered identity (RA); `ProjectPackageStore.storedDocument(in:)` moved out of a `private extension` (RI, compile error). |
| `SiteForge/PackagedSiteTemplate.swift` | Template and new-project resource checks cover fonts and media via `ProjectCreationResources.storedFiles(in:)` (RB). |
| `SiteForge/CanvasRendererCore.swift` | Nested pages rewrite ` poster="assets/` (RH); hidden rule on every page with the interaction runtime (RC); `assets-unused` counts media (RB). |
| `SiteForge/DecorativeEffects.swift`, `DecorativeEffectsInspector.swift` | Overlays ignore visibility conditions, Show/Hide go through the overlay stack, condition decides first render, new warnings `overlay-condition-ignored` and `interaction-container-flat`, comment fix (RC, RH). |
| `SiteForge/ClipboardTransfer.swift` | Translated images carried and remapped on paste (RE). |
| `SiteForge/CommandKernel.swift` | `historyList()` save-drop rule matches the store, duplicate cancellation check removed (RI). |
| `SiteForge/WorkspaceShellModel.swift` | Coalescing ends on page switch and selection change; history jump pages and announcement; no page switch inside a component definition (RI); RTL refusal announced only on the selection (RE); Video & Audio shared state and media diagnostics (RB). |
| `SiteForge/WorkspaceShellView.swift` | Comparison task passes only Sendable values (RA); library row labels (RA); Collections editor validation once per pane, field labels (RD); Languages picker labels (RE); Check Website findings first (RH); Site menu Video & Audio…, root media sheet (RB); history row accessibility (RI). |
| `SiteForge/CanvasSettings.swift`, `BrowserPreview.swift` | Settings › Project Reset keeps build settings; repair button focusable (RH). |
| `SiteForge/ProjectResources.swift` | Five `MediaAssetOperation` cases (RB). |
| `SiteForge/DocumentLifecycle.swift` | Duplicate cancellation check removed (RI). |
| Tests | 5 new methods (`TransformModelTests` 1, `PersistedHistoryTests` 2, `ProjectResourceTests` 2); 12 changed, listed in the summary. |
| `docs/architecture-decisions/` | New ADR-0064 (lane C review fixes) and ADR-0073 (collection file import); review notes in ADR-0040, 0041, 0051, 0100, 0130, 0131, 0132. |
| `docs/OPEN_DECISIONS.md` | Was iCloud-renamed to `OPEN_DECISIONS 2.md` at 6:05 PM; renamed back at 6:22 PM with identical bytes. One lane R sentence appended to the implementation status lines of OD-035, 037, 038, 039, 042, 043, 045, 046. |

New selectors:

```
SiteForgeTests/TransformModelTests/testInteractionOutputHiddenRuleFirstRenderOverlayConditionsAndStaticLayoutContainers
SiteForgeTests/PersistedHistoryTests/testCollectionImportReadsCSVAndJSONMapsFieldsAndChecksEveryRow
SiteForgeTests/PersistedHistoryTests/testCollectionImportRefusesBrokenFilesAndStaysBounded
SiteForgeTests/ProjectResourceTests/testProjectCreationResourcesRequireEveryFontAndMediaFile
SiteForgeTests/ProjectResourceTests/testFontAndMediaEditsRestoreFromPersistedHistory
```

New finding codes: `overlay-condition-ignored`, `interaction-container-flat` (warnings). No new accessibility
identifiers that need UI-timing entries, so `scripts/ci-ui-timings.txt` is unchanged.

Cross-checks after all reviewers finished: balance and duplicate check on every changed Swift file returned no issue;
every identifier added since batch 17 is declared or already used; argument labels of calls to project functions
match a declaration; no `switch` without `default` misses a case added since batch 17; no file outside the ledger
changed.

Suggested first checks: the project builds in Swift 6 language mode with complete concurrency checking (from the
restore-point copy of `SiteForge.xcodeproj`); `SupportSettingsTests.swift` was never readable on Windows and the
flag registry now has 5 entries; each per-lane report's "Suggested first checks" list.

## Batch E08 — November 26, 2026 (right-to-left canvas layout, OD-038 / SF-1007, SF-1506, unverified, complete)

Decision record: ADR-0086 (Proposed). Restore point `RP-2026-11-26-E08` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27 and persisted-history schema 4; website metadata unchanged (version 3);
no new `CanonicalDocument` or `DocumentNode` key, no new command, no new flag.
Second half of OD-038 part 4c.

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New section before the CMS collections section: `SiteRightToLeftCanvasLayout` (`statusNote`, `transformRefusal`, `isMirrored(showing:in:)`, `mirrored(_:page:breakpoint:viewportWidth:)`, private `childRule`). `SiteCanvasLanguage.status` uses `statusNote` for a right-to-left language. |
| `SiteForge/WorkspaceShellModel.swift` | `WorkspaceScenePreparationRequest.mirrorsLayoutRightToLeft` (init parameter defaulted to `false`). `WorkspaceScenePreparationWorker.prepare`: `unmirroredGeometry`, then `resolvedGeometry` mirrored when requested. `scheduleScenePreparation` passes `canvasMirrorsRightToLeft`. New in the canvas-language section: `canvasMirrorsRightToLeft`, private `refuseMirroredCanvasTransform()`; called first in `beginPointerTransform(at:)` and `beginTransform(_:provenance:)`. |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | 1 new test before the E07 canvas-language test; uses the existing `siteTranslationFixture()`. |
| `docs/architecture-decisions/ADR-0086-right-to-left-canvas-layout.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-038 implementation status line. |

New selector:

```
SiteForgeTests/PersistedHistoryTests/testSiteRightToLeftCanvasLayoutMirrorsLaidOutChildrenLikeExportDirection
```

No new accessibility identifier and no UI test, so `scripts/ci-ui-timings.txt` is unchanged.

Suggested first checks: the `let resolvedGeometry: [NodeID: InsertionGeometry] = if request.mirrorsLayoutRightToLeft,
let activePage { … } else { unmirroredGeometry }` expression; `let flow: Bool = switch parent.kind` covering every
`NodeKind`; the `(flow: Bool, navigation: Bool)` tuple return; that `refuseMirroredCanvasTransform` (private, declared in
the canvas-language section) is reachable from `beginTransform`; that `lastTransformAnnouncement` (private(set)) is
assigned inside the type; that the E07 test's `contains("right to left")` still passes with the new status text; and
that no existing transform or keyboard-nudge test shows a right-to-left language.

## Batch A04 — November 26, 2026 (feature flags for Compare Versions and Component Libraries, unverified, complete)

Owner decision 2026-11-26 6:01 PM EST: one flag each, on by default.
Restore point `RP-2026-11-26-A04` was taken before this batch (lane E batch
E08 was in progress). No document, package, history or clipboard change.

| File | Change |
|---|---|
| `SiteForge/SupportSettings.swift` | `FeatureFlagID.versionComparison` (`versions.compare`) and `FeatureFlagID.componentLibraries` (`components.shared-libraries`) after `siteLanguages`; two `FeatureFlagRegistry.definitions` entries after Site languages (default on, introduced 2026-11-26, remove by 2027-03-31, SF-1306 / SF-0906). |
| `SiteForge/WorkspaceShellView.swift` | `SiteForgeCommands`: Compare Versions… and Component Libraries… each inside `if features.isEnabled(…)`. `ProjectSnapshotsSheet` (lane E): the row's Compare button inside `if FeatureFlagStore.shared.isEnabled(.versionComparison)`. |
| `SiteForge/WorkspaceShellModel.swift` | `presentProjectComparison` and `presentComponentLibraries` return early when their flag is off. |
| `docs/architecture-decisions/ADR-0040-version-comparison.md`, `ADR-0041-shared-component-libraries.md` | Flag lines replace "No feature flag". |

No new tests; `Tests/SiteForgeTests/SupportSettingsTests.swift` was not read
(iCloud online-only placeholder on this PC), so any test there that counts
registry entries or lists flag identifiers may need the two new flags.

Suggested first checks: that test file; `FeatureFlagRegistry.issues(in:today:)`
is empty; `ProjectSnapshotsSheet` reads the shared store without observing it
(the button appears or disappears the next time the sheet is shown).

## Batch A03 — November 26, 2026 (shared component libraries, OD-046 / SF-0906, unverified, complete for the approved first slice)

Decision record: ADR-0041 (Proposed). Restore point `RP-2026-11-26-A03` was
taken before this batch (other lanes may have been mid-batch). No document
schema, package version, history, clipboard or feature-flag change; the
project record is the new optional package member `libraries/index-v1.json`.

| File | Change |
|---|---|
| `SiteForge/ProjectPackage.swift` | New at the end, after `ProjectComparer`: `ComponentLibraryIdentifierDomain`, `ComponentLibraryID`, `ComponentLibraryVersion` (parse, `initial`, `nextMinor`, Comparable, string Codable), `ComponentLibraryFile` (format v1, exact keys, 4 MiB), `ComponentLibraryContent` (`digest()`, `comparisonDocument(id:)`), `ComponentLibraryPublication`, `ComponentLibraryKnownVersion`, `ComponentLibraryImport`, `ComponentLibraryIndex` (v1, exact keys, custom `encode` writing `published` as null, `validate()`), `ComponentLibraryError`, `ComponentLibraryStatus`, `ComponentLibraryRow`, `ComponentLibraryUpdatePreview`, `ComponentLibraryOperation`, `ComponentLibraryDiagnosticRecord`, `ComponentLibraries` (`validatedName`, `index`, `protectedIdentifiers`, `readOnlyViolation`, `content`, `status`, `rows`, `exporting`, `reading`, `importing`, `previewingUpdate`, `updating`, `detaching`, `removingAll`). |
| `SiteForge/CommandKernel.swift` | `DocumentSession.commitGuard` after `authoringTransform`; `execute` passes it to `commit(…, check:)`; `commit` calls `check?(committedDocument, draft)` after the component transition checks (undo/redo pass none). |
| `SiteForge/DocumentLifecycle.swift` | `init` installs `session.commitGuard`. Before `noteSnapshotsChanged()`: `libraryDiagnostics`, `libraryDiagnosticRecords`, `componentLibraryIndex()`, `componentLibraryRows()`, `exportComponentLibrary(named:version:write:)`, `importComponentLibrary(_:)`, `previewComponentLibraryUpdate(_:)`, `updateComponentLibrary(_:)`, `detachComponentLibrary(_:)`, `removeAllComponentLibraryRecords()`, private `checkLibraryCopies(from:to:)` (cached by record bytes), `performLibraryOperation`. |
| `SiteForge/WorkspaceShellView.swift` | New private `ComponentLibrariesSheet` before `RecoveryCandidateBar` (after the A02 comparison types). Workspace `.sheet(isPresented: $state.isComponentLibrariesPresented)` after the comparison sheet. File menu **Component Libraries…** after Compare Versions…. |
| `SiteForge/WorkspaceShellModel.swift` | `isComponentLibrariesPresented`, `presentComponentLibraries()` after `presentProjectComparison`. |
| `Tests/SiteForgeTests/ProjectPackageTests.swift` | 1 new test before `testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded`. |
| `Tests/SiteForgeTests/DocumentLifecycleTests.swift` | 1 new test before the private `awaitProjectComparison(_:)`. |
| `docs/architecture-decisions/ADR-0041-shared-component-libraries.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-046 implementation status line. |

New selectors:

```
SiteForgeTests/ProjectPackageTests/testComponentLibrariesExportImportReadOnlyUpdateCompareAndDetach
SiteForgeTests/DocumentLifecycleTests/testComponentLibraryImportIsOneUndoableStepAndCopiesStayReadOnlyUntilDetached
```

New accessibility identifiers: `libraries.sheet`, `libraries.recordFailure`,
`libraries.removeAll`, `libraries.empty`, `libraries.import`,
`libraries.update.<id>`, `libraries.detach.<id>`, `libraries.review`,
`libraries.review.summary|removed|changes|apply|cancel`,
`libraries.export.name|version`, `libraries.export`, `libraries.status`,
`libraries.close`. No UI tests were added, so `scripts/ci-ui-timings.txt` is
unchanged.

Suggested first checks: the `commitGuard` closure installed from the
main-actor controller (same shape as the existing `authoringTransform`
installs); existing tests that build a `DocumentLifecycleController` and then
edit component definitions (the guard returns early without a
`libraries/index-v1.json` member); whether `InsertPageCommand` accepts a
component definition page at the end of the list and `RenamePageCommand` on a
definition (both used by the lifecycle test); `withCopy.validate()` for the
hand-built instance in the package test; `ComponentLibraryContent.digest()`
encoding `DocumentPage` without decoder/encoder user info; the
`confirmationDialog(_:isPresented:presenting:actions:message:)` overload and
`.onReceive(session.$document)` in `ComponentLibrariesSheet`.

## Batch E07 — November 26, 2026 (language on the canvas and in Local Preview, OD-038 / SF-1007, SF-1506, unverified, partial)

Decision record: ADR-0085 (Proposed). Restore point `RP-2026-11-26-E07` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27 and persisted-history schema 4; website metadata unchanged (version 3);
no new `CanonicalDocument` or `DocumentNode` key and no new command. First half
of OD-038 part 4c; right-to-left canvas layout is the second half.

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New section before the CMS collections section: `SiteCanvasLanguageOption`, `SiteCanvasLanguage` (`textEditingRefusal`, `options(_:)`, `shownLocale(_:in:)`, `displayedDocument(_:showing:in:)` → `SiteLanguageOutput.translatedDocument`, `status(showing:in:)`), `SiteCanvasLanguageDiagnostic`. |
| `SiteForge/WorkspaceShellModel.swift` | New MARK section before the snapshots sheet section: `canvasLanguageLocaleID`, `canvasLanguageAnnouncement`, `lastCanvasLanguageDiagnostic`, `previewLocaleID`, private `canvasRenderPlanLocaleID`, `canvasLanguageOptions`, `canvasShownLocaleID`, `canvasDisplayedDocument`, `canvasLanguageStatus`, `previewLanguageName`, `showCanvasLanguage(_:)`, private `refuseCanvasLanguage`. `scheduleScenePreparation` renders the displayed document, captures `requestLocaleID`, throws `.staleResult` for a plan of another language and records `canvasRenderPlanLocaleID`. Document-boundary reset clears both. `openPreview`/`refreshPreview` wait for a plan of the shown language and record `previewLocaleID`; Refresh's "already current" check includes it; `preparePreviewRuntime` compiles `canvasDisplayedDocument` and drops a runtime of another language. `beginTextEditing(nodeID:provenance:)` refuses while a language is shown. |
| `SiteForge/WorkspaceShellView.swift` | New `private struct CanvasLanguageBar` before `CanvasPlaceholderView`; `CanvasPlaceholderView` gets `@ObservedObject var features: FeatureFlagStore = .shared` and shows the bar after the isolation breadcrumb. `LocalPreviewView` shows the captured language after the page menu. |
| `SiteForge/SupportSettings.swift` | `siteLanguages` flag summary mentions the canvas and Local Preview (no other change). |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | 1 new test before the per-language export test; uses the existing `siteTranslationFixture()`. |
| `docs/architecture-decisions/ADR-0085-site-language-on-canvas.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-038 implementation status line. |

New selector:

```
SiteForgeTests/PersistedHistoryTests/testSiteCanvasLanguageShowsALanguageAsExportedWithoutChangingTheDocument
```

New accessibility identifiers (no UI test added, so `scripts/ci-ui-timings.txt` is
unchanged): `canvas.language.bar`, `canvas.language`, `canvas.language.default`,
`canvas.language.status`, `preview.language`.

Suggested first checks: `Picker("Canvas Language", selection:)` with
`SiteLocaleID?.none` / `.some(id)` tags; `Binding(get:set:)` with `_ = state.showCanvasLanguage($0)`;
the multi-clause `if features.isEnabled(.siteLanguages) || …, … {}` in `CanvasPlaceholderView.body`
staying within the type-checker limit; that the defaulted `features` property keeps
`CanvasPlaceholderView(state:focus:tabRouter:compact:)` callable; `guard canvasShownLocaleID ==
requestLocaleID else { throw CanvasRendererError.staleResult }` inside the adoption `do` (caught by the
existing `.staleResult` branch); that existing Preview tests still pass the new
`canvasRenderPlanLocaleID == canvasShownLocaleID` guard (both `nil` without languages); the Arabic string
literal in the test; and that `try session.undo()` after removing a language restores the shown language.

## Batch H03 — November 26, 2026 (build settings, per-file report and budget/policy findings, OD-042 / SF-1208 / SF-1211, unverified, complete)

Decision record: ADR-0122 (Proposed); new open decision OD-120 (default budgets and release policy,
recommended default in use). Restore point `RP-2026-11-26-H03` was taken before this batch (other lanes may
have been mid-batch). Still document schema 27 and persisted-history schema 4; website metadata unchanged
(version 3); no new `CanonicalDocument` or `DocumentNode` key and no new command: build settings are a new
optional `build` key inside `ProjectPreferences` (version stays 1) and use `document.projectPreferences.set`.

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | `ProjectPreferences.build` (init parameter, `isEmpty`, `isValid`, `isStructurallyValid` rejects an empty build record, coding key `build`, null rejected). New after `ProjectPreferences` (before `ProjectPreferenceID`): `BuildProfileSettings`, `BuildReleasePolicy`, `BuildSettingID`, `BuildBudgetKind`, `BuildSettingsResolver`. |
| `SiteForge/TransformModel.swift` | `ProjectPreferencesEdit.build(_:)`; `ProjectPreferencesError.invalidBuildBudget` (+ description); `ProjectPreferencesCommandRegistry.prepare` handles `.build` and refuses a new invalid budget. |
| `SiteForge/CanvasSettings.swift` | `ProjectSettingsStore.category`: `.invalidBuildBudget` → `invalid-value`. |
| `SiteForge/CanvasRendererCore.swift` | New section before `LocalBuildProfile`: `BuildSettingsResolution`, `StaticOutputFileKind`, `StaticBuildOutputSummary` (+ `Row`, `Total`), `StaticBuildBudgetAudit`, `StaticBuildRepairAction`, `BuildSettingsDiagnostic`. `StaticBuildCompiler.compile`: `affectedOutputNodes` filled in the image and media loops; budget findings after the reference audit; `release-policy-warnings` after `publishing-excluded`. |
| `SiteForge/WorkspaceShellModel.swift` | `synchronizeProjectPreferences` applies a saved profile; after `commitProjectPreferences`: `buildSettingsStatus`, `lastBuildSettingsDiagnostic`, `saveBuildSettings(_:reviewed:operation:)`, `buildRepairAction(for:)`, `applyBuildRepair(_:)`, private `recordBuildSettings`, `buildSettingsCategory`. |
| `SiteForge/WorkspaceShellView.swift` | `StaticBuildDiagnosticsView`: `StaticBuildSettingsBox` after Status, `StaticBuildOutputFilesBox` after Stylesheet size, findings pass `repairAction:` / `applyRepair:`. New private structs `StaticBuildOutputFilesBox`, `StaticBuildSettingsBox` (explicit inits) after the view. |
| `SiteForge/BrowserPreview.swift` | `StaticBuildFindingRepairRow`: optional `repairAction` and `applyRepair` (defaults keep Preview's call unchanged) and a repair button. |
| `Tests/SiteForgeTests/CanvasRendererTests.swift` | 1 new test after the H02 test. |
| `Tests/SiteForgeTests/CanvasSettingsTests.swift` | 1 new test before the Settings Project pane test. |
| `docs/architecture-decisions/ADR-0122-build-settings-and-budgets.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-042 implementation status line (lane H); new OD-120 section at the end. |

Output change: none. Every output file of both profiles is byte-identical with and without build settings
(asserted). New findings can appear: `budget-page-exceeded`, `budget-asset-exceeded`,
`budget-total-exceeded` (warnings, SF-1211-003, OD-120 defaults 256 KB / 5 MB / 50 MB) and
`release-policy-warnings` (error, only when a project chooses "Block Static Release on warnings").

New selectors:

```
SiteForgeTests/CanvasRendererTests/testBuildSettingsResolveBudgetsPerFileReportAndReleasePolicy
SiteForgeTests/CanvasSettingsTests/testBuildSettingsSaveUndoRedoRepairsAndStaleReview
```

New accessibility identifiers: `build.settings`, `build.settings.profile`, `build.settings.budget.page|asset|total`,
`build.settings.policy`, `build.settings.save`, `build.settings.revert`, `build.settings.reset`,
`build.settings.status`, `build.settings.stale`, `build.outputFiles`, `build.outputFiles.list`,
`build.finding.repairAction.<action>.<finding id>`. No UI tests were added, so `scripts/ci-ui-timings.txt` is
unchanged.

Suggested first checks: `@State private var draft: BuildSettingsDraftState? = nil` with the explicit inits
of the two new private views (`self.state = state` on `@ObservedObject`); `.tag(LocalBuildProfile?.none)` /
`.tag(Int?.some(…))` against `Binding<…?>` selections; `var values: [Int] = switch kind { … }` in
`budgetChoices`; `case .raiseBudget(let kind, let kilobytes)` patterns against the labeled associated value;
`StaticBuildFindingRepairRow` memberwise init with the two new defaulted `var`s after `reveal`;
`LocalBuildReport(…, deferredCapabilities: [], outputFiles: …)` skipping `cssReports`; the
`affectedOutputNodes` dictionary being in scope inside the compile `do` block; `ByteCountFormatter`
`.binary`; that `ProjectSettingsStore.reset()` (Settings › Project) now also drafts removing build settings;
whether any existing test compiles a site over the default budgets (it would now see a warning);
`SupportSettingsTests.swift` is unreadable from Windows and was not checked.

## Batch F01 — November 26, 2026 (project video and audio, OD-045 / SF-0803, unverified, complete)

Decision records: ADR-0100 (Proposed); OD-100 opened (16 MB per-file limit,
recommended default: keep it). Restore point `RP-2026-11-26-F01` was taken
before this batch (other lanes may have been mid-batch). Lane F took this item
over from lane B (B3). Still document schema 27 and persisted-history schema 4;
website metadata unchanged; no new node kind (Image media mode instead).

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New `MediaAssetKind`, `MediaAssetFormat` (`kind`, `mediaType`, `fileExtension`), `MediaAsset` (exact keys, optional `language`, `isValidLanguage`, `isValid`, `validate`, static `validate(_:)`), `CanonicalMediaPlayback` (`namespace`, `assetKey`, `captionsKey`, `Setting`, `keys`, `resolve`, `validate(_:media:)`, `keepingAvailable`, `provenance`, `explanation`), `MediaPlaybackEditing.prepare`, `MediaAssetEditing` (`prepare`, `usageCount`). `CanonicalDocument.mediaAssets` (optional key `mediaAssets`, written only when not empty; init parameter `mediaAssets: []` last; accepted by the strict optional-key check). `validate()` calls `MediaAsset.validate`, refuses media/image ID collisions and calls `CanonicalMediaPlayback.validate` per node. Schema gate below 27. `ModelValidationError.invalidMediaAsset`, `.invalidMediaPlayback` + messages. |
| `SiteForge/CommandKernel.swift` | `CommandName.setMediaAssets` (`document.mediaAssets.set`), `SetMediaAssetsCommand` (exact keys), `DocumentCommand.setMediaAssets` in `minimumPersistedHistorySchema` (4), `name`, `targets`, descriptor ("Edit Video and Audio"), availability, apply/inverse. |
| `SiteForge/PersistedHistory.swift` | Payload check for `setMediaAssets` (`documentID`, `mediaAssets`). |
| `SiteForge/ProjectPackage.swift` | Snapshot restore: media resources must be available; `setMediaAssets` appended when media differ. `ProjectComparer.compare` "Video and audio files"; `sameUncomparedContent` aligns `mediaAssets`. |
| `SiteForge/PackagedSiteTemplate.swift` | Template creation copies `mediaAssets`. |
| `SiteForge/ClipboardTransfer.swift` | `preparePaste` drops playback properties whose file the destination lacks (`CanonicalMediaPlayback.keepingAvailable`). |
| `SiteForge/ProjectResources.swift` | `ProjectImageResourceSnapshot` also carries media resources. New `MediaImportError`, `ProjectMediaFormatSniffer` (`knownExtensions`, `format(of:fileExtension:)`), `PreparedMediaImport`, `MediaImportWorker`, `ProjectMediaOutput` (`references`, `exportCandidates`, `exportedPaths`, `findings`). `StaticAssetExportPlanner` accepts the seven media types with a matching signature → `assets/<sha>.mp4|webm|mp3|m4a|ogg|wav|vtt`. |
| `SiteForge/CanvasRendererCore.swift` | `InternalStaticImage.media` (defaulted `nil`), new `InternalStaticMedia`. `InternalDocumentRenderTreeCompiler.compile(…, mediaAssets:, mediaOutputPaths:)` (defaulted, last). `staticImage(for:outputPaths:assets:media:mediaPaths:)` (defaulted) and private `staticMedia`. `SafeHTMLEmitter.emitImage` emits media through new private `emitMedia` and `isVerifiedMediaPath`. `MultiPageStaticBuildPlanner.plan(…, mediaOutputEntries:)` (defaulted, last). `StaticBuildCompiler.compile` (descriptor overload) packages used media after the image loop and before the error guard, with `media-missing`, `media-invalid` (errors) and `media-video-no-captions` (warning). |
| `SiteForge/BrowserPreview.swift` | `WebsitePreviewHTTPContent.Response.contentRange` (defaulted), 206/416 reasons, `Accept-Ranges: bytes`; media MIME types; single `Range` request handling; new static `byteRange(_:count:)`. |
| `SiteForge/LaunchExperience.swift` | New `NativeMediaOpenPanel.chooseMedia(allowsMultiple:)`. |
| `SiteForge/WorkspaceShellModel.swift` | `mediaImportWorker`, `isImportingMedia`, `lastMediaAnnouncement`, `mediaAssets`, `mediaUsageCount(_:)`, `mediaResourceIsAvailable(_:)`, `importMedia()`, `importMediaURLs(_:)`, `replaceMediaFile(_:)`, `replaceMediaURL(_:for:)`, `updateMediaAsset(_:)`, `removeMediaAsset(_:)`, `setMediaPlayback(_:nodeID:)`. |
| `SiteForge/WorkspaceShellView.swift` | Assets: `showingProjectMedia`, Video & Audio… button + sheet. New private `ProjectMediaSheet`, `ProjectMediaRow`, `MediaPlaybackInspector` (shown in the Image Inspector for one selected Image). |
| `Tests/SiteForgeTests/ProjectResourceTests.swift` | 4 new tests and private `MediaTestFixture` / `mediaFixture()` before `makeFixture()`. |
| `docs/architecture-decisions/ADR-0100-project-video-and-audio.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-045 implementation status line; new OD-100 at the end. |

New selectors:

```
SiteForgeTests/ProjectResourceTests/testMediaModelIsStrictValidatedOmittedWhenEmptyAndUndoable
SiteForgeTests/ProjectResourceTests/testMediaPlaybackRulesProvenanceAndOneUndoableEditPerChange
SiteForgeTests/ProjectResourceTests/testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound
SiteForgeTests/ProjectResourceTests/testMediaImportKeepsOriginalBytesAndMediaSurvivesSaveAndReopen
```

New accessibility identifiers: `assets.media`, `media.import`, `media.empty`,
`media.status`, `media.name.<id>`, `media.missing.<id>`, `media.language.<id>`,
`media.replace.<id>`, `media.remove.<id>`, `inspector.media`,
`inspector.media.asset`, `inspector.media.captions`, `inspector.media.loop`,
`inspector.media.muted`, `inspector.media.autoplay`,
`inspector.media.explanation`, `inspector.media.missing`,
`inspector.media.status`. No UI tests were added, so
`scripts/ci-ui-timings.txt` is unchanged.

Suggested first checks: exhaustive `switch` over `DocumentCommand` and
`CommandName` elsewhere (tests that list all command names, e.g.
`CommandKernelTests` descriptor test, and any persisted-history fixtures);
the export test's exact attribute order in `emitMedia`
(`controls preload="metadata" muted playsinline autoplay poster=…`); that the
Image fixture in `mediaFixture()` passes `document.validate()` (layout keys
only, no structural defaults); `ProjectSnapshots.restoreCommand` returning
exactly `.batch([.setMediaAssets(…)])` for a media-only difference;
`MediaPlaybackEditing.prepare` relying on `CommandRegistry().availability` for
the autoplay/captions refusals; `Data(found.dropFirst(…).prefix(…))` slice
indices in the range reply; `MediaImportWorker`'s `URLResourceValues.fileSize`
pre-check; the `Binding<AssetID?>` pickers and `.tag(AssetID?.some(…))` in
`MediaPlaybackInspector`; `mediaResourceIsAvailable` reading
`lifecycle.staticBuildResourceSnapshot().optionalMembers` on the main actor.

## Batch B04 — November 26, 2026 (SVG and font gaps, OD-045 / SF-0804, SF-0805, unverified, complete)

Decision records: ADR-0050 and ADR-0051 amendments. Restore point
`RP-2026-11-26-B04` was taken before this batch (other lanes may have been
mid-batch). No schema, command or history change.

| File | Change |
|---|---|
| `SiteForge/ProjectResources.swift` | New `MediaAssetOperation` (with `requirementID`), `MediaAssetDiagnosticRecord` (hashed asset token, duration, failure category, count-only detail), `ProjectFontCanvasRegistration` (`folder`, `register(_:format:contentHash:)` via `CTFontManagerRegisterFontsForURL`, process scope). |
| `SiteForge/WorkspaceShellModel.swift` | `mediaAssetDiagnostics`, `mediaAssetDiagnosticRecords`, private `recordMediaAsset(_:)`; records in `importImageURLs` (SVG only), `recolorSVGAsset`, `importFontURLs`, `updateFontAsset`, `removeFontAsset`. `isProjectFontsPresented`, `svgRecolorAssetID`, `canManageProjectFonts`, `presentProjectFonts()`, `canRecolorSVG(_:)`, `presentSVGRecolor(_:)`. Private `canvasRegisteredFontHashes`, `registerProjectFontsForCanvas(_:refreshScene:)` called from the document sink and at the end of `init`. |
| `SiteForge/WorkspaceShellView.swift` | Root sheets for `ProjectFontsSheet` and `SVGRecolorSheet` next to the Collections sheet; menu items Project Fonts… and Recolor Selected SVG… after Collections…; `AssetRow` and the Assets library use the shared state (local `isRecoloring` / `showingProjectFonts` and their sheets removed); canvas wording in the fonts sheet and Inspector summary. |
| `Tests/SiteForgeTests/ProjectResourceTests.swift` | 1 new test before `makeFixture()`. |
| `docs/architecture-decisions/ADR-0050-…`, `ADR-0051-…` | Amendment B04 sections. |
| `docs/OPEN_DECISIONS.md` | OD-045 implementation status line. |

New selector:

```
SiteForgeTests/ProjectResourceTests/testMediaAssetCommandsShareStateAndRecordContentFreeDiagnostics
```

Suggested first checks: `CTFontManagerRegisterFontsForURL` with WOFF2 files
and its deprecation status on the deployment SDK;
`CTFontManagerError.alreadyRegistered.rawValue` compared with `CFErrorGetCode`;
`defer` blocks inside the `for` loops of the main-actor import tasks; the
`Binding(get:set:)` sheet for `svgRecolorAssetID`; that the init-time font
registration does not disturb tests that count temporary files.

Still open in SF-0804/SF-0805: 100/10,000-object performance fixtures (007),
UI tests (008), SVG title as automatic output alt text (kept as a suggestion),
snapshot comparison listing font changes (lane A).

## Batch E06 — November 26, 2026 (Inspector translations, OD-038 / SF-1007, SF-1506, unverified, partial)

Decision record: ADR-0084 (Proposed). Restore point `RP-2026-11-26-E06` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27 and persisted-history schema 4; website metadata unchanged (version 3);
no new `CanonicalDocument` or `DocumentNode` key and no new command. Part 4b of
OD-038; showing another language on the canvas/Preview is part 4c.

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New section before the CMS collections section: `SiteTranslationInspectorTarget`, `SiteTranslationInspectorRow` (`isMissing`), `SiteTranslationInspection` (`target(selectedNodeIDs:pageID:in:)`, `translatableLocales(_:)`, `locale(preferred:in:)`, `isRightToLeft(_:in:)`, `rows(for:localeID:in:)`, `missingTranslations(on:pageID:in:)`, `missingSummary(_:in:)`). |
| `SiteForge/WorkspaceShellModel.swift` | New MARK section after the Languages sheet section: `translationInspectorLocaleID`, `translationInspectorStatus`, `lastTranslationInspectorDiagnostic`, `canEditTranslations`, `translationInspectorTarget`, `translationInspectorEffectiveLocaleID`, `commitTranslation(_:field:nodeID:pageID:localeID:openingRevision:)`, private `recordTranslationInspectorDiagnostic`. Uses `documentSession.document`. |
| `SiteForge/WorkspaceShellView.swift` | `InspectorView`: new `@ObservedObject var features: FeatureFlagStore = .shared`; after `inspectorDetails(reader:)` in `inspectorContents`, the Translations section for the Content tab behind `features.isEnabled(.siteLanguages)`, `.id` includes node, language and document revision. New `private struct SiteTranslationInspectorView` before `StaticBuildDiagnosticsView`. |
| `SiteForge/SupportSettings.swift` | `siteLanguages` flag summary mentions the Inspector's Translations section (no other change). |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | 1 new test before the per-language export test; uses the existing `siteTranslationFixture()`. |
| `docs/architecture-decisions/ADR-0084-site-translation-inspector.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-038 implementation status line. |

New selector:

```
SiteForgeTests/PersistedHistoryTests/testSiteTranslationInspectorEditsOneElementUndoablyAndListsItsMissingTranslations
```

New accessibility identifiers (no UI test added, so `scripts/ci-ui-timings.txt` is
unchanged): `inspector.translation`, `inspector.translation.locale`,
`inspector.translation.<field>.explanation|value|apply|clear` (field = `text`,
`image.assetID`, `image.alt`; the image has no apply/clear buttons),
`inspector.translation.missing`, `inspector.translation.missing.<language id>`,
`inspector.translation.status`.

Suggested first checks: `TextField(row.resolution.value ?? "Translation", text:axis:)`
resolving to the `StringProtocol` overload; `Picker` with `String?` tags and the
`Binding<String?>` setter that commits; `.onExitCommand` on the vertical `TextField`;
`ForEach(rows, id: \.field)`; that the new `features` property keeps
`InspectorView(state:focus:)` callable and the extra `if let` keeps
`inspectorContents` within the type-checker limit; `catch SiteTranslationEditError.unchanged`
in `commitTranslation`; `String(describing:)` of an optional diagnostic in the test;
and that set-then-clear of an image translation leaves `pages` equal.

## Batch I03 — November 26, 2026 (history list, jump to a state, page-following Undo, SF-0307, unverified, complete)

Decision record: ADR-0132 (Proposed). Restore point `RP-2026-11-26-I03` was
taken before this batch. No document, package, history or snapshot schema change;
no new `CanonicalDocument` or `DocumentNode` key.

| File | Change |
|---|---|
| `SiteForge/CommandKernel.swift` | New `HistoryListItem` (before `TransactionCoalescingKey`). `DocumentSession`: `historyList()`, `nextUndoPageIDs`, `nextRedoPageIDs`, static `pageIDs(affectedBy:)`, `jump(toStateAfter:)` (before `flattenedCommands`). |
| `SiteForge/WorkspaceShellModel.swift` | `WorkspaceShellState`: `historyJumpFailure`, `historyItems`, `jumpToHistory(_:)`, private `followHistoryPage(_:)` (before `undo()`); `undo()` and `redo()` follow the changed page and return early after a page switch. |
| `SiteForge/WorkspaceShellView.swift` | `StatusBarView` shows `HistoryListButton`; new private views `HistoryListButton` and `HistoryListContent` (before `LocalPreviewView`). |
| `Tests/SiteForgeTests/CommandKernelTests.swift` | 1 new test before the I02 test. |
| `Tests/SiteForgeTests/DocumentLifecycleTests.swift` | 1 new test before the I01 test. |
| `docs/architecture-decisions/ADR-0132-history-list-and-page-following-undo.md` | New. |

New selectors:

```
SiteForgeTests/CommandKernelTests/testHistoryListMarksStepsSavingDropsAndJumpMovesBothWays
SiteForgeTests/DocumentLifecycleTests/testHistoryListJumpsAndUndoRedoFollowTheChangedPage
```

New accessibility identifiers `status.history`, `history.oldest`, `history.item`,
`history.failure` (no UI test), so `scripts/ci-ui-timings.txt` is unchanged.

Suggested first checks: `ordered.enumerated().map { index, row in … }` over labelled
tuples in `historyList()`; `id.flatMap { id in … }` shadowing in `jumpToHistory`;
`(try? documentSession.undo()) != nil`; the nested string literal inside the
announcement interpolation; `Button("…") { state.jumpToHistory(nil) }` (Bool result in
a Void action); existing unit and UI tests that undo an edit on another page and expect
the page to stay (Undo now switches to it); the status-bar width with the new History
button; that `state.selectPage` is accepted in a fresh `WorkspaceShellState`.

## Batch D04 — November 26, 2026 (collection list pages, OD-035 / SF-1003, unverified, complete)

Decision record: ADR-0072 (Proposed, updated). Restore point `RP-2026-11-26-D04`
(other lanes may have been mid-batch). Still document schema 27 and history
schema 4. Completes D3 (the plan had reassigned list pages to lane G as G1;
the owner gave them back to lane D at 5:11 PM, and the plan says so).

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New (after `CollectionTemplates`): `CollectionListSortDirection`, `CollectionList`, `CollectionListResolution`, `CollectionLists` (`pageRoute`, `pageLinkID`, `copyID`, `subtree`, `resolve`, `stylePages`, `linkRoutes`, `findings`, `diagnostic`; fileprivate `Placement`, `placements`, `expand`, `outputPages`). New `extension CollectionEditing` (`repeatableNodes`, `listBindableNodes`, `paginationNodes`, `addList`, `removeList`, `updateList`, `setListFilter`, `setListTextBinding`, `setListImageBinding`, `setListLinkBinding`, `replacingBinding`, `listPreview`). `ContentCollection.lists` (optional key, init parameter `lists: []`). `CollectionBindingTarget.link` + `CollectionBinding.link(_:)` (decoder accepts the bare key set for links). `CollectionIssue.Kind` + `list`, `duplicateListLayer`. `CollectionTemplateFinding` + `listID` and 8 list kinds. `CollectionTemplates`: `OutputPage.listPageNumber`, `itemLinkPageID`, `itemLinkRoutes`; `Compiled` is fileprivate and has `links`; binding checks moved to `compileBindings`, filling to `bind`/`setLink`; `outputPages` expands list pages; `findings` appends list findings. |
| `SiteForge/CanvasRendererCore.swift` | `MultiPageStaticBuildPlanner.plan`: adds `CollectionLists.linkRoutes` to `staticRoutes`; links and image sources are page-relative for every page in a folder (was: language trees only — this fixes root-relative links and `src` on D03 item pages); layout, motion, fluid, glass, container query and connected CSS read `stylePages`. `StaticBuildCompiler`: exports pictures shown only by list copies. |
| `SiteForge/WorkspaceShellView.swift` | `CollectionsEditorView`: new **Lists** tab (`listsPane`, `listEditor`, `listBindingRow`, `paginationPicker`, `limitBinding`, `updateList`, `addList`, `listPages`, `listFindings`, `newListLayers`, state `newListPageID`, `newListNodeID`). |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | 2 new tests before the custom code test. |
| `docs/architecture-decisions/ADR-0072-template-pages-and-bindings.md` | List pages, resolution, output, findings, relative links, editor. |
| `docs/OPEN_DECISIONS.md` | OD-035 implementation status line. |

New selectors:

```
SiteForgeTests/PersistedHistoryTests/testCollectionListRepeatsALayerPerItemFilteredOrderedAndPaginated
SiteForgeTests/PersistedHistoryTests/testCollectionListRecordIsStrictBoundedAndUndoable
```

No UI tests; `scripts/ci-ui-timings.txt` unchanged. New accessibility
identifiers start with `collections.lists`.

Suggested first checks: the D03 test still passing with page-relative
`src="../assets/…"` on item pages; the `styles.css` selector assertion for a
slot-1 copy (layout CSS must emit a rule per node); the fixture stack/link
nodes passing `document.validate()`; `href="…"` strings in the new test;
fileprivate `CollectionTemplates.Compiled` used from `CollectionLists`; the
nested `report`/`control` functions in `placements`; `Toggle` and `Stepper`
bindings in `listEditor`; the forgery closures built by `changingList`.

## Batch H02 — November 26, 2026 (static asset export: integrity manifest and references, OD-042 / SF-1206, unverified, complete)

Decision record: ADR-0121 (Proposed). Restore point `RP-2026-11-26-H02` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27 and persisted-history schema 4; website metadata unchanged (version 3);
no new `CanonicalDocument` or `DocumentNode` key; no new command.

| File | Change |
|---|---|
| `SiteForge/CanvasRendererCore.swift` | New section after the H01 CSS section: `StaticOutputCachePolicy`, `StaticOutputFileRecord`, `StaticOutputManifest` (`fileName` `siteforge-integrity.json`, `init(files:binaryFiles:)`, `init(plan:)`, `json`, `mismatchedPaths(in:)`), `StaticOutputReferenceAudit` (`unresolved(in:)`, `references(in:isStylesheet:)`, `resolves(_:from:written:)`). `LocalBuildReport.outputFiles` (new `var`, default `[]`). `LocalBuildProfileCompiler.compile`: Static Release adds `siteforge-integrity.json`; report carries the records for both profiles. `StaticBuildCompiler.compile`: `assets-unused` information after the language findings; per-file `output-reference-unresolved` warnings after compiling; `asset-oversized` has its own explanation and repair. `LocalStaticBuildWriter.write`: reads every staged file back before promotion. |
| `SiteForge/ProjectResources.swift` | `StaticAssetExportPlanner.plan`: the size check is split out of the type guard (negative → `corrupt`, over the limit → `oversized`); lane F's `mediaTypes` kept. |
| `Tests/SiteForgeTests/CanvasRendererTests.swift` | 1 new test after the H01 test. |
| `docs/architecture-decisions/ADR-0121-static-asset-integrity-manifest.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-042 implementation status line (lane H). |

Output change: Static Release writes one more file, `siteforge-integrity.json`. Development output
and all existing files of both profiles are unchanged; `manifest.txt` does not list the new file.

New selector:

```
SiteForgeTests/CanvasRendererTests/testStaticOutputIntegrityManifestCachePolicyAndReferenceAudit
```

New finding codes: `output-reference-unresolved` (warning), `assets-unused` (information);
`asset-oversized` can now occur. No accessibility identifiers or UI tests were added, so
`scripts/ci-ui-timings.txt` is unchanged.

Suggested first checks: the synthesized `Decodable` init of `StaticOutputManifest` next to its two
custom inits; `text.range(of:range:)` without `options:`; `guard try Data(contentsOf: safeOutputURL(…)) == …`
in the folder writer; `Dictionary(_:uniquingKeysWith:)` in `mismatchedPaths`; that the blank-project
assertion (`output-reference-unresolved` absent) holds, which means no generated page links a
stylesheet or script that is not written; whether any lane F media test expects `.unsupported` for an
over-limit file; tests that compile collection sites and assert on warnings (item pages at nested
routes will now get `output-reference-unresolved`).

## Batch I02 — November 26, 2026 (coalesced, named and bounded transactions, SF-0306, unverified, complete)

Decision record: ADR-0131 (Proposed). Restore point `RP-2026-11-26-I02` was
taken before this batch. No document, package, history or snapshot schema change;
no new `CanonicalDocument` or `DocumentNode` key.

| File | Change |
|---|---|
| `SiteForge/CommandKernel.swift` | New `TransactionCoalescingKey` (before `HistoryEntry`). `DocumentSession`: `coalescedTransactionCount`, `droppedTransactionCount`, private `coalescing`, `maximumUndoEntries` (1,000), `coalescingWindow` (1 s), `maximumCoalescedCommands` (256); `executeCoalescing(_:key:at:)`, `endCoalescing()`, `transactionName(for:)`, static `flattenedCommands(_:)`, private `trimUndoJournal()`. `execute`, `undo`, `redo`, `establishBaseline` and `installValidatedHistory` end coalescing; `execute` trims the journal. |
| `SiteForge/DocumentLifecycle.swift` | `session.endCoalescing()` before the history capture in Save/Save As and in autosave. |
| `SiteForge/WorkspaceShellModel.swift` | `commitTransform`: keyboard moves go through `executeCoalescing` keyed by the selection. |
| `Tests/SiteForgeTests/CommandKernelTests.swift` | 1 new test before `testComponentDefinitionTextDraftRetainsPairedEditsAndDetectsBindingReplacement`. |
| `docs/architecture-decisions/ADR-0131-coalesced-named-bounded-transactions.md` | New. |

New selector:

```
SiteForgeTests/CommandKernelTests/testCoalescedTransactionsAreOneUndoStepNamedBoundedAndPersistable
```

No accessibility identifiers or UI tests were added, so `scripts/ci-ui-timings.txt`
is unchanged.

Suggested first checks: the stored tuple `coalescing: (key: TransactionCoalescingKey, at: Date)?`
assigned with `(key, now)`; `commands.flatMap(flattenedCommands)` inside the static
function; `if provenance == .keyboard, case .move = preview.operation` in
`commitTransform`; that renaming a missing page throws (the test relies on it); the
nested local functions `name()` and `rename(_:key:after:)` in the `@MainActor` test;
runtime of the 1,004-command bounded-journal loop; any existing test that commits more
than 1,000 transactions and then expects to undo all of them; UI tests that nudge with
arrow keys and count Undo steps.

## Batch C04 — November 26, 2026 (lane C review fixes and spec gap list, OD-039 / SF-1101, SF-1105, unverified, complete)

Decision record: ADR-0063 (Proposed). Restore point `RP-2026-11-26-C04` was
taken before this batch (other lanes may have been mid-batch). No schema,
document, clipboard or project-file change.

Review of C01–C03 against the code they call (balance and duplicate checks
pass; root edits, `setProperty` availability, document validation order and
lane H's new release CSS optimizer were checked by reading). Lane H had
already updated the two release-CSS assertions to `StaticCSSOptimizer.minify`;
the optimizer keeps every lane C rule (rules with `:not(…)` or no object id
are never removed; motion rules name ids used in the HTML). The copy-path
remapping added by the cross-lane review (`CanonicalEventGraph.remappingTargets`)
keeps the C03 `variable`/`value` action fields because it decodes and
re-encodes `CanonicalInteraction`.

| File | Change |
|---|---|
| `SiteForge/DecorativeEffects.swift` | `EventGraphRuntime.javascript`: modal portal (placeholder comment, move to `<body>` while open, restore on close). `EventGraphOutput.findings`: new `interaction-action-unreachable` warning. |
| `SiteForge/DecorativeEffectsInspector.swift` | `InteractionInspector.interactionEditor`: inline note when actions follow Go To Page. |
| `SiteForge/CanvasRendererCore.swift` | `StaticBuildCompiler.compile`: interaction findings run on component-expanded pages. |
| `Tests/SiteForgeTests/TransformModelTests.swift` | `testRuntimeVariablesOverlaysOutputHydrationRuntimeAndDiagnostics`: unreachable-action case and two portal assertions. The glass test's doc comment, which the copy-path test had been inserted into, is back above the glass test (comment only). |
| `docs/architecture-decisions/ADR-0063-lane-c-review-fixes.md` | New. |
| `docs/OPEN_DECISIONS.md` | New OD-070 (variable scopes beyond the page) and OD-071 (later motion slices), both Open with recommended defaults. |

No new test selectors. New finding code: `interaction-action-unreachable`
(warning).

Spec gaps left in lane C (also listed as C5–C10 in the plan): overlay
placement relative to the trigger and arrow-key menu navigation (SF-1105);
binding text content to a variable (SF-1106); key-press triggers and a page
overview of interactions (SF-1101); session/URL variables (OD-070);
reusable transitions, scroll progress and parallax (OD-071); browser-run
tests of the generated runtimes (the browser harness files are not readable
on Windows). ADR-0060's note about line-based release de-duplication is
superseded by ADR-0120.

Suggested first checks: `element.before` / `replaceWith` on the moved modal
in Safari; the explicitly typed `reduce` closure in `findings`;
`ComponentGraphResolver.resolvedPage` returning the same node ids for pages
without instances (the C02/C03 finding assertions rely on it).

## Review B01–B02 — November 26, 2026 (quality pass on SVG and fonts, unverified)

No restore point (two small edits in one file; `RP-2026-11-26-B02` predates them).

| File | Change |
|---|---|
| `SiteForge/WorkspaceShellView.swift` | `SVGRecolorSheet`: report and preview are now `@State`, computed in `Task.detached` (`loadReport()`, `refreshPreview()` debounced 150 ms via `.task(id: hex)`), with a "Reading SVG…" progress row; the sheet no longer parses SVG on every body evaluation. `CanvasContentTileLayer.decodedTileImage` is now an instance method with a bounded per-layer `vectorImages: [Data: NSImage]` cache (cleared at 32 entries). |

Checked without change: every exhaustive `DocumentCommand` and
`ModelValidationError` switch includes the new cases; no production
`CanonicalDocument(…)` construction copies a full document field by field
(so none drops `fontAssets`); the package build path carries font resources
through `ProjectImageResourceSnapshot`; the existing typography test
expecting `"Georgia", system-ui` still holds (fallbacks default to empty).

Known gaps against SF-0804/SF-0805 (not built): Recolor SVG… and Project
Fonts… are not entries in the central command registry or menu bar
(006); no 100/10,000-object performance fixtures (007); SVG
`diagnosticSummary` is not yet recorded in a diagnostics buffer and there are
no UI tests (008); project fonts are not registered with CoreText for the
canvas; the SVG title is not used as an output alt-text fallback; snapshot
comparison (lane A) does not list font changes.

Suggested first checks: `.task(id:)` with `Task.detached` capturing `Data`
under the project's concurrency settings; `Data` as a dictionary key in the
tile layer.

## Batch H01 — November 26, 2026 (Static Release CSS optimization, OD-042 / SF-1204, unverified, complete)

Decision record: ADR-0120 (Proposed). Restore point `RP-2026-11-26-H01` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27 and persisted-history schema 4; website metadata unchanged (version 3);
no new `CanonicalDocument` or `DocumentNode` key; no new command.

| File | Change |
|---|---|
| `SiteForge/CanvasRendererCore.swift` | New section before `LocalBuildProfile`: `StaticCSSOptimizationReport` (`readable(path:css:)`, `savedBytes`, `summary`), `StaticCSSTraceEntry`, `StaticCSSOptimizer` (`optimize(_:path:usedIdentifiers:)`, `minify`, `usedIdentifiers(in:)`, `trace(_:nodeID:)`, nested `CSSFailure`, `Output`, fileprivate `CSSByte`, `CSSContext`, `CSSStatement`, `CSSCounts`, `CSSParser`). `LocalBuildReport.cssReports` (new `var`, default `[]`). `LocalBuildProfileCompiler.compile`: Development unchanged; Static Release replaces the line-based trim/de-duplication with `StaticCSSOptimizer.optimize` (used identifiers from `.html`/`.js` files). `StaticBuildCompiler.compile`: warning `css-optimization-skipped` (SF-1204-004) only when a stylesheet could not be optimized. |
| `SiteForge/WorkspaceShellView.swift` | `StaticBuildDiagnosticsView`: "Stylesheet size" group box after Status, identifier `build.cssSize`, shown when the last compilation has CSS reports. |
| `Tests/SiteForgeTests/CanvasRendererTests.swift` | 1 new test after `testStaticBuildCompilerProfilesAreDeterministicRedactedAndCancellationNeutral`. |
| `Tests/SiteForgeTests/TransformModelTests.swift` | The two Static Release assertions (overlay CSS lines, motion lines) now look for `StaticCSSOptimizer.minify(line)`. |
| `docs/architecture-decisions/ADR-0120-static-css-optimization.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-042 implementation status line (lane H appended). |

Output change (intended, SF-1204): Static Release `styles.css` is now minified on one line.
The old line-based de-duplication dropped every repeated line, including a second line that is
only `}` (for example the end of the dark-mode `@media` block when another multi-line block
followed), which produced unbalanced CSS. Development output and all HTML, scripts, assets and
manifests are byte-identical to before.

New selector:

```
SiteForgeTests/CanvasRendererTests/testStaticReleaseCSSOptimizerMinifiesDeduplicatesAndKeepsBlocksWhole
```

New finding code: `css-optimization-skipped` (only when optimization fails closed). New
accessibility identifier `build.cssSize`; no UI tests were added, so `scripts/ci-ui-timings.txt`
is unchanged.

Suggested first checks: access levels of the fileprivate nested types used by the private
`clean`/`deduplicated` helpers and by `CSSParser` methods; the `scan(_:_:)` closure type with
`_ index:` labels and the trailing closures that mutate captured locals in `split`, `firstIndex`
and the three minifiers; `guard let found = try read(until:)` returning a labeled tuple;
`StaticCSSOptimizationReport` memberwise init calls that skip defaulted members (`isOptimized:`
then `skippedReason:`); the multi-statement `map { file -> LocalStaticBuildPlan.File in … }` that
appends to `cssReports`; the multi-line test literal (indentation and interpolation) against the
expected one-line string; that the motion and overlay tests in `TransformModelTests` still pass
(their release CSS must not hit `css-optimization-skipped`); `SupportSettingsTests.swift` is
unreadable from Windows and was not checked for Static Release CSS assertions.

## Batch I01 — November 26, 2026 (document migration framework, SF-0309, unverified, complete)

Decision record: ADR-0130 (Proposed). Restore point `RP-2026-11-26-I01` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27, package versions 1/2, persisted-history schema 4, snapshot index
version 1; website metadata unchanged; no new `CanonicalDocument` or
`DocumentNode` key.

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New section after `DocumentSerializer`: `DocumentMigrationStep`, `DocumentMigrationRefusal` (`errorDescription`, `recoverySuggestion`, `diagnosticCategory`), `DocumentMigrationReport` (`needsMigration`, `addedPageCount`, `addedNodeCount`, `summary`, `stepLines`), `DocumentMigrationCandidate`, `DocumentMigrationDiagnosticRecord` (+ `Operation`), `DocumentMigrations` (`requirementIDs`, `steps` 1→27, `validateRegistry`, `path(from:)`, `dryRun`, `storedIdentifiers`). |
| `SiteForge/ProjectPackage.swift` | `ProjectPackageStore.storedDocument(in:)` (after `parseContainer`); `ProjectSnapshots.migrationBackupName(for:)` and `creatingMigrationBackup(of:schemaVersion:documentID:in:id:at:)` (after `creating`). |
| `SiteForge/DocumentLifecycle.swift` | `LoadedProject.migration` (defaulted `var`); `DocumentLifecycleBackend.read` runs `migrationCandidate(for:)` (new static) before history; `map` handles `DocumentMigrationRefusal`; controller `migrationReport`, `migrationNotice`, `migrationDiagnostics`, `migrationDiagnosticRecords`, private `adoptMigration(_:)` (called after adoption sets `project`), reset with the new-document state. |
| `SiteForge/WorkspaceShellView.swift` | Status bar label `status.migrationNotice` after the file-action notice. |
| `Tests/SiteForgeTests/ProjectPackageTests.swift` | 1 new test before `testUnknownOptionalMemberIsPreservedByteForByteAcrossRoundTrip`. |
| `Tests/SiteForgeTests/DocumentLifecycleTests.swift` | 1 new test before the private `makeController` helper. |
| `docs/architecture-decisions/ADR-0130-document-migration-framework.md` | New. |

New selectors:

```
SiteForgeTests/ProjectPackageTests/testDocumentMigrationRegistryIsContiguousAndDryRunReportsWithoutContent
SiteForgeTests/DocumentLifecycleTests/testLegacyOpenKeepsOriginalAsSnapshotBeforeUpgradedSaveAndBackupRestoresUndoably
```

New accessibility identifier `status.migrationNotice` (status bar, no UI test),
so `scripts/ci-ui-timings.txt` is unchanged.

Suggested first checks: `catch DocumentSerializationError.unsupportedSchema(let version)`
in `dryRun`; `try pageMembers.map { path -> Data in … }` in `storedDocument`; that
`LoadedProject(…, migration: migration)` still matches the memberwise init and no other
code constructs `LoadedProject`; that the schema-4 legacy-surface and other legacy
lifecycle tests still open (the dry run refuses only missing page/node identities);
that the raw-written golden package is accepted by the descriptor-bound durable read
in the lifecycle test; the `let detail = …` statement inside the status-bar `if let`;
that opening a legacy project still leaves `phase == .clean`.

## Batch E05 — November 26, 2026 (Languages sheet, OD-038 / SF-1007, SF-1506, unverified, partial)

Decision record: ADR-0083 (Proposed). Restore point `RP-2026-11-26-E05` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27 and persisted-history schema 4; website metadata unchanged (version 3);
no new `CanonicalDocument` or `DocumentNode` key. Part 4a of OD-038 (UI); the
Inspector translation field and RTL preview are part 4b.

| File | Change |
|---|---|
| `SiteForge/SupportSettings.swift` | `FeatureFlagID.siteLanguages` (`localization.site-languages`) and its `FeatureFlagRegistry` entry (default on, remove by 2027-03-31, SF-1007/SF-1506). |
| `SiteForge/WorkspaceShellModel.swift` | New MARK section before the named-snapshots section: `isLanguagesEditorPresented`, `languagesOpeningRevision`, `languagesStatus`, `lastLanguagesDiagnostic`, `canEditLanguages` (false while a component variant is open), `presentLanguagesEditor()`, `languagesDroppedTranslationCount(_:)`, `languagesTranslationReport`, `commitLanguages(_:)`, private `recordLanguagesDiagnostic`. Uses `documentSession.document`, not `authoringDocument`. |
| `SiteForge/WorkspaceShellView.swift` | `.sheet(isPresented: $state.isLanguagesEditorPresented)` after the Collections sheet; File > Languages… after Collections…, inside `if features.isEnabled(.siteLanguages)`; new `private struct SiteLanguagesEditorView` before `ProjectSnapshotsSheet`. |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | 1 new test before the per-language export test; uses the existing `siteTranslationFixture()`. |
| `docs/architecture-decisions/ADR-0083-site-languages-sheet.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-038 implementation status line. |

New selector:

```
SiteForgeTests/PersistedHistoryTests/testSiteLanguagesSheetCommitsDraftsUndoablyAndCountsRemovedTranslations
```

New accessibility identifiers (no UI test added, so `scripts/ci-ui-timings.txt` is
unchanged): `languages.sheet`, `languages.empty`, `languages.list`,
`languages.row.<id>`, `languages.<id>.name|code|direction|fallback|missing|makeDefault|remove|issue`,
`languages.add.code`, `languages.add`, `languages.turnOn`, `languages.turnOff`,
`languages.report`, `languages.status`, `languages.cancel`, `languages.apply`.

Suggested first checks: the generic `localeBinding<Value>(_:_:fallback:)` getter
`draft?.locale(id)?[keyPath: keyPath] ?? fallback` (with `Value` = `SiteTextDirection?`
and `SiteLocaleID?`); `change { try SiteLocalizationEditing.makeDefault(locale.id, in: &$0) }`
against `change(_ body: (inout SiteLocalization) throws -> Void)`; the `let` bindings
inside the footer `HStack`; `if let draft` shadowing the `@State` property in `body`;
that `features` is the `FeatureFlagStore` in scope at the Collections… menu item;
`WorkspaceShellState(documentSession:announcementPoster:)` skipping the defaulted
parameters in the test; that `transformValidationContext.isLifecycleAvailable` is true
for a test shell without a lifecycle; and that the extra `.sheet` keeps the workspace
body within the type-checker limit.

## Batch E04 — November 26, 2026 (per-language export, OD-038 / SF-1007, SF-1506, unverified, partial)

Decision record: ADR-0082 (Proposed). Restore point `RP-2026-11-26-E04` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27 and persisted-history schema 4; website metadata unchanged (version 3);
no new `CanonicalDocument` or `DocumentNode` key. Part 3 of 4 of OD-038; no UI.

| File | Change |
|---|---|
| `SiteForge/CanvasRendererCore.swift` | New section before `MultiPageStaticBuildPlanner`: `SiteLanguageOutputPass` (`pathPrefix`, `htmlAttributes`, `route(_:)`) and `SiteLanguageOutput` (`passes`, `translatedDocument`, `translatedNode`, `relativeRoutes`, `relativePath`, `alternates`, `translatedAssetIDs`, `findings`). `MultiPageStaticBuildPlanner.plan`: the per-page loop now runs once per language (body re-indented one level; default pass unchanged), language trees use prefixed output paths, page-relative control links, prefixed image sources, `lang`/`dir`, the language's canonical address and hreflang alternates; shared styles/trees only from the default pass; sitemap from `indexableRoutes` of every language. `StaticBuildCompiler.compile`: exports translated-only images and appends `SiteLanguageOutput.findings`. |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | 1 new test after the second site-translations test; uses the existing `siteTranslationFixture()`. |
| `docs/architecture-decisions/ADR-0082-site-language-export.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-038 implementation status line. |

New selector:

```
SiteForgeTests/PersistedHistoryTests/testSiteLanguagesExportOneTreePerLanguageWithAlternatesAndTranslations
```

New finding codes: `translation-missing`, `translation-orphaned`, `language-alternates-need-site-url`.
No accessibility identifiers or UI tests were added, so `scripts/ci-ui-timings.txt`
is unchanged.

Suggested first checks: `let output = try language.pathPrefix + outputPath(for: page)`
(`try` on the left of the whole expression); `var passPages = pages` assigned only for
non-default languages; `ordered.compactMap { locale -> SiteLanguageOutputPass? in … }`;
`passes.first(where: \.isDefault)`; that every existing plan/compile test for sites without
languages still produces identical files (`<html lang="en">`, no `dir`, no `hreflang`,
sitemap order); the ` src="assets/` rewrite against `SafeHTMLEmitter.emitImage` output;
that `fixture.translated` (never placed on a node) is now exported via
`translatedAssetIDs`; tests elsewhere that list every `StaticBuildFinding` code of a
compile. Observation, not changed: default-language pages at nested routes (collection
item pages under `/posts/`) still write root-relative image `src` and control `href`
values, which break when those files are opened from their folder.

## Batch E03 — November 26, 2026 (per-node translations, OD-038 / SF-1007, SF-1506, unverified, partial)

Decision record: ADR-0081 (Proposed). Restore point `RP-2026-11-26-E03` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27 and persisted-history schema 4; website metadata unchanged (version 3);
no new `CanonicalDocument` or `DocumentNode` key. Part 2 of 4 of OD-038; no UI or export.

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New section before the CMS collections MARK: `SiteTranslationField` (`title`, `baseKey(for:)`, `fields(for:)`), `SiteTranslationKey` (namespace `locale.translation.v1.`, `init?(rawValue:)`, `rawValue`), `CanonicalTranslations` (`validate(_:assetIDs:)` per node, `validate(_:)` per document, `isValid`, `translations(on:)`, `value`, `baseValue`, `usesAsset`), `SiteTranslationResolution` (`Source`, `explanation`), `SiteTranslationResolver.resolve`, `SiteTranslationGap`, `SiteTranslationReport` (`build`, `missingCount`, `orphanedCount`, `summary`, `requiredFields`), `SiteTranslationEditError`, `SiteTranslationEditing` (`prepare`, `droppedTranslationCount`, `transitionCommands`), `SiteTranslationEditDiagnostic`. `ModelValidationError.invalidTranslation` + message. `validate()` calls the document rule after the languages check; page validation calls the node rule after `CanonicalImageFill.validate`. `SiteLocalizationEditing.prepare` returns `.batch(translation edits + setLocalization)` when translations are affected, else the single command as before. |
| `SiteForge/CommandKernel.swift` | `removeImageAsset` availability refuses an asset a translation uses. |
| `SiteForge/ProjectResources.swift` | `ImageAssetDependencies.unusedAssetIDs` counts translated images as used; `retarget` also rewrites translated image references. |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | 2 new tests after the second site-languages test; private helper `siteTranslationFixture()` before `makeController`. |
| `docs/architecture-decisions/ADR-0081-site-translations.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-038 implementation status line. |

New selectors:

```
SiteForgeTests/PersistedHistoryTests/testSiteTranslationsAreStrictUndoablePersistedAndResolvedPerLanguage
SiteForgeTests/PersistedHistoryTests/testSiteTranslationReportAndLanguageChangesKeepTranslationsConsistent
```

No accessibility identifiers or UI tests were added, so `scripts/ci-ui-timings.txt`
is unchanged.

Suggested first checks: the closures of type `() throws -> DocumentCommand` in the
refusal table of the first test (they capture the `@MainActor` session); `try` inside
the tuple elements of the `forgeries` array; `guard let localization else { continue }`
shadowing in `SiteTranslationReport.build` and `guard let swap else { continue }` in
`transitionCommands`; `case .string = base.value` without a binding; that the
two-root fixture page from D03 validates (`try document.validate()` in
`siteTranslationFixture`); that undo of the default swap (two `setProperty` on one node,
one of which changes the key of an existing property id) restores the document exactly;
`CommandKernelTests` line 210 (`ImageAssetReference.Kind.allCases`) is unchanged
because no new reference kind was added.

## Cross-lane review 2 — November 26, 2026 5:05 PM EST (Code Forge coordinator, unverified)

Review of finished lanes B (B01–B02), C (C01–C03) and D (D01–D03) against
each other and earlier batches. Whole-tree static checks clean; every
`DocumentCommand` case handled; `CanonicalDocument` keys (`collections`,
`fontAssets`, `localization`) gated, copied by templates and accepted in any
combination; website metadata still version 3; no foreign changes. Gaps fixed:

| File | Change |
|---|---|
| `SiteForge/DecorativeEffects.swift` | New `CanonicalEventGraph.remappingTargets(_:nodeMap:pageMap:freshIdentity:)`. |
| `SiteForge/ClipboardTransfer.swift` | Paste remaps interaction targets inside the copy (and Go To Page for cross-project source page). Before, pasted interactions still operated the original objects. |
| `SiteForge/TransformModel.swift` | Same for definition graph copies, customized slot contents and Create Component. |
| `SiteForge/CommandKernel.swift` | Same for `CanonicalPageGraphClone` (page duplicate); Go To Page follows like links when `preservePageLinks` is false. |
| `SiteForge/InsertionModel.swift` | Component instance expansion remaps targets to the instance's derived IDs with `freshIdentity: false` (deterministic output). Before, interactions inside component definitions targeted IDs that do not exist in output. |
| `SiteForge/CanvasRendererCore.swift` | `StaticBuildCompiler` exports images that only collection items use (item pages pointed at unexported files). Item pages ignore a title set on the template page itself (`ignoresPageTitle`). |
| `SiteForge/DocumentModel.swift` | `WebsiteMetadataResolver.resolve(page:document:ignoresPageTitle:)`. |
| `SiteForge/ProjectPackage.swift` | Comparison names "Site languages" and reports "Other project data" whenever uncompared fields differ, not only when nothing else changed (`sameUncomparedContent` replaces `sameContent`). |
| `Tests/SiteForgeTests/TransformModelTests.swift` | New `testCopiedInteractionsFollowCopiedTargetsAndKeepOutsideTargets`. |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | `testCollectionTemplatePageBuildsOneEscapedPagePerPublishedItem`: template-title and item-only picture export assertions. |

New selector: `SiteForgeTests/TransformModelTests/testCopiedInteractionsFollowCopiedTargetsAndKeepOutsideTargets`.

Known and not fixed here: page variables are page-scoped, so pasting an object
whose interactions or visibility use a variable onto another page leaves those
uses unresolved (reported by Check Website, not dropped). Lane A (A3) and lane E
(E1) were still running during this review.

## Batch E02 — November 26, 2026 (site languages model, OD-038 / SF-1007, SF-1506, unverified, partial)

Decision record: ADR-0080 (Proposed). Restore point `RP-2026-11-26-E02` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27 and persisted-history schema 4; website metadata unchanged (version 3).
Part 1 of OD-038: model only, no UI, export or per-node translations.

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New section before the CMS collections MARK: `SiteLocaleIdentifierDomain` / `SiteLocaleID`, `SiteTextDirection` (`title`, `htmlValue`, `implied(byCode:)`), `SiteLocaleCode` (`canonical`, `isValid`, `routeSegment`), `SiteLocale` (optional `direction`, `fallbackLocaleID`; null refused), `SiteLocalization` (`version` 1, exact keys), `SiteLocalizationIssue` (`Kind: CaseIterable`), `CanonicalLocalization` (`issues(_:pages:)`, `walk(from:in:)`), `SiteLocaleResolution`, `SiteLocaleResolver` (`resolve`, `route`, `firstAvailable`), `SiteLocalizationEditError`, `SiteLocalizationEditing` (`prepare`, `start`, `addLocale`, `removeLocale`, `makeDefault`, `suggestedName`), `SiteLocalizationEditDiagnostic`. `CanonicalDocument.localization` (optional key `localization`, init parameter last, after `fontAssets`; in the strict optional-key set). `validate()` checks the language rules. Schema gate for languages below 27. `ModelValidationError.invalidLocalization` + message. |
| `SiteForge/CommandKernel.swift` | `CommandName.setLocalization` (`document.localization.set`), `SetLocalizationCommand` (exact keys, `localization` written as null when off), `DocumentCommand.setLocalization` in `minimumPersistedHistorySchema` (4), `name`, `targets`, descriptor ("Edit Languages"), availability, apply/inverse. |
| `SiteForge/PersistedHistory.swift` | Payload check for `setLocalization` (`documentID`, `localization`). |
| `SiteForge/ProjectPackage.swift` | Snapshot restore appends `setLocalization` when languages differ; comparison adds a "Languages" settings change. |
| `SiteForge/PackagedSiteTemplate.swift` | Template copy passes `localization: original.localization`. |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | 2 new tests before the second collections test. |
| `docs/architecture-decisions/ADR-0080-site-languages-model.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-038 implementation status line. |

New selectors:

```
SiteForgeTests/PersistedHistoryTests/testSiteLanguagesAreStrictSchemaGatedUndoableAndPersistedInHistory
SiteForgeTests/PersistedHistoryTests/testSiteLanguageRulesResolveFallbacksDirectionAndAddresses
```

No accessibility identifiers or UI tests were added, so `scripts/ci-ui-timings.txt`
is unchanged.

Suggested first checks: the `let fallbackRule: String = switch …` expression in
`SiteLocaleResolution.explanation`; `Character.isASCII`/`isLetter`/`isNumber` use in
`SiteLocaleCode.canonical`; that `ProjectComparer.compare` with two `nil` snapshot ids
does not throw `sameSource`; that `ProjectSnapshots.restoreCommand(to: blank, …)`
returns exactly one `setLocalization` command for the test fixture;
`Locale(identifier: "en_US_POSIX").localizedString(forIdentifier:)` output used by
`suggestedName` (the test only checks non-empty and the duplicate suffix); and tests
elsewhere that list every `CommandName` or build command JSON by hand.

## Batch D03 — November 26, 2026 (template pages and bindings, OD-035 / SF-1003, unverified, partial)

Decision record: ADR-0072 (Proposed). Restore point `RP-2026-11-26-D03`
(lanes B, C and E were mid-batch when it was taken). Still document schema 27
and history schema 4. Partial: detail pages (one page per published item) are
done; list pages are not.

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New (before `CollectionEditDiagnostic`): `CollectionBindingTarget`, `CollectionBinding`, `CollectionTemplate`, `CollectionTemplateFinding`, `CollectionTemplates` (`itemRoute`, `publishedItems`, `activePage`, `templatePageIDs`, `linkTargets`, `findings`, `itemPage`, `outputPages`, `OutputPage`, `diagnostic`), `extension CollectionEditing` (`bindableNodes`, `setTemplatePage`, `setTitle`, `setTextBinding`, `setImageBinding`, `templatePreview`). `ContentCollection.template` (optional key; init parameter `template: nil`). `CollectionIssue.Kind` gains `template`, `duplicateTemplatePage` (+ messages, checked in `CanonicalCollections.issues`). Optional keys in `ContentCollection`, `CollectionTemplate`, `CollectionBinding` and (D02) `CollectionField.referencedCollectionID` now refuse an explicit null. |
| `SiteForge/CanvasRendererCore.swift` | `MultiPageStaticBuildPlanner.plan`: builds `CollectionTemplates.outputPages`, maps template page links to the first item, loops over output pages (`entry.page`), leaves template pages out of navigation, takes shared style nodes/trees only from primary pages, sitemap from output pages. |
| `SiteForge/BrowserPreview.swift` | Previewing a template page opens its first item page. |
| `SiteForge/WorkspaceShellView.swift` | `CollectionsEditorView`: new **Template** tab (`templatePane`, `expressionField`, `templatePages`, `templateFindings`). |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | 2 new tests before the custom code test. |
| `docs/architecture-decisions/ADR-0072-template-pages-and-bindings.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-035 implementation status line. |

New selectors:

```
SiteForgeTests/PersistedHistoryTests/testCollectionTemplatePageBuildsOneEscapedPagePerPublishedItem
SiteForgeTests/PersistedHistoryTests/testCollectionTemplateRecordIsStrictUndoableAndPreviewedLive
```

No UI tests; `scripts/ci-ui-timings.txt` unchanged. New accessibility
identifiers start with `collections.template`.

Suggested first checks: existing planner tests whose pages could match a
template (none should; no fixture sets `template`); the bare text/image
layer fixtures in the first test (only `layout.*` and content keys) passing
the planner; the exact `<title>` string; tuple `<` in the binding sort; the
`(String, inout ContentCollection) -> Bool` closures in `templatePane`.

## Batch B02 — November 26, 2026 (project fonts, OD-045 / SF-0805, unverified, complete)

Decision record: ADR-0051 (Proposed). Restore point `RP-2026-11-26-B02` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27 and persisted-history schema 4; website metadata unchanged.

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New `FontAssetFormat`, `FontFaceStyle`, `FontFallbackStack`, `FontEmbeddingRights`, `FontAsset` (exact keys, optional `licenseNote`, `isValidFamily`, `isValid`, `faceKey`, `validate`, static `validate(_:)`), `ProjectFontResolver` (`cssWeight`, `faces`, `families`, `fallback`, `nearestWeight`, `resolve`, `usageCount`, `Resolution`), `FontAssetEditing.prepare`. `CanonicalDocument.fontAssets` (optional key `fontAssets`, written only when not empty; init parameter `fontAssets: []` last). `validate()` calls `FontAsset.validate`. Schema gate for fonts below 27. `ModelValidationError.invalidFontAsset` + message. |
| `SiteForge/CommandKernel.swift` | `CommandName.setFontAssets` (`document.fontAssets.set`), `SetFontAssetsCommand` (exact keys), `DocumentCommand.setFontAssets` in `minimumPersistedHistorySchema` (4), `name`, `targets`, descriptor ("Edit Fonts"), availability, apply/inverse. |
| `SiteForge/PersistedHistory.swift` | Payload check for `setFontAssets` (`documentID`, `fontAssets`). |
| `SiteForge/ProjectPackage.swift` | Snapshot restore: font resources must be available; `setFontAssets` appended when fonts differ. |
| `SiteForge/ProjectResources.swift` | `import CoreText`. `ProjectImageResourceSnapshot` also carries font resources. New `FontImportError`, `ProjectFontFormatSniffer`, `ProjectFontMetadata` (`OS2`), `PreparedFontImport`, `FontImportWorker`, `ProjectFontOutput` (`cssFamilyName`, `isUsed`, `exportCandidates`, `exportedPaths`, `fontFaceCSS`, `fallbackStacks`, `usesProjectFont`, `findings`). `StaticAssetExportPlanner` accepts `font/woff2` / `font/ttf` with a matching signature → `assets/<sha>.woff2|ttf`. |
| `SiteForge/CanvasRendererCore.swift` | `StaticTypographyOutputEmitter.emit(nodes:fontFallbacks:)` (defaulted) and private `rule(for:fontFallbacks:)`: project families get their fallback stack. `MultiPageStaticBuildPlanner.plan(…, fontOutputEntries:)` (defaulted, last): `@font-face` block first in `styles.css`, fallbacks in light and dark typography, stylesheet linked when a page uses a project font. `StaticBuildCompiler.compile` (descriptor overload) adds font findings and packages used faces with web rights. |
| `SiteForge/LaunchExperience.swift` | New `NativeFontOpenPanel.chooseFonts()`. |
| `SiteForge/WorkspaceShellModel.swift` | `fontImportWorker`, `isImportingFonts`, `lastFontAnnouncement`, `fontAssets`, `fontUsageCount(_:)`, `importFonts()`, `importFontURLs(_:)`, `updateFontAsset(_:)`, `removeFontAsset(_:)`. |
| `SiteForge/WorkspaceShellView.swift` | Assets: `showingProjectFonts`, Project Fonts… button + sheet. New private `ProjectFontsSheet`, `ProjectFontRow`. Typography Inspector: Use Project Font menu, `chooseProjectFont(_:)`, project-font branch in `installedWeightSummary`. |
| `Tests/SiteForgeTests/ProjectResourceTests.swift` | 5 new tests before `makeFixture()`. |
| `docs/architecture-decisions/ADR-0051-project-fonts.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-045 implementation status line. |

New selectors:

```
SiteForgeTests/ProjectResourceTests/testProjectFontModelIsStrictValidatedOmittedWhenEmptyAndUndoable
SiteForgeTests/ProjectResourceTests/testProjectFontResolutionFollowsCSSWeightMatchingAndFallbackRule
SiteForgeTests/ProjectResourceTests/testProjectFontsExportOnlyWithDeclaredWebRightsAndUseFallbackStacks
SiteForgeTests/ProjectResourceTests/testFontImportKeepsOriginalBytesAndReadsFaceFacts
SiteForgeTests/ProjectResourceTests/testProjectFontEditsAreUndoableAndFontBytesSurviveSaveAndReopen
```

New accessibility identifiers: `assets.fonts`, `fonts.import`, `fonts.empty`,
`fonts.status`, `fonts.family.<id>`, `fonts.weight.<id>`, `fonts.style.<id>`,
`fonts.rights.<id>`, `fonts.fallback.<id>`, `fonts.license.<id>`,
`fonts.remove.<id>`, `inspector.design.typography.projectFont`. No UI tests
were added, so `scripts/ci-ui-timings.txt` is unchanged.

Suggested first checks: CoreText calls in `FontImportWorker`
(`CTFontManagerCreateFontDescriptorFromData` with WOFF2 data, `CTFontCopyTable`
with `CTFontTableTag(kCTFontTableOS2)` and `[]` options) and whether a 5-byte
TrueType header returns nil rather than trapping; the import test skips when
`/System/Library/Fonts/Supplemental/Arial.ttf` is absent; the text-node fixture
in the export test passes `document.validate()`; whether pages that do not link
`styles.css` were expected to (the font change adds the link only when a page
uses a project font); tests elsewhere that build `CanonicalDocument` JSON or
command lists by hand; the `ProjectFontRow` key-path `Binding` and
`onChange(of:)` two-parameter form.

## Batch C03 — November 26, 2026 (page variables and overlays, OD-039 / SF-1105, SF-1106, unverified, complete)

Decision record: ADR-0062 (Proposed). Restore point `RP-2026-11-26-C03` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27; no website metadata, clipboard or project-file change. With C02
this completes the approved OD-039 first slice.

| File | Change |
|---|---|
| `SiteForge/DecorativeEffects.swift` | New `CanonicalVariableValue`, `CanonicalStateVariable` (`ValueType`), `CanonicalPageState` (`Condition`, keys, limits, reasons, `encode`, `isValid`, `properties(variables:)`, `properties(condition:)`, `storedVariables`, `condition`, `variables(on:)`, `validate(_:isPageRoot:)`), `CanonicalOverlay` (`Kind`, keys, `resolve`). `ActionKind` gains `setVariable`, `toggleVariable`, `openOverlay`, `closeOverlay` (+ `usesVariable`); `Action` gains `variable`, `value` and a per-kind `isValid`; decode allows the two keys. `EventOutputConfiguration.Action` gains `variable`, `value`. `EventGraphOutput` rewritten: `overlayCSS`, `VariableOutput`, `ConditionOutput`, `PageOutput.attributes/stateJSON/hasOverlays/needsRuntime`, `overlayIDs`, `compile(_:…)`, new findings. `EventGraphRuntime.javascript` rewritten (variables, bindings, overlay stack). `DecorativeEffectEdit` gains `.overlay`, `.visibility`, `.pageVariables`; `prepare` handles them (Root-only variables, never-Root overlays and conditions). |
| `SiteForge/DocumentModel.swift` | `ModelValidationError.invalidRuntimeState`, `.invalidOverlayState` + descriptions; page validation calls `CanonicalPageState.validate(_:isPageRoot:)`; the schema-27 gate also covers `state.` and `overlay.` keys. |
| `SiteForge/CanvasRendererCore.swift` | Planner: runtime when `needsRuntime`, state `<div hidden data-siteforge-state>` before the script, overlay CSS. `SafeHTMLEmitter.emit(…, attributes:)`, `emitNode(…, extra:)`. |
| `SiteForge/DecorativeEffectsInspector.swift` | `InteractionInspector`: `variables`, rewritten `actionEditor`, new `reshaped(_:to:node:overlays:)`. New `RuntimeStateInspector`, `VariableValueField`. |
| `SiteForge/WorkspaceShellView.swift` | `RuntimeStateInspector` after `InteractionInspector`. |
| `SiteForge/WorkspaceShellModel.swift` | Preview operation names "overlay", "visibility", "page-variables". |
| `Tests/SiteForgeTests/TransformModelTests.swift` | 2 new tests before the C01 output test. |
| `docs/architecture-decisions/ADR-0062-variables-and-overlays.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-039 implementation status line (complete first slice). |

New selectors:

```
SiteForgeTests/TransformModelTests/testRuntimeVariablesOverlaysAndVisibilityTypedValidationHistoryAndSchemaGate
SiteForgeTests/TransformModelTests/testRuntimeVariablesOverlaysOutputHydrationRuntimeAndDiagnostics
```

New finding codes: `state-binding-invalid`, `overlay-unreachable`,
`overlay-unnamed` (warnings). New accessibility identifiers:
`inspector.state.addVariable`, `inspector.state.variable.<n>.name|type|remove|initial`,
`inspector.overlay.enabled|kind|dismissOutside`,
`inspector.visibility.enabled|variable|value`,
`inspector.interactions.<n>.action.<m>.variable|value|overlay`. No UI tests were
added, so `scripts/ci-ui-timings.txt` is unchanged.

Suggested first checks: `CanonicalVariableValue` single-value decoding order
(Bool before Double) and the encoded form of whole numbers (`3`, not `3.0`),
which the canonical-text check relies on; the `switch` and `let` inside the
`VStack` builder in `actionEditor`; `ForEach(choices)` / `ForEach(overlays)`
with `Optional` tags; `PageBackgroundPolicy.root` for the formatting fixture
(the tests unwrap it); whether `CanonicalDocument.validate` rethrows
`ModelValidationError` unwrapped (C02 and C03 tests compare it).

## Cross-lane review — November 26, 2026 4:35 PM EST (Code Forge coordinator, unverified)

Static review of every file the lanes wrote (write ledger): balance and new
duplicate checks clean; every `DocumentCommand` case (now 22, including
`setCollections` and `setFontAssets`) is handled in every exhaustive switch;
`CanonicalDocument` optional keys (`projectPreferences`, `collections`,
`fontAssets`) are accepted in any combination and gated to schema 27; no
foreign (non-lane) changes. Two gaps fixed:

| File | Change |
|---|---|
| `SiteForge/PackagedSiteTemplate.swift` | Template creation copies `fontAssets` too (it dropped them; collections were already copied). |
| `SiteForge/ProjectPackage.swift` | `ProjectComparer.compare` reports "Project fonts" changes, and names "Other project data" once when two versions differ in data without a dedicated comparison, so different versions are never shown as identical. New `ProjectComparer.sameContent(_:_:)` ignores only the revision. |
| `Tests/SiteForgeTests/ProjectPackageTests.swift` | `testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded`: font change, revision-only and other-data assertions. |

## Batch E01 — November 26, 2026 (Snapshots sheet, batch 18 part 2, OD-043 / SF-1301, unverified, complete)

Decision record: ADR-0039 (Proposed). Restore point `RP-2026-11-26-E01` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27; no website metadata, package, history, clipboard or project-file
change. With batch 18 part 1 this completes the approved SF-1301 slice.

| File | Change |
|---|---|
| `SiteForge/SupportSettings.swift` | `FeatureFlagID.namedSnapshots` (`versions.named-snapshots`) and its `FeatureFlagRegistry` definition (default on, remove by 2027-03-31, SF-1301). |
| `SiteForge/WorkspaceShellModel.swift` | `WorkspaceShellState` block before `// MARK: SF-0206 project-scoped preferences`: `isSnapshotsPresented`, `snapshotEntries`, `snapshotStorageFailure`, `snapshotsStatus`, private `pendingSnapshotComparison`, `canManageSnapshots`, `snapshotRows`, `canCreateSnapshot`, `presentSnapshots()`, `reloadSnapshots()`, `suggestedSnapshotName(base:)`, `snapshotNameIssue(_:renaming:)`, static `snapshotDetail(_:)`, `createSnapshot(named:)`, `renameSnapshot(_:to:)`, `deleteSnapshot(_:)`, `deleteAllSnapshots()`, `restoreSnapshot(_:keepingCurrentAs:)`, `compareSnapshotWithCurrent(_:)`, `completeSnapshotsDismissal()`, private `performSnapshotAction(_:)`. |
| `SiteForge/WorkspaceShellView.swift` | New private `ProjectSnapshotsSheet` before `StaticBuildDiagnosticsView`. Workspace `.sheet(isPresented: $state.isSnapshotsPresented, onDismiss: state.completeSnapshotsDismissal)` after the Collections sheet. `SiteForgeCommands`: `@ObservedObject private var features = FeatureFlagStore.shared`; File > Snapshots… (flag-gated) before Compare Versions…. |
| `Tests/SiteForgeTests/DocumentLifecycleTests.swift` | 1 new test before the private `makeController` helper. |
| `docs/architecture-decisions/ADR-0039-snapshots-sheet.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-043 implementation status line (Snapshots UI part only). |

New selector:

```
SiteForgeTests/DocumentLifecycleTests/testSnapshotsSheetCreatesRenamesRestoresKeepingCurrentHandsOffCompareAndRecoversDamagedStorage
```

New accessibility identifiers: `snapshots.sheet`, `snapshots.name`,
`snapshots.name.issue`, `snapshots.limit`, `snapshots.create`,
`snapshots.empty`, `snapshots.list`, `snapshots.row.<id>`,
`snapshots.<id>.restore|compare|rename|delete|renameField|renameCancel|renameApply`,
`snapshots.restore`, `snapshots.restore.keep|keepName|keepIssue|limit|cancel|confirm`,
`snapshots.failure`, `snapshots.retry`, `snapshots.recover.deleteAll`,
`snapshots.status`, `snapshots.deleteAll`, `snapshots.done`. No UI tests were
added, so `scripts/ci-ui-timings.txt` is unchanged.

Suggested first checks: `.keyboardShortcut(_:)` with an optional
`KeyboardShortcut` (macOS 12.3+) on Done; `@ObservedObject` of the
main-actor `FeatureFlagStore.shared` inside `SiteForgeCommands`; the
dismissal hand-off to lane A's `presentProjectComparison(baseline:)` (lane A
batch A02 may still be changing it); the test's direct `ProjectPackageStore.write`
over the saved file and reopen with a damaged snapshot member; any test that
expects `FeatureFlagRegistry.definitions` to hold exactly one flag (the
unreadable `SupportSettingsTests.swift` was not checked).

## Batch D02 — November 26, 2026 (CMS collections and Collections editor, OD-035 / SF-1001, SF-1002, unverified, complete)

Decision record: ADR-0071 (Proposed). Restore point `RP-2026-11-26-D01` (taken
before D01) is the last lane D restore point; D02 started without a new one.
Still document schema 27 and persisted history schema 4; website metadata
unchanged (version 3).

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New (before `DocumentSerializationError`): `CollectionIdentifierDomain`, `CollectionFieldIdentifierDomain`, `CollectionItemIdentifierDomain`, `CollectionID`, `CollectionFieldID`, `CollectionItemID`, `CollectionFieldType`, `CollectionFieldValue`, `CollectionField` (`reservedKeys`, `isValidKey`, `suggestedKey`), `CollectionItemStatus`, `CollectionItemValue`, `CollectionItem` (`value(for:)`, `setValue(_:for:)`), `CollectionSlug`, `ContentCollection` (`expressionSchema(in:)`, `expressionContext(for:in:)`), `CollectionIssue`, `CanonicalCollections` (`issues`, `usesAsset`, `referencingFields`, `itemsWithValue`, `referencesTo`, `documentSchema` 27), `CollectionEditDiagnostic`, `CollectionEditError`, `CollectionEditing`. `CanonicalDocument.collections` (init parameter `collections: []`; key `collections` optional in the strict key check, written only when non-empty, empty/null refused); `validate` runs `CanonicalCollections.issues`; new `ModelValidationError.invalidCollections` + message; schema < 27 with collections refused. |
| `SiteForge/CommandKernel.swift` | `CommandName.setCollections` (`document.collections.set`), `SetCollectionsCommand` (exact keys), `DocumentCommand.setCollections` (history schema 4, name, targets, descriptor "Edit Collections", availability, mutation with inverse). `removeImageAsset` refused while a collection item uses the image. |
| `SiteForge/PersistedHistory.swift` | `setCollections` payload keys. |
| `SiteForge/ProjectPackage.swift` | Snapshot `restoreCommand` restores collections. |
| `SiteForge/PackagedSiteTemplate.swift` | Template copy keeps collections. |
| `SiteForge/ProjectResources.swift` | `ImageAssetDependencies.unusedAssetIDs` treats images used by collection items as used. |
| `SiteForge/WorkspaceShellModel.swift` | `isCollectionsEditorPresented`, `collectionsOpeningRevision`, `collectionsStatus`, `lastCollectionsDiagnostic`, `canEditCollections`, `presentCollectionsEditor()`, `commitCollections(_:)`. |
| `SiteForge/WorkspaceShellView.swift` | New private `CollectionsEditorView` (top of file); `.sheet(isPresented: $state.isCollectionsEditorPresented)` after the Website Settings sheet; File menu **Collections…** after Site & Page Settings…. |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | 2 new tests before the custom code test. |
| `docs/architecture-decisions/ADR-0071-cms-collections.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-035 implementation status line. |

New selectors:

```
SiteForgeTests/PersistedHistoryTests/testCollectionsAreStrictSchemaGatedUndoableAndPersistedInHistory
SiteForgeTests/PersistedHistoryTests/testCollectionRulesProtectDataAndEditorOperationsAreDeterministic
```

No UI tests were added, so `scripts/ci-ui-timings.txt` is unchanged. New
accessibility identifiers start with `collections.`.

Suggested first checks: tests that compare `CommandName.allCases` or the
command registry count; tests that assert the exact top-level document keys;
the `List(…, selection:)` with an optional `CollectionItemID` binding and the
`confirmationDialog(…, presenting:)` in `CollectionsEditorView`; the
image-asset fixture passing `document.validate()` in the second test.

## Batch A02 — November 26, 2026 (version comparison, OD-043 / SF-1306, unverified, complete)

Decision record: ADR-0040 (Proposed). Restore point `RP-2026-11-26-A02` was
taken before this batch (other lanes may have been mid-batch). No document
schema, package, history, clipboard or feature-flag change. Builds on batch 18
part 1 (ADR-0038). Batch A01 wrote no tree files: item A1 was taken by the
schedule (batch 18); restore point `RP-2026-11-26-A01` exists.

| File | Change |
|---|---|
| `SiteForge/ProjectPackage.swift` | New at the end, after `ProjectSnapshots`: `ProjectComparisonSource` (`currentDocumentName`, `resolve(_:head:package:checkpoint:)`), `ProjectComparisonArea`, `ProjectComparisonChangeKind`, `ProjectComparisonChange` (`summary`, `matches`), `ProjectComparisonDiagnosticRecord`, `ProjectComparison` (`isIdentical`, `count(of:)`, `filtered(area:kind:query:)`, `countSummary`, `report()`), `ProjectComparisonError`, `ProjectComparer` (`requirementIDs`, `maximumChanges` 5,000, `maximumValueCharacters` 160, `compare(_:with:checkpoint:)`, `movedIdentifiers(from:to:)`, `valueText`, `clipped`; private `Collector` and per-area helpers). |
| `SiteForge/WorkspaceShellView.swift` | New before `RecoveryCandidateBar`: `ProjectComparisonRequest`, `@MainActor ProjectComparisonModel` (detached run per generation, `compare`, `cancel`, `isStale(headRevision:)`, `createSnapshot(named:)`, `deleteAllSnapshots`, `exportReport`, diagnostics), private `ProjectComparisonSheet`. `WorkspaceShellView`: `.sheet(item: $state.projectComparisonRequest)` after the Quick Open sheet. `SiteForgeCommands` save group: Divider + **Compare Versions…** after Revert to Saved. |
| `SiteForge/WorkspaceShellModel.swift` | `WorkspaceShellState.projectComparisonRequest`, `presentProjectComparison(baseline:target:)` after `websiteSettingsStatus`. |
| `Tests/SiteForgeTests/ProjectPackageTests.swift` | 1 new test before `testUnknownOptionalMemberIsPreservedByteForByteAcrossRoundTrip`. |
| `Tests/SiteForgeTests/DocumentLifecycleTests.swift` | 1 new test and private `awaitProjectComparison(_:)` before `makeController`. |
| `docs/architecture-decisions/ADR-0040-version-comparison.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-043 implementation status line (comparison part). |

New selectors:

```
SiteForgeTests/ProjectPackageTests/testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded
SiteForgeTests/DocumentLifecycleTests/testCompareVersionsRunsOffTheMainActorIgnoresStaleRunsAndNeverEditsTheDocument
```

New accessibility identifiers: `comparison.sheet`, `comparison.empty`,
`comparison.snapshotName`, `comparison.createSnapshot`, `comparison.listFailure`,
`comparison.deleteAll`, `comparison.baseline`, `comparison.target`,
`comparison.compare`, `comparison.cancel`, `comparison.retry`, `comparison.failure`,
`comparison.stale`, `comparison.summary`, `comparison.filter.area|kind|text`,
`comparison.identical`, `comparison.changes`, `comparison.change.<n>`,
`comparison.status`, `comparison.copyReport`, `comparison.exportReport`,
`comparison.close`. No UI tests were added, so `scripts/ci-ui-timings.txt` is
unchanged.

Suggested first checks: the `Task.detached` closure in
`ProjectComparisonModel.compare()` under the project's concurrency checking
(captures `ProjectPackage`, `CanonicalDocument`, `ContinuousClock.Instant` and
`[weak self]`, then `await self?.finish`); `ProjectComparer.clipped`
(`String.unicodeScalars.append(contentsOf:)` with a `" "` scalar literal in a
ternary); type-checking time of `WorkspaceShellView.body` with one more sheet;
`.font(.caption.monospaced())` and `.confirmationDialog(…message:)` on the
deployment target; the snapshot document round trip (`DocumentSerializer`
encode → decode) giving an equal document, which the lifecycle test's
one-change assertion relies on.

Review of batch 18 part 1 (A1), observed, not changed: restore runs through
`DocumentSession.execute`, so while a component variant is being edited the
`authoringTransform` applies to the restore batch and can refuse it (not listed
in ADR-0038 consequences). Snapshot-only changes do not schedule autosave
(listed in ADR-0038).

Observed: at 16:09:29 the activity log was present only as
`docs/coordination/CODE_FORGE_ACTIVITY 2.md` (iCloud name-conflict copy, bytes
identical to lane C's ledgered write) and `CODE_FORGE_ACTIVITY.md` was missing.
Lane A renamed it back under the file lock and recorded it in the ledger; the
content was not changed.

## Batch C02 — November 26, 2026 (event graph and generated runtime, OD-039 / SF-1101, unverified, partial)

Decision record: ADR-0061 (Proposed). Restore point `RP-2026-11-26-C02` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27; no website metadata, clipboard or project-file change. Partial for
OD-039 only: runtime variables and overlays (SF-1105, SF-1106, lane item C3)
are not started. SF-1101 itself is complete for the approved first slice.

| File | Change |
|---|---|
| `SiteForge/DecorativeEffects.swift` | New `CanonicalInteraction` (`Trigger`, `ActionKind`, `Action`), `CanonicalEventGraph` (keys, limits, `supportedKinds`, `clickKinds`, `isAllowed(on:)`, `encode`, `decode`, `properties`, `resolve`), `EventOutputConfiguration`, `EventGraphOutput` (`hiddenCSS`, `PageOutput`, `page(_:staticRoutes:prefix:)`, `findings(_:availablePageIDs:)`), `EventGraphRuntime.javascript`. `DecorativeEffectEdit.events`; `prepare` skips form fields and click on non-controls with reasons; when every skip has one reason it is the error message (motion and events only). |
| `SiteForge/DocumentModel.swift` | `ModelValidationError.invalidInteractionGraphState` + description; `validate` calls `CanonicalEventGraph.resolve`; the C01 schema-27 gate also covers `event.` keys. |
| `SiteForge/CanvasRendererCore.swift` | Planner: per-page `EventGraphOutput.page`, stylesheet link, `siteforge-events.js` script and file, hidden CSS line; `script` became `var`. `SafeHTMLEmitter.emit(…, events:, startsHidden:)`, `emitNode(…, events:, startsHidden:)` write `data-siteforge-events` and `hidden`. `StaticBuildCompiler.compile` adds the interaction findings. |
| `SiteForge/DecorativeEffectsInspector.swift` | New `InteractionInspector`. |
| `SiteForge/WorkspaceShellView.swift` | `InteractionInspector` after `MotionInspector`. |
| `SiteForge/WorkspaceShellModel.swift` | Design-style preview operation name "interaction". |
| `Tests/SiteForgeTests/TransformModelTests.swift` | 2 new tests before the C01 output test. |
| `docs/architecture-decisions/ADR-0061-event-graph.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-039 implementation status line (partial). |

New selectors:

```
SiteForgeTests/TransformModelTests/testEventGraphTypedValidationHistoryClickPolicyAndSchemaGate
SiteForgeTests/TransformModelTests/testEventGraphOutputCompilesFixedActionsStartHiddenAndDiagnostics
```

New finding codes: `interaction-target-missing`, `interaction-pointer-only`,
`interaction-focus-loop` (all warnings). New accessibility identifiers:
`inspector.interactions.startsHidden`, `inspector.interactions.add`,
`inspector.interactions.<n>.trigger|remove|addAction`,
`inspector.interactions.<n>.action.<m>.kind|page|target|remove`. No UI tests
were added, so `scripts/ci-ui-timings.txt` is unchanged.

Suggested first checks: `CanonicalInteraction.Action` synthesized Codable with
defaulted optional `var`s; `try? JSONSerialization.jsonObject(…) as? [[String: Any]]`
and the `allSatisfy` closures inside the `decode` guard; the `attributes`
concatenation in `emitNode` (type-check time); `Picker` tags of `Optional(id)`
in `InteractionInspector`; UI tests or snapshots that count Design inspector
groups; any test that expects every enabled finding to block or not block.

## Batch B01 — November 26, 2026 (SVG assets, OD-045 / SF-0804, unverified, complete)

Decision record: ADR-0050 (Proposed). Restore point `RP-2026-11-26-B01` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27; no website-metadata, clipboard or project-file format change.

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | `ImageAssetFormat.svg` (`image/svg+xml`). Schema gate: an SVG image asset in a schema < 27 file is refused. |
| `SiteForge/ProjectResources.swift` | New `SVGSanitizationReport`, `SanitizedSVG`, `SVGAssetSanitizer` (`sanitize`, `isCanonicalSanitized`, `recolor`, `normalizedHexColor`, `accessibleName`, `diagnosticSummary`, `safeAttributeValue`, `safeStyleAttribute`, `isSafeStyleSheet`, `hasOnlyFragmentURLs`, `compacted`, `looksLikeSVG`) and private `SVGSanitizerElement`, `SVGSanitizerContent`, `SVGSanitizerParseResult`, `SVGSanitizerParserDelegate` (`XMLParserDelegate`). `ImageImportError.unsupportedSVG` (+ messages; `.unsupported` text lists SVG). `PreparedImageImport.svgReport` (defaulted `var`). `ImageImportWorker.prepare` routes `.svg` / SVG-looking data to new private `prepareSVG` (stores only sanitized bytes). `ImageThumbnailWorker.thumbnailPNG` returns SVG bytes unchanged. `StaticAssetExportPlanner` accepts canonical sanitized `image/svg+xml` → `assets/<sha>.svg`. |
| `SiteForge/CanvasRendererCore.swift` | Asset-path regexes accept `svg` (CSS image fill, `SafeHTMLEmitter.isVerifiedAssetPath`); asset repair text mentions SVG; new `social-image-svg` warning (SF-0804-004). |
| `SiteForge/BrowserPreview.swift` | Serves `svg` as `image/svg+xml`. |
| `SiteForge/LaunchExperience.swift` | `NativeImageOpenPanel`: the three panels allow `.svg`; import panel messages mention SVG cleaning. |
| `SiteForge/WorkspaceShellModel.swift` | `svgAssetReport(_:)`, `svgRecolorPreview(_:hex:)`, `recolorSVGAsset(_:hex:)` (one `updateImageAsset` with a new resource via `installingProjectResource`). `importImageURLs` announces removed unsafe SVG parts. |
| `SiteForge/WorkspaceShellView.swift` | `CanvasContentTileLayer.decodedTileImage(_:longestSide:)` (ImageIO, then `NSImage` SVG fallback) used by tile drawing. `AssetRow`: `isRecoloring`, Recolor SVG… menu item for SVG assets, sheet. New private `SVGRecolorSheet`. |
| `Tests/SiteForgeTests/ProjectResourceTests.swift` | 3 new tests before `makeFixture()`. |
| `docs/architecture-decisions/ADR-0050-sanitized-svg-assets.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-045 implementation status line. |

New selectors:

```
SiteForgeTests/ProjectResourceTests/testSVGSanitizerRemovesScriptsExternalReferencesAndEventAttributes
SiteForgeTests/ProjectResourceTests/testSVGRecolorRewritesEveryPaintAndRefusesIncompatibleIcons
SiteForgeTests/ProjectResourceTests/testSVGAssetImportRecolorUndoSaveReopenExportAndSchemaGate
```

New accessibility identifiers: `assets.recolor.color`, `assets.recolor.apply`,
`assets.recolor.validation`, `assets.recolor.incompatible`,
`assets.recolor.accessibleName`. No UI tests were added, so
`scripts/ci-ui-timings.txt` is unchanged.

Suggested first checks: `XMLParserDelegate` conformance on the private
`NSObject` subclass under the project's concurrency settings; whether
`XMLParser` reports `xmlns` attributes in `attributeDict` (they are skipped
either way) and calls `parseErrorOccurred` after `abortParsing()` (the first
failure is kept); the exact removed-part counts asserted in the sanitizer test
(6 elements, 5 attributes); `NSImage(data:)` SVG decoding and
`cgImage(forProposedRect:context:hints:)` inside `CALayer.draw(in:)` on the
deployment target (canvas falls back to the missing-image placeholder if it
fails); the schema-26 control decode in the third test (PNG format must
decode); the `switch` expression inside the `StaticAssetExportPlanner` map
closure.

## Batch C01 — November 26, 2026 (motion: state transitions and reveal on scroll, OD-040 / SF-1103, SF-1104, unverified, complete)

Decision record: ADR-0060 (Proposed). Restore point `RP-2026-11-26-C01` was
taken before this batch (other lanes may have been mid-batch). Still document
schema 27; no website metadata, clipboard or project-file change.

| File | Change |
|---|---|
| `SiteForge/DecorativeEffects.swift` | New `CanonicalMotion` (`Easing`, `EntranceEffect`, `Transition`, `Entrance`, `prefix`, `namespace`, key sets, defaults, `supportedKinds`, `properties`, `resolve`), `MotionOutput` (`entrances`, `usesMotion`, `css`, `keyframe`), `MotionRuntime.javascript`. `DecorativeEffectEdit.motion`; `DecorativeEffectCommandRegistry.prepare` handles it (skips unsupported kinds and form fields with reasons). |
| `SiteForge/DocumentModel.swift` | `ModelValidationError.invalidMotionState` + description; `validate` calls `CanonicalMotion.resolve`; schema-27 gate for `motion.` keys. |
| `SiteForge/CanvasRendererCore.swift` | `MultiPageStaticBuildPlanner.plan`: motion CSS after advanced styles, stylesheet link for any motion, `siteforge-motion.js` script and file for reveal nodes. `SafeHTMLEmitter.emit(…, entrances:)` and `emitNode(…, entrance:)` write `data-siteforge-entrance`. |
| `SiteForge/DecorativeEffectsInspector.swift` | New `MotionInspector` (Motion group). |
| `SiteForge/WorkspaceShellView.swift` | `MotionInspector` placed after `DecorativeEffectsInspector`. |
| `SiteForge/WorkspaceShellModel.swift` | Design-style preview operation name "motion". |
| `Tests/SiteForgeTests/TransformModelTests.swift` | 2 new tests after the glass test. |
| `docs/architecture-decisions/ADR-0060-css-first-motion.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-040 implementation status line. |

New selectors:

```
SiteForgeTests/TransformModelTests/testMotionTypedValidationHistoryPropertyIdentityAndSchemaGate
SiteForgeTests/TransformModelTests/testMotionOutputIsReducedMotionSafeProgressiveDeterministicAndReleaseStable
```

New accessibility identifiers: `inspector.motion.transition.enabled`,
`inspector.motion.transition.duration.slider|.value`,
`inspector.motion.transition.easing`, `inspector.motion.entrance.enabled`,
`inspector.motion.entrance.effect`, `inspector.motion.entrance.duration|delay|distance|offset.slider|.value`,
`inspector.motion.entrance.easing`. No UI tests were added, so
`scripts/ci-ui-timings.txt` is unchanged.

Suggested first checks: the new `DecorativeEffectEdit` case (no other switch
over it was found); `ModelValidationError` switches outside `DocumentModel.swift`;
`CanonicalMotion` static lets that use other static lets; `EffectNumberControl`
memberwise init from `MotionInspector` (same file, private type); pages that
now link `styles.css` only because of motion; the runtime in Safari
(IntersectionObserver `rootMargin` with a percent bottom inset).

Observed, not changed: `forge_io.foreign_changes` reports files written by
lanes that pass `/` paths (the ledger keeps them as written; the tree walk uses
`\`), so it can flag Code Forge writes as foreign. Lane C compared with
normalized paths. Separately, the release profile de-duplicates identical
trimmed CSS lines across the whole stylesheet, which can drop repeated `}`
lines inside multi-line blocks such as the glass `@supports` CSS.

## Batch D01 — November 26, 2026 (expression language, OD-036 / SF-1004, unverified, complete)

Decision record: ADR-0070 (Proposed). Restore point `RP-2026-11-26-D01` was
taken before this batch (other lanes may have been mid-batch). No document
schema, website metadata, clipboard, history or project-file change.

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New, inserted before `DocumentSerializationError`: `SiteExpressionType`, `SiteExpressionDate` (`init?(year:month:day:)`, `init?(iso:)`, `iso`, Codable as `YYYY-MM-DD`), `SiteExpressionValue` (`type`, `renderedText`), `SiteExpressionSourceRange`, `SiteExpressionError` (`Category`, `recoverySuggestion`), `SiteExpressionUnaryOperator`, `SiteExpressionBinaryOperator`, `SiteExpressionSyntax`, `SiteExpressionNode`, `SiteExpressionSchema`, `SiteExpressionContext`, `SiteExpressionProgram` (fileprivate init), `SiteExpressionDecision`, `SiteExpressionRuntimeFinding`, `SiteExpressionEvaluation`, `SiteExpressionDiagnostic`, `SiteExpression` (stored record, version 1, exact keys), `SiteExpressionEngine` (`parse`, `check`, `evaluate`, `diagnostic`, `numberText`, limits, `functionSignatures`, `functionNames`); private `SiteExpressionToken`, `SiteExpressionLexeme`, `SiteExpressionLexer`, `SiteExpressionParser`, `SiteExpressionEvaluator`. |
| `Tests/SiteForgeTests/BlankProjectTests.swift` | 3 new tests before `testNavigatorAccessibilityIdentityComesOnlyFromStablePageIdentity`. |
| `docs/architecture-decisions/ADR-0070-expression-language.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-036 implementation status line. |

New selectors:

```
SiteForgeTests/BlankProjectTests/testExpressionLanguageTransformsTextNumbersDatesAndExplainsWhichRuleWon
SiteForgeTests/BlankProjectTests/testExpressionLanguageRejectsInvalidInputWithLocatedErrorsAndStaysBounded
SiteForgeTests/BlankProjectTests/testStoredExpressionRoundTripsExactKeysAndKeepsIntentWhenAFieldIsRemoved
```

No UI tests were added, so `scripts/ci-ui-timings.txt` is unchanged. No UI in
this batch; the authoring UI comes with template bindings (D03).

Suggested first checks: implicit member `.text` returned as
`SiteExpressionType?` in `SiteExpressionValue.type`; `Unicode.Scalar`
comparisons with character literals in the lexer; `String(format: "%.Nf")`
output; the 10,000-evaluation loop time in the second test.

## Batch 18 part 1 — November 26, 2026 (local named snapshots, OD-043 / SF-1301, unverified, partial)

Decision record: ADR-0038 (Proposed). Restore point `RP-2026-11-26-11` was
taken before this batch. No document schema, package version, history schema,
clipboard or project-file format change (snapshots are new optional package
members `snapshots/index-v1.json` and `snapshots/<id>.json`).

| File | Change |
|---|---|
| `SiteForge/ProjectPackage.swift` | New at the end: `ProjectSnapshotIdentifierDomain`, `ProjectSnapshotID`, `ProjectSnapshotEntry` (exact keys), `ProjectSnapshotIndex` (version 1, exact keys, `validate()`, bounds), `ProjectSnapshotError`, `ProjectSnapshotOperation`, `ProjectSnapshotDiagnosticRecord`, `ProjectSnapshots` (`validatedName`, `nameKey`, `digest`, `index(in:documentID:)`, `list`, `creating`, `renaming`, `deleting`, `removingAll`, `document(for:…)`, `restoreCommand(to:from:resources:)`). |
| `SiteForge/DocumentLifecycle.swift` | `DocumentLifecycleController`: `snapshotDiagnostics`, `snapshotDiagnosticRecords`, `projectSnapshots()`, `createProjectSnapshot(named:)`, `renameProjectSnapshot(_:to:)`, `deleteProjectSnapshot(_:)`, `deleteAllProjectSnapshots()`, `restoreProjectSnapshot(_:keepingCurrentAs:)`, private `performSnapshotOperation`, `noteSnapshotsChanged()`. Inserted after `projectResourceDescriptor(for:)`. |
| `Tests/SiteForgeTests/ProjectPackageTests.swift` | 1 new test before `testUnknownOptionalMemberIsPreservedByteForByteAcrossRoundTrip`. |
| `Tests/SiteForgeTests/DocumentLifecycleTests.swift` | 2 new tests before the private `makeController` helper. |
| `docs/architecture-decisions/ADR-0038-local-named-snapshots.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-043 implementation status line. |

New selectors:

```
SiteForgeTests/ProjectPackageTests/testNamedSnapshotsAreStrictBoundedAndRoundTripThroughThePackage
SiteForgeTests/DocumentLifecycleTests/testSnapshotRestoreCommandIsOneNewUndoableTransaction
SiteForgeTests/DocumentLifecycleTests/testNamedSnapshotsSaveReopenRestoreToANewHeadUndoAndRecover
```

No UI was added (planned as batch 18 part 2), so no UI test and
`scripts/ci-ui-timings.txt` is unchanged. `DocumentLifecycleController.requirementIDs`
and `ProjectPackageStore.requirementIDs` are unchanged; the SF-1301 IDs are on
`ProjectSnapshots.requirementIDs`.

Suggested first checks: multi-statement closure type inference for the
generic `performSnapshotOperation` calls (Void and `ProjectSnapshotEntry`
results); the restore `batch` passing `PersistedHistoryStore` validation on
reopen (third controller in the lifecycle test) and the component transition
checks in `DocumentSession.commit`; the 75% package budget arithmetic in
`ProjectSnapshots.creating`.

## Batch 17 — November 26, 2026 (custom code, OD-041 / SF-1107, unverified, complete)

Decision record: ADR-0037 (Proposed). Restore point `RP-2026-11-26-10` was
taken before this batch. Website metadata version 3, still document schema 27.

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New `CustomCodeBlock` (`make`, `isValid`, `containsScript`, exact keys). `PageWebsiteMetadata.customCode` (key written only when set; accepts the old key set). `WebsiteMetadata` version 3: `customCode`, `versionWithoutCustomCode`, `VersionTwoCodingKeys`, `usesCustomCode`; page code refused in version 1/2 records. Schema-27 gate also covers `usesCustomCode`. `invalidWebsiteMetadata` message adds the custom code rule. |
| `SiteForge/CanvasRendererCore.swift` | New `CustomCodeOutput`; `MultiPageStaticBuildPlanner.plan(…, includesCustomCode: false)` writes head/style/body code; `StaticBuildCompiler.compile(…, includesCustomCode: true)` on both overloads; new `customCodeFindings(document:included:)`; `deferredCapabilities` no longer lists `custom-code`. |
| `SiteForge/BrowserPreview.swift` | Both `BrowserWebsiteBuilder.prepare` overloads pass `includesCustomCode: false`. |
| `SiteForge/WorkspaceShellView.swift` | `WebsiteSettingsView`: site custom code state, `PageDraft` code fields, `pageDraft(_:)`, `customCodeSection(…)`, `codeEditor(…)`; sections on the Website and page forms. |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | 1 new test. Batch 14 test updated for version 3: `currentVersion` 3, the version-1 conversion also removes `customCode`, the unknown-version forgery uses 4. |
| `Tests/SiteForgeTests/CanvasRendererTests.swift` | 1 new test. |
| `docs/architecture-decisions/ADR-0037-custom-code.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-041 implementation status line. |

New selectors:

```
SiteForgeTests/PersistedHistoryTests/testCustomCodeIsStrictVersionedSchemaGatedUndoableAndRemovedWithItsPage
SiteForgeTests/CanvasRendererTests/testCustomCodeIsWrittenVerbatimToBuildsAndLeftOutOfPreview
```

Suggested first checks: tests elsewhere that build website metadata JSON by
hand with version 2; `TextEditor` modifiers (`scrollContentBackground`,
`autocorrectionDisabled`) on the deployment target; the custom code sections
inside the Website Settings sheet height.

## Foundation check — November 26, 2026 (before batch 16)

Static source checks over every readable Swift file under `SiteForge/` and
`Tests/` (Code Forge has no compiler): string and comment lexing, brace,
parenthesis and bracket balance per file, duplicate top-level type names,
duplicate test method names, and switch statements that list most but not all
cases of a known enum without `default`. Result: no balance errors, no
duplicate types or tests; the five switch hits were checked by hand and are
complete (several cases per line). `SupportSettingsTests.swift` was not
readable (iCloud placeholder) and was not checked. These checks do not replace
compilation.

## Batch 16 — November 26, 2026 (feature flags, OD-047 / SF-1803, unverified, complete)

Decision record: ADR-0036 (Proposed). Restore point `RP-2026-11-26-09` was
taken before this batch. No schema, clipboard, history or project-file change.

| File | Change |
|---|---|
| `SiteForge/SupportSettings.swift` | New `FeatureFlagID`, `FeatureFlagDate`, `FeatureFlagDefinition`, `FeatureFlagRegistry` (`definitions`, `definition(_:)`, `issues(in:today:)`, `Issue`), `FeatureFlagOverrides` (version 1, exact keys), `FeatureFlagSource`, `FeatureFlagResolution`, `FeatureFlagResolver`, `FeatureFlagDiagnostic`, `@MainActor FeatureFlagStore` (`shared`, draft/committed, `apply`, `cancel`, `useDefault`, `restoreAllDefaults`, `reload`, `isEnabled`), `FeatureFlagSettingsView`. Settings root: `@StateObject features`; Advanced shows Testing then Features. |
| `SiteForge/BrowserPreview.swift` | `BrowserPreviewPanel` gains `@ObservedObject var features: FeatureFlagStore = .shared`; Export Zip… shown only when `export.zip-archive` is on. |
| `SiteForge/WorkspaceShellView.swift` | `StaticBuildDiagnosticsView` gains the same property; Build Zip Archive… gated the same way. |
| `Tests/SiteForgeTests/CanvasSettingsTests.swift` | 2 new tests and a private `flagDate(_:)` helper at the end of the class. |
| `docs/architecture-decisions/ADR-0036-feature-flags.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-047 implementation status line. |

New selectors:

```
SiteForgeTests/CanvasSettingsTests/testFeatureFlagRegistryIdentifiersOwnersAndRemovalDatesAreValid
SiteForgeTests/CanvasSettingsTests/testFeatureFlagStoreDraftApplyCancelPersistenceLaunchOverrideAndCorruptRecovery
```

No UI tests were added, so `scripts/ci-ui-timings.txt` is unchanged. The new
UserDefaults key is `SiteForgeFeatureFlags.v1`; tests use a private suite.

Suggested first checks: the default-valued `@ObservedObject var features`
property in the two views (memberwise initializer and main-actor default
value); UI tests that inspect the Advanced settings page layout.

## Batch 15 — November 26, 2026 (zip export target, OD-042 / SF-1209, unverified, partial)

Decision record: ADR-0035 (Proposed). Restore point `RP-2026-11-26-08` was
taken before this batch. No schema, clipboard, history or project-file change.

| File | Change |
|---|---|
| `SiteForge/CanvasRendererCore.swift` | New `StaticExportTarget` (`folder`, `zipArchive`); new `StaticSiteZipArchive` (`archive(_:cancellation:)` deterministic stored ZIP, `storedEntries(_:)` verifying reader, `crc32`, `isSafeEntryPath`); new `LocalStaticBuildWriter.writeZipArchive(…)` (stage, read back, verify, promote); new `LocalStaticBuildWriteError.archiveTooLarge`. |
| `SiteForge/BrowserPreview.swift` | `import UniformTypeIdentifiers`; `BrowserWebsiteBuilder.export(…, target:)`; `BrowserPreviewController.export(…, target:)` with zip status and `archiveTooLarge` message; **Export Zip…** button (`preview.website.exportZip`) and save panel. |
| `SiteForge/WorkspaceShellModel.swift` | `StaticBuildWorker.write(…, target:)`; `writeStaticBuild(…, target:)` with zip success status and `archiveTooLarge` message. |
| `SiteForge/WorkspaceShellView.swift` | Check Website: **Build Zip Archive…** (`build.writeZip`); `chooseDestination(target:)` restricts the panel to zip. |
| `Tests/SiteForgeTests/CanvasRendererTests.swift` | 3 new tests after `testLocalStaticBuildWriterStagesDeterministicOutputAndRejectsStale`. |
| `docs/architecture-decisions/ADR-0035-zip-export-target.md` | New. |
| `docs/OPEN_DECISIONS.md` | OD-042 implementation status line. |

New selectors:

```
SiteForgeTests/CanvasRendererTests/testZipExportArchiveIsDeterministicStoredAndRoundTripsEveryPlanFile
SiteForgeTests/CanvasRendererTests/testZipExportWriterStagesVerifiesReplacesAndRefusesUnsafeTargets
SiteForgeTests/CanvasRendererTests/testBrowserPreviewZipExportUsesTheSuccessfulPreviewPlan
```

No UI tests were added, so `scripts/ci-ui-timings.txt` is unchanged.

Not done (still open under OD-042): one hashed runtime script. The runtime
still ships as `siteforge-effects.js` and `siteforge-navigation.js`; about 20
test assertions, one UI test selector and `Tests/Tooling/flow_runtime_browser.py`
name them. That Python file, `test_flow_runtime_browser.py`,
`SupportSettingsTests.swift`, `docs/TESTING.md` and `.github/workflows/ci.yml`
could not be read from this iCloud copy on Windows (not downloaded locally), so
they were not checked or changed.

Suggested first checks: the two exhaustive switches over
`LocalStaticBuildWriteError` that gained `.archiveTooLarge` (any other switch
outside the files read here would fail to compile); `Swift.withUnsafeBytes`
inside the private `Data` extension; the archive opening in Archive Utility and
`unzip -t`.

## Owner decisions — November 26, 2026 1:30 PM EST (recorded by Code Forge)

The owner approved the recommended defaults of OD-001, OD-013, OD-014, OD-017
and OD-035 through OD-047 (`docs/OPEN_DECISIONS.md`, Status lines). OD-012
(publisher identity and bundle identifier) stays open. No code was written for
OD-035–OD-047; each needs its own planned batch. OD-017 still needs the
Developer ID team, update-signing key owner and feed URL before Install is enabled.

## Batch 14 — November 26, 2026 (social previews, sitemap, robots, SEO warnings, SF-1207, unverified, complete)

Decision record: ADR-0034 (Proposed). `WebsiteMetadata` version 2 shares
document schema 27 with batches 09–10 (none released).

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | `WebsiteMetadata` version 2: `siteURL`, `socialImageAssetID`, `usesSocialFields`, `validSiteURL`; strict decoding of version 1 and 2 key sets; schema-27 gate; error message. |
| `SiteForge/ProjectResources.swift` | `ImageAssetReference.Kind.socialImage`; retarget updates the social image. |
| `SiteForge/CommandKernel.swift` | Removing the social image asset is refused with a reason. |
| `SiteForge/CanvasRendererCore.swift` | `StaticSEOEmitter.head(_:route:siteURL:socialImagePath:)` (Open Graph / Twitter tags, absolute canonical), `sitemap`, `robots`, `escape`; new `StaticSEOAudit` (warnings). Export writes `robots.txt` always and `sitemap.xml` with an address; the social image is exported; `social-image-missing` error. |
| `SiteForge/BrowserPreview.swift` | Content types for `txt` and `xml`. |
| `SiteForge/WorkspaceShellModel.swift` | Delete with Uses and the usage filter include the social image. |
| `SiteForge/WorkspaceShellView.swift` | Website Settings: Sharing section (site address with validation, social image), page Shared Link Preview and length note. |
| `Tests/SiteForgeTests/CanvasRendererTests.swift` | 1 new test. |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | 1 new test. |
| `docs/architecture-decisions/ADR-0034-social-previews-sitemap-robots.md` | New. |

New selectors: `CanvasRendererTests/testSocialPreviewTagsSitemapRobotsAndSEOWarningsInExport`,
`PersistedHistoryTests/testWebsiteMetadataVersionTwoSiteAddressAndSocialImageAreStrictAndTracked`.

Suggested first checks: existing tests that compare exported file lists now
see `robots.txt`; `WebsiteMetadata` decoding inside persisted history commands
(older history entries hold version 1 records); the `og:image` path format.

## Batch 13 — November 26, 2026 (asset dependencies, SF-0807, unverified, complete)

Finding: Replace Asset Everywhere (new bytes for the same asset), Reveal Usage
(first use) and delete-with-uses already exist. Added: the full list of uses,
moving every use to another existing asset, and removing unused assets. No
schema, clipboard or history change.

| File | Change |
|---|---|
| `SiteForge/ProjectResources.swift` | New `ImageAssetDependencies` (`unusedAssetIDs(in:)`, `retarget(from:to:in:expectedRevision:isLifecycleAvailable:)` — Image asset, image fill, component media values and favicon in one batch, same property identities, QR codes refused; `removeUnused(…)`). |
| `SiteForge/WorkspaceShellModel.swift` | `imageAssetReferences(_:)`, `revealImageAssetReference(_:)`, `useOtherImageAsset(instead:target:)`, `unusedImageAssetCount`, `removeUnusedImageAssets()`. |
| `SiteForge/WorkspaceShellView.swift` | Asset row menu: Uses (N) with each use, Use Another Asset Instead. Library: Remove N Unused Assets (confirmed). |
| `Tests/SiteForgeTests/ProjectResourceTests.swift` | 1 new test. |

New selector: `ProjectResourceTests/testAssetUsesRetargetToAnotherAssetAndUnusedAssetsAreRemovedInOneStep`.

## Batch 12 — November 26, 2026 (value sources, SF-0704, unverified, complete)

Finding: per-field source captions already exist (geometry, sizing, layout,
appearance, box styles, component values). Missing: one trace in engine order
per setting, jump to the source, and clearing the winning value. Added here.
No schema, clipboard or history change.

| File | Change |
|---|---|
| `SiteForge/TransformModel.swift` | New `ValueTraceSetting` (x, y, width, height, visibility, opacity, text size, line height; `applicable(to:)`), `ValueTraceStep` (`Source`: default, Desktop, linked style, local, fluid, breakpoint, container-query rule), `ValueTrace` (`winner`, `canClearWinner`), `CanonicalValueTrace` (`trace(…)` in engine order: geometry Desktop → fluid → breakpoint → container query; visibility Desktop → breakpoint → container query; opacity default → linked styles → own → container query; text default → own → fluid → container query; `describe`, `clearWinner` returning one command or a specific refusal). Container-query refusal message for fluid text. |
| `SiteForge/DocumentModel.swift` | **Fix to batch 09:** `CanonicalContainerQueries.accepts` refuses text size / line height rules on text that uses fluid size / line height (on the canvas fluid would win, in CSS the rule would win). |
| `SiteForge/WorkspaceShellModel.swift` | `valueTraceAnnouncement`, `valueTrace(_:)`, `valueTraceSettings`, `clearWinningValue(_:)`, `clearWinningValueAvailability(_:)`, `revealValueSource(_:)` (breakpoint, container, linked style). |
| `SiteForge/WorkspaceShellView.swift` | Layout tab: `ValueTraceInspectorView` (one disclosure per setting: winner and source, every step, Show, Clear Winning Value). |
| `Tests/SiteForgeTests/CommandKernelTests.swift` | 1 new test. |
| `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift` | New journey. |
| `scripts/ci-ui-timings.txt` | Row `testValueSourcesShowWinnerAndClearItJourney 50` (**estimate**; spread 5 s). |

New selectors: `CommandKernelTests/testValueTraceMatchesEnginePrecedenceAndClearsTheWinnerInOneStep`,
`SiteForgeUITests/testValueSourcesShowWinnerAndClearItJourney`.

## Batch 11 — November 26, 2026 (relative multi-object geometry edits, SF-0703, unverified, complete)

Finding: most of SF-0703 already exists in source (applicable subset with
skipped counts, Mixed values for geometry, sizing, typography, color, opacity,
fill, tokens and box styles; one transaction per edit). It has no records in
`REQUIREMENT_EVIDENCE.json`. The missing piece was relative edits, added here.
No schema, clipboard or history change.

| File | Change |
|---|---|
| `SiteForge/TransformModel.swift` | `GeometryInspectorCommand.relativeDelta` (defaulted). New `GeometryInspectorRelativeInput.delta(_:locale:)` (`+=N`, `-=N`, `−=N`; non-zero finite only). `GeometryInspectorCommandRegistry.prepare` computes each object's value from its own value at the command's breakpoint; out-of-range results are skipped (reported), never clamped. |
| `SiteForge/WorkspaceShellModel.swift` | `commitGeometryInspectorValue(…relativeDelta:)`; announcement "X changed by +15 on 2 objects; …". |
| `SiteForge/WorkspaceShellView.swift` | Geometry fields accept `+=` / `-=` (hint and help text say so). |
| `Tests/SiteForgeTests/TransformModelTests.swift` | 1 new test. |

New selector: `TransformModelTests/testRelativeGeometryEditChangesEachObjectFromItsOwnValueInOneTransaction`.

## Batch 10 — November 26, 2026 (responsive audit, SF-0606, unverified, complete)

Decision record: ADR-0032 (Proposed). Suppressions share document schema 27
and clipboard version 8 with batch 09 (neither is released).

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New `CanonicalResponsiveAuditSuppression` (`responsive.audit.v1.suppressed`, `kinds`, `suppressedKinds(of:)`, `encoded`, strict `validate`); page validation calls it; the schema-27 gate covers its namespace; the `invalidContainerQueryState` message covers it. |
| `SiteForge/CanvasRendererCore.swift` | New `ResponsiveAuditSample` (`standard`), `ResponsiveAuditFindingKind`, `ResponsiveAuditFinding` (stable `id`, `explanation`, `repair`), `ResponsiveAuditReport`, `CanonicalResponsiveAudit.findings(page:canonicalPage:objects:sample:checkpoint:)` (overflow, collision, truncation, tap target 24 pt, unreachable override). |
| `SiteForge/WorkspaceShellModel.swift` | New `ResponsiveAuditRunner.run(document:pageID:samples:)`. Workspace: `responsiveAuditReport`, `isRunningResponsiveAudit`, `responsiveAuditStatus`, `isResponsiveAuditPresented`, `currentResponsiveAuditReport`, `runResponsiveAudit`, `cancelResponsiveAudit`, `revealResponsiveAuditFinding`, `setResponsiveAuditFinding(_:suppressed:)`, `responsiveAuditSuppressionAvailability`. |
| `SiteForge/TransformModel.swift` | New `ResponsiveAuditSuppressionRegistry`. |
| `SiteForge/ClipboardTransfer.swift` | Version 8 also carries the suppression namespace. |
| `SiteForge/WorkspaceShellView.swift` | Compare Screen Sizes: `ResponsiveAuditSection` (Run/Run Again/Cancel, status, show suppressed, list) and `ResponsiveAuditFindingRow` (Show, Intentional/Report Again). |
| `Tests/SiteForgeTests/CanvasRendererTests.swift` | Fixture `responsiveAuditDocument()`; 2 new tests. |
| `Tests/SiteForgeTests/CommandKernelTests.swift` | 1 new test. |
| `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift` | New journey. |
| `scripts/ci-ui-timings.txt` | Row `testResponsiveAuditFindsOverflowSuppressesAndUndoJourney 90` (**estimate**; spread 5 s). |
| `docs/architecture-decisions/ADR-0032-responsive-audit.md` | New. |

New selectors (3 + 1 UI): `CanvasRendererTests/testResponsiveAuditReportsEachKindAtItsExactWidthAndHonorsSuppression`,
`CanvasRendererTests/testResponsiveAuditStaysWithinBoundsOnStandardAndLargeFixtures`,
`CommandKernelTests/testResponsiveAuditSuppressionIsStrictAndOneUndoableChange`,
`SiteForgeUITests/testResponsiveAuditFindsOverflowSuppressesAndUndoJourney`.

Suggested first checks: canvas world coordinates of objects at Tablet and
Mobile (the overflow check compares against the sample width from x = 0); the
stress fixture is not audited (the audit is per page; the 20,000-object page
limit is the renderer's); text measurement off the main actor.

## Batch 09 — November 26, 2026 (container queries, SF-0605, unverified, complete)

**Owner instruction:** 2026-11-26 4:12 AM and 12:16 PM EST: finish the remaining
code without asking. Decision record: ADR-0031 (Proposed). No owner product
decision was needed (an editor capability in the existing responsive model).

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New `ContainerQueryRuleID`, `CanonicalContainerQueryRule` (`matches(width:)`, `rangeDescription`), `CanonicalContainerQueries` (namespace `responsive.query.v1.`, `containerKey`, `rulesKey`, `ruleKey`, `setKey`, `isValidName`, `containerName(of:)`, `isActiveContainer`, `hasRules`, `accepts`, strict `rules(on:)`, `validate(_:parent:)`; limits 8 rules, widths 0–100,000 whole points). Page validation calls it. `ModelValidationError.invalidContainerQueryState`. Document schema 27; schema 26 accepted; older files carrying the namespace rejected. |
| `SiteForge/InsertionModel.swift` | New `ContainerQueryFinding` (codes `container-query-no-container`, `container-query-container-hugs`), `ContainerQueryRuleStatus`, `ContainerQueryEvaluation`; `CanonicalContainerQueries.container(for:of:nodesByID:findings:)`, `evaluated(_:breakpoint:viewportWidth:availablePageIDs:)` (widths measured once, rules in order, later wins), `setting(_:on:breakpoint:)` (also writes the breakpoint's own visibility/width/height key), `cssDeclaration`, `cssName`. |
| `SiteForge/WorkspaceShellModel.swift` | Scene preparation (canvas and Preview) evaluates container queries on the expanded page. Workspace: `containerQueryAnnouncement`, cached `containerQueryEvaluation`, `containerQueryTarget`, `performContainerQueryEdit`, `containerQueryEditAvailability`. |
| `SiteForge/CanvasRendererCore.swift` | New `StaticContainerQueryOutputEmitter`; its output is appended last to `styles.css`. |
| `SiteForge/TransformModel.swift` | New `ContainerQueryEdit`, `PreparedContainerQueryEdit`, `ContainerQueryCommandRegistry` (container name, add rule, range, rule container, set/remove value, move, remove; specific refusals). |
| `SiteForge/ClipboardTransfer.swift` | `versionWithContainerQueries = 8` (current), `carriesContainerQueries`; older headers carrying it are refused. |
| `SiteForge/WorkspaceShellView.swift` | Layout tab: `ContainerQueryInspectorView` (container name, state, rules with status, range, container, settings, move/remove, Add Rule) and `ContainerQueryRuleView`. |
| `Tests/SiteForgeTests/CommandKernelTests.swift` | Fixture `containerQueryFixture()`; 3 new tests. **Changed** `testComponentVariantsRoundTripAndRequireSchemaTwentySix` (current schema at least 26). |
| `Tests/SiteForgeTests/CanvasRendererTests.swift` | Fixture `containerQueryCardDocument(hugRoot:)`; 2 new tests. |
| `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift` | New journey. |
| `scripts/ci-ui-timings.txt` | Row `testContainerQueryContainerRuleStatusAndUndoJourney 70` (**estimate**; 8-shard spread 5 s). |
| `docs/architecture-decisions/ADR-0031-container-queries.md` | New. |

New selectors (5 + 1 UI): `CommandKernelTests/testContainerQueriesUseOneStrictEncodingAndRequireSchemaTwentySeven`,
`CommandKernelTests/testContainerQueryEvaluationIsOrderedNearestFirstAndBeatsBreakpointValues`,
`CommandKernelTests/testContainerQueryEditsAreOneUndoableTransactionEachWithSpecificRefusals`,
`CanvasRendererTests/testContainerQueriesFollowEachCopysContainerOnCanvasPreviewAndExport`,
`CanvasRendererTests/testContainerQueriesStayWithinBoundsOnStandardLargeAndStressFixtures`,
`SiteForgeUITests/testContainerQueryContainerRuleStatusAndUndoJourney`.

Suggested first checks: the definition root's container name and sizing keys
reach each expanded copy root (the card fixture relies on it); the CSS selector
of expanded objects is their derived identity; the Inspector section's
SwiftUI type-checking time.

## Batch 08 — November 26, 2026 (package v2 page members, OD-032, unverified, complete)

**Owner instruction:** OD-032 approved 2026-11-25 3:57 PM EST; overnight run
2026-11-26 ("do not stop until all features are completed"). Decision record:
ADR-0030. One member per page was not possible within the 256-member bound, so
pages are packed in order into members of at most 4 MiB.

| File | Change |
|---|---|
| `SiteForge/ProjectPackage.swift` | New `ProjectPackagePageSplit` (`marker`, `memberPath`, `memberIndex`, `split(envelope:pages:memberLimit:)`, `join(root:members:checkpoint:)` with JSON-array validation of every member and a marker-position check), `ProjectPackageMeasurement` (`fileBytes`, `largestPageBytes`, `packageVersion`). `ProjectPackageMemberRole.pages`. `ProjectPackage.currentPackageVersion = 2`, `singleMemberPackageVersion = 1`. `makeMeasuredContainer` writes v1 when the document fits one member (unchanged bytes) and v2 otherwise; manifest compatibility follows the written format; optional members may not use the page prefix or role. `parseContainer` accepts v1 and v2, requires header and manifest versions to agree, validates page members (`pageMemberPaths`: `pages/NNNN.json` without gaps, role `pages` only there; none in v1; v2 must declare minimum reader 2) and joins them before the unchanged strict decode; page members are not returned as optional members. `writeMeasured` returns the measurement. `pageMeasurementFraction = 0.85`. All existing limits unchanged. |
| `SiteForge/DocumentLifecycle.swift` | `CompletedPackageWrite.measurement`. `ProjectFileCapacity` now measures the written file against `maximumPackageBytes` (8 MiB) and the largest page against `maximumMemberBytes - 2`: `fileBytes`, `largestPageBytes`, `fileLimitBytes`, `pageLimitBytes`, `isPageLimited`, `init(_ measurement:)`; status "Largest page N% full" when the page limit is closer. `projectTooLarge` message names both limits. (`documentBytes` and `limitBytes` removed.) |
| `SiteForge/WorkspaceShellView.swift`, `SiteForge/WorkspaceShellModel.swift` | Comments only (capacity limits; stress fixture). |
| `Tests/SiteForgeTests/ProjectPackageTests.swift` | Fixture `framedPackage(pages:framesPerPage:)`; 3 new tests (below). |
| `Tests/SiteForgeTests/DocumentLifecycleTests.swift` | Fixture `framedDocument(pages:framesPerPage:)`. **Changed** `testProjectTooLargeSaveAndAutosaveAreRefusedTruthfullyWithoutWriting` (now one 9,000-frame page above the page limit; the stress fixture may now save) and `testProjectFileCapacityIsMeasuredOnSaveAndAutosaveAndWarnsNearTheLimit` (file and page limits; measures the written file and recovery file). New test (below). |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | **Changed** `testProjectPreferencesPersistAtLargeFixtureAndRespectPackageLimitAtStress`: the stress branch follows whether the package actually encodes within the file limit. |
| `docs/architecture-decisions/ADR-0030-package-v2-page-members.md` | New (Proposed). |
| `docs/OPEN_DECISIONS.md` | OD-032 implementation status. |

New selectors (4): `ProjectPackageTests/testPackageVersionTwoSplitsALargeDocumentIntoBoundedPageMembersAndRoundTrips`,
`ProjectPackageTests/testPageSplitPacksWholePagesInOrderAndRefusesTamperedMembers`,
`ProjectPackageTests/testPackageVersionTwoReaderRefusesMalformedPageMembers`,
`DocumentLifecycleTests/testProjectAboveOneMemberSavesAsPackageVersionTwoAndReopensIdentically`.

Suggested first checks when building:
1. `split` relies on each page encoding identically alone and inside the
   envelope (same `JSONEncoder` settings); if not, every save above 4 MiB fails
   with `corruptDocument` and the v2 tests show it.
2. Fixture sizes are estimates (about 680 bytes per frame): each test asserts
   its size precondition first.
3. Callers outside the files above that used `ProjectFileCapacity.documentBytes`
   or `.limitBytes`, or the tuple label `documentBytes` from `writeMeasured`
   (none found in source or tests on this copy).
4. ProjectPackage.swift stays in the headless model slice: it references no
   lifecycle type.

## Batch 07 — November 26, 2026 (component variants, OD-033, unverified, complete)

**Owner instruction:** 1:55–1:59 AM EST: Code Forge builds features with Codex
verifying; variants before Fast visual styling; work continues overnight
without check-ins. Plan and requirement contract:
`PROMPT_2026-11-26_OD-033_VARIANTS` (same text as the Codex prompt given to the
owner): property-only variants, edit inside the variant, structure only in the
base. Starting point: restore point `RP-2026-11-26-07` (after Codex's Quick
batch integrity repair; `.git` and `.codex-loop` not copied).

Write path note: files Codex changed on the Mac cannot be read by Code Forge's
on-device scripts on Windows, so every Batch 07 file is written whole with the
file tools and read back byte for byte. Five files are iCloud placeholders on
Windows and were neither read nor written (`.github/workflows/ci.yml`,
`docs/TESTING.md`, `Tests/SiteForgeTests/SupportSettingsTests.swift`,
`Tests/Tooling/flow_runtime_browser.py`, `Tests/Tooling/test_flow_runtime_browser.py`).

### Milestone 1 — model, validation, document schema 26, resolution

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New `ComponentVariantAxisID`, `ComponentVariantValueID`, `CanonicalVariantValue`, `CanonicalVariantAxis`, `CanonicalVariantCombination` (canonical key: value IDs in axis order joined by `+`), `CanonicalVariantTarget` (`value` / `combination`), `CanonicalVariantSet` (combinations, allowed check, precedence targets, names), `CanonicalVariantChoiceSource`, `CanonicalVariantFinding` (codes `variant-axis-unavailable`, `variant-value-unavailable`, `variant-combination-not-allowed`), `CanonicalVariantResolution`, `CanonicalComponentVariants` (namespace `component.variant.v1.`; root metadata `axes`, `axis.<id>.name/values/default`, `value.<id>.name`, `disallowed`; node overrides `override.<target>.<key>` and `unset.<target>.<key>`; copy choices `component.instance.v1.variant.<axis>`; limits 4 axes, 2–16 values, 256 combinations, 4,096 overrides, 64 choices; `isVariantCapable` allow-list; strict `variantSet(in:)`, `overrides(on:)`, `resolvedNode`, `resolved`, `resolution(for:set:)`, `resolvedDefinition(_:for:)`, per-node `validate`, `validateDefinition` which validates each distinct authored variant with the same page rules). `CanonicalComponentReference.validate` accepts variant keys. Page validation calls both variant validators. `ModelValidationError.invalidComponentVariants`, `.componentVariantResolvesInvalid`. Inherited values in `CanonicalComponentOverrides.resolve` use the copy's variant. Serializer: current schema 26, schema 25 accepted as historical, older files carrying variant data or choices rejected. |
| `SiteForge/InsertionModel.swift` | `ComponentGraphResolver.expand` applies the copy's variant first (parameter renamed `definition source:`; external label unchanged): the one resolution point for canvas, Preview, export, detach and Customize. |
| `Tests/SiteForgeTests/CommandKernelTests.swift` | New fixture `variantFixture()` and helpers; 4 new tests (below). Existing `testSuppliedSlotContentAndEmptyStateValidateResolveAndRequireSchemaTwentyFive` now asserts the current schema is at least 25 (it pinned 25). |

New selectors (M1): `CommandKernelTests/testComponentVariantsUseOneStrictCanonicalEncodingWithinLimits`,
`testComponentVariantResolutionFollowsOnePrecedenceRuleAndKeepsUnavailableChoices`,
`testComponentVariantsRoundTripAndRequireSchemaTwentySix`,
`testComponentVariantThatWouldBeInvalidIsRejectedWithItsReason`.

### Milestone 2 — rendering parity and scale

No source change: `expand` is the single resolution point. New tests in
`Tests/SiteForgeTests/CanvasRendererTests.swift` (fixture
`variantButtonDocument(copies:)`):
`testComponentVariantsDrawOnCanvasPreviewAndExportIdentically` (text, child
width, opacity, a radius one variant removes; canvas, in-app Preview, static
HTML/CSS; a Button inside a Card keeps its own variant) and
`testComponentVariantsStayWithinBoundsOnStandardLargeAndStressFixtures` (49 /
4,999 / 9,990 copies across all four variants; validation and resolution within
safety bounds; no variant storage in drawn objects).

### Milestone 3 — commands, editing inside a variant, copy choice

| File | Change |
|---|---|
| `SiteForge/TransformModel.swift` | New `ComponentVariantEdit`, `ComponentVariantError`, `PreparedComponentVariantEdit`, `ComponentVariantCommandRegistry` (add/rename/move/remove axis and value, default, allowed combinations, Use Base Value, copy choice with size follow, reset choices; one batch of property commands each; stale, lifecycle, names, limits and default rules refuse; `copiesNeedingRepair`). `CanonicalComponentVariants.previewCombination`, `presentedDocument`, `source(of:on:set:combination:)`, `rewrite(_:definitionID:target:document:)` (the one edit conversion point). |
| `SiteForge/CommandKernel.swift` | `DocumentSession.authoringTransform` applied in `execute` only (history stores the converted command; undo/redo replay it). |
| `SiteForge/WorkspaceShellModel.swift` | **All 412 reads of `documentSession.document` now read `authoringDocument`** (identical except while a variant is edited, when the open definition is presented as that variant). New `variantEditingTarget`, `variantAnnouncement`, `authoringDocument` (cached per document/revision/definition/target), `editingComponentVariantSet`, `editVariant(_:)`, `performVariantEdit(_:definitionID:)` (bypasses the conversion point), `variantEditAvailability`, `selectedComponentVariants`, `variantSource(of:nodeID:)`. `editingComponentID` ends variant editing when it changes. Insertion is unavailable while a variant is edited. |
| `Tests/SiteForgeTests/CommandKernelTests.swift` | 4 new tests (below). |

### Milestone 4 — transfer and repair

| File | Change |
|---|---|
| `SiteForge/ClipboardTransfer.swift` | `versionWithVariants = 7` (current); `carriesVariantData`; a clipboard is v7 only when it carries variant data; older headers carrying it are refused; variant storage is definition-owned (stripped when copying out of a definition). |
| `Tests/SiteForgeTests/ClipboardTransferTests.swift` | Fixture `variantSourceDocument()`; new test (below). |
| `Tests/SiteForgeTests/CommandKernelTests.swift` | New detach/duplicate test (below). |

### Milestone 5 — on screen, journey, ADR

| File | Change |
|---|---|
| `SiteForge/WorkspaceShellView.swift` | Definition banner: `ComponentVariantEditingBar` (Editing picker `components.variant.editing`: Base, each value, each allowed combination; `Add Variants…`/`Variants…` popover). `ComponentVariantManager` (add property with comma-separated values, rename, reorder, remove with confirmation, values with Make Default/reorder/remove, allowed combinations toggles; every control disabled with the registry's reason). `ComponentVariantOverridesView` in the Inspector while a variant is edited (each variant-supplied setting with the rule that wins; Use Base Value for the edited variant). `ComponentVariantChoiceFields` in the copy Inspector (one picker per property, "Shows …", findings, Use Default Variant). `ComponentVariantSettingTitle`. Reset copy changes ignores variant choices. |
| `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift` | New journey `testComponentVariantCreateEditInsideVariantAndSwitchCopyJourney`. |
| `scripts/ci-ui-timings.txt` | Row `testComponentVariantCreateEditInsideVariantAndSwitchCopyJourney 110` (**estimate**; 8-shard spread 4 s). |
| `docs/architecture-decisions/ADR-0029-property-only-component-variants.md` | New (Proposed). |
| `docs/OPEN_DECISIONS.md` | OD-033 implementation status. |

#### Batch 07 handoff (everything for Codex)

New selectors (13 core + 1 UI): `CommandKernelTests` —
`testComponentVariantsUseOneStrictCanonicalEncodingWithinLimits`,
`testComponentVariantResolutionFollowsOnePrecedenceRuleAndKeepsUnavailableChoices`,
`testComponentVariantsRoundTripAndRequireSchemaTwentySix`,
`testComponentVariantThatWouldBeInvalidIsRejectedWithItsReason`,
`testVariantAxesValuesAndCombinationsAreEditedInOneUndoableTransactionEach`,
`testEditingInsideAVariantStoresItsSettingsAndKeepsStructureShared`,
`testCopyVariantChoiceIsOneUndoableStepAndFollowsTheVariantSize`,
`testWorkspaceEditsInsideAVariantAndReturnsToBaseOnExit`,
`testDetachPageAndDefinitionDuplicateKeepTheVariantACopyShows`;
`CanvasRendererTests` — `testComponentVariantsDrawOnCanvasPreviewAndExportIdentically`,
`testComponentVariantsStayWithinBoundsOnStandardLargeAndStressFixtures`;
`ClipboardTransferTests` — `testComponentVariantsTravelThroughClipboardAsVersionSevenAndCopiesKeepTheirChoice`;
`SiteForgeUITests` — `testComponentVariantCreateEditInsideVariantAndSwitchCopyJourney`.
Changed existing test: `testSuppliedSlotContentAndEmptyStateValidateResolveAndRequireSchemaTwentyFive`
(current schema at least 25).

Suggested first checks when building:
1. The `authoringDocument` replacement in `WorkspaceShellModel.swift`: any
   read that must stay on the stored project while a variant is edited.
2. Swift 6 isolation of `DocumentSession.authoringTransform` (non-Sendable
   closure stored on a `@MainActor` class) and the closure installed by
   `installVariantAuthoringTransform`.
3. `@Published private(set) var editingComponentID { didSet }` and the
   `didSet` calling `endVariantEditing()`.
4. SwiftUI type-checking time of `ComponentVariantManager` and
   `ComponentVariantChoiceFields` (pickers with optional tags).
5. Whether every Inspector edit path for appearance, geometry and text builds
   its commands from `authoringDocument` (so the conversion point sees the
   presented property identities); any path that does not will report
   "no changes" or stale identity while a variant is edited.

Out of scope (unchanged): transitions between variants, per-breakpoint variant
selection, structural variants, a variant picker in the Components panel (the
copy Inspector has it).

## Final review of batches 01–06 for code quality and Codex compatibility — November 25, 2026 (unverified)

**Owner instruction:** 7:16 PM EST, review everything once more for code
quality and compatibility with Codex's workflow and gate.

Compared the whole tree with restore point `RP-2026-11-25-01` (before any Code
Forge edit): 6 files added (2 Python tooling files, ADR-0027, ADR-0028, this
log, the batch 01 handoff), 41 changed, none removed; `SiteForge.xcodeproj`,
`AGENTS.md`, the scripts and Codex's `.codex-loop` were not touched.

Gate emulation (`./sf verify` → `scripts/check-repository.sh`, then build and
full tests):
- Ran here and passed: secret scan, traceability (441 records), authoring
  runway, layout, canvas-renderer and selection evidence checks.
- Applied by hand: every changed text file is UTF-8 with LF only, no trailing
  whitespace, a final newline and no blank line at the end (`git diff --check`);
  no empty TODO/FIXME; insertion, transform, snapping, inline-text and drag-drop
  evidence checks only read evidence JSON this work did not touch.
- `check-architecture-boundaries.py`: no model-slice file (the headless
  `swiftc -typecheck` list) imports a UI framework or uses a type or extension
  member defined only in a UI or clipboard file; fixture-root, Debug-argument,
  Open-panel and App-root rules unchanged; no editor session type became
  Codable.
- CI accounting: 176 UI tests, 176 timing rows, no duplicates; greedy 8-shard
  spread 3 s (limit < 10 s).
- `select-test-scope.py`: unchanged; changed files without a mapping
  (`ClipboardTransfer.swift`, `CanvasSettings.swift`, `SupportSettings.swift`,
  `DragDropModel.swift`, `PackagedSiteTemplate.swift`, `Tests/Tooling/*.py`)
  make the changed-scope level ask for the full gate, which is the intended
  verification for this work.
- ADR-0027/0028 follow `ADR-0000-template.md`; ADR and OD numbers are unique
  (the duplicate `OD-025` heading predates Code Forge).

Code-quality scan of all 10,043 added lines: no `as!`, `print`, `NSLog`,
`fatalError` (except the standard `init?(coder:)`), `DispatchQueue.main.sync`,
`@unchecked Sendable` or `nonisolated(unsafe)`; every new `static let` holds a
`Sendable` value; no added app declaration is unreferenced.

Fixed in this review:

| File | Change |
|---|---|
| `SiteForge/TransformModel.swift` | `customizedSlotContents` no longer force-unwraps the copied node's identity; it throws `TransformError.missingTarget`. |
| `Tests/SiteForgeTests/CommandKernelTests.swift`, `CanvasRendererTests.swift` | 7 dictionary force unwraps and 2 `try!` in Code Forge tests replaced with `XCTUnwrap`, so a broken expectation fails the test instead of crashing the test run. |
| Tests (5 files) | 13 comments that named batches, milestones or "Code Forge review" now cite only requirement and decision IDs. |
| `docs/CODEX_HANDOFF.md` | Heading and link text said "batches 01–02"; now "01–06" with a pointer to this log. No status, changelog or queue change. |

Residual risks (not testable here): Swift type-checking time of the larger
SwiftUI bodies (`ComponentSlotFallbackFields`, `ProjectSettingsView`); the
stress-scale tests add to the 40-minute non-UI CI step; and everything listed
under each batch's open risks.

## Review of batches 02 and 03 against the current code — November 25, 2026 (unverified)

**Owner instruction:** 6:58 PM EST, review batches 02–03 the same way as
batches 04–06. Diffs were rebuilt from restore points `RP-2026-11-25-02`,
`-03` and `-04`.

Checked, no change needed:
- Batch 03: every `DocumentCommand` switch covers `.setProjectPreferences`;
  persisted history v4 payload shape and v1–v3 migration; strict document key
  set for schemas 18–21 vs 22+ (later schemas 23–25 add no document keys);
  `SettingsDestination` switches include `.project`; the names the Project pane
  uses exist (`WindowGroup` id `workspace`, `ActiveWorkspaceResolver`,
  observed `isPreviewPresented` / `lifecycle.phase`, view helpers, diagnostics
  sanitizer); the save-limit mapping (resource blobs are not package members, so
  `oversizedInput` on write can only be `document.json` or a bounded member);
  grid density floor leaves the default grid's intervals unchanged at every
  zoom band.
- Batch 03 test expectations traced against the code: the Settings store test
  (asynchronous document observation drained with `drainMainQueue`), workspace
  grid adoption (the workspace's own listener is dispatched to the next main
  turn, so the test's explicit calls decide), busy/invalid/repair test (Preview
  reason text), stress fixture (blank pages are single-root; no page-count limit
  exists).
- Batch 02 test expectations traced against the code: premultiplied
  interpolation and coincident-stop sampling, Flow eligibility (64-stop cap),
  page budget (four enabled flows; a fifth is `flow-configuration-unavailable`
  and the planner throws), runtime configuration; the fixture APIs used by the
  browser bridge test exist with matching shapes.
- Mechanical scan of members, argument labels and initializer labels in all
  batch 02–03 tests: no mismatches (trailing-closure calls and computed
  properties excluded by hand).

Still open (unchanged, listed in the batch 02–03 entries below): the browser
harness needs Google Chrome at `/Applications/Google Chrome.app` (or
`SITEFORGE_CHROME`) on the test host and was never run; its pixel thresholds
are reasoned, not measured; the large-fixture save test expects `document.json`
under 4 MiB from an estimate (~3.6 MiB).

## Review of batches 04 and 05 (milestones 1–2) against the current code — November 25, 2026 (unverified)

**Owner instruction:** 6:46 PM EST, review batch 04 and batch 05 milestones 1–2
again, now that batches 05–06 have changed the code around them.
Method: re-read the batch 04 and batch 05 M1–M2 hunks; matched every pattern
match on the changed `AdvancedStyleEdit` cases; checked the stored box keys
that Use Linked Border/Corners/Shadow removes; checked the schema list in the
loader (22–25 accepted), clipboard version choice, export call sites and the
CSS strings the tests expect against the emitters' number formatting; checked
that every member, function argument label and initializer label used by the
tests of batches 04–06 exists in the code (mechanical scan; system APIs
excluded); checked every identifier the batch 03–04 UI journeys use.

Finding (cross-batch, introduced by batch 06), fixed:

| # | Finding | Fix |
|---|---|---|
| 1 | **Wrong positions under automatic sizing.** `ResponsiveSizingLayout` (canonical page pass) treated a component copy's stored children like a container's: when any slot item had hug/fill sizing, it laid them out as a stack at page positions, and when an auto-layout parent moved the copy it shifted them too. Slot contents are stored slot-local and are laid out after projection (the canvas and export lay out the resolved page), so projection then added the slot origin a second time. | `ResponsiveSizingLayout.scope` ignores slot contents and does not descend into copies; `children(_:)` returns nothing for a copy. `CanonicalSizingConstraints.isLayoutResolved` stops at a copy, so slot items inside a copy placed by an auto-layout Stack stay movable. |

Checked and unchanged: batch 04 and batch 05 M1–M2 code. No other compile or
expectation problems found by these checks; they do not replace a build.

| File | Change |
|---|---|
| `SiteForge/InsertionModel.swift` | `ResponsiveSizingLayout.scope` / `resolve` (finding 1). |
| `SiteForge/DocumentModel.swift` | `isLayoutResolved` stops at a copy (finding 1). |
| `Tests/SiteForgeTests/CanvasRendererTests.swift` | New regression test `testSlotContentsKeepSlotLocalPositionsWhenThePageUsesAutomaticSizing` (fails without the fix: hug item and Stack-placed copy). |

New selector (1): `CanvasRendererTests/testSlotContentsKeepSlotLocalPositionsWhenThePageUsesAutomaticSizing`.

## Review of batches 05 (milestones 3–4) and 06 — November 25, 2026 (unverified)

**Owner instruction:** 6:28 PM EST, review and fix batch 05 milestones 3–4 and
all of batch 06 before Codex builds; batch 07 (OD-033 variants) stays on hold.
Method: re-read every changed hunk against the model and kernel code, checked
enum-switch exhaustiveness, call sites and on-screen identifiers used by the UI
journeys, and recomputed the coordinates the tests expect.

Findings and fixes:

| # | Finding | Fix |
|---|---|---|
| 1 | **Test fixture bug.** `CanvasRendererTests.suppliedCardFixture` reused one `NodeProperty` (slot membership) on several nodes; property IDs must be unique across a document, so `validate()` throws `duplicatePropertyID` and all three batch 06 renderer tests would fail. | `membership()` is now a function returning a fresh property. |
| 2 | **Compile error.** `CanonicalSlotRules.none` is read as `Optional.none` where the value is optional (`property(on:)?.rules ?? .none` in `ComponentSlotRulesFields`), making `rules` optional. | Renamed to `CanonicalSlotRules.unrestricted` (model default, view, test). |
| 3 | **Wrong positions on paste.** Paste into Slot converted only the pasted top-level objects to slot-local storage, so their contents were drawn offset by the slot origin; pasting into a copy's slot contents converted everything, including a pasted copy's own slot contents (already slot-local). | `ClipboardTransferRegistry.worldPositionedNodeIDs` (roots and descendants, stopping at pasted copies) decides what converts in both paths. |
| 4 | **Lost mobile/tablet positions.** Customize dropped the per-breakpoint geometry of an inner copy's own slot contents when copying defaults that contain such a copy. | Their responsive geometry is rebuilt like the rest (they are already slot-local, so nothing is subtracted). |
| 5 | Customize checked the object limit against the page, not the project. | Uses the project-wide count, like Insert and Add to Slot. |
| 6 | **Performance.** Each slot button ran the full command preparation, including whole-project validation, on every Inspector redraw (5 buttons per slot). | `slotEditAvailability` caches results per document, revision, page, scene generation, selection and lifecycle state; same registry result as before. |
| 7 | **Performance.** Every move/resize preview frame computed slot offsets when any copy on the page owned contents. | Computed only when the selection is inside a copy's slot contents. |

Checked and unchanged: switch exhaustiveness for `ComponentEdit`,
`ComponentOverrideValue`, `ModelValidationError`, `ClipboardTransferError`,
`DragDropError`; command-kernel batch validation (intermediate states inside a
batch are not validated, so marker-before-insert order is fine); every
identifier used by `testComponentSlotCustomizeAddReorderEmptyAndDefaultJourney`,
`testNestedComponentInsertInsideDefinitionRefusesSelfAndShowsUsageJourney` and
`testComponentSlotFallbackNativeAuthoringCancelHistoryAndReopenJourney` exists
in the views; expected coordinates in the batch 06 tests.

Known limitation (not changed): `CanonicalSlotGeometry` places a slot at the
position the definition's own layout gives it at the definition's size. If a
copy is resized and the definition root is a Stack or Grid that repositions
the slot container, the drawn slot and the stored slot-local origin can differ.

| File | Change |
|---|---|
| `SiteForge/ClipboardTransfer.swift` | `worldPositionedNodeIDs(_:roots:)`; both slot paste conversions use it (finding 3). |
| `SiteForge/TransformModel.swift` | `customizedSlotContents` rebuilds responsive geometry for inner copies' contents (4); project-wide object limit (5); transform preview computes slot offsets only for slot content (7). |
| `SiteForge/DocumentModel.swift` | `CanonicalSlotRules.unrestricted` replaces `.none` (2). |
| `SiteForge/WorkspaceShellView.swift` | `?? .unrestricted` (2). |
| `SiteForge/WorkspaceShellModel.swift` | `slotEditAvailability` cache (`SlotAvailabilityKey`) (6). |
| `Tests/SiteForgeTests/CanvasRendererTests.swift` | Fixture fix (1). |
| `Tests/SiteForgeTests/CommandKernelTests.swift` | `.unrestricted` (2); new regression test `testCustomizeKeepsAnInnerCopysOwnSlotContentsAtEveryBreakpoint` (4). |
| `Tests/SiteForgeTests/ClipboardTransferTests.swift` | New regression test `testPasteIntoASlotConvertsNestedObjectsButKeepsAPastedCopysOwnContents` (3). |

New selectors (2): `CommandKernelTests/testCustomizeKeepsAnInnerCopysOwnSlotContentsAtEveryBreakpoint`,
`ClipboardTransferTests/testPasteIntoASlotConvertsNestedObjectsButKeepsAPastedCopysOwnContents`.
Both fail without their fix. No new UI tests or timing rows.

## Batch 06 — November 25, 2026 (instance-owned slot content and slot rules, OD-018, unverified, complete)

**Owner instruction:** plan approved 5:18 PM EST. OD-018: a component copy can
own its slot contents (or an authored empty state) instead of the default
contents; the definition never owns copy content; a removed slot keeps copy
content as a recoverable conflict. Owner choices: Customize starts from a copy
of the default contents; basic slot rules (allowed top-level types, maximum
number of items) are included in this batch. Five milestones; this entry grows
per milestone. Out of scope: filling slots of nested instances from the page,
variants (OD-033).

**Starting point:** restore point `RP-2026-11-25-06` (end of batch 05;
`.git/index` locked and skipped; no project source skipped).

### Milestone 1 — model, rules, validation, document schema 25, conflicts

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | `ExposedComponentSlotProperty.rules` (defaulted). New `CanonicalSlotRules` (`allowedKinds: Set<NodeKind>?`, `maximumRoots: Int?`, `.none` (renamed `.unrestricted` in the review above), `encodedKinds` in `allowedRootKinds` order, `isValid`, strict `decode` — one canonical spelling, whole number 1…256 — and `violation(for:)`), `CanonicalSlotRuleViolation` (`kind` / `count`, `summary` text without content values), `CanonicalSlotState` (`inherited` / `empty` / `supplied([NodeID])`). `CanonicalComponentSlot`: `overrideNamespace` (the formerly reserved `component.instance.v1.slot.`; `unsupportedOverrideNamespace` kept as an alias for existing tests), `supplyKey` = `component.supplied.v1.slotID`, rule keys `component.exposedSlot.v1.allowedKinds` / `.maximumRoots`, `contentSchema = 25`, `maximumRoots = 256`, `allowedRootKinds`, `markers(on:)`, `suppliedSlotID`, `suppliedRoots(of:nodesByID:)`, `state(of:on:nodesByID:)`, `suppliedNodeIDs(in:)`, `validateContent(in:)` (membership only on an instance's direct children; marker "supplied" ⇔ ≥1 root, "empty" ⇔ none; ≤256 roots; ≤64 markers; nested-instance supplied content in a definition carries no exposed bindings; default and supplied contents of existing slots obey the rules → `componentSlotRuleBroken`), `ruleConflicts(_:slot:definitionID:in:)`; slot metadata validation accepts the optional rule keys; `validateTransition` refuses retargeting an instance that keeps slot state (`componentSlotContentWouldBeLost`). `ComponentOverrideValue` gains `.slotEmpty`, `.slotSupplied`; `CanonicalComponentOverrides.resolve` reports slot state as authored, and as a `missingProperty` / `missingDefinition` conflict when the slot or definition is gone; slot markers count toward `maximumOverridesPerInstance`. `CanonicalComponentReference.validate` allows slot markers and `supplyKey` (a supplied root may be an instance) and no longer requires instances to be childless; page validation lets `.component` own children; `CanonicalDocument.validate` calls `validateContent`. `ModelValidationError` gains `componentSlotRuleBroken`, `componentSlotContentWouldBeLost`. Serializer: current schema = 25, 24 added to the current decode list, files < 25 with instance children, markers, membership or rule keys refused. |
| `SiteForge/TransformModel.swift` | `ComponentEdit.setSlotRules(nodeID:rules:)` (definition pages only; refuses invalid rules and rules the default contents or any copy's contents break, naming the rule and the number of copies). `removeSlotProperty` also removes rule keys. `resetOverrideConflicts` on a slot conflict also removes that slot's supplied subtree from the instance (graph replacement, one transaction). Interim: `detach` and delete-with-detach refuse copies with slot state (`ComponentCommandRegistry.slotDetachUnavailable`). |
| `SiteForge/InsertionModel.swift` | Interim until milestone 2: `resolvedPage` omits nodes inside supplied content; `expand` omits an inner instance's supplied content and gives inner instance nodes no children. |
| `SiteForge/ClipboardTransfer.swift` | Envelope still refuses supplied content, markers, membership and (new) slot rule keys with `unsupportedSlotContent` until milestone 4. |
| `SiteForge/WorkspaceShellView.swift` | Retained-value text for `.slotEmpty` / `.slotSupplied` in both exhaustive switches. |
| `Tests/SiteForgeTests/CommandKernelTests.swift` | New: `testSuppliedSlotContentAndEmptyStateValidateResolveAndRequireSchemaTwentyFive`, `testSlotRulesConstrainDefaultAndSuppliedContentAndRefuseWithTheReason`, `testRemovedSlotKeepsSuppliedContentAsAConflictAndResetRemovesItInOneUndoableStep`; helpers `suppliedSlotFixture()`, `supply(_:slot:to:in:validate:)`, `markEmpty(_:on:in:)`. Batch 05's `testNestedInstancesKeepOwnValuesAndRequireSchemaTwentyFour`: current-version assertions relaxed to `>= 24` / `== currentSchemaVersion` (its schema-24 gate assertions unchanged). |

Interim state after milestone 1 (by plan): no editing path creates supplied
content yet (milestone 3); a schema-25 file with it validates and saves, but
canvas/Preview/export leave the supplied content out until milestone 2
projects it. Existing test `testComponentSlotFallbackBindingOrderingHistoryAndSchemaRoundTrip`
still asserts that a fallback-only instance is childless — still true. Existing
tests that write `unsupportedOverrideNamespace` keys use invalid marker values
("unsupported …") and are still refused. Slot-rule editing has no UI yet
(milestone 5). Checks: traceability, secret scan, runway and the evidence
checks that run here; nothing compiled or run.

### Milestone 5 — Inspector, slot rules UI, Layers, UI journey, handoff

Owner instruction 6:03 PM: continue through the remaining milestones without
check-ins.

| File | Change |
|---|---|
| `SiteForge/WorkspaceShellView.swift` | `ComponentSlotFallbackFields` (per slot on a selected copy): provenance (`component.slot.provenance.<slot>` value "Contents from original; …" / "Empty on this copy; …" / "Custom contents on this copy; N top-level item(s)"), rules caption (`component.slot.rules.<slot>`), item list (select), Customize / Make Empty / Use Default (confirmation when it removes contents, `component.slot.useDefault.confirm`), Add Frame / Add Text / Paste into Slot; every button disabled with the command's own reason (`slotEditAvailability`). New `ComponentSlotRulesFields` in the definition slot fields (Any type, per-kind checkboxes, item limit stepper, Apply Rules → `setSlotRules`; Escape resets the draft). New `ComponentSlotRulesSummary`. New `SlotContentItemView` above the Inspector details for objects in a copy's own contents (context, "measured from the slot's top-left corner", item N of M, Move Up/Down, Select owner). Layers rows: caption and accessibility value "Custom contents: <slot> of <copy>". The two "custom contents are unavailable" texts replaced (`component.slot.explanation`, `component.slot.instance.explanation`). Reset All no longer counts slot markers (it never removed them). |
| `SiteForge/WorkspaceShellModel.swift` | `selectionIsSlotContent`, `SelectedSlotItem` + `selectedSlotItem`, `slotContentLabel(_:)` (cached per document revision and page), `selectSlotItemOwner(_:)`; Move announcements say up/down. |
| `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift` | New `testComponentSlotCustomizeAddReorderEmptyAndDefaultJourney`. Existing `testComponentSlotFallbackNativeAuthoringCancelHistoryAndReopenJourney`: its assertions that custom contents are unavailable (`component.slot.supply.unavailable`, no supply button) are replaced, because OD-018 makes that the old behavior; it now asserts the explanation and that Customize exists, and still asserts inheritance. |
| `scripts/ci-ui-timings.txt` | Row `testComponentSlotCustomizeAddReorderEmptyAndDefaultJourney 160` (**estimate**; 8-shard spread 3 s). |
| `docs/architecture-decisions/ADR-0018-local-component-definition-graphs.md` | Amendment for OD-018 (Proposed). |
| `docs/OPEN_DECISIONS.md` | OD-018 implementation status. |

#### Batch 06 handoff (everything for Codex)

New selectors (17, plus 2 from the review above): `CommandKernelTests` —
`testSuppliedSlotContentAndEmptyStateValidateResolveAndRequireSchemaTwentyFive`,
`testSlotRulesConstrainDefaultAndSuppliedContentAndRefuseWithTheReason`,
`testRemovedSlotKeepsSuppliedContentAsAConflictAndResetRemovesItInOneUndoableStep`,
`testCustomizeMakeEmptyAndUseDefaultReplaceOneSlotStateInOneUndoableStepEach`,
`testAddToSlotFollowsTheRulesAndMoveSlotItemReordersWithinTheSlot`,
`testDetachKeepsTheCopysOwnSlotContentsAndDetachUsesAndDeleteIncludesThem`,
`testCanvasPathsConvertBetweenWorldAndSlotLocalGeometryAtTheBoundary`,
`testCreateComponentFromSelectionKeepsAnInnerCopysOwnSlotContents`,
`testPageDuplicateCopiesEachCopysOwnSlotContentsAndEmptyState`;
`CanvasRendererTests` —
`testSuppliedSlotContentDrawsInItsSlotWithCanonicalIdentityOnCanvasExportAndPreview`,
`testSuppliedContentInsideDefinitionsAndSuppliedInstancesProjectAtEveryLevel`,
`testSuppliedSlotProjectionStaysWithinBoundsOnStandardLargeAndStressFixtures`;
`ClipboardTransferTests` —
`testCopyOwningSlotContentsPastesWithItsOwnObjectsAndRequiresVersionSix`,
`testCrossProjectPasteMapsSlotStateAndMembershipToTheImportedSlot`,
`testPasteIntoASlotAddsTopLevelItemsWithinTheRulesAtTheirCopiedPosition`;
`InsertionModelTests` — `testPageChromeReuseCopiesAComponentCopysOwnSlotContents`;
`SiteForgeUITests` — `testComponentSlotCustomizeAddReorderEmptyAndDefaultJourney`.
Changed existing tests: batch 05 `testNestedInstancesKeepOwnValuesAndRequireSchemaTwentyFour`
(current-version assertions relaxed), batch 04 `testLinkedBoxStylesTravelThroughClipboardAsVersionFive`
and batch 05 `testNestedComponentCopyImportsInnerDefinitionsFirstAndReusesThemOnRepeatPaste`
(clipboard current version is now 6; they assert 5 = `versionWithLinkedBoxStyles`),
`testComponentSlotFallbackNativeAuthoringCancelHistoryAndReopenJourney` (see above).

Suggested first checks when building:
1. `ComponentEdit` switch exhaustiveness in `ComponentCommandRegistry.prepare`
   (five new slot cases plus `setSlotRules`) and the shared
   `case .customizeSlot(let id, let slotID), .makeSlotEmpty(...), .useSlotDefault(...)`
   binding pattern.
2. `ClipboardTransferError.componentNesting` / `.unsupportedSlotContent`
   Equatable; `ClipboardValidationContext.slotID` (`var` with default) keeps the
   memberwise initializer used by tests.
3. `ComponentDefinitionGraphCopy.remap(…slotMap: inout…)` call sites (2).
4. Expected coordinates in `testCanvasPathsConvertBetweenWorldAndSlotLocalGeometryAtTheBoundary`
   and `testPasteIntoASlotAddsTopLevelItemsWithinTheRulesAtTheirCopiedPosition`
   (derived from the fixtures: slot origins (104, 104) and (52, 72)).
5. SwiftUI type-checking of `ComponentSlotFallbackFields` (switch/if inside
   `HStack`) and `ComponentSlotRulesFields` (`LazyVGrid` of checkboxes).

Not updated by the owner's standing instruction: `IMPLEMENTATION_STATUS.md`,
`CHANGELOG.md`, `REQUIREMENT_EVIDENCE.json`, `CODEX_HANDOFF.md`, `CODEX_QUEUE.md`.
Restore point: `RP-2026-11-25-06`.

### Milestone 4 — transfer: clipboard v6, cross-project slot mapping, paste into a slot, page duplicate, header/footer copy

| File | Change |
|---|---|
| `SiteForge/ClipboardTransfer.swift` | Envelope: `versionWithLinkedBoxStyles = 5`, `versionWithSlotContent = 6`, `currentVersion = 6`; `carriesSlotContent(_:)`; each envelope picks the oldest version that keeps its content (box styles / nested → 5, slot contents → 6); the two existing `< currentVersion` checks now compare with 5. Slot contents are validated with `CanonicalComponentSlot.validateNodes` (page nodes and each carried definition; rules from carried definitions); failures are `unsupportedSlotContent` (message updated: no longer "cannot be transferred in this version"). Copy: nodes inside slot contents whose owning copy is also copied keep slot storage; others are converted to world without membership (M3 rule, now scoped). `ClipboardComponentImportPlan.slotPropertyMap` (defaulted): identity for same-project, imported/reused mapping cross-project (`mapEquivalentSlots`, `remap(…slotMap:…)`); pasted slot markers and membership values follow it; `definitionFingerprint(…slotMap:)` compares membership values (and marker keys via `overrideKeyMap`) in destination terms. `ClipboardValidationContext.slotID` (defaulted): paste as top-level items of that slot of the copy `activeContainerID` — refused while inheriting ("Choose Customize or Make Empty first"), after the slot's last item, slot-local via `CanonicalSlotGeometry.slotOffset`, within the rules (`unavailable("This slot does not accept that: … Nothing was pasted.")`), marker set to supplied in the same batch. |
| `SiteForge/TransformModel.swift` | `ComponentDefinitionGraphCopy.remap` gains `slotMap: inout` (own slots get new IDs; inner instances' slot markers and membership map through it; missing → `missingDependency`); `duplicate` pre-fills identity entries for inner definitions' slots. |
| `SiteForge/DocumentModel.swift` | `CanonicalComponentSlot.validateContent` split into `slotsByDefinition(_:)` + `validateNodes(_:inDefinition:slotsByDefinition:)` (same rules). |
| `SiteForge/InsertionModel.swift` | `CanonicalSlotGeometry.slotOffset(instance:slot:page:document:breakpoint:)`. |
| `SiteForge/WorkspaceShellModel.swift` | `pasteSiteForgeObjects(…intoSlot:)` (defaulted) builds the slot context for the selected copy. |
| `Tests/SiteForgeTests/ClipboardTransferTests.swift` | New: `testCopyOwningSlotContentsPastesWithItsOwnObjectsAndRequiresVersionSix`, `testCrossProjectPasteMapsSlotStateAndMembershipToTheImportedSlot`, `testPasteIntoASlotAddsTopLevelItemsWithinTheRulesAtTheirCopiedPosition`; helper `supplySlot(_:on:in:items:)`. Batch 04's `testLinkedBoxStylesTravelThroughClipboardAsVersionFive` and batch 05's `testNestedComponentCopyImportsInnerDefinitionsFirstAndReusesThemOnRepeatPaste`: assertions that version 5 is current changed to `versionWithLinkedBoxStyles` (5) / `currentVersion >= 5` (their content still writes 5). |
| `Tests/SiteForgeTests/CommandKernelTests.swift` | New: `testPageDuplicateCopiesEachCopysOwnSlotContentsAndEmptyState`. |
| `Tests/SiteForgeTests/InsertionModelTests.swift` | New: `testPageChromeReuseCopiesAComponentCopysOwnSlotContents`. |

Page duplicate and header/footer copy needed no source change: both use
`CanonicalPageGraphClone.prepare`, which already maps every node and child
identity and copies properties as stored (slot IDs and slot-local geometry
stay valid because the owning copy travels too). Batches are validated only
at the end, so inserting a copy before its contents is valid. Conflict repair
reuses the existing recovery flow (M1 makes it remove kept contents).
Checks: traceability, secret scan, runway, evidence checks; nothing compiled
or run.

### Milestone 3 — editing: Customize / Empty / Default, Add, reorder, every canvas path

| File | Change |
|---|---|
| `SiteForge/TransformModel.swift` | New `SlotItemKind` (`frame`, `text`; `node(parentID:slotID:y:)` with the same canonical defaults as Insert Frame/Text). `ComponentEdit` gains `customizeSlot`, `makeSlotEmpty`, `useSlotDefault`, `addToSlot(instanceID:slotID:kind:)`, `moveSlotItem(nodeID:offset:)` (allowed on pages and in definitions). Customize copies the slot's defaults as this copy shows them (`customizedSlotContents`: `expand` at every breakpoint, new node/property IDs, slot-local frames per breakpoint written as base + responsive overrides only where they differ, internal links remapped, contents of inner instances copied as is); defaults that are empty give the empty state. Empty/Default remove that slot's supplied subtree in the same graph transaction. Add refuses while inheriting and applies the slot rules with the reason; items of one slot stay contiguous in `childIDs`. Move swaps within the slot only. Helpers `replacingInstance`, `suppliedSubtree`, `exposedSlot`. Detach (and delete with detach uses) now keep the copy's own contents via `replacingInstance`; the M1 interim refusal and `slotDetachUnavailable` are removed. `.insert` converts placement into slot-local storage. `TransformCommandRegistry.prepare` reports world frames (outline, snapping) for supplied nodes while mutating stored values by the delta. |
| `SiteForge/InsertionModel.swift` | New `CanonicalSlotGeometry` (`offsets(in:document:breakpoint:)`, `offsetsByBreakpoint`, `shifted(_:sign:by:)`, `shiftCommands(subtreeOf:in:delta:)`). Insertion into supplied contents stores slot-local. `detachedNodes` projects the copy's own contents at every breakpoint (`projected`) and refuses while a slot state's slot is missing; new `detachedSuppliedNodeIDs`. |
| `SiteForge/DragDropModel.swift` | `DragDropError.slotItem` (+ message, category `slot-item`): top-level slot items are reordered with Move Up/Down. Moves between domains append shift commands so the canvas position is kept. |
| `SiteForge/ClipboardTransfer.swift` | Copy from slot contents carries world geometry and no membership; paste into slot contents stores slot-local; cut of a slot's last top-level items sets that slot to "empty". |
| `SiteForge/WorkspaceShellModel.swift` | `insertComponent` places against the world parent frame. New `selectedComponentSlotState(_:)`, `performSlotEdit(_:)` (announces the result), `slotEditAvailability(_:)`. |
| `Tests/SiteForgeTests/CommandKernelTests.swift` | New: `testCustomizeMakeEmptyAndUseDefaultReplaceOneSlotStateInOneUndoableStepEach`, `testAddToSlotFollowsTheRulesAndMoveSlotItemReordersWithinTheSlot`, `testDetachKeepsTheCopysOwnSlotContentsAndDetachUsesAndDeleteIncludesThem`, `testCanvasPathsConvertBetweenWorldAndSlotLocalGeometryAtTheBoundary`, `testCreateComponentFromSelectionKeepsAnInnerCopysOwnSlotContents`. M1 test `testRemovedSlotKeepsSuppliedContentAsAConflictAndResetRemovesItInOneUndoableStep`: the "detach refused" assertion now applies only while the slot is missing. |

Not in this milestone (by plan): Inspector controls for these actions and
slot rules (milestone 5); copying/cutting a copy that owns slot contents, and
pasting at the top level of a slot (clipboard still refuses instance children
— milestone 4). Geometry Inspector X/Y for a supplied object show and edit the
stored slot-local value (caption in milestone 5). `performSlotEdit` posts the
generic component announcement and then the specific one. Checks:
traceability, secret scan, runway, evidence checks; nothing compiled or run.

### Milestone 2 — projection on canvas, Preview, Browser Preview and export

| File | Change |
|---|---|
| `SiteForge/InsertionModel.swift` | `resolvedPage`: supplied nodes are left out of the page loop and prepared once with `slotLocalSource(_:frames:)` (page-resolved, slot-local frames written to `layout.*`, responsive geometry removed); `occupied` excludes them (each appears once, under its canonical ID); an unresolved instance placeholder has no children. `expandNested` gains `source:` (defaulted): contents supplied to instances inside the definition are taken out of the level into the recursion's source; `projectSlots(_:instance:definition:source:)` runs on every level; a supplied instance starts its own nesting depth (`nextDepth = 1`); unresolved inner placeholders and depth-capped instances have no children. New `derivedID(_:in:)` (same formula as `expand`), `slotLocalSource`, `projectSlots` (per marked slot: removes the derived default subtree; for "supplied", inserts the instance's top-level items in order after the slot container, parent = derived slot container, `layout.x/y` = slot origin + slot-local; a supplied instance's own children are not walked — they are its slot contents; `supplyKey` removed from output; a slot the definition no longer exposes is not drawn). `expand` keeps contents supplied to inner instances with slot-local frames (no definition offset) and maps every node's children (M1 interim reverted). |
| `Tests/SiteForgeTests/CanvasRendererTests.swift` | New: `testSuppliedSlotContentDrawsInItsSlotWithCanonicalIdentityOnCanvasExportAndPreview` (async), `testSuppliedContentInsideDefinitionsAndSuppliedInstancesProjectAtEveryLevel`, `testSuppliedSlotProjectionStaysWithinBoundsOnStandardLargeAndStressFixtures`; private `SuppliedCardFixture` + `suppliedCardFixture(customInstances:)`. |

Canvas, in-app Preview, Browser Preview and export share `resolvedPage`.
Supplied objects on a page keep canonical identities, so they appear as
canvas objects and selection targets. Budget: the existing pre-count already
counts every page node (supplied objects included) plus each instance's full
definition size, so it stays an upper bound (default contents replaced by
supplied ones are still counted). Fixture sizes: 101 / 10,001 / 16,606 objects
drawn (19,927 counted; 3,333 Cards = 20,005 is refused). Interim until
milestone 3: canvas move/resize of a supplied object would write world
coordinates into slot-local storage; no editing path creates supplied content
yet, so this cannot happen through the UI. Checks: traceability, secret scan,
runway, evidence checks; model files import only Foundation/CryptoKit; nothing
compiled or run.

## Batch 05 — November 25, 2026 (nested component instances, OD-034, unverified, complete)

**Owner instruction:** plan for OD-034 approved 4:15 PM EST, with values on
inner instances allowed. Component instances may sit inside definitions with
a cycle check on every route an instance can enter a definition, a bounded
nesting depth and the shared 20,000-object budget. Values on an inner
instance are authored inside the outer definition (one level deep); values
on an inner instance from the page are out of scope, as are slot content
(OD-018), variants (OD-033) and instance swap. Four milestones; this entry
grows per milestone.

**Starting point:** restore point `RP-2026-11-25-05` (end of batch 04;
`.git/index` locked and skipped; no project source skipped).

### Milestone 1 — dependency graph, validation, document schema 24

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | New `CanonicalComponentGraph` (`documentSchema = 24`, `maximumNestingDepth = 8`): `order`, `dependencies` (direct, unique, first-appearance order, existing definitions only), `names`, `cycle` (first cycle in document order, first definition repeated at the end), `nestingDepth(of:)`, `deepestChain(from:)`, `expandedObjectCount(of:)` (nested instances expanded; a missing link counts 1; saturates at `ResolvedGraphPolicy.maximumNodes + 1`), `dependents(of:)`, `wouldCreateCycle(placing:inside:)`, `violation` (cycle, then depth, then size, each in document order), `validate()`. Measurements are only computed when the graph is acyclic (iterative, no recursion). New `ComponentGraphViolation` (`kind` cycle / tooDeep / tooLarge with `category` `component-cycle` / `component-nesting-too-deep` / `component-expansion-too-large`, `path`, `names`, `objectCount`, user message naming the chain with " → ", `validationError`). `ModelValidationError` gains `componentDependencyCycle`, `componentNestingTooDeep`, `componentExpansionTooLarge`. `CanonicalDocument.validate` checks the graph after the reusable-style index. Definition page validation no longer rejects `.component` nodes (root still must accept children). The five instance-value validators (text, image fit, image, action, visibility) accept values on an instance inside a definition (`!inDefinition` removed from those guards only). The six `validateTransition` checks and `validateSerializableRetention` now include instances on definition pages. `DocumentSerializer.currentSchemaVersion` = `CanonicalComponentGraph.documentSchema` (24); 23 added to the current-envelope decode list; a file declaring schema < 24 with an instance inside a definition is refused (`malformedInput`). |
| `Tests/SiteForgeTests/CommandKernelTests.swift` | New: `testComponentGraphAllowsNestedInstancesWithDepthUsersAndExpandedSize`, `testComponentGraphRejectsCyclesWithTheirPathOnSaveAndOpen`, `testComponentGraphBoundsNestingDepthAndExpandedSizeWithSaturation`, `testNestedInstancesKeepOwnValuesAndRequireSchemaTwentyFour`; private fixture `nestedComponentDocument(_:links:extra:)`. |
| `Tests/SiteForgeTests/TransformModelTests.swift` | `testLinkedBoxStylesValidateInTheDocumentAndRequireSchemaTwentyThree`: current-version assertions relaxed to `>= 23` / `== currentSchemaVersion` (the schema-23 gate assertions are unchanged). |

Interim state after milestone 1 (by plan): a schema-24 project with an
instance inside a definition opens, saves and validates, but
`ComponentGraphResolver.expand` still returns `nil` for a definition that
contains an instance, so the outer instance draws as an unresolved placeholder
until milestone 2. No authoring path can create nesting yet (milestone 3).
Existing `testComponentSchemaRejectsHistoricalSmugglingCyclesAndPreservesMissingReferences`
still expects `incompatibleChildOwnership` for a definition whose root is an
instance; that rule is unchanged. Visibility bindings still cannot target an
instance (`CanonicalComponentVisibility.eligibleKinds` excludes `.component`).
Checks: traceability (441 records), secret scan, authoring runway pass;
brackets balance; nothing compiled or run.

### Milestone 4 — paste into open definitions, panel usage, navigation, journey, handoff

Owner chose "Milestone 4 + paste into components" (5:04 PM).

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | `CanonicalComponentGraph`: private `instanceCounts` (counted links per definition); `static violation(adding:into:definitions:)` (the probe, now shared); `insertionViolations(into:definitions:)` (one-pass decision per candidate, exact rebuild only for refused ones; falls back to rebuilding every candidate if the graph is already invalid). |
| `SiteForge/TransformModel.swift` | `ComponentCommandRegistry.nestingViolation` delegates to `CanonicalComponentGraph.violation(adding:into:definitions:)`. |
| `SiteForge/ClipboardTransfer.swift` | `ClipboardTransferError.componentNesting(ComponentGraphViolation)` (message = rule message + " Nothing was pasted."; `diagnosticCategory` = rule category). `preparePaste` into a definition checks every pasted instance (destination definitions + imported ones) before building commands. `prepareCopy` from a definition strips `definitionOwnedPrefixes` (exposed text/visibility/choice/media/action/slot, organization) and usage notes from the copied nodes. |
| `SiteForge/WorkspaceShellModel.swift` | `clipboardValidationContext` no longer refuses while a definition is open. New `componentInsertionIsAvailable` (lifecycle only); Quick Open insert uses it plus the graph reason. `componentInsertionUnavailableReason` reads `componentInsertionReasons()` (cache keyed by document ID, revision, open page). `editComponentDefinition` opens an inner definition in place when another definition is open (`adoptInnerComponentDefinition`, keeps the original return context). New `componentNestedUsageCount(_:)`, `componentDefinitionNames(_:)`. |
| `SiteForge/WorkspaceShellView.swift` | Component menu and Components panel Insert use `componentInsertionIsAvailable` (the M3 version still used `pageEditingIsAvailable`, which is false while a definition is open, so Insert stayed disabled there; fixed here). Quick Open "Insert Instance" disabled with the graph reason. Components panel rows: "Used inside: …" (`components.definition.usedInside.<id>`) and "Contains: …" (`components.definition.contains.<id>`), both with `accessibilityValue`. Details: "Used inside components" count. Delete confirmation says "Detach Uses and Delete" when uses exist only inside other definitions. |
| `Tests/SiteForgeTests/CommandKernelTests.swift` | New `testOnePassInsertionAnswersMatchTheFullRebuildForEveryPairOnRandomGraphs` (seeded; 40 valid graphs; the seed's refusals by cycle/depth/size and allowances were computed offline with an independent Python model of the same rules: 757 / 9 / 20 / 859; the one-pass rule also matched full rebuilds on 29 further seeds offline). |
| `Tests/SiteForgeTests/ClipboardTransferTests.swift` | New `testPasteIntoAnOpenDefinitionNestsCopiesAndRefusesTheDefinitionItself`. |
| `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift` | New `testNestedComponentInsertInsideDefinitionRefusesSelfAndShowsUsageJourney`. |
| `scripts/ci-ui-timings.txt` | Row `testNestedComponentInsertInsideDefinitionRefusesSelfAndShowsUsageJourney 60` (**estimate**; 8-shard spread 2 s after the row). |

#### Batch 05 handoff (everything for Codex)

New selectors (15): `CommandKernelTests` —
`testComponentGraphAllowsNestedInstancesWithDepthUsersAndExpandedSize`,
`testComponentGraphRejectsCyclesWithTheirPathOnSaveAndOpen`,
`testComponentGraphBoundsNestingDepthAndExpandedSizeWithSaturation`,
`testNestedInstancesKeepOwnValuesAndRequireSchemaTwentyFour`,
`testInsertComponentInsideADefinitionIsUndoableAndRefusesCyclesAndDepth`,
`testCreateComponentFromSelectionContainingAnInstanceKeepsItLinkedWithItsValue`,
`testInnerInstanceValuesDuplicateAndDetachInsideADefinitionAreOneLevelAndUndoable`,
`testRenameAndDetachUsesAndDeleteIncludeUsesInsideOtherDefinitions`,
`testOnePassInsertionAnswersMatchTheFullRebuildForEveryPairOnRandomGraphs`;
`CanvasRendererTests` —
`testNestedComponentDrawsExportsAndKeepsItsOwnValuesWithStableDerivedIdentity`,
`testNestedMissingDefinitionBlocksPreviewAndExportAndCyclesStillResolve`,
`testNestedComponentExpansionStaysWithinBoundsOnStandardLargeAndStressFixtures`;
`ClipboardTransferTests` —
`testNestedComponentCopyImportsInnerDefinitionsFirstAndReusesThemOnRepeatPaste`,
`testPasteIntoAnOpenDefinitionNestsCopiesAndRefusesTheDefinitionItself`;
`SiteForgeUITests` —
`testNestedComponentInsertInsideDefinitionRefusesSelfAndShowsUsageJourney`.
Changed existing tests: `SelectionModelTests/testComponentDependencySnapshotReportsNestedCyclesAndBoundedCapacity`
(the `.nestedComponent` expectation removed by OD-034; cycle checks kept, acyclic
case added) and `TransformModelTests/testLinkedBoxStylesValidateInTheDocumentAndRequireSchemaTwentyThree`
(current-version assertions relaxed to `>= 23`).

Suggested first checks when building:
1. `ComponentEdit` switch in `ComponentCommandRegistry.prepare`: the new grouped
   `case .insert, .detach, .set…Override, …:` list must be exhaustive and
   non-overlapping with the expose/remove case.
2. `ClipboardTransferError` gained an associated-value case; `Equatable` /
   `Sendable` synthesis relies on `ComponentGraphViolation` being both.
3. Tuple-typed iterative stacks (`[(PageID, Bool)]` with `while let (id, exiting)`)
   in `CanonicalComponentGraph`.
4. Same-project paste into a definition: link targets pointing at the source
   page are left as authored (same-project `pageReferenceMap` is empty).
5. The random-graph test's runtime (expected well under 10 s: ~2,000 objects
   per graph on average).

Docs: ADR-0018 amendment (Proposed), OD-034 status. Not updated by the owner's
standing instruction: `IMPLEMENTATION_STATUS.md`, `CHANGELOG.md`,
`REQUIREMENT_EVIDENCE.json`, `CODEX_HANDOFF.md`, `CODEX_QUEUE.md`.
Restore point: `RP-2026-11-25-05`.

### Milestone 3 — authoring and transfer paths

| File | Change |
|---|---|
| `SiteForge/TransformModel.swift` | `ComponentCommandRegistry.nestingViolation(inserting:into:document:)` (probe instance in the target definition, returns `ComponentGraphViolation?`; `nil` for non-definition pages) and `requireValidNesting(_:)`. `prepare`: `.insert`, `.detach` and every instance-value edit (set/reset text, visibility, choice, media, action; reset all; reset conflicts) are allowed on definition pages; other edits keep "Exit definition editing…". `.insert` refuses a violation with its message; `.create/.createNamed` re-checks the candidate graph. `creationSourceIDs` keeps instances inside the selection (new message only for a vanished node). `.rename` and `.delete` iterate every page except the definition itself, so uses inside definitions are renamed / detached. `ComponentDefinitionGraphCopy.duplicate` pre-fills identity property maps for the definitions its inner instances link to; `remap` gains `definitionMap:` (defaulted) for the instance reference and maps action value keys through `actionMap`. |
| `SiteForge/ClipboardTransfer.swift` | Envelope picks v5 when a carried definition contains an instance; a lower header with that content is `unsupportedVersion`. Envelope validation and copy gathering no longer refuse nested definitions (graph violation in the carried set is `componentCycle`). Cross-project import: refuses inner action values (`unsupportedComponentDependency`); processes definitions via `CanonicalComponentGraph.dependenciesFirst()`; `definitionFingerprint` gains `definitionMap:` and `overrideKeyMap:` so inner links/value keys compare in destination terms; `remap` receives `definitionMap`. |
| `SiteForge/DocumentModel.swift` | `CanonicalComponentGraph.dependenciesFirst()` (iterative post-order, document order otherwise, terminates on cycles). |
| `SiteForge/WorkspaceShellModel.swift` | `ComponentDependencySnapshot`: `.nestedComponent` issue removed; `canDetachUses` true for page uses or dependent definitions (no issues); `isTransferable` = no issues. Detach-unavailable announcement text updated. New `componentInsertionUnavailableReason(_:)` (uses `nestingViolation` on the active authoring page). |
| `SiteForge/WorkspaceShellView.swift` | Component menu "Insert Component" enabled while editing a definition; each item disabled with the graph reason. Components panel Insert button: disabled only for unavailable editing or a graph reason, with help/accessibility hint. |
| `Tests/SiteForgeTests/CommandKernelTests.swift` | New: `testInsertComponentInsideADefinitionIsUndoableAndRefusesCyclesAndDepth`, `testCreateComponentFromSelectionContainingAnInstanceKeepsItLinkedWithItsValue`, `testInnerInstanceValuesDuplicateAndDetachInsideADefinitionAreOneLevelAndUndoable`, `testRenameAndDetachUsesAndDeleteIncludeUsesInsideOtherDefinitions`. |
| `Tests/SiteForgeTests/ClipboardTransferTests.swift` | New: `testNestedComponentCopyImportsInnerDefinitionsFirstAndReusesThemOnRepeatPaste`. |
| `Tests/SiteForgeTests/SelectionModelTests.swift` | `testComponentDependencySnapshotReportsNestedCyclesAndBoundedCapacity`: the `.nestedComponent` assertion is removed (that rule is superseded by OD-034; the cycle, transferable and removal assertions stay, plus `canDetachUses` false for the cycle) and an acyclic Card → Button case is added. |

Not changed by design: paste while a definition is open stays unavailable
(existing `clipboardValidationContext` rule); Edit Original for an inner
instance while another definition is open stays unavailable (milestone 4
adds navigation); diagnostics keep the existing component record (failure
category `validation`; no names). The command kernel re-validates every
commit, so `componentDependencyCycle` / `componentNestingTooDeep` /
`componentExpansionTooLarge` also guard any path without its own message.
Known limit (existing class, wider with nesting): a definition edit can make
a page that uses it exceed the 20,000-object render budget; the canvas then
reports the existing object-limit error rather than refusing the edit.
The bracket check over `ClipboardTransferTests.swift` reports +5 parentheses;
that is the checker treating `//` inside `"https://example.com/inner"` as a
comment, not a real imbalance.
Checks: traceability, secret scan, runway and the evidence checks that run
here; nothing compiled or run.

### Audit — batch 04 milestone 5 and batch 05 milestones 1–2

Owner asked for a full audit of everything not yet audited against the
specification, development docs (`AGENTS.md`, `docs/TESTING.md`) and the
repository checks. Scope: batch 04 milestone 5 (UI journey, timing row,
handoff) and batch 05 milestones 1–2.

Checked: every identifier, caption, sample text, confirmation title and
enable rule used by `testReusableBoxStyleLinkOverrideAndUseLinkedBorderJourney`
against `WorkspaceShellView`/`WorkspaceShellModel` (all match); every M1–M2
test's arithmetic against the code paths; existing tests that touch
expansion, schema version, detachment and definition validation; package
manifest version handling (generic, no change needed); fixtures pinned to a
schema version (none); actor isolation of async test calls; headless import
boundaries; `check-repository.sh` steps.

| Finding | Fix |
|---|---|
| `testNestedMissingDefinitionBlocksPreviewAndExportAndCyclesStillResolve` expected `component-definition-unavailable` for an inner instance that carries an authored value; the compiler reports `component-override-conflict` for that case (the test would fail). | Fixture now has two inner Buttons: the one with "Buy" must report `component-override-conflict` (SF-0905-004), the other `component-definition-unavailable` (SF-0901-004); the outer instance has no finding; the redacted summary never contains "Buy". |
| The journey reads the per-style summary (`inspector.design.style.<id>.summary`) and box sample (`inspector.design.style.boxCapture`) with `waitForValue`, but those two Texts set no `accessibilityValue`, unlike every other Inspector status text the UI suite reads. | `WorkspaceShellView`: both Texts gain `.accessibilityValue` with their visible text (also gives VoiceOver the value). |
| `CanonicalComponentGraph` kept an unused stored property (`instanceTargets`) and an unused `validate()`. | Removed. |
| The two size-limit messages formatted 20,000 differently (locale-dependent `formatted()` vs plain `20000`). | Both use `ComponentGraphViolation.objectLimitText` ("20,000", fixed `en_US` grouping); test asserts the wording and category. |
| ADR-0018 still said nested instances are rejected; OD-034 said "not started"; ADR-0028 said every save writes schema 23. | ADR-0018 amendment section (Proposed, source only); OD-034 implementation status and temporary-assumption note; ADR-0028 consequence line. |
| Batch 04 heading said "in progress". | Heading now says complete. |

Repository checks run here: secret scan, traceability (441), authoring
runway, layout/canvas-renderer/selection evidence (pass). Not runnable here
(they launch other programs): `test-secret-scanner.py`,
`test-ci-test-accounting.py`, `ci-test-accounting.py`, the insertion,
transform, snapping, inline-text and drag-drop evidence checks (they only read
evidence JSON this work did not touch), `check-architecture-boundaries.py`
(its text rules were applied by hand: model files import only
Foundation/CryptoKit; no new `ProcessInfo.processInfo.arguments`,
`NSOpenPanel` or fixture-root code), `select-test-scope.py --self-test`,
`git diff --check` (trailing whitespace checked by hand: none), `plutil`.
No empty TODO/FIXME markers. Development-doc steps deliberately not done by
the owner's standing instruction: `IMPLEMENTATION_STATUS.md`, `CHANGELOG.md`,
queue entries, installed-app refresh.

Known interim states (by plan, milestone 3): `ComponentDependencySnapshot`
still flags `.nestedComponent` (a Card containing a Button shows as not
transferable); deleting a definition used only inside another definition is
not yet treated as "in use"; Insert Component stays disabled while editing a
definition; clipboard still refuses nested dependencies. None of these can
corrupt a document; they only refuse or under-report.

### Milestone 2 — nested expansion on canvas, Preview and export

| File | Change |
|---|---|
| `SiteForge/InsertionModel.swift` | `ComponentGraphResolver.expand` no longer returns `nil` for a definition that contains instances; it returns them as instance nodes (one level; detachment uses it, so inner instances stay linked). New `expandNested(_:definition:definitions:pageID:geometry:breakpoint:expandsNested:depth:checkpoint:)` (throws): expands one level, then each inner instance at the geometry its outer definition gives it, recursively, stopping at `CanonicalComponentGraph.maximumNestingDepth`; an inner instance with a missing definition or no geometry stays one placeholder node; checkpoint per node. Derived identities chain: an inner instance's objects derive from the inner instance's derived ID with the existing `component-child:` label. `resolvedPage` builds `CanonicalComponentGraph` once, pre-counts with `expandedObjectCount` (budget error unchanged: `objectLimitExceeded(maximumNodes + 1)`) and calls `expandNested`; a cyclic in-memory graph expands one level only. |
| `SiteForge/DocumentModel.swift` | `CanonicalComponentGraph.dependencyClosure(of:)` and `static outputInstances(in:)` (page instances, then instances inside every definition those pages use, directly or indirectly, definitions in document order). |
| `SiteForge/CanvasRendererCore.swift` | `StaticBuildCompiler` component findings loop uses `CanonicalComponentGraph.outputInstances(in:)` (codes and requirement IDs unchanged; `affectedNodeID` is the canonical inner instance ID). |
| `SiteForge/WorkspaceShellModel.swift` | `LocalPreviewRuntimeCompiler.compile` recovery gate and `componentOutputIsAvailable` use `outputInstances(in:)`. |
| `Tests/SiteForgeTests/CanvasRendererTests.swift` | New: `testNestedComponentDrawsExportsAndKeepsItsOwnValuesWithStableDerivedIdentity` (async), `testNestedMissingDefinitionBlocksPreviewAndExportAndCyclesStillResolve` (async), `testNestedComponentExpansionStaysWithinBoundsOnStandardLargeAndStressFixtures`; private `NestedButtonCardFixture` + `nestedButtonCardFixture(buttonsPerCard:buttonParts:cards:)`. |

Canvas, in-app Preview, Browser Preview and export all go through
`resolvedPage`, so they share one expansion. The definition editor
(Card open) also expands inner instances under their canonical IDs, which are
selectable there; objects inside them are not (same rule as page instances).
Fixture sizes: 106 / 9,997 / 19,993 objects (953 Cards = 20,014 exceeds the
budget). Bounds are safety limits only (1 s / 5 s / 10 s). Still pending by
plan: no authoring path creates nesting until milestone 3;
`ComponentDependencySnapshot` still reports `.nestedComponent`.
Checks: traceability (441), secret scan, authoring runway pass; model files
import only Foundation/CryptoKit; nothing compiled or run.

## Batch 04 — November 25, 2026 (linked border, corners and shadow in reusable styles, unverified, complete)

**Owner instruction:** roadmap batch 3 "Reuse depth". Owner approved this plan:
reusable styles (SF-0510) also carry border, corner radius and outer shadow,
linked to every object that uses the style, with per-object overrides.
Padding and clip-content are excluded (layout reads them directly). Variants,
nested components, supplied slot content (OD-018) and override migration
(OD-019) are out of scope. Five milestones; this entry grows per milestone.

**Starting point:** restore point `RP-2026-11-25-04` (`.git/index` was locked
by another process and skipped; no project source skipped).

### Milestone 1 — model, file version 23, resolver, clipboard

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | `CanonicalReusableStyleDefinition.box` (+ init with default, `hasAppearance`). New `CanonicalReusableBoxAppearance`: groups border (`borderWidth`, `borderColor`, `borderStyle`), `cornerRadius`, shadow (`shadowColor`, `shadowOffsetX/Y`, `shadowBlur`, `shadowSpread`) stored as `style.reusable.v1.definition.<id>.<field>`; all-or-nothing groups; colors canonical `#RRGGBBAA`; strict `decode`, `fieldValues`, `quantized`, `semanticFingerprint`, `ownsDefinitionProperty`. Index parses the box fields (repeat = invalid), `definitionFields` allow-list, a style must supply at least one value. `DocumentSerializer.currentSchemaVersion` 22 → 23 (22 accepted as historical); schema < 23 with box fields → `malformedInput`. |
| `SiteForge/TransformModel.swift` | `CanonicalBoxAppearanceSource` (`local` / `linked(id)` / `unset`), `CanonicalBoxStyleResolution`, `CanonicalLinkedBoxStyleResolver` (per group: local wins, then last applied style, then unset; shadow-enabled flag only for a local shadow; padding/clip local only). `LocalColorTokenResolver.resolvedBoxStyle(for:tokens:reusableStyles:)` overload. **Not yet used by canvas/Preview/export (milestone 3).** |
| `SiteForge/ClipboardTransfer.swift` | `ClipboardReusableStyleDependency.box` with explicit Codable (known keys only; `box` omitted when empty, empty object rejected); validity requires RGBA8 colors. Envelope `currentVersion` 4 → 5 (`versionWithDecorativeData` = 4 keeps decorative-only content at 4); box content requires v5. Copy, paste install, same-name equivalence and component fingerprints include the box. |
| `Tests/SiteForgeTests/TransformModelTests.swift` | 3 tests + helpers `linkedBoxStyleProperties`, `localBoxProperties`. |
| `Tests/SiteForgeTests/ClipboardTransferTests.swift` | 1 test. |
| `Tests/SiteForgeTests/CanvasSettingsTests.swift` | Batch 03 schema assertions now compare with `DocumentSerializer.currentSchemaVersion` instead of 22 (the record still requires schema ≥ 22). |

New selectors:

```
SiteForgeTests/TransformModelTests/testReusableStyleLinkedBoxAppearanceUsesOneStrictGroupedCodec
SiteForgeTests/TransformModelTests/testLinkedBoxStylesValidateInTheDocumentAndRequireSchemaTwentyThree
SiteForgeTests/TransformModelTests/testLinkedBoxResolutionIsLocalFirstThenLastLinkedStyleWithProvenance
SiteForgeTests/ClipboardTransferTests/testLinkedBoxStylesTravelThroughClipboardAsVersionFive
```

Interim state: styles can hold box values (by file or paste) but nothing
creates them in the UI yet and nothing draws them yet; milestones 2–4 add
those. Every save now writes document schema 23. Nothing compiled or run.

#### Milestone 1 review fix

Owner review. A style that supplies only border/corners/shadow could not be
renamed or updated: `AdvancedStyleCommandRegistry.definitionEdit` still
required fill or opacity (it rejected with `.invalidValue`, no data change).
`SiteForge/TransformModel.swift`: the update path now also accepts existing
linked box values (update keeps them; create unchanged). New selector:

```
SiteForgeTests/TransformModelTests/testUpdatingABoxOnlyReusableStyleKeepsItsLinkedBoxValues
```

#### Milestone 1 full review (owner asked to review and fix all items)

- Owner-facing correction: an earlier message said compile notes were in this
  log; they were not. They are below.
- Readability/compile-safety rewrites, same behavior: `CanonicalLinkedBoxStyleResolver`
  uses explicitly typed `if/else` instead of optional-tuple `??` chains;
  `CanonicalReusableBoxAppearance.semanticFingerprint` uses an explicit
  `entry -> String` closure instead of a `switch` expression as the closure
  body; `decode` evaluates `try present(...)` into locals instead of `if try`.
- **Compile notes for Codex** (constructs not used elsewhere in this tree or
  worth a first look if the build fails): custom `Codable` on
  `ClipboardReusableStyleDependency` (replaces the synthesized one; decodes
  `box` as `[String: PropertyValue]`); `CanonicalReusableStyleDefinition` now
  has an explicit memberwise-compatible `init` with a defaulted `box`;
  `let source: String = switch ...` in `ProjectSettingsStore` (batch 03).
- **Installed app:** every save now writes document schema 23 (22 after batch
  03). The SiteForge app currently installed on the owner's Mac cannot open
  projects saved by this tree until Codex rebuilds and installs it.
- Confirmed, no change needed: Update rewrites only name/fill/opacity and keeps
  box fields; component duplicate and fingerprint skip style definitions by
  prefix, which covers the new fields; clipboard dependency decoding now rejects
  unknown keys (older builds never write any); content without box values keeps
  clipboard versions 2–4.

### Milestone 2 — style editing (registry)

| File | Change |
|---|---|
| `SiteForge/TransformModel.swift` | `ReusableBoxProperty` (`border`, `cornerRadius`, `shadow`); `ReusableBoxSelectionCapture`; `AdvancedStyleEdit.setReusableStyleBox(id:box:)` and `.useLinkedBox(_)`; `AdvancedStyleCommandRegistry.captureBoxSelection(_:in:)`; private `definitionBoxEdit` (one batch: set/replace/remove box fields on the style's owner, RGBA8, no partial groups, keeps name/fill/opacity, refuses removing a style's last value); `.useLinkedBox` in `selectedNodeEdit` (removes only that local group: border its six fields, corners `radius.uniform`, shadow its eight fields plus `shadow.enabled`; whole selection refused if any object lacks a linked style supplying the group; refused while a color token is bound to that border/shadow, matching linked fills); diagnostics `reusable.box.set` and `reusable.inherit.<group>`. |
| `Tests/SiteForgeTests/TransformModelTests.swift` | 3 tests. |

New selectors:

```
SiteForgeTests/TransformModelTests/testSetReusableStyleBoxReplacesLinkedValuesInOneUndoableTransaction
SiteForgeTests/TransformModelTests/testUseLinkedBoxHandsEachGroupBackToLinkedStylesAtomically
SiteForgeTests/TransformModelTests/testCaptureBoxSelectionStoresWhatTheSelectionShows
```

Behavior notes: capture reads the effective value (own value first, then
linked); a disabled shadow is not captured; a group that differs across the
selection is reported in `mixed`, never averaged; token colors are captured as
plain values (snapshot, as for fills). Shell/Inspector wiring is milestone 4.

#### Milestone 2 review fix

Owner review. Creating a style could not include box values (a box-only style
needed a fill first, then a second transaction), and an Update from Selection
that also changes box values would have been two undo steps.
`SiteForge/TransformModel.swift`: `createReusableStyle` gains
`box: CanonicalReusableBoxAppearance = .init()` and `updateReusableStyle`
gains `box: CanonicalReusableBoxAppearance? = nil` (nil keeps the style's box;
a value replaces it). Both are written by `definitionEdit` in the same batch.
New shared `boxFieldCommands(prefix:box:owner:pageID:)` is used by
`definitionEdit` and `definitionBoxEdit`. Existing 4-argument call sites
(`WorkspaceShellView`, tests) compile unchanged via the defaults; the two
pattern matches in `prepare` now bind five values. **Compile note:** defaulted
enum associated values (Swift 5.1+); not used elsewhere in this tree.
The capture test now creates its box-only style in one step.

```
SiteForgeTests/TransformModelTests/testCreateAndUpdateReusableStyleCarryBoxValuesInOneTransaction
```

#### Final review pass (owner: "fix all issues")

- `ReusableBoxProperty.cornerRadius` raw value is now `corner-radius`, so its
  diagnostic is `reusable.inherit.corner-radius`, matching existing kebab-case
  names (`position.z-index`). `border`/`shadow` unchanged.
- `testUseLinkedBoxHandsEachGroupBackToLinkedStylesAtomically` no longer calls
  `validate()` on a document with a content-less Text node (no existing test
  does; it could fail for an unrelated reason). The skip assertion is unchanged.
- Re-checked with no change needed: no production code or test pins clipboard
  version 4 or document schema 22; every `AdvancedStyleEdit` case is handled by
  the diagnostics switch; the two `create`/`update` pattern matches bind all
  five values; no other `CanonicalReusableStyleDefinition` or
  `ClipboardReusableStyleDependency` constructors exist; clipboard encoding uses
  sorted keys, so the new `box` object is deterministic.

### Milestone 3 — canvas, Preview and export

| File | Change |
|---|---|
| `SiteForge/WorkspaceShellModel.swift` | `WorkspaceScenePreparationWorker.prepare`: the canvas box style now calls `resolvedBoxStyle(for:tokens:reusableStyles:)` with the `reusableStyleIndex` the function already builds. Editor Preview uses this canvas plan. |
| `SiteForge/CanvasRendererCore.swift` | `staticBoxStyle(for:colorTokens:reusableStyleIndex:)`; `InternalDocumentRenderTreeCompiler.compile` passes its existing optional `reusableStyleIndex`. Static build (light and dark trees) and Browser Preview already pass the index, so linked values export; `formCompatibilityReport` passes none (structure only). |
| `Tests/SiteForgeTests/CanvasRendererTests.swift` | 1 test. |

Deliberately unchanged (object-only by design): `DesignBoxStyleCommandRegistry.resolvedStyle` used by layout for padding/clip; color-token target availability (`WorkspaceShellModel` ~7978, a token binds only to an object's own border/shadow); token unbind literal write-back (`TransformModel` ~3394); `designInspectorBoxStyleValue` (Inspector, milestone 4). Canvas hit testing, selection and accessibility frames do not depend on border/radius/shadow.

```
SiteForgeTests/CanvasRendererTests/testLinkedBoxStylesDrawOnCanvasAndExportIdentically
```

Component instances whose definition root links a style: covered by
`testComponentInstanceDrawsAndExportsItsDefinitionsLinkedBoxStyle` (added in
the "fix everything" pass below; expanded nodes keep the definition's applied
style IDs and the index is document-wide).

#### Audit after milestone 3 (owner: "audit all current work and fix any production or dev doc gaps")

Production:
- `CanonicalReusableStyleIndex.init` rescanned an owner's properties for every
  style (fill, opacity and box lookups). It now groups definition properties
  by style-ID segment in one pass; lookup semantics are unchanged (first
  property with the exact key). Matters for SF-0510-007 with many styles.
- Confirmed covered, no change: component instances (expansion keeps each
  definition node's applied style IDs; the index is document-wide); in-app
  Preview (`LocalPreviewRuntimeCompiler` builds from the canvas scene worker);
  Browser Preview (uses `StaticBuildCompiler` → `MultiPageStaticBuildPlanner`,
  which passes the index for light and dark trees).
- Remaining interim gap, closed by milestone 4: the Design Inspector box value
  (`WorkspaceShellModel.designInspectorBoxStyleValue`) still reports only an
  object's own border/corners/shadow while the canvas draws linked values.

Dev docs:
- New `docs/architecture-decisions/ADR-0028-linked-box-appearance-in-reusable-styles.md`
  (no earlier ADR covered reusable styles).
- New `docs/OPEN_DECISIONS.md` OD-033 (component variants, SF-0904) and OD-034
  (nested component instances, SF-0901), promised in the batch plan.
- SF-0510-007 previously recorded "100/10000-object propagation performance
  evidence is not yet executed"; two source tests now cover standard, large and
  stress (still unexecuted):

```
SiteForgeTests/TransformModelTests/testLinkedBoxStylesStayResponsiveOnStandardLargeAndStressFixtures
SiteForgeTests/TransformModelTests/testReusableStyleIndexGroupsManyDefinitionsOnOneOwnerIdentically
```

- Not updated, per the owner's standing instruction: `IMPLEMENTATION_STATUS.md`,
  `CHANGELOG.md`, `REQUIREMENT_EVIDENCE.json`, `CODEX_HANDOFF.md`.

### Milestone 4 — Inspector

| File | Change |
|---|---|
| `SiteForge/WorkspaceShellModel.swift` | `designInspectorBoxStyleValue()` now resolves with the reusable-style index, so the Design Inspector shows what the canvas draws (editing a shown linked value writes an explicit own value, as before; commits still require a dirty draft). New: `reusableBoxSource(_:)` ("Base local border", "Base linked border: Card", "Default / omitted border", "Mixed border sources"), `selectionBoxGroupIsLinked(_:)`, `reusableBoxCapture`, `linkedBoxAvailability(_:)` (same registry validation as the commit), `nonisolated static boxPropertyTitle(_:)`. |
| `SiteForge/WorkspaceShellView.swift` | Design Inspector box controls: source captions `inspector.design.borderSource`, `.cornerRadiusSource`, `.shadowSource`; Remove border/corners/shadow disabled with help text when the value comes only from a linked style; "Shadow enabled" shown only for an own shadow. Reusable Styles panel: scope text mentions border/corners/shadow; **Create Box Style** (`inspector.design.style.createBox`) and box sample text (`.boxCapture`); **Use Linked Border… / Corners… / Shadow…** (`.inheritBorder`, `.inheritCorners`, `.inheritShadow`) with confirmations; per style **Update Box…** (`.<id>.updateBox`, confirmation lists usage counts) and a summary line (`.<id>.summary`). `PendingReusableStyleAction` gains `.updateBox` and `.inheritBox`. New `ReusableStyleSummary`. |
| `Tests/SiteForgeTests/TransformModelTests.swift` | 1 test. |

```
SiteForgeTests/TransformModelTests/testInspectorReportsLinkedBoxSourcesAndGuardsLinkedOnlyRemoval
```

**Overlap note for Codex:** the Design Inspector box controls edited here are the
same view as the in-progress fast-styling work (border/corner sliders). Edits
are limited to `.disabled`/`.help` on the three Remove buttons, three caption
lines, and one extra condition on "Shadow enabled". Existing identifiers and
the existing `inspector.design.style.*` controls are unchanged.

Behavior notes: `designInspectorBoxStyleValue` origin is still `.authored` only
when the object has its own box properties (linked-only shows `.defaulted`;
the origin is not displayed today). Existing UI journeys that assert
"Reusable styles share solid color and opacity" text: none found.

#### Milestone 4 review

- **Performance (SF-0510-007):** one Design Inspector refresh rebuilt the
  reusable-style index for every read (about 16 full-document scans: three
  `reusableBoxSource`, seven `selectionBoxGroupIsLinked`, several
  `designInspectorBoxStyleValue`), plus three availability checks and capture
  in the panel. `WorkspaceShellState.currentReusableStyleIndex()` now caches one
  index per document value (compared with `==`, which is O(1) for the unchanged
  value because arrays compare buffer identity first). The registry gains
  `prepare(_:in:context:styleIndex:)` and `captureBoxSelection(_:in:styleIndex:)`
  with `nil` defaults (existing callers unchanged; a given index must be built
  from the same document). The pre-batch helpers were moved to the cache in the
  next pass (below).
- **Hints:** the border/corners/shadow add/remove buttons had an empty `.help("")`
  outside the linked case; now "Add a border to this object." / "Remove this
  object's own border." / the linked explanation.
- **Disabled reasons:** Create Box Style and Update Box now show why they are
  disabled (nothing to capture, or values differ) in help and accessibility hint.
- **ADR-0028:** replaced the stale interim-Inspector sentence; added an Inspector
  decision bullet.
- Checked, no change: existing UI journeys use border/corner/shadow toggles on
  unlinked objects only, so the new disabling does not affect them.

```
SiteForgeTests/TransformModelTests/testPrebuiltStyleIndexGivesIdenticalRegistryAndCaptureResults
```

#### "Fix everything" pass (owner)

- Pre-batch Inspector helpers now use `currentReusableStyleIndex()` instead of
  building the index themselves: `designInspectorFillValue`,
  `designInspectorOpacityValue`, `reusableAppearanceSource`,
  `reusableStyleDefinitions`, `reusableStyleCapture` and
  `linkedAppearanceAvailability`. `WorkspaceShellModel` no longer builds the
  index from `documentSession.document` anywhere except the cache.
  `AdvancedStyleCommandRegistry.captureSelection(_:in:styleIndex:)` gains the
  same optional parameter (nil default; behavior unchanged). Commits
  (`commitAdvancedStyle`) still build their own index.
- New test for the milestone 3 gap (component instance with a linked style):

```
SiteForgeTests/CanvasRendererTests/testComponentInstanceDrawsAndExportsItsDefinitionsLinkedBoxStyle
```

Batch 04 milestone 5 (UI journey, CI timing row, handoff) was completed after
this section; see "Milestone 5" below.

#### Owner decisions recorded (3:57 PM)

The owner approved the recommended defaults of OD-018, OD-019, OD-032, OD-033
and OD-034. `docs/OPEN_DECISIONS.md` now marks each "Approved by the owner —
2026-11-25" with a Decision line and an implementation-status line. No code was
written for any of them. Follow-up implied by the approvals, each a separate
planned batch the owner reviews first: OD-018 supplied slot content (schema bump,
ADR-0018 amendment); OD-032 package v2 (incompatible format, migration, new
ADR); OD-033 property-only variants (schema bump, ADR); OD-034 nested instances
with cycle checks (ADR-0018 amendment). OD-019 needs no change. `CODEX_QUEUE.md`
was not edited (Codex's queue).

### Milestone 5 — UI journey, CI timing, batch handoff

| File | Change |
|---|---|
| `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift` | New `testReusableBoxStyleLinkOverrideAndUseLinkedBorderJourney` (native pointer/keyboard path; reuses existing helpers `action`, `confirm`, `replaceStructuralLayoutField`, `replaceComponentTextField`, `componentMenu`, `waitForValue`, `attachWindowScreenshot`). |
| `scripts/ci-ui-timings.txt` | Row `testReusableBoxStyleLinkOverrideAndUseLinkedBorderJourney 90` (**estimate**, between the 50 s Settings journey and the 232 s reusable-fill journey; 8-shard spread recomputed at 4 s, limit < 10 s; keeps alphabetical order). |

Journey steps: insert Frame → add own border (3 pt) and corners (14 pt) →
sources read "Base local …" → Create Box Style "Outlined" (sample text shows
the values) → link it → Use Linked Border cancelled (nothing changes) then
confirmed (source "Base linked border: Outlined", Remove disabled, value still
shown) → Use Linked Corners → Undo ×2 and Redo restore each step exactly.
Screenshots attached at four points. **UNRUN**; it relies on the Inspector
identifiers listed under milestone 4 and on the existing `.link`/`.usage`
style-row identifiers.

#### Batch 04 handoff (everything for Codex)

New selectors (16): `TransformModelTests` — `testReusableStyleLinkedBoxAppearanceUsesOneStrictGroupedCodec`,
`testLinkedBoxStylesValidateInTheDocumentAndRequireSchemaTwentyThree`,
`testLinkedBoxResolutionIsLocalFirstThenLastLinkedStyleWithProvenance`,
`testUpdatingABoxOnlyReusableStyleKeepsItsLinkedBoxValues`,
`testSetReusableStyleBoxReplacesLinkedValuesInOneUndoableTransaction`,
`testUseLinkedBoxHandsEachGroupBackToLinkedStylesAtomically`,
`testCaptureBoxSelectionStoresWhatTheSelectionShows`,
`testCreateAndUpdateReusableStyleCarryBoxValuesInOneTransaction`,
`testLinkedBoxStylesStayResponsiveOnStandardLargeAndStressFixtures`,
`testReusableStyleIndexGroupsManyDefinitionsOnOneOwnerIdentically`,
`testInspectorReportsLinkedBoxSourcesAndGuardsLinkedOnlyRemoval`,
`testPrebuiltStyleIndexGivesIdenticalRegistryAndCaptureResults`;
`ClipboardTransferTests` — `testLinkedBoxStylesTravelThroughClipboardAsVersionFive`;
`CanvasRendererTests` — `testLinkedBoxStylesDrawOnCanvasAndExportIdentically`,
`testComponentInstanceDrawsAndExportsItsDefinitionsLinkedBoxStyle`;
`SiteForgeUITests` — `testReusableBoxStyleLinkOverrideAndUseLinkedBorderJourney`.

Suggested first checks when building (most likely compile or behavior risks):
1. Defaulted associated values on `AdvancedStyleEdit.createReusableStyle` /
   `updateReusableStyle` and the five-value pattern matches in `prepare`.
2. Custom `Codable` on `ClipboardReusableStyleDependency`.
3. `WorkspaceShellState.currentReusableStyleIndex()` cache (`CanonicalDocument ==`
   per Inspector read; if profiling shows cost on very large documents, key the
   cache by `documentID + revision` instead).
4. Exact CSS strings in `testLinkedBoxStylesDrawOnCanvasAndExportIdentically`
   (alpha `0.251` comes from RGBA8 rounding of `#00000040`).
5. Document schema 23 and clipboard v5 assertions in existing fixtures.

Decisions: ADR-0028 (new, Proposed); OD-018/019/032/033/034 approved by the
owner, not implemented (see above). Docs deliberately not updated:
`IMPLEMENTATION_STATUS.md`, `CHANGELOG.md`, `REQUIREMENT_EVIDENCE.json`,
`CODEX_HANDOFF.md`, `CODEX_QUEUE.md`. Restore point: `RP-2026-11-25-04`.

## Batch 03 — November 25, 2026 (project-scoped preferences, unverified)

**Owner instruction:** start the native Settings milestone. Settings that belong
to a project (such as grid layout) live in the project; app settings (such as
appearance or text size) live with the app; all are available in the Settings
window. Follow the development specification (module 0206) closely. Codex was
paused while these edits were made.

**Starting point:** restore point `RP-2026-11-25-03` (taken before this batch).
**Edited tree:** this iCloud working copy only.

### Design

See [ADR-0027](../architecture-decisions/ADR-0027-project-scoped-preferences.md).
Document schema 21 → 22 (optional `projectPreferences`); persisted history schema
3 → 4 (`setProjectPreferences`). New Settings destination `project` after `canvas`.

### Files

Source (no new Swift files; no `project.pbxproj` change):

| File | Change |
|---|---|
| `SiteForge/DocumentModel.swift` | `ProjectPreferences`, `ProjectPreferenceSource`, `ProjectPreferenceResolution`, `ProjectPreferenceResolver`; `CanonicalDocument.projectPreferences` with schema-22 key gating and null rejection; validation; `ModelValidationError.invalidProjectPreferences`; `DocumentSerializer.currentSchemaVersion = 22`, schema 21 accepted as historical, post-decode gate. |
| `SiteForge/CommandKernel.swift` | `CommandName.setProjectPreferences`, `SetProjectPreferencesCommand`, `DocumentCommand.setProjectPreferences` (history schema 4, name, targets, descriptor "Edit Project Preferences", availability, mutation with inverse). |
| `SiteForge/PersistedHistory.swift` | `currentSchemaVersion = 4`; closed payload shape for `setProjectPreferences`; v3 migrates like v1/v2. |
| `SiteForge/TransformModel.swift` | `ProjectPreferencesEdit`, `ProjectPreferencesError`, `ProjectPreferencesCommandRegistry`. |
| `SiteForge/CanvasViewport.swift` | `CanvasWorldGridPolicy.defaultBaseInterval` and `base:` overloads; existing intervals unchanged. |
| `SiteForge/WorkspaceShellModel.swift` | `worldGridSpacing`; `synchronizeProjectPreferences` (called from the document sink and at init); `projectPreferencesAvailability`, `projectPreferencesTitle`, `commitProjectPreferences`. |
| `SiteForge/WorkspaceShellView.swift` | Canvas view `worldGridSpacing` (set in configure/update, used by `drawWorldGrid`); `ActiveWorkspaceResolver`. |
| `SiteForge/CanvasSettings.swift` | `import Combine`; `CanvasSettingsStore.committedGridRecord`; `ProjectSettingsStore`, `ProjectGridVisibilityChoice`, `ProjectGridSpacingChoice`, `ProjectSettingsView`, window host. |
| `SiteForge/SupportSettings.swift` | `SettingsDestination.project` ("Project", `folder`); `SettingsDraftNotice(projectDirty:)` (default `false`); root view `project` store, pane, draft notice and Cancel Drafts. |
| `SiteForge/SiteForgeApp.swift` | `projectSettings` store passed to the Settings root. |
| `SiteForge/InsertionModel.swift` | `AuthoringLanguage.projectPreferencesScope`. |
| `SiteForge/PackagedSiteTemplate.swift` | Template copies keep `projectPreferences`. |

Tests:

| File | Change |
|---|---|
| `Tests/SiteForgeTests/CanvasSettingsTests.swift` | 7 new tests (see selectors). |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | 1 new test. |
| `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift` | 1 new UI journey. |
| `Tests/SiteForgeTests/WorkspaceMaterialPolicyTests.swift`, `Tests/SiteForgeTests/SupportSettingsTests.swift` | Expected `SettingsDestination` order now includes `project` after `canvas` (deliberate product change, not a weakened check). |
| `scripts/ci-ui-timings.txt` | Row for the new UI journey (**estimated** 50 s, between comparable Settings journeys at 37–57 s; 8-shard spread recomputed at 6 s, limit < 10 s). |

Docs: this section and `docs/architecture-decisions/ADR-0027-project-scoped-preferences.md` (new).

### New selectors

```
SiteForgeTests/CanvasSettingsTests/testProjectPreferencesResolutionPrecedenceValidationAndStrictCoding
SiteForgeTests/CanvasSettingsTests/testProjectPreferencesDocumentSchemaGateAndBackwardCompatibleReopen
SiteForgeTests/CanvasSettingsTests/testProjectPreferencesRegistryUndoRedoAndRejectionsWithoutMutation
SiteForgeTests/CanvasSettingsTests/testWorkspaceAdoptsAuthoredProjectGridAndKeepsSceneToggleLocal
SiteForgeTests/CanvasSettingsTests/testProjectSettingsStoreDraftApplyCancelStaleResetAndNoProject
SiteForgeTests/CanvasSettingsTests/testProjectPreferencesStayResponsiveOnStandardLargeAndStressFixtures (renamed from ...OnStandardAndLargeFixtures)
SiteForgeTests/CanvasSettingsTests/testProjectSettingsDestinationChoicesAndPendingDraftNotice
SiteForgeTests/PersistedHistoryTests/testProjectPreferencesSaveReopenRecoveryAndPersistedHistorySchema
SiteForgeUITests/SiteForgeLaunchTests/testProjectSettingsGridPreferenceDraftApplyUndoAndCancelJourney
```

### Verification status

- Swift: **not compiled, not run.** Written against the current source and the
  existing Website Settings command path as the template.
- No UI journey was executed; its Settings pop-up and Undo steps follow existing journeys.

### Open risks and known gaps

- Swift 6 strict concurrency: `ProjectSettingsStore` default `resolveTarget` closure,
  `nonisolated static let` strings and the `@objc` window observers mirror
  `CanvasSettingsStore`, but were not compiled.
- Every save now writes document schema 22, so older builds cannot open new saves.
- App text size is **not** implemented (named by the owner as an app-scoped example);
  only the scope and the Project pane were built in this batch.
- No version-comparison surface exists in the codebase to exercise (SF-0206 lists it).

### Batch 03 save-limit fix (same day, unverified)

Owner asked to fix the save-limit problem found with the stress fixture. The
package v1 4 MiB member cap is a security boundary (ADR-0012), so the limits are
unchanged; the fix makes reaching them safe and truthful, and raises the
capacity question as `OPEN_DECISIONS.md` OD-032 (recommends a package-v2 split
into bounded per-page members; owner decision).

| File | Change |
|---|---|
| `SiteForge/ProjectPackage.swift` | `makeMeasuredContainer(for:)` returns the container plus `document.json` size; `makeContainer` wraps it. `writeMeasured(...)` returns fingerprint + document bytes; `write` wraps it (signature and behavior unchanged). |
| `SiteForge/DocumentLifecycle.swift` | `DocumentLifecycleFailure.projectTooLarge` (message, diagnostic category `project-too-large`); a write's `ProjectPackageError.oversizedInput` maps to it (reads unchanged). `CompletedPackageWrite.documentBytes`. New `ProjectFileCapacity` (levels normal / nearLimit ≥ 85% / exceeded). Controller `capacity` set on successful save and autosave, `.exceededLimit` on a too-large save/autosave, reset on new/open/restore. |
| `SiteForge/WorkspaceShellView.swift` | Status bar: help text on the document status; `status.projectCapacity` label when near/over the limit; one high-priority accessibility announcement when the level changes to near/over. |
| `Tests/SiteForgeTests/DocumentLifecycleTests.swift` | `makeController(document:)` parameter (default unchanged); 2 new tests. |
| `docs/OPEN_DECISIONS.md` | New OD-032 at the top. |

New selectors:

```
SiteForgeTests/DocumentLifecycleTests/testProjectTooLargeSaveAndAutosaveAreRefusedTruthfullyWithoutWriting
SiteForgeTests/DocumentLifecycleTests/testProjectFileCapacityIsMeasuredOnSaveAndAutosaveAndWarnsNearTheLimit
```

Known gaps: capacity is unknown after Open until the first save/autosave (the
reader does not expose member sizes); no UI journey for the status-bar warning;
a refused autosave means crash recovery does not cover edits made while over
the limit (surfaced by the failure, not fixed).

### Batch 03 stress fixture (same day, unverified)

Owner chose to add the stress fixture SF-0206-007 asks for ("stress fixtures
target the documented practical limit"). The spec states no number. The limit
the code documents and enforces is the canonical node budget shared by
insertion, layout and the resolved render graph: `InsertionPolicy.maximumNodeCount`
= `LayoutPolicy.maximumNodeCount` = `ResolvedGraphPolicy.maximumNodes` = 20,000.

| File | Change |
|---|---|
| `SiteForge/WorkspaceShellModel.swift` | `WorkspaceFixtureScale.stress` (launch value `stress`): blank baseline plus single-root pages until total nodes = 20,000 (20,000 pages); `stressPageCount`; `pageCount` is now a switch. Standard/large unchanged. |
| `Tests/SiteForgeTests/CanvasSettingsTests.swift` | New `testStressFixtureFillsTheDocumentedNodeBudgetExactly`; perf test renamed to `testProjectPreferencesStayResponsiveOnStandardLargeAndStressFixtures` and now also covers stress plus workspace adoption and a Settings Apply at stress. |
| `Tests/SiteForgeTests/PersistedHistoryTests.swift` | New `testProjectPreferencesPersistAtLargeFixtureAndRespectPackageLimitAtStress`. |

**Finding for Codex/owner (pre-existing, not changed):** package v1 caps each
member at 4 MiB (ADR-0001/ADR-0012). Estimated from the minimal-page JSON shape,
the large fixture's `document.json` is ~3.6 MiB and the stress fixture's ~7.1 MiB,
so a project that reaches the 20,000-node editing budget cannot be saved even with
empty pages; real pages with content reach 4 MiB far sooner. The save is refused
before writing (`oversizedInput`), so no data is lost, but the editor allows
building more than can be saved. The new persistence test branches on the actual
encoded size, so it stays correct if either limit changes. Recommend an
`OPEN_DECISIONS.md` entry: align the node budget with the package cap, raise the
cap under ADR-0012, or warn before the cap is reached.

All bounds in the new tests are safety bounds, not budgets; named-hardware timings
still need retained evidence. Nothing was compiled or run.

### Batch 03 refinement — spec comparison (same day, unverified)

Owner asked to compare batch 03 with the development docs and fix gaps. Compared
against spec module 2.6 (behavioral model, states, SF-0206-001…008, module
checklist), `AGENTS.md`, `docs/TESTING.md`, `docs/COMPLETION_ROADMAP.md` batch 2
and the SF-AUTHORING-064 deferred list (which names project-canonical preferences
and grid spacing configuration as the deferred items).

Gaps found and fixed:

| Gap | Fix |
|---|---|
| Opening runs full validation, so one out-of-range stored spacing made the whole project unopenable (violates "invalid values recover safely", SF-0206-004). | Value-rule violations are retained, resolved as `invalidProjectValue` with the SiteForge default, explained in Settings with a **Use SiteForge Default** repair; registry still blocks introducing invalid values. |
| No stable identity for individual preferences (SF-0206-001/004). | `ProjectPreferenceID` (`project.canvas.gridVisibleOnOpen`, `project.canvas.gridSpacing`); used in diagnostics. |
| Diagnostics always said SF-0206-008 and named no affected preference. | Per-operation requirement IDs plus affected preference IDs; still value-free. |
| Busy/read-only state only showed a tooltip and did not refresh. | Pane observes Preview and lifecycle phase, shows the reason, keeps the draft. |
| Empty state explained but offered no action ("provide it directly"). | **Open or Create a Project…** brings a SiteForge window forward (opens one if none). |
| Fine spacing could draw up to 4x more grid lines than today (SF-0206-007). | Density floor of 8 screen points between minor lines; default grid unchanged. |
| Module checklist: preview/export semantics not demonstrated. | Test proves static output is identical with and without preferences. |
| Migration: no positive test that a v3 history still restores. | Added to the history test. |

Files changed by this refinement: `SiteForge/DocumentModel.swift`,
`SiteForge/TransformModel.swift`, `SiteForge/CanvasSettings.swift`,
`SiteForge/CanvasViewport.swift`, `Tests/SiteForgeTests/CanvasSettingsTests.swift`,
`Tests/SiteForgeTests/PersistedHistoryTests.swift`, ADR-0027, this file.
`ProjectSettingsStore.Diagnostic` changed shape (`requirementIDs`, `preferenceIDs`).

New selectors:

```
SiteForgeTests/CanvasSettingsTests/testProjectPreferencesInvalidStoredValueIsRetainedRepairedAndNeverIntroduced
SiteForgeTests/CanvasSettingsTests/testProjectPreferencesAreEditorOnlyAndNeverChangePreviewOrExportOutput
SiteForgeTests/CanvasSettingsTests/testProjectSettingsStoreUnavailableInvalidRepairAndValueFreeDiagnostics
```

Requirement coverage after refinement (source only; nothing executed):

| SF-ID | Covered in source | Still open |
|---|---|---|
| 001 Authoritative state | Optional versioned record, omitted/default/authored distinct, strict coding, stable preference IDs, schema-22 gate | Version comparison: no comparison surface exists in the app |
| 002 Create and modify | Draft → Apply/Cancel/Escape/Reset; preview of resolved value in provenance before commit | — |
| 003 Resolution rules | Project → this Mac → SiteForge; invalid fallback; provenance per control | — |
| 004 Failure and recovery | Stale/different/closed project, busy lifecycle, invalid stored and new values, repair, Undo | — |
| 005 History and persistence | One transaction per Apply; undo/redo; save/reopen; autosave recovery; history v4 with v3 migration | Version comparison (as 001) |
| 006 Accessible operation | Native pickers/buttons with labels, ids, announcements on status; Settings sidebar arrow-key navigation reaches Project; ⌘, menu path | VoiceOver / Full Keyboard Access / 200% matrix is exploratory QA; no dedicated menu item beyond Settings |
| 007 Performance and scale | Standard and large fixture bounds; bounded grid density | No stress fixture exists in the codebase; named-hardware timings |
| 008 Diagnostics and tests | Per-operation value-free records; unit, integration, history, migration, UI journey | Support bundle does not include Settings diagnostics (true for existing Appearance/Canvas stores too) |

Not changed: app text size (the spec defines no app text-size preference; the owner
named it as an example of an app-scoped setting), grid color (deferred in
SF-AUTHORING-064), `IMPLEMENTATION_STATUS.md`/`CHANGELOG.md`/`REQUIREMENT_EVIDENCE.json`
(no verified result to record).

## Batch 02 — November 25, 2026 (tests and browser harness, unverified)

**Owner instruction for this batch:** build production code and comprehensive
tests in the existing test format, following the development specification; work
only in this iCloud working copy so the changes show as uncommitted on the Mac for
Codex to review. Codex was paused while these edits were made.

**Starting point:** this tree was byte-identical to restore point
`RP-2026-11-25-02` (taken earlier the same day). Restore points are kept outside
the repository on the owner's Windows PC.

**Edited tree:** this iCloud working copy only. The owner's Windows GitHub clone
was not edited in this batch.

### Files

Tests (Swift; added to existing target files, no project-file change):

| File | Change |
|---|---|
| `Tests/SiteForgeTests/TransformModelTests.swift` | Added `testGlassSurfaceTypedValidationHistoryFallbackOutputAndHistoricalSchema`, `testFlowEligibilityDisabledIntentPageBudgetAndEscapedOutputConfiguration`, `testLocalColorTokenDarkVariantHistorySchemaGateAndThemedStaticOutput` after the two existing decorative-effects tests. |
| `Tests/SiteForgeTests/CanvasRendererTests.swift` | Added `testPremultipliedGradientInterpolationMatchesCSSReferenceForAlphaHardStopsAndBounds` before `testFillLayersAreImmutablePlanDataAndExcludeEditorOverlays`. |
| `Tests/SiteForgeTests/SupportSettingsTests.swift` | Added `testFlowRuntimeActualBrowserDeformationFallbacksAndLifecycle`, its private helpers `writeFlowFixture` and `runFlowTooling`, and a file-private `FlowRuntimeBrowserFixtures` enum at the end of the file. |

Tooling (Python, new files, not compiled by Xcode):

| File | Change |
|---|---|
| `Tests/Tooling/flow_runtime_browser.py` | New. Promotes `.codex-loop/interactive/flow_runtime_browser-draft.py` to an 11-case actual-browser harness (owned temporary Chrome profile, loopback DevTools and loopback static server, standard library only). |
| `Tests/Tooling/test_flow_runtime_browser.py` | New. Pure checks of the harness PNG decoder, pixel difference, raster budget and case list. These 5 checks were executed by Code Forge in Python and passed; the browser harness itself was not run. |

Docs:

| File | Change |
|---|---|
| `docs/coordination/CODE_FORGE_ACTIVITY.md` | New (this file). |
| `docs/coordination/QUICK_BATCH_01_HANDOFF.md`, `docs/CODEX_HANDOFF.md`, `docs/IMPLEMENTATION_STATUS.md`, `docs/REQUIREMENT_EVIDENCE.json` | Factual update only: the hosted branch, pull request and run named by batch 01 were deleted by the owner (see below). |

No source files under `SiteForge/`, no scripts, no `ci.yml`, no `ci-ui-timings.txt`
and no `SiteForge.xcodeproj` were changed in this batch.

### New core selectors

```
SiteForgeTests/TransformModelTests/testGlassSurfaceTypedValidationHistoryFallbackOutputAndHistoricalSchema
SiteForgeTests/TransformModelTests/testFlowEligibilityDisabledIntentPageBudgetAndEscapedOutputConfiguration
SiteForgeTests/TransformModelTests/testLocalColorTokenDarkVariantHistorySchemaGateAndThemedStaticOutput
SiteForgeTests/CanvasRendererTests/testPremultipliedGradientInterpolationMatchesCSSReferenceForAlphaHardStopsAndBounds
SiteForgeTests/SupportSettingsTests/testFlowRuntimeActualBrowserDeformationFallbacksAndLifecycle
```

No UI tests were added, so `scripts/ci-ui-timings.txt` is unchanged.

### What each test covers

- **Glass:** typed validation (blur 0–60, opaque fallbacks), mixed-kind skipping
  with a reason, one undo, stable property IDs on edit, no-change/stale/invalid
  rejection without mutation, closed `style.glass.` namespace, generated
  `backdrop-filter`, `@supports not`, `prefers-reduced-transparency` and dark
  fallback CSS, serializer round trip, schema-20 rejection and clean removal.
- **Flow:** eligibility ignores disabled layers and caps stops at 64; enabling on
  an ineligible fill is refused unchanged; disabled intent is kept with no runtime
  or finding; five enabled flows on one page produce
  `flow-configuration-unavailable` and four compile; the `data-siteforge-flow`
  attribute is the HTML-escaped configuration JSON; runtime angle 315 matches the
  static `linear-gradient(45.0deg` output; runtime CSS ships with the stylesheet.
- **Dark token variant:** `.darkVariant` is one transaction; unchanged, invalid
  and unknown-token edits are rejected; light output is unchanged and the dark
  value is emitted only inside `@media (prefers-color-scheme:dark)` with
  `:root { color-scheme:light dark; }`; undo/redo; recolor, rename and update keep
  the variant; invalid variants fail validation; schema 20 rejects a variant and
  accepts the document once it is removed.
- **Premultiplied interpolation:** `CanonicalSolidColor.premultipliedInterpolation`
  against a CSS Images 4 reference (premultiply, interpolate, un-premultiply)
  across alpha samples, symmetry, bounds, and `CanvasAuthoredFillCompositor`
  ordering of coincident stops as hard edges.
- **Browser harness:** WebGL plus the shared local runtime; pointer deformation;
  larger radius/strength produce more change; return to static rest after
  pointer leave; at most one pending frame; reduced motion, no hover and
  JavaScript-disabled keep the static gradient (and links) with no canvas;
  element removal and `pagehide` dispose the runtime; the canvas has
  `pointer-events:none` and never wins hit testing over a link; canvas matches the
  element and stays within the 1024×768 / 786,432-pixel raster budget at 1440,
  768 and 390 CSS-pixel viewports. Fixture sites are compiled by
  `MultiPageStaticBuildPlanner` from three ordinary validated documents.

### Verification status

- Swift: **not compiled, not run.** Written against the current source APIs and
  existing test helpers (`formattingFixture`, `gradientLayer`, `assertRGBA`,
  `toolingInputRoot`).
- Python helper checks: 5/5 passed in Code Forge's Python environment.
- Browser harness: **not run** (no browser was available to Code Forge).

### Open risks and known gaps

- The browser harness passes `--use-angle=swiftshader --enable-unsafe-swiftshader`
  so a GPU-less runner still has WebGL; the first case fails explicitly if WebGL is
  still unavailable.
- The no-hover case relies on `Emulation.setTouchEmulationEnabled` switching
  `(hover: hover) and (pointer: fine)` to false. If Chrome does not, the case fails
  with an explicit "could not emulate" message rather than passing.
- The bridge test launches `/usr/bin/python3` and Chrome from the test host, as the
  existing affected-scope tooling test launches python3. Whether the hosted CI test
  host permits launching Chrome was not observed.
- Pixel thresholds (≥1,000 changed pixels for deformation, large > 3× small,
  ≤0.2% for static comparisons) are reasoned from the runtime math, not measured.
- Still open from Codex's own assignment, not addressed here: the Aurora Flow
  sample bytes are not bundled (no Swift runtime was available to generate them),
  there is no `launch.newAuroraFlowProject` UI journey, and the pending
  alpha-fix and Colors-panel replays have no receipts in this tree.

## Batch 01 — November 25, 2026 (unverified candidate)

Full detail: [QUICK_BATCH_01_HANDOFF](QUICK_BATCH_01_HANDOFF.md).

- **Changed files (5):** `scripts/ci-ui-timings.txt` (two missing fast-style UI
  rows, estimated 150 s and 210 s), `.github/workflows/ci.yml` (Safari pre-open
  regex adds `FastStyleVisibleColors`), `SiteForge/PackagedSiteTemplate.swift`
  (`auroraFlowID`, `auroraFlowURL`), `SiteForge/LaunchExperience.swift` (Aurora Flow
  creation choice and Start card shown only when the sample is bundled) and
  `Tests/SiteForgeTests/LaunchExperienceTests.swift` (two tests plus
  `AuroraFlowShowcaseRecipe`).
- **Docs:** `docs/coordination/QUICK_BATCH_01_HANDOFF.md` (new), entries in
  `docs/CODEX_QUEUE.md` and `docs/evidence/SF-INTERACTIVE-GRADIENT-SHOWCASE.md`, and
  Nov 25 sections in `docs/IMPLEMENTATION_STATUS.md`, `docs/CHANGELOG.md`,
  `docs/CODEX_HANDOFF.md` plus `currentCodeForgeBatch01` in
  `docs/REQUIREMENT_EVIDENCE.json`.
- **Hosted CI history:** the owner copied this whole working tree (Codex's
  uncommitted Nov 15–22 files plus batch 01) into the Windows GitHub clone and
  published it as branch `quick/batch-01` (commit `fe77e61`) with draft PR #1. In run
  #127 the "Build app and test targets" step passed on UI shards 1 and 2
  (about 7.5–8 minutes), so that tree compiled with the Windows-prepared project
  file. The core job was not acquired by a runner. The owner then deleted the
  pull request and the branch before UI tests finished; no test results were kept.
- **Project file:** that published branch's `project.pbxproj` was the committed
  `0133939` file plus app-target entries (IDs `…F8`–`…FC`) for
  `DecorativeEffects.swift`, `DecorativeEffectsInspector.swift`,
  `FastStyleControls.swift`, `FooterContent.swift` and `TestingWindow.swift`. The
  Mac's own `SiteForge.xcodeproj` was never read or written by Code Forge.
- **Restore points:** `RP-2026-11-25-01` (before batch 01) and `RP-2026-11-25-02`.
