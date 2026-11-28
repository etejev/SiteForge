# Lane V14c review — SupportSettingsTests, browser harnesses + CI/TESTING.md, preferences key, undo-compare sweep (2026-11-26)

Reviewer: Code Forge lane V14c (owner tag `lane-V14c`), one of five cross-tree verifiers (V14a–V14e) of the whole
lane V candidate. Verification by reading on Windows (no Swift toolchain, git, subprocess or browser), plus the pure
Python helper checks of both harnesses executed in a sandbox. Restore points: before = `RP-2026-11-26-V14`
(after phase 1), pre-lane-V baseline `RP-2026-11-26-V00`. `foreign_changes(30)` = [] and `icloud_duplicates()` = []
before the first write and again before this report.

## Scope

Manifest items 6, 7, 8 and 10 (`scope_V14c.json`):

| Item | Files read | Files changed |
| --- | --- | --- |
| 6 SupportSettingsTests vs current code | `Tests/SiteForgeTests/SupportSettingsTests.swift` (all 26 tests), `SiteForge/SupportSettings.swift` (diff RP-07 → now, `SettingsDraftNotice`, `SettingsDestination`, `FeatureFlagRegistry`, `FeatureFlagStore`), `WorkspaceMaterialPolicy.swift` (settings geometry), `CanvasRendererCore.swift` (`StaticRuntimeBundle`, `LocalBuildProfileCompiler`, cache policy), `DocumentModel.swift` (fixture APIs), flag tests in `CanvasSettingsTests` / `PersistedHistoryTests` | none (no defect) |
| 7 browser harnesses, CI, TESTING.md | `Tests/Tooling/flow_runtime_browser.py`, `test_flow_runtime_browser.py`, `interaction_runtime_browser.py`, `test_interaction_runtime_browser.py`, `SupportSettingsTests` Flow tests, `TransformModelTests.testInteractionAndMotionRuntimesActualBrowserFocusTrapEscapePlacementAndReveal`, `.github/workflows/ci.yml`, `docs/TESTING.md`, `scripts/unattended-verification.py` (`prepare_tooling_inputs`), `scripts/ci-test-accounting.py` | `docs/TESTING.md` |
| 8 `ProjectPreferences.build.reviewedCustomCodeDigest` | `DocumentModel.swift` (`ProjectPreferences`, `BuildProfileSettings`, `CustomCodeReview`, `BuildSettingID`), `WorkspaceShellModel.swift` (`saveBuildSettings`, `applyBuildRepair`), `CanvasSettings.swift` (`ProjectSettingsStore` rebase/reset/apply), `ProjectPackage.swift` (`ProjectComparer.compare`, `sameUncomparedContent`, snapshot restore), `PackagedSiteTemplate.swift`, `WorkspaceShellView.swift` (Build settings pane), ADR-0037 Amendment 1, tests | `CanvasSettingsTests.swift`, `ProjectPackageTests.swift`, ADR-0037 |
| 10 whole-document comparisons after undo/redo; expected strings changed by several lanes | every file under `Tests/` (scripted scan), `CommandKernel.swift` (`undo`/`redo`/`commit`), production string literals V00 → now | none (no defect) |

## Item 6 — SupportSettingsTests.swift

Findings: no defect.

- `testGlobalSettingsNavigationAndDraftNoticeHaveNoProjectScope` (V06 added the feature-draft lines): matches
  `SettingsDraftNotice.init(appearanceDirty:canvasDirty:projectDirty:featuresDirty:)` (`.advanced` appended last),
  `message` ("Unsaved Canvas and Advanced changes. … Project files are unchanged."), the 8 `SettingsDestination` raw
  values in declaration order, and `SettingsWindowGeometry.preferred.contentSize` = 860 × (470 − 28) = 442
  (`SiteForgeVisualSystem.settingsIdealWidth/Height`).
- `testStaticReleaseFlowRuntimeIsOneHashedFileInEveryLanguageTree` (V12b): the planner tag
  `<script src="../siteforge-effects.js" defer></script>` (`CanvasRendererCore` effects tag with `prefix`) is exactly
  `StaticRuntimeBundle.sourceTag("effects", prefix: "../")`; the bundle tag format
  `<script src="<prefix><bundle>" data-siteforge-runtime="effects" defer></script>` matches `StaticRuntimeBundle.page`;
  `LocalBuildProfileCompiler.compile(_:profile:)` returns `(LocalStaticBuildPlan, LocalBuildReport)`;
  `StaticOutputFileRecord.cache` is `.immutable` for `StaticRuntimeBundle.isBundlePath` paths; manifest rewrite drops the
  replaced names, so no Release file contains `siteforge-effects.js`. `SiteLocalizationEditing.start(code:name:)` /
  `addLocale(code:name:to:)` signatures match.
