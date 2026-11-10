# SF-LOCAL-BUILDER-014 — stable Inspector layout

IN PROGRESS — SOURCE IMPLEMENTED, ACCEPTANCE DEFERRED. No compilation, tests,
parser/lint/check scripts, app/browser launches, screenshots, visual comparison,
performance run or verification executed. Mandatory verification remains required,
not waived. No commit/push/install/sign/release or owner project/recovery edit.
Preserve007–013, frozen title acceptance, coordinator files and OD-018/019.

## Contract and source findings

Bounded SF-0201-009 (adaptive accessible native chrome), SF-0202-003
(navigation does not mutate content), SF-0203-006 (existing accessible commands),
SF-0701-002/003/006 (Inspector discovery, truthful provenance/mixed state and
accessible operation). Modules stay Partial. No new canonical capability,
property, schema, component decision, theme, icon or Settings geometry.

Read AGENTS, these exact specification clauses, OPEN_DECISIONS, current visual
contract,012/013 receipts, shared shell implementation/tests and current dirty
diff. Original concept01/05/12 images are not present in the inspected repository
image inventory; documented direction is not a new original-render comparison.
Existing screenshots do not verify this changed source.

Concrete findings and source corrections:

- Tab labels were measured in the strip, but pane minima used only a root-width
  threshold. The shell now uses the same current-font/current-label demand,
  bounded by the existing maximum allocation. Each strip still allocates from
  its own actual GeometryReader width, not the window width. No state-writing
  geometry preferences or feedback loop. Default32-point rows grow for larger
  font metrics; native overflow menu text grows too. One row only, no scrolling,
  tiny type or extra pointer-focus decoration; existing keyboard focus survives.
- Inspector's outer stack now aligns leading. Group/disclosure surfaces use
  full-width header → divider → content framing, shared insets/material/contrast
  tokens. Disclosure headers and contents share one card instead of an external
  header plus an inner card. Component property cards no longer sit inside a
  second enclosing decorative card. Settings styles are unchanged.
- `InspectorField` gives fields a persistent label above their usable width.
  `InspectorColumnsLayout` uses label-based minimum traits, not draft/editor
  string widths; typing cannot choose a different column count. Native fields
  retain their own focus/draft identity. `InspectorActionLayout` wraps existing
  actions using measured bounds without duplicating controls or switching view
  branches on width. Long action labels grow vertically rather than shrink.

## Exact source-derived fit boundary

For five labels at the current scaled semibold font, the required pane width is:

`sum(ceil(label glyph widths)) + 5×8 + 4×2 + 2×3 + 2×12`.

The terms are segment padding, gaps, strip inset and pane gutters. A strip below
that measured threshold uses the existing native explicit overflow, retaining
all five complete choices. Surplus width fills the usable row. Row height is
`max(32, ceil(ascender − descender + leading) + 2×6)`, plus the strip's outer
insets. No fixed claim about all labels fitting at200% is made.

Existing supported minimum remains1100×700, canvas minimum500, pane maxima360/
420. Base minima are250/280 below1280 and324/356 at1280+. Each pane minimum may
rise to its measured complete-strip demand only if that demand fits its existing
maximum budget. Otherwise the base minimum and accessible overflow remain.
Thus a usable content width slightly below1280 is not automatically treated as
too narrow when its measured strips can fit. No implicit window growth.

Future acceptance matrix (ALL UNRUN):

| Shell width | Existing base pane limits | Required review |
| --- | --- | --- |
| 1100 | Navigator250…282.57; Inspector280…315.43 | Native overflow where necessary, compact fields/actions, canvas≥500 |
| 1280 | Navigator324…360; Inspector356…418 | Five complete standard-size labels in each row, usable field widths |
| 1440 /1710 | Navigator324…360; Inspector356…420 | Complete rows fill usable width, consistent gutters/cards |
| 1182 /1200 /1278 | Existing proportional maxima, measured minima promotion | No abrupt window-threshold starvation; never steal canvas budget |
| Each at150%/200% text | Same maximum budgets; font-metric row height | Complete direct labels or explicit accessible overflow; no clipping |

