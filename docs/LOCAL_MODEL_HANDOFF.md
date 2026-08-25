# Local Continuation Handoff — SF-AUTHORING-013

## Current checkpoint

`SF-AUTHORING-013` remains **IN PROGRESS**. Work is on `main` in a reviewed
checkpoint commit. The applicable bounded requirements are `SF-0508-001`
through `SF-0508-008`; do not mark the normative module complete.

## Authoritative files

- `SiteForge/TransformModel.swift`: canonical `style.fill.layers.v1` codec,
  migration adapter, and `DesignInspectorCommandRegistry` layer operations.
- `SiteForge/CanvasRendererCore.swift`: immutable renderer-facing layer data
  and deterministic compositing policy.
- `SiteForge/WorkspaceShellModel.swift`: identity-gated command submission
  and renderer snapshot preparation.
- `SiteForge/WorkspaceShellView.swift`: native tile compositing and visible
  Design Inspector Fill Layers controls.
- `Tests/SiteForgeTests/TransformModelTests.swift`,
  `Tests/SiteForgeTests/CanvasRendererTests.swift`, and
  `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift`: focused evidence.
- `docs/evidence/SF-AUTHORING-013-FILL-LAYERS-CHECKPOINT.md`: actual current
  checkpoint evidence.

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

## Exact next bounded task

Implement native colour editing for an individual selected solid layer and
for gradient stops, keeping the existing NSColorWell experience and routing
it through `DesignInspectorCommandRegistry`. Then add an accessible gradient
stop reorder action. Prove command inverses, cancel/stale neutrality, and
saved/reopened identity/order with focused tests only.

Suggested focused selectors before expanding further:

1. `SiteForgeTests/TransformModelTests/testDesignFillLayerRegistryCommitsOrderedLayersWithExactHistoryAndPersistence`
2. `SiteForgeTests/TransformModelTests/testDesignFillLayerRegistryRejectsInvalidStaleCancelAndAllInapplicableEdits`
3. `SiteForgeTests/CanvasRendererTests/testAuthoredFillLayerCompositorPreservesOrderDisabledLayersStopsAnglesAndOpacity`
4. `SiteForgeUITests/SiteForgeLaunchTests/testDesignInspectorOrderedFillLayersAccessibilityJourney`

## Stop/escalate conditions

Stop and record an entry in `docs/OPEN_DECISIONS.md` only for an unresolved
product choice with broad downstream effect or an incompatible migration.
Do not run the complete UI suite or `./sf verify` at this checkpoint. Do not
commit generated artifacts, local result bundles, secrets, or machine paths.
Do not begin image fills, blending/filter effects, borders, shadows, tokens,
responsive overrides, preview/export parity, or release work.
