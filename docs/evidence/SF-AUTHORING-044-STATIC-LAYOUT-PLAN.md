# SF-AUTHORING-044 — Static multi-page layout-plan integration

## Bounded outcome

`MultiPageStaticBuildPlanner` now appends a deterministic `styles.css` entry
when the canonical pages contain valid typed geometry. Its content is the
immutable `StaticLayoutOutputEmitter` projection introduced by
SF-AUTHORING-043. The plan uses the same stable NodeID-derived selectors,
base geometry, explicit Tablet/Mobile overrides, and visibility cascade as the
compiler foundation.

The entry is an in-memory build-plan artifact only. No writer is invoked, no
HTML shell is linked, and the change creates neither authored CSS state nor a
browser/runtime execution path.

## Requirement coverage

This contributes bounded deterministic planning evidence for `SF-1206-003`
and extends the projection boundary of `SF-1204-003`/`004`. `SF-1204` and
`SF-1206` remain Partial: authorable CSS, generated-site file packaging,
document shells, browser layout, export/publishing, and release acceptance are
explicitly deferred.

## Focused regression

`CommandKernelTests.testMultiPageStaticBuildPlanIncludesTypedLayoutStylesheet`
asserts that a canonical Frame's stable selector, base geometry, and mobile
override appear in the plan stylesheet. It was added but not executed because
the owner-directed test pause remains active.
