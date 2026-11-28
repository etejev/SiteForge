# ADR-0035 — Zip archive export target

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-042 (approved by the owner 2026-11-26 1:30 PM EST)
- Requirements: SF-1209 (export targets); SF-1206, SF-1211-004 behaviour reused

## Context

OD-042 keeps export static and asks for two export adapters, a plain folder
and a zip archive. Only the folder writer existed (`LocalStaticBuildWriter`),
used by Browser Preview Export and by Check Website's build.

## Decision

- `StaticExportTarget` (`folder`, `zipArchive`) selects the adapter for the
  same immutable `LocalStaticBuildPlan`. Both carry byte-identical files.
- `StaticSiteZipArchive.archive(_:)` writes a deterministic ZIP: stored
  entries only (no compression), sorted by path, UTF-8 names (flag bit 11),
  DOS epoch timestamps (1980-01-01 00:00), UNIX regular-file permissions
  0644, no extra fields or comments. The same plan always gives the same
  bytes. Paths follow the folder writer's rules; duplicates are refused.
- ZIP64 is not written. A plan over 65,535 files or 4 GiB is refused before
  any write with the new `LocalStaticBuildWriteError.archiveTooLarge`; the
  user is told to export a folder instead.
- `LocalStaticBuildWriter.writeZipArchive` has the folder writer's revision,
  replacement, cancellation and permission rules. The destination must end in
  `.zip` and must not be a folder. The archive is staged beside the
  destination as `.siteforge-build-<UUID>.zip`, read back and verified with
  `StaticSiteZipArchive.storedEntries(_:)` (signatures, names, sizes, CRC-32),
  then promoted in one move or replace. A failure removes the staged file.
- UI: Browser Preview adds **Export Zip…** (`preview.website.exportZip`);
  Check Website adds **Build Zip Archive…** (`build.writeZip`). Both use a
  save panel restricted to zip.

## Not in this decision (still open under OD-042)

- One hashed runtime script file. Today the runtime ships as
  `siteforge-effects.js` and `siteforge-navigation.js`. Renaming them affects
  about 20 test assertions, a UI test selector and the Python flow-runtime
  browser harness, so it is a separate batch.
- Publishing, domains, hosting and rollback stay deferred.

## Consequences

- No document schema, clipboard, history or project-file change.
- Stored entries make archives larger than deflated ones; the trade is exact
  determinism and no compression dependency.

## Reversal

Remove the two buttons and the zip adapter; the folder writer is unchanged.
