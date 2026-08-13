# Open Decisions

## OD-015 — Initial structural-element defaults

Status: Approved — 2026-08-12

- Needed by: the first persisted Section, Stack, and Grid authoring slice.
- Context: `SF-0502-001` and `SF-0503-001` require explicit, versioned
  defaults that distinguish defaulted from authored values. The specification
  defines the required semantics but does not select numerical starting values
  for a Section's padding/size, a Stack's gap/padding/alignment, or a Grid's
  columns/gap/padding. These values would become canonical package data,
  migration behavior, layout results, undo/redo results, and exported-layout
  semantics, so they must not be silently invented in implementation.
- Recommended default: Section — 960 × 320 points, 48-point padding, vertical
  structural container; Stack — vertical axis, 24-point gap, 24-point padding,
  start alignment; Grid — two equal columns, 24-point gap, 24-point padding,
  row-major placement. All values would be stored as `.defaulted`, with no
  property editor in this bounded slice.
- Alternatives: compact defaults (24-point Section padding and 16-point
  Stack/Grid spacing) for denser composition; or defer concrete geometry until
  an inspector-property milestone, leaving these catalogue entries unavailable.
- Tradeoffs: the recommended values create calm, legible first results and are
  easy to explain, but they establish persistent product behavior before a
  broader layout-property editor exists. Compact values reduce whitespace but
  offer less visual separation. Deferral avoids a decision but prevents the
  requested real insertion capability.
- Approved decision: adopt the recommended defaults as the canonical v1
  structural-element baseline. Schema v4 persists them with `.defaulted`
  provenance; supported schema-v3 documents decode unchanged and re-save as
  v4 because they contain no Section, Stack, or Grid nodes. Any later schema
  reader must retain these exact values when such a node is present. ADR-0015
  records the resulting persistent boundary.
- Affected requirements: bounded evidence for `SF-0405-001`–`008`,
  `SF-0501-001`–`008`, `SF-0502-001`–`008`, and `SF-0503-001`–`008`.
- Decision deadline: before canonical schema or package migration work begins
  for `SF-AUTHORING-010`.

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

## OD-014 — Trusted app-owned artifact retention and reclamation

Status: Open — non-blocking safety boundary

- Needed by: before any automatic cleanup policy for retained package staging/quarantine files or recovery tombstones.
- Context: the identity-bound filesystem intentionally does not reverse a completed swap, reopen an ambiguous displaced name, or unlink a name after a raced replacement. Recovery Discard performs logical retirement through an owned tombstone. These choices preserve unknown external data at the tested seams but can leave owned artifacts for later maintenance.
- Recommended default: retain these artifacts under verified app-owned directories; expose no automatic deletion beyond the identity-bound retirement path until a maintenance operation can prove an owned trusted root and define user-visible recovery semantics.
- Alternatives: bounded age/size reclamation under a verified app-owned root; explicit user-initiated cleanup with diagnostics; or a future platform primitive that offers expected-inode conditional unlink/rename.
- Tradeoffs: automatic reclamation limits disk use but risks deleting an artifact after ownership has changed; conservative retention preserves safety but needs a size/visibility policy.
- Safe temporary assumption: logical retirement, typed retry, and retained staging/quarantine artifacts only. Do not claim universal protection against a hostile same-UID process racing the final macOS rename/unlink syscall.
- Affected requirements: `SF-0301-004`, `SF-0301-005`, `SF-0306-003`, `SF-0306-004`, `SF-1504-003`, `SF-1504-004`, `SF-1603-004`, `SF-1604-004`, and `SF-1702-004`.

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

## OD-004 — Layout engine implementation versus embedding an existing standards engine

Status: Approved — 2026-07-21

- Decision: use a SiteForge-owned, typed, deterministic, UI-independent layout engine for canonical authoring computation. Generate HTML/CSS through an adapter and use WebKit only as an isolated preview/export runtime and standards oracle.
- Evidence: the optimized runway subset produced deterministic results at 100 and 10,000 nodes, rejected invalid, unsupported, cancelled, and stale work, and matched exported WebKit geometry on the retained responsive and complete fixtures. Methodology and raw measurements are retained in `docs/evidence/authoring-engine-runway/`.
- Reversibility: the engine and export adapter are protocol boundaries. A versioned embedded alternative may replace or supplement a subset only with equivalent deterministic migration, cancellation, identity, accessibility, and parity evidence.
- Revisit triggers: unsupported text shaping, grid, intrinsic sizing, or international-layout behavior cannot meet the declared parity tolerance; an owner-approved performance budget is missed; or maintaining the owned subset exceeds the cost of a bounded embedded alternative.
- Architecture record: ADR-0013.
- Affected requirements: `SF-0501-001` through `SF-0501-008`, `SF-1901-001` through `SF-1901-008`, and `SF-1903-001` through `SF-1903-008`.

## OD-011 — Canvas technology split among SwiftUI, AppKit, Core Animation, and Metal

Status: Approved — 2026-07-21

- Decision: retain SwiftUI for workspace chrome; use a dedicated AppKit viewport for native input, focus, accessibility, coordinate ownership, hit testing, and invalidation; use bounded Core Animation tiles/surfaces and overlay layers for composition. Do not require a layer per object. Keep Metal behind an optional renderer boundary rather than adopting it initially.
- Evidence: the retained 10,000-object run showed fast AppKit dirty-region and Core Animation incremental work, while every full-render alternative crossed or approached the reference frame interval and SwiftUI Canvas rerasterized after a one-object change. The Metal probe intentionally measured only buffer/command overhead and is not treated as end-to-end renderer proof.
- Reversibility: typed immutable scene snapshots isolate the viewport, renderer, overlays, hit testing, and accessibility. Metal can replace tile rasterization without changing canonical or interaction semantics when production evidence justifies it.
- Revisit triggers: production display-link traces miss an owner-approved budget; tile/cache memory exceeds its bound; required effects cannot be expressed efficiently; or framework improvements provide equivalent incremental, input, accessibility, material, and stress evidence.
- Architecture record: ADR-0014.
- Affected requirements: `SF-0401-001` through `SF-0401-008`, `SF-0407-001` through `SF-0407-008`, `SF-1901-001` through `SF-1901-008`, and `SF-1903-001` through `SF-1903-008`.
