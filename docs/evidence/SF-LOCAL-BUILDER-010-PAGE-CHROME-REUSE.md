# SF-LOCAL-BUILDER-010 — Copy Header/Footer to Pages

Current focused acceptance supersedes the historical source-only hold below:
all 11 new code methods pass in the focused 007–011 group. Both native journeys
pass155.645s/24.593s after exposing real sheet accessibility children; nine
original normal/compact screenshots were inspected. Keep IN PROGRESS;
full verification is deferred, not waived. No commit/push/install or owner-data
change. [Current focused results](SF-LOCAL-BUILDER-007-011-FOCUSED-ACCEPTANCE.md).

IMPLEMENTED IN SOURCE — ACCEPTANCE DEFERRED; OWNER TEST APPROVAL REQUIRED.
IN PROGRESS. No build, test, check/lint/script, collector, app/browser/UI,
performance or verification execution. No commit/push/install/sign/schedule.
No screenshots were collected or visually accepted. No next workflow dispatched.

## Bounded contract and user benefit

SF-0303-002/003/004/005/006, SF-0304-002/003/004/005/006,
SF-0308-002/003/004/005/006/008 and SF-0806-002/003/004/005/006.
Supporting existing SF-0501-003 and SF-0504-003 connected geometry only where
exercised. All modules remain Partial. No publication-copy/specification change,
schema, master/global chrome ownership, component slot or responsive cascade.

Finish ordinary editable Header/Footer once, choose other pages, then add
independent editable copies without rebuilding their title, navigation, styling
and customized children. Later source-node edits do not silently propagate.
Existing explicit token/style/asset/component links retain their normal shared
project definitions; independent nodes are not flattened dependency definitions.

## Source implementation

- `CommandKernel.swift`: extracted `CanonicalPageGraphClone` from the existing
  complete-page duplication path; both duplication and chrome copy now use it.
  New NodeID/PropertyID ownership, fill-layer/stop IDs and fluid/select-option
  identities are allocated once during preparation. Ordered child ownership,
  property values/origins and component customization references are retained.
  `PageChromeCopyRegistry` compiles add-missing roles into one existing batch.
- `DocumentModel.swift` / `ClipboardTransfer.swift`: shared canonical graph
  asset/token reference discovery; the isolated clipboard still rejects managed
  page structure. Its public transfer policy is not weakened to enable this action.
  Explicit Hashable conformance for the unchanged PageFlowRole values supports
  derived role selections only, not new persisted data.
- `WorkspaceShellModel.swift`: actor preparation validates current package
  resource descriptors/hash/size/original bytes without importing or rewriting
  blobs. Scene-local request/progress/cancel/status and sanitized bounded last
  diagnostic use the existing session, current-editor/IME gate and renderer.
- `WorkspaceShellView.swift`: one native Page action (also Pages context) and
  dedicated Header/Footer action open a compact ordinary sheet. Header/Footer
  choices reflect source availability. All targets begin unchecked. Rows show
  existing roles and protected/locked/incompatible reasons. Counts distinguish
  missing roles from kept/ineligible roles. A successful adopted result offers
  ordinary navigation to a copied target. No second management pane/window.

## Exact transfer and safety semantics

- Normal Home/standard website pages with one visible unlocked Frame root may
  receive copies. Source, protected Not Found and component-definition pages
  cannot be destinations. Source itself and known ineligible roles are counted
  as skips; missing/deleted selected pages are unexpected stale failures.
- Add missing only. Existing Header/Footer subtrees, all inbound references and
  destination body content are left intact. No Merge/Replace or misleading
  replacement checkbox is exposed. Explicit replacement is deferred because it
  needs a separately scoped inbound-section/component-reference policy and
  confirmation before deleting targeted identities. No policy waiver/owner
  architecture decision is needed to ship safe independent add-missing source.
- Header inserts first, Footer after existing page children. Full containing
  width and connected Section layout derive from the same existing resolver.
  Heights, padding, title/logo/navigation inclusion, customized children, literal
  styling, linked definitions and raw responsive/fluid intent remain ordinary
  canonical properties. Target PageIDs/routes/root/body IDs/order, metadata and
  guides are not replaced. Canonical copies receive fresh owned identities;
  exact Redo reuses those prepared identities.
