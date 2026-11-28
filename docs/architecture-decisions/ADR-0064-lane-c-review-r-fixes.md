# ADR-0064 — Lane R review of lane C: hidden rule, overlay visibility and static-layout containers

- Status: Proposed (implemented as an unverified Code Forge candidate by lane R reviewer C; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-039 (approved); review of ADR-0061 … ADR-0063
- Requirements: SF-1101-004, SF-1105-003/004, SF-1106-003 (hydration-safe first render)

## Context

The lane R review of batches C01–C04 found four output defects and one
unsupported layout case:

1. `[data-siteforge-node][hidden] { display:none !important; }` was written
   only when some object started hidden. Static (absolute) layout gives every
   object `display: block`, which wins over the browser's own `[hidden]`
   rule, so Hide, Show or Hide and visibility conditions that only hide an
   object later did nothing on those pages.
2. A visibility condition on an overlay let the runtime show the overlay on
   load or on a variable change outside the overlay stack (no backdrop, no
   focus handling, Escape could not close it).
3. Show, Hide and Show or Hide aimed at an overlay changed `hidden` directly,
   with the same result, and Check Website reported such an overlay as never
   opened.
4. An object with Start hidden and a condition that is true at the start was
   written with `hidden`, but the runtime showed it on load, so the first
   render did not match the runtime state.
5. On a page without page flow or automatic sizing every object is written as
   its own absolutely placed element, so a container's contents are not
   inside its HTML element: hiding, showing or opening the container leaves
   them as they are, and a modal cannot keep focus on them.

## Decision

- Every page that loads `siteforge-events.js` also gets the hidden rule.
- An overlay never carries `data-siteforge-visible-when`; Check Website warns
  `overlay-condition-ignored` (SF-1105-003) and the Overlay and Visibility
  section explains it instead of offering a condition.
- The runtime treats Show and Show or Hide on a hidden overlay as Open
  Overlay, and Hide and Show or Hide on an open overlay as Close Overlay;
  other visibility actions on an overlay do nothing. Check Website counts Show
  and Show or Hide as openers.
- A valid visibility condition, not Start hidden, decides whether an object
  starts hidden (the runtime applies bindings on load).
- Check Website warns `interaction-container-flat` (SF-1101-004) for a
  container with children that is hidden, shown, opened or conditioned on a
  page without page flow or automatic sizing. Support for those pages is
  remaining work (see the lane RC review report).

## Consequences

- Pages with interactions carry one more stylesheet line.
- Two new warning codes; no stored data, schema or clipboard change.

## Reversal

Remove the two findings, the runtime mapping and the planner condition; no
document data depends on them.
