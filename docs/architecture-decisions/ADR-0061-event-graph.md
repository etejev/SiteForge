# ADR-0061 — Declarative event graph and generated interaction runtime

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-039 (approved by the owner 2026-11-26 1:30 PM EST)
- Requirements: SF-1101-001 … SF-1101-008 (runtime variables and overlays follow in a later batch: SF-1105, SF-1106)

## Context

OD-039 chooses a declarative event graph (trigger → action list) with a fixed
action set, compiled to a small generated runtime script, with no authored
JavaScript. Runtime variables and overlays/menus build on it later.

## Decision

- `CanonicalEventGraph` (DecorativeEffects.swift) lives on the trigger node in
  the closed `event.v1.` namespace:
  - `event.v1.interactions`: canonical JSON text (sorted keys, no escaped
    slashes, at most 16 KiB) of 1–8 `CanonicalInteraction` values in authored
    order. Each has `id` (UUID), `trigger` and 1–8 actions with `kind` and
    either `target` (node) or `page` (navigate). Exact keys; the stored text
    must equal its re-encoding, so forged or reformatted data is refused.
  - `event.v1.startsHidden`: present only as `true`.
  Errors are `ModelValidationError.invalidInteractionGraphState`. Still
  document schema 27; a schema 26 file with any `event.` key is refused.
- Triggers: click, pointer-enter, pointer-leave, focus-in, focus-out,
  page-load, viewport-enter. Click is allowed only on buttons and links so it
  is always keyboard- and VoiceOver-operable. Actions: show, hide, toggle
  (visibility), focus, scroll-to, navigate (website page). State toggling is
  expressed with runtime variables in the later SF-1106 batch.
- Supported trigger kinds: frame, text, section, stack, grid, image, button,
  link; form fields are skipped with a reason.
- A deleted target keeps its reference (validation still passes); output
  leaves the action out and the build reports it.
- Editing: `DecorativeEffectEdit.events(CanonicalEventGraph?)` through the
  shared effect registry (one undo entry, property identity kept). UI: an
  Interactions group (`InteractionInspector`) with Start hidden, a trigger
  picker per interaction, ordered action rows (kind, target or page) and
  add/remove buttons.
- Output (`EventGraphOutput`, `EventOutputConfiguration`, `EventGraphRuntime`):
  - trigger nodes get `data-siteforge-events` (escaped JSON: trigger, action
    kind, lowercase target node id or a build-relative page path);
  - start-hidden nodes get `hidden` in the initial HTML plus one CSS line
    `[data-siteforge-node][hidden] { display:none !important; }`, so the first
    render already matches the runtime state;
  - pages with interactions load `siteforge-events.js` (written once);
  - the runtime binds listeners in authored order (deterministic), runs
    page-load actions in document order, observes viewport-enter once, finds
    targets only by validated UUID, refuses navigation to anything with `:`,
    a backslash or a leading `//`, scrolls without smooth motion when Reduce Motion
    is on, sets `aria-expanded` on button triggers for visibility actions, and
    stops re-entrant chains after four steps.
- Build findings (warnings, node ids only): `interaction-target-missing`
  (SF-1101-004), `interaction-pointer-only` (pointer triggers with no focus or
  click trigger, SF-1101-006), `interaction-focus-loop` (focus-in → focus
  cycles, SF-1101-003).

## Consequences

- Without JavaScript, start-hidden content stays hidden and actions do not
  run; links and buttons keep their normal behavior.
- A third runtime file joins the others until OD-042's single runtime.
- No canvas playback of interactions.

## Reversal

Stop emitting the attribute, script and CSS and hide the group; keep reading
`event.v1.` data so documents stay valid.
