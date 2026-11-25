# Fast visual styling — next development assignment

## Owner request

Make SiteForge fluid enough to build a real website quickly. Changing colors,
line/border thickness and box corners currently takes too much effort. Gradients
appeared as sections of solid color rather than flowing smoothly. The owner wants
an implemented improvement, with actual editor validation.

Owner clarification: a corner-radius slider is explicitly required. The goal is
intuitive visual adjustment, with sliders and direct manipulation for common
continuous values, alongside numeric entry for precision. Merely moving existing
text fields or adding steppers does not satisfy this request.

The latest appearance decision remains semantic macOS default grays, native
controls and blue accents. Preserve the approved workspace layout and matching
sidebar tab strips. This assignment improves the Design inspector and its editing
behavior; it does not reopen the overall app redesign.

## Contract and starting points

Read `AGENTS.md`, the current queue, and specification sections 5.6, 5.8 and 7.1.
Cite SF-0506-001–008, SF-0508-001–008 and SF-0701-001–008 for the bounded work
actually delivered. Include SF-0305/SF-0306 history/persistence and
SF-1204-003/004 static-output evidence where exercised; do not promote entire
modules on the basis of this slice.

Existing foundations to reuse:

- `SiteForge/WorkspaceShellView.swift`: Design inspector ordering,
  `boxStyleControls`, opacity stepper, token controls, `NativeDesignColorWell`,
  and the real `drawAuthoredFillLayer` paint path.
- `SiteForge/FillLayerListInspectorView.swift`: canonical layer and stop controls.
- `SiteForge/CanvasRendererCore.swift`: `CanvasAuthoredFillCompositor`, normalized
  gradient geometry and `StaticFillLayerStyleOutputEmitter`.
- `SiteForge/TransformModel.swift` and `SiteForge/DocumentModel.swift`: existing
  validated transactions, preview infrastructure, styles, layers and stable IDs.
- `docs/evidence/SF-AUTHORING-054-NATIVE-FILL-AUTHORING.md`,
  `SF-AUTHORING-055-BOX-STYLE-FOUNDATION.md`, and local color-token evidence.

Inspection found that common border/radius controls follow advanced styles and
semantic controls. Gradient editing presents separate stop rows without a visual
ramp. Add Stop currently always inserts a legacy-colored stop at 50%. The pure
compositor already interpolates between stops, and native painting already uses
CGGradient; the reported visual defect is not yet diagnosed. The color well
currently forwards each panel action directly to a canonical commit and converts
through device RGB, while native fill painting documents sRGB. Audit these paths
without assuming either observation explains the owner's gradient result.

## Execution

Add this as the highest-priority ready queue item and record a short implementation
plan. Work through the following dependent slices, keeping the result coherent.
Preserve existing dirty work and already verified test infrastructure. Do not
delegate to OpenCode or a local model.

### 1. Reproduce the actual authoring friction and gradient defect

Use a real editable project to make a Frame/Section, change fill color, change
border thickness, round its corners, and create a two- then three-color gradient.
Record the current actions and capture the current states. Read the existing
owner-dark-flow gradient journey and relevant renderer/history tests first.

Trace active appearance provenance: legacy fill, explicit fill layers, token,
reusable style and responsive override. Determine whether the gradient result
comes from hidden covering layers, stop positions/colors, coordinate geometry,
tiling, clipping, color conversion, preview invalidation, or output projection.
Inspect actual native rendered pixels as well as model values. Do not declare a
renderer bug fixed just because a pure interpolation helper passes.

Test a tall and a wide box at horizontal, vertical and diagonal angles, including
zoom and tile boundaries. Inspect a page background too. Compare supported
Frame/Section static output in the browser through the existing preview path.
Preserve intentionally coincident stops as hard edges. If the reported banding
cannot be reproduced, record the attempted fixture and evidence honestly and
still improve the demonstrably awkward editing workflow.

### 2. Put everyday styling directly within reach

