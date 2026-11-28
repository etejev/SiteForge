# ADR-0031 — Container queries

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Requirements: SF-0605-001, SF-0605-002, SF-0605-003, SF-0605-004, SF-0605-005, SF-0605-006, SF-0605-007, SF-0605-008; supporting SF-1204-003, SF-0308-003

## Context

Responsive behavior keyed to the window (breakpoints, SF-0601) cannot make a
component adapt to the space it is placed in. SF-0605 asks for query
containers, named contexts, thresholds, nested evaluation, cycle safety and a
defined fallback for unsupported targets.

## Decision

- Storage (document schema 27, namespace `responsive.query.v1.`): a Frame,
  Section, Stack or Grid is a container with `container` = name (`[a-z][a-z0-9-]{0,31}`).
  Any object may hold up to 8 ordered rules (`rules` list; per rule optional
  `container` name, `minWidth` / `maxWidth` in whole points, inclusive, at least
  one; one or more `set.<key>` values).
- Queryable settings (each with one canvas meaning and one CSS declaration):
  visibility, opacity, text size and line height (text, buttons, links), width
  and height (only fixed-size objects placed by a Frame and without a fluid
  size, so nothing else reflows).
- Resolution: the nearest active container above the object (filtered by name
  when the rule names one; an object never queries itself). Container widths are
  measured once without any rule applied; a container is active only when its
  width never depends on its contents (no Hug width at any breakpoint), like CSS
  inline-size containment. This makes evaluation cycle-free. Matching rules apply
  in order; a later rule wins per setting and also beats the breakpoint's own
  value. Unknown names are kept and reported (`container-query-no-container`);
  Hug containers are skipped and reported (`container-query-container-hugs`).
- Canvas and Preview evaluate on the expanded page in scene preparation, so
  rules inside components follow each copy's container. Export emits
  `container-type: inline-size; container-name: sf-cq-<name>` for active
  containers and one `@container` block per rule after all other rules.
- Edits are ordinary property commands through `ContainerQueryCommandRegistry`
  (no new history command); clipboard version 8 carries the data.

## Consequences

- Canvas evaluates at the canvas width; browsers evaluate continuously. Both use
  the same container and range rules, so they agree at every width the canvas shows.
- A text-size rule combined with a line height from another rule can make an
  invalid text style on the canvas; validation checks each value, not combinations.
- A rule that hides an object is exported as `<selector>[data-siteforge-node] { display: none; }`
  in its own `@container` block, because text and controls take `display` from
  compound selectors that a plain hide would lose to (ADR-0143). A rule that
  shows writes no `display`; a hide holds only while no later Show rule of the
  object matches, so browsers and the canvas both let the later rule win (lane
  V19 amendment below; this replaces the earlier "a matching hide always wins").
- Browsers measure a container's content box, and so does the canvas: rules query
  the width inside the padding and border that export emits for that container
  (OD-143, approved; `CanonicalContainerQueries.contentInset`, ADR-0143).
- Each edit leaves a sanitized `ResponsiveAuthoringDiagnostic` (ADR-0143).

## Reversal

Remove the namespace from validation and the schema-27 gate, the scene hook and
the emitter. Projects using container queries would need their rules removed.

## Amendment (lane V19, owner decision 2026-11-26 9:55 PM)

Approved by the owner 2026-11-26 9:55 PM EST (items 1 and 2 of the decisions on
the lane V14 findings). Implemented by lane V19; unverified until Codex builds
and runs the tests (no Swift toolchain or browser on the lane V PC). Document
schema 27, persisted-history schema 4 and WebsiteMetadata version 3 unchanged; no
new document key, command or clipboard change.

### 1. Container queries work in browsers on pages without page flow

Context: those pages write every object as its own absolutely placed element
(`SafeHTMLEmitter`), so no element was the DOM ancestor of a container's
contents and no `@container` rule ever matched in a browser, while the canvas
applied them (lane V14a, SF-0605-003). The owner chose to make them work rather
than report them as canvas-only.

Decision (`StaticContainerQueryWrapping`, InsertionModel.swift):
- Every container that a rule on the page queries, as resolved by the shared
  walk `CanonicalContainerQueries.container(for:…)`, gets a wrapper element
  `<div data-siteforge-cq="<id>">` written directly after the container's own
  element. It holds the elements of everything inside the container. Paint
  order is depth first, so the wrapper only adds tags at subtree boundaries: the
  order of every element, and so stacking, reading and tab order, is unchanged.
  The wrapper is a plain `div` without role, text, focus or events, so the
  accessibility tree is unchanged.
