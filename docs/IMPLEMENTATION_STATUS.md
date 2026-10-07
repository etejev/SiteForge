# SiteForge Implementation Status

## Verified authoring checkpoint — 2026-10-07

The bounded implementation through `SF-AUTHORING-105`, excluding the still-
ready `SF-AUTHORING-106`, plus `SF-AUTHORING-107` and
`SF-PRODUCT-UI-005/006`, is integrated. The authoritative `./sf verify` passed
repository/security/traceability/architecture checks and all 640 tests: 542
unit/integration plus the complete 98-journey UI target. Its shared native
text-entry helper resolves live SwiftUI replacement controls and preserves
automatic NSTextView first-responder state. Normative modules remain Partial
where their evidence documents list deferred product scope.

Older source-only entries below are chronological detail; their “verification
deferred” wording is superseded for the bounded slices named above.

## SF-AUTHORING-107 — Source implemented, verification deferred

`SF-0308-001`–`008` now have a connected bounded authored-object clipboard
path. A strict v1 envelope captures selected subtree order and verified local
asset/token dependencies without paths or workspace/history state. Native
Cut/Copy/Paste/Paste in Place/Duplicate use the active window-owned workspace,
existing document commands, exact history inverses, resource staging, stable
identity remapping, renderer/selection adoption, and redacted diagnostics.
Cross-project component closure remains an explicit typed rejection. New model,
security, dependency, history, and actual-app test source is unrun, so SF-0308
remains Partial. Evidence:
`docs/evidence/SF-AUTHORING-107-CLIPBOARD-TRANSFER.md`.

OD-016 is now approved and makes SF-AUTHORING-106 the next dependency-safe
source slice: Blank Site plus one local neutral Starter Site containing Home
and About only.

## SF-AUTHORING-105 — Source implemented, verification deferred

Bounded `SF-0201-002/003/004/006`, `SF-0204-002/003/004/006`, and supporting
`SF-1504-001/003/004/006` now connect successful user-authorized Open to a
path-free native Recent Projects list. Reopen resolves the existing retained
bookmark and returns through the normal lifecycle; stale/missing access keeps
intent and offers Locate, while recency removal leaves authorization intact.
No project package or canonical document stores launch recency. New focused
tests are unrun, so the modules remain Partial. Evidence:
`docs/evidence/SF-AUTHORING-105-RECENT-PROJECTS.md`.

The broader source-completeness classification and dependency-ordered gaps are
recorded in `docs/evidence/SF-SOURCE-COMPLETENESS-AUDIT.md`; no overall source
completion claim is made.

## SF-PRODUCT-UI-006 — Source implemented, verification deferred

Bounded `SF-0201-006/009` and `SF-0203-003/006` now have a reconciled launch
and toolbar hierarchy. The
welcome state uses the approved static AppIcon and direct New Site/Open Project
actions. Five essential tools remain persistent; six additional implemented
tools use one native accessible menu while preserving the central Insert and
shortcut routes. This is scene-local command presentation, never project
content. Updated test source has not run, so the modules remain Partial.
Evidence: `docs/evidence/SF-PRODUCT-UI-006-LAUNCH-TOOLBAR.md`.

## SF-AUTHORING-104 — Source implemented, verification deferred

Bounded `SF-0206-004/006/008`, `SF-1507-003/004/006`, `SF-1602-004/006`, and
`SF-1607-002/003/004/006/008` now have a native Support settings surface with
truthful build/update/recovery provenance and a cancellable, stale-safe,
content-free diagnostic report workflow. Copy and user-selected export require
a generated reviewable report; failures disclose closed categories without
paths or content. Test source exists but has not run under the owner pause, so
all four normative modules remain Partial. Evidence:
`docs/evidence/SF-AUTHORING-104-SUPPORT-DIAGNOSTICS.md`.

Last updated: 2026-10-05.

SF-AUTHORING-103 is source-implemented but unverified. Local Preview now builds
an immutable all-website-page runtime through the production scene resolver,
projects validated stable Link targets, and offers native page, Back, Forward,
Refresh, and Done controls. Internal navigation and history are scene-local;
the editor page, selection, canonical document, revision, and history remain
unchanged. Missing targets are inert with recovery guidance, external targets
do not execute, and Preview uses the resolved page artboard instead of object-
union bounds. New focused tests are unrun, so `SF-1102`, `SF-1201`, and
`SF-1202` remain Partial. See
`docs/evidence/SF-AUTHORING-103-PREVIEW-NAVIGATION.md`.

SF-AUTHORING-102 is source-implemented but unverified. A strict versioned
fluid-value payload owns stable identity plus monotonic minimum, preferred,
maximum, and linear interpolation intent. The existing responsive geometry,
container layout, typography, immutable canvas preparation, breakpoint
comparison, and closed static-output paths now resolve that one source for
width/height, font size/line height, and padding/gap. Explicit breakpoint
literals retain precedence. Native Layout controls keep drafts noncanonical
and commit or remove one identity-gated property transaction with truthful
mixed/inapplicable state. Focused test source is unrun; `SF-0604` remains
Partial. See `docs/evidence/SF-AUTHORING-102-FLUID-VALUES.md`.

SF-AUTHORING-101 is source-implemented but unverified. The viewport and View
menu now open a native Desktop/Tablet/Mobile comparison sheet. Its pure policy
projects existing resolved structural geometry, effective visibility, and
responsive property provenance for the selection or active page. Review
actions change only the scene preset; no canonical comparison state, command,
history entry, or package member exists. Focused model and UI test source is
unrun. Custom breakpoints, simultaneous canvases, orientation/safe-area
simulation, responsive style/content/assets/components, fluid values,
container queries, broad preview/export parity, scale/accessibility matrices,
and release acceptance remain Partial. See
`docs/evidence/SF-AUTHORING-101-RESPONSIVE-COMPARISON.md`.

SF-AUTHORING-100 is source-implemented but unverified. Components definition
rows now expose a native Rename workflow with scene-local draft/cancel and
specific validation. `ComponentCommandRegistry` compiles one atomic graph
transaction that renames the stable definition and every linked instance while
preserving definition PageID, instance NodeIDs, overrides, geometry, child
data, and ordering. Exact history and package round-trip are covered by new
source tests, but none ran under the owner pause; `SF-0901`/`SF-0902` remain
Partial. See `docs/evidence/SF-AUTHORING-100-COMPONENT-RENAME.md`.

SF-AUTHORING-099 is source-implemented but unverified. Heading is now a visible
Basic Elements item and native Insert command that creates an existing Text
node with deterministic 360×48 geometry, `Heading` content, bold 32/38
typography, and authored `<h2>` semantics. It reuses canonical insertion,
Typography, Content, semantic role, renderer, selection, history, persistence,
and accessibility paths; no parallel node or renderer was introduced. Focused
model/actual-app test source is added but unrun, so `SF-0405`, `SF-0507`, and
`SF-1203` remain Partial. See
`docs/evidence/SF-AUTHORING-099-HEADING-TEMPLATE.md`.

SF-AUTHORING-098 is source-implemented but unverified. Applicable Frame, Text,
Section, Stack, Grid, Button, and Link selections now expose canonical authored
Accessible name and Description metadata in the Accessibility Inspector, with
defaulted/authored/mixed provenance, scene-local drafts, identity-gated atomic
commits, exact history, stable property identity, and package round-trip. The
same resolved values project to canvas accessibility and escaped static
`aria-label`/`aria-description`; role remains owned by the typed semantic-
element registry. Image and Form keep their dedicated schemas. Focused
model/output/actual-app test source is added but unrun, so `SF-0701`, `SF-0702`,
and `SF-1203` remain Partial. See
`docs/evidence/SF-AUTHORING-098-GENERAL-ACCESSIBILITY.md`.

SF-AUTHORING-097 is source-implemented but unverified. Blank-canvas drags now
produce a scene-owned directional marquee through the existing selection
registry: left-to-right contains visible clipped geometry; right-to-left
intersects it; Shift and Command add or toggle in stable paint order. Its
accent rectangle is editor-only, cancellation/stale identities retain the last
valid selection, and committed IDs continue through the existing canvas,
Layers, Inspector, status, and accessibility projections. Focused model and
actual-app test source is added but unrun, so `SF-0402` remains Partial. See
`docs/evidence/SF-AUTHORING-097-MARQUEE-SELECTION.md`.

SF-AUTHORING-096 is source-implemented but unverified. The Form Content and
Accessibility tabs now share a read-only projection of canonical field role,
accessible name, machine name, required state, help, options, bounds, and
property provenance. Mixed selections report Mixed rather than borrowing the
primary field. Form-level accessibility exposes configuration counts, the
existing category-only local validator, and the disabled/unconfigured submit
boundary. Writes still use the identity-gated atomic Form registry; test source
is added but unrun. `SF-0701`, `SF-0702`, `SF-0705`, and `SF-1006` remain
Partial. See `docs/evidence/SF-AUTHORING-096-FORM-ACCESSIBILITY-VALIDATION.md`.

SF-AUTHORING-091–095 are source-implemented but unverified. Email, Text Area,
Checkbox, Select, and Submit are real Form-only Elements and native Insert
actions backed by the established Text/form-field schema and atomic insertion
registry. Deterministic geometry and metadata flow into Content Inspector,
history, serialization, and safe static form output. Select seeds stable
ordered options; Submit remains explicitly disabled/unconfigured in output.
Shared model/output/UI test source is added but unrun. `SF-0405`, `SF-1006`,
and `SF-1202` remain Partial. See the five `SF-AUTHORING-091`–`095` evidence
notes.

SF-AUTHORING-090 is source-implemented but unverified: a selected Form can
receive a canonical Text-backed Input field from Elements or Insert, with
defaulted `form.field.v1` metadata and one undoable insertion. Non-Form
destinations are rejected. Model/actual-app test source is added but unrun;
`SF-0405` and `SF-1006` remain Partial. See
`docs/evidence/SF-AUTHORING-090-FORM-INPUT-TEMPLATE.md`.

SF-AUTHORING-086–089 are source-implemented and unverified. Divider, Header,
Navigation, and Footer are no longer disabled Elements rows; the same typed
Frame/Section insertion path now creates distinct, deterministic authored
templates and semantic section roles, also available from the native Insert
menu. Model/UI test source was added but not executed under the owner pause.
See `docs/evidence/SF-AUTHORING-086-089-ELEMENT-TEMPLATES.md`.

SF-AUTHORING-085 is source-implemented, unverified. Quick Open component
definition results now offer a distinct Insert Instance action routed through
the existing component registry, with live PageID/parent checks and no sheet
dismissal on command rejection. The actual-app test source covers rendered
adoption and Undo/Redo but remains unrun. See
`docs/evidence/SF-AUTHORING-085-QUICK-OPEN-COMPONENT-INSERT.md`.

SF-AUTHORING-084 is source-implemented and unverified: Quick Open asset search
now offers a separate direct Image insertion action that revalidates AssetID
and uses the existing Image command, with scene-selection rollback on rejection.
The real-app source journey covers one insertion and Undo/Redo but was not run
under the owner pause. See `docs/evidence/SF-AUTHORING-084-QUICK-OPEN-IMAGE-INSERT.md`.

SF-AUTHORING-079–083 extend the source-only ten-slice cycle. Quick Open New
Page uses the existing native page-editor transaction after its search sheet
dismisses. Components has native current-definition name search; Assets has
scene-only All/Used/Unused filtering composed with its existing search; Quick
Open can reveal current-project AssetIDs and component-definition PageIDs in
their real navigators without inserting or modifying them. Focused model/UI
test source is added, but has not run under the owner's five-slice execution
restriction. The approved `SF-0201-009` wording was synchronized into the
editable publication copy and its affected rendered pages were inspected.
No cycle gate, commit, or hosted result is claimed yet; all cited normative
modules remain Partial. See `docs/evidence/SF-AUTHORING-079-083-QUICK-OPEN-DISCOVERY.md`.

SF-PRODUCT-UI-005 and SF-AUTHORING-075–078 are an owner-directed source-only
half-batch, not a verified milestone. The approved gradient SF source now feeds
all ten checked-in AppIcon variants through an offline exterior-matte removal
script. Quick Open now projects a closed list of Frame/Text, structural,
Button/Link/Form, and Image actions; each dispatches through the existing
validated insertion/import boundary rather than a second document command.
Four policy tests, one actual-app journey, and stronger AppIcon assertions were
added as source. No tests, UI automation, `./sf verify`, local commit, or
GitHub action ran under the explicit batch restriction. `SF-0201`, `SF-0205`,
`SF-0405`, and `SF-0801/0802` remain Partial. See
`docs/evidence/SF-PRODUCT-UI-005-QUICK-OPEN-INSERTIONS.md`.

