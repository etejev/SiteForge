# SF-AUTHORING-056 — Native bounded outer-shadow foundation

## Bounded result

The established typed `style.box.v1` outer shadow now has explicit enabled
provenance for Frame and Section. Existing shadows without `shadow.enabled`
retain their deterministic enabled fallback. Explicit `false` preserves the
typed color, X/Y offset, blur, and spread rather than deleting them; reset
removes only the enabled property and restores the fallback.

The existing identity-gated Design transaction registry remains the only
canonical write path. The native canvas omits disabled shadow compositing,
Local Preview resolves the same canvas snapshot, and the closed static output
projection emits `box-shadow` only when the shadow resolves enabled. Bounds
remain the existing finite ranges: offsets ±10,000, blur 0...1,000, and spread
±1,000; RGBA remains normalized 0...1.

## Focused evidence — 2026-09-27

- `TransformModelTests.testDesignBoxStyleRegistryCommitsValidatesMixesPersistsAndUndoRedo`
- `CommandKernelTests.testMultiPageStaticBuildPlanProjectsClosedFrameBoxStyle`
- `CanvasTextRenderingTests.testBorderRadiusAndShadowUseProductionTileCompositionWithoutGeometryDrift`
- `SiteForgeLaunchTests.testDesignInspectorBorderRadiusShadowUndoRedoAccessibilityJourney`

These selectors cover typed transaction/inverse behavior, enabled-state
persistence and cancellation, enabled/disabled static adoption, production
tile compositing without authored-frame drift, and the native accessible
Inspector toggle. All four passed on 2026-09-27. The retained native
Inspector captures were reviewed at original resolution: the maximized shell,
canvas selection, and compact scrollable Design controls remained readable;
disabling shadow removed only the authored effect. The normative modules
remain Partial.

## Explicit exclusions

Multiple/layered, inner, or inset shadows; blend modes; filters; arbitrary
CSS; browser runtime; unsupported node kinds; publishing; and release
acceptance remain deferred.
