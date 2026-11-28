# Lane RE review — site languages (lane E batches E02–E08), 2026-11-26

Reviewer: lane R reviewer E (`lane-RE`), Code Forge review freeze. Restore point before the review:
`RP-2026-11-26-R01`. Read-only checks plus five fixes through `forge_io.edit`; no compiler was available, so
every changed line was re-read against the declarations it calls (listed per fix). Still document schema 27,
persisted-history schema 4, website metadata version 3; no new `CanonicalDocument` key, command, flag or file.

## Scope

| Batch | ADR | What it added |
|---|---|---|
| E02 | ADR-0080 | `SiteLocaleID`, `SiteTextDirection`, `SiteLocaleCode`, `SiteLocale`, `SiteLocalization`, `CanonicalLocalization`, `SiteLocaleResolver`, `SiteLocalizationEditing`, `SetLocalizationCommand` / `DocumentCommand.setLocalization`, snapshot restore, comparison, template copy |
| E03 | ADR-0081 | `SiteTranslationField`, `SiteTranslationKey` (`locale.translation.v1.<id>.<field>`), `CanonicalTranslations`, `SiteTranslationResolver`, `SiteTranslationReport`, `SiteTranslationEditing` (`prepare`, `droppedTranslationCount`, `transitionCommands`), asset protection |
| E04 | ADR-0082 | `SiteLanguageOutputPass`, `SiteLanguageOutput`, per-language loop in `MultiPageStaticBuildPlanner.plan`, translated images and findings in `StaticBuildCompiler.compile` |
| E05 | ADR-0083 | `FeatureFlagID.siteLanguages`, Languages sheet (`SiteLanguagesEditorView`), shell `commitLanguages` |
| E06 | ADR-0084 | `SiteTranslationInspection`, Inspector Translations section (`SiteTranslationInspectorView`), shell `commitTranslation` |
| E07 | ADR-0085 | `SiteCanvasLanguage`, `CanvasLanguageBar`, canvas/Preview language state and stale-plan guard |
| E08 | ADR-0086 | `SiteRightToLeftCanvasLayout`, `WorkspaceScenePreparationRequest.mirrorsLayoutRightToLeft`, transform refusal |

Modules: SF-1007 (site localization), SF-1506 (localized strings; per OD-038 the app UI stays English-only,
so SF-1506 is read for authored-site strings). Files reviewed: `SiteForge/DocumentModel.swift`,
`CommandKernel.swift`, `PersistedHistory.swift`, `ProjectPackage.swift`, `PackagedSiteTemplate.swift`,
`ProjectResources.swift`, `ClipboardTransfer.swift`, `CanvasRendererCore.swift`, `WorkspaceShellModel.swift`,
`WorkspaceShellView.swift`, `SupportSettings.swift`, `InsertionModel.swift` (component expansion),
`Tests/SiteForgeTests/PersistedHistoryTests.swift` (the 9 lane E tests and `siteTranslationFixture()`).

## Fixes made

