# Aurora workflow follow-up — focused acceptance in progress

## Final changed-tree verification — 2026-10-21

Collector `20261021-034253-d689cac6` PASSED, 07:42:53–09:53:03 UTC:
repository/build and 682 code + 133 UI = 815 tests, zero failures/skips;
`failed-selectors.json` is empty. Every new and repaired selector passes in
the complete UI target. No publish-during-update/invalid-view-geometry text;
56 retained Apple QoS diagnostic lines remain classified by the existing
residual note, not suppressed or recast as new product failures.
Source fingerprint stayed
`85f0f55de2b76a6f016d8ffe0651278f108a66eef0276570e5b407f5d204bb79`,
matching regular installed app and its testing provision. No source changed
during collection. No collector or test runner remains.

This closes implementation and integrated acceptance for the bounded workflow,
not all specification modules, universal browser parity, release or GitHub.
Historical pending/failure records below are superseded for the source gate.

Extra installed-shell review remains explicitly incomplete (OD-025): after the
passing gate and installed Aurora journey, `installed-dark-review.xcresult`
executed zero tests because XCTest timed out enabling automation mode. Native
fallback read Welcome and blank and retained `live-installed-review/installed-blank.png`.
That original-resolution capture is inspected: fitted paper/grid/pasteboard,
centered empty hint, readable nonwrapping destinations, no authored/debug object.
Settings shortcut and fresh SiteForge binding then returned a closed native pipe;
Finder remained readable and the Mac was unlocked. Sampling the regular app
shows normal AppKit main-event waiting, not a proven product deadlock. No force
quit, permission reset or speculative code change. Owner normal reopen/Settings
confirmation or screenshot is the remaining installed comparison. The running
ordinary app has a new blank document, not the protected original or Study.

## Independent reuse and contextual editing — 2026-10-21

Installed follow-up: `installed-aurora-review.xcresult` passes 1/1 (158.722s)
against `/Applications/SiteForge.app`, with the exact same native test using a
driver-supplied existing Study input and a new ordinary review destination.
No app mutation hooks or fixture-content launch arguments. Native Open, Save As,
copy/include/presets, actual Safari, close/reopen and ordinary Quit all pass.
All seven `installed-aurora-captures/` images inspected: readable dark controls,
upright text, aligned Header, Mobile menu, fitted gutters, saved independent copy.
Existing Tablet label ellipsis and authored overlay limits at wide browser widths
are retained, not claimed as universally responsive composition. No ghost/stale
selection or invalid geometry/publish-during-update message observed.

Fresh before/after SHA-256 manifests match Editorial, Study and both resource
sidecars. This is a current package/resource preservation check, not a fabricated
replacement for the unavailable historical 69-file recovery manifest. No genuine
recovery was written, and prior Study conversion/padding was not repeated.
Installed Info and OwnerTesting provision match current source fingerprint
`85f0f55de2b76a6f016d8ffe0651278f108a66eef0276570e5b407f5d204bb79`.
The runner's first in-repository build failed only for Finder resource-fork
signing metadata; an outside-repository runner build passed without source or
signing-policy change. Repository/security/architecture/423-record traceability,
runtime/icon/evidence checks and `git diff --check` pass. Final changed-tree gate
is next; the milestone is not complete yet.

Repair collector `20261021-002649-dee2b04f` finished PASSED: repository/build,
675 code + 129 UI = 804 tests, zero failures/skips/expected failures. This is the
pre-consolidation snapshot, not a pass for the subsequent production edits.

Current source uses existing duplication for opt-in named/route page reuse,
including document-owned metadata in the same transaction. Header/Footer Include
All Pages compiles existing edits atomically, preserving identities, labels/order
and no-op behavior; locked/stale/cancel/capacity inputs are neutral. No schema or
global shared-content model. Plain Text uses contextual Text Foreground beside
Typography. Shared title resolution exposes truthful provenance without changing
rendered values. Bounded SF-0303-002/003/004/005/006, SF-0308-002/003/005/006,
SF-0507-003/005/006, SF-0509-003/006, SF-0806-002/003/005/006 and
SF-1207-003/005 remain Partial.

