# Lane V11 review — site localization (lane E batches E02–E08 and lane RE fixes), 2026-11-26

Reviewer: lane V11 (`lane-V11`), lane V verification. Start state: `RP-2026-11-26-V00`. No compiler, git or
subprocess on this machine: every changed line was re-read against the declarations it calls. All writes went
through `forge_io.edit` / `write_new`; `check()` returned `[]` for every changed file, `foreign_changes(30)` and
`icloud_duplicates()` stayed `[]`. Still document schema 27, persisted-history schema 4, website metadata
version 3; no new `CanonicalDocument` key, command, feature flag or Swift file.

## Scope

| Batch | ADR | Diffed against | Verified |
|---|---|---|---|
| E02 | ADR-0080 | RP-E02 → RP-E03 | `SiteLocaleCode`, `SiteLocale`/`SiteLocalization` exact-key Codable (null refused, omit when defaulted), `CanonicalLocalization.issues`/`walk`, `SiteLocaleResolver`, `SiteLocalizationEditing`, `SetLocalizationCommand` in all 5 `CommandKernel` switches with explicit `setMediaAssets`/`setFontAssets` cases, persisted payload keys, snapshot restore, comparison, template copy, validation call (`CanonicalDocument.validate` → issues + `CanonicalTranslations.validate`) |
| E03 | ADR-0081 | RP-E03 → RP-E04 | `SiteTranslationKey` (canonical lowercase id), node/document validation, resolver, report, `transitionCommands` (incl. lane RE fix 2), asset delete protection |
| E04 | ADR-0082 | RP-E04 → RP-E05 | `SiteLanguageOutput.passes/translatedDocument/relativeRoutes/alternates/translatedAssetIDs/findings`, per-language loop in `MultiPageStaticBuildPlanner.plan` (paths, prefixes, poster rewrite, hreflang, sitemap), Static Release CSS optimizer reads every language tree's HTML |
| E05 | ADR-0083 | RP-E05 → RP-E06 | Languages sheet (`SiteLanguagesEditorView`), `commitLanguages`, menu item behind the flag |
| E06 | ADR-0084 | RP-E06 → RP-E07 | `SiteTranslationInspection`, `SiteTranslationInspectorView`, `commitTranslation` |
| E07 | ADR-0085 | RP-E07 → RP-E08 | `SiteCanvasLanguage`, `CanvasLanguageBar`, stale-plan guard, Preview guards |
| E08 | ADR-0086 | RP-E08 → RP-R01 | `SiteRightToLeftCanvasLayout.mirrored/childRule` (exhaustive `NodeKind` switch), request flag, transform refusal |
| lane RE | — | RP-R01 → RP-V00 | fixes 1–5 (comparison entry, default move + removal, translated-image copy/paste, mirrored click announcement, picker labels) |

Modules: SF-1007, SF-1506. Files changed by this lane: `SiteForge/DocumentModel.swift`, `CanvasRendererCore.swift`,
`ProjectResources.swift`, `ClipboardTransfer.swift`, `TransformModel.swift`, `BrowserPreview.swift`,
`WorkspaceShellModel.swift`, `WorkspaceShellView.swift`, `SupportSettings.swift`,
`Tests/SiteForgeTests/PersistedHistoryTests.swift`, `ClipboardTransferTests.swift`, `CommandKernelTests.swift`;
new `docs/architecture-decisions/ADR-0087-site-language-leftovers.md` and this report.

## Fixes made

