# ADR-0028 — Linked border, corner radius and shadow in reusable styles

- Status: Proposed (implemented as a Code Forge candidate; compiled by Codex's integrity repair on
  2026-11-25, its tests not yet run; awaiting Codex verification)
- Date: 2026-11-25
- Owners: Product / Engineering
- Requirements: SF-0510-001, SF-0510-002, SF-0510-003, SF-0510-004, SF-0510-005, SF-0510-006, SF-0510-007, SF-0510-008; supporting SF-0506-003/005, SF-0308-003/004, SF-1204-003

## Context

Reusable styles (`style.reusable.v1.`) stored only a solid fill and opacity
(evidence `SF-SOURCE-BATCH-20261027-06-REUSABLE-STYLES.md` explicitly deferred
borders and shadows). Box appearance (`style.box.v1.`, SF-0506) was object-only.
Roadmap batch 3 ("Reuse depth") asks for a bounded shared-style workflow that
preserves exact inheritance and history. The owner approved extending reusable
styles with border, corner radius and outer shadow.

## Decision drivers

- One precedence rule for canvas, Inspector, in-app Preview, Browser Preview and export.
- An object's own value always remains explicit, inspectable and removable.
- Older projects open unchanged; older builds never silently drop the new values.
- No change to layout: padding and clip-content are read directly by layout
  (about 25 call sites), so they stay object-only.

## Considered options

1. Store box values as a separate "box style" object. Rejected: a second shared
   style concept with its own link list, ordering and Inspector.
2. Extend the existing reusable-style definition with optional box groups. **Chosen.**
3. Include padding and clip-content. Deferred: requires layout to resolve
   linked values, which is a separate, larger change.

## Decision

- **Storage.** A definition may carry three optional, all-or-nothing groups as
  `style.reusable.v1.definition.<id>.<field>`: border (`borderWidth`,
  `borderColor`, `borderStyle`), `cornerRadius`, and shadow (`shadowColor`,
  `shadowOffsetX`, `shadowOffsetY`, `shadowBlur`, `shadowSpread`). Colors are
  canonical `#RRGGBBAA` strings (RGBA8), as for linked fills. Ranges match
  SF-0506. A definition must supply at least one of fill, opacity or a box group.
  `CanonicalReusableBoxAppearance` is the single codec for document, history
  and clipboard; a partial group, non-canonical color, wrong type, unknown
  field, repeated field or out-of-range value is invalid (never dropped).
- **Schema.** Document schema 22 → 23. Schema 22 and older open unchanged; a
  file declaring schema < 23 that contains box fields is rejected. Clipboard
  envelope 4 → 5, used only when copied styles carry box values; older readers
  refuse v5 instead of losing values.
- **Precedence** (`CanonicalLinkedBoxStyleResolver`), separately per group:
  the object's own value (including an authored zero or a disabled own shadow);
  otherwise the last applied style in the object's ordered list that supplies
  the group; otherwise nothing. Each value reports its source (`local`,
  `linked(styleID)`, `unset`). A linked shadow is always enabled. Color tokens
  bind only to an object's own border/shadow color; linked colors are literals.
- **Editing** (`AdvancedStyleCommandRegistry`), each one transaction with an
  exact inverse: create/update a style with box values; `setReusableStyleBox`
  replaces a style's box groups; `useLinkedBox(group)` removes only the
  selected objects' own value for that group (refused for the whole selection
  if any object lacks a linked supply, and while a token is bound to that
  border/shadow color); `captureBoxSelection` stores what the selection shows,
  reports groups that differ instead of averaging, ignores a disabled shadow and
  snapshots token colors.
- **Output.** The canvas scene, in-app Preview (built from the canvas scene),
  static export and Browser Preview resolve through the same rule. Export emits
  per-object declarations (no shared CSS class), matching existing reusable
  fills. Style definitions never appear in output.
- **Inspector.** Each border, corner radius and shadow value names its source
  ("Base local border", "Base linked border: Card", "Default / omitted
  border", "Mixed border sources"). The Reusable Styles panel offers Create
  Box Style, Update Box and Use Linked Border / Corners / Shadow, each enabled
  only when the registry would accept it. The workspace builds the style index
  once per document value and passes it to the registry and capture.

## Consequences

### Positive

- Shared border/corner/shadow changes propagate to every linked object in one
  undoable edit, identically on canvas and in exported sites.
- Copy/paste between projects keeps these values and detects look-alike styles.

### Negative or risky

- Every save writes schema 23 or later (schema 24 adds nested component
  instances, ADR-0018 amendment); builds before this change cannot open new saves.
- The Design Inspector shows the effective (linked) value. Editing a shown
  linked value writes an explicit own value on that object; Remove is disabled,
  with an explanation, for a value that only a linked style supplies.
- Export flattens per object; a shared CSS class would be smaller but changes
  output structure (not done).

## Verification

Unit tests in `TransformModelTests`, `ClipboardTransferTests` and
`CanvasRendererTests` (listed in `docs/coordination/CODE_FORGE_ACTIVITY.md`,
batch 04) cover the codec, schema gate, precedence and provenance, editing and
undo, capture, clipboard v5, canvas/export agreement and standard/large/stress
scale. None has been executed when this ADR was written.

## Reversal

The groups are optional fields under an existing namespace. Removing them needs
a schema that drops the fields after an explicit migration that materializes
linked values onto objects (the same transformation as detaching a style).
