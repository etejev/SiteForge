# SF-AUTHORING-047 — Static Image fit/focal output parity foundation

## Bounded outcome

`StaticImageStyleOutputEmitter` consumes the existing typed `InternalStaticImage`
projection. Each valid Image receives an existing NodeID-scoped stylesheet rule:

- Fit → `object-fit: contain`;
- Fill → `object-fit: cover`;
- Stretch → `object-fit: fill`; and
- normalized focal X/Y → fixed rounded percentage `object-position` values.

Only finite 0…1 focal values are eligible. Invalid metadata is omitted from
static presentation output without modifying canonical Image intent. This is
non-destructive presentation mapping: no crop, rendition, derived bytes,
transform, or additional image source exists.

## Requirement coverage

This is bounded static projection evidence for `SF-0802-003`/`004` and
`SF-1204-003`/`004`. Image editing, filters, masks, source sets, browser
loading, resource-byte writes, export/publishing, and release acceptance remain
deferred.

## Focused regression

`CommandKernelTests.testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference`
now also asserts default Fit and centered focal presentation in `styles.css`.
It has not run under the owner-directed test pause.
