# ADR-0086 — Site languages: right-to-left layout on the canvas (part 4c, second half)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-038 (approved by the owner 2026-11-26 1:30 PM EST)
- Builds on: ADR-0082 (per-language export writes `dir`), ADR-0085 (language shown on the canvas)
- Requirements: SF-1007-002 (preview of a language), -003 (resolution explained), -004 (failure and
  recovery), -008 (tests); SF-1506-003 (resolution rules)

## Context

Export writes `dir="rtl"` for a right-to-left language (ADR-0082), so a browser lays out flex and grid
containers from the right. ADR-0085 showed a chosen language on the canvas but kept the default
left-to-right layout, so an Arabic or Hebrew page looked different on the canvas than in the browser.

## Decision

- **Mirror exactly what `dir="rtl"` changes.** `SiteRightToLeftCanvasLayout.mirrored` (`DocumentModel.swift`)
  takes the resolved page geometry and, parents before children, mirrors inside its parent every child that
  the parent lays out: Stack, Section, Form, Grid and padded Frame children (export: flex/grid, so they run
  from the right) and page navigation links of a header or footer whose links the parent lays out. Children
  that a natural-flow page frame or an unstyled Frame places absolutely (export: `left:` offsets, which
  `dir` does not change) keep their offset from the parent's left edge and move with the parent. Page roots
  keep their place on the artboard. Vertical positions and sizes never change. Mirroring twice gives the
  original geometry. The rule mirrors the same parents `DocumentPage.resolvedStructuralGeometry` lays out.
- **When.** Only while a shown language other than the default reads right to left
  (`SiteRightToLeftCanvasLayout.isMirrored`, `WorkspaceShellState.canvasMirrorsRightToLeft`). The flag
  travels in `WorkspaceScenePreparationRequest.mirrorsLayoutRightToLeft` (default `false`, so other
  requests — responsive comparison, build-finding reveal — are unchanged). Render frames, content clips,
  absolute/fixed positioning offsets, hit testing and selection all use the mirrored frames, so Local Preview
  (which captures the canvas plan) shows the mirrored layout too. A direction change in the Languages
  sheet, Undo, or showing another language re-renders because the revision or the shown language changes.
- **Editing.** Mirrored frames are not the frames a transform changes, so pointer and keyboard moving and
  resizing (`beginPointerTransform`, `beginTransform`) are refused while the canvas is mirrored, with the
  recovery "Show the default language to change the layout." Inspector edits keep working and show live.
- **Status.** The Canvas Language status says the canvas mirrors the layout the way exported pages do and
  that moving and resizing are off (`SiteRightToLeftCanvasLayout.statusNote`).
- No schema change: document schema 27, persisted-history schema 4, website metadata version 3; no new
  `CanonicalDocument` or node key; no new command; no new feature flag.

## Consequences

- Not built: a default language that is itself right to left is still shown unmirrored (export writes
  `dir="rtl"` for it); mirroring it would need transforms that work in mirrored coordinates.
- Not built: text paragraphs on the canvas keep their left alignment and natural base direction. Export
  writes `text-align: left` for authored typography (unchanged by `dir`), but text without authored
  typography is right-aligned by the browser in a right-to-left tree; the canvas does not do that yet.
- Not built: Website Preview opening at the shown language's address.
- Codex must verify compilation of the `if … , let activePage { … } else { … }` expression in
  `WorkspaceScenePreparationWorker.prepare`, the tuple return of the private `childRule`, the exhaustive
  `NodeKind` switch, the new defaulted init parameter, and the new test; and that no existing test runs a
  transform while a right-to-left language is shown.