Batch SF-AUTHORING-065–074 local acceptance: one complete `./sf verify`
executed 504 unit/integration tests (all passed) and 81 UI tests (79 passed,
two failed). The keyboard traversal assertion was updated for the newly native
Pages search focus stop. The Layers type-filter journey was corrected to query
its own picker and account for the structural Root as a Frame-kind row. Both
exact failed journeys passed focused reruns; no second full-gate pass is
claimed under the owner's repair cadence. Original-resolution Elements,
Layers, Quick Open, and Settings screenshots were reviewed. `SF-0205` and
`SF-0206` remain Partial outside these bounded slices.

SF-AUTHORING-074 adds an explicit All/Pages/Layers/Actions scope to native
Quick Open under bounded `SF-0205-003/004/006/008`. Scope filters existing
authorized result projections and recent sections without changing PageID,
NodeID, command validation, or canonical document content. Focused policy
and actual-app tests passed in the batch, completing the ten source slices
065–074. Original-resolution scope screenshots were reviewed. See
`docs/evidence/SF-AUTHORING-074-QUICK-OPEN-SCOPES.md`.

SF-AUTHORING-073 adds bounded scene-local recent Layers to Quick Open under
`SF-0205-003/004/006/008`. Only successful Layers selection records a NodeID;
projection revalidates against the current page's authorized targets and
document identity. No visit history enters canonical content or packages.
Focused unit and actual-app tests passed in the batch; the recent-Layers
screenshot was reviewed. See
`docs/evidence/SF-AUTHORING-073-RECENT-LAYERS.md`.

SF-AUTHORING-072 adds bounded, deduplicated recent pages to native Quick Open
under bounded `SF-0205-003/004/006/008` and existing page navigation. The
list stores stable PageIDs in scene memory, revalidates against the live
document, and resets on document identity change. It neither serializes nor
alters project history. Focused policy and actual-app tests passed in the
batch; the recent-pages screenshot was reviewed. See
`docs/evidence/SF-AUTHORING-072-RECENT-PAGES.md`.

SF-AUTHORING-071 extends Quick Open with a closed list of non-destructive
Fit Document, Actual Size, and Toggle Grid actions under bounded
`SF-0205-002/003/004/006/008`, using the existing scene-local viewport/Grid
paths (`SF-0407`). The actions do not enter document history, packages, or
authored pixels. Focused policy and actual-app tests passed in the batch;
the Actions screenshot was reviewed. See
`docs/evidence/SF-AUTHORING-071-QUICK-OPEN-ACTIONS.md`.

SF-AUTHORING-070 implements an editor-only native Quick Open sheet for
current-document pages and current-page authorized Layers under bounded
`SF-0205-002/003/004/006/008`. A visible navigator button and View-menu
`Command-Shift-O` share the same active-window state. Results retain PageID/
NodeID and canonical order and dispatch through existing `selectPage` and
`selectLayer` paths; Cancel and no-result state are noncanonical. Focused
policy and actual-app tests passed in the batch, with sheet visual review;
see `docs/evidence/SF-AUTHORING-070-QUICK-OPEN.md`.

SF-AUTHORING-069 implements a native Layers NodeKind filter composed with
the existing local name query (`SF-0205-003/004/006/008`). The picker filters
only existing authorized targets and preserves selection, stable IDs, paint
order, project data, and renderer adoption. Show Selected Layer clears both
filters to recover a hidden selected row. The unit test passed in the batch;
the exact UI journey passed after picker-scoped querying and a truthful
two-Frame-kind fixture assertion. Both filter screenshots were reviewed. See
`docs/evidence/SF-AUTHORING-069-LAYERS-TYPE-FILTER.md`.

SF-AUTHORING-068 implements scene-local native Elements catalogue search under
bounded `SF-0205-002/003/004/006/008` and existing `SF-0405-002/006`.
Search matches names/categories without changing stable item identity,
availability, insertion commands, or project content. A count, no-result state,
Clear Search, and Escape are present. Focused policy and actual-app tests
passed in the batch; original-resolution result/empty/unavailable screenshots
were reviewed. `SF-0205` remains Partial;
see `docs/evidence/SF-AUTHORING-068-ELEMENTS-SEARCH.md`.

SF-AUTHORING-067 adds a native Layers search over the current page's existing
authorized targets (`SF-0205-002/003/004/006/008`, supporting
`SF-0402-002/006`). It preserves stable NodeIDs, paint order, and selection
while filtering; Return uses the existing Layers selection command, Escape
clears the query, and no-result/filtered-selection states offer a visible
recovery action. The new pure policy and actual-app journeys plus the affected
existing keyboard/multi-selection journey passed focused 3/3. Three original-
resolution states were reviewed. `SF-0205` remains Partial; the later batch
result is recorded above. See
`docs/evidence/SF-AUTHORING-067-LAYERS-SEARCH.md`.

SF-AUTHORING-066 adds a scene-local native Pages search field under bounded
`SF-0205-002/003/004/006/008` and existing `SF-0303-002/006`. It matches
current-document page names and routes case/diacritic-insensitively in canonical
page order. Return opens the first result; Escape and Clear Search restore the
list, and Show Selected Page recovers a filtered-out current page. Search alone
does not change selection, project revision, history, or package content. The
new model and UI journeys plus the affected Pages keyboard-navigation journey
passed focused 3/3; three original-resolution states were reviewed. `SF-0205`
remains Partial; the later batch result is recorded above.
See `docs/evidence/SF-AUTHORING-066-PAGES-SEARCH.md`.

SF-AUTHORING-065 adds a native application-only Reset tab for the two existing
Appearance and new-workspace Grid defaults (bounded `SF-0206-002/003/004/006/008`).
One explicit confirm action captures both exact records, rejects unsaved drafts,
managed preferences, and stale storage, then removes both with rollback on a
write mismatch. Cancel is neutral; Restore Previous recovers the prior records
within the Settings session. The existing tabs refresh from committed storage;
projects and open-workspace Grid state do not participate. Five focused model
tests and three affected actual-app Settings journeys passed 8/8;
five full-resolution Settings states were reviewed. No project schema, shared
document persistence, renderer, or global workspace boundary changed, so this
slice did not rerun the broad gate; the later batch result is recorded above.
`SF-0206` remains Partial. See
`docs/evidence/SF-AUTHORING-065-APPLICATION-RESET.md`.

SF-AUTHORING-064 adds an application-local Canvas Settings default for Grid
visibility in newly created workspaces (bounded `SF-0206-002/003/004/006/008`;
supporting `SF-0407-006`). A versioned, strictly decoded preference stays out of
project packages; draft, Apply, Cancel/Escape, Reset, stale-context rejection,
and session restoration use the existing native Settings window. The live
toolbar/View-menu Grid toggle remains scene-local and existing workspaces do
not change when the default is saved. Three exact unit tests and three affected
actual-app journeys passed focused 6/6; five original-resolution new-slice
captures were reviewed. No post-063 full gate, commit, push, or hosted result
is claimed for that focused slice; the later batch result is recorded above.
`SF-0206` remains Partial; see
`docs/evidence/SF-AUTHORING-064-CANVAS-SETTINGS.md`.

SF-PRODUCT-UI-004 adds an owner-approved, original static AppIcon and bounded
native frosted-pane refinement (`SF-0201-009`; supporting `SF-0201-003/006`,
`SF-1505-006`, `SF-1605-002/006`). Debug and Release select the same complete
macOS icon catalog; the built app contains its icon and bundle registration.
Navigator/Inspector use native behind-window material, with opaque Reduce
Transparency and stronger Increased Contrast boundaries. Three focused unit
and three affected UI selectors passed (6/6); seven full-resolution shell
screenshots and the built icon were reviewed. The XCTest Dock screenshot still
showed a generic icon, so fresh Finder/Dock cache presentation remains an
explicit visual follow-up. No new full gate, commit, push, or hosted result is
claimed. See `docs/evidence/SF-PRODUCT-UI-004-BRANDING-SHELL.md`.

SF-AUTHORING-063 passed its local prompt-ten checkpoint: bounded project-local image-asset folder,
tag, and favorite organization (`SF-0801` Partial). Optional schema-eleven
metadata preserves existing asset/resource identity and schema-ten decoding;
native Assets controls use one revision- and scene-guarded history command.
Focused model/migration/static-reference tests passed 4/4; the exact native
import/organize/filter/undo/reopen journey passed 1/1 after the console was
unlocked, and five original-resolution screenshots were reviewed. The
tenth-prompt gate passed 486/486 unit/integration and 70/70 UI tests on
2026-09-29 (556 total, zero failures). Previously,
an earlier managed UI launch was denied before testing by macOS testmanagerd
sandbox error 159, while a later direct UI run completed 70 tests and exposed
the two selection failures corrected below. The final post-repair full gate
passed. This tree remains uncommitted; no hosted/release completion is claimed. See
`docs/evidence/SF-AUTHORING-063-ASSET-ORGANIZATION.md`.

Focused checkpoint recovery (`SF-0402-005`, `SF-0601-003`, `SF-0602-003`):
the direct UI run completed 70 tests, with 68 passing and two Mobile-preset
selection failures. `SelectionCommandRegistry.adopt` incorrectly cleared a
valid selection when the selected Frame became fully artboard-clipped. The
corrected scene-local retention passes one focused model test and both exact
UI journeys (2/2); reviewed Tablet/Mobile/Reveal attachments show no ghost
overlay and truthful accessibility status. The broader SF-AUTHORING-063 gate
subsequently passed 556/556. See `docs/evidence/SF-RESPONSIVE-SELECTION-RECOVERY.md`.

SF-AUTHORING-062 adds a bounded component Boolean visibility-property
foundation (`SF-0901`, `SF-0902`, `SF-0905` Partial). Definition children own a
stable property ID, name, and default; instances may author or reset a typed
override without changing the definition. Component expansion resolves the
visibility before layout, canvas/Preview rendering, accessibility projection,
and closed static output. The native Content Inspector exposes inherited versus
authored provenance, and Layers retains a read-only hidden-child status. Exact
focused results and original-resolution visual review are recorded in
`docs/evidence/SF-AUTHORING-062-COMPONENT-VISIBILITY.md`. The prompt-nine full
gate and hosted checkpoint have not run.

SF-AUTHORING-061 is a focused local Frame/Section image-fill checkpoint
(`SF-0508`, `SF-0801`, `SF-0802` Partial). A strictly validated optional
AssetID plus Fit/Fill mode reuses existing package resources and typed history;
the image paints above solid/gradient backgrounds inside the same rounded
object clip, with object opacity applied once. Asset deletion accounts for
both Image nodes and image fills. Native Inspector selection and the immutable
canvas/Preview/static projections are wired. Focused model and exact native
pixel checks and the real-app import/Inspector/undo/reopen journey passed 3/3
exact selectors. Four original-resolution screenshots were reviewed; see
`docs/evidence/SF-AUTHORING-061-FRAME-SECTION-IMAGE-FILL.md`. Existing runtime
warnings are recorded there. No prompt-eight full gate or hosted run occurred.

SF-AUTHORING-060 adds a bounded native whole-object text foreground for
Text, Button, and Link (`SF-0507`, `SF-0508`, `SF-0509` Partial). Optional
normalized RGBA channels preserve automatic legacy color when omitted;
target-keyed local Color Tokens retain a literal fallback. The existing typed
typography/token transactions provide history and stable property identity.
Native committed text and inline editing use sRGB, and the closed static
projection emits the resolved color. Focused model, render, and actual-app
checks passed; four Inspector/canvas captures were reviewed. See
`docs/evidence/SF-AUTHORING-060-TEXT-FOREGROUND.md`. The prompt-seven full
gate and hosted checkpoint have not run.

SF-AUTHORING-059 extends the bounded local Color Token path to authored Border
and Outer Shadow colors (`SF-0509`, `SF-0506`, `SF-0508` Partial). Schema ten
migrates schema-nine fill-only references to a target-keyed property namespace
without changing TokenIDs, PropertyIDs, literal fallbacks, or unrelated style.
The central token registry handles bind/unbind and in-use deletion, and shared
resolution feeds the native canvas and closed Frame/Section static output.
The native Design Inspector exposes a target picker and bound/literal state.
Focused results and remaining limits are in
`docs/evidence/SF-AUTHORING-059-APPEARANCE-TOKENS.md`; the prompt-six full gate
has not run.

SF-AUTHORING-058 has a focused base-only fixed-sizing foundation for Frame and
Image (`SF-0505-001`–`008`, Partial). Versioned typed min/max and aspect
properties preserve NodeProperty IDs and provenance; strict document validation
rejects malformed or contradictory values. The central sizing command clamps
base numeric and pointer geometry, provides exact history, and feeds a native
Layout Inspector with scene-local drafts and Reset. The immutable static tree
projects only closed validated sizing declarations. Four focused model/static/UI
selectors passed; three native window captures were visually reviewed. No
full gate was run under the prompt-5 reset policy. See
`docs/evidence/SF-AUTHORING-058-SIZING-CONSTRAINTS.md`.

