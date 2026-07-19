# ADR-0004: Approved blank-project baseline and compatibility migration

- Status: Accepted
- Date: 2026-07-19
- Decision: OD-003
- Requirements: SF-0301-001, SF-0301-002, SF-0301-005, SF-0301-006, SF-0301-008; SF-0303-001, SF-0303-003, SF-0303-005, SF-0303-006, SF-0303-008

## Context

A canonical document may not have an invalid empty page list. New blank projects also need a useful but neutral route baseline that exercises the specified home and error-page semantics without becoming a content template. Existing schema-v1 packages can contain empty pages or pages without roots, so tightening the invariant requires a safe compatibility policy.

## Decision

A new blank project contains exactly two pages in navigator order: Home at `/` with the home role, then Not Found at `/404` with the not-found role. Each page owns one typed, stable frame root named `Root`, with no children or properties. No sample text, sections, or other template content is added.

Blank creation records explicit blank-default provenance and establishes the complete document at revision zero as one clean history baseline. Template creation uses a separate template provenance and typed template identity. Published routes are unique, and canonical validation rejects an empty page list, invalid routes, duplicate special roles, missing roots, or inconsistent creation provenance.

Canonical document schema v2 stores routes, roles, provenance, and creation kind. Supported schema-v1 payloads are decoded before adoption. Missing page metadata receives explicit migrated-legacy provenance; empty legacy documents receive Home and Not Found, and rootless legacy pages receive one minimum root. Migrated page/root identifiers are deterministically derived from existing document or page identity so repeated opens yield the same result. Persisted history that no longer matches the migrated canonical state is isolated by ADR-0003 and opens on a clean baseline.

## Consequences

- Save, reopen, autosave, and recovery preserve page and root identities through the existing package and lifecycle boundaries.
- Initial defaults cannot be undone as separate user edits; the first user mutation remains the first history entry.
- Older packages remain readable without accepting an invalid canonical document.
- Changing the approved default set later affects only newly created blank projects unless a separate owner-approved migration is defined.
