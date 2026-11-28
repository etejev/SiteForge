# Next ten development prompts — 2026-10-27

## Subsequent owner approval — acceptance phase

After the source batch, the owner explicitly requested **full local testing and
a local commit** on 2026-10-27. Finish incomplete prompt-10 integration first,
then perform full verification, fix failures and commit only after green.
This later approval supersedes the source-phase testing/commit hold below for
that acceptance workflow; historical source-only reports remain unverified until
execution. No push, installation or scheduled follow-up is authorized here.

Owner-authorized sequential development batch. These are ten source-development
workflows, not ten acceptance runs or a promise of complete specification delivery.

Target: **Build SiteForge**, local thread
`01a0eff1-fef2-7950-bb6e-e7587fd5bb61`.
Model: `gpt-6.1-sol`; reasoning: `medium`.
Batch marker: `SF-SOURCE-BATCH-20261027`.
Coordinator state: `.codex-loop/queued-development-20261027.json`.

The existing Page Background discoverability run
`01a17c37-c07b-7be1-ba60-254437bc427b` is the predecessor, **not prompt 1**.
Do not dispatch prompt 1 until that run finishes its source scope.

## Dispatch and stop rules

- Send exactly one development prompt at a time, only when the preceding target
  turn is complete and its source implementation/report can be inspected.
- Never send a future development item into an active or attention-needed run.
  This is a coordinator-held queue, not ten steering messages sent up front.
- A source item can finish while testing is deferred. It cannot be represented
  as verified, accepted, production-ready, installed, or DONE under AGENTS.md.
- Advance only after the report and changed source/evidence address that item's
  bounded scope. A generic stop, unresolved decision, interrupted/failed turn,
  quota error, or plan-only report does not satisfy the condition.
- If blocked, pause dispatch and report the precise owner action. Do not retry
  unchanged failures, silently skip items, expand scope, or run tests to unblock.
- At most ten development prompts. No automatic repair/continuation messages in
  addition to the ten: pause for direction if a prompt needs another turn.
- Record dispatch intent before sending. After tool acknowledgement record the
  slot/marker and observed target turn. If acknowledgement is ambiguous, pause
  rather than risk sending twice. Recover from thread evidence when possible.
- After prompt 10's source report is reviewed, pause the automation and report
  the batch's implementation/remaining-risk summary. Do not start prompt 11.
- The latest direct owner instruction always supersedes this batch. Stop/pause
  requests cancel further dispatch. No test approval is inferred from “next,”
  “done,” this batch authorization, or reaching the tenth prompt.

## Shared prompt contract

The coordinator sends this contract followed by ONE numbered prompt below.

Implement only the selected source workflow in the shared SiteForge repository.
Read AGENTS.md, linked normative specification requirements, current queue/status,
relevant decisions, implementation and test source before editing. Inspect the
current implementation for actual gaps; do not reimplement completed features
from stale roadmap paragraphs. Requirement lists below are candidate bounded
coverage: cite the exact applicable IDs after reading their contracts. Do not
claim that a bounded workflow completes a whole normative module.

**OWNER HOLD ALL TESTING.** Do not execute tests of any kind, ./sf verify, UI
automation, readiness/smoke/visual journeys, collectors, builds/build-for-testing,
lint/check scripts or app/browser launches for acceptance. Add/update meaningful
test source and intended selectors, but leave it unrun. Static code/diff/history
inspection and ordinary source editing are allowed. Do not turn static inspection
into a claimed runtime result. Verification remains a mandatory future acceptance
step requiring separate explicit owner approval; it is not waived.

Complete a coherent native UI → existing canonical transaction → renderer/shared
compiler source path, not just a plan or cosmetic placeholder. Preserve stable
identifiers, backwards-compatible packages, UI/document separation, atomic edits,
undo/redo, explicit responsive overrides, cancellation, native text editing and
accessibility. Use existing registries/resolvers and immutable revision-tagged
work. Avoid parallel models, speculative abstractions, sample-specific behavior,
silent coercion and unnecessary schema changes. Keep expensive work off the main
actor. If a new architecture or irreversible migration is truly required, follow
AGENTS.md's owner-decision boundary rather than inventing approval.