Place clear, compact Fill, Border, Corners and Opacity controls near the top of the
selected object's Design inspector. Move specialist styling and semantic-element
configuration into sensible secondary sections. Keep page-background inspection
appropriately limited and text styling contextually correct.

For an ordinary box, expose its current fill swatch/value, border swatch and width,
and uniform corner radius without requiring unrelated panels or manual layer
creation. Setting a valid border width or radius should enable that appearance
through the existing typed command as needed, in the same transaction. Preserve
the distinction between an omitted property, explicit zero, a token and a default.
Reset/remove must restore the appropriate source. Label mixed and unavailable
states truthfully; do not silently flatten a multi-selection or detach a token.

Provide native sliders with synchronized numeric fields for corner radius,
border width and opacity. Corner radius must be adjustable by dragging a visible
slider and watching the selected box round on the canvas immediately, without
pressing Apply or Return after each adjustment. Show the current value and units
beside the slider, with exact typing and accessible keyboard adjustment retained.
Use consistent control geometry and behavior across these adjustments.

Choose useful slider ranges from existing model constraints and, for corners,
the selected geometry's meaningful visual range. Preserve valid authored values
outside the convenient slider range through numeric entry; do not silently clamp
the document, rewrite a stored value on inspection, or rescale a slider beneath
the pointer during a drag. Mixed and unavailable states must remain truthful.
Dragging previews transiently and creates one undo transaction on release;
Escape restores the value at gesture start. Keyboard adjustment should also have
a deliberate undo boundary. Selection changes, pointer cancellation and save
requests must resolve preview ownership safely. Check these interactions in the
native UI rather than proving only the model setter.

Arrow/Tab/Return/Escape behavior should be consistent, with visible units and
validation. If line elements use a separate existing stroke path,
include their thickness control; otherwise keep unsupported kinds explicit rather
than inventing a new geometry model as part of this assignment.

Use native macOS controls, semantic surfaces, aligned labels and equal-sized peer
actions. At the supported compact inspector width, fields must remain readable,
hittable and reachable with the keyboard. Keep user-facing copy concise. Extract
cohesive reusable controls instead of adding another unrelated body of ad hoc
logic to the large workspace view.

### 3. Make changing a color quick and transactional

Offer an immediately accessible swatch and editable hex value for the active fill
and border, with a clear alpha value. Reuse the same color-editing component for
gradient stops and other applicable existing color targets. Retain access to the
native Colors panel, including its sampling tools, and existing project tokens.
Specify the supported hex forms; incomplete or invalid drafts must not mutate
the project or silently turn black.

Live changes should visibly preview on the canvas, with a defined commit and
cancel lifecycle. Coalesce a continuous color interaction into one meaningful
undo action instead of saving every drag event. Escape/cancellation restores the
previous committed value. Commit an ordinary completed edit without imposing an
extra Apply step on every click. Selection/page changes, shared-panel ownership,
window closure and save/preview requests must resolve drafts safely and must not
apply a stale color to another object. Use deterministic canonical sRGB and alpha
conversion across the well, ramp, canvas, persistence and supported output.

Changing the active fill must edit that fill. Do not silently add a covering solid
layer or destroy an existing gradient/stack. Keep advanced layer add/reorder/delete
available, with clear active-layer targeting. Simple existing legacy fills should
remain simple to edit using their authoritative provenance.

### 4. Make gradients visual and continuous

Add a compact gradient ramp with visibly selectable stop handles, selected-stop
color/alpha/position controls, angle entry and a clear direction preview. Allow
pointer stop movement with live preview and an equivalent precise keyboard/numeric
path. Reuse the canonical layer/stop IDs and command validation. Dragging a stop
commits once; Escape cancels; crossing stops must not lose identity or change the
authored list merely to obtain interpolation order.

