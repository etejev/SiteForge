# LANE-V14a review — 2026-11-26 (cross-tree verifier: hidden content in export, fixed positioning, container-query fixture)

Owner tag `lane-V14a`. Restore point before: RP-2026-11-26-V14 (state after phase 1). All writes through
`forge_io.edit` / `write_new`; `check([...]) == []` after every edit; `foreign_changes(30) == []` and
`icloud_duplicates() == []` before the first write and at every later check. Verification by reading only
(no Swift toolchain, no browser on the PC).

## Scope

Manifest items (scope_V14a.json):
1. Hidden text may still show in exported pages (LANE-V04 out-of-area): every hide path — visibility settings
   (desktop `hidden`, breakpoint overrides), container-query hide, interaction start-hidden, overlays, localized
   trees, collection item/list pages, C6 bound text.
2. Fixed-position objects may be misplaced in Preview and in the responsive audit (LANE-V04 out-of-area).
3. `CanvasRendererTests/testContainerQueriesFollowEachCopysContainerOnCanvasPreviewAndExport` builds an invalid
   Hug-width fixture (LANE-V16 out-of-area).

Modules: SF-0601 (breakpoint cascade), SF-0603 (adaptive visibility), SF-0605 (container queries), SF-0606
(responsive audit). Files: `SiteForge/InsertionModel.swift`, `SiteForge/CanvasRendererCore.swift`,
`SiteForge/WorkspaceShellModel.swift`, `Tests/SiteForgeTests/CanvasRendererTests.swift`,
`Tests/SiteForgeTests/InsertionModelTests.swift`.

## Item 1 — hidden content in exported pages

### Findings (all verified against current code)
- Every object is written to the HTML; hiding is CSS only (`InternalDocumentRenderTreeCompiler.compile` maps
  `canonicalDepthFirstNodes()` without a visibility filter; `SafeHTMLEmitter.emit`).
- Static-layout pages (no page-flow role, no automatic sizing) are written flat: `SafeHTMLEmitter.emit` nests
  children only when `structured || pageFlowRole != nil || nested`, so each object is its own top-level element.
- `StaticLayoutOutputEmitter.baseRule/responsiveRule` hide with `[data-siteforge-node="id"] { display: none; }`
  (specificity 0,1,0). `StaticTypographyOutputEmitter` gives Text `…[data-siteforge-node] { display:flex … }`
  (0,2,0) and Buttons/Links `…:is(a,button) { display:flex … }` (0,1,1), written later. Canvas hides an object and
  all its descendants (`DocumentPage.effectiveVisibleNodeIDs`).

