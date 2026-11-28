# ADR-0121 — Static asset export: integrity manifest, cache policy and reference audit (SF-1206)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-042 (approved by the owner 2026-11-26 1:30 PM EST: static export only); lane H item H2
- Builds on: ADR-0120 (Static Release CSS optimization)
- Requirements: SF-1206-001 (manifest model), -003 (resolution: names, cache policy, unused files),
  -004 (missing, oversized and unresolved output; verified writes), -008 (tests)

## Context

Images, SVGs and project fonts were already written content-addressed (`assets/<sha256>.<ext>`) after
verifying their bytes, and `assets.manifest.txt` listed exported images. Missing: a manifest of every
written file with its hash, cache metadata, a check that every output reference resolves (the module's
critical invariant), a distinct oversized diagnostic (the planner reported over-limit files as
"unsupported"), a report of project files the site does not use, and read-back verification for folder
builds (zip builds already verified).

## Decision

- `StaticOutputCachePolicy` (`immutable` for `assets/<64 hex>.<ext>`, otherwise `revalidate`),
  `StaticOutputFileRecord` (path, bytes, sha256, cache) and `StaticOutputManifest` (version 1, records
  sorted by path; `json` is one line with sorted keys; `mismatchedPaths(in:)`). The manifest has no
  revision or time, so identical output gives an identical manifest. All in
  `SiteForge/CanvasRendererCore.swift`, section "SF-1206 static asset export".
- `LocalBuildReport.outputFiles` holds the records for both profiles. Static Release also writes
  `siteforge-integrity.json` (every other written file; it does not list itself). Development output is
  unchanged. The planner's `manifest.txt` and `assets.manifest.txt` are unchanged (they are produced before
  profiles; `manifest.txt` therefore does not list the integrity file).
- Generated page, stylesheet and script names are not hashed here: one hashed runtime script file is OD-042's
  separate item (lane E, E2, blocked on unreadable harness files), and hashing them would change every page.
  Their cache policy is `revalidate`.
- `StaticOutputReferenceAudit.unresolved(in:)`: relative `src`, `href` and `poster` values and `url(…)`
  inside `style` attributes of every page, and `url(…)` in stylesheets, must name a written file (folder
  references need `index.html`). Values with a scheme, `//`, `/` (site-root addresses such as canonical and
  hreflang links) or only a fragment are not checked. `StaticBuildCompiler` adds one warning
  `output-reference-unresolved` (SF-1206-004) per affected file with the count only.
- `StaticAssetExportPlanner`: an unknown type stays `unsupported`; a negative size is `corrupt`; over
  `ProjectResourceIndex.maximumResourceBytes` is now `oversized` (finding `asset-oversized`, its own
  explanation and repair). Lane F's media types are kept.
- `assets-unused` (information, SF-1206-003) once per build when project images
  (`ImageAssetDependencies.unusedAssetIDs`) or fonts no text uses are not written; counts only.
- `LocalStaticBuildWriter.write` (folder) reads every staged file back and compares it with the plan before
  promotion; a mismatch is `writeFailed` and the destination is untouched.

## Consequences

- Static Release gains one file; findings may gain `output-reference-unresolved` (for example collection item
  pages at nested routes whose image and control references are written relative to the site root, noted in
  batch E04) and `assets-unused`. Neither blocks writing.
- Folder builds read their output once more before promotion.
- Not built: responsive renditions, a host-specific cache headers file (publishing is deferred), hashing of
  generated pages/scripts, and fixing the nested-route references themselves (planner code other lanes are
  changing; reported instead).

## Update — 2026-11-26 (lane V12 verification)

- Nested-route references: the multi-page planner now writes every generated reference of a page in a folder
  (language trees, collection item pages, a list's later pages, nested routes) relative to that page: links and
  navigation through `SiteLanguageOutput.relativeRoutes`, image sources, video posters, media sources and
  captions through the folder prefix, stylesheets, scripts and favicons through `prefix`, interactions through
  `EventGraphOutput.page(_:staticRoutes:prefix:)`. Canonical and `hreflang` links stay site-root addresses (not
  checked). Regression fixtures: collection item pages in `PersistedHistoryTests` and the nested video page in
  `ProjectResourceTests`. The audit stays as the safety net (for example for custom code).
- `LocalBuildReport.outputFiles` also lists `siteforge-integrity.json` in Static Release (ADR-0123).

## Update — 2026-11-26 (lane V12b, ADR-0124)

- Static Release now writes the generated runtime as one content-addressed `siteforge-runtime.<sha256>.js` (cache
  policy `immutable`, listed in `manifest.txt`, the integrity manifest and the report); every page that used a runtime
  references it from its own folder. Development keeps the readable per-runtime files (`revalidate`). Pages and
  stylesheets keep their names.
- `assets.manifest.txt` lists every exported asset type: images (SVG and video posters included) with their pixel size,
  fonts, video, audio and captions with their media type, in asset-identity order.

## Verification

`SiteForgeTests/CanvasRendererTests/testStaticOutputIntegrityManifestCachePolicyAndReferenceAudit`. Not
compiled or run by Code Forge.
