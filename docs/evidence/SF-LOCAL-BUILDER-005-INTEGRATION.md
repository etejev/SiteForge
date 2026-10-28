# Local-builder integration — source-focused checkpoint

## Current owner handoff — 2026-10-24

Supported native inspection of the selected Xcode found the actual **Install
Required** dialog: system-wide components are required to manage shared resources
such as simulators and connected devices. Buttons are **Quit** and **Install**.
Original screenshot: ignored `.codex-loop/xcode-readiness-20261024/install-required.png`.
Dialog left open. No installation, agreement, authentication, platform selection,
privacy/service/global toolchain change, test or collector retry occurred.

Owner action is now exact: choose Install in Xcode and personally complete its
subsequent setup/authentication. Then check readiness before ONE accumulated
collector retry. OD-025 records recommendation, alternative and safe assumption.
The 13 focused UI workflows, nine affected code passes, reviewed visual limits,
blocked full gate and unrefreshed ordinary installed app remain unchanged.

## Current accumulated native acceptance — 2026-10-23

### Latest authoritative focused outcome

### Required accumulated gate — externally blocked

After source/visual/document review, repository checks passed (security,
architecture, migration/evidence and 440 traceability records); `git diff --check`
passed. ONE supported `./sf testing full` collector was attempted at frozen source
fingerprint `d3b06b9d…`. It terminated **blocked**, exit 1, before build/code/UI:
`xcode-first-launch-setup-required`. Read-only `xcodebuild -checkFirstLaunchStatus`
returns 69 without diagnostic on selected Xcode 27.1/build 27A9275. Focused XCTest
working does not waive this independent mandatory preflight.

Retained report: `.codex-loop/full-verification/20261023-200720-8f1f5b4c/`
`state.json`, `report.json`, `REPORT.md`, `collector.log`. No xcresult/full test
totals exist for this attempt: zero test stages executed, not a passing zero-test
run. Collector exited and no test runner is active. OD-025 records the exact
owner setup boundary; no preflight bypass, Apple agreement/installer, global
configuration change, ordinary-app replacement, commit or GitHub action occurred.

SF-LOCAL-BUILDER-002/003/004/005 remain IN PROGRESS pending required full and safe
installed delivery. The current visible limitations remain the fixed template
geometry below, not an all-width fit claim.

All **13 distinct native workflows** in the accumulated focused inventory now
have passing results across the retained serial runs (not one full-suite run).
`connected-image-final.xcresult` passes **5 code + 1 UI**, zero failures/skips;
`testPracticalImageReuseScopedReplacementAndTypographyJourney` passes in 385.272s.
It completes real scoped/global image replacement, installed font selection,
invalid Preview neutrality, Save's live-draft boundary, separate native/document
Undo, context adoption, real reopen and committed Device Preview. Its six captures
are in `connected-image-attachments/`; reviewed examples include
`A29692A0-D1D6-4A52-B433-2D37097A9712.png` (Saved reopened typography),
`E1D19309-E821-4D53-910D-F1FF2FFD05D7.png` (committed geometry/history), and
`C3FDBB11-71ED-4A5D-820E-C15990166C61.png` (preview without selection chrome).
Upright glyphs, readable controls and matching selection bounds are visible.

The existing Aurora copy/Safari method now also drives native Export Cancel,
retries Export into a fresh independently owned folder, verifies the real output,
reopens the saved project and quits normally. A broad Cancel query initially
matched Touch Bar and Inspector controls; the corrected test scopes the native
`save-panel`/`CancelButton`, retaining cancellation/no-output assertions.
`browser-export-scoped.xcresult` passes 1/1 (148.551s).

Real Safari review exposed a distinct mobile navigation defect: Safari AX link
activation transiently focuses the document body, and the menu's focus-dismissal
listener collapsed the target before activation. Ignore body/documentElement as
transient focus destinations; real outside controls, click and Escape still
dismiss. The earlier click-order experiment did not fix this and was reverted.
`navigation-focus-review.xcresult` passes **1 code + 1 UI**, zero failures/skips:
`testConnectedNavigationVisibilityCapacityAccessibilityAndNoDecorativeMenu`
(0.111s), and `testAuroraRelatedPageReuseNativeCopyAndSafariJourney` (150.253s).
Fingerprint `d3b06b9d725c7ab2796a3598a737e3f8fde8d099e65a99d3a72e4a6a3e5af1c7`.
The actual exported mobile menu subsequently reaches Journal in Safari; Back,
reload and Escape were exercised through real browser controls. No HTML/CSS was
hand-edited and no protected project was converted or rewritten.

