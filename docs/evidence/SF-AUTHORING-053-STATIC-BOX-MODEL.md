# SF-AUTHORING-053 — Static authored-box parity foundation

## Bounded result

`StaticLayoutOutputEmitter` now adds only the fixed declaration
`box-sizing: border-box` to every valid typed authored geometry rule. The
canonical `layout.width` and `layout.height` therefore remain the outer static
box when a later bounded presentation rule supplies border or padding.

This is a closed compiler default, not an authored CSS property or a new
layout mode. It neither changes canonical geometry nor enables arbitrary CSS,
browser layout execution, responsive source sets, generated files, publishing,
or release work.

## Requirements and evidence

- `SF-1204-003`–`004`: typed layout output has deterministic, safe box-model
  behavior and cannot silently expand an authored frame.

The queued focused regression is
`CanvasRendererTests.testStaticLayoutOutputUsesStableRoundingAndExplicitVisibilityOverrides`.
Local test execution remains paused by owner direction.

## Explicit exclusions

Authorable CSS, layout modes, browser rendering, generated output files,
publishing, and release acceptance remain deferred.