### Defects and fixes
| # | File | Symbol | Defect | Fix |
|---|------|--------|--------|-----|
| 1 | `SiteForge/InsertionModel.swift` | new `StaticVisibilityOutputEmitter.emit(pages:)` | Static-layout pages: hidden Text, Buttons and Links still showed (plain `display: none` lost to the typography/control `display`), and the contents of a hidden Frame/Stack showed (flat HTML) — at desktop and at every breakpoint. | For every static-layout page (`!usesConnectedOutput`) and breakpoint, every node outside `effectiveVisibleNodeIDs(breakpoint:)` gets `[…][data-siteforge-node] { display:none; }`; hidden at all three breakpoints → one unconditional rule, otherwise one `@media <range>` line per breakpoint where hidden, so another breakpoint can still show it. First page wins per node ID (list copies). One complete rule per line (ADR-0120 minifier). |
| 2 | `SiteForge/InsertionModel.swift` | new `ResponsiveBreakpoint.cssRangeCondition` | No media range existed for "desktop only" (desktop rules are unconditional). | `cssMediaCondition ?? "(min-width: 1024px)"` (complement of tablet's `width < 1024px`, same half-open ranges as `resolving(width:)`). |
| 3 | `SiteForge/InsertionModel.swift` | new `ConnectedPageOutput.hiddenRule(_:breakpoint:)`, used in `css(pages:)` (2 sites) and `fluidFlowRules` (1 site) | Connected pages: only Text hides used `[data-siteforge-node]`; a hidden Button/Link showed (`:is(a,button)` wins). And the desktop hide was unconditional at (0,2,0), so Text hidden on desktop but shown on tablet/phone stayed hidden there (the plain tablet/phone rule lost). | All kinds hide with `[data-siteforge-node]`; the desktop hide is wrapped in `@media (min-width: 1024px)`. Tablet/phone hides are already inside their exclusive media blocks. |
| 4 | `SiteForge/CanvasRendererCore.swift` | `MultiPageStaticBuildPlanner` stylesheet assembly (`themedStylesheet`) | The dark-mode block repeats typography (`…[data-siteforge-node] { display:flex }`, font sizes) after the container queries, so in dark mode a container-query hide of Text and container-query text sizes lost (equal specificity, later wins); the new hide rules would have lost the same way. | `containerQueries` moved out of `stylesheet`; `themedStylesheet = [stylesheet + dark block, StaticVisibilityOutputEmitter.emit(pages: stylePages), containerQueries]`. Container rules still come after every layout rule (existing assertion). |

### Hide paths checked and found correct (no change)
- Interaction start-hidden / runtime hide: `hidden` attribute + `EventGraphOutput.hiddenCSS` (`!important`), and
  `FlatContainerOutput` (`[…][hidden] ~ [data-siteforge-within~=…]`, `!important`) for contents on static pages.
- Overlays: `overlayCSS` sets only position (`!important`), never `display`.
- Container-query hide: `[…][data-siteforge-node] { display: none; }` in its own `@container` block (lane V04),
  now also last in dark mode.
- Localized trees: one shared `styles.css`; node IDs are the same in every language tree.
- Collection item pages share the template's node IDs; list copies come from `CollectionLists.stylePages`.
- C6 bound text (`CanonicalTextBinding.outputPage`) changes text only.

### Evidence / tests
- New `CanvasRendererTests/testStaticLayoutExportHidesObjectsContentsAndTextOnlyWhereHidden`: Frame hidden on
  phones hides its Text child (phone `@media` line contains both rules), Text hidden only on desktop gets exactly
  `@media (min-width: 1024px) { … }` and nothing at tablet/phone or unconditionally, Text hidden everywhere gets one
  unconditional rule, the hide line comes after the Text's `display:flex` rule, the text stays in `index.html`.
- Changed `InsertionModelTests/testHiddenResponsiveFluidTextKeepsRendererOutputAndLayoutParticipationConsistent`:
  the old assertion looked for a plain `[card] { … display:none` line (the format that loses to `:is(a,button)` for
  the Button inside); it now requires the `[card][data-siteforge-node] { display:none; }` phone rule, no plain hide,
  no desktop hide, and adds the desktop-hidden/phone-shown case: `@media (min-width: 1024px) { … }` present and the
  rule appears exactly twice (desktop range + tablet block). Not weakened: every old guarantee is still asserted.
- Existing assertions re-checked against the new strings: `InsertionModelTests` lines with
  `[data-siteforge-node] { display:none; }` (Text hide) still match as substrings of the wrapped desktop rule;
  navigation `.sf-nav-*` / `.sf-page-navigation-*` hides are unchanged; `CommandKernelTests`/`CanvasRendererTests`
  `display: none;` / `display: block;` checks target the unchanged layout base rule.

## Item 2 — fixed positioning in Preview and the responsive audit

### Finding
`WorkspaceScenePreparationWorker` places fixed, sticky and page-level absolute objects from
`request.viewport.visibleWorldRect` (`positionedFrame`). `LocalPreviewRuntimeCompiler.compile` and
`ResponsiveAuditRunner.run` built `CanvasViewportState` with the default `worldOrigin (-128, -96)` (the editor's
scroll origin), while Preview shows the page from (0, 0) (`viewportBounds = bounds`) and the browser viewport starts
at the page corner. A fixed object with `left: 16` was drawn at x = −112 in Preview and reported by the audit as
overflowing the page by 112 pt.

### Fixes
| # | File | Symbol | Defect | Fix |
|---|------|--------|--------|-----|
| 5 | `SiteForge/WorkspaceShellModel.swift` | `LocalPreviewRuntimeCompiler.compile` | Fixed/sticky/page-level absolute objects offset by (−128, −96) in Preview. | `CanvasViewportState(worldOrigin: .init(x: 0, y: 0), viewportSize:…, contentBounds:…, pixelRatio:…)`. |
| 6 | `SiteForge/WorkspaceShellModel.swift` | `ResponsiveAuditRunner.run` | Same offset in the audit → false overflow (and possibly collision) findings. | Same `worldOrigin: (0, 0)`. |

Not changed: `ResponsiveBreakpointReviewWorker` keeps the default origin — `ResponsiveLayoutReviewPolicy` skips
fixed/sticky objects and their descendants by design (`viewportDependent`, asserted by
`CanvasViewportTests` "Viewport-dependent positioning is explicitly outside this review slice"). The editor canvas
keeps placing fixed objects from the visible editor area (intended editor behavior).

### Evidence / tests
- New `CanvasRendererTests/testPreviewAndResponsiveAuditPlaceFixedObjectsFromThePageCorner`: Preview at 390 pt puts
  a fixed `left 16 / top 20` object at (16, 20) and a fixed `right 10 / bottom 10` 120×40 object at (260, 850); the
  audit (standard samples) reports no overflow for either.

## Item 3 — Hug-width container-query fixture

### Finding
`containerQueryCardDocument(hugRoot: true)` adds `layout.sizing.v1.widthMode = "hug"` and calls
`document.validate()`, which throws `invalidSizingConstraints`: `CanonicalSizingConstraints.isValid` starts with
`guard widthMode != .hug`, and `CanonicalSizingNamespaceValidator.validate` runs for every node of every page
(`DocumentPage.validate`). The test therefore failed before any assertion.

Is the fallback reachable in a valid document? No: Hug width is refused on every node kind; variants can't set
sizing modes (`CanonicalComponentVariants.isVariantCapable`); instance overrides are text/visibility/choice/media/
action/slot only; `dimensionResolution` can only turn a declared mode into `.fixed` (breakpoint/fluid numbers);
container-query rules accept only `hidden`, opacity, text size/line height, width/height
(`CanonicalContainerQueries.accepts`). The branch is **kept**: ADR-0031 / OD-031 define "Hug containers are skipped
and reported", it is the single gate canvas, Preview, Inspector and export share (`isActiveContainer`), and it costs
nothing. Removing it would also remove `ContainerQueryFinding.containerHugs` used by the Inspector.

### Fix
| # | File | Symbol | Defect | Fix |
|---|------|--------|--------|-----|
| 7 | `Tests/SiteForgeTests/CanvasRendererTests.swift` | `testContainerQueriesFollowEachCopysContainerOnCanvasPreviewAndExport` | Invalid fixture; test failed at `validate()`. | The Hug part now asserts that the Hug fixture is refused (`.invalidSizingConstraints`), that the valid resolved page applies the wide copy's title rule, and — on the resolved page with a Hug width written onto both copies (a state a valid document can't produce) — that `isActiveContainer` is false, no rule applies (`winners` nil, status without container), and both `container-query-container-hugs` (wide copy) and `container-query-no-container` are reported. Canvas/Preview/export assertions for valid documents unchanged. |

