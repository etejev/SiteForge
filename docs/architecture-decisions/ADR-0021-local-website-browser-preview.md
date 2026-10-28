# ADR-0021 — Immutable local website preview

Status: accepted for the owner-authorized local-builder slice; implementation
and browser acceptance remain in progress.

Requirements: SF-1201-002/003/004/006/008, SF-1206-003/004,
SF-1208-003/004/006/008.

## Decision

Safari website preview consumes `StaticBuildCompiler` and its immutable
`LocalStaticBuildPlan`, the same artifact written by local static export.
The native canvas-device preview remains a separate editor aid, not evidence
of browser output parity. No alternate HTML generator or sample-specific
renderer is introduced.

An app-owned Network listener binds only IPv4 loopback on an OS-assigned port.
It serves a validated in-memory mapping of compiler output paths to bytes.
HTTP requests never access the project, checkout, or arbitrary filesystem.
Only GET/HEAD with the exact loopback Host/port are accepted; traversal,
double-encoding, unsupported methods and oversized headers are rejected.
Connections have bounded concurrency, header size and lifetime.

Resource hashing/validation and compilation run on a worker actor using an
immutable package snapshot. Adoption requires the same document/revision and
request identity. A failed, cancelled or superseded build does not replace the
last successful plan. Explicit Stop retires the listener and owned temporary
output; application shutdown also releases operating-system listener ownership.
Browser-open/export completion cannot overwrite a replacement scene's status.

The sandbox server entitlement supports the loopback listener; there is no
network-client entitlement. This is not remote hosting or publication. Safari
is opened explicitly through its application identity, not a default-browser
assumption. Generated temporary output is owner-private and excluded from the
canonical package/history/recovery payload.

## Consequences and verification limits

The listener must remain owned while Safari uses its URLs. Closing the preview
controls alone is not Stop. Output remains an explicit revision snapshot;
Refresh compiles current edits rather than silently mixing live document data.
HTTP and real loopback lifecycle tests pass; native Safari, sandboxed-artifact,
full output parity, cancellation/adoption and user-visible acceptance remain
required before milestone completion. No release or distribution is authorized.