Current original-resolution browser captures, all inspected, are under
`.codex-loop/component-navigation-20261023/browser-review/current/`:
`safari-320.png`, `safari-375.png`, `safari-390.png`, `safari-430.png`,
`safari-574.png`, `safari-768.png`, `safari-1024.png`, `safari-1440.png`,
`safari-390-menu-open.png`, and `safari-390-menu-journal.png`.
Photography and glyphs are upright, native browser navigation is semantic, and
grid/selection/editor chrome is absent. This review does NOT establish an
all-width visual fit: at 320 the template's explicit Mobile content frame is
342 points at X=24; at 1024 its Desktop content frame is 1100 points at X=170.
Their right-edge clipping preserves fixed authored intent. At 574 that fixed
Mobile frame remains left-biased; at 768 long navigation labels ellipsize with
full accessible titles. Do not silently reflow these fixed properties or claim
universal parity. Responsive conversion remains explicit and opt-in, separately
covered by the passing practical sizing journey.

Nine directly affected code methods in this continuation have passing focused
results (5 draft/identity + 3 viewport + 1 navigation); groups overlap older
evidence and must not be added to the historical 717 target. The final accumulated
gate and installed delivery have not passed. Ordinary installed work/recovery
and protected source projects remain untouched; no commit or GitHub operation.

Earlier: `viewport-focus.xcresult` passes **3/3 focused code + 1/1 UI**, zero
failures/skips. The UI method is
`testPracticalResponsiveSizingConversionWinnerResetAndDraftJourney` (165.978s).
Code methods: `testViewportPresetFocusGateAdoptsOnlyCurrentSceneWindowAndRequest`,
`testViewportPresetFocusLossDoesNotReclaimWithoutANewRequest`, and
`testViewportPresetNativeContractSynchronizesSelectionAndAccessibility`.
Fingerprint `59ae7ba1f81f9440fff264967476f6d24059095fa10caeb1c03e49a386f2686c`.

The full redacted event sequence corrected the initial cancellation hypothesis:
the X editor never regained focus after the preset interaction, so its Escape
handler never ran. The visible cancellation announcement belonged to an earlier
width edit. All speculative cancellation guards, editor replacement/abort changes
and temporary tracing were removed. The production correction defers native
viewport focus publication until AppKit's responder transition finishes, guarded
by the same current window/request and actual first responder. Rejected choices
immediately mirror the retained canonical preset in native selection and AX.
The test now requires real keyboard focus and the full pre-draft value after
Escape; no content/history/selection assertion is weakened.

Twelve distinct UI workflows now have passing focused results. Only the connected
image/typography method is still running (`connected-image-final.xcresult`);
no pass is inferred. Its prior native Undo returned the earlier 120 draft while
canonical geometry remained 320: Save does not end a native typing group. The
test now ends that session through Escape before testing a fresh native Undo.

Original-resolution `viewport-focus-attachments/9A0030F0-A9AC-4EA6-8A1C-1C65273B0F02.png`
and `F12B59B7-39A8-4197-B876-F1D598969DFD.png` were inspected: Tablet fit after
real cancellation and Saved reopened responsive sizing. Controls/provenance are
readable, text upright, selected Frame bounds aligned, grid/pasteboard distinct,
and no ghost object is introduced. This is not final browser/full/installed acceptance.

Historical sequence below: all runs are serial, isolated OwnerTesting sessions. Eleven distinct
methods have passed; this is not one full-suite result or a final integrated gate:

| Result bundle | Passing methods |
| --- | --- |
| `component.xcresult` | Practical named component creation/Design/Return (1/1) |
| `acceptance-group.xcresult` | Two-instance text, retained-conflict recovery, concept Settings, fixed Settings/reopen, owner-local Settings/blank (5/9; four initial failures retained) |
| `repaired-acceptance.xcresult` | Independent Aurora native copy/Safari, local image/fill/media persistence, compact fill Inspector, actual Safari website preview (4/7; three failures retained) |
| `navigation-acceptance.xcresult` | Native sizing bounds (1/3; two failures retained) |

Bundles/logs and exported attachment manifests are retained under ignored
`.codex-loop/component-navigation-20261023/`. Exact method names are in the
authoritative inventory below. New Bounds geometry uses the existing native
Inspector disclosure style; its contained control passes the unchanged pointer
containment checks. Native text focus is explicitly returned to the selected
canvas object before document Undo; no history or stable-ID assertion is removed.