- `testFlowRuntimeActualBrowserDeformationFallbacksAndLifecycle`: writes `release.files` and `release.binaryFiles`
  (both exist on `LocalStaticBuildPlan`) into `sites/small|large|link/`, the folders the harness `--root` expects.
  `FlowRuntimeBrowserFixtures.expectedCases` equals the harness `CASES` (11, compared programmatically).
- `testFixedOutputPreservesDefaultPlacementAndHonorsAuthoredStatic`: `StaticAdvancedStyleOutputEmitter` writes
  `position: static;` only for an authored mode (`CanonicalPositioning.resolve` origin `.defaulted` otherwise).
- The remaining 21 tests use APIs in `SupportSettings.swift` / `TestingWindow.swift` whose declarations are unchanged
  since `RP-2026-11-26-07` (the only `SupportSettings.swift` changes are the draft-notice lines above and the inserted
  feature-flag block 939–1351; `TestingWindow.swift` has no diff).
- Flag strings asserted elsewhere: `PersistedHistoryTests` expects the `siteLanguages` summary to contain
  "Translations section" and "canvas and Local Preview" (both present in the V11 summary) and requirement IDs
  `["SF-1007", "SF-1506"]` (present). `CanvasSettingsTests` (`@MainActor` class, so `@MainActor FeatureFlagStore` is
  usable from its sync tests) matches the five shipped IDs, `defaultEnabled: true`, `FeatureFlagID: Comparable`.

## Item 7 — browser harnesses, CI and TESTING.md

Findings:

- Harness pairs are consistent with the Swift tests: Flow `CASES` = Swift `expectedCases` (set, 11);
  interaction `CASES` = `TransformModelTests.interactionBrowserCases` (ordered, 11); both Swift tests run the helper
  checks first, then the harness with `--root/--report/--captures`, and read `cases/passed/failed` from the report.
- `loads_effects_runtime` accepts the Development file and a 64-hex `siteforge-runtime.<sha256>.js` naming `effects`
  (the V12b change), matching `StaticRuntimeBundle.isBundlePath`.
- Executed here (cloud sandbox, `subprocess`/`signal` stubbed because the sandbox blocks them):
  `test_interaction_runtime_browser.py` 6/6 passed; `test_flow_runtime_browser.py` 6/8 passed, the 2 others
  (`test_missing_browser_reports_actionable_prerequisite`, `test_browser_override_requires_executable_file`) could not
  run because the sandbox's `os.environ` refuses `mock.patch.dict` — an environment limit, not a harness defect.
- Owner-local Testing copies `Tests/Tooling` with `git ls-files -c -o --exclude-standard`, so the new (untracked)
  interaction harness files are prepared beside the products too. CI runs both browser tests inside `./sf test half`
  after the "Prepare Flow browser prerequisite" step installs Chrome; non-UI tests are discovered, not listed, so CI
  needs no change.
- Gap (fixed): `docs/TESTING.md` said only "The Flow runtime browser integration test also requires Google Chrome" and
  did not name the interaction and motion harness or the helper-check commands.

Fix:

| File | Symbol | Defect | Fix |
| --- | --- | --- | --- |
| `docs/TESTING.md` | Chrome prerequisite paragraph | Named only the Flow browser test; the interaction/motion browser test (C10, ADR-0065) that also needs Chrome, which output each harness runs (Static Release bundle vs Development) and the browser-free helper commands were missing | Paragraph names both XCTest selectors and harness files, what each runs against, the shared owned browser, and the two `/usr/bin/python3 Tests/Tooling/test_*_runtime_browser.py` commands |

## Item 8 — `ProjectPreferences.build.reviewedCustomCodeDigest`

Findings: no code defect; two coverage gaps closed with tests.

- Strict decoding: `BuildProfileSettings.init(from:)` uses `requireKnownKeys`, rejects `null` for every optional key
  (digest included) and checks `version`; `encode(to:)` uses `encodeIfPresent` (omitted when unset).
  `isEmpty` includes the digest, so a digest-only record is stored and `ProjectPreferences.isStructurallyValid` accepts
  it. Round trip covered by `testCustomCodeReviewUnblocksStrictStaticReleaseUntilTheCodeChanges`.