| # | File / symbol | Defect | Fix | Why / checked against |
|---|---|---|---|---|
| 1 | `ProjectPackage.swift` `ProjectComparer.compare` | A language change was listed twice: "Languages" (E02) and "Site languages" (cross-lane review 2). `testSiteLanguagesAreStrictSchemaGatedUndoableAndPersistedInHistory` asserts exactly `["Languages"]`, so it failed. | Removed the second `"Site languages"` block. | No test or doc expects "Site languages" (searched all readable tests). `sameUncomparedContent` still aligns `localization`. |
| 2 | `DocumentModel.swift` `SiteTranslationEditing.transitionCommands` | Making another language the default **and** removing the old default in the same Languages draft (allowed by the sheet: Make Default, then Remove) left the new default's translations keyed to the default, so `CanonicalTranslations.validate` failed and Apply was refused with an obscure validation message. | The swap now runs whenever the new default existed before; the tuple gains `keepsOldDefault`. When the old default is kept, behaviour is unchanged (values swap). When it is removed, the new default's translation becomes the node's own value and the translation property is removed. | `SetPropertyCommand` replaces by property id (`CommandKernel` mutate), `RemovePropertyCommand(pageID:nodeID:propertyID:)`, batch availability mutates then validates once. Undo restores both properties. |
| 3 | `DocumentModel.swift` `CanonicalGraphReferences.assets`; `ClipboardTransfer.swift` envelope check, paste remap, `definitionFingerprint` | Copy/paste did not carry or remap an image that only a translation shows (`locale.translation.v1.<id>.image.assetID`). A cross-project paste (or a paste where the image was de-duplicated to another asset id) produced a translation pointing at a missing asset, so `CanonicalTranslations.validate` refused the whole paste. | `CanonicalGraphReferences.assets` also returns translated image assets; the envelope's `referencedAssets` now uses `CanonicalGraphReferences.assets` (so it equals the dependencies the copy side collects); paste remaps translated image ids through `assetMap`; the component fingerprint compares them semantically. | `SiteTranslationKey(rawValue:)` returns `nil` outside the namespace; `field == .imageAssetID` compares an optional enum. Side effects checked: page chrome copy (`CommandKernel` line ~294, `PageChromeCopyWorker`) now also requires a translated image to be available, and component library export refuses a definition with a translated image (`usesImages`) — both correct, because the destination validates translated image ids. Clipboards written before this change with translated images fail with `invalidDependency` instead of pasting a broken translation. |
| 4 | `WorkspaceShellModel.swift` `beginPointerTransform(at:)` | The canvas calls `onPointerTransformStart` on **every** mouse-down (`beginTransformGesture` in `WorkspaceShellView`), and E08 refused first, so with a right-to-left language shown every click — even a plain selection click or a click with another tool — posted "Moving and resizing … are off" to VoiceOver. | The refusal now runs after the existing select-tool/plan/selection guard and only when the press hits the selection's frame or a handle (`TransformOverlayPlanner.hitHandle`); any mirrored press returns `false` and selection continues. Keyboard, menu and automation transforms are still refused in `beginTransform`. | `TransformOverlayPlanner.hitHandle(at:frame:worldRadius:) -> TransformHandle?`, `WorldRect.minX/maxX/minY/maxY`, `refuseMirroredCanvasTransform()` is not `@discardableResult` (hence `_ =`). Covers the page-flow (header/footer) branch too, because the check precedes it. |
| 5 | `WorkspaceShellView.swift` `SiteLanguagesEditorView.languageRow` | Every row's pickers were read only as "Direction" / "Falls back to" by VoiceOver (SF-1007-006). | `.accessibilityLabel("Reading direction of <name>")` and `.accessibilityLabel("Fallback language of <name>")`. | Identifiers unchanged. |

Found and already fixed concurrently by lane RC (verified in the file, not edited by RE): nested pages (language
trees, item pages) rewrote ` src="assets/` but not a video's ` poster="assets/`, so posters broke under `fr/…`
and lane H's `StaticOutputReferenceAudit` would count them as unresolved. `MultiPageStaticBuildPlanner.plan`
now rewrites both.

