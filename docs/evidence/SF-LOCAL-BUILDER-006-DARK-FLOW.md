# Aurora Dark Flow — public-control authoring

Status: IN PROGRESS. No finished website or verification claim.

## Owner testing hold — safely stopped authoritative run, 2026-10-27

The owner superseded prior automatic verification authorization with HOLD ALL
TESTING until explicit approval. The exact owned xcodebuild77761 (child of this
`sf verify`, bound to the unique bundle below) received SIGINT. No owner app was
force-quit. Collector session80878 exited75; read-only process inspection confirms
the collector, xcodebuild and UI runner78211 are gone. No new test was launched.

Retained bundle:
`dark-flow-authenticated-final-results/full-006e2c73-8f20-4cd8-916d-c8736ec2cddb.xcresult`;
log: `dark-flow-authenticated-final-verify.log`. Actual summary: **833 passed,
one cancellation, three skips** out of837 recorded outcomes. This comprises
733/733 non-UI and100 UI passes. The cancelled UI case is
`testProductNavigatorProvidesTruthfulElementsAssetsAndComponentsDestinations`;
failure text explicitly says “Testing was canceled.” Thirty-eight of142 declared
UI methods were not reached. There was no recorded SiteForge assertion failure
before owner-requested cancellation. This is NOT a complete/green full gate.

Existing skips, unchanged:
- `testOwnerDarkFlowNativeThemeAndFlow`: owner-open independent project required.
- `testOwnerDarkFlowVisibleGradientControls`: same owner-open project requirement.
- `testOwnerDarkFlowTransferSavedProjectToCurrentBuild`: explicit owner-session
  project and isolation storage required.

Readiness itself was demonstrated after owner authentication (native1/1 and
actual CLI UI execution), distinct from unfinished full acceptance. All nine
previously repaired methods, including native nesting/history, Rename, header/
footer, typography, asset history and structural layout focused evidence remain
preserved; historical passes are not combined into a fabricated green gate.
No further tests/check suites/UI automation/install will run during the hold.
No privacy/service changes, commit or push. Installed app stays26.10.21; accepted
revision245 owner website/export, recovery, projects and all evidence preserved.

## Owner-assisted native readiness passed — 2026-10-27

After the owner reported completing the actual system authentication, no prior
runner was active. One exact-method native Test navigator attempt ran (not a
scheme-wide run). macOS automation enabled state changed from0 to1 at01:10:47
-0400; SiteForge launched with ordinary identity. The unchanged existing
`testApplicationLaunchesCompleteNativeShellAtPracticalMinimumSize` **passes1/1**,
zero failures/skips in `Test-SiteForge-2026.10.27_01-10-46--0400.xcresult` in normal
DerivedData Logs/Test. No runner remains; source fingerprint unchanged4b3301f6…,
23 GiB free. This is changed readiness evidence, not a fabricated full-gate pass.
The concrete current correction was owner completion of native authentication,
not a speculative app/configuration patch. Preserve the historical failed runs.
Reconcile/freeze for one ordinary-identity ./sf verify, no competing input or
source/doc edits beneath it; install only after its actual green result.

## Bounded native readiness comparison — 2026-10-27

**Final reconciliation:** the native session has finished. Its ordinary Xcode
result `Test-SiteForge-2026.10.27_00-55-21--0400.xcresult` in the normal DerivedData
Logs/Test directory records zero passes, zero UI methods executed, one runner
initialization failure, zero skips: “Timed out while enabling automation mode.”
Xcode console agrees and Stop is disabled. Process inspection finds no collector,
xcodebuild or UI runner; historical PID75613 is gone. The previously inspected
UIAgent dialog is no longer available; this does not establish authentication
success or denial. No second run was launched. The native route now reproduces
the CLI pre-method startup boundary, despite the earlier successful native
comparison. An invocation/configuration fix is not supported by this evidence.
Smallest actionable next step is owner-present authentication in the actual
macOS dialog during one coordinated exact-method native attempt. No broad gate
until readiness is demonstrated, no service/privacy changes or installed update.
The pending language below describes observation before this final result.

Requirements: SF-1201-004/006, SF-1203-003/004, SF-0806-003/005;
shell comparison SF-0201-002/006/008. No active collector or runner existed before
starting. Xcode Test navigator was filtered to the exact existing
`testApplicationLaunchesCompleteNativeShellAtPracticalMinimumSize` method and its
own Run context action selected, not the scheme-wide Test action. Ordinary
SiteForge scheme/My Mac destination, selected Xcode developer directory and
DerivedData match the previous native comparison and failed CLI run. The actual
test configuration targets `Debug/SiteForge.app` and the SiteForgeUITests bundle;
no identity override or repository invocation defect has been demonstrated.

After the build, native runner 75613 reached automation initialization. Logs at
00:57:16 -0400 show the automation writer requested authentication. Unlike an
inference from those logs, supported native inspection of the already-running
`com.apple.LocalAuthentication.UIAgent` **actually exposes** the system dialog:
“XCTest is trying to Enable UI Automation. Touch ID or enter your password to
continue with XCTest.” Its real buttons are Use Password and Cancel. This is
the concrete current owner-only boundary. A single precise owner request was
sent; no credentials, privacy changes or authentication actions were entered by
the agent. No UI method or passing readiness result is claimed yet. The prior
CLI request alone does not prove the same dialog was visible then. Do not
duplicate the native run or launch a broad suite while this request is pending.

## Post-cleanup full gate — external UI initialization boundary, 2026-10-27

Requirements: SF-0806-003/005, SF-1201-004/006, SF-1203-003/004.
The single authorized ordinary-identity post-cleanup `./sf verify` completed;
it is **not green**. Retained log: `dark-flow-post-cleanup-verify.log`.
Bundle: `dark-flow-post-cleanup-verify-results/full-8179c1a9-8ec4-47e4-b8f4-88dd6c27ac7a.xcresult`.
Repository checks and 733/733 unit/integration tests passed. Result summary:
733 passed, one runner-initialization failure, zero skips, zero UI methods run.
The three historical owner-session skips were not reached in this run and must
not be counted again. At 00:15:23 -0400, the UI runner reported XCTest
XCTFuture code 1000, “Timed out while enabling automation mode.” At 00:15:33,
testmanagerd reported “Results channel was never configured.” This establishes
a pre-journey automation initialization failure, not a SiteForge assertion,
screen-lock diagnosis, or recurrence proven to involve cache_delete. The exact
underlying OS cause is not established; do not claim authorization was denied.

Read-only reconciliation confirms no collector, xcodebuild or UI runner remains,
source fingerprint still `4b3301f6d5d6f4f70072205bde3a6750ecf9031fab0c2c1ddad291a964e1ae9d`,
and 22 GiB free. No duplicate broad run, privacy/service change or install was
performed. OD-026/027 remain resolved. Installed bundle remains version
26.10.21, fingerprint `85f0f55de2b76a6f016d8ffe0651278f108a66eef0276570e5b407f5d204bb79`.
The safe local refresh remains gated on full verification, not on a repeated
permission question. Accepted revision245 website/export and evidence remain
preserved; this external boundary prevents milestone completion/local delivery.

## Owner-authorized cache cleanup and local refresh scope — 2026-10-26

