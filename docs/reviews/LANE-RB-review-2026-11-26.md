# Lane RB review — 2026-11-26 (SVG, project fonts, video and audio; unverified)

Reviewer: Code Forge lane RB (review freeze, no compiler on this PC). Every fix
below was built from text read in the same call, passed `check([...]) == []`
and was re-read against the declarations it calls. Nothing was committed.

## Scope

- Batches: B01 (sanitized SVG, ADR-0050), B02 (project fonts, ADR-0051), the
  "Review B01–B02" pass, B04 (SVG/font gaps: diagnostics records, menu
  commands, Core Text canvas registration), F01 (video/audio, ADR-0100, OD-100).
- Modules: SF-0803 (video/audio), SF-0804 (SVG), SF-0805 (fonts).
- Files read in full for these batches: `SiteForge/ProjectResources.swift`
  (SVG sanitizer, font/media sniffers and workers, outputs, diagnostics, canvas
  registration, export planner), `DocumentModel.swift` (FontAsset…,
  MediaAsset…, CanonicalMediaPlayback, editing helpers, CanonicalDocument keys,
  validate, schema gates), `CommandKernel.swift` (set commands, every
  `DocumentCommand`/`CommandName` switch), `PersistedHistory.swift`,
  `ProjectPackage.swift` (snapshot restore, comparison, component library
  export), `PackagedSiteTemplate.swift`, `ClipboardTransfer.swift`,
  `CanvasRendererCore.swift` (render tree, emitMedia, typography fallbacks,
  multi-page planner, StaticBuildCompiler image/media/font loops, reference
  audit), `BrowserPreview.swift` (MIME types, byte ranges), `LaunchExperience.swift`
  (open panels), `WorkspaceShellModel.swift` and `WorkspaceShellView.swift`
  (sheets, rows, Inspector, menu, tile layer), and all lane-B/F tests in
  `Tests/SiteForgeTests/ProjectResourceTests.swift`.

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/DocumentModel.swift` | `MediaPlaybackEditing.prepare` | Relied on `CommandRegistry().availability` to refuse invalid playback, but a single `.setProperty` is `.enabled` without validating the result (only `.batch` and set-commands validate). A one-property change (captioned video → audio, which keeps the captions key) was returned as a valid command. `testMediaPlaybackRulesProvenanceAndOneUndoableEditPerChange` asserts `prepare(.init(assetID: audio, captionsAssetID: captions))` throws, so the test would have failed; production was saved only by `DocumentSession.execute`'s own validation (generic "invalid result" message). | After the availability check, apply the command to a draft with `registry.apply` and `draft.validate()`; a `ModelValidationError` becomes `CommandExecutionError.disabled(<message>)`. | Test contract and SF-0803-002/004 (refuse before commit with a specific reason). |
| 2 | `SiteForge/PackagedSiteTemplate.swift` | `PackagedSiteTemplateLoader.originalResourcesAreIndexed`, `ProjectCreationResources.validate`, new `ProjectCreationResources.storedFiles(in:)` | Only `imageAssets` resource IDs/hashes/sizes were checked, so a template (or any new-project baseline) whose font or media bytes were missing or mismatched was accepted and became a project that silently lost fonts/media. | `storedFiles(in:)` lists images, fonts and media (resource ID, content hash, byte count); both checks use it (missing → `missingBlob`, mismatch → `corruptBlob`). Bundled Aurora templates have no fonts/media, so behavior for them is unchanged. | Brief decision: fonts/media are project files exactly like images (SF-0805-004, SF-0803-004). |
| 3 | `SiteForge/WorkspaceShellModel.swift`, `SiteForge/WorkspaceShellView.swift` | new `isProjectMediaPresented`, `canManageProjectMedia`, `presentProjectMedia()`; `AssetsNavigatorView`; root sheets; Site menu | Video & Audio… was reachable only from a button with a local `@State` sheet (no menu command, unlike Project Fonts and Recolor SVG after B04). SF-0803-006 gap. | Shared model state like fonts; the Assets button calls `presentProjectMedia()`; the sheet is presented once at the workspace root; Site menu gains "Video & Audio…" after Project Fonts…. `canManageProjectMedia` is lifecycle availability only, so the sheet can be reopened while an import runs (its progress lives there). Local `showingProjectMedia` removed. | SF-0803-006 (keyboard/menu reachability, one presentation state). |
| 4 | `SiteForge/ProjectResources.swift`, `SiteForge/WorkspaceShellModel.swift` | `MediaAssetOperation` (+`mediaImport`, `mediaReplace`, `mediaUpdate`, `mediaRemove`, `mediaPlayback`, requirement IDs SF-0803-004/002/005), `importMediaURLs`, `replaceMediaURL`, `updateMediaAsset`, `removeMediaAsset`, `setMediaPlayback` | SF-0803-008: media operations emitted no diagnostics (SVG and fonts did). | Each operation appends one content-free `MediaAssetDiagnosticRecord` (hashed asset token, duration, failure category), mirroring the font import pattern (`defer` per file). Only switch over `MediaAssetOperation` is `requirementID` (updated). | SF-0803-008. |
| 5 | `SiteForge/CanvasRendererCore.swift` | `StaticBuildCompiler.compile` ("assets-unused") | The SF-1206-003 information finding counted unused images and fonts but not video/audio/captions files, which are also not written. | Counts media no Image plays (`MediaAssetEditing.usageCount == 0`) and names "Video & Audio" in the repair. No test asserts the text. | Consistency of SF-1206-003 with SF-0803 output rules. |
| 6 | `docs/architecture-decisions/ADR-0100-…`, `ADR-0051-…` | Review amendment sections | Record 1–5. | — | Documentation discipline. |

Found by another reviewer while I was reviewing (verified, not re-edited):
lane RH changed `MultiPageStaticBuildPlanner.plan` to rewrite ` poster="assets/`
as well as ` src="assets/` on pages in a folder (language trees, item pages,
list pages, nested routes) and added the nested-route assertions to
`testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound`. Before
that, posters on nested pages pointed at a non-existent `…/assets/` path.