SF-AUTHORING-057 has a focused local color-token foundation: versioned stable
RGBA token records, reversible solid-fill binding and safe unbinding, native
Design Inspector controls, and shared canvas/Preview/closed-static resolution.
The bounded model, migration, static-output, and actual-app focused tests pass;
the full SF-0509 module and the tenth-prompt verification gate remain Partial.
See `docs/evidence/SF-AUTHORING-057-LOCAL-COLOR-TOKENS.md`.

SF-AUTHORING-037 is IN PROGRESS. A pure local validation engine resolves the
canonical Form field schema against a caller-owned ephemeral visitor snapshot:
required/text/email/select/checkbox checks, stable form/field result identity,
revision/scene/renderer rejection, and redacted failure categories. It has no
document, history, package, autosave, recovery, or submission write path. The
Form Inspector can adopt the current category-only result for an empty local
draft; its static-output indicator explicitly reports that submission is
unavailable. Focused non-UI coverage is green (3/3). See
`docs/evidence/SF-AUTHORING-037-LOCAL-VALIDATION.md`.

SF-AUTHORING-036 remains IN PROGRESS. Form is now an enabled canonical Elements
and Insert action; its empty 320×180 container uses the shared insertion,
selection, Layers, renderer, and package path. Content presents a truthful
unavailable Form summary, while Text children of Form receive native field
kind, label, machine name, help, required, and Select-options controls. One
identity-gated `FormInspectorCommandRegistry` compiles validated edits into
atomic generic history with exact undo/redo and package/recovery preservation.
Focused non-UI coverage is green; actual-app UI evidence and visitor/runtime
submission behavior remain deferred. Ephemeral local validation is tracked in
SF-AUTHORING-037; release acceptance remains deferred. See
`docs/evidence/SF-AUTHORING-036-FORM-FOUNDATION.md`.

SF-AUTHORING-026 is IN PROGRESS: current authored node kinds resolve a typed,
versioned semantic HTML element with omitted/defaulted/authored provenance.
The native Design Inspector uses the identity-gated transaction path; raw HTML,
generated markup, browser runtime and publishing remain out of scope. See
`docs/evidence/SF-AUTHORING-026-SEMANTIC-ELEMENTS.md`.

SF-AUTHORING-025 is hosted verified: the native Preview command captures an
immutable adopted render-plan snapshot at an explicit open/refresh boundary.
The preview is scene-local and has no document/history write path. Focused
model and native UI evidence covers empty/unavailable status, snapshot refresh,
editor-chrome exclusion and Close focus restoration. The final gate passed 430
unit/integration + 63 UI = 493 tests with zero failures. SF-1201/SF-1202 remain
Partial; browser runtime, HTML/CSS/JS, export/publishing and SF-1204
are excluded. Actions `36166584811` passed at `1ab912e` with the same 493
tests and zero failures. SF-CI-025 is closed.

SF-CANVAS-POINTER-001 is locally verified: native backing-layer ownership removes
the duplicate container reflection; empty guidance yields during creation.
Independent native-event and painted-edge regression evidence is recorded in
`docs/evidence/SF-CANVAS-POINTER-001.md`. Ten affected renderer checks and the
native pointer journey pass; twelve final captures passed visual review.

SF-AUTHORING-024 is locally verified: exposed plain-text definition properties,
independent instance overrides, removal-based reset, non-destructive binding
guards and schema-v8 compatibility. Eight new model/renderer checks and three
affected budget/resource checks pass, plus the native two-instance journey.
Five original-resolution captures passed visual review. The combined final
`./sf verify` passed 429 non-UI + 61 UI = 490 tests, zero failures, including
repository checks. Hosted confirmation pending. Bounded SF-0902/0905 remain Partial; see
`docs/evidence/SF-AUTHORING-024-COMPONENT-TEXT.md`.

SF-AUTHORING-023 is locally verified and DONE: native application-only Appearance Settings,
with preview/apply/cancel/reset/restoration and versioned app-local persistence.
Bounded SF-0206-002/003/004/006/008 evidence is recorded in
`docs/evidence/SF-AUTHORING-023-APPEARANCE-SETTINGS.md`; module remains Partial.
No canonical project preference coverage is claimed. Focused acceptance passed
6 model + 1 UI tests; five native Settings captures were visually reviewed.
Final `./sf verify` passed 420 unit/integration + 59 UI = 479 tests, zero failures.
Repository checks passed. Hosted Actions `34252345248` passed at `b50375c`.

SF-AUTHORING-022 and the integrated SF-AUTHORING-021 hosted repair are VERIFIED
AND DONE within their bounded scopes. Actions `34172995329` at `bb5992f`
passed `./sf verify`: 414 unit/integration + 58 UI = 472 tests, zero failures.
The notes below preserve the local and hosted-repair chronology; they do not
supersede this final result. Normative component modules remain Partial.

Pre-hosted local evidence: focused checks cover
pre-allocation expansion limits, strict schema rejection, resource save/recovery
and historical fixtures. New component placement respects the visible selected
parent. Revised safe-delete and compact visual acceptance now pass in native
XCTest: both focused journeys passed independently, and retained window images
were reviewed. The earlier automation authentication block is resolved.
Final `./sf verify` passed 413 unit/integration + 56 UI = 469 tests, zero
failures, with all repository gates green. See
`docs/evidence/SF-AUTHORING-022-LOCAL-COMPONENTS.md`. Hosted acceptance is not
inferred from this local result.

Hosted follow-up `34165188350` exposed two narrow-display pointer failures,
not canonical component/page failures. Both corrected journeys and the new
1024-point edge-alignment regression passed together 3/3. The component
evidence records the retained recording, screenshots and bounded CI headroom.
The next hosted attempt passed the component workflow; the remaining placement
observer and native image-panel query defects now have six passing affected
selectors, including actual window movement. See the same evidence chronology.

SF-AUTHORING-021 is locally verified: native static page creation, name/route
editing, duplicate/delete/reorder and live link targets share canonical
transactions and preserved history. Five focused model and two new UI selectors,
plus the affected prior compact journey, passed. Seven window images were
reviewed. Final verification passed 404 non-UI + 54 UI = 458 tests, zero
failures. Hosted acceptance follows the commit. SF-0303 remains
Partial; see `docs/evidence/SF-AUTHORING-021-STATIC-PAGES.md`.

SF-AUTHORING-020 is locally verified: schema-v6 Button/Link nodes, native label
and typed internal/external target editing, immutable glyph rendering,
atomic subset edits, missing-target preservation and exact history/package
round trips are implemented. All three new actual-app journeys and reviewed
compact/internal-target visuals pass. Final `./sf verify` passed 399 non-UI
and 52 UI tests (451 total), zero failures. Actions `34000476753` passed
the same hosted totals for `85615b9`. SF-0806 and SF-1102 remain Partial. See
`docs/evidence/SF-AUTHORING-020-BUTTON-LINK.md` for exact scope and evidence.

SF-AUTHORING-041 has begun a bounded static-control compiler foundation. Only
typed canonical Link routes are projected into immutable markup; generated
Button markup is intentionally inert, and unresolved internal targets remain
accessible but do not become raw URLs. This does not enable browser runtime,
actions, submission, static file export, or release acceptance. Typed
new-context Links emit only safe static `noopener noreferrer` attributes.
Evidence is in
`docs/evidence/SF-AUTHORING-041-STATIC-CONTROLS.md`; local test execution is
paused by owner instruction for this checkpoint. The queued focused regression
is `CanvasRendererTests.testStaticControlCompilerEscapesTypedRoutesAndKeepsMissingTargetsInert`.

SF-AUTHORING-042 has begun a bounded static-navigation compiler foundation.
`StaticNavigationEmitter` projects only ordered persisted Home and standard
pages that have validated static output routes, marks the generated page with
`aria-current=page`, and omits special/unavailable pages without mutating the
canonical document. Nested generated paths use safe relative links. Browser runtime, navigation authoring, static file export,
and publishing remain deferred; evidence is in
`docs/evidence/SF-AUTHORING-042-STATIC-NAVIGATION.md`. Local test execution is
paused by owner instruction.

SF-AUTHORING-043 has begun a bounded static layout-output parity foundation.
`StaticLayoutOutputEmitter` projects only typed canonical base geometry,
explicit Tablet/Mobile overrides, and visibility into a NodeID-scoped CSS
allowlist. It keeps base/inherited state and breakpoint overrides distinct,
uses deterministic decimal rounding, and does not mutate or serialize
document content. Raw CSS/media input, browser layout, flex/grid/container
queries, static-file export, publishing, and release acceptance remain
deferred. Evidence is in
`docs/evidence/SF-AUTHORING-043-STATIC-LAYOUT.md`; local test execution is
paused by owner instruction.

SF-AUTHORING-044 has begun the dependency-safe static multi-page layout-plan
integration. `MultiPageStaticBuildPlanner` now includes the immutable typed
layout projection as a deterministic `styles.css` plan artifact whenever
canonical geometry exists. It shares SF-AUTHORING-043's selectors and
responsive cascade without creating files, linking a browser document shell,
or mutating canonical content. Evidence is in
`docs/evidence/SF-AUTHORING-044-STATIC-LAYOUT-PLAN.md`; local test execution
is paused by owner instruction.

SF-AUTHORING-045 has begun static typography-output parity. The static tree
now carries canonical plain Text separately from editor state and escapes it
at the HTML boundary. `StaticTypographyOutputEmitter` projects only resolved,
validated scalar typography and fixed enum mappings; the canonical System
family maps to `system-ui`, while arbitrary installed-family names are safely
omitted. Component overrides/defaults remain canonical and unmodified; this
slice does not flatten components. Rich text, raw HTML/CSS, custom/remote
fonts, browser rendering, responsive typography, generated files, publishing,
and release acceptance remain deferred. Evidence is in
`docs/evidence/SF-AUTHORING-045-STATIC-TYPOGRAPHY.md`; local test execution is
paused by owner instruction.

SF-AUTHORING-046 has begun static Image resource-reference parity. The
immutable static tree carries canonical AssetID, alt/decorative intent, and an
optional verified content-addressed path from the existing resource planner.
Missing/corrupt plan entries remain an explicit safe missing-resource state;
they never become a Finder path, raw URL, or canonical mutation. Resource-byte
export/writes, browser loading, remote assets, responsive source sets,
publishing, and release acceptance remain deferred. Evidence is in
`docs/evidence/SF-AUTHORING-046-STATIC-IMAGE-REFERENCES.md`; local test
execution is paused by owner instruction.

SF-AUTHORING-047 has begun static Image fit/focal output parity. The static
stylesheet maps only canonical Fit/Fill/Stretch and finite normalized focal
coordinates to fixed `object-fit`/`object-position` declarations using the
existing stable Image selector. It preserves the original resource and
canonical geometry; image crops/renditions, transforms, responsive sources,
browser loading, generated resource writes, publishing, and release acceptance
remain deferred. Evidence is in
`docs/evidence/SF-AUTHORING-047-STATIC-IMAGE-PRESENTATION.md`; local test
execution is paused by owner instruction.

SF-AUTHORING-048 has begun static Image dimension and responsive-layout
parity. Verified ImageAsset pixel dimensions are retained only as safe integer
HTML sizing hints; canonical layout and explicit Tablet/Mobile geometry and
visibility continue to flow exclusively through `StaticLayoutOutputEmitter`.
This does not infer an aspect-ratio constraint or add a responsive source-set,
remote-loading, browser, generated-resource, publishing, or release path.
Evidence is in `docs/evidence/SF-AUTHORING-048-STATIC-IMAGE-RESPONSIVE-LAYOUT.md`;
local test execution is paused by owner instruction.

SF-AUTHORING-049 has begun static asset-manifest integrity projection. The
multi-page plan emits a deterministic content-free Image manifest only for
verified content-addressed references, retaining AssetID/path/dimension
provenance while omitting filenames, local paths, bytes, and metadata.
Missing/corrupt entries remain omitted from this optional plan artifact and
continue through the existing safe missing-resource markup state. Evidence is
in `docs/evidence/SF-AUTHORING-049-STATIC-ASSET-MANIFEST.md`; local test
execution is paused by owner instruction.

SF-AUTHORING-050 has begun static semantic-element resolution parity. The
existing typed semantic resolver is now shared by the Inspector and immutable
static compiler, so supported authored roles retain stable NodeID output while
omitted metadata uses the node-kind default and invalid historical values are
safely omitted. Evidence is in
`docs/evidence/SF-AUTHORING-050-STATIC-SEMANTIC-RESOLUTION.md`; local test
execution is paused by owner instruction.

SF-AUTHORING-051 has begun static semantic-outline parity. Immutable static
nodes retain canonical parent provenance, and the multi-page plan projects a
validated page/node/parent/semantic outline without altering HTML nesting,
canonical state, browser behavior, or file writes. Evidence is in
`docs/evidence/SF-AUTHORING-051-STATIC-SEMANTIC-OUTLINE.md`; local test
execution is paused by owner instruction.

