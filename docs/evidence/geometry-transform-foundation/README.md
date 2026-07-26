# SF-AUTHORING-006 Geometry Transform Evidence

This bounded evidence covers `SF-0403-001` through `SF-0403-008` without claiming the complete transform module or release acceptance.

## Reproduction

```sh
scripts/run-transform-foundation-evidence.sh
xcodebuild -project SiteForge.xcodeproj -scheme SiteForge -destination platform=macOS \
  -derivedDataPath "${TMPDIR%/}/SiteForge/DerivedData" test \
  -only-testing:SiteForgeUITests/SiteForgeLaunchTests/testGeometryTransformPointerKeyboardNumericUndoRedoAndAccessibilityJourney
./sf verify
```

The retained machine-readable record is `measurements.json`. It names the hardware, processor, macOS and Xcode versions, optimized-test configuration, raw samples, resident-memory reading, methodology, and limitations.

## Behavioral and visual evidence

- `TransformModelTests` exercises exact move and all eight resize resolutions, axis constraints, stable operation identity, lifecycle/revision/renderer gates, invalid geometry, missing/hidden/locked/unavailable/cross-page targets, compatible ordered multiple movement, explicit multiple-resize rejection, cancellation, stale preview neutrality, one transaction and inverse, undo/redo, persisted history/package determinism, renderer hit testing, old/new dirty regions, diagnostics, and production workspace synchronization.
- The running-app UI journey uses genuine pointer drags on native accessible resize handles and selected content, then exercises inspector numeric movement/resizing, keyboard movement, undo, redo, Escape, Layers synchronization, visible focus, and stable accessibility labels/values.
- XCTest retains screenshots named `SF-AUTHORING-006 pointer resize`, `SF-AUTHORING-006 numeric move and resize`, `SF-AUTHORING-006 pointer move`, and `SF-AUTHORING-006 cancelled selection scope`. These were inspected for handle visibility, preview/committed alignment, canvas/Layers/inspector/status consistency, and absence of panel overlap at the exercised window size.

## Retained results and limits

- 100-object transform preparation P95: **0.629 ms**.
- 10,000-object transform preparation P95: **28.493 ms**.
- Maximum resident-memory reading: **110,804,992 bytes**.
- Each capacity fixture transforms one selected authored frame in a real 100- or 10,000-object canonical project. It does not claim interactive transformation of 10,000 simultaneously selected objects.
- The 10,000-object result exceeds one 60 Hz frame interval. It is truthful capacity evidence, not proof of final incremental layout/render performance, interactive frame pacing, or an owner-approved hardware budget.
- Rotation, skew, snapping, guides, rich-text transformation, responsive-breakpoint editing, broad inspector property editing, export generation, OS-level VoiceOver speech/settings acceptance, and release qualification remain outside this slice.