Provide a straightforward solid/linear-gradient choice for the active fill and
retain explicit advanced stacking. For a newly created gradient, initialize
distinct endpoint positions with a visible smooth transition. Insert a new stop
at a useful unoccupied position, using the current interpolated color so inserting
it alone preserves the ramp, rather than repeatedly introducing an unrelated
opaque color at 50%. Handle the minimum stop count, duplicate positions, alpha,
disabled layers and invalid drafts through the existing model.

Fix the reproduced cause of blocky or disconnected gradients in the real paint
path. The ramp and canvas must describe the same authored stops and direction.
Verify interpolation at interior points and no seams across canvas tiles. Keep
object opacity applied once. Check the aspect ratio and native/CSS angle mapping
instead of masking mismatches with an attractive ramp. Do not change deliberately
authored hard stops or silently recolor neighboring sections. A gradient spanning
multiple sections should use the supported shared parent/page background, with
child fills handled explicitly; do not pretend independent fills share one
continuous coordinate space. Record any remaining supported-output difference.

### 5. Prove the complete authoring workflow

After implementation, repeat the original real-app workflow and record actions
before/after. Demonstrate changing box color, border width and corner radius from
the visible Design controls, then producing and adjusting a smooth gradient.
Check zero/empty/default/mixed states, invalid drafts, alpha, keyboard-only input,
token-bound colors, switching selection mid-edit, cancellation, undo/redo and save
reopen. No extra transaction for an unchanged value; no stale editor write.

Extend meaningful existing tests instead of duplicating the implementation. Start
with the current exact selectors, confirming names still exist before selecting:

- `TransformModelTests.testDesignFillLayerRegistryCommitsOrderedLayersWithExactHistoryAndPersistence`
- `TransformModelTests.testDesignFillLayerRegistryRejectsInvalidStaleCancelAndAllInapplicableEdits`
- `TransformModelTests.testDesignBoxStyleRegistryCommitsValidatesMixesPersistsAndUndoRedo`
- `CanvasRendererTests.testAuthoredFillLayerCompositorPreservesOrderDisabledLayersStopsAnglesAndOpacity`
- `SiteForgeLaunchTests.testDesignInspectorOrderedFillLayersAccessibilityJourney`
- `SiteForgeLaunchTests.testDesignInspectorBorderRadiusShadowUndoRedoAccessibilityJourney`
- `SiteForgeLaunchTests.testOwnerDarkFlowVisibleGradientControls`

Add targeted coverage for the actual new interactions and the reproduced gradient
failure, including actual native painting rather than only expected CSS strings
or helper arithmetic. Update accessibility journeys when controls deliberately
move, preserving their semantic assertions. Capture real Light/Dark and compact
inspector states after at least two visual-review passes.

All normal local verification must start through the native Testing window using
its regular/UI Start controls and exact affected scopes. Keep the always-on-top
monitor, live discovered counts, descriptive current test, pause/cancel, elapsed
time, measured ETA and saved reports. Test app main windows initially fill the
usable desktop without hiding the menu bar or Dock. Use compact geometry only in
named phases. No parallel collectors or new automation permission detour.

Run focused checks during each slice. The completed consolidated styling overhaul
is a major authoring feature: run the required full verification gate once after
focused acceptance, using the Testing window's explicit full-verification route.
Do not run the whole suite after every small edit. Diagnose failures and report
exact source fingerprints/receipts and any remaining limitations; never weaken
the gate or claim a retained older receipt covers changed behavior.

## Delivery

Update queue, implementation status, requirement evidence and changelog, with
before/after screenshots and exact verification receipts. Refresh
`/Applications/SiteForge.app` through `scripts/package-owner-local-app.sh --install`
after verified milestones, and verify installed bundle signatures and source/
harness fingerprints. If the owner's app is open, let them save and quit normally;
do not force-quit it. Finish by reporting what is usable in the installed app,
what caused the gradient problem if established, and any concrete limitations.
Leave all work local and uncommitted; no GitHub actions. Do not continue into an
unrelated feature queue after this assignment.
