# Lane V14d review — whole-tree enum exhaustiveness, symbol/label checks, copy paths, localized and collection output (2026-11-26)

Owner tag `lane-V14d`. Restore point before: `RP-2026-11-26-V14` (phase-1 result); lane V baseline `RP-2026-11-26-V00`;
pre-lane baseline `RP-2026-11-26-11`. Verification by reading only (no Swift toolchain, git or browser on the PC).

## Scope

Manifest item 9 (cross-tree checks no single lane did):

1. Every `switch` over every enum any lane extended is exhaustive across `SiteForge/` and `Tests/`.
2. `review/symcheck.py` and `review/labelcheck.py` re-run with BASE = `RP-2026-11-26-V00` over all lines added since.
3. Duplicate test method names per class (classes and their extensions).
4. New node properties storing NodeID / PageID / variable IDs remapped, or deliberately kept, in all six copy paths.
5. Every new output feature (structured data, hashed runtime, bound text, media, fonts) works in every language tree and
   on collection item/list pages.
6. `StaticBuildCompiler` exports everything the output references.

Reports read (only the parts about these checks): LANE-V02..V13, V12b, V16, V17, V18 "Out-of-area", "Cross-lane",
"Suggested first checks", "Remaining work" sections, and V18's C6 copy-path rule.

Files changed: `Tests/SiteForgeTests/ProjectResourceTests.swift` (2 tests extended), `SiteForge/CanvasRendererCore.swift`
(one stale doc comment). Scratch copies of the adapted checkers are in
`_quick-scratch/review/V14d/` (`symcheck.py`, `labelcheck.py`, `swchk.py`, `added_lines.json`).

## Item 1 — enum exhaustiveness (whole tree)

Findings
- Enum case sets were diffed against `RP-2026-11-26-11` and `RP-2026-11-26-V00`. Extended since the pre-lane baseline:
  `CommandName`/`DocumentCommand` (+`setCollections`, `setFontAssets`, `setLocalization`, `setMediaAssets`),
  `ModelValidationError` (+10), `CanonicalInteraction.Trigger` (+6 key-press triggers, V18), `DecorativeEffectEdit` (+6),
  `ProjectPreferencesEdit` (+`build`), `ProjectPreferencesError`, `ImageAssetFormat` (+`svg`), `ImageImportError`,
  `FluidValueCommandError`, `LifecycleBackendFault`, `LifecycleReadOutcome`, `BuildSettingID`, `StaticBuildRepairAction`,
  `ValueTraceStep.Source` (+`layout`), `CollectionImportError`, `ComponentLibraryError` (27 cases), `FontImportError`,
  CommandKernel `Operation` (coalesce/jump/trim), plus ~90 new enums.
- New checker `swchk.py`: every `switch` in all 75 Swift files (42 app, 33 test) is parsed (top-level `case` patterns,
  multi-line enum case declarations handled); for each switch without `default` the set of matched case names is compared
  with every enum whose cases contain it. Result: **627 default-less switches, 0 non-exhaustive.** The 12 switches with
  no matching enum were all checked by hand: they are parse artifacts (`if case` inside a case body, `.some(...)`/`.none`
  over an Optional, SwiftUI `HoverPhase`, `UTType` string switches). The 7 tuple switches were checked by hand and are
  exhaustive (`StaticOutputFeature × StaticBrowserTarget`: all 16 pairs; `(before, after)` / `(minWidth, maxWidth)`
  optional pairs: all 4; `(setting, PropertyValue)`: PropertyValue has exactly string/number/boolean).
- `allCases`-based test expectations: none over an extended enum (only `CanonicalSizingMode`, `ShellRegion`, `CanvasTool`,
  `InspectorTab`, `ElementCatalogItem`, `ProjectPreferenceID`, `SettingsDestination`, ... — unchanged).
- Feature flags are string IDs in `FeatureFlagRegistry` (no `FeatureFlagID` enum exists); coverage is lane V06's.
- Key-press triggers end to end: `Trigger.keyboardKey` (exhaustive), the runtime key map
  (`'key-enter': 'Enter'` ... `'key-arrow-right'`), the keyboard-reachability finding and Inspector warning all use it.