Focused model group passes 8/8 (`focused-e88985da-18de-419d-8aac-05c982dbb784`),
with separately strengthened metadata/package and deep-clone assertions passing.
The added title-provenance regression passes 1/1 in `focused-31b7bd84-9d5e-4b3a-ba14-9e979f269901`.
Controls UI passes 3/3 in `focused-23ab18c7-ae8d-444c-96dc-b411f96f1e34`:
`testContextualTypographyReturnTabEscapeAndColorTargetJourney` (62.482s),
`testRelatedPageReuseControlsAtPracticalMinimum` (31.913s),
`testRelatedPageReuseNavigationActionAuditAndNativeReopenJourney` (231.866s).
Existing foreground/token/inline journey passes (179.803s) in `focused-ff40cf75-24d0-4ae6-affa-e35868bc652f`.
That earlier group had two now-corrected test failures; it is not a whole pass.

`testAuroraRelatedPageReuseNativeCopyAndSafariJourney` passes 1/1 (142.149s),
`focused-8c05cb14-7563-40ec-b918-4fb401a850ed.xcresult`. It starts at normal
Welcome without project-content launch hooks, saves an independent packaged
Aurora, copies via real Page controls, includes destinations, visits three
presets, previews in Safari, closes and opens the actual saved package, and
asserts stable Home/copy PageIDs and noncanonical preview/preset byte neutrality.
Failures exposed Safari's link title (not label) and Go to Folder selecting the
similarly named resource sidecar. The helper now selects the exact file in its
parent and waits for live enabled/hittable Open; no Save implementation workaround.

All nine control captures in ignored `workflow-reuse-20261021/reviewed-controls-captures/`
and seven in `workflow-reuse-20261021/aurora-passed-captures/` inspected. Dark
native sections, nonwrapping destinations, centered pasteboard gutters, upright
text, selected Header bounds, Mobile menu and reopened copy are coherent. Long
Tablet navigation names retain existing ellipsis; fixed authored spacing and
browser-width composition are not universal responsive/pixel-parity acceptance.
The earlier no-Home fixture captures exposed inaccurate default-title provenance;
the shared resolver and explicit regression now correct it.

Matched actual pointer audit: page 10 -> 6, current navigation 2 -> 1; equal text
entry/setup/reset excluded, no timing or total-workflow percentage claim. The
complete method/test matrix lives in the adjacent authoring-friction evidence.
Next: regular installed-app refresh and protected Study-copy review, then one
final accumulated changed-tree checkpoint. No commit/push or original/recovery
rewrite; do not replay Study conversion or padding edits.

## Targeted collector repairs — 2026-10-21

Additional observed tooling repair: preparation `20261021-002446-9a5c34ca` was
cancelled before build/tests because Swift rejected the native progress helper's
nonisolated top-level construction of its main-actor delegate. The whole AppKit
entry now uses one explicit main-actor scope and retains its delegate through
the run loop. The launcher type-checks before locking/spawning, so this failure
cannot silently leave an invisible progress helper. Type-check and affected
`Tests/Tooling/test_unattended_verification.py` pass 21/21, including a new
compile-failure/no-spawn/no-lock regression. Its initial test expectation needed
canonical `/private/var` resolution; the corrected deterministic assertion passes.
No product/UI source changed after the focused 2/2 pass. Cancelled preparation
is not a full verification result. Python bytecode cache is ignored generated
debris, not part of the source/artifact fingerprint.

Collector `20261020-213032-8c1fc557` completed FAILED: build passed, 675 code
tests passed, UI 127 passed / two failed / zero skipped; repository failed on
ambient Python's missing PIL. This supersedes historical running/banner notes.

The icon checker now runs through declared Pillow 11.3.0 in a private ignored
venv. Setup is explicit and portable; normal repository checks, unattended
preflight and the installed-testing packager validate the same runtime. Missing
runtime exits 2 with the setup command, never skips artwork verification. Both
prerequisite regression cases, approved icon and full repository checks pass.
No global package, approved artwork or system settings were changed.

SF-0306-003/004/005/006: the failed recovery journey searched ordinary bundle
identity/path while the actual collector used OwnerTesting. Its force-termination
guard now requires configured bundle, exact runner-sibling Debug executable,
current-run recorded PID and matching lifecycle bundle/executable record. No
ordinary installed application qualifies. First/clean/interrupted launch,
retained snapshot bytes and recovery offer assertions remain intact.

SF-0507-003/005/006: the failed token-name field was at Y=993, height=26, below
the safe Inspector viewport. AX reported it hittable; screenshot/hierarchy show
foregroundHex still focused. The native field was never fully revealed. The
journey now uses the shared strict live-control containment/reveal helper before
the real click; keyboard-focus verification and Return/Escape/token/inline/reset
assertions are unchanged. No speculative product focus or recovery patch.

