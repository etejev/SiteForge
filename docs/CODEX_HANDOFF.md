# SiteForge coding handoff for AWS Quick

This file holds substantial implementation work for Quick when the owner
hands off the shared checkout. The [work queue](CODEX_QUEUE.md) owns routine
fixes and scheduling. [Testing](TESTING.md) and the
[implementation status](IMPLEMENTATION_STATUS.md) own verification and
delivery. [Historical handoffs](coordination/archive/CODEX_HANDOFF_HISTORY.md)
are archived.

**Keep this file current.** Whenever Codex or Quick changes code for a listed
prompt, update its status, remaining implementation work and evidence before
handing back or ending the session. Record partial progress even if testing is
pending. Cite the changed symbols, exact test selectors and any available run
ID or fingerprint. Move completed details to the implementation status or
existing review, and remove the finished prompt from the active list. Keep the
remaining prompt IDs stable.

Before coding, check the current queue, applicable
[specification](SiteForge-Specification.md), ADRs and
[owner decisions](OPEN_DECISIONS.md). Use one writer per file and start with
the earliest ready dependency. Reuse current models and entry points, preserve
on-disk compatibility and stable IDs, and keep edits transactional with exact
undo. Add focused regressions for changed behavior. Record which checks ran and
which are pending on the Mac. The current stabilization commit's failed-test
scope is recorded in the queue.

## November 27 stabilization checkpoint

