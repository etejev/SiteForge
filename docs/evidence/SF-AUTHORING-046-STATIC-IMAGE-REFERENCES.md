# SF-AUTHORING-046 — Static Image resource-reference parity foundation

## Bounded outcome

The static render tree has a typed `InternalStaticImage` projection for
canonical Image nodes. It retains the stable `AssetID`, canonical alt text,
and decorative state. `MultiPageStaticBuildPlanner` takes optional,
already-verified `StaticAssetExportEntry` values and resolves a `src` only by
calling the existing content-addressed resource-reference planner.

The HTML boundary emits only a checked `assets/<sha256>.png|jpg` path. If the
resource is unavailable, corrupt, unsupported, or absent from the supplied
plan, it emits an in-bounds `data-siteforge-asset-state="missing"` marker
instead. Canonical resource intent is not changed, and Finder paths, remote
URLs, EXIF, bytes, and user-provided filenames never enter output markup.

Decorative Images receive empty `alt` plus presentation semantics. Other
Images receive escaped canonical alt text; invalid historical text is safely
empty rather than being interpreted as HTML.

## Requirement coverage

This is bounded static projection evidence for `SF-0801-003`, `SF-0802-003`,
and `SF-1203-003`/`004`. The modules remain Partial: byte export/writing,
browser image loading, remote content, responsive source sets, preview/export
parity, publishing, and release acceptance are deferred.

## Focused regression

`CommandKernelTests.testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference`
checks that only a verified content-addressed entry supplies `src`, while
canonical alt and stable asset provenance are retained. It is added but not
run under the owner-directed test pause.