| # | File / symbol | Defect | Fix | Why / checked against |
|---|---|---|---|---|
| 1 | `TransformModel.swift` `ComponentDefinitionGraphCopy.remap` | Cross-project definition import (one of the six copy paths) did not remap an image only a translation shows; when the asset was de-duplicated or re-identified the imported definition referenced a missing asset and `CanonicalTranslations.validate` refused the whole paste. Lane RE fix 3 covered element paste and the fingerprint only. | The asset-id branch also accepts `SiteTranslationKey(rawValue: key)?.field == .imageAssetID`. | Same condition as `ClipboardTransfer` paste (RE fix 3); `assetMap` is empty for same-project callers (Create Component, library import), so they are unchanged. |
| 2 | `ClipboardTransfer.swift` paste node construction and `prepareComponentImport` | Projects made from one template share language identities; pasting into one whose default is another of them carried a translation keyed to the destination default, which validation refuses, so the whole paste failed (RE gap 3). | `SiteTranslationEditing.pastableProperties(_:into:)` for pasted elements and `pastablePage(_:into:)` for imported definitions drop exactly those translations. | `document` is the destination in both scopes; `DocumentPage.nodes` / `DocumentNode.properties` are `var`. Test `testCrossProjectPasteDropsTranslationsKeyedToTheDestinationDefaultLanguage`. |
| 3 | `ProjectResources.swift` `ImageAssetReference.references` / `Kind` | Reveal Usage and the Uses list did not show translated images, while Replace Everywhere retargets them and delete is refused for them; the Replace confirmation count differed from the retarget count (RE gap 1). | New `Kind.translation` ("Translated images"); references include translated images (orphans too, because they are stored and still protect the asset). | No `switch` over `Kind` anywhere in the tree; `summary` iterates `allCases`; `revealImageAssetReference` handles any page/node reference. |
| 4 | `Tests/…/CommandKernelTests.swift` `testSelectedMediaAssetUseAndGlobalReferenceInventoryPreserveScope` | The test asserted one use of **every** `Kind` while its fixture creates 5 uses for (now) 7 kinds; it already failed since `socialImage` was added (batches 07–14). | Asserts the exact set `[.image, .fill, .definition, .mediaOverride, .favicon]` and one use of each; count 5 unchanged. | The test was wrong, not the code; nothing weakened. Small and certain, so fixed here (outside lane E). |
| 5 | `WorkspaceShellModel.swift` `canvasLanguageStatus` | The canvas bar rebuilt a whole-site `SiteTranslationReport` on every render (RE gap 5, SF-1007-007). | Cached per document id, revision, shown language and Mirror Layout (same pattern as `authoringDocumentCache`); reset when another document opens. | Revisions are monotonic (undo/redo commit inverses). |
| 6 | `WorkspaceShellModel.swift` `scheduleScenePreparation` / worker | `SiteLanguageOutput.translatedDocument` ran on the main actor for every scene preparation (RE gap 6). | `WorkspaceScenePreparationRequest.displayedLocaleID` (defaulted) + `displayingShownLanguage()`; `WorkspaceScenePreparationWorker.prepare(_ incomingRequest:progress:)` translates first. | External label `_` unchanged, so all callers compile; identity/revision unchanged so adoption gates hold. |
| 7 | `WorkspaceShellModel.swift` `geometryInspectorValue` | A computed X from a mirrored plan was shown as plain "Computed by responsive layout" (RE gap 4). | `SiteRightToLeftCanvasLayout.computedSource` appends ", mirrored right to left" while the adopted plan is mirrored. | Uses the plan's own mirroring (`canvasRenderPlanMirrors`). |
| 8 | `DocumentModel.swift` `SiteTranslationInspection.target`; shell `translationInspectorTarget` | Definition translations are exported for every instance and counted as missing by the report, but the Inspector refused to edit them (RE gap 8, first half). | Definition pages are allowed; the section is still hidden while a variant is open. | `effectiveSelectedPageID` is the definition while one is open; `canEditTranslations` still requires no variant. |
| 9 | `docs/architecture-decisions/ADR-0086` claim (documented in ADR-0087) | ADR-0086 said text without authored typography is right aligned by the browser in RTL trees. Export writes `text-align: left` for **every** Text/Button/Link (`CanonicalTypography.resolved(for:)` supplies the default), so the canvas already matches. Building "right alignment of untyped text" would have made canvas and export disagree. | No code change; ADR-0087 corrects the record; logical alignment in export is OD-090 part 3. | `CanvasRendererCore` line ~830 `typography: node.kind.isTextual ? CanonicalTypography.resolved(for: node) : nil`; emitter writes `text-align` unconditionally. |
| 10 | `SupportSettings.swift` `siteLanguages` summary | The flag summary did not describe the new UI. | Mentions Website Preview and Mirror Layout; keeps the substrings the tests assert ("Translations section", "canvas and Local Preview"). | `SupportSettingsTests.swift` is an unreadable placeholder; no readable test checks the full string. |

