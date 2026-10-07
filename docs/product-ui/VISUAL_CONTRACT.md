# SiteForge Visual Contract

## Short-display Inspector reachability

At the supported production minimum window size, selected-object Inspector
content retains bottom scroll clearance. On a shorter macOS display the Dock
may overlap the window's lower edge, but the final native control must still
scroll entirely above it and remain pointer/keyboard accessible. This
clearance is editor chrome only and does not change project content or the
production minimum width.

## Native pointer and composition contract

The flipped AppKit canvas backing layer owns the top-left/Y-down conversion.
Owned content, text and overlay composition containers must not flip again.
Raster/text leaf APIs retain their single local drawing conversion. Native
pointer screen positions, painted preview edges and committed accessible bounds
must coincide without changing canonical coordinates or adding tool offsets.
When a creation tool is armed, the empty-state card and empty-only convenience
row yield so they neither obscure the preview nor resize the viewport on commit.
The empty project remains genuinely empty until the user commits insertion.

## Exposed component text (SF-AUTHORING-024)

Content Inspector names plain-text properties on one linked instance and
distinguishes inherited definition content from authored values, including
empty strings. Native draft fields provide Apply/Return, Cancel/Escape, Reset
and Reset All Text Overrides. Definition Text selection exposes a property-name
and default form; future property types are not presented as working controls.
Missing bindings retain authored text for inspection and explicit reset.
Canvas accessibility text comes from the same immutable snapshot as raster
glyphs. Component badges, clipping, practical-minimum panes and maximized-window
policy are unchanged.

## Local components (SF-AUTHORING-022)

The Components destination is reachable through the native navigator overflow
menu when the horizontal tab strip cannot show every full label. Its definition
rows retain readable names, usage counts and Insert/Edit/Rename/Delete actions
at the 1100-point practical minimum. Rename uses a compact native sheet and
updates linked display names without changing stable identities or overrides.
Linked instances distinguish inherited appearance
from independent geometry. Editing a definition displays an explicit breadcrumb
and Exit Definition action above the canvas. Definitions never appear as website
pages. Destructive definition removal names its detach-uses effect and offers
pointer Cancel and keyboard Escape; cancellation must retain linked identity.
New instances fit the visible selected-parent/artboard area without moving the
definition. No expanded child becomes a second editable canonical object.

## Static pages (SF-AUTHORING-021)

Pages exposes New Page and Page Actions, with equivalent native Page and row
context menus. Rows show the display name and route separately; full values and
protected roles remain accessible. Draft sheets keep persistent field labels,
readable validation and native Cancel/Apply semantics. Deletion names its
object/link impact and uses a destructive confirmation. New pages contain
only a non-rendered structural root; page changes do not leave old canvas
objects or editor drafts visible. Duplication is not a template operation.
The Pages search field filters current-document names and routes without
changing selection until an explicit open; Layers search filters only the
current authorized row projection by name without changing NodeID or paint
order. Both display a readable count and no-result recovery, and preserve
visible keyboard focus and Return/Escape semantics.
The Elements query filters native catalogue names/categories but keeps
unavailable entries visibly disabled. Layers' native type picker composes with
name search, retains the structural Root where its kind matches, and exposes
Show Selected Layer when filtering hides selection. A visible Quick Open entry
and View-menu shortcut open a native centered sheet with readable All/Pages/
Layers/Actions scopes, current-document page and authorized current-page
Layer results, bounded scene-local recents, and only the closed non-destructive
View actions. Long result sets scroll inside the sheet; labels, routes, type
names, status counts, and Cancel stay legible at the practical minimum. Query,
scope, and recent state are editor-only and must never appear as authored
content or in a saved site.

## Button and Link authoring (SF-AUTHORING-020)

Button and Link are real Elements and native Insert actions. Content edits
their labels; Interactions edits stable page/section or HTTP(S) navigation
intent. These actions never navigate in the editor. Unsupported selections
receive an explicit unavailable explanation; mixed values are not borrowed
from the primary node. Native fields retain readable bezels inside the
Inspector scroll viewport. Button text uses contrast resolved from its fill
snapshot; label layout shares the canonical text geometry without offsets.
Separately authored objects may intentionally overlap, but visual evidence
must position them through real Layout controls so both can be inspected.

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

