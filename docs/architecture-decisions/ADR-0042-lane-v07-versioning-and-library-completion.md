# ADR-0042 — Lane V07 review: versioning and library completion rules

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-043 and OD-046 (approved 2026-11-26 1:30 PM EST); owner request 2026-11-26 6:55 PM EST
  ("finish partial features too"); owner-approved addition 2026-11-26 (lane V02 finding, reusable styles in libraries)
- Builds on: ADR-0038, ADR-0039, ADR-0040, ADR-0041
- Requirements: SF-1301-003, SF-1301-006, SF-1306-001, SF-1306-003, SF-1306-007, SF-0906-004, SF-0906-006, SF-1803

## Context

The lane V07 verification of batch 18 part 1, E01, A02, A03, A04 and the lane RA fixes found that the structural
comparison could still hide a difference behind other changes, that restore, library import and update reached the
component-variant conversion point with an unrelated message, that library export refused several kinds of
components with the generic "could not be stored", and that the Snapshots sheet offered no way to see what a
restore would change before choosing it.

## Decision

- Comparison (`ProjectComparer`): a page's origin is its own change ("Page origin"); order-only changes of images,
  guides and color tokens are moves ("Image order", "Guide order", "Token order"), using the same longest-run rule
  as pages and layers. "Other project data" stays as the safety net. No format change.
- Restore preview (SF-1301-003): the restore panel's **Review Changes…** closes the Snapshots sheet and opens Compare
  Versions with the current document as the baseline and the snapshot as the other side
  (`WorkspaceShellState.previewSnapshotRestore`). Gated by `versions.compare`, which the Snapshots sheet now observes.
- Open component variant: `WorkspaceShellState.canReplaceProjectContent` is false while a variant is being edited.
  Restore (state and sheet), Import Library…, Update… and Apply Update are disabled with the reason
  `WorkspaceShellState.variantOpenReplacementMessage`; `restoreSnapshot` refuses with it and changes nothing.
- Library export refusals (SF-0906-004), each naming the component: `usesVideoOrAudio`, `usesTranslations`,
  `usesProjectFonts` (a text family that matches a project font, case-insensitive), `linksOutside` (a page or
  section link to a page other than the definition itself), `usesReusableStyle(component, style)` (an applied
  reusable style whose definition is stored outside the exported components; styles defined inside them travel).
  `recordTooLarge` replaces the misleading `tooManyLibraries` when the record would exceed 256 KiB.
- Not built, pending OD-050: automatic snapshots with pruning, rendered/visual comparison, and images, fonts,
  video/audio, translations and outside reusable styles carried inside library files.

## Consequences

- Comparison lists can contain more entries than before for the same two versions (order moves, page origin).
- A component that previously failed export with the generic message now names the reason; a component whose page
  links previously exported with dangling links (if model validation accepted them) is now refused.
- No document schema (27), persisted-history (4), WebsiteMetadata (3), package or clipboard change.

## Reversal

Remove the new entries, cases and the state property; behaviour returns to ADR-0038–0041 as written before.
