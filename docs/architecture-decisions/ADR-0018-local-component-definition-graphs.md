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

### Action-property integration addendum — source only, SF-AUTHORING-116/117

Schema v13 stores one stable Button/Link action binding on the definition and
one typed destination override on an instance. The default remains the
definition's canonical link target. Existing atomic commands and exact
inverses own metadata/override changes; drafts and current Inspector state
remain scene-local. Binding removal leaves retained missing-property conflicts;
reusing the same stable binding for another source while values survive is
rejected. This matches SF-AUTHORING-113's intent-preserving reconciliation.

Transfer maps action identities and destinations only through explicit copied
page/node or imported/equivalent definition mappings. Unsupported references
fail before mutation. Immutable expansion feeds canvas/Preview/static output;
virtual section availability is checked in the resolved graph, with no second
canonical store. Native Content fields share the existing Interactions editor.
Tests and runtime acceptance are deferred to the owner's Prompt-10 gate.

## Named fallback slots — SF-AUTHORING-118 source-only clarification

Schema v14 adds optional stable slot metadata on non-root definition containers.
The existing ordered childIDs are the only fallback content store. The native
Inspector edits the binding and routes users to canonical definition editing;
immutable expansion/detach strips slot metadata while retaining child identity.
Instances remain childless, and supplied-content state is not introduced.
OD-018 records the unresolved storage/cardinality decision before that broader
architecture can change. These source additions are unverified until Prompt 10.

## Optional local usage notes — SF-0907

Document schema 20 reserves one versioned plain-text property for the
canonical definition root. A missing property supplies the optional
default. Editing keeps the property identity and history stores the
existing property command and its inverse. Historical project schemas
reject the namespace. Clipboard v3 carries notes with definitions and
the v2 reader path supports transfers without notes. Root ownership,
property origin and text validation apply at both serialization boundaries.

Definition duplication and compatible import share the remapper in
TransformModel. Transfer owns envelope validation and resource reconciliation.
Their copied definitions own new graph/property identities. Structural
equivalence includes notes. Derived instance expansion removes the note
before rendering or detachment. OD-018 and OD-019 retain their existing
scope.

## Deferred

Source-only SF-AUTHORING-120 derives recovery findings from the original stable
override projection. Native confirmation compiles identified property removals
through the existing registry/kernel; original data restoration retains IDs.
Valid conflicts remain serializable in schema v15. Output/transfer fail closed;
no recovery store, tombstone, guessed retarget or type conversion is added.
OD-019 records the policy boundary before enabling broader migration. Tests
and runtime acceptance are deferred to Prompt 10.

Source-only SF-AUTHORING-119 adds optional schema-v15 flat group/order metadata
on existing definition source nodes, indexed by binding type. Typed exposed IDs
remain the stable references; groups are presentation labels, not content or
new entity graphs. Central property batches preserve exact history, while
projection/detach removes organization. No instance-child or slot ownership
decision changes; runtime verification remains deferred to Prompt 10.

Nested authoring, variants, supplied/nested slots, per-child overrides, remote libraries,
preview/export and release acceptance. Broader component modules remain Partial.

## Amendment — nested instances in definitions (OD-034, document schema 24)

- Status: Proposed — Code Forge batch 05, complete in source. Codex's
  integrity repair (2026-11-25, `docs/evidence/SF-QUICK-BATCH-INTEGRITY.md`)
  compiled it and ran one nested selector; the full gate is still pending.
  Becomes Implemented after Codex's verification. Approved by the owner as OD-034
  on 2026-11-25 (values on inner instances authored inside the outer
  definition allowed).
- Requirements: SF-0901-001–008, SF-0905-001/003/004, SF-0308-003/004.
- Supersedes, for schema 24 and later: "Nested instances in definitions are
  rejected in this first slice" above. Schemas 1–23 still reject an instance
  inside a definition.

**Graph.** A definition depends on every existing definition that one of its
own instances links to. `CanonicalComponentGraph` (headless, in the canonical
model) derives this graph from the document; nothing new is serialized. Every
valid document keeps it acyclic, keeps each chain within 8 definitions
(outermost included) and keeps each definition's fully expanded size within the
shared 20,000-object budget (`ResolvedGraphPolicy`). Violations are found in a
fixed order (cycle, depth, size; definitions in document order) and reported
with the definitions involved ("Card → Button → Card"); diagnostics carry the
category and identifiers only, never names. A link to a missing definition
stays representable and counts as one placeholder object.

**Resolution.** Expansion is one rule applied level by level: an inner
instance is placed at the frame its outer definition gives it, keeps the values
authored on it inside that definition, and its objects derive their identities
from the inner instance's own (already derived) identity, so every object is
unique and stable across reopen. The page budget counts nested instances fully
expanded before anything is allocated. Canvas, in-app Preview, Browser Preview
and export share this resolver; the recovery gate covers every instance that
output contains (page instances and instances inside definitions those pages
use). A cyclic graph held in memory expands one level only, so resolution
always terminates.

**Values.** An instance inside a definition owns values for its own
definition's exposed properties under the same validation, retention and
transition guards as a page instance. Values on an inner instance from the page
(nested override paths, SF-0905) stay out of scope.

**Authoring.** Insert Component works while a definition is open; the command
and its menu/panel availability share one check
(`ComponentCommandRegistry.nestingViolation`) and refuse an insertion that
breaks the graph with the chain in the message. Create Component keeps
instances inside the selection linked. Inside a definition an inner instance
takes, resets and keeps values and can be detached. Detach is one level:
inner instances stay linked. A use inside a definition counts as a use:
rename renames it, Remove Unused is unavailable, and Detach Uses and Delete
inlines it in the same transaction. Duplicate keeps inner links and values.
Every commit is still re-validated by the command kernel, so the graph rule
holds even for paths without their own message.