The native welcome card uses the approved packaged SiteForge AppIcon, not a
generic tool symbol or project-provided artwork. Its first actions are the
plain-language **New Site** and **Open Project…** choices, followed by compact
local-project, private-by-default, and recovery-protected assurances. These
assurances may adapt from one row to a short vertical group at narrower widths;
they must not wrap into clipped fragments or imply cloud/template behavior
that is not implemented.

When authorized recency exists, a bounded **Recent Projects** group follows the
primary actions. Rows show only the project display name and “Authorized local
project,” never a path. Open uses the retained macOS authorization; Remove
changes recency without revoking it. Missing authorization leaves the row's
intent recoverable through a visible Locate/Open Project action. The group may
show at most four rows on the launch card so it cannot displace primary actions
below the practical minimum.

The macOS menu bar uses native command groups and exposes the final product
information architecture: **File**, **Edit**, **View**, **Insert**,
**Selection**, **Preview**, **Window**, and **Help**. Current command groups
may contain only the bounded commands implemented by the command registry;
unimplemented commands are not represented as enabled lookalikes.

The workspace toolbar keeps Select, Frame, Text, Image, and Component visible
at the practical-minimum window. Section, Stack, Grid, Button, Link, and Form
use the adjacent native **More Tools** menu and retain equivalent Insert-menu
and keyboard routes. The menu reports the selected additional tool, preserves
native focus and pointer targets, and changes only scene-local tool choice.
Toolbar grouping never creates project data or bypasses the typed command
registry.

The left-side navigation architecture is Pages, Layers, Elements, Assets, and
Components. Pages and Layers remain functional. Elements is a real accessible
catalogue: Section, Stack, Grid, Frame, Form; Text, Heading, Button, Link, Divider; Header,
Navigation, Footer; and Form-only Input, Email, Text Area, Checkbox, Select,
and Submit actions have stable identities, icons,
shortcuts/capability contracts, and availability state. Section, Stack, Grid,
Frame, Form, and plain Text have previously verified canonical insertion.
Divider and semantic site templates, plus the Form-only Text-backed fields,
are source-implemented through that same registry but visual acceptance is
deferred. Form is a 320×180 semantic container; its submission/destination
behavior remains explicitly unavailable.
Section is a 960×320 structural
container with 48-point default padding; Stack is vertical/start with 24-point
padding and gap; Grid is two equal row-major columns with 24-point padding and
gap. Form field actions are disabled without a selected Form; they do not
become standalone authored nodes. Assets
is a functional local-raster library with a direct Import Images action,
searchable nonwrapping rows, bounded thumbnails, filename, dimensions, format,
byte size, usage count, rename, replacement, usage reveal, safe deletion, and
selected-asset insertion. Image is a real Basic element and Insert command;
its Design controls expose the asset, Fit/Fill/Stretch, bounded Fill focal
point, and explicit alt/decorative semantics without duplicating Layout
geometry. Missing bytes preserve the Image and show an in-bounds editor
placeholder. Components is a functional project-local definition/instance
surface; cloud libraries, marketplaces, slots, and variants remain unavailable.