The later `draft-ui.xcresult` completed **0/2**, exposing two further concrete
boundaries. The typography alignment query also matched Window > Center; the
correction scopes the real menu item to its originating alignment popup. The
responsive recording shows Escape announces cancellation, but AppKit writes the
field editor's old `-` back afterward. The correction rejects reconciliation only
during that cancellation event and restores the committed value; the test now
asserts the full pre-draft value before permitting Tablet. Neither fix mutates
canonical geometry or bypasses a native control. Current build-for-testing passes
at fingerprint `351da51786edebf9195b95a0840faa9bf84e1a79fb2affae7f0c27194dc460fc`.
The affected `cancel-ui.xcresult` run is in progress; no result inferred.

Before that last cancellation correction, `draft-model.xcresult` passed **5/5**:
`testInspectorAccessibilityAnnouncesRetainedDraftInsteadOfCommittedValue`,
`testRetainedNumericNoOpRecognizesEquivalentInputWithoutDiscardingConflict`,
`testSizingInspectorShowsWinningOverrideAndRejectsDraftFromPreviousBreakpoint`,
`testTypographyScopeGuardPreservesMissingFamilyFluidSizingAndExactHistory`, and
`testWorkspaceInvalidOrStaleDraftBlocksContextPreviewAndCloseUntilCancelled`.
Draft accessibility now announces actual retained input, not an unrelated
committed/computed value. The font chooser is a genuine accessible popover group;
its pointer checks use that surface, not the background Inspector scroll view.

Original-resolution Settings, compact, component, image, native Aurora and Safari
captures have been inspected. Settings' seven destinations are readable and
consistent; compact selected labels/overflow and deep fill controls are contained.
Aurora's native page has distinct pasteboard, upright text and aligned selection;
its saved/reopened independent copy remains intact. A wide-browser overlay edge
and Tablet navigation ellipsis remain bounded fidelity observations, not universal
parity acceptance. The eight-width browser review and one final accumulated gate
remain pending. No ordinary installed-app replacement, recovery mutation, privacy
change, commit or GitHub operation has occurred.

## Corrected component workflow — 2026-10-23

### Subsequent focused group and bounded repairs

The nine-selector group completed: **5 passed / 4 failed / 0 skipped**. Passing:
retained-conflict recovery (212.378s), two-instance text (280.508s), concept Settings
(22.948s), fixed Settings/reopen (34.673s), owner-local Settings/blank canvas (38.381s).
All seven fixed Settings destinations plus reopened geometry were inspected from
the retained original-resolution PNGs: consistent sidebar/cards/dividers, readable
labels, program-wide controls, Testing in Advanced, no release-channel selector.
The isolated testing app honestly reports unavailable testing provision; this is
not an installed-app testing-provision claim.

Four failures are preserved in `acceptance-group.xcresult` / `acceptance-group.log`
under ignored `.codex-loop/component-navigation-20261023/`:

- Image history and responsive reset tests invoked document Undo while a native
  text editor still owned focus. Correct their real focus preconditions, preserving
  the native/document history split and exact undo assertions.
- Connected image workflow queried label `Image`, but the hierarchy exposes
  `Image: workflow-picture-one; alternative text is empty`. Use that truthful
  semantic label and stable NodeID; Text likewise exposes `Text object`.
- Bounds' default DisclosureGroup reports an outdented, non-contained triangle
  frame. Reuse `SiteForgeInspectorDisclosureStyle` (already shipping for other
  sections), providing one visible native Button with truthful Expanded/Collapsed
  state. Do not loosen pointer containment or invent a second automation control.

Build-for-testing of these repairs passed. The affected four plus practical
compact and real Safari journeys are running serially; no pass is inferred yet.
Direct computer-use inventory is available, but binding the exact ordinary
installed app still closes its native pipe. That route does not block XCTest
captures or authorize replacement of unknown owner work.

Only test navigation changed: use the real Design tab and assert its selected
state before Design-only provenance, also after the later definition return.
Production tab behavior and all creation/cancel/identity/draft/persistence
assertions are unchanged. Build-for-testing and exact workflow pass: **1/1**,
0 failures/skips, 232.398 seconds, exit 0. Isolated app/runner identity remains
OwnerTesting; fingerprint `eab81b81db9dee155ee5ac9022c7706b0f8efb779a79ec008821d6bb28311f43`.
The production source is unchanged from the earlier 717-code result; this is not
a new full code or integrated gate. One QoS warning is retained without source
attribution; no warning-free claim.