Verified without change: lane RE fixes 1–5 (the `transitionCommands` labeled tuple and `guard … else { continue }`,
`CanonicalGraphReferences.assets` multi-line guard, envelope reference set, fingerprint, `pressesSelection`);
`SiteLanguagesEditorView` generic `localeBinding` (`Value?` chaining is correct in generic context), `let` in
`ViewBuilder` closures, picker tags; `SiteTranslationInspectorView` bindings and `TextField(_:text:axis:)`;
`CanvasLanguageBar` tags; RE gap 2 (an image used only by an orphaned translation counts as used) is correct by
design: the stored translation still references it, delete is refused, so Remove Unused must not propose it; the
`translation-orphaned` finding names the recovery.

## Features finished (ADR-0087, inside OD-038)

- **Right-to-left default language on the canvas** — "Mirror Layout" (view state `canvasMirrorsDefaultLanguage`,
  `setDefaultLanguageMirroring(_:)`, checkbox `canvas.language.mirrorDefault`, diagnostics `mirror-default` /
  `unmirror-default`, transforms and canvas text editing refused with `defaultMirrorRefusal`, stale plans and
  Preview guarded by `canvasRenderPlanMirrors` / `previewMirrorsRightToLeft`). Finished up to the boundary:
  transforms in mirrored coordinates need OD-090 part 1.
- **Website Preview at the shown language's address** — `BrowserPreviewController.build(…, localeID:)` +
  `SiteLanguageOutput.previewPath`.
- **Right alignment of untyped text** — resolved as no change (fix 9); OD-090 part 3 for logical alignment.
- **Lane RE gaps** 1, 3, 4, 5, 6 (fixes 2–7), 8 first half (fix 8), 9 performance fixtures (100 / 10,000
  objects); gap 2 verified correct by design.

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-1007-001 state | Met | Exact-key `SiteLocalization`/`SiteLocale`, authored-only translation properties; `testSiteLanguagesAreStrictSchemaGatedUndoableAndPersistedInHistory`, `testSiteTranslationsAreStrictUndoablePersistedAndResolvedPerLanguage` |
| SF-1007-002 create/modify | Partial | Sheet, Inspector (now incl. definitions), canvas/Local/Website Preview in a language, report + `translation-missing`; instance overrides, collection item values, page names/metadata not translatable (OD-090 part 2); no UI test (harness) |
| SF-1007-003 resolution | Met | `SiteLocaleResolution`/`SiteTranslationResolution.explanation`, Inspector rows, canvas status; E02/E03/E06/E07 tests |
| SF-1007-004 failure/recovery | Met | Every refusal leaves the document unchanged with a recovery; cross-template paste and cross-project definition import no longer refused (fixes 1–2); `testCrossProjectPasteDropsTranslationsKeyedToTheDestinationDefaultLanguage` |
| SF-1007-005 history/persistence | Met | One grouped undoable edit per change, persisted history, snapshot restore/comparison, hreflang |
| SF-1007-006 accessibility | Partial | Labels/identifiers on every control incl. Mirror Layout, keyboard-reachable pickers/toggle, announcements; no UI/VoiceOver test (harness unreadable) |
| SF-1007-007 performance | Met | Off-main translation (fix 6), cached status (fix 5), Inspector reads one element; `testSiteLanguagesStayWithinSafetyBoundsOnStandardAndLargeFixtures` (100 / 10,000). Local Preview Open still translates the other pages once, at the explicit action |
| SF-1007-008 diagnostics/tests | Partial | Sanitized diagnostics (edit, translation, canvas incl. mirror); 13 unit/integration tests; UI tests blocked |
| SF-1506-001 state | Met | As SF-1007-001 (authored sites; app UI English-only per OD-038) |
| SF-1506-002 create/modify | Partial | Direction authored/implied; authored-site date/number formatting is outside OD-038 |
| SF-1506-003 resolution | Met | Direction provenance, `lang`/`dir` in export, mirrored canvas for shown languages and (on request) the default |
| SF-1506-004 failure/recovery | Met | Invalid codes/directions refused; Mirror Layout refused for a left-to-right default with failure `not-right-to-left` |
| SF-1506-005 history/persistence | Met | Direction edits undoable and persisted; Mirror Layout is view state, never undone (tested) |
| SF-1506-006 accessibility | Partial | RTL typing in the Inspector, Mirror Layout labelled; no VoiceOver test |
| SF-1506-007 performance | Met | As SF-1007-007 |
| SF-1506-008 diagnostics/tests | Partial | As SF-1007-008 |

