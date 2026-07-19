# ADR-0010: macOS file-access boundary

- Status: Accepted for the unsigned development and Release-candidate configurations
- Date: 2026-07-19
- Requirements: SF-1504-001 through SF-1504-008; SF-1603-004

## Decision

SiteForge owns external project access in one actor-isolated `FileAccessService` above the identity-bound package store from ADR-0007. Native panels authorize the initial user selection. Subsequent open, revert, save, and relocation operations resolve a versioned app-scoped security bookmark, repair stale bookmark data, acquire one balanced security scope, and keep `NSFileCoordinator` coordination active for the actual package operation. A per-document `NSFilePresenter` reports external change, move, and deletion without becoming a source of canonical content.

Bookmarks are machine-local access capabilities and live in restrictive app-owned Application Support storage (`0700` directory, `0600` file); they are deliberately not portable project members. The canonical project retains stable project/document identity, while the bookmark registry keys access by a one-way sanitized resource identifier. Diagnostics record intent, sanitized identifier, bookmark/repair state, duration, result, and failure category, never bookmark bytes, content, filenames, or complete paths.

The unsigned Release candidate enables App Sandbox, user-selected read/write access, and app-scoped bookmarks. Debug and hosted XCTest remain credential-free and unsandboxed so repository-local fixtures work without granting access to user files. Distribution signing remains disabled. Full distributed-build verification therefore requires the owner-approved publisher identity and trust configuration before release; the local implementation is not represented as final release verification.

## Consequences

- Panel-selected projects can be reopened after service recreation through real Foundation bookmark data; stale and relocated bookmarks are refreshed without replacing canonical content.
- Missing, denied, corrupt, stale-repair, and coordination failures are typed and actionable. Security-scope acquisition and release are balanced across success, failure, and cancellation paths.
- Package validation, conditional commit, ownership, metadata, no-follow, and atomic replacement remain the responsibility of ADR-0007 inside the coordinated access window.
- External file changes become explicit lifecycle conflict state. Moves update only the durable location and bookmark alias; deletes never discard the current in-memory project.
- Application-owned recovery artifacts bypass user-selected security scope but retain the stricter ownership and identity checks from ADR-0007.
- Supporting external assets beyond the bounded project-package lifecycle will reuse this service and must add their own canonical reference/transaction semantics before those broader SF-1504 acceptance criteria can be marked Verified.

## Alternatives considered

- Persisting bookmarks inside portable project packages was rejected because bookmark data is machine-local capability state and would leak location/access metadata across copies.
- Scattering `startAccessingSecurityScopedResource()` calls through lifecycle and package code was rejected because balanced lifetime, stale repair, diagnostics, and test injection would not have one enforceable owner.
- Coordinating only a preliminary path check was rejected because it would leave the actual asynchronous package operation outside macOS file coordination.
- Enabling sandbox entitlements for Debug/XCTest was rejected for this bounded correction because it would require interactive grants for repository-local fixtures and weaken deterministic local verification. Release-candidate settings remain inspectable, unsigned, and reversible.
