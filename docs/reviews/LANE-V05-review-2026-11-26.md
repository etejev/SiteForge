# Lane V05 review — batches 12–14 (SF-0704, SF-0807, SF-1207) — 2026-11-26

Verification by careful reading only (Windows PC, no Swift toolchain). Every change below is
unverified until Codex builds and runs the tests. Schemas unchanged: document 27, persisted
history 4, WebsiteMetadata 3. No new Swift files, no new `CanonicalDocument` keys.

## Scope

- Batch 12 — value sources (SF-0704): `ValueTraceSetting`, `ValueTraceStep`, `ValueTrace`,
  `CanonicalValueTrace` (TransformModel); `CanonicalContainerQueries.accepts` fix (DocumentModel);
  `valueTrace…`, `clearWinningValue…`, `revealValueSource` (WorkspaceShellModel);
  `ValueTraceInspectorView` (WorkspaceShellView); `CommandKernelTests/testValueTraceMatchesEnginePrecedenceAndClearsTheWinnerInOneStep`;
  `SiteForgeUITests/testValueSourcesShowWinnerAndClearItJourney`; `scripts/ci-ui-timings.txt`.
- Batch 13 — asset dependencies (SF-0807): `ImageAssetDependencies` (ProjectResources); shell
  `imageAssetReferences`, `revealImageAssetReference`, `useOtherImageAsset`, `unusedImageAssetCount`,
  `removeUnusedImageAssets`; Assets row menu and Remove Unused; `ProjectResourceTests/testAssetUsesRetargetToAnotherAssetAndUnusedAssetsAreRemovedInOneStep`.
- Batch 14 — social previews, sitemap, robots, SEO warnings (SF-1207, ADR-0034): `WebsiteMetadata`
  v2 fields (now v3), `ImageAssetReference.Kind.socialImage`, removal guard, `StaticSEOEmitter`,
  `StaticSEOAudit`, export of robots/sitemap/social image, BrowserPreview types, Website Settings
  Sharing section and Shared Link Preview, two tests, ADR-0034.
- Diff: RP-2026-11-26-07 → RP-2026-11-26-08 (shared with batches 07–11; hunks attributed by the
  activity entries), then the current code of every changed region and its declarations/call sites.

## Fixes made

