# Codex Continuation Handoff

## Current checkpoint

`SF-AUTHORING-014` is **VERIFIED AND DONE**. The current tree implements the bounded
uniform border, uniform corner radius, and one drop-shadow Design Inspector
slice through canonical `style.box.v1` properties, the shared transaction
registry, immutable renderer snapshots, native controls, package/recovery, and
focused actual-app evidence. Do not expand this into margins/padding,
independent borders, per-corner radii, multiple/inner shadows, clipping UI, or
preview/export work. Focused acceptance passed 7/7 and the authoritative
`./sf verify` passed 360 unit/integration plus 43 UI tests (403 total), zero
failures. Hosted Actions `32934689112` passed the same complete gate at
`65571dc` after the compact-window pointer placement correction.

`SF-AUDIT-001` is **VERIFIED AND DONE**. Confirmed audit defects were fixed at
their production boundaries rather than returned to the owner as a
prioritization list. Focused integration and running-app visual review passed;
the final 2026-08-25 `./sf verify` passed 356 unit/integration tests plus 41 UI
tests (397 total), zero failures, with repository/security/traceability/
architecture/migration/evidence checks green.
Hosted Actions `32917355488` subsequently passed the same 356 unit/integration
plus 41 UI test gate at `3c90e33`, including the compact-window Inspector and
navigator accessibility corrections.

`SF-AUTHORING-013` remains a **VERIFIED BOUNDED** historical milestone. Its
broader deferred scope is unchanged. SF-AUTHORING-014 is the sole active item;
no subsequent feature item is READY.

## Authoritative files

- `SiteForge/TransformModel.swift`: canonical `style.fill.layers.v1` codec,
  migration adapter, and `DesignInspectorCommandRegistry` layer operations.
- `SiteForge/CanvasRendererCore.swift`: immutable renderer-facing layer data
  and deterministic compositing policy.
- `SiteForge/WorkspaceShellModel.swift`: identity-gated command submission
  and renderer snapshot preparation.
- `SiteForge/WorkspaceShellView.swift`: native tile compositing and visible
  Design Inspector Fill Layers controls.
- `SiteForge/FillLayerListInspectorView.swift`: per-layer and per-stop native
  colour controls plus accessible gradient-stop ordering actions.
- `Tests/SiteForgeTests/TransformModelTests.swift`,
  `Tests/SiteForgeTests/CanvasRendererTests.swift`,
  `Tests/SiteForgeTests/ProjectPackageTests.swift`, and
  `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift`: focused evidence.
- `docs/evidence/SF-AUTHORING-013-FILL-LAYERS-CHECKPOINT.md`: verified bounded
  milestone evidence and visual review.
- `docs/evidence/SF-AUDIT-001-CORRECTIONS.md`: exact post-gate corrections,
  focused evidence, and recurring-risk controls.
- `SiteForge/ProjectResources.swift`, `SiteForge/FileAccessBoundary.swift`,
  `SiteForge/InsertionModel.swift`, and `SiteForge/DiagnosticSupport.swift`:
  resource identity, cancellation, large-Grid, and diagnostic corrections.
- `SiteForge/WorkspaceShellModel.swift`: off-main production scene, renderer,
  selection, and viewport projection with identity-gated main-actor adoption.
- `SiteForge/WorkspaceMaterialPolicy.swift`,
  `SiteForge/WorkspaceShellView.swift`: document-window policy and minimum
  workspace/canvas integration corrections.

## Invariants that must not change

1. `DocumentNode.properties` is the sole canonical style source. `v1` wins
   whenever its order key exists; legacy v4 solid properties are read only
   before first v1 write and must never be written alongside v1.
2. Layer/stop identity and authored order are stable. The renderer may make a
   local stable position sort for interpolation, but may not rewrite model
   order.
3. All edits use `DesignInspectorCommandRegistry`; views, test code, and
   renderer code may not mutate canonical properties directly.
4. Renderer snapshots are immutable and identity-gated. Object opacity applies
   once to the complete authored layer stack. Editor chrome is separate from
   authored and preview-facing compositing.
5. Preserve the existing centered pasteboard, top-left/Y-down coordinate
   convention, normal maximized window policy, blank-project emptiness, and
   focused command/window ownership behavior.

## Next task

No item after SF-AUTHORING-014 is READY. Create another queue item only when its requirements
and exclusions are explicit. Do not silently expand deferred SF-0506/SF-0508
capability or represent the product as release-complete.

## Stop/escalate conditions

Stop and record an entry in `docs/OPEN_DECISIONS.md` only for an unresolved
product choice with broad downstream effect or an incompatible migration.
Do not commit generated artifacts, local result bundles, secrets, or machine
paths. External signing, notarization, publication, credentials, or a genuinely
unavailable external dependency remain owner boundaries. Do not begin a
feature beyond SF-AUTHORING-014 until a READY queue item defines its scope.
