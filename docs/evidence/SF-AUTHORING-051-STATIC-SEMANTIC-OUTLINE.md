# SF-AUTHORING-051 — Static semantic-outline foundation

## Bounded result

The immutable document compiler now carries canonical parent NodeID provenance
into each static render-tree node. `MultiPageStaticBuildPlanner` emits a
deterministic, content-free `semantic-outline.txt` plan artifact with page,
node, verified parent-or-root marker, and closed semantic element type.

The outline validates node identity and closed semantic vocabulary before
emission. It does not alter emitted HTML nesting, canonical document state,
resource bytes, browser execution, or static-file writing.

## Requirements and evidence

- `SF-1203-003`–`004`: computed semantic hierarchy has deterministic stable
  provenance and safe omission at invalid/missing boundaries.
- `SF-1206-003`–`004`: the multi-page plan gains a deterministic metadata-only
  output artifact without packaging or file-system side effects.

The queued focused regression is
`CommandKernelTests.testMultiPageStaticBuildPlanUsesAuthoredSemanticElementResolution`.
Local test execution remains paused by owner direction.

## Explicit exclusions

Nested browser DOM generation, arbitrary HTML/attributes, browser execution,
file writes, source maps, publishing, and release acceptance remain deferred.