**Transfer.** Clipboard v5 carries nested definitions (older headers with
nesting are refused). A paste into another project imports inner definitions
before the definitions that contain them, relinks inner instances and their
values to the imported or reused definitions, and compares structural
identity in destination terms so a repeated paste reuses both. A destination
stored as an inner instance's action value is refused for cross-project paste
until action destinations inside definitions can be translated. Page
header/footer copy already carries the full definition closure.

**Editing inside an open definition.** Copy, cut, paste and duplicate work in
the definition being edited. Paste applies the same graph rule to every
instance it would add (`ClipboardTransferError.componentNesting`, category =
the rule's category) before any change. Content copied out of a definition is
ordinary content: exposed-property, slot, organization and notes metadata stay
in the definition; the current values travel.

**Navigation and presentation.** Edit Original on an inner instance while a
definition is open opens the inner definition in place; Return still goes back
to the page and selection from which definition editing began. The Components
panel lists "Used inside" and "Contains" for each definition and Details
counts "Used inside components". Menu, panel and Quick Open availability use
`CanonicalComponentGraph.insertionViolations(into:definitions:)`: one graph
pass decides, for every definition, whether inserting it would break a rule
(cycle when it already contains the target; depth when the longest chain down
to the target plus its own depth exceeds 8; size when a user of the target
would exceed the budget), and only those are rebuilt to report the exact
chain. A seeded randomized test compares it with a full rebuild for every
target/candidate pair. The answers are cached per document revision and open
definition.

**Consequences.** Every save writes schema 24 or later (25 adds slot
contents, below); builds before this change cannot open new saves. Older
schemas reopen unchanged.

## Amendment — instance-owned slot contents and slot rules (OD-018, document schema 25)

- Status: Proposed — Code Forge batch 06, complete in source. Codex's
  integrity repair (2026-11-25) compiled it, fixed slot-origin and
  coordinate-conversion defects and ran the slot selectors; the full gate is
  still pending. Approved by the owner as OD-018 on 2026-11-25;
  owner choices: Customize starts from a copy of the default contents; basic
  slot rules are included.
- Requirements: SF-0903-001–008, SF-0902-001/004, SF-0905-001/004/005,
  SF-0304-001/003/005, SF-0308-003/004/005.
- Supersedes, for schema 25 and later: "Instances remain childless, and
  supplied-content state is not introduced" (Named fallback slots, above).

**Storage.** Per slot, an instance stores `component.instance.v1.slot.<slot>`
= `supplied` or `empty`; absent means it shows the definition's default
contents. Supplied top-level items are the instance's own canonical children,
each marked `component.supplied.v1.slotID`, in `childIDs` order (one slot's
items contiguous). The definition never owns instance content. Supplied
geometry (base and responsive overrides) is slot-local: offset from the slot
container's origin, so contents move with the instance and follow definition
edits that move the slot. `CanonicalComponentSlot.validateNodes` enforces the
structure everywhere (document, clipboard). Older schemas reject all of it.

**Rules.** A slot may carry `component.exposedSlot.v1.allowedKinds` (canonical
comma list) and `.maximumRoots` (1…256). They bind the default contents and
every instance's supplied contents; a document breaking them is invalid, so
every editing path is guarded by the command kernel, and the slot-rule edit,
Add and Paste into Slot refuse with the specific rule beforehand.

**Resolution.** One projection rule (`ComponentGraphResolver.projectSlots`)
runs at every expansion level: for a marked slot the derived default subtree
is removed; supplied items are inserted under the derived slot container at
slot origin + slot-local offset. Page content keeps canonical identities
(selectable and editable on the canvas); contents stored in a definition get
derived identities. A slot the definition no longer exposes is a retained
conflict (`missingProperty`): kept, not drawn, output blocked; Reset removes
the contents with the marker in one transaction. Retargeting an instance that
keeps slot state is refused.

**Editing.** Customize copies the defaults as the copy shows them (its own
values applied) as new instance-owned nodes with per-breakpoint slot-local
geometry; empty defaults give the empty state. Make Empty and Use Default
replace one slot's state in one transaction (Use Default confirms when it
removes contents). Add Frame/Text and Paste into Slot append within the rules;
Move Up/Down reorders within a slot; top-level items are not dragged. Every
path that uses canvas coordinates converts at one boundary
(`CanonicalSlotGeometry`): insertion, component insertion, drag between
domains (canvas position kept), copy out (world, no membership), paste in
(slot-local), move/resize outline and snapping (world) while stored values
change by the delta. Detach keeps the copy's own contents in place of the
defaults; Detach Uses and Delete does the same per use. Cutting a slot's last
items leaves it empty.

**Transfer.** Clipboard v6 (oldest-sufficient versioning: 5 for box styles and
nesting, 6 for slot contents). Same-project paste keeps slot identities;
cross-project import maps slot identities (imported or reused definitions)
for markers and membership, and structural equivalence compares them in
destination terms. Page duplicate and header/footer copy use the shared graph
clone unchanged.

**Slot origin.** The slot origin is read from the same expanded, sized page
geometry the canvas paints (so copies of different sizes, and slots of
supplied inner instances, convert correctly). Changing coordinate domain adds
a responsive x/y override only where the breakpoint offsets differ.

**Diagnostics.** Slot edits are recorded with the component requirement IDs
plus SF-0903-008 (`ComponentEdit.isSlotEdit`); records carry sanitized
identifiers only.

**Consequences.** Every save writes schema 25 or later; builds before this
change cannot open new saves. Older schemas reopen unchanged.

**Out of scope.** Supplying a slot of an instance nested inside a definition
from the page; variants (OD-033); per-slot rules beyond type and count.
