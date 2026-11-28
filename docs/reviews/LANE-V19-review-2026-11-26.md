# LANE-V19 review — 2026-11-26 (container queries on static-layout pages; container-query Show display)

Owner tag `lane-V19`. Restore point before: RP-2026-11-26-V19. Owner decision: `_quick-scratch/review/OWNER_DECISIONS_LANE_V.md`,
"2026-11-26 9:55 PM EST", items 1 and 2. All tree writes through `forge_io.edit` / `write_new`; `check([...]) == []` after
every edit; `foreign_changes(30) == []` and `icloud_duplicates() == []` before the first write and at every later check.
Verification by reading only (no Swift toolchain, git or browser on the PC). Nothing here has been compiled or run.

## Scope

- Owner items: (1) make container queries work in browsers on static-layout pages (pages without page flow, written flat
  as absolutely placed elements); (2) container-query Show (`hidden: false`) must restore each object's own display and be
  able to reveal an object hidden at another breakpoint or by a less specific base rule.
- Read first: LANE-V14a (the two SF-0605-003 findings, `StaticVisibilityOutputEmitter`, `hiddenRule`, stylesheet order),
  LANE-V04 (hide block, V04 test), LANE-V16 (OD-143, `contentInset`, `evaluated`), LANE-V14e (static pages link
  `styles.css`), LANE-V09 / ADR-0065 (`FlatContainerOutput`, runtimes' groups), ADR-0031, ADR-0143, spec module SF-0605
  (SF-0605-001…008).
- Modules: SF-0605 (container queries), with SF-0603-003 (adaptive visibility) and SF-1204-003 (CSS generation).
- Files changed: `SiteForge/InsertionModel.swift`, `SiteForge/CanvasRendererCore.swift`, `SiteForge/WorkspaceShellView.swift`,
  `Tests/SiteForgeTests/CommandKernelTests.swift`, `docs/architecture-decisions/ADR-0031-container-queries.md`,
  `docs/architecture-decisions/ADR-0143-container-query-and-audit-verification.md`, this report (new).
- No new Swift file, no new document key, command or clipboard change. Document schema 27, persisted-history schema 4,
  WebsiteMetadata version 3 unchanged.

## Design (ADR-0031 amendment, decided here as the owner asked)

- **Wrapper per queried container.** On a page without page flow, every container that a rule on the page queries (resolved
  by the one shared walk `CanonicalContainerQueries.container(for:…)`) gets `<div data-siteforge-cq="<id>">` written directly
  after the container's own element, holding the elements of everything inside it. Paint order is depth first, so only
  tags at subtree boundaries are added: the order of every element (stacking, reading and tab order) is unchanged; the
  wrapper is a plain `div` (no role, text, focus, events), so the accessibility tree is unchanged.
- **Zero-origin content box instead of converting child coordinates.** Wrapper CSS: `position:absolute; left:0; top:0;
  width:<content width>; height:0; margin:0; padding:0; border:0; container-type:inline-size; container-name:sf-cq-<name>
  sf-cqid-<id>`. An absolutely placed child is positioned against its nearest positioned ancestor; a wrapper at the page
  corner keeps that origin, so every `left`/`top` rule (desktop, tablet/phone overrides, fluid values, the right-to-left
  trees, which keep physical `left`) is literally the same rule and nothing can drift. Only the inline size matters to the
  query; it is the container's exported width at each breakpoint (desktop width or fluid width as one continuous `calc`,
  tablet/phone overrides in their `@media` blocks) less `contentInset` (OD-143), so browsers switch at the width `evaluated`
  measures. With no height it paints and catches nothing.
- **Only queried containers are wrapped**: wrapping all containers would change the HTML of every static page (also pages
  without rules) and add containment boundaries nobody needs. Pages without rules are byte-for-byte unchanged (test).
