# ADR-0012 — Versioned content-addressed project resources

- Status: Accepted
- Date: 2026-07-19
- Owners: Product / Engineering
- Requirements: SF-0303-001, SF-0303-008, SF-1702-008, SF-2002-008

## Context

Package v1 intentionally caps its single control file at 8 MiB, each inline member at 4 MiB, and member count at 256. Relaxing those parser limits would turn resource scale into unbounded allocation and hashing risk. The specification's representative large fixture contains 500 real assets, so resource bytes cannot all be treated as inline package members or empty metadata records.

## Decision

The package remains the deterministic control plane. A sorted `resources/index-v1.json` member declares each resource's typed stable ID, basename, media type, byte count, and SHA-256 digest. Resource bytes live in a sibling `<project>.siteforge.resources-v1` content-addressed store. Each blob is immutable and named by its digest. Resource bytes are made durable before a package containing their index is committed; therefore an interrupted resource write can leave only an unreferenced blob and cannot invalidate the last committed package. A package commit remains the single adoption point.

Resource index v1 allows at most 2,000 resources, 16 MiB per resource, and 2 GiB total declared bytes. The package's existing 8 MiB/4 MiB/256 security limits do not change. Blob reads use no-follow descriptors, validate current-user single-link regular-file identity, restrictive permissions, and exact size before work, hash in 64 KiB chunks, and check cancellation between chunks. Stores are current-user-owned directories with no group/world access; newly written blobs use restrictive permissions, synchronize before publication, install exclusively, and synchronize the containing directory. Missing, corrupt, unsafe, oversized, duplicate, or unsupported resources fail with typed errors without changing canonical package bytes.

The sidecar is part of the logical project package. Native document operations must move or copy it with the control file once asset authoring is enabled; the current Milestone 0 shell has no asset-import UI and therefore does not yet expose such an operation. Recovery packages may reference the same immutable blobs because validation is content-addressed and read-only. Garbage collection is deliberately deferred and must never remove a blob reachable from a durable or recovery index.

## Alternatives considered

- Increasing package-v1 limits was rejected because it would weaken the bounded parser and still require whole-file allocation.
- Embedding hundreds of inline members was rejected because member-count and total-byte limits are security boundaries, not tuning values.
- A package-v2 directory bundle remains a viable future migration if Finder portability of one visible item outweighs single-file conditional replacement. The versioned index and digest blobs are reusable inside that representation.
- An app-global cache alone was rejected because it would make project resources machine-local rather than project-owned.

## Consequences

- The 500-asset fixture stores 16 MiB of non-empty PNG-like payloads while its deterministic control package remains below the unchanged parser limit.
- Index ordering, stable identities, integrity, versioning, cancellation, legacy no-index behavior, recovery round trips, and missing/corrupt blobs are directly testable.
- Resource validation does not accumulate all asset bytes in memory; peak validation buffering is one 64 KiB chunk plus metadata. A requested individual resource is bounded to 16 MiB.
- Until resource authoring ships, Finder move/copy integration for the logical two-item package remains an explicit downstream integration requirement. This bounded persistence layer does not claim that UI workflow.

## Reversibility

The resource index is versioned and self-describing. A future package-v2 directory or streaming container can reuse the descriptors and digest layout, preserve package-v1 reading, and migrate blobs without changing canonical document identity.

## Verification

`ProjectResourceTests` exercises a deterministic 500-asset fixture, stable index order, package save/reopen, one-resource lazy read, capacity/version/metadata rejection, missing and corrupt blobs, cooperative cancellation, restrictive directory/file/link metadata, recovery-package round trip, and unchanged control bytes after rejection. Repository verification headlessly type-checks the resource layer with the command/persistence slice.
