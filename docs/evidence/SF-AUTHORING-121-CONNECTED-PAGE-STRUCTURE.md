# SF-AUTHORING-121 — Connected page structure and Header/Footer navigation

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED. Prompt 8/10, 2026-10-13.
No tests, standalone compiler/parser/linter/check scripts, UI automation,
hosted CI, commits or pushes ran for this feature. The separate owner-authorized
experimental app build subsequently compiled this source successfully; that is
not acceptance. Original-resolution visuals are pending; screenshot attachments
are source only.

## Contract

Owner-approved clarification is in the searchable specification and ADR-0020.
Bounded IDs: SF-0501-001/003/004/005/006/008, SF-0502-003/005,
SF-0504-003/004, SF-0505-003, SF-0601-003, SF-0602-003,
SF-0701-003/006, SF-0806-001/002/003/004/005/006/008,
SF-0304-003/005, SF-0308-004/008, SF-1201-003 and SF-1203-003/006.
Dependencies: structural/responsive/geometry/style/link/Preview foundations,
SF-PRODUCT-UI-008 and preserved component work. Modules remain Partial.

## Delivered source behavior

- Schema v16 closed optional roles on existing Sections, not a second graph.
  New Header is first and Footer last among managed root siblings; body Sections
  share canonical ordering. New insertion sets defaults without viewport-derived
  X/Y/width storage. Header/Footer remain page-owned; component insertion and
  component conversion reject unsupported managed structures.
- One structural projection derives full allocated width, heights, vertical
  positions, content padding and responsive visibility. Root flow has no extra
  gap; Footer follows content, never screen bottom. Nested Section widths retain
  Stack/Grid cell ownership. Free Frames remain absolute. Page height expands
  for visible flow content, with a 900-point editor minimum; hidden content does
  not extend the boundary. Flow budgets and navigation minimum-height checks
  reject impossible state instead of shrinking or discarding authored intent.
- Native Header/Footer/Section settings show flow provenance, height, padding,
  shared Design/Accessibility guidance and explicit legacy conversion. Position/
  width/free/fixed/sticky/fluid controls do not pretend to edit managed geometry.
  Existing latent geometry is preserved. Mixed/partial selection is explicit;
  compatible height editing remains on the shared geometry registry.
- Pointer Section insertion displays a solid boundary marker; body drag reorders,
  the bottom handle edits height, anchors cannot freely move, and cancel/revision
  replacement clears scene-only drafts/markers. Registry confirmation/identity/
  selection/lifecycle/availability/lock/domain gates own canonical edits. No-op
  organization produces no history. Existing commands own exact inverses.
- Header/Footer link settings add/edit/remove/reorder ordinary Link children.
  Stable PageID destinations and node/property IDs survive rename, undo/redo,
  save/reopen and complete-page duplication. Default labels resolve current page
  names; deleted pages retain explicit missing references. Links are capped at
  32; metadata validates owner/kind/type/roles/labels and rejects malformed state.
- Hamburger setting affects immutable navigation snapshots. Editor keeps links
  inspectable; Mobile visitor Preview uses a real native Menu with page actions,
  keyboard and Escape/focus semantics. Inline navigation remains Desktop/Tablet.
  Empty navigation has no decorative menu. Static HTML escapes labels/hrefs,
  emits native details/summary and bounded responsive CSS; an external fixed
  `siteforge-navigation.js` handles Escape/focus without authored script strings.
- Root connected flow/ordinary descendants have structured HTML and shared
  frame/CSS projection. Unsupported isolated nested free-container and Stack/Grid
  flow output is blocked with `page-flow-containing-block`; native authoring and
  Preview remain available. Isolated clipboard transfer rejects flow/navigation
  with `unsupported-page-structure` rather than dropping metadata. No release,
  broad browser parity or arbitrary responsive navigation is claimed.
- Historical unmarked Sections and semantic Header/Footer templates remain
  unchanged on load. Explicit conversion derives layout while retaining original
  coordinates, responsive data, children and property IDs. Undo restores them.
  Older schema headers cannot accept new namespaces; supported fixtures are not
  rewritten. Current/future-schema assertions were updated, and the obsolete
  Section-centering test now asserts the approved flow behavior, not a weaker test.

## Unrun selectors — six new plus one updated

InsertionModelTests:

- testConnectedPageFlowAnchorsOrderDynamicWidthHeightAndHistory
- testPageFlowLegacyConversionRetainsExactAuthoredGeometryAndRejectsUnsafeEdits
- testHeaderNavigationStableLinksRenameDeleteReorderHamburgerAndOutput
- testPageFlowNestedContainerWidthTransferRejectionAndEmptyPage
- testConnectedPageFlowSceneRenderSelectionAndHitFramesShareResolvedGeometryAtScale
- Updated: testNamedSectionInsertionUsesConnectedFlowAndUndoRedoPreservesCanonicalIntent

SiteForgeLaunchTests:

- testConnectedHeaderFooterNavigationMenuHeightUndoAndReopenJourney

The scene matrix covers three breakpoints, 25/100/800% zoom, 1x/2x, signed pan,
shared renderer/selection/hit frames. Source also covers role ordering, height,
history, old-data conversion, navigation identity/rename/delete/reorder/menu,
serialization, output and safe transfer. The native source uses actual menus,
fields, page creation, Mobile Menu/Escape/focus/page navigation, Undo/Redo and
package relaunch, with four named window screenshot states. None has executed.

## Remaining acceptance and next slice

Prompt 9 has now source-integrated the nested containing-layout/output path as
SF-AUTHORING-122. Its evidence supersedes the earlier blanket nested-container
output block, not remaining unsupported positioning/fluid/root/menu cases.
The 121 native source now queries the actual `Legacy Surface` fixture page
instead of an invented `Home`; identity/history/save-reopen proof is retained.
All acceptance still remains unrun.

Prompt 10: compile all affected test targets; run listed selectors and relevant old
structural/geometry/link/transfer/Preview/output suites; inspect actual Desktop/
Tablet/Mobile, normal/maximized/minimum-width screenshots; validate marker and
menu clipping/focus/no-ghost behavior; measure large fixtures; synchronize DOCX;
run privacy/hygiene and the authoritative accumulated gate. No visual pass exists.

Recommended Prompt 9: complete bounded responsive containing-layout output and
connected-navigation polish where compatibility findings remain, without new
component ownership or arbitrary external menus. Sticky/fixed headers, custom
navigation breakpoints, component flow, broader browser/output/release parity
remain excluded. The testing-runner and experimental Settings owner add-ons are
independent and do not increment the feature counter.

Changed production: DocumentModel, InsertionModel, TransformModel, CommandKernel,
WorkspaceShellModel, WorkspaceShellView, CanvasRendererCore, DragDropModel.
Tests: InsertionModelTests, SiteForgeLaunchTests and schema assertion updates.
Docs: spec clarification (MD only), ADR-0020, queue/status/changelog/handoff,
visual contract, requirement evidence and this note. All work is uncommitted.
