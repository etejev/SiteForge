# ADR-0084 — Site languages: the Inspector's Translations section (part 4b)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-038 (approved by the owner 2026-11-26 1:30 PM EST)
- Builds on: ADR-0080 (language model), ADR-0081 (per-node translations), ADR-0082 (per-language export),
  ADR-0083 (Languages sheet)
- Requirements: SF-1007-002 (translate content without a context switch; missing translations visible),
  -003 (resolution explained), -004 (failure and recovery), -005 (undo/redo), -006 (accessibility),
  -008 (diagnostics/tests); SF-1506-001 (authored-site languages)

## Context

ADR-0081 added `SiteTranslationEditing.prepare` (one validated, undoable grouped edit per translation),
`SiteTranslationResolver` (with a plain-language `explanation`) and the project-wide
`SiteTranslationReport`. ADR-0083 added File > Languages…. Nothing in the app could enter a translation:
only tests and automation called `prepare`. Part 4b of OD-038 adds the translation field in the Inspector.

## Decision

- **Where.** A "Translations" group at the end of the Inspector's Content tab, shown when the
  `localization.site-languages` flag (ADR-0083) is on, the site has a language besides the default, and
  exactly one element of a translatable kind (text, link controls, images) on a website page is selected.
  It is hidden while a component definition or variant is open, because those edits are converted before
  they commit. The flag summary now mentions the section; the document format is unchanged.
- **Read side** (`SiteTranslationInspection`, `DocumentModel.swift`, pure): `target(selectedNodeIDs:pageID:in:)`,
  `translatableLocales(_:)` (every language but the default, in author order), `locale(preferred:in:)`,
  `isRightToLeft(_:in:)`, `rows(for:localeID:in:)` (one `SiteTranslationInspectorRow` per field: the
  resolution with its explanation, the language's own translation, whether it is required) and
  `missingTranslations(on:pageID:in:)`, which lists exactly the gaps `SiteTranslationReport.build` lists
  for that element, in the same order, while reading only that element. `missingSummary` names languages
  and is shown to the author only, never written to diagnostics.
- **State** (`WorkspaceShellState`): `translationInspectorLocaleID` (kept across selections; a language that
  is gone falls back to the first translatable one through `translationInspectorEffectiveLocaleID`),
  `translationInspectorStatus`, `lastTranslationInspectorDiagnostic`, `canEditTranslations` (same rule as
  `canEditLanguages`), `translationInspectorTarget`, and `commitTranslation(_:field:nodeID:pageID:localeID:openingRevision:)`.
  It reads and edits `documentSession.document`, not `authoringDocument`.
- **One edit each.** Apply (or Return) saves the draft through `SiteTranslationEditing.prepare` and executes
  the one command it returns; Use Fallback removes the translation; the image picker ("Same as fallback"
  plus the project's images) commits on change. Undo/Redo restore exactly. An unchanged value is reported
  and is not an error; stale, default-language, unknown, unsupported and invalid edits are refused with the
  existing `SiteTranslationEditError` messages and change nothing. Escape discards a draft. The section is
  rebuilt (drafts dropped) whenever the document revision changes, so an edit is never applied to a newer
  project than the one it was typed against.
- **Explained values.** Each field shows `SiteTranslationResolution.explanation` (translated, fallback,
  default value, missing), with missing required values in the danger colour, and uses the shown value as
  the field's placeholder. Under the fields, the element's missing translations are listed per language;
  choosing one switches the section to that language.
- **Right to left.** The translation field of a right-to-left language (authored or implied by its code)
  uses a right-to-left layout direction, so Arabic or Hebrew is typed in its own direction.
- **Accessibility.** Labels name the field and language, hints carry the explanation, status changes are
  announced through `announcementPoster`, and every control has an identifier (see the activity log).
- **Diagnostics.** Every commit records a `SiteTranslationEditDiagnostic` (`set`/`clear`, node, language
  and field identities, duration, failure category; never the value, name or code).
- No schema change: document schema 27, persisted-history schema 4, website metadata version 3; no new
  `CanonicalDocument` or node key; no new command.

## Consequences

- Still not built (part 4c): showing a language other than the default on the canvas and in Preview
  (including right-to-left canvas layout), and a translation entry point for component definition text.
  Translations are entered per element; there is no side-by-side bulk translation table yet.
- Codex must verify compilation of `SiteTranslationInspectorView` (the `TextField(_:text:axis:)` overload
  with a `String` placeholder, `Picker` with `String?` tags, `.onExitCommand`, `ForEach(rows, id: \.field)`),
  that adding `@ObservedObject var features: FeatureFlagStore = .shared` keeps `InspectorView(state:focus:)`
  callable, that the extra `if let` in `inspectorContents` stays within the type-checker limit, and the new test.