- **Containment boundary.** `container-type` applies containment; in browsers that apply layout containment the wrapper is
  the containing block for fixed descendants and a stacking context, and `right`/`bottom` insets would be measured from it.
  So objects with any `layout.position.v1.` output (mode, insets, z-order across the page) and overlays with their contents
  (the runtime layers/moves/centres them on the page) are never wrapped, and a container holding one can't be queried on
  these pages: the shared walk skips it like a Hug container (`container-query-container-positioned`), so canvas, Preview,
  Inspector, responsive audit and export agree.
- **Interactions (ADR-0065).** Contents in a wrapper are no longer siblings of their container. The wrapper carries
  `data-siteforge-cq-within` (hidden/shown containers holding it, outermost first) and
  `[data-siteforge-node="X"][hidden] ~ [data-siteforge-cq-within~="X"] { display:none !important; }` hides it with its
  container without scripts. Contents keep `data-siteforge-within`, so the runtimes' groups (focus, trap, outside clicks,
  reveal animation, z-order, placement) are unchanged; the wrapper is in no group, so nothing is translated or animated twice.
- **Show (item 2).** Show writes no `display` at all; it lifts hides. A container-query hide holds only while no later Show
  rule of the object matches (nested `@container … not (…)`), which also makes browsers follow rule order like the canvas
  (before, a matching hide always won). On static pages a breakpoint hide (`StaticVisibilityOutputEmitter`, V14a's
  `[…][data-siteforge-node]` specificity) for an object hidden there by itself or a container above it, where that object has
  Show rules, holds only while none match (`@media <range> { @container sf-cqid-<C> not (…) { … } }`), and the object's
  layout rule keeps `display: block` so the plain layout hide can't win first. On pages with page flow an object hidden at a
  breakpoint has no layout there, so Show can't reveal it: canvas and export agree, Inspector says why
  (`container-query-show-without-layout`); a reveal with its own layout is proposed as an OD below.

## Fixes / features