Owner resolved OD-026/027: existing local-only ad-hoc signature may be used after
green verification; only regenerable build-cache cleanup is authorized. No active
app/test/build process existed before cleanup. Removed about 1.7 GiB from these
seven ignored `.build/` directories:

- `owner-local/DerivedData/Intermediates`
- `experimental/DerivedData/Intermediates`
- `installed-review-runner/Build/Intermediates.noindex`
- `installed-review-runner/SDKExplicitPrecompiledModules`
- `installed-review-runner/ModuleCache.noindex`
- `ci-ui-baseline/Build/Intermediates.noindex`
- `ci-ui-baseline/ModuleCache.noindex`

No app product/backup, project, recovery candidate, screenshot, log or result
bundle was removed. Compilers can regenerate the removed data. Ordinary active
verification DerivedData and its Logs/Test were preserved. Source fingerprint is
still `4b3301f6d5d6f4f70072205bde3a6750ecf9031fab0c2c1ddad291a964e1ae9d`.
No service/privacy change or installed replacement occurred. Reconcile and freeze
one post-cleanup full gate; storage was only a possible eviction trigger and
cleanup is not claimed to fix macOS. Safe local refresh remains gated on green.

Pre-run storage is now 20 GiB free / 90% used. Whitespace and 440-record
traceability pass after reconciliation. Freeze the unchanged source plus these
factual docs for one ordinary-identity post-cleanup `./sf verify`; no edits or
duplicate input driver under that run. Exact result will be appended afterward.

## Reconciled full gate — external runner termination, 2026-10-26

The single isolated retry subsequently **passes 1/1, 99.566s**, on unchanged
fingerprint `4b3301f6…`: `dark-flow-fixes-focused/focused-39fedc1a-36b1-48bd-8094-a85b3681ad28.xcresult`.
All authoring/search/favorite/Undo/Redo/save/reopen assertions complete. This is
not a replacement full-gate result. Process inspection confirms no SiteForge app,
UI runner or xcodebuild remains. Whitespace/440-record traceability checks pass
after factual documentation reconciliation. Await OD-026/027; no unchanged broad
retry, cache deletion, installed replacement, signing, commit or push.

The frozen `4b3301f6…` source fingerprint remained unchanged throughout the
completed `./sf verify`. Repository/security/440-record traceability/build pass;
733/733 unit/integration pass. Result bundle
`dark-flow-reconciled-final-results/full-a222e0fc-7144-40ab-a9aa-a954a7421ac8.xcresult`
records **871 passed, 1 failed, 3 owner-session skips**: 733 non-UI plus 138 UI
passes; the sole failure is `testNativeAssetOrganizationSearchFavoriteUndoAndReopenJourney`
with `Test crashed with signal kill.` Exit 65, NOT a green full gate.

The runner was terminated at initial Window readiness, before asset authoring.
Targeted macOS logs identify the exact external request at 02:27:30 -0400:
`com.apple.cache_delete` requested `CacheDeleteAppContainerCaches` termination
of `app.siteforge.SiteForgeUITests.xctrunner`, code `0xBADDD15C`; runner PID 49948
then lost its XCTest connection. This is not an app assertion, agent cancellation,
authentication failure, or evidence that the Mac was locked. Xcode restarted its
runner and completed the remaining coverage. No SiteForge assertion failed in
this gate. Publish-during-view-update/invalid-view-geometry messages were absent
from retained stdout; QoS/runtime warnings remain, so it is not called warning-free.

Disk inspection found 14 GiB free / 93% used, ignored retained evidence 22 GiB and
regenerable local build data 4.3 GiB. Storage pressure is a possible trigger, not
proved by the termination reason. No evidence, cache, project, recovery data or
system service was deleted/changed. OD-027 requests the bounded storage decision;
OD-026 separately holds any local install/signature. One isolated retry of the
interrupted asset journey is running after this concrete diagnosis; it cannot
retroactively turn the failed full run into a pass. No repeated broad gate.

## Focused repairs complete; final gate pending — 2026-10-26

All nine UI methods that failed in the uncancelled gate now have passing focused
results (not a new full-suite result):

| Method suffix (`SiteForgeLaunchTests/`) | Passed duration |
| --- | ---: |
| testComponentDefinitionRenamePropagatesToLinkedInstancesJourney | 39.688s |
| testConnectedHeaderFooterNavigationMenuHeightUndoAndReopenJourney | 252.752s |
| testConnectedNestedSectionContainerGeometryAndBreakpointJourney | 116.034s |
| testContextualTypographyReturnTabEscapeAndColorTargetJourney | 61.473s |
| testLayersParentAccessibilityTracksNativeNestingInsertionAndHistory | 44.155s |
| testLocalColorTokenBorderAndOuterShadowInspectorJourney | 81.179s |
| testNativeAssetOrganizationSearchFavoriteUndoAndReopenJourney | 98.819s |
| testNativeSelectAllInPageEditorReplacesDefaultDraftJourney | 35.218s |
| testStructuralLayoutInspectorReflowsSectionStackAndGridJourney | 264.871s |

Two affected model methods also pass: content-independent fluid diagnostics and
exact clear-selection/sibling-insertion/nesting/history (names below). No timeout
increase or removed assertion. Six of eight passed in the first repair group;
the remaining pair needed actual production corrections:

- A native context menu has a distinct hosting lifetime. Its own observed view
  now resolves current selection/lifecycle availability using the same central
  drag/drop registry, instead of retaining the Layers row's old menu capture.
  Renderer adoption and an enabled-state wait alone had failed; those were not
  accepted as the product fix. Nesting, exact history, parent AX and subsequent
  child insertion now pass.
- Rename's dismissed sheet retained a native-editing focused value. Failure
  diagnostics showed no sheet, main-window responder, and both toolbar history
  values incorrectly `Text editing`. Rename now makes that value conditional on
  its real focus state and ends focus before successful or cancelled dismissal.
  The passing diagnostic reads `Grouped Edit`/`Unavailable` before document Undo.
  Exact Frame/Feature Card label restoration passes. Temporary before-action
  tracing was removed; failure-only focus/history diagnostics remain.

One intermediate compile failed before UI execution and was corrected; it is not
counted as test evidence. No broad history/persistence change was necessary.

Original-resolution reviewed captures: `dark-flow-rename-fixed-review/`
`A2F66BAB-58DF-47F6-B5BE-E9690C59669F.png` and
`dark-flow-nesting-fixed-review/396A1D12-236D-42BB-9E26-7BD95C78DA1D.png`.
Readable single-line pane/header labels, upright nested Text and aligned selection
are preserved. These are ordinary blank-document test objects, not the owner
website or authored fixtures. Accepted revision-245 browser visuals are unchanged.
No installed-app refresh, commit or push. Reconcile docs then freeze ONE final
full gate; earlier failed totals remain historical evidence, not completion.

Reconciled final freeze: source/test/tooling fingerprint
`4b3301f6d5d6f4f70072205bde3a6750ecf9031fab0c2c1ddad291a964e1ae9d`.
Whitespace checks and 440-record traceability pass. No app/test runner remains
before launch. One ordinary-identity `./sf verify` follows with private test
fixtures and the same native-comparison DerivedData; no source/doc changes under
that run. Local install/signature decision OD-026 remains separate and pending.

