# ADR-0085 — Site languages: showing a language on the canvas and in Local Preview (part 4c, first half)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-038 (approved by the owner 2026-11-26 1:30 PM EST)
- Builds on: ADR-0080 (language model), ADR-0081 (per-node translations), ADR-0082 (per-language export),
  ADR-0083 (Languages sheet), ADR-0084 (Inspector Translations section)
- Requirements: SF-1007-002 (preview clearly distinguished from committed state; missing translations
  visible), -003 (resolution explained), -004 (failure and recovery), -006 (accessibility), -008
  (diagnostics/tests); SF-1506-003 (resolution rules)

## Context

Authors could translate an element in the Inspector (ADR-0084) and export one tree per language
(ADR-0082), but the canvas and Local Preview only ever showed the default language, so a translation could
only be seen by exporting. Part 4c of OD-038 shows a chosen language on the canvas and in Preview.

## Decision

- **View state, not a document change.** `WorkspaceShellState.canvasLanguageLocaleID` is published view
  state: never saved, never in the document, never an undoable edit, and reset (with
  `canvasRenderPlanLocaleID`) when another document opens. `nil` and the default language both show the
  document itself. A language the site no longer has shows the default again; if Undo brings the language
  back, the canvas shows it again.
- **Exactly what export writes.** `SiteCanvasLanguage.displayedDocument` (`DocumentModel.swift`) returns
  `SiteLanguageOutput.translatedDocument` (ADR-0082) for the shown language, so the canvas, Local Preview and
  export cannot disagree: the language's own translation, else a fallback language's, else the default
  value; translated images; translation properties removed. Identities and the revision are unchanged, so
  the existing render identity and adoption gates apply unchanged.
- **Canvas.** `scheduleScenePreparation` renders the displayed document (on top of a design-style preview
  if one is open). The language is captured with the request; a plan prepared for the language shown
  before is dropped as `CanvasRendererError.staleResult`, and the adopted plan records its language.
- **Local Preview.** Open and Refresh wait until the adopted plan is of the shown language, record the
  language they captured (`previewLocaleID`, shown as a globe label in the Preview toolbar), and compile
  the other pages from the displayed document. Refresh is not "already current" after a language change.
  The Preview stays a snapshot (unchanged rule): changing the canvas language later needs Refresh.
- **Editing.** Inline text editing on the canvas is refused while another language is shown, because the
  canvas shows a translation and not the text that editor changes; the refusal names the recovery
  (Inspector Translations section, or show the default language). Choosing a language commits an open
  inline edit first (refused with "busy" if it cannot), and cancels an open transform or guide edit. The
  Inspector's Translations section follows the shown language. Inspector translation edits and Undo/Redo
  appear on the canvas immediately because the displayed document is derived from each revision.
- **UI.** A slim "Canvas Language" bar above the viewport controls when the site has more than one
  language and the `localization.site-languages` flag is on (or a language is shown, so the author can
  always switch back): a picker (default marked), Show Default Language, and a status that names the
  language, counts its values not translated yet, says when it reads right to left, and repeats the
  text-editing rule. The flag summary mentions the canvas and Local Preview.
- **Diagnostics.** Every choice records a `SiteCanvasLanguageDiagnostic` (requirement SF-1007-003,
  operation `show`, language identity, duration, failure category `none`/`unknown-locale`/`busy`; never a
  name, code or value). Status text names the language and is shown and announced only.
- No schema change: document schema 27, persisted-history schema 4, website metadata version 3; no new
  `CanonicalDocument` or node key; no new command.

## Consequences

- Still not built (part 4c, second half): right-to-left layout on the canvas. The canvas renders a
  right-to-left language with the default layout (text runs still use their natural direction); the
  status says so. Export already writes `dir="rtl"`.
- Not built: Website Preview opening at the shown language's address, the responsive comparison view in
  another language, and a menu command for the canvas language (the picker is keyboard reachable).
- Frames of flowing text on the canvas follow the shown language's text length; geometry edits made while
  another language is shown still change the shared layout. Codex should confirm transforms started from
  such frames behave like the default language.
- Codex must verify compilation of `CanvasLanguageBar` (`Picker` with `SiteLocaleID?` tags,
  `Binding(get:set:)` with `_ =`), that the new `features` property keeps
  `CanvasPlaceholderView(state:focus:tabRouter:compact:)` callable, the `guard … else { throw
  CanvasRendererError.staleResult }` inside the adoption `do`, and the new test.
