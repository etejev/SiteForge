# SF-LOCAL-BUILDER-015 — Preview and Check Website repair workflow

Historical source boundary;016's [current integration closeout/matrix](SF-LOCAL-BUILDER-016-SOURCE-INTEGRATION-CLOSEOUT.md)
refines Design draft ownership/live-project artifact guards and this existing
native journey. The five+one count below belongs to015; none has subsequently
run.016 is not an acceptance receipt or authorization to execute.

IN PROGRESS — source implemented; acceptance deferred. All five new code methods
and one native journey are UNRUN. No compiler, parser, build, tests, check scripts,
app/browser/UI execution, screenshots or verification ran for this slice. The
execution pause remains; mandatory verification is deferred, not waived. No
commit, push, installation, signing, owner project/recovery change or016 dispatch.

## Bounded contract

SF-0202-003, SF-0203-006, SF-0701-002/003/006,
SF-1202-003/004/006, SF-1203-003/004/006, SF-1204-003/004/006,
SF-1211-004/006. Modules remain Partial. OD-018/019 and updater trust are unchanged.
Navigation is editor state, never an automatic content repair. No new output
support, schema, canonical route, writer, resource policy or component ownership.

## Source findings and corrections

- Preview previously retained a successful plan/URL after a failed build while
  replacing findings without an independent attempt receipt. A scene-local
  `StaticBuildFindingReceipt` now records attempt UUID, document, revision and
  exact findings. Same-revision attempts remain distinguishable. Membership
  requires the complete finding, not its reusable code-derived ID.
- Both panels use `StaticBuildFindingRepairRow`: explicit severity, explanation,
  repair and one actual focusable action where safe. Requirement/code stays in
  help, not the primary heading. Long findings scroll; footer controls remain
  outside the central scroll. No-target findings have no invented destination.
- `WorkspaceShellState.revealBuildFinding` is shared. It validates the originating
  visible panel, receipt, page/component/scene context, lifecycle, export state,
  canonical target, effective visibility and lock state. It requests clean
  editors rather than asking unrelated drafts to commit. Legacy Return-driven
  Design strings are now included in that existing clean-editor gate.
- Existing scene preparation checks the exact target before switching pages or
  entering an original component. Cancellation/failure during that preparation
  leaves the opening page/selection unchanged. After navigation, identity-guarded
  live renderer/selection adoption completes through the existing Layers route;
  only then does the originating panel close. Failure clears the pending intent
  and leaves a recovery message rather than falsely reporting success.
- Actual original-component entry/return logic and selection command registry
  are reused, not duplicated. Different active originals/isolation restrictions
  require the existing return/exit action first. Missing/projected targets without
  an actual canonical node remain unavailable; no name/prose-based matching.
- Conservative code mapping: navigation room on actual Header/Footer opens its
  Content settings; page-flow positioning opens Layout; navigation clipping on
  actual Header/Footer opens Design box settings. Other real targets use Show
  Object and preserve the current Inspector tab. Existing section anchors,
  scrolling and guarded shell focus restore the live editor.
- Preview explicitly distinguishes the last successful artifact from the latest
  findings, even at the same revision. Refresh is explicit. Export still uses
  only its immutable successful request; no failed plan is exported. Opening
  an active export's status does not cancel/restart it; repair waits until it
  finishes or the user cancels. Check Website now presents its actual results.

## Second source review

Reviewed stale/foreign/full-membership receipts, coincident IDs in replacement
projects, page changes, same-revision refresh, clean draft/IME guards, cancelled
preparation, unavailable/hidden/locked targets, isolation/original-component
context, renderer failure, scene/selection/tab drift, panel dismissal and export
ownership. Shared actions retain accessible children and native keyboard focus;
source layout keeps findings scrollable and final actions reachable. These are
source observations, not compiled/runtime/visual proof.

## Future exact acceptance selectors — all UNRUN

`SiteForgeTests/InsertionModelTests/`:

- `testOutputFindingTargetUsesExactReceiptMembershipTypedEditorsAndReadOnlyIdentity`
- `testPreviewAndCheckWebsiteRevealExactCrossPageObjectAfterSceneAdoptionWithoutHistoryOrPackageMutation`
- `testOutputRepairRejectsOldForeignPageChangedAndProjectReplacedReceiptsWithoutPartialNavigation`
- `testOutputRepairCleanEditorIMEAndCancellationGuardsNeverCommitUnrelatedDrafts`

`SiteForgeTests/CanvasRendererTests/testBrowserFindingReceiptIsIndependentOfRetainedSuccessfulArtifactAndExportIntent`

`SiteForgeUITests/SiteForgeLaunchTests/testPreviewAndCheckWebsiteFindingRepairUsesExistingEditorJourney`

Code coverage source uses actual compiler/scene preparation for both panels,
exact cross-page selection, canonical byte/history/package neutrality, invalid
receipts, project replacement, clean editor/IME and cancellation. The controller
test injects its existing browser opener, retaining a real successful plan while
a later real compilation fails; it checks immutable export intent/cancellation.
The native journey uses real Header/clip controls, keyboard repair, pointer
repair, Escape, undo/redo neutrality and actual repaired Safari output plus
explicit Refresh. It closes only tabs identified by its unique authored title.
Named screenshot attachments are requested by the test source; none exist yet.

Minimally affected existing future selectors: CanvasRendererTests/
`testBrowserExportPanelIntentCannotRetargetReplacementBuild`,
`testBrowserPreviewPendingIdentityCancelsReplacementAndRevisionWithoutOpeningBrowser`,
`testBrowserPreviewExportUsesExactSnapshotAndSupersededCompletionKeepsStoppedStatus`;
CommandKernelTests/
`testComponentPropertySourceTransitionReturnsExactInstanceAndGuardsRenameContext`.

## Remaining acceptance / limits

Compilation, focused execution, clean legacy Design-draft UI rejection, exact
component original/return native navigation, compact/scaled panel keyboard focus,
scroll restoration, original-resolution native/browser review and final
`./sf verify` remain required. Earlier frozen title/007–014 receipts do not
validate015. No browser parity, export feature, performance or release acceptance
is claimed. No additional settings/resource editor is fabricated for findings
without an actual supported editor. Keep IN PROGRESS; do not auto-run acceptance.
