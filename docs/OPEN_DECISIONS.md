# Open Decisions

## OD-001 — Publisher identity and bundle identifier

Status: Open

- Needed by: first distributable build
- Recommended default: use `app.siteforge.SiteForge` locally and replace it before public distribution.
- Owner decision: publisher’s legal identity, public product name, and final reverse-DNS bundle identifier.
- Safe temporary assumption: local development identifier only; do not register or publish externally.
- Affected areas: signing, entitlements, update feed, saved preferences, crash identifiers.

## OD-002 — Initial distribution trust level

Status: Open

- Recommended default: GitHub-hosted unsigned alpha during development; Developer ID signing and notarization before public beta.
- Options: unsigned technical alpha, Developer ID direct distribution, Mac App Store, or both signed channels.
- Safe temporary assumption: local and GitHub prerelease artifacts only; no claim that Gatekeeper will trust them.