- Same-project page-only destinations keep their original PageIDs. Section
  links within the copied closure map to new NodeIDs and the destination page.
  Links to uncopied source body sections remain explicit source-page references;
  no same-label destination section is guessed. Component action overrides use
  the same distinction. Header/Footer role references map inside the cloned
  closure. Missing dependencies reject before mutation with fixed recovery text.
- Images/resources, tokens, reusable styles and component definitions keep
  stable same-project identities. Existing component-conflict validation applies;
  no supplied slots, conflict retargeting or cross-project import is introduced.
- One captured document revision/source role map and selected target IDs feeds
  all preparation. Request, exact selection/scene/viewport/definition context,
  lifecycle and clean draft/IME boundaries are rechecked immediately before one
  existing command execution. Rename/delete/role changes invalidate the sheet;
  unexpected graph/dependency validation failure aborts all selected pages.
  Cancel before commit changes nothing. After durable canonical commit, Close
  does not pretend to cancel it; the UI waits for matching renderer adoption.
- One Undo restores the exact prior graph through existing inverses; Redo keeps
  committed identities. All-covered repeats are neutral, with no history entry.
  Bounds: 100 selected targets, 10000 nodes per source closure, 256 dependency
  definitions and existing 20000-node project/expanded graph limits. Progress is
  indeterminate/cancellable, not an invented percentage or measured budget.
- Shared renderer/native Preview/static HTML/CSS consume the resulting ordinary
  document. No writer fork, generated patch, sample exception or owner macro.
  Browser/output visual certification remains deferred.
- Diagnostics retain requirement ID, sanitized document/page identity, target
  count, category and duration only. No page names, values, image bytes or paths.

## Added acceptance source — UNRUN

Eleven methods in `Tests/SiteForgeTests/InsertionModelTests.swift`:

1. `testPageChromeReuseHeaderFooterBothMissingRoleAndEmptyTargets`
2. `testPageChromeReuseSkipsExistingProtectedAndComponentPagesWithoutReplacement`
3. `testPageChromeReuseClonesFreshOwnedIDsAndPreservesConnectedBodyAndRoutes`
4. `testPageChromeReuseInternalAndExternalSectionDestinationsRemainTruthful`
5. `testPageChromeReuseAtomicUndoRedoCancellationBranchAndRepeatNoOp`
6. `testPageChromeReuseRejectsStaleDeletedRoleInvalidTargetAndCancelWithoutPartialWrites`
7. `testPageChromeReuseIndependentTargetEditDoesNotPropagateOrChangeSource`
8. `testPageChromeReusePackageRecoveryAndOrdinaryHistoryRoundTrip`
9. `testPageChromeReuseResourceTokenComponentIdentityAndMissingDependencyRejection`
10. `testPageChromeReuseSheetSelectionRaceAndPreparationCancellationAreNeutral`
11. `testPageChromeReuseResponsiveSharedLayoutRendererAndCompilerGraph`

Two methods in `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift`:

- `testCopyHeaderFooterToPagesIndependentAtomicUndoAndReopenJourney`
- `testCopyHeaderFooterSheetAtPracticalMinimumKeepsMissingRolesTruthful`

The normal journey sources real page creation, editable Header/Footer fields,
explicit unchecked target choices, Escape cancellation, one native default-action
commit, adopted target navigation, exact Undo/Redo identities, independent target
editing, existing-chrome skip, Save and reopen. The named compact journey reuses
the established explicitly constrained minimum-window fixture, not a production
window-policy change. Screenshot checkpoints cover source, normal sheet, adopted
summary, target controls, Undo/Redo, existing skips, reopened target and compact
sheet. They are requests in source, NOT retained visual evidence.

## Review and remaining acceptance

Read-only source/diff/API inspection only. No test result, compile success,
latency, keyboard/VoiceOver certification or visual correctness is claimed.
Future owner-approved acceptance must compile and run the listed focused methods
plus affected whole-page duplication regressions, inspect normal/compact originals
and native Preview/Safari output, then run mandatory `./sf verify`. This gate is
deferred, not waived. Source tests cannot establish runtime or visual acceptance.

Preserve007's historical built/partial focused receipts (3/9 then4/6, with latest
fixture correction unverified),008's10 code+1UI UNRUN and009's15 code+1UI UNRUN.
The936-pass ba342938 baseline does not accept this dirty source. Owner Aurora/
Dark Flow revision245, editable45-degree three-stop gradient, resources/recovery,
regular app, excluded coordinator/artwork files and OD-018/019 remain unchanged.
