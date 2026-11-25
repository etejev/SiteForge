# Interactive gradients, flexible footer and redesigned showcase

## Owner authorization and scope

The owner requests a flowing gradient that follows mouse direction, with editable
pull radius, speed and related adjustments; footer sections such as About Us and
Contact Us with links/addresses, or a large QR code; and a full redesign of the
test website using modern glass surfaces, interactive design, dark-friendly
styling and flexible responsive layout. They also request a commit afterward.

This extends the active FAST_STYLE_AUTHORING assignment. Finish or stabilize its
current owned verification before moving to dependent changes. Preserve its
native sliders, live previews, gradient geometry fix, history semantics and app
appearance. Do not interrupt a running collector or combine its frozen receipt
with later changed source. Add these dependent slices to the queue and continue
through implementation, acceptance, installation and a verified local commit.

The commit is explicitly owner-authorized. Repository instructions reserve all
GitHub authentication, pushes, PRs and releases for the owner. Make the local
commit only after the final gate passes; do not push or publish.

## Requirements and architecture

Read AGENTS.md, relevant specification sections and approved ADRs before editing.
Map delivered behavior to the exact applicable requirements in these modules:

- SF-0508-001–008: typed color/fill/effect authoring and resolution.
- SF-1101-001–008 and SF-1103-001–008: bounded pointer interaction and animation.
- SF-1201-001–008 and SF-1204-003/004: isolated preview and generated output.
- SF-0502-001–008, SF-0602-001–008, SF-0604-001–008: responsive flex/stack behavior.
- SF-0304/SF-0305/SF-0306 and SF-0701: node ownership, properties, history,
  persistence and native authoring controls, using applicable exact IDs.
- SF-0802/SF-0806, SF-1102 and SF-1206: image resources, safe links/navigation
  and packaged assets, using applicable exact IDs for QR/footer work.
- SF-0204: a genuinely editable bundled example, using applicable exact IDs.

These are bounded implementation slices, not claims that whole modules are done.
Read ADR-0013, ADR-0014 and ADR-0020. Keep canonical authoring native and typed;
WebKit remains an isolated preview/output adapter. Do not replace the editor
renderer or canonical layout engine with a web app. Ordinary reversible local
implementation choices are authorized. Record a new ADR for consequential
extensions. If a genuine unresolved ownership/migration/architecture decision
arises, document the exact dependency and continue independent authorized work.

## 1. Authorable mouse-reactive flowing gradient

Add an explicit opt-in effect on a supported gradient-filled Frame/Section or
page background. Preserve plain solid/linear fills as defaults. This must be an
authorable feature that works in website preview and exported output, not an
editor cursor decoration or a one-off script embedded only in the sample.

The gradient should deform/pull locally in the direction of cursor movement and
ease smoothly toward its resting shape. A colored circle merely following the
mouse does not satisfy flowing-gradient acceptance. Prefer a bounded local field
deformation over introducing a full fluid-simulation framework. State the actual
effect semantics and confirm them in a visual acceptance capture.

Expose a compact native effect section with Enable, pull radius, pull strength,
follow speed/response, return smoothing/easing and Reset. Give clear units and
concise labels/help distinguishing speed from damping. Use native sliders with
precise numeric fields, useful validated ranges and truthful mixed/unavailable
states. Configuration belongs to the selected website object/page, not global app
preferences. Preserve canonical gradient colors and alpha. Pointer locations,
velocity, deformation/time samples and rendered frames are transient runtime
state, never document revisions or persisted mouse trails.

Use the existing typed model/command/versioning discipline. Each configuration
edit must support owned live preview, cancellation, one undo per gesture,
save/reopen, duplication and appropriate copy/reuse without changing other fills.
Default-absent old projects must reopen unchanged. Use a backward-compatible
optional model extension where appropriate; do not bypass validation or invent
an irreversible migration. Finite values, ranges, missing targets and unsupported
kinds need explicit behavior.

