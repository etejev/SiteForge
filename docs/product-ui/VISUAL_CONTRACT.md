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
foundation. `SF-PRODUCT-UI-003` establishes inspector navigation, truthful
unavailable Content and Interactions destinations, legible bounded Frame
defaults, and normal maximized-window presentation. These milestones do not
implement general Element, Asset, Component, property, interaction, responsive,
CMS, export, or publishing workflows.

## Native window and scene

- SiteForge uses one native, resizable macOS document window. On first launch
  it is maximized to `NSScreen.visibleFrame`; the menu bar and Dock remain
  available and SiteForge never enters a separate full-screen Space.
- Valid user resize and position restoration takes precedence on later launch;
  malformed/off-screen/under-minimum restoration falls back safely.
- Welcome, project creation, opening/loading, recovery, failure/retry, preview
  presentation, and the workspace are states of the same native window.
- AppKit’s frame autosave restores a valid user-resized/repositioned workspace.
  A malformed, off-screen, or under-minimum restoration falls back to the
  usable display frame. The editor content minimum remains 1100 × 700 points.
- Debug/UI-test constrained-display placement is an explicit Debug-only seam.
  Release composition ignores every automation argument and retains normal
  visible-frame/maximized presentation and restoration behavior.

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
availability state. Section, Stack, Grid, Frame, and plain Text route to the
verified canonical insertion registry today. Section is a 960×320 structural
container with 48-point default padding; Stack is vertical/start with 24-point
padding and gap; Grid is two equal row-major columns with 24-point padding and
gap. Button, Link, Divider, Navbar, and Footer remain disabled with a specific
reason and cannot create canonical content, history, or package state. Assets
and Components are explicit accessible unavailable destinations until their
separate storage/definition work exists.

The inspector order is Design, Layout, Content, Interactions, and
Accessibility. Design is a read-only appearance summary; Layout retains the
bounded geometry, transform, guide, and snapping controls; Accessibility is a
read-only selection summary. Content and Interactions are intentionally
selectable native unavailable surfaces: each states why it cannot operate and
what later canonical milestone is required. They expose no simulated editable
fields, interaction controls, command, history, package, or canonical mutation.

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
- **Coordinate convention:** canonical world, viewport, and device space use
  a top-left origin with X increasing right and Y increasing down. AppKit
  pointer/input conversion, Core Animation content tiles, editor overlays,
  selection handles, guides/snapping, hit testing, inline text editing, and
  preview/export-facing scene snapshots consume that convention directly. The
  tile drawing boundary performs the one required Core Graphics Y-up → canvas
  Y-down conversion before AppKit draws text; individual labels never rotate
  or compensate for a coordinate mismatch.
- **Initial pasteboard policy:** a fresh or newly adopted document centers its
  noncanonical pasteboard at the existing 100% initial zoom only after the
  AppKit viewport has a usable size. Resize and pane changes retain that
  centered origin until an explicit pan or viewport
  command. This never changes authored world coordinates. The empty-state
  message is centered over that viewport with a bounded, non-hit-testable
  footprint, so blank canvas input remains available outside its visible card.
- **Plain-text geometry:** `CanvasTextLayout` is the shared native contract for
  committed tile text and the inline editor. It derives the exact viewport
  object rectangle, scaled font, insets, line fragment, and vertical glyph
  placement once; the editor frame and selection bounds therefore remain the
  same authored viewport rectangle within normal device-pixel rounding.
- A newly inserted blank Frame has a deterministic restrained authored surface:
  a neutral fill, thin separator border, and its canonical `Frame` name. When
  selected, an editor-only accent outline and context chip identify the Frame,
  its dimensions, and parent. The chip, outline, handles, and selection state
  never enter the canonical package, history, preview, or export snapshots.

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
- The viewport header remains visible above the canvas. It contains a labeled
  preview-viewport preset (Desktop 1440, Tablet, or Mobile), zoom out/current
  percentage/zoom in, Actual Size, Fit to Canvas, and Fit to Document. At
  explicitly constrained Debug/UI-test geometry these remain real named native
  controls; an overflow affordance, when required by a later narrower layout,
  must stay visible rather than hiding functional controls behind automation.
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
transforms, guides, bounded plain-text editing, local drag/reorder, the ordered
read-only Design/Layout/Accessibility inspector summaries, native unavailable
Content/Interactions destinations, native materials, and the central command/history/persistence
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

`SF-PRODUCT-UI-003` adds inspector identity/availability/nonmutation unit
coverage, complete forward/reverse inspector focus traversal, a visible selected
Frame journey with undo/redo, normal maximized visible-frame restoration policy
coverage, and an actual-app Content/Interactions unavailable-state journey.
Reproducible visual review paths, including each inspector tab, empty, single,
multiple, and locked selection variants, are recorded in
`docs/evidence/product-ui-003/README.md`.

## Testing workflow

- During bounded implementation, use focused tests or `./sf test changed`.
  Documentation-only changes use repository/traceability checks; uncertain
  change mapping uses `./sf test half`.
- Use focused real-app UI journeys for the changed surface while iterating.
  `./sf verify` is the local completion gate, required before a milestone is
  committed or pushed and after cross-cutting persistence/history/schema,
  shared-shell/focus, security, or CI-tooling changes.
- GitHub Actions remains the authoritative post-push full gate. No READY item
  is marked complete from focused or changed-only testing.