## Completed uncancelled gate and focused repairs — 2026-10-26

Frozen ordinary-identity run `full-a85a5d73-bc20-4115-96c6-dac8cb500538.xcresult`
completed: 861 passed, 10 failed, 3 skipped. Non-UI 731/732; UI 130/139 executed.
The skips are the three explicitly owner-session-only Dark Flow authoring/transfer
methods, not cancelled general coverage. Original reuse (242.980s), corrected
conversion (82.518s), and prior cancelled Button/Link case (126.090s) pass.
No early cancellation, installed replacement, or complete/green claim.

Privacy failure was a substring check for `180` in a record containing sanitized
identity hashes. Replacement proves exact diagnostic equality for distinct
authored min/preferred/max values, retaining the raw-identity exclusion. Focused
`TransformModelTests/testFluidValueRegistryCommitsApplicableSubsetPersistsAndRestoresExactInverse`
passes 1/1. `DragDropModelTests/testClearSelectionThenSiblingInsertionOffersCanonicalNesting`
passes 1/1, proving the exact canonical clear/insertion/nesting/history path.

Retained original-resolution `dark-flow-final-undo/undo-49.png` and its AX text
show Footer height 240 still keyboard-focused when document Undo was expected.
Native field-editor Undo must remain native; document-history checks now focus
the real nonediting breakpoint popup and cancel its menu without changing preset,
selection, geometry or viewport. All exact history assertions remain.
`testConnectedNestedSectionContainerGeometryAndBreakpointJourney` passes 1/1,
116.034s, using actual Edit menu Undo/Redo after this handoff.

`dark-flow-final-nesting/nesting-27.png` shows the selected Text sibling and a
disabled Nest In context item. The model path passes; real renderer adoption and
bounded menu-enabled waits are being evaluated, not claimed repaired yet. Eight
remaining affected methods are running together. Other failed history boundaries:
component rename, Header direction, contextual typography, token shadow binding,
asset favorite after search, page-editor width, and Grid columns. Full runtime
retains QoS warnings; no warning-free claim. Final full gate/installed delivery
remain pending focused fixes and factual reconciliation.

## Native Xcode comparison and bounded correction — 2026-10-25

Both methods were selected individually using the Test navigator's exact Run
context-menu action, never Run All. SiteForge/My Mac, Xcode 27.1 build 27A9275,
native scheme app identity app.siteforge.SiteForge; prior CLI used OwnerTesting.
No Apple dialog, privacy/service change or second app-input driver.

- Related-page reuse passes 1/1, 235.493s, including Saved, actual Safari page,
  export Cancel/retry and real reopen. Retained bundle:
  `dark-flow-xcode-native-reuse.xcresult`. Original-resolution reopened Saved and
  actual Safari screenshots were inspected in `dark-flow-native-reuse/`:
  `3BDDD83C-F1AC-4AD4-852A-B13ED32FF0C1.png` and
  `E28F77E0-FB9E-4A64-86A9-934AE1F98688.png`. No speculative persistence change.
- Conversion initially fails at the post-preset Hug-height assertion (69.858s),
  plus Xcode runner-exit issue. `dark-flow-native-conversion/recording-65.png`
  shows the selected Section at Tablet with effective authored Hug and height
  452; the generic geometry field is BELOW the Inspector viewport and absent from
  AX. This is not lost sizing/selection. The driver now uses bounded real Inspector
  scrolling and a fresh identity query to reveal the disabled computed readout,
  retaining the same Hug, cancellation, selection and exact undo/redo assertions.
- Corrected conversion passes 1/1, 97.941s, no unexpected failure. Bundle:
  `dark-flow-xcode-native-conversion-fixed.xcresult`. Original-resolution images
  inspected in `dark-flow-native-conversion-fixed/`: Desktop
  `AA77571D-DF66-4FD1-8149-1110804752A6.png`, Tablet
  `107BCDFA-FED2-4ADD-8E6C-0A53D13FE706.png`, Mobile
  `15D8EA48-AD21-4CA7-8F0D-DBB5E4CA10CB.png`. Live computed heights 540/452/438,
  selected identity and upright content agree. Inspector scroll is intentional;
  unrelated fixed-template sample limitations are not silently changed.

The earlier cancelled case was caused by the agent sending SIGINT after failures,
not an established collector continue-on-failure violation. It remains cancelled,
not passed. The new full gate must run remaining cases, without that early stop.
Native reuse retained a QoS runtime warning; it is not called warning-free. The
isolated-identity CLI discrepancy is not proven globally repaired by native passes.
The next supported full gate uses the same ordinary identity/DerivedData as the
native comparison; all test fixture roots remain private and the installed app is
not running. Snapshot fingerprint:
`5ffff41c033bf98540c100ba0eb2cd7bb34e327d231b7cf4ece842180a1c3fc6`.
No source/doc edits underneath the gate. Installed delivery remains pending green.

## Frozen accumulated verification snapshot

Actual outcome: repository/build pass, 732 unit/integration tests pass with zero
failures (21.480s). UI initialization succeeded; six UI cases passed, two failed,
and one was deliberately cancelled after those failures. Result: 738 passed,
two assertion failures plus one cancelled case, NOT a full pass. The cancellation
returned exit 75. Artifact:
`dark-flow-frozen-verify-results/full-af3502ef-9861-46f7-94e7-dc47c456a283.xcresult`.

Related-page reuse missed Saved (100.065s); conversion failed live pointer
readiness (32.381s). Original recording frames were inspected:
`dark-flow-save-failure/recording-95.png` visibly shows the app with Preview menu
open while its Save helper's AX snapshot lacks identifiers and has infinite/empty
frames; `dark-flow-pointer-failure/recording-28.png` shows the normal sample while
the AX attachment contains only a query chain. Neither proves a persistence bug.

Added only bounded test-failure diagnostics (live target/frame, redacted hierarchy
and named screenshot), no weakened assertion or timeout. One diagnostic pair:
`dark-flow-save-pointer-diagnostic-results/focused-b0edd099-082d-457f-937a-3d69003270c0.xcresult`,
0/2 passed, exit 65. Related-page reuse completed Save, then failed Preview URL
discovery (99.515s); conversion failed before editing at selected-height discovery
(22.755s). Input-free supported native inspection during the first case exposed
complete shipping controls and truthful Modified/key-window state for that same
test app while XCTest reported invalid rectangles. No input was injected into
the test. This proves a native/XCTest AX discrepancy, not universal app correctness.

OD-025 requests exact Xcode-normal execution of these two methods, rather than
another identical CLI retry or speculative persistence patch. No collector/app/
runner remains. Installed SiteForge is unchanged at build 26.10.21, ab18c663,
fingerprint 85f0f55d…. Full verification/installed delivery remain incomplete.

### Historical snapshot preparation

Pre-freeze repository checks pass, including security, 440 bounded traceability
records, architecture, runtime prerequisites and evidence checks; diff whitespace
checks pass. Production/test/tooling source fingerprint:
`c985a7423c4acfe708371c35b67edacadade5e10fde493db361edbf1d267348e`.
One supported `./sf verify` is next, using the isolated OwnerTesting identity.
No source/document edits or duplicate collector may run underneath it. The earlier
26 focused code passes and native/browser observations are not full-gate totals.

