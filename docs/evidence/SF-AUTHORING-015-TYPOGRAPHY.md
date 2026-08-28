# SF-AUTHORING-015 Typography Evidence

## Bounded outcome

SiteForge now stores plain-Text typography in the strict
`style.typography.v1.*` canonical namespace. The Design Inspector authors font
family, regular/medium/semibold/bold weight, point size, explicit line height,
tracking, and leading/center/trailing paragraph alignment. Drafts remain
scene-local; one validated edit becomes one identity-gated document transaction
and exact inverse. Reset removes the namespace and restores the deterministic
System 14/17/regular/leading default.

Installed font resolution is deliberately noncanonical. Missing families keep
their authored name, render through the system fallback, and expose a specific
recoverable Inspector status. `CanvasTextLayout` supplies the same resolved
font, paragraph, tracking, wrapping, insets, and vertical placement to committed
tile text and the live `NSTextView` editor.

## Focused automated evidence

- `TransformModelTests/testTypographyRegistryValidatesMixesResetsPersistsAndUndoRedo`
- `CanvasTextRenderingTests/testCanonicalTypographySharesRendererAndInlineMetricsAcrossZoomAndAlignment`
- `ProjectPackageTests/testTypographyPersistsAcrossPackageReopenAndOwnedRecovery`
- `SiteForgeLaunchTests/testDesignInspectorTypographyInlineUndoRedoAccessibilityJourney`

The focused model/render/package group passed 3/3 and the fresh-process app
journey passed 1/1 on 2026-08-28. The app journey uses native fields and pickers,
Return, Escape, Undo/Redo, inline editing, a missing-font fallback, native Save,
process termination, and production package reopen.

## Visual review

Six original-resolution attachments from the final focused result bundle were
reviewed: default controls; Menlo/Bold/22 pt/30 pt line height/1.5 tracking and
center alignment; Undo/Redo; live inline-editor parity; missing-font fallback;
and saved/reopened state. The normal maximized window retained menu bar and Dock,
labels did not wrap, glyphs remained upright, the editor and selection rectangle
coincided, the page/grid hierarchy remained clear, and no ghost/debug content
was present. Larger type is truthfully clipped by the unchanged authored 120×24
Text frame; automatic sizing is outside this bounded slice.

Focused result bundles:

- `focused-82e51945-9b43-44a2-9ce8-938c343e3d47.xcresult` (3/3)
- `focused-65fe4e4d-32ed-4bef-a32d-e2a20b6376f2.xcresult` (1/1)

## Explicitly deferred

Font import/licensing, web fonts, variable axes, rich-text ranges, lists/links,
advanced paragraph controls, vertical/path text, automatic text sizing,
responsive typography overrides, tokens, preview/export parity, cross-hardware
performance acceptance, and release acceptance remain outside SF-AUTHORING-015.

## Completion gate

The documentation-inclusive `./sf verify` passed 363 unit/integration plus 44
actual-app UI tests (407 total), zero failures, on 2026-08-28. Security,
traceability, architecture, migration, evidence, repository, build, and test
gates all passed.