| # | File | Symbol | Defect | Fix |
|---|---|---|---|---|
| 1 | SiteForge/TransformModel.swift | `CanonicalValueTrace.trace`, `ValueTraceStep.Source` | Geometry that layout places (Fill/Hug/Stack/Grid) was traced as the stored number the canvas does not draw — violates the SF-0704 invariant. | New `Source.layout(String)`, optional `layout:` parameter (last geometry step), cannot be cleared, specific refusal. |
| 2 | SiteForge/WorkspaceShellModel.swift | `valueTrace(_:)`, `revealValueSource(_:)` | Shell never supplied the layout value; switch must cover the new case. | Reads the layout value from `geometryInspectorValue(for:)` when `isLayoutResolved`; no trace while the frame is pending; `.layout` added to the non-revealable cases. |
| 3 | SiteForge/TransformModel.swift | `FluidValueCommandRegistry.prepare`, `FluidValueCommandError` | Batch 12 refused rule-over-fluid only; fluid could still be added under a rule for the same setting (canvas and CSS disagree). | `containerQuerySets(_:on:)` guard, new `.containerQueryConflict` (description + diagnostic category). |
| 4 | SiteForge/WorkspaceShellView.swift | `ValueTraceInspectorView` | macOS DisclosureGroup label is not clickable or keyboard-reachable; the accessibility value was on the group, not on `inspector.valueTrace.<setting>` (the UI journey clicks and reads that element); one large body. | Label is a plain Button toggling the row, with label/value/hint/identifier; body split into `settingRow`, `stepRow`, `clearButton`. |
| 5 | SiteForge/WorkspaceShellModel.swift | `revealImageAssetReference`, `revealImageUsage` | A social-image use said "This use no longer exists"; Reveal Usage of a social-image-only asset did nothing. | Favicon and social image both open Website Settings. |
| 6 | SiteForge/ProjectResources.swift | `ImageAssetDependencies.retarget` | Collection item images (OD-035) stayed on the source, which stayed "used" after "now unused". | Rewrites collection image values in the same transaction (`setCollections`), counted in the result. |
| 7 | SiteForge/ProjectResources.swift | `unusedAssetIDs`, new `usedAssetIDs`, `holdsAssetUse` | One full project scan per asset (Assets body each render, export) — O(assets × objects) on the main actor. | One pass; `holdsAssetUse` shared with `retarget` so "used" = "what retarget moves" + favicon/social + collections. |
| 8 | SiteForge/WorkspaceShellModel.swift | `imageAssets` | Unused filter ignored collection items and translations (disagreed with Remove Unused). | Uses `ImageAssetDependencies.usedAssetIDs`. |
| 9 | SiteForge/WorkspaceShellModel.swift | `imageAssetReferences`, `imageAssetUsageCount` | Full scan per asset row per render (context menu + accessibility value). | Per-authoring-document cache (id, revision, open definition, variant). |
| 10 | SiteForge/CommandKernel.swift + WorkspaceShellModel.swift | `CommandDiagnostics.recordValueSourceOperation`, `recordAssetDependencyOperation`; `clearWinningValue`, `useOtherImageAsset`, `removeUnusedImageAssets` | SF-0704-008 / SF-0807-008 diagnostics had no requirement IDs. | Identity-only records with requirement IDs, duration, result. |
| 11 | SiteForge/CanvasRendererCore.swift | `StaticSEOAudit.findings` | Audited the collection template page (never written) and not the item pages (dynamic routes). | Iterates `CollectionTemplates.outputPages`, item pages resolved with `ignoresPageTitle` like export, later list pages skipped. |
| 12 | SiteForge/ProjectResources.swift | `ImageAssetDependencies` doc comment | Pointed at non-existent ADR-0033. | Points at ADR-0144. |
| 13 | SiteForge/WorkspaceShellView.swift | Remove Unused `.help` | Omitted social image, collection items, translations. | Lists every kind of use. |
| 14 | SiteForge/WorkspaceShellModel.swift | `deleteImageAssetAndUses` | A refused delete (collection/translation use) set the status but was not announced. | Posts the announcement. |

Found but fixed concurrently by another lane (verified in current text, not changed by me):
`CommandKernelTests/testSelectedMediaAssetUseAndGlobalReferenceInventoryPreserveScope` asserted one
reference of every `ImageAssetReference.Kind.allCases`, which failed once batch 14 added `.socialImage`;
lane V11 replaced it with an explicit kind set.

Verified without change: `WebsiteMetadata` strict v1/v2/v3 decoding and schema-27 gate;
`StaticSEOEmitter.head/sitemap/robots` escaping and absolute URLs (all language trees and item pages);
`social-image-missing` / `social-image-svg` findings; social image in exported assets and in delete
guard / Delete with Uses; ValueTrace precedence for geometry (Desktop → fluid → breakpoint → container
query), visibility, opacity (default → linked styles → own) and text; all batch 12–14 tests read against
their declarations and the exact strings the code produces.

## Features finished