Checked without change (evidence for Codex):
- Every exhaustive `switch` over `DocumentCommand` (`minimumPersistedHistorySchema`,
  `name`, `targets`, availability, mutate) and the descriptor list include
  `setFontAssets`/`setMediaAssets`; `CommandKernelTests.testCentralRegistryIsExhaustiveAndProvidesDisabledReasons`
  compares against `CommandName.allCases`; `historyAvailability` uses `default`.
  `PersistedHistory.validateDocumentCommand` lists both payloads. No other
  switch in the tree (incl. tests) enumerates these enums. `ModelValidationError`
  messages include the three new cases; no other switch over it exists.
  `ImageAssetFormat` is switched only in `mediaType`; `ImageImportError` only in
  its own two properties (both include `.unsupportedSVG`).
- `CanonicalDocument`: `fontAssets`/`mediaAssets` are optional keys, omitted
  when empty, refused as null/`[]`, accepted by the strict optional-key set,
  schema-27 gated, copied by template creation, listed in `ProjectComparer.compare`
  and `sameUncomparedContent`, restored by `ProjectSnapshots.restoreCommand`
  (files must be available; the grouped restore is validated as a whole, so
  restored Images find their files). No production `CanonicalDocument(…)`
  constructor drops them (only legacy migrations and the library carrier,
  which cannot contain Images).
- Copy paths: media/font references are document-level asset IDs, not
  NodeIDs/PageIDs, so the six node copy paths keep them unchanged; cross-project
  paste drops playback whose file the destination lacks
  (`CanonicalMediaPlayback.keepingAvailable`). Component library export already
  refuses definitions with Images (`usesImages`), which covers media mode.
- Save / reopen / recovery: resources are never pruned from the index, and
  `ProjectImageResourceSnapshot` carries font and media bytes to builds.
- StaticBuildCompiler: media candidates come from all page nodes (incl.
  component definitions) plus collection item/list copies
  (`CollectionTemplates.outputPages`); per-language trees reuse the same nodes
  and paths; fonts are found through `ProjectFontResolver.usageCount` over all
  pages; nested pages link `styles.css` with `../` and `@font-face` URLs are
  relative to the root stylesheet. Lane H's planner change (`.oversized` /
  `.corrupt` split) does not conflict with F01: media errors map to
  `media-invalid`; F01 tests never hit the size limit.
- BrowserPreview: `Response` memberwise init with defaulted `contentRange`;
  `Data.dropFirst(_:).prefix(_:)` slices are relative (correct for `Data`);
  single range, suffix range, open range, `416` with `bytes */N`, HEAD.
- SVG sanitizer test arithmetic re-derived by hand (6 removed elements,
  5 removed attributes, colors `["#00f", "blue"]`, idempotence, dimension
  sources, recolor outputs). Font resolution and OS/2 byte offsets re-derived.