Totals: 10 Met, 6 Partial, 0 Missing.

## Remaining work (blocked only)

1. OD-090 part 1 — moving/resizing on a mirrored canvas (needed to mirror a right-to-left default by default):
   owner decision plus compiler verification of mirrored geometry. Until then they are refused with a recovery.
2. OD-090 part 2 — translating component instance text overrides, collection item values, page names and page
   metadata: new translation keys/export rules need an owner decision.
3. OD-090 part 3 — logical text alignment (`start`/`end`) in export: changes every exported stylesheet.
4. UI / VoiceOver tests for the Languages sheet, Inspector section and canvas bar: UI harness unavailable here
   (`docs/TESTING.md` is an unreadable placeholder; no Xcode).
5. SF-1506-002 authored-site date/number formatting: outside OD-038; needs its own OD.

## Proposed OD (AGENTS.md format) — for the coordinator to add to docs/OPEN_DECISIONS.md

## OD-090 — Site languages: mirrored editing, more translatable values, logical alignment

Status: Open — proposed by Code Forge lane V11 on 2026-11-26.

- Affected requirements: SF-1007-002, SF-1007-007, SF-1506-002, SF-1506-003.
- Recommended default: (1) keep moving and resizing refused while the canvas is mirrored and keep Mirror Layout
  opt-in for a right-to-left default until Codex verifies the mirrored geometry; then map pointer deltas through
  `SiteRightToLeftCanvasLayout.mirrored` and mirror a right-to-left default by default. (2) Translate component
  instance text overrides and page titles/descriptions next, with keys `locale.translation.v1.<id>.override.<property>`
  and per-language page metadata; collection item values later. (3) Export `leading`/`trailing` text alignment as
  CSS `start`/`end` in a new profile-neutral output change, with a snapshot-test update.
- Alternative: keep authoring left to right only and rely on export for right-to-left review; keep only node text,
  alternative text and images translatable.
- Tradeoff: (1)–(3) touch transforms, schema-adjacent keys and every exported stylesheet, which Codex must verify;
  deferring leaves right-to-left authors without direct manipulation and leaves override text untranslated.
- Safe temporary assumption: current behaviour — transforms refused while mirrored, overrides/collection
  values/page metadata shown in the default language in every tree, `text-align: left` for `leading`.

## Intended plan / OD status-line changes (exact text, for lane V15)

- OD-038, append to the Status line: "Lane V11 (2026-11-26, ADR-0087): Mirror Layout for a right-to-left default
  language (view state; moving, resizing and canvas text editing refused while on), Website Preview opens the shown
  language, translation off the main actor, cached canvas status, translated images listed as uses, cross-template
  paste and cross-project definition import keep translations valid, component definitions translatable, 100/10,000
  performance fixtures; untyped-text alignment needs no change (export writes text-align for every text).
  Remaining: OD-090. Still unverified."
