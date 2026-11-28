# ADR-0063 — Lane C review fixes: modal portal, unreachable actions, instance checks

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-039 (approved); review of ADR-0060 … ADR-0062
- Requirements: SF-1101-003, SF-1105-003/006

## Context

A review of lane C batches C01–C03 found:

1. An open modal stayed inside its authored parent. An ancestor with a
   transform, filter, `backdrop-filter`, `isolation` or a filling entrance
   animation (C01) becomes the containing block and stacking context, so the
   fixed, centered modal could be placed relative to that ancestor and drawn
   under its own backdrop (which is appended to `<body>`).
2. SF-1101's invariant says unreachable actions are diagnosed; actions after
   Go To Page in the same interaction never run and were not reported.
3. Interaction findings were computed on unexpanded pages, so interactions and
   overlays inside component instances were never checked.

## Decision

- Runtime: opening a modal leaves a comment placeholder at its place and
  moves the element to the end of `<body>` after its backdrop (a portal).
  Closing hides it and puts it back at the placeholder. Popovers and menus
  stay in place (they keep their authored position). Event listeners, focus
  trap and Escape are unchanged.
- New warning `interaction-action-unreachable` (SF-1101-003): counts actions
  after the first Go To Page whose page is built. The Interactions editor shows
  the same hint inline.
- `StaticBuildCompiler.compile` expands component instances before
  `EventGraphOutput.findings`, like the existing page-flow checks.

## Consequences

- An open modal inherits text styles from `<body>` rather than from its
  authored parent; SiteForge styles are set per object, so this matters only
  for inherited properties the author set on an ancestor.

## Reversal

Remove the move to `<body>` and the finding; nothing is stored.