- `BuildSettingID.customCodeReview`: both switches over `BuildSettingID` (`title`, `changedSettingIDs`) are exhaustive;
  no other switch over it in the tree (tests included).
- Comparison: `ProjectComparer.compare` reports any `build` difference as "Build settings"; `sameUncomparedContent`
  aligns `projectPreferences`. Snapshot restore replaces `projectPreferences` whole (one undoable command), and
  `PackagedSiteTemplate` copies it whole; no bundled template stores a digest. The digest only counts while it equals the
  current code's digest, so a copied or restored review never covers other code (ADR-0037 Amendment 1, "project data").
- Settings → Project pane (`ProjectSettingsStore`, V01 fix): the rebase copies `document.projectPreferences?.build`
  whole and `reset()` keeps `committed?.build`, so neither drops the review. Use SiteForge Defaults:
  `keepingCustomCodeReview`; Clear Custom Code Review drafts `nil`.
- Gaps: no test exercised a review change against a pending Settings grid draft, Reset/Apply, or the comparison of a
  review-only difference.

Tests added (existing tests extended, existing style, no assertion removed or weakened):

| File | Test | Added |
| --- | --- | --- |
| `Tests/SiteForgeTests/CanvasSettingsTests.swift` | `testProjectSettingsPaneKeepsGridDraftAcrossBuildSettingChanges` | After the final Undo: drain, clean pane; grid draft pending; `saveBuildSettings` with a `reviewedCustomCodeDigest` rebases the draft (`rebase-draft`, not stale, draft = grid + reviewed build); `reset()` keeps the reviewed build; `apply()` keeps the digest in the document |
| `Tests/SiteForgeTests/ProjectPackageTests.swift` | `testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded` | A document differing only by `reviewedCustomCodeDigest` compares as exactly `["Build settings"]` |

Doc: `docs/architecture-decisions/ADR-0037-custom-code.md` Amendment 1 **Tests** lists the two extended selectors.

## Item 10 — whole-document comparisons after undo/redo; multi-lane expected strings

Findings: no defect left.

- `DocumentSession.undo()`/`redo()` commit through `commit(...)`, which assigns `revision + 1`
  (`CommandKernel.swift`), so a whole `CanonicalDocument` compared after Undo/Redo with a value captured earlier can
  never be equal unless `revision` is normalized (the V17 defect).