Original-resolution captures under ignored `.codex-loop/component-navigation-20261023/attachments/`
were inspected: `1A67569C-B71B-4683-BF0A-DD0E94A06D4E.png` (named component/empty
properties), `1F42B5C4-CB0A-4845-A163-B33D8F9A1EFD.png` (focus-loss and Escape),
`85816658-3C97-4F34-9466-14B0999F4717.png` (reopened Saved value). Dark native shell,
readable five-destination rows, clear page/grid boundary, upright text and aligned
selection are visible; no ghost or clipped control in these states. Browser,
compact and Settings acceptance are not inferred. Result: `component.xcresult`
with `component.log` in the parent directory. The next focused inventory group
is running serially; no new feature or installed-app change.

## Single isolated retry — 2026-10-23 17:19

The authorized retry passed initialization and executed
`testPracticalComponentNamedCreationDesignDraftAndReturnJourney`: 0 passed,
1 assertion failure, 0 skipped (64.376 seconds; exit 65). No authentication
prompt was confirmed visible; owner reported none. Authentication is therefore
not the current blocking boundary. No privacy or service settings changed.

The failure is at line 5644: the journey queries Design-only
`inspector.component.provenance` while the retained hierarchy explicitly has
Layout selected. The hierarchy contains the newly named Editorial Card definition,
one linked instance and the selected instance; creation itself succeeded. This
is a concrete test-navigation mismatch, not evidence that component creation
failed. The remaining workflow did not execute. One QoS runtime warning is
retained, not waived. No second retry or source change was made.

Private retained evidence: `.codex-loop/native-initialization-diagnosis-20261023/`
`current-retry/component.xcresult`, `component.log`, and `attachments/` (hierarchy
and screen recording). The isolated app/runner exited; the ordinary installed
app remains untouched. Current source and prior 717-code result are unchanged.

## Historical native initialization diagnosis — superseded by 17:19 execution

Existing diagnostics, not another test attempt, locate the failure upstream of
SiteForge: runner/IDE session and test-daemon authorization succeed, then Apple's
automation-mode writer requires device-owner authentication. LocalAuthentication
returns -1004 “User interaction is required”; testmanagerd requests the interactive
“Enable UI Automation” policy. The UI service reports UI shown without error,
but no authentication completion precedes the 60-second timeout. This establishes
the missing prerequisite, not why interaction failed to complete or that a prompt
is currently visible. No product code/configuration defect is demonstrated.

The successful October 21 UI session (133 passes, Xcode 27.0) completed this same
automation handshake in about 8 ms. The October 23 failure uses Xcode 27.1; the
simulator mismatch also occurs in the successful 717-code run. Simulator mismatch
causality is NOT established; no update is recommended from that warning. Selected
developer/xcodebuild/xctest/Swift/framework paths are consistent; no process-local
developer/toolchain/SDK/architecture overrides or stale target identity were found.
The provision is current and universal; actual destination was arm64. Developer
mode is already enabled. A logged-in console session exists; no locked-console
denial appears in the scoped trace. A read-only first-launch check exits 69,
recorded separately without running installers or accepting agreements.

No independent control target or unchanged selector was run: neither bypasses
the now-proven authentication gate. Existing 717-code/repository passes are not
rerun or newly counted. Raw diagnostics stay private/ignored; tracked evidence
contains only sanitized boundary/timing/category facts, not sandbox extensions,
user paths, credentials or project content.

At that historical checkpoint, the proposed owner action was to complete macOS's “Enable UI Automation”
authentication during one isolated retry, after confirming readiness at the Mac.
Credentials stay in macOS, not chat. No service/privacy/global toolchain reset.
Normal SiteForge reopening is withdrawn as a test-manager fix; saved/quit proof
is still separately required before a future installed update. No new native
workflow has executed; host repair is NOT claimed. OD-025 and the inventory below
remain open. No new feature, code test, app replacement or commit occurred.

Private diagnostic artifacts: `.codex-loop/native-initialization-diagnosis-20261023/`
contains exported failed/last-good session and daemon diagnostics plus narrow
`scoped-system-log.json` / `authentication-system-log.json`. The directory is
owner-private; those raw files are not tracked evidence.

