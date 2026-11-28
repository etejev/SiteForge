# ADR-0083 — Site languages: the Languages sheet (part 4a)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-038 (approved by the owner 2026-11-26 1:30 PM EST)
- Builds on: ADR-0080 (language model), ADR-0081 (per-node translations), ADR-0082 (per-language export)
- Requirements: SF-1007-002 (create/modify, missing translations visible), -004 (failure and recovery),
  -006 (accessibility), -008 (diagnostics/tests); SF-1506-001 (authored-site languages)

## Context

ADR-0080 added `SiteLocalizationEditing` (pure draft operations plus `prepare`), ADR-0081 the
translations, the missing-translation report and `SiteTranslationEditing.droppedTranslationCount`, and
ADR-0082 the per-language export. Nothing in the app could turn languages on. Part 4 of OD-038 is the
editing UI; it is split: this part is the Languages sheet; the Inspector translation field and the
right-to-left preview follow (part 4b).

## Decision

- **Menu and flag.** File > Languages… (beside Collections…) opens the sheet. It is shown only while the
  new feature flag `localization.site-languages` (`FeatureFlagID.siteLanguages`, default on, remove by
  2027-03-31, requirements SF-1007 and SF-1506) is on. The flag gates the menu only; the document format
  is unchanged.
- **State** (`WorkspaceShellState`, `WorkspaceShellModel.swift`): `isLanguagesEditorPresented`,
  `languagesOpeningRevision`, `languagesStatus`, `lastLanguagesDiagnostic`, `canEditLanguages`,
  `presentLanguagesEditor()`, `languagesDroppedTranslationCount(_:)`, `languagesTranslationReport`,
  `commitLanguages(_:)`. Like Collections, the opening revision is recorded when the sheet opens and Apply
  is refused as stale if the project changed since.
- **One transaction.** Apply calls `SiteLocalizationEditing.prepare` with the whole draft and executes the
  one command it returns (`setLocalization`, or a grouped edit when translations are dropped or swapped).
  Undo restores languages and translations together. Unchanged drafts report "Languages are unchanged."
  and are not an error; invalid drafts are refused with the first rule's message and change nothing.
- **Project, not variant.** The sheet edits `documentSession.document`, not `authoringDocument`.
  `canEditLanguages` is false while a component variant is open, because the session converts edits for
  the open variant before they commit; the menu item is disabled and `presentLanguagesEditor` explains why.
- **Removal is said before it happens.** The sheet shows how many translations Apply removes (removed
  languages, orphans, or every translation when languages are turned off) in the footer, and Apply asks
  for confirmation when the count is above zero. Making another language the default swaps values and
  removes nothing (ADR-0081).
- **Sheet** (`SiteLanguagesEditorView`, `WorkspaceShellView.swift`): with no languages, one field takes
  the code of the language the site is written in now ("Turn On Languages"). With languages, each row
  edits the name, shows the code and address (`/fr/`, default at the site root), a direction picker
  ("Automatic (…)" is the direction the code implies) and, except for the default, a fallback picker,
  Make Default and Remove. Rule failures show under their row and in the footer, live. Turn Off
  Languages sets the draft to no languages. The missing-translation summary
  (`SiteTranslationReport.summary`) and per-language missing counts are read once when the sheet opens.
- **Diagnostics.** Every Apply records a `SiteLocalizationEditDiagnostic` (identities and counts only,
  never names or codes) with the failure category.
- No schema change: document schema 27, persisted-history schema 4, website metadata version 3; no new
  `CanonicalDocument` or node key.

## Consequences

- Still not built (part 4b): a translation field in the Inspector (`SiteTranslationEditing.prepare`), a
  right-to-left canvas/preview, and a per-element list of missing translations. Codes cannot be edited in
  place; remove the language and add it again (its translations are then dropped, and the sheet says so).
- Codex must verify compilation of the sheet (generic `localeBinding`, `change { … &$0 }` closures,
  optional `Picker` tags), the new test, that `features` is in scope where the menu item was added, and
  that the extra `.sheet` modifier does not push the workspace body over the type-checker limit.
