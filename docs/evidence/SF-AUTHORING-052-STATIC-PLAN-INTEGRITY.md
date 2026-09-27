# SF-AUTHORING-052 — Static plan-integrity foundation

## Bounded result

`LocalStaticBuildPlan` now computes a deterministic SHA-256 integrity digest
from a path-sorted, length-delimited in-memory representation of its planned
files. This gives callers stable revision-independent comparison provenance
without writing an additional file, exposing source content, or invoking the
static writer.

The digest is recomputed for an optimized profile plan, so it always describes
the exact immutable file list carried by that plan. It does not become
canonical project state, a browser checksum, a publishing protocol, or a
resource-byte export.

## Requirements and evidence

- `SF-1206-003`–`004`: static plans have deterministic output provenance and
  safe immutable failure boundaries.

The queued focused regression is
`CommandKernelTests.testFormFieldsPreserveAtomicHistoryAndRemapSelectOptionsOnPageDuplicate`.
Local test execution remains paused by owner direction.

## Explicit exclusions

Generated integrity files, signature/notarization, browser verification,
resource-byte export, publishing, and release acceptance remain deferred.