No item in this scope was marked partial/open. Gaps closed inside approved scope (ADR-0144):
layout step in value traces (SF-0704-003), two-way fluid/rule refusal (SF-0605-003), keyboard and
VoiceOver value-source rows (SF-0704-006), collection uses in retarget (SF-0807-002/004, OD-035),
one-pass used set and reference cache (SF-0807-007), item-page SEO audit (SF-1207-003),
requirement-tagged diagnostics (SF-0704-008, SF-0807-008).

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-0704-001 | Met | Trace is derived from canonical properties with origin (authored → "Set here", defaulted → default); no stored UI state. `testValueTraceMatchesEnginePrecedenceAndClearsTheWinnerInOneStep`. |
| SF-0704-002 | Met | Show reveals breakpoint / container / linked style (`revealValueSource`); Clear Winning Value one command; UI journey. |
| SF-0704-003 | Met | Engine order incl. layout step and container queries; new test `testValueTraceLayoutWinnerFluidRuleConflictAndDiagnosticsStayTruthful`. |
| SF-0704-004 | Met | Specific refusals (busy, changed, default, Desktop, linked style, layout, invalid result). |
| SF-0704-005 | Met | One `removeProperty` or container-query command; undo restores one value (test). |
| SF-0704-006 | Met | Buttons with label/value/hint/identifier, Show buttons labeled, status announced. |
| SF-0704-007 | Partial | Per-node work only, container-query evaluation cached per revision; no large-fixture timing (blocked: no macOS toolchain here). |
| SF-0704-008 | Met | `recordValueSourceOperation`; unit + UI tests. |
| SF-0807-001 | Met | Uses derived from canonical asset IDs; no new state. |
| SF-0807-002 | Met | Replace one use: reveal a use from Uses, change it in the Image Inspector (`prepareAssetUse`); replace everywhere: Use Another Asset Instead incl. collections (new test). |
| SF-0807-003 | Met | Uses (N) list, each revealable (favicon/social → Website Settings). |
| SF-0807-004 | Met | Remove Unused confirmed, undoable; refusals with reasons. |
| SF-0807-005 | Met | One batch per operation; undo/redo tests. |
| SF-0807-006 | Partial | Actions live in the asset row context menu (VoiceOver/Full Keyboard Access reachable); no menu-bar command; macOS accessibility not verifiable here (blocked: no macOS). |
| SF-0807-007 | Partial | One-pass used set and per-revision reference cache; no 10,000-object timing fixture (blocked: no toolchain). |
| SF-0807-008 | Met | `recordAssetDependencyOperation`; tests. |
| SF-1207-001 | Met | `WebsiteMetadata` v3 strict, schema-27 gate; PersistedHistory test. |
| SF-1207-002 | Met | Local Snippet Preview + Shared Link Preview in Website Settings. |
| SF-1207-003 | Partial | Duplicate/missing/long checks on the pages a build writes (new test); structured data not implemented — needs OD-144. |
| SF-1207-004 | Met | Invalid address refused, missing favicon/social image are errors, SVG social image warned. |
| SF-1207-005 | Met | `setWebsiteMetadata` one undoable command, persisted history (v3). |
| SF-1207-006 | Met | Labeled/identified fields, combined preview element, validation messages. |
| SF-1207-007 | Partial | Audit linear in written pages; no stress fixture (blocked: no toolchain). |
| SF-1207-008 | Met | Export, persistence and audit tests. |

Totals: Met 18, Partial 6, Missing 0.

## Remaining work (blocked only)

1. Build and run all tests, incl. the UI journey `testValueSourcesShowWinnerAndClearItJourney`
   (timing row 50 s is an estimate) — blocked: no Swift toolchain / macOS on this machine.
2. Large/stress performance fixtures for SF-0704-007, SF-0807-007, SF-1207-007 and macOS
   accessibility checks for SF-0807-006 — blocked: need the macOS harness.
3. Structured data (SF-1207-003 scope) — blocked on OD-144 (proposed in ADR-0144; recommended
   default: typed schema.org WebSite/WebPage JSON-LD only with a site address).

## Intended plan / OD status-line changes (for the coordinator)

- CODE_FORGE_ACTIVITY.md, Batch 12 heading: `## Batch 12 — November 26, 2026 (value sources, SF-0704, re-verified by lane V05 2026-11-26: layout step, fluid/rule refusal, accessible rows, diagnostics — ADR-0144; unverified, complete)`
- Batch 13 heading: `## Batch 13 — November 26, 2026 (asset dependencies, SF-0807, re-verified by lane V05 2026-11-26: collection uses in retarget, one-pass used set, social-image reveal, diagnostics — ADR-0144; unverified, complete)`
- Batch 14 heading: `## Batch 14 — November 26, 2026 (social previews, sitemap, robots, SEO warnings, SF-1207, ADR-0034; re-verified by lane V05 2026-11-26: SEO audit checks written item pages — ADR-0144; unverified, complete)`
- OPEN_DECISIONS.md, new entry: `## OD-144 — SF-1207 structured data (Proposed, lane V05)` — "SiteForge writes no structured data. Recommended default: schema.org WebSite and WebPage JSON-LD generated only from typed metadata (site name, page title, description, absolute URL), only when the site address is set; no authored JSON. Alternative: defer structured data. Affected: SF-1207-001, SF-1207-003. Deadline: before SF-1207 is release-complete. Safe assumption: none is written."
- DEVELOPMENT_PLAN.md lane V table: `V05 | batches 12–14 | done — 14 fixes, 3 tests added, ADR-0144, OD-144 proposed`.

