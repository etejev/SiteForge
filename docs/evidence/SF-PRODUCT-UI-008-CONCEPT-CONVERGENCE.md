# SF-PRODUCT-UI-008 — Concept-aligned visual-system correction

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED. Owner add-on; the ten-prompt feature counter remains at 3. Follow-up source reconciliation: 2026-10-13.

Requirements: `SF-0201-002/003/006/007/008`, `SF-0203-006`, `SF-0205-006/007`, `SF-0206-006/007`, `SF-0407-006/007`, `SF-1505-006/007/008`, and `SF-1605-002/006/007/008`.

## Synthesis

The concept set is directional rather than a pixel contract. Repeated decisions are now explicit in one semantic source: compact calm chrome, balanced navigator/Inspector ownership, a visually dominant bounded canvas, a restrained blue selection role, native vertical Settings navigation, readable bounded forms, and intentional launch/loading/recovery hierarchy. Contradictory concept-only capabilities were not enabled.

## Source changes

- Extended `SiteForgeVisualSystem` with one 8-point-derived spacing system, semantic row/field/status colors, shared radii, launch composition, Settings measurements, and toolbar grouping.
- Migrated shell tab surfaces and selection radii, launch padding/rhythm, and Settings sidebar/detail sizing to shared roles.
- Expanded the visual contract with canonical palette, measurements, material fallback, inactive-window, and cross-region alignment rules.
- Refined deterministic token/layout test source while preserving existing launch, Settings, appearance, minimum-window, pane, canvas, and accessibility journeys.

## Verification state

Per owner policy, no test, build, checker, UI automation, repository script, or verification command was executed. Prompt 10 must inspect actual app-only captures at original resolution for launch/loading/recovery; blank/populated/selected/inline editor; every navigator and Inspector destination; Desktop/Tablet/Mobile/comparison; every Settings destination; minimum/maximized; light/dark/inactive; Increased Contrast; and Reduce Transparency. Reference images and the diagnostic recording remain private local inputs and are not repository artifacts.

## Surface-by-surface source coverage

Every original concept image (01–13) was inspected at original resolution. The table records source decisions, not rendered acceptance. The diagnostic screenshot named in the owner prompt was unavailable at its supplied location; no new visual comparison against that screenshot is claimed.

