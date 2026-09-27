# SF-AUTHORING-054 — Native fill and bounded linear-gradient authoring

## Bounded result

SiteForge already supplies the user-visible vertical path: typed versioned
solid/linear-gradient layers; native accessible Design Inspector controls;
identity-gated atomic commands with exact inverses; immutable renderer
compositing; package, recovery, undo/redo, cancellation, and mixed-selection
handling. This prompt closes the supported static-output adoption gap for
Frame and Section only.

The immutable compiler carries only validated canonical layers and opacity for
those kinds. `StaticFillLayerStyleOutputEmitter` emits fixed CSS gradients
from normalized RGBA values and stable stop-position interpolation order. CSS
background order reverses the authored compositor sequence so later authored
layers remain visually on top, matching native source-over composition.
Opacity is emitted once. Invalid layers, unsupported kinds, raw CSS, and
browser-side definitions are omitted.

## Requirements and focused evidence

- `SF-0508-001`–`005`: canonical/provenance, Inspector command, renderer, and
  persistence foundations are reused; this slice adds output adoption.
- `SF-0701-001`–`005`, `SF-0305-001`–`005`, `SF-0306-001`–`005`: existing
  supported Frame/Section editing, rendering, and recovery paths remain the
  authoritative user workflow.
- `SF-1204-003`–`004`: the static mapping is a closed deterministic compiler
  projection with no raw CSS input.

Focused selectors for this prompt:

- `CommandKernelTests.testMultiPageStaticBuildPlanProjectsClosedFrameAndSectionFillLayers`
- `TransformModelTests.testDesignFillLayerRegistryCommitsOrderedLayersWithExactHistoryAndPersistence`
- `CanvasRendererTests.testAuthoredFillLayerCompositorPreservesOrderDisabledLayersStopsAnglesAndOpacity`
- `SiteForgeLaunchTests.testDesignInspectorOrderedFillLayersAccessibilityJourney`

Observed 2026-09-27: the three focused unit selectors passed (3/3). The
existing native Inspector journey was invoked once, but XCTest timed out while
enabling macOS automation before its test body ran. That runner failure does
not establish a product result and is recorded here for the next permitted UI
automation pass; no assertion or product behavior was weakened.

## Explicit exclusions

Raw CSS, arbitrary gradients, image fills, browser runtime, remote assets,
publishing, unsupported node-kind static styling, and release acceptance
remain deferred. `SF-0508`, `SF-0701`, `SF-0305`, and `SF-0306` remain Partial
outside this bounded evidence.
