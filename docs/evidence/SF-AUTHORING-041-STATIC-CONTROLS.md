# SF-AUTHORING-041 — Static Button and Link output foundation

## Bounded scope

This checkpoint covers immutable compiler projection for the existing typed
Button and Link canonical state under SF-0806-001–005, SF-1102-001–005, and
SF-1203-001–005. It is intentionally not a browser runtime or publishing
feature.

## Delivered behavior

- The static render-tree compiler resolves `CanonicalLinkTarget` directly from
  validated canonical nodes; no view state, raw HTML, event handler, or path
  string becomes an output source.
- Valid external HTTP(S) targets and known package Page/Section targets are
  escaped and emitted as static Link hrefs. Section targets use a stable NodeID
  fragment only after the target Section is present in the route map.
- A Link with typed new-context intent emits only the conventional safe static
  `target=_blank` and `rel=noopener noreferrer` pair; no editor/browser runtime
  or arbitrary attribute path is introduced.
- Missing and absent Link targets remain visible, accessible inert anchors.
- Button output is a disabled `type=button` control. It cannot accidentally
  submit a form or introduce a browser action in this bounded static surface.
- Internal render-tree snapshots remain immutable and use stable NodeID-derived
  selectors; canonical document data is never mutated during compilation.

## Verification status

No local tests or UI automation were run for this checkpoint because the owner
has explicitly paused local test execution. The focused regression
`CanvasRendererTests.testStaticControlCompilerEscapesTypedRoutesAndKeepsMissingTargetsInert`
was added but not executed; it records external/section route escaping, stable
anchors, missing target fallback, and inert Button output for the next allowed
verification step.

## Deferred scope

Browser navigation/runtime behavior, button actions, form submission, arbitrary
HTML and attributes, generated-site accessibility certification, static-file
export, publishing, performance certification, and release acceptance remain
deferred.
