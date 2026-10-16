# ADR-0020 — Opt-in connected page flow and page-owned navigation

Status: Owner-approved behavior; SOURCE IMPLEMENTED, verification deferred — 2026-10-13.
Requirements: bounded SF-0501, SF-0502-003/005, SF-0504-003/004,
SF-0505-003, SF-0304-003/005, SF-0806 and SF-1201-003/SF-1203-003/006.

Use existing Section nodes and canonical childIDs with optional schema-v16
`page.flow.v1.role` (Header/body/Footer). Existing authored geometry is not
rewritten on open; conversion adds the role explicitly and has an exact inverse.
The shared structural resolver derives full allocated width and sequential
positions from parent ownership, padding, responsive height and visibility.
Header/Footer anchor the managed sibling list. Free Frames are not flow members.
New page Header/Footer are unique root-owned anchors, not component templates.

Legacy navigation reuses direct child Link nodes and their stable PageID targets/labels.
`page.navigation.v1.member`, hamburger and alignment are closed optional metadata,
not another link catalogue. Defaulted labels are derived from current page names
in immutable projections; authored labels and missing targets are retained.
Mobile hamburger mode shares the existing below-600-point range. Native Preview
uses a real AppKit-backed SwiftUI Menu; static output uses native details/summary
plus a fixed external Escape/focus handler. Visitor state never enters history.

One identity-gated registry compiles insertion/conversion/reorder/settings/link
edits into existing property/node commands. Pointer reorder/height drafts live
only in the scene and use the same registry; markers never enter authored pixels.
Shared renderer/selection/hit/accessibility geometry consumes the resolved frames.

No duplicate flow tree, positioning store, resource store or output writer is
introduced. Components and isolated clipboard transfer reject unsupported flow
ownership before mutation. Complete-page duplication retains metadata and uses
existing stable reference mapping. Static nested containing layouts not yet
represented correctly produce a blocking finding rather than misleading HTML.

Deferred: sticky/fixed roles, arbitrary navigation breakpoints, external nav
destinations, component page-flow authoring, unsupported containing-layout static
parity, browser/runtime/visual certification and release acceptance. Prompt 10
owns compilation, tests, original-resolution review and DOCX synchronization.

## Prompt-9 implementation integration

SF-AUTHORING-122 shares typed container policy and resolved snapshots between
native layout and connected output. Nested Frame/Section/Stack/Grid output now
retains authored ownership instead of flattening or rejecting every nested
Section. Legacy pages retain the old output path. One connected geometry sheet
replaces old absolute declarations; parent origins and padding apply once.
No additional canonical graph, schema change or output writer is introduced.
Unsupported independent roots, non-free positioning, fluid containing geometry
and clipped expanded menus retain explicit compatibility findings. Browser
certification remains unproven. Exact source tests/risks are in the 122 evidence;
Prompt 10 owns execution and visual acceptance.

## Owner correction — editable Header/Footer contents (schema 17)

New Header/Footer insertions own an ordinary content Stack with a Text title and
Navigation Stack of ordinary Link children. Closed `page.chrome.v1` references
name those roles; they contain no duplicate title, link or geometry catalogue.
The default title derives from the Home page name until explicitly authored.
Existing eligible pages are initially included, with stable PageID destinations.
Exclusion hides a link without deleting its page, label or identity. Mobile menus
are enabled by default and reuse the same navigation snapshot and native control.

The content Stack receives the Header/Footer inner bounds. Its ordinary layout
properties resolve children; flexible navigation consumes remaining horizontal
space. Explicit customization retains ordinary Stack intent. Automatic Reset
restores default row properties, not hidden view-only offsets. Managed content/
navigation geometry cannot be edited as a misleading fixed frame.

Schema 16 and older packages remain readable and are not rewritten on open.
The explicit Add Editable Title and Navigation command preserves old child/link
identities and values in one reversible transaction. Missing role references
retain intent rather than borrowing another object. Duplication maps references
to copied NodeIDs. Native rendering, Preview and connected output use the same
resolved hierarchy; a navigation menu attaches only to its actual surface, never
both the Header and its nested Navigation Stack.

Focused model evidence covers defaults, title/show/page inclusion, custom/reset,
exact history, legacy conversion, round-trip persistence, duplication and static
navigation identity. Native visual and accumulated acceptance remain in progress
under SF-PRODUCT-UI-010; this addendum does not claim complete module coverage.