## Requirement table (items in scope)
| Requirement | Status | Evidence |
|---|---|---|
| SF-0601-003 Resolution rules (breakpoint cascade in export) | Met | `StaticVisibilityOutputEmitter`, `ConnectedPageOutput.hiddenRule`; tests above |
| SF-0603-003 Resolution rules (hidden objects and contents) | Met | same; `effectiveVisibleNodeIDs` shared with canvas |
| SF-0603-008 Diagnostics and tests | Met | two new/changed tests |
| SF-0605-003 Resolution rules (container queries in export) | Partial | dark-mode order fixed; static-layout pages and Show rules — see out-of-area |
| SF-0605-004 Failure and recovery (Hug fallback) | Met | fallback kept as defensive gate; test fixed |
| SF-0606-003 Resolution rules (audit measures what the browser shows) | Met | `ResponsiveAuditRunner` origin; new test |
| SF-0606-008 Diagnostics and tests | Met | new test |

## New/changed test selectors
- `SiteForgeTests/CanvasRendererTests/testStaticLayoutExportHidesObjectsContentsAndTextOnlyWhereHidden` (new)
- `SiteForgeTests/CanvasRendererTests/testPreviewAndResponsiveAuditPlaceFixedObjectsFromThePageCorner` (new)
- `SiteForgeTests/CanvasRendererTests/testContainerQueriesFollowEachCopysContainerOnCanvasPreviewAndExport` (changed)
- `SiteForgeTests/InsertionModelTests/testHiddenResponsiveFluidTextKeepsRendererOutputAndLayoutParticipationConsistent` (changed)