- Scripted scan of every test function under `Tests/`: captured `.document`/`…Document` values, one- and two-line
  `XCTAssertEqual/NotEqual`, `XCTAssertTrue/False(a == b)`, Undo/Redo after the capture, no `x.revision =`
  normalization. Result: 0 defects. The 7 matches are false positives: save/encode-and-reopen round trips
  (`CommandKernelTests` 1304, `InsertionModelTests` 861, `LinkAuthoringTests` 120, `ProjectResourceTests` 629),
  a local fixture value (`TransformModelTests` 6698), and `PersistedHistoryTests.assertCanvasLanguageLeftDocumentAlone`
  (both sides current). All other whole-document comparisons follow refused edits (no commit) or normalize the
  revision (V17's 10 tests: `var undone = session.document; undone.revision = …`).
- Production string literals removed V00 → now that tests still contain: only `"interaction-container-flat"`, used in
  an `XCTAssertFalse(codes.contains { $0.hasPrefix(…) })` that correctly expects it gone (ADR-0065).
- Expected strings added by lane V in tests that several lanes edited, checked against the producing interpolation:
  "3 file(s) differ, 1 identical." (`StaticBuildProfileComparison`), "Since the previous check: 1 changed, …"
  (`StaticOutputChangeSummary`), "Safari 17: Works, with fallbacks", "Showing French. N value(s) are not translated yet"
  (`DocumentModel` 10225–10228), "Translated images: 1" (`ImageAssetReference.summary`, `Kind.translation`),
  "Shows 5000 of 10000 published items on 50 pages." (`DocumentModel` 11501), "at characters 7 to 11", "Computed by …"
  — all match.

## Requirement table (items in this lane's scope)

| Requirement | Status | Evidence |
| --- | --- | --- |
| SF-1803-002 feature choices are a pending draft | Met | `SettingsDraftNotice` `featuresDirty`; `testGlobalSettingsNavigationAndDraftNoticeHaveNoProjectScope` |
| SF-1205 one hashed runtime, browser-verified | Met (by reading) | `StaticRuntimeBundle`; both SupportSettings Flow tests; harness `loads_effects_runtime` + helper test |
| SF-1101/1104/1105 browser coverage (C10) documented and run in CI | Met (by reading) | `./sf test half` + Chrome step; TESTING.md fix |
| SF-1107-005 / SF-1211-003 review persisted, compared, restored | Met | strict codable; comparer; snapshot/template copy; new comparison assertion |
| SF-0206-004 Project pane keeps drafts across build-setting changes (review included) | Met | rebase/reset/apply; extended pane test |
| SF-1902-007/008 tooling inputs prepared for owner-local Testing | Met | `prepare_tooling_inputs` lists tracked + untracked `Tests/Tooling` |

## New/changed test selectors

```
SiteForgeTests/CanvasSettingsTests/testProjectSettingsPaneKeepsGridDraftAcrossBuildSettingChanges            (extended)
SiteForgeTests/ProjectPackageTests/testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded (extended)
```
Commands that cover this lane's items (from `docs/TESTING.md` / CI):
```
/usr/bin/python3 Tests/Tooling/test_flow_runtime_browser.py
/usr/bin/python3 Tests/Tooling/test_interaction_runtime_browser.py
./sf test focused SiteForgeTests/CanvasSettingsTests/testProjectSettingsPaneKeepsGridDraftAcrossBuildSettingChanges SiteForgeTests/ProjectPackageTests/testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded SiteForgeTests/CanvasSettingsTests/testCustomCodeReviewUnblocksStrictStaticReleaseUntilTheCodeChanges SiteForgeTests/SupportSettingsTests/testGlobalSettingsNavigationAndDraftNoticeHaveNoProjectScope SiteForgeTests/SupportSettingsTests/testStaticReleaseFlowRuntimeIsOneHashedFileInEveryLanguageTree SiteForgeTests/SupportSettingsTests/testFlowRuntimeActualBrowserDeformationFallbacksAndLifecycle SiteForgeTests/TransformModelTests/testInteractionAndMotionRuntimesActualBrowserFocusTrapEscapePlacementAndReveal
```

## Remaining work (blocked only)

- Compile and run the selectors above on a Mac (no Swift toolchain on the PC).
- Run both actual-browser tests with Google Chrome (no browser or subprocess on the PC).
- Run the two Flow helper checks that patch `os.environ` (`test_missing_browser_reports_actionable_prerequisite`,
  `test_browser_override_requires_executable_file`) in a normal Python; the sandbox here refuses `mock.patch.dict`.

## Intended doc changes for the coordinator

- DEVELOPMENT_PLAN lane V table, V14c row: `done (V14c; SupportSettingsTests re-verified (26 tests, no defect); harness pairs, CI and TESTING.md checked — TESTING.md now names both browser tests and helper commands; reviewedCustomCodeDigest verified across comparison, snapshots, templates, Settings rebase/Reset, Use Defaults — 2 tests extended; undo-compare sweep of all Tests/: no remaining defect; remaining blocked: Mac/Chrome runs)`.
- Activity log: lane V14c entry with the fix and two extended tests above.
- OD-041 status line, append: `Lane V14c (2026-11-26): review digest verified in comparison, snapshot restore, template creation, Settings → Project rebase/Reset and Use SiteForge Defaults; tests extended. Still unverified (no Mac).`
- `.github/workflows/ci.yml` (optional wording only, not changed): the step "Prepare Flow browser prerequisite" also serves the interaction/motion browser test; a rename to "Prepare browser prerequisite" would be accurate.

## Out-of-area issues

None found.

## Suggested first checks for Codex

1. `testProjectSettingsPaneKeepsGridDraftAcrossBuildSettingChanges` tail: after the final `session.undo()` and
   `drainBuildRebaseMainQueue()`, the pane must be clean (`store.isDirty == false`, committed = grid 24 + `changed`)
   before `chooseGridVisibility(true)`; then the digest save must take the rebase branch (`sameGridPreferences`).
2. `reviewedBuild.projectPreferences?.build?.reviewedCustomCodeDigest = …` (optional-chained mutation of a `var`) in
   `ProjectPackageTests`; the comparison must list only "Build settings".
3. `SupportSettingsTests.testStaticReleaseFlowRuntimeIsOneHashedFileInEveryLanguageTree`: `release.1.outputFiles`
   record for the bundle `.cache == .immutable` and the French tag prefix `../`.
4. `FeatureFlagStore` is `@MainActor`; every test using it must be on the main actor (`CanvasSettingsTests` class is).
5. `docs/TESTING.md` paragraph wording (lines 9–22).
