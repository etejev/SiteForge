# ADR-0081 — Site languages: per-node translations and the missing-translation report (part 2)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-038 (approved by the owner 2026-11-26 1:30 PM EST)
- Builds on: ADR-0080 (language model)
- Requirements: SF-1007-001, -002, -003, -004, -005, -008 (translation storage, edits, resolution, report);
  SF-1506-001 (localized-string state for authored sites only; the app UI stays English-only per OD-038)

## Context

OD-038 stores translatable text and media per language on the node. ADR-0080 added the languages;
this part adds the translations themselves, how a value is chosen for a language, and the report that
makes missing translations visible before publish. Export (part 3) and the Languages editor (part 4)
are still to come.

## Decision

- Storage (`SiteForge/DocumentModel.swift`): the node's own property stays the default language's
  value (`content.text` for Text, `content.control.v1.label` for Button/Link, `content.image.v1.assetID`
  and `content.image.v1.alt` for Image). Every other language stores one authored string property
  `locale.translation.v1.<language id>.<field>` on the same node, field `text`, `image.assetID` or
  `image.alt` (`SiteTranslationField`, `SiteTranslationKey`). Keys use the language's stable identity in
  canonical lowercase form, so renaming or recoding a language never rewrites translations. No new
  `CanonicalDocument` or `DocumentNode` key: still document schema 27, persisted-history schema 4 and
  website metadata version 3. A site without translations is byte-for-byte unchanged.
- Rules (`CanonicalTranslations`, new `ModelValidationError.invalidTranslation`): keys must parse; the
  field must apply to the node kind; values are authored strings; text at most 64 KiB and alternative
  text at most 4 KiB without control characters other than newline and tab; a translated image must be
  an existing asset; at most 150 translations per node; no translation for the default language.
  Translations of a language the site no longer has (for example after a paste from another project)
  stay openable as orphans: reported, never shown, and dropped by the next language edit.
- Resolution (`SiteTranslationResolver`, SF-1007-003): the language's own translation, else the first
  fallback language with one (`SiteLocaleResolver.firstAvailable`), else the node's own value.
  `SiteTranslationResolution` names the source (`translation`, `fallback`, `defaultValue`, `missing`),
  the language whose value is shown and a plain-language explanation without values.
- Report (`SiteTranslationReport.build`): for every non-default language, text and the alternative text
  of non-decorative images without a translation are listed as `missing` with the language shown instead;
  translated images are optional. Orphans are listed separately. Pages in document order, nodes in tree
  order, languages in authored order. The summary holds counts only.
- Editing (`SiteTranslationEditing.prepare`): sets or clears one translation as a grouped edit
  (`.batch([setProperty | removeProperty])`) so the whole document is validated before it is offered;
  refuses busy, stale, exhausted, not localized, unknown language, default language, unknown element,
  unsupported field, unchanged and invalid values without touching the document.
- Language changes (`SiteLocalizationEditing.prepare`): when translations are affected the result is one
  grouped edit `translation edits + setLocalization`. Translations of removed languages (or all of them
  when languages are turned off) are removed; `droppedTranslationCount(to:in:)` reports the number before
  commit. When the default moves to another existing language, that language's translation becomes the
  node's own value and the old default's value becomes its translation, so no text is lost; Undo restores
  both. Without affected translations the result is still the single `setLocalization` command.
- Assets: a translated image keeps its asset in use (`ImageAssetDependencies.unusedAssetIDs`), deleting
  it is refused with a specific reason, and Replace Everywhere also retargets translated images.
- Diagnostics: `SiteTranslationEditDiagnostic` holds the requirement id, operation, node and language
  identities, field, duration and failure category only.

## Consequences

- Not built yet: per-language export, `hreflang`, `lang`/`dir` (part 3); the Languages editor, a
  translation surface in the Inspector and the RTL preview (part 4). Component instance text overrides
  (`component.instance.v1.text.*`) and collection item values are not translatable in this part.
- Variant pages stored inside component definitions are validated by the node rules but not by the
  default-language rule.
- Codex must verify compilation, the two new tests, that the batch path of `SiteLocalizationEditing.prepare`
  keeps the E02 tests unchanged, and that no fixture elsewhere uses the `locale.translation.v1.` prefix.
