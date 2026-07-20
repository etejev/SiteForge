# Open Decisions

## OD-001 — Minimum supported macOS release and reference hardware tiers

Status: Open

- Needed by: Milestone 0 exit and any release-level performance claim.
- Recommended default: support the current and previous two major macOS releases, with Apple silicon as the primary reference tier.
- Safe temporary assumption: the reversible local project continues to target macOS 14.0, while evidence is labeled with the exact OS, SDK, Xcode, architecture, and hardware on which it was gathered.
- Owner decision: final supported OS range and reference hardware tiers.
- Affected requirements: `SF-0201-007`, `SF-0301-007`, `SF-1505-007`, `SF-1602-007`, `SF-1605-007`, `SF-1902-007`, and `SF-2002-003`.

## OD-002 — Persistence store and project package representation

Status: Approved — 2026-07-19

- Decision: use the deterministic versioned single-file control container defined by ADR-0001, with bounded persisted history from ADR-0003, identity-bound atomic replacement from ADR-0007, and versioned content-addressed resource storage from ADR-0012.
- Reversibility: a later package version may adopt a directory or standard archive while retaining an explicit migration reader for package v1.
- Scale boundary: package-v1 control data remains limited to 8 MiB total and 4 MiB per member. Resource-index v1 retains those limits and bounds its immutable sidecar to 2,000 resources, 16 MiB per resource, and 2 GiB total; native move/copy integration remains downstream authoring work.
- Affected requirements: `SF-0301-001`, `SF-0301-003`, `SF-0301-004`, `SF-1702-001`, `SF-1702-004`, and `SF-1702-008`.

## OD-012 — Publisher identity and bundle identifier

Status: Open

- Needed by: first distributable build
- Recommended default: use `app.siteforge.SiteForge` locally and replace it before public distribution.
- Owner decision: publisher’s legal identity, public product name, and final reverse-DNS bundle identifier.
- Safe temporary assumption: local development identifier only; do not register or publish externally.
- Affected areas: signing, entitlements, update feed, saved preferences, crash identifiers.

## OD-013 — Initial distribution trust level

Status: Open

- Recommended default: GitHub-hosted unsigned alpha during development; Developer ID signing and notarization before public beta.
- Options: unsigned technical alpha, Developer ID direct distribution, Mac App Store, or both signed channels.
- Safe temporary assumption: local and GitHub prerelease artifacts only; no claim that Gatekeeper will trust them.

## OD-003 — Blank-project default page set

Status: Approved — 2026-07-19

- Needed by: before `SF-FOUNDATION-007` implementation begins.
- Recommended default: seed `Home` at `/` and `Not Found` as the designated error page at `/404`, in that navigator order, with no authored content beyond the minimum valid page roots.
- Alternatives: seed only `Home` for the smallest project; or add content-oriented pages such as `About` and `Contact`, which improves immediate discoverability but embeds product assumptions and increases deletion work for users who do not need them.
- Tradeoffs: `Home` plus `Not Found` exercises the specification's home/error-page model and provides a practical baseline without turning a blank project into a template; `Home` alone is simpler but defers the error-page path; a larger set is more instructive but less neutral.
- Affected requirements: `SF-0301-001`, `SF-0301-002`, `SF-0301-005`, `SF-0301-008`, `SF-0303-001`, `SF-0303-003`, `SF-0303-005`, `SF-0303-006`, and `SF-0303-008`.
- Decision deadline: before the first code or migration fixture for `SF-FOUNDATION-007`; changing the set after persisted projects exist requires an explicit migration/default-provenance policy.
- Approved decision: seed `Home` at `/`, followed by `Not Found` at `/404`; assign the home and not-found roles respectively; give each page only one minimum valid root node; add no sample text, sections, or template content.
- Implementation consequence: blank-project creation is a single clean baseline with explicit blank-default provenance. Template creation remains a separate provenance path. Schema-v1 empty/rootless documents receive deterministic minimum identities during compatibility migration.