The inspector order is Design, Layout, Content, Interactions, and
Accessibility. Design provides bounded ordered solid and linear-gradient fill
editing for applicable structural containers. It exposes native
`NSColorWell`/standard Colors-panel controls, hexadecimal RGBA, object opacity,
layer add/enable/reorder/delete, gradient angle, and per-stop colour,
position/add/remove/reorder controls. Picker and text drafts are editor-only
until a completed transaction; Return or focus loss commits a valid numeric
draft, Escape restores the committed value, and invalid input remains visible
with an accessible explanation. Exact shared multiple-selection stacks expose
shared editable rows, differing stacks show a truthful mixed state without
borrowing the primary object's rows, and incompatible objects remain
unchanged. For plain Text, Design also exposes one non-wrapping native
Typography group: editable family, regular/medium/semibold/bold weight, size,
explicit line height, tracking, leading/center/trailing alignment, provenance,
and Reset. Missing installed fonts preserve the authored family and show a
specific system-fallback status. The committed tile renderer and live inline
editor consume one `CanvasTextLayout` metric snapshot; caret and marked-text
state remain editor-only. Font import, variable axes, rich-text spans, advanced
paragraphs, responsive overrides, and preview/export parity are unavailable
rather than simulated. Layout retains the bounded geometry, structural layout,
transform, guide, and snapping controls. For applicable Frame, Text, Section,
Stack, and Grid selection, Layout exposes native locale-aware X, Y, Width, and
Height fields, including truthful Desktop-base and Tablet/Mobile override
provenance. Section exposes uniform padding; Stack exposes vertical/horizontal
direction, uniform padding and gap, and start/center/end/stretch cross-axis
alignment; Grid exposes uniform padding and gap plus bounded row-major column
count. Draft strings are editor-only; Return and focus loss submit one
identity-gated canonical transaction, while Escape preserves the displayed
committed value. Reset removes responsive geometry/container/visibility
overrides or restores a container's canonical v1 default without writing a
visually equivalent authored value. At Tablet and Mobile, Section padding;
Stack direction, gap, padding, and alignment; and Grid columns, gap, and
padding name their inherited or authored breakpoint source. Applicable
authored objects expose a native Visible at Current Breakpoint control. Hidden
objects do not paint or expose canvas chrome, hit targets, inline editors, or
canvas accessibility objects; Layers keeps their stable identity with an
icon-plus-text `Hidden here` state and a route to show or reset the object.
Hidden children do not occupy a Stack/Grid layout slot, while a hidden
container suppresses its subtree without deleting or rewriting descendants.
Mixed and partially applicable selections identify the exact affected subset.
Applicable Layout selections also expose one compact Fluid Value group for
width, height, font size, line height, padding, and gap where supported. It
shows a property picker, nonwrapping minimum/preferred/maximum fields, the
390/768/1440 reference widths, authored/defaulted/mixed provenance, and a
visible Remove Fluid Value action. Incomplete values remain local drafts;
Escape cancels and removal reveals the untouched fixed value. Fluid controls
must remain readable in the practical-minimum scrollable Inspector and must
not imply support for arbitrary curves or non-monotonic interpolation.
Sizing modes, constraints, aspect ratio, automatic sizing, advanced Stack/Grid
behavior, and broad property editing remain unavailable. Accessibility exposes
non-wrapping Accessible name and Description fields for applicable general
objects, with native focus, Return/focus-loss commit, Escape cancellation,
Reset, and truthful defaulted/authored/mixed status. The semantic role remains
derived from the existing Design semantic-element control rather than becoming
a second editable value. Image alternative text remains in Image Content. For
a selected Form or Form field Accessibility
expands into a non-wrapping canonical summary of control role, accessible name,
required/help/options/bounds, defaulted/authored/mixed provenance, and the
scene-local category-only validation result. Its Edit in Content action changes
Inspector destination but never mutates content. Content and
Interactions are intentionally
selectable native unavailable surfaces: each states why it cannot operate and
what later canonical milestone is required. They expose no simulated editable
fields, interaction controls, command, history, package, or canonical mutation.
For a Form selection, Content truthfully summarizes its unavailable submission
workflow. A selected Text child of Form exposes non-wrapping local draft fields
for field kind, label, machine name, help, required, and ordered Select
options; Apply is one identity-gated canonical transaction and Cancel leaves
the document unchanged. Mixed fields display Mixed rather than copying the
primary field and require explicit resolution before one shared configuration
can be applied. The Form Accessibility surface states that submission remains
disabled and unconfigured; it does not imply a destination or visitor-data
workflow.

## Surface system

- Quick Open may reveal current-project pages, authorized Layers, image assets,
  and component definitions. Its separate Page/Insert actions are visibly
  named and disabled when their existing command is unavailable. Components
  search and Assets usage filtering remain navigator-local, use readable
  native controls, and never masquerade as authored site content.

- SiteForge's static app identity uses the owner-approved purple-to-blue
  rounded-square SF monogram from `docs/design-assets/siteforge-app-icon-sf-gradient-approved-v1.png`.
  Only its exterior white matte is removed for packaging; the white lettering
  and gradient field are preserved. The macOS AppIcon asset catalog owns standard Dock/Finder
  sizes; icon artwork never enters project data, authored rendering, or export.

- Application Appearance Settings uses a compact native Settings window with
  readable radio choices for Follow macOS, Light and Dark. Scope, provenance,
  unsaved preview and recovery status remain visible. Apply persists; Cancel,
  Escape or window close restores committed appearance. Reset removes the
  app-local override. Dynamic native colors/materials remain authoritative;
  this never changes canonical project content or website colors (ADR-0006).