Verified without change (selection): `SiteLocaleCode.canonical` against every literal in the E02 test;
`SiteLocalizationIssue` ordering for the cycle/twin cases; the `let fallbackRule: String = switch` and
`let flow: Bool = switch parent.kind` expressions (every `NodeKind` case listed); the `let resolvedGeometry … =
if request.mirrorsLayoutRightToLeft, let activePage { … } else { … }` expression; the `(flow:navigation:)` tuple;
`SetLocalizationCommand` exact keys with `localization` written as null; `PersistedHistory` payload keys;
`DocumentCommand.setLocalization` in all 8 kernel switches and `CommandName.allCases` descriptor test; the
schema-27 gate, strict optional key and null refusal in `CanonicalDocument`; snapshot restore returns exactly
`.batch([.setLocalization])` for the fixture; `PackagedSiteTemplate` copies `localization`; the stale-plan guard
`guard canvasShownLocaleID == requestLocaleID else { throw CanvasRendererError.staleResult }` is caught by the
existing `.staleResult` branch; Preview open/refresh/runtime guards compare `canvasRenderPlanLocaleID`/`previewLocaleID`;
`canvasDisplayedDocument`, `preparePreviewRuntime` and `SiteLanguageOutput.passes` all go through
`SiteLanguageOutput.translatedDocument`; E05–E08 UI is reachable only behind `siteLanguages` (File > Languages…,
Inspector section, canvas bar — the bar stays visible while a non-default language is shown so the author can
switch back after turning the flag off); flag summary contains the strings the tests assert; Arabic/Hebrew literals
contain no bidi control characters; mirrored-layout numbers in the E08 test (576/452/462) match `mirrored`.
Copy paths: translation keys use language identity, not node/page ids, so ClipboardTransfer paste, definition graph
copy, slot contents / Create Component, page duplicate (`CanonicalPageGraphClone`) and component expansion copy them
unchanged (correct within a project; cross-project they become reported orphans). Only translated image ids needed
remapping (fix 3). Output: hreflang (every language + `x-default`, none on Not Found), canonical `/fr/post`, sitemap
with every language, relative links/scripts/styles/images in `fr/` trees, and lane H's manifest/reference audit/budgets
all see the nested files consistently.

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-1007-001 state | Met | `SiteLocalization`/`SiteLocale` (exact keys, omitted vs authored direction/fallback, null refused), translation properties authored-only; tests `testSiteLanguagesAreStrictSchemaGatedUndoableAndPersistedInHistory`, `testSiteTranslationsAreStrictUndoablePersistedAndResolvedPerLanguage` |
| SF-1007-002 create/modify | Partial | Languages sheet, Inspector Translations, canvas language; missing-translation report, `translation-missing` finding. Not translatable: component instance text overrides, collection item values, page names/metadata; no UI test |
| SF-1007-003 resolution | Met | `SiteLocaleResolution.explanation`, `SiteTranslationResolution.explanation`, Inspector rows; tests E02/E03/E06/E07 |
| SF-1007-004 failure/recovery | Met (after fix 2/3) | Every refusal leaves the document unchanged with a recovery message; orphans reported; default move + removal now commits; cross-project paste of translated images now works |
| SF-1007-005 history/persistence | Met | One grouped undoable edit per change; persisted history; snapshot restore/comparison; hreflang. Fix 1 makes the comparison test pass |
| SF-1007-006 accessibility | Partial | Identifiers and labels on all controls (fix 5), announcements; no keyboard shortcut for Languages…, no UI/VoiceOver test |
| SF-1007-007 performance | Partial | Inspector reads one element; but `SiteCanvasLanguage.status` builds a whole-document `SiteTranslationReport` on every canvas-bar render and `translatedDocument` runs on the main actor per scene preparation; no 100/10,000-object fixture |
| SF-1007-008 diagnostics/tests | Partial | Sanitized diagnostics (`SiteLocalizationEditDiagnostic`, `SiteTranslationEditDiagnostic`, `SiteCanvasLanguageDiagnostic`), 9 unit/integration tests; no UI, performance or migration test |
| SF-1506-001 state | Met (authored site) | Same as SF-1007-001; app UI English-only per OD-038 |
| SF-1506-002 create/modify | Partial | Language/direction editing; date/unit formatting for authored sites not in scope of OD-038 |
| SF-1506-003 resolution | Met | Direction authored vs implied by code with provenance; `lang`/`dir` in export; mirrored canvas |
| SF-1506-004 failure/recovery | Met | Invalid codes/directions refused with SF-1007-004 messages |
| SF-1506-005 history/persistence | Met | Direction edits undoable and persisted (E08 test) |
| SF-1506-006 accessibility | Partial | RTL typing in the Inspector; no VoiceOver test of the mirrored canvas |
| SF-1506-007 performance | Partial | As SF-1007-007 |
| SF-1506-008 diagnostics/tests | Partial | As SF-1007-008 |

## Remaining gaps (easiest → hardest)

1. Reveal Usage (`ImageAssetReference.references`) does not list translated image uses (delete is already refused).
   Plan: add a reference kind or a separate "used by a translation" row; mind `CommandKernelTests` line ~317
   (`ImageAssetReference.Kind.allCases`).
2. `ImageAssetDependencies.unusedAssetIDs` counts an image used only by an orphaned translation as used, while export
   skips it (`translatedAssetIDs` only counts current languages). Plan: filter orphans in `CanonicalTranslations.usesAsset`
   for the unused count, keep delete protection.