Use local element coordinates and elapsed time, with correct resize/scroll/zoom
handling. Avoid frame-rate-dependent motion. Handle pointer entry, fast motion,
leave, lost capture and page navigation without snapping or retaining stale
state. The decorative layer must not intercept links, selection, scroll, keyboard
focus or pointer input intended for real content. Normal editing must remain
stable; activation of animation belongs in a clearly labeled live-preview mode
or the existing isolated website preview. Do not wire global mouse tracking into
the ordinary native edit canvas.

Produce one SiteForge-owned runtime from validated typed configuration. Reuse
the same configuration and behavior for isolated preview and output; avoid two
unrelated implementations. Bundle all required assets/runtime locally with no
CDN, remote service or added account. Preserve URL validation, escaping, resource
policy and CSP. User text/URLs must not become executable code; do not add a raw
JavaScript/CSS editor as a shortcut.

Coalesce input into at most one pending animation frame, avoid per-frame layout
thrash and document commits, and stop work when disabled, settled, offscreen,
backgrounded or disposed. Cap resource size/update work and measure real runtime
cost on this Mac. Honor reduced motion with a useful static-gradient fallback;
touch/no-hover users also get a complete static design. JavaScript-disabled and
unsupported-feature output must retain a good-looking static gradient, readable
content and functional links. Expose no unsupported animation as a successful
static-export parity claim.

## 2. Flexible editable footer content

Inspect existing Header/Footer content ownership, unique page anchors, connected
flow and reusable-copy paths. The current footer must accept ordinary editable
content groups instead of restricting users to one title/navigation row.

Make it straightforward to add a footer column/group containing a heading and
editable links, text/contact/address lines, or an image/QR. Use native insertion
and inspector controls with sensible defaults and visible placement. About Us
and Contact Us are editable starting groups, not immutable magic roles. Users
must be able to add, rename, reorder, duplicate and delete groups and items, edit
their destinations, and adjust gap/alignment/width using real layout controls.

Represent groups with normal canonical containers and content nodes. Keep one
semantic footer page anchor; groups are not extra page-level footers. Preserve
stable IDs, parent/child integrity and link targets; make compound insertion and
duplication transactional. Header/Footer copy-to-pages should preserve nested
groups and resources through the established ownership policy, without silently
creating new live component/slot ownership rules or overwriting existing chrome.

Use actual responsive stack/flex constraints: multiple columns at desktop widths,
wrapping/stacking at narrower widths, content-fitting heights, consistent spacing
and no overlap with preceding page content. Do not fake this with fixed-position
coordinates or bitmap footer artwork. Long labels, addresses, empty groups and
larger text must not clip or overflow horizontally. Use semantic lists/links and
contact structure where supported. Retain visible focus and real editable link
destinations; no placeholder controls that pretend to navigate.

Add a QR insertion/editing flow using a local platform encoder if available.
Generate a real code from editable validated content/URL, retain its payload and
resource through the existing content-addressed image pipeline, and allow useful
size adjustment plus accessible alternate text and an adjacent text link. The
sample may use an explicitly labeled example URL until a real destination exists.
Do not invent an owner's business URL or use a temporary localhost preview URL
as a phone destination. Verify decoding of generated output, sufficient quiet
zone and contrast, and sharp output at the displayed size; a decorative QR-like
pattern is not accepted. No online QR service or tracking redirect.

## 3. Fully redesign the editable test website

Treat Aurora as the existing test website unless repository inspection identifies
a more explicit current owner test project. Start a fresh named redesign version
or working copy, preserving the existing Aurora/Dark Flow project, history,
sidecars and recovery. Existing preservation notes concern the prior original;
the owner now authorizes this new redesign. Do not delete the reference fixture
or silently invalidate unrelated legacy sample tests.

