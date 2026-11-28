# ADR-0050 — SVG import as a sanitized image asset

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-045 (approved by the owner 2026-11-26 1:30 PM EST)
- Requirements: SF-0804-001 … SF-0804-008

## Context

OD-045 imports SVG as a sanitized asset (scripts, external references and
event attributes removed) that is rendered as an image, not as editable
vectors.

## Decision

- `ImageAssetFormat.svg` (`image/svg+xml`). An SVG is an ordinary
  `ImageAsset`: same library, uses, replacement, organization, clipboard,
  persistence and undo. Still document schema 27 (unreleased); a schema 26
  file with an SVG asset is refused.
- `SVGAssetSanitizer.sanitize` parses with `XMLParser` (no namespace
  processing, no external entities) and writes a canonical re-serialization:
  allow-listed SVG elements only (subtrees of anything else, such as
  `script`, `foreignObject`, `animate`, `set`, `feImage` and editor
  namespaces, are dropped; `a` is unwrapped), attributes sorted, fixed
  `xmlns` (plus `xmlns:xlink` only when used), no comments, processing
  instructions or DOCTYPE. Removed attributes: `on…`, `src`-like, `xml:base`,
  unknown prefixed names, `href` other than `#fragment` (and, on `image`
  only, base64 PNG/JPEG/GIF/WebP data), any value with `javascript:`,
  `vbscript:`, `expression(`, `@import`, `-moz-binding`, `behavior:`, or a
  `url(` that is not `url(#…)`. `style` attributes keep only safe
  declarations; a `<style>` element is kept only when its whole text is safe
  (also no backslash or `</`). Entity declarations and a non-`svg` root are
  refused (`ImageImportError.unsupportedSVG`); malformed XML, more than 128
  levels or 50,000 elements are `corrupt`. Only UTF-8 is accepted.
- The output is idempotent, so export checks stored bytes exactly
  (`isCanonicalSanitized`): `StaticAssetExportPlanner` accepts
  `image/svg+xml` only when the bytes are already canonical and writes
  `assets/<sha256>.svg`. HTML/CSS asset-path checks accept `.svg`. Browser
  Preview serves `image/svg+xml`.
- Size (SF-0804-001): root `width`/`height` (number or `px`), else derived
  from `viewBox`, else 300 × 150; rounded up; the source is reported
  (`attributes`, `viewBox`, `defaulted`), never stored.
- Recolor (SF-0804-002): an icon is compatible when it has at most one
  concrete paint and no gradients, patterns, embedded images or `url(#…)`
  paint. `recolor` rewrites every concrete paint and `currentColor` in
  attributes, style attributes and style sheets, and adds a root `fill` when
  there is none. `WorkspaceShellState.recolorSVGAsset` stores the result as a
  new resource for the same asset identity in one `updateImageAsset`
  transaction; Undo restores the previous resource. The Assets row menu
  offers Recolor SVG… (sheet: current and not-applied preview, hex field,
  Cancel/Escape, Apply).
- Accessible names (SF-0804-003): an Image's own alt text wins, then the SVG
  root `<title>` as a suggestion only, decorative Images have none
  (`accessibleName`); the sheet explains this. Output alt text is unchanged.
- Preview: thumbnails pass the SVG bytes through; canvas tiles fall back from
  ImageIO to `NSImage(data:)` rasterized at about twice the drawn size.
- Diagnostics (SF-0804-008): `diagnosticSummary` gives requirement, counts,
  size source and recolor compatibility with a hashed asset token only. Import
  announcements report how many unsafe SVG parts were removed. A social
  image that is an SVG gives the `social-image-svg` warning.

## Consequences

- The project never contains the original SVG bytes, only the sanitized form.
- SVGs that depend on removed features (scripts, external sprites or fonts,
  CSS with `url()` to other files, UTF-16 encoding, undefined HTML entities)
  look different or are refused.
- Canvas and thumbnail preview depend on AppKit's SVG support (macOS 14+).

## Amendment B04 (2026-11-26)

- Recolor SVG… is also File ▸ Recolor Selected SVG…; the menu, the Assets row
  menu and the sheet share `WorkspaceShellState.svgRecolorAssetID`
  (`presentSVGRecolor`, `canRecolorSVG`). The sheet is presented once at the
  workspace root and parses/recolors off the main actor.
- SVG import and recolor append a `MediaAssetDiagnosticRecord` (requirement,
  operation, hashed asset token, duration, failure category, removed-part
  count) to a bounded buffer (`mediaAssetDiagnosticRecords`).
- Still not built: an SVG title as an automatic output alt text (kept as a
  suggestion only), 100/10,000-object performance fixtures, UI tests.

## Verification amendment (lane V08, 2026-11-26)

- SF-0804-003: the Image Inspector shows, for one selected SVG Image, which
  rule gives it its accessible name (`SVGAssetSanitizer.accessibleNameExplanation`:
  decorative, the Image's own alternative text, the SVG title as a
  suggestion only, or nothing). The title is read from the stored sanitized
  bytes in a detached task (`SVGAccessibleNameRow`, identifier
  `inspector.image.svgAccessibleName`); output alt text is unchanged.
- SF-0804-007: sanitizing and recoloring a 10,000-element SVG stays within a
  safety bound (`testMediaFontAndSVGChecksStayWithinBoundsOnStandardAndLargeFixtures`).
- Still not built: UI tests (they need measured entries in
  `scripts/ci-ui-timings.txt` from a run on the Mac).

## Reversal

Remove `.svg` from the open panels; existing SVG assets keep decoding.