- Core Text: `CTFontManagerRegisterFontsForURL(_:_:_:)` (not deprecated),
  `CTFontManagerError.alreadyRegistered.rawValue` vs `CFErrorGetCode` (both
  `CFIndex`), `CTFontManagerCreateFontDescriptorFromData` returns an optional,
  `CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), [])` → `CFData?`.

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-0803-001 | Met | `MediaAsset` exact keys, optional `language`, `CanonicalDocument.mediaAssets` omit-when-empty, schema gate; `CanonicalMediaPlayback` omitted/authored distinction. `testMediaModelIsStrictValidatedOmittedWhenEmptyAndUndoable`, `testMediaPlaybackRulesProvenanceAndOneUndoableEditPerChange`. |
| SF-0803-002 | Met | Video & Audio sheet (import, rename, language, replace, remove), Image Inspector playback, one undoable edit each; menu command added (fix 3). Same tests + `testMediaImportKeepsOriginalBytesAndMediaSurvivesSaveAndReopen`. |
| SF-0803-003 | Met | `provenance(_:)`, `explanation(_:media:)`, closed rules in `CanonicalMediaPlayback.validate`. |
| SF-0803-004 | Met | Sniffed import errors (unsupported vs damaged), missing-file labels in sheet/Inspector, Replace File recovery, `media-missing`/`media-invalid` blocking findings, creation-resource check (fix 2). |
| SF-0803-005 | Met | `setMediaAssets` undo/redo, persisted history (new test), snapshot restore, comparison, save/reopen. |
| SF-0803-006 | Partial | Labels/identifiers, keyboard (Return/Escape), Site menu (fix 3). Not entries in the central `CommandRegistry` (workspace sheet commands, like fonts/SVG); no UI tests. |
| SF-0803-007 | Partial | Import in `MediaImportWorker` actor with size pre-check; no 100/10,000 fixtures. |
| SF-0803-008 | Partial | Diagnostics records (fix 4); unit/integration tests; no UI or performance tests. |
| SF-0804-001 | Met | `ImageAssetFormat.svg`, schema gate, canonical sanitized bytes. `testSVGAssetImportRecolorUndoSaveReopenExportAndSchemaGate`. |
| SF-0804-002 | Met | Recolor sheet with uncommitted preview, one undoable `updateImageAsset`. `testSVGRecolorRewritesEveryPaintAndRefusesIncompatibleIcons`. |
| SF-0804-003 | Partial | `SVGAssetSanitizer.accessibleName` rule and recolor-sheet summary; the Image Inspector does not show which rule wins, and output never uses the SVG title (by design, kept as a suggestion). |
| SF-0804-004 | Met | Entities/non-SVG root refused, unsafe parts removed and counted, export gate `isCanonicalSanitized`, `social-image-svg` warning. |
| SF-0804-005 | Met | Recolor undo/redo keeps previous bytes; save/reopen test. |
| SF-0804-006 | Partial | Site menu + row menu share `svgRecolorAssetID`; not in the central registry; no UI tests. |
| SF-0804-007 | Partial | Sheet parses/recolors in `Task.detached`; tile layer caches parsed SVGs; no perf fixtures. |
| SF-0804-008 | Partial | `diagnosticSummary`, import/recolor records; no UI/perf tests. |
| SF-0805-001 | Met | `FontAsset` strict keys, optional `licenseNote`, omit-when-empty, schema gate. `testProjectFontModelIsStrictValidatedOmittedWhenEmptyAndUndoable`. |
| SF-0805-002 | Met | Project Fonts sheet (family, weight, style, rights, fallback, note, remove); Inspector Use Project Font. |
| SF-0805-003 | Met | `ProjectFontResolver` (CSS Fonts 4), Inspector explanation, `font-face-missing`. |
| SF-0805-004 | Met | Import errors, never-assumed rights, export only with web rights, missing/damaged file warnings, creation-resource check (fix 2). |
| SF-0805-005 | Met | `setFontAssets` undo/redo, persisted history (new test), snapshot restore, comparison, save/reopen. |
| SF-0805-006 | Partial | Menu + Assets button share state; not in the central registry; no UI tests. |
| SF-0805-007 | Partial | Import in `FontImportWorker`; canvas registration writes the file and registers on the main actor; no perf fixtures. |
| SF-0805-008 | Partial | Records for import/update/remove; no UI/perf tests. |

## Remaining gaps (easiest → hardest)

1. Unregister faces on the canvas when a font is removed or replaced
   (`CTFontManagerUnregisterFontsForURL` for hashes no longer in the document)
   so a removed font shows its fallback on the canvas too (SF-0805-003).
2. Show the SVG accessible-name rule (alt text / title / decorative) in the
   Image Inspector for SVG assets (SF-0804-003), reusing `accessibleName`.
3. Move `ProjectFontCanvasRegistration.register` (file write + Core Text
   registration, up to 16 MB) off the main actor: prepare in a detached task,
   then refresh the scene on the main actor (SF-0805-007).
