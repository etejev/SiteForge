# Full closeout failure inventory — 2026-11-02

Status: IN PROGRESS. Requirements remain Partial: bounded SF-0501-003/004,
SF-0507-003/004, SF-0606-002/003/004/006/007/008, SF-0806-006,
SF-0901-006, SF-1203-003/006 and SF-1211-004. This is a diagnostic inventory,
not complete milestone acceptance.

## OD-031 sharded execution — run 42847939727

[Run 42847939727](https://github.com/etejev/SiteForge/actions/runs/42847939727)
on `7a74d58` accepted the workflow and ran on macOS 26.7.2 (25G332),
arm64, Xcode 26.6 (17F113). Core completed discovery and passed all 888
non-UI tests. Shards 4 and 8 each had 21 selectors and no test steps:
GitHub's check annotations say the job was not acquired by a hosted runner
after multiple attempts and identify macOS arm64 capacity constraints.
These 42 unrun selectors are not UI assertion failures.

| Job | Passed | Failed | Policy skip | Not run | First observed failures |
| --- | ---: | ---: | ---: | ---: | --- |
| Core | 888 | 0 | 0 | 0 | Discovery and full non-UI receipt passed. |
| UI 1 | 20 | 1 | 0 | 0 | Generated website paint journey queried the replaced Footer title field before adoption. |
| UI 2 | 18 | 3 | 1 | 0 | Compact Inspector Accessibility destination, native image import readiness, responsive Grid render adoption. |
| UI 3 | 19 | 2 | 1 | 0 | Aurora browser remained unloaded after foreground; generated menu comparison queried a replaced Footer title field. |
| UI 4 | 0 | 0 | 0 | 21 | Runner was never assigned. |
| UI 5 | 17 | 4 | 0 | 0 | Nested Grid adoption, keyboard overflow reachability, Footer title replacement, and Page Background pixel mismatch. |
| UI 6 | 19 | 2 | 0 | 0 | Installed font journey did not open the inline editor via the unscoped menu query; narrow Footer companion had the same title lookup failure as UI 3. |
| UI 7 | 13 | 8 | 0 | 0 | See first-failure boundaries below. |
| UI 8 | 0 | 0 | 0 | 21 | Runner was never assigned. |

The terminal UI totals are 106 passed, 20 failed, two observed owner-only
skips, and 42 not run. The aggregate Verify job 129992842804 rejected
missing receipts `ui-4` and `ui-8`, exit 1. Replaying the seven unique
downloaded receipts through the revised aggregator printed the same
per-shard counts and still exited 1. The dark-flow project transfer and
visible-gradient skips are documented by the real test transcripts.

UI 2/5 evidence: Accessibility was available through
the compact overflow rather than the direct button. The keyboard traversal
probe now aligns the real overflow before opening it, then re-aligns Pages
for the initial click. Image Open became hittable only by the time failure
diagnostics ran; the journey now uses the exact native folder/file readiness
sequence. Two Grid count failures still lack a render/selection diagnosis.
The Page Background film shows an authored fill on the artboard, but the
fixed sample's red value was 0.1753 versus expected 0.1333 ±0.03. Neither
the color check nor the sample has been relaxed. The custom responsive
width journey passed on UI 5 without a change.

UI 7 first failures:

- Aurora responsive conversion: Mobile preset did not report the expected
  value after the native menu action.
- Heading template and responsive geometry: semantic picker and breakpoint
  reset button were not hittable through their immediate checks.
- Normal destination rows and stable Inspector strips: the 1024-point
  runner clips the leading side of the 1100-point window; native resize to
  1280 did not move the screen-edge grip. No minimum or wider-row acceptance
  was relaxed.
- Preview repair: AX scroll height was 2435 points, so its generated center
  hit was outside the actual display. The shared reveal helper now sends
  the real scroll within the pane/display intersection, then still requires
  strict containment. The Heading picker and geometry reset use that path.
- Related-page reopen: native Open matched an offscreen completion row.
  Resolve the exact parent and wait for Go to Folder dismissal before
  selecting a real hittable file row and confirming Open.
- Basic website preview: Safari was foreground but the loopback WebArea
  was not loaded. The same symptom recurred in Aurora; the reason for the
  load failure has not been established.

The Footer hierarchy showed the selected Footer and its real title field
after the failing early query. The companion now waits for that selected
row and live field. The font journey now uses the scoped Selection menu
helper already exercised in the focused inline-text acceptance. Exact
history, text, geometry, native panel and Safari assertions remain.
Relevant evidence: SF-0406-006, SF-0507-006, SF-0602-006, SF-0701-006,
SF-1203-006, SF-1204-006, SF-1605-008.

The hosted Xcode 26 tree omitted an approved skip's reason, while its
own transcript retained the exact module-qualified XCTest diagnostic.
Accounting now uses that exact case diagnostic only when the tree already
records a skip and lacks a reason; a missing, duplicate or unapproved
reason still fails. Five synthetic tests and a real shard 3 transcript
replay passed. Local Xcode 27.2 unsigned build-for-testing passed; no
local UI suite was launched in that follow-up.

### Batched candidate and exact failure map

The owner approved UI `max-parallel: 2` without changing eight shard
assignments, coverage, job time limits, local verification, or retry policy.

| Shared boundary | Exact failing methods (SiteForgeLaunchTests) | Candidate disposition |
| --- | --- | --- |
| Footer Content host replacement | `testGeneratedWebsiteMenuEscapeStateAndPaintJourney`, `testGeneratedWebsiteMenuEscapePresentationContextComparison`, `testMeasuredSafariNarrowChromeBoundaryCompanion`, `testNarrowChromeFooterAndMeasuredSafariBoundaryCompanion` | Await selected Footer row and the real live title field; no browser assertions removed. |
| Compact scroll/pane geometry and overflow | `testInspectorProvidesTruthfulUnavailableContentAndInteractionsDestinations`, `testKeyboardFocusTraversesWorkspaceForwardAndReverse`, `testHeadingTemplateElementsMenuTypographyAndHistoryJourney`, `testResponsiveBreakpointGeometryAuthoringUndoResetAndAccessibilityJourney`, `testPreviewAndCheckWebsiteFindingRepairUsesExistingEditorJourney` | Use the real reachable pane or overflow; scroll inside the visible Inspector intersection, not the AX content-height center. |
| Native panel readiness | `testPracticalImageReuseScopedReplacementAndTypographyJourney`, `testRelatedPageReuseNavigationActionAuditAndNativeReopenJourney` | Resolve the fixture parent, await dismissal, select the exact real file, and require enabled native Open/Import. |
| Inline menu tracking | `testInstalledFontPairChooserCancelAtomicUndoAndHeadingSemanticsJourney` | Scope to the live Selection menu after confirming the exact text selection. |
| Compact scrolled Insert menu | `testResponsiveContainerLayoutAndBreakpointVisibilityJourney`, `testConnectedNestedSectionContainerGeometryAndBreakpointJourney` | The films show the pointer over Header or the bottom scroll arrow, not Grid. Use the existing Command–Option–3 Grid action; preserve exact counts and subsequent layout/identity assertions. |
| Foreground Safari with unloaded WebArea | `testAuroraRelatedPageReuseNativeCopyAndSafariJourney`, `testWebsitePreviewBuildsAuthoredOutputAndOpensActualSafari` | Unresolved. Core loopback HTTP test passes. A failure-only three-second probe now records exact route HTTP status/byte count without response contents or URL, separately from the unchanged real Safari assertion. |
| Normal width evidence on 1024-point runner | `testNormalFiveDestinationRowsAndInspectorFieldStabilityJourney`, `testStableInspectorStripsFieldsDraftsAndComponentRecoveryAtNormalAndCompactWidthsJourney` | Unresolved. Actual normal-window width was 1100, left edge −76, and the 1280-point native drag never moved. Need real wider-screen evidence or a supported on-screen resize path, not reduced coverage. |
| Mobile preset publication | `testAuroraResponsiveContentConversionPreservesSelectionAndReflowsAcrossPresetsJourney` | Unresolved. Need live preset value and exact action target after native tracking; no product change inferred. |
| Exact page fill sample | `testPageBackgroundEntryUsesSharedFillEditorAndTransparentHistory` | Unresolved. Retain the exact lossless failing crop; film shows an authored fill but cannot resolve sampling coordinates/profile/adoption. Same channels and tolerances. |

The distinct custom-width journey passed and was not changed. The revised
accounting displays missing shard counts alongside available receipts and
rejects duplicate receipts without choosing one by download order.

## Hosted execution and capacity — run 42746959758

[Run 42746959758](https://github.com/etejev/SiteForge/actions/runs/42746959758),
job 129601250899 at `56650d2`, compiled app and UI targets on Xcode 26.6.
All 888 non-UI passed. The job concluded `cancelled` after 90m21s,
consistent with the configured 90-minute cap; the log reports only that
the operation was canceled. No diagnostics artifact was uploaded. Log
inventory: 46 UI passes, 14 UI failures, no skips reached, one test
started without outcome (`testFormFieldTemplateMenuParityInspectorAndHistoryJourney`),
and 109 never started, from `testFormInputTemplateInsertsOnlyIntoSelectedFormJourney`
through `testWorldGridArtboardHierarchyVisualJourney` in the complete inventory.

| Exact method | First causal observation |
| --- | --- |
| `testApplicationLaunchesCompleteNativeShellAtPracticalMinimumSize` | Direct Interactions button absent at the compact pane width; test now exercises the supported direct or native overflow route and verifies the resulting selection. |
| `testAuroraRelatedPageReuseNativeCopyAndSafariJourney` | Safari passed the foreground gate; AX showed `IsPageLoaded=false` with a loopback address and no expected link. No evidence that link semantics or app activation caused this. The earlier ordinary replay passed; unresolved on hosted. |
| `testAutomaticNarrowChromeNativeAndMeasuredSafariMenuJourney` | Header field succeeded; Footer title query had no matching AX snapshot after insertion. Require the actual selected Footer row and live field before editing. |
| `testComponentActionNativeInspectorDraftResetHistoryAndReopenJourney` | `component.action.target.*.type` frame ended at X=1029 on a 1024-point display. |
| `testComponentDirectPropertySourceRetainsDefinitionDraftAndExactInstanceJourney` | Definition name field ended at X=1029. |
| `testComponentPropertyDiscoveryNativeSearchClearTraversalAndContextJourney` | Definition name field ended at X=1029. |
| `testComponentPropertyOrganizationNativeKeyboardCancelHistoryAndReopenJourney` | Definition name field ended at X=1029. |
| `testComponentRetainedOverrideRecoveryConfirmationUndoAndReopenJourney` | Definition name field ended at X=1029. |
| `testComponentSlotFallbackNativeAuthoringCancelHistoryAndReopenJourney` | Slot remove control ended at X=1030. |
| `testComponentTextPropertiesTwoInstancesResetHistoryAndReopenJourney` | Definition name field ended at X=1029. |
| `testComponentVisibilityDefinitionInstanceResetAndReopenJourney` | Visibility definition name field ended at X=1029. |
| `testConnectedFluidPreflightSafariExportCancelAndReopenJourney` | The global Cancel lookup matched a Touch Bar element. Scope the click to the existing native `save-panel` `CancelButton`; keep preview and reopen checks. |
| `testCustomResponsiveViewportWidthEntryComparisonAndCancellationJourney` | Comparison card showed 1440 and Escape dismissed it; the committed width field check then failed. Log does not include actual field value and records an XCTest internal application-specifier assertion. Earlier ordinary run passed; unresolved on hosted. |
| `testDarkEditorialEditorAndSharedInspectorVisualJourney` | Content alignment read End, but title was tested for hittability without revealing it in the compact scroll pane. Check the real field after standard reveal and retain the strict geometry check. |

The eight component failures shared the same ordering defect: the Inspector
helper demanded containment before the component helper could translate
the real window. Vertical scrolling cannot change the offending X extent.
The shared Inspector path now performs bounded native title-bar movement
before its unchanged strict display/scroll intersection assertion. No
product minimum, workflow, or test tolerance changed (SF-0201-006,
SF-0701-006, SF-0902-006, SF-1204-006). The exact hosted geometry remains
to be confirmed on the narrower display. See OD-031 for the measured
capacity decision; no next push against the unchanged serial gate.

Local focused attempt `focused-48e1d177-9b64-47c2-b06c-c1c054eb0c57.xcresult`
found a duplicate Footer binding at compile time. After the correction,
`focused-01ddadc1-d3b8-4046-a379-dd674405f7e7.xcresult` compiled the UI
target on Xcode 27.2 but exited 65 before executing any of the five selected
methods (minimum shell, narrow chrome, component discovery, fluid export,
and dark editorial). XCTest reported “Timed out while enabling automation
mode.” No focused runtime pass or new 1024-point reproduction is claimed.
Do not repeat unchanged without normal macOS automation authorization.

### OD-031 approved hosted gate

The owner approved eight isolated macOS UI jobs and one core job with the
existing 90-minute cap. The retained 170-selector XCTest inventory supplies
timings; deterministic longest-first assignment yields 21–22 methods and
1,534–1,540 historical seconds per shard. The hosted core job enumerates
the complete built scheme, then runs the non-UI target. Each UI runner
builds once, runs only its exact selectors serially and reserves time for
receipt/diagnostic upload. The aggregate checks the exact candidate SHA,
all nine job receipts, full selector union, native skip reasons, and job
outcomes. A canceled runner may prevent artifact recovery; that remains a
failure, not a skip or a pass. Local full verification is unchanged.

Local validation: four synthetic accounting tests passed; all 1,058
records from the completed ordinary XCTest bundle parsed and all 170 UI
IDs matched the timing manifest. Workflow shape, shell syntax, harness
shim (four cases), traceability and diff checks passed. A compile-only
UI enumeration attempt was unable to enable local UI automation; no
local UI tests or full suite were rerun for this workflow change.

## Hosted UI test compile follow-up

[Run 42745329588](https://github.com/etejev/SiteForge/actions/runs/42745329588)
on `8e214a7` cleared the two original app compile errors on Xcode 26.6
but failed before tests ran. `SiteForgeLaunchTests.swift` reported
“sending 'self' risks causing data races” at lines 4306, 7056, and 7069
in the native file chooser and the related-page pointer/focus helpers.
The two enclosing XCTest methods now explicitly share the main actor
with the local helpers; the chooser helper is explicitly isolated too.
No change to user interaction, click accounting, assertions, production
code, or test selection (SF-0801-002, SF-0802-006, SF-0308-006, SF-0806-006).
Clean unsigned `build-for-testing` passed with Xcode 27.2 (27B52),
including the UI target for arm64 and x86_64. No tests were launched;
Xcode 26.6 still reported the same three calls in
[run 42746063990](https://github.com/etejev/SiteForge/actions/runs/42746063990)
on `e715e1e` (lines 4307, 7058, 7071). No tests ran. The follow-up moves
the native chooser, pointer/menu actions, and focus/typing into XCTest
instance methods. The only remaining nested helper in those two methods
records the same action strings into the same phase counters without
capturing the XCTest case. Waits, diagnostics, assertions and click counts
are preserved. The actual UI target compiled again with the unsigned
Xcode 27.2 `build-for-testing` command, exit 0. No local tests were run;
the Xcode 26.6 result must come from the next push-triggered run.

## Hosted compile follow-up

[SiteForge CI run 42743446225](https://github.com/etejev/SiteForge/actions/runs/42743446225)
on checkpoint `955f910` failed building with Xcode 26.6 (17F113), exit 65;
tests never started. `WorkspaceShellView.swift` reported a type-check
timeout at the inline component-property row move handler (1795:40)
and an extra argument at the eleventh outer command declaration (11196:9).
The row and typed move handler now compile separately from the discovery
view. The supplementary menus and View toolbar command group now compose
as one outer child, in their original order and native slots. Focus,
accessibility IDs, command targets, shortcuts, and draft/source identity
checks are unchanged (SF-0701-006, SF-0902-006, SF-0401-006).

An unsigned clean `xcodebuild build` in fresh DerivedData passed with
Xcode 27.2 (27B52), the only installed version located locally. Xcode 26.6
confirmation requires a hosted build of the reviewed correction. The
earlier exact 4/4 UI replay is separate evidence; no UI or full suite was
rerun for this compile-only follow-up.

## November 9 ordinary full gate and targeted replay

`full-51ae6ac8-6773-45a1-bb4c-c4155c54bbb3.xcresult` completed exit 65
on ordinary app identity and source/test/tool diff SHA-256
`1527320483e7ea4238936cd91ad33ce9ec5fb4072b698c62e82e1fde66467ef0`.
Repository checks and build passed. Of 1,058 tests, 1,051 passed (888
non-UI and 163 UI), four UI failed, and three owner-session opt-in UI
methods skipped (`testOwnerDarkFlowNativeThemeAndFlow`,
`testOwnerDarkFlowTransferSavedProjectToCurrentBuild`,
`testOwnerDarkFlowVisibleGradientControls`). Zero methods were unrun.

| Exact UI method | Observed failure and narrow disposition |
| --- | --- |
| `testButtonLinkContentTargetsUndoRedoAndReopenJourney` | XCTest timed out synthesizing native URL-field typing before validation. The retained video shows the prior committed URL, and the spindump shows SiteForge's main thread idle in its event loop. No product deadlock or validation regression was established; replay unchanged (SF-0806-002/005). |
| `testComponentActionNativeInspectorDraftResetHistoryAndReopenJourney` | After save/reopen, the Layers control was enabled and hittable but the app reported background state. Video shows System Settings in front of the reopened project, which displays Saved. Preserve foreground and persistence assertions; replay unchanged on an available desktop (SF-0902-005/006, SF-0905-005). |
| `testInlineTextNativeSelectAllReplacesExactlyAndCancelPreservesIdentity` | XCTest reactivated SiteForge while resolving the Selection menu action; the editor never opened and the selected Text remained on screen. Scope the lookup to the actual opened menu after foreground and selected identity are confirmed. Keep native Select All, exact text, focus, cancellation, and history checks (SF-0406-002/006). |
| `testStableInspectorStripsFieldsDraftsAndComponentRecoveryAtNormalAndCompactWidthsJourney` | Screenshot and geometry show native resize stopped at 1104 instead of 1100 points, before compact acceptance. Drive the real window edge beyond the minimum to exercise AppKit's clamp, preserving the existing ±2-point assertion and all draft/focus/Inspector checks (SF-0501-004, SF-0507-004). |

The four exact selectors ran together using `./sf test focused`, ordinary
identity, and disposable fixtures. `focused-04cbf0e7-7f8f-45e4-bbe6-67a166e4b739.xcresult`
exited 0: 4/4 passed, zero failed or skipped, in table order 112.481s,
159.029s, 35.340s, and 411.810s. Tested source/test/tool diff SHA-256:
`42c38a97c9b6549ebf8e583f0b8f266d73cc4f3a9f073a5405c576b6c9a178b0`.
The first two methods passed unchanged. The compact drag reached 1100
points with its live draft intact. The reopened Link target, reopened
component action, inline draft, and compact missing-property recovery
screenshots were inspected. Screenshots, recordings, and results are
retained outside Git. No unrelated methods were replayed.

The fresh full local gate is deferred by the owner for this checkpoint;
the targeted replay is separate evidence and cannot turn the full run green.

## November 9 isolated full gate — completed, not green

### Closeout receipt manifest

Checkout base: `ba34293` plus preserved working changes. Fingerprints are
SHA-256 of the diff for `SiteForge Tests scripts sf`, not a substitute for a
commit ID. The ordinary and isolated debug identities are distinct.

| Result bundle | Build identity / source fingerprint | Completed, failed, or not run |
| --- | --- | --- |
| `full-4837c421-2ddf-4de8-8b69-cdf658b13731` | OwnerTesting, separate derived data; `a76acc4f0394cfba2844d5ebfab535411d733b723b796d920727166d76db2681` | 888 non-UI and 162 UI passed; five UI failed; three opt-in skips. All 170 UI methods reached. Image journey passed 168.644s. |
| `focused-19b144c7-fee7-4172-bb42-29004ec242cd` | Ordinary; same tested source as isolated gate | Four earlier failures passed, one native window resize failure reproduced. |
| `focused-55ca5461-61f5-49bc-8694-80ca2acbb6c2` | Ordinary; after native drag correction, `1527320483e7ea4238936cd91ad33ce9ec5fb4072b698c62e82e1fde66467ef0` | Exact Inspector journey passed 418.426s. |
| `full-1fc71fc2-8ab1-41f8-96b7-9a6f53b90655` | Ordinary; same corrected fingerprint | 888 non-UI and 69 UI passed. Image method lost connection at line 6232. Replacement runner failed initialization, LocalAuthentication -2. 100 UI methods not run; no skips reached. |
| `focused-b77eedd4-0bee-4158-be31-a164894899e4` | Ordinary; same corrected fingerprint | Exact interrupted image method replay passed 1/1, 171.265s, exit 0; disposable fixtures. No authorization prompt. |

The not-run set is the 170 named UI methods in the isolated full result
minus the 70 named UI methods reached in the ordinary interrupted result.
It starts at `testInitialLaunchOffersKeyboardFocusedNativeProjectActions`
and ends at `testWorldGridArtboardHierarchyVisualJourney`. The extra
replacement-runner error is not a UI method. No matching crash report or
product assertion was found for the connection loss. Do not combine these
receipts into a claimed full pass.

The earlier wasted runs exposed an occupied desktop and later an
authorization failure after helper loss. Keep the ordinary installed app
and owner data untouched, check for a free unlocked desktop and no other
collector before launching, and complete any system authorization
interactively. Do not change OS security settings or rerun unchanged
after another canceled authorization.

`full-4837c421-2ddf-4de8-8b69-cdf658b13731.xcresult` exited 65:
1,058 records, 1,050 passed (888 non-UI and 162 UI), five UI failures,
three owner opt-in UI skips. The corrected component return, native/Safari
focus and Aurora copy/export/reopen passed during this collection.

The failures were appearance Settings, minimum-window Pages list discovery,
Settings group reset, packaged Aurora navigator activation, and the
stable Inspector journey's native drag to 1,280 points. In the Settings
group failure, the exact control existed and was enabled but unhittable;
the app was in the background and the captured screen showed another app
in front. The Aurora pointer diagnostic also reports background state.
Do not infer a production Settings routing failure or assume that every
failure shares the same cause. The native window drag timed out before
testing compact Inspector controls.

After the ordinary installed app was no longer running, the five exact
failures were replayed with the ordinary test identity on unchanged source:
`focused-19b144c7-fee7-4172-bb42-29004ec242cd.xcresult`.
Appearance Settings, minimum shell, Settings group, and packaged Aurora
passed unchanged (37.551s, 8.063s, 55.334s, 47.762s). The Inspector journey
reached 1280 and restored the full width, then failed the compact resize
with a live typography draft. The straight-edge diagnostic
`focused-7227f87d-56e2-44a2-9bce-5f0850c9ee09.xcresult` established a
foreground native drag that landed at 1284 rather than 1280. A single
measured correction after real movement replaces reliance on the rounded
corner. The original width tolerance, draft, focus, and component checks
remain. Exact replay passed 1/1, 418.426s, exit 0 in
`focused-55ca5461-61f5-49bc-8694-80ca2acbb6c2.xcresult`.
Reviewed the 1280 layout, compact draft and recovery originals from
`siteforge-inspector-edge-review-20261109`: controls remained readable and
reachable and selection stayed aligned. Remaining wording/repetition is
the separate owner follow-up.

The final ordinary-identity gate
`full-1fc71fc2-8ab1-41f8-96b7-9a6f53b90655.xcresult` exited 65 after
5,946.343s of test collection. Repository checks and build passed.
The result reports 957 passes (888 non-UI, 69 UI), two failure records,
and no skips reached. The image journey
`testImageMixedFitAltDraftAndIndependentAssetReuseJourney` lost XCTest's
connection to the application. The replacement runner then failed to
initialize with LocalAuthentication -2, “Authentication canceled.”
The same image journey passed in the isolated full gate (168.644s).
No image assertion or product cause was established for this interruption.
The source/test/tool diff fingerprint matched the start of the final run.
See OD-030 for the required authorization boundary; no green full
receipt, commit, or push is claimed.

## Completed November 2 collector and November 9 follow-up

`full-96d605e0-a34f-49f2-8fbb-165472e79ab7.xcresult` exited 65.
The completed summary counted 987 records: 984 passes (888 non-UI,
96 UI), two UI assertion failures and one replacement runner initialization
error. No skips were reached. The runner timed out enabling automation;
unreached methods are not passes. Both long Safari comparison journeys
passed within this run (1305.732s and 1315.464s).

For SF-0203-006/SF-0701-002, the return journey now waits for the original
NodeID to become selected after scene adoption, then still asserts exact
geometry. For SF-0806-006/SF-1203-003/006/SF-1211-004, the browser journey
requires focus on the exact named Safari disclosure, not any element with
an empty identifier. The wait remains five seconds. Both changes are
test-only. Focused verification passed 3/3, no skips, exit 0
(`focused-b78ee9c0-bef4-4b3e-b46f-6aebf2ce9e7b.xcresult`): the two failed
UI methods and `testComponentDefinitionReturnContextRestoresOrderedSelectionAndRejectsReplacement`.
The Safari journey passed in 183.745s. The key originals reviewed in
`siteforge-closeout-focused-review-20261109` show the restored selection
aligned to the Frame, a readable and contained 430-point Header popup, and
the genuine intentionally blank About destination without editor chrome.
The November 9 ordinary full gate passed repository/build and 888 non-UI
tests, then hit the Aurora safety guard because the installed app was open.
Only the owned collector was interrupted (exit 75). The isolated Aurora
replay failed at the native Save button because Go to Folder remained open
(`focused-a8c88e22-3ef8-44a1-9fa7-5cc3d62e9134.xcresult`). The failure
screenshot shows the nested chooser blocking Save. Entering a directory
with a trailing separator and asserting its exact text and native chooser
dismissal preserves Save As and export interaction without bypassing them.
The corrected isolated replay passes 1/1 in 158.051s
(`focused-e3dfceeb-f55c-40c0-b587-b3f38054e89a.xcresult`).
The isolated full gate is running; no green full receipt yet. The live
November 2 notes below are historical.

## Current outcome — all27 original failures have passing focused receipts

The new authoritative collection `full-96d605e0-a34f-49f2-8fbb-165472e79ab7`
is still running. It has exposed a failure in
`testFormattingCommandsRemainVisibleAcrossInspectorDestinationsWithoutToolsDisclosureJourney`
at line3464: the immediate selected-state assertion after Back to this copy.
Creation preserves the source NodeID; returning schedules identity-checked scene
adoption. The test currently queries selection immediately after the click,
without awaiting that adoption. This is a diagnosis to verify, not a waived
assertion or green receipt. Keep the original collector running and source frozen;
inspect the completed result, then repair and replay this exact boundary before
the final gate can be accepted.

The same still-running collection also failed
`testNarrowChromeFooterAndMeasuredSafariBoundaryCompanion` at line9373,
506.892s, at the430-point Safari Header post-Escape focus assertion. The generic
focus helper discards the passed element and queries only its identifier;
Safari's summary has an empty identifier, so that predicate neither identifies
the menu nor proves focus belongs to it. Preserve the focus requirement and
inspect the retained hierarchy before replaying an exact live role/label focus
lookup. This diagnosis does not prove a generated Escape-handler defect and is
not a passing receipt. No source/test edit was made under the collector.

OD-029's explicit focused investigation/repair approval is recorded in
OPEN_DECISIONS. Both required native selectors now pass, with unchanged pointer,
geometry, keyboard, focus and destination assertions. The final full gate is
still required; the failed full inventory below remains historical evidence.

Before the storage-backed retries the workspace had11GiB available; Xcode setup
exited0 and no collector was active. The previous2.7GiB reading is historical. The prior
3139.734s browser bundle uses675MiB; the full inventory bundle uses1.2GiB.
Budget at most2GiB for these targeted receipts, recheck capacity between runs,
and preserve all existing projects/recovery/builds/results. No deletion was performed.
Final native-repair readiness is7.3GiB available. Reserve3GiB for the final full
collection and incremental output; recheck during the run without deleting evidence.

| Original failed selector (`SiteForgeLaunchTests/`) | Latest actual receipt | Next exact action |
| --- | --- | --- |
| `testAutomaticNarrowChromeNativeAndMeasuredSafariMenuJourney` | PASS1/1,511.484s, `focused-fa393b1a-3abd-4b9c-a4f6-8735da2e759a` | Final stable-source verification |
| `testNativePreviewHeaderPublicPointerBoundaryProbe` | PASS1/1,50.786s in the same group; final-source replay PASS50.516s | Final stable-source verification |

The other25 original failed methods have exact passing focused replays:6 non-UI
and19 UI (9 in the vocabulary/layout group,6 in the interaction group,Where Used1,
the original browser presentation-context comparison1, and the two storage-backed retries).
This is reconciliation of the27 failures, not a new full-suite total or green gate.
Together these reconcile all27 original failures. The three owner-session skips
remain intentional. Final verification and reviewed commit/push remain pending.

## Native page-chrome ownership repair

Bounded SF-0806-006, SF-1203-003/006 and SF-1211-004. The short baseline still
fails ordinary Header pointer at50.885s. A redacted in-process trace then shows
the native window/control reaching the genuine popup cell, while the sheet
hosting accessibility path resolves a SwiftUI node at Header instead of that
cell; Footer reaches its native cell. The native Preview had flattened the
container paint surfaces and their actual children into overlapping AX siblings.
The background was exposed as a separate leaf over the control.

Restoring a standard cell, removing navigation wrappers, a compact bezel and
passive-container metadata did not repair the real pointer path; none of these
experiments remains. Hiding all background leaves makes the short pointer probe
pass51.140s, but loses the required Header geometry element: the broader selector
correctly rejects that incomplete approach. No assertion was removed or relaxed.

The adopted fix carries optional canonical parent ID/page-flow role into the
immutable render object and groups only Header/Footer presentation by that real
ancestry inside the existing SwiftUI Preview sheet. The actual Header/Footer
container owns its background and child views; pure paint is hidden from AX only
within that group. Standalone object accessibility stays on its previous path.
World frames, NodeIDs, clipping, menu target/action, native popup/cell, focus and
teardown remain authoritative. Relative child placement plus owner placement is
algebraically the original world-to-Preview transform. No new host, renderer,
canonical property, schema migration, fake role/frame, pointer fallback or
browser/compiler change was introduced. The temporary trace was removed.

The newly reachable430-point check also detects the old90-point control cap
inside a110-point resolved navigation allocation (a10-point center displacement).
The popup now fills its real resolved navigation frame. The existing hosting
test now covers90/110/160 widths at24/32 heights and asserts width and both
centers, not merely containment.

Focused result `focused-fa393b1a-3abd-4b9c-a4f6-8735da2e759a`: code1/1 plus
both required UI selectors2/2,511.484s/50.786s,exit0. Log:
`siteforge-native-resolved-width-required-journeys-20261102.log`.
After limiting decoration exclusion to owned page chrome and removing stale
UNRUN comments/unused direct-AX import, final-source focused result
`focused-b335f521-719a-40c4-9624-4d4f90f439f5`: code4/4 and short UI1/1,
50.516s,exit0; log `siteforge-native-final-source-focused-20261102.log`.
The two new code regressions are
`testNativePreviewDecorationsDoNotOwnAccessibilityOverRealContent` and
`testNativePreviewPageChromeGroupsUseCanonicalAncestryWithoutMovingFrames`.
The latter proves ancestry rather than rectangle overlap, stable identity/order,
exact world frames/clips, snapshot round trip and old optional-metadata decoding.

All19 original PNGs from the required pair were inspected in temporary
`siteforge-native-two-required-reviewed-20261102`, with retained manifest.
Native320/430 panels show upright text, readable menus and restored focus with
no stale popup; the430 popup aligns with the actual wider allocation. Editor
320/430/768 views retain aligned Header selection, clear grid/pasteboard and
readable Inspector/header controls. Safari320/430 and768 inline states retain
real content/destinations and focus without editor-chrome leakage. About is the
deliberately blank destination fixture, not missing authored content. Representative
native430 focus: `02A1ED3B-7720-4C64-AC53-C40FD5E70994.png`; native Header open:
`B38FC5C9-7648-455D-B046-3D97B472DA7F.png`; Safari768:
`24241F78-D96C-449E-91A9-6500ED35B06C.png`.
Window screenshots do not themselves include the menu bar/Dock; normal window
policy is separately asserted by the unchanged launch helper. No full-green
claim is inferred from this focused result.

The full original browser selector compiled with the public snapshot reader,
but `focused-a3136e6a-9d35-4731-b1c8-be60d1f506a9` executed0 methods: runner12731
timed out enabling automation mode. Current OS logs record a new “Enable UI
Automation” request. This is initialization failure, not a browser assertion or
passing receipt. Following the owner's “next” response, one isolated authentication
retry completed as recorded below. No collector is running.

That retry entered the UI journey but failed1/1,105.845s,
`focused-9585a2bd-a4a7-4ed9-9d1e-620b4a2a6a12`: public snapshot attribute limits
truncate a512-byte payload plus its marker. The retained Base64 is5642 characters,
length mod4=2, and cannot decode; no browser behavior is accepted from it.
Chunks now use384 bytes, preserving the original131072-byte aggregate bound,
with declared aggregate length, exact per-chunk lengths, duplicate consistency,
strict Base64/JSON validation and one public snapshot. The original full selector
completed in `siteforge-presentation-complete-snapshot-baseline-20261102.log`.
No viewport, focus, Escape, mutual-exclusion or pixel assertion was relaxed.

The corrected ORIGINAL `testGeneratedWebsiteMenuEscapePresentationContextComparison`
passes1/1,972.799s, exit0 in `focused-ef85f1c7-6a6e-4ff9-ad14-d2899423dab4`.
No reduced probe or omitted breadth is counted as this result. It retains both
ordinary and responsive modes at the same548×516 CSS viewport, genuine pointer/
Escape/focus, artifact/runtime identity, peer-menu exclusivity and exact pixels:
ordinary Header/Footer each0/103664 changed (allowed103); responsive Header/Footer
each0/33600 (allowed33). Runtime is69% shorter than3139.734s by removing repeated
AX chunk traversals, not assertions. All14 original PNGs were inspected in
temporary `siteforge-browser-baseline-passing-20261102`, with its retained manifest.
The all-closed ordinary baseline is `F102080C-B268-4A4E-BBEB-7902BA0D2BFD.png`;
ordinary Footer closed is `9601D2F4-71BF-4BB6-9DFE-F3B2EA3A64C5.png`;
responsive all-closed baseline is `01ABF707-C4D7-4B76-A641-4E3793BBA875.png`;
responsive Footer closed is `7EF802D3-3F68-45DE-979E-E2D65FB9F01E.png`.
Open panels are readable, Footer opens upward, close leaves no residue, and focus
remains visible; the deliberately open-peer handoff is not mislabeled all-closed.
Fresh storage remains11GiB. The two OS-killed selectors completed their single
exact retry: Aurora passes68.844s and Related Page passes255.725s,2/2,exit0,
`focused-c0b1a09a-2786-4f74-a775-dd018d51ec77.xcresult`; log
`siteforge-storage-recovered-exact-retries-20261102.log`. Their original OS kills
remain historical failures, not retroactive passes. All four Aurora originals in
temporary `siteforge-storage-retry-aurora-review-20261102` and all five Related
Page originals in `siteforge-storage-retry-related-review-20261102` were viewed
at original resolution. Labels remain upright, selection bounds align, page and
pasteboard remain distinct, the named-copy sheet is readable, and the reopened
independent page shows Saved without a retained sheet or ghost overlay.
No production changes were needed for these retries. Only the two native
Header methods were then unresolved. That historical pause is superseded by
the approved repair and passing native outcomes recorded above.

Final focused-reconciliation repository checks exit0 in temporary log
`siteforge-final-focused-reconciliation-repository-20261102.log`: security,
440-record traceability, architecture, runtime and bounded evidence checks pass.
Requirement evidence JSON parses and `git diff --check` passes. Final live disk
reading is9.9GiB available (11GiB was the pre-retry reading). No test or check is
left running. This is not a final full verification or approval to commit/push.

## Final authoritative collection — RUNNING

The final focused source is frozen with source/test/tool diff SHA256
`5456f330b7d0fc9dc6a0bc04e7f592a314b50d31480728798fade13b1d00150d`.
One `./sf verify` is running, result
`full-96d605e0-a34f-49f2-8fbb-165472e79ab7.xcresult`, retained log
`siteforge-native-closeout-authoritative-20261102.log`. No source/test/tool edits
or duplicate collection are permitted during that run. No final result is yet
claimed; record actual result-bundle totals and all owner-session skip reasons
after completion before any reviewed commit or normal push.

Current observed milestones: all888 non-UI tests pass37.909s; the repaired
native/Safari journey passes523.336s in this full collector. Subsequent UI
methods are progressing. The collector survived the interrupted chat turn and
was adopted, not restarted. Source/test/tool hash remains unchanged.

## Stable collection — historical failed inventory

One supported `./sf verify` ran to completion, exit65. Repository checks and
application build passed. No source/test edits or duplicate collector occurred
during collection. Tracked source/test/tool diff SHA256 before and after:
`2a2d8ae96f6b469a90daf58b5f6786a9f12c41c00ac510928b41caaddc4ca72e`.

Retained temporary log: `siteforge-full-inventory-20261102.log`.
Retained result: `full-1c824ea6-059e-4c75-9e65-18fc5d8f9378.xcresult`.
The result bundle, rather than incomplete per-runner console summaries, reports:

| Target | Total | Passed | Failed methods | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Unit/integration | 886 | 880 | 6 | 0 |
| UI | 170 | 146 | 21 | 3 |
| Combined | 1056 | 1026 | 27 | 3 |

The three skips explicitly require owner-open Dark Flow projects/isolation
storage. No owner data was opened to force these checks to run. Two UI failures
are recorded as `Test crashed with signal kill`, not passing or product assertion
results. Subsequent OS-log attribution identifies both as cache-cleanup-service
terminations; this does not convert them to passing tests.

## Ordered repair classification

### Post-inventory focused results (do not overwrite original failures)

Six exact failed non-UI methods pass6/6,0.754s, exit0 in
`focused-424870fc-a2fa-4d63-8866-3b5793396d3b`; temporary log
`siteforge-inventory-unit-repairs-20261102.log`. No canonical behavior changed:
tests now distinguish base and narrow CSS rules, assert the actual Text-node
visibility selector, supply real document routes, and require approved wording.

Nine exact UI methods pass9/9,1091.696s, exit0 in
`focused-eaa7db05-6e41-4e36-8787-f658fa357a0a`; temporary log
`siteforge-inventory-ui-vocabulary-layout-repairs-20261102.log`:

- ComponentActionNativeInspectorDraftResetHistoryAndReopenJourney.
- ComponentPropertyDiscoveryNativeSearchClearTraversalAndContextJourney.
- ComponentSlotFallbackNativeAuthoringCancelHistoryAndReopenJourney.
- GeometryTransformPointerKeyboardNumericUndoRedoAndAccessibilityJourney.
- MixedFluidFallbacksAcceptExplicitRangeWithoutBorrowingPrimaryValuesJourney.
- NativeSelectAllInPageEditorReplacesDefaultDraftJourney.
- PagesSiteSetupPageIndexingResetAndCancelJourney.
- PracticalComponentNamedCreationDesignDraftAndReturnJourney.
- StructuralLayoutInspectorReflowsSectionStackAndGridJourney.

All names above have the XCTest `test` prefix. The production search/filter
group now uses the shared inset Inspector section, preserving native bezel
bounds and all real keyboard/pointer assertions. No selection/history mutation
was added. A separate eight-method focused group completed exit65,6 passed/2 failed,
`focused-caa2847f-a5bf-4baa-a4ec-17175a357d57`. The six passes are component
text properties, component visibility, ordered fill layers, solid fill/opacity,
typography, and matched Safari title widths. The last passes288.171s. Where
Used and presentation-context comparison remain failures in that receipt.

Original-resolution review of the focused component-discovery screenshot
`750ADD40-D5FA-47A8-9C7E-FA5EBF1BDE65.png` confirms the search bezel and focused
ring remain within the inset section; Previous/Next/Clear and the explanatory
labels are readable. Shell destination labels remain single-line, canvas text
is upright, and the selected surface aligns with its outline. This scoped
visual receipt does not waive the remaining native Preview failure.

The six typography originals (default, authored family/size/tracking, inline,
undo/redo, fallback, reopened), seven solid/opacity originals (including the
real Colors panel, stepper, focus-loss and invalid/cancel), one ordered-layer
original, five linked-text originals and six component-visibility originals
from `focused-caa2847f-a5bf-4baa-a4ec-17175a357d57` were extracted and inspected
at original resolution. Temporary review directory basename:
`siteforge-interaction-reviewed-20261102`; each subsystem has its own manifest
mapping retained UUID filenames to named states. Text stays upright and inside
selection; authored surfaces align; inherited/override and hidden states are
readable; no ghost is visible. The solid-opacity pointer journey deliberately
uses its existing constrained placement, not generic maximized-window proof.
Both Where Used originals were also inspected in
`siteforge-where-used-row-hit-reviewed-20261102`.
The five matched Safari title screenshots at1440/430/320, short430 and hidden430
were inspected from `matched-title` in the same review directory. Long titles
truncate within their reserved box, narrow Menu remains separate, short text is
readable, hidden title leaves no stale glyphs, and authored body text stays
upright. No editor grid/selection chrome appears in these website captures.

Read-only original-video inspection exposes Where Used's first divergence:
clicking its plain HStack row center (Spacer) leaves both sheet and Components
tab unchanged, so the action has not fired. A model-selection workaround is
not warranted. Its visible bounded label now has a rectangular content shape;
the exact journey passes1/1,33.692s in
`focused-deb18385-1436-48b8-b993-1717fa8a025f`. It additionally requires the real
sheet to dismiss before exact instance identity and selected Layers adoption.
Reviewed original `12B463EC-399A-45EF-B45F-0342A3A3111A.png` shows the correct
Layers selection and aligned rendered surface, with no remaining sheet.

The presentation-context receipt evaluates ordinary548×516 at devicePixelRatio
3.5, then responsive313×294 at1.75 although548×516 was requested: ordinary175%
page zoom persisted. A concrete replay uses Safari's actual View menu to reset
zoom rather than a Console-consumed Command-0. Exact evaluated dimensions,
artifact/runtime identity and strict pixels remain required. That replay fails
1/1,693.752s in `focused-07aec268-1069-4ffd-b49c-974450386bed`, before reaching
the reset: fresh AX collapse lookup fails after ordinary Header Escape, with an
XCTest commonInit assertion in snapshot collection. The two original screens
show the baseline and genuine opened menu; no closed screen/DOM was reached.
Failure-only diagnostics now retain live target existence/value/frame and the
same artifact's observational DOM receipt without closing it or replacing the
AX assertion. Diagnostic replay fails1/1,923.108s in
`focused-9e330837-4793-4079-af13-b22aa27420ba`: the trusted Escape targets SUMMARY,
the same document closes both menus, and the live AX value is0. The retained
closed screenshot `3D1BEF8C-CFD9-448A-BADE-1E82A18FEF50.png` visibly has no popup
and retains the summary focus ring. Serial exists/value snapshots overrun the
3-second predicate deadline, rather than proving a website closure failure.
The current replay queries label and collapsed value in one native snapshot,
retaining the same deadline and strict DOM/pixel checks:
`siteforge-presentation-single-snapshot-collapse-20261102.log` completed exit65,
1 failed/0 passed,3139.734s, result
`focused-e48d5a1f-8893-4d03-8d35-7f4e6577e42a`. All four AX collapse checks and
the exact ordinary/responsive548×516 comparison pass. Three pixel comparisons
return zero; ordinary Footer differs7396/103664, allowed103. Original-resolution
review proves its baseline intentionally contains the reopened Header panel,
whereas after Footer Escape both menus are closed. The test reopens Header to
challenge mutual exclusion; its baseline must therefore be the same viewport's
all-closed screen, not the open-peer handoff screen. Preserve both the exclusivity
and strict pixel assertions. Originals are retained in temporary
`siteforge-presentation-single-snapshot-review-20261102`; ordinary Footer baseline
`6946F234-D118-4310-B1BA-30A9AF494E2E.png`, closed
`6B7B256C-D290-4299-A084-3DFD2F667148.png`, Header closed
`7848AC43-BAF4-49CB-90F8-DA5760530CFC.png` were inspected.
The authorized read-only native hit-path probe completed exit65,1 failed/0 passed,
45.577s in `focused-ab1d6dc5-21dc-4cf3-84a9-2998b669372a`. Header's center hit-test
returns the genuine NativePreviewNavigationButton, fully visible90×24 bounds,
enabled/alpha1/key sheet/active application. XCTest still rejects its92×26 AX
menu as not hittable. No sampled center obstruction is proven; the AX boundary
remains unresolved, not waived. Receipt `FA597AB6-EDAB-4E46-87BB-86ADC4FB7CBC.txt`
is retained in temporary `siteforge-native-authorized-hit-path-review-20261102`.
The temporary trace was removed without host/control/pointer changes.
The browser test now retains its all-closed presentation baseline separately
from the deliberately open Header-to-Footer handoff, preserving exclusivity,
window-frame identity and the exact pixel tolerance. This new correction is
UNRUN: only2.7GiB remains free after collection. Owner storage action is required
before another recorded UI attempt; no cache/project/recovery/evidence deletion.
No test process remains active. One earlier diagnostic attempt was deliberately stopped
early (exit75) to correct missing-element-safe diagnostics; no pass is inferred.

Post-diagnostic `scripts/check-repository.sh` passes, exit0, retained temporary
log `siteforge-post-diagnostic-repository-20261102.log`: security, traceability,
architecture, migration and evidence checks pass. Evidence JSON parses and
`git diff --check` passes. These checks do not compile or execute the new browser
baseline correction and do not supersede the failed full inventory. No commit,
push, installation, privacy change or evidence cleanup occurred.

Retained typography hierarchy proves Tracking y986 begins at scroll maxY986;
the opacity hierarchy proves Stepper y890 lies below constrained scroll maxY753.
AXHittable alone is insufficient. The active replay uses the existing bounded
scroll/re-query helper and retains real focus/stepper assertions.

System logs04:43:47.057 and07:26:17.120 explicitly identify runners95710 and1445
as terminated by `CacheDeleteAppContainerCaches`. The latter reports
`code:0xBADDD15C explanation:CacheDeleteAppContainerCaches requesting termination
assertion for app.siteforge.SiteForgeUITests.xctrunner`. Both have OS
reason0xBADDD15C. No service/privacy setting was changed.
Owner space action is pending; no unchanged retry of those killed methods.

Native Header remains failed. Its earlier host/control/AX experiment prohibition
is preserved; permission for one read-only actual-hit-path diagnostic is pending.

A means product/interaction boundary; B means test vocabulary, fixture context,
or automation setup; C means runner termination. Candidate diagnoses below are
not claimed fixed until exact focused replay passes.

### A — concrete product boundaries

- `testAutomaticNarrowChromeNativeAndMeasuredSafariMenuJourney` and
  `testNativePreviewHeaderPublicPointerBoundaryProbe`: genuine Header Menu
  remains not hittable. Keyboard/visible geometry do not waive ordinary pointer
  acceptance. No further speculative host/control/AX replacement experiments.
- `testComponentPropertyDiscoveryNativeSearchClearTraversalAndContextJourney`
  and `testPracticalComponentNamedCreationDesignDraftAndReturnJourney`: the
  search field extends one point beyond each horizontal scroll boundary.
  Both reproduce control x1365/width334 versus viewport x1366/width332.

### A — unresolved interaction/state attribution

- `testComponentTextPropertiesTwoInstancesResetHistoryAndReopenJourney`:
  app/root reports Disabled at the pointer readiness boundary. Inspect actual
  modal/activation/control state; do not simply remove the enabled assertion.
- `testComponentVisibilityDefinitionInstanceResetAndReopenJourney`:
  insertion does not satisfy the expected adopted render-object count.
- `testDesignInspectorTypographyInlineUndoRedoAccessibilityJourney`:
  live field fails keyboard-focus assertion in the replacement helper.

### B — unit/fixture expectations

- `testResponsiveLayoutReviewDeterministicWidthMatrixAndScope` and
  `testResponsiveLayoutReviewReportsFixedFluidAndOverrideWinnersWithoutAuthoredChanges`:
  old Fluid presentation versus approved Smooth scaling vocabulary.
- `testFormInspectorAccessibilityPresentationPreservesMixedValuesAndProvenance`:
  old Authored presentation versus Set here; canonical origin remains authored.
- `testAutomaticChromeNavigationSharesTrailingDefaultAndRemainingWidthWithStaticOutput`:
  blanket assertions do not distinguish inherited base rules from mobile
  partial overrides and the shared 90-point Menu reservation.
- `testConnectedFluidCascadeCustomWidthsResetAndHiddenGridParticipation`:
  exact standalone CSS string needs comparison to the real visibility rule.
- `testManagedChromeTitleStaticOverflowRetainsSemanticIdentityAndResponsiveHeight`:
  compiler fixture omits document route context used by production allocation.

### B — UI vocabulary expectations

- `testComponentActionNativeInspectorDraftResetHistoryAndReopenJourney`.
- `testComponentSlotFallbackNativeAuthoringCancelHistoryAndReopenJourney`.
- `testGeometryTransformPointerKeyboardNumericUndoRedoAndAccessibilityJourney`.
- `testMixedFluidFallbacksAcceptExplicitRangeWithoutBorrowingPrimaryValuesJourney`.
- `testNativeSelectAllInPageEditorReplacesDefaultDraftJourney`.
- `testPagesSiteSetupPageIndexingResetAndCancelJourney`.
- `testStructuralLayoutInspectorReflowsSectionStackAndGridJourney`.

These fail old Inherited/authored/defaulted/applicable/Padding wording. Preserve
their value, identity, history, cancellation and provenance assertions using the
approved presentation; do not accept arbitrary text or merely element existence.

### B — candidate query/reveal/browser-setup boundaries

- `testComponentOrganizationDependencyInspectionAndWhereUsedJourney`: immediate
  canvas query follows asynchronous usage selection/adoption without readiness.
- `testDesignInspectorOrderedFillLayersAccessibilityJourney`: Add controls are
  queried without revealing the scrolled section.
- `testDesignInspectorSolidFillOpacityKeyboardUndoRedoJourney`: real opacity
  stepper is not hittable after the preceding field interactions.
- `testGeneratedWebsiteMenuEscapePresentationContextComparison`: hard-coded
  execution-context selector lookup fails before its comparison acceptance.
- `testManagedChromeTitleMatchedSafariWidthsAndOverflowJourney`: measured
  `innerWidth`1441 versus requested1440. Correct real viewport setup; preserve
  exact matched-width and geometry checks.

### C — signal-killed runners; cache-cleanup-service termination confirmed

- `testAuroraResponsiveContentConversionPreservesSelectionAndReflowsAcrossPresetsJourney`.
- `testRelatedPageReuseNavigationActionAuditAndNativeReopenJourney`.

No blind unchanged retries. OS logs identify the cache-cleanup service as the
terminator of both exact runner PIDs. Low free storage is separately observed;
no SiteForge assertion failure or successful test result is inferred.

## Passing evidence retained

`testGeneratedWebsiteMenuEscapeStateAndPaintJourney` passes1011.238s, retaining
strict Header/Footer320/430 pixel thresholds, wider768 and real destinations.
The measured Safari companion and Footer companion also pass. Shared runtime
and canonical document remain unchanged. The separate presentation-context test
failure does not negate the strict pixels, nor does the pixel pass waive native
Header pointer failure.

`testWorldGridArtboardHierarchyVisualJourney` passes44.329s. Native Save/Close/
Reopen, image authoring/reopen, all-five-element selected/render geometry,
responsive container/visibility, responsive comparison/reveal, Inspector normal/
compact stability and Preview/Check Website repair have passing inventory
results. New inventory screenshots still need extraction/review; the previously
reviewed nine browser originals remain in the linked focused receipt.

No publish-during-view-update or invalid-view-geometry warning was found in the
console log. Internal QoS warnings are retained and need stack attribution;
their absence is not claimed. No commit/push, release/install, owner/coordinator
data change, cache/evidence deletion or new feature work occurred.

Next: focused concrete repairs and exact selectors, factual evidence updates,
then the required green documentation-inclusive final gate and reviewed Git
boundary. Keep the milestone IN PROGRESS until all required acceptance is green.
