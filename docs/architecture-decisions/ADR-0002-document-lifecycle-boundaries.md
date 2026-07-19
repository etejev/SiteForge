# ADR-0002: Document lifecycle and recovery boundaries

- Status: Accepted
- Date: 2026-07-19
- Requirements: SF-0301-002, SF-0301-004, SF-0301-005, SF-0301-006, SF-0301-008; SF-0306-001 through SF-0306-006 and SF-0306-008; SF-1504-001, SF-1504-003, SF-1504-004, SF-1504-006, SF-1504-008; SF-1603-004; SF-1604-004; SF-1702-004

## Decision

SiteForge uses a main-actor lifecycle coordinator for presentation state and an actor-isolated backend for package reads, writes, fingerprints, recovery artifacts, and diagnostics. The backend delegates every durable and recovery operation to the `ProjectPackageStore` approved by ADR-0001 and the identity-bound filesystem contract in ADR-0007.

An open or revert validates the complete package before replacing the current canonical document. Package bytes and the durable fingerprint are returned by one bounded descriptor snapshot. Durable saves conditionally replace only the exact previously validated digest, byte count, device, and inode, so an external modification becomes an explicit conflict instead of an overwrite. Background saves consume immutable committed revisions and carry a monotonically increasing generation; work older than the newest requested generation cannot replace newer output.

Autosave writes a valid recovery package below app-owned Application Support storage after a debounce boundary. It does not overwrite the last durable package. Recovery directories require current-user ownership and restrictive permissions; artifacts require matching project identity and validated file identity. A recovery package is offered only when it validates completely and has a higher canonical revision than the durable package. Restore establishes a recovered, modified baseline; Discard removes only the exact owned artifact and retains the candidate with a typed failure when deletion fails; Inspect Details exposes only non-content metadata.

## Consequences

- Failure, cancellation, stale access, malformed data, and conflict do not replace the committed in-memory document or the last valid durable package.
- Native window close requests are guarded while lifecycle state is modified or recovered.
- Recovery artifacts use app-owned storage rather than predictable sibling paths; tests inject repository-local storage and never use real user documents.
- Open and recovery delegate optional history restoration to the bounded, independently validated representation defined by ADR-0003. Missing or rejected history establishes a clean boundary without rejecting the canonical document.