| Production surface | Concept direction | Remaining drift addressed / governing production source |
| --- | --- | --- |
| Startup and loading | 03, 07 | `LaunchExperienceView` retains real lifecycle progress and cancellation; shared brand, section rhythm, semantic panel and launch shadow measurements replace local spacing. No fabricated progress stages. |
| Welcome, New, Open | 03, 08 | Approved icon and native Blank/Starter/Open actions retain their adaptive horizontal/vertical layout; shared launch card, typography roles and margins govern all states. |
| Recent projects | 03, 08 | Bounded rows now use elevated semantic surface, common radius/insets and readable metadata. Project names remain single-line; private paths remain excluded. |
| Missing-project recovery and load failure | 08 | Same launch identity/card hierarchy; semantic warning treatment, wrapped recovery copy and native actions. Existing recovery/authorization behavior is unchanged. |
| Titlebar and authoring toolbar | 01, 02, 06, 09 | Native document title/modified state remain AppKit-owned; selected tools now use semantic accent. Persistent primary tools, More Tools, history and Preview retain native roles and enabled states. |
| Pages | 01, 02, 09 | Shared pane inset/tab strip, search controls and selected-row surface; native focus remains independent. Page metadata stays readable and truncates truthfully. |
| Layers | 01, 02, 05, 06 | Same row height, selection/hover/inactive treatment as Pages; hidden/locked states remain explicit text/icons. No change to ordered IDs or selection commands. |
| Elements | 09 | Catalogue receives shared pane spacing and inherited native group style. Existing native entries/disabled states remain authoritative; no concept-only entries are enabled. |
| Assets | 13 | Search/filter/list rhythm is migrated; thumbnails use semantic field surface and a shared 48-point size; rows use common selection/hover geometry and native context menus. |
| Components | 13 | Definition cards and details inherit shared groups; revealed rows use the same row surface/radius/inset. Existing component property and transfer paths are untouched. |
| Viewport control strip | 01, 02, 05, 09, 11 | Existing width-driven layout retains preset, width, comparison, Grid, zoom and Fit order. Context hint now wraps within a bounded semantic width rather than forcing the header beyond its available width. |
| Pasteboard, grid, viewport and artboard | 01, 05, 09, 11 | Existing semantic dynamic colors, world anchoring, fitted gutters and artboard clipping remain the sole drawing hierarchy. No source coordinate/fit/render transform was changed. |
| Blank canvas | 06 | Compact bounded header hint remains present with real insertion actions; no central mock website/card or fixture content is introduced. |
| Populated and selected canvas | 01, 02, 09 | Shared editor selection roles remain distinct from authored pixels; artboard intersection, handles and badge placement are unchanged. |
| Inline editing | 06 | Shared text layout, native NSTextView and selection geometry remain unchanged. Source migration stops before authored/preview drawing code. |
| Design Inspector | 01, 10 | Shared native GroupBox style establishes heading, separator, surface, inset and contrast. Fill, typography, image and box-style controls retain the same transactions and intrinsic native control behavior. |
| Layout Inspector | 02, 05, 11 | Same grouping, spacing, provenance and validation styling; responsive and container controls retain their canonical resolution. Bottom clearance remains a semantic token. |
| Content Inspector | 06, 13 | Same group treatment for text/forms/component properties. Stable values, scene-local drafts and disabled states are retained. |
| Interactions Inspector | 09, 10 | Native link/control groups use the same hierarchy and semantic validation colors. No future event graph is implied. |
| Accessibility Inspector | 10 | Same grouping/provenance/validation treatment for existing authored semantics; focus and accessible values are preserved. |
| Desktop, Tablet and Mobile | 05, 11 | Same header/pasteboard/artboard source; active preset and canonical resolved geometry remain unchanged. Source styling does not manufacture responsive reflow. |
| Comparison | 11 | Existing scene-local review cards now use common spacing, elevated surface and control radius; factual current/difference/provenance values remain the content. No concept-only image comparison engine is added. |
| Settings sidebar | 04, 12 | Native left sidebar now includes the read-only inherited Accessibility destination. Single-line native rows, common insets and bounded detail width replace independent page measurements. |
| Appearance Settings | 04 | Shared header/card/form width/padding; existing native appearance radio control retains current transaction/cancel behavior. No unsupported accent picker is added. |
| Canvas Settings | 12 | Shared form/group style and explicit application-default scope. Existing Grid preference remains the actual implemented control. |
| Accessibility Settings | 12 | Read-only native rows report inherited Reduce Transparency, Increase Contrast and Reduce Motion and explain keyboard/VoiceOver behavior. No second preference store or pretend toggles. |
| Defaults, Updates and Support | 04, 12 | Shared bounded form geometry and native group treatment; report field uses semantic field surface. OD-017 updater gating and support/privacy behavior remain unchanged. |
| Light/dark, inactive, contrast, transparency | 04, 05, 10, 12, 13 | Separate dynamic palette definitions remain; fallback chrome/elevated colors are now opaque. Shared rows handle hover and inactive selection; shared cards/groups strengthen contrast and honor Reduce Transparency. |

## Shared consumers and source review

`SiteForgeInspectorGroupStyle` is inherited by Navigator, all five Inspector destinations, and all Settings detail destinations. It preserves native content accessibility children and draws non-interactive decoration. `SiteForgeRowSurface` owns Pages/Layers/Assets/Components/tab selection, minimum row height, hover and inactive states. `SiteForgeVisualSystem` owns pane, form, header, thumbnail, clearance, status and launch measurements; ordinary editor stacks and recovery/validation labels were migrated to these roles. Native `.bar`/AppKit materials, zero-spacing composition containers, field-specific widths and authored preview colors remain intentional distinct responsibilities.

Review was read-only source/diff inspection. No component/action code, canonical serializer, command registry, authored geometry, app icon, updater policy, rendering transforms or private reference media changed in this follow-up.

## Acceptance source and remaining visual gate

- New `testConceptAlignedSettingsHasOneSidebarIncludingInheritedAccessibility` covers destination identities and balanced pane ownership.
- New `testConceptAlignedSettingsSidebarAndInheritedAccessibilityJourney` checks left-sidebar placement, every Settings destination and truthful read-only inherited preference controls, retaining named screenshots.
- Existing `testOpaqueHighContrastDarkAndInactiveMaterialStatesRemainOperable` includes one-row destination/control assertions; existing launch/loading, grid/artboard, selected/inline, minimum-window and Settings journeys remain the Prompt-10 matrix.
- All are unrun. Rendered contrast, hover/focus, practical-minimum scroll reachability, increased-text layout, material sampling and actual app screenshot comparisons remain required at Prompt 10. No pixel or runtime visual pass is claimed.

Excluded render-only ideas: marketplace templates/stock images, video/SVG library tabs, unsupported publishing actions, invented stage timelines, per-side spacing or extra style modes not implemented, and decorative websites in blank projects. Concept titlebar/menu layouts do not override native macOS menu/window conventions.