## Earlier acceptance checkpoint — 2026-10-23 before the 17:19 retry

No new authoring code was added. Current source fingerprint:
`f601b53bdd0d90b861828a57e65586910cc43ab4b978ebcc6ea2aa8d512cebab`.
Fresh build-for-testing passed. App metadata, actual v1 xctestrun target path,
app/runner OwnerTesting identities, handler rank None and source fingerprint
were checked before launch. The regular app remained running and untouched.

ONE exact pending native selector was attempted:
`SiteForgeUITests/SiteForgeLaunchTests/testPracticalComponentNamedCreationDesignDraftAndReturnJourney`.
It exited 65 before the test method could launch its target app: runner initialization
timed out enabling automation mode. xcresult's `totalTestCount: 1` represents
the runner error, NOT an executed workflow. Zero native passes/skips; no product
assertion failed. Runner PID 68635 was in the validated new test build; it exited
without terminating the regular app. This is fresh October 23 evidence, not
reuse of the October 21 failure. No unchanged UI retry/full collector followed.

Computer-use reset/rebind controls are absent from the enabled tool inventory.
No unsupported call, app/service termination or privacy change was attempted.
That unavailable inspection route is recorded separately from the actual XCTest
initialization timeout; neither proves a SiteForge product deadlock.

The permitted **complete code target passes 717/717**, zero failures/skips,
confirmed by xcresult summary and process exit 0. The code-only xctestrun excludes
the UI target and injects existing test-mode private recovery/recents/bookmarks
arguments; its host diagnostics confirm OwnerTesting. Its 717 tests include
the overlapping focused groups, not 717 plus their prior counts. No current
integrated `./sf verify` or native/visual/Safari acceptance is claimed.

Retained under ignored `.codex-loop/local-builder-acceptance-20261023/`:

- `provision.json`, `test-application-info.plist`, `build.log` — current isolated provision.
- `component-route.log`, `component-route.xcresult`, `component-route-summary.json` — initialization failure.
- `code-only-private.xctestrun`, `code-only.log`, `code-only.xcresult`, `code-only-summary.json` — 717 code passes.
- `protected-before.json`, `closeout.json` — matching fresh 4/4 hashes, source and installed metadata.
- `REPORT.md`, `repository.log` — stage-by-stage closeout; repository/security/
  architecture checks and 440-record traceability pass. `git diff --check` passes.

Both protected Aurora project files and both resources-v1 sidecars match their
fresh pre-attempt hashes. Genuine recovery was not used or manipulated; no claim
is made about an unavailable historical 69-file baseline. Source fingerprint
remained unchanged throughout build/native/code execution. No owned runner or
collector remains. The regular app remains build **26.10.21**, fingerprint
`85f0f55de2b76a6f016d8ffe0651278f108a66eef0276570e5b407f5d204bb79`:
it is NOT the current code and was NOT installed/refreshed.

Original-resolution concept references 01, 05 and 12 were inspected. No changed-
build app screenshots exist from this attempt, so no current editor/Settings/
Safari fidelity conclusion follows. The complete inventory below remains pending.
The later diagnostic section above supersedes the generic reopening suggestion:
UI Automation authentication is required for XCTest, while a normal saved/quit
state is needed separately before installation. Do not restore/discard recovery.
Installation and accumulated delivery remain
deferred; no new feature stream, commit, GitHub or release operation begins.

## Scope and existing policy

SF-LOCAL-BUILDER-005 is IN PROGRESS. Bounded SF-0203-002/003/004/005/006,
SF-0301-003/004/005/006, SF-0306-003/004/005/006,
SF-0307-003/005/006, SF-0702-002/003/004/005/006 and
SF-0705-003/004/006 remain Partial. Preview request/output fixes additionally
exercise SF-1201-003/004 and SF-1206-003/004, read with ADR-0021.
ADR-0024 recovery qualification and ADR-0025 sizing/metrics are unchanged.

Existing native policies remain Return/valid focus loss to commit, Escape to
cancel the relevant editor, typed registry validation, exact command inverses,
and immutable explicit-revision preview/export. File Save does not serialize
draft strings. Native text Undo is distinct from document history. No new
canonical schema, draft/history store, cascade, resource authority or recovery
retention policy is introduced.

## Demonstrated gaps and corrections