Limits above describe source constraints, not measured runtime pane sizes. The
new regression source uses actual AppKit text measurement and intermediate pane
widths rather than presuming that a pane equals the window.

## Representative before/after action paths

| Surface | Previous source pressure | Current source path |
| --- | --- | --- |
| Selected-object header | Loose summary, formatting prose and progress could change horizontal alignment | One leading full-width summary card; same directly reachable Reuse Formatting and visible mixed/error/progress feedback; static explanation in help |
| Header/Footer | Placeholder-only title, label/value side rows and fixed action rows | Persistent title/height/inner-spacing/links labels, full-width editors, wrapping Apply/Cancel; same Return/Apply, Escape/Cancel, include-page/menu commands |
| Text Essentials/Design | Weight/alignment competed horizontally; three numeric fields always shared a row; reset competed with color editor | Adaptive labeled fields; numeric label-based columns; color editor and reset on separate lines; same font chooser, mixed values and central typography/style registry |
| Component Content | Long grouped names/recovery headings clipped; fixed traversal/action rows; nested cards | Complete wrapping names and retained values, adaptive original/independent/traversal/apply actions, distinct existing property cards and recovery; same source/return IDs and counted resets |

No primary-object borrowing was added: single/mixed/unavailable typography and
appearance projections still use their existing registries; component edits
still require an exact compatible single selection. Locked/hidden/missing states
keep current reasons/guards. Unsupported supplied slots and conflict migrations
remain behind OD-018/019, not new controls.

## Second independent source re-walk

Rechecked empty Inspector, one/multiple/locked selection gates, missing originals,
retained long values, validation appearing/disappearing, all five destinations,
pane dragging, font scale, Reduce Transparency/Increased Contrast and focused
editors. Corrected fixed-height enlarged tabs and draft-dependent column sizing
found in this pass. Layout is derived only; no new `.id`, keystroke commit,
focus reset, canonical mutation, history operation or command route. Existing
IME/stale/revision/selection validation and native Return/focus-loss/Escape
semantics remain. Error/help can grow vertically; this is not a promise of fixed
vertical positions or tested VoiceOver/render equivalence.

## Focused regression source — all UNRUN

New code selectors:

- `SiteForgeTests/WorkspaceMaterialPolicyTests/testMeasuredSidebarTabsHonorActualPaneBudgetAtNormalCompactAndIncreasedText`
- `SiteForgeTests/WorkspaceMaterialPolicyTests/testInspectorActionFlowKeepsLongActionsOrderedContainedAndNonoverlapping`
- `SiteForgeTests/WorkspaceMaterialPolicyTests/testInspectorFieldColumnsUseCompleteMinimumsInsteadOfSqueezingOrTinyType`
- `SiteForgeTests/CanvasViewportTests/testInspectorPanePresentationPreservesDraftSelectionHistoryAndCanonicalBytes`

Minimally affected existing selector, refined UNRUN:
`SiteForgeTests/WorkspaceMaterialPolicyTests/testNativeOverflowPaintsTheDisplayedPullDownItemAndRetainsAccessibleControl`.
Existing default-size regression retained:
`SiteForgeTests/WorkspaceMaterialPolicyTests/testNormalPaneMinimaFitAllFiveMeasuredDestinationLabelsWithoutOverflow`.

One new future native selector:
`SiteForgeUITests/SiteForgeLaunchTests/testStableInspectorStripsFieldsDraftsAndComponentRecoveryAtNormalAndCompactWidthsJourney`.
It uses real controls/native window resizing, checks complete labels, shared-row
bounds/fill, nonoverlap, focus, invalid-draft/Escape retention, Header/Footer,
Text appearance and component original/copy/missing-property recovery/Undo.
Seven named screenshots are planned in its source, none captured. This is not a
pass receipt. Live pane dragging, wider-window/increased-text, contrast/focus and
original-resolution visual review still need authorized acceptance, followed by
the required final gate. Do not launch it automatically or start015.

Source paths: `WorkspaceShellModel.swift`, `WorkspaceMaterialPolicy.swift`,
`WorkspaceShellView.swift`; the three test files named above. No new architecture
decision is needed for these derived view-layout adapters. Remaining capability
scope and previous source limitations are unchanged.
