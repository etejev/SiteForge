# Codex Continuation Handoff

## Current static-control checkpoint

SF-AUTHORING-041 adds immutable static-tree projection for existing canonical
Button and Link controls. `InternalDocumentRenderTreeCompiler` is the sole
output boundary: it accepts only `CanonicalLinkTarget` values that already pass
canonical validation, resolves internal Page/Section references only against
the current package route map, escapes output, and leaves missing targets
inert. Static Buttons are deliberately emitted as disabled `type=button`
controls: no browser action or submission behavior exists. Typed new-context
Links emit only `target=_blank` with `rel=noopener noreferrer`.

No local test execution was performed for this checkpoint under the current
owner-directed test pause. The focused compiler regression
`CanvasRendererTests.testStaticControlCompilerEscapesTypedRoutesAndKeepsMissingTargetsInert`
now covers escaped external/section routes, stable anchors, missing targets,
and inert button output; it must be run before any runtime or export work.

## Current checkpoint

SF-AUTHORING-038 adds fixed-breakpoint static CSS emission for canonical
geometry and visibility overrides. SF-AUTHORING-037 Local form-validation and
preview-state foundation v1 remains IN PROGRESS. `LocalFormValidationEngine` resolves only caller-owned,
non-Codable `FormVisitorValueSnapshot` input against canonical Form metadata.
Its results contain stable document/revision/form/field identities and failure
categories only; it has no command, history, package, autosave, recovery,
network, browser, or submission path. The Form Inspector presents its adopted
category-only empty-draft result without retaining input; focused model coverage
is 3/3. Do not make visitor values canonical. The next bounded Form task is
authored validation-rule configuration through the existing Inspector registry.

SF-AUTHORING-036 Accessible form authoring v1 remains IN PROGRESS. Form is now
an enabled Elements/Insert container and its Text children have native bounded
Content Inspector field controls. `FormInspectorCommandRegistry` is the sole
identity-gated canonical edit boundary; focused foundation plus current-slice
coverage is green (9/9). Actual-app UI evidence and all visitor/runtime
submission behavior remain deferred.

## Current Form boundary

- Form field metadata is valid only on Text nodes owned by a Form node.
- Static output permits only escaped text/email/textarea/checkbox/select and
  disabled unconfigured-submit controls; it has no runtime submission path.
- Page duplication remaps stable select-option IDs but keeps labels and values.
- The next bounded task is actual-app keyboard, pointer, and accessibility
  evidence for Form insertion and field editing. Keep visitor values,
  submission destinations, validation rules, anti-abuse, generated-site
  runtime, scale, and release acceptance out of scope.

## Earlier delivered boundary

- `WorkspaceShellState` owns a scene-local `LocalPreviewState` containing an
  immutable `CanvasPreviewSceneSnapshot` captured only by Preview or Refresh.
- Preview renders authored Frame, Text, fill and Image content without editor
  selection, grid, guides or insertion chrome. It never writes document or
  history state.
- The Preview toolbar and Command-Shift-P route to the same state; Refresh
  adopts only a matching newer render revision; Done/Escape closes and restores
  editor focus.
- The constrained-window reveal helper aligns the live target, while retaining
  the approved 1100-point production window width on narrow displays.

## Evidence and invariants

- `docs/evidence/SF-AUTHORING-025-LOCAL-PREVIEW.md` records scope and focused
  tests. The UI journey retains `SF-AUTHORING-025 local preview authored
  snapshot` in its result bundle.
- `CanvasRendererTests.testLocalPreviewStateFreezesRevisionAndRejectsStaleRefreshes`
  and `SiteForgeLaunchTests.testLocalPreviewRefreshesOnlyOnExplicitRequestJourney`
  are the focused Preview checks.
- Do not turn preview scene state into canonical document/history state or add
  browser runtime, generated HTML/CSS/JS, export, publishing, routes, remote
  content or CMS. SF-1203 semantic authoring begins as its own bounded slice.

## Deferred scope

SF-1201 and SF-1202 remain Partial outside this bounded local-preview surface:
runtime bundles, generated render trees, export/preview parity, large-project
performance certification, broad accessibility matrices and release acceptance
remain future work.
