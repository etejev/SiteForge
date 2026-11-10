# ADR-0020 — Opt-in connected page flow and page-owned navigation

## 013 native control focus boundary — bounded repair,2026-11-01

The restored document-modal SwiftUI sheet remains unchanged. Correlated tracing
shows its content Menu receiving Down through a SwiftUI KeyViewProxy without
opening; window/app routing is correct and no Safari action fires. Native
content navigation therefore uses one genuine NSPopUpButton/NSMenu inside the
existing representable boundary, with the native control owning first responder
and its standard cell owning accessibility metadata/hits. No synthetic role,
frame, parent/window ownership or key forwarding is introduced. Immutable
navigation snapshots remain projections; existing Preview actions stay sole
navigation authority. Menu tracking defers snapshot replacement, stale items
reject, and teardown cancels only this control's menu. Safari/compiler/export
and the rejected host replacement remain untouched. The exact new control
regression passes; actual native/Safari acceptance is still pending.

## Owner-approved013 native Preview host experiment —2026-11-01

Outcome: rejected/removed after actual013 failed78.950s with unchanged content
Menu hittability and keyboard-opening failure. Isolated host tests passed, but
did not establish the actual control boundary. Current architecture remains the
preceding SwiftUI document-modal Preview sheet and existing immutable actions;
no AppKit-owned controller/presenter remains. Historical experiment source and
results are retained only in owner-local diagnostics, not product coverage.
The paragraphs below describe the approved experiment, not adopted architecture.

Only native in-app Preview may use a per-originating-document AppKit sheet
controller around its existing observed SwiftUI presentation. The controller
owns one real document-modal sheet and native key/accessibility lifecycle; its
scene-local anchor retires it on owner/state/document replacement or teardown.
No global host/event interceptor, AX window spoof, canonical state, renderer or
browser-output fork. Existing snapshot identity, actions, async cancellation and
editor preflight remain authoritative. Safari's private-loopback compiler path
is unchanged. This is a falsifiable approved experiment, not accepted runtime
evidence; remove it if the strict actual-app activation boundary does not improve.

## Narrow automatic navigation allocation —013 source-only addendum

2026-11-02 accepted correction: the90-point Menu budget is an allocation floor,
not a native control width cap. The actual popup fills its resolved navigation
frame. Native Preview carries canonical parent IDs/page-flow roles as optional
immutable snapshot metadata and presents Header/Footer as real semantic owners
of their existing child views. Flattened paint backgrounds must not become AX
leaves over native controls. No rectangle-based ancestry, fake AX frame/role,
host replacement, layout-engine fork, canonical schema change or browser-output
change. The two exact native journeys pass511.484s/50.786s; final full closeout
is pending. Later source-only paragraphs are historical delivery notes.

After shared structural/responsive sizing, eligible automatic mobile rows reserve
the existing native 90-point Menu budget before default title shrink. Fixed
siblings and authored spacing retain their intent; only default spacing may
reduce. The same derived intent emits continuous static/fluid flex rules inside
existing containing boxes. No writer/schema/migration/breakpoint fork. Custom
sizes/fonts/fluid constraints remain on their prior path with bounded guidance.
Existing safety blockers remain; a 320-point compatibility probe rejects known
insufficient menu space without emitting sampled coordinates. It does not certify
all smaller widths. Menu display requires a visible available destination.
See the013 source receipt: nine code methods plus one native journey UNRUN,
no execution/visual acceptance. This addendum does not resolve OD-018/019.
The013 source continuation passes actual document/route availability as ephemeral
snapshot input to allocation and menu-room preflight, matching Menu display.
Empty navigation consumes no slot; unavailable retained links keep disabled
inline intent without a Menu floor. No stored link catalogue or visibility
rewrite. Callers without document context know only their own page. Same nine
code methods and one native journey remain UNRUN; source usability review is not
visual/browser acceptance. Existing clipping/positioning blockers are unchanged.

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
uses a real AppKit popup/menu control in its SwiftUI content; static output uses native details/summary
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

## Independent cross-page chrome reuse — source only, local workflow010

Reuse whole-page duplication's extracted canonical graph remapper for explicitly
selected Header/Footer subtrees. One existing atomic command batch adds only
missing roles to ordinary website pages. Existing roles/inbound links, body
identities/routes/metadata and resource ownership stay intact. Copied nodes are
independent, not a master/global chrome relationship; existing explicit token/
style/asset/component references retain normal project semantics. Page-only
destinations remain original PageIDs; copied internal sections map through the
graph identity map. Uncopied source sections remain explicit source-page links,
never same-label destination guesses. No schema/automatic migration. Replacement,
merge and supplied-slot retargeting remain excluded. The010 receipt lists UNRUN
selectors; no build/test/visual/output acceptance is claimed by this addendum.

## Closed connected-fluid output — source only, local workflow011

The existing compiler now admits the bounded connected-fluid adapter described
in the011 receipt, replacing the blanket fluid-containing-layout rejection.
Typed canonical cascade/container policy supplies allowlisted continuous clamp
lengths and normal block/flex/grid flow. Neutral HTML layout divs apply padding
once inside existing semantic nodes without changing their canonical ownership,
paint bounds, anchors or accessibility content. No graph/schema/writer fork.
Root-owned roles and managed chrome keep native allocated bounds; responsive
literals win over curves. No-fluid pages retain the previous output path.
Unproven intrinsic/Grid compression, free containing blocks, aspect coupling,
Fill height, legacy direct navigation and other named combinations stay blocked,
along with the existing positioning/root/menu/dependency boundaries. This is
source scope only; browser and native visual acceptance plus verification are
deferred under the owner hold. No universal output parity is implied.