## Out-of-area issues (not fixed; need a design decision)
- **Container queries on static-layout pages never match in a browser** (SF-0605-003). Static-layout pages are
  written flat (no DOM parent), so `@container` finds no container ancestor even though the canvas applies the rule.
  Proposed OD (V14a, recommended default): Check Website reports a container-query rule on a static-layout page as
  "applies on the canvas only" until static pages get nested output; no output format change in lane V.
- **Container-query "Show" (`hidden: false`) writes a plain `[…] { display: block; }`** (lane V04 design, asserted
  by `CommandKernelTests/testContainerQueryExportHidesTextAboveItsDisplayRule`). It overrides the flex/grid display
  of visible connected containers and Text when the rule matches, and it can't reveal an object hidden at that
  breakpoint by its visibility settings (now hidden with higher specificity; on connected pages such an object also
  has no layout at that breakpoint). Recommended default: write no `display` for Show on objects visible at every
  breakpoint, and report Show on breakpoint-hidden objects as canvas-only in Check Website.

## Remaining work
None in scope. Blocked-only: a browser run of an exported site (hidden objects at 390/768/1440 px, dark mode) and
a compiler/test run on a Mac — not available on this PC.

## Intended doc changes for the coordinator
- ADR-0031 (container queries), Consequences: "The Hug-width fallback is a defensive gate: document validation
  refuses a Hug width (`CanonicalSizingConstraints.isValid`), so a valid document never reaches it (lane V14a)."
- Activity/plan line: "V14a: hidden objects and their contents stay hidden in exported static-layout and connected
  pages at exactly the breakpoints the canvas hides them; container rules and hiding rules follow the dark-mode block;
  Preview and the responsive audit place fixed/sticky/page-level absolute objects from the page corner; Hug fixture
  fixed (unverified, lane V14a)."
- docs/TESTING.md selector list: add the two new selectors above (CanvasRendererTests).
- Record the two out-of-area proposals above as Open ODs with their recommended defaults (owner not asked).

## Suggested first checks for Codex
1. `InsertionModel.swift` `StaticVisibilityOutputEmitter.emit`: `Set(breakpoints.indices.filter { !visible[$0].contains(node.id) }.map { breakpoints[$0] })`,
   `hidden[$0]?.count == breakpoints.count`, nested `func rule` used with `.map(rule)`.
2. `ConnectedPageOutput.hiddenRule(selector, breakpoint: breakpoint)` at the three call sites (`css(pages:)` ×2,
   `fluidFlowRules` ×1): `breakpoint` is the loop variable in scope.
3. `CanvasRendererCore.swift` `themedStylesheet` assembly (`darkThemed`, then visibility, then container queries).
4. `CanvasRendererTests.testContainerQueriesFollowEachCopysContainerOnCanvasPreviewAndExport`: `XCTAssertThrowsError`
   with `$0 as? ModelValidationError`, `hugging.nodes[index].properties.append(NodeProperty(key:value:))`,
   `evaluation.statuses[wideTitle]?.first?.containerID`.
5. `InsertionModelTests.testHiddenResponsiveFluidTextKeepsRendererOutputAndLayoutParticipationConsistent`: the
   `count == 3` assertion assumes tablet inherits desktop visibility (`ResponsiveVisibilityResolver.value`) and
   the Card is laid out by the connected path (fluid adapter or not — both use `hiddenRule`).
6. `testPreviewAndResponsiveAuditPlaceFixedObjectsFromThePageCorner`: Preview viewport height is 900 pt
   (`LocalPreviewRuntimeCompiler`), so the bottom-fixed bar is expected at y = 850.

## Write problems
One read call timed out (device slow); it was read-only and re-run with a narrower read. No `AnchorError`, no
`ICloudRenameError`, no foreign changes, no iCloud duplicates.
