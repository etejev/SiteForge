# ADR-0018: Local component definition graphs

- Status: Implemented — local milestone verification passed
- Requirements: SF-0901-001–005, SF-0905-003–005

## Implemented boundary

Reuse the canonical ordered node graph and existing property transactions
for definition editing. A definition is a non-route graph with stable identity,
not a website page and not a serialized expansion of its instances. Instances
reference that identity and retain independent placement and responsive
geometry/visibility. The resolved graph is immutable, revision-scoped derived
data; virtual child identities include both definition-node and instance
identity and cannot become canonical mutation targets.

The schema-v7 storage adapter uses an explicit component-definition graph role
in the existing graph collection, excluded from website routes and the Pages
navigator. A schema boundary must reject this role in historical payloads;
legacy packages acquire no definitions. Definition editing reuses the same
session, graph commands and history rather than introducing a second editable
document. Historical schemas reject this role and the component reference
namespace instead of silently discarding them. Existing schema-one/four/five
fixtures retain their identities and acquire no definitions. Detailed focused
evidence is in `../evidence/SF-AUTHORING-022-LOCAL-COMPONENTS.md`; the final gate
is recorded separately and must not be inferred from this decision.

Creation and detachment must preserve appearance, ordering and resource/link
intent with exact inverses. Missing references remain representable. Nested
instances in definitions are rejected in this first slice, preventing cycles.
Delete with live uses requires explicit detach-all confirmation or cancellation.

Derived expansion and the renderer share the existing 20,000-node execution
budget, checked before expanded allocation. Neither this budget nor expanded
children are serialized. New instance placement uses the visible parent/artboard
intersection; it does not rewrite definition or responsive geometry. Detachment
materializes each supported breakpoint's child geometry with stable root identity
and exact history inverses.

## Deferred

Nested authoring, variants, slots, per-child overrides, remote libraries,
preview/export and release acceptance. Broader component modules remain Partial.
