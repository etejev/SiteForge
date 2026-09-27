# SF-AUTHORING-043 — Static layout-output parity foundation

## Bounded outcome

`StaticLayoutOutputEmitter` is an immutable compiler-side projection of typed
canonical geometry and responsive visibility. It emits only allowlisted
absolute-position declarations for stable NodeID-derived selectors:

- base `left`, `top`, `width`, `height`, `position`, and `display` values;
- explicit Tablet (`600…1023`) and Mobile (`≤599`) geometry overrides; and
- explicit breakpoint visibility overrides.

Base visibility is emitted from the Desktop cascade. A breakpoint rule is
emitted only when an override was explicitly authored, so inherited hidden
state remains inherited instead of being copied into a second source of
truth. Invalid/nonfinite or out-of-domain geometry is omitted rather than
being serialized as an unsafe declaration. Numeric output is rounded
deterministically to three decimal places using a fixed POSIX representation.

## Requirement coverage

This is bounded evidence for deterministic resolution and failure-safe static
projection under `SF-1204-003` and `SF-1204-004`, with existing responsive
geometry/visibility resolution under `SF-0601-003` and `SF-0603-003`. The
broader `SF-1204` module remains Partial: it has no authored CSS-rule model,
CSS Inspector, browser execution, static file output, publishing, or release
acceptance.

## Focused regression

`CanvasRendererTests.testStaticLayoutOutputUsesStableRoundingAndExplicitVisibilityOverrides`
covers stable rounding, base hidden state, an explicit Tablet geometry
override, and a Mobile visibility restoration. Per the owner-directed test
pause, it has been added but not executed in this checkpoint.

## Deferred scope

Raw CSS/media input, arbitrary selectors, browser/runtime layout, flex/grid
or container queries, generated files, preview/export parity, publishing, and
release acceptance remain deferred.