- The native Canvas Settings tab labels its application-only scope and shows
  whether Grid visibility for *new* workspaces is defaulted, drafted, or
  authored. Apply, Cancel/Escape, Reset, and Restore Previous are visible and
  accessible. Already-open workspaces retain independent Grid toolbar/View-menu
  state; the grid remains editor-only and never becomes project content.
- The Settings Reset tab shows the two implemented application defaults with
  readable labels and current values. Its explicit confirmation replaces the
  staged action, Cancel leaves both values intact, and Restore Previous is
  disabled until a reversible group operation exists. Status text names the
  application-only scope and does not imply project or live-scene mutation.
- The native Support tab groups Application & Updates, Recovery, and
  Diagnostics in a compact scrollable Settings surface. Version/build/channel
  and non-installing update provenance are always readable. Generate and Cancel
  are distinct from disabled Copy/Export actions; a completed redacted report
  is reviewable in monospaced text before either sharing action becomes
  available. Failure and cancellation status remains visible, wraps instead of
  clipping, and never exposes a local path or authored project value.

- The title bar and toolbar are unified native macOS chrome.
- Navigator and inspector use native sidebar material blended behind the
  window so their frosted surfaces stay distinct from the canvas. Viewport
  controls use a
  header material; status uses under-window material; recovery has an
  emphasized material; launch uses a native popover-like material.
- Materials are `NSVisualEffectView` based and pass through hit testing. Canvas
  input, scrolling, resizing, selection, and renderer overlays remain outside
  chrome surfaces.
- With Reduce Transparency, all chrome becomes an intentional opaque native
  fallback. Increased Contrast raises separator strength without changing
  semantics. Light/dark, accent color, and inactive-window appearance rely on
  native dynamic colors and materials.
- Material views are accessibility-hidden decoration and never become extra
  focus stops or pointer targets. The normal app remains windowed within the
  usable display frame, with the macOS menu bar and Dock available.
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
- **Canvas composition and adoption:** the editor draws, from back to front,
  pasteboard, optional world grid, page/artboard surface and boundary,
  authored raster content, guides, then selection/focus/text-editor overlays.
  The grid and page decoration are editor-only. Each authored tile subtree is
  bound to the immutable viewport snapshot that allocated its tiles; a
  compositor-only reuse is permitted only when that snapshot is unchanged.
  A newer preset, pan, zoom, resize, or Fit generation never transforms an
  older raster into place: it withholds that raster until the matching plan
  adopts, then presents raster, selection/transform chrome, and accessibility
  from the same snapshot. Artboard clipping applies to authored pixels and
  all editor object chrome; a selected off-artboard node retains its canonical
  identity but has no ghost outline or handles on pasteboard space.
- **Selection context chrome:** the selection badge, handles, hover chrome,
  and focus chrome are editor-only and obey the active artboard clip. A badge
  uses its actual native font measurement to fit within that boundary; it is
  repositioned into the visible intersection, then switches to a compact
  readable form only when necessary. Its complete NodeID-derived context is
  still available through the real accessibility label and help. Editor Frame
  and Section content clips apply only to descendant authored content; their
  own border, radius, and selection geometry remain truthful and unobscured.
- **Directional marquee:** a blank-canvas drag draws one bounded editor-only
  accent rectangle above authored content and below committed selection chrome.
  Left-to-right uses a solid containment treatment; right-to-left uses a dashed
  intersection treatment. The marquee follows the world transform, never
  appears in Preview/static output, and disappears on commit or cancellation.
  names choose contrasting foregrounds against their resolved surface; none
  of this chrome is authored or preview/export-facing content.
- **Initial pasteboard policy:** a fresh or newly adopted document centers its
  noncanonical viewport with Fit Document after AppKit reports a usable size.
  The fit leaves a 48-point pasteboard/grid gutter around the active artboard
  so the page boundary is visible at Desktop, Tablet, and Mobile. Resize and
  pane changes preserve that fitted policy until an explicit pan or viewport
  command. Preset changes refit and recenter the active artboard without
  changing authored world coordinates. The empty-state message is centered
  over that viewport with a bounded, non-hit-testable footprint, so blank
  canvas input remains available outside its visible card.
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
  authored-breakpoint preset (Desktop 1440, Tablet 768, or Mobile 390), a
  visible Compare action, zoom out/current percentage/zoom in, Actual Size,
  Fit to Canvas, and Fit to Document. Compare opens a native scrollable review
  of the same resolved geometry, layout, and visibility cascade; its cards use
  nonwrapping facts with a vertical compact fallback and never become project
  data. At
  explicitly constrained Debug/UI-test geometry these remain real named native
  controls; an overflow affordance, when required by a later narrower layout,
  must stay visible rather than hiding functional controls behind automation.