Both exact failed selectors pass 2/2 in
`focused-8fb70684-3db1-4096-af4f-853a1d7339b5.xcresult`, exit 0:
`testCrashQualifiedRecoverySeparatesFirstCleanAndInterruptedLaunchJourney`
(25.368s), `testTextForegroundNativeInspectorTokenAndInlineParityJourney`
(178.210s). Log, bundle and original-resolution captures are retained under
ignored `.codex-loop/full-verification/targeted-repair-20261021/`.
All seven captures were visually inspected: clean Welcome has no crash offer;
interrupted work offers explicit review/Later; red authored, green bound/inline
and reset automatic text stay upright/aligned; controls and token fields are
readable after scrolling, no ghost or external obstruction. No publish-during-
update or invalid geometry message appears. The separate integrated checkpoint
remains required; no milestone completion or new recovery-checksum claim.

## Historical accumulated attempt and external obstruction — 2026-10-20

`full-77de4af7-db9f-4e5c-a724-33f7a8e611e4.xcresult` passes all 675 non-UI
checks and eight UI journeys, then fails
`testButtonLinkInternalTargetControlsAtPracticalMinimum` at its post-Undo
Home-target assertion (line 5769). The exact owned collector was interrupted,
exit 75; this is not a full gate or a zero-test pass. No runner remains.

Fresh `B8968276-F03D-4D09-A472-C0CF402CEFEE.png` shows the unrelated system
notification covering title-bar Undo/Redo. The logged Undo click falls back to
screen point (1580, 76), inside the banner; the target had been correctly removed
immediately beforehand. Therefore no speculative command/history patch is made.
The capture remains outside the repository in owner-local
`workflow-compact-undo-obstruction`. Native Notification Center inspection shows
only its calendar widget, not a standard banner-dismiss target. Owner dismissal
of that one banner is requested (OD-024); no notification/privacy settings,
system services or owner project data are changed. Next is only the exact compact
test after dismissal, followed by accumulated verification when ready.

Read-only preservation check on 2026-10-20: the original Editorial checksum
still matches its before-workflow manifest. The prior 69-file recovery baseline
manifest is no longer present in the temporary evidence directory, so today's
recovery hash comparison could not be repeated; the successful 2026-10-18
comparison below remains historical evidence, not a new hash claim. No recovery
files were modified by this resume. Installed application/provision fingerprints
still agree at the previously delivered source fingerprint; they have not yet
been refreshed to the current test-source tree.

## Structural acceptance resumed — 2026-10-20

The exact pending selectors pass 2/2 in
`focused-20923f31-5b20-456e-9592-6237107acb48.xcresult`:
`testStructuralLayoutControlsRemainReachableAtPracticalMinimum` (34.303s) and
`testStructuralLayoutInspectorReflowsSectionStackAndGridJourney` (262.069s).
No privacy/service reset or repeated blocked activation was used. The prior
`focused-aec94d75-3857-44ed-ba62-76a78fb53d69.xcresult` failed both app activations
before feature assertions, not the concrete-button correction; its final
zero-test suite is not accepted evidence.

The preceding integrated attempt passed 675 models and 116 UI journeys before
the structural test compared an outdented segmented AX wrapper against the
scroll viewport. The screenshot shows the native buttons visible. The check
now validates both concrete Vertical/Horizontal targets and uses the shared
bounded foreground/enabled/hittable/screen-containment helper, without relaxing
the bounds or changing authored layout.

Eight structural and two minimum captures were inspected at original resolution
in owner-local `workflow-structural-segments-final-captures` and
`workflow-structural-minimum-final-captures`. Direction/alignment labels remain
readable, geometry and selection agree, Grid order/reset and saved reopen are
truthful. Several captures include an unrelated OS notification over the title
bar; they are not accepted as unobscured full-window presentation evidence.
No notification settings were changed. Final integrated acceptance is pending.

Requirements: bounded SF-0201-003/006, SF-0501-001/003/004/005/006,
SF-0502-003/005, SF-0505-001/002/003/004/005/006,
SF-0507-003/005, SF-0602-003/005, SF-0701-002/003/004/005/006,
SF-1203-003/004/006 and SF-1207-003/004/006. Modules remain Partial.

## Implemented source

- Measured five-destination normal navigator/Inspector rows, wider bounded
  normal pane minima, and preserved compact/large-text adaptation.
