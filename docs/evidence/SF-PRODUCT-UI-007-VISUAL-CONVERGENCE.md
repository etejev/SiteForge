# SF-PRODUCT-UI-007 — Whole-app visual convergence

Verification checkpoint (2026-10-12): the focused keyboard, responsive,
structural-layout, and Form accessibility journeys are green. The complete
actual-app target passed 104/104 journeys, and the one stale native-tab policy
expectation exposed by the first full gate was corrected and passed its exact
focused selector. Original-resolution dark, selected, practical-minimum, and
light/reduced-transparency evidence was reviewed again.

## Scope

Bounded evidence for `SF-0201-002`, `SF-0201-003`, `SF-0201-006`,
`SF-0201-008`, `SF-0203-006`, `SF-0203-008`, `SF-1505-006`–`008`, and
`SF-1605-002`, `SF-1605-006`–`008`. The thirteen owner-provided directional
renders were treated as a family of concepts, not pixel specifications. The
owner subsequently named `04-settings-appearance.png` as the primary reference
for cohesive gray-blue chrome, padding, balanced panes, and vertical Settings
navigation. The specification, repeated visual patterns, native macOS behavior, and scalable
accessibility take precedence in that order.

## Synthesized design system

- One calm three-region editor: balanced gray-blue navigator and Inspector around an
  opaque blue-neutral pasteboard, bounded artboard, and authored content.
- Native semantic type roles; an 8-point-derived spacing rhythm; 7-point
  controls, 14-point cards, and a 20-point launch card.
- System materials and dynamic colors extend through toolbar, pane chrome,
  status, launch, and Settings. The macOS accent color owns primary
  action and selection; supporting borders and surfaces stay neutral.
- Persistent viewport controls prefer one compact row and fall back only when
  the center viewport is genuinely constrained.
- Navigator and Inspector destinations never truncate or wrap. At constrained
  pane widths they remain one row in a horizontal scroll surface with the
  native overflow menu.
- Empty, loading, recovery, unavailable, and Settings states share the same
  readable header/card hierarchy without fabricating capabilities.

## Gap matrix and corrections

| Surface | Before | Correction | Focused review |
| --- | --- | --- | --- |
| Welcome/loading/recovery | Correct native state, but bespoke spacing/type metrics | Shared launch metrics and semantic title/callout hierarchy | Welcome and recovery inspected in a normal maximized window |
| Navigator | Last destination visibly clipped or wrapped | Stable one-row strip; constrained widths scroll horizontally and retain the native overflow menu | All five labels share one row when space permits; the practical minimum never creates a second row |
| Viewport header | Always consumed two rows even with ample canvas width | One-row maximized layout with width-driven two-row fallback; empty/off-artboard context retains its own row | Breakpoint, Compare, Grid, zoom, Actual Size, Fit Canvas, and Fit Document visible |
| Canvas | Gray wash flattened pasteboard, artboard, and pane hierarchy; the centered empty card resembled authored content | Shared dynamic pasteboard/grid/artboard palette; compact `Blank artboard` header hint replaces the centered card | Dark selected, blank, practical-minimum, and light increased-contrast/Reduce-Transparency states inspected |
| Inspector | Final destinations clipped or wrapped | Same stable one-row scroll/overflow primitive as navigator | Design/Layout/Content/Interactions/Accessibility remain one row |
| Settings | Separate top tabs and bespoke heading/spacing patterns | Native vertical sidebar plus shared header, scope, detail, icon tile, group spacing, and 680-point readable content width | Source and focused build reviewed; a clean retained capture was blocked by the macOS private-window inspection permission prompt |
| Status/error/unavailable | Existing native semantics were truthful | Retained semantic colors and accessibility; no decorative gradients or fake capabilities added | Saved/Ready and Nothing Selected remain readable |

## Directional-render conformance

