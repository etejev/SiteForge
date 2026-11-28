# Lane V08 verification — 2026-11-26 (lanes B + F: SVG, project fonts, video and audio; unverified)

Reviewer: Code Forge lane V08 (owner tag `lane-V08`). No Swift toolchain on
this PC: every change below was built from text read in the same call,
written with `forge_io.edit()`, passed `check([...]) == []` and was re-read
against the declarations it calls. Nothing was committed. Brief:
`_quick-scratch/review/VERIFY_BRIEF.md`.

## Scope

- Batches: B01 (sanitized SVG, ADR-0050), B02 (project fonts, ADR-0051), the
  "Review B01–B02" pass, B04 (SVG/font gaps), F01 (video/audio, ADR-0100,
  OD-100) and the lane RB review fixes (`docs/reviews/LANE-RB-review-2026-11-26.md`).
- Restore points diffed: `RP-2026-11-26-B01` → `RP-2026-11-26-V00` (current
  tree) for every file lanes B, F and RB wrote (from `WRITE_LEDGER.tsv`),
  read together with RP-B02, RP-B04, RP-F01 and RP-26-11. Other lanes edited
  the same big files in that window, so the lane-B/F regions were located by
  symbol and read in full in the CURRENT tree.
- Modules: SF-0803 (video/audio), SF-0804 (SVG), SF-0805 (fonts).
- Files read in full for these regions: `SiteForge/ProjectResources.swift`
  (snapshot, image/SVG/font/media import workers, sniffers, outputs,
  diagnostics record, canvas registration, SVG sanitizer and parser delegate,
  export planner), `DocumentModel.swift` (FontAsset…, ProjectFontResolver,
  FontAssetEditing, MediaAsset…, CanonicalMediaPlayback, MediaPlaybackEditing,
  MediaAssetEditing, document keys, validate, schema gates),
  `CommandKernel.swift` (`CommandAvailability`, set commands, availability,
  mutate), `PersistedHistory.swift`, `ProjectPackage.swift` (snapshot restore,
  comparison), `PackagedSiteTemplate.swift`, `ClipboardTransfer.swift`,
  `CanvasRendererCore.swift` (InternalStaticMedia, staticMedia, typography
  fallbacks, multi-page planner, StaticBuildCompiler image/media/font loops,
  emitImage/emitMedia, reference audit), `BrowserPreview.swift` (types,
  ranges), `LaunchExperience.swift` (open panels), `DocumentLifecycle.swift`
  (`installingProjectResource`, `projectResourceData`,
  `staticBuildResourceSnapshot`), `WorkspaceShellModel.swift` (all font,
  media and SVG members, init/sink), `WorkspaceShellView.swift` (root sheets,
  Assets buttons and row menu, SVGRecolorSheet, ProjectMediaSheet/Row,
  MediaPlaybackInspector, ProjectFontsSheet/Row, Typography Inspector project
  font menu and summary, Image Inspector, menu commands, tile layer), and all
  lane B/F/RB tests in `Tests/SiteForgeTests/ProjectResourceTests.swift`.

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/ProjectResources.swift`, `SiteForge/WorkspaceShellModel.swift` | `ProjectFontCanvasRegistration` (new `retain`, `release`, `userCount`, `fileURL`), new `actor ProjectFontCanvasSession`, `WorkspaceShellState.registerProjectFontsForCanvas(_:)` (was `(_:refreshScene:)`), new `fontCanvasSession`, `fontCanvasTask`, `canvasFontHashes` (replace `canvasRegisteredFontHashes`) | (a) A removed or replaced face stayed registered with Core Text until the app quit, so the canvas kept drawing a face the project no longer has while the website and the Inspector explanation use the fallback (SF-0805-003 provenance mismatch). (b) Every new face was read, hashed (up to 16 MB) and registered with Core Text synchronously on the main actor, at window open and on each document change (AGENTS "expensive work off the main actor", SF-0805-007). | Each window owns a `ProjectFontCanvasSession` actor: it reads and verifies the bytes from an immutable package snapshot, writes the file and calls Core Text off the main actor, and releases faces that leave the document. `retain`/`release` count windows per content hash under one `OSAllocatedUnfairLock`; the last user calls `CTFontManagerUnregisterFontsForURL(…, .process, nil)`. The state chains one task per change of the document's font hashes (so updates apply in document order) and prepares the scene again when the registered faces change (also after window open, since registration is now asynchronous). The actor's `deinit` releases a closed window's faces. Bytes Core Text refuses are not retried; a missing file is looked for again on the next change. | SF-0805-003/007; Undo of a removal registers the face again. |
| 2 | `SiteForge/ProjectResources.swift` | `FontImportError.unreadableWOFF2` (+ message, category `unreadable-woff2`), `ProjectFontFormatSniffer.hasValidWOFF2Header`, `FontImportWorker.prepare` | A WOFF2 file Core Text can't read was reported as "damaged or cannot be read" with no recovery, even when its header is intact (RB gap 8). | The fixed 48-byte WOFF2 header is checked (`length` equals file size, `numTables` > 0, `reserved` 0). Intact header + Core Text refusal → `.unreadableWOFF2` ("…Import the TrueType (.ttf) version of the font, or export the WOFF2 file again."); otherwise `.corrupt` as before. No other switch over `FontImportError` exists in the tree (checked, incl. tests). Importing such files with guessed facts is not done; that is the new OD-060. | SF-0805-004 (specific recovery). |
| 3 | `SiteForge/ProjectResources.swift`, `SiteForge/WorkspaceShellView.swift` | new `SVGAssetSanitizer.accessibleNameExplanation`, new private `SVGAccessibleNameRow`, Image Inspector | SF-0804-003 requires the Inspector to show which rule wins; the rule existed (`accessibleName`) but the Image Inspector never showed it for SVG Images (RB gap 2). | For one selected SVG Image with a common alt text and decorative state, the Inspector shows the winning rule (decorative / the Image's alt text / SVG title as a suggestion only / nothing). The title is read from the stored sanitized bytes in a detached task (`.task(id: asset.contentHash)`), same pattern as `SVGRecolorSheet.loadReport`. Identifier `inspector.image.svgAccessibleName`. Output alt text is unchanged. | SF-0804-003. |
| 4 | `SiteForge/WorkspaceShellView.swift` | `CanvasContentTileLayer.decodedTileImage` / `vectorImages` | The function's doc comment ("ImageIO first…") had been left above the cache property added in Review B01–B02, so the property carried two unrelated doc comments and the function none. | Moved the comment back to the function. | Comment quality (comments say why, next to what they explain). |

Checked without change (evidence for Codex):

- Lane RB fix 1 (`MediaPlaybackEditing.prepare` draft validation): `CommandAvailability.disabled(reason:)` matched by `if case .disabled(let reason)`; `registry.apply(_:to:cancellation:)` re-checks availability then mutates; non-exhaustive `catch let error as ModelValidationError` inside a throwing function is valid. The test contract (`prepare(.init(assetID: audio, captionsAssetID: captions))` throws) now holds.
- Lane RB fix 2 (`ProjectCreationResources.storedFiles`): labeled tuple appends, both checks use it; packaged template copies `collections`, `fontAssets`, `localization`, `mediaAssets`.
- Lane RB fixes 3–5 (Video & Audio… menu/root sheet, media diagnostics, `assets-unused` count) read against `WorkspaceShellState` and `StaticBuildCompiler.compile`; no regressions found.
- SVG sanitizer test arithmetic re-derived (6 removed elements, 5 removed attributes, colors `["#00f", "blue"]`, canonical idempotence, dimension sources, recolor outputs including `stroke-width` not being treated as paint and the root `fill` insertion).
- Font resolution (`nearestWeight` CSS Fonts 4 order), OS/2 offsets, `cssFamilyName`, export-test findings and `@font-face` text, media sniffer cases (M4A brand/extension, QuickTime refused, WebM DocType, MP3 frame sync vs AAC ADTS, WebVTT BOM/terminator), byte-range cases and media HTML strings re-derived against the implementation.
- Every `DocumentCommand`/`CommandName` switch includes `setFontAssets`/`setMediaAssets`; `PersistedHistory.validateDocumentCommand` lists both payloads; snapshot restore, comparison and `sameUncomparedContent` include both keys; clipboard paste drops playback whose file the destination lacks; nested pages rewrite ` src="assets/` (also `<source>`/`<track>`) and ` poster="assets/`.
- Concurrency: `ProjectPackage`, `FontAsset`, `MediaAsset`, `SVGSanitizationReport` are `Sendable`; the default actor isolation is not MainActor (import actors already call these statics); `CanvasContentTileLayer` is a plain `CALayer` (main-thread drawing), so its cache is not shared across threads.

## Features finished

| Item | Decision record | State |
|---|---|---|
| Canvas faces released when they leave the document; registration off the main actor (RB gaps 1 and 3) | ADR-0051 "Verification amendment (lane V08)" | Done: model + actor + workspace wiring + test. |
| SVG accessible-name rule in the Image Inspector (RB gap 2) | ADR-0050 "Verification amendment (lane V08)" | Done: model sentence + Inspector row + test. |
| 100 / 10,000-object performance fixtures for SF-0803/0804/0805-007 (RB gap 7, fixtures part) | ADR-0050/0051/0100 amendments | Done: one test with safety bounds (10 s / 120 s, and 60 s for a 10,000-element SVG). |
| WOFF2 import (RB gap 8) | OD-045 covers WOFF2 import itself; ADR-0051 amendment; new OD-060 for the fallback question | Done up to the decision boundary: unreadable WOFF2 is told apart from damaged files with its own recovery and test. Importing unreadable WOFF2 with guessed facts needs OD-060. |
| OD-100 16 MB limit | OD-100 (open) | Unchanged; the recommended default (16 MB) stays in force. |

ADR-0052 / ADR-0101 were not needed: every change is an amendment of an
existing decision record.

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-0803-001 | Met | `MediaAsset` exact keys, optional `language`, omit-when-empty, schema 27 gate; `CanonicalMediaPlayback` omitted/defaulted/authored. `testMediaModelIsStrictValidatedOmittedWhenEmptyAndUndoable`, `testMediaPlaybackRulesProvenanceAndOneUndoableEditPerChange`. |
| SF-0803-002 | Met | Video & Audio sheet, Image Inspector playback, one undoable edit each, Site menu + Assets button. Same tests + `testMediaImportKeepsOriginalBytesAndMediaSurvivesSaveAndReopen`. |
| SF-0803-003 | Met | `provenance(_:)`, `explanation(_:media:)`, closed rules in `CanonicalMediaPlayback.validate`. |
| SF-0803-004 | Met | Sniffed import errors, missing-file labels, Replace File recovery, `media-missing`/`media-invalid`, creation-resource check. `testProjectCreationResourcesRequireEveryFontAndMediaFile`. |
| SF-0803-005 | Met | `setMediaAssets` undo/redo, persisted history, snapshot restore, comparison, save/reopen. `testFontAndMediaEditsRestoreFromPersistedHistory`. |
| SF-0803-006 | Partial | Labels/identifiers, Return/Escape, announcements, Site menu and Assets button share one state; mutations validate through `CommandRegistry`. Blocked part: the sheet-presentation commands are workspace UI state, not entries in the central `CommandRegistry` (same for every workspace sheet of every lane; cross-lane architecture, see Remaining work). |
| SF-0803-007 | Met | `MediaImportWorker` actor with size pre-check and progress text; `testMediaFontAndSVGChecksStayWithinBoundsOnStandardAndLargeFixtures` (100 / 10,000 objects). |
| SF-0803-008 | Partial | Content-free `MediaAssetDiagnosticRecord`s, unit/integration/performance/migration tests. Blocked part: UI tests (see Remaining work). |
| SF-0804-001 | Met | `ImageAssetFormat.svg`, schema gate, canonical sanitized bytes. `testSVGAssetImportRecolorUndoSaveReopenExportAndSchemaGate`. |
| SF-0804-002 | Met | Recolor sheet with uncommitted preview, one undoable `updateImageAsset`. `testSVGRecolorRewritesEveryPaintAndRefusesIncompatibleIcons`. |
| SF-0804-003 | Met | `accessibleName` + `accessibleNameExplanation`; recolor-sheet summary and (fix 3) Image Inspector row. `testSVGAccessibleNameExplanationNamesTheWinningRule`. |
| SF-0804-004 | Met | Entities/non-SVG root refused, unsafe parts removed and counted, export gate `isCanonicalSanitized`, `social-image-svg`. `testSVGSanitizerRemovesScriptsExternalReferencesAndEventAttributes`. |
| SF-0804-005 | Met | Recolor undo/redo keeps previous bytes; save/reopen. |
| SF-0804-006 | Partial | Site menu + row menu share `svgRecolorAssetID`; same central-registry boundary as SF-0803-006. |
| SF-0804-007 | Met | Sheet parses/recolors in `Task.detached`; Inspector title read detached; tile cache; 10,000-element SVG fixture. |
| SF-0804-008 | Partial | `diagnosticSummary`, import/recolor records, unit/integration/performance tests; UI tests blocked. |
| SF-0805-001 | Met | `FontAsset` strict keys, optional `licenseNote`, omit-when-empty, schema gate. `testProjectFontModelIsStrictValidatedOmittedWhenEmptyAndUndoable`. |
| SF-0805-002 | Met | Project Fonts sheet, Inspector Use Project Font. `testProjectFontEditsAreUndoableAndFontBytesSurviveSaveAndReopen`. |
| SF-0805-003 | Met | `ProjectFontResolver`, Inspector explanation, `font-face-missing`; canvas now drops removed faces (fix 1). `testProjectFontResolutionFollowsCSSWeightMatchingAndFallbackRule`, `testProjectFontCanvasSessionReleasesRemovedFacesAndNeverRetriesRefusedBytes`. |
| SF-0805-004 | Met | Import errors incl. `unreadableWOFF2` (fix 2), never-assumed rights, export only with web rights, missing/damaged warnings. `testWOFF2ImportTellsUnreadableFilesFromDamagedOnes`, `testFontImportKeepsOriginalBytesAndReadsFaceFacts`. |
| SF-0805-005 | Met | `setFontAssets` undo/redo, persisted history, snapshot restore, comparison, save/reopen. |
| SF-0805-006 | Partial | Menu + Assets button share state; same central-registry boundary. |
| SF-0805-007 | Met | `FontImportWorker` actor; canvas registration off the main actor (fix 1); 100 / 10,000-object fixture. |
| SF-0805-008 | Partial | Records for import/update/remove; unit/integration/performance tests; UI tests blocked. |

Totals: 18 Met, 6 Partial, 0 Missing.

## Remaining work (blocked only)

1. UI tests for Project Fonts, Video & Audio, Recolor SVG and the Image
   Inspector media/SVG rows (SF-0803/0804/0805-008). Blocked: XCUITest cannot
   run on this PC, `scripts/ci-test-accounting.py` requires every UI selector
   to have a measured duration in `scripts/ci-ui-timings.txt` (header: taken
   from a full `.xcresult`), and journeys through the native open panel need
   calibration on the Mac. Suggested journey for Codex: open a fixture
   project, Site ▸ Project Fonts… (`fonts.empty`, Escape closes), Site ▸
   Video & Audio… (`media.empty`, Escape closes), Assets row ▸ Recolor SVG…
   (`assets.recolor.color`, Cancel leaves the document unchanged).
2. Central `CommandRegistry` entries for workspace sheet commands (Project
   Fonts…, Video & Audio…, Recolor SVG…), SF-0803/0804/0805-006. Blocked:
   cross-lane architecture — the registry holds document commands only and
   no workspace sheet of any lane (Collections, Languages, Snapshots, Site
   Settings…) is in it; adding a workspace-command layer needs one decision
   for all lanes (suggest the coordinator opens an OD).
3. Unreadable WOFF2 with guessed facts — blocked on new OD-060.
4. Resource index never prunes and shares one 2,000-resource cap across
   images, recolor history, fonts and media — blocked on new OD-101 (retention
   rules for history and snapshots).

## Intended plan / OD status-line changes (for the coordinator)

- OD-045 — append to the Implementation status line: "Lane V08 verification
  2026-11-26: canvas faces released when they leave the document and
  registered off the main actor; unreadable WOFF2 named with its own recovery
  (OD-060); SVG accessible-name rule in the Image Inspector; 100/10,000-object
  fixtures for SF-0803/0804/0805-007; UI tests still open (need a Mac run);
  still unverified."
- OD-100 — unchanged (open; the 16 MB per-file limit stays in force).
- New OD-060 (append to `docs/OPEN_DECISIONS.md`):

  > ## OD-060 — WOFF2 fonts that Core Text can't read
  > Status: Open (raised by lane V08, 2026-11-26). Context: OD-045 approves
  > WOFF2/TTF project fonts; import reads family, weight, style and
  > embedding rights through Core Text. When Core Text can't read a WOFF2
  > file whose header is intact, SiteForge can't check those facts.
  > Recommended default: keep refusing such files with the specific
  > "unreadable-woff2" message (import the TrueType version or export the
  > WOFF2 again) — implemented. Alternatives: (a) import with guessed facts
  > (family from the file name, 400 normal, rights not confirmed), editable in
  > Project Fonts; the canvas shows the fallback; risk: a damaged file is
  > exported and a wrong weight goes unnoticed; (b) add a WOFF2 decoder
  > (Brotli via the Compression framework plus table reconstruction) to read
  > OS/2 and name tables; more code and attack surface. Affected:
  > SF-0805-002/003/004/007. Decision deadline: before the milestone that
  > enables SF-0805. Safe temporary assumption: refuse (current behavior).

- New OD-101 (append to `docs/OPEN_DECISIONS.md`):

  > ## OD-101 — Project file retention and compaction (images, fonts, media)
  > Status: Open (raised by lane V08, 2026-11-26). Context: resources are
  > never removed from the project index so Undo, saved history and
  > snapshots stay exact; images, SVG recolor results, fonts and media share
  > `ImageAsset.maximumAssetCount` (2,000 resources) and 2 GB total.
  > Recommended default: keep never-pruning; later add an explicit,
  > undo-safe "Compact Project" that removes only resources no document
  > state, retained persisted history entry or snapshot references.
  > Alternatives: automatic save-time compaction (smaller files, but trims
  > history or snapshots); separate caps per kind. Affected: SF-0803-004/005,
  > SF-0804-005, SF-0805-005, SF-0807, SF-1301. Decision deadline: before
  > large media projects are supported. Safe temporary assumption: never
  > prune (current behavior).

- DEVELOPMENT_PLAN lane B/F rows: "Lane V08 verified B01, B02, Review
  B01–B02, B04, F01 and lane RB fixes (2026-11-26): 4 defects fixed, partial
  items finished except UI tests (blocked: Mac run for ci-ui-timings) and
  central-registry sheet commands (cross-lane); OD-060 and OD-101 raised."
- CODE_FORGE_ACTIVITY entry: "Lane V08 — verification of lanes B and F" with
  the files and selectors below.

## New/changed test selectors

New:

```
SiteForgeTests/ProjectResourceTests/testProjectFontCanvasSessionReleasesRemovedFacesAndNeverRetriesRefusedBytes
SiteForgeTests/ProjectResourceTests/testWOFF2ImportTellsUnreadableFilesFromDamagedOnes
SiteForgeTests/ProjectResourceTests/testSVGAccessibleNameExplanationNamesTheWinningRule
SiteForgeTests/ProjectResourceTests/testMediaFontAndSVGChecksStayWithinBoundsOnStandardAndLargeFixtures
```

Behavior change covered by existing tests (no edit): every test that builds
a `WorkspaceShellState` with fonts now registers them asynchronously
(`testProjectFontEditsAreUndoableAndFontBytesSurviveSaveAndReopen`,
`testMediaAssetCommandsShareStateAndRecordContentFreeDiagnostics`,
`testFontAndMediaEditsRestoreFromPersistedHistory`); their fake TrueType
bytes are refused by Core Text, so no scene refresh is scheduled.

Suggested run: `SiteForgeTests/ProjectResourceTests`,
`SiteForgeTests/CanvasTextRenderingTests`, `SiteForgeTests/CanvasRendererTests`.

## Suggested first checks for Codex

1. `ProjectFontCanvasRegistration.retain` / `release` / `userCount`:
   `OSAllocatedUnfairLock<[String: Int]>.withLock` takes a `@Sendable
   (inout State) throws -> R` closure; the closures call the static
   `register` / `fileURL` without `Self.` and return `Bool`/`Int`. Needs
   `import os` (added) and macOS 13+.
2. `actor ProjectFontCanvasSession`: `deinit` reads `retained`;
   `for (hash, format) in retained where !wanted.contains(hash) { retained[hash] = nil … }`;
   `try? ProjectResourceIndex.decode(from:)` flattened to an optional.
3. `WorkspaceShellState.registerProjectFontsForCanvas(_:)`: the task chain
   (`await previous?.value`, `guard await session.update(…) else { return }`,
   `self?.scheduleScenePreparation()`) and its two call sites (init end and
   the document sink) after the `refreshScene:` parameter was removed.
4. `FontImportWorker.prepare`: `throw cond ? FontImportError.unreadableWOFF2 : FontImportError.corrupt`,
   and that `CTFontManagerCreateFontDescriptorFromData` returns nil for the
   64-byte WOFF2 header fixture.
5. `CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)`.
6. `SVGAccessibleNameRow.loadTitle()`: `Task.detached { bytes.flatMap { try? SVGAssetSanitizer.sanitize($0).report.title } }.value`
   is `String?`; and the Image Inspector `if image.applicableCount == 1, let altText = image.altText, let decorative = image.decorative, let asset = …, asset.format == .svg`
   inside the long Inspector `VStack` (type-check time).
7. Performance test: `header[0...3] = [0x77, 0x4F, 0x46, 0x32]` (ArraySlice
   assignment), the explicitly typed `[(String, PropertyValue)]` literals,
   `try clock.measure { try document.validate() … }`, and that a 10,001-node
   page validates within 120 s.
8. Items from the lane RB list that remain unverified without a compiler:
   `SVGSanitizerParserDelegate` conformance, `NSImage(data:)` SVG decoding,
   root `.sheet` chain length in `WorkspaceShellView`.

## Out of area (seen, not fixed)

- `StaticAssetManifestEmitter.emit` (lane H) writes only image entries to
  `assets.manifest.txt`; fonts and media written by the build are not listed
  (the Static Release `StaticOutputManifest` covers every binary file).
- Lane RB reported that `ProjectComparer.compare` can add both "Languages"
  and "Site languages" when localization differs (lane E); not re-verified.

## Write problems

- The first `edit()` of `SiteForge/ProjectResources.swift` exceeded the 65 s
  default sandbox timeout while waiting for the 15 s file gap; the worker
  finished the write in the background (one ledger line, 19:27:13). The
  retry then failed its first anchor (already applied) and wrote nothing.
  All later writes used a 240 s timeout.
- The PC went offline for a few minutes around 19:44 EST; after it
  reconnected every edit was re-read and `check([...]) == []` passed again.
- No `ICloudRenameError`, no `foreign_changes(30)` hits,
  `icloud_duplicates() == []`.
