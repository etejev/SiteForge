# SF-AUTHORING-050 — Static semantic-element resolution foundation

## Bounded result

The immutable static-tree compiler now uses the same typed
`CanonicalSemanticElement.resolved(for:)` path as the Semantic Inspector.
An authored supported semantic role therefore reaches safe static markup with
its NodeID selector unchanged. Omitted metadata resolves to the deterministic
node-kind default. Invalid historical metadata has no output effect and does
not become a raw element or a canonical mutation.

## Requirements and evidence

- `SF-1203-001`–`004`: typed semantic identity, explicit provenance,
  deterministic defaulting, and safe invalid-state handling share one resolver.

The queued focused regression is
`CommandKernelTests.testMultiPageStaticBuildPlanUsesAuthoredSemanticElementResolution`.
Local test execution remains paused by owner direction.

## Explicit exclusions

Semantic Inspector UI changes, arbitrary HTML/attributes, browser execution,
generated-site packaging, publishing, and release acceptance remain deferred.
