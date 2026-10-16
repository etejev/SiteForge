# ADR-0019 — Policy-gated application update service

Status: Accepted for bounded source implementation — 2026-10-08

## Context

`SF-1507-001`–`008` require deterministic channels, update verification,
recovery, accessibility, cancellation, and a fail-closed signed installation
boundary. Publisher identity, final bundle identifier, Developer ID ownership,
notarization, and production feed ownership remain open in OD-012, OD-013, and
OD-017. SiteForge must not invent those credentials or imply that an unsigned
development artifact is installable.

## Decision

SiteForge owns a typed, app-local `UpdateSettingsStore` and
`UpdateFeedChecking` boundary. A public unauthenticated HTTPS GitHub Releases
adapter may read release metadata for Stable and Preview channels. It sends no
project content, user path, credential, or persistent identifier. Deterministic
version ordering rejects malformed versions and downgrade candidates.

Installation is a separate trusted handoff. Until the owner approves publisher
identity, a signed/notarized artifact format, signature key ownership, and a
production feed, the handoff is deliberately policy-blocked. The current app
is never replaced and `/Applications` is never mutated.

Sparkle 2 is the preferred future handoff because it is mature, open source
(MIT), supports EdDSA-signed appcasts, background downloads, verification, and
relaunch. It is not added yet: doing so before key/feed ownership is resolved
would add supply-chain and maintenance surface without enabling a trustworthy
install. The service boundary permits a later Sparkle adapter without changing
Settings UI or project documents.

## Consequences

- Update preferences and transient requests remain app-local and never enter a
  SiteForge project, history, autosave, recovery, Preview, or export.
- Network work is asynchronous, cancellable, timeout-bounded, and request-ID
  gated; stale responses are neutral.
- Diagnostics contain requirement ID, bounded request ID, operation, and
  failure category only.
- Metadata checking can be enabled by an approved HTTPS feed URL; trusted
  download, signature/integrity verification, replacement, rollback recovery,
  signing, notarization, and release publication remain blocked.

## Rejected alternatives

1. Treat GitHub HTTPS or a checksum alone as installation trust. Rejected:
   neither establishes publisher identity or signed-update authenticity.
2. Bundle Sparkle and generate a development key now. Rejected: key ownership
   and feed policy are owner decisions, and generated private material must not
   enter the repository.
3. Let Settings call GitHub or Sparkle directly. Rejected: it couples UI to a
   provider and makes cancellation, stale rejection, diagnostics, and testing
   inconsistent.

## Requirements

`SF-1507-001` through `SF-1507-008`.