1. Geometry and typography focus-loss commits defer to the next main event to
   avoid SwiftUI update-time publication. File Save previously started a package
   snapshot immediately, without consulting those retained editors. A synchronous
   scene-local `WorkspaceEditCommitRequest` now asks visible component, sizing,
   geometry, container and typography fields to use their existing commit paths
   before a consuming user action. It carries only an action and acceptance flag,
   never draft content or a second canonical copy. Reentrancy is bounded.
2. Invalid/incomplete/conflicting editors reject Save/Save As, Preview, Close
   and user selection/page/breakpoint/Inspector/definition context changes, with
   a visible accessible paused/retry notice. Fields retain their own drafts and
   precise validation. Escape/Cancel clears the relevant draft and action notice.
   Compatible committed changes still have separate normal transactions. Clean
   adoption/native Undo back to an equivalent number is neutral, including
   format-only numeric differences; stale conflicts are never cleared as no-ops.
3. Safari Preview previously cancelled active inline text unconditionally. It
   now commits through the existing text registry or pauses for invalid/marked
   text. Device Preview additionally requires the current adopted viewport/page,
   not just a matching document revision; Presentation mode cannot become active
   when that opening was rejected. No old canvas is called a current preview.
4. Menu and toolbar Undo/Redo route to the native responder while a native text
   editor owns focus. Otherwise they use existing document history. No fake text
   writes, synthetic history or per-keystroke canonical commands are added.
5. A component draft now also checks its ordered selection context, including
   the adoption interval with no current identity. Untouched rows can adopt a
   new selection; dirty/conflicting rows cannot rebase their text onto it.
6. Native Save As and Open panels run nested event loops. Their former return
   paths did not check whether their originating document/revision had changed;
   Save As also queued a task without a second check. Both boundaries now check
   origin before proceeding. Save As returns its real task result for normal
   operation coordination. Stale notices belong to the originating lifecycle
   only; a replacement document is not overwritten or given old feedback.
7. The first in-flight website build had no adopted document identity yet.
   Pending document/revision is now tracked separately from the last successful
   plan. Replacement/revision change and Cancel retire request ownership promptly;
   delayed build/browser-open/export completion cannot replace newer feedback.
   Browser opening and export expose specific bounded busy state; export failure
   categories are sanitized and actionable, with no user paths or content.
8. A real export regression exposed macOS URL aliasing: an existing private
   temporary stage normalized from `/private/var` to `/var`, but its absent child
   retained the other spelling. Comparing separately normalized strings rejected
   safe output as `unsafeDestination`. Normalize the stage once before appending
   children and compare against that same root. Traversal/target-symlink checks
   remain; explicit unsafe output still fails. This is shared writer correction,
   not an export bypass or new cleanup policy.

## Review and repository checks

Repository/security/hygiene, architecture, tooling and foundation-evidence checks
pass; traceability now covers 440 bounded records, including fifteen newly indexed
Partial clauses exercised by this package. `git diff --check` passes. Generated
logs/results remain ignored. All focused processes started here have completed.
No native collector, privacy change, installation, commit or GitHub action ran.

Source changes: `WorkspaceShellModel.swift`, `WorkspaceShellView.swift`,
`TransformModel.swift`, `DocumentLifecycle.swift`, `LaunchExperience.swift`,
`BrowserPreview.swift` and the shared `CanvasRendererCore.swift` writer. Tests:
`ProjectResourceTests.swift`, `CanvasRendererTests.swift`, `CommandKernelTests.swift`,
`TransformModelTests.swift`, and the existing UI journey in `SiteForgeLaunchTests.swift`.
The affected `InsertionModelTests.swift` sizing-state regression now explicitly
injects fixture-owned recovery and a manual autosave debouncer as well.
Queue/status/changelog/handoff/visual-contract/traceability link this evidence.
Prior dirty work is preserved, not blanket-certified by the focused group.

Review found no new canonical/property write path, target-membership requirement,
duplicate draft store, hidden automation controls, credentials or machine-specific
source paths. The event adapter holds no editor strings or persistent state.
Native warning-free/focus/visual claims are deliberately not inferred from this
review; those remain in the acceptance inventory below.

## Focused results

Final reviewed affected group passes **24/24 code tests**, zero failures/skips:
ten new tests plus fourteen directly affected regressions. Application and both
test targets compile, including the extended public-control journey. Final bundle
`focused-1046d027-90fe-4f41-b186-ab4827eda3ed.xcresult` is retained under ignored
`.codex-loop/integration-polish-focused/`, with log under ignored
`.codex-loop/component-reuse-focused/integration-polish-reviewed.log`.
Earlier four- and 22-selector passes are incremental, not additional unique
coverage. Initial compile/fixture failures were fixed, not waived. The fixture's
Fill width was correctly non-editable, not a product failure to waive. New test
controllers use isolated fixture-owned resources/files/recovery. No UI selector,
Safari or installed app is executed by these checks.

