# ADR-0032 — Responsive audit

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Requirements: SF-0606-001 … SF-0606-008; supporting SF-1605 (target size), SF-0602

## Context

Compare Screen Sizes already reviews horizontal boundary overflow for the
selection. SF-0606 asks for a reproducible audit across representative widths
(overflow, collisions, truncation, tap targets, unreachable breakpoint
settings), jumping to failures and suppressing intentional findings.

## Decision

- Samples: Desktop 1440, Tablet 768, Mobile 390 (the canvas presets).
- Each sample is prepared exactly as the canvas and Preview prepare it
  (`WorkspaceScenePreparationWorker`), and the checks read the drawn objects and
  the expanded page (container queries applied), so a finding is reproduced by
  opening that width.
- Checks: overflow (visible part beyond the page's sides, after clipping);
  collision (text, image or control overlapping another under the same parent,
  at most 400 compared per parent); truncation (fixed-height text needing more
  height, measured with `ResponsiveTextMetrics`, the canvas text layout);
  tap target (buttons and links below 24 pt, WCAG 2.2 SC 2.5.8); unreachable
  override (a stored object hidden at a breakpoint that has its own geometry or
  container setting there).
- A finding carries kind, page and object identity (and the other object for a
  collision), sample, bounds and the measured number; its identity is stable.
- Suppression is per object and kind, stored as
  `responsive.audit.v1.suppressed` (sorted kinds), part of document schema 27
  and clipboard version 8, edited as one property command. Objects that exist
  only inside component copies are suppressed in the original.
- The audit runs off the main actor, is cancellable, and a report is shown only
  while it matches the current revision and page.

## Consequences

- No automatic fixes; repairs are described per finding.
- Collisions between decorative frames are not reported (only content objects).
- Overflow is measured against the page's sides with only content-clipping
  ancestors applied. The scene's own clip always includes the page bounds, so
  it is not used for this check (ADR-0143).
- Runs, cancellations and suppressions leave a sanitized
  `ResponsiveAuthoringDiagnostic` (ADR-0143).

## Reversal

Remove the section, runner and checks, and the suppression key from validation
and the schema-27 gate.