3. Cross-project paste between projects that share language identities (projects made from the same template) can carry
   a translation keyed to the destination's default language, which validation refuses. Plan: drop translation
   properties keyed to the destination default during `preparePaste` (it is a `.map`, needs a `compactMap`).
4. Geometry Inspector "Computed by responsive layout" X shows the mirrored frame while a right-to-left language is shown;
   edits still change authored values. Plan: read X from the unmirrored geometry or show "mirrored".
5. Canvas bar status rebuilds the whole translation report per render. Plan: cache by document revision + locale in the
   shell (`@Published` value refreshed from the document sink).
6. Move `SiteLanguageOutput.translatedDocument` into `WorkspaceScenePreparationWorker.prepare` (pass locale id +
   localization in the request) so large sites are translated off the main actor.
7. A right-to-left **default** language is not mirrored on the canvas (export writes `dir="rtl"` at the root). Needs
   mirrored transforms (ADR-0086 leftover).
8. Component instance text overrides and collection item values are not translatable (ADR-0081/0082 consequence);
   translations on nodes moved into a definition by Create Component are exported but not editable in the Inspector
   (definition pages are excluded from the Translations section).
9. UI tests for Languages sheet, Inspector section and canvas bar; 100/10,000-object performance fixtures.

## Intended OD status-line changes

- OD-038: append "Reviewed 2026-11-26 by lane RE: fixed duplicate comparison entry, default move + removal refusal,
  translated-image copy/paste, mirrored-canvas click announcements, Languages picker labels; remaining gaps in
  docs/reviews/LANE-RE-review-2026-11-26.md." (Not written: `docs/OPEN_DECISIONS.md` is iCloud-renamed.)

## New/changed test selectors

Changed (assertions added or corrected; no assertion weakened):

```
SiteForgeTests/PersistedHistoryTests/testSiteTranslationReportAndLanguageChangesKeepTranslationsConsistent
SiteForgeTests/PersistedHistoryTests/testSiteTranslationsAreStrictUndoablePersistedAndResolvedPerLanguage
SiteForgeTests/PersistedHistoryTests/testSiteRightToLeftCanvasLayoutMirrorsLaidOutChildrenLikeExportDirection
```

- E03 report test: new block "new default with the old default removed" (exact command names
  `[.setProperty, .removeProperty, .setProperty, .removeProperty, .setLocalization]`, promoted values, Undo).
- E03 strict test: `CanonicalGraphReferences.assets(picture)` contains the translated image.
- E08 test: the press at (10, 10) (no plan, no selection) must **not** announce the refusal; the refusal is now asserted
  through `performTransform(.move(…), provenance: .keyboard)`. The old assertion encoded the defect of fix 4.

Unchanged but now expected to pass (was failing): `testSiteLanguagesAreStrictSchemaGatedUndoableAndPersistedInHistory` (fix 1).

## Suggested first checks for Codex

- `var swap: (from: SiteLocaleID, to: SiteLocaleID, keepsOldDefault: Bool)?` assigned from a labeled tuple literal and
  `guard swap.keepsOldDefault else { …; continue }` inside the `for field` loop (`transitionCommands`).
- `CanonicalGraphReferences.assets`: the multi-line `guard … != nil || SiteTranslationKey(rawValue: …)?.field == .imageAssetID,
  case .string(let raw) = property.value` condition.
- `ClipboardTransfer`: `Set(allNodes.flatMap(CanonicalGraphReferences.assets))` (function reference to a static method
  returning `[AssetID]`), and the `[…].contains(key) || SiteTranslationKey(rawValue: key)?.field == .imageAssetID,` first
  clause of the remap `if` and of the fingerprint `else if`. Run the clipboard and component-library test suites
  (ClipboardTransfer, `testComponentLibrariesExportImportReadOnlyUpdateCompareAndDetach`).
- `beginPointerTransform`: the `pressesSelection` expression and that existing pointer-transform tests (none show a
  right-to-left language) are unaffected.
- The E03 report test's exact command-name order (pages in document order; blank-project pages carry no translations).
- `ProjectComparer.compare` callers/tests that count settings changes (ProjectPackageTests comparison test, A02).