- Desktop is the base geometry source. Tablet and Mobile Layout fields resolve
  inherited Desktop values until the user authors a breakpoint-specific X, Y,
  Width, or Height override. Each field names its source, and the visible Reset
  Override action removes the canonical override rather than writing a copied
  literal. Switching presets changes only the scene-local authoring context and
  immutable resolved geometry; it never serializes the selected preset, moves
  another breakpoint, or fabricates responsive reflow.
- The same Desktop-base cascade resolves responsive container layout and
  visibility. Tablet/Mobile Reset removes only the active-breakpoint override.
  A hidden canvas object remains discoverable through an explicit Layers state
  but produces no authored pixels, ghost selection chrome, hit target, inline
  editor, or canvas accessibility object at that breakpoint.
- A canonical fluid value, when present, resolves a monotonic linear
  minimum/preferred/maximum clamp at Mobile 390, Tablet 768, and Desktop 1440.
  Explicit Tablet/Mobile literals retain precedence. Breakpoint comparison,
  canvas, typography, container layout, Preview planning, and closed static
  output must show the same resolved value; the scene preset itself remains
  noncanonical.
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

Current verified or source-implemented product surfaces include the native
scene/window lifecycle; Pages/Layers/Elements/Assets/Components navigation;
structural, text, image, semantic, interaction and bounded Form authoring; the
canvas/renderer/overlay system; selection, insertion, transforms and guides;
local assets and components; Design, Layout, Content, Interactions and
Accessibility Inspector workflows; responsive geometry/layout/visibility;
typography; local Preview navigation; application Settings and Support; native
materials; and the central command/history/persistence boundaries. The exact
verification state and exclusions of each slice are authoritative in
`docs/IMPLEMENTATION_STATUS.md`; source-implemented work is not promoted to
accepted merely because its visual contract is recorded here.

Explicitly future beyond the bounded current slices: cloud or remote asset and
component libraries, rich-text spans and advanced typography, arbitrary
responsive styling/content/assets, advanced CSS grid/flex behaviors, image
editing/renditions, broad CMS/runtime data, general interaction graphs,
complete preview/export parity, publishing, third-party plugin execution, and
release acceptance. Naming a destination in this contract does not make it
implemented or enabled.

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

`SF-PRODUCT-UI-006` adds source coverage for the approved launch identity and
the bounded persistent/overflow authoring-tool hierarchy. Its focused test
source is unrun, so it is not visual or accessibility acceptance evidence.

## Authored-object clipboard (SF-AUTHORING-107 source contract)

Cut, Copy, Paste, Paste in Place, and Duplicate use the standard macOS Edit
menu names and shortcuts. When a native text field/editor owns first responder,
those commands retain ordinary NSText behavior; otherwise they address the
active SiteForge object selection. Layers and canvas contextual menus expose
the same central routes. A material result appears as one concise status-bar
announcement without showing clipboard content, paths, or opaque identifiers.
Paste must never create preview chrome, ghost rectangles, or a second selection
model: newly inserted roots adopt through the normal renderer/selection scene.
Unavailable, malformed, oversized, stale, or unsupported dependency states
remain document-neutral and state one bounded repair action. This source
contract is not visual acceptance until its focused actual-app test runs.

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
## Local Preview navigation (SF-AUTHORING-103 source contract)

Local Preview is visually and behaviorally separate from the editor. Its
compact header keeps the current page, Back, Forward, Refresh, and Done visible
without overlaying authored content. The page surface uses the same resolved
artboard bounds as canvas preparation; it must not infer a false artboard from
the union of authored objects. Internal Link activation changes only the
Preview page/history. Editor grid, selection, guides, badges, focus chrome, and
pasteboard never enter Preview pixels. Missing links remain visibly inert and
announce repair guidance. External targets are not executed by this bounded
local runtime.
