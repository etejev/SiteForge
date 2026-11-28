# ADR-0060 — CSS-first motion: state transitions and reveal on scroll

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-040 (approved by the owner 2026-11-26 1:30 PM EST)
- Requirements: SF-1103-001 … SF-1103-008, SF-1104-001 … SF-1104-008 (first slice)

## Context

OD-040 chooses CSS-first motion: transitions and keyframe animations on state
changes and viewport-entry triggers, honoring `prefers-reduced-motion`, with
no timeline editor in the first slice.

## Decision

- `CanonicalMotion` (DecorativeEffects.swift) lives in node properties under
  the closed `motion.v1.` namespace. Two optional, all-or-nothing groups:
  - transition: `transition.duration` (whole ms, 50–2000), `transition.easing`;
  - entrance (reveal on scroll): `entrance.effect` (fade, rise, zoom,
    slide-from-left, slide-from-right), `entrance.duration` (whole ms,
    100–3000), `entrance.delay` (whole ms, 0–3000), `entrance.distance`
    (whole px, 0–400; kept but unused by fade and zoom), `entrance.offset`
    (trigger line, whole percent of the viewport height above its bottom,
    0–50), `entrance.easing`.
  Easing is one of ease, linear, ease-in, ease-out, ease-in-out. An omitted
  group means no motion; any other `motion.` key, a partial group, a wrong
  value type, an unknown value or an unsupported kind fails validation with
  `ModelValidationError.invalidMotionState`.
- Supported kinds: frame, text, section, stack, grid, image, button, link.
  Component instances and form fields are skipped with a reason.
- Still document schema 27 (unreleased); a schema 26 file with any `motion.`
  key is refused.
- Editing: `DecorativeEffectEdit.motion(CanonicalMotion?)` through the shared
  `DecorativeEffectCommandRegistry` (lock, hidden, stale, history, property
  identity, one undo entry). The design-style preview names the operation
  "motion". UI: a Motion group in the Design inspector (`MotionInspector`).
- Output (`MotionOutput`, `MotionRuntime`):
  - transition: `transition-property:background-color,opacity` with the
    authored duration and easing, inside `prefers-reduced-motion:no-preference`;
  - entrance: one `@keyframes sf-entrance-<node>` (`from` only: opacity 0 plus
    the effect's transform, so the end state is the element's own style), a
    hide rule and an animation rule, both inside
    `screen and (prefers-reduced-motion:no-preference)` and both requiring
    the runtime's `sf-motion-ready` class on `<html>`, so content is visible
    with scripts off, in print and with Reduce Motion. Only opacity and
    transform change: no layout shift.
  - Each motion CSS line is one complete rule, so the release profile's
    line de-duplication cannot split it.
  - Reveal nodes carry `data-siteforge-entrance="<offset>"`; pages with one
    load `siteforge-motion.js` (written once per site). Any motion links
    `styles.css`.
  - The runtime groups elements by trigger line (one IntersectionObserver per
    line, `rootMargin` bottom inset), reveals once, reveals everything when
    Reduce Motion is on or turns on, when IntersectionObserver is missing, when
    the page bottom is reached (so the last screen never stays hidden) and
    when keyboard focus enters a hidden element; it then removes its
    listeners. No author text, network or storage.

## Consequences

- An element may be visible for a moment before the deferred runtime adds
  `sf-motion-ready` and hides it for its entrance (a short flash on slow
  loads). Accepted to keep content visible without JavaScript.
- An entrance `from` transform replaces the element's own transform during
  the animation.
- Not built (later OD-040 slices if wanted): timeline editor, parallax,
  pinning, scroll-progress effects, canvas playback.
- Another runtime file joins `siteforge-effects.js` and
  `siteforge-navigation.js` until OD-042's single hashed runtime (lane E2).

## Reversal

Stop emitting motion output and hide the Motion group; keep reading
`motion.v1.` data so documents stay valid.