- Registry-validated unchanged Site Settings Apply closes without history and
  reports that settings are unchanged, not an unrelated appearance error.
- Opt-in canonical Fill/Hug sizing, width-first wrapping, intrinsic parent
  propagation, computed read-only Inspector geometry, and exact inverses.
- A separately confirmed subtree conversion removes dimension overrides only
  with explicit consent. Original fixed geometry/content/IDs remain intact.
- Shared actual Core Text font objects and authored optical size prevent both
  private-font name substitution and zoom-dependent system-font wrapping.
- Design Essentials reuses existing label, geometry and destination controls;
  typography/color remain on that same tab. No second mutation path exists.

## Focused results

`focused-14f135e0-1a83-4770-9032-19e51a344431.xcresult` passes
four model/native-render checks and one real-app journey:

- `TransformModelTests/testResponsiveContentConversionIsExplicitAtomicAndRestoresOverridesAndIDs`
- `TransformModelTests/testSizingModesCommitSeparatelyPreserveFallbackAndExactInverse`
- `InsertionModelTests/testResponsiveFillAndHugUseContainingWidthAndPropagateWrappedHeightWithoutMutatingIntent`
- `CanvasTextRenderingTests/testIntrinsicSizingAndLiveCanvasUseSameFontAndWrappingBounds`
- `SiteForgeLaunchTests/testNativeFillHugSizingModesPreserveIdentityUndoAndComputedGeometryJourney`

The metric matrix covers 320/375/390/430/574/768/1024/1440 widths;
native font/wrapping parity covers System, Georgia, unavailable-family fallback
and 25/100/800% zoom. It caught real unsupported private-font reconstruction
and optical-sizing divergence; those were corrected, not waived.

Additional focused evidence retained from this workflow:

- Three model/pane/settings checks pass in
  `focused-a41354c8-ad69-4960-ab8e-b748c3b013dd.xcresult`.
- Normal five-tab/Inspector geometry journey passes 1/1 (61.129 seconds) in
  `focused-445257d1-c7e8-4512-9c20-1b7e3c4a15f5.xcresult`.
- Unchanged Site Settings journey passes 1/1 (20.443 seconds); the containing
  earlier mixed bundle is not claimed wholly green.
- `testContextualEssentialsEditLinkedButtonWithoutInspectorTabSwitchesJourney`
  passes 1/1 (84.923 seconds) in
  `focused-6725b83a-7870-42d0-a62c-10b2e87b0d3a.xcresult`. That bundle also
  contains a failed new Aurora conversion locator and is not wholly green.
  Label, Width, Height, native destination, invalid URL/Escape and Undo/Redo
  were operated on Design with zero additional Inspector-tab changes. Earlier
  observed authoring required Content/Layout/Design/Interactions transitions;
  no invented time-saving percentage or unmeasured total click count is claimed.

Latest integrated focused checkpoints:
- `focused-1a60d004-8528-4dbf-b103-564cde76f6b1.xcresult`: two model checks and
  `testAuroraResponsiveContentConversionPreservesSelectionAndReflowsAcrossPresetsJourney`
  pass (native journey 75.523s). Earlier Touch Bar locator failures are retained,
  not counted as passes; the final confirmation is scoped to the actual sheet.
- `focused-43c8fcc3-65c3-4c8c-935a-7f07344d3eb4.xcresult`: four model/native
  renderer checks plus two native journeys pass. The models are
  `testConnectedHugHeightUsesResolvedInspectorAndRejectsFallbackMutation`,
  `testFrameAndTextUseOneUprightTopLeftTileConventionAcrossViewportMatrix`,
  `testCanonicalTypographySharesRendererAndInlineMetricsAcrossZoomAndAlignment`,
  and `testSizingConstraintsSetClampAspectResetAndExactHistory`. Essentials
  passes in 87.884s; existing typography/inline/Undo/Redo/save/reopen passes in
  97.685s. All nine retained final captures were inspected.
- `focused-e62306e9-66e7-4f82-b1db-4f2897ca9e96.xcresult`: four checks pass on
  adopted-snapshot Inspector geometry, responsive layout, conversion and the
  immutable schema-four legacy surface package fixture.
