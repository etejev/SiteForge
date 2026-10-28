# ADR-0024 — Crash-qualified automatic recovery offers

Status: Implemented source; focused and native acceptance tracked separately.

Requirements: bounded SF-0306-003/004/005/006 and SF-0204-004/006.

## Context

A valid recovery package proves recoverable content and ownership, not that
SiteForge crashed. Legacy snapshots from clean sessions must not be presented
automatically as crash evidence. They must remain available to the owner.

## Decision

New recovery writes atomically include a versioned optional session identifier
alongside the existing canonical document/history. The process owns a private
fixed-size session marker in the same validated recovery directory and holds an
exclusive advisory lock. The operating system releases that lock on process
death. AppKit's actual termination notification marks all already-open markers
clean synchronously; no asynchronous termination task is relied upon.

Automatic Welcome discovery still fully validates the package and project-bound
filename, then requires a recognized running marker with no live lock owner.
Live sessions, clean sessions, missing/malformed evidence and legacy packages do
not qualify automatically. The explicit Recovery History action uses existing
validated discovery and restore/discard paths. Qualification never grants
mutation or deletion rights; exact artifact fingerprints and lifecycle epochs
continue to control adoption and retirement.

Session evidence is not document content or history. It is replaced on the next
recovery write and removed from durable saves. Markers contain only a versioned
state byte and random session identity in the filename, not project names,
paths, user content or process command lines. Descriptor-bound no-follow reads,
private owner/mode, single-link regular files and absence of extended ACLs are
required. No old recovery or session file is automatically deleted.

## Consequences and limits

This is a recoverability signal, not forensic proof of a particular crash cause.
Forced termination and power loss qualify just like a crash. Unverifiable
evidence remains manual-only and never makes the package disposable. Markers
remain tiny historical evidence; bounded pruning/retention UI is not introduced
in this slice. The process bounds open marker descriptors to 256 distinct
recovery directories. Native clean-quit/crash acceptance requires an unlocked
session and is not implied by source compilation or model tests.

## Alternatives

PID inspection is vulnerable to reuse and runner restrictions. A timestamp or
the mere presence of a recovery file misclassifies clean sessions. Deleting old
snapshots would lose intent. None of those alternatives is used.
