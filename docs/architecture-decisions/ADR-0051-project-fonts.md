# ADR-0051 — Project fonts (WOFF2/TTF), rights, fallback stacks and @font-face export

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-045 (approved by the owner 2026-11-26 1:30 PM EST)
- Requirements: SF-0805-001 … SF-0805-008

## Context

OD-045: fonts are project-embedded WOFF2/TTF files with a license note and
system-font fallback stacks; no font service.

## Decision

- `FontAsset` (one face): `AssetID` identity, `resourceID`, `family`,
  `weight` (100–900 in steps of 100), `style` (normal/italic), `format`
  (`woff2` `font/woff2`, `ttf` `font/ttf`), file facts, `rights`
  (`unconfirmed` default, `webEmbeddingAllowed`, `editorOnly`), optional
  `licenseNote` (omitted when absent, never null or blank, ≤ 4 KiB) and
  `fallback` (`sansSerif`, `serif`, `monospace` system stacks). Exact keys.
  Family may not be `System` (the existing default family). At most 200
  faces; ids, resources, hashes and family+weight+style (case-insensitive
  family) are unique.
- `CanonicalDocument.fontAssets`, an optional key written only when not
  empty (null or `[]` refused), like `collections`. Still document schema 27;
  a schema 26 file with fonts is refused.
- One command `setFontAssets(SetFontAssetsCommand)` (`document.fontAssets.set`,
  "Edit Fonts", persisted-history schema 4) replaces the list; all edits go
  through `FontAssetEditing.prepare`. Font bytes are installed with
  `installingProjectResource` and stay in the project when a face is removed,
  so Undo is exact. Snapshot restore also restores fonts.
- Import (`FontImportWorker`): signature `wOF2` or `00010000`/`true` (WOFF 1,
  OpenType-CFF and collections refused), CoreText must read it, family from
  CoreText (filename stem if unusable), weight/italic from the OS/2 table, and
  OS/2 fsType "restricted license embedding" makes the face `editorOnly`.
  Original bytes unchanged. Rights are never assumed to allow the web.
- Resolution (`ProjectFontResolver`): CSS Fonts 4 matching (style, then
  weight: 400–500 tries heavier up to 500, then lighter, then heavier; below
  400 lighter first; above 500 heavier first). A family's fallback comes from
  its lightest face; changing the fallback in the UI changes every face of the
  family. The Inspector's weight summary shows which face wins and why.
- Output: `StaticBuildCompiler` packages, as `assets/<sha>.woff2|ttf`, only
  faces with `webEmbeddingAllowed` that some text uses, after
  `StaticAssetExportPlanner` checks hash and file signature. `styles.css`
  starts with one `@font-face` per packaged face (`font-display: swap`), and
  every use of a project family is written `"Family", <fallback stack>`
  (`StaticTypographyOutputEmitter.emit(nodes:fontFallbacks:)`). A page using a
  project font links `styles.css`. Findings (no names or text):
  `font-rights-unconfirmed`, `font-not-licensed-for-web`, `font-face-missing`,
  `font-resource-missing`, `font-resource-invalid` (warnings; the build still
  completes with fallback fonts).
- UI: Assets → Project Fonts… sheet (import, family, weight, style, rights,
  fallback, license note, remove; one undoable edit per change) and
  Inspector → Use Project Font menu.

## Consequences

- Since B04 the canvas registers project faces for the app process only
  (see the amendment); a face Core Text can't load shows the system font.
- Renaming a family does not rename text that used the old name.
- Fonts share the resource index cap (2,000 resources) with images.

## Amendment B04 (2026-11-26)

- `ProjectFontCanvasRegistration.register` verifies signature and hash, writes
  the bytes once to `<tmp>/SiteForgeProjectFonts/<sha>.<ext>` and calls
  `CTFontManagerRegisterFontsForURL(…, .process, …)`; "already registered"
  counts as success. `WorkspaceShellState` registers new hashes when the
  document changes and refreshes the scene. Faces stay registered until the
  app quits; a renamed family only matches on the canvas if the file's own
  family name matches.
- Project Fonts… is also in the Site menu; menu and Assets button share
  `isProjectFontsPresented` (`presentProjectFonts`, `canManageProjectFonts`);
  the sheet is presented once at the workspace root.
- Font import, update and removal append `MediaAssetDiagnosticRecord`s.

## Review amendment (lane RB, 2026-11-26)

- New-project resources (`ProjectCreationResources.validate`, packaged
  template loading) require every project font file the document lists, with
  matching hash and size, not only image files.

## Verification amendment (lane V08, 2026-11-26)

- Canvas faces are no longer kept until the app quits. Each window has a
  `ProjectFontCanvasSession` actor that reads and verifies the bytes, writes
  the file and calls Core Text off the main actor, in document order
  (`WorkspaceShellState.registerProjectFontsForCanvas` chains one task per
  change of the document's font hashes and prepares the scene again when the
  registered faces change). `ProjectFontCanvasRegistration.retain` /
  `release` count the windows that use a face under one lock; the last user
  calls `CTFontManagerUnregisterFontsForURL(…, .process, …)`, so a removed
  face shows its fallback on the canvas too (SF-0805-003), and Undo
  registers it again. A closed window releases its faces (actor `deinit`).
  Bytes Core Text refuses are not retried; a missing file is looked for again
  on the next change.
- WOFF2 (OD-045 covers the format; OD-060 asks about a fallback): a WOFF2
  file whose fixed 48-byte header is intact (`ProjectFontFormatSniffer.hasValidWOFF2Header`:
  `length` equals the file size, `numTables` > 0, `reserved` 0) but that Core
  Text can't read is refused with `FontImportError.unreadableWOFF2`
  ("unreadable-woff2") and a specific recovery (import the TrueType version
  or export the WOFF2 again) instead of "damaged". Such files are still never
  imported with guessed family, weight or style; that is OD-060.
- Performance fixtures (SF-0805-007): font usage, resolution and findings on
  100 and 10,000-object documents are covered by
  `testMediaFontAndSVGChecksStayWithinBoundsOnStandardAndLargeFixtures`.

## Reversal

Hide Project Fonts and stop emitting `@font-face`; documents keep decoding.
