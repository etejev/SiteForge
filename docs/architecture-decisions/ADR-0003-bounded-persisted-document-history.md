# ADR-0003: Bounded persisted document history

- Status: Accepted
- Date: 2026-07-19
- Requirements: SF-0306-002, SF-0306-004, SF-0306-005, SF-0306-008; SF-0307-001, SF-0307-002, SF-0307-003, SF-0307-004, SF-0307-005, SF-0307-006, SF-0307-008

## Context

The canonical document and atomic project package are already authoritative. Undo and redo must survive save, reopen, autosave, and recovery without making a replay log a second source of document truth or allowing bad optional history to make a valid document unavailable.

## Decision

Package version 1 may contain an optional, integrity-declared `history.json` member. The member has its own `app.siteforge.persisted-history` format identifier and schema version. It records the canonical document identity and revision, a minimum undo boundary, and ordered undo and redo entries.

Each entry stores a stable transaction UUID, parent and result revisions, typed command name, registry-derived non-content label, RFC 3339 timestamp, affected typed stable identifiers, forward command, and supported inverse. Encoding uses sorted-key JSON. History is limited to 128 total entries and 512 KiB; deterministic retention removes the oldest reachable entries first and advances the minimum boundary.

History is loaded and validated off the main actor after the package and canonical document validate. Validation requires unique transaction identities, contiguous logical ordering, exact one-revision transactions, matching command type/label/affected identities, valid timestamps, matching document identity/revision, and forward/inverse round trips against the expected canonical state. Only a fully validated snapshot is installed into `DocumentSession`.

Missing legacy history and missing, corrupt, oversized, unsupported, reordered, duplicate, mismatched, or internally inconsistent history establish a clean baseline and emit a redacted compatibility diagnostic. They never reject or mutate the canonical document.

Recovery autosaves persist only history at or after the last durable document revision. Restoring a compatible recovery snapshot installs that explicit boundary. Incompatible recovery history restores the validated recovered document on a clean boundary. Discarding recovery retains the already loaded durable history. No undo or redo operation may cross those boundaries.

## Consequences

- Compatible undo and redo state survives atomic save, close, reopen, autosave, and recovery.
- New edits after reopen or recovery invalidate redo through the existing central transaction kernel.
- Older package readers preserve `history.json` as an opaque optional member.
- History can contain bounded command payloads required for inverses, but diagnostics contain only hashed document identity, counts, result, and failure category—never content or complete paths.
- Future command types require an explicit Codable representation and inverse validator before they can enter persisted history.

## Reversal

A later history schema may add checkpoints, coalescing, or migration metadata. Schema 1 remains independently isolatable, and the canonical document remains sufficient to open the project on a clean history baseline.
