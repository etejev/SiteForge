# Lane V14e review — Codex first checks, unfixed out-of-area issues, consolidated Codex checklist (2026-11-26)

Owner tag `lane-V14e`. Cross-tree verifier of the whole lane V candidate (phase 2, parallel with V14a–V14d).
Restore point before: RP-2026-11-26-V14 (state after phase 1); lane V baseline RP-2026-11-26-V00.

## Scope

- Item 11: every "Suggested first checks for Codex" expression in LANE-V01…V13, V12b, V16, V17, V18 (and V14a–d,
  re-read at the end), read against the current declarations; fix what is wrong now.
- Item 12: every out-of-area issue in any lane V report that no later lane fixed: fix inside an approved decision,
  or list precisely.
- Extra: one consolidated, deduplicated "Suggested first checks for Codex" list across all lane V reports, ordered by
  compile risk (section "Consolidated Codex checklist" below) — the Codex handoff checklist.
- Method (no Swift toolchain, git, subprocess or browser on the PC): targeted reads of every named declaration and its
  call sites; a label check (call labels vs declarations, `_quick-scratch\review\labelcheck.py`) and an undeclared
  identifier check (`symcheck.py`) over all 7,079 lines lane V added since RP-2026-11-26-V00 (29 Swift files); and the
  repository gate scripts that CI runs before compiling (`scripts/check-repository.sh`), executed in-process on the PC
  where they do not need `swiftc`, `git` or the Xcode project.

Files changed: `SiteForge/LaunchExperience.swift`, `SiteForge/WorkspaceShellView.swift`, `SiteForge/CanvasRendererCore.swift`, `Tests/SiteForgeTests/CommandKernelTests.swift`, `Tests/SiteForgeTests/CanvasRendererTests.swift`.

## Item 12 — out-of-area issues (status of every one)

| Source | Issue | Status now | Evidence / action |
|---|---|---|---|
| V02 | Library export with reusable styles gives a generic error | Fixed by V07 | `ComponentLibraryError.usesReusableStyle` (ProjectPackage.swift, thrown in `ComponentLibraries.exporting`), `ProjectPackageTests` refusal assertions |
| V03 | `ContainerQueryEdit.diagnosticOperation` never recorded | Fixed (V04) | `WorkspaceShellModel` records it via `recordResponsiveAuthoringDiagnostic("SF-0605-002", operation: edit.diagnosticOperation, …)` |
| V03 | OD-142 variant-override translations | Approved, not built (after-Codex queue) | Coordinator item, no code |
| V04 | Desktop/breakpoint-hidden text may show in export | Fixed by V14a (fixes 1–4) + V14e fix 2 | `StaticVisibilityOutputEmitter`, `ConnectedPageOutput.hiddenRule`, stylesheet order; static pages now link the stylesheet that carries the rules |
| V04 | Fixed/sticky offset in Preview and audit (`worldOrigin`) | Fixed by V14a (fixes 5–6) | `LocalPreviewRuntimeCompiler.compile`, `ResponsiveAuditRunner.run` use `worldOrigin (0, 0)` |
| V05 | Delete with Uses does not detach collection or translation image uses | Not a defect — listed | Refusal is the documented design: ADR-0087 comment in `ImageAssetReference.references` ("delete is refused while one exists"); `CommandRegistry.availability(.removeImageAsset)` gives the specific reasons ("A translation uses this image…", "Collection items use this image…"), announced by `deleteImageAssetAndUses`. Clearing a collection image field can break a required field, so extending Detach needs an owner decision (proposed below). |
| V05 | Orphaned-language translations count as uses | Decided by lanes E/V11 ("still stored") | No change |
| V05 | Value-source Clear while editing a variant | Manual check for Codex | Listed in checklist T6 |
| V06 | 10 whole-document asserts after Undo in PersistedHistoryTests | Fixed by V17; re-scanned by V14c (0 left) | — |
| V06 | Custom code can never pass Static Release under `warningsBlockRelease` | Fixed by V17 (reviewed-code digest, ADR in V17) | — |
| V06 | Plan E2 hashed runtime blocked | Built by V12b | — |
| V08 | `assets.manifest.txt` lists only images | Fixed by V12b | `StaticAssetManifestEmitter.emit(… fontPaths:mediaPaths:)` |
| V08 | `ProjectComparer.compare` may add both "Languages" and "Site languages" | Not reproducible now | `ProjectComparer.compare` names localization once ("Languages"); "Site languages" exists only as a feature-flag title and an accessibility label; `sameUncomparedContent` aligns `localization` |
| V09/V18 | `docs/REQUIREMENT_EVIDENCE.json` lists only the Flow tooling files | Doc item for V15 | The index is a results receipt; `check-traceability.py` passes (441 records). Add the interaction harness only with a run receipt. |
| V09 | `select-test-scope.py` maps `Tests/Tooling/*` to explicit selectors | Existing behaviour | No change |
| V16 | Hug-width container fixture fails `validate()` | Fixed by V14a (item 3) | Test now expects the validation refusal (`XCTAssertThrowsError … ModelValidationError`) |
| V17 | `release-policy-warnings` repair text | No change needed | "Repair the warnings, …" stays accurate: the custom code warning row carries its own Review Code button (`StaticBuildRepairAction.acknowledgeCustomCode`) |
| V18 | `docs/TESTING.md` lacks the interaction harness and new selectors | Doc item for V15 | Listed below |
| V14a | Container queries on static-layout pages never match in a browser (flat output, no container ancestor) | Listed — proposed OD by V14a | Needs nested static output or a Check Website "canvas only" finding; not inside a lane V decision |
| V14a | Container-query Show writes a plain `display: block` (V04 design) | Listed — proposed default by V14a | Changes an asserted V04 behaviour (`testContainerQueryExportHidesTextAboveItsDisplayRule`); needs the owner/Codex decision |
| V14b | View ▸ Move Selection Right 1 px uses ⌃→ (macOS Mission Control "Move right a space" by default) | Listed for Codex — not changed | Shortcut choice is a UX decision (central command registry is still an open OD); the UI test passes because XCUITest injects the event. Suggest ⌃⌥→ or plain arrow nudging. |
| V14b | Canvas `keyDown` treats Return with any modifiers as begin text editing, so a disabled ⌥⌘Return / ⇧⌥⌘Return falls through to text editing | Listed — harmless, older behaviour | No change |
| V14d | Static-layout pages (`!page.usesConnectedOutput`) linked `styles.css` only when they used flow, motion, interactions, effects, glass or a project font, though `StaticLayoutOutputEmitter` (positions, `display`), typography, fills, box styles, container queries and V14a's new `StaticVisibilityOutputEmitter` hide rules for those pages are written there (present since RP-2026-11-25-01) | **Fixed by V14e (fix 2)** | Without the link a plain static page opened in a browser or Local Preview had no positions and showed every hidden object, so V14a's static-layout hide fix (and the V04 hidden-content finding) could not take effect. No test asserted the missing link (scanned every `stylesheet`/`<head>`/`</head>`/`styles.css` expectation under `Tests/`). |