| Render | Adopted direction | Deliberately rejected or deferred |
| --- | --- | --- |
| 01 Editorial canvas | Three-region shell, bounded artboard, compact viewport controls | Pixel-specific light-only palette |
| 02 Editorial Layout Inspector | Rulers, page hierarchy, dense but readable Inspector | Mock property controls not backed by canonical commands |
| 03 Launch/opening | Strong identity, primary creation/open actions, visible progress hierarchy | Separate dashboard window |
| 04 Settings appearance | Sidebar/card hierarchy and clear descriptions | Custom window chrome replacing native Settings tabs |
| 05 Responsive mobile | Persistent device and zoom controls, strong artboard context | Fake responsive reflow or device chrome |
| 06 Blank/inline text | Calm blank artboard and aligned inline editing | Fixture rectangles or screen-specific offsets |
| 07 Minimal loading | Single-task loading hierarchy | A second launch window |
| 08 Recents/recovery | Bounded recents and explicit recovery actions | Raw paths or cloud implications |
| 09 Elements/canvas/Inspector | Catalogue–canvas–Inspector rhythm | Unavailable catalogue entries presented as working |
| 10 Dark Design Inspector | Native dark materials and compact property groups | A hard-coded dark-only product theme |
| 11 Breakpoint comparison | Clear breakpoint identity and provenance | Simultaneous editable canvases outside current scope |
| 12 Canvas/accessibility Settings | Carded settings groups and preview-oriented explanation | Mock accessibility controls |
| 13 Assets/components | Thumbnail/list density and linked-instance provenance | Cloud libraries, folders, or marketplace UI |

## Retained evidence

- `docs/evidence/product-ui-convergence-welcome-before.png`
- `docs/evidence/product-ui-convergence-recovery-before.png`
- `docs/evidence/product-ui-convergence-welcome-after.png`
- `docs/evidence/product-ui-convergence-workspace-after.png`
- `docs/evidence/product-ui-convergence-selected-after.png`
- `docs/evidence/product-ui-convergence-blank-corrected.png`
- `docs/evidence/product-ui-convergence-minimum-corrected.png`
- `docs/evidence/product-ui-convergence-light-reduced-transparency.png`
- `docs/evidence/product-ui-convergence-blank-reference-corrected.png`

The corrected images were inspected at their original 3420 × 2004/2006 and
2200 × 1504 capture sizes. They show normal maximized and practical-minimum
windows, a distinctly blue-neutral gridded pasteboard, a bounded artboard,
material side panes, one-row destination strips, a compact blank-artboard hint,
aligned selected text, and no debug/fixture objects. The light capture also
enables Reduce Transparency and Increased Contrast and retains the hierarchy.
The universal macOS build, repository checks, and complete 104-test actual-app
target succeeded. The final documentation-inclusive `./sf verify` result is
recorded below; no commit, push, or hosted result is claimed.

The final blank-reference capture shows equal-ideal-width panes, cohesive
gray-blue chrome, the explicit “Your canvas is empty” message, real Frame/Text
actions, and an unobscured grid/artboard hierarchy. Settings was inspected live
with the required vertical sidebar, but the inspection tool raised a macOS
privacy prompt before a clean retained capture could be produced. The
contaminated capture is excluded from evidence and no system permission was
changed.

## Deferred acceptance

Broad increased-text/VoiceOver matrices, cross-hardware appearance review,
release performance, preview/export visual parity, and release acceptance
remain deferred. Visual convergence does not change canonical project data or
claim unavailable capability. The repository architecture checker now passes;
the earlier standalone-model dependency conflict is no longer an active
blocker.

## Verification

- Focused Form accessibility/history journey: 1/1 passed.
- Focused native Tab-routing policy regression: 1/1 passed.
- Complete actual-app target: 104/104 passed with zero failures.
- Final documentation-inclusive `./sf verify`: 567 unit/integration tests and
  104 actual-app UI journeys passed (671 total, zero failures). Result bundle:
  `full-05a92a22-d6bb-444d-8cfa-ac88d72a9b09.xcresult` in the local SiteForge
  test-results root.
