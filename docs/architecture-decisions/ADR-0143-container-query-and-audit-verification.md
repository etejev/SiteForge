# ADR-0143 — Container queries and responsive audit: verification completions

- Status: Proposed (lane V04 verification of batches 09–11; unverified until Codex builds and runs the tests)
- Date: 2026-11-26
- Owners: Product / Engineering
- Requirements: SF-0605-002, SF-0605-003, SF-0605-007, SF-0605-008, SF-0606-003, SF-0606-008, SF-0703-004
- Amends: ADR-0031 (container queries), ADR-0032 (responsive audit)

## Context

Lane V04 re-checked batches 09 (container queries), 10 (responsive audit) and
11 (relative multi-object geometry edits) by reading the code against its real
declarations. Four behaviors did not match their ADRs or the specification:

1. The audit never reported overflow. Every scene object's clip starts at the
   page bounds, and the check intersected the object with that clip first.
2. A container-query rule that hides text, a button or a link had no effect in
   the exported site. Those elements take `display` from compound selectors
   (`…[data-siteforge-node]`, `…:is(a,button)`), which beat a plain `display: none`.
3. The Inspector could add a rule but not change its values or add another
   setting, so a new rule (which starts from the object's current value) could not
   be made to do anything except hide.
4. Neither feature produced diagnostics (SF-0605-008, SF-0606-008).

## Decision

- Overflow uses the object's frame narrowed only by ancestors that clip their
  content (the same ancestors the scene's clip uses), then compares it with the
  page's sides.
- A rule that hides is exported in its own block:
  `@container … { <selector>[data-siteforge-node] { display: none; } }`. All other
  settings of the rule stay in the plain block. (Lane V19 amendment: a rule
  that shows writes no `display`; see below.)
- Each rule setting has its own Inspector row: a Hidden/Shown picker or a number
  field (Return commits, Escape restores). "Add Setting" adds a queryable setting
  that the rule does not change yet. Both use `ContainerQueryCommandRegistry`
  (one undoable transaction each, same refusals).
- `ResponsiveAuthoringDiagnostic` records requirement ID, operation, stable
  identities (node or page) hashed with `DiagnosticStableIdentifier.sanitize`
  (the lane V03 variant-diagnostic pattern), a count, duration and a failure category (`none`,
  `refused`, `cancelled`, `stale`, `revision-exhausted`, `invalid-result`,
  `unexpected`) for container-query edits, audit runs and cancellations, and
  suppressions. It never holds names, text or values. The workspace publishes the
  last one as `lastResponsiveAuthoringDiagnostic`.
- A cancelled or replaced audit run never changes the state of the run that
  replaced it, even when it ends with the scene worker's own cancellation error.
- The Inspector's container-query evaluation does not expand components on the
  main actor when no page or component has rules.
- A relative geometry edit names skipped objects as "out of range or not editable".

## Open question (OD-143) — approved 2026-11-26 8:06 PM EST, built by lane V16

Browsers evaluate `@container` against the container's content box; the canvas
evaluated against its frame. They differ by the CSS padding and border that export
emits for that container (horizontal Stacks, Hug-height Stacks, Sections and Grids,
Frames with box padding, and CSS borders). Recommended default (approved by the
owner): the canvas measures the content box, using one shared inset helper.
Alternative (not chosen): keep the frame width and document the difference. See
"Implemented (lane V16)" below.

## Consequences

- Superseded by the lane V19 amendment: a hide holds only while no later Show
  rule of the object matches, so browsers use rule order as the canvas does.
- No schema, clipboard or history change. Document schema 27, persisted-history
  schema 4 and WebsiteMetadata version 3 are unchanged.

## Implemented (lane V16)

Unverified until Codex builds and runs the tests (no Swift toolchain on the lane V PC).

- `CanonicalContainerQueries.contentInset(of:on:breakpoint:viewportWidth:visibleIDs:nodesByID:reusableStyles:)`
  (InsertionModel.swift) is the one shared inset helper: the left-plus-right space
  that export's CSS puts between a container's border edge and its content box at a
  breakpoint, read from the resolvers the emitters use.
  - Static-layout pages (`StaticLayoutOutputEmitter` writes `box-sizing: border-box`
    and the frame width; `StaticBoxStyleOutputEmitter` writes `border` and `padding`):
    2 × border width (the object's own or a linked reusable style's) + 2 × box
    padding, with the same validity gates and 0.001 px rounding as the emitter.
  - Connected pages (`ConnectedPageOutput`): a box border is an `outline` and takes
    no space; the element has CSS padding only as a horizontal Stack, or as a
    Hug-height Stack, Section, Grid or Frame with box padding (its resolved layout
    padding at the breakpoint's preset width, as the rules are written), or as a
    winning fluid padding, resolved at the viewport width like the browser's `calc`.
  - Pages that need the fluid-flow adapter put padding on an inner wrapper
    (`.sf-layout-…`), so the container element has none.
- `CanonicalContainerQueries.evaluated(_:breakpoint:viewportWidth:availablePageIDs:styleSource:)`
  subtracts that inset (never below 0) once per container per evaluation, so every
  in-app evaluator switches at the exported width together: the canvas and in-app
  Preview (scene preparation), the responsive audit (`ResponsiveAuditRunner`) and the
  Inspector (`containerQueryEvaluation`, which also feeds value traces). The new
  `styleSource` argument (the document) lets static-layout containers take a border
  from a linked reusable style; the style index is built only for pages with rules.
- `ContainerQueryRuleStatus.containerWidth` is now the content width. The rule status
  reads "… is N pt wide inside its padding and border here …", shown to a tenth and
  rounded down so a fractional width is never shown at a boundary it does not reach.
- Containers without padding or border measure exactly their frame, as before.
- No schema, clipboard, history or export change (export already used the content box).
- Test: `CommandKernelTests/testContainerQueriesMeasureTheContentBoxInsidePaddingAndBorderLikeBrowsers`
  (static page with border and box padding at 448/449 and 447/448 against the exported
  CSS, connected horizontal Stack padding, no change without padding or border).

## Reversal

Revert the four changes: the overflow helper in `CanonicalResponsiveAudit`, the
split hide block in `StaticContainerQueryOutputEmitter`, `ContainerQueryValueRow`
and the "Add Setting" menu, and `ResponsiveAuthoringDiagnostic` with its calls.
For OD-143, remove `contentInset`, the subtraction and the `styleSource` argument in
`evaluated` (and its three shell call sites); rules then query the frame again. No
data migrates.

## Amendment (lane V19, owner decision 2026-11-26 9:55 PM)

Approved by the owner 2026-11-26 9:55 PM EST (item 2: "fix now"; item 1 in
ADR-0031's amendment). Unverified until Codex builds and runs the tests.

- Defect: Show (`hidden` = false) wrote a plain `[…] { display: block; }` after
  every other rule. It replaced the flex or grid display of shown containers with
  page flow and the flex box of Text, Buttons and Links whenever it matched, and
  it could not reveal an object hidden at that breakpoint, whose hide (lane V14a)
  has higher specificity.
- Decision: Show writes no `display`; it stops hides instead. A container-query
  hide is written as `@container <query> { @container <later Show query> not (…) { <selectors>[data-siteforge-node] { display: none; } } }`,
  so it holds only while no later Show rule of the object matches (rule order,
  as on the canvas). On pages without page flow, a breakpoint hide for an object
  hidden there by itself or by a container above it that has Show rules is
  written `@media <range> { @container sf-cqid-<container> not (…) { … } }`, one per
  reason, with lane V14a's `[data-siteforge-node]` specificity, and the object's
  layout rule keeps `display: block`, so a matching Show rule reveals it with its
  own display. Hiding rules on those pages query the container's wrapper by its
  unique name (ADR-0031 amendment).
- Pages with page flow give an object hidden at a breakpoint no layout there, so
  Show can't reveal it; canvas, Preview, audit and export agree and the Inspector
  shows `container-query-show-without-layout` with the recovery. A reveal with
  its own layout is proposed as an open decision in the lane V19 report.
- Tests: `CommandKernelTests/testContainerQueryExportHidesTextAboveItsDisplayRule`
  (changed: no forced `display: block`, the later Show rule stops the hide, canvas
  agreement on 500 pt and 400 pt Panels),
  `CommandKernelTests/testContainerQueryShowRevealsHiddenObjectsAndKeepsTheirOwnDisplay`
  (new).
