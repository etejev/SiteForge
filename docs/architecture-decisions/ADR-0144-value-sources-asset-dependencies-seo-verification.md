# ADR-0144 — Value sources, asset dependencies and SEO audit: verification completions

- Status: Proposed (lane V05 verification of batches 12–14; unverified until Codex builds and runs the tests)
- Date: 2026-11-26
- Owners: Product / Engineering
- Requirements: SF-0704-002/003/006/008, SF-0807-002/004/006/007/008, SF-1207-003/004, SF-0605-003
- Amends: ADR-0034 (social previews, sitemap, robots). Batches 12 and 13 had no ADR; the
  `ImageAssetDependencies` comment pointed at a non-existent ADR-0033 and now points here.

## Context

Lane V05 re-read batches 12 (value sources, SF-0704), 13 (asset dependencies, SF-0807)
and 14 (social previews, sitemap, robots, SEO warnings, SF-1207) against the real
declarations. These behaviors did not match the module invariants:

1. SF-0704 ("the trace matches the engine's actual resolution order; stale provenance is
   impossible"): a width, height or position placed by layout (Fill, Hug, a Stack or Grid)
   was traced as its stored Desktop or breakpoint number, which the canvas does not draw.
2. Batch 12 refused a container-query rule for text size or line height on text with a
   fluid value, but a fluid value could still be added under an existing rule for the same
   setting (canvas: fluid wins; CSS: the rule wins). The same held for width and height.
3. The value-source rows were DisclosureGroup labels: on macOS the label does not toggle the
   group, it is not reachable with the keyboard, and its accessibility value sat on the group
   instead of the identified element (the UI journey clicks and reads that element).
4. Use Another Asset Instead left collection item images (OD-035) on the old asset, so the
   "now unused" asset stayed in use; the unused set was computed with one project scan per
   asset, on the main actor, in every Assets render and in every export; the Assets "Unused"
   filter disagreed with Remove Unused (it ignored collection items and translations).
5. Reveal for a social-image use reported "This use no longer exists" (Reveal Usage of a
   social-image-only asset did nothing).
6. SEO warnings checked the collection template page (never written) instead of the item
   pages a build writes, so duplicate or missing titles of dynamic routes were not reported.
7. SF-0704-008 / SF-0807-008 diagnostics carried no requirement IDs.

## Decision

- `ValueTraceStep.Source.layout(String)`: when layout places a geometry value at the canvas
  breakpoint and width, the trace ends with a "Computed by …" step read from the same adopted
  frame the Geometry fields show. It cannot be cleared ("Layout places this value. Change the
  object's sizing or its Stack or Grid instead."). While that frame is being prepared the
  setting has no trace rather than a stale one.
- `FluidValueCommandError.containerQueryConflict`: a fluid value is refused for a setting that
  a container-query rule on the same object sets (both directions are now refused).
- Each value-source row is a plain button inside the DisclosureGroup label: click, Space or
  Return opens the steps; it carries the label "<Setting> source", the value
  "<value>, from <source>, <n> sources", a hint, and the identifier
  `inspector.valueTrace.<setting>`.
- `ImageAssetDependencies.holdsAssetUse(_:)` names the node properties that hold a use
  (exactly the ones `retarget` moves). `usedAssetIDs(in:)` is one pass over the project
  (those properties, favicon, social image, collection items); `unusedAssetIDs` uses it, and
  so does the Assets usage filter. `retarget` also rewrites collection item image values in
  the same transaction (`setCollections`). The shell caches each asset's references per
  authoring document (identity, revision, open definition and variant).
- The favicon and social image uses both reveal Website Settings.
- `StaticSEOAudit` checks `CollectionTemplates.outputPages` (item pages resolved with their
  item's title, as export does; a list's later pages skipped; the template page not checked).
- `CommandDiagnostics.recordValueSourceOperation` and `recordAssetDependencyOperation` record
  requirement IDs, stable identities (sanitized), duration and result only.

No schema change: document schema 27, persisted-history schema 4, WebsiteMetadata version 3.

## Consequences

- A fluid value can no longer be added to a setting a container-query rule sets; remove that
  setting from the rule first (the refusal says so).
- Remove Unused, the Unused filter and export's "assets-unused" information agree.

## Open question (OD-144) — approved 2026-11-26 8:06 PM EST, built by lane V16

SF-1207's scope lists structured data ("invalid structured data is reported before publish").
SiteForge emitted none. Recommended default (approved by the owner): generate
schema.org `WebSite` and `WebPage` JSON-LD only from typed metadata (site name, page title,
description, absolute URL), only when the site address is set, with no authored JSON.
Alternative (not chosen): defer structured data. See "Implemented (lane V16)" below.

## Implemented (lane V16)

Unverified until Codex builds and runs the tests (no Swift toolchain on the lane V PC).

- `StaticSEOEmitter.structuredData(_:route:siteRoot:isHome:siteURL:)` (CanvasRendererCore.swift)
  writes one `<script type="application/ld+json">` per page, right after the search and
  social tags in the head, from the same `StaticSEOMetadata` the head uses (resolved title,
  description, site name, the tree's language) and the absolute address. Nothing authored is
  copied as JSON; no document key is added (document schema 27, WebsiteMetadata version 3).
- Shape (keys in this fixed order, so the bytes are deterministic):
  `{"@context":"https://schema.org","@graph":[…]}`. Every page has a `WebPage` with `@id`
  (`<address>#webpage`), `url`, `name`, `description` (when there is one), `inLanguage` and
  `isPartOf` → the `@id` of its language tree's `WebSite` (`<site address><tree root>#website`).
  The home page of each tree (`/`, `/fr/`; not a list's later pages) also carries the `WebSite`
  (`@id`, `url`, `name`, `inLanguage`) first. `WebPage` is used for every page, including
  collection item pages; the approved default names no other type (no `Article`).
- Written only when the site address is set; nothing is written without one, and the Not Found
  page never gets a block. Every language tree is covered (localized address and language), and
  so is every collection item page (the item's resolved title and address; the template page is
  never written). A list's later pages are web pages at their own addresses.
- Escaping: `StaticSEOEmitter.jsonEscape` writes JSON string escapes and turns `<`, `>`, `&`,
  U+2028 and U+2029 (and other control characters) into `\uXXXX`, so authored text can never
  close the script element (`</script`) or open a comment; the result is valid JSON.
- Static Release minifies stylesheets and, in pages, only swaps the exact generated runtime
  tags (`<script src="…siteforge-….js" defer></script>`) for the bundle tag
  (`StaticRuntimeBundle.page`); the block (whose `<` are escaped) can never match those, so
  it is written unchanged. The integrity
  manifest (`siteforge-integrity.json`) and the Output files report hash each page with its
  block, like any other byte of the page. The CSS optimizer's used-identifier scan can only
  keep more rules because of it, never fewer.
- Check Website: no new finding. The approved default does not call for one when the address is
  missing (the existing `seo-social-image-needs-site-url` and `language-alternates-need-site-url`
  warnings already ask for it where it matters), and a block cannot be invalid when it is
  written: it uses only metadata that the head has already validated (a page whose site name,
  title or route is unusable fails the build before this point).
- Tests: `CanvasRendererTests/testStructuredDataDescribesEachPageOnlyWithASiteAddress`,
  `CanvasRendererTests/testStructuredDataEscapesTextSoItCannotCloseItsScript`,
  `CanvasRendererTests/testStructuredDataFollowsEveryLanguageTreeAndCollectionItemPages`.

## Reversal

Remove the layout step and the conflict refusal; restore per-asset scans. No data migrates.
For OD-144, remove `structuredData`/`jsonEscape` and the block in the page head; no data migrates.
