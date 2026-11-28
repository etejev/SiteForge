# ADR-0080 — Site languages: the localization model (part 1)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-038 (approved by the owner 2026-11-26 1:30 PM EST)
- Requirements: SF-1007-001, -003, -004, -005, -008 (model part); SF-1506-001, -003 (localized-string
  state and resolution for authored sites only; the app UI stays English-only per OD-038)

## Context

OD-038 chooses per-project languages with a default, translatable text and media stored per language on
the node, per-language routes (`/fr/…`) and an export that writes one tree per language with hreflang.
This is a large item, so lane E builds it in parts. Part 1 (this ADR) is the authoritative language
model only. Later parts: per-node translations and the missing-translation report; per-language export
and hreflang; the Languages editor UI and RTL preview.

## Decision

- Model (`SiteForge/DocumentModel.swift`): `SiteLocalization` (`version` 1, `defaultLocaleID`, ordered
  `locales`) and `SiteLocale` (`id`, canonical BCP 47 `code`, `name`, optional `direction`, optional
  `fallbackLocaleID`). New stable identifier domain `site-locale`. Exact keys; the optional keys are
  omitted when defaulted and null is refused, so the file tells apart omitted (no localization key),
  defaulted (no `direction` / `fallbackLocaleID`) and authored values, even when an authored direction
  equals the implied one.
- `CanonicalDocument.localization` is optional and written only when the site is localized. Still
  document schema 27 (unreleased); a schema 26 file with languages is refused. Website metadata
  unchanged (still version 3).
- Codes (`SiteLocaleCode`): language (2–3 letters), optional script (4 letters, title case), optional
  region (2 letters upper case or 3 digits), variants (5–8 alphanumerics or digit + 3); at most 35 bytes;
  ASCII only. Input is canonicalized (`fr_ca` → `fr-CA`); stored codes must already be canonical.
  Extension and private-use subtags are not supported.
- Rules (`CanonicalLocalization.issues`, enforced by `CanonicalDocument.validate` as
  `ModelValidationError.invalidLocalization`): 1–50 languages; the default exists; unique ids; codes
  unique case-insensitively; non-blank trimmed names (128 bytes) unique case-insensitively; the default
  has no fallback; no fallback to itself, to an unknown language, or around a loop. Critical invariant:
  a non-default language's address segment (`/` + lowercased code) may not equal or prefix any website
  page route, so adding a page at `/fr/notes` while French exists, or adding French while that page
  exists, is refused. Issues name the language and page by id; messages hold no names or codes.
- Resolution (`SiteLocaleResolver`, SF-1007-003): direction = authored value, else implied by the code
  (a script subtag wins: `az-Arab` RTL, `ar-Latn` LTR); fallback chain = authored fallbacks, then the
  default (an unknown fallback continues at the default, so resolution is total); address prefix = empty
  for the default, `/<code>` otherwise (`/` → `/fr`, `/about` → `/fr/about`). `SiteLocaleResolution`
  carries the sources and a plain-language `explanation`. `firstAvailable(_:in:where:)` is the hook the
  translation part will use to pick the first language with a value.
- Editing: one `DocumentCommand.setLocalization` (`document.localization.set`, "Edit Languages")
  replaces the whole record (`nil` = localization off); its inverse restores the previous record.
  Persisted history stays schema 4 and checks the payload keys. `SiteLocalizationEditing` has pure draft
  operations (`start`, `addLocale`, `removeLocale` — languages that fell back to it fall back to the
  default again —, `makeDefault`, `suggestedName`) and `prepare`, which refuses busy, stale, exhausted,
  unchanged and invalid drafts without touching the document.
- Snapshots: restore appends `setLocalization` when languages differ; comparison reports a "Languages"
  settings change. Packaged templates copy the record.
- Diagnostics: `SiteLocalizationEditDiagnostic` holds the requirement id, operation, locale ids, count,
  duration and failure category only.

## Consequences

- No UI, export or per-node translation storage yet; the safe assumption for those parts still holds.
  A site without languages is byte-for-byte unchanged.
- Translations will be stored on nodes keyed by `SiteLocaleID`, so renaming or recoding a language never
  rewrites them; removing a language must later report how many translations it drops before commit.
- Codex must verify compilation, the two new tests and that no hand-built document or command fixture
  elsewhere depends on the closed key set.
