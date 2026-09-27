# SF-AUTHORING-049 — Static asset-manifest integrity foundation

## Bounded result

`MultiPageStaticBuildPlanner` now includes `assets.manifest.txt` only when
there are verified content-addressed Image references. Each deterministic
entry contains the stable AssetID, the validated `assets/<sha256>.<extension>`
plan path, and validated pixel dimensions. It intentionally excludes original
filenames, local paths, resource bytes, EXIF, and arbitrary metadata.

Missing or corrupt export entries are omitted from this optional integrity
manifest and remain the existing safe missing-resource state in static markup.
The manifest is an immutable in-memory planning artifact; it does not export
bytes, invoke a writer, create a browser/runtime dependency, or change
canonical project content.

## Requirements and evidence

- `SF-0801-003`–`004`: stable Image/resource identity resolves only through
  verified content-addressed output references with safe absence handling.
- `SF-1206-003`–`004`: output planning has deterministic ordering and bounded
  failure behavior without exposing user paths or content.

The queued focused regression is
`CommandKernelTests.testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference`.
Local test execution remains paused by owner direction.

## Explicit exclusions

Resource-byte writes, generated-site packaging, browser loading, remote
providers, source sets, image transforms, publishing, and release acceptance
remain deferred.
