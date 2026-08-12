# ADR-0014 — AppKit/Core Animation authoring canvas with optional Metal backend

- Status: Accepted; resolves OD-011
- Date: 2026-07-21
- Owners: Architecture / Engineering
- Requirements: SF-1901-001–008, SF-0401-001–008, SF-0407-001–008, SF-1903-001–008

## Context

OD-011 asked how SwiftUI, AppKit, Core Animation, and Metal should divide the authoring canvas. The workspace chrome is already native SwiftUI/AppKit with centralized materials. The canvas needs precise coordinate conversion, cursor-anchored zoom, pan, incremental drawing, independent hit testing and editor overlays, accessibility virtualization, and predictable behavior at 100 and 10,000 objects.

## Decision drivers

- Canvas interaction and coordinate conversion need explicit event, focus, clipping, and invalidation control.
- Editor-only overlays must never enter exported content.
- Pan/zoom should transform retained content rather than rerasterize every object per event.
- Accessibility and native material composition must remain first-class.
- Metal should be adopted only when measured native paths cannot meet approved budgets.

## Decision

SwiftUI remains responsible for workspace chrome, commands, panels, and state composition. A dedicated AppKit `NSView` owns the production canvas viewport, input routing, focus, accessibility virtualization, dirty-region/tile invalidation, and world/view/device conversion. Core Animation supplies the backing/composition boundary: retained content tiles or bounded render surfaces, viewport transforms, and distinct editor-overlay layers. Canonical objects do not each require a `CALayer`; the layer-per-object prototype is a stress comparison, not the production structure.

Rendering, hit testing, and overlays consume one immutable revision-tagged scene snapshot through separate adapters. Editor overlays have their own pass and are excluded from preview/export. Layout and scene preparation run off the main actor; only AppKit/Core Animation adoption and display work run on the main actor. Stale or cancelled snapshots are discarded.

Metal is not an initial dependency. The renderer boundary must permit a later Metal tile/content backend without changing coordinate, hit-test, overlay, accessibility, or canonical-model semantics.

## Evidence

On the retained Mac16,13 optimized run, 100-object full rasters were below 1.1 ms P95 for AppKit, SwiftUI Canvas, and Core Animation. At 10,000 objects, AppKit full offscreen raster was 17.633 ms P95, Core Animation layer-tree raster 18.183 ms, and SwiftUI Canvas 36.574 ms. After a single model change, AppKit dirty-region raster was 0.074 ms P95 and a Core Animation one-layer transaction was 0.107 ms, while SwiftUI Canvas rerasterized the surface at 29.244 ms. Uniform-grid hit testing measured 0.000125 ms P95 at 10,000 objects.

The full AppKit/Core Animation stress rasters sometimes crossed the 16.67 ms reference interval, so the decision requires dirty tiles and compositor transforms rather than full repaint per pan/zoom. The Metal probe measured buffer mutation plus an empty command round trip (0.023 ms P95 at 10,000 objects) but did not implement shaders or presentation and therefore is not evidence that Metal improves end-to-end rendering.

The native-material pass-through check preserved canvas hit testing. Content digest was unchanged by an editor overlay. The harness constructed 10,000 stable AppKit accessibility elements; it did not measure VoiceOver speech. Resident and process-high-water fields are retained but are sequential/process-wide, not isolated backend allocation measurements.

## Alternatives considered

1. SwiftUI Canvas for the complete authoring surface. Rejected initially because one-object changes rerasterized the 10,000-object surface and exceeded the reference interval on every retained sample; event and accessibility virtualization control are also less explicit.
2. One Core Animation layer per canonical object. Rejected as the default because layer count and process high-water grew materially; retained layers remain appropriate for bounded tiles and overlays.
3. AppKit immediate-mode only. Viable for drawing and precise input, but selected with Core Animation so pan/zoom and overlays can be composited without full rerasterization.
4. Metal from Milestone 1 start. Deferred because no measured need justifies shader/pipeline/accessibility complexity; the current probe is intentionally insufficient to select it.
5. The chosen SwiftUI chrome + AppKit viewport + bounded Core Animation composition split, with Metal behind a reversible renderer interface.

## Tradeoffs and consequences

- Positive: precise native events, focus, accessibility, dirty regions, scrolling, materials, and test seams.
- Positive: coordinate, hit-test, render, and overlay ownership stays separate and deterministic.
- Positive: Metal remains available without contaminating canonical semantics.
- Negative: AppKit/SwiftUI bridging and tile invalidation require explicit engineering and regression coverage.
- Negative: the initial full 10,000-object offscreen raster did not stay within one reference interval, so incremental architecture is mandatory.
- Accessibility: AppKit exposes stable virtual semantic elements independent of visual layers; offscreen/virtualized objects require deliberate navigation policy.
- Performance: model/layout preparation is background work; main-actor adoption is revision checked and bounded. Frame pacing requires display-link/signpost evidence in production.
- Preview/export: editor layers are structurally separate; preview/export consumes canonical scene/layout data, never AppKit or Core Animation state.

## Failure modes

- Pan/zoom triggers full scene rerasterization rather than a compositor transform or bounded tile work.
- Overlay, hover, or selection state changes canonical/export content.
- AppKit and scene-snapshot coordinate transforms diverge.
- Accessibility identity follows recycled layers instead of stable model identity.
- A stale background scene or tile reaches the viewport.
- Layer/tile growth exceeds a bounded cache or memory policy.

