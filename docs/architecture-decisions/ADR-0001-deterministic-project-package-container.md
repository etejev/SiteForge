# ADR-0001 — Deterministic project-package container

- Status: Accepted
- Date: 2026-07-19
- Owners: Product / Engineering
- Requirements: SF-0301-001, SF-0301-003, SF-0301-004, SF-0301-008, SF-1702-001, SF-1702-004, SF-1702-008

## Context

The foundation needs a portable package that can preserve canonical document identity and opaque future members, reject archive-style path and duplicate attacks, and replace an existing local package atomically. Native document UI, autosave, recovery candidates, and persisted history are later slices.

## Decision drivers

- Deterministic bytes for identical canonical package state.
- Complete validation before an in-memory document can be replaced.
- Same-volume atomic replacement without partially updating a directory tree.
- Explicit package/schema compatibility and per-member integrity.
- Lossless preservation of unknown optional members.
- Bounded parsing that does not rely on an external archive library or service.

## Considered options

1. A directory package with separate files.
2. A ZIP archive.
3. A bounded SiteForge container containing length-prefixed named members.

## Decision

Package version 1 is a single regular file beginning with an eight-byte SiteForge magic value and a bounded sequence of length-prefixed, lexically ordered members. It requires `manifest.json` and `document.json`. The canonical sorted-key manifest declares package and schema versions, project identity, RFC 3339 creation and modification timestamps, reader compatibility minima, and each non-manifest member's role, length, and SHA-256 digest. Unknown members declared as optional or resource data remain opaque and are preserved byte-for-byte.

The actor-isolated store validates every member and the canonical document before returning a package. Writes create and synchronize a same-directory staging file, then use one atomic filesystem replacement. Symbolic-link sources, destinations, and destination ancestors are rejected.

## Consequences

### Positive

- Identical canonical package state produces identical bytes.
- Duplicate members, traversal names, corruption, incompatibility, and size abuse are detected before document adoption.
- A process interruption before replacement leaves the preceding package untouched.
- Future bounded members can round-trip through older readers when declared optional.

### Negative or risky

- The container is SiteForge-specific and needs dedicated tooling rather than generic ZIP inspection.
- Package and document migrations must retain explicit version handling.
- Version 1 limits packages to 8 MiB, individual members to 4 MiB, and 256 members; later resource scaling requires a versioned increase or external-resource design.

## Verification

Unit tests compare deterministic bytes and cover round trips, replacement, simulated interruption, opaque members, missing/corrupt members, compatibility, metadata, integrity, traversal, symbolic links, duplicates, size limits, unchanged state, diagnostics, and requirement mapping. `./sf verify` runs the package tests with the existing app and UI suites.

## Reversal

A later package version may adopt a standard archive or directory representation if inspection interoperability or resource scale outweighs single-file replacement. The versioned manifest and canonical document payload provide the migration boundary; package v1 remains readable through a dedicated decoder.