SF-AUTHORING-052 has begun static plan-integrity parity. Every immutable
static build plan now carries a deterministic SHA-256 digest of its
path-sorted, length-delimited in-memory files, without creating an integrity
file, changing canonical state, or invoking a writer. Evidence is in
`docs/evidence/SF-AUTHORING-052-STATIC-PLAN-INTEGRITY.md`; local test
execution is paused by owner instruction.

SF-AUTHORING-053 has begun static authored-box parity. Valid typed static
geometry now includes a fixed `border-box` declaration, retaining canonical
width/height as the outer output box without adding an authorable CSS or
browser-layout path. Evidence is in
`docs/evidence/SF-AUTHORING-053-STATIC-BOX-MODEL.md`; local test execution is
paused by owner instruction.

SF-AUTHORING-056 is Development Prompt 3 of the restored ten-prompt cadence.
It retains the canonical outer-shadow value and adds an explicit reversible
enabled flag for Frame/Section. An omitted flag resolves to enabled for
existing authored/legacy shadows; explicit disabled retains all typed values
for exact undo/redo, persistence, and recovery. The same resolution reaches
the native canvas, Local Preview, and closed static output vocabulary.
Multiple/inner/inset shadows, filters, arbitrary CSS, browser runtime, and
release acceptance remain deferred.

SF-AUTHORING-055 is Development Prompt 2 of the restored ten-prompt cadence.
It extends the existing validated `style.box.v1` representation for Frame and
Section only: uniform content padding and explicit content clipping. The
identity-gated atomic box-style registry, native Design Inspector controls,
resolved structural/canvas geometry, and closed static output projection share
the same typed values. Invalid persisted content-box values are unavailable
rather than silently treated as defaults. Focused model, static-output, and
native Inspector selectors passed 3/3 on 2026-09-27; see
`docs/evidence/SF-AUTHORING-055-BOX-STYLE-FOUNDATION.md`. Per-side/logical
controls, margin, per-corner radius, corner smoothing, layered shadows,
browser output, and release acceptance remain deferred.
It reuses the verified native canonical fill-layer, Inspector, transaction,
renderer, persistence, recovery, and accessibility path while adding a closed
static Frame/Section projection for solid and linear-gradient layers plus
single application of canonical opacity. Evidence is in
`docs/evidence/SF-AUTHORING-054-NATIVE-FILL-AUTHORING.md`; the related
normative modules remain Partial outside this bounded slice.

Focused compiler, command, and native-raster selectors passed 3/3 on
2026-09-27. The existing Inspector UI selector was attempted once but XCTest
timed out while enabling automation before the test body ran, so this records
no new UI result and leaves the assertion unchanged.

SF-AUTHORING-019 final Save follow-up is verified: native durable Save remains
available during recovery autosave through the existing cancel/drain boundary.
Focused lifecycle and typography persistence checks passed (2/2). Actions
`33991018406` passed 392 unit/integration plus 49 UI tests (441/441), with
repository checks green, for final production correction `f951df7`.

Current SF-AUTHORING-019 repair evidence supersedes the earlier AX-only
explanation in the historical checkpoint row: immutable-snapshot autosave
was disabling the shared Inspector validation context. Editing now remains
available with revision guards. Actions `33980431383` passed the new autosave
regression plus geometry and structural UI journeys (3/3). Final local
verification passed 392 unit/integration plus 49 UI tests (441/441), with
repository checks green. Actions `33982941555` confirmed the same 441/441
hosted gate for production commit `f6c58ef`; see
`docs/evidence/SF-AUTHORING-019-INSPECTOR-REPAIR.md`.

The subsequent documentation-only run `33984707264` retained 49/49 UI passes
but exposed an unordered-task assumption in a save unit test. Its deterministic
checkpoint-barrier correction and adjacent save-race test passed 2/2; no
application code changed. See the same evidence note for exact assertions.

