# SF-AUTHORING-122 — Connected layout/output integration

Development Prompt 9/10, 2026-10-13. SOURCE IMPLEMENTED; ACCEPTANCE UNRUN.
No tests, builds, compiler/parser checks, linters, repository scripts, UI
automation, installation, signing, commits, pushes or GitHub operations ran.
Existing changes and both testing add-ons are preserved.

## Contract and dependencies

SF-0501-003/004/005/006/008, SF-0502-003/005, SF-0503-003/004,
SF-0504-003/004, SF-0601-003, SF-0602-003, SF-0701-003/006,
SF-0806-002/003/004/006/008, SF-0304-003/005, SF-0308-004/008,
SF-1201-003, SF-1203-003/006, SF-1204-003/004.
Dependencies: SF-AUTHORING-121/ADR-0020, structural/responsive layout, typed
geometry/structure/link commands, immutable scene preparation, safe static
planning, component projection and transfer validation. Modules remain Partial.
No new schema, property namespace, document graph or persistence store.

## Delivered source behavior

- `ResolvedContainerLayoutPolicy` reads existing padding/gap/axis/alignment/
  columns once through the established cascade. Native structural geometry and
  connected output use that policy; `ConnectedPageLayoutSnapshot` carries the
  same frames, effective visibility, content height and cached child indices.
- Frame-owned connected flow preserves authored Section heights even when the
  Frame has padding. Padding is applied once, root bottom padding contributes
  to page height, Header stays first and Footer follows visible connected body
  content. Non-flow free children retain their authored world coordinates.
  Section/Stack/Grid still own their allocated content/cell bounds.
- Minimum-length redistribution now fixes clamped children before distributing
  remaining weight. This prevents the previous fitted-size overflow without
  changing canonical geometry or child identity/order. Work is bounded by one
  sort and passes, not repeated quadratic redistribution.
- Boundary lookup ignores hidden nodes, unavailable frames and root free
  objects. Insertion and drag markers use one shared boundary projection;
  markers remain transient and never become authored objects or saved geometry.
- Connected static pages retain the complete authored hierarchy, including
  nested Frame/Section/Stack/Grid and component-expanded descendants. The
  internal tree exposes actual resolved frames for connected pages instead of
  zero placeholders. Dangling/cyclic structured ownership fails safely.
- Connected pages no longer receive the legacy authored-absolute layout sheet.
  Their geometry sheet uses parent-local resolved coordinates, dynamic full
  content widths, bounded cell widths and owning horizontal Stack flex rules.
  Each declaration is emitted once after resolution. Borders remain inset
  paint rather than adding another content inset; padding has one layout owner.
  Non-renderable geometry-less legacy descendants retain identity but consume
  no output layout space. Unmarked pages retain their prior flat output path.
- A connected page has an explicit UTF-8/viewport document envelope and bounded
  page container. Historical generated route navigation is omitted there so it
  cannot displace the authored Header. Authored semantic header/section/main/
  footer/nav tags are preserved; no invented main landmark or sample content.
- Continuous breakpoint comparisons cover fractional widths below 600/1024,
  avoiding the previous integer-only CSS gaps. Fixed geometry and container
  overrides use the same inherited source; authored coordinates are not copied.
- Navigation uses shared bounded spacing/item allocation and row height across
  editor geometry and native Preview. Hidden links do not create an empty Menu;
  missing references remain disabled and named. Current-page and existing
  context intent survive projection. Canvas accessibility names page links and
  exposes repair help; the Content Inspector can reveal their actual owner.
- Exported navigation carries role-specific labels, full label help, current
  page semantics, expanded/control relationships and a real hamburger summary.
  Its fixed external script handles Escape/focus, closing other menus, outside
  click/focus exit and responsive collapse with visible-link/body focus fallback.
  Visitor state is not canonical. Native Preview continues to use the real Menu.
- Build diagnostics distinguish independent roots, positioned containing
  geometry, clipped expanded menus and fluid containing-layout combinations.
  Those unsupported combinations fail before output, never by dropping bindings
  or replacing fluid values with sampled literals. Original data stays intact.
- Isolated managed transfer remains rejected; ordinary free-object transfer
  remains supported. Existing schema-v16 serialization, complete-page duplication,
  exact history, component expansion and dependency identities remain intact.

## Unrun test source — seven unit/integration plus one UI

`InsertionModelTests`:

- testConnectedNestedContainerOutputUsesResolvedOwnershipAtAllBreakpoints
- testConnectedHiddenFlowBoundariesNeverUseInvisibleFrames
- testConnectedHorizontalStackMinimaRemainBoundedAndOutputHasSingleOwner
- testConnectedRootPaddingHeightRemovalAndReorderHaveExactHistory
- testConnectedNavigationVisibilityCapacityAccessibilityAndNoDecorativeMenu
- testConnectedOutputRejectsPositionedOrClippedMenusWithoutDroppingIntent
- testConnectedStructuredEmitterRejectsCyclesAndRetainsLegacyFlatOutput

`SiteForgeLaunchTests`:

- testConnectedNestedSectionContainerGeometryAndBreakpointJourney

The native source uses real Insert/Layers/Inspector/preset/Fit/Undo/Redo controls
in a fresh normal window and retains four planned screenshot states. No images
were captured. The model matrix includes Desktop/Tablet/Mobile, custom/fractional
widths, native/static/selection frame equality, padding, fitted minima, removal,
history, package serialization, responsive navigation and safe transfer.

Updated prior source acceptance, not weakened: the formerly blocked nested
output test now requires a plan and explicit preserved node markup. The 121
save/reopen journey selects `Legacy Surface`, the actual checked-in fixture
page, rather than an invented `Home` page. Existing identity/persistence/menu
assertions remain. Those journeys have not run in this source batch.

## Source review and remaining scope

Reviewed ownership, single-offset conversion, declaration precedence, bounded
work, visibility, stale callbacks, escaped links/labels, retained IDs, strict
decoding and existing assertions. No direct view-to-property write, duplicated
canonical layout store, debug fixture, new machine path or external service.
Root style/ordinary-child interactions, minimum-size rounding, CSS flex/grid/
outline behavior, component-containing layout and native menu focus require
actual Prompt-10 execution and original-resolution visual review.

Explicit exclusions: fixed/sticky page roles, unsupported positioned/fluid
containing output, multiple independent roots, clipped-container browser menu
portals, external navigation, supplied component slots (OD-018), arbitrary
retargeting (OD-019), general browser/style/compositing certification, publishing
and release acceptance. Legacy conversion stays explicit and undoable. The
implementation does not claim browser execution or visual parity from source.

Prompt 10 acceptance: follow `docs/PROMPT-10-ACCEPTANCE.md`. One detached full
collector owns the accumulated run and all final failure reporting. Do not run
it now, poll it through an agent, or start a duplicate broad gate.
