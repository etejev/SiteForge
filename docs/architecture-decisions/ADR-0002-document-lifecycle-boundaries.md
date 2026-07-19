# ADR-0002: Document lifecycle and recovery boundaries

- Status: Accepted
- Date: 2026-07-19
- Requirements: SF-0301-002, SF-0301-004, SF-0301-005, SF-0301-006, SF-0301-008; SF-0306-001 through SF-0306-006 and SF-0306-008; SF-1504-001, SF-1504-004, SF-1504-006, SF-1504-008

## Decision

SiteForge uses a main-actor lifecycle coordinator for presentation state and an actor-isolated backend for package reads, writes, fingerprints, recovery artifacts, and diagnostics. The backend delegates every durable write to the atomic `ProjectPackageStore` approved by ADR-0001.

An open or revert validates the complete package before replacing the current canonical document. Durable saves compare a content fingerprint captured at the last successful open/save, so an external modification becomes an explicit conflict instead of an overwrite. Background saves consume immutable committed revisions and carry a monotonically increasing generation; work older than the newest requested generation cannot replace newer output.

Autosave writes a valid same-directory recovery package after a debounce boundary. It does not overwrite the last durable package. A recovery package is offered only when it has the same project identity, validates completely, and has a higher canonical revision than the durable package. Restore establishes a recovered, modified baseline; Discard removes the recovery artifact; Inspect Details exposes only non-content metadata.

## Consequences

- Failure, cancellation, stale access, malformed data, and conflict do not replace the committed in-memory document or the last valid durable package.
- Native window close requests are guarded while lifecycle state is modified or recovered.
- Recovery artifacts inherit the destination directory's access constraints and are never written to a global user folder by tests.
- Open and recovery delegate optional history restoration to the bounded, independently validated representation defined by ADR-0003. Missing or rejected history establishes a clean boundary without rejecting the canonical document.