- Wrapper CSS, one rule per line: `position:absolute; left:0; top:0;
  width:<content width>; height:0; margin:0; padding:0; border:0;
  container-type:inline-size; container-name:sf-cq-<name> sf-cqid-<id>`. The
  width is the container's exported width at each breakpoint (desktop width or
  fluid width as one continuous `calc`, then tablet and phone overrides in their
  `@media` blocks, exactly as `StaticLayoutOutputEmitter` and
  `StaticFluidValueOutputEmitter` write the container) less `contentInset`
  (OD-143), so browsers switch at the width the shared evaluation (`evaluated`)
  measures on the canvas, in Preview, in the Inspector and in the responsive audit.
- Why a zero-origin wrapper instead of converting each child's coordinates to be
  relative to the container: an absolutely placed element is positioned against
  its nearest positioned ancestor. A wrapper at the page corner keeps the page
  corner as that origin, so every `left`/`top` (desktop, every breakpoint, fluid
  values, the right-to-left trees, which keep physical `left`) stays exactly the
  same rule and nothing needs converting or can drift. Only the wrapper's inline
  size matters to `container-type: inline-size`; with no height it paints and
  catches nothing.
- Only queried containers are wrapped: wrapping every container would change
  the HTML of every page without page flow (also pages without any rule) and put
  a containment boundary around content that doesn't need one. Pages without
  rules are byte-for-byte unchanged (test).
- `container-type` applies containment: in browsers that apply layout
  containment the wrapper is the containing block of fixed descendants and a
  stacking context, and absolute insets (`right`, `bottom`) would be measured
  from it. So objects whose output has any `layout.position.v1.` declaration
  (mode, insets, z-order across the page) and overlays with their contents (the
  interaction runtime layers, moves and centres them on the page) are never put
  in a wrapper, and a container holding one can't be queried on these pages: the
  shared walk skips it like a Hug container and reports
  `container-query-container-positioned` (Inspector: container state), so canvas,
  Preview, Inspector, audit and export agree that its rules don't apply.
- Interactions (ADR-0065): contents written in a wrapper are no longer siblings
  of their container. The wrapper carries `data-siteforge-cq-within` with the
  hidden/shown containers that hold it (outermost first), and
  `[data-siteforge-node="X"][hidden] ~ [data-siteforge-cq-within~="X"] { display:none !important; }`
  hides it with its container, without scripts. The contents keep
  `data-siteforge-within`, so the runtimes' groups (focus, modal trap, outside
  clicks, reveal and its animation, z-order, placement) are unchanged; the
  wrapper is not in a group, so nothing is moved or animated twice.
- A hide rule on such a page also names the object's contents (the canvas hides
  an object and everything inside it); hiding rules query the wrapper by its
  unique name, so a rule written on a content element inside a nested wrapper
  still queries the right container. An object's own settings keep the rule's
  authored query (`@container (…)` or `@container sf-cq-<name> (…)`), which the
  nesting resolves to the same wrapper.
- The container's own `container-type` line is still written (inert on these
  pages, as no element is inside it) so existing output stays the same.
- Localized trees, collection item pages and list pages compute wrappers per
  written page from the same node IDs; the wrapper rules are written once per
  container from the style pages. Dark mode does not touch them. Static Release
  minifies them (nested `@container` groups are supported by `StaticCSSOptimizer`),
  keeps them (their selectors name objects in the HTML) and hashes the written
  files into the integrity manifest.

### 2. Show restores each object's own display

- A rule that shows writes no `display` (`cssDeclaration` has none for
  visibility). The object keeps whatever its normal rules give it at every
  breakpoint: flex or grid for containers with page flow, flex for Text, Buttons
  and Links, block otherwise.
- Show works by stopping hides: a container-query hide holds only while no later
  Show rule of the object matches (nested `@container … not (…)` blocks), and on
  pages without page flow a breakpoint hide (`StaticVisibilityOutputEmitter`,
  the same `[…][data-siteforge-node]` specificity lane V14a uses) for an object
  hidden there by itself or by a container above it holds only while none of
  that object's Show rules match. The layout rule of an object with a Show rule
  writes `display: block` so its plain hide can't win first. So Show reveals an
  object hidden at another breakpoint or by a less specific base rule, exactly
  when the canvas does.
- Pages with page flow lay out only visible objects at each breakpoint
  (`ConnectedPageOutput` writes only a hiding rule for a hidden one), so a Show
  rule can't reveal an object hidden there: canvas and export keep it hidden and
  the Inspector says why (`container-query-show-without-layout`, with the
  recovery "show it at this breakpoint in Visibility and hide it with a rule").
  Revealing it with a layout of its own is a proposed open decision (lane V19
  report).

Reversal: remove `StaticContainerQueryWrapping`, the `queryWrappers` argument of
`SafeHTMLEmitter.emit`, the `unqueryable` argument of `container(for:…)`, the
`revealable` argument of `StaticLayoutOutputEmitter.emit`, the conditional
hides in `StaticVisibilityOutputEmitter` and the two finding cases, and restore
`display: block` for Show. No data migrates.
