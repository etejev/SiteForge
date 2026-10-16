# Open Decisions

## OD-021 — Recover native XCTest automation availability

Status: Resolved owner action — 2026-10-15. No product requirement waiver.
The owner quit/reopened Xcode and confirmed ready. The four exact native
journeys subsequently passed 4/4 (399.845 seconds), with twelve original-size
captures reviewed. No privacy reset or shared-service termination was used.
The following records the historical failure and recovery recommendation.

- Context: the latest complete attempt passed 636 model tests and 93 UI
  journeys, recorded four concrete UI failures, then its next runner timed out
  enabling automation mode. After bounded corrections compiled, both the normal
  focused route and supported already-built route failed at the same 60-second
  initialization handshake before executing any test. Console inspection shows
  an unlocked logged-in session; no SiteForge test/app/xcodebuild process remains.
- Recommended default: owner saves any Xcode work, quits Xcode normally and
  reopens it with the Mac unlocked, then resumes the four exact focused journeys.
  This is a recovery attempt, not an assurance that restarting Xcode fixes macOS.
- Alternative: owner performs a normal system restart after saving work if the
  native Xcode route remains unavailable. Do not reset TCC or broaden permissions.
- Tradeoff: temporary interruption versus preserving system privacy and other
  applications; the agent will not terminate shared testmanagerd/WindowServer.
- Affected requirements: SF-0201-008, SF-0407-006/008, SF-0602-006/008,
  SF-0701-006/008 and SF-1201-006/008; SF-PRODUCT-UI-010 acceptance/delivery.
- Deadline: before the remaining native acceptance and authoritative full gate.
- Safe temporary assumption: retain all edits and original recovery; no commit,
  push or completion claim until focused native checks and final verification pass.

## OD-020 — Dismiss outstanding macOS test-host Documents prompt

Status: Resolved owner action — 2026-10-15.
The owner answered the original permission request with "done". The subsequent
native recording confirms that the system permission prompt is absent. No
agent changed a privacy permission; no product-policy change was requested.

- Context: the isolated test host's old raw checkout fixture read triggered a
  macOS Documents permission prompt. A process sample and TCC logs confirm the
  request. After fixtures moved into test resources/application-owned temporary
  storage, the focused model checks pass without that access. The later native
  recovery recording still shows the outstanding system prompt above the real
  reset confirmation, preventing its accessibility query. Computer Use refuses
  access to UserNotificationCenter for safety; no workaround is authorized.
- Recommended default: the owner dismisses the outstanding prompt with
  **Don't Allow**. The corrected fixture paths do not need Documents permission.
- Alternative: owner explicitly allows Documents access for that local test
  host; this grants broader access than the fixture checks now require.
- Tradeoff: denial keeps the test host narrowly scoped; allowing avoids that
  individual prompt but is unnecessary for the corrected test architecture.
- Affected requirements: focused SF-0701-006 and SF-0308-006 acceptance;
  SF-PRODUCT-UI-010 local verification/delivery. No requirement is waived.
- Deadline: before resuming the recovery UI journey and final accumulated gate.
- Safe temporary assumption: preserve all changes and genuine owner recovery;
  no commit, installation replacement or completion claim. All focused test
  runners exited; the owner's regular installed app remains untouched.

## OD-019 — Explicit migration of retained component override conflicts

Status: Open — 2026-10-13

- Needed by: future retargeting/conversion beyond SF-AUTHORING-120 recovery.
- Context: SF-0902-004/005 and SF-0905-003/004/005 require stable or migrated
  intent but do not define candidate eligibility, value conversion, source
  tombstones or collision resolution. Current override keys retain definition
  and typed property IDs, not a deleted binding's original source/label.
  Guessing a new source violates SF-AUTHORING-113's transition guards.
- Recommended default: retain reset/restore-original/navigation only until the
  owner approves explicit same-type target selection, collision policy and
  preview/confirmation. Reject cross-type conversion; never select by label.
- Alternatives: add versioned source tombstones for original-binding restore
  (broader persistence/transfer obligations), or approve authored mappings with
  explicit typed conversions (requires individual conversion specifications).
- Tradeoffs: conservative recovery preserves all intent and exact history but
  requires original project/history to restore a removed binding. Migration
  could improve convenience but introduces ambiguity and loss/privacy risks.
- Affected requirements: SF-0902-004/005, SF-0905-003/004/005, SF-0308-004/008.
- Decision deadline: before enabling any retarget/convert control or serialized
  migration metadata. No decision blocks the independent safe recovery slice.
- Safe temporary assumption: canonical conflicts remain serializable; explicit
  confirmed reset removes only identified authored values. Original stable IDs
  can be restored through existing Undo or original package/definition data.
  Available definitions/sources are inspectable; no automatic reassignment.

## OD-018 — Canonical ownership of supplied component slot content

Status: Open — 2026-10-13

- Needed by: supplied-content authoring in `SF-AUTHORING-118` under
  `SF-0902`, `SF-0903` and `SF-0905`.
