# ADR-0065 — Lane V09: trigger-relative overlay placement, menu keys, static-layout containers and browser-run runtime tests

- Status: Proposed (implemented as an unverified Code Forge candidate by lane V09; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-039 (approved: "overlays and menus built on it"), OD-040 (approved); verification of ADR-0060 … ADR-0064
- Requirements: SF-1101-004/008, SF-1104-004/006/008, SF-1105-002/004/006/008, SF-1106-002 (validation feedback)
- Supersedes: the `interaction-container-flat` warning of ADR-0064 (the case is now supported)

## Context

Lane C left these features partly built (plan items C5 and C10, lane RC gaps R1–R5):

1. A popover or menu could only open where it is drawn (SF-1105-002 "position relative to triggers"), and
   menus had no arrow-key navigation (SF-1105-006).
2. On a page without page flow or automatic sizing, static layout writes every object as its own absolutely
   placed element, so a container's contents are not inside its HTML element. Hiding, showing or opening a
   container, its reveal on scroll, and a modal's focus trap did not include its contents (ADR-0064 only
   warned about it).
3. Scrolled Into View interactions never ran without IntersectionObserver (R2).
4. Variable name and value fields dropped invalid input silently (R1).
5. The clipboard definition fingerprint hashed interactions as raw text, so an identical definition from
   another project was never reused (R3).
6. Create Component did not refuse inbound interaction targets on moved contents (R4).
7. The generated runtimes had no actual-browser tests (C10; the harness files were unreadable on Windows until
   the owner downloaded them on 2026-11-26 at 7:40 PM).

## Decision

- `overlay.v1.placement` (optional; `below`, `above`, `start`, `end`) is stored only for a popover or menu; a
  modal is always centred and a modal with a placement is invalid (`invalidOverlayState`). The key lives in
  the existing `overlay.` namespace, so the schema-27 gate, copy paths, comparison and snapshots already
  cover it; no new CanonicalDocument key, still document schema 27, history schema 4, WebsiteMetadata 3.
  Edits go through the existing effect registry (one transaction, property identities kept). The Overlay
  and Visibility section offers "Opens" (Where It Is Drawn / Below / Above / Before / After the Trigger) for
  a popover or menu; choosing Modal Dialog clears it.
- Output writes `data-siteforge-placement`. The runtime places the overlay next to the object whose
  interaction opened it, moves it to the opposite side when it does not fit, follows the reading direction
  for start and end, clamps it 8 px inside the viewport and re-places it on resize and scroll. It moves the
  overlay (and its contents) with the CSS `translate` property, so layout never changes and the entrance
  `transform` is untouched; closing resets it.
- In a menu, Arrow Down / Arrow Up (wrapping), Home and End move focus between its links and buttons while
  focus is in the menu or on its opener.
- `FlatContainerOutput` (static-layout pages only): each content element of a container that the website
  hides, shows, opens or reveals carries `data-siteforge-within="<container ids, outermost first>"`; an
  overlay with contents carries `data-siteforge-flat`. Contents follow their container in paint order, so
  one sibling rule per container, `[data-siteforge-node="X"][hidden] ~ [data-siteforge-within~="X"] {
  display:none !important; }`, hides them without scripts (hydration-safe, works with JavaScript off). Two
  gated rules per revealed container hide its contents until the reveal and play the same animation on them;
  the motion runtime reveals contents with their container and reveals the container when focus lands in a
  content element. The interaction runtime treats contents as part of an overlay for focus, the modal focus
  trap, outside clicks, the menu close rule, z-order and placement. A modal with separately written contents
  keeps its static box (the centring rule excludes `[data-siteforge-flat]`), is not moved to the end of
  `<body>` (it already sits there) and is centred with its contents by the runtime. Form fields are written
  inside their form, so the form carries the attribute. The release CSS optimizer keeps these rules
  (`~=` is never removed). `interaction-container-flat` is no longer reported.
- Without IntersectionObserver, Scrolled Into View interactions run once at load.
- Variable name, number and text fields keep an invalid entry with a caption that says why (whole number
  range, 256 bytes without control characters, name rules, unique names); the document is unchanged.
- The definition fingerprint describes interactions without their identities, with targets inside the
  definition by position (like link targets), pages and outside nodes through the transfer maps.
- Create Component refuses an interaction on another object that targets the container's contents
  ("Remove or retarget interactions on other objects that point at objects inside this container before
  creating this component."); a target on the container itself is kept, because the instance keeps its id.
- C10: `Tests/Tooling/interaction_runtime_browser.py` (8 cases) and its pure helper checks
  `Tests/Tooling/test_interaction_runtime_browser.py` follow the Flow harness pair. The harness reuses
  `flow_runtime_browser.py`'s owned headless Chrome, loopback DevTools client and loopback static server
  (imported, not copied); every case is recorded, none is skipped, a missing Chrome fails with the same
  guidance. `TransformModelTests/testInteractionAndMotionRuntimesActualBrowserFocusTrapEscapePlacementAndReveal`
  compiles the fixture with `MultiPageStaticBuildPlanner`, runs both scripts with `/usr/bin/python3` and
  attaches the ledger, log and captures, like the Flow wrapper in `SupportSettingsTests`.

## Consequences

- A placed popover inside a container with `overflow:hidden` on a page-flow page can still be clipped by
  that container (it is translated, not moved out of its parent). Moving non-modal overlays to `<body>` would
  break their authored stacking; left as is and documented here.
- Placement re-measures on every scroll frame while an overlay is open (bounded by the open stack).
- The browser test adds one Chrome launch (about 10–30 s) to the `SiteForgeTests` target; CI already
  provisions Chrome for the Flow test.
- Not verified on a Mac: no Swift compiler and no browser ran these changes.