Build a cohesive modern showcase using actual SiteForge authoring capabilities:
an immersive flowing-gradient hero, tasteful glass navigation/cards, clear
typography and generous spacing, purposeful interactive hover/focus states,
responsive flexible sections and the new multi-column footer with About Us,
contact details and a large working QR. Preserve useful linked pages and give
each a coherent responsive design. Keep copy brief and intentional. Demo contact
details must remain clearly fictional rather than inventing owner information.

Glassy means controlled translucency, blur, subtle borders and layered depth,
with readable contrast over the moving background. Implement any missing glass
surface capability through typed normal authoring controls and generated output;
do not inject unsupported sample-only CSS or ship a screenshot. Provide a solid
fallback for missing backdrop support and reduced transparency. Keep native app
chrome on the approved semantic macOS gray palette; website styling is separate.

Use theme-aware color tokens/variants for a polished dark presentation and a
readable light presentation, following existing theme infrastructure where
available. Content and controls must retain contrast across the gradient, motion
and theme changes. Prefer subtle effects with static/reduced-motion alternatives
and equivalent keyboard feedback. Keep local assets appropriately sized and
avoid adding heavy dependencies for visual flourishes.

Make the redesigned website accessible from the installed app's example/start
workflow and save the reviewable editable project in the repository's sample
structure. Resource packaging, template loading and static preview must work
offline from a fresh copy. Use the existing PackagedSiteTemplateLoader creation
path and canonical validation. Do not hardcode a local machine path or depend on
an uncommitted generated site to make the example work.

Inspect actual desktop, tablet and mobile output, including 1440, 768 and 390
pixel widths plus narrow-boundary cases, both themes and reduced motion. Make
multiple visual passes using actual native authoring and website preview/output.
Capture the final editable project and browser result; renders or source text
alone cannot establish visual acceptance. Demonstrate that the footer can still
be edited and that all showcase effects are obtainable from shipped controls.

## 4. Acceptance, installation and local commit

Add focused tests alongside existing subsystem coverage. Verify typed defaults,
invalid input, backward-compatible reopen, exact undo/redo, cancellation,
configuration persistence, duplicate/copy resource behavior, nested footer layout,
safe links, QR payload/decoding and deterministic output. Test the real browser
runtime for radius/strength/speed differences, resize/leave/disposal, reduced
motion and static fallback. Test actual native controls/gestures and keyboard
access rather than proving only setters. Confirm the preexisting gradient and
slider regression cases remain green.

Keep all normal local verification inside the native Testing window, with one
collector, exact affected scopes, descriptive current test, truthful progress,
pause/cancel and persisted reports. Test app main windows initially fill the
usable desktop, preserving the menu bar and Dock. Do not run a full gate after
every small change. Coordinate the active assignment's final gate with this
expanded work: each claimed installed milestone needs the verification required
for its scope, and the final exact commit candidate needs the full ./sf verify
gate including the native UI suite. If a full run is already active, preserve its
source and receipt before further edits; it cannot certify later changes.

Record requirements, decisions, coverage and remaining limitations in the queue,
status, changelog and evidence. Refresh the local app after verified milestones
using scripts/package-owner-local-app.sh --install and verify strict signatures
and source/harness fingerprints. Let the owner save and quit normally if open.

Before committing, review all staged changes, including the existing dirty work.
Include only coherent reviewed source, tests, docs and required sample resources;
do not blindly stage the entire working tree. Exclude unrelated files, personal
machine paths, private owner projects, credentials, reports/build artifacts and
retired model material. Preserve unrelated unstaged work. Use the configured
local Git identity; do not change global identity or authentication. Run the
repository's required secret/security checks and confirm the full green receipt
matches the exact source being committed. Reuse an exact green receipt where
permitted; if behavior changes after it, rerun the affected/full checks required
by policy. Do not commit a failing or partially accepted feature as delivered.

Create an appropriately scoped local commit after all acceptance passes. Report
its hash, installed build and fingerprints, exact test receipts, where to open
the redesigned project and any honest limitations. No push, PR or release.
