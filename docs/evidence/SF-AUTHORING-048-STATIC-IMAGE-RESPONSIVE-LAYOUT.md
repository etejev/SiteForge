# SF-AUTHORING-048 — Static Image responsive-layout foundation

## Bounded result

The immutable static build plan now carries verified Image resource dimensions
as safe integer HTML hints while `StaticLayoutOutputEmitter` remains the sole
source of the authored Image box and explicit Tablet/Mobile geometry and
visibility rules. `InternalStaticImage` retains the canonical `AssetID`, safe
content-addressed path-or-missing state, alt/decorative intent, fit/focal
intent, and optional validated intrinsic dimensions.

`width` and `height` attributes are emitted only for validated `ImageAsset`
metadata. They do not replace `layout.x/y/width/height`, introduce an image
aspect-ratio constraint, or change responsive resolution. Missing/corrupt
resources retain the AssetID and safe missing marker, with no Finder path,
remote URL, generated resource write, source-set selection, transform, or
browser execution path.

## Requirements and evidence

- `SF-0802-003`–`004`: typed Image size/presentation intent reaches the
  immutable render tree and a closed HTML/CSS projection.
- `SF-0601-003` and `SF-0603-003`: the existing typed responsive geometry and
  visibility cascade remains the only static Image breakpoint resolver.
- `SF-1203-003`, `SF-1204-003`–`004`: output is a deterministic in-memory
  plan using stable NodeID selectors and safe omission at invalid boundaries.

The queued focused regression is
`CommandKernelTests.testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference`.
Local test execution remains paused by owner direction for this checkpoint.

## Explicit exclusions

Responsive source sets, remote loading, image transforms/crops/renditions,
arbitrary CSS, browser execution, generated resource writes, static-site
packaging, publishing, and release acceptance remain deferred.