## Latest focused continuation

2026-10-25 current native continuation supersedes the authentication handoff:
supported direct app inspection/open/Preview/Export worked. No further XCTest
initialization retry was needed. Recent Projects truthfully requested renewed
authorization; the existing Dark Flow package was opened through the normal Open
panel, restored history, and reported Saved. Original projects/recovery were not
opened or changed.

The first current-source loopback capture at 1440 × 844 still showed the white
strip. Inspection of the normal exported CSS established the missing distinction:
the actual Root had no fill; only Header, Section and Footer were dark. A viewport
minimum cannot paint a transparent root. Through real Layers/Design controls,
Contact and Not Found each received one solid root layer bound to the existing
Dark Surface token (#100B1CFF), then normal Save. These four canonical transactions
changed neither text, geometry, hierarchy nor the Home gradient. No compiler theme
color or handwritten output was introduced. The root layer remains editable.

Native Preview/Export reports revision 245. The fresh output is named
Aurora — Dark Flow Website Delivery; an earlier normal export used the panel's
default Website name before explicit settable filename entry was confirmed.
Both are real compiled output, not manually edited files. Original-resolution
captures reviewed in ignored dark-flow-browser-review storage:

- not-found-root-fill-loopback-1440.png — 1440 × 844, no white strip.
- not-found-root-fill-loopback-390.png — 390 × 844, readable wrapped recovery text,
  contained Menu and Footer, dark surface to the bottom.
- contact-root-fill-export-390-top.png — 390 × 844, natural overflowing content.
- contact-root-fill-export-390-footer.png — scroll value 1; Footer follows content,
  no clipped paragraph or white lower band.
- contact-root-fill-export-1440.png — 1440 × 844, all content and Footer readable,
  dark viewport coverage. The prior contact-current-loopback-1440.png is rejected
  pre-root-fill evidence, not the accepted final appearance.

The app reported Saved, Preview was stopped and dismissed, and normal Quit was
confirmed by process inspection. The accumulated verification gate and installed
delivery remain pending. Existing Menu/navigation/eight-width and native gradient
evidence is reused; it was not replayed or counted as new tests. Distinct affected
code methods remain 26. The Layers description of a geometry-less Root as hidden
is a recorded usability limitation, not proof that its authored children are hidden.

### Historical authentication attempt (not a product test failure)

2026-10-25 owner-present authentication retry: the prior browser-stage run ended
with exit 65 before any test method began. After the owner explicitly offered one
retry, `dark-flow-browser-owner-auth-retry.xcresult` likewise built successfully
but failed to initialize UI testing: “Timed out while enabling automation mode.”
The matching log is retained beside the result bundle in ignored evidence storage.
System logs confirm the runner requested automation mode and its authorization
tracking was removed after the 60-second timeout; they do not establish that an
authentication dialog was displayed or completed. No authoring, export, or browser
action executed in this retry. The process exited; no duplicate retry was started.
No privacy settings, services, credentials, installed app, or owner data changed.
The owner must confirm what the native authentication surface actually showed
before another UI attempt. Current browser-stage visual acceptance, accumulated
verification and installed delivery remain incomplete (SF-0806-003/005,
SF-1201-004/006, SF-1203-003/004).

2026-10-25 current reconciliation: the previous usage-limit interruption did not
create a development result. The actual browser continuation below did execute:
the refreshed export's 320-wide summary is visibly single-line/contained, opens by
pointer, Escape closes it with focus returned, and Return reopens it with truthful
expanded state. Home and Journal menu links navigate. The About CTA reaches About;
Contact and Not Found were opened and reviewed at mobile/Desktop sizes. Retained
images are listed in the browser matrix below. A fresh Safari window restored
stable content/frame exposure after an old responsive window repeatedly lost it
for both old and new exports; no app/layout patch was made for that browser state.

One additional real output defect remains under focused correction: short Contact
left white space below its dark authored root. The arbitrary 900px viewport minimum
was on the outer transparent wrapper only. Shared output now uses a viewport-based
minimum on the actual authored flow root and its wrapper; content, background
properties and canonical frames are unchanged. New immutable-projection test
`InsertionModelTests/testConnectedPageViewportMinimumBelongsToAuthoredRootWithoutMutation`
passes 1/1 in `dark-flow-root-viewport-minimum.xcresult`. A short native browser/
export stage is now checking actual loopback 320 Menu pointer/Return/Escape and
Contact, then normal export. No page authoring/history replay. Distinct affected
code methods total 26. Full verification/installed delivery are still pending.

### Browser evidence matrix (actual CSS viewport, height 844)

Files below are under ignored `dark-flow-browser-review/` evidence storage;
original-resolution images were inspected, not only accessibility values.

| Page/state | Width | Retained image / observation |
| --- | --- | --- |
| Home corrected summary/hero | 320 | home-reviewed-320-settled.png; single-line Menu, native gradient, stacked contained CTAs |
| Journal expanded menu | 320 | journal-reviewed-320-menu-open.png; readable four destinations, expanded state, Return/Escape focus exercised |
| Home prior unchanged content | 390/430/600/768/900/1024/1440 | home-export-WIDTH.png; 390 hero, other captures editorial/Footer regions; not all-page matrix |
| Home Desktop top | 1440 | home-reviewed-1440-top.png; readable white Header links, hero/CTA composition |
| About | 320/1440 | about-reviewed-320.png / about-reviewed-1440.png; wrapped readable paragraphs, bounded column and genuine Footer |
| Contact revision 245 export | 390/1440 | contact-root-fill-export-390-top.png / contact-root-fill-export-1440.png; honest no-backend explanation, authored dark viewport coverage |
| Contact Footer revision 245 export | 390 | contact-root-fill-export-390-footer.png; actual scroll-to-end capture, no white band |
| Not Found revision 245 loopback | 390/1440 | not-found-root-fill-loopback-390.png / not-found-root-fill-loopback-1440.png; authored recovery explanation, root fill reaches viewport bottom; prior Home-link navigation evidence reused |

No percentage efficiency claim: these are QA/creative/safety operations. The one
actual Footer Journal click, one About CTA click, and 320 Menu pointer + Escape +
Return operations are distinct observed actions. Standard Tab did not traverse
links under the current Safari keyboard preference; no system preference changed.
Menu keyboard activation/cancellation is proved; blanket browser keyboard-path
coverage is not inferred from it.

### Earlier checkpoints

Fresh native readiness is now unlocked; no setup/authentication retry was needed.
Resumed directly in Safari using the normally exported website, without replaying
page authoring/history. Actual Responsive Design Mode fields were set to
320/390/430/600/768/900/1024/1440 by native controls. Retained original-resolution
Home captures cover the hero at 320/390 and editorial/Footer flow at the other
widths; this is not an all-pages/all-widths acceptance claim. White exported
navigation is confirmed, and the real Footer Journal link reaches Journal.
Journal's 390-wide Header menu opens by pointer and exposes all four destinations.

The 320-wide Home review found the summary wrapping its icon and Menu onto two
lines in a narrower remaining navigation box; its center activation was ineffective.
The shared output now keeps that summary intrinsic and single-line, with the
existing authored alignment on a Mobile flex surface. No title/node geometry,
canonical project data or global timeout changes. A focused two-code-method plus
native-export run is active; this correction is not yet claimed visually accepted.
The owner-only macro gained an export-only stage using the same existing native
preview/export controls, so refreshed output does not replay accepted authoring
or history checks. No production mutation hook or handwritten output was added.

`dark-flow-intrinsic-menu-native-export.xcresult` now passes: two affected code
methods (automatic chrome remaining-width projection and responsive one-surface/
link-identity regression), plus the native export-only owner journey 1/1 in
71.683s. Fresh destination is the normally named Website Reviewed output, all five
HTML destinations present. The Mac locked again before actual browser inspection
of this corrected output; native inventory reports that explicitly. Owner unlock
requested, no Xcode/privacy/authentication changes. No SwiftUI publication or
invalid-geometry warning appears in this focused log. Distinct affected code
methods now total 25; full verification and installed delivery remain pending.

## Current action/friction ledger (bounded observations)

| Observed task | Actions/evidence | Classification and result |
| --- | --- | --- |
| Complete short-page viewport background | Real Layers Root → Add Solid → existing Dark Surface token → Bind on each of Contact and Not Found; Saved | Four canonical authoring transactions, not a compiler/theme patch or replay of content entry |
| Refresh output after saved correction | Native Preview and Export; live status revision 245; Desktop/Mobile original-resolution captures | QA/output delivery; no handmade HTML/CSS or canonical geometry mutation |
| Inspect final output at eight widths | Eight actual Responsive Design Mode width values; eight retained Home images | Necessary visual QA, not authoring/dimension corrections; no per-box project edits |
| Follow Journal | One actual Footer link click at Desktop | Reaches journal.html with truthful title and content |
| Operate Mobile menu | At 390, one summary click opens four destinations | Shipping pointer path works; keyboard/focus and 320 correction remain to verify |
| Repeated original authoring setup | Already retained long-page authoring runs, failed redundant Nest In and native-edit Undo attempts | Driver errors distinguished from product defects; not repeated for browser access |
| Context shifts and sizing edits | Layers/Design/Layout shifts, explicit confirmed responsive conversion, repeated default/no-change applies recorded above | Real product friction; parent accessibility, intrinsic sizing and no-op success corrections are bounded shared fixes, not fabricated efficiency percentages |
| Reopen and Safari interruptions | Duplicate history validation proved by late worker sample; later Mac lock explicitly observed | Product replay duplication fixed with strict validation preserved; physical lock is external, no privacy/service changes |

The next review, `dark-flow-review-native-output-final.xcresult`, again completed
real history, native close/reopen, exact gradient checks, Safari preview and export
Cancel/retry to a fresh destination. Its final Safari URL input timed out. Native
inventory explicitly reported the Mac locked with automatic unlock paused after
physical input; this is a concrete external visual-review boundary, not a new
SiteForge mutation failure or request for authentication/privacy changes. Owner
unlock requested. Final result is exit 65 after 265.132s; the failing owner method
timed out synthesizing Safari input and its restarted runner executed zero tests.
Both xcodebuild and its UI runner exited. This is not a passing journey. Output visual
acceptance, accumulated verification and installed delivery remain incomplete.

Original-resolution captures extracted from that completed result were inspected:
`dark-flow-review-native-output-final-attachments/`
`D858532D-88EA-4660-9A7F-5BBAFE0EAB62.png` shows actual Safari loopback preview:
navigation is now readable white on the dark Header, the diagonal native gradient
has no transparent wedges, hero text/buttons are upright and the editorial Section
follows it. This is one desktop view, not the outstanding responsive-width review.
`9EC636B3-E51D-45A1-85ED-1C34A2C3DBC0.png` shows the reopened Saved document,
stable selected Section, exactly one gradient with 45 degrees and 0/50/100 stops.
`83869BA5-32CD-4E99-A836-239F8A4B2E7C.png` shows the temporary Redo value 49
and Modified status before the driver restores 48 and saves; no false Saved claim.
`7FD53600-CA0F-4150-B4DE-9B07085629E5.png` shows native Exported revision 241
after Cancel/retry. The export sheet image is diagnostic evidence, not a full-window
layout acceptance image. The final file-output browser view remains unreviewed.

Actual Safari export review found black desktop navigation over the dark surface,
despite correct native paint. Its stable generated navigation links deliberately
use `data-siteforge-nav-link`, not the ordinary geometry-bearing node attribute;
the typography emitter matched only the latter. Shared text typography/foreground
now targets both appropriate identities, without applying absolute object
geometry to inline/menu copies. Missing-destination links retain the same stable
link attribute. The strengthened dark-navigation output/immutable-native test,
existing safe typography output and authored Button/navigation test pass 3/3
in `dark-flow-navigation-output-identity.xcresult` (two additional distinct code
methods; the dark-navigation method was already in the current slice count).
The rejected browser image is `dark-flow-browser-review/export-before-navigation-style-fix.png`.
Fresh native export and browser visual confirmation are pending, not assumed.

The prior corrected-history review completed real history, close/reopen, exact
three-stop identity/value checks, Safari loopback preview and native Export
Cancel/retry. It then failed synthesizing the file URL into Safari, which had no
window after its last preview tab closed. The owner Mac is not reported locked.
The driver now uses native New Window when needed, otherwise New Tab, and waits
for an actual window before address entry. No privacy/authentication change or
repeated owner setup request. A normally reopened Safari window independently
loads the exported file through its real address field; its contrast defect is
recorded above rather than calling that visual result accepted.

Late-phase process sampling now proves persisted-history replay remains active
on its worker during the failed native reopen readiness check. Each inverse/
forward was checked with `availability` immediately before `apply`, which calls
that same availability validation itself. Removed only that duplicate replay;
validated apply, exact forward/inverse content comparisons, strict schema,
identity/order/retention and cancellation checks all remain. Disabled-command
failures retain inverseMismatch classification. Four focused methods pass in
`dark-flow-history-replay-validated.xcresult`: full retained 128-entry dual-stack
package reopen/exact replay, canonical survival after inverse mismatch, forged
metadata redo inverse rejection, and cancellation distinct from isolation.
The first new-test build used async work in XCTest autoclosures; moved awaits
to local results before assertions. That compile failure is not a product pass.
The production-corrected native review is pending at the unchanged budget.
No history is trimmed beyond the existing policy and no owner package is rewritten
outside ordinary save commands. This is not evidence of a general font/GPU issue
or justification for a speculative AppKit/window-policy change.

Native final-review driver refinements: `dark-flow-reopen-preview-export`
stopped before mutation because it expected bare padding 48 rather than the
shipping accessible value `48; authored; Desktop base`. The next
`dark-flow-review-provenance` attempt committed 49 but exercised native field
Undo because Return intentionally leaves that responder active. The driver now
ends the native session with Escape, verifies canonical 49 remains and rejects
the Text editing toolbar route before document Undo/Redo. This reuses the
previously verified native-versus-document Undo contract; no product routing
change or assertion weakening. Read-only package inspection after that failure
still finds saved base padding 48 and Mobile 24. The corrected review is pending.
The known XCTest-internal QoS warning was observed again; it is not claimed fixed
by these driver changes. No SwiftUI publish/invalid-geometry warning was observed.

Home expansion passes 1/1 (549.457s), `dark-flow-home-package-readiness.xcresult`,
normal Save/Quit. Its original-resolution Desktop capture
`CC295B64-7F91-49AB-B4F8-65141AFA2B51.png` and Mobile
`B620AEC6-953C-4915-9051-513C54C5B042.png` under its `-attachments` directory
were reviewed. The single native gradient remains smooth, real white hero text
and CTA controls remain upright, the extra editorial Section is contained and
its Footer follows it, and Mobile actions stack vertically. No bitmap wallpaper,
ghost/white overflow or false red sizing error appears. Browser/output/reopen,
width comparison, final gate and installed delivery are still pending.

Two Home-expansion attempts stopped before any edit at package readiness
(`dark-flow-home-editorial-expansion`, `dark-flow-home-live-readiness`). Fresh
per-poll AX queries disprove a cached-proxy-only explanation: the shell appears
at the final five-second poll, and the failure attachment immediately reports
the exact expected workspace label, foreground application, zero sheets/dialogs.
Parent Window AXEnabled is false, but this alone does not prove a production
disabled state. The retained early image is partially composited and is not
accepted as settled visual evidence. This accumulated-history package now uses
the existing native-package reopen budget of eight seconds, as other real
package journeys already do; generic blank launch and text typing timeouts are
unchanged. The next changed-driver run is pending. No permission or persistence
workaround, hidden controls, package rewrite or app-policy change is introduced.

Contact and Not Found native authoring now pass together (1/1, 1176.261s),
`dark-flow-contact-not-found.xcresult`, normally saved and quit. Four original-size
captures under `dark-flow-contact-not-found-attachments` were inspected:
Contact Desktop `7923BD9F-6E2C-4B75-ADDB-2F67D8E0FB89.png`, Mobile
`154D7862-0DB6-42AC-B35F-9471C03E552D.png`; Not Found Desktop
`4157BA67-4F98-4B66-9B7B-AA6FEE8E78D8.png`, Mobile
`D5B82096-28B2-4390-B9CA-2C9CAAB79932.png`. Text is upright, readable and
contained, dark navigation remains visible, and no ghost/white overflow appears.
Not Found's Inspector does expose a false red unchanged-sizing failure. The
typed registry correctly rejects a mutation-neutral no-op; the scene boundary
now treats that validated unchanged draft as successful without history.
`testWorkspaceSizingUnchangedDraftIsSuccessfulAndHistoryNeutral` passes 1/1,
including exact document/history/selection equality and invalid/stale rejection.
`testLayersParentAccessibilityTracksNativeNestingInsertionAndHistory` passes
1/1 (40.016s), `dark-flow-parent-live-adoption.xcresult`: public Nest In,
Undo/Redo, retained identity, truthful parent values and direct child insertion.
Two earlier new-test attempts queried counts before asynchronous adoption; the
test now waits boundedly for the exact live renderer and Layers result rather
than assuming menu dismissal means adoption has completed. No product timing,
transaction or no-op validation was weakened. Home expansion is the next run;
output/reopen/final acceptance remain pending.

The supporting-page continuation `dark-flow-supporting-pages.xcresult` failed
on About (0/1, 309.527s): the original heading's Nest In succeeded, then a new
Text inserted into the selected Stack was already its child. The driver falsely
inferred hierarchy from flat row X coordinates and requested a second, correctly
disabled no-op move. This is not a lifecycle or permission defect. Newly inserted
children now retain their established parent without a redundant move. Layers
also expose truthful parent names in their standard accessibility value
(SF-0408-003/006), rather than making assistive clients infer indentation.
The changed-code build passes. About's native continuation then passes 1/1
(451.458s), `dark-flow-about-parent-corrected.xcresult`, with normal Save/Quit.
Original-resolution Desktop `AD6F5166-7F45-470F-A663-68A56A4634CA.png` and Mobile
`03D07586-965A-404E-83DC-1144072B6B74.png` under its `-attachments` directory were
reviewed: readable upright heading/body, dark authored surfaces, contained Hug
content and Footer below, no white overflow or ghost. The bounded left-aligned
reading column is preserved, and the saved Desktop status is truthful. Contact
and Not Found are the next native continuation; Home expansion and browser/
output/reopen/final acceptance are still pending.

Latest actual Bounds screenshot supersedes the initial remote-service hypothesis:
`.codex-loop/dark-flow-journal-native-bounds-attachments/11706232-7B12-4BC3-84BC-D8BDEF0E9A5C.png`
was inspected at original resolution. There is no visible blocking dialog. Text's
Bounds controls explicitly say Unavailable; the driver incorrectly targeted an
unsupported Max Width field. Do not change production enabled-state policy or
privacy settings to make that action succeed. The continuation uses a genuine
Stack reading column with supported width bounds and ordinary Layers Nest In
commands, preserving the original text NodeIDs.

That screenshot also catches a real keyboard-routing defect: default placeholder
text survived before the article. SwiftUI's command body could freeze native
Select All as disabled before the deferred NSTextView focus transfer. It now
recognizes the live window-owned scene's active inline session as native editing
context; actions still route through AppKit's responder chain. Fresh-process
`testInlineTextNativeSelectAllReplacesExactlyAndCancelPreservesIdentity` passes
1/1 (36.669s) in `dark-flow-native-select-all-live.xcresult`: real Edit menu,
Command-A replacement, exact draft, commit, Escape, stable identity and document
Undo/Redo. Its first test attempt queried the obsolete label Text rather than
the shipping label Text object and stopped before editing; that locator was
corrected without changing any assertion about content or focus.

The authoring driver now verifies the exact native draft before committing,
saves completed text normally, and never treats the failed Bounds attempt as a
finished page. Other pages/browser/output/full acceptance remain pending.

The genuine Stack workflow exposed two additional production boundaries under
SF-0408-002/003/005/006. The drag registry still limited destinations to Frame,
contrary to the canonical `acceptsAuthoredChildren` rule already used by insertion
and command validation. It now reuses that rule. Focused canonical
insertion→nesting→exact inverse/redo/serialization and existing invalid/stale/
hidden/cancel cases pass 2/2 (`dark-flow-structural-nesting-canonical.xcresult`).
The first new fixture was invalid because it changed a node kind without its
required defaults; the corrected test uses the production insertion registry.

The next native attempt commits Nest In but clears the moved selection because
its old parent scope is no longer valid (`dark-flow-journal-nesting-live.xcresult`,
0/1, 117.286s). The synchronous command boundary now rebases a sole surviving
selection to its actual canonical parent and uses the existing guarded pending
selection adoption; history does likewise. Removed/hidden/locked/page changes
still repair, and the selection cannot follow a move outside active isolation.
Focused nesting/history/selection and existing neutral-failure coverage pass 3/3
in `dark-flow-nesting-selection-scope.xcresult`, including new
`testExplicitNestingAndHistoryKeepSelectedNodeInItsCanonicalParent`.
Native continuation remains pending; do not infer a completed page from code tests.

`dark-flow-journal-selection-retained.xcresult` now passes 1/1 (415.116s), with
normal Save/Quit and exact native text replacement. The original text NodeIDs
are retained through real Nest In into a bounded Stack. Desktop capture reviewed:
`.codex-loop/dark-flow-journal-selection-retained-attachments/49CE6CB4-A424-47A2-8D38-AEA688732721.png`.
It has readable upright editorial text, coherent dark surfaces and real navigation.
Mobile capture `70F77B8C-A32F-49B5-BBA4-40D2FA4D2D79.png` is rejected despite the
green test: old authored Mobile height 460 still wins over base Hug; text overflows
through Footer. This is not permission to move canonical coordinates silently.
The next public-control step explicitly confirms Make Content Responsive on the
independent Section subtree, removes its legacy dimension overrides and checks
effective Hug at Desktop/Tablet/Mobile. Preserve original projects unchanged;
do not call Mobile or the full website accepted before its new captures pass.

The confirmed conversion continuation passes 1/1 (105.475s),
`dark-flow-journal-confirmed-flow.xcresult`. Its Desktop, Tablet and Mobile
captures were inspected at full original resolution (not only resized previews):
under `.codex-loop/dark-flow-journal-confirmed-flow-attachments/`, respectively
`822A018F-1359-4C22-A757-21BEBA83048A.png`,
`6892A5DF-FD6A-46C8-A571-9573EF2D12A1.png`,
`A2385E22-8C3F-486D-9766-28B756FB5D7D.png`.
All article text stays inside its Hug Section, Footer follows the content, the
mobile Menu is white/readable, dark page/artboard and pasteboard remain distinct,
and the native shell controls remain upright/unwrapped. No ghost, white overflow
band or bitmap background is present. Original text NodeIDs remain preserved.
The left-aligned bounded editorial column is authored structure, not an editor
viewport offset. Other pages, Home expansion and browser/output acceptance remain.

The native token-row pointer regression passed 1/1 (109.934s). The isolated
Saved/Quit/project-open route passed 1/1 (36.941s), without changing original
projects or recovery stores. Home theme/foreground/flow then passed 1/1
(549.781s): actual Header/Footer, title, navigation, body and buttons use authored
foreground/token controls; Mobile CTA direction and Section padding are actual
breakpoint edits, not package mutation or fabricated responsive output.

Original-resolution Mobile capture inspected:
`.codex-loop/dark-flow-home-foreground-attachments/2BD2F192-92EB-4406-B525-EE7C293160B5.png`.
The gradient covers its corners; white hero/body remain upright and mobile actions
fit. Inspection exposed a black collapsed Menu and implicit Text placeholder
surface/stroke. These are general production rendering defects, not a creative
reason to alter canonical text geometry.

SF-0507-003/005: plain Text now paints glyphs without an implicit authored-looking
background or fallback stroke. `dark-flow-text-surface.xcresult` passes 3/3:
`testCommittedPlainTextHasTransparentNonGlyphPixelsAtBothBackingScales`,
`testControlGlyphPixelsRemainVisibleWithinAuthoredBounds`, and
`testDiagonalGradientEndpointCapsCoverAuthoredCornersWithoutEscapingBounds`.
The helper allocates genuine 1x/2x bitmaps and includes the real authored text
layer; it checks nonempty glyphs and transparent nonglyph/outside pixels.

SF-0501-003 / SF-0806-003 / SF-1201-003: collapsed navigation now shares
the common authored link foreground and opaque owner surface between immutable
canvas preparation and compiled website CSS. Mixed links do not borrow a primary
value; readable contrast comes from the owner when there is no common value.
No canonical node/property is mutated. `dark-flow-menu-contrast.xcresult` passes
2/2: `testDarkNavigationSharesAuthoredForegroundAndOpaqueSurfaceWithoutMutation`
and `testAutomaticChromeNavigationSharesTrailingDefaultAndRemainingWidthWithStaticOutput`.
These are focused results, not the final website/browser/full-gate acceptance.

## Current authored result and focused repairs

Journal continuation reached real inline article entry but failed event synthesis
after 239 seconds (`dark-flow-journal.xcresult`, 0/1, 827.866s overall). A sampled
main-thread trace shows repeated SwiftUI Geometry Inspector field rendering calling
`geometryInspectorAvailability` → registry preparation → full canonical command
availability/document validation while the inline draft is noncanonical. This is
not a new authentication failure or a completed Journal pass. The isolated app
exited with the runner; earlier saved authoring remains preserved.

The bounded correction reuses per-field availability only for identical document
revision, draft/viewport scope, complete renderer identity and complete transform
validation context. Any ownership, availability or lifecycle change invalidates
it. Commits still perform full central-registry validation; no mutation path is
cached or bypassed. Focused invalidation and text-adoption coverage passes 2/2
in `dark-flow-inspector-availability.xcresult`:
`TransformModelTests/testGeometryAvailabilityReusesOnlyIdenticalCommandContext`
and `testNestedLayersSelectionSurvivesTextGeometryAndRendererAdoptionWithoutIsolation`.
The first partial article-entry retry also timed out (`dark-flow-journal-content.xcresult`);
its fresh main-thread sample moved the dominant cost to Insert and Transform
menu availability, which likewise prepared hypothetical full transactions on
each draft redraw. The same bounded memoization now covers those queries,
including insertion parent/index, selected asset, viewport, template and complete
validation context. Entries are capped at 32 per current context; commits remain
uncached. Expanded focused storage/lock/undo/selection coverage passes 4/4 in
`dark-flow-command-availability.xcresult` (the two earlier methods plus
`testWorkspaceAvailabilityMemoKeepsOperationsDistinctAndStorageBounded` and
`testWorkspaceInsertionAndTransformAvailabilityInvalidateAfterLockAndUndo`).
Duplicate unchanged native text/selection notifications also now return without
republishing the scene-local draft; changed text, selection and IME composition
retain their ordinary publication path. Its focused regression passes 1/1 in
`dark-flow-inline-neutral.xcresult`:
`testDuplicateInlineDraftNotificationsDoNotRepublishOrMutateCanonicalState`.

Read-only package inspection confirms the failed Journal runs never completed
their normal Save: Journal still has its original 19 nodes/text and unthemed
Header. Do not claim those in-memory edits persisted. Next resume uses the theme
stage and a normal intermediate Save before long text entry. The public-control helper also stops
polling immediately once a control is safely visible, preserving its original
bounded reveal and final focus/visibility assertions.

The next changed-code run saved Journal's shared palette normally before article
entry, then still failed event synthesis (0/1; `dark-flow-journal-responsive.xcresult`).
A third fresh sample identifies Layers row context-action preparation as the
remaining dominant full-validation path. It now uses the same context-bounded
memoization, capped at 256 row actions to retain the visible working set; ordinary
Inspector/command caches remain capped at 32. Full drag/drop execution validation
is unchanged. New lock/undo and existing hierarchy/stale/hidden/cancellation
focused coverage passes 4/4 in `dark-flow-layers-availability.xcresult`:
`testLayersMoveAvailabilityInvalidatesAfterLockAndUndo`,
`testWorkspaceAvailabilityMemoKeepsOperationsDistinctAndStorageBounded`,
`DragDropModelTests/testCanonicalHierarchyOrderAdoptsThroughLayersRendererAndReverseHitTesting`,
`testCyclesDepthStaleLockedHiddenUnavailableAndCancellationAreNeutral`.
Read-only inspection confirms
Journal's Header/Footer token bindings persisted, but not the unfinished article.

With Layers availability memoized, the full article typing/commit step completes.
`dark-flow-journal-layers-cached.xcresult` then fails separately at the Max Width
readiness query (0/1, 304.251s), with an unresolved remote AX element. A bounded
system-log inspection identifies that remote PID as Apple's
`ThemeWidgetControlViewService`, not the SiteForge process. Its connections
invalidate during native sizing-menu replacement. The failure hierarchy has a
zero-size/infinite-position Dialog tree; the screen-recording attachment itself
contains only “Finished test run with pending attachment,” so no visual result
is claimed from it. No permission/service configuration is changed and no product
test is weakened. The next concrete diagnostic pass waits for the actual committed
sizing value, captures the native Bounds state before readiness, and normally
saves each completed text edit so a later infrastructure failure cannot lose it.

The owner-ready authentication retry passed the native audit (1/1, 16.102s).
Xcode readiness and that authentication request are no longer current blockers.
Subsequent public-control gradient authoring passes (1/1, 97.287s): the saved
Home Section has ONE enabled native gradient at 45 degrees, exactly three stable
stops in 0/50/100 order, with exact normalized #160D2B/#6A36C8/#C52E53 values.
The scenic image fill was removed from this independent Section only; no asset
was deleted globally and no generated wallpaper was imported. Package inspection
was read-only, not a construction/mutation route. Retained result is ignored
`dark-flow-colors.xcresult`; original-resolution final window capture:
`dark-flow-colors-attachments/5B773443-9E6D-4E47-9A64-426BB2354136.png`
under `.codex-loop`. It was inspected: existing pale overlay remains to be removed,
and the native gradient visibly exposes transparent diagonal corner wedges.

Demonstrated production repairs (not yet installed in the ordinary app):
- SF-0508-003: Core Graphics omitted endpoint-extension options, unlike the
  already-clamped compositor/CSS. Extend first/last colors while retaining the
  authored-shape clip. New four-diagonal, 1x/2x production-tile corner/outside
  regression passes; existing exact layer/order/opacity pixel test also passes.
- SF-0508-002/005: valid unchanged angle/stop edits reached the central registry's
  no-change rejection, then surfaced as a red validation error. The shell now
  treats that validated neutral result as successful, clears failure, and creates
  no history/revision mutation. New state/history/invalid-input regression passes.
- SF-0701-006 / SF-0508-002/006: a plain Color Token row omitted a rectangular
  content shape. Its center spacer was not a pointer hit region: the first theme
  attempt retained the previous token, and the next attempt opened no editor.
  Full-row hit shape is corrected; a fresh native pointer regression is pending.

Focused code result: 3/3, zero failures, retained
`dark-flow-gradient-regression.xcresult` under ignored evidence storage:
`CanvasTextRenderingTests/testDiagonalGradientEndpointCapsCoverAuthoredCornersWithoutEscapingBounds`,
`CanvasTextRenderingTests/testAuthoredFillLayerStackAndGradientUseExactProductionTilePixels`,
`TransformModelTests/testWorkspaceFillLayerUnchangedAngleIsSuccessfulAndHistoryNeutral`.
Repository checks passed before the three latest production repairs; no claim
that this substitutes for their focused/native review or the required final gate.

The initial theme macro also incorrectly tried to add leaves across active-parent
selection scopes. Its preserved-selection assertion failed before the color edit;
the continuation uses verified sibling groups instead. This is recorded as an
authoring/automation planning issue, not permission to weaken selection checks
or redesign selection ownership. All five actual pages remain: Home, Not Found,
Journal, About, Contact. Other-page theming, responsive completion, browser review,
native export/reopen and final verification remain pending.

## Historical route diagnosis before owner-ready retry — 2026-10-24

Owner completed Xcode setup. Independent `xcodebuild -checkFirstLaunchStatus`
exits 0; the earlier Install Required request is historical, not current.
SiteForge native inspection still fails with `native pipe closed before response`.
The existing ordinary app was not relaunched or terminated.

Alternative supported route: added opt-in public-control XCTest
`testOwnerDarkFlowVisibleGradientControls`, attaching to the already-running
ordinary app only when explicitly enabled. It checks the exact independent
window before selecting Layers/Section/Design; it never launches/terminates that
app, writes package data or uses an app mutation hook. Normal unattended runs
skip this owner-session audit. Build-for-testing succeeds.

One fresh exact-selector execution failed initialization before its method:
exit 65, zero authoring actions, no passing UI test. Retained ignored bundle/log:
`.codex-loop/dark-flow-audit.xcresult` and `dark-flow-audit.log`.
Fresh system diagnostics identify the current separate blocker: testmanagerd
requests automation mode; writer requires authentication; LocalAuthentication
requests **Enable UI Automation**; the runner times out 60 seconds later.
No historical authentication failure is being reused as evidence. Xcode itself
now presents its ordinary Welcome window. No collector or unchanged retry ran;
the exact runner exited and no test process remained. `git diff --check` passes.
The source-backed full gate remains required after actual authoring acceptance.

## Owner design refinement

Use one ordinary editable linear gradient with exactly three stops: deep plum
`#160D2B` at 0%, purple `#6A36C8` at 50%, ruby `#C52E53` at 100%.
Smooth diagonal; dark region behind white heading. Do not use bitmap wallpapers,
additional glow layers or application-wide appearance changes. Supplied generated
artwork is not imported or used as this background. This is a creative decision,
not a demonstrated product defect.

Bounded requirements: SF-0508-002/003/005/006 for normal editable fill authoring;
the broader website requirements are listed in queue item 006 and remain pending.

## Initial native actions (historical before gradient continuation)

| Goal | Public route / actions | Result / classification |
| --- | --- | --- |
| Preserve originals and start independent copy | Welcome Aurora Editorial sample (1 click) | New Untitled editable five-page copy; no original opened |
| Save independent project | File → Save As…; name field; Save (4 interactions) | Window title Aurora — Dark Flow; live status Saved; package exists |
| Select background owner | Layers tab; Section row (2 clicks) | Native inspection connection closed on Section selection; selection outcome unknown |

No gradient edit, image import, Undo, browser preview/export or responsive review
has occurred yet. Counts describe these exact observed interactions only, not
matched before/after efficiency gains. SiteForge remained running after the
connection failure. Rebinding failed twice; resetting only the inspection runtime
and rebinding also failed. Finder inspection still worked, so this is not evidence
of a general native-tool outage or a proven gradient/model defect. No force quit,
application replacement, privacy/service change or project-data workaround used.

The independent package is in the owner's normal SiteForge Projects folder as
`Aurora — Dark Flow.siteforge`. Machine-specific paths are kept out of this note.
Original Editorial/Workflow Study and recovery were not opened or modified.

Next: restore a usable native SiteForge inspection connection without discarding
work, select the existing Section, use regular Design gradient controls and save.
Do not recreate the project or synthesize package data. Xcode first-launch
readiness is resolved; the fresh automation-mode authentication boundary above
is separate. No gradient or completed dark website is claimed.
