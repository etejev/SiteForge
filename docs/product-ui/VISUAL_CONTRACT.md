# SiteForge Visual Contract

## Purpose and scope

This is the source of truth for SiteForge’s final-product visual language. It
is an interaction and appearance contract, not a promise that every named
destination is implemented. The development specification remains normative
for product behavior; this contract makes the current visual decisions
testable and keeps later product slices from presenting unavailable features as
working software.

`SF-PRODUCT-UI-001` establishes the shared window, launch, material, spacing,
and state foundation. `SF-PRODUCT-UI-002` adds the truthful product-navigation
foundation. It does not implement general Element, Asset, Component,
responsive, CMS, export, or publishing workflows.

## Native window and scene

- SiteForge uses a normal, resizable macOS document window. On first launch it
  occupies the current screen’s AppKit `visibleFrame`, which respects the menu
  bar and Dock; it does **not** enter a separate full-screen Space.
- Welcome, project creation, opening/loading, recovery, failure/retry, preview
  presentation, and the workspace are states of the same native window.
- AppKit’s frame autosave restores a valid user-resized/repositioned workspace.
  A malformed, off-screen, or under-minimum restoration falls back to the
  usable display frame. The editor content minimum remains 1100 × 700 points.
- Debug/UI-test constrained-display placement is an explicit Debug-only seam.
  Release composition ignores every automation argument and keeps normal
  minimum-size/restoration behavior.

## Application navigation

The macOS menu bar uses native command groups and exposes the final product
information architecture: **File**, **Edit**, **View**, **Insert**,
**Selection**, **Preview**, **Window**, and **Help**. Current command groups
may contain only the bounded commands implemented by the command registry;
unimplemented commands are not represented as enabled lookalikes.

The left-side navigation architecture is Pages, Layers, Elements, Assets, and
Components. Pages and Layers remain functional. Elements is a real accessible
catalogue: Section, Stack, Grid, Frame; Text, Button, Link, Divider; Navbar,
and Footer have stable identities, icons, shortcuts/capability contracts, and
availability state. Only Frame and plain Text route to the verified insertion
registry today. Every other entry is disabled and says why it is not available;
it must not create canonical content, history, or package state. Assets and
Components are explicit accessible unavailable destinations until their
separate storage/definition work exists.

The inspector architecture is Design, Layout, Content, Interactions, and
Accessibility. Current Layout, bounded design/style, geometry, guides, and
Accessibility summaries are truthful inspection surfaces. Content and
Interactions require their later canonical-property/interaction slices; they
must not appear as editable simulated controls before then.

## Surface system

- The title bar and toolbar are unified native macOS chrome.
- Navigator and inspector use native sidebar material; viewport controls use a
  header material; status uses under-window material; recovery has an
  emphasized material; launch uses a native popover-like material.
- Materials are `NSVisualEffectView` based and pass through hit testing. Canvas
  input, scrolling, resizing, selection, and renderer overlays remain outside
  chrome surfaces.
- With Reduce Transparency, all chrome becomes an intentional opaque native
  fallback. Increased Contrast raises separator strength without changing
  semantics. Light/dark, accent color, and inactive-window appearance rely on
  native dynamic colors and materials.
- Canvas remains visually distinct from surrounding chrome through material
  boundaries, native separators, and its under-page background—not static
  gradients or simulated glass.

## Spacing, type, controls, and responsive rules

- Use the existing 8-point family: 4 for compact row gaps, 8–12 for controls
  and pane interiors, 14–16 for grouped content, and 24–48 for launch-level
  grouping. Avoid one-off spacing that changes hierarchy.
- Body labels use native text styles; titles use native semantic styles; values
  that convey geometry, percentages, paths, or revisions use monospaced digits
  where scanning benefits from it.
- Keep native controls at platform-standard sizes. Icons require text labels,
  help, or accessibility labels whenever their action is not self-evident.
- Navigator: 210–300 pt; inspector: 280–360 pt; canvas keeps a 500 pt minimum.
  The 1100 × 700 editor minimum prevents clipping/overlap in normal use.
- At explicitly constrained Debug/UI-test geometry, tests may expose safe
  screen edges while retaining the production metrics as the Release contract.

## States and accessibility

All states have a visible, accessible counterpart:

| State | Contract |
| --- | --- |
| Launch / loading | Real operation status and determinate/indeterminate progress; cancellation only where safe. |
| Recovery / failure | Specific Restore, Discard, Inspect, Retry, or Choose Another Project action; no private path/content disclosure. |
| Empty | Native `ContentUnavailableView`-style explanation and next valid action. |
| Selected / focused | Accent selection plus an actual keyboard focus ring/first responder; focus order remains scene-local. |
| Disabled | Native disabled control plus a specific accessibility reason; never a fake enabled capability. |
| Error | Readable contrast, a recovery action, and redacted diagnostic context. |
| Reduced transparency / increased contrast | Opaque fallback and stronger boundaries without a semantic or input change. |

Stable accessibility identifiers are part of the automated contract. Accessible
labels describe the current operation or value; announcements report material
state changes without authored content, credentials, complete local paths, or
other private data.

## Implemented versus future capability

Implemented now: one full-size native scene/window, project lifecycle states,
Pages/Layers, the bounded Elements catalogue (Frame/plain Text only), a bounded canvas/renderer/overlay system, selection, insertion,
transforms, guides, bounded plain-text editing, local drag/reorder, inspector
summaries, native materials, and the central command/history/persistence
boundaries documented in `docs/IMPLEMENTATION_STATUS.md`.

Explicitly future: container/basic/site Element authoring beyond Frame/plain
Text, Asset storage/import, Component definitions/instances, general property editing, gradients/effects, responsive editing, CMS,
production typography, asset import/placement, external drag/drop, export,
publishing, plugins, and release acceptance. Naming these destinations in this
contract does not make them implemented.

## Verification evidence

`SF-PRODUCT-UI-001` is covered by window restoration/minimum/composition unit
tests, launch/workspace accessibility UI tests, and the retained visual review
manifest at `docs/evidence/product-ui-001/README.md`. Existing requirements
`SF-0201-002`, `SF-0201-003`, `SF-0201-006`, `SF-0201-008`, `SF-1505-006`,
`SF-1505-007`, `SF-1505-008`, and `SF-1605-002`, `SF-1605-006`,
`SF-1605-007`, `SF-1605-008` remain bounded/partial where the specification
requires later authoring or release-scale acceptance.

`SF-PRODUCT-UI-002` adds catalogue identity/availability/nonmutation unit
coverage and an actual-app Elements/Assets/Components navigation journey. The
same requirement IDs remain bounded/partial; this is a truthful navigation
foundation, not an asset, component, or full element-authoring implementation.