4. `assets.manifest.txt` (`StaticAssetManifestEmitter`, lane H) lists only
   image entries; add font and media entries (Static Release's
   `StaticOutputManifest` already covers every binary file).
5. Resource index never prunes and shares one cap (`ImageAsset.maximumAssetCount`
   = 2,000 resources) across images, recolor history, fonts and media; plan a
   save-time compaction that keeps resources referenced by the document,
   history and snapshots (needs an ADR; history/snapshot retention rules).
6. Central `CommandRegistry` entries for workspace sheet commands (Project
   Fonts…, Video & Audio…, Recolor SVG…) — architectural, shared with other
   lanes' sheets (SF-0803/0804/0805-006).
7. UI tests for the three sheets and the Inspector, and 100/10,000-object
   performance fixtures (007/008); add timings to `scripts/ci-ui-timings.txt`.
8. WOFF2 without Core Text support: if `CTFontManagerCreateFontDescriptorFromData`
   cannot read WOFF2 on the deployment target, WOFF2 import fails as "damaged";
   a fallback (family from file name, weight 400) or a WOFF2 decoder needs an
   owner decision (new OD in lane B's range).

Also noticed outside my scope (for the owning reviewers): `ProjectComparer.compare`
adds both "Languages" and "Site languages" when localization differs (lane E).

## Intended OD status-line changes

- OD-045 — append to the Implementation status line: "Lane RB review
  2026-11-26: playback edits validated before commit, new-project resources
  check fonts and media, Video & Audio… in the Site menu, media diagnostics
  records; still unverified."
- OD-100 — unchanged (open; 16 MB limit in force).

## New/changed test selectors

New:

```
SiteForgeTests/ProjectResourceTests/testProjectCreationResourcesRequireEveryFontAndMediaFile
SiteForgeTests/ProjectResourceTests/testFontAndMediaEditsRestoreFromPersistedHistory
```

Changed:

```
SiteForgeTests/ProjectResourceTests/testMediaAssetCommandsShareStateAndRecordContentFreeDiagnostics   (Video & Audio presentation state)
SiteForgeTests/ProjectResourceTests/testMediaImportKeepsOriginalBytesAndMediaSurvivesSaveAndReopen   (media diagnostics records)
SiteForgeTests/ProjectResourceTests/testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound   (nested-route posters; edited by lane RH)
```

Should now pass because of fix 1 (no test edit):
`SiteForgeTests/ProjectResourceTests/testMediaPlaybackRulesProvenanceAndOneUndoableEditPerChange`.

Suggested run: `SiteForgeTests/ProjectResourceTests`, `SiteForgeTests/CommandKernelTests/testCentralRegistryIsExhaustiveAndProvidesDisabledReasons`,
`SiteForgeTests/CanvasRendererTests` (assets-unused), `SiteForgeTests/LaunchExperienceTests` (template loading).

## Suggested first checks for Codex

1. `MediaPlaybackEditing.prepare`: `_ = try registry.apply(command, to: &draft)`
   and the non-exhaustive `do { try draft.validate() } catch let error as ModelValidationError { … }`.
2. `ProjectCreationResources.storedFiles(in:)`: labeled-tuple array with
   `files.append((asset.resourceID, asset.contentHash, asset.byteCount))`.
3. `SVGSanitizerParserDelegate` (`private final class … NSObject, XMLParserDelegate`)
   under the project's concurrency settings, and whether `XMLParser` calls
   `parseErrorOccurred` after `abortParsing()` (first failure is kept).
4. Exact removed-part counts (6 elements / 5 attributes) in
   `testSVGSanitizerRemovesScriptsExternalReferencesAndEventAttributes` — they
   depend on `XMLParser` not reporting `xmlns` attributes as removable.
5. `FontImportWorker`: `CTFontManagerCreateFontDescriptorFromData` with WOFF2
   on the deployment SDK, and that 5-byte TrueType data returns nil (no trap).
6. `ProjectFontCanvasRegistration.register` called from `WorkspaceShellState.init`
   in tests (writes to `<tmp>/SiteForgeProjectFonts`; tests that count temp
   files).
7. Font/media import `Task` closures: `defer` blocks inside `for` loops with
   `try await` and `return`/`continue`, calling main-actor `recordMediaAsset`.
8. Root `.sheet(isPresented: $state.isProjectMediaPresented)` next to the fonts
   and SVG sheets (one more modifier on a long chain; SwiftUI type-check time).
9. `NSImage(data:)` SVG decoding (macOS 14+) for thumbnails, the recolor sheet
   and `CanvasContentTileLayer.decodedTileImage`; `[Data: NSImage]` cache keyed
   by up to 16 MB `Data`.
