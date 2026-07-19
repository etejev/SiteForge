# ADR-0008 — Lifecycle epoch and typed operation intent

- Status: Accepted
- Date: 2026-07-19
- Owners: Product / Engineering
- Requirements: SF-0301-002, SF-0301-004, SF-0301-005; SF-0306-003, SF-0306-004, SF-0306-005; SF-1504-004; SF-1902-004
- Findings: M0-P1-01, M0-P1-02, related autosave-coalescing portion of M0-P2-04

## Context

ADR-0002 separated main-actor lifecycle presentation from actor-isolated persistence, and ADR-0007 established an identity-bound conditional filesystem commit. The lifecycle coordinator still needed one identity spanning those layers. A revision or destination alone cannot distinguish an old operation from a newly adopted document that happens to use the same values, and a monotonic backend generation cannot express whether work is a durable Save, Save As, recovery autosave, or document transition.

Without a lifecycle-wide boundary, a late success or failure could reattach metadata or presentation to another document. Pending or executing autosave could also race explicit Save and create misleading conflicts or revision order.

## Decision drivers

- No result from a superseded document lifecycle may mutate canonical or presentation state.
- Operation identity must be sufficient for redacted diagnosis without including content or complete local paths.
- Explicit Save must have deterministic precedence over recovery autosave.
- Editing during Save must not discard the newer edit or misstate what reached durable storage.
- Race evidence must use controllable scheduling seams rather than wall-clock sleeps.
- The identity-bound filesystem guarantees in ADR-0007 must remain the final byte-level commit boundary.

## Decision

The main-actor lifecycle coordinator owns a monotonically advancing typed `LifecycleEpoch`. Every asynchronous operation receives an immutable `LifecycleOperationIdentity` containing:

- a unique operation ID;
- lifecycle epoch;
- canonical document ID;
- project ID;
- captured document revision;
- a destination kind and sanitized destination token; and
- a typed intent: New, Open, Save, Save As, Revert, Autosave, Restore, Discard Recovery, Close, or Discover Recovery.

New, Open, Revert, Restore, Close, and successful incoming-document adoption advance the epoch. The boundary invalidates active operation IDs and cancels or drains prior read, manual-save, autosave, and recovery work as appropriate. Every success, failure, and cancellation path must match its full identity and active-operation registration before it can update the document, project metadata, URL, fingerprint, history, recovery candidate, failure state, or lifecycle phase. A stale or cancelled result is state-neutral.

### Save and autosave ordering

Manual Save and Save As first cancel and drain pending or executing autosave work, then serialize with any other explicit save. They capture an immutable document revision, history snapshot, project package, destination identity, and expected durable fingerprint. The backend passes that request to ADR-0007's conditional commit without substituting a global generation rule.

Autosave uses an injected cancellation-aware debouncer. After the debounce boundary it waits for active explicit Save work and revalidates its operation identity before preparation and before filesystem commit. Autosave writes only recovery storage and never changes the durable URL or fingerprint.

If editing occurs while Save is executing, the Save may finish for its captured revision. The resulting durable URL, project metadata, and fingerprint describe that captured revision, while the active newer canonical revision remains modified and receives a recovery autosave. A destructive transition waiting on Save does not silently proceed when newer edits remain.

### Diagnostics and testing seams

Lifecycle diagnostics record intent, revision, destination kind, and hashed operation/epoch/document/project/destination tokens. They exclude document content and complete paths. Tests inject an autosave debouncer, clock, backend observer, and actor barriers to control every relevant boundary and assert exact state, disk bytes, write counts, and revision order without scheduling sleeps.

## Alternatives considered

1. **Backend-wide monotonic generation only.** Rejected because it does not bind document/project adoption, destination identity, or semantic intent, and it can order unrelated lifecycle work accidentally.
2. **Revision and URL checks at completion.** Rejected because values may be reused after adoption and do not cover project identity, recovery work, or failure/UI state.
3. **Cancellation only.** Rejected because cancellation is cooperative and backend/filesystem work may complete after cancellation is requested; every completion still needs identity validation.
4. **Allow explicit Save and autosave to race through conditional commits.** Rejected because the recovery writer can cause false ordering/conflict behavior and makes durable intent nondeterministic.
5. **Block editing during Save.** Rejected because it harms responsiveness and is unnecessary when the captured durable revision and newer active revision are represented explicitly.

## Consequences

### Positive

- A superseded lifecycle result cannot attach to another document or UI phase.
- Explicit Save has deterministic precedence without weakening recovery autosave.
- Edits made during Save remain active, visibly modified, and recoverable.
- Read, save, autosave, recovery, and transition diagnostics have one redacted correlation model.
- Autosave coalescing and lifecycle races are reproducible without wall-clock sleeps.

### Negative or risky

- Lifecycle operations must carry and validate a larger identity at every completion boundary.
- Document adoption may advance the epoch more than once during a user-visible operation; callers must treat the epoch as an opaque invalidation token, not a revision number.
- Cancellation cannot undo a filesystem commit that already completed. ADR-0007 guarantees conditional external-byte preservation, while the lifecycle identity prevents stale state adoption.
- Future lifecycle intents must be added explicitly and tested at document-adoption boundaries.

## Verification

`DocumentLifecycleRaceTests` contains eleven deterministic tests. Save and executing autosave are crossed with New, Open, Revert, Restore, and Close; pending and executing autosave are followed immediately by Save; Save As is crossed with a pending autosave; edit-during-Save proves the durable/active revision split; burst coalescing proves exact write count and ordering; and stale success, stale failure, and cancellation at two backend boundaries prove state neutrality. Assertions cover canonical document, project identity, URL, fingerprint, history, recovery candidate, lifecycle phase, durable/external bytes, operation intent, and redacted diagnostics. `./sf verify` passes with 115 unit tests and 14 UI tests.

## Reversal

The public lifecycle behavior depends on the identity contract, not the current task/debouncer implementation. A later structured-concurrency coordinator or operation graph may replace the internal task bookkeeping if it retains typed intent, full identity matching, explicit Save precedence, edit-during-Save semantics, ADR-0007's conditional commit, and the deterministic adversarial tests.