- `focused-08ee82e5-a217-4148-bd88-a18653fd863f.xcresult`: 2/2 pass:
  `testHugStackBreakpointOutputResetsFlexBasisAndPreservesButtonLabelAlignment`
  and `testResponsiveFillAndHugUseContainingWidthAndPropagateWrappedHeightWithoutMutatingIntent`.
  The new output regression preserves fixed 64-point Button height, resets the
  full flex basis when a row becomes a column, preserves flex label centering,
  and requires content-sized rows for the opt-in free-Frame overlay grid.

These are overlapping focused checkpoints, not a summed full-suite total.

## Visual review and measurements

Original full-window captures are retained outside the repository in the
owner-local correction evidence directories. The five-tab measurement before/
after captures show readable single-row labels and aligned selection/content.
All eight measured Layout states have field X 23.5, field Y 257.5, field width
152, heading X 12.5, content width 332 and scrollbar value 0: selection,
Return, Undo, Redo, tab round-trip, Tablet, Mobile, Desktop. This is evidence
for that sequence, not a claim that every possible Inspector update is stable.

Essentials label/size, destination and exact-redo captures were inspected.
They show upright text, stable selection, readable five-tab rows and real
destination controls. Review found the foreground field squeezed by its color
well's intrinsic width; the well now uses the same explicit native size as the
fill control and the entry placeholder is concise. All nine final Essentials/
typography captures confirm the refinement, upright text and inline/committed
alignment. Computed dimensions now read the adopted immutable render snapshot;
the separate Section height control cannot silently edit a dormant fallback.

## Installed Study and browser comparison

The regular app was saved and quit normally before each bounded update. Latest
installed source fingerprint:
`2d25a03f100d1cab8b57b46b7c16b18cc1c59a956c5665b1f47d31e472ea9f12`.
No extra named app copy was introduced.

The actual saved Workflow Study was converted once through visible controls
(seven compatible nodes; two fixed Buttons explicitly skipped), then its shared
content Stack padding was authored once as 32. Native installed acceptance
`testResumeConvertedWorkflowStudyPaddingAndPreviewWithoutReplayingConversion`
passes 1/1. `testReopenConvertedSavedWorkflowStudyAndPreviewWithoutMutation`
passes 1/1 (27.356s), proving retained Hug/padding and truthful Saved after real
normal quit/reopen, followed by native browser Preview. These black-box helpers
remain outside the repository; no product hooks or canonical file writes.

A read-only comparison proves all 84 NodeIDs, names, ownership/order, content,
and base X/Y/width/height remain unchanged. Revisions 183 → 185 represent only
the explicit conversion and shared padding. Only consented dimension overrides
were removed; neither skipped Button changed. Original Editorial and all 69
original recovery file hashes still match their before-workflow manifests.

Visual review found two browser defects rather than accepting CSS-string
assertions alone. A Desktop flex width basis became a Mobile height after axis
change. Resetting the full basis per breakpoint fixes it without touching
geometry. Safari also retained a 982-point default auto grid row around a
432-point content Stack plus 70-point offset; explicit content-sized rows at
the free-Frame boundary resolve the correct 502 points. A temporary browser-only
diagnostic isolated that cause; it was removed by reload. Final captures use
fresh output from the installed production source, not modified page styles.

Owner-local original-resolution directories inspected:
- `workflow-installed-study-final-captures`: Desktop/Tablet/Mobile native
  responsive content, shared padding and Saved/Preview status (four captures).
- `workflow-final-typography-essentials-captures`: all nine final native states.
- `workflow-safari-final-reviewed`: `width-320.png`, `width-375.png`,
  `width-390.png`, `width-430.png`, `width-574.png`, `width-768.png`,
  `width-1024.png`, `width-1440.png`. All eight inspected: upright wrapping,
  containing-width content, fixed-height readable Buttons, appropriate vertical
  versus horizontal actions and bounded spacing. The smallest viewport scrolls
  normally; the existing minimum page height is not silently rewritten.

Responsive-mode AX link clicks again targeted the Header rather than an anchor
(temporary sanitized native event tracing), so that attempt is not claimed as
a new navigation pass. Existing normal-browser Return/Escape/Journal delivery
evidence remains valid; no speculative navigation patch was made. Temporary
instrumentation is absent from final production source and reloaded output.
Browser/system font shaping and the generated coast/Georgia differ from the
concept; no universal browser or full-module parity is claimed.

## Still required before integrated acceptance