The existing invalid/stale boundary selector was then strengthened with a second
scene sharing the same canonical document identity. Its isolated rerun passes
1/1 in `focused-b605ba8c-03cc-4e40-995c-a2f2c2b9546d.xcresult`; it is not an
additional unique test. Another scene neither commits nor rejects this draft.
Production source stayed unchanged during that targeted test-only strengthening.
The affected sizing-state fixture-isolation correction then passes its exact
selector 1/1 in `focused-3ba119ff-492c-42ec-aa03-881bdf3b0eb2.xcresult`.
These two single-selector reruns do not increase the 24 unique tests. No default
recovery location is needed by either strengthened state regression.

Ten new `SiteForgeTests/` selectors:

- `ProjectResourceTests/testWorkspaceSaveBoundaryCommitsDraftOnceAndReopensExactResourceIntent`
- `ProjectResourceTests/testWorkspaceInvalidOrStaleDraftBlocksContextPreviewAndCloseUntilCancelled`
- `ProjectResourceTests/testWorkspaceInlineCommitBoundaryPreservesMarkedTextAndExactHistory`
- `ProjectResourceTests/testSavePanelRejectsChangedOriginAndQueuedReplacementBeforeWriting`
- `ProjectResourceTests/testOpenPanelRejectsChangedOriginWithoutOpeningOrReplacingCurrentLifecycle`
- `CommandKernelTests/testComponentRetainedDraftRejectsReplacementSelectionAndRepeatedAdoptionIsNeutral`
- `TransformModelTests/testRetainedNumericNoOpRecognizesEquivalentInputWithoutDiscardingConflict`
- `CanvasRendererTests/testBrowserPreviewPendingIdentityCancelsReplacementAndRevisionWithoutOpeningBrowser`
- `CanvasRendererTests/testBrowserPreviewExportUsesExactSnapshotAndSupersededCompletionKeepsStoppedStatus`
- `CanvasRendererTests/testBrowserPreviewLateOpenCompletionCannotReplaceStoppedFeedback`

Fourteen directly affected existing regressions in the final group:

- `DocumentLifecycleTests/testSaveOpenAndSaveAsValidateBeforeReplacingState`
- `DocumentLifecycleTests/testSaveDiscardAndSavePanelCancellationBranchesAreDeterministic`
- `DocumentLifecycleTests/testStaleSaveSuppressionAndMainActorResponsiveness`
- `CanvasRendererTests/testBrowserPreviewWorkerWritesSameCompilerArtifactInsidePrivateOwnership`
- `CanvasRendererTests/testLocalStaticBuildWriterStagesDeterministicOutputAndRejectsStale`
- `CanvasRendererTests/testStaticBuildCompilerExportsOnlyReferencedVerifiedAssetsAndWriterContainsPaths`
- `CanvasRendererTests/testLocalPreviewStateFreezesRevisionAndRejectsStaleRefreshes`
- `CommandKernelTests/testComponentTextDraftAdoptionPreservesTypingAndRejectsConflictingContext`
- `CommandKernelTests/testComponentConnectedReusePropagationResetHistoryAndImmutableOutput`
- `CanvasTextRenderingTests/testTypographyScopeGuardPreservesMissingFamilyFluidSizingAndExactHistory`
- `InsertionModelTests/testSizingInspectorShowsWinningOverrideAndRejectsDraftFromPreviousBreakpoint`
- `ProjectResourceTests/testSelectedImageImportIsAtomicLocalDeduplicatedAndReopensWithOriginalBytes`
- `ProjectResourceTests/testAssetUsageRevealWaitsForActualFillReferencePageAdoption`
- `ProjectResourceTests/testSharedAssetThumbnailTracksReplacementUndoAndRedoResourceIdentity`

002's 17, 003's 23 unique, 004's 22 and this group's coverage overlap. They must
not be summed as an integrated unique total. The historical 682 code +133 UI
=815 full gate predates all four packages and is not changed-tree verification.

## Current acceptance inventory — authoritative for 002/003/004/005

