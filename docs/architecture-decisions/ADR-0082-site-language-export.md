# ADR-0082 — Site languages: per-language export (part 3)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-038 (approved by the owner 2026-11-26 1:30 PM EST)
- Builds on: ADR-0080 (language model), ADR-0081 (per-node translations)
- Requirements: SF-1007-002 (missing translations visible before export), -003 (resolution in output),
  -005 (hreflang / alternates), -008 (tests); SF-1506-003 (authored-site language and direction in output)

## Context

OD-038 says export writes one tree per language with hreflang. ADR-0080 added the languages and their
address prefixes, ADR-0081 the translations and the missing-translation report. This part makes the
static build (Check Website, Export, Preview, all through `MultiPageStaticBuildPlanner.plan` and
`StaticBuildCompiler.compile`) write every language.

## Decision

- `SiteLanguageOutput.passes(document)` (`SiteForge/CanvasRendererCore.swift`) returns one
  `SiteLanguageOutputPass` per language: the default language first, then the others in authored order.
  A site without languages gets one pass (`lang="en"`, no `dir`, no prefix) and its output is unchanged
  byte for byte.
- The default language is written at the site root exactly as before (its values are the nodes' own).
  Every other language is written under `<route segment>/` (`fr/index.html`, `fr/post.html`,
  `fr/404.html`). Its pages come from an output-only copy of the document
  (`SiteLanguageOutput.translatedDocument`): each translatable value becomes the language's own
  translation or a fallback language's (`SiteTranslationResolver`); values with neither keep the default
  language's; translation properties are removed. The copy is translated before component resolution, so
  definition translations reach instances; instance text overrides stay untranslated (ADR-0081). The copy
  is never committed or validated again; the original document is validated once as before.
- Shared files (`styles.css`, runtimes, `robots.txt`, manifests, semantic outline) are written once and come
  from the default language's pages; class names are node-identity based, so every tree uses the same
  stylesheet. Collisions between trees fail closed through the existing `paths` check (for example a
  collection with slug `fr` while French exists).
- Inside a language tree, links are relative to the page (`SiteLanguageOutput.relativeRoutes`), generated
  navigation already was, scripts and the stylesheet use the existing `../` prefix, and generated image
  sources (`src="assets/…"`) get the same prefix. Authored text and attributes are escaped, so only
  generated sources match that rewrite.
- `<html>` carries `lang` (the language's code) and `dir` (`ltr`/`rtl`, authored or implied by the code)
  for localized sites. The canonical link, Open Graph URL and sitemap use the language's address
  (`/fr/post`, `/fr/` for the home page because it is `fr/index.html`; this deliberately differs from
  `SiteLocaleResolver.route`'s `/fr`).
- Every page except Not Found lists `<link rel="alternate" hreflang>` for every language plus
  `x-default` (the default language). With a site address the links are absolute; without one they are the
  address alone, like the canonical link, and the build warns `language-alternates-need-site-url`.
- `sitemap.xml` lists every language's indexable pages.
- `StaticBuildCompiler` writes images that only a translation of a current language shows
  (`SiteLanguageOutput.translatedAssetIDs`) and adds findings from `SiteLanguageOutput.findings`:
  `translation-missing` (warning, SF-1007-002, one per language with its address prefix and count),
  `translation-orphaned` (information, SF-1007-004), `language-alternates-need-site-url` (warning,
  SF-1007-005). Findings carry counts and addresses only, never text.
- No schema change: document schema 27, persisted-history schema 4, website metadata version 3.

## Consequences

- Not built yet (part 4): the Languages editor, a translation field in the Inspector and the RTL preview.
  Page names in the generated navigation and website metadata (titles, descriptions) are not translatable.
- Existing behaviour noted, not changed: default-language pages at nested routes (for example collection
  item pages under `/posts/`) still write root-relative image sources and control links.
- Codex must verify compilation, the new test, that every existing export test is unchanged for sites
  without languages, and the ` src="assets/` rewrite against `SafeHTMLEmitter` output.
