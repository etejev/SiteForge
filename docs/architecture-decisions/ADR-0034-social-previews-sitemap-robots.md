# ADR-0034 — Site address, social previews, sitemap and robots

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Requirements: SF-1207-001 … SF-1207-008

## Context

Website metadata (title pattern, descriptions, favicon, indexing) existed, with
a search snippet preview. Shared links had no Open Graph or Twitter tags, there
was no sitemap or robots file, and the canonical link was the bare route.

## Decision

- `WebsiteMetadata` version 2 adds `siteURL` (https, host, no credentials,
  port 443 only, no query, fragment or trailing slash, at most 512 bytes) and
  `socialImageAssetID`. A version 1 record still decodes with exactly its own
  key set and is read as version 2 with both fields absent; any other key set
  or version is refused. Using the fields needs document schema 27.
- Export: every page gets `og:type`, `og:site_name`, `og:title`,
  `og:description` (when known) and `twitter:card`. With a site address the
  canonical link and `og:url` are absolute and, with a social image,
  `og:image` is the absolute URL of its content-addressed exported file and
  the card is `summary_large_image`. `robots.txt` is always written (Allow or
  Disallow by the site's indexing preference, plus the sitemap when known);
  `sitemap.xml` is written when the address is known and lists indexable,
  non-Not-Found pages.
- The social image is an asset use (Uses, retarget, delete guard, delete with
  uses, export).
- `StaticSEOAudit` warnings (not blocking): missing description, title over 60
  or description over 160 characters, duplicate titles, social image without
  address. They carry no authored text.
- Browser Preview serves `.txt` and `.xml` with text content types.

## Consequences

- Every export now contains `robots.txt`.
- Per-page social images are not included (site-wide only).
- With a site address, every page except Not Found also carries schema.org JSON-LD
  (`WebPage`, and `WebSite` on each language tree's home page) built from the same
  typed metadata (OD-144, ADR-0144).

## Reversal

Stop emitting the new tags and files; keep reading version 2 records.