- Context: §9.3 requires ordered projected content, constraints, fallback and
  stable identity but does not choose storage ownership or slot cardinality.
  ADR-0018 and the shipped canonical rules explicitly require linked instances
  to be childless; ordinary children have exactly one ordered canonical parent.
  Enabling instance children changes insertion, history, transfer, selection,
  layout and rendering boundaries and is a consequential architecture change.
- Recommended default: approve instance-owned canonical child subtrees with
  explicit stable slot membership and ordered roots, reusing the document graph
  and command kernel. Supplying content replaces only that slot's fallback in
  derived projection; the definition never acquires instance-owned nodes.
  Slot removal must retain supplied content as a recoverable conflict until an
  explicit migration/reset/detach transaction. Approve zero-or-more supplied
  roots and an authored empty state separately from inheritance.
- Alternatives: separate instance-content graphs (keeps instances childless but
  adds graph-role/persistence/navigation complexity); or retain fallback-only
  slots (safe and useful, but cannot complete supplied-content requirements).
  A serialized secondary node store in a property is not recommended because
  it duplicates the canonical graph and mutation rules.
- Tradeoffs: canonical children reuse existing ownership/history but require
  explicit projection-aware eligibility and conflict repair. Separate graphs
  isolate storage but broaden lifecycle and transfer integration.
- Affected requirements: `SF-0304-001/003/005`, `SF-0902-001`–`008`,
  `SF-0903-001`–`008`, `SF-0905-001`–`008`, and `SF-0308-003/004/005`.
- Decision deadline: before supplied-content mutations or any migration that
  makes linked instances canonical parents.
- Safe temporary assumption: SF-AUTHORING-118 exposes non-root existing
  Frame/Section/Stack/Grid definition containers as named fallback slots.
  Their current ordered childIDs remain the sole content/ownership source;
  instances inherit and inspect/edit the definition fallback. Nested slots
  and supplied-content storage are unavailable, with no fake controls or
  silent conversion. Older packages remain readable.

## OD-016 — Initial starter-template catalogue and canonical content

Status: Approved — 2026-10-05

- Needed by: the first production template/onboarding slice under `SF-0204`.
- Context: the specification requires choosing a template, editable/removable
  examples, stable template identity, migration, Preview/output behavior, and
  resettable learning state, but it does not define the initial template set or
  authorize SiteForge to invent branded page copy/assets. Those choices become
  persistent product content and cannot be inferred from competitor products.
- Approved decision: retain **Blank Site** as the neutral existing creation
  path and add exactly one local **Starter Site** template. The Starter Site
  contains exactly two ordinary pages, **Home** and **About**, with semantic
  Header/Main/Footer structure, system typography, no remote assets, explicit
  template provenance, and entirely editable/removable neutral generic copy.
  It does not present a Not Found/404 page as starter content. Existing internal
  missing-route/404 handling remains separate where the specification requires
  it.
- Alternatives: ship only Blank Site (simpler but does not satisfy “choose a
  template”); approve several vertical templates (more useful but creates a
  larger content, localization, migration, and visual-review commitment); or
  defer the entire template catalogue while keeping New Site direct.
- Tradeoffs: one curated local starter proves the canonical workflow with low
  maintenance and no licensing/network dependency, but its content establishes
  visible product direction. Multiple templates improve discovery but broaden
  quality and accessibility obligations immediately.
- Affected requirements: `SF-0204-001`–`SF-0204-008`, supporting
  `SF-0301-001/002/005`, `SF-1201-003`, and `SF-1203-002/003/004`.
- Decision deadline: before SF-AUTHORING-106 writes any canonical template
  fixture or migration.
- Implementation consequence: SF-AUTHORING-106 is unblocked. Keep New Site's
  Blank Site option unchanged and do not add branded identity, licensed
  content, remote media, or additional template/page choices.

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

## OD-017 — Signed update feed and installer ownership

Status: Open — blocks trusted update installation, not metadata inspection

- Needed by: enabling the SF-1507 installer handoff or publishing a production update feed.
- Recommended default: Developer ID signing and notarization with Sparkle 2,
  an EdDSA-signed appcast derived from owner-controlled GitHub Releases, stable
  and preview feeds, monotonic upgrades, and a retained last-known-good app.
- Owner decision: final publisher/bundle identity; Developer ID team; who owns
  and rotates the private update-signing key; exact GitHub repository/feed URL;
  stable/preview promotion policy; minimum supported macOS; rollback and
  emergency-revocation policy.
- Alternatives: Mac App Store delivery (store-owned update trust); a fully
  SiteForge-owned signed downloader/installer (substantially larger security
  surface); metadata-only checking with manual download (current safe state).
- Tradeoffs: Sparkle is mature and MIT-licensed but adds a binary/package
  dependency and key/appcast maintenance. A custom installer avoids that
  dependency but creates a security-critical long-term maintenance burden.
- Safe temporary assumption: public HTTPS metadata may be inspected without
  authentication; download/install remains policy-blocked and the running app
  is never replaced.
- Decision deadline: before any public beta or enabling the Install action.
- Affected requirements: `SF-1507-001`–`SF-1507-008`, plus OD-001, OD-012, and OD-013.

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