The focused regular replays cover all 14 failures from the frozen baseline.
The last regular run, `20261127-151559-9508dcf9`, passed all three selected
methods. Native run `20261127-152034-6a7f2402` passed 11 of the 24
exact selectors. The Mac restart cleared the desktop obstruction. After
automation authorization, run `20261127-215622-86b1f7fd` passed nine
more methods. Container query status and the Snapshots-to-Compare flow
passed in `20261127-221824-6546a6d7`. Mixed fill and the minimum-width
fill Inspector passed on the final source in `20261127-223727-68efdf0a`. All original failed
selectors have passing receipts, and owner-local build `26.11.28` is
installed with the exact final source fingerprint.
[Focused delivery evidence](reviews/QUICK-INTEGRATION-2026-11-26.md#november-27-focused-delivery-scope).

## Active implementation prompts

### 02 — Make project storage and recovery safe under interruption

**State:** Snapshot reopen repairs passed in `20261127-145357-166f25e7`; work on other demonstrated storage gaps.

Use SF-0301-004/005, SF-0306-004/005, SF-0307, SF-0309 and SF-1504.
Start with `DocumentLifecycle.swift`, `ProjectPackage.swift`,
`PersistedHistory.swift` and the file/resource-access paths. Trace reads
and writes from the native command through coordinated I/O and adoption.
Close confirmed gaps for transfer, Save As, external replacement,
revert/recovery, interrupted writes and supported older packages. Reuse the
existing identity-bound filesystem and migration rules. Review unknown
schema handling and corrupt optional members independently. Prove that
cancellation and invalid inputs preserve the previous document, history and
owned recovery state. Test round trips with snapshots and resource sidecars.

### 03 — Guard export destination identity and cancellation

**State:** Open finding in the whole-checkout audit.

Use SF-1206-004, SF-1209-004 and ADR-0007. Start with folder/ZIP promotion in
`CanvasRendererCore.swift` and the destination handoff in
`BrowserPreview.swift`. Carry the selected target's identity from confirmation
to promotion. Reuse the established replacement boundary where applicable
and otherwise require a fresh decision when the destination changes. Test an
ordinary external replacement between staging and promotion, an initially
empty destination that becomes occupied, cancellation, failure and successful
replacement for both targets. Verify the foreign item and its contents survive
rejection. Retain only app-owned staging artifacts under OD-014.

### 04 — Protect component libraries and finish local reuse

**State:** Source exists; confirm the read-only guard finding and outstanding approved paths.

Use SF-0901–SF-0907, OD-018/019/033/046. Inspect `ProjectPackage.swift`,
the `DocumentLifecycle.swift` library guard, the component command registry,
and the Components/Inspector entry points. First, distinguish absent records
from unreadable or unsupported records so imported read-only content stays
protected until explicit repair. Then close proven gaps in exposed properties,
nested instances, slot contents, variants, override reset and library
import/update/compare/detach. Extend only approved resource/dependency
representations. Verify old and new package schemas, rejection of cycles,
preserved instance intent, copy/paste and undo of a library update. Check
scale budgets and a native journey with independently customized instances.

### 05 — Unify asset usage, replacement and collection output routes

**State:** Partial. Reuse the existing build-side image reference index.

Use SF-0807-001–003/007, SF-1003-003/004 and SF-1201-007. Build on
`ProjectResources.swift` and the compiler's existing per-build reference
index. Reuse one revision-scoped lookup for Uses, Reveal Usage and replacement
disclosure, including collection-only assets with stable IDs. In the static
planner and Preview router, resolve links from emitted destinations and
surface the existing no-published-items finding for a template with zero
emitted pages. Test empty and unpublished collections, item routes, translated
and collection-only assets, replacement undo, missing items and many-asset
fixtures. Measure existing time and memory budgets without widening them.

### 06 — Implement transactional native style controls

**State:** The native mixed and inapplicable fill journey and six-stop
minimum-width Inspector passed for the installed stabilization build in
`20261127-223727-68efdf0a`. The follow-up implements one painted ramp for
the active fill. Stop dots are direct Colors controls, drag uses one
transaction, and the selected stop has compact exact inputs. Focused
acceptance passed 3/3 in `20261127-234016-1b7181ad`; the exact-source
full run `20261127-235410-4d147154` was stopped under the owner's
failed-only instruction. The two corrected metadata cases passed in
`20261128-002056-9a8e3287`. The four recorded native failures have passing
receipts across `20261128-002320-2df2e3d1` and `20261128-004044-c93248cf`.
Owner-local build `26.11.28` is installed. See
[the queue](CODEX_QUEUE.md#done--one-gradient-ramp-per-fill) and
[the styling evidence](evidence/SF-FAST-STYLE-AUTHORING.md#one-gradient-ramp-per-fill).
The earlier failed-only gate applied to stabilization commit `0e61ec2`.

Use SF-0506–SF-0511 and SF-0701–SF-0705. Trace the controls in
`FastStyleControls.swift`, `WorkspaceShellView.swift` and the existing
style command registry. Consolidate draft/preview/commit behavior for fill,
stroke width, corner radii, gradient stops, spacing and typography where
existing controls diverge. Keep sliders live and make a completed edit one
history entry. Reuse the same numeric parsing and validation for keyboard
input, handle mixed and inapplicable selections correctly, and ensure an
external selection or revision change invalidates a stale draft safely.
Test precise repeatable values, Escape, scope change, mixed applicability,
reopen and exact undo/redo. Check large selections for main-thread work.

### 07 — Complete responsive authoring and resolver parity

**State:** Partial. Keep the passing regular scale evidence. Native width
comparison, audit findings and value provenance passed in
`20261127-215622-86b1f7fd`, and the container-query journey passed in
`20261127-221824-6546a6d7`. Use the queue for remaining resolver work.

Use SF-0501–SF-0505 and SF-0601–SF-0606. Follow the existing resolver from
canonical fields through the scene, Inspector value trace, Compare Widths,
responsive audit and connected export. Fix one remaining cascade or
containment case at a time. Test boundary widths, inheritance/reset,
container queries, nested slots, fluid values, fixed/sticky output and
intentional overflow. Check explicit CSS-width changes, Escape, selection
identity, and undo/redo survival. Compare native canvas geometry with the
same authored content and widths in a real browser. Keep sampled or
unsupported cases identifiable in findings and pursue current scale budgets.

### 08 — Finish media, fonts and resource failure handling

**State:** Partial. Read current format and resource limits before extending them.

Use SF-0801–SF-0807 and OD-045/100. Inspect `ProjectResources.swift`, its
import/export adapters and the native asset controls. Close approved
organization, replacement, image/SVG/vector, font and audio/video workflows
within documented format and size limits. Preserve originals and content
hashes. Review external SVG references, font license notes, fallback fonts,
poster/caption routes, missing/unavailable assets and sidecar save/reopen.
Test malformed or oversized files, duplicate import, unavailable originals,
an undoable replacement and supported-browser output. Keep larger media
behind OD-100 until a storage decision is approved.

### 09 — Complete footer composition and interactive effects

**State:** Source exists. Close the remaining editor, renderer and output gaps.

Use SF-0508/0509, SF-0802, SF-1103/1104 and SF-1201. Start with
`FooterContent.swift`, `DecorativeEffects.swift` and
`DecorativeEffectsInspector.swift`. Unify pointer-reactive Flow radius,
direction, speed and pull so editor preview and generated runtime use the
same bounded parameters. Keep continuous gradients and alpha/theme
resolution consistent. Build one reusable typed operation for editable
footer groups, link/contact/address content and optional QR that creates
ordinary responsive nodes and assets. Verify QR payload, quiet zone, scannable
pixels and resource/undo integrity. Use the existing sample recipe and fixtures
to prove desktop/mobile, dark/light and reduced-motion/transparency output
parity. Leave sample art direction and manual review to the existing queue.

### 10 — Complete local CMS and authored-site localization

**State:** Partial. Reuse existing file import and localization source.

Use SF-1001–SF-1007 and OD-035–038. Reuse the collection schema, editor,
template routes, list pages, expression engine and local CSV/JSON import
implementation already in the checkout. Provide a native local import path
where missing, with preview/errors and atomic apply. Verify failed/partial
imports, stable item/route identity, empty and unpublished data, tokenized
expressions and guarded built-in functions, escaping, import size limits,
fallback locale, default RTL and language-specific Preview/output. Keep
forms authored and usable within the documented submission boundary.
Connectors or a real submission backend require the applicable service,
credential and data-handling decisions. Keep local acceptance independent.

### 11 — Complete authored interactions, motion and generated runtime

**State:** Partial. The browser-runtime journey passed all eleven behavior
checks in `20261127-151559-9508dcf9` at fingerprint `31fbf5fea43c` after
the Chrome test driver corrected key-event encoding. Runtime bundling and
the remaining approved behavior below still need implementation or evidence.

Use SF-1101–SF-1107, SF-1205 and OD-039–042. Reuse the event/motion model
and runtime emitters, retaining bounded variables, no-script behavior,
reduced motion and keyboard access. Verify click and key paths, initial
and updated binding text, modal focus restoration, scroll reveal, disabled
or missing targets, cleanup, expressiveness supported by the approved slice
and connected/static-output parity. Finish the approved hashed generated
runtime bundle when ready. Prove repeatability, local route resolution,
cache identity and script absence where unused. Keep authored scripting,
later timeline/scroll effects and expanded variable scopes behind their
documented decisions. Test in real browsers with all relevant user assertions.

### 12 — Finish portable static builds and diagnostics

**State:** Partial. Depends on Prompt 03 for replacement behavior.

Use SF-1201–SF-1211 and OD-042/120. Review `CanvasRendererCore.swift`,
`BrowserPreview.swift` and Check Website. Verify output from one immutable
plan through Preview, folder and ZIP after Prompt 03. Close supported
semantic HTML/CSS, metadata, SEO routes, sitemaps, profiles, build checks,
asset integrity and checksums, local serving, reproducibility and explicit
unsupported-feature findings. Use agreed limits and label any temporary
default. Build equivalent projects twice, compare file bytes/paths, extract
ZIP and open offline, verify links to nested/localized pages, and simulate
cancellation and failure. Verify the report points back to the right live
editing target and that invalid builds cannot publish or replace valid output.

### 13 — Finish local version inspection and review

**State:** Partial. Snapshot reopen and native File → Snapshots and Compare
Versions passed in `20261127-145357-166f25e7` and
`20261127-221824-6546a6d7`. Retain those receipts for further work.

Use SF-1301/1306 and OD-043. Reuse `ProjectSnapshotsSheet.swift`,
`DocumentLifecycle.swift` and the current comparison view. Close named
create/rename/delete, reopen, comparison between two stored versions or current
and stored, and undoable restore that offers to keep the current head. Extend
visual comparison only through approved immutable snapshots and existing
renderer paths. Test exact identity, missing/corrupt records or resources,
asynchronous cancellation and stale results, and accessibility of both
structural and visual review. Keep network collaboration out of this slice.

### 15 — Remove measured hot paths and reliability hazards

**State:** Start from retained profiles and scale receipts. Advance one
confirmed hotspot at a time.

Use SF-1601/1602/1607 and SF-1902-007. Profile package open/save, active edits,
large component rendering, responsive audit and export on the approved
hardware/OS matrix under OD-001. Find repeated graph traversals, cache
invalidation gaps, unnecessary decoding and oversized retained results before
altering algorithms. Prefer revision-scoped indexes and bounded,
cancellable off-main work where they preserve deterministic output and
current-state checks. Verify original budgets, cancellation, stale results,
memory growth and macOS responsiveness on reproducible fixtures. Publish
before/after evidence to the existing review.

### 18 — Connect approved data sources and form destinations

**State:** Owner decision required for connected sources and destinations.

Use SF-1005/1006, SF-1603/1604 and OD-037. Proceed after approval of the
provider, credential store, consent, retention and revocation design.
Start with the existing collections/import and form schema. Build explicit
adapter contracts and local fixtures first. Preserve stable bindings when
a source is offline or changes schema. Verify permission denial, revocation,
request cancellation, failed and retried submissions, duplicate submissions,
and the user's ability to see and correct a mapping or destination error.
Keep account creation, live credentials and deployment with the owner.

### 19 — Add owner-approved publishing, domains and rollback

**State:** Owner decision required for provider and deployment policy.

Use SF-1210, SF-1208/1209 and OD-042. Begin after provider, credential and
deployment policy approval. Reuse the tested build artifact and integrity
manifest from Prompt 12. Define immutable releases, explicit preview versus
production destinations, promotion and rollback state transitions before
adding the provider adapter. Use a local fixture adapter to verify interrupted
uploads, a failed promotion, stale credentials and rollback to an intact
release. Add truthful native status and history. Leave live infrastructure
changes and production publication to the owner.

### 20 — Add approved collaboration and conflict resolution

**State:** Owner decision required for collaboration architecture and service.

Use SF-1302/1303, SF-0306 and OD-043. Begin after approval of the sync,
offline, identity and merge architecture. Start with two local replicas,
the existing stable object IDs, transactions and checkpoints. Define merge
and replay semantics for edits, deletion, reconnect, duplicate operations
and incompatible schema before adding a service transport. Exercise
competing edits, repeat delivery, lost connection and conflict recovery.
Keep unsynced edits recoverable, surface conflicts, and verify that presence
does not mutate or overwrite canonical content.

### 21 — Finish approved review, roles and permissions

**State:** Depends on the approved authorization and collaboration contracts in Prompt 20.

Use SF-1304/1305, SF-1603/1604 and OD-043. Reuse approved collaboration
identity and authorization contracts from Prompt 20. Add comments,
annotations, review states and approval records in bounded slices. Define
anchors to stable project, revision and node identities, plus behavior
for moved or deleted items. Verify read-only and revoked access, concurrent
review updates, approval transitions, and project-content redaction.
Network and account testing depend on the approved roles and service model.

### 22 — Implement the approved post-release extension system

**State:** Post-release milestone under OD-044; owner architecture review required.

Use SF-1401–SF-1406 and OD-044. Begin after the approved post-release
milestone and permission/API review. Implement the declared-capability
manifest and out-of-process lifecycle, then a versioned read-only document
API, then approved mutation and export hooks through existing validated
entry points. Keep no-network defaults, capability revocation and clear
crash recovery. Use local extensions to verify the denied and allowed
paths, API compatibility, cancellation, timeout, undo and deterministic
output. Defer marketplace/account work until its policy and owner
permissions are settled.
