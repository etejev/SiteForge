# ADR-0040 — Version comparison (structural snapshot diff)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-043 (approved by the owner 2026-11-26 1:30 PM EST)
- Requirements: SF-1306-001 … SF-1306-008 (structural comparison; rendered/visual comparison not in this slice)
- Builds on: ADR-0038 (local named snapshots)

## Context

OD-043 asks for a structural/visual diff between two snapshots. SF-1306 asks to
compare versions, filter changes, inspect before/after and export a review
report, and requires that diffs distinguish reordering from recreation and that
visual comparisons declare their viewport, data and font context.

## Decision

- Model (`SiteForge/ProjectPackage.swift`, after `ProjectSnapshots`):
  `ProjectComparisonSource` (a snapshot or the current document; `resolve`
  reads it from an immutable package copy), `ProjectComparer.compare`, and the
  value types `ProjectComparison`, `ProjectComparisonChange`,
  `ProjectComparisonArea`, `ProjectComparisonChangeKind`,
  `ProjectComparisonError`, `ProjectComparisonDiagnosticRecord`.
- Matching is by stable identity only (pages, nodes, properties, image assets,
  guides, color tokens). An object with a new identity is removed + added even
  when its name, key and value are equal (recreation). Order changes use one
  longest common increasing run (`movedIdentifiers`): only objects outside it
  are "moved", so an insertion or removal never marks neighbours as moved.
  A node whose container changed is reported once as moved ("Container").
  Property order is not compared. Website metadata, project preferences,
  build settings (`ProjectPreferences.build`, ADR-0122), collections, site
  languages, project fonts and video/audio files are reported as one
  "changed" entry each when they differ. A page's origin ("Page origin") and
  the order of images, guides and color tokens ("Image order", "Guide order",
  "Token order", moved) have entries of their own, so they are never hidden
  behind other changes (lane V07 review, ADR-0042). Any other difference (data
  without a comparison of its own) is reported once as "Other project data",
  so two different versions are never shown as identical.
- Areas: Pages, Layers, Properties, Images, Guides, Color Tokens, Settings.
  Kinds: added, removed, changed, moved. Values are shown as text, control
  characters replaced, clipped at 160 characters.
- Bounds: at most 5,000 changes are listed (`isTruncated`, stated in the
  summary and report). The comparison checks cancellation per page and every
  256 nodes.
- Determinism: the same two versions always give the same list; change IDs are
  list positions.
- Report: `ProjectComparison.report()` — Markdown, grouped by area, with both
  names and revisions and the statement that this is a structural comparison
  with no viewport, data or font context.
- UI (`SiteForge/WorkspaceShellView.swift`): File menu **Compare Versions…**
  opens a sheet (`ProjectComparisonSheet`) with Baseline / Compared with
  pickers (any snapshot or the current document; default newest snapshot vs
  current), Compare / Cancel, filters (area, kind, text), a lazy change list
  with before → after, Copy Report, Export Report… (save panel, plain text)
  and Close (Escape). Empty state offers Create Snapshot directly. Damaged
  snapshot storage shows the reason and Delete All Snapshots… (confirmed).
  A result read from the current document is labeled stale once the document
  revision changes, with Compare Again.
- Execution (`ProjectComparisonModel`, main actor): each run captures the
  package and head, runs in a detached task, and carries a generation; a newer
  run, Cancel or closing the sheet makes older results stale and they are
  ignored. Comparing never edits the document or the package.
- Diagnostics: `ProjectComparisonDiagnosticRecord` (SF-1306-008, duration,
  change count, truncated, result, failure category); no names, values or IDs.
- Feature flag `versions.compare` (`FeatureFlagID.versionComparison`, default on,
  remove by 2027-03-31, SF-1306; owner decision 2026-11-26 6:01 PM EST, batch A04)
  gates the menu item, the Snapshots sheet's Compare button and
  `presentProjectComparison`. No document schema, package, history or
  clipboard change.

## Consequences

- No rendered/visual comparison yet (a later slice would have to declare
  viewport, data and font context). Image bytes are compared by content hash
  only.
- The sheet is a window-modal sheet, not a separate window, like the other
  project sheets.
- The Snapshots management UI (lane E item E0) can open the sheet with
  `WorkspaceShellState.presentProjectComparison(baseline:target:)`.

## Reversal

Remove the menu item and sheet; the model has no stored state.
