# ADR-0087 — Site languages: finishing the part 4c leftovers and the lane RE gaps

- Status: Proposed (implemented as an unverified Code Forge candidate by lane V11; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-038 (approved by the owner 2026-11-26 1:30 PM EST); owner instruction 2026-11-26 7:00 PM EST
  "Finish partial features too". Open part: OD-090 (proposed in docs/reviews/LANE-V11-review-2026-11-26.md).
- Builds on: ADR-0081 (translations), ADR-0082 (per-language export), ADR-0084 (Inspector Translations),
  ADR-0085 (language on the canvas), ADR-0086 (right-to-left canvas layout)
- Requirements: SF-1007-002, -003, -004, -006, -007, -008; SF-1506-003, -007; SF-0807-001 (asset uses)

## Context

ADR-0085 and ADR-0086 left three items unbuilt (a right-to-left default language on the canvas, right
alignment of text without authored typography, Website Preview at the shown language's address), and the
lane RE review (docs/reviews/LANE-RE-review-2026-11-26.md) listed nine gaps. The owner asked that partial
features be finished, not only listed.

## Decision

- **Right-to-left default language ("Mirror Layout", view state).** `WorkspaceShellState.canvasMirrorsDefaultLanguage`
  is published view state: never saved, never an undoable edit, reset when another document opens. While the
  default language reads right to left (`SiteRightToLeftCanvasLayout.defaultReadsRightToLeft`) the Canvas
  Language bar offers a "Mirror Layout" checkbox (identifier `canvas.language.mirrorDefault`, keyboard
  reachable, shown even on a one-language site, and kept visible while it is on).
  `setDefaultLanguageMirroring(_:)` mirrors the canvas exactly as ADR-0086 does for other languages and records
  a `SiteCanvasLanguageDiagnostic` (operation `mirror-default` / `unmirror-default`; failure `none`,
  `not-right-to-left` or `busy`; the language identity only). While it is on, moving, resizing and inline text
  editing on the canvas are refused with `SiteRightToLeftCanvasLayout.defaultMirrorRefusal` (recovery: turn off
  Mirror Layout); Inspector edits keep working and show live. The canvas does not mirror a right-to-left
  default by itself, because transforms change the authored (unmirrored) frames; transforms in mirrored
  coordinates are OD-090.
- **Stale plans.** The adopted plan records whether it is mirrored (`canvasRenderPlanMirrors`). A plan prepared
  with the other mirroring is dropped as `CanvasRendererError.staleResult`; Local Preview Open/Refresh wait for
  a plan with the current mirroring, and Refresh is not "already current" after Mirror Layout changes
  (`previewMirrorsRightToLeft`).
- **Text alignment (no change, ADR-0086 corrected).** ADR-0086 said text without authored typography is
  right aligned by the browser in a `dir="rtl"` tree. It is not: `CanonicalTypography.resolved(for:)` gives every
  Text, Button and Link a typography (default alignment `leading`), and export writes `text-align: left` for each
  of them, which `dir` does not change. The canvas already draws the same alignment, so it is left as is.
  Exporting logical alignment (`start`/`end`, so `leading` follows the language's direction) changes every
  exported stylesheet and is OD-090 part 3.
- **Website Preview.** `BrowserPreviewController.build(document:pageID:package:localeID:…)` opens
  `SiteLanguageOutput.previewPath(_:showing:in:)`, the page's path inside the shown language's tree
  (`fr/about.html`); the default language, `nil` and a removed language open the root path.
- **Off the main actor.** `WorkspaceScenePreparationRequest.displayedLocaleID` carries the shown language and
  `WorkspaceScenePreparationWorker.prepare` translates the document (`displayingShownLanguage()`), so a large
  site is no longer translated on the main actor for every scene preparation. Identity and revision are unchanged.
- **Cached canvas status.** `canvasLanguageStatus` is cached per document identity, revision, shown language and
  Mirror Layout, so the whole-site translation report is no longer rebuilt on every canvas-bar render.
- **Geometry Inspector.** A computed X read from a mirrored plan is labelled "…, mirrored right to left"
  (`SiteRightToLeftCanvasLayout.computedSource`); edits still change authored values.
- **Translated images are listed uses.** `ImageAssetReference.Kind.translation` ("Translated images"): Reveal
  Usage, the Uses list, the Replace confirmation count, Replace Everywhere and the delete refusal now agree.
  Translations of removed languages are included because they are still stored and still protect their asset
  (so Remove Unused never proposes a removal that validation would refuse); the `translation-orphaned` build
  finding names the recovery.
- **Copy paths.** `ComponentDefinitionGraphCopy.remap` (cross-project definition import) maps translated image
  identities through the asset map, like element paste (lane RE fix 3). A paste drops a translation keyed to the
  destination's default language (`SiteTranslationEditing.pastableProperties` for elements, `pastablePage` for
  imported definitions) instead of refusing the whole paste; projects made from one template share language
  identities, so this happens when such a project made another of those languages its default.
- **Component definitions are translatable.** The Inspector Translations section also shows for an element of an
  open component definition (not while a variant is open). Definition translations are exported for every
  instance and were already counted as missing by `SiteTranslationReport`, so they must be editable.
- No schema change: document schema 27, persisted-history schema 4, website metadata version 3; no new
  `CanonicalDocument` or node key; no new command; no new feature flag (the UI stays behind
  `localization.site-languages`, whose summary now mentions Website Preview and Mirror Layout).

## Consequences

- Still open (OD-090 part 1): moving and resizing on a mirrored canvas. Recommended default: keep them refused
  while the canvas is mirrored until Codex has verified the mirrored geometry; then map pointer deltas through
  `SiteRightToLeftCanvasLayout.mirrored` (horizontal delta negated for flow children, unchanged for absolutely
  placed children) and turn mirroring of a right-to-left default on by default.
- Still open (OD-090 part 2, owner decision): translating component instance text overrides, collection item
  values, page names and page metadata (new translation keys and export rules).
- UI and VoiceOver tests of the Languages sheet, Inspector section and canvas bar need the UI test harness
  (docs/TESTING.md is an unreadable iCloud placeholder in this tree).
- Codex must verify compilation of: `prepare(_ incomingRequest:progress:)` with `let request = incomingRequest.displayingShownLanguage()`;
  the labeled-tuple `canvasLanguageStatusCache`; the `Toggle` with `Binding(get:set:)` in `CanvasLanguageBar`;
  the defaulted `localeID:` parameter of `BrowserPreviewController.build`; the `if A || B, case .string(let raw) = …`
  condition in `ComponentDefinitionGraphCopy.remap`; and the new tests.
