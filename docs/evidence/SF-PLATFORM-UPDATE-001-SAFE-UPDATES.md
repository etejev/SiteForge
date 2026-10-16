# SF-PLATFORM-UPDATE-001 — Safe application-update foundation

Verification checkpoint (2026-10-08): repository/build gates and update model
coverage ran. Version parsing now canonicalizes equivalent trailing-zero forms,
and its exact regression passes. UI execution remains blocked externally; the
owner signing/update-install decision is unchanged.

## Scope

Bounded source evidence for `SF-1507-001`–`SF-1507-008`. This slice adds a
native Settings > Updates surface and a typed, UI-independent update service
boundary. It does not enable update installation or change project content.
The normative module remains Partial.

## Delivered source contract

- Stable and Preview are explicit app-local channels. The selected channel and
  automatic-check preference never enter canonical projects, history, recovery,
  or diagnostics.
- `UpdateFeedChecking` isolates metadata transport from Settings. The initial
  adapter accepts only public HTTPS GitHub Releases metadata, sends no
  credentials or project data, supports cancellation, and classifies offline,
  malformed, incompatible, policy-blocked, and transport outcomes.
- Monotonic version comparison rejects rollback. Request identity prevents a
  stale asynchronous result from replacing the current state.
- `UpdateInstallTrustPolicy` is a pure fail-closed boundary for owner policy,
  channel, monotonic version, HTTPS artifact, signature, integrity, bundle
  identity, and minimum-system compatibility. Metadata discovery never grants
  installation authority.
- Installation remains disabled in practice. No approved installer adapter,
  signing identity, notarization ownership, trusted feed, or key rotation
  policy exists. `OD-017` records that owner decision and
  `ADR-0019-policy-gated-update-service.md` records the reversible architecture.
- Settings uses a native vertical sidebar and exposes idle, checking,
  up-to-date, available, offline, cancelled, incompatible, failure, and
  policy-blocked recovery states with keyboard controls and accessibility
  announcements. Downloading/verifying/relaunch states are typed for the future
  trusted adapter but cannot be entered by the untrusted metadata adapter.
- Automatic scheduling is truthfully inactive while the feed is unconfigured.
  The UI stores only the local preference and does not imply a background task.
- Diagnostics contain only requirement ID, request ID, operation, and closed
  failure category. They exclude paths, release notes, project content,
  credentials, raw metadata, and artifact bytes.

## Evidence and verification status

- Production source: `SiteForge/SupportSettings.swift`
- Settings composition: `SiteForge/SiteForgeApp.swift`
- Source tests: `Tests/SiteForgeTests/SupportSettingsTests.swift`
- Architecture: `docs/architecture-decisions/ADR-0019-policy-gated-update-service.md`
- Owner decision: `docs/OPEN_DECISIONS.md` (`OD-017`)

The integrated universal application build succeeded. The test source covers
version ordering, request adoption, offline and rollback behavior, cancellation
neutrality, and the fail-closed trust boundary, but XCTest execution and
`./sf verify` were prohibited for this source-only pass. No update feed URL is
present in the bundle, no network update request occurs automatically, and no
install/download/relaunch behavior is claimed.

## Deferred acceptance

Owner approval of Developer ID/notarization ownership, signed feed and EdDSA
key custody/rotation, the trusted installer adapter (Sparkle 2 is the current
recommendation), authenticated artifact integrity, download staging,
verification, atomic replacement, relaunch, rollback/recovery, automatic
scheduling, migration, performance, complete accessibility/localization, and
release acceptance remain deferred. `SF-AUTHORING-110` remains paused.
