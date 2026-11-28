# Lane V07 review — 2026-11-26 (lane A + batch 18 part 1 + E01 snapshots UI)

Reviewer: Code Forge lane V07 (owner tag `lane-V07`). Static review on Windows (no Swift toolchain); every edit was
made with `forge_io.edit`, `check()` returned `[]` after each, and each changed region was re-read against the real
declarations. `foreign_changes(30)` and `icloud_duplicates()` were empty before the first write and at the end.

## Scope

| Batch | Feature | ADR | Modules | Diffed against |
|---|---|---|---|---|
| 18 part 1 | Named snapshots model + lifecycle API | ADR-0038 | SF-1301 | RP-2026-11-26-11 → V00 |
| E01 | Snapshots sheet, state block, flag `versions.named-snapshots` | ADR-0039 | SF-1301 | RP-2026-11-26-E01 |
| A02 | Version comparison | ADR-0040 | SF-1306 | RP-2026-11-26-A02 |
| A03 | Shared component libraries, `DocumentSession.commitGuard` | ADR-0041 | SF-0906 | RP-2026-11-26-A03 |
| A04 | Flags `versions.compare`, `components.shared-libraries` | ADR-0040/0041 | SF-1803 | RP-2026-11-26-A04 |
| lane RA fixes | 9 fixes in `LANE-RA-review-2026-11-26.md` | — | all above | R01 → V00 |
| Owner addition | Library export with reusable styles (lane V02 out-of-area finding) | ADR-0041/0042 | SF-0906 | — |

Files read in full for the changed regions: `SiteForge/ProjectPackage.swift` (snapshots ~1063–1590, comparison
~1588–2215, libraries ~2215–end), `SiteForge/DocumentLifecycle.swift` (init guard, snapshot and library API),
`SiteForge/CommandKernel.swift` (`DocumentSession.commitGuard`, `execute`, `commit`), `SiteForge/WorkspaceShellModel.swift`
(`presentProjectComparison`, `presentComponentLibraries`, snapshot block), `SiteForge/WorkspaceShellView.swift`
(`ProjectComparisonRequest`, `ProjectComparisonModel`, `ProjectComparisonSheet`, `ComponentLibrariesSheet`,
`ProjectSnapshotsSheet`, `SiteForgeCommands` save group, workspace sheets), `SiteForge/SupportSettings.swift`
(flag IDs and registry), and all tests listed below. Declarations checked: `CanonicalDocument`/`DocumentPage`/
`DocumentNode`/`LocalColorToken`/`ImageAsset`/`ProjectPreferences` fields, `PropertyValue`, `PageProvenance`,
`CanonicalLinkTarget`, `CanonicalMediaPlayback`, `CanonicalTypography.resolved(for:)`, `FontAsset.init`,
`SiteTranslationKey`, `CanonicalReusableStyleIndex`, `StableIdentifier`, `BoundedDiagnosticBuffer`,
`DiagnosticStableIdentifier.sanitize`, `CommandExecutionError`.

### Lane RA fixes re-verified

