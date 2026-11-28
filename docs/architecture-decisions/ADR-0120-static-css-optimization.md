# ADR-0120 — Static Release CSS optimization and size report (SF-1204)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-042 (approved by the owner 2026-11-26 1:30 PM EST: static export only); lane H item H1
- Requirements: SF-1204-003 (deterministic rules, provenance), -004 (fail closed, last valid output kept),
  -007 (linear work per stylesheet), -008 (diagnostics and tests)

## Context

`LocalBuildProfileCompiler` (Static Release) "optimized" CSS by trimming every line and dropping any line
that had appeared before anywhere in the file. That is not safe: generated blocks that span lines (the dark
mode `@media (prefers-color-scheme:dark) {` … `}` block, effect and motion blocks) end with a line that is
only `}`; the second such line was dropped, which produced an unbalanced stylesheet, and a repeated rule
inside a condition block could be removed even though it was not a duplicate in its context. There was no
size report and no way to see which generated rules target an object.

## Decision

- New `StaticCSSOptimizer` (`SiteForge/CanvasRendererCore.swift`, section "SF-1204 CSS generation and
  optimization"). It parses SiteForge's own generated CSS into statements (rules, `@media`, `@supports`,
  `@container`, `@layer`, `@keyframes`, `@font-face` and other declaration at-rules, block-less
  `@import`/`@charset`/`@namespace`/`@layer`) with quote, escape, comment, bracket and parenthesis awareness.
- It never reorders statements, so the cascade order the emitters produce (and that the canvas mirrors)
  is unchanged. Ordering stays the emitters' deterministic order.
- It minifies: comments dropped; selector whitespace collapsed (a remaining space is a descendant
  combinator) and removed around `,` `>` `+` `~` outside brackets/parentheses; declaration values
  collapsed with no space after `(`/`,` or before `)`/`,`; at-rule preludes collapsed only; quoted text kept
  exactly; custom property values kept exactly (trimmed) because scripts may read them; statements joined
  with no separator.
- It removes only what cannot change the computed result:
  - an earlier exact copy of a later declaration in the same block;
  - an earlier exact copy of a later sibling statement (same parent, so the same conditions; the later
    copy has the same selectors, declarations and a later position). `@layer` and block-less at-rules are
    never removed (their first position matters);
  - empty rules and empty `@media`/`@supports`/`@container` blocks (empty `@keyframes`, `@font-face` and
    `@layer` are kept);
  - unused rules: a rule whose every comma-separated selector contains an object identifier (UUID text)
    that appears in no `.html` or `.js` file of the build. Selectors with `(` (for example `:not(…)`, which
    would match more, not less) or substring attribute operators are never removed. Class and attribute
    matching is case-sensitive, so the exact-case check matches browser behavior.
- Fail closed (SF-1204-004): unknown at-rules, nested rules, unbalanced braces/brackets/quotes and
  malformed declarations leave the stylesheet unchanged; the report says why and `StaticBuildCompiler`
  adds a warning `css-optimization-skipped` (SF-1204-004, output path, no content). Custom code CSS is in
  each page's `<style data-siteforge-custom-code>` and is never optimized.
- Profiles: Development writes stylesheets exactly as generated (readable; byte-identical to before).
  Static Release writes the optimized text; every non-CSS file is unchanged.
- Size report (SF-1204-003/008): `LocalBuildReport.cssReports` holds one `StaticCSSOptimizationReport` per
  stylesheet (path, original and output bytes, counts per removal kind, skip reason; never selectors or
  values). Check Website shows it in a "Stylesheet size" box (`build.cssSize`).
- Provenance: `StaticCSSOptimizer.trace(_:nodeID:)` lists the generated rules that name an object in
  source order with their enclosing conditions.

## Consequences

- Static Release `styles.css` bytes change (one line, smaller); the old dropped-brace defect is gone.
  Development output, HTML, scripts, assets and every manifest are unchanged.
- Two existing tests that looked for exact generated lines in Static Release CSS now look for the
  minified form of those lines (`StaticCSSOptimizer.minify`).
- Not built here: an authored CSS-rule model, CSS source maps, a provenance UI in the Inspector, vendor
  prefixing (SiteForge emits no prefixed properties) and merging of different rules with the same
  selector (it could change the cascade). The comment in `EventGraphOutput.overlayCSS` that release
  de-duplication is line based is now out of date.

## Update — 2026-11-26 (lane V12b, ADR-0124)

Static Release also replaces the per-runtime script files with one content-hashed runtime file and changes the
runtime tags of the pages that use one; every other non-CSS file is still unchanged.

## Verification

`SiteForgeTests/CanvasRendererTests/testStaticReleaseCSSOptimizerMinifiesDeduplicatesAndKeepsBlocksWhole`
(exact output, counts, idempotence, the dropped-brace regression, six fail-closed inputs, trace, both
profiles through `LocalBuildProfileCompiler`). Not compiled or run by Code Forge.