## Reversibility and revisit triggers

The canvas renderer is an adapter over typed scene snapshots. A Metal backend can replace content-tile rasterization while AppKit retains viewport/input/accessibility ownership and Core Animation retains composition.

Build a production Metal comparison before adoption if display-link evidence on owner-approved reference hardware shows repeated frame misses during pan/zoom or incremental edits; if tile/cache memory exceeds its budget; if required effects cannot be expressed efficiently with native drawing/Core Animation; or if stress fixtures exceed the practical limit. Revisit SwiftUI canvas rendering only if framework changes produce equivalent incremental invalidation, event, accessibility, material, and 10,000-object evidence.

## Production checkpoint: SF-AUTHORING-001

The first production slice implements the decision's coordinate and viewport boundary without pulling the later renderer forward. `CanvasViewport.swift` is a Foundation-only typed geometry/state layer. Each `WorkspaceDocumentContext` owns an independent, nonpersistent viewport; an AppKit `NSView` owns native scroll, magnification, keyboard, focus, accessibility, and bounded placeholder drawing. Immutable preparation results carry document, revision, scene, and generation identity and are adopted only when all fields still match.

Core Animation tiles, real scene rendering, hit testing, editor overlays, and accessibility virtualization remain `SF-AUTHORING-003`. Metal remains absent. This checkpoint preserves the renderer seam and validates deterministic 100-/10,000-object preparation rather than claiming renderer frame pacing.

## Production checkpoint: SF-AUTHORING-003

`CanvasRendererCore.swift` now defines a Foundation-only immutable scene contract and bounded plan keyed by document, revision, scene, scene generation, viewport generation, and Retina scale. The AppKit viewport adopts bounded 512-device-pixel Core Animation content tiles under a dedicated authored-content container; focus and future selection overlays live in a separate editor-only container. Preview-facing snapshots are created only from authored scene objects, so overlays are unrepresentable in that boundary. Hit testing and accessibility consume the same stable scene identity but remain independent adapters.

The canonical coordinate convention is top-left origin with X increasing right
and Y increasing down across world, viewport, and device units. AppKit events,
hit testing, selection/transform overlays and handles, guides/snapping, inline
text editing, Core Animation tile placement, and preview/export-facing
snapshots all use that convention. Core Graphics raster contexts are Y-up, so
`CanvasContentTileLayer` owns the sole explicit conversion before AppKit text
drawing. This prevents authored Frame labels and plain Text from becoming
vertically mirrored while preserving one shared geometry source; no individual
label or overlay applies a compensating rotation.

Retained named-host evidence records full planning, one-object dirty planning, and reverse-order hit testing at 100 and 10,000 objects, raw samples, memory, an idle display-link probe, and limitations. The 10,000-object full and dirty paths exceeded 16.67 ms in every retained sample. Tile adoption still invalidates bounded affected surfaces and viewport-only pan/zoom uses a compositor transform, but whole-snapshot validation/diffing requires later incremental indexing. This checkpoint therefore confirms the selected ownership split without establishing OD-001 release budgets or selecting Metal.

## Production checkpoint: SF-AUTHORING-004

`SelectionModel.swift` adds the next Foundation-only adapter under this decision. Every scene/window owns one ordered selection snapshot keyed by stable `NodeID`, active page/container, provenance, and the renderer's complete request identity. A central typed registry validates pointer, keyboard, menu, contextual, Layers, and accessibility commands; rejected, cancelled, or stale work is state-neutral. Selection is editor convenience state, not authored website content: it is non-`Codable`, creates no transaction/history entry, and cannot enter package, autosave, recovery, preview, or export-facing snapshots.

The AppKit viewport draws primary/secondary and locked inspection outlines only in the existing editor-overlay layer. Selection-only updates rebuild that layer and invalidate the bounded old/new world regions without recomputing layout or rebuilding authored content tiles. Pan, zoom, resize, and Retina changes reapply the compositor transform and rebuild overlay/accessibility geometry from the current immutable plan. Retained optimized evidence covers registry validation/traversal and overlay planning at 100 and 10,000 objects; this does not establish final incremental indexes, interactive Instruments/frame pacing, or OD-001 budgets.

## Production checkpoint: SF-AUTHORING-006

`TransformModel.swift` retains the selected ownership split for move and resize. The Foundation-only registry resolves exact geometry and validates stable session, document, page, revision, scene, renderer-generation, and selected-node identities before compiling the existing canonical `layout.x/y/width/height` properties into one batch transaction. The scene/window-owned session and preview remain non-`Codable`; they cannot become a second geometry source or enter packages, persisted history, preview, or export-facing snapshots.

The AppKit viewport owns genuine pointer gestures and bounded native accessible handle views. Preview outlines and handles remain in the editor-overlay container; only a successful transaction produces a new authored scene. Renderer adoption then uses exact old/new dirty regions and the existing hit-test/accessibility adapters. Compatible multiple selection can move atomically, while multiple resize and any incompatible target are rejected instead of coerced. Retained 100-/10,000-object preparation evidence confirms deterministic bounded behavior but the large result exceeds one 60 Hz interval; simultaneous 10,000-object transforms, incremental indexing, interactive frame pacing, and OD-001 budgets remain unproven. Metal remains absent.