All nine RA fixes are present and correct in the current text: single "Languages" entry (1); "Build settings" named
on its own (2); "Other project data" safety net (3, kept and extended here); `ProjectComparisonModel.compare()` passes
only `ProjectComparison?` and `(message:category:)?` across actors (4); `ComponentLibraries.updating` keeps the union
of delivered identities (5); library row buttons name the library (6); test assertions (7, 8); ADR sentences (9).
RA's remaining gaps 1–4 are closed below; gap 5 (UI tests) and 6–9 are blocked or need OD-050 (see Remaining work).

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/ProjectPackage.swift` | `ProjectComparer.comparePages` | A page's `provenance` change was only reported by the "Other project data" fallback, which runs only when nothing else changed — hidden whenever any other change exists. | New `.pages/.changed` entry "Page origin" (before/after raw values). | ADR-0040 "never hide a difference"; SF-1306-001/003. |
| 2 | `SiteForge/ProjectPackage.swift` | `compareImages`, `compareGuides`, `compareColorTokens` | Order-only changes of images, guides and tokens were likewise hidden whenever another change existed. | `movedIdentifiers` per list; "Image order", "Guide order", "Token order" moved entries. Fallback comment updated. | Same; SF-1306 "distinguish reordering". |
| 3 | `SiteForge/WorkspaceShellView.swift` | `ProjectSnapshotsSheet` | Read `FeatureFlagStore.shared` without observing it (RA gap 1). | `@ObservedObject private var features = FeatureFlagStore.shared`; Compare buttons use it. | SF-1803 flag behaviour while the sheet is open. |
| 4 | `SiteForge/WorkspaceShellModel.swift`, `WorkspaceShellView.swift` | `canReplaceProjectContent`, `variantOpenReplacementMessage`, `restoreSnapshot`, `ProjectSnapshotsSheet`, `ComponentLibrariesSheet.canReplaceContent()` | Restore, library Import/Update/Apply ran while a component variant was edited and were refused by the variant conversion point with an unrelated message (RA gap 2). | State property + message; `restoreSnapshot` refuses first (nothing changes, announced); Restore…/Restore, Import Library…, Update…, Apply Update disabled with the reason; sheet actions guard too. | SF-1301-004, SF-0906-004; same pattern as `canEditLanguages`. |
| 5 | `SiteForge/ProjectPackage.swift` | `ComponentLibraryError`, `ComponentLibraries.exporting` | Components with video/audio, translations, project fonts or links to project pages failed export with the generic `invalidContent` or would travel with dangling references (RA gap 3). | New cases `usesVideoOrAudio`, `usesTranslations`, `usesProjectFonts`, `linksOutside` (component name), both exhaustive switches; checks before the carrier is built. | SF-0906-004 specific recovery. |
| 6 | `SiteForge/ProjectPackage.swift` | `ComponentLibraryError.usesReusableStyle`, `ComponentLibraries.exporting` | **Owner-approved addition (lane V02 finding):** a component applying a reusable style whose definition lives on a website page node made `DocumentSerializer.encode(carrier)` fail → generic "could not be stored". | Refused up front with `usesReusableStyle(component, style)` naming both; styles defined inside the exported components still travel. Carrying outside styles was not chosen: definitions live as properties on arbitrary page nodes, so carrying them needs a new place in the carrier, name-conflict handling in the consumer and read-only protection of style definitions — a format/import-path change better decided in OD-050 and verified with a compiler. | SF-0906-004. |
| 7 | `SiteForge/ProjectPackage.swift` | `ComponentLibraries.replacing` | A record over 256 KiB reported `tooManyLibraries` (RA gap 4). | New `recordTooLarge` with its own message and category. | Accurate recovery text. |
| 8 | `SiteForge/WorkspaceShellModel.swift`, `WorkspaceShellView.swift` | `previewSnapshotRestore`, `pendingSnapshotComparison`, `completeSnapshotsDismissal`, restore panel | SF-1301-003 Partial: no way to see what a restore would change before choosing it. | Review Changes… in the restore panel (flag-gated) hands off to Compare Versions as current → snapshot; the pending hand-off is now a `(baseline:target:)` tuple. | SF-1301-002/003. |
| 9 | ADR-0039, ADR-0040, ADR-0041; new ADR-0042 | Decision text | Out of date after fixes 1–8. | Sentences updated; ADR-0042 records the rules. | Docs match code. |

Counts: 9 defects found, 9 fixed (8 code, 1 documentation).

## Features finished

- Restore preview (SF-1301-003) — ADR-0042 / ADR-0039: model hand-off, UI button with label/identifier
  `snapshots.restore.review`, flag gating, state test.
- Variant-safe replacement of project content — ADR-0042: state, both sheets (`snapshots.restore.variantOpen`,
  `libraries.variantOpen`), test.
- Specific library export refusals incl. reusable styles — ADR-0042 / ADR-0041: model, diagnostics categories, tests.
- Structural comparison completeness (page origin, list order) — ADR-0042 / ADR-0040: model, tests.
- A2 rendered/visual diff: **not built** — OD-043 approved "a structural/visual diff", but a rendered comparison needs
  off-screen rendering of two versions at a declared viewport, language, data and fonts plus pixel tolerance; it cannot
  be built or verified safely without a Mac and compiler. Recommended default in OD-050.
- A3 images/fonts in library packages: **not built** — OD-046 approves "component definitions and tokens"; resources
  are outside it. Refused with specific reasons; OD-050.

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-1301-001 | Met | Strict versioned index/entries, stable IDs; `testNamedSnapshotsAreStrictBoundedAndRoundTripThroughThePackage`. |
| SF-1301-002 | Met | Create/rename/delete/restore/compare from the sheet; `testSnapshotsSheet…`. |
| SF-1301-003 | Met | Deterministic restore rules (ADR-0038) + Review Changes preview (fix 8); `testSnapshotsSheet…` new hand-off assertions. |
| SF-1301-004 | Partial | Specific errors, Delete All recovery, variant refusal (fix 4). Automatic snapshots + pruning not approved (OD-050). |
| SF-1301-005 | Partial | Restore = one undoable transaction, valid persisted history; snapshot-only changes are saved with Save only (ADR-0038 design). |
| SF-1301-006 | Partial | Labels, identifiers, announcements, keyboard; no UI test (Mac only). |
| SF-1301-007 | Partial | Bounded (10 / 2 MiB / 75%); encode/decode on the main actor; no restore fixture. |
| SF-1301-008 | Partial | `ProjectSnapshotDiagnosticRecord`; unit + integration tests; no UI/performance test. |
| SF-1306-001 | Met | Derived deterministic value types; every difference listed (fixes 1–2). |
| SF-1306-002 | Met | `filtered(area:kind:query:)`, sheet filters. |
| SF-1306-003 | Met | Identity matching, moves vs recreation incl. images/guides/tokens; `testVersionComparison…`. |
| SF-1306-004 | Met | notFound/corrupt + Delete All, cancel, stale, Try Again; `testCompareVersions…`. |
| SF-1306-005 | Met | Comparing never edits; stale labelling. |
| SF-1306-006 | Partial | Row labels, identifiers, announcements; no UI test. |
| SF-1306-007 | Partial | Detached run, 5,000 bound; new 10,000-layer fixture checks cancellation every ≤256 layers; library update preview still compares on the main actor; no timing fixture. |
| SF-1306-008 | Partial | Diagnostics, unit + integration tests; rendered mode not built (OD-050); no UI test. |
| SF-0906-001 | Met | Strict file/index formats, stable identities. |
| SF-0906-002 | Met | Export/import/update/detach with reviewed update. |
| SF-0906-003 | Met | Status current/earlier/changed/missing; update preview. |
| SF-0906-004 | Met | Specific refusals incl. media, translations, fonts, page links, outside reusable styles, record too large, variant open (fixes 4–7). |
| SF-0906-005 | Partial | Import/update one undoable command; detach/export record changes are not undoable (ADR-0041 design). |
| SF-0906-006 | Partial | Labels incl. per-row names, disabled reasons; no UI test. |
| SF-0906-007 | Partial | 4 MiB / 32 / 16 bounds; file decode on the main actor; no fixture. |
| SF-0906-008 | Partial | `ComponentLibraryDiagnosticRecord`; unit + integration tests; no UI test. |
| SF-1803 (flags part) | Met | Registry entries; menu, Compare/Review buttons and `present…` gated; Snapshots sheet observes the store (fix 3). |

Totals: 13 Met, 12 Partial, 0 Missing.

## Remaining work (blocked only)

1. UI tests for Snapshots, Compare Versions and Component Libraries sheets — blocked: Mac-only XCUITest harness and
   `scripts/ci-ui-timings.txt` cannot be run or timed on this Windows PC.
2. Moving snapshot encode/decode and library file decode off the main actor — blocked: needs the synchronous throwing
   lifecycle API (used by 6 tests and 3 sheets) to become async; without a compiler the isolation/Sendable changes cannot
   be verified. Work is bounded (2 MiB snapshots, 4 MiB library files).
3. Automatic snapshots with pruning, rendered/visual comparison, and resources/outside styles inside library files —
   blocked on owner decision OD-050 (proposed below).
4. `Tests/SiteForgeTests/SupportSettingsTests.swift` is an unreadable iCloud placeholder; any test there counting
   `FeatureFlagRegistry.definitions` is unverified (RA check 7 still applies).

## Intended plan / OD status-line changes (coordinator)

- OD-043 status line, append: "Lane V review 2026-11-26 (lane-V07, ADR-0042): comparison names a page's origin and image, guide and token order on their own; Review Changes shows what a restore would change; restore waits while a component variant is open. Rendered/visual comparison and automatic snapshots: see OD-050. Still unverified."
- OD-046 status line, append: "Lane V review 2026-11-26 (lane-V07, ADR-0042): export names the component (and style) when it uses video or audio, translations, project fonts, page links or a reusable style defined outside the exported components; record-too-large has its own message; import and update wait while a component variant is open. Resources inside libraries: see OD-050. Still unverified."
- New OD (AGENTS.md format):

  ## OD-050 — Later versioning and library slices: automatic snapshots, rendered comparison, resources in libraries

  Status: Open — raised by Code Forge lane V07, 2026-11-26. Implementation status: not started (waiting for this decision).

  - Affected requirements: SF-1301-004 (automatic checkpoints and pruning), SF-1306 (rendered comparison mode), SF-0906 (resources and styles in libraries).
  - Context: OD-043 approved named snapshots and a structural/visual diff; the structural diff is built (ADR-0040, ADR-0042). OD-046 approved definitions and tokens only; components using images, video/audio, translations, project fonts, page links or outside reusable styles are refused by name.
  - Recommended default: (a) automatic snapshots off by default, one per save at most every 30 minutes, at most 5 kept and pruned oldest first, never counting toward the 10 named snapshots; (b) a rendered comparison that renders one page of both versions with the Local Preview renderer at a chosen breakpoint width, language and the project fonts of each version, shows side-by-side and difference overlay with a stated 1% pixel tolerance, built in its own batch on a Mac; (c) library files version 2 carrying the images, fonts and reusable style definitions their components use (resource bytes base64, size-limited), imported as read-only copies with identity-conflict refusal and name-conflict renaming; video/audio and translations stay refused.
  - Alternative: keep the current slices (named snapshots, structural diff, definitions and tokens only).
  - Tradeoff: each part adds storage, rendering or format surface Codex must verify; deferring keeps the gaps as specific refusals.
  - Safe temporary assumption: none of (a)–(c) exists; the specific refusals stay.

- `DEVELOPMENT_PLAN.md`, lane V table, V07 row: "done (unverified) — batch 18 p1, E01, A02–A04, RA fixes verified; 9 fixes incl. owner-approved reusable-style refusal; ADR-0042; OD-050 proposed; report docs/reviews/LANE-V07-review-2026-11-26.md".
- `docs/coordination/CODE_FORGE_ACTIVITY.md`: entry "## Lane V07 review — November 26, 2026 (batch 18 part 1, E01, A02–A04, OD-043 / OD-046, ADR-0042, unverified, complete)" with the fixes table and selectors.

## New/changed test selectors

Changed (new assertions):

```
SiteForgeTests/ProjectPackageTests/testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded
SiteForgeTests/ProjectPackageTests/testComponentLibrariesExportImportReadOnlyUpdateCompareAndDetach
SiteForgeTests/DocumentLifecycleTests/testSnapshotsSheetCreatesRenamesRestoresKeepingCurrentHandsOffCompareAndRecoversDamagedStorage
SiteForgeTests/CommandKernelTests/testWorkspaceEditsInsideAVariantAndReturnsToBaseOnExit
```

Run as well: the RA list (`testNamedSnapshots…`, `testSnapshotRestoreCommand…`, `testNamedSnapshotsSaveReopen…`,
`testCompareVersions…`, `testComponentLibraryImport…`, `PersistedHistoryTests/testSiteLanguagesAreStrictSchemaGatedUndoableAndPersistedInHistory`,
`ProjectResourceTests/testMediaModelIsStrictValidatedOmittedWhenEmptyAndUndoable`,
`CanvasSettingsTests/testFeatureFlagRegistryIdentifiersOwnersAndRemovalDatesAreValid`). No UI tests added;
`scripts/ci-ui-timings.txt` unchanged.

Note on the reusable-style test: the refusal path changes nothing (pure function throws), so there is nothing to undo;
the test asserts the named refusal and that a style defined inside the component is not refused by the new rule.

## Suggested first checks for Codex

1. `ComponentLibraries.exporting`: `switch try? CanonicalLinkTarget.resolve(node)` with
   `case .page(let pageID)? where …, .section(let pageID, _)? where …:` (multi-pattern case, per-pattern `where`).
2. `ComponentLibraries.exporting`: `Set(definitions.flatMap(\.nodes).flatMap(\.properties).compactMap { property -> ReusableStyleID? in … })`
   and `(try? CanonicalReusableStyleIndex(document: document))?.byID ?? [:]`.
3. `WorkspaceShellState.pendingSnapshotComparison` as an optional labeled tuple and `static let variantOpenReplacementMessage`
   in the `@MainActor` class, used from `ProjectSnapshotsSheet`/`ComponentLibrariesSheet`.
4. `ProjectSnapshotsSheet`: `@ObservedObject private var features = FeatureFlagStore.shared` alongside the custom `init(state:)`.
5. `testVersionComparison…`: the new `["Page origin", "Other project data"]` ordering and `["Token order"]` with location
   `"Accent"`; the 10,000-layer fixture's checkpoint closure mutating a captured `var` (non-escaping).
6. `testComponentLibrariesExport…`: `libraryRefusal(.text, …family "inter"…, fonts:)` relies on
   `CanonicalTypography.resolved(for:)` returning a valid value with only `family` set; the reusable-style case relies on
   `CanonicalReusableStyleIndex(document:)` accepting a name+opacity definition on the Home root.
7. `testWorkspaceEditsInsideAVariant…`: `shell.canReplaceProjectContent` true after `exitComponentDefinition()` with the
   default lifecycle of `WorkspaceShellState(documentSession:)`.