Use approved editor references 01/05 and Settings 12 as consistent design
direction, respecting their differences rather than copying contradictory details.
Keep stable field/label geometry, single-row accessible destination tabs at normal
supported sizes, consistent cards/headings/dividers, compact controls, and simple
user-facing language. Preserve existing keyboard and reduce-transparency behavior.
No new generated mockups or image assets are needed for this batch.

Preserve all existing dirty changes and owner projects/resources/recovery/evidence.
Do not edit the saved Aurora Dark Flow, Editorial or Workflow Study packages or
exports to make source changes appear accepted. Do not alter Dark Flow's approved
one editable 45-degree native gradient: 0% #160D2B, 50% #6A36C8, 100% #C52E53.
No handwritten replacement website or generated-output patch.

OD-018/019 supplied slots/conflict retargeting, remote services/publishing,
distribution/update trust, legal/licensing and Apple account boundaries remain
governed by their decisions. No credentials, purchases, external writes, signing,
cache/evidence cleanup, installation, commits, pushes, tags, PRs or releases.
Prior local-install approval is conditional on future green verification and does
not authorize an install in this batch. Do not ask again about resolved OD-026/027.

Add a short plan in the appropriate queue entry before implementation. Update
implementation status, changelog and concise evidence after meaningful changes.
Use **IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED**.
Keep broader modules Partial and existing acceptance failures/cancellations
truthful. Do not edit the coordinator plan/state or send the next prompt yourself.

Start commentary with the selected batch marker and number. End with that same
marker and: implemented source paths, concrete user-facing changes, unrun coverage
selectors, dependency/decision limitations, and confirmation that no execution,
installation or GitHub mutation occurred. A plan-only response is not delivery.

## Prompt 01/10 — Site and page setup

Marker: `SF-SOURCE-BATCH-20261027-01`.
Candidate requirements: SF-0303-002/003/004/005/006,
SF-1207-001/002/003/004/005/006/008; existing asset reference contracts for favicon
and social images.

Close real gaps in the ordinary local workflow for site title, browser-tab/page
title, description, favicon, per-page navigation label/route and metadata. Extend
the existing typed site/page metadata and native controls; do not create another
settings model or confuse website metadata with global application preferences.
Keep one obvious entry from Pages, clear defaults/overrides, safe route/duplicate
validation and readable local browser/social snippet presentation. Do not imply a
Google account, live search-indexing guarantee or external service integration.

Ensure existing favicon/social-image references use ResourceStore/dependency
tracking and preserve original bytes. Page rename/reorder/delete and route changes
must preserve PageIDs, link intent and cancellation safety. Inspect shared output
source so document titles, descriptions, icon references and existing metadata
are emitted from the same committed snapshot. Avoid extending SEO beyond the
approved local contract merely to add fields. Write unrun transactional,
stale-draft, persistence, link/reference and semantic-output source coverage.

## Prompt 02/10 — Header, footer and navigation authoring

Marker: `SF-SOURCE-BATCH-20261027-02`.
Candidate requirements: SF-0501-003/005, SF-0504-003/004,
SF-0601-003/005, SF-0602-003/006, SF-0806-002/003/005/006.

Complete the practical dedicated Header/Footer workflow using existing connected
roles and navigation identities. Keep full available width, Header first and
Footer after content, adjustable height/padding and connected section flow.
Make title/logo visibility, included-page toggles, link labels/order/destinations,
alignment, spacing and mobile menu behavior clear and editable together. Reuse
existing customization rather than flattening these roles into free-floating
Sections. Users should obtain a useful default without positioning every child,
while intentional content customization remains possible through existing tools.

Preserve explicit responsive values and existing mobile keyboard/focus behavior.
Keep canvas and generated menu/link/title styling derived from the same state;
do not invent fixed/sticky policy or external navigation scope. Add unrun source
coverage for no/one/many links, title/logo options, page lifecycle changes,
responsive menu state, stale drafts and exact undo/reopen projection.

## Prompt 03/10 — Connected sections and structural layout

Marker: `SF-SOURCE-BATCH-20261027-03`.
Candidate requirements: SF-0501-002/003/005/006,
SF-0502-002/003/005/006, SF-0503-002/003/005/006,
SF-0505-002/003/005/006, SF-0304-003/005.