## Fixes

| # | File | Symbol | Defect | Fix |
|---|---|---|---|---|
| 1 | `SiteForge/WorkspaceShellView.swift`, `SiteForge/LaunchExperience.swift` | `CollectionsEditorView.chooseImportFile()`, `ComponentLibrariesSheet.chooseFile(message:)`; new `NativeCollectionImportOpenPanel.chooseFile()`, `NativeComponentLibraryOpenPanel.chooseFile(message:)` | The repository gate `scripts/check-architecture-boundaries.py` requires `NSOpenPanel()` to appear only in `LaunchExperience.swift` (`open_panel_owners != ["SiteForge/LaunchExperience.swift"]` → fail). Lane V added two panels in `WorkspaceShellView.swift` (collection CSV/JSON import, component library file), so `scripts/check-repository.sh` and CI would fail before compiling. | Moved both panels into `@MainActor` enums in `LaunchExperience.swift` beside `NativeImageOpenPanel`/`NativeFontOpenPanel`/`NativeMediaOpenPanel`, with identical content types, options and messages; the two call sites now call them (`guard let url = … else { return }` / `return nil`). Behaviour unchanged; `WorkspaceShellView.swift` has no `NSOpenPanel` left. |
| 2 | `SiteForge/CanvasRendererCore.swift` | `MultiPageStaticBuildPlanner.plan` (`stylesheetLink`, new `var linksStylesheet`, `styles.css` write) | A static-layout page without flow, motion, interactions, effects, glass or a project font got no `<link rel="stylesheet">`, although its layout, typography, fill, box-style, container-query and hide rules are only in `styles.css` (V14d out-of-area finding; it also made V14a's static-layout hide fix ineffective in a browser). | `stylesheetLink` now also holds for every page with objects (`!page.nodes.isEmpty || …`, the existing conditions unchanged); `linksStylesheet` records that some page links it, and `styles.css` is written when the stylesheet is non-empty **or** a page links it, so the link never dangles (`StaticOutputReferenceAudit`). Connected/flow pages and pages that already linked are unchanged; a page with no objects still has no link. |

`check([…]) == []` after each edit; every changed region re-read against the declarations (`DocumentPage.nodes`, `StaticOutputReferenceAudit.unresolved(in: LocalStaticBuildPlan)`, `MultiPageStaticBuildPlanner.plan(document:…) throws -> LocalStaticBuildPlan`).

## Item 11 — first checks re-read against current declarations

Every check names code that exists now with the stated shape; none was wrong against the current tree, so no code
change was needed for item 11 beyond fix 1 (found by running the gate scripts). Read in full (declaration + every call
site): V01 1–3 (`ProjectFileCapacity.opened` — `encodedPages(of:) throws -> [Data]` is a static method of the
`ProjectPackageStore` actor, so the expression is `Int?`; `LoadedProject` label order; `ProjectSettingsStore.documentChanged`
private statics and `record(_:started:failure:preferences:)`), V02 1–3 (all eight slot cases exist in `ComponentEdit`;
`recordComponentOperation(…, slotOperation:)`; `performComponentEdit(_:draftIdentity:successAnnouncement:)`), V03 1
(`prepare(…, forCommit: Bool = true)`, all 4 callers), V06 5 (`PageWebsiteMetadata.init` with all 5 labels in the page
duplicate), V07 1 (`CanonicalLinkTarget.resolve` is non-optional `throws`; `.section(pageID:nodeID:)` matched as
`.section(let pageID, _)?`), V08 1–2 (`withLock` closures capture only Sendable values; deinit reads a Sendable
dictionary), V10 4 (`Text.foregroundStyle` returning `Text`, macOS 14 — the tree already uses macOS 14 SwiftUI APIs),
V11 (`BrowserPreviewController.build` has `localeID` and `isDocumentCurrent` defaulted before the trailing `isCurrent`;
all 14 calls fit), V12 5 (`StaticBuildCompilation` memberwise init with three defaulted `var`s; every `.init` call passes
the six leading values), V13 2–4 (`coalescingNow: () -> Date` is not `@Sendable`, so capturing `var now` compiles;
`takeMigrationRefusal(for:)` is an actor method awaited in the catch; `LifecycleBackendFault` lost automatic `Equatable`
by gaining a payload — no `==`/`XCTAssertEqual` on it anywhere), V16 3 (`jsonEscape` scalar switch). Label check:
2,696 calls in lane V lines checked; the only reports are Foundation/SwiftUI/stdlib methods and two memberwise structs
declared with `;` on one line (`StaticSEOMetadata`, `LocalStaticBuildPlan.File`), both verified by hand. Identifier
check: 14 names flagged, all declared (comma declarations, `Mirror`, `State` underscore, UTType members).

Gate scripts run on the PC (current tree): `check-traceability.py` passed (441 records); `check-authoring-runway.py`,
`check-layout-foundation-evidence.py`, `check-canvas-renderer-evidence.py`, `check-selection-model-evidence.py` passed;
`check-architecture-boundaries.py` text checks passed after fix 1 (its `swiftc` slices and `project.pbxproj` checks
cannot run here — the Xcode project is not in the iCloud tree on this PC); forbidden-import scan of the 19 headless slice
files clean and no slice file names a type declared only outside the slice; UI discovery vs `scripts/ci-ui-timings.txt`:
180 = 180, no missing/unknown/duplicate; core test method names unique per class (1,140 tests, 30 classes); empty
TODO/FIXME markers: 0; credential/artifact scan (same patterns as `scan-repository-secrets.py`): 0 findings in 5,922 files.

## Proposed OD (coordinator assigns the number; not approved)

Delete with Uses for images used only by translations or collection items (SF-0806/SF-0807, OD-035, OD-038).
- Recommended default: keep the current specific refusal (ADR-0087): Delete with Uses detaches Image objects, image
  fills, component media values, the favicon and the social image, and refuses with a specific reason while a
  translation or a collection item shows the image; Replace Everywhere already retargets both.
- Alternative: Detach also removes translated images (falls back to the element's own image) and clears collection
  image fields, refusing only when a cleared field is required.
- Tradeoff: the alternative removes one manual step but silently changes translated pages and collection content.
- Safe temporary assumption: current behaviour.

## New/changed test selectors

- `SiteForgeTests/CommandKernelTests/testMultiPageStaticBuildPlanIncludesTypedLayoutStylesheet` — strengthened (fix 2):
  `index.html` contains `<link rel="stylesheet" href="styles.css">` and `StaticOutputReferenceAudit.unresolved(in: plan) == [:]`.
- `SiteForgeTests/CanvasRendererTests/testStaticLayoutExportHidesObjectsContentsAndTextOnlyWhereHidden` (lane V14a's test) —
  strengthened (fix 2): the page links `styles.css`, so its hide rules reach the page.
- Fix 1 has no unit test (a modal panel); it is covered by the repository gate `scripts/check-architecture-boundaries.py`.

## Remaining work (blocked only)

- Compile and run on a Mac: the `swiftc -typecheck` headless slices of `check-architecture-boundaries.py` and its
  `project.pbxproj` checks (the Xcode project is not on this PC), then the full gate.
- Browser check (no browser on the PC): export a plain static-layout page (no page flow) and open it — objects are positioned
  and objects hidden at the shown width stay hidden (fix 2 with V14a's hide rules); also in Local Preview.

## Intended doc changes for the coordinator (V15)

- `docs/TESTING.md` / `docs/REQUIREMENT_EVIDENCE.json`: add the interaction browser harness
  (`Tests/Tooling/interaction_runtime_browser.py`, `test_interaction_runtime_browser.py`, 11 cases) and lane V's new
  selectors only together with a recorded run (the evidence index is a results receipt).
- Activity entry: "Lane V14e: static-layout pages now link `styles.css` whenever they have objects (their layout, typography and hide rules were unreachable); moved the collection-import and component-library file panels into
  `LaunchExperience.swift` (`NativeCollectionImportOpenPanel`, `NativeComponentLibraryOpenPanel`) so
  `check-architecture-boundaries.py` (single `NSOpenPanel` owner) passes; all lane V first checks and out-of-area issues
  re-checked; consolidated Codex checklist in LANE-V14e."
- Record the proposed OD above as Open with its recommended default.

## Consolidated Codex checklist
Deduplicated across LANE-V01…V13, V12b, V14a–V14e, V16–V18 (V14a–V14d re-read at 9:45 PM after they were written) (source lanes in brackets). Ordered by risk: T0 fails CI
before compiling; T1–T5 are compile risks (most likely first); T6–T8 are runtime/test-expectation checks. Items marked
"read OK (V14e)" were re-read against the current declarations in this lane and look right; they still need a compiler.

### T0 — repository gate (`scripts/check-repository.sh`, before any build)
1. `check-architecture-boundaries.py`: single `NSOpenPanel()` owner `LaunchExperience.swift` (fixed by V14e fix 1) and
   the 12 headless `xcrun swiftc -typecheck -swift-version 6` slices. Lane V added to slice files: `ProjectResources.swift`
   (`import os`, `OSAllocatedUnfairLock`, CoreText registration), `CanvasRendererCore.swift`
   (`StaticRuntimeBundle`, `StaticSEOEmitter.structuredData/jsonEscape`, `StaticBuildProfileComparison`,
   `StaticBrowserSupportReport`), `DecorativeEffects.swift` (`EventGraphOutput.loopMembers`, `CanonicalTextBinding`),
   `InsertionModel.swift` (`CanonicalContainerQueries.contentInset/evaluated`), `DocumentModel.swift`, `TransformModel.swift`,
   `CommandKernel.swift`, `ProjectPackage.swift`. V14e scan: no forbidden import, no slice file names a type declared only
   outside the slice. [V14e]
2. `check-traceability.py` (passed on PC, 441 records), `select-test-scope.py --self-test`, secret scan (0 findings on PC),
   empty TODO/FIXME markers (0). [V14e]
3. `ci-test-accounting.py` UI discovery vs `scripts/ci-ui-timings.txt`: 180 selectors = 180 timing lines on PC; a UI
   journey added later needs a measured timing line (why V12/V12b added no UI test). [V14e, V12b]

### T1 — Swift 6 isolation / Sendable (most likely compile errors)
4. `ProjectFontCanvasRegistration.retain/release/userCount`: `OSAllocatedUnfairLock<[String: Int]>.withLock` takes a
   `@Sendable (inout State) throws -> R`; closures call static `register`/`fileURL` unqualified and return `Bool`/`Int`
   (read OK (V14e)); `actor ProjectFontCanvasSession` `deinit` reads `retained` and calls the static `release`;
   `try? ProjectResourceIndex.decode(from:)` flattened. [V08 1–2, 5, V14d 3]
5. `WorkspaceShellState.registerProjectFontsForCanvas(_:)`: `await previous?.value`, `guard await session.update(…) else
   { return }`, `self?.scheduleScenePreparation()`; its two call sites after `refreshScene:` was removed. [V08 3]
6. `CollectionsEditorView` (top of `WorkspaceShellView.swift`): `_issues` set in `init`; `.onChange(of: draft) { _, collections in }`;
   `.task(id: request)` with private `ImportRequest: Equatable`; `Task { @MainActor in await readImportFile(…) }`;
   `Task.detached(priority:) { Result { try CollectionImport.read(url) } }.value` with Sendable captures (`URL`,
   `CollectionImportTable`, `CollectionImportMapping`, `ContentCollection`, `[ImageAsset]`). [V10 1]
7. `StaticExportDiagnostic(target:documentID:plan:duration:failure:)` in the `Task` closures of
   `WorkspaceShellState.writeStaticBuild` and `BrowserPreviewController.export` (`started.duration(to: .now)`);
   `startStaticBuildPreflight`: `let started = ContinuousClock.now` captured, `staticBuildChanges` /
   `lastStaticOutputDiagnostic` with implicit self after `guard let self`. [V06 1, V12 8]
8. `DocumentLifecycle` `loadAndAdopt` read task: `await backend.takeMigrationRefusal(for: identity.id)` inside
   `catch let error as DocumentLifecycleFailure` of a main-actor `Task<LifecycleReadOutcome, Never>`; outcome switch
   handles `.refused`; `LifecycleBackendFault` (Sendable, payload `migrationRefusal`, no longer auto-Equatable — no `==`
   uses, read OK (V14e)). `restoreMigrationOriginal()` → `prepareForWorkspaceAction(.context)` → `reloadSnapshots()` →
   `restoreSnapshot(id, keepingCurrentAs: nil)`. [V13 3–4, 10]
9. `WorkspaceScenePreparationWorker.prepare(_ incomingRequest:progress:)`: `let request = incomingRequest.displayingShownLanguage()`
   and every later `request.` use (`viewportWidth: Double` into `Double?`); `canvasLanguageStatusCache` labeled tuple
   assigned from an unlabeled tuple in a computed getter of the `@MainActor` class. [V11]
10. `reconcileVariantEditingTarget()` inside the `documentSession.$document` sink's `DispatchQueue.main.async`;
    `DocumentSession.authoringTransform` and its closure; `@Published private(set) var editingComponentID { didSet }`. [V03 4, 7]
11. `AccessibilityAnnouncementPoster.native.post` called from `VariableValueField` (isolation of the static). [V18]
12. `SVGAccessibleNameRow.loadTitle()`: `Task.detached { bytes.flatMap { try? SVGAssetSanitizer.sanitize($0).report.title } }.value`
    is `String?`. [V08 6]
13. `FeatureFlagStore` is `@MainActor`: every test using it on the main actor; `ProjectSnapshotsSheet`
    `@ObservedObject private var features = FeatureFlagStore.shared` with a custom `init(state:)`. [V14c 4, V07 4]
14. `WorkspaceShellState.pendingSnapshotComparison` optional labeled tuple and `static let variantOpenReplacementMessage`
    in the `@MainActor` class used from `ProjectSnapshotsSheet`/`ComponentLibrariesSheet`. [V07 3]
15. `InsertionModelTests.testFastStyleRepeatedFieldAdjustmentsCoalesceIntoOneUndoStep`: `var now` captured by
    `state.coalescingNow = { now }` (`() -> Date`, not `@Sendable` — read OK (V14e)) and mutated by the nested async `adjust`. [V13 2]
16. `NativeCollectionImportOpenPanel` / `NativeComponentLibraryOpenPanel` (`@MainActor`) called from SwiftUI view methods. [V14e]

### T2 — expressions, patterns, definite initialization
17. Switch expressions: `ComponentEdit.isSlotEdit` (read OK); `CanonicalComponentVariants.isEditable(_:in:)` and the
    recursive local `editsDefinition(_:)` used as `commands.contains(where: editsDefinition)`;
    `StaticOutputFeature.firstSupportedVersion(_:)` over `(self, target)` 4×4 with comments between cases;
    `let reviewNote: String = switch review { … }`; `CanonicalInteraction.Trigger.keyboardKey` with a `nil` branch. [V02 1, V03 2–3, V12 2, V17 3, V18]
18. Multi-pattern cases: `ComponentLibraries.exporting` `case .page(let pageID)? where …, .section(let pageID, _)? where …:`
    (read OK); `performSlotEdit` `case .moveSlotItem(_, let offset)` and `let announcement: String` assigned per case. [V07 1, V02 3]
19. Definite initialization: `DecorativeEffectCommandRegistry.prepare` `case .textBinding(let binding)` throwing before
    `namespace/values/kinds` are assigned; `CollectionEditing.templatePreviewProblem` (`catch let found as SiteExpressionError`
    then bare `catch`); `StaticOutputChangeSummary.init` (no read of `self` before init). [V18, V10 6, V12 4]
20. Optionals: `(try? ProjectPackageStore.encodedPages(of: document))?.map(\.count).max()` (read OK, `Int?`);
    `(try? CanonicalReusableStyleIndex(document: document))?.byID ?? [:]` and the `Set(definitions.flatMap(\.nodes)
    .flatMap(\.properties).compactMap { property -> ReusableStyleID? in … })`; `try CanonicalMotion.resolve(node)?.entrance`;
    `let zipIssue = state.staticBuildCompilation?.plan.flatMap { … }` in `InspectorActionLayout` and `controller.plan.flatMap`
    in `BrowserPreviewPanel`; `guard digest == CustomCodeReview.digest(authoringDocument.websiteMetadata)` (String vs String?);
    `XCTAssertNotEqual(CustomCodeReview.digest(moved), digest)`; `CanonicalTextBinding.outputPage` (`try? resolve(…)`). [V01 1, V07 2, V09, V06 2, V17 4, 6, V18]
21. Closures with labeled tuples / tuple comparison: `StaticRuntimeBundle.bundle` `parts.compactMap { part -> (part: String,
    javascript: String)? in … }`, `bundleText(_:)` labeled-tuple parameter, `files.filter { … }.map { file ->
    LocalStaticBuildPlan.File in … }` calling static `page(_:path:parts:bundlePath:)`; `StaticAssetManifestEmitter.emit`
    closures returning `(id: String, line: String)?`, `images + faces + files`, `.sorted { ($0.id, $0.line) < ($1.id, $1.line) }`;
    `StaticBrowserVersion: Comparable, Hashable` with custom `<` over `(major, minor)`; tuple key paths `values.map(\.key)`,
    `applied.mapValues(\.1)`; `StaticBuildProfileComparison.init` (`if let developmentFile, let releaseFile`,
    `Set(…keys).union(…keys).sorted()`). [V12b 1, 5, V12 1, 3, V04 6]
22. Nested functions mutating captured state: `EventGraphOutput.loopMembers` `enter` (captures `index`, `low`, `counter`,
    `stack`, `onStack`, `work`; `while let (node, next) = work.last`; `work[work.count - 1].next = next + 1`);
    `CanonicalContainerQueries.evaluated` `contentWidth(of:)` called from `container.flatMap { contentWidth(of: $0) }`;
    `contentInset` nested `written(_:)` inside a `guard … else`; `CustomCodeReview.digest` nested `append`;
    `StaticRuntimeBundle.page` nested `removingTags(_ text: Substring)` with `used.reduce(String(text))`;
    `CanonicalResponsiveAudit.findings` nested `shownHorizontalSpan(of:)` returning an unlabeled tuple into `(minX:, maxX:)?`. [V18, V16 1–2, V17 2, V12b 2, V04 1]
23. Loop/conditional patterns: `while case .node(let id)? = parent, let ancestor = nodes[id], …` (`NodeParent?`);
    `FlatContainerOutput.members` `while case .node(let id) = parent, seen.insert(id).inserted, let ancestor = byID[id]`;
    `ComponentDefinitionGraphCopy.remap` `if [ … ].contains(key) || SiteTranslationKey(rawValue: key)?.field == .imageAssetID,
    case .string(let raw) = value`; `ImageAssetReference.references` `for … where entry.key.field == .imageAssetID &&
    entry.property.value == .string(raw)`; `ComponentCommandRegistry.creationSourceIDs` `if case .string(let text)? = …`;
    `WorkspaceShellState.previewDesignStyle` `if case .effect = edit`; `CanonicalOverlay.resolve`
    `keys == [kindKey, dismissKey] || keys == [kindKey, dismissKey, placementKey]` (Set vs array literal). [V04 1, V09, V11, V18]
24. Literals and formatting: `StaticSEOEmitter.jsonEscape` `switch scalar` with `"\""`, `"\\"`, `"\u{2028}"` patterns and
    `String(format: "\\u%04x", scalar.value)` (read OK); `structuredData` interpolations with nested quotes;
    `FeatureFlagID` pattern `#"…+\z"#` with `.regularExpression` (ICU `\z`); `highlightedExpression`
    `Text("\(Text(verbatim: …))\(Text(verbatim: …).underline().bold().foregroundStyle(…))…")` (macOS 14 `Text.foregroundStyle`);
    `throw cond ? FontImportError.unreadableWOFF2 : FontImportError.corrupt`; `CTFontManagerUnregisterFontsForURL(url as CFURL,
    .process, nil)`; `StaticOutputCachePolicy.policy(for:)` `a != nil || StaticRuntimeBundle.isBundlePath(path) ? .immutable :
    .revalidate`; perf test `header[0...3] = [0x77, 0x4F, 0x46, 0x32]`, typed `[(String, PropertyValue)]` literals,
    `try clock.measure { try document.validate() … }`; `Set<String?>` + `.sorted(by:)` in `StaticBuildCompiler.customCodeFindings`;
    `DocumentLifecycleController.migrationRefusalText` nested `$0` in `[$0.errorDescription, $0.recoverySuggestion].compactMap { $0 }`;
    `WorkspaceShellState.designStyleFieldName(_:)` `outer.flatMap { child -> String? in … }`;
    `DocumentSession.nextUndoDescription` `undoStack.last.map { historyDescription($0) }`;
    `CollectionImport.read` `url.resourceValues(forKeys: [.fileSizeKey]).fileSize`; `CollectionImportMapping.assign`. [V16 3, V06 3, 4, V10 4–5, V08 4–5, 7, V12b 3, V13 1, 5, 7]
25. `CanonicalValueTrace.trace(…, layout: (value: Double, source: String)? = nil)` and
    `guard case .computed(let value, let source) = geometryInspectorValue(for: field)`; `ImageAssetDependencies.retarget`
    collection rewrite (`collections[c].items[i].values[v].value`); `CommandDiagnostics.recordAssetDependencyOperation`
    `assetIDs.map(\.commandTarget)` (file-private extension, same file); `WorkspaceShellState.imageAssetReferences` cache key
    `String(describing: variantEditingTarget)`. [V05 2, 4, 6, 8]

### T3 — exhaustive switches over enums lane V extended (whole tree incl. tests; V14d scope)
26. `ValueTraceStep.Source.layout(String)`: `sourceTitle`, `canClearWinner`, `WorkspaceShellState.revealValueSource`;
    `CommandExecutionError` (4 cases) in `ResponsiveAuthoringDiagnostic.category(for:)` (+ `error is WorkspaceScenePreparationError`);
    `FluidValueCommandError.containerQueryConflict` in `errorDescription` and `FluidValueDiagnosticFactory.category`;
    `LifecycleBackendFault` in `throwFault()`; `StaticBuildRepairAction` (title, hint, identifier, `applyBuildRepair`) and
    `BuildSettingID` (title, `changedSettingIDs`); `CanonicalInteraction.Trigger`; `ComponentLibraryError` (`usesReusableStyle`,
    `errorDescription`, `diagnosticCategory`); every `DocumentCommand` / `CommandName` / `FeatureFlagID` switch. [V05 1, 3, V04 3, V13 3, V17 3, V18, V07, V14d]

### T4 — call labels and memberwise inits (V14e label scan of all lane V lines: no mismatch; still compile)
27. `LoadedProject(… migration:, capacity:)`; `StaticBuildCompilation` memberwise init with three defaulted `var`s and the
    single call passing `buildSettings:profileComparison:browserSupport:`; `PageWebsiteMetadata.init(pageID:title:description:
    allowsIndexing:customCode:)` in the page duplicate; `VariableValueField` memberwise order `type, value, label, identifier,
    commit, problem` (trailing closure binds to `commit`; `nameProblem` uses `variables.indices.contains { … }`);
    `SettingsDraftNotice(appearanceDirty:canvasDirty:projectDirty:featuresDirty:)`; `PageDraft(headHTML:bodyHTML:css:)`;
    `StaticSEOMetadata` and `Groups(visibility:)` memberwise; `ComponentVariantCommandRegistry.prepare(…, forCommit:)` default;
    `refuseCanvasLanguage(_:category:localeID:startedAt:operation:)` defaulted last parameter; `BrowserPreviewController.build(
    document:pageID:package:localeID:isDocumentCurrent:isCurrent:)` with trailing `isCurrent`; `performComponentEdit(edit,
    successAnnouncement:)`; `recordComponentOperation` `requirementIDs: […] + (slotOperation ? ["SF-0903-008"] : [])`;
    `recordBuildSettings("review-custom-code", started:failure:settings:)`; `LocalBuildProfileCompiler.compile(withAssets,
    profile: otherProfile).1`; `EventGraphOutput.PageOutput.htmlAttributes` (`attributes.merging(memberAttributes) { $0 + $1 }`)
    and the planner's `attributes: events.htmlAttributes`; `SafeHTMLEmitter.emit` form branch `extraAttributes[node.id] ?? ""`;
    planner page loop `seoMetadata`, `structuredData` (`entry.listPageNumber ?? 1`), head `\(metadataHead)\(structuredData)\(alternates)…`,
    `let page = CanonicalTextBinding.outputPage(entry.page)` in the language loop. [V01 2, V12 5–6, V06 5–6, 8, V09, V11, V02 2–3, V17 4, V16 4, V18]

### T5 — SwiftUI type-check time and builder limits
28. `ComponentVariantManager` (axis `HStack` with two more `let`s), `ComponentVariantChoiceFields`,
    `.accessibilityLabel(label ?? title)` in `ComponentVariantManager.button`; Image Inspector `if image.applicableCount == 1,
    let altText = image.altText, let decorative = image.decorative, let asset = …, asset.format == .svg` inside the long Inspector
    `VStack`; `ContainerQueryValueRow.body` (`switch value` in an `HStack`, `Picker(title, selection: Binding(get:set:))`,
    `TextField`) and `addSettingMenu`; `ValueTraceInspectorView.settingRow` (`DisclosureGroup(isExpanded:) { … } label:
    { Button { … } label: { … } }`); `CollectionsEditorView` (`ForEach(Array(table.columns.enumerated()), id: \.offset)
    { column, name in }`, `Picker` tags `CollectionImportColumnTarget.field(field.id)`, `$importMapping.newItemStatus`,
    `Menu { } label: { Image(systemName: "function") }` + `.menuStyle(.borderlessButton)` + `.menuIndicator(.hidden)`);
    `CanvasLanguageBar` (`Toggle("Mirror Layout", isOn: Binding(get:set:))`, `.toggleStyle(.checkbox)`) and the extended
    visibility condition in `CanvasPlaceholderView`; `StaticBuildOutputReportsView`, `StaticBuildProfileComparisonBox`
    (`let differing = …` in a `VStack`), `StaticBuildBrowserSupportBox`; `RuntimeStateInspector.overlayControls` /
    `textBindingControls` (`.tag(CanonicalOverlay.Placement?.none)`, `foregroundStyle(missing ? SiteForgeVisualSystem.danger :
    .secondary)`); `PageInteractionsOverview` / `PageInteractionRow`; build settings view (10 direct `VStack` children,
    `@ViewBuilder private var customCodeReview`, `update { $0 = $0.keepingCustomCodeReview }`); `SiteForgeSettingsRootView`
    `features.isDirty` / `features.cancel()`; `.saveItem` CommandGroup with 15 children, `.undoRedo` Divider + Show History… (⌘Y);
    bindings `$state.isHistoryListPresented`, `$lifecycle.isMigrationDetailsPresented`; root `.sheet` chain length in
    `WorkspaceShellView`; `TextEditor` modifiers on the deployment target. [V03 6–7, V08 6, 8, V04 4, V05 5, V10 1–3, V11, V12 9,
    V18, V17 5, V06 6, 9, V13 6]

### T6 — tests most likely to fail on expectations (run these first)
29. Exact output strings: `CanvasRendererTests/testLinkedBoxStylesDrawOnCanvasAndExportIdentically` (`0.251` alpha);
    `testContainerQueryExportHidesTextAboveItsDisplayRule` (new CSS string); `testContainerQueriesMeasureTheContentBoxInsidePadding
    AndBorderLikeBrowsers` (`"<sel> { box-sizing: border-box;"`, `"<sel> { border: 2.0px solid rgba(0.0, 0.0, 0.0, 1.0); padding: 24.0px; }"`,
    connected `;padding:16.0px;`); `testStructuredDataDescribesEachPageOnlyWithASiteAddress` and
    `testStructuredDataFollowsEveryLanguageTreeAndCollectionItemPages` (exact JSON-LD, `fr/about.html`, `"url":"https://studio.example/blog/first"`);
    `testStaticReleaseWritesOneContentHashedRuntimeEveryPageReferences` (`<p>Home</p><script …></script></body>`,
    `<body><script src="../…" data-siteforge-runtime="motion events" defer></script><div hidden data-siteforge-state="[]"></div></body>`);
    `SupportSettingsTests/testStaticReleaseFlowRuntimeIsOneHashedFileInEveryLanguageTree` (bundle `.cache == .immutable`,
    French `../` prefix, `data-siteforge-runtime="effects"`); lane C menu/content tags (`… data-siteforge-placement="end"
    data-siteforge-within="<root>" data-siteforge-flat hidden>`, `data-siteforge-within="<root> <frame>">`,
    `animation:sf-entrance-<root> 600ms ease-out 0ms both;`); text binding `…>Ready &lt;now&gt;`, item page `posts/first.html`,
    `output.attributes[fixture.frame] == " tabindex=\"0\""`, overview order `[text, frame×3, button]`. [V02 4, V04 2, V16 5–7, V12b 6–7, V14c 3, V09, V18]
30. Counts/strings computed offline: `CommandKernelTests/testOnePassInsertionAnswersMatchTheFullRebuildForEveryPairOnRandomGraphs`
    (757 / 9 / 20 / 859 and runtime); `TransformModelTests/testInspectorReportsLinkedBoxSourcesAndGuardsLinkedOnlyRemoval` (captions);
    `testVersionComparison…` (`["Page origin", "Other project data"]`, `["Token order"]` at "Accent"); `testSocialPreviewTagsSitemapRobots
    AndSEOWarningsInExport` (3 duplicates over `CollectionTemplates.outputPages`); collection import (`CollectionImportFormat(fileExtension: "CSV")`,
    `CollectionImportProblem(kind: .duplicateSlug, row: 2, column: 2)`, `parseNumber(numberText(1e20)) == 1e20`, curly-quote explanations,
    `templatePreviewProblem("upper(titel)")` range `6..<11`, `"Shows 5000 of 10000 published items on 50 pages."`); undo journal
    `trim` records `[1, 1, 1, 1, 1]`; `toolbar.undo` value `"Grouped Edit: …"`. [V02 4, V07 5, V05 7, V10 7, V13 8–9]
31. Fixture assumptions: `testNestedComponentDrawsExportsAndKeepsItsOwnValuesWithStableDerivedIdentity` (plan non-nil for a blank
    document); `testContainerQueriesFollowEachCopysContainerOnCanvasPreviewAndExport` (Hug-width fixture vs `validate()` — V14a item 3);
    `testComponentLibrariesExport…` (`CanonicalTypography.resolved(for:)` with only `family`; reusable style on the Home root);
    `testWorkspaceEditsInsideAVariant…` (`shell.canReplaceProjectContent` after `exitComponentDefinition()`);
    `testContainerQueryAndAuditDiagnosticsAreSanitizedAndCategorized` (Home page selected by default, async wait on
    `isRunningResponsiveAudit`); the Arabic-default mirror test (`fr/<page path>`, heading render object);
    `testProjectPreferencesDocumentSchemaGateAndBackwardCompatibleReopen` (blank document relabelled schema 21 must carry no
    schema-27-only key); `testStaticBuildCompilerProfilesAreDeterministicRedactedAndCancellationNeutral` (`first == second` now
    includes comparison + browser report); `testStaticReleaseCSSOptimizerMinifiesDeduplicatesAndKeepsBlocksWhole` (`index.html`
    unchanged, no runtime file); H02 `outputFiles.map(\.path) == filePaths`; `StaticOutputReferenceAudit.unresolved(in:) == [:]`
    (a failure names a real unresolved reference); the V17 precondition `plain.canWrite`; ProjectResourceTests media manifest
    order (`id.description` sorted as strings); `restoreMigrationOriginal()` right after opening → `ProjectSnapshotError.unchanged`;
    Create Component not refusing a container whose text carries `state.v1.text`; `ComponentGraphResolver.resolvedPage` keeping
    the binding. [V02 4, V16 OOA, V07 6–7, V04 5, V11, V01 7, V12 6–7, 10, V12b 4, 9, V17 1, V13 10, V18]
32. Async/queue-order tests: `CanvasSettingsTests/testProjectSettingsPaneKeepsGridDraftAcrossBuildSettingChanges` (one main-queue
    turn after `saveBuildSettings`; tail after final Undo + `drainBuildRebaseMainQueue()` must leave the pane clean and take the
    rebase branch); `testUndoThatRemovesTheEditedVariantReturnsToBaseAndRefusesStaleEdits` (two queued publications; drain twice
    if flaky); `DocumentLifecycleTests/testProjectFileCapacityIsMeasuredWhenAProjectIsOpened`. [V01 4–5, V14c 1, V03 5]
33. Performance: 65,536-file plan in the zip capability test; 10,001-node page validates within 120 s; 10,000-object build within
    120 s; 10,000-layer comparison fixture. [V06 7, V08 7, V18, V07 5]
34. Manual: value-source Clear while editing a component variant (session authoring conversion point). [V05 OOA]

34b. Lane V14d language-tree output tests: `ProjectResourceTests/testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound`
    (`fr/index.html`, `" poster=\"../assets/…"`, same binary files as the single-language build) and
    `testProjectFontsExportOnlyWithDeclaredWebRightsAndUseFallbackStacks` (`<link rel="stylesheet" href="../styles.css">`);
    `EventGraphOutput.findings` `(try? CanonicalTextBinding.resolve(node)) ?? nil` (valid, redundant `?? nil`); the static-layout
    stylesheet link (V14d question) is fixed by V14e fix 2 — run the two strengthened tests and a browser check of a plain
    static page (positions applied, hidden objects hidden). [V14d 1–2, 4–5, V14e]

34c. Lane V14b (menus and sheets): `MigrationDetailsPresentation.init(state:)` (`_lifecycle = ObservedObject(wrappedValue:
    state.lifecycle)` after `let state` is assigned); `WorkspaceProjectSheets.body(content:)` `ViewModifier` with
    `@ObservedObject var state` (`$state.isQuickOpenPresented`, `onDismiss: state.completeSnapshotsDismissal` /
    `completeQuickOpenDismissal`, the SVG sheet `Binding(get:set:)`); `.keyboardShortcut(.return, modifiers: [.command,
    .option, .shift])`, `("h"/"v", [.command, .control])`, `("b", [.command, .option])` shown in the menu bar;
    `DocumentLifecycleTests` `import Combine`, `state.editCommitRequests.sink { $0.reject() }`, `state.toggleFocusMode()`;
    `presentCollectionsEditor()` / `presentLanguagesEditor()` guard order. [V14b 1–5]

34d. Lane V14a (hidden content, fixed positions): `StaticVisibilityOutputEmitter.emit` (`Set(breakpoints.indices.filter { … }.map {
    breakpoints[$0] })`, `hidden[$0]?.count == breakpoints.count`, nested `func rule` used with `.map(rule)`);
    `ConnectedPageOutput.hiddenRule(selector, breakpoint: breakpoint)` at its three call sites; `themedStylesheet` order
    (dark block, then visibility, then container queries); `testContainerQueriesFollowEachCopysContainerOnCanvasPreviewAndExport`
    (`XCTAssertThrowsError` with `$0 as? ModelValidationError`, `evaluation.statuses[wideTitle]?.first?.containerID`);
    `testHiddenResponsiveFluidTextKeepsRendererOutputAndLayoutParticipationConsistent` (`count == 3`);
    `testPreviewAndResponsiveAuditPlaceFixedObjectsFromThePageCorner` (Preview height 900 pt → bar at y = 850). [V14a 1–6]

### T7 — browser and harness (Chrome on a Mac)
35. Flow, motion/interaction harness: DevTools key events `rawKeyDown` with `windowsVirtualKeyCode` (Enter dispatches `keydown`
    with `key: "Enter"`, no click on the frame); JavaScript-off reads via `DOM.enable` + `CSS.enable` + `CSS.getComputedStyleForNode`;
    `DOM.getOuterHTML` with scripts disabled; runtime `place` with `style.translate`, flat modal centring, `focusables` visibility
    filter, menu key block before the Tab trap, motion `members`/`reveal` recursion; Flow cases now load the Static Release site and
    wait for `window.SiteForgeDecorativeEffects`; run the two Flow helper checks that patch `os.environ` in a normal Python. [V09, V18, V12b 8, V14c]
36. Browser support facts used by ADR-0123: container queries Safari 16 / Chrome 105 / Firefox 110; `backdrop-filter` Safari 9 /
    Chrome 76 / Firefox 103; `::details-content` Safari 18.4 / Chrome 131 / Firefox 143 (double-check Firefox 143);
    `IntersectionObserver` Safari 12.1 / Chrome 58 / Firefox 55. [V12 12]

### T8 — selectors never run
37. Batch 03 core selectors in its activity-log entry plus `SiteForgeUITests/SiteForgeLaunchTests/testProjectSettingsGridPreferenceDraft
    ApplyUndoAndCancelJourney`; UI journeys `testReusableBoxStyleLinkOverrideAndUseLinkedBorderJourney`,
    `testNestedComponentInsertInsideDefinitionRefusesSelfAndShowsUsageJourney`, `testComponentSlotCustomizeAddReorderEmptyAndDefaultJourney`,
    the fast-style journeys after coalescing (`containing: "Grouped Edit"`), `…["inspector.containerQuery.rule.addSetting.0"].menuItems["Opacity"]`,
    `inspector.valueTrace.width` value "…, from Set here · Desktop, …", Settings → Advanced (`settings.experimental.enabled`); then every
    new selector listed in the lane V reports. [V01 6, V02 5, V13 8, V04 7, V05 5, V06 9]

## Suggested first checks for Codex (this lane)

1. `scripts/check-repository.sh` on the Mac: `check-architecture-boundaries.py` must report "Architecture boundary
   checks passed." (single `NSOpenPanel` owner after fix 1, plus the 12 `swiftc -typecheck -swift-version 6` slices).
2. `MultiPageStaticBuildPlanner.plan`: `var linksStylesheet` mutated inside the language/page loops and read after them;
   `let stylesheetLink = !page.nodes.isEmpty || hasFlow || …` (`page` is the loop's `CanonicalTextBinding.outputPage(entry.page)`);
   any other test that compares a whole static page's `<head>` must now include the stylesheet link (none found).
3. `NativeCollectionImportOpenPanel.chooseFile()` / `NativeComponentLibraryOpenPanel.chooseFile(message:)`: `@MainActor`
   enums called from SwiftUI view methods (`CollectionsEditorView.chooseImportFile`, `ComponentLibrariesSheet.chooseFile`);
   `.commaSeparatedText` / `.json` resolve through `import UniformTypeIdentifiers` in `LaunchExperience.swift`.