**Native acceptance is incomplete, but execution now works.** The 17:19 retry
reached the named-component workflow and exposed the wrong-tab test precondition
described above. Correct and rerun that focused workflow, then continue this
inventory. Do not reset privacy/services, invent a permission request, force quit
or overwrite unknown owner work. Compilation alone cannot prove usability;
retained runtime images, not source-only checks, establish visual findings.

Continue these bounded public-control
journeys from `SiteForgeUITests/SiteForgeLaunchTests/`:

Regenerate the isolated testing provision for the current frozen source before
native collection. Headless checks reused the existing OwnerTesting role; they
do not certify that the earlier provision fingerprint matches the changed tree.

| Package / path | Exact selector | Required observation |
| --- | --- | --- |
| 002 | `testPracticalComponentNamedCreationDesignDraftAndReturnJourney` | Named creation, two instances, Design/Content drafts, exact Return, reset/cancel |
| 003 | `testPracticalResponsiveSizingConversionWinnerResetAndDraftJourney` | Conversion, numeric winner/reset, invalid context switch paused until Escape, then allowed switch |
| 003 bounds | `testNativeSizingConstraintsClampResetAndAccessibilityJourney` | Real bounds disclosure, keyboard/focus/AX, clamp/reset |
| 004 + connected 005 | `testPracticalImageReuseScopedReplacementAndTypographyJourney` | Native panels/scoped versus global image replacement, typography; pending Save, invalid Preview, native versus document Undo, context, reopen, Device Preview |
| Existing component | `testComponentTextPropertiesTwoInstancesResetHistoryAndReopenJourney` | Definition propagation, per-instance overrides, exact history and actual reopen |
| Existing conflict | `testComponentRetainedOverrideRecoveryConfirmationUndoAndReopenJourney` | Retained conflict recovery, explicit confirmation, exact Undo/reopen |
| Existing image/fill/media | `testLocalImageAssetImportAuthoringUndoRedoAndReopenJourney` | Shared chooser and affected image-fill/component-media composition, geometry, resources and real lifecycle |

The connected 005 acceptance extends the existing 004 journey rather than
creating another near-identical long launch. It has planned screenshot names for
scoped/global replacement, installed font/cancel, committed draft/context/native
versus document Undo, reopened content and committed Device Preview. These are
NOT retained evidence until the journey runs. Inspect original-resolution normal
maximized and practical compact states against `product-ui/VISUAL_CONTRACT.md`:
five destinations, readable labels, focus order, honest paused notices, no clipped
controls, lost drafts, wrong alpha, stale pixels, ghost objects or text drift.

**Actual Safari/output:** on a safe independently owned review copy, inspect
320/375/390/430/574/768/1024/1440 widths, connected component propagation/reset,
responsive sizing/provenance and image/typography intent. Exercise Refresh,
cancel/retry, page navigation and the same immutable export, comparing matched
native/browser content and image/text layout. Model/CSS/HTTP tests are not browser
parity. Do not replay a sample conversion or edit protected Aurora originals.

**Settings:** all seven destinations remain pending: Appearance, Canvas,
Accessibility, Defaults, Updates, Support, Advanced. Use existing Settings
journeys (`testConceptAlignedSettingsSidebarAndInheritedAccessibilityJourney`,
`testFixedSettingsSharesCardWidthTitlebarClearanceAndReopenGeometryJourney`,
`testOwnerLocalSettingsAndCenteredEmptyCanvasUseRealControlsJourney`) and installed
original-resolution inspection. Verify global preferences, fixed Settings geometry,
Advanced testing and absence of a release-channel selector. Do not claim older
captures are inspection of these changed sources.

**Installed/local delivery:** the regular installed app remains the older
verified build; its current saved/modified work is unknown. Normal owner Save/
Cancel/Quit proof is required before a safe update. After focused native/visual/
Safari acceptance, freeze source and run ONE accumulated `./sf verify` collector.
No source edits underneath it. Fix real failures with affected coverage, not
unchanged repeated broad suites. Compare source, testing-provision and installed
fingerprints before claiming refreshed delivery; the old 815 fingerprint does
not certify these sources. Preserve protected Aurora packages/resource sidecars
and genuine recovery. No recovery cleanup or legacy-history reinterpretation.

No commit, push, GitHub, signing, release or new unrelated feature is authorized.
OD-018/019 component architecture, broad typography/font distribution, responsive
style/content systems and universal export/browser/release certification remain
outside this package. Return next to accumulated acceptance/local delivery.