Close remaining practical Section/Stack/Grid editing gaps using the existing
layout resolver and central mutation path. Section insertion/reordering should
connect to surrounding flow, not behave as arbitrary free-positioned boxes.
Expose useful existing direction/distribution/wrapping, columns, gap/padding,
alignment and content-sizing controls coherently. Where a listed capability is
not in the approved canonical model, scope a safe existing alternative explicitly
rather than adding unsupported controls or silently broadening architecture.

Keep nested containing widths, Hug heights, empty containers and mixed content
predictable. Preserve intentional free Frames and unconverted legacy pages;
conversion must be explicit and reversible. Avoid special-casing Aurora.
Update unrun source matrices for nesting/reorder, min/max/aspect interactions,
hidden children, history/cancellation and canvas/output geometry agreement.

## Prompt 04/10 — Responsive visibility and fluid styling

Marker: `SF-SOURCE-BATCH-20261027-04`.
Candidate requirements: SF-0601-002/003/005/006,
SF-0602-003/005/006, SF-0603-002/003/005/006,
SF-0604-002/003/005/006.

Extend the existing responsive authoring workflow where real source gaps remain:
clear current breakpoint, adaptive visibility/content where supported, useful
fluid typography/spacing controls and explicit override/reset choices. Reuse the
existing cascade and fluid-value model, not another mobile sizing system.
Changing device preset must not rewrite document values. A content-responsive
conversion must retain its explicit confirmation and exact reversible effects.

Aim to eliminate repeated per-box mobile adjustments through general containing
layout, text wrapping and constrained fluid rules, without deleting authored
overrides or auto-converting old projects. Make unavailable/mixed states clear
without cluttering every row with internal diagnostics. Add unrun source coverage
at breakpoint boundaries/intermediate widths, invalid bounds, hidden flow,
document/page changes and faithful shared compiler projection.

## Prompt 05/10 — Practical text and typography

Marker: `SF-SOURCE-BATCH-20261027-05`.
Candidate requirements: SF-0406-002/003/005/006,
SF-0507-002/003/004/005/006, SF-0805-003/004/006.

Close remaining real editing gaps in Heading/Text typography and paragraph
presentation: understandable hierarchy, actual installed font family/weight
selection, size/line-height/tracking/alignment, wrapping and readable text-column
behavior. Reuse existing native text and typography registries. Avoid a new
rich-text persistence architecture merely for convenience; keep any unsupported
range-formatting scope explicit. Do not import unlicensed fonts, download fonts
or promise browser support that output cannot provide.

Preserve native marked-text/caret/selection and field Undo behavior separately
from document Undo. Draft focus changes, Escape, empty values and unavailable
weights must be predictable. Keep renderer, inline editor and output typography
consistent in source. Write unrun source coverage for controls, multi-selection,
fallback, cancellation, exact history and compiler font/style emission.

## Prompt 06/10 — Reusable visual styles and tokens

Marker: `SF-SOURCE-BATCH-20261027-06`.
Candidate requirements: SF-0506-002/003/005/006,
SF-0508-002/003/005/006, SF-0509-002/003/005/006,
SF-0510-002/003/005/006.

Make the existing fill/gradient, border/radius/shadow, token and reusable-style
tools work as one understandable styling workflow. Close source gaps in applying,
editing, resetting and reusing these existing styles rather than forcing users
to reproduce the same treatment on each element. Keep preview of a draft
noncanonical until commit and preserve exact fill/stop/token identities.

Do not create a second stylesheet or custom CSS editor; retain typed supported
values, cycle/dependency rules and explicit overrides. Applying a shared style
must disclose its existing scope and must not silently detach token bindings or
recolor unrelated pages. Preserve app-theme versus authored-site separation.
Update unrun model/Inspector/output source coverage for linked changes,
mixed/inapplicable selections, cancel/reset, history and stable style ordering.

## Prompt 07/10 — Local assets and image usability

Marker: `SF-SOURCE-BATCH-20261027-07`.
Candidate requirements: SF-0801-002/003/004/005/006,
SF-0802-002/003/005/006, SF-0807-002/003/004/005/006,
SF-0806-003/005.