The native conversion, installed Study and matching/intermediate-width browser
review are complete for this bounded follow-up. Reconcile factual documents
and run the accumulated final `./sf verify`; no full-gate pass is claimed yet.
Original Aurora and all 69 owner recovery files remain checksum-identical.
No original project conversion, commit, push or publication is authorized.

Integrated attempt `full-350be5b1-b888-4e65-8306-b6afdd24a9f9.xcresult`
passed repository checks/build but exposed six model/fixture failures and two
Settings journeys; it was explicitly interrupted instead of continuing an
already-red full run. Historical synthetic fixtures had incorrectly retained
the new metadata key while changing their schema number; they now use the
actual old shape, preserving strict decoder rejection. Welcome's exact
announcement and Settings default expectations now match Aurora/Dark behavior.

Focused `focused-2e1209c7-8cce-445c-9940-443f39f64599.xcresult` passes all six
affected model checks and
`testApplicationSettingsGroupResetCancelRestoreAndRelaunchJourney` (58.957s).
The separate appearance test remains blocked by the unrelated macOS Safari
Apple Events permission dialog: its recording proves UserNotificationCenter
owns the modal and disables input to Settings. See OD-023; no product enabled
state or test assertion was weakened. The historical chrome-forgery assertion
was strengthened to remove unrelated metadata first and passes independently
1/1 in `focused-fac83892-2326-4547-bfc9-609b4725310d.xcresult`.
After the owner reported no prompt visible, the exact appearance selector passed
1/1 (37.828s), bundle `focused-4de2a0c3-86e7-45cb-a6de-acd755018b88.xcresult`.
No permission was granted or reset. OD-023 is resolved; the package stays
IN PROGRESS pending the accumulated final gate.

The next integrated attempt, `full-53755cfd-467b-4f43-8ea7-b76507b3e8a8.xcresult`,
passed all 675 model/integration checks, but the dark-editor journey still capped
the navigator at 300 points (observed 341), contrary to the approved measured
five-tab contract. It was stopped, not claimed green. The visual assertion now
requires navigator 324–360 and Inspector 356–420 (one-point AX tolerance), canvas
minimum/remainder and no overflow. An old contradictory range in the visual
contract was reconciled; no production pane was shrunk to satisfy the old test.

`focused-994388ba-9214-4f86-bb87-f74f60f28987.xcresult` passes 3/3:
- `WorkspaceMaterialPolicyTests/testSelectedReferencePaneAllocationKeepsCanvasDominantAtMinimumAndMaximizedWidths`
- `WorkspaceMaterialPolicyTests/testNormalPaneMinimaFitAllFiveMeasuredDestinationLabelsWithoutOverflow`
- `SiteForgeLaunchTests/testDarkEditorialEditorAndSharedInspectorVisualJourney` (34.234s).

All five original-resolution captures in owner-local
`workflow-dark-measured-panes-final-captures` were inspected: blank, Content,
Accessibility, Design and fixed Settings. Rows are readable, page/grid and pale
authored content remain distinct, selection is aligned, and section controls
are not clipped. All five appearance preview/commit/cancel/reset/relaunch
captures in `workflow-appearance-final-captures` were also inspected. No system
modal is present. Neither focused result substitutes for the final full gate.
# Fresh clear-screen pointer acceptance — 2026-10-20

Bounded SF-0201-006/008 and SF-0702-006: after the owner confirmed no notification,
the unchanged `SiteForgeLaunchTests/testButtonLinkInternalTargetControlsAtPracticalMinimum`
passes 1/1, 52.649s, exit 0. Bundle
`focused-75b3a453-d776-44f2-8d7c-cb50f82a0b96.xcresult` and matching log are retained
in ignored `.codex-loop/full-verification/owner-clear-focused/`.
Removal first resolves No target; the real `toolbar.undo` pointer action at
49.27s restores the live Home page target at 50.91s. No center fallback appears.
Both original-resolution 2200×1504 captures were inspected:
`captures/DA00FCD9-F3E9-4D78-A915-2EF3EBF0BFCA.png` (authored target) and
`captures/EBFFDE2D-C75B-48B4-9607-4EA66D8ABB67.png` (restored target).
Toolbar is unobstructed, target/context readable, selection/content aligned;
Redo is enabled after Undo. No product/test changes or weaker assertions.
No publish-during-update or invalid-view-geometry message appears; an Apple QoS
warning remains observable and is not reclassified. Historical temporary
artifacts are missing, not evidence of a current obstruction. OD-024 resolved;
accumulated verification is still required. Original Aurora/recovery untouched.