| Requirement or work item | Status | Implementation | Automated evidence | Manual evidence | Notes |
|---|---|---|---|---|---|
| SF-AUTHORING-019 / bounded SF-0801-001–008; SF-0802-001–008 | **Verified bounded local-raster slice and hosted Inspector/autosave correction; both modules remain Partial overall** | Schema-v5 owns stable asset descriptors and Image references; original bytes remain in the existing resource sidecar. Shared Inspector edits stay available during revision-guarded immutable snapshot saves. Native Save handles already-Saved state; narrow displays retain the 1100-point minimum; live native controls retain focus and readable compact Alignment labels. | Seven distinct affected selectors passed; three consecutive original-failure groups passed 9/9. Final local and hosted verification each passed 392 unit/integration plus 49 UI tests (441/441), zero failures. Actions 33982941555 passed for production commit f6c58ef; repository checks passed. See docs/evidence/SF-AUTHORING-019-INSPECTOR-REPAIR.md. | Retained original-resolution typography/image/structural reopen states and Alignment screenshots were reviewed for Saved status, preserved content, readable controls, upright rendering, and aligned selection. | Folders/tags/favorites, bulk organization, drag-to-artboard, remote providers, SVG/video/audio/fonts, advanced editing, masks/renditions, responsive source sets, metadata-policy UI, non-Image fills, preview/export parity, broad accessibility matrices, and release acceptance remain deferred. |
| SF-AUTHORING-018 / bounded SF-0601-001–008; SF-0602-001–008; SF-0603-001–008; supporting SF-0502/SF-0503 | **Verified bounded responsive layout/visibility slice; normative responsive modules remain Partial overall** | The existing stable Desktop/Tablet/Mobile cascade now owns versioned Section/Stack/Grid container overrides and Frame/Text/Section/Stack/Grid visibility overrides. Identity-gated registries compile atomic set/reset transactions. One resolved scene excludes hidden subtrees from authored pixels, layout participation, hit testing, inline editing, canvas accessibility, and selection chrome while preserving stable Layers identity and a visible recovery route. | Seven focused model/renderer/selection/package selectors and the fresh-process responsive UI journey passed. Hosted follow-up proves nested insertion remains available during background autosave and bounds numeric Inspector fields so intrinsic Reset controls remain visible. Final hosted `./sf verify` passed 379 unit/integration plus 48 UI tests (427 total), zero failures, with every repository gate green on 2026-08-31. | Seven original-resolution maximized-window states were reviewed for Desktop base, Tablet/Mobile overrides, hidden Layers inspection, Undo/Redo restoration, Stack/Grid layout, readable controls, clear artboard/grid composition, upright content, and absence of ghost/debug objects. | Custom breakpoints, responsive styles/typography/content/assets/components, comparison panes, orientation/safe areas, container queries, fluid typography, alternate source sets, preview/export parity, cross-hardware/OS accessibility matrices, and release acceptance remain deferred. |
| SF-AUTHORING-017 / bounded SF-0502-001–008; SF-0503-001–008; structural-spacing portion of SF-0506-001–008 | **Verified bounded structural-layout slice; normative modules remain Partial overall** | Existing schema-v4 structural properties remain authoritative. One typed identity-gated registry authors Section padding; Stack direction, gap, padding, and cross-axis alignment; and Grid columns, gap, and padding. One shared resolver projects stable child frames to renderer, selection, hit testing, accessibility, history, packages, and recovery, proportionally fitting oversized insertion defaults into bounded content boxes without changing canonical child geometry. | Focused model/renderer/package selectors passed 5/5; actual-app journeys passed 2/2; `./sf test half` passed 371/371. Final `./sf verify` passed 372 unit/integration plus 47 UI tests (419 total), zero failures, with every repository gate green on 2026-08-28. | Original-resolution maximized and practical-minimum Inspector states were reviewed for readable controls, page/grid clarity, bounded child surfaces, aligned selection, upright labels, and absence of ghost/debug content. | Responsive container-layout overrides, per-side/logical padding, separate row/column gaps, wrapping/distribution, advanced grid tracks/flow, preview/export parity, cross-hardware scale, and release acceptance remain deferred. |
| SF-AUTHORING-016 / bounded SF-0601-001–008; SF-0602-001–008 | **Verified bounded responsive geometry slice; both modules remain Partial overall** | Stable fixed Desktop/Tablet/Mobile IDs resolve deterministic non-overlapping widths. Desktop owns base `layout.*`; versioned per-node properties author isolated Tablet/Mobile X/Y/Width/Height overrides. The identity-gated Layout registry provides atomic set/reset with exact inverses and one resolver feeds renderer, selection, hit testing, accessibility, inline geometry, history, packages, and recovery. | Focused model/renderer/package plus actual-app coverage passed 5/5. Final `./sf verify` passed 367 unit/integration plus 45 UI tests (412 total), zero failures, on 2026-08-28; all repository gates passed. | Five original-resolution maximized-window states were reviewed for inherited/authored provenance, visible Tablet/Mobile geometry, reset, undo/redo, readable controls, artboard/grid clarity, aligned selection, upright content, and absence of ghost/debug artifacts; see `docs/evidence/SF-AUTHORING-016-RESPONSIVE-GEOMETRY.md`. | SF-0601/SF-0602 remain Partial: custom breakpoint management, responsive style/typography/content/visibility, comparison panes, orientation/safe areas, container queries, fluid typography, component responsiveness, preview/export parity, performance budgets, and release acceptance remain deferred. |
| SF-AUTHORING-015 / bounded SF-0507-001–008 | **Verified bounded typography slice; SF-0507 remains Partial overall** | Strict `style.typography.v1` properties and one identity-gated registry author plain-Text family, bounded weight, size, explicit line height, tracking, and leading/center/trailing alignment. Immutable renderer objects and the live native editor share resolved font/fallback and layout metrics. | Focused registry/history, render/layout, package/recovery, and actual-app Save/reopen coverage passed 4/4. Final `./sf verify` passed 363 unit/integration plus 44 UI tests (407 total), zero failures, on 2026-08-28; all repository gates passed. | Six original-resolution maximized-window states were reviewed for control readability, upright glyphs, selection/editor parity, missing-font status, page/grid clarity, and absence of ghost/debug content; see `docs/evidence/SF-AUTHORING-015-TYPOGRAPHY.md`. | SF-0507 remains Partial: font import/licensing, variable axes, rich-text spans, advanced paragraph controls, automatic sizing, responsive overrides, tokens, preview/export parity, performance, and release acceptance remain deferred. |
| SF-AUTHORING-014 / bounded SF-0506-001–008 | **Verified bounded; SF-0506 remains Partial overall** | Typed `style.box.v1` properties provide an optional uniform border, uniform corner radius, and one drop shadow for Frame, Section, Stack, and Grid. Native Design controls route scene-local drafts through one identity-gated atomic registry. Immutable renderer snapshots compose exterior shadow, radius-clipped fills, and border without changing interaction geometry. | Focused registry/history, package/recovery, production raster/tile, and two running-app journeys passed 7/7. Final local `./sf verify` passed 360 unit/integration plus 43 UI tests (403 total), zero failures, with every repository gate green on 2026-08-26. After two hosted runs isolated the compact-window placement boundary, Actions `32934689112` passed the same complete 403-test gate at `65571dc`. | Original-resolution maximized-window attachments for unstyled selection, border/radius, shadow, undo/redo, and practical-minimum Inspector were reviewed for readable controls, aligned geometry, contrast, and absence of ghost/debug content; see `docs/evidence/SF-AUTHORING-014-BOX-APPEARANCE.md`. | SF-0506 remains Partial: margin/padding, logical or independent borders, per-corner radii, multiple/inner shadows, clipping controls, preview/export parity, cross-hardware performance, and release acceptance remain deferred. |
| SF-AUDIT-001 / bounded SF-0201-002, 003, 006, 008; SF-0301-004–006; SF-0303-001, 005, 008; SF-0405-007; SF-0407-006–008; SF-0503-007; SF-0508-001–008; SF-1502-001; SF-1504-004; SF-1702-008; SF-1802-008; SF-1804-008; SF-1902-008; SF-2002-008 | **Verified bounded audit correction** | Strict fill-v1/model/package decoding and explicit numeric drafts; descriptor-bound resource I/O with exact role/key/ACL policy; coordinated cancellation relay; linear Grid row preparation; off-main production scene/renderer/selection/viewport projection; bounded domain-separated diagnostics; portable checksum output; marked-document-window material policy; intrinsic viewport controls and scrollable minimum-width Fill Inspector. Synchronous selection repair now shares scene preparation's page-level projection for implicit structural roots, preserving valid selection through undo/redo. | Named fill decode/migration/package selectors and numeric-draft coverage passed; the resource/cancellation/Grid/diagnostic group passed 8/8; the 10,000-object active-work heartbeat, portable-checksum regression, and 3/3 selection/geometry follow-up passed. Final `./sf verify` passed 356 unit/integration plus 41 UI tests (397 total), zero failures, on 2026-08-25; all repository gates passed. Exact selectors are in `docs/evidence/SF-AUDIT-001-CORRECTIONS.md`. | The minimum 1100×700 and normal-maximized running-app journeys passed 2/2. Original-resolution attachments were reviewed for visible viewport controls, scrollable fill rows, readable navigation/Inspector tabs, centered grid/artboard composition, upright content, aligned selection, and absence of ghost/debug artifacts. | Image fills, blend/filter effects, borders, shadows, responsive overrides, preview/export parity, OS-level VoiceOver/settings acceptance, cross-hardware budgets, signing, notarization, publishing, and release acceptance remain deferred. No unsupported feature scope was added. |
| SF-AUTHORING-013 / bounded SF-0508-001–008 | **Verified bounded; SF-0508 remains Partial overall** | Versioned `style.fill.layers.v1` owns stable ordered solid/linear-gradient layers and stops after first v1 style edit. The central Design registry compiles atomic property batches; renderer preparation snapshots layers immutably and native tile paint composites enabled layers clipped to authored geometry with object opacity applied once to the completed stack. Design exposes accessible layer, native colour, and stop-order controls. Exact shared stacks remain editable across a multiple selection; differing stacks show mixed without borrowing primary-object rows, and incompatible objects remain unchanged. | Production-raster coverage and adjacent regressions passed 3/3. A retained schema-v4 golden proves legacy retirement, exact identity/order/value preservation, deterministic save/reopen, and owned recovery. The corrected multi-selection selector passed. Final `./sf verify` passed 331 unit/integration plus 39 UI tests (370 total), zero failures, on 2026-08-25; repository/security/traceability/architecture/migration/evidence checks passed. See `docs/evidence/SF-AUTHORING-013-FILL-LAYERS-CHECKPOINT.md`. | The corrected Inspector journey passed 1/1. Its original-resolution attachment was reviewed and shows readable native controls, two distinct solid rows, centered selected geometry, visible grid/artboard boundaries, and normal maximized-window presentation. | Image fills, blend/filter effects, borders, shadows, tokens, broad colour-profile behavior, responsive overrides, preview/export parity, OS-level VoiceOver/settings acceptance, cross-hardware budgets, and release acceptance remain deferred. |
| SF-AUTHORING-012 / bounded SF-0508-001–008 | **Verified bounded; SF-0508 remains Partial overall** | Design Inspector resolves legacy `style.fill = surface` as a deterministic v1 default, stores authored solid fill as finite normalized RGBA numeric properties plus normalized opacity, and routes native NSColorWell/Colors-panel, hexadecimal, field, and NSStepper commits through central identity-gated existing-property transactions. Immutable viewport snapshots preserve one artboard intersection across authored pixels, selection/transform chrome, hit testing, accessibility, and Inspector geometry. Native menu, keyboard, and toolbar commands resolve through one live window-owned shell binding; host-state replacement atomically retires the old binding before the replacement is eligible. | Focused Save, geometry/Escape, and insertion/adoption journeys passed individually and together (3/3). Complete UI passed 38/38; final `./sf verify` passed 323 unit/integration + 38 UI tests (361 total), zero failures, on 2026-08-24; repository/security/traceability/architecture/migration/evidence checks passed. | Original-resolution Inspector, native Colors, stepper, save/reopen, and Grid/preset screenshots were reviewed at original resolution; see `docs/evidence/SF-AUTHORING-012-DESIGN-INSPECTOR.md`. | Layered fills, gradients, images, borders, shadows, typography, tokens, broad color-management, responsive overrides, preview/export parity, OS-level VoiceOver/settings acceptance, performance budgets, and release acceptance remain deferred. |
| SF-AUTHORING-011 / bounded SF-0403-001–008; partial foundation toward SF-0505-002, 004–006, 008 | Verified (fixed Layout Inspector geometry); SF-0403/SF-0505 remain Partial overall | Native X/Y/Width/Height fields keep locale-formatted incomplete input in scene-local draft state and invoke `GeometryInspectorCommandRegistry` only at Return or focus-loss. The registry scopes document/page/revision/scene/renderer/selection identity, validates finite bounded values plus width/height minimums, locks/hidden/unavailable state, and Frame/Text/Section/Stack/Grid applicability, then prepares one canonical existing-property batch and exact inverse. Mixed and inapplicable subsets are explicit. Inspector diagnostics use a dedicated redacted operation type. | `TransformModelTests` adds atomic multi-target, stale/invalid/cancel-neutral, supported-kind/subset, persistence/undo/redo, locale parsing, and diagnostic-redaction coverage (16 focused tests passed). The actual-app geometry journey covers pointer, Return, focus-loss, Escape, undo/redo, accessibility field labels/values, and retained screenshot attachment. `./sf test half` passed 306/306; final `./sf verify` passed 306 unit/integration + 33 UI, zero failures, with repository/security/traceability/architecture/migration/evidence/fixture checks. | Retained XCTest attachment `SF-AUTHORING-011 fixed geometry fields` was reviewed for readable native fields, selected-object geometry, normal maximized-window composition, and contrast; see `docs/evidence/SF-AUTHORING-011-LAYOUT-INSPECTOR.md`. | No responsive overrides, sizing modes, min/max constraint UI, aspect ratio, automatic sizing, rotation/skew, rich text, broad property editing, OS-level VoiceOver/settings, cross-hardware budgets, export, publishing, or release acceptance. |
| SF-CANVAS-VISUAL-001 / bounded SF-0401-001, 003, 005; SF-0405-006; SF-0406-001, 002, 006, 008; SF-1902-008 | Verified | Fresh/adopted workspace centering is noncanonical and waits for usable AppKit viewport geometry; it retains 100% zoom and preserves authored coordinates. The blank-state card is centered and non-hit-testable. `CanvasTextLayout` is shared by committed tile text and `NSTextView`, retaining one top-left/Y-down object rect and tile-only Y conversion. | Text-layout matrix covers 25/100/800% zoom, 1×/2× scale, positive/negative origins, glyph containment/vertical centering, and tile conversion. Viewport-center plus actual native-canvas and inline text journeys passed; local and hosted `./sf verify` passed 303 unit/integration + 33 UI tests. | Owner-provided screenshots were inspected and showed the former top-pinned empty state and text/selection mismatch; retained XCTest window screenshots cover native text draft/commit/cancel after the shared contract. | Hosted Actions `31675543875` passed at `f449813`. Production typography, OS-level settings, cross-hardware visual inspection, export, and release acceptance remain Partial. |
| SF-CI-007 / bounded SF-0201-006, 008; SF-0203-006; SF-0406-006; SF-1902-008 | Verified | Explicit constrained Debug/UI-test placement preserves the 1100-point product width, fits titled height within both vertical safe edges, and independently aligns left/right and top/bottom; its launch and workspace surfaces share the same constrained minimum. The bottom text pointer journey requests right/bottom. Generic UI tests, production, and Release retain their existing presentation policies. `sf` owns a deterministic result-root policy (project override, then Actions runner temporary root, then local TMPDIR), and CI uploads both matching `.xcresult` and log. | Hosted run `31671468329` isolated a Commit control below the lower inset. Run `31673619911` then proved the welcome surface retained a 700-point SwiftUI minimum and prevented the requested fitted frame after workspace adoption. The focused bottom journey and final local/hosted `./sf verify` passed: 303 unit/integration + 33 UI tests on 2026-08-13. | Hosted attachments recorded the 1100-point right/bottom window and the real Commit button below the safe inset; local policy and actual-pointer diagnostics prove the launch/window surfaces permit the requested fitted height, preserve width, and expose both safe edges. Deterministic result-root evidence confirms matching `.xcresult` and log ownership. | Hosted Actions `31675543875` passed at `f449813`. This changes only explicit Debug/UI-test placement and failure-artifact retention, not production sizing or command behavior. |
| SF-AUTHORING-010 / bounded SF-0405-001–008; SF-0501-001–008; SF-0502-001–008; SF-0503-001–008 | Verified (structural Elements foundation); all listed normative modules remain Partial overall | Schema-v4 canonical `section`, `stack`, and `grid` nodes have stable IDs, explicit `.defaulted` v1 properties, strict validation, ordered ownership, schema-v3 compatibility decoding, and one existing insertion/transaction/history/persistence path. The shared resolver supplies Stack/Grid geometry to renderer, selection overlays, hit testing, Layers, and Inspector; Elements/Insert expose real accessible commands. | Focused schema/default/migration tests 3/3; actual-app structural catalog/Insert-menu nested journey 1/1; focused inline-text regression 1/1; `./sf test half` 301/301; final `./sf verify` on 2026-08-12 passed 301 unit/integration + 33 UI tests, zero failures, plus repository/security/traceability/architecture/migration/evidence/fixture checks. | Retained XCTest screenshots cover blank canvas, Section/Stack/Grid, nested structural insertion, and undo/redo. `docs/evidence/structural-elements-foundation/` retains raw 100/10,000 samples, environment, memory, methodology, and limitations. | No property editor, automatic sizing, broad CSS parity, responsive overrides, other Element behavior, production typography, OS-level VoiceOver/settings, cross-hardware budgets, export, publishing, or release acceptance. Large full layout/render samples exceed one 60 Hz frame. |
| SF-AUTHORING-009 / bounded SF-0408-001–008 | Verified (bounded local drag foundation); SF-0408 remains Partial overall | Canonical `document.node.move` reuses the sole ordered parent/child model and has one atomic inverse. A Foundation-only registry/session scopes source/destination/insertion/document/page/revision/scene/renderer identity; validates same-page source, frame-only containers, availability, locked/hidden state, insertion index, cycle/depth, lifecycle, cancellation, stale work, and revision exhaustion. The source-level Layers pointer capability implements bounded same-page “before row” placement, including compatible cross-parent placement. Contextual controls, named accessibility actions, and automation route supported reorder/nesting through the registry. An explicitly declared internal UTI prevents generic text/Finder payloads from becoming a move; indicators, payloads, hover, and session state are noncanonical. | Focused behavioral tests cover same-parent adjustment, pointer cross-parent capability, invalid-hover repair, malformed parent-cycle rejection, cross-parent nesting, cycle/depth/stale/locked/unavailable/cancel neutral rejection, exact inverse/history/serialization/session exclusion, all six registry provenances/payload-free diagnostic redaction, unavailable accessibility feedback, and measured 100/10,000-node preparation. `scripts/check-drag-drop-foundation-evidence.py` validates raw local evidence and `scripts/check-architecture-boundaries.py` headlessly type-checks the registry with no UI imports. The checkpoint's complete UI target passed 29/29 and `./sf verify` passed 248 unit + 29 UI tests on 2026-07-31; the final audit gate is recorded separately. | Reviewed retained native Layers contextual reorder/undo/redo screenshot: stable Layer identities and selection, authored canvas, empty inspector, status state, and chrome were readable with no clipping. Retained UI evidence does not claim an XCTest-driven native drag gesture, native pointer nesting, or terminal cleanup for a drag outside every row. | Production keyboard/application-menu drag commands, end-to-end native pointer terminal cleanup, native pointer nesting, external/Finder drags, assets, cross-window/project transfer, components, responsive editing, export, broad autoscroll, OS-level VoiceOver/settings, incremental indexing, cross-hardware budgets, and release acceptance remain excluded or unproven. |
| SF-CI-006 / bounded SF-0201-006, 008; SF-0203-006, 008; SF-0405-006, 008; SF-0406-006; SF-1902-008 | Verified | Independent horizontal/vertical Debug UI-test placement; window-local AppKit frame coordinator with coalesced exact-window observers and deterministic teardown; requested frame derived from 1100×700 content plus bound-window chrome rather than constrained screen geometry; every explicit Debug/UI-test placement fits vertically before applying its safe edge; runtime tests derive their minimum expected automation frame from the native visible screen; unchanged Release/non-test behavior; dedicated real pointer journeys and sanitized diagnostics | Native-screen minimum and large-fixture journeys 6/6 across three fresh processes; complete UI target 28/28; authoritative local `./sf verify` 242 unit + 28 UI with every repository gate green; hosted Actions `30599626407` passed the complete macOS 26.4/Xcode 26.5 Verify job at `94a372b`. | `30581883646` isolated unfitted top placement. `30584649437` passed every Layers/material regression and isolated the two obsolete literal 700-point automation-frame assertions. `30599626407` passed the corrected complete gate and skipped failure diagnostics. | Production 1100×700 and Release composition are unchanged and remain directly unit-tested. The completed SF-AUTHORING-009 slice leaves no next feature item ready. |
| SF-AUTHORING-008 / bounded SF-0406-001–008 | Verified (inline plain-text editing foundation); SF-0406 remains Partial overall | Foundation-only typed text-edit registry; exact document/page/revision/renderer/session/node identities; existing versioned `content.text` property as the sole canonical source; scene-owned inactive/drafting/previewing/composing/committing/cancelled/failed state; native `NSTextView` caret, selection, multiline, clipboard, and marked-text semantics; shared pointer/keyboard/menu/contextual/accessibility/automation activation; one transaction/inverse; selection/Layers/layout/renderer/hit-test/dirty-region/package/history/autosave/recovery adoption; redacted diagnostics | Thirteen focused unit/integration tests cover session/range/composition/identity gates, limits, typed rejection, cancellation, all provenances, exact history/package round trips, node removal, shortcut routing, native clipboard behavior, capacity, and redaction; one actual-app editing/commit/cancel/undo/redo/clipboard/accessibility journey; headless import and editor-state nonserialization checks; retained two-measurement evidence validator; `./sf build`, full `./sf test`, and authoritative `./sf verify` passed with 241 unit + 27 UI tests and zero failures | Inspected retained native-window screenshots for the active draft editor and status actions, committed authored text with selection overlay, and the cancelled state; the cancellation screenshot was captured before the authored layer visibly repainted, while exact restoration is proven by reopening the editor in the same UI journey | Draft, caret/range, marked text, clipboard state, and editor overlays are noncanonical. Rich-text spans/range styling, font management, production shaping/typography, advanced paragraph layout, vertical/path text, responsive overrides, collaboration, export generation, OS-level IME/VoiceOver/settings, localization, incremental performance, cross-hardware budgets, and release acceptance remain unproven. Debug-test preparation P95: 0.819/2.419 ms at 100/10,000 objects; 108,314,624-byte resident high water. |
| SF-AUTHORING-007 / bounded SF-0404-001–008 | Verified (snapping/guide foundation); SF-0404 remains Partial overall | Foundation-only deterministic snap resolver over the existing transform draft; 6/9-point entry/exit hysteresis; authored-guide → edge → center priority; independent axes and stable tie-breaking; zoom-aware suppression/eligibility; canonical schema-v3 page-owned `GuideID` state; typed atomic add/move/remove commands; native rulers, smart guides, measurements, accessibility alternatives, and bounded editor-overlay invalidation | Six focused unit/integration tests cover resolution, priority/ties/hysteresis, zoom, suppression, cancellation/stale neutrality, eligibility, all command provenances, exact inverses/history/package round trips, strict schema-v3 decode/schema-v2 migration, preview/commit parity, bounded scale, and redaction; one actual-app ruler/guide/suppression/accessibility journey; headless import and editor-state non-serialization checks; `./sf build`, full `./sf test`, and authoritative `./sf verify` passed with 228 unit + 26 UI tests and zero failures | Inspected retained dark-appearance window screenshots for native horizontal/vertical rulers, a selected authored guide with aligned inspector/status state, and explicit suppression; no clipping or unrelated desktop/private content was present | Snap candidates, winners, measurements, ruler interaction, and previews are noncanonical. Only authored guides persist. Baseline/glyph snapping, distribution, rotation/skew, breakpoints, export, final spatial indexing/frame pacing, OS-level VoiceOver/settings, localization, cross-hardware budgets, and release acceptance remain unproven. Resolver P95: 0.972/40.341 ms at 100/10,000 objects; 109,428,736-byte resident high water; the large full-scan result is not a 60 Hz pass. |
| SF-AUTHORING-006 / bounded SF-0403-001–008 | Verified (move/resize transform foundation); SF-0403 remains Partial overall | Foundation-only typed transform registry; exact session/document/page/revision/scene/generation identities; canonical `layout.x/y/width/height` mutation only; scene-owned noncanonical draft/preview/commit state; exact move/eight-handle resize and axis constraints; compatible ordered multiple move with explicit multiple-resize/incompatible rejection; native accessible handles; unified pointer/keyboard/menu/contextual/numeric/accessibility/automation adapters; one transaction/inverse; selection/Layers/layout/renderer/hit-test/dirty-region/package/history integration; redacted diagnostics | Thirteen focused unit/integration tests; one actual-app pointer resize/move, keyboard/numeric, cancellation/Escape, undo/redo, focus/accessibility journey; headless import/typecheck and non-`Codable` enforcement; deterministic package/history/schema-v1 regressions; retained two-measurement evidence validator; `./sf build` and full `./sf test` passed, with the authoritative `./sf verify` total recorded in project status | Inspected retained pointer-resize, numeric move/resize, pointer-move, and cancelled-scope screenshots for visible native handles, aligned geometry, synchronized shell state, focus, and panel layout | This slice originally used schema v2; current packages write schema v3, whose schema-v2 adapter adds only an empty guide collection. Rotation/skew, rich-text transforms, responsive breakpoint editing, broad inspector property editing, export generation, large simultaneous selection, OS-level VoiceOver/settings, incremental performance, and OD-001 budgets remain later. P95 prepare: 0.629/28.493 ms at 100/10,000 objects; 110,804,992-byte resident high water; the large result is not a 60 Hz pass. |
| SF-CI-005 / bounded SF-0201-006, 008; SF-0203-006, 008; SF-0602-006; SF-1902-006, 008 | Verified | Scene-owned/window-bound AppKit local Tab router; unchanged central `ShellFocusTraversal`; genuine first-responder transfer into/out of the native preset; wrong/inactive/stale window, sheet, menu, text-editing, missing-focus, detached, and non-boundary pass-through; deterministic monitor teardown; Debug/UI-test-only redacted responder diagnostics | 12/12 focused focus/control unit tests; unchanged traversal 10/10 with per-repetition app relaunch; viewport pointer/keyboard/accessibility journey passed; complete UI target 24/24; final local `./sf verify` ran 209 unit + 24 UI tests with zero failures; hosted Actions `30215756810` passed the complete Xcode 26.5 gate at `a1328ea` on 2026-07-26 | Actions `30213209340` showed the original wrap to Pages. Actions `30214993143` proved both corrected mixed boundaries and exposed only a later offscreen Inspector pointer dependency; the final journey keyboard-traverses and asserts Layout, Style, Advanced, and Accessibility | No sleep, retry, synthetic repeated Tab, layout change, assertion weakening, or Release automation behavior was added. |
| SF-CI-004 / bounded SF-0201-006, 008; SF-0203-006, 008; SF-0602-006; SF-1902-006, 008 | Verified | Native `NSPopUpButton` viewport preset; canonical preset binding remains in `WorkspaceShellState`; typed scene/window/request focus gate; synchronous real first-responder adoption; focus-loss non-reclamation; bidirectional `ShellFocus`; native pointer and Up/Down keyboard selection; unchanged Tab/Shift-Tab traversal and accessibility contract | 3/3 focused unit tests; final implementation 10/10 consecutive complete forward/reverse focus journeys; focused viewport pointer/keyboard/accessibility journey passed; complete UI target 24/24; final `./sf verify` ran 206 unit + 24 UI tests with zero failures on 2026-07-26 | Reviewed supplied hosted Xcode 26.5 evidence: Not Found was the last confirmed focused control and the SwiftUI menu existed without adopting the AppKit first responder; reviewed the native popup at the unchanged workspace dimensions | No Debug-only behavior, synthetic Tab, sleep, layout change, or test weakening was added. A fresh hosted execution of the committed correction remains the CI-only confirmation. |
| SF-CI-003 / bounded SF-0201-006, 008; SF-0203-006, 008; SF-0405-006, 008; SF-0602-006; SF-1902-006, 008 | Verified | Production keyboard Undo/Redo in generic insertion journeys; dedicated right-aligned toolbar-history pointer journey; native SwiftUI viewport-preset menu in the scene-owned focus chain; explicit native-canvas Tab handoff; actual AX-focus predicates; expected/current identifier, redacted hierarchy, and screenshot failure attachments | Both formerly failing UI journeys passed 10/10 across five consecutive iterations; complete UI target passed 24/24; final `./sf verify` ran 203 unit + 24 UI tests with zero failures on 2026-07-26 | Reviewed supplied hosted Xcode 26.5 diagnostics showing the offscreen Redo frame and Not Found retaining focus; reviewed local full forward/reverse focus and right-edge control geometry | Production 1100×700 minimum and toolbar layout are unchanged. Release automation isolation remains enforced. A fresh hosted Xcode 26.5 run is the remaining CI-only confirmation. |
| SF-CI-002 / bounded SF-0201-006, 008; SF-0203-006, 008; SF-1505-006, 008; SF-1602-006, 008; SF-1605-006, 008; SF-1902-006, 008 | Verified | Accessible `workspace.shell` readiness boundary; post-welcome app reactivation and bounded window/shell predicates; failure screenshot plus path-redacted hierarchy; Debug/UI-test-only left/right alignment that preserves 1100×700; Release argument isolation; Preview-specific keyboard/accessibility/presentation and pointer coverage; upload-artifact v5 | Supplied Actions run showed 202/202 unit tests passing and fourteen UI failures at one offscreen Preview gate; 13 focused composition/material tests passed; sixteen affected/focused UI journeys passed 48/48 across three consecutive runs without sleeps; final `./sf verify` ran 203 unit + 23 UI tests with zero failures on 2026-07-26 | Reviewed the supplied verify log and `.xcresult`, including the shared failure lines and 1100-point window on an approximately 1024-point test display | Production minimum and toolbar layout are unchanged. Generic tests no longer require Preview pointer visibility; Release ignores geometry arguments. A fresh hosted Actions execution of the committed correction remains CI-only confirmation. |
| SF-TOOLING-001 / bounded SF-1902-007, SF-1902-008 | Verified (local workflow) | `./sf test quick\|changed\|half\|full`; conservative subsystem selector; unknown/cross-cutting full fallback; full-only verify/CI gate; documented level semantics | Selector self-tests plus successful quick, half, and full verification runs on 2026-07-26; authoritative `./sf verify` ran 202 unit + 21 UI tests with zero failures | Reviewed command help, invalid-level behavior, changed-scope escalation, and the final diff | Changed selection is file/subsystem based, not Swift-AST function analysis. Narrow levels are local feedback only and never completion evidence. |
| SF-CI-001 / bounded SF-0201-006, 008; SF-0203-006, 008; SF-1505-006, 008; SF-1602-006, 008; SF-1605-006, 008; SF-1902-006, 008 | Verified | Stable state-specific launch acknowledgements; accessible static Reduce Motion progress; predicate-bound focus/hittability; deterministic UI-app teardown; visible-screen-clamped Debug-only test window; Release injection isolation; checkout v5 and failure-only log/xcresult retention | Exact five GitHub-runner failures passed locally before correction, then 15/15 across three consecutive focused runs without sleeps; `./sf build`, `./sf test`, and `./sf verify` (202 unit + 21 UI, 0 failures) on 2026-07-26 | Reviewed the supplied Actions log and exact failing assertions/frames; retained XCTest results from three focused repetitions | This fixes runner-sensitive synchronization and observability without weakening behavior. OS-level VoiceOver speech and release signing remain outside this correction. |
| SF-AUTHORING-005 / bounded SF-0405-001–008 | Verified (frame/plain-text insertion foundation); SF-0405 remains Partial overall | Foundation-only typed insertion registry; stable-ID frame/text canonical nodes originally introduced in schema v2; explicit ownership/order/kind/default provenance; exact identity/revision/generation validation; one transaction and inverse; scene-owned noncanonical insertion session; pointer/keyboard/menu/contextual/accessibility/automation adapters; post-commit selection; Layers/layout/renderer/hit-test/package/history integration; redacted diagnostics; iterative set-backed graph validation | `./sf build`, `./sf test`, and `./sf verify` (202 unit + 21 UI, 0 failures) on 2026-07-21; 11 focused unit/integration tests; one actual-app insertion/cancellation/undo/redo UI journey; headless import/typecheck and non-`Codable` enforcement; retained six-measurement evidence validator | Inspected retained running-app inserted-frame, inserted-text, and cancelled-preview screenshots in the XCTest result; stable Layers identity and selection state remained visible | Defaults: frame 240×160; bounded plain text `Text` at 120×24; all `.defaulted`. Current schema v4 preserves them; schema-v3 remains readable, schema-v2 adds only empty guides, and schema-v1 migration remains supported. Drag creation, shaping/rich text, transforms/handles, snapping/guides, media/components, inspector editing, export generation, incremental indexes, OS-level VoiceOver/settings, and release budgets remain later. P95 command/layout/render: 0.756/0.897/1.289 ms at 100 and 44.961/68.002/93.654 ms at 10,000 objects; large layout/render results are not a 60 Hz pass. |
| SF-AUTHORING-004 / bounded SF-0402-001–008 | Verified (selection-model foundation); SF-0402 remains Partial overall | Foundation-only scene/window selection snapshot and typed registry; ordered stable `NodeID` identities, primary/anchor, page/container scope, provenance; reverse-paint pointer hit testing; deterministic lifecycle repair; noncanonical/undo-neutral state; editor-only overlay planner with old/new dirty regions; Layers/inspector/status/menu/contextual/keyboard/accessibility adapters; redacted diagnostics | `./sf build`, `./sf test`, and `./sf verify` (191 unit + 20 UI, 0 failures) on 2026-07-21; 8 focused unit tests; actual-app empty/single/multiple UI journey; headless import/typecheck and non-`Codable` enforcement; retained four-measurement evidence validator | Inspected cropped empty, single, and multiple screenshots on Mac16,13 / macOS 27.0 build 26A5378n in dark appearance: stable Layers rows, primary/secondary aligned outlines, inspector summaries, status counts, no overlap | Selection is intentionally excluded from canonical serialization, package/autosave/recovery/history, preview, and export boundaries. Marquee, component drill-in UI, insertion, transforms/handles, snapping/guides, inspector editing, shaping/decoding, export generation, incremental indexes, interactive Instruments, OS-level VoiceOver/settings acceptance, and OD-001 budgets remain later. Command P95: 0.073/3.803 ms; overlay P95: 0.014/0.958 ms at 100/10,000 objects. |
| SF-AUTHORING-003 / bounded SF-0407-001–008 | Verified (native renderer foundation); SF-0407 remains Partial overall | Foundation-only immutable scene/plan contract; exact six-dimension adoption identity; deterministic paint/clip/visibility/hit-test; bounded tile/cache/accessibility policy with deterministic focus repair; dirty regions and compositor-only viewport updates; AppKit/Core Animation authored/overlay trees; overlay-free preview adapter; cancellation/failure preservation; signposts and redacted diagnostics | `./sf build`, `./sf test`, `./sf verify` (183 unit + 19 UI, 0 failures) on 2026-07-21; 11 focused unit tests; actual-app UI journey; headless typecheck; retained schema-v1 evidence validator | Inspected and retained the default Retina/dark workspace with rendered blank-project roots, readable native chrome, focus ring, and canvas input; manifest truthfully distinguishes other automated appearance/scale regressions | Canonical render-pass commands/persistence/history, selection/editing, text/image/effects, export generation, offscreen accessibility navigation, interactive Instruments evidence, Metal, and OD-001 budgets remain later work. Full/dirty 10,000-object planning P95 was 75.980/113.634 ms and is not a frame-budget pass. |
| SF-AUTHORING-002 / bounded SF-0501-001–008 | Verified (layout-engine foundation); SF-0501 remains Partial overall | Foundation-only versioned layout snapshots keyed by `NodeID`; deterministic fixed/intrinsic/fill and stack solver; min/max provenance; bounded graph/value validation; immutable document/revision/generation/viewport-tagged results; actor worker; cancellation/stale gate; redacted diagnostics; isolated HTML/CSS oracle adapter | `./sf build`, `./sf test`, and `./sf verify` (172 unit + 18 UI, 0 failures) on 2026-07-21; 11 focused layout tests; headless import/typecheck enforcement; retained schema-v1 evidence validator | Reviewed retained Mac16,13/macOS 27.0 environment, methodology, raw timing/memory samples, exact WebKit geometry parity at 320/768/1,440 and 100/10,000 nodes, and stated limitations | Supported: fixed/intrinsic/fill, min/max, padding, gap, start/center/end/stretch, horizontal/vertical stacks, nesting, visible/clip overflow, responsive width. Typed unsupported: percentage/automatic, baseline, scroll overflow, missing axis, shaping/fallback and broader CSS. Canonical property commands/persistence, inspector/accessibility UI, renderer, production text shaping, incremental layout, preview/export UI, and release hardware budgets remain later work. The 10,000-node production P95 was 22.290 ms and is not a 60 Hz or release-budget pass. |
| SF-AUTHORING-001 / bounded SF-0401-001–008 | Verified (viewport foundation); SF-0401 remains Partial overall | Phantom-typed Foundation world/viewport/device geometry; deterministic precision/clamp/overflow rules; scene-owned viewport; AppKit input/focus/accessibility surface; typed commands; actor scene preparation with document/revision/scene/generation adoption gate | `./sf verify` (161 unit + 18 UI, 0 failures) on 2026-07-21; 11 focused coordinate/viewport tests; native UI command/focus/accessibility coverage; headless import/typecheck enforcement | Inspected default/minimum windows, 100%/125% zoom, +626.4/-1958 world-origin pan, light/dark, Retina, Reduce Motion, and active/inactive policy states on Mac16,13 / macOS 27.0 build 26A5378n | Viewport state is deliberately noncanonical and nonpersistent. Canonical authored world-point creation/removal, real layout/rendering, selection/fit-selection, overlays, export parity, release hardware budgets, and OS-level VoiceOver speech remain later work. |
| SF-AUTHORING-000 / M0-P1-07 / SF-1901-001–008; bounded SF-0401, SF-0407, SF-0501, SF-1903 evidence | Verified (architecture runway only) | Isolated Foundation coordinate/layout core and HTML/CSS adapter; native SwiftUI/AppKit/Core Animation/Metal/WebKit harness; production resource-store fixture; accepted ADR-0013 and ADR-0014 | `./sf verify` (150 unit + 17 UI, 0 failures) on 2026-07-21; five focused runway unit tests; 25 retained raw measurement series plus correctness, environment, memory, resource, and limitation records; repository checks validate evidence shape and prototype isolation | Reviewed named-host methodology, raw samples, alternatives, stalls, sequential-memory limitation, browser parity, unsupported cases, and recommendation boundaries | Fixes M0-P1-07 and resolves OD-004/OD-011. This does not mark the production canvas, layout engine, preview, export, or release budgets complete; those remain Partial and are queued as SF-AUTHORING-001–003. |
| SF-CORRECTION-008 / M0-P2-03, 08, 11, 12; M0-P3-01–02 / listed bounded accessibility, navigator, resource, hygiene, and performance-prerequisite requirements | Verified (bounded audit correction) | Deterministic bidirectional pane focus; PageID-derived navigator identifiers; singular native Open adapter; redacting tested repository scanner; versioned resource index and bounded content-addressed resource store; centralized repository fixture allocator/cleanup | `./sf verify` (145 unit + 17 UI, 0 failures) on 2026-07-19; 7 resource tests including 500 non-empty assets and restrictive metadata; stable-identity and focus unit/UI tests; 8 seeded scanner pattern detections plus 4 sensitive-name policies with zero negative/repository findings; architecture/fixture checks | Retained accessibility manifest records the actual host, OS settings, states, observations, and limitations; no VoiceOver speech or actual OS-setting exercise is claimed | Fixes all six residual findings. Full renderer/object/asset performance remains Partial for `SF-AUTHORING-000`; logical sidecar move/copy UI remains downstream asset-authoring integration. ADR-0012 records version and limits. |
| SF-CORRECTION-007 / M0-P2-06–07 / SF-1801-001–004, 008; SF-1802-008 | Verified (bounded architecture correction) | Scene-owned `WorkspaceDocumentContext`; focused-window command routing; centralized Debug-only composition seam; headless canonical-model and command/persistence source slices; repository dependency enforcement | `./sf verify` (136 unit + 16 UI, 0 failures) on 2026-07-19; three ownership/composition tests; headless Swift 6 type-check and forbidden-import/ownership checks on every verification | Reviewed app lifetime, focused command routing, Release-default composition behavior, source-slice imports, target membership, and complete diff | Fixes M0-P2-06 and M0-P2-07. Full SF-1801 module-authoring behavior and signed CI/release acceptance remain explicitly outside this bounded boundary correction. ADR-0011 records the decision. |
| SF-CORRECTION-006 / M0-P1-08–10; M0-P2-01–03, 09, 13 / listed bounded SF-0201, SF-0301, SF-0303, SF-1505, SF-1602, SF-1605, SF-1902, SF-2002 requirements | Verified (bounded evidence correction) | Canonical decision namespace; strict bounded evidence index/lint; cooperative package/canonical/history cancellation; recovery-operation diagnostics; retained visual/performance methodology; real production-loader UI journeys; injectable native accessibility announcements | `./sf verify` (133 unit + 16 UI, 0 failures) on 2026-07-19; barrier cancellation, diagnostic, announcement, real open/malformed-Retry, and real recovery Restore/Discard tests | Retained environment/settings/fixture inspection manifest distinguishes manual evidence from UI preview fixtures | Fixes M0-P1-08–10, M0-P2-01, M0-P2-02, M0-P2-09, and M0-P2-13. M0-P2-03 remains Partial for complete reverse traversal/OS-level speech evidence; the 500-asset package-capacity gap remains M0-P2-12. Both are explicitly queued in SF-CORRECTION-008. |
| SF-CORRECTION-005 / M0-P1-05, remaining M0-P1-06 / SF-1504-001–008; SF-1603-004 | Verified (bounded local slice) | Actor-isolated file-access policy; real app-scoped bookmarks, including parent-scoped new-save access; restrictive versioned bookmark registry; stale repair and relocation; balanced security scopes; `NSFileCoordinator` around actual package I/O; `NSFilePresenter` external events; unsigned sandboxed Release-candidate settings; declared project type | `./sf verify` (129 unit + 14 UI, 0 failures) on 2026-07-19; 10 focused real/injected boundary and lifecycle tests plus retained native panel, lifecycle, filesystem, keyboard, and accessibility coverage | Reviewed release build settings and entitlement/type declarations; no distribution signing or credential use; inspected source/diff for scope lifetime, coordination window, presenter cleanup, canonical preservation, redaction, paths, and generated artifacts | Fixes `M0-P1-05` and completes `M0-P1-06`. Full generated-module SF-1504 acceptance remains Implemented/Not fully Verified for future external-asset authoring, scale, undo/version comparison, and an owner-approved signed sandboxed distribution exercise. Machine-local bookmarks intentionally stay outside portable packages. ADR-0010 records the boundary. |
| SF-CORRECTION-004 / M0-P1-04, M0-P2-05 / SF-0301-004–005; SF-0303-005, 008; SF-0307-004; SF-1702-004, 008; SF-1902-004, 008 | Verified | Strict current schema-v3 decoding; isolated schema-v2 adapter for empty guides and schema-v1 adapter for deterministic empty/rootless migration; validated terminal revision plus checked transaction arithmetic; immutable package-v1/schema-v1 goldens | `./sf verify` (119 unit + 14 UI, 0 failures) on 2026-07-19; 5 focused strict-schema/revision/golden tests plus retained package/lifecycle/history rejection coverage | Reviewed the schema dispatch, canonical validation/adoption boundary, typed error path, fixture provenance/checksums, deterministic identities, history isolation, and diff scope | Current schema never invokes compatibility defaults. ADR-0009 records the boundary; ADR-0004 points blank defaults exclusively to the schema-v1 adapter. Foundation JSON decoding still collapses duplicate keys before exact-key validation, recorded in the final audit as a parser-hardening limitation. |
| SF-CORRECTION-003 / M0-P1-01, M0-P1-02, related M0-P2-04 / SF-0301-002, 004–005; SF-0306-003–005; SF-1504-004; SF-1902-004 | Verified | Typed lifecycle epochs and operation identities bind document/project/revision/destination/intent; document adoption invalidates prior work; explicit Save drains autosave; edit-during-Save retains a recoverable newer revision; stale completion is state-neutral | `./sf verify` (115 unit + 14 UI, 0 failures) on 2026-07-19; 11 injected-debouncer/barrier race tests plus wall-clock-free retained autosave/recovery integration coverage | Reviewed lifecycle and backend state gates, filesystem commit handoff, cancellation paths, exact state/disk assertions, diagnostic redaction, actor isolation, and absence of timing sleeps in autosave race coverage | Fixes `M0-P1-01`, `M0-P1-02`, and the autosave-coalescing portion of `M0-P2-04`. ADR-0008 defines the lifecycle-wide identity and explicit Save/autosave ordering boundary; ADR-0007 remains the inner filesystem guarantee. |
| SF-CORRECTION-002 / M0-P0-02–04, filesystem portion of M0-P1-06, M0-P2-10, M0-P2-14 / SF-0301-004–005; SF-0306-003–004; SF-1504-003–004; SF-1603-004; SF-1604-004; SF-1702-004 | Verified | One bounded descriptor snapshot for package bytes, SHA-256 digest, device/inode identity, and security metadata; no-follow parent/file opens; exclusive creation or identity-checked atomic swap; secure owner/mode/ACL/approved-xattr policy; app-owned recovery validation and identity-bound deletion | `./sf verify` (104 unit + 14 UI, 0 failures) on 2026-07-19; 11 new barrier-controlled adversarial tests plus retained interruption/static-symlink coverage | Reviewed the complete filesystem and lifecycle diff for conditional-commit rollback, external-byte preservation, recovery collision/deletion behavior, bounded allocation, diagnostic redaction, staging cleanup, repository paths, signing, and scope | Fixes `M0-P0-02`, `M0-P0-03`, remaining `M0-P0-04`, `M0-P2-10`, and `M0-P2-14`. The no-follow and confidentiality-metadata portion of `M0-P1-06` is fixed; sandbox security scopes/bookmarks/file coordination remain in `SF-CORRECTION-005`. ADR-0007 defines the bounded guarantee. |
| SF-CORRECTION-001 / M0-P0-01, M0-P1-03 / SF-0203-004–006; SF-0301-004–006; SF-0306-004–006; SF-1902-004–006 | Verified | One asynchronous destructive-transition coordinator for New, Open, Revert, recovery Restore, and Close; injected native save destination; exact lifecycle snapshots; app-owned project-identity recovery storage; untitled recovery discovery | `./sf verify` (93 unit + 14 UI, 0 failures) on 2026-07-19; 5 focused correction tests plus one native UI journey | Inspected native Save/Discard/Cancel alert, Return default Save, Escape cancellation, save-panel cancellation, and discard-to-new flow | Resolves audit findings `M0-P0-01` and `M0-P1-03`. Failed or cancelled decisions preserve canonical document, persisted history state, project identity, URL, durable fingerprint, lifecycle phase, display name, failure, and candidate state. `SF-CORRECTION-002` now supplies the lower-level identity-bound filesystem boundary. |
| SF-FOUNDATION-001 / SF-1501-008, SF-1802-008, SF-1902-006, SF-1902-008 | Verified | `SiteForge.xcodeproj`; `SiteForge/`; `Tests/`; portable `sf` project discovery and Derived Data | `./sf build`; `./sf test` (2 unit + 1 UI, 0 failures); `./sf verify` passed in-place and from an isolated source-only copy on 2026-07-19 with Xcode 27.0 beta | Audited shared scheme, target membership, generated Info.plists, bundle identity, deployment target, paths, artifacts, and signing settings | Debug uses credential-free local ad-hoc signing so XCTest can launch; Release distribution signing is disabled. The UI smoke test covers both fresh launch and the persisted native no-window state. |
| SF-FOUNDATION-002 / SF-0201-002, SF-0201-004, SF-0201-006, SF-0201-008, SF-0203-006, SF-0203-008, SF-0602-002, SF-0602-006, SF-1902-006, SF-1902-008 | Verified | `WorkspaceShellView`; `WorkspaceShellState`; native window, toolbar and menus; navigator, viewport placeholder, inspector, and status components | `./sf build`; `./sf test` and `./sf verify` (5 unit + 3 UI, 0 failures) on 2026-07-19 | Inspected the launched shell at its default size and enforced 1100×700 minimum content size; all commands, panes, tabs, placeholders, and status content remained visible without clipping or overlap | Stable accessibility identifiers cover shell regions and commands. Selected, disabled, empty, keyboard-focus, and accessibility states are intentional. Canvas editing and real preview remain bounded placeholders for later work. |
| SF-FOUNDATION-003 / SF-0203-001, SF-0203-004, SF-0203-005, SF-0203-006, SF-0203-008; SF-0302-001, SF-0302-004, SF-0302-005, SF-0302-008; SF-0303-001; SF-0304-001, SF-0304-004; SF-0305-001; SF-0306-001, SF-0306-004, SF-0306-005, SF-0306-008; SF-0307-001, SF-0307-004, SF-0307-005, SF-0307-006, SF-0307-008; SF-1607-008; SF-1702-001, SF-1702-004, SF-1702-008; SF-1902-001, SF-1902-004, SF-1902-005, SF-1902-006, SF-1902-008 | Verified | `DocumentModel`; `DocumentSerializer`; `CommandRegistry`; `DocumentSession`; redacted command diagnostics; shell Undo/Redo binding | `./sf build`; `./sf test`; `./sf verify` (22 unit + 3 UI, 0 failures) on 2026-07-19 | Audited ownership invariants, transaction commit points, history branching, serialized output, diagnostic fields, UI/model separation, project membership, generated artifacts, paths, credentials, and signing settings | Bounded schema v1 feeds the verified package persistence layer. Native open/save/autosave/recovery and persisted history integration remain queued as `SF-FOUNDATION-005` and `006`. |
| SF-FOUNDATION-004 / SF-0301-001, SF-0301-003, SF-0301-004, SF-0301-008; SF-1702-001, SF-1702-004, SF-1702-008 | Verified | `ProjectPackage`; deterministic package codec and manifest; actor-isolated atomic store; typed errors; SHA-256 member integrity; redacted persistence diagnostics | `./sf build`; `./sf test`; `./sf verify` (35 unit + 3 UI, 0 failures) on 2026-07-19; 13 focused persistence tests | Audited staging/replacement boundaries, full-read-before-return behavior, member preservation and validation, repository-local fixture cleanup, project membership, artifacts, paths, credentials, signing, and scope | Package v1 persists the canonical schema-v1 document with stable identity and metadata. Native open/save/autosave/recovery and persisted history remain queued separately. |
| SF-FOUNDATION-005 / SF-0301-002, 004, 005, 006, 008; SF-0306-001–006, 008; SF-1504-001, 004, 006, 008 | Verified | `DocumentLifecycleController`; actor-isolated lifecycle backend; native panels and commands; durable fingerprints; coalesced recovery packages; guarded window close; redacted diagnostics | `./sf build`; `./sf test`; `./sf verify` (45 unit + 4 UI, 0 failures) on 2026-07-19; 10 focused lifecycle tests | Inspected launched shell, File commands, document status, native save panel, minimum layout, and close behavior; audited fixture cleanup, paths, signing, and history scope | Open adopts only fully validated packages. Atomic writes reuse `ProjectPackageStore`; generation and fingerprint checks prevent stale or conflicting replacement. Persisted transaction history remains queued as `SF-FOUNDATION-006`. |
| SF-FOUNDATION-006 / SF-0306-002, 004, 005, 008; SF-0307-001–006, 008 | Verified | `PersistedHistoryStore`; schema-v1 `history.json`; stable transaction metadata; inverse/revision/identity validation; bounded retention; lifecycle save/autosave/reopen/recovery integration; redacted compatibility diagnostics | `./sf build`; `./sf test`; `./sf verify` (57 unit + 4 UI, 0 failures) on 2026-07-19; 12 focused persisted-history tests | Inspected compatible reopen, redo branching, durable/recovered/discarded/incompatible boundaries through integration behavior and launched shell; audited package determinism, fixture cleanup, paths, signing, and scope | Valid compatible history restores Undo/Redo. Legacy or rejected history opens the canonical document on a clean explicit boundary. History is capped at 128 entries and 512 KiB. |
| SF-FOUNDATION-007 / SF-0301-001, 002, 005, 006, 008; SF-0303-001, 003, 005, 006, 008 | Verified (bounded blank-project slice); SF-0303-003 Partial | `BlankProjectDefaults`; canonical page routes/roles/provenance; current schema-v3 serializer with schema-v2 empty-guide and schema-v1 deterministic blank-default migrations; lifecycle clean baseline; ordered accessible Pages navigator | `./sf build`; `./sf test`; `./sf verify` (65 unit + 5 UI, 0 failures) on 2026-07-19; 8 focused new unit/integration tests plus navigator UI coverage | Inspected approved Home and Not Found rows, ordering, routes, selected state, labels, and keyboard movement; audited package/history compatibility, generated artifacts, fixtures, paths, credentials, signing, and scope | `OD-003` approved. The default route/role baseline is proven, but full SF-0303-003 route-rule provenance and explanation UI are not implemented. |
| SF-FOUNDATION-008 / SF-0201-004, 006–008; SF-0301-002, 004, 006–008; SF-1602-004, 006–008 | Verified (bounded launch/lifecycle slice); performance rows Partial | `LaunchExperienceController`; native launch/loading/recovery views; actor-backed real-stage lifecycle progress; cancellation-safe adoption; redacted launch diagnostics; accessibility announcements/focus and environment fallbacks | Unit/integration and UI evidence proves bounded state/adoption semantics; parser/history cancellation now has cooperative barrier evidence | Retained inspection is listed in `docs/evidence/MILESTONE-0-VISUAL-INSPECTION.md` | The prior 100-page single-run check is a smoke budget, not release percentile/memory proof. |
| SF-FOUNDATION-009 / SF-0201-002, 003, 006–008; SF-1505-006–008; SF-1605-002, 006–008 | Verified (workspace-material slice); SF-1505/SF-1605 Partial | `WorkspaceMaterialPolicy`; pass-through `NSVisualEffectView` surfaces; native unified toolbar/title bar; centralized accessibility/appearance/activity fallbacks; responsive canvas placeholder; standard/large fixtures | Policy and UI smoke tests prove workspace chrome only | Retained bounded inspection manifest records environment, settings, fixtures, and limitations | The 10,000-page fixture does not render 10,000 canvas objects or generated-site custom canvases. SF-1505/SF-1605 generated-site acceptance and release performance remain unimplemented. |
| SF-PRODUCT-UI-001 / bounded SF-0201-002, 003, 006, 008; SF-1505-006–008; SF-1605-002, 006–008 | Verified (visual/window foundation); normative modules remain Partial | Scene-root `WorkspaceWindowConfigurator`; normal AppKit frame autosave/restoration validation; visible-frame fallback; native unified chrome; `docs/product-ui/VISUAL_CONTRACT.md` | Focused restore/fallback, material, Release-composition, and launch/workspace accessibility tests; retained visual-review manifest | Reviewed the live normal window at usable-display size and the native launch card; evidence manifest covers launch, loading, recovery, empty/selected workspace, appearance, and constrained composition | Does not implement Elements/Assets/Components, Content/Interactions editing, gradients, responsive/CMS, export, publishing, release accessibility, or final performance acceptance. |
| SF-PRODUCT-UI-002 / bounded SF-0201-002, 006, 008; SF-0203-006; SF-1505-006–008 | Verified (truthful navigation foundation); normative modules remain Partial | Stable noncanonical `ElementCatalogItem` metadata; functional Pages/Layers; categorized Elements catalogue; Frame/plain-Text-only verified tool routing; explicit Asset/Component unavailable states; native Insert menu naming; extended deterministic scene-local focus traversal | `AppMetadataTests.testElementsCatalogIsOrderedTruthfulAndDoesNotCreateCanonicalState`; `SiteForgeLaunchTests.testProductNavigatorProvidesTruthfulElementsAssetsAndComponentsDestinations`; updated complete forward/reverse focus journey; `./sf verify` on 2026-08-10 (291 unit + 30 UI, zero failures) | `docs/evidence/product-ui-002/README.md` records reproducible Elements, Assets, Components, light/dark/reduced-transparency, and constrained-display review paths and limitations | Only Frame/plain Text may arm existing insertion. Other elements, Assets, Components, general properties, responsive behavior, export, publishing, OS-level VoiceOver/settings acceptance, and release acceptance remain unavailable or unproven. |
| SF-PRODUCT-UI-003 / bounded SF-0201-002, 003, 006, 008; SF-0203-006, 008; SF-1505-006–008 | Verified (bounded product-UI slice); normative modules remain Partial | Stable scene-local InspectorTab identity/order/availability; Design/Layout/Accessibility summaries; native unavailable Content/Interactions explanations; canonical deterministic Frame surface/border defaults; noncanonical selected Frame/dimension/parent context overlay; normal AppKit visible-frame maximized placement with valid geometry restoration and Debug/UI-test isolation; geometry-less structural roots excluded from render/selection scenes with a real empty-canvas insertion state; explicit post-transaction scene/renderer adoption for visible Frame/Text starting actions. | Focused frame/text chain regression (1 unit) plus blank/renderer, material/canvas, and selected-Frame actual-app journeys (3 UI) passed; final `./sf verify` passed on 2026-08-12 with 297 unit + 32 UI tests, zero failures, and all repository/security/traceability/architecture/migration/evidence/fixture-hygiene checks. | `docs/evidence/product-ui-003/README.md` records reproducible commands, named actual-app attachments, inspected states, and limitations. | General property editing, interaction authoring, responsive controls, effects, export, publishing, OS-level VoiceOver/settings acceptance, cross-hardware normal-window manual acceptance, and release acceptance remain outside this bounded slice. |
| Milestone 0 integrity corrections | Verified (bounded audit-correction program plus runway) | `SF-CORRECTION-001` through `008` and `SF-AUTHORING-000` have bounded verification; the final audit reconciles their evidence with subsequent schema, lifecycle, filesystem, renderer, and drag work | Historical `./sf verify` passed with 150 unit + 17 UI tests on 2026-07-21; the final audit `./sf verify` passed on 2026-08-09 with 288 unit + 29 UI tests (317 total), zero failures, and all repository/evidence checks | Complete correction/runway ledger reconciled; final diff and repository were inspected for data loss, credentials, artifacts, machine paths, signing, publication, fixture residue, evidence overclaim, and unrelated work | This closes the bounded audit program, not the unbuilt authoring engine or release-level generated-site acceptance. The macOS final-syscall and trusted artifact-reclamation boundary is OD-014; no next feature item is ready. |

Allowed statuses: Not started, In progress, Implemented, Verified, Blocked, Deferred, Superseded.

A requirement may be marked Verified only when its acceptance evidence passes for the named build and environment.