| # | File | Symbol | Defect | Fix |
|---|------|--------|--------|-----|
| 1 | `SiteForge/InsertionModel.swift`, `SiteForge/CanvasRendererCore.swift` | new `StaticContainerQueryWrapping` (`plan`, `openingTags`, `css`, `pinnedNodeIDs`, `unqueryableContainers`, `keepsOwnPositioning`, `subtree`, `revealConditions`, `nested`, `condition`, `hiddenValue`, `identifier`, `uniqueName`); `SafeHTMLEmitter.emit` new `queryWrappers:` and wrapper loop; planner passes `StaticContainerQueryWrapping.openingTags(page)` | Static-layout pages are flat, so no element is a DOM ancestor of a container's contents: `@container` never matched in browsers while the canvas applied the rules (V14a, SF-0605-003). | Zero-origin content-box wrapper per queried container (Design). Positions, order, accessibility unchanged; works in every language tree, item/list page, dark mode and Static Release. |
| 2 | `SiteForge/InsertionModel.swift` | `ContainerQueryFinding.containerHoldsPositioned`, `CanonicalContainerQueries.container(for:…, unqueryable:)`, `evaluated` | Wrapping a positioned object or overlay would change its containing block/stacking. | Such objects stay outside; containers holding one are skipped on static pages by the shared walk with a finding and explanation; Inspector container state shows it (`WorkspaceShellView` `containerSection`). |
| 3 | `SiteForge/CanvasRendererCore.swift` | `StaticContainerQueryOutputEmitter.emit(pages:reusableStyles:)` | A container-query hide of a container on a static page hid only the container's element; its contents stayed visible in browsers (canvas hides them). | On static pages the hide names the object and its whole subtree, querying the wrapper by its unique `sf-cqid-<id>` name (valid inside nested wrappers). `reusableStyles` (planner passes its index) gives the wrapper the linked-style border, as `contentInset` does on the canvas. |
| 4 | `SiteForge/InsertionModel.swift` | `CanonicalContainerQueries.cssDeclaration` (`hidden` → nil); `StaticContainerQueryOutputEmitter.emit` | Show wrote plain `display: block`, overriding the flex/grid display of containers with page flow and the flex box of Text/Buttons/Links (V14a). | Show writes no `display`; objects keep their own display at every breakpoint. |
| 5 | `SiteForge/CanvasRendererCore.swift` | `StaticContainerQueryOutputEmitter.emit` (`cancels`) | In browsers a matching hide beat a matching later Show (canvas: later rule wins). | A hide is nested in `@container … not (…)` for each later Show rule of the object (page flow: the rule's own query; static: unique names). |
| 6 | `SiteForge/InsertionModel.swift` | `StaticVisibilityOutputEmitter.emit` (`conditional`), `StaticContainerQueryWrapping.revealConditions`, `StaticLayoutOutputEmitter.emit(nodes:revealable:)` (+ `baseRule`, `responsiveRules`, `responsiveRule`); planner passes `revealable:` | Show could not reveal an object hidden at a breakpoint (V14a's higher-specificity hide, or the plain layout `display: none`). | Static pages: those hides hold only while none of the object's Show rules match; its layout rule keeps `display: block`. Output for pages/objects without Show rules is unchanged. |
| 7 | `SiteForge/InsertionModel.swift` | `ContainerQueryFinding.showWithoutLayout`, `evaluated`; `WorkspaceShellView` `ContainerQueryRuleView.statusText` | Pages with page flow: the canvas revealed an object hidden at the breakpoint, the browser couldn't (no layout there). | Shared evaluation leaves it hidden and reports the finding with a recovery; the rule's status line shows it. |
| 8 | `Tests/SiteForgeTests/CommandKernelTests.swift` | `testContainerQueryExportHidesTextAboveItsDisplayRule` (V04) | Asserted the old `@container (min-width: 500px) { caption { display: block; } }`. | Now asserts the wrapper rule, the hide nested under `not ((min-width: 500px))`, no `display: block` anywhere, and canvas agreement on 500 pt (shown) and 400 pt (hidden) Panels. Every old guarantee still asserted. |

Docs: ADR-0031 and ADR-0143 got "Amendment (lane V19, owner decision 2026-11-26 9:55 PM)" sections; ADR-0031's and
ADR-0143's statements that a matching hide always wins in browsers and that Show keeps `display: block` now point to the
amendment. Comments in code say why.

Checked and unchanged: the container element's own `container-type` line is still written on static pages (inert there,
keeps existing output/tests); connected pages keep their element-based containers; `FlatContainerOutput` lines are
unchanged; `EventGraphOutput.hiddenCSS` (`!important`) still wins over Show (runtime state); the release optimizer handles
nested `@container` groups (`groupAtRules` contains `container`) and keeps the rules (their selectors name objects in the
HTML); `StaticRuntimeBundle` only rewrites script tags; `StaticOutputReferenceAudit` has nothing to resolve in a wrapper.

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-0605-001 Authoritative state | Met | Unchanged model (`CanonicalContainerQueries` strict encoding, schema 27); no new key. |
| SF-0605-002 Create and modify | Met | Unchanged registry/Inspector; new finding texts in existing labelled captions. |
| SF-0605-003 Resolution rules | Met | One shared walk (`container(for:…, unqueryable:)`) and `evaluated` drive canvas/Preview/Inspector/audit and export (wrappers, unique names, `not` cancels); Show keeps own display and reveals on static pages; page-flow boundary reported (OD proposal below). Tests 1–4 below. |
| SF-0605-004 Failure and recovery | Met | `container-query-container-positioned` and `container-query-show-without-layout` with recovery text; Hug fallback unchanged. |
| SF-0605-005 History and persistence | Met | No new mutation path; existing transaction/undo tests unchanged. |
| SF-0605-006 Accessible operation | Met | Wrapper has no role/focus/text; DOM order unchanged; Inspector captions keep identifiers `inspector.containerQuery.containerState`. |
| SF-0605-007 Performance and scale | Met | Work only on pages with rules (`hasRules` guards); O(objects × rules × depth) per build; no main-actor work added. |
| SF-0605-008 Diagnostics and tests | Met (not yet run) | Findings by stable identity only; 4 new tests + 1 strengthened. |
| SF-0603-003 Adaptive visibility in export | Met | Conditional hides keep V14a's specificity/ranges; unchanged without Show rules. |
| SF-1204-003 CSS generation | Met | One complete rule per line; release minifies/keeps them (test). |

## New / changed test selectors

- `SiteForgeTests/CommandKernelTests/testStaticLayoutContainerQueriesWrapQueriedContentsWithoutMovingAnything` (new): canvas
  448 pt / tablet 348 pt equals the wrapper widths; wrapper follows the Panel and holds Caption/Row/Chip in order; HTML
  without the wrapper tags equals the page without rules; every CSS line of the page without rules is unchanged and exactly
  three lines are added; a page without rules has no wrapper.
- `SiteForgeTests/CommandKernelTests/testStaticLayoutContainerQueryWrappersNestFollowInteractionsLanguagesAndRelease` (new):
  nested Panel/Row wrappers, unnamed rule → Row, named → Panel (canvas statuses agree); Panel hidden by an interaction:
  wrappers carry `data-siteforge-cq-within`, new sibling rule, ADR-0065 rule unchanged, contents keep
  `data-siteforge-within`; Arabic tree (`dir="rtl"`) has the same wrappers; Static Release keeps every wrapper/`@container`
  line (minified), HTML keeps the tags, integrity manifest hashes the written HTML.
- `SiteForgeTests/CommandKernelTests/testStaticLayoutContainerHoldingAPositionedObjectIsNotQueried` (new).
- `SiteForgeTests/CommandKernelTests/testContainerQueryShowRevealsHiddenObjectsAndKeepsTheirOwnDisplay` (new): Text and
  Button keep `display:flex`, no `display` in any `@container` line, phone-hidden Caption revealed when the 500 pt Panel
  matches and hidden on a 250 pt phone Panel (canvas), conditional phone hide and `display: block` layout rule in CSS; page
  with page flow: no `display` from Show, the Row keeps `display:flex`, the phone-hidden Chip stays hidden with
  `container-query-show-without-layout`.
- `SiteForgeTests/CommandKernelTests/testContainerQueryExportHidesTextAboveItsDisplayRule` (changed, strengthened).

## Remaining work (blocked only)

- Compile and run the tests on a Mac (no Swift toolchain on this PC).
- A browser run of an exported static-layout page with container queries at several widths (no browser on this PC); the
  C10 harness pattern (`Tests/Tooling/interaction_runtime_browser.py`) could gain a container-query case later.
- Proposed OD (owner decision needed; recommended default already implemented): **Container-query Show on pages with page
  flow for an object hidden at that breakpoint.** Context: `ConnectedPageOutput` lays out only visible objects per
  breakpoint, so a revealed object would have no position and its siblings would not make room. Recommended default (built):
  keep it hidden there on canvas and in export and say why (`container-query-show-without-layout`, recovery: show it at that
  breakpoint in Visibility and hide it with a rule). Alternative: write a second layout for that breakpoint under the
  container condition (the object and its reflowed siblings), a larger change to `ConnectedPageOutput`. Affected:
  SF-0605-003/004, SF-0603-003.

## Intended doc changes for the coordinator

- OPEN_DECISIONS.md (next free numbers, or the number V14a's proposal gets):
  - "## OD-<n> — Container queries on static-layout pages (SF-0605-003)\n- Status: **Approved by the owner 2026-11-26 9:55 PM EST** (alternative chosen: make them work in browsers). Implemented by lane V19 (ADR-0031 amendment): each queried container's contents are written in a zero-origin content-box wrapper (`container-type: inline-size`, `sf-cq-<name> sf-cqid-<id>`); positions, order, accessibility, interactions, motion, language trees, collection pages and Static Release unchanged; a container holding a positioned object or overlay can't be queried on such pages (`container-query-container-positioned`). Unverified until Codex builds and runs the tests."
  - "## OD-<n+1> — Container-query Show restores the object's own display (SF-0605-003)\n- Status: **Approved by the owner 2026-11-26 9:55 PM EST** (fix now). Implemented by lane V19 (ADR-0143 amendment): Show writes no `display` and lifts hides (later rule wins in browsers as on the canvas; static pages reveal objects hidden at another breakpoint); on pages with page flow an object hidden at that breakpoint stays hidden (`container-query-show-without-layout`). Unverified until Codex builds and runs the tests."
  - New proposed OD from "Remaining work" above, with its recommended default (status Proposed).
- ADR-0031 Consequences (V14a's intended line still valid): "The Hug-width fallback is a defensive gate…".
- Activity/plan line: "Lane V19: container queries now work in browsers on static-layout pages (zero-origin content-box wrapper per queried container; positioned objects/overlays keep the page and make their container unqueryable there); container-query Show writes no display and lifts hides, revealing objects hidden at another breakpoint on static pages; later Show rules beat earlier hides in browsers as on the canvas (unverified, lane V19)."
- docs/TESTING.md selector list: add the four new `CommandKernelTests` selectors above.

## Suggested first checks for Codex

1. `InsertionModel.swift` `StaticContainerQueryWrapping.unqueryableContainers` / `visibilityGroups`:
   `while case .node(let ancestorID)? = parent, let ancestor = nodesByID[ancestorID], steps < nodesByID.count` with
   `var parent = nodesByID[id]?.parent, steps = 0` (optional parent pattern).
2. `pinnedNodeIDs`: `page.nodes.filter(keepsOwnPositioning)` (static method reference), `positioning.mode != .static`.
3. `StaticVisibilityOutputEmitter.emit`: `for breakpoint in breakpoints where !shows.isEmpty && hiddenAt.contains(breakpoint)`
   mutating `hiddenAt` in the body; `.map(rule)` with the new `private static func rule(_:)`.
4. `evaluated`: `if connected, case .boolean(false)? = applied["hidden"]?.0, let visibleIDs, …`.
5. `CanvasRendererCore.swift` `StaticContainerQueryOutputEmitter.emit`: labelled tuple array append
   `resolved.append((rule, container, …))`, `resolved.suffix(from: index + 1).filter { … }.map { later -> String in … }`.
6. `StaticContainerQueryWrapping.css`: `CanonicalFluidValueCodec.value(for: .width, node:).flatMap { StaticFluidValueOutputEmitter.expression(for: $0.0) }`
   and `contentInset(of:on:breakpoint:reusableStyles:)` skipping defaulted labels.
7. `SafeHTMLEmitter.emit` nested `holds(_:_:)` and `guard try !hasFlowAncestor(node) else { continue }`.
8. Tests: exact wrapper strings (`width:448.0px`, `width:348.0px`, `width:300.0px`, `width:500.0px`), the nested hide
   string in the V04 test, `" dir=\"rtl\""` for the `ar` tree (`SiteLanguageOutput` direction for `ar`), and
   `html[chipStart..<chipTagEnd].contains(…)` (Substring search in the Chip's opening tag).
9. Existing `CanvasRendererTests/testContainerQueriesFollowEachCopysContainerOnCanvasPreviewAndExport` and the V16 test
   `CommandKernelTests/testContainerQueriesMeasureTheContentBoxInsidePaddingAndBorderLikeBrowsers` still assert the element
   container line and authored `@container` heads, which are unchanged.

## Out-of-area observations (not changed)

- Container opacity on static-layout pages applies only to the container's own element in export (contents are separate
  elements); not compared against the canvas in this lane.
- `symcheck`/`labelcheck` against RP-2026-11-26-V19 report only standard-library members for this lane; their
  `CanvasTextRenderingTests.swift` and `WorkspaceShellView.swift:17759` entries come from other lanes' concurrent edits.

## Write problems

None: no `AnchorError`, no `ICloudRenameError`, no foreign changes, no iCloud duplicates. Scratch helper files written outside
the tree: `_quick-scratch/review/v19_newenums.txt`, `v19_tests.txt`, `added_lines_v19.json` (checker output).
