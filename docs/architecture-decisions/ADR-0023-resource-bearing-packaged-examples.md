# ADR-0023 — Resource-bearing packaged examples

Status: Accepted for the bounded SF-LOCAL-BUILDER-001 implementation.

Requirements: SF-0204-002/004/005/006; supporting SF-0801-004/005.

## Decision

Ship the ordinary UI-authored Aurora package and content-addressed resource
sidecar as a bundled example. Load through the existing package and resource
readers, validate canonical data and every resource digest, then establish a
fresh ProjectID/DocumentID, revision zero and clean history baseline. Preserve
internal identities together so existing page links, assets and tokens remain
consistent within the new document identity. Never import source history or
unrelated optional package members into the new baseline.

Bundled resources require an explicit read-only mode in ProjectResourceStore:
resolve beneath the application resource root, reject writable-by-other or
unsafe files, retain descriptor/no-follow/hash checks, and forbid creation or
writes. Application bundle read permissions differ from private resource-store
permissions; private stores retain their existing stricter policy.

## Alternatives and consequences

Hand-assembling a separate sample model or renderer would duplicate product
truth and lose the actual authoring evidence. Mutating bundle permissions would
break bundle integrity. Neither is used. The source package stays unchanged;
new examples remain ordinary editable documents and save through the existing
resource-bearing lifecycle. Missing/corrupt input or cancellation cannot replace
the current document. Remote catalogues and downloads are outside this decision.

## Evidence

LaunchExperienceTests covers independent creation, clean history, exact resource
identity, invalid/corrupt input, missing resources, cancellation, save/reopen,
and the bundle store's read-only/containment boundary (five focused tests green).
Actual-app Welcome acceptance and integrated verification are tracked separately
in the SF-LOCAL-BUILDER-001 evidence; this ADR does not claim those gates passed.
