# Codex Continuation Handoff

## Current checkpoint

SF-AUTHORING-025 Local Preview v1 and SF-CI-025 are hosted verified. Actions
`36166584811` passed at `1ab912e` with 430 unit/integration + 63 UI = 493 tests
and zero failures. SF-AUTHORING-026 Semantic HTML element authoring v1 is in
progress; its focused model/package/preview checks pass and its retained native
Inspector journey passed before a later external XCTest automation-mode error.
SF-AUTHORING-027 now contains the typed CSS-rule marker foundation; its next
bounded task is the identity-gated transaction registry and persistence tests.

## Delivered boundary

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