Close the remaining practical local-image workflow gaps: clear import/reuse,
search/organization, image or fill placement, existing fit/position controls,
alt-text access and missing-resource recovery. Distinguish replacing one selected
use from intentionally replacing a shared asset everywhere; show impact through
the existing dependency model and keep cancel/undo exact.

Preserve original bytes, security-scoped access, stable AssetIDs, thumbnail
budgets and off-main expensive processing. Keep component/fill/favicon usages
accounted for by safe deletion/replacement. No remote providers, general SVG/code
execution, audio/video expansion or new import architecture in this item.
Write unrun source coverage for repeated use, failed/cancelled import, stale
selection, reference safety, original-byte preservation and exported references.

## Prompt 08/10 — Coherent reusable component workflow

Marker: `SF-SOURCE-BATCH-20261027-08`.
Candidate requirements: SF-0901-002/003/005/006,
SF-0902-002/003/005/006, SF-0904-002/003/005/006,
SF-0905-003/004/005/006.

Complete real source gaps in creating/naming a reusable component, editing its
definition, returning to an instance, and using existing exposed text/media/link/
choice controls. Integrate supported existing variant/state selection where the
current contract and model allow it, without inventing a parallel component
model. Keep scope/change propagation apparent and avoid unnecessary navigation
or repeated duplicate Apply controls.

Preserve stable definition/property identities, instance-specific values,
explicit Reset, cycle/capacity guards, native field focus and exact history.
Do not implement supplied-slot ownership or conflict retargeting without the
still-required OD-018/019 owner decisions. No remote library/provider work.
Add unrun coverage for definition/instance transitions, applicable exposed
properties, missing definitions, existing variant resolution and compiler parity.

## Prompt 09/10 — Native settings and project lifecycle usability

Marker: `SF-SOURCE-BATCH-20261027-09`.
Candidate requirements: SF-0204-002/003/004/006,
SF-0206-002/003/005/006, SF-0301-003/004/005,
SF-0306-003/004/005, SF-1505-006.

Close real remaining source gaps in the approved global Settings/Welcome/
project lifecycle workflow. Preserve Settings reference12 geometry, consistent
card widths/padding and nonresizable behavior; ordinary editor windows remain
normally resizable. Keep simple program-wide preferences, no App/Project/
Workspace settings selector, release-channel picker or experimental-app split.
Do not confuse website metadata from item01 with application preferences.

Make defaults, cancellation, save/close/recent-project errors and crash-qualified
recovery understandable. First or clean launch must not fabricate crashed work;
preserve genuine recovery choices and owner bytes. Advanced testing remains
user-triggered and independent of an open workspace, but DO NOT invoke it or
autorun anything while this batch executes. Keep updater trust/install boundaries
explicit; no bypass of unresolved update/security decisions or fake enabled
installer. Add unrun source coverage for preference drafts, clean/crash sessions,
error/cancel, accessibility labels and identity-safe lifecycle transitions.

## Prompt 10/10 — Connected Preview/export and source integration closure

Marker: `SF-SOURCE-BATCH-20261027-10`.
Candidate requirements: SF-1201-003/004/005/006,
SF-1202-003/004/005, SF-1203-003/004,
SF-1204-003/004, SF-1206-003/004, SF-1211-003/004/006.

Integrate the preceding source changes across the existing real Safari loopback
Preview and native local export code. Inspect coherent snapshot/draft commit,
metadata/navigation/style/resource projection, semantic output, cancellation,
stale result rejection and truthful unsupported-state diagnostics. Finish
concrete source gaps rather than adding custom hand-authored website output,
another compiler/runtime or publishing adapter. Keep Preview/export sourced from
the same actual HTML/CSS/assets and preserve local-server security/lifecycle.

Review the batch diff statically for duplicate controls/models, inconsistent
Inspector cards, unsafe resource ownership, identity/history regressions and
contradictory source-status documents. Correct demonstrated source mistakes and
write the related unrun regression source. No runtime inspection or automation.

End with a batch source-completion inventory: each of the ten workflows, code
paths, intended tests, source limitations/owner decisions, and what future
approval-gated acceptance must cover. **Do not run testing on prompt10.** Do not
install, sign, commit, push or claim the application is finished. Hand the batch
back to the coordinator for the owner's next decision.