## New / changed test selectors

- `SiteForgeTests/CommandKernelTests/testValueTraceLayoutWinnerFluidRuleConflictAndDiagnosticsStayTruthful` (new)
- `SiteForgeTests/ProjectResourceTests/testAssetRetargetMovesCollectionItemImagesAndUsedSetMatchesPerAssetScans` (new)
- `SiteForgeTests/CanvasRendererTests/testSEOWarningsCheckCollectionItemPagesNotTheTemplate` (new)
- Re-run: `SiteForgeTests/CommandKernelTests/testValueTraceMatchesEnginePrecedenceAndClearsTheWinnerInOneStep`,
  `SiteForgeTests/ProjectResourceTests/testAssetUsesRetargetToAnotherAssetAndUnusedAssetsAreRemovedInOneStep`,
  `SiteForgeTests/CanvasRendererTests/testSocialPreviewTagsSitemapRobotsAndSEOWarningsInExport`,
  `SiteForgeTests/PersistedHistoryTests/testWebsiteMetadataVersionTwoSiteAddressAndSocialImageAreStrictAndTracked`,
  `SiteForgeUITests/SiteForgeLaunchTests/testValueSourcesShowWinnerAndClearItJourney`, and every test that
  adds fluid values (TransformModelTests fluid tests) for the new refusal.

## Suggested first checks for Codex

1. `ValueTraceStep.Source.layout(String)` — exhaustive switches: `sourceTitle`, `canClearWinner`
   (TransformModel) and `WorkspaceShellState.revealValueSource` (`.defaultValue, .desktop, .local, .fluid, .layout`).
2. `CanonicalValueTrace.trace(…, layout: (value: Double, source: String)? = nil)` and the shell call
   `guard case .computed(let value, let source) = geometryInspectorValue(for: field)`.
3. `FluidValueCommandError.containerQueryConflict` in `errorDescription` and `FluidValueDiagnosticFactory.category`.
4. `CommandDiagnostics.recordAssetDependencyOperation` — `assetIDs.map(\.commandTarget)` uses the file-private
   `StableIdentifier.commandTarget` extension (same file).
5. `ValueTraceInspectorView.settingRow` — `DisclosureGroup(isExpanded:) { … } label: { Button { … } label: { … } }`;
   UI journey clicks `inspector.valueTrace.width` and reads its value "…, from Set here · Desktop, …".
6. `ImageAssetDependencies.retarget` collection rewrite (`collections[c].items[i].values[v].value`) and the
   `setCollections` availability; `usedAssetIDs` equality with the per-asset scans (new ProjectResource test).
7. `StaticSEOAudit.findings` over `CollectionTemplates.outputPages` — existing count of 3 duplicates in
   `testSocialPreviewTagsSitemapRobotsAndSEOWarningsInExport`; new fixture's `CollectionTemplate(pageID:)` validates.
8. `WorkspaceShellState.imageAssetReferences` cache key (`String(describing: variantEditingTarget)`).

## Out-of-area notes (not fixed)

- `deleteImageAssetAndUses` does not detach collection or translation uses; deleting such an asset is refused
  with the registry's reason (now announced). Owner of Delete with Uses (SF-0806/OD-035/OD-038) may extend it.
- Lane RE gap 2 (orphaned-language translations count as uses) stays as lane E/V11 decided ("still stored").
- Value-source Clear while editing a component variant goes through the session's authoring conversion point
  like every other Inspector edit; worth one manual check by Codex.
