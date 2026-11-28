# ADR-0062 — Page variables, visibility conditions and overlays on the event graph

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-039 (approved by the owner 2026-11-26 1:30 PM EST); builds on ADR-0061
- Requirements: SF-1105-001 … SF-1105-008, SF-1106-001 … SF-1106-008 (first slice)

## Context

OD-039 adds bounded runtime variables (boolean, number, string) and overlays,
modals and menus built on the event graph, compiled to SiteForge's own
generated runtime with no authored JavaScript.

## Decision

- Page variables (`CanonicalStateVariable`, `CanonicalVariableValue`) are
  stored on the page Root as canonical JSON text in `state.v1.variables`
  (exact keys `id`, `name`, `type`, `initial`; at most 16; unique ids and
  names; names 1–64 bytes without control characters or outer spaces).
  Types: boolean, whole number (|n| ≤ 1,000,000,000, so the text has one
  canonical form) and text (≤ 256 bytes). Scope is the page; values reset on
  every load, so nothing is stored and no consent is needed (session,
  persistent and URL scopes are later slices).
- `state.v1.visibleWhen` on any supported object (not the Root): canonical
  JSON `{equals, variable}`. The object is shown only while the variable has
  that value.
- `CanonicalOverlay` (`overlay.v1.kind` = modal | popover | menu,
  `overlay.v1.dismissOutside`) on frames, sections, stacks and grids, never the
  page Root.
- New actions: Set Variable (typed value), Flip True or False Variable, Open
  Overlay, Close Overlay. Each action carries exactly the fields its kind uses.
- Removed variables and non-overlay targets keep their references; output
  drops them and Check Website reports them. Errors:
  `ModelValidationError.invalidRuntimeState`, `.invalidOverlayState`. Still
  document schema 27; schema 26 files with `state.` or `overlay.` keys are
  refused.
- Editing goes through the shared effect registry (`DecorativeEffectEdit`
  `.pageVariables`, `.visibility`, `.overlay`): one undo entry per edit,
  property identity kept. UI: Page Variables on the page background; Overlay
  and Visibility for one selected object; variable and overlay actions in
  the Interactions editor.
- Output (hydration-safe): the initial HTML already matches the starting
  values. Overlays and objects whose condition is false at the start get
  `hidden`; overlays get `data-siteforge-overlay`, `role="dialog"` (plus
  `aria-modal="true"` for modals) and `data-siteforge-dismiss-outside` when
  set; conditions become `data-siteforge-visible-when`; the page's variables
  travel as escaped JSON in `<div hidden data-siteforge-state>` before the
  runtime script. Two single-line CSS rules: modals are centered and fixed
  while open, plus a backdrop.
- Runtime (`siteforge-events.js`): typed writes only (a value of another type
  is ignored); bindings re-render on change. Overlays form a stack (z-index
  1000 + 2 per level); opening puts focus on the first focusable item;
  Escape closes the top one; closing one closes those opened after it and
  returns focus to the control that opened it; a modal has a backdrop and
  traps Tab and focus; popovers and menus close on outside pointer-down when
  set; a menu closes after one of its links or buttons is used; opening an
  open overlay from the same control closes it.
- Findings (warnings, node ids only): `state-binding-invalid`,
  `overlay-unreachable` (nothing on the page opens it), `overlay-unnamed` (no
  Accessible name); `interaction-target-missing` also covers variables,
  wrong-typed values and non-overlay targets.

## Consequences

- Popovers and menus open where they are drawn; positioning relative to the
  trigger, portals and arrow-key menu navigation are not in this slice.
- Without JavaScript, overlays and objects hidden at the start stay hidden.
- Changing a variable's type leaves its uses to be updated (reported).
- Interactions copied to another page or project keep their references and
  are reported there.

## Reversal

Stop emitting the attributes, state data and CSS and hide the sections; keep
reading `state.v1.` and `overlay.v1.` data so documents stay valid.
