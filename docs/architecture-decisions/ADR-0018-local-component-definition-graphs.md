# ADR-0018: Local component definition graphs

- Status: Implemented — local and hosted milestone verification passed (Actions 34172995329)
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

## Exposed plain text (SF-AUTHORING-024)

Schema v8 adds one bounded property type. A definition Text node owns an
exposed property ID, label and `plain-text` type in `component.exposedText.v1`.
Its existing `content.text` is the sole default. Instance values are authored
strings under `component.instance.v1.text.<property-id>`, scoped by definition
identity. Renaming preserves the binding. Empty strings are authored values;
Reset removes overrides and reveals the current default. Labels are unique
within the definition, trimmed and bounded to 256 UTF-8 bytes; the limits are
64 exposed properties per definition and 64 KiB per text value.

Schemas 1–7 acquire no bindings or overrides. New namespaces under an older
header are rejected. V8 reuses ordered properties, IDs, origins and existing
package/history/recovery adapters rather than adding a second content store.

The existing component registry validates captured document/page/revision/
scene/renderer and exact single-selection identities before atomic edits.
Native Inspector drafts commit with Apply or Return; Cancel/Escape restores
the displayed committed value. Selection/revision replacement discards an
obsolete draft. Multiple selection is explicitly inspection-only in this slice.

Derived expansion resolves text before raster/accessibility preparation.
Virtual children remain noncanonical; detachment materializes effective text
without binding metadata. A complete-transaction guard rejects source/binding
removal or retargeting while a surviving instance's authored value depends on
it. Reset or explicit detach resolves that intent. Loaded unresolved values
remain inspectable; detach is rejected until restoration or explicit reset.
No destructive migration is inferred.

## Deferred

Nested authoring, variants, slots, per-child overrides, remote libraries,
preview/export and release acceptance. Broader component modules remain Partial.
