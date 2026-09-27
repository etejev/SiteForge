# SF-AUTHORING-059 — Local color-token appearance bindings v1

Bounded evidence for SF-0509-001–008, SF-0506-001–008, and SF-0508-001–008. These normative modules remain Partial.

## Delivered slice

- Schema 10 stores typed target-keyed ColorTokenID bindings for an enabled solid Fill, an authored Border, and an authored Outer Shadow. Schema-9 fill references migrate to the new key without changing their PropertyID, token ID, origin, or literal fallback. A current-schema legacy key is rejected.
- The central token command binds/unbinds applicable selected nodes atomically, preserves exact history, rejects hidden/locked selections and in-use token deletion, and leaves unsupported kinds unchanged. Missing token records retain the literal color. Unbind freezes the resolved color into the target's literal properties; while bound, native literal color wells are disabled with an unbind explanation.
- The Design Inspector exposes a visible Fill/Border/Outer Shadow target chooser and binding status. Native canvas, scene-local Preview, and closed Frame/Section static output resolve the same bound color. Selection and grid chrome are editor-only.

## Focused evidence

- `TransformModelTests.testLocalColorTokenBorderShadowBindingHistoryAndStaticResolution` — passed; covers bind/recolor/unbind, literal preservation, in-use deletion, exact history, persistence, and static projection.
- `TransformModelTests.testLocalColorTokenSchemaNineFillBindingMigratesToTargetKeyedIdentity` — passed; uses a schema-nine envelope synthesized from the test document, not a checked-in historical fixture.
- `TransformModelTests.testLocalColorTokenTargetValidationFallbackMixedAndNeutralFailures` — passed; covers strict target validation, missing-token fallback, compatible/incompatible selection, stale and cancelled neutrality.
- `TransformModelTests.testLocalColorTokenCreateBindRecolorUnbindHistoryAndPersistence` — passed for the original Fill route after schema migration.
- `SiteForgeLaunchTests.testLocalColorTokenBorderAndOuterShadowInspectorJourney` — passed twice, including after the target chooser layout refinement. Original-resolution window attachments “border token bound”, “outer shadow token bound”, and “outer shadow literal retained” were visually inspected: target labels fit on one line; red authored Border and Shadow align with the selected Frame; the artboard, grid, and editor-only selection remain distinct.
- `SiteForgeLaunchTests.testLocalColorTokenInspectorCreateBindAndUnbindJourney` — passed for the established Fill interaction after the chooser change.

The focused checkpoint is 6 exact selectors passed (4 model and 2 actual-app), zero assertion failures. One mistyped UI selector failed before XCTest launched; the corrected exact selector passed. No full `./sf verify`, push, or hosted gate is claimed for Development Prompt 6; that checkpoint is reserved for Prompt 10.

## Deferred

Aliases, themes/modes, tokens for text/gradients/images/opacity, broad color management, project-wide scale and accessibility matrices, actual-app save/close/reopen for the new targets, browser/runtime output, publishing, and release acceptance remain outside this slice.