- Re-run at the end of this lane (after the other V14 lanes' writes): still 627 / 0.

Fixes: none needed.

## Item 2 — symcheck / labelcheck (BASE = RP-2026-11-26-V00)

- `symcheck`: 30 files changed since V00, 7,768 added lines; 14 identifiers not declared in the tree, all valid:
  CoreText `CTFontManagerUnregisterFontsForURL`, `os.OSAllocatedUnfairLock` (target macOS 14.0; `import os` present),
  stdlib `Mirror`/`displayStyle`/`Character.isNewline`, SwiftUI `_issues = State(initialValue:)`, `UTType.commaSeparatedText`
  (now in `LaunchExperience.NativeCollectionImportOpenPanel`, `import UniformTypeIdentifiers` present) and locals declared in
  multi-name `let a = …, b = …` lines.
- `labelcheck`: 2,796 calls in added lines; 33 reported mismatches, all Foundation/SwiftUI/stdlib overloads
  (`range(of:options:)`, `frame(maxWidth:alignment:)`, `merge(_:uniquingKeysWith:)` with trailing closure, …) or parser
  artifacts (one-line `struct File { let path: String; let contents: String }` and `StaticSEOMetadata` memberwise inits,
  which do take all their labels in declaration order; `case .section(let pageID, _)?` pattern).
- Test string expectations in all test lines added since V00 were matched against the app source: every literal ≥ 14
  characters is either in the source, built by interpolation there (e.g. `"Computed by \(source)"`,
  `"\(missing) value(s) are not translated yet…"`, `"at characters \(start + 1) to \(end)"`), a fixture value, or an
  assertion message. `interaction-container-flat` is used only in negative `hasPrefix` guards: that code existed at V00 and
  was removed when V09 built `FlatContainerOutput`, so the guard is a deliberate regression check.

Fixes: none needed.

## Item 3 — duplicate test method names

Every member `func` of every test class/struct/enum and its extensions (1,697 members, 1,321 `test…` methods in 31
classes) grouped by type name and label signature: **0 duplicates**. (Repeated helper names such as `node(_:)` or
`prepare(_:_:)` are local functions inside different test bodies, which Swift allows.)

## Item 4 — ID-storing node properties in the six copy paths

- `interactions` (Trigger/Action targets and Go To Page): `CanonicalEventGraph.remappingTargets` is called in all six
  paths plus collection list copies — `ClipboardTransfer` paste (node + page reference maps),
  `CanonicalPageGraphClone.prepare` in CommandKernel (page duplicate, `[page.id: destinationPageID]`),
  `ComponentDefinitionGraphCopy.remap` (definition graph copy, merged node/page reference maps), Create Component and slot
  contents in TransformModel (`nodeMap: ids`), `InsertionModel.expand` (component expansion, `freshIdentity: false`,
  `[definition.id: pageID]`), `CollectionLists.expand` for list copies (`slot > 0`, `freshIdentity: false`).
  Key-press triggers are ordinary interactions, so they follow.
- `state.v1.text` (V18 text binding), `state.v1.visibleWhen` and an action's `variable`: they store a page-variable UUID,
  never a NodeID/PageID. Variables are page-scoped and travel with the page root in page duplicate, so the copy stays valid;
  every path copies the property verbatim (none filters the `state.` namespace). A paste to another page keeps the reference
  (never matched by name); the Inspector shows `CanonicalTextBinding.missingStatus` and Check Website reports
  `state-text-binding-missing`. Deliberately kept, as documented in LANE-V18 "Copies".
- `overlay.v1.*`, `motion.v1.*`, container-query rules (by container *name*), media playback (asset IDs, document level,
  dropped on paste when missing via `CanonicalMediaPlayback.keepingAvailable`): no NodeID/PageID inside.
- Collection templates, lists and bindings store page/node IDs in the collection record, not on nodes; a duplicated page is
  an ordinary page (as LANE-V10 states). Nothing to remap.

Fixes: none needed.

## Item 5 — output features in every language tree and on collection item/list pages

Read in `MultiPageStaticBuildPlanner.plan` (per-language loop over `CollectionTemplates.outputPages(passPages, …)`):
- Bound text: `CanonicalTextBinding.outputPage(entry.page)` runs on every written page after translations and collection
  items (rule "binding wins" per LANE-V18). Tested for item pages and the French tree (TransformModelTests).
- Structured data: `language.route(page.route)`, `siteRoot: language.routePrefix + "/"`, home only on list page 1, none on
  Not Found. Tested (`CanvasRendererTests/testStructuredDataFollowsEveryLanguageTreeAndCollectionItemPages`).
- Hashed runtime: `StaticRuntimeBundle.page` uses the planner's own folder-prefix formula; tested with `posts/hello.html`
  and `fr/posts/hello.html`.
- Media and posters: ` src="assets/` and ` poster="assets/` are rewritten to the page folder for every page in a folder
  (language tree, item page, later list page, nested route); `<source>` and `<track>` match ` src="`. Was tested only for
  a nested route — **French-tree assertions added** (below).
- Fonts: `@font-face` lives in the root `styles.css` (`url("assets/…")` relative to it); pages link it with the folder
  prefix. Was tested only at the root — **French-tree assertions added**.
- The generator writes no `style="…"` attributes (only the reference audit reads them, for custom code), so the LANE-V10
  cross-lane note about root-relative `url(assets/…)` in style attributes cannot occur for generated output.

## Item 6 — the compiler exports what the output references

`StaticBuildCompiler.compile` exports images referenced by website nodes, item pages and list copies
(`CollectionTemplates.outputPages … itemID != nil || listPageNumber != nil`), images only a translation shows
(`SiteLanguageOutput.translatedAssetIDs`), favicon and social image; posters are the Image's own asset; media via
`ProjectMediaOutput.exportCandidates(nodes: outputNodes, …)`; fonts via `ProjectFontOutput.exportCandidates`. Each runtime
file is written exactly when a page links it (`needsEffectsRuntime` / navigation / motion / events match the tag conditions).
`assets.manifest.txt` now lists images, fonts and media (the LANE-V08 note is already resolved in the tree).

## Fixes

| File | Symbol | Defect | Fix |
|---|---|---|---|
| `Tests/SiteForgeTests/ProjectResourceTests.swift` | `testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound` | No test showed video, poster and captions resolving in a language tree (OD-038 "every new output feature keeps working in every language tree"); only a nested route was covered. | Builds the same media fixture with an English + French localization and asserts `fr/index.html` uses `poster="../assets/…png"`, `<source src="../assets/…mp4"`, `<track kind="captions" src="../assets/…vtt"`, writes the same binary files as the single-language build, and has no `output-reference-unresolved` finding. |
| `Tests/SiteForgeTests/ProjectResourceTests.swift` | `testProjectFontsExportOnlyWithDeclaredWebRightsAndUseFallbackStacks` | Project-font output was tested only at the site root. | French tree: `fr/index.html` contains `<link rel="stylesheet" href="../styles.css">`, the face is written once (`["assets/<hash>.woff2"]`), `@font-face` stays `url("assets/<hash>.woff2")` relative to the root stylesheet, no `output-reference-unresolved`. |
| `SiteForge/CanvasRendererCore.swift` | `StaticBrowserTarget` doc comment | Said "OD-121, open; recommended default in use"; the owner approved OD-121 at 8:00 PM. | "OD-121, approved 2026-11-26; its recommended default". Comment only. |

Defects found: 3 (2 test-coverage gaps for item 5, 1 stale comment). Fixed: 3. `check()` returned [] after each edit;
every changed region was re-read against the declarations (`SiteLocalizationEditing.start(code:name:)`,
`addLocale(code:name:to:) throws -> SiteLocale` — result discarded with `_ =`, `CanonicalDocument.localization`,
the tests' own `compile`/`css` helpers, `StaticBuildCompilation.plan/findings`). `SiteLanguageOutput.findings` adds only
warnings (`translation-missing`, `language-alternates-need-site-url`), so the plan is still produced.
`foreign_changes(30)` was [] before the first write and at every later check; `icloud_duplicates()` stayed [].

## New/changed test selectors

- `SiteForgeTests/ProjectResourceTests/testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound` (extended)
- `SiteForgeTests/ProjectResourceTests/testProjectFontsExportOnlyWithDeclaredWebRightsAndUseFallbackStacks` (extended)

## Requirement / check table

| Check | Status | Evidence |
|---|---|---|
| Exhaustive switches over extended enums (app + tests) | Met | `swchk.py`: 627 default-less switches, 0 missing cases; 7 tuple switches by hand |
| symcheck since V00 | Met | 14 identifiers, all system APIs or locals |
| labelcheck since V00 | Met | 33 reports, all overloads or parser artifacts |
| Duplicate test names per class | Met | 0 of 1,697 members |
| ID-storing properties in six copy paths | Met | interactions remapped in 6 paths + list copies; variable IDs deliberately kept (page-scoped) |
| Output features in language trees and item/list pages | Met | code read + tests (bound text, structured data, runtime bundle, media and fonts now in `fr/`) |
| Compiler exports everything referenced | Met | item/list/translation images, posters, media, fonts, runtimes, manifest |

## Remaining work (blocked only)

- None in this item that a PC can do. Running the two extended tests needs a Mac with Xcode.

## Out-of-area observations (not changed)

- Long-standing (present at `RP-2026-11-25-01`, before every lane): on a page without page flow or automatic sizing
  (`!page.usesConnectedOutput`), `MultiPageStaticBuildPlanner.plan` links `styles.css` only when the page uses effects,
  glass, motion, interactions or a project font, although `StaticLayoutOutputEmitter` writes that page's layout rules (and
  `StaticContainerQueryOutputEmitter` its container-query rules) into `styles.css`. `CommandKernelTests/
  testMultiPageStaticBuildPlanIncludesTypedLayoutStylesheet` checks only the stylesheet, not the link. Not changed (exact
  HTML expectations depend on it); Codex should confirm whether legacy static-layout pages are meant to load the stylesheet.

## Intended doc changes for the coordinator (lane V15)

- Plan / activity entry for lane V14d: "done by lane V14d (unverified): whole-tree checks — 627 default-less switches
  exhaustive, symcheck/labelcheck clean since V00, no duplicate test names, ID-storing properties handled in all six copy
  paths, output features verified in language trees and item/list pages; media and project-font output now tested in the
  French tree (ProjectResourceTests)."
- docs/TESTING.md (if it lists ProjectResourceTests selectors): no new selectors, the two named tests were extended.
- OD-121 implementation status already approved (8:00 PM); the code comment now matches.

## Suggested first checks for Codex

1. `ProjectResourceTests/testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound`: the French block expects
   `fr/index.html` (home route, default language at the root) and the poster rewrite `" poster=\"../assets/…"` in the
   French tree; also `Set(mediaFrenchBuild.plan?.binaryFiles.map(\.path) ?? []) == Set(video.plan?.binaryFiles…)`.
2. `ProjectResourceTests/testProjectFontsExportOnlyWithDeclaredWebRightsAndUseFallbackStacks`: exact link text
   `<link rel="stylesheet" href="../styles.css">` (format from `stylesheetLink` in the planner).
3. `ProjectFontCanvasRegistration.retain/release`: multi-statement closures passed to
   `OSAllocatedUnfairLock<[String: Int]>.withLock` (`@Sendable`, result type inferred) calling non-isolated statics.
4. `DecorativeEffects.swift` `EventGraphOutput.findings`: `(try? CanonicalTextBinding.resolve(node)) ?? nil` (valid, flattened
   by SE-0230; redundant `?? nil`).
5. The static-layout stylesheet link question above.
