# ADR-0009: Strict current-schema decoding and bounded revisions

- Status: Accepted
- Date: 2026-07-19
- Requirements: SF-0301-004, SF-0301-005, SF-0303-005, SF-0303-008, SF-0307-004, SF-1702-004, SF-1702-008, SF-1902-004, SF-1902-008

## Context

Canonical schema v2 added page routes, roles, provenance, creation kind, template identity, and mandatory page roots. Reusing compatibility defaults inside current-model `Codable` decoding made a damaged v2 payload indistinguishable from a supported schema-v1 migration. Separately, unchecked revision increment could trap at the unsigned integer boundary and leave no representable revision for a transaction result.

Compatibility also needs retained evidence independent of the current encoder. Tests assembled legacy payloads from current output, so a shared regression could change both the implementation and its alleged historical fixture.

## Decision

Current schema v2 decodes strictly. Every current canonical document and page field is required; an absent optional template identity must still be represented by an explicit JSON `null`. Missing fields, empty page lists, and rootless pages are rejected rather than repaired.

Schema v1 has its own private decoding DTO and the only supported compatibility adapter. It deterministically supplies migrated-legacy metadata, the approved Home/Not Found minimum for an empty legacy document, and one stable minimum root for a rootless legacy page. The adapter result must pass all current canonical validation before package adoption. Missing or incompatible persisted history remains isolated by ADR-0003.

`UInt64.max` is not a valid persisted document revision. A session at `UInt64.max - 1` cannot accept another transaction and returns a typed, non-mutating `revisionExhausted` error. Revision arithmetic is checked even after that precondition, preserving the last committed document and history if the boundary is reached.

Two tracked package-v1/schema-v1 fixtures are immutable compatibility inputs: one empty document and one rootless page. Their raw package SHA-256 checksums and provenance are recorded beside the Base64 fixtures. Tests decode those bytes, assert exact migrated identities and structure, establish a clean history baseline, and deterministically save and reopen the current representation.

## Consequences

- Corrupt current data cannot silently acquire legacy defaults.
- Every future schema migration requires a schema-specific DTO, explicit adapter, retained historical input, and current-model validation.
- The final representable committed revision is `UInt64.max - 1`; this version keeps such a document unchanged unless a future explicit revision-rebasing migration is approved.
- Fixture bytes do not depend on production encoders, while Base64 keeps them reviewable and portable in the repository.
