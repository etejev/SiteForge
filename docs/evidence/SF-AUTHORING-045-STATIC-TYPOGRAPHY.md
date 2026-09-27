# SF-AUTHORING-045 — Static typography-output parity foundation

## Bounded outcome

The immutable static render tree now carries canonical plain Text content and
effective canonical typography only for Text nodes. `SafeHTMLEmitter` escapes
that plain content in its final HTML context. `StaticTypographyOutputEmitter`
adds one deterministic NodeID-scoped CSS rule per eligible Text node:

- canonical System family becomes the fixed portable `system-ui` family;
- canonical weight maps to the fixed 400/500/600/700 scale;
- finite canonical font size, line height, tracking, and alignment become
  allowlisted scalar declarations; and
- unsupported installed-family names are omitted without changing canonical
  intent.

The projection neither reads installed fonts nor accepts raw CSS/HTML. It does
not mutate component default/override text; component expansion remains out of
scope.

## Requirement coverage

This is bounded evidence for deterministic typography resolution and
failure-safe static omission under `SF-0507-003`/`004`, together with escaped
Text semantic/static output under `SF-1203-003` and typed CSS projection under
`SF-1204-003`/`004`. These modules remain Partial: rich text, local/web fonts,
browser behavior, responsive typography, generated files, export/publishing,
and release acceptance are deferred.

## Focused regression

`CanvasRendererTests.testStaticTypographyOutputEscapesTextAndUsesAllowlistedCanonicalValues`
checks escaped Text content plus System-family, weight, size, and alignment
output. It has been added but not run under the owner-directed test pause.