- OD-038, replace "Not built: a right-to-left default language mirrored on the canvas, right alignment of text without
  authored typography, Website Preview at the shown language's address." with "Not built: editing on a mirrored canvas
  and further translatable values (OD-090)."
- Add OD-090 as above.
- DEVELOPMENT_PLAN.md lane E row E1: replace "Leftovers folded into E3+: …" with "Leftovers finished by lane V11
  (ADR-0087); open: OD-090." Lane E state line: "Next ADR: ADR-0088."
- CODE_FORGE_ACTIVITY.md entry: "2026-11-26 lane V11 — verified lane E E02–E08 + lane RE fixes; 10 defects fixed;
  ADR-0087; tests: 3 new in PersistedHistoryTests, 1 new in ClipboardTransferTests, 1 corrected in CommandKernelTests;
  report docs/reviews/LANE-V11-review-2026-11-26.md."

## New/changed test selectors

New:
```
SiteForgeTests/PersistedHistoryTests/testSiteRightToLeftDefaultMirrorsOnRequestKeepsExportedAlignmentAndOpensPreviewInTheShownLanguage
SiteForgeTests/PersistedHistoryTests/testSiteTranslatedImagesAreListedUsesAndDefinitionsAreTranslatable
SiteForgeTests/PersistedHistoryTests/testSiteLanguagesStayWithinSafetyBoundsOnStandardAndLargeFixtures
SiteForgeTests/ClipboardTransferTests/testCrossProjectPasteDropsTranslationsKeyedToTheDestinationDefaultLanguage
```
Changed (test was wrong; nothing weakened):
```
SiteForgeTests/CommandKernelTests/testSelectedMediaAssetUseAndGlobalReferenceInventoryPreserveScope
```
Run also (behaviour touched): all `PersistedHistoryTests/testSite*`, `ClipboardTransferTests` (cross-project
component import), `ProjectResourceTests` (asset uses / retarget), `CanvasRendererTests` Website Preview build tests
(`BrowserPreviewController.build` gained a defaulted parameter).

## Suggested first checks for Codex

- `WorkspaceScenePreparationWorker.prepare(_ incomingRequest:progress:)`: `let request = incomingRequest.displayingShownLanguage()`
  and every later `request.` use; `WorkspaceScenePreparationRequest.displayingShownLanguage()` re-calls the memberwise-style init
  (`viewportWidth: Double` into `Double?`).
- `canvasLanguageStatusCache` labeled tuple assigned from an unlabeled tuple inside a computed getter of the
  `@MainActor` class.
- `CanvasLanguageBar`: `Toggle("Mirror Layout", isOn: Binding(get:set:))` with `_ = state.setDefaultLanguageMirroring($0)`,
  `.toggleStyle(.checkbox)`; the extended `if … || …, … || …` visibility condition in `CanvasPlaceholderView`.
- `refuseCanvasLanguage(_:category:localeID:startedAt:operation:)` defaulted last parameter; callers in
  `showCanvasLanguage` unchanged.
- `ComponentDefinitionGraphCopy.remap`: `if [ … ].contains(key) || SiteTranslationKey(rawValue: key)?.field == .imageAssetID, case .string(let raw) = value, …`.
- `ImageAssetReference.references`: `for entry in CanonicalTranslations.translations(on: node) where entry.key.field == .imageAssetID && entry.property.value == .string(raw)`.
- `BrowserPreviewController.build(document:pageID:package:localeID:isDocumentCurrent:isCurrent:)` — existing calls with
  trailing closures still resolve to `isCurrent`.
- In the new mirror test: `MultiPageStaticBuildPlanner.plan(document:)` on an Arabic-default fixture produces
  `fr/<page path>`; the heading render object exists for the fixture page (root text with layout geometry).
