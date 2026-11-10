# Codex Continuation Handoff

## Current closeout — targeted replay only

The exact ordinary-identity image journey passed 1/1, 171.265s, exit 0,
in `focused-b77eedd4-0bee-4158-be31-a164894899e4.xcresult`. No source
changes or owner data access. The interrupted prior full run reached
70 of 170 UI methods; see the closeout manifest for the two error records
and 100 not run. These are separate receipts, not a stitched green gate.

The subsequent ordinary `./sf verify` finished with exit 65: repository
checks and build passed; 888 non-UI and 163 UI passed, four UI failed,
three owner opt-in UI skipped, and zero were unrun. Receipt:
`full-51ae6ac8-6773-45a1-bb4c-c4155c54bbb3.xcresult`; source/test/tool diff
SHA-256 `1527320483e7ea4238936cd91ad33ce9ec5fb4072b698c62e82e1fde66467ef0`.
See the [failure inventory](evidence/SF-LOCAL-BUILDER-FULL-INVENTORY-20261102.md)
for the exact failures and the separate 4/4 passing replay receipt,
`focused-04cbf0e7-7f8f-45e4-bbe6-67a166e4b739.xcresult`. The owner authorized
the reviewed checkpoint commit and normal push after that replay; a fresh
local full run is deferred for this checkpoint only. This is not full
milestone acceptance. Keep the separate usability/Header resize follow-up
pending for a fresh explicit request. Previous live-run statements below
are historical.

## Current baseline gate — November 9, ordinary replay

The isolated full gate completed, exit 65, in
`full-4837c421-2ddf-4de8-8b69-cdf658b13731.xcresult`: 888 non-UI passed,
162 UI passed, five UI failed, and three owner opt-in UI journeys skipped.
The repaired component return, Safari focus, and Aurora Save As/export/reopen
all passed inside that run. Settings failure diagnostics show the isolated app
in the background with an enabled but unhittable control; the retained screen
shows another foreground application. No app-wide disabled-state defect was
established. The Inspector resize timeout remains a separate native pointer
boundary to compare.

After confirming the installed app was no longer running, replayed only the
five exact failures under the ordinary test identity, without changing source.
Result `focused-19b144c7-fee7-4172-bb42-29004ec242cd.xcresult` and temporary
log `siteforge-closeout-ordinary-five-20261109.log`: the first four passed
unchanged. The fifth reproduced the resize timeout only on the compact
transition with a live draft. A straight-edge diagnostic produced actual
movement to 1284 rather than 1280 points while foregrounded. One correction
for a measured near miss now retains the native drag and two-point width
assertion. The complete Inspector journey passed 1/1, 418.426s, in
`focused-55ca5461-61f5-49bc-8694-80ca2acbb6c2.xcresult`.
Reviewed original 1280, compact draft, and recovery screenshots in
`siteforge-inspector-edge-review-20261109`.

The final ordinary-identity `./sf verify` exited 65. Log:
`siteforge-closeout-final-ordinary-20261109.log`. Source/test/tool diff hash
`1527320483e7ea4238936cd91ad33ce9ec5fb4072b698c62e82e1fde66467ef0`.
Result: `full-1fc71fc2-8ab1-41f8-96b7-9a6f53b90655.xcresult`.
Repository checks, build, 888 non-UI and 69 UI tests passed. The image
journey lost XCTest's application connection; the replacement runner
reported macOS authentication canceled (LocalAuthentication -2) before
executing a method. The bundle has 957 passes, two failure records and no
skips reached. No source drift. See OD-030: resolve interactive automation
authorization before a bounded exact replay and a new gate. Do not loop
unchanged verification. No commit, push, or next-slice implementation.
Earlier live-run statements below are historical.

## Current closeout — 2026-11-09

The November 2 authoritative run exited 65. Its completed result reported
984 passes (888 non-UI, 96 UI), two failed UI methods and one replacement
runner initialization error (“Timed out while enabling automation mode”).
It did not reach the remaining UI methods. The run is no longer active.

The focused follow-up preserves exact component NodeID/geometry while waiting
for scene adoption, and requires Safari focus on the exact named disclosure
instead of matching an empty identifier. Both failed selectors and the
component return-context regression passed (3/3, zero skips) in
`focused-b78ee9c0-bef4-4b3e-b46f-6aebf2ce9e7b.xcresult`. The Safari method
passed in 183.745s. Key original screenshots were reviewed.

The November 9 ordinary-identity `./sf verify` is no longer active.
Temporary log: `siteforge-closeout-authoritative-20261109.log`.
Result: `full-eff79e59-3f89-42a0-b478-91c75ffe8cab.xcresult`.
Repository checks, build and 888 non-UI tests passed. The Aurora copy
journey refused to run while the installed SiteForge app was open. We
interrupted only the owned xcodebuild (exit 75) rather than continuing an
invalid gate; the installed app remains open and untouched. No green full
result is claimed. The same Aurora selector is now replaying with the existing
OwnerTesting bundle identity and separate build directory in
`focused-a8c88e22-3ef8-44a1-9fa7-5cc3d62e9134.xcresult`.
That first replay reached Save As but left the native Go to Folder panel
open. After explicitly entering the exact directory path with a trailing
separator and requiring chooser dismissal, the same isolated selector
passed in 158.051s (`focused-e3dfceeb-f55c-40c0-b587-b3f38054e89a.xcresult`),
including native export cancellation/retry and reopen.

One isolated `./sf verify` is now running with the existing
`app.siteforge.SiteForge.OwnerTesting` build identity in its separate build
directory. Temporary log: `siteforge-closeout-isolated-authoritative-20261109.log`.
Result: `full-4837c421-2ddf-4de8-8b69-cdf658b13731.xcresult`. All 888
non-UI tests passed. The live log records Settings appearance, Settings group,
minimum-window Pages list, and Aurora packaged-sample pointer failures.
The Settings window is present but XCTest marks the app/window disabled;
the Aurora pointer diagnostic reports the app in the background. Cause
is not established. The corrected Aurora copy/export/reopen journey passed
in this collection. Wait for the completed bundle before comparing exact
failed selectors under the ordinary identity. No source edit during collection.
Do not duplicate it or change source/tests/tools. The ordinary installed
app, its projects and recovery data remain untouched.
Source/test/tool diff SHA-256:
`f64786aa78f3549a180718f279e73cd38352b287ee42602228e23a005dc94a09`.
The earlier fingerprint above describes the ordinary interrupted run.
The isolated run's source/test/tool diff SHA-256 is
`a76acc4f0394cfba2844d5ebfab535411d733b723b796d920727166d76db2681`.
No milestone completion,
commit or push is claimed. The live-run notes below are historical.

## CURRENT EXECUTION — focused repairs after full inventory,2026-11-02

LIVE AUTHORITATIVE COLLECTION: the existing `./sf verify` is still running;
do not start another. Result `full-96d605e0-a34f-49f2-8fbb-165472e79ab7.xcresult`,
temporary log `siteforge-native-closeout-authoritative-20261102.log`. All888
non-UI tests pass; the repaired native/Safari journey passes523.336s in this
full run. Later UI methods are progressing. No final total or green gate is
claimed. Source/test/tool hash remains
`5456f330b7d0fc9dc6a0bc04e7f592a314b50d31480728798fade13b1d00150d`.
Keep source/tests/tools frozen until this collector exits and its authoritative
result is read. This live entry supersedes the preparatory “Next” below.

The running collector has now exposed one failure at line3464 of
`testFormattingCommandsRemainVisibleAcrossInspectorDestinationsWithoutToolsDisclosureJourney`:
the immediate selection assertion after Back to this copy. Source creation
preserves NodeID; return selection is applied during asynchronous scene adoption.
Verify the completed diagnostics before accepting a live identity/adoption wait
as the correction. No production/test edit has been made during collection.
The final gate is not green. Do not duplicate or abort the healthy collector.

A second failure is recorded at line9373 in
`testNarrowChromeFooterAndMeasuredSafariBoundaryCompanion` (506.892s): Safari
Header post-Escape focus at430 points. `waitForKeyboardFocus(element:)` drops
the element's role/label and searches only its empty Safari identifier. That
cannot identify the intended menu. Inspect its retained hierarchy, preserve the
focus requirement and use the exact live control rather than accepting any
empty-identifier focus. Source/tests remain frozen until collection completes.

LATEST: all27 original failed methods now have exact passing focused receipts.
OD-029 approval was recorded and the native ownership repair is implemented in
the existing host: canonical Header/Footer containers own the real child views,
paint-only surfaces do not intercept their AX hits, and the popup uses its full
resolved navigation width. Both exact native selectors pass511.484s/50.786s in
`focused-fa393b1a-3abd-4b9c-a4f6-8735da2e759a`; final-source checks pass4 code
plus1 UI in `focused-b335f521-719a-40c4-9624-4d4f90f439f5`. All19 originals
were inspected. No temporary production trace or speculative override remains.
Next: stable-source authoritative `./sf verify`, exact result reconciliation,
reviewed scoped commit and ordinary origin/main push, then hosted check review.
Do not start a duplicate collector, new feature, install/signing step or cleanup.
Preserve coordinator/audit/archive and owner projects/recovery/results. The
following outcomes are chronological history, superseded by this entry.

Current outcome: no collector is active. The original full browser comparison
passes1/1,972.799s, with all four pixel comparisons zero and14 originals reviewed.
The storage-backed Aurora and Related Page retries pass2/2,68.844s/255.725s;
all9 originals were reviewed. Available storage remains11GiB. Thus25 of the27
original failed methods now have exact passing focused receipts. Only the two
native Header selectors in the evidence's current table remain paused under
OD-029. Its single read-only diagnostic is exhausted; further native AX
ownership/activation investigation needs separate owner authorization. No final
green verification, commit or push is claimed. The execution narrative below is
historical and superseded by this outcome and the current evidence table.

The successful original browser replay follows one automation initialization
failure (zero methods) and one snapshot-attribute truncation failure. The concrete
384-byte chunk correction preserves the131072-byte receipt bound and validates
every byte. No contract breadth or pixel tolerance was reduced. The evidence's
two-row current table is authoritative; historical failures are retained there.

The authorized native diagnostic has completed:
1 failed/0 passed,45.577s, `focused-ab1d6dc5-21dc-4cf3-84a9-2998b669372a`.
The genuine Header popup wins AppKit's center hit-test and is fully visible;
XCTest still rejects its AX target. Temporary tracing is removed. OD-029's
one diagnostic is exhausted; no speculative native redesign is authorized.
The concrete browser baseline correction passed exact replay. The prior
Footer comparison sampled a deliberately open Header panel as its baseline;
the correction preserves the all-closed screen and exact pixel/exclusivity gates.
The old2.7GiB reading is superseded; preserve projects/recovery/results.
The detailed execution receipts below are chronological history, not active jobs.

Post-inventory repairs: six exact non-UI methods pass6/6,0.754s,
`focused-424870fc-a2fa-4d63-8866-3b5793396d3b`; nine exact UI methods pass9/9,
1091.696s, `focused-eaa7db05-6e41-4e36-8787-f658fa357a0a`. Component discovery
now uses the standard inset Inspector section; both overflow journeys pass.
Approved vocabulary/route-context/CSS-cascade expectations retain their exact
semantic/history checks. The eight-method interaction/browser replay completed
exit65,6 passed/2 failed in `focused-caa2847f-a5bf-4baa-a4ec-17175a357d57`.
Matched Safari title widths now pass288.171s. Where Used subsequently passes1/1,
33.692s in `focused-deb18385-1436-48b8-b993-1717fa8a025f`: the real bounded row
label now has a rectangular content shape; the test requires sheet dismissal
and exact original instance/selected Layers identity. No model workaround.
The presentation-context replay failed1/1,693.752s before reaching its zoom reset:
fresh collapse AX lookup failed after Header Escape. Result
`focused-07aec268-1069-4ffd-b49c-974450386bed`; screenshots show real ordinary
Header open, but no post-Escape visual/DOM receipt was reached. No paint-cause
claim. That diagnostic replay failed1/1,923.108s, but proves the trusted Escape
reached SUMMARY, closed the real DOM, and exposed AX value0. The retained closed
screen has no popup. Serial exists/value queries exceed the same3-second deadline.
The combined snapshot replay completed1 failed/0 passed,3139.734s,
`focused-e48d5a1f-8893-4d03-8d35-7f4e6577e42a`. All four AX collapse checks and
matched548×516 viewport pass. Ordinary Footer's baseline includes the intentionally
reopened Header panel, so it differs from the correctly all-closed final screen;
use the same presentation's all-closed baseline without dropping exclusivity.
Completed authorized temporary read-only native hit-path probe, log
`siteforge-native-authorized-hit-path-20261102.log`; do not duplicate or edit
source/tests during collection. One initial diagnostic attempt was stopped
early (exit75) to guard absent-element reads; it is not acceptance.
Prior receipts show ordinary175% page zoom
persisting into RDM (requested548×516, evaluated313×294). Replay resets zoom
through the actual View menu, retaining exact dimension/pixel assertions.

Two external runner terminations have OS reason0xbaddd15c; both exact-PID OS
logs explicitly name CacheDeleteAppContainerCaches. Storage is about5–6GiB free. Owner asked to
free space while focused work continues; no cache/evidence cleanup or service
changes. Native Header remains failed. Earlier prohibition on further native
host/control/AX experiments is preserved. The owner's “yes” authorizes the single
read-only actual-hit-path diagnostic in OD-029, after the active browser run ends.
No host replacement is authorized or planned.

The single stable-source `./sf verify` completed, exit65: repository/build pass;
unit880/886 pass (6 failed), UI146/170 pass (21 failed,3 owner-session skips).
Combined1026 passed/27 failed/3 skipped. No source/test changes occurred during
collection. Authoritative result `full-1c824ea6-059e-4c75-9e65-18fc5d8f9378`;
log `siteforge-full-inventory-20261102.log`. That full collector is finished.
See [the complete ordered A/B/C inventory](evidence/SF-LOCAL-BUILDER-FULL-INVENTORY-20261102.md)
before repairs. Two missing console outcomes are signal-killed runners, not
passes. Strict browser pixel journey passes1011.238s in this inventory, and
final grid/artboard passes44.329s. Native Header pointer still fails; component
search has reproduced horizontal overflow. No further speculative host/control/
AX experiments. Fix proven product/test boundaries with exact focused replays,
then final green verification and reviewed commit/push. Ignored audit/archive
and coordinator materials remain preserved/excluded. No Git write occurred.

The launch note below and subsequent sections are historical receipts.

### Full inventory launch receipt

Preserved main at ba34293 plus accumulated dirty work; owner authorizes reviewed
commit/current-main push only after required gates are green. Browser correction
is integrated in `ConnectedPageOutput.menuCSS`, with no runtime/document change:
intrinsic details-content grid overlap and canonical panel alignment, legacy
positioning only under feature detection. Focused compiler checks pass2/2.
Strict `testGeneratedWebsiteMenuEscapeStateAndPaintJourney` passes1/1,822.330s,
`focused-01d348fd-ecd6-45e0-a32f-8e6b3474ba13`: Header/Footer320/430 each return
0/33600 changed pixels (allowed33), wider768/destination checks pass. Nine key
originals inspected in temporary `siteforge-overlay-browser-passing-20261102`;
open/closed panels and focus are visually correct, titles truthfully ellipsize.

Native Header ordinary click STILL FAILS. Real-host geometry regression passes
(0.036s), but pointer probe fails45.617s in `focused-5f879618-5042-485f-b2bf-4820fe2d6a5e`.
Removing intermediate row clipping also fails the pointer probe in
`focused-c546046d-8ce0-4a4a-a4fd-de7c483d64e6`; that ineffective production
experiment is removed. Do not claim the26/24-point discrepancy proves the cause.
No further speculative native host/control/AX experiments are authorized.

Next/active job: one stable-source `./sf verify` full failure inventory, log
`siteforge-full-inventory-20261102.log`. Do not start an overlapping collector
or edit source/tests while it runs. Preserve actual failed statuses; classify
all inventory failures before focused repairs and the final authoritative gate.
Earlier notes below are historical. Ignored audit/archive and coordinator
materials remain excluded/preserved. No commit/push has occurred.


## Post-setup continuation —2026-11-02, acceptance still in progress

Owner installed Xcode's components. Readiness exits0; the exact fixture passed
1/1,0.057s in `siteforge-post-setup-menu-fixture-20261102.xcresult`.
Shared output now uses intrinsic details-content grid overlap when supported,
with canonical start/center/end alignment and old positioning only as a detected
fallback. Runtime/document unchanged. Production fixture plus overlay checks
passed2/2,0.116s (`focused-f5d15c97-bf06-4f7f-9513-9cf65080cfab`).
Private real Header/Footer at320/430/550 closes visually; Footer opens upward,
Space reopens, About navigates correctly. Matched-pointer Header430 interior
returns0/33600 changed, Footer3200/33600, Footer43013/33600 (allowed33).
Initial unmatched-pointer Header crops exceed tolerance and remain diagnostic,
not passing evidence. Full strict native/browser acceptance is still required.
First strict browser replay failed before pixels because Inspector AX truncated
its long JSON string (`focused-278198d9-ba1e-4f09-b9e8-ea341f299e20`,86.051s).
Helper now transfers complete bounded console chunks; a changed-helper run is
underway. Do not duplicate it. No full gate, commit or push yet.
The independent local audit/artwork archive remains ignored and excluded.


## Current full-closeout boundary —2026-11-02

Owner authorized testing and a reviewed current-branch push, but acceptance is
not green. Repository checks passed, exit0. The single serial focused
`InsertionModelTests/testManagedHeaderFooterMenuReproductionUsesRealRoutesAndUnchangedRuntime`
attempt launched its host but executed no test method. Sampled main thread:
`XCTestDriver._prepareTestConfigurationAndIDESession` → `XCTFuture` → `XCTWaiter`.
Native Xcode displays “Install Required System-wide components” (Quit/Install).
See OD-028: owner completes visible setup/authentication; no toolchain/service
or privacy changes by the agent. Do not assume this proves every prior failure.
The exact xcodebuild PID85433 was interrupted then terminated, exit143; its
host85775 exited. No duplicate test, full verification, commit or push.
Retained temporary evidence basenames:
`siteforge-full-closeout-fixture-20261102.log`,
`siteforge-full-closeout-fixture-20261102.xcresult`,
`siteforge-full-closeout-host-sample-20261102.txt`, and
`siteforge-full-closeout-repository-20261102.log`.
After owner setup, resume the exact fixture, private Footer/full-panel/width
proof, strict native pointer correction and only then the full closeout gates.
All preceding popup failures remain unresolved; excluded owner/coordinator
files and the two ahead commits are preserved, not yet cleared for publication.


## Targeted overlay candidate —2026-11-02, incomplete/external runner boundary

No production CSS/runtime change. One private grid/details-content candidate
and its scoped-margin refinement visibly close the minimal Header popup with
pointer and Space/Escape, retaining Header/page bounds. Refined open/closed
summary Y delta0.438CSSpx; left former-panel crop open1081/6300, closed0/6300.
Eight new originals inspected. NOT full-panel, Footer,320/430/wider or013 proof.
New exact `InsertionModelTests/testManagedHeaderFooterMenuReproductionUsesRealRoutesAndUnchangedRuntime`
compiled but executed0: sampled test host waits in XCTestDriver's IDE-session
preparation, no method entered. Result `focused-04359f9f-d785-44fa-9dea-d2448e410b55`;
interrupt left xcodebuild stuck with SchemeActionResultOperation warning, then
only its verified PID83875 terminated (exit143); host84055 already exited.
No retry of unchanged initialization. Log `siteforge-menu-overlay-fixture.log`,
sample `siteforge-menu-overlay-host-sample.txt`. Candidate and full-observer
assets preserved privately in the same reproduction directory/README below.
No active run/server/new tab. Strict failures and43-code/7of8-native historical
scope plus the preceding separate1/1 diagnostic remain unchanged.
Next bounded work requires the exact fixture method to execute, then Footer,
exclusivity, destinations, measured-width and strict-pixel proof BEFORE shared
output integration. Do not claim that preliminary candidate is a shipped fix.

## Minimal reproduction closeout —2026-11-02, acceptance unresolved

Source audit found live `result.dom=state()` and separate cached event history;
no proven crop/query cause. New exact
`InsertionModelTests/testMinimalManagedMenuCompilerReproductionPreservesRuntimeAndDocument`
passes1/1,0.034s, result `focused-f7087ab2-0fab-41d4-9b02-3bb5b8a1a716`.
Private real-compiler one-Header/one-link artifact and unchanged runtime retained
under temporary `SiteForgeMenuReproduction-41F1A718-E32B-48C3-8474-9E630892498A`.
Uninstrumented generated case still shows panel after real Escape with AX off.
Generated observational variant displays live closed/expanded=false/focused=true,
trusted Escape and one menu in the same screenshot that still shows its panel;
adding the readout did not fix it. Stock plain and observed controls close
visibly. Changing only generated popup position:absolute to static also closes
visibly, but alters popup placement and is NOT an acceptable product fix.
Keeping position:absolute unconditional still leaves residue. Thus absolute
popup rendering is a proven relevant condition, not yet a safe production fix
or a specific WebKit/capture root cause. No more experiments in this task.
All18 valid originals reviewed (one additional failed-navigation capture is
preserved/excluded); readout reports actual547×515, nominal RDM548×516 at100%.
The private artifact README contains the six-case matrix, exact differences,
portable reproduction, screenshots and cleanup. New diagnostic tab closed,
server stopped, original320×820 failure tab preserved. No process left active.
No production correction, new UI-test launch or broad verification. Historical
43-code/7-of8-native scope unchanged; new diagnostic code pass is separate.

## Same-artifact presentation comparison —2026-11-02, unresolved

Ordinary Safari and RDM were independently inspected on the same cached private
artifact at an actual548×516 CSS viewport, explicit main-page Inspector context,
with no reload or production mutation. Both still show menu panels after trusted
Escape despite closed DOM/AX state. A later RDM capture322s after closure retains
the residue. This rules out an RDM-only explanation, not a specific compositor or
capture cause. No safe production correction is established; stop new speculative
experiments and retain the strict failed pixel gate. The compact comparison UI
method compiles, but two launch attempts executed zero tests (automation-mode
initialization timeout). Native observations are not XCTest passes. Detailed
context, original-image names, metrics and cleanup are in
[the comparison receipt](evidence/SF-LOCAL-BUILDER-012-016-FOCUSED-ACCEPTANCE.md#same-artifact-native-safari-presentation-comparison--2026-11-02).
No runner remains active. Full verification is required but deferred; no Git,
install, owner data or coordinator files changed. Primary native7/8 and distinct
passing code43 remain unchanged. Earlier receipts below are historical.

## Newer Escape correlation receipt —2026-11-02

FINAL: the new actual-pixel gate fails1/1,106.962s in
`focused-8bc86f35-54f4-494c-985e-15d9244794b0`:1855/33600 former-panel
pixels differ after Escape (allowed33), while DOM/focus/hit checks pass. A unique
visible fixture prefix rules out an older Home document; the exact recording
frame shows the same residue. Earlier assertion-only passes below are NOT the
current method's acceptance. No active run; no accepted visual fix. Preserve
this failure and the pixel gate. See the focused receipt's Final pixel gate
section for original filenames, interrupted scaling attempt and next bounded
same-artifact/non-RDM investigation. No full gate/Git/install was run.

Actual runtime delivery/execution and trusted Escape closure/focus are proven;
visual closure is NOT. Screen-before-Inspector comparison passes1/1,243.967s
at320/430/768, but all four original closed-state images still paint panels.
Explicit closed CSS did not fix it and is removed. No runtime/CSP/host fix is
retained. See the newest section of the focused acceptance receipt for exact
results, hashes, filenames and rejected experiments. New root/nested HTTP unit
passes; distinct code evidence43, primary native7/8 unchanged. Do not replay
native Header, denied AX discovery, full gate, Git/install or owner data.
The following paragraphs are older receipts, not newer conclusions.

## Current focused acceptance authority —012–016

### Latest bounded pointer/browser closeout —2026-11-02

No run active. No production control/host rewrite retained in this continuation.
Header ordinary XCUIElement.click fails (two short46s probes), not just its
readiness Boolean. Footer ordinary click, Down/Escape/focus and About navigation
work independently. Native control/window/app hit results and native↔XCUI
coordinates agree; external public hit API returns-25211. A borderless-fit
hypothesis failed its exact unit check and was removed with its diagnostic test.
All temporary native observation is removed; working focus/modal fixes remain.

Current native-control regression passes1/1,0.628s. Browser-only companion
`testMeasuredSafariNarrowChromeBoundaryCompanion` passes1/1,167.058s in
focused-f763b692-92bb-4b29-8840-4ade17445037. It measures actual CSS320/430/768,
real Header/Footer clicks/focus and narrow About destinations. Real Safari Width
uses a unique label/title (no identifier) and one measured one-pixel correction,
not universal+1. Strict013 shares that query correction; all native behavioral
assertions remain intact, with no long013 rerun. Final build-for-testing passes.

NOT visually accepted: after-Escape screenshots still paint menu panels despite
passing focus checks. Do not claim closure or infer JavaScript/paint cause.
All nine final originals were inspected; names/results are in the current receipt.
Long titles ellipsize. No universal/full-title/larger-text usability claim.
Primary native7/8 and current distinct passing code42 unchanged; three extra
diagnostic UI methods are separate (only browser-only method has a whole-method
pass). No full gate, Git/install, owner data or coordinator files touched.

Smallest next bounded task, not automatically authorized: correlate actual
details.open/aria-expanded/script-load state around Escape; obtain remote Header
versus Footer AX hit identity only through an already-authorized public client.
No privacy change, new host/control rewrite or unchanged long retry is justified.
The paragraphs below are preceding receipts and do not negate this newer result.

No run remains active. Preserve all dirty work and owner/coordinator data. No
full suite, ./sf verify, Git/install/signing, new host or017 is authorized.

The approved AppKit Preview-host experiment failed actual013 and is removed,
including its two retired diagnostic tests. Original SwiftUI document-modal
hosting remains. Its archival passes do not increase current product coverage.

The subsequent ONE correlated dispatch trace is complete and all temporary
observation removed. Down reaches the correct active Preview sheet with Function
only, but the SwiftUI KeyViewProxy does not open the Menu. No native-follow or
browser opener action fires. The earlier apparent Safari transition was an
imprecise video frame from after teardown, not the key activating Safari.

Retained bounded correction: one genuine NSPopUpButton/NSMenu owns native first
responder and labels its actual accessible cell, with a live screen-coordinate
activation point. No role/frame/window spoof, global interceptor, key forwarding,
canonical model or Safari/compiler/export change. Real Header Down opening and
Escape focus now pass. Initial pointer hittability STILL FAILS; strict assertions
are preserved. Footer activation/destinations and measured-Safari tail remain
unreached;013 is NOT accepted.

Final exact control/modal checks pass2/2 in
focused-1008cad5-c590-46de-a56f-82fa6a7204b6; one new current code method brings
distinct passing code evidence42 versus the original41 baseline, not a42-test
run. Historical native baseline remains7/8. Latest exact013 result
focused-a8ed2b38-bbec-4b0b-a0a2-f950b5f943a0 fails84.206s at initial hittability.
Named originals/recordings, exact methods, all failures and corrected frame times
are in [the current receipt](evidence/SF-LOCAL-BUILDER-012-016-FOCUSED-ACCEPTANCE.md).

Do not replay authentication prompts, revive the rejected host, run unchanged
long tests or waive pointer readiness. No framework fault, lock, privacy issue or
user interference is inferred. All modules/items stay Partial/IN PROGRESS.
Full verification and installed delivery remain mandatory but deferred/not
authorized. Actual larger-text runtime review remains unperformed.

## Historical source-only boundary —007–016 local-usability closeout

016 source integration and independent re-walk are finished; acceptance remains
deferred. Read the [single current acceptance matrix and exact source fixes](evidence/SF-LOCAL-BUILDER-016-SOURCE-INTEGRATION-CLOSEOUT.md)
and first queue entry. Legacy Design strings now retain captured draft ownership,
clean-only navigation never commits, and Save/Preview preflight submits valid
owned input before snapshot. Retained Preview artifacts check live project
identity at action boundaries; Check Website preserves an active local write.
Seven new code methods and one refined existing015 native journey are UNRUN.
All later012–016 source totals30 new code/four distinct native journeys UNRUN.

Remaining checkpoint work is acceptance-only, not017 or an unresolved product
decision. Ready to REQUEST separately bounded acceptance authorization; do not
execute it automatically or replay historical authentication requests. No tests,
build/parser/lint/check/verify, collectors, app/browser/UI/screenshots/performance,
commit/push/GitHub/install/sign/release/schedule, owner project/resource/recovery
or coordinator-ledger changes. Full verification stays mandatory before DONE.
Modules stay Partial;007–016 IN PROGRESS. Preserve all dirty work, owner Aurora
gradient/site/resources and frozen evidence; OD-018/019 remain unchanged.

Everything below is historical context, not current execution authority.
Old “current”, “next”, running/pending and authorization statements describe
their dated boundary only; the summary above and016 matrix take precedence.
No execution or new authentication request was initiated by016.

## Historical —015 repair workflow SOURCE ONLY

Read [015 evidence](evidence/SF-LOCAL-BUILDER-015-PREVIEW-REPAIR-WORKFLOW.md)
and first queue entry. Source implementation/second review finished. Preview and
Check Website share exact receipt/context/clean-editor target navigation and
existing page/original/Layers adoption, with actual editor focus/scroll request.
Findings and last successful artifact have separate identities; Export guards
remain immutable and Refresh explicit. Five new code methods and one native
journey are UNRUN. No compile/test/check/visual/verify receipt. Keep015 IN PROGRESS,
modules Partial. No execution/apps/browsers/screenshots, commit/push/install/sign,
owner project/recovery changes, coordinator edits or016. Prior007–014 and frozen
acceptance remain preserved, not proof for015. No current runner/authentication
request. Next bounded work is same-scope acceptance only when separately approved;
do not replay historical prompts or automatically start it.

## Historical —014 stable Inspector SOURCE ONLY

Read [014 source evidence](evidence/SF-LOCAL-BUILDER-014-STABLE-INSPECTOR-LAYOUT.md)
and first queue entry. Source implementation/second usability review finished.
Measured labels and font height, bounded pane allocation, shared section framing
and identity-stable adaptive fields/actions refine the selection header and three
representative surfaces. Four code methods and one native journey plus one
affected existing test are UNRUN. No build/check/visual/verify acceptance.014
stays IN PROGRESS and modules Partial. No execution, apps/browsers, commit/push,
install/sign/release/schedule, owner project/recovery edits or015. Preserve all
007–013 work, frozen receipt, coordinator files and OD-018/019. No pending runner
or authentication request. Next recommendation is a final same-scope compact/
scaled-control review, not a new feature or authorization to execute acceptance.

## Historical —013 narrow chrome SOURCE ONLY

Read [013 source receipt](evidence/SF-LOCAL-BUILDER-013-NARROW-CHROME-LAYOUT.md)
and first queue entry. Shared final allocation/static/fluid CSS reserve Menu
space before default title shrink. Custom intent and command/data ownership
remain; bounded guidance and availability-aware menus avoid fabricated usability.
Nine code methods and one native/Safari journey are UNRUN.013 IN PROGRESS, modules
Partial. No tests/builds/checks/app/browser/UI/verify/commit/push/install/sign,
owner-data mutation or next dispatch.012 and the frozen title receipt below are
preserved, not evidence for013. No new runner/authentication request is pending.
2026-11-01 continuation finished source consistency and both usability passes.
Actual destination availability now drives width reservation/preflight as well
as Menu display; empty links have no slot and broken links retain disabled intent.
Same9+1 tests refined, UNRUN. Source implementation is finished;013 is not DONE.
Deferred acceptance includes compile/focused results, Footer/compact/native/
measured-browser originals and final verification. Do not start014 or execution.

## Historical —012 usability/language SOURCE ONLY

Targeted title repair finished: six exact code methods pass, matched native/
Safari journey passes205.263s; final `focused-4cb5a055-d0fc-4c60-b300-8c405153fef0`
passes3/3. All15 originals inspected; actual CSS1440/430/320,scale1. Read frozen
focused receipt for paths and precise remaining navigation/browser limitations.
No runner remains. Earlier70/70 and eight native receipts remain historical
acceptance, not proof of later source edits. Four source passes under
SF-LOCAL-BUILDER-012 are implemented and source-reviewed: fewer steps, plain
language, shared hierarchy and a full source re-walk. Read
[012 source evidence](evidence/SF-LOCAL-BUILDER-012-USABILITY-AND-LANGUAGE.md).
Five new code methods and one native journey are UNRUN. Source changes include
direct formatting commands, visible asset import, shared labels/search aliases,
matching site-settings entry names and explicit Settings scope. The completed
source continuation clarifies component original/copy/reset counts and recovery,
fallback-only default contents, reusable solid-color/opacity samples and
responsive review/reset/conversion. Direct original editing now works from
Content using the existing command and ID; original/copy return is guarded.
Read both wording and surface-coverage tables. No build or
visual acceptance exists for this package. Keep012 IN PROGRESS. ALL execution
remains paused: no tests/builds/checks/lints/collectors/
readiness/UI/app/browser/performance/verify or automatic final cycle. No commit,
push, installation, signing, owner project/recovery change or next dispatch.
Do not automatically start later acceptance or replay old authentication requests.

## Historical authority — bounded 007–011 focused acceptance, before012

Owner approved compilation and exact new/minimally affected tests, targeted
repairs and original-resolution visual inspection. This supersedes the source-only
execution holds preserved below, not their historical results. Read the
[exact manifest and current results](evidence/SF-LOCAL-BUILDER-007-011-FOCUSED-ACCEPTANCE.md).
No broad/whole-target testing, ./sf verify, commit, push, installation, signing,
owner package/recovery mutation or next workflow. Keep all five IN PROGRESS;
full verification remains deferred. Do not replay old authentication requests.

Latest focused code group is green70/70 (56 new+14 affected existing), result
`focused-e9ba0e1d-6657-444c-9e5b-4ebd7d85d2c7`. Current2026-10-30 native runs
initialize: all eight distinct journeys pass, three compositor and three HTTP
regressions pass, and all corresponding originals were inspected. Final result
`focused-daa8beb2-fec8-4330-a774-06f19775eaee` passes4/4; no runner remains.
Named-page Preview is fixed. These earlier runs exposed the title mismatch later
resolved for the measured current-Safari path in the frozen receipt above.
Broader browser parity and full verification remain deferred, not waived.
Do not rerun unchanged focused groups or dispatch another workflow.
The following authentication handoff is historical, not a fresh blocker.
Native `focused-3ffd3675-fe21-4621-b103-99688380ec8e` passed the isolated
no-change code regression but executed zero UI methods: new coreauthd XCTest
Enable UI Automation request18:03:28-0400 timed out18:04:28. Owner was notified
during that run. No screenshots/visual acceptance. Do not retry unchanged or
infer a locked screen. Historical next step, now superseded by the012 hold:
authentication: exact `SiteForgeUITests/SiteForgeLaunchTests/testCustomResponsiveViewportWidthEntryComparisonAndCancellationJourney`,
then the remaining manifest native journeys serially. No broad gate/commit/push.

## Historical authority — SF-LOCAL-BUILDER-011 connected fluid output, source only

No tests/builds/checks/lints/scripts/collectors/readiness/UI/app/browser/
performance/verify, commit/push/install/sign/release/schedule or next prompt.
Do not request lifting the hold. Workflow011 is not an execution checkpoint.

Read [011 source receipt](evidence/SF-LOCAL-BUILDER-011-CONNECTED-FLUID-OUTPUT.md).
Existing compiler/allowlisted scalar/container policy now owns the supported
fluid connected CSS/semantic-layout path; precise unsupported combinations
remain blocked before any complete plan. Eleven code methods and one native
journey are UNRUN, not compile/browser/visual evidence. Keep011 IN PROGRESS.
Future focused execution, normal/compact originals and measured-width Safari
review plus mandatory ./sf verify are deferred, not waived.
Preserve007 partial failures/latest unverified fixtures;00810+1,00915+1 and01011+2
UNRUN receipts; historical936 passes accept only ba342938. Owner revision245,
native gradient/resources/recovery, ordinary installed app, OD-018/019 and all
coordinator/artwork/evidence files remain unchanged. No cleanup or next dispatch.

## Preserved010 context — page-chrome reuse, source only

No builds/tests/checks/lints/scripts/collectors/readiness/UI/app/browser/
performance/verify, commit/push/install/sign/release/schedule or automatic next
prompt. Do not request lifting the hold. 010 is a local workflow ID, not the
historical ten-prompt execution boundary. Source edits/read-only inspection only.

One native Page/Header/Footer action now prepares independent add-missing copies
through the shared page clone, existing resource validation and one central batch.
Existing roles/inbound references remain intact; no replacement/merge or global
linked-chrome model. Eleven code methods and two native journeys are UNRUN.
Read [010 source receipt](evidence/SF-LOCAL-BUILDER-010-PAGE-CHROME-REUSE.md) for
exact selectors and deferred acceptance. Keep010 IN PROGRESS. Future compile,
focused model/native/normal-compact visual and Safari review plus mandatory
./sf verify remain required, not waived. No current success receipt exists.
Preserve007's failed partial results/latest unverified fixtures,008's10+1 and
009's15+1 UNRUN source, owner revision245/resources/recovery/gradient, normal
installed app, OD-018/019 and coordinator/artwork files. No cleanup authorized.

## Preserved009 context — formatting reuse, source only

The renewed no-execution hold remains. Do not build, test, check/lint, launch
apps/browsers/UI, verify, commit, push, install, sign, schedule or dispatch another
workflow. Source edits/read-only inspection only; do not ask to lift the hold.

009 source uses one closed canonical family envelope, background existing-resource
validation, central Design property-batch preparation and native Edit/Inspector
actions. Fifteen code methods and one real-control journey are UNRUN. Read the
[009 receipt](evidence/SF-LOCAL-BUILDER-009-FORMATTING-REUSE.md) for exact symbols,
reference/no-op/identity semantics and deferred live/visual acceptance. Keep009
IN PROGRESS. Prior007 partial failures and008 source-only evidence remain valid
context; ba342938 owns only the historical baseline. Preserve all dirty work,
owner revision245/resources/recovery, OD-018/019 and excluded owner-local files.

## Preserved008 context — renewed source-only hold

Owner direction2026-10-29 supersedes the prior direct testing approval: keep
NO TESTING. No builds/tests/checks/lints/collectors/readiness/UI/app/browser
acceptance/verify, commit/push/install/sign/schedule. Do not ask to lift this hold
or dispatch another prompt. Source edits and read-only inspection only.

008 extends007's existing actor-backed comparison with measured horizontal
Review suggestions and exact-node/width navigation into ordinary Layout controls.
Read [008 source evidence](evidence/SF-LOCAL-BUILDER-008-RESPONSIVE-LAYOUT-REVIEW.md).
Ten new model/integration methods and one native journey are UNRUN. No canonical
audit store/suppression, schema, auto-fix or second responsive engine is added.
SF-0606 remains Partial;001/005 persistence/suppression scope is not completed.

007 really WAS built. Historical3133a465:9 methods,3 passed/6 failed; after
structural/owned-path corrections d3dafe44:6 methods,4 passed/2 failed (viewport
initialization then dependent assertions). Latest source adds real viewport
resize before the two text/selection fixtures. No rerun is authorized. Artifacts
remain retained, no runner is active; do not claim nine UNRUN or current passes.
007's UI source remains unexecuted. Prior fully accepted ba342938 still owns
the936-pass baseline only. Preserve all dirty work and owner artifacts.

## Preserved007 source workflow context — not acceptance

Preserve the uncommitted custom-responsive-width implementation and all owner
artifacts. The preceding accepted batch is committed locally at ba342938; its
test results are baseline only. No process is running for this source workflow.

Read [current source receipt](evidence/SF-LOCAL-BUILDER-007-CUSTOM-RESPONSIVE-WIDTH.md)
and the first queue item. Width lives only in CanvasViewportState bounds;
presets/ranges and existing cascade are reused, not replaced. Actual width feeds
Inspector/layout/insertion/native Preview; four-sample comparison is asynchronous
and guarded against stale scope/generation. Nine model/integration tests and one
real-control UI journey have the partial execution described above. Modules stay
Partial;007/008 stay IN PROGRESS pending separately approved acceptance.

Current hold: no tests/builds/check scripts/lints/collectors/verify, UI automation,
app/browser acceptance, commit/push/GitHub/install/sign/schedule/new workflow.
Only source edits/read-only review are authorized. Future owner-approved compile,
focused acceptance, original-resolution normal/compact visual review and mandatory
./sf verify remain required. Do not replay historical authentication requests.
Preserve Aurora/Dark Flow revision245/resources/recovery/gradient, OD-018/019 and
the three excluded owner-local files. No next feature or new prompt is authorized.

## Historical local acceptance checkpoint — 2026-10-28

Final ./sf verify exits0 on the reviewed source batch:939 total,936 passes,
0 failures,3 intentional owner-session skips;785 non-UI and151 UI passes.
Result: full-e7ee511e-a6f5-4449-a0dd-15680fe3a7c8.xcresult, matching log under
ignored source-batch-20261027-acceptance/results. Security, traceability440,
architecture, build and focused3/3 corrections passed. Nine corrected originals
were inspected; see the integration evidence for all exact paths/findings.

The approved action is one reviewed LOCAL checkpoint commit after final
documentation/hygiene checks. No push, installation, new feature/prompt11,
schedule or owner-project mutation. Preserve/exclude coordinator-owned notes
and superseded Aurora bitmap/prompt; report those intentionally uncommitted.
Normative modules remain Partial; OD-018/019 and broader owner delivery are not
resolved by this bounded batch. Seventy-two runtime QoS warnings remain observed;
do not claim they are eliminated or invent a new app-owned call path.

All pending/hold/authentication and failed receipts below are historical.

## Historical policy and receipts — superseded by the verified checkpoint

LATEST: authentication resolved by owner; corrected three pass3/3, result
`focused-07cad6e0-4c7b-46f8-a4ad-30572e50049a.xcresult`. All nine originals
were inspected. Final coherent ./sf verify is next; source/docs frozen during
execution. No current authorization blocker, duplicate runner or local commit.
Commit locally only after a genuinely green gate/review. No push/install.

CURRENT owner-only boundary,2026-10-28: three remaining full-gate UI failures
have bounded test-interaction corrections, compiled successfully. Focused
`6c4a1ac5-8556-4392-a72c-d4d7bc602622` then failed initialization before any UI
method: fresh testmanagerd “Enable UI Automation” LA request at11:21:49-0400,
timeout11:22:49. No runner remains. Owner presence/system authentication during
ONE isolated retry is required; do not replay tests unchanged or claim acceptance.
No commit/push/install. Exact evidence and safe next step are in the integration
receipt; all previous holds/waiting statements below are historical.

2026-10-28 authoritative finished receipt: full8731db4c FAILED,939 total,
933 passed/3 failed/3 intentional owner-session skips; non-UI785/785 passed,
UI148 passed/3 failed/3 skipped. Three bounded UI interaction repairs are now
being verified: reveal fluid Enable inside the Inspector, reveal Site Settings
fields inside the native form before requiring focus, and allow the structural
Page structure row while retaining zero authored-object/ghost assertions.
Failure originals/hierarchies were inspected; no product geometry, state,
timeout or assertion weakening is justified. Seventy recurring QoS warnings
remain observed; no unsupported source attribution or elimination claim.
Finish affected three, inspect changed originals, then one final ./sf verify
and reviewed LOCAL commit only after green. No push or installation. This
receipt supersedes older pending/authentication text below.

CURRENT RESULT (supersedes waiting text below): native shell readiness passed
1/1. All twelve new/prerequisite UI methods now passed affected acceptance after
targeted corrections. Visual review additionally caught missing structural Root
paint and incorrect calibrated-RGB conversion. Shared page-surface rendering and
explicit sRGB now pass four exact native paint tests plus Page Background UI5/5.
See evidence/SF-SOURCE-BATCH-20261027-10-INTEGRATION.md for results and inspected
original screenshots. Finish Preview digest regression, reconcile docs, then
one coherent final full gate and reviewed local commit only if green. Nothing
pushed or installed. Historical failed-run/hold paragraphs below are superseded.

The owner explicitly approved full local testing, fixes, and a local commit.
This supersedes the earlier hold for the preserved Page Background and ten-item
source batch. Finish Preview/export integration, run current-source verification,
repair affected failures, review and commit only after green. No push, GitHub
operation, installation, publication or scheduled follow-up. Older run/authentication
instructions below are historical evidence, not instructions to replay. No current
acceptance result or completion is claimed yet.

Latest current-source attempt FINISHED, exit65: repository/security/traceability/
architecture/build pass; non-UI784 executed,781 pass,3 failing methods. Those
three are now corrected and pass affected3/3 (shipping text-system initializer,
cancellable manual recovery review, validated recovery replacement fingerprint).
Five new integration methods pass5/5. UI executed0: testmanagerd logged XCTest's
Enable UI Automation authentication request and timed out enabling automation.
Owner presence requested for ONE isolated retry; no lock state inferred, no
unchanged full rerun. No active runner, local commit, push or installation.
Read evidence/SF-SOURCE-BATCH-20261027-10-INTEGRATION.md for exact artifacts.
Next: owner-present isolated native readiness, then changed-state UI/visual
acceptance, one coherent final full gate, review and local commit only if green.

## Historical — SF-LOCAL-BUILDER-006 Aurora Dark Flow

Development-only continuation implemented Page Background discoverability in
source (not built/tested). Read evidence/SF-LOCAL-BUILDER-006-PAGE-BACKGROUND.md:
exact Root navigation, reused fill/gradient/token controls, atomic None, truthful
structural visibility, six UNRUN acceptance methods. Source now differs from the
historical frozen partial gate; do not attribute its passes to these edits.
Testing hold still applies to every test/check script/build-for-testing/UI or
manual acceptance action. No launch/install/sign/commit/push. Await explicit
approval before compilation and the six named selectors; keep006 IN PROGRESS.

**OWNER HOLD ALL TESTING — effective immediately, 2026-10-27.** Do not run unit,
integration, UI/readiness/visual tests, collectors or verification until explicit
owner approval. No install on incomplete verification. No new feature/commit/push.
The authoritative authenticated run was safely cancelled via SIGINT to its exact
owned xcodebuild77761; collector80878 exited75. No runner/collector remains.
Result: 733 non-UI +100 UI passes, three declared owner-session skips, one UI
cancellation (not a product assertion), 38 UI methods not reached. Artifact
`dark-flow-authenticated-final-results/full-006e2c73-8f20-4cd8-916d-c8736ec2cddb.xcresult`.
Full gate is NOT green. Installed app unchanged; all owner data/evidence preserved.
Only safe non-testing inspection/documentation is allowed. Earlier automatic
verification/install plans below are historical and superseded by this hold.

Readiness now demonstrated after owner authentication: exact native shell test
passes 1/1, zero failures/skips, artifact
`Test-SiteForge-2026.10.27_01-10-46--0400.xcresult`. macOS automation state changed
to enabled; SiteForge genuinely launched. No runner remains. Source fingerprint
unchanged4b3301f6…, 23 GiB free. Freeze this reconciliation for ONE ordinary-
identity final ./sf verify, then approved safe owner-local install only if green.
Do not duplicate, edit beneath the run or replay authoring/browser review. Prior
startup timeout/waiting notes below are historical. No repository startup fix
was necessary or justified; owner completed the actual system authentication.

Latest reconciliation: the exact native readiness comparison FINISHED, not
waiting. Bundle `Test-SiteForge-2026.10.27_00-55-21--0400.xcresult` records zero
UI methods executed and one automation-mode initialization timeout. Xcode Stop
is disabled; no collector/xcodebuild/UI runner remains. Previously inspected
authentication dialog is no longer available. No authentication success is
inferred. Native Xcode now reproduces the CLI startup boundary; no repository
configuration correction is supported. Next requires an owner-present single
native-method attempt with completion of the actual macOS authentication dialog,
not another full run. Do not launch until that owner-assisted step is coordinated.
No installed update, source edit, commit or push. Earlier waiting text is historical.

Current native readiness comparison: exact shell practical-minimum method started
through Xcode Test navigator; build completed. Runner75613 is awaiting the actual
visible macOS UIAgent dialog “XCTest is trying to Enable UI Automation.” Owner
asked once to complete Touch ID/password in macOS only. No test method has run
yet; no duplicate/full run or app install. Inspect this exact session first.
The older no-runner statement describes the completed CLI run, not this native
comparison. Same scheme/destination/ordinary identities; no invocation fix proven.

2026-10-27 current boundary: the post-cleanup collector completed, NOT green.
733/733 non-UI passed; UI runner initialization timed out enabling automation
before any UI method executed (one infrastructure failure, zero skips). No
collector/xcodebuild/UI runner remains. See latest 006 evidence for the exact
artifact. Source fingerprint remains 4b3301f6…. Do not repeat an unchanged broad
run or install the app. OD-026/027 remain resolved; this is not a renewed owner
permission request. Existing installed build is unchanged. All older pending
run/decision paragraphs below are historical, not current instructions.

Owner decisions OD-026/027 are now resolved: local-only ad-hoc signature after
green verification, and build-cache cleanup only. Approximately 1.7 GiB of seven
ignored regenerable intermediate/module-cache directories removed; all evidence,
projects, recovery and app backups/products preserved. No process was active.
Source remains 4b3301f6…. Reconcile then run ONE post-cleanup full gate; do not
duplicate it or edit beneath it. After green use existing safe owner-local install
workflow; no commit/push. Earlier STOP/pending-decision paragraphs are historical.

STOP/HANDOFF at owner decisions OD-026/027, not an unfinished runner: isolated
asset retry passes 1/1 (99.566s), unchanged source4b3301f6…. No app/test/xcodebuild
process remains. Full gate still 871 passed/1 OS-cache-delete runner kill/3 skips,
exit65; do not call complete or silently retry broad coverage. Docs/whitespace/
440-record traceability reconciled. Preserve all 85 dirty entries and owner data.
No cleanup/install/signing/commit/push occurred. Read latest 006 evidence and owner
answers before next action; earlier active/failing notes below are historical.

Latest frozen full run FINISHED: 733 non-UI + 138 UI passed; one external runner
SIGKILL; three owner-session skips (871/1/3 total), exit65. No product assertion
failure. Source 4b3301f6… unchanged. Bundle full-a222e0fc-7144-40ab-a9aa-a954a7421ac8.xcresult.
System log proves cache_delete requested CacheDeleteAppContainerCaches termination
of runner49948 at 02:27:30, not lock/authentication/app diagnosis. Remaining tests
completed after Xcode runner restart. One isolated interrupted-asset retry runs;
do not duplicate or repeat broad suite. OD-027 storage/evidence retention choice
and OD-026 local ad-hoc-signature choice are pending; no deletion/install/service
change/commit/push. Read latest 006 evidence before acting. Earlier notes historical.

Newest: all nine formerly failing UI methods now pass focused coverage; two
affected model methods pass. Native menu host observes current command state.
Rename's stale focused edit value is cleared before sheet dismissal; failure
diagnostics proved Text editing after no sheet, passing route is Grouped Edit.
Exact history/persistence assertions retained; no blanket Undo or lifecycle patch.
Corrected rename/nesting original-resolution screenshots reviewed. Freeze one
final full gate after reconciliation; installed refresh additionally needs local
ad-hoc-signature policy clarification (question sent, no signing/install done).
No commit/push. Historical active/pending failures below remain audit evidence.

2026-10-26: full ordinary-identity gate FINISHED, not green: 861 passed, 10 failed,
3 owner-session skips (731/732 non-UI; 130/139 executed UI). No agent cancellation.
Artifact full-a85a5d73-bc20-4115-96c6-dac8cb500538.xcresult. The two original
journeys and earlier cancelled Button/Link coverage pass. Privacy substring
collision corrected with content-independence equality (focused 1/1); exact
clear-selection/sibling/nesting model passes 1/1. Recorded Footer field remained
keyboard-focused at Undo. Real nonediting preset focus makes nested-layout menu
Undo/Redo pass 1/1, preserving native text Undo and canonical assertions. Remaining
eight affected UI methods run in one focused group; no result claimed yet.
Layers recording shows disabled Nest In with Text selected; renderer-adoption and
native enabled-state waits are under focused evaluation. Do not install or claim
completion. Earlier pending/no-runner statements are historical snapshots.

Newest native comparison: reuse passes 1/1 (235.493s), corrected conversion passes
1/1 (97.941s), selected through exact Xcode Test navigator Run actions. Normal
scheme identity app.siteforge.SiteForge, not prior CLI OwnerTesting. Conversion's
real defect was the test reading a geometry field below the rebuilt Inspector's
viewport; bounded shipping scroll + fresh readout query fixes it with assertions
unchanged. Bundles/screenshots and QoS warning limits: latest 006 evidence. No app/
runner remains. Freeze fingerprint 5ffff41c… for ONE full ./sf verify using this
same ordinary identity/DerivedData; preserve owner data and private test fixtures.
The earlier cancelled case was agent-initiated SIGINT, not a collector policy bug.
No installed update or completion until the new full gate genuinely passes.

Newest outcome supersedes pending/freeze wording below: repository/build and
732/732 non-UI pass. UI: six pass, two assertion failures, one cancellation; NOT
a full pass. Artifact: dark-flow-frozen-verify-results/full-af3502ef-9861-46f7-94e7-dc47c456a283.xcresult.
One diagnostic pair compiled, 0/2: reuse Save now passes but Preview discovery
fails; conversion fails before editing at selected-height discovery. Native
read-only inspection concurrently exposed the complete shipping control tree
while XCTest lost frames/identifiers. Recordings/006 evidence retain the boundary.
No lifecycle patch, weakened assertions or timeout increase. No active runner.
OD-025: exact Xcode-normal rerun of the pair, not another CLI/authentication loop.
Installed app remains build 26.10.21 / ab18c663 / 85f0f55d…. Preserve the uncommitted
tree and gate installed replacement on a genuinely green full run.

Preserve the entire uncommitted tree, the independent Dark Flow owner package,
original Editorial/Workflow Study resources and genuine recovery. No commit,
push, GitHub operation, privacy/service change or installed-app overwrite is
currently permitted. Installed replacement waits for final green verification
and normal Saved/Quit plus source/provision checks.

Current: direct supported native controls worked after the owner continuation.
Dark Flow opened through the real Open panel, restored history and reached Saved.
Preview/current-source export succeeded at revision 245. Contact/Not Found had
transparent Root nodes despite dark child surfaces; real Add Solid + Dark Surface
token bindings now author those two backgrounds. Normal Save/Preview/Export used
the central shipping controls; no handwritten package/output or global theme.
Original-resolution Desktop/Mobile captures prove dark viewport coverage and
natural Contact scrolling/Footer ordering. Details: 006 evidence. The app was
normally quit and process inspection confirms no app/test runner remains.
Twenty-six affected code methods pass across focused runs. Freeze the reconciled
tree for ONE accumulated ./sf verify; do not edit underneath it. Current full gate
and installed delivery remain incomplete. Do not repeat accepted authoring/Menu QA.

Historical boundary: the owner-authorized single authentication retry built but
exited 65 before any test method, again timing out enabling automation mode.
Evidence: dark-flow-browser-owner-auth-retry.xcresult and its matching log in
ignored evidence storage. System logs prove the request/timeout, not a displayed
or completed authentication dialog. No runner remains active. Ask what the owner
actually saw before another UI retry; do not change privacy/services or replay
authoring. Earlier readiness claims below are historical, not current proof.
The new authored-root viewport minimum has one passing focused code test;
actual refreshed-output visual acceptance is still pending. Distinct affected
code methods now total 26, not the historical 25 below.

Home's native exact three-stop
45-degree gradient, foreground tokens and Mobile flow are saved. Journal,
About, Contact and Not Found now have real editable editorial content. Journal
confirmed-flow passes 1/1 (105.475s), About 1/1 (451.458s), Contact/Not Found
1/1 (1176.261s). Original-resolution captures were reviewed; details and failures
remain in evidence/SF-LOCAL-BUILDER-006-DARK-FLOW.md.

Twenty-five distinct affected code methods pass; permanent native token-row,
Select All and Layers parent/nesting/history regressions pass. Availability
memoization is bounded and identity-gated; real commands always validate fully.
Native Layers values expose the actual parent. Unchanged valid sizing drafts
finish without false red errors or canonical/history mutation.

Home expansion passed 1/1 (549.457s), normally saved/quit; its Desktop/Mobile
original-resolution captures were reviewed. Two earlier attempts
stopped before editing at the five-second blank-workspace readiness boundary.
Fresh diagnostics found the correct shell at the final poll, no modal dialog.
Use the existing eight-second real-package reopen budget for this owner package;
do not change generic launch or text-entry timeouts.

Current handoff: no test process is running. Fresh readiness was unlocked and
the final export was opened directly in Safari; accepted authoring was not
replayed. Eight real Responsive Design Mode widths were inspected in bounded
Home regions. A 320-wide wrapped Menu affordance prompted a small shared output
correction: intrinsic single-line summary and Mobile flex alignment, no canonical
geometry change. The two affected code methods and native export-only journey
pass (1 UI, 71.683s) in dark-flow-intrinsic-menu-native-export.xcresult. The fresh
normal export is named Aurora — Dark Flow Website Reviewed. Native inventory then
reported the Mac locked again. Request only physical unlock/keeping awake; do
not repeat setup/authentication or accepted authoring. Resume actual browser
review directly on that export, especially 320 Menu pointer/keyboard and all five
destinations. Full frozen verification and safe installed delivery remain pending.
Original Editorial/Workflow Study package and resource raw-file hashes match
the consistent pre-review baseline in all four groups.

Earlier partial review, dark-flow-review-native-output-final.xcresult, completed real
history, save/close/reopen, exact gradient identity, shared-compiler Safari preview
and native export Cancel/retry. Its final Safari address-entry event timed out;
native inventory then explicitly reported the Mac locked. Owner unlock is needed,
not another automation-authentication or Xcode setup retry. Capture the run's final
result before another run. The final export exists through ordinary native commands;
its navigation typography now targets generated link identities as well as normal
text identities. Three affected output methods pass; visual confirmation remains
pending. Then inspect actual Safari output
at required widths/intermediates, reconcile factual evidence/traceability/docs,
freeze sources and run ONE supported accumulated ./sf verify. Do not claim
completion, browser parity or installed delivery before those steps succeed.

## Historical — Connected local-builder integration polish

Current observed owner boundary — 2026-10-24: supported native inspection of
the selected Xcode shows an actual **Install Required** dialog: system-wide
components must be installed to use Xcode (shared simulators/connected-device
resources). Buttons are Quit and Install. The dialog is left open; no Install,
agreement, authentication, component/platform selection or configuration action
was performed. Owner must choose Install in Xcode and personally handle Apple's
subsequent setup/authentication. Screenshot and exact evidence: OD-025 and 005.

No tests/collector were rerun. Preserve the 13 passing focused UI workflows,
nine affected code passes and reviewed visual limits; full verification/installed
delivery remain incomplete. After the owner finishes, confirm read-only readiness
succeeds, freeze current sources and run ONE supported accumulated collector.
Do not bypass preflight, repeat unchanged focused runs, alter privacy/services,
install over unknown owner work, commit or use GitHub. Production fingerprint
remains `d3b06b9d…`; earlier active-run/authentication paragraphs below are historical.

Earlier: all 13 distinct focused UI workflows now have passing results across
serial runs; nine directly affected code regressions pass (overlapping older
evidence, not additive to 717). Connected image/typography completes Save, native
versus canonical Undo, actual reopen and preview (385.272s). Native export Cancel/
retry/reopen passes; actual Safari mobile Journal navigation now works after a
document-body transient-focus dismissal correction. The full eight-width browser
review and original-resolution captures are recorded in the 005 evidence, with
explicit fixed-template clipping at 320/1024 and no universal-parity claim.
Current source fingerprint `d3b06b9d…`; no test process is left from these runs.
Freeze sources/docs for the supported ONE accumulated collector. Do not bypass
its Xcode readiness preflight, replace the ordinary installed app over unknown
work, start another feature, commit or use GitHub. Installed delivery still needs
full verification and normal owner Saved/Quit proof.

Earlier: responsive sizing/draft/reopen workflow passes 1/1 (165.978s), plus three
viewport focus/identity code regressions, at fingerprint `59ae7ba1…`. Twelve
distinct native workflows now have passing results. Complete trace proved X
never regained focus; speculative cancellation changes and temporary logs are
removed. Native viewport focus publication now waits for the completed responder
transition with window/request/responder guards; rejected presets mirror the real
canonical value. Stronger focus/committed-value assertions pass. Tablet/reopened
screenshots inspected and listed in 005 evidence. `connected-image-final.xcresult`
is the sole active run (five affected code methods plus the last connected
image/typography UI method); monitor it, do not duplicate or infer success.

Earlier continuation, 2026-10-23: native automation is working; no current
authentication request. Eleven distinct focused UI workflows have passed across
the retained serial runs, including named components, component history/recovery,
all seven Settings destinations, image/fill persistence, practical compact layout,
native sizing bounds and two real Safari workflows. Two connected workflows are
still being completed, not waived: practical image/typography and responsive
sizing/draft cancellation. The most recent completed two-method run failed at
an ambiguous unscoped Center menu query and Escape's native field-editor
write-back recreating a cancelled geometry draft. The current build corrects
those boundaries and strengthens the committed-value assertion. Five affected
code regressions passed before that cancellation correction. Source fingerprint
`351da51786edebf9195b95a0840faa9bf84e1a79fb2affae7f0c27194dc460fc`;
`cancel-ui.xcresult` is the active isolated run under the ignored evidence root
listed in the 005 evidence. Do not start a duplicate or infer its result.
Eight-width independent Safari review, final accumulated collector, and safe
installed delivery remain pending. Ordinary owner work is untouched.

Historical 2026-10-23 17:19 isolated retry superseded the authentication blocker below:
initialization succeeded; one component workflow executed and failed at line 5644.
Named component creation succeeded, but the test queried Design-only provenance
with Layout still selected (retained AX hierarchy). No prompt was confirmed visible.
0 passes/1 assertion failure/0 skips; no second retry or source edit. Next bounded
correction is explicit native Design-tab navigation before that provenance assertion,
then the unfinished workflow; do not treat creation or authentication as failed.
Retained result/hierarchy/recording: evidence document's Single isolated retry section.

Historical 04:51 assessment (not the current blocker): isolated app/provision fingerprint
`f601b53b…` builds and passes all 717 code tests, zero failures/skips. ONE pending
component UI selector failed initialization before its method (automation-mode
timeout; one runner error, not a product assertion). Computer-use tooling is
separately unexposed. No current screenshots/Safari/full integrated pass. All
owned runs exited, protected hashes match 4/4, installed build 26.10.21 is unchanged.
The later retry above supersedes this initialization failure. No more source-only
features; continue the existing acceptance inventory with demonstrated repairs.

Historical traced prerequisite: runner session and test-daemon authorization succeed;
automation-mode writer then requires device-owner authentication. LocalAuthentication
reports “User interaction is required” and requests “Enable UI Automation”; no
completion precedes the timeout. Developer mode is already enabled. Simulator
mismatch causality is unproven (the 717-code pass has the same warning). Paths,
provision and architecture do not demonstrate a repository launcher defect.
No new tests were run during diagnosis. Owner readiness was requested for ONE
isolated retry with the owner handling macOS authentication personally. Do not
request credentials, alter permissions/services or recommend SiteForge reopening
as a test-manager fix. Normal saved/quit proof is only a later install safeguard.
Exact sanitized chain and alternatives: OD-025 and the evidence below.

SF-LOCAL-BUILDER-005 is IN PROGRESS. Visible retained editors now participate in
a synchronous user-action commit/validation boundary before Save/Preview/Close
and context changes. Native text history remains separate from document Undo.
Native panel origins and preview/build/open/export feedback are identity-gated;
shared static output handles macOS temporary-path aliases without relaxing bounds.
Reviewed affected group passes 24/24 code tests (ten new); app/UI targets compile.
No native journey, screenshots, Safari or final changed-tree full gate executed.
Exact source results and the ONE pending native/visual/Safari/Settings/installed
inventory: `evidence/SF-LOCAL-BUILDER-005-INTEGRATION.md`. 002/003/004 remain
IN PROGRESS; their groups overlap and the historical 815 gate predates them.

Do not change privacy/services,
force quit, replace the installed app or touch Aurora/genuine recovery. No commit/
GitHub/release. After access genuinely returns, finish that inventory, inspect
actual original-resolution/Safari output, freeze sources, then ONE accumulated
full gate. A safe install requires normal Save/Quit proof and matching source/
app/provision fingerprints. No unrelated feature starts next.

## Prior — Practical image reuse and typography source checkpoint

SF-LOCAL-BUILDER-004 is IN PROGRESS. Scoped chooser/import shares existing
Image/fill/component registries and one atomic asset/reference command. Global
replacement confirms canonical reference scope; usage reveal waits for adopted
page identity. Thumbnail caching follows document/resource/request identity.
Installed-font search and discovered weights reuse CoreText; retained typography
drafts reject changed scope without losing unfinished input or missing intent.
Final affected code group passes 22/22 (seven new); app/UI targets compile.
New public-control UI journey is NOT executed. Exact evidence and a single
pending inventory: `evidence/SF-LOCAL-BUILDER-004-ASSETS-TYPOGRAPHY.md`.

No native retry, privacy change, app refresh, commit or GitHub operation. Keep
002/003 IN PROGRESS, OD-025 independent, owner work unknown and protected. After
access returns, finish 004/002/003 native/visual/Safari, seven Settings destinations,
then ONE accumulated changed-tree full gate. Installed refresh requires normal
Save/Quit proof and fingerprint checks. Historical 815 is not current coverage.
No further slice starts now.

## Prior source package — Practical responsive sizing source checkpoint

SF-LOCAL-BUILDER-003 is IN PROGRESS. Effective winner/source, exact dimension
reset, counted conversion confirmation and adjacent Layout controls are wired
through existing registries. Numeric drafts preserve user intent across renderer
adoption and reject changed context. Grid numeric precedence and continuous
connected fluid CSS projection are corrected without a new cascade or schema.
23 unique affected code tests pass (11 new), plus 2/2 strengthened height/reset
reruns; app/UI targets compile. New native journey is NOT executed. Exact
selectors/results and continuation:
`evidence/SF-LOCAL-BUILDER-003-RESPONSIVE-SIZING.md`.

No native retry, installed refresh, full gate, commit or GitHub operation.
OD-025 remains independent; current owner work is unknown and preserved. After
access returns: responsive/bounds and component journeys, Settings review,
original-resolution visual/Safari acceptance, then ONE accumulated changed-tree
gate. Safe installed refresh requires normal save/quit proof and fingerprint
checks. SF-LOCAL-BUILDER-002 remains IN PROGRESS; the 815-test baseline is older
than both packages, not current integration evidence. Do not begin another slice.

## Prior source package — Practical component reuse, native acceptance pending

SF-LOCAL-BUILDER-002 is owner-authorized and IN PROGRESS. Named component
creation/shared eligibility, typed Return to Instance/Page, shared organized
Design/Content controls and stable scene-local text drafts are implemented.
Final focused source group passes 17/17, including seven new tests. Both test
targets compile; the new public-control UI journey is compiled but NOT executed.
Exact selectors/results and continuation:
`evidence/SF-LOCAL-BUILDER-002-COMPONENT-REUSE.md`.

Do not repeat the failed native binding or timeout. OD-025 remains independent;
current owner work cannot be inspected. Keep the regular installed verified app
untouched, preserve original Aurora/recovery, no commit/push. After normal native
access returns, execute the named journey and existing two-instance/recovery
journeys, inspect captures and actual Safari, then one final changed-tree gate.
The 815-test result below is historical PRE-package evidence, not acceptance of
these changed sources. Settings-only prohibitions below are superseded only for
this explicitly authorized component package; no additional feature is started.

## Historical baseline — 2026-10-21 final full gate PASSED

Latest bounded continuation: a single fresh native SiteForge binding still fails.
No UI actions or tests followed; do not assume the historical blank remains clean.
Owner must use normal Save/Cancel/Quit, reopen regular SiteForge and show Settings
or provide screenshots. Every Settings destination remains pending OD-025.
No product change is justified; keep the current verified installed app as-is.
Current comparison and exact next already-listed Practical component reuse package:
`evidence/SF-LOCAL-BUILDER-001-INSTALLED-VISUAL-DELIVERY.md`. No feature starts now.

`20261021-034253-d689cac6` completed: repository/build, 682 code + 133 UI =
815 tests, zero failures/skips; failed-selectors is empty. Source fingerprint
`85f0f55de2b76a6f016d8ffe0651278f108a66eef0276570e5b407f5d204bb79`
matches installed app and testing provision. No source changed during collection.
All new reuse/contextual/Safari/reopen and repaired recovery/token journeys pass
in the complete target. No publish-during-update/invalid-geometry diagnostic;
retained Apple QoS warnings are not silently reclassified or suppressed.

Installed Aurora review passes 1/1, seven captures inspected; protected Editorial,
Study and both resource sidecars match fresh before/after hashes. Nine controls
and seven source-Aurora captures also reviewed. Work stays uncommitted; no GitHub.

One additional installed Settings visual capture remains blocked, OD-025:
the extra XCTest launch timed out before any test; native fallback retained the
blank capture but its Settings shortcut/fresh app binding lost the native pipe.
Finder remains readable, Mac unlocked, app main thread is idle in AppKit. Do not
claim this extra journey passed or change product code/permissions speculatively.
The last observed blank is historical; current saved/modified state is unknown.
Do not force quit or touch retained recovery. Owner normal reopen/Settings confirmation
or screenshot is the exact next action. Earlier pending/failure sections below
are historical and superseded by this checkpoint, not instructions to rerun it.

## Historical focused workflow checkpoint — superseded by final gate above

Installed review also PASSED 1/1 (158.722s), `installed-aurora-review.xcresult`:
the regular app opened the existing Study, native Save As created a new review
project, then copy/navigation/presets/Safari/close/reopen completed. Seven installed
captures inspected. Fresh before/after hashes match both protected packages and
both resource sidecars. No conversion/padding replay or genuine recovery writes.
Installed Info, testing provision and source fingerprint agree:
`85f0f55de2b76a6f016d8ffe0651278f108a66eef0276570e5b407f5d204bb79`.
Only final changed-tree unattended verification remains before acceptance.

Independent named page copy, metadata preservation, current-owner Include All
Pages and contextual Text Colors are implemented. Model group 8/8 and separate
title-provenance regression 1/1 pass. Controls UI 3/3, existing foreground/token
journey and normal Aurora copy/Safari/native-reopen 1/1 (142.149s) pass.
Final Aurora bundle: `focused-8c05cb14-7563-40ec-b918-4fb401a850ed.xcresult`.
All nine control and seven Aurora captures inspected. Actual matched pointer
counts are page 10 -> 6 and navigation 2 -> 1; equal text entry excluded.
Safari links expose title rather than label; native Go to Folder can autocomplete
the project's resource sidecar, so Open now selects the exact file from its
parent and waits for enabled/hittable state. No product saving workaround.

Next: safely refresh only the regular installed app, review an independent
native Save As copy of the existing Study without replaying conversion/padding,
compare original bytes, verify installed/provision/source fingerprints, and run
one final unattended accumulated gate. The earlier 804 pass predates these edits.
Keep all work uncommitted; no GitHub, original/recovery mutation or new sharing
architecture. New captures are ignored under the workflow-reuse-20261021 report.

## Historical repair-checkpoint authority — superseded by final gate above

Integrated repair checkpoint PASSED in `20261021-002649-dee2b04f`: all repository
and build checks, 675 code tests and 129 UI tests (804 total), zero failures,
skips or expected failures. Both repaired selectors pass in the full target.
No active collector or runner. No publish-during-update/invalid view geometry
message; Apple QoS diagnostics remain retained without reopening classification.
Proceed with the approved page-copy/navigation/contextual-edit consolidation;
this passing snapshot does not verify subsequent source edits. Preserve original
Aurora and genuine recovery; work stays uncommitted, no GitHub/publication.

Targeted repairs are green: repository checks pass, including the isolated
Pillow 11.3.0 icon checker and two prerequisite regression cases. The two failed
UI selectors now pass 2/2 in `focused-8fb70684-3db1-4096-af4f-853a1d7339b5.xcresult`:
crash recovery 25.368s, text foreground/token/inline parity 178.210s. Seven
captures were inspected from ignored
`.codex-loop/full-verification/targeted-repair-20261021/captures/`.
Recovery termination now validates the actual configured bundle, sibling Debug
artifact, recorded current-run PID and executable; ordinary apps are ineligible.
The token failure was a partly clipped field (Y=993, height=26); hittable did
not mean pointer-visible. Strict live-control containment fixes reveal, keeping
verified keyboard focus and all canonical assertions. No product recovery or
typography model change. Next: one unattended integrated checkpoint, no source
edits while it runs; no full pass yet. Original Aurora/recovery remain untouched.

Preparation run `20261021-002446-9a5c34ca` was cancelled before build/tests after
its progress helper exposed a Swift main-actor entry error. The helper now has
one explicit main-actor lifecycle; launcher type-checks it before claiming a
collector lock. Type-check and 21/21 affected tooling tests pass, including the
new failure/no-launch/no-lock regression. No UI selector changed after its 2/2
pass. Retain the cancelled report; it is not integrated acceptance.

Collector `20261020-213032-8c1fc557` finished FAILED: build passed, 675 code tests
passed; UI 127 passed, two failed, zero skipped. Repository failed because the
ambient Python lacked Pillow. No collector remains. Plan: declare an isolated
verification Python runtime with actionable prerequisite checks; bind the crash
journey's termination to the launched OwnerTesting artifact/run/PID; fix the
token journey's partly clipped field reveal without weakening keyboard focus.
Run affected repository checks and only the two failed UI selectors, inspect
captures, then one unattended integrated checkpoint. OD-024 remains resolved.
No commit/push, owner project or genuine recovery mutation is authorized.

## Previous focused record — 2026-10-20

OD-024 is resolved by fresh evidence: the unchanged compact Button/Link journey
passes 1/1 (52.649s), bundle `focused-75b3a453-d776-44f2-8d7c-cb50f82a0b96.xcresult`.
Logs and two inspected 2200×1504 captures are retained under ignored
`.codex-loop/full-verification/owner-clear-focused/`. Native pointer Undo
restores Home; no toolbar obstruction, center fallback, publish-during-update
or invalid-geometry message was observed. An Apple QoS warning remains recorded;
the earlier classification is not reopened. No product/test changes were needed.
Next: launch one unattended full checkpoint; no overlapping collector or source
edits during collection. It is not yet a passing integrated gate.

Collector `20261020-212952-c486fb09` was cancelled before tests after repository
checking caught two documentation-only trailing blank lines. Those are fixed;
`git diff --check` passes. Retain its report as cancelled, not passed. The next
collector replaces this interrupted preparation, without changing source/tests.

Owner confirmation on 2026-10-20: there is no notification and the screen is
clear. OD-024's banner evidence is historical, not a current blocker. Its old
temporary evidence directory is unavailable; retain new focused results in
ignored report storage. Run the exact compact Button/Link journey now, preserving
the pointer Undo and restored-target assertions; no passing result is implied.

Historical external obstruction: OD-024, an unrelated calendar notification covers
native title-bar Undo. Owner has been asked to dismiss that one banner normally;
no preferences/permissions are changed. Fresh capture and exact pointer fallback
are recorded in workflow evidence. The accumulated attempt
`full-77de4af7-db9f-4e5c-a724-33f7a8e611e4.xcresult` passed all 675 models and eight
UI journeys, then failed `testButtonLinkInternalTargetControlsAtPracticalMinimum`
at its post-Undo assertion. It was stopped (exit 75), not passed. No runner
remains. Next: after the banner is gone, run only that exact selector and inspect
its capture; do not rerun a broad gate before the concrete obstruction is fixed.
Then close the accumulated checkpoint and continue phase two below.

Preservation check: original Editorial still matches its saved checksum on
2026-10-20. The temporary 69-file recovery baseline manifest is now unavailable;
do not report a fresh recovery checksum pass. The 2026-10-18 exact comparison
remains historical. This resume made no recovery writes. Installed app/provision
still match each other, not yet the current test-source fingerprint.

SF-LOCAL-BUILDER-001 remains IN PROGRESS, uncommitted. The owner authorizes
verification followed by evidence-based workflow consolidation, not new unrelated
features, GitHub, signing or publication. Original Aurora/recovery stay protected.
The two exact structural selectors now pass 2/2 in
`focused-20923f31-5b20-456e-9592-6237107acb48.xcresult` (34.303s and 262.069s).
The prior `focused-aec94d75-3857-44ed-ba62-76a78fb53d69.xcresult` failed activation
before feature assertions; its trailing zero-test suite is not a pass. The
segmented-control check preserves strict bounds on concrete native buttons,
not the outdented noninteractive AX wrapper. Ten captures were inspected;
OS notification banners limit their full-window presentation evidence.
Next: one accumulated full checkpoint; then the safe page-duplicate/navigation
and contextual-edit follow-up in the queue, measured against actual old logs.
No source/test edits while the collector is active. Refresh the regular app only
after normal Saved/Quit and source/provision fingerprint validation.

## Historical owner package — SF-LOCAL-BUILDER-001 — 2026-10-18

Latest correction: the next integrated attempt passed all 675 model/integration
checks, then exposed an obsolete dark-editor 300/340-point pane cap. The approved
five-destination layout uses normal minima 324/356 and bounded maxima 360/420.
The exact visual journey now asserts both bounds, remaining canvas width and
no overflow. It and both measured-pane model tests pass 3/3 in
`focused-994388ba-9214-4f86-bb87-f74f60f28987.xcresult`; all five original-resolution
captures were reviewed. The red full attempt was stopped, not counted as passed.
Final integrated verification remains required; no commit/push is authorized.

Latest integration result: repository checks/build pass; first full attempt was
interrupted after real failures. Six corrected historical-fixture/announcement
checks now pass, grouped Settings passes 1/1, and strengthened historical chrome
rejection passes 1/1. After the owner reported no prompt visible, the exact
appearance journey passed 1/1 (37.828s), bundle
`focused-4de2a0c3-86e7-45cb-a6de-acd755018b88.xcresult`. OD-023 is resolved
without changing permissions. The accumulated final gate is now required.
Do not claim verification or completion yet. The following focused/native
delivery record remains valid; preserve all original Aurora/recovery bytes.

Latest authority: normal unlock restored native execution. Sample, explicit
legacy-history and isolated clean/crash journeys each pass 1/1. The regular app
was safely updated after real Saved/Quit (fingerprint 0a76a510a64ab351504e740e23fda56b2eb218ad1bdf6660cc0370a4b160c24c);
installed sample/original-reopen and installed responsive/Safari/export journeys
each pass 1/1. Seven native delivery/recovery captures plus installed captures
were reviewed; see the latest Aurora evidence for exact bundles/failures/limits.
All 69 genuine recovery hashes match. Aurora Editorial is preserved; a separate
Aurora Workflow Study was created through native Save As (1/1), original hash
unchanged. No authoring replay, commit, push or extra named app copy.

The owner-authorized workflow follow-up now has focused Fill/Hug and shared
text-metric proof (four model/native-render tests plus one native journey),
measured five-tab rows/Inspector stability, and neutral no-change Site Settings
Apply. Design Essentials label/size/destination, invalid draft/Escape and
Undo/Redo pass a new native journey. Aurora conversion/preset now passes, as do
installed Study conversion/padding and normal save/reopen. Eight Safari widths
were inspected after fixing flex-basis cascade and intrinsic grid-track sizing.
The regular installed app now contains these workflow edits (fingerprint
2d25a03f100d1cab8b57b46b7c16b18cc1c59a956c5665b1f47d31e472ea9f12).
All 84 Study nodes/base frames remain exact; only two intentional content edits
exist. The original and original recovery hashes remain unchanged. See workflow
evidence and ADR-0025 for schema 19, precedence, opt-in conversion and remaining
native/browser/integrated acceptance. Reserve the accumulated final gate for
the ready state. The checkpoint trail below is historical; do not replay
authoring or treat its former locked/pending-install state as current.

Owner-selected direction: a dark translation of original render 01, preserving
its slim navigator, dominant framed canvas, clean sections and compact toolbar.
Aurora website content stays pale. Preserve fixed render-12 Settings geometry.
No new commit, push, GitHub operation, publication, distribution signing or app
duplication is authorized. Baseline ab18c66 remains accepted; this package is
IN PROGRESS and must remain uncommitted. Preserve genuine owner data.

## Historical implementation trail — superseded by the active record above

Past pending-install, locked-console and unfinished-native-check statements
below describe their original checkpoints, not current instructions or blockers.

Historical source checkpoints:
- Crash qualification source is now implemented (ADR-0024): new recovery-only
  receipts bind session/project/document/revision; private held locks identify
  live sessions; actual normal termination marks clean; automatic Welcome
  discovery excludes clean/live/legacy snapshots. Explicit Recovery History
  retains manual access. Durable saves strip evidence. Latest focused recovery,
  autosave and ownership checks pass 7/7, bundle
  `focused-8cebb442-2596-4507-89f1-d560022915b7.xcresult`; all 69 originals hash
  identically. No native interaction was retried while locked. Native crash/clean
  exit acceptance and integrated verification remain pending. Additional
  `testInitialRecoveryOffersAbandonedSessionButKeepsCleanExitManual` passes 1/1
  in `focused-eb3ae24b-9dc8-4159-99ba-8711d9192584.xcresult` (eight distinct
  checks total). Native source builds for testing without launching. No runner
  remains. After normal unlock, run only the exact packaged-sample selector and
  `SiteForgeLaunchTests/testProductionRecoveryDiscoverySupportsKeyboardRestoreAndDiscard`
  first; inspect captures before safe normal Saved/Quit/install. Preserve the
  ordinary Aurora original and do not replay authoring.
- Packaged Aurora Welcome source is implemented, not yet installed/visually
  accepted. The loader uses the exact UI-authored package and verified resources
  with fresh project/document identity and no source history. Five focused
  template/resource/lifecycle checks pass; two corrected historical resource
  fixture checks pass. ADR-0023 records the read-only bundled-resource policy.
  The new exact UI selector is
  `SiteForgeLaunchTests/testAuroraPackagedSampleCreatesEditableFourPageWebsiteJourney`.
  Its first attempt compiled but was interrupted during launch after macOS
  reported a locked console; it is not a passing or product-failing result.
  No runner remains. Recheck unlock before the next attempt. The final source
  assertion uses the genuine Section Height field, not an invented width ID.
  Do not duplicate the delivered Aurora or replay authoring scripts.
- Aurora was authored through the installed app and saved as an ordinary
  `Aurora — Editorial.siteforge`, with real Home/Journal/About/Contact pages,
  independent image/overlay/text/actions and responsive Layout edits. Native
  export exists; shared compiler fixes for linked Buttons, authored borders,
  preserved line breaks and plain-Text vertical placement pass 3/3 focused.
  Continue from this saved package, not a new prototype. Exact authoring
  checkpoint evidence and rejected loading-only Safari capture are recorded in
  the Aurora evidence. Real Safari navigation and mobile menu were exercised;
  latest delivery captures supersede earlier output experiments. Installed
  startup-sample acceptance, native crash-qualified recovery and integrated final
  verification remain unfinished.
- Canonical Site Settings/page metadata is now implemented (schema 18/history
  3), including native File-menu sheet, local drafts, exact inverse, escaped
  compiler output and favicon asset safety. Latest focused checks: 22/22
  model/history, 2/2 additional adversarial/dependency, 5/5 existing output;
  actual Apply/Cancel/Undo/Redo 1/1 (49.593s). Both final screenshots inspected;
  search preview is pinned outside the scrollable fields. Full package pending.
- Primary Preview builds the existing static artifact and opens actual Safari
  on bounded loopback. Canvas Device Preview remains separate (Command-Option-P).
- Native raster retains/reprojects compatible world layout during zoom; role
  names no longer enter authored pixels. Existing focused geometry checks pass.
- Dark sRGB semantic palette/default is shared with Settings; explicit saved
  appearance choices still win. Website ink/paper remain independent.
- Canvas-priority layout yields render-01-like slim panes. Native pull-down tab
  overflow now has visible template icons, truthful values and real AX focus;
  every destination remains available. Forward/reverse traversal passes.
- Accessibility, Image Fill and Fill Layers share section styling; Reset is a
  genuine content button, not a flattened GroupBox heading. Reusable-style
  creation is no longer clipped. Inspector navigation alignment shares the
  native/output resolver rather than displaying a false Start default.
- Existing test tab actions now use the shipping adaptive menu helper; no
  feature/history/persistence assertion was removed.

Latest focused evidence: appearance/palette 10/10; tab identity/traversal model
checks 2/2; native overflow/default-reset checks 2/2; real dark-section and fill-
layer journeys 2/2; complete native forward/reverse keyboard journey 1/1; latest
paper-ink/material checks 3/3 plus Accessibility and Safari journeys 2/2. These
are overlapping focused checkpoints, not a summed full-suite result. Exact
bundles/selectors and reviewed captures are in the Aurora evidence document.
OD-022 is resolved after normal owner unlock/Xcode restart. No test runner is
active at this handoff. New focused logs contain no publish-during-update or
invalid-view-geometry diagnostic; Apple service/QoS diagnostics remain observable.

The regular installed app was safely updated after normal Saved/Quit and now
contains the shared output/Direction corrections, but not the new packaged
sample. The ordinary delivered project is Aurora Editorial; the earlier Aurora
Authoring Attempt remains preserved. Both and all genuine recovery must stay
untouched. Browser/photo authoring used real UI, not JSON or model shortcuts.
Samples/Aurora contains the generated photograph/provenance and exact packaged
copy of the UI-authored website.

Next bounded work in this same package:
1. Check repository hygiene/traceability and retain the current focused evidence.
2. Validate crash-qualified recovery and explicit legacy history in the native
   app after normal unlock. Source and 7/7 focused checks exist; do not classify
   every old snapshot as a crash or touch genuine owner snapshots for testing.
3. Integrate the focused Site Settings checkpoint into final Aurora/Safari
   acceptance; retain explicit broader SEO exclusions in ADR-0022.
4. Finish Aurora through production authoring tools: independent overlay,
   typography/text/actions, destination pages and real Safari mobile navigation.
   Fix observed native long-title/output font/link differences through shared
   resolution, not sample-specific branches or hand HTML.
5. Review installed blank/Aurora/Inspector, Settings and actual Safari captures;
   safely refresh only the regular owner app, preserving documents/recovery.
6. Run one integrated unattended final gate only when the full package is ready.
No integrated acceptance or completion is claimed by the current focused passes.

## Residual follow-up — 2026-10-16

Accepted baseline `ab18c66` remains unchanged (755/755). All 47 QoS stacks
inspected: 37 AppKit Services-menu AX inspection and 10 native text-checking,
both through `_getDataDetectorsScanner`; no SiteForge blocking frame found.
See `evidence/SF-PRODUCT-UI-010-RESIDUAL-QOS.md` for paths, limits and other
retained Apple diagnostics. No production/test changes, tests, reinstall,
commit or push for this follow-up. Documentation-only edits await owner review;
no owner action is required. Do not reopen accepted repairs based on count alone.

## Historical final checkpoint — 2026-10-15

SF-PRODUCT-UI-010 bounded correction is accepted: final `./sf verify` exit 0,
636 model/integration +119 UI =755 tests, zero failures/skips, all repository
checks green. Bundle `full-ccd26b85-b343-4b99-a179-af63921dd057.xcresult`.
The compact Interactions test uses the existing native overflow-menu helper;
all original page-protection/live-link assertions remain. Final focused
follow-ups pass 4/4 +1/1, fourteen captures reviewed. Installed owner app matches
fingerprint `a3a19bf4a4b6af0fbe0dd89250519db92923abe15f137a8862c132dc3db6525e`.
All 69 original recovery hashes match; no test runner is active. One local
commit is authorized after final review; no push or next feature is authorized.
Modules remain Partial; broader responsive/output/release scope is not accepted.
Internal Xcode QoS warnings remain observable (47); no clean-runtime claim.
All pending/blocker/action wording below is historical, superseded here.

## Historical complete collection — 2026-10-15

Full collection finished 754/755 (636 models +118 UI), sole failure a compact
test assuming a direct Interactions tab rather than native overflow. Corrected
through the existing real-menu helper; exact follow-up passes 1/1 (36.095s),
both captures reviewed. All four prior interaction repairs passed in that full
collection. Next: clean final gate and local-only commit; no push.

## Historical focused authority — 2026-10-15

Owner Xcode restart restored native execution: all four interaction repair
journeys below pass 4/4 (399.845 seconds). All twelve retained captures were
reviewed at original resolution: readable controls, clipped authored surfaces,
no Mobile ghost, truthful hidden Layers state, working Contact preview link.
The regular installed app now includes these corrections, source fingerprint
`0b263c7be7cb3d46078795ad0a8caa3344885834fcc3100ef548fd3987791aef`.
OD-021 is resolved. Next: authoritative final `./sf verify`, factual final
reconciliation and one authorized local commit only. No push. Earlier blocker
and pending language below is historical, not the current execution state.

## Historical blocker and next action — 2026-10-15

SF-PRODUCT-UI-010 remains IN PROGRESS. No commit or push. Latest full attempt
completed 636 model tests and 93 UI passes, with four UI assertion failures and
one subsequent runner initialization failure (729/734 total recorded passes).
Four bounded corrections compile but native validation is blocked by XCTest's
"Timed out while enabling automation mode" before any test executes, through
both normal and already-built routes. No test process remains. OD-021 requests
normal owner Xcode restart; do not reset privacy or kill shared system services.

Next: run only these four SiteForgeLaunchTests selectors after native automation
recovers, inspect their captures, fix any remaining cause, then the final gate:
`testInspectorWorkflowSearchPinGeometryPasteUndoAndMixedJourney`,
`testMinimumWorkspaceContainsViewportAndScrollableFillInspectorControls`,
`testResponsiveContainerLayoutAndBreakpointVisibilityJourney`,
`testLocalPreviewFollowsAuthoredPageLinkWithBackForwardAndNoEditorMutation`.
The fixes reveal contextual tools, require fully visible live controls/real
keyboard focus, and restore Preview link rectangle hit testing for transparent
native text. No canonical content/history/geometry changes or weakened assertions.
Four focused Preview metrics/navigation, responsive projection and container
registry checks pass 4/4 (0.075 seconds); this is not native UI acceptance.
Repository/security/traceability/architecture/evidence checks pass, as does
`git diff --check`. All 69 original recovery hashes still match; no runner active.
The installed bundle precedes these last interaction corrections; refresh only
after their acceptance. Original owner recovery remains preserved.
All older active/completed language below is historical, superseded here.

## Historical installed acceptance — 2026-10-15

Latest focused repair: nested connected-layout acceptance passes 1/1 (105.140
seconds), four captures reviewed. Its old single-node Header/Footer counts now
reflect five editable nodes each and Mobile closed-menu exclusions. Semantic
count matching is exact, not a substring. The latest interrupted full attempt
passed 636 models and Settings but is not a full pass. Final gate remains due.

Latest gate correction: the next full attempt passed 636/636 model tests but
found Settings root accessibility identity propagation. Explicit root containment
preserves the native sidebar/content identities; the unchanged seven-destination
journey passed 1/1 (24.021 seconds), with all seven captures visually reviewed.
The regular app is refreshed at fingerprint
`215dcbd91f5aacd8a64dcd92f9d48980cc2dffa33efa6774ce2c9f8d3a40c1c6`.
Its exact installed focused rerun passed 1/1 (23.627 seconds); all 69 recovery
hashes still match. The corrected final gate follows.
The preceding interrupted full result is retained, not counted as passing.

SF-PRODUCT-UI-010 remains IN PROGRESS; no final gate or local commit yet.
All older pending/action wording below is chronological history, superseded here.
The owner quit the regular app normally. Safe replacement succeeded without
terminating a document, with recoverable backups and matching source/provision/
installed fingerprint `4e67f9b22548c30b17b88585e01d9d4a642c53e778c570a4b28dfc283326ecd5`.
All 69 original recovery files still match their recorded hashes.

Native installed production smoke passed 1/1 (222.566 seconds), using the actual
regular app with no product launch arguments/hooks: own blank project, real
Header/body/Footer, title edit, native Save, Preview, static output bytes,
Close/Open, retained title and normal Quit. Initial Welcome/Review/Later were
also captured on the first production launch without restoring/discarding owner
recovery. Six final smoke captures were inspected at original resolution.
Visual review found unscaled Preview text truncating titles; Preview now uses
the shared canvas text-layer factory, transparent ordinary text and authored-only
borders. Three focused metric/ink/navigation tests pass. Temporary native smoke
helpers were corrected for real modal-field keyboard ownership and Touch Bar
ambiguity, not by changing persistence or weakening repository assertions.

The installed fixed-Settings, connected Header/Footer and owned recovery fixture
selectors passed together 3/3 (308.387 seconds). All 17 retained captures were
inspected at original resolution; all 69 recovery hashes still match. No runner
remains active. Run the final `./sf verify`, review and create ONE authorized local commit.
No push, GitHub change, publication or distribution signing. Counter stays 2/10.

## Historical owner correction and LOCAL COMMIT authorization — 2026-10-15

SF-PRODUCT-UI-010 is IN PROGRESS and supersedes older no-commit directions.
Preserve the accumulated tree. The owner authorizes a local commit only after
all repairs, focused tests, installed visuals and the accumulated collector pass.
No push, GitHub change, publication or distribution signing is authorized.

Completed baseline collector 20261015-103239-d7607136 failed: repository/build
passed; 614/623 non-UI and 108/118 UI passed. All 19 failures remain recorded.
Nine failing code selectors subsequently passed after exact Undo storage-order
repair and valid current-schema/multi-selection fixtures. Shared sidebar layout
and non-destructive welcome/recovery tests passed 2/2. The formerly failing
geometry native journey passed; reviewed capture prompted further hierarchy
refinement. Twenty collector tests pass, including staging-neutral fingerprints.

Current source adds balanced complete-label sidebar allocation, contextual
Inspector sections and compact tools, welcome recovery Review/Later, fixed
Settings (preferred content 970×740, sidebar 250, common form 680), and schema-v17
editable Header/Footer contents using ordinary Stack/Text/Link nodes. The
Header/Footer command/UI/output integration has focused model coverage and a
passing native edit/Undo/Redo/save/reopen journey; expanded title visibility,
page inclusion and Preview acceptance passed (263.736 seconds). Fixed Settings native
acceptance passed across seven destinations and reopening; all eight retained
window captures were inspected at original resolution. Installed regular-app
acceptance and the final accumulated collector remain pending. Do not mark the
item complete.

Shared Component Properties disclosures now use full-width native Button rows
with explicit Expanded/Collapsed accessibility values and balanced body insets.
The slot-fallback and two-instance text journeys pass. Retained-override text
now passes its exact accessibility-value assertion using a standard static-text
representation while preserving pointer text selection. Its next confirmation
check is blocked by an outstanding macOS Documents permission prompt above the
real reset alert (recording inspected). See OD-020: owner should dismiss that
prompt with Don't Allow; the test host now reads bundled fixtures and uses its
own temporary storage. Computer Use cannot handle the protected system app.
The owner subsequently handled the prompt; the next recording confirms it is
gone. The real reset confirmation is a native Sheet, not XCUI Alert. The test
scopes stable action identifiers to that sheet, avoiding Touch Bar ambiguity,
and requires its heading, enabled/hittable actions, Escape and exact history.
That exact recovery UI selector passed 1/1 (211.793 seconds); all four settled
captures were inspected at original resolution. OD-020 is resolved.

Repository checks passed after these corrections. Focused recovery/history and
immutable legacy-package checks passed 2/2; strict legacy control decoding and
temporary-fixture containment passed 2/2. All nineteen original failing selectors
now have passing focused evidence. Regular owner-local universal packaging and
safe installation passed, preserving the previous bundle. The 69 existing
recovery files remained byte-identical across normal Quit. Installed smoke is
pending: Computer Use returned a closed native pipe twice, including after a
fresh kernel. Do not bypass native automation or privacy controls.

The component-instance inset focused checks completed: discovery/recovery 2/2
and two-instance text/history/reopen 1/1. All ten resulting original-resolution
captures were inspected, with contained focus rings, readable groups, upright
text and aligned selection. No test runner is active. Logs are in the ordinary
owner-correction temporary evidence directory under component-instance-inset-
focused.log and component-instance-inset-two-text.log.
The earlier invocation had a mistyped temporary path; its replacement reached
635 model tests with one stale outer-Header navigation assertion, then was
explicitly interrupted. The corrected nested Navigation/outer-owner/exact-links/
no-duplicate assertion passed focused 1/1 (0.105 seconds). The next final attempt
passed 635/635 unit/integration tests and fourteen UI journeys, then found a
component-instance search control extending one point beyond its viewport.
That failed attempt was explicitly interrupted, not passed. The shipping
instance-property group now uses the same shared inset section as other
Inspector groups; no pointer containment assertion was relaxed. The failing
discovery and retained-recovery selectors passed 2/2 (113.476/213.818 seconds).
The initial two-instance selector had a name typo; its actual
testComponentTextPropertiesTwoInstancesResetHistoryAndReopenJourney then passed
separately (283.374 seconds). No runner/app from the interrupted gate remains.
No duplicate full run
and no source edits while it runs. Final installed acceptance/local commit are
still pending. Preserve the normal app and its genuine recovery candidate.

Installed acceptance fallback: the owner reopened the regular app and confirmed
Welcome visible, but Computer Use still loses its SiteForge pipe; Finder is
readable and a process sample shows SiteForge idle in its normal event loop.
Do not repeatedly reset or bypass privacy controls. After the active run exits,
use a copied standard XCTest runner/configuration targeting the exact installed
app where feasible. Existing fixed Settings, Header/Footer and production
recovery journeys provide app-window captures with owned test fixtures; clearly
distinguish those from normal production launch. A native black-box production
smoke may drive visible Welcome/Review/Later, own blank project, Save/reopen,
Preview and local output, without product hooks or genuine recovery mutation.
The assertion and shared instance-section corrections change the fingerprint, so
refresh the regular package/provision before installed testing, only after the
owner quits it normally. Require installed/process path and fingerprint proof;
never count temporary-build captures as installed evidence. Keep publication
reconciliation proportional; do not reformat the large DOCX.

Ephemeral installed-acceptance preparation (outside the repository):
prepare-installed-runner.sh copies the standard generated XCTest runner,
changes only its copied test-bundle target identity and xctestrun target path
to the installed regular artifact, and signs only that copied local runner.
InstalledOwnerSmoke.swift compiled successfully against native XCTest with no
SiteForge import, app launch arguments, model calls or product hooks. It drives
production Welcome/Review/Later, an owned blank Header/body/Footer project,
native Save/Close/Open, Preview and actual local static output, retaining window
captures. Neither preparation has executed against the installed app yet.
Before running it, require the owner app be quit normally and refresh the
installed provision/fingerprint. Keep the original recovery manifest intact
and check all original bytes afterward. Run targeted installed Settings,
Header/Footer and recovery acceptance plus that bounded production smoke;
then inspect the captures before the final complete verification.

The updated universal package built successfully with fingerprint
dc1f9df1a11e10c20afc8b23a3acc66609724f7c29ca79acf0196dd6b541ae0e.
Its installer correctly refused to replace the still-running regular app;
the owner has been asked to quit it normally and leave it closed. Do not kill
that app. After owner confirmation, rerun the safe installer (cached build),
verify installed/provision/source fingerprints match, and execute the prepared
installed-artifact native tests. No final complete gate/local commit is claimed.

Finish the owner's exact acceptance in the queue/evidence: practical title/page
inclusion/menu/customization, all failed affected journeys, fixed Settings
size/common cards/titlebar, complete collector with continuation reporting,
safe regular-app update and smoke, source/report fingerprint agreement, full
diff review and local commit. Preserve genuine owner recovery. Counter stays
2/10. No new feature milestone.

## Historical delivery evidence — do not restart or discard the tree

Regular app owner-local provisioning, both real Testing buttons, cancellation,
native Settings close/reopen and report actions passed installed-window checks.
Eleven distinct model checks, 19 collector tests and nine affected UI journeys
passed. Latest installed source includes canonical empty-page recognition so
hidden/unavailable authored objects cannot trigger a false blank hint.
The standard Close Window command was restored through native responder routing.
Experimental packaging was removed; regular safe updater preserves backups.
No worker/xcodebuild remained after bounded checks; progress windows intentionally
remain until the owner closes them. No full-suite success is claimed.

Current next action is the remaining real installed-app connected website/
Preview/local-export smoke and reachable-surface review, not a new feature.
The shared automatic text ink correction passed its new light/dark glyph test
and the existing authored-color/inline-editor parity test. Native historical
fixtures now load from UI resources into the owned temporary lease, not from
the protected checkout folder. One fixture-staging check and four script
harness scenarios also passed. Final accumulated verification remains pending.
Finish documentation/visual acceptance against UI-009 and owner-local testing
evidence. Preserve the original recovery candidate; never restore/discard it as
test setup. Source code edits require rebuilding the installed provision because
the harness refuses stale fingerprints. No commits/pushes/GitHub/publication.
Counter remains 2/10. All older no-install/experimental directions below are
historical; the top current owner-local direction is authoritative.

## Historical owner-local delivery correction — IN PROGRESS

Owner supersedes separate experimental copies: deliver the regular SiteForge app
with an installation-provisioned Advanced > Testing harness. No source-folder
chooser, Experimental Options switch, Settings scope/provenance badge or release-
channel selector. Keep global preference data and genuine authoring provenance.
Bounded SF-0201-003/006/008, SF-0206-002/003/004/005/006/008 and
SF-1607-002/004/006/008; normative modules remain Partial.

Plan: integrate regular Settings/harness; test automatic provisioning, persistent
reports, duplicates/cancellation and isolated test identity; compile; package with
source fingerprint; safely replace only the inactive regular installed bundle
with recoverable backup; inspect that installed app and affected UI captures.
Compact native icon toolbar, viewport-centered bounded empty hint, paired geometry
fields and inline ordinary Inspector controls are part of this correction.
No commits, pushes, GitHub, publication, distribution signing or notarization.
Local ad-hoc owner packaging/install is authorized. Counter remains 2/10.
Focused acceptance is running; no completed delivery or full gate is claimed.
Earlier experimental/owner-away instructions below are historical and superseded.

## Historical owner-return visual acceptance — counter remains 2/10

01/05/12 selected references replace 04. Source shared matte/flat-editor/card-
Settings treatment and proportional split allocation are integrated; loading's
prior opaque fallback is retained. Two unsigned experimental builds passed;
all test targets compiled after fixing 124's invalid XCTest modifier calls.
Three focused model tests and two Settings/grid UI journeys passed. Later
compact management/transfer-disclosure refinement has an eight-selector affected
visual matrix running; do not duplicate it or modify code during the run.
Native computer-use disconnected on Settings and still fails after rebind/reset;
continue available XCTest acceptance, recording missing experimental/manual
states honestly. Evidence: `evidence/SF-PRODUCT-UI-009-SELECTED-REFERENCES.md`.
No full suite/verify, commits/pushes/GitHub/manual signing/install/release.
Current authorization allows necessary local builds/launch and focused UI tests;
the owner-away execution prohibition below is historical, not current.

## Historical handoff — cohesive local-builder cycle Prompt 2/10

124 source implements native Inspector section search/navigation/pins and strict
typed geometry-value copy/paste through the existing registry, including mixed/
applicable subsets, current-breakpoint provenance and exact history/persistence.
Four model tests and one native journey are unrun. Preserve 123 and the entire
accumulated tree; no active collector ownership file at the one pre-edit read.
Evidence: `evidence/SF-AUTHORING-124-INSPECTOR-WORKFLOW.md`.
No execution/commit/GitHub/automation/installation/release while owner is away.

Next complete package: connected local website/output completion, based on
110/121/122 and the greatest remaining usability gap, not numeric sequencing.
Combine containing-layout recovery, navigation/Preview/local-export/assets/
semantic metadata and their history/AX/error integration. Inspect exact contract
and retained failed acceptance evidence first. Do not split off routine controls
or documentation into extra development prompts. Phase one has provisionally
5–8 remaining packages; phase two defers CMS/services/collaboration/plugins/
remote/publishing. ROADMAP retains requirements and OD-018/019/update boundaries.

## Historical owner-away source cycle — Prompt 1/10

SF-AUTHORING-123 source implements derived component-property discovery,
provenance filtering and keyboard reveal against the existing Inspector scroll
owner. Preserve all source through 122, experimental testing and visual add-ons.
Three model tests and one native journey are source only, not compiled or run.
See `evidence/SF-AUTHORING-123-COMPONENT-DISCOVERY.md` and
`REMAINING_DEVELOPMENT_ROADMAP.md` for exact selectors, risks and next bounded
candidate. Schema stays v16; no mutation path, override scope or slot ownership
changed. Search/focus are scene-local and do not enter diagnostics/packages.

The one authorized read of prior run `20261013-153433-e964329d` found it finished
(exit 1) and collector process gone. Build passed; repository/code failed; UI
initialization timed out enabling automation mode. Retain report; accumulated
acceptance is pending owner return. No relaunch/polling. Prior RUNNING/launch
instructions below are historical, not a direction to start another test.

While owner is away: no tests/build/compiler/parser/linters/repository scripts,
UI automation or permission requests, commits/pushes/GitHub, replacement/signing/
notarization/release. Native/visual/scale and final acceptance remain deferred.

## Historical handoff — Development Prompt 10 accumulated acceptance

**RUNNING — owner report handoff.** The single detached full collector launched
as run `20261013-153433-e964329d`, retained in
`.codex-loop/full-verification/20261013-153433-e964329d/`. Its collector and
progress process ownership were confirmed. Preparation: 13/13 tooling tests,
2/2 ordinary Settings tests, successful app/test build and progress-helper
compilation. Do not launch another run or monitor this run from Codex. Await
the owner's completion/report; no full pass or native visual acceptance is
claimed. The prior pre-launch instructions below are historical prerequisites.

Counter is 9/10. Preserve SF-AUTHORING-122 shared container policy, resolved
snapshots and nested output, padded flow/minimum fitting, visible-only markers,
navigation sizing/visibility/context/focus/accessibility and owner recovery.
Schema remains v16; legacy data, stable identities and exact history remain.
Seven new model/integration selectors and one native journey are unrun; see
`docs/evidence/SF-AUTHORING-122-CONNECTED-OUTPUT-INTEGRATION.md`.
No execution/build/check/automation/install/signing/GitHub operation ran in
Prompt 9. Both testing add-ons and all existing uncommitted work are preserved.

Follow `docs/PROMPT-10-ACCEPTANCE.md` for feature prompts 2–9, UI-008 and
experimental testing. Fix compile/integration issues with affected focused
coverage when execution is authorized. Then launch `./sf testing full` once,
give the owner the printed `.codex-loop/full-verification/<run-id>/` directory
and stop agent monitoring. Do not start it now, poll it, start a duplicate broad
suite or simultaneously run `sf verify`. The collector owns both progress
sections and final failure reporting; the owner reports completion. Source
readiness is not verified completion. No commit, push or replacement authorized.

## Prior Prompt-8 checkpoint and independent testing add-ons

Preserve SF-AUTHORING-121 connected page source: schema-v16 Section roles,
shared structural frames, captured native settings, PageID navigation,
Mobile Menu and fail-closed structured output. Counter 8/10. Six new selectors
and one updated selector are unrun; see the 121 evidence and ADR-0020.
The unattended collector and experimentally gated Settings source add-ons are
delivered; their runtime acceptance belongs to Prompt 10. Do not launch tests
before Prompt 10. Only
the owner-authorized experimental local app build/package/install is permitted
now; no commits, pushes or GitHub operations. Prompt 9 should address bounded
containing-layout/output gaps after checking the exact specification.

The add-ons now have source: `scripts/unattended-verification.py`, the native
two-section progress helper, `./sf testing full|ui` and an explicit experimental
packager/Settings route. Prompt 10 must execute the source tooling/Settings
tests first, then launch full testing **once**. Give the owner the printed report
directory and stop agent polling; the detached collector/progress owns the run.
The owner reports completion and any report failures become bounded repairs.
Do not run both this collector and `./sf verify` concurrently or launch duplicate
UI suites. Direct `./sf verify` remains unchanged for CI and direct script use.

Experimental local app build/install passed. The separately identified app is
installed alongside the normal SiteForge app in Applications; nothing was
terminated or overwritten. Enable Experimental Options under Defaults to expose
Testing. Native/runtime/official-bundle exclusion and the nine written tooling/
Settings acceptance tests are unrun. Prompt 10 must inspect progress placement
against click targets and exercise failed/blocked/cancelled/duplicate runs.
See `docs/evidence/SF-LOCAL-TESTING-001-EXPERIMENTAL.md`.
The final installation includes the latest Settings selection repair and native
progress helper. The previous experimental installation is retained recoverably
alongside it; the normal app remains untouched. No SiteForge/Xcode test or app
process was running at final non-test process inspection.

## Prior Prompt-7 checkpoint

Preserve SF-AUTHORING-120 source-only recovery: `ComponentOverrideConflictFinding`,
shared conflicts/provenance including missing action destinations, confirmed
`resetOverrideConflicts` with captured operation/PropertyID identity, native
review/cancel/source navigation, exact existing history and retained-schema-v15
serialization, dependency/clipboard/Preview/static build findings. Seven unrun
selectors and risks: `docs/evidence/SF-AUTHORING-120-COMPONENT-OVERRIDE-RECOVERY.md`.
Counter is 7/10. No tests/builds/compiler/parser/checkers/scripts/automation,
commits/pushes/GitHub operations before Prompt 10. OD-018 remains unresolved;
OD-019 documents retarget/conversion policy. Neither blocks independent work.
Recommended Prompt-8 candidate: native component-property discovery/search and
keyboard navigation for large grouped definitions under SF-0902-006/007 and
the applicable SF-0701 Inspector contract, after inspecting exact requirements.
Keep filtered presentation scene-local; it must not change values, order,
grouping, conflicts or reset scope. No next feature is started in this prompt.

## Prior Prompt-6 checkpoint

Preserve SF-AUTHORING-119 source-only property organization: schema-v15
`CanonicalComponentOrganization`, central `organizeProperty`/reset commands,
binding-removal cleanup, grouped native instance fields, definition captured
drafts, transfer/dependency/projection integration and six unrun selectors.
Exact targets/risks: `docs/evidence/SF-AUTHORING-119-COMPONENT-PROPERTY-ORGANIZATION.md`.
Counter is 6/10; no tests/builds/compiler/parser/checkers/scripts/automation,
commits/pushes or GitHub operations before the owner-authorized Prompt-10 gate.
OD-018 stays unresolved, instances stay childless, and supplied content remains
unavailable. Next dependency-ready candidate: component property conflict
reconciliation/retargeting with explicit typed migration under SF-0902-004/005
and SF-0905-004/005, after inspecting the exact spec and existing 113 guards.
Do not silently reattach a retained override or change its type. If the spec
does not authorize a conversion, restrict repair to explicit reset/restore and
document the missing owner decision. No new feature has been started here.

## Prior Prompt-5 checkpoint — OD-018 remains unresolved

SF-AUTHORING-118 implements the safe fallback slice in source. Preserve stable
slot IDs, definition-owned ordered childIDs, native captured-identity
Apply/Cancel/remove and inherited inspection/edit routes, slot-aware transfer,
dependency inspection and metadata-free expanded/detached graphs. Schema v14
reads earlier packages and rejects forged older slot state. Six new selectors
are unrun; exact names and risks are in
`docs/evidence/SF-AUTHORING-118-COMPONENT-SLOT-FALLBACK.md`.
The current feature counter is 5/10. Supplied content is blocked by OD-018:
the spec does not choose its storage/cardinality and ADR-0018 keeps instances
childless. Obtain that decision before enabling instance-owned children or
supplied overrides. Prompt 6 can finish that path after approval; otherwise
bounded component-property grouping/order is independent and ready to inspect.
Tests/builds/checks/automation remain deferred to Prompt 10; no commit/push.

SF-AUTHORING-117 completes source integration of the component action editors
and transfer boundary. Preserve shared `NativeLinkDestinationFields`, captured
identity Apply/Cancel/Reset drafts, transition guards, precise unmapped-target
findings, action/node reference mappings and dependency inspection, page
duplication/impact coverage, and request-local virtual section resolution.
Nine new selectors are written and unrun; their exact names and Prompt-10 risks
are in `docs/evidence/SF-AUTHORING-117-COMPONENT-ACTION-INTEGRATION.md`.
The recorded Prompt-4 checkpoint counter was 4/10; visual add-ons did not increment it.
Recommend the next bounded component slot/default-fallback authoring slice,
using current ordered canonical child ownership and graph/history paths after
inspecting the exact SF-0902/SF-0905 contract. Do not execute tests/builds/checks,
automation or GitHub operations before Prompt 10, and do not commit/push.

The SF-PRODUCT-UI-008 follow-up has completed its source migration and coverage
matrix. Preserve shared native Inspector/Settings groups, selected/hover/inactive
rows, semantic field/validation/spacing roles, and the read-only inherited
Accessibility Settings page. Original-resolution runtime acceptance remains
reserved for Prompt 10. Component action integration is now source-implemented; this
visual add-on did not increment the feature counter.

The accumulated source batch completed its authorized gate on 2026-10-12.
Repository/security/traceability (409 records), architecture, AppIcon, retained
evidence, 567 unit/integration tests, and 104 actual-app UI journeys passed
(671 total, zero failures). The earlier automation-mode timeout is historical,
not an active blocker.

`SF-AUTHORING-114` adds the first bounded enum component property: an Image
definition can expose its canonical Fit/Fill/Stretch value and each linked
instance can author or reset a typed override through the native Content
Inspector. Continue with the next dependency-ready component-property gap
without duplicating the component graph, command registry, or renderer.
Arbitrary enum option authoring, remote/multi-format media, actions, slots,
variants, and nesting remain explicitly deferred.

Its focused affected selectors pass 3/3 and a final-gate attempt passed every
repository/build check plus 568 unit/integration tests. macOS XCTest then timed
out while enabling automation mode before executing a UI journey. Preserve
`full-788bd61f-04f1-4071-ab01-260195fd373b.xcresult`; do not classify this as a
product assertion failure or repeat the unchanged broad suite until the host
automation service is available.

`SF-AUTHORING-115` is the subsequent source-only slice under the temporary
ten-prompt cadence. Preserve schema-v12 `CanonicalComponentMedia`, its stable
AssetID override path, registry edits, immutable graph projection, native
project-asset picker, safe deletion accounting, dependency entry and clipboard
resource/property remapping. Test source is present but intentionally unrun.
Development Prompts 3/4 source-implement the action foundation/integration as
SF-AUTHORING-116/117; prompts 2–9 must not execute tests/builds/checks, and
Prompt 10 owns the single accumulated verification and repair gate.

`SF-AUTHORING-116` source-implements the stable Button/Link action-property
model, strict destination codec, identity-gated expose/set/reset commands,
schema-v13 persistence, provenance projection, and immutable graph resolution.
The owner-directed visual-convergence correction does not increment
the feature cadence. Prompt 4 source-implements native instance action controls
and deterministic transfer handling for internal destinations. No
tests/builds/checks run before Prompt 10.

The owner add-on `SF-PRODUCT-UI-008` then refines the shared visual system
without incrementing the feature counter. Preserve the centralized 8-point
rhythm, semantic chrome/row/field/status roles, coordinated editor panes,
bounded Settings sidebar/detail measurements, launch composition, and tab
surface migration. Prompt 10 must perform the complete original-resolution
launch/editor/Settings/light-dark/accessibility visual matrix; no concept or
diagnostic reference media belongs in the repository.

## Historical checkpoint — 2026-10-07

The bounded batch `SF-AUTHORING-075`–`105` (excluding `SF-AUTHORING-106`),
`SF-AUTHORING-107`, and `SF-PRODUCT-UI-005/006` is integrated. The
authoritative `./sf verify` passed every repository check and all 640 tests:
542 unit/integration plus the complete 98-journey UI target. The shared live
native text-control/focus correction also passed its exact focused 2/2 rerun.
After this checkpoint, `SF-AUTHORING-106` was source-implemented under the
owner testing pause using approved OD-016. Blank Site remains intact; the sole
local Starter Site creates canonical Home/About semantic content through the
same clean lifecycle. Its focused test source is unrun, so do not infer
verified completion or completion of broader onboarding/learning scope.

SF-AUTHORING-108 is also source-implemented under the testing pause. Preserve
the single `editor.isolation.v1.root` marker, `IsolationCommandRegistry`,
immutable subtree projection, restoration stack, breadcrumb, Focus mode, and
Presentation-over-Preview path. Its focused tests are unrun; after the pause,
execute those selectors before any broader completion claim.

Owner-approved AppIcon v2 source work is also present after that checkpoint.
Preserve `docs/design-assets/siteforge-app-icon-sf-gradient-approved-v2.png`,
the deterministic package/check scripts, and all ten regenerated catalog
renditions. Allowed static validation passes; App-host and direct
launch/About/Finder/Dock review remain deferred by the testing pause. Do not
restore v1 as the normative source or use icon artwork as authored content.

SF-AUTHORING-109 is source-implemented and parser-checked. Preserve the closed
`layout.position.v1.*`, `style.reusable.v1.*`, and `style.state.v1.*` models,
`AdvancedStyleCommandRegistry`, immutable renderer/static-output resolution,
native Inspector controls, scene-local forced preview, and redacted diagnostic
boundary. Its focused tests are unrun; the visual-convergence pass now takes
priority before SF-AUTHORING-110 resumes.

SF-PRODUCT-UI-007 has now completed that focused visual-convergence pass and
the owner's follow-up correction. Keep `SiteForgeVisualSystem`, its dynamic
blue-neutral pasteboard/grid/artboard palette, the stable one-row
scroll/overflow shell tabs, the compact blank-artboard header hint, the
width-driven viewport header, the shared Settings headers/cards, and the
unchanged authored geometry contract. The affected source parser-check and
universal build passed; retained normal/selected/minimum/dark/light/
Reduce-Transparency captures were reviewed at original resolution. Focused
affected journeys and the complete 104-test UI target pass. The first full gate
found one outdated native-tab traversal expectation; its exact focused
regression now passes. The final documentation-inclusive `./sf verify` passed
567 unit/integration tests plus 104 actual-app UI journeys (671 total, zero
failures). This accumulated checkpoint is ready for owner review; do not infer
a commit or GitHub action.

SF-PLATFORM-UPDATE-001 is the subsequent source-only slice. Preserve the
vertical Settings sidebar, `UpdateFeedChecking`, `UpdateSettingsStore`,
monotonic `UpdateVersion`, request-ID stale rejection, and fail-closed
`UpdateInstallTrustPolicy`. The bundle deliberately has no feed URL and the
automatic-check preference is not scheduled while trust is unconfigured.
`OD-017` blocks signing/notarization identity, feed/key custody, and installer
ownership; do not add private keys, checksums-as-trust, unsigned replacement,
or a Settings-owned provider call. The universal app build passed; update test
source is unrun and the full gate is deferred.

SF-AUTHORING-110 is now source-implemented under the same pause. Preserve
`StaticBuildCompiler`, the versioned scene-local build profiles, referenced-only
content-addressed asset export, contained sibling-staged writer, actor-owned
request/revision gating, redacted compatibility findings, and native Build
Diagnostics sheet/menu. Parser checks and one universal app build passed; its
focused tests are present but unrun. Before a completion claim, run the two
named `CanvasRendererTests` build regressions and
`testStaticBuildDiagnosticsPreflightProfileCancelAndAccessibilityJourney`,
then the required full gate. Publishing/hosting/arbitrary code and browser or
release certification remain excluded. `SF-AUTHORING-111` was selected next
from the first dependency-ready specification gap in this source-only batch.

SF-AUTHORING-111 is now source-implemented under the pause. Preserve clipboard
envelope v2, its complete supported definition/dependency closure, structural
equivalence rule, deterministic identity/name remapping, one-batch exact
inverse, stale prepared-transfer guard, and native import preflight. The
universal app build passed; its new focused model and actual-app tests are
unrun. Before any completion claim, run the named ClipboardTransferTests and
`testCrossProjectComponentPastePreflightImportUndoRedoAccessibilityJourney`,
then the required full gate.

SF-AUTHORING-113 is now source-implemented under the pause. Preserve
`ComponentOverridePathV1`, `CanonicalComponentOverrides`, explicit retained
missing-binding conflicts, exact reset-all visibility/component commands,
strict transfer mapping, dependency override counts, and the redacted static-
output compatibility finding. Its affected sources parse and the universal
arm64/x86_64 app build passes; focused tests are unrun. Before any completion
claim, run the named CommandKernelTests and CanvasRendererTests plus the two
existing component actual-app journeys, then the required full gate. Do not
add a duplicate serialized path store or silently retarget a stable property
identity. The accumulated 671-test checkpoint supersedes the historical
verification warning, and `SF-AUTHORING-114` now supplies the first bounded
typed Image-fit choice property.

An owner-evaluation build is installed at `/Applications/SiteForge.app` from
the repository's build-only local-alpha path. It is version `0.1.0` build `1`,
universal arm64/x86_64, ad-hoc signed, and passed bundle/checksum/AppIcon v2 and
ordinary launch-smoke validation. It is intentionally unsigned by Developer ID,
not notarized, not published, and not evidence that the deferred test gate ran.
The standalone architecture-boundary checker mismatch is repaired. Its
headless slice now includes the actual canonical dependency closure while the
forbidden UI-framework checks still inspect every source file; the checker and
the complete repository gate pass.

SF-AUTHORING-112 is now source-implemented under the pause. Preserve the
scene-local organization policy, immutable `ComponentDependencySnapshot`,
utility-priority request/revision-gated worker, native Component Details and
Where Used path, and safe-maintenance predicates. The universal app build
passed; its two model tests and one actual-app journey are unrun. Before a
completion claim, run the named SelectionModelTests and
`testComponentOrganizationDependencyInspectionAndWhereUsedJourney`, then the
required full gate. Do not add persistent folders/tags/favorites or compatible
replacement without a specification-backed decision. Next recommended bounded
slice: `SF-AUTHORING-113` should address the earliest dependency-ready
component authoring gap in the queue/specification without adding remote
libraries, nested components, slots, or variants.

The source-only notes below are historical and no longer describe current test
execution status for the bounded slices above.

## Source-only continuation under owner testing pause

SF-AUTHORING-107 adds one strict `com.siteforge.authored-objects.v1`
pasteboard envelope and native Cut/Copy/Paste/Paste in Place/Duplicate routes.
The central clipboard registry normalizes selected roots, captures bounded
subtree/image/token closure, validates before Cut, remaps every destination
node/property and supported dependency identity, stages bytes through the
existing lifecycle rollback boundary, and emits one existing batch command.
Cross-project component closure is intentionally rejected. Model and actual-app
test source are unrun. Preserve this implementation and the source-complete
SF-AUTHORING-106 Starter Site path. Before any completion claim, run the new
focused Starter model, lifecycle, and actual-app selectors when the owner
testing pause is lifted.

SF-AUTHORING-105 adds path-free Recent Projects to the launch card. The new
app-local store retains only display name, stable recent ID, and the SHA-256
lookup key for the existing security-scoped bookmark owner. Reopen, stale
repair, coordination, package validation, recovery, and adoption remain in the
normal lifecycle. New source tests are unrun. OD-016 and the source-connected
SF-AUTHORING-106 Starter Site now establish the bounded launch choice. Use
`docs/evidence/SF-SOURCE-COMPLETENESS-AUDIT.md` as the ordered gap map and do
not infer full source completion from the large accumulated UI surface.

SF-PRODUCT-UI-006 replaces the launch hammer glyph with the approved packaged
AppIcon and establishes a bounded native toolbar hierarchy: Select, Frame,
Text, Image, and Component are persistent; Section, Stack, Grid, Button, Link,
and Form remain available in More Tools and the established Insert commands.
No command or insertion model was duplicated. Updated source tests are unrun.
Recent-project navigation and the approved SF-AUTHORING-106 Starter Site
workflow were subsequently source-connected without changing this toolbar split.

SF-AUTHORING-104 adds a native Support settings tab with build/channel
provenance, explicit installed-distribution update limits, the existing
recovery contract, and cancellable redacted report generation/copy/export.
The report is controlled metadata only and never reads document content or
paths. New source tests are unrun. Continue the next exact Settings/update/
recovery requirement without adding an unsigned updater, collecting project
content, or duplicating lifecycle recovery. Plugin trust/distribution remains
an owner-decision boundary if a future slice requires enabling third-party
code.

SF-AUTHORING-103 adds isolated multi-page local Preview navigation over the
existing stable Link target and canvas scene systems. Preview owns page/history
state, Back/Forward, page selection, and missing-target recovery without
changing editor scene or canonical content. External targets remain non-
executing and host-only in status. New source tests are unrun. Continue the
next exact interaction/output gap without duplicating link targets, page
routes, scene preparation, or static navigation.

SF-AUTHORING-102 adds one canonical monotonic fluid-value model for supported
width/height, typography size/line height, and container padding/gap. It uses
the established responsive cascade, atomic property commands, immutable canvas
preparation, comparison, and closed static output. Explicit Tablet/Mobile
overrides win; removing fluid intent reveals the untouched fixed value. New
model/output/UI tests are unrun. Continue the next exact uncovered responsive
requirement without adding a parallel breakpoint or layout resolver.

SF-AUTHORING-101 adds a native responsive comparison sheet driven exclusively
by the established Desktop/Tablet/Mobile geometry, container-layout, and
visibility resolvers. It reviews the selected objects or active page and
switches only scene-local viewport preset; no document/history/package state is
introduced. New model/UI tests are unrun. Pages/routes and internal PageID/
Section navigation targets are already source-complete; continue the next
genuinely uncovered responsive or navigation requirement without duplicating
their command, resolver, Preview, or static-output paths.

SF-AUTHORING-100 adds native component-definition rename. The existing central
component registry updates a stable definition plus linked instance display
names atomically; IDs, overrides, geometry, ordering, persistence, and exact
history remain intact. New model/UI tests are unrun. Assets organization,
replacement, usage filtering, portable static references, component creation,
linked insertion, edit-main, text/visibility properties, detach/delete, search,
and Quick Open were already source-complete and were not duplicated. Continue
the next exact uncovered Assets/Components requirement, not a second asset
store or component graph.

SF-AUTHORING-099 adds Heading as a semantic Text template in Elements and the
native Insert menu. It seeds deterministic geometry/content/typography and an
authored `<h2>` property through the existing insertion command; all later
editing and output stay on established systems. New model/UI tests are unrun.
Continue the next exact uncovered Elements/site-structure requirement without
inventing a node kind, automatic heading outline, or alternate renderer.

SF-AUTHORING-098 adds one canonical general-accessibility metadata namespace
for applicable Frame, Text, Section, Stack, Grid, Button, and Link nodes. The
Accessibility Inspector edits name/help through the existing identity-gated
transaction path; the immutable canvas accessibility snapshot and safe static
HTML projection consume the same authored values. Role remains derived from
the typed semantic-element registry. Image and Form remain on their dedicated
schemas. New model/output/UI tests are unrun. Next continue the highest-value
uncovered Elements/site-structure slice without adding a competing role, alt-
text, or Form schema and without claiming this slice verified.

SF-AUTHORING-097 adds directional native-canvas marquee selection through the
existing immutable scene and central selection registry. Left-to-right contains
visible clipped object geometry; right-to-left intersects; Shift/Command add or
toggle in stable paint order. The marquee never enters document data, history,
packages, renderer content, Preview, or static output. Model/UI test source is
unrun. Next reconcile the highest-value uncovered Inspector property slice;
do not duplicate established fills, typography, box style, responsive geometry,
structural layout, or Form field registries.

SF-AUTHORING-096 adds a canonical read-only Form Inspector presentation shared
by Content and Accessibility. It exposes accessible names, roles, requirement,
help, options, validation bounds, and provenance; mixed values stay Mixed until
the author resolves every shared draft. Form accessibility reuses the existing
scene-local validator and keeps Submit disabled/unconfigured. New model/UI test
source is unrun. Do not add a submission destination or visitor-value storage
without an approved specification/owner decision. The next safe action is the
deferred focused Forms gate and original-resolution visual/accessibility review,
not another competing Form schema.

SF-AUTHORING-091–095 add the remaining supported Form field templates through
the existing canonical Text/form-field path. Select options have deterministic
stable IDs; Submit is intentionally inert in safe output until a destination
is approved. The shared model/output/UI test source is unrun. Next inspect the
remaining SF-1006 authoring experience (field configuration, local validation,
accessibility semantics, and submit boundary) without duplicating the existing
SF-AUTHORING-036/037 registries.

SF-AUTHORING-090 adds Form-only Input insertion via the existing Text/form
field transaction, Elements category, and native Insert menu. The model and
actual-app test source is unrun. Continue with the next form-control slice;
do not claim Form output or visual acceptance before the deferred gate.

SF-AUTHORING-086–089 activate Divider and semantic Header/Navigation/Footer
templates through existing Frame/Section commands. Added model/UI test source
is unrun. Continue the remaining required Elements and Inspector/site-building
source without claiming visual or output parity before the later gate.

SF-AUTHORING-085 adds direct linked-instance insertion from Quick Open
definition results. Its new source assertions, including the prior reveal-
status correction, were not executed. Continue to the next dependency-ready
product slice without building, testing, committing, or pushing.

SF-AUTHORING-084 adds direct Quick Open Image insertion from a current-project
asset result. It is source implemented, not tested or committed. The owner has
paused all builds, tests, UI automation, verification, commits, and pushes while
the remaining specification-backed product source is implemented. Continue
from the existing dirty tree; do not describe 075–084 as verified.

## 2026-10-04 external XCTest automation blocker

The existing ten-slice dirty tree remains uncommitted and unpushed. Repository
checks and 513/513 non-UI tests passed in the interrupted `./sf verify`. The
macOS console locked at 12:58:32 EDT during the UI target, and app activation
then failed. The exact new Quick Open insertion journey was attempted after
unlock; `SiteForgeUITests-Runner` timed out in
`XCUIInitializeForUITesting` before SiteForge launched. No SiteForge test
process remains. The completed built-app AppIcon test passed 1/1, and
`scripts/check-app-icon.py` passed. Resume only when macOS XCTest automation
is available; run the exact new UI journeys, then an authoritative full gate,
review visuals and diff, reconcile factual status, commit, and push. Begin the
owner-requested two further ten-slice batches only after this checkpoint is
clean and pushed. Do not mistake the interrupted run for a green gate.

## Ten-slice source cycle awaiting one local gate (2026-09-30)

SF-PRODUCT-UI-005 plus SF-AUTHORING-075–083 are source-complete in the dirty
working tree, not verified. The final five slices provide New Page from Quick
Open, Components search, Assets usage filtering, and Quick Open asset/component
reveal. The pre-existing Assets name search was not duplicated. The approved
`SF-0201-009` wording is synchronized from Markdown to the editable DOCX;
rendered publication pages 40–42 were visually checked. See
`docs/evidence/SF-AUTHORING-079-083-QUICK-OPEN-DISCOVERY.md` and the prior
half-batch note below. Owner direction: run the complete local suite once now,
repair failures with exact failed selectors/new regressions only, reconcile
docs with actual results, review diff, then make one local commit and push
origin/main if green. No PR, release, signing, notarization, or settings change.

## Historical source-only half-batch (2026-09-30)

SF-PRODUCT-UI-005 and SF-AUTHORING-075–078 were implemented in that historical
dirty tree. The current normative gradient AppIcon source supersedes v1 at
`docs/design-assets/siteforge-app-icon-sf-gradient-approved-v2.png`; the
offline packager `scripts/package_app_icon.py` removes only its exterior matte
and writes ten static catalog variants. Quick Open adds closed insertion
actions for basic, structural, site-control, and image workflows and routes
through existing active-scene commands. New policy/UI/icon test source is
unrun. The owner forbids tests, UI automation, full verification, commits,
pushes, and GitHub during this half-batch. Next action when authorized: run
only affected AppMetadata/SelectionModel selectors and the new Quick Open
insertion journey, inspect original-resolution icon/app screenshots, repair
any issue, synchronize the editable specification publication copy with the
approved `SF-0201-009` Markdown wording, then run the applicable milestone gate. Do not describe these
source changes as verified or modify project content from Quick Open itself.

## Hosted checkpoint correction (2026-09-30)

Commit `73c653a` was pushed, but Actions run `36669009531` hit its 60-minute
job cap while UI tests were still progressing. Its log identified two
offscreen/not-hittable pointer interactions on the 1024-point hosted display.
The exact Quick Open and snapping/guide selectors now pass locally 2/2 after
the test uses live selected-state and scroll-to-reveal assertions. The checked-
in CI job has a 90-minute cap; no production minimum-window reduction or
individual XCTest timeout increase was made in that first correction. Its
hosted result is recorded below; do not claim a green gate until one actually
completes successfully.

That next run (`36674126611`) completed 504/504 non-UI and 78/81 UI. Its
artifact proved the Inspector's last control was trapped behind the Dock on
the 1024×768 hosted display; the large fixture displayed a real workspace but
its first AX query exceeded the ordinary five-second bound; and a text-field
reveal helper chose the wrong scroll direction at the lower edge. The product
Inspector gained bottom scroll clearance; only the 10,000-page fixture gets
a 30-second readiness bound while retaining the exact window/shell assertion.
The three exact UI selectors passed locally 3/3. Push this correction and
inspect the next hosted result before starting another slice.

The next run (`36680840818`) passed 504/504 non-UI and 80/81 UI. The only
remaining hosted failure was an AX-present but offscreen New Color Token
button in the text-foreground journey; its click did not reveal the form.
The corrected journey requires a real native-scroll reveal, a hittable button,
and an actual hittable draft field. It passed focused 1/1 locally. Push this
single-selector correction and wait for a genuinely green hosted gate.

## Historical ten-slice local checkpoint (2026-09-30)

SF-AUTHORING-065–074 deliver application Settings reset plus native Pages,
Layers, Elements, and Quick Open search under bounded `SF-0205-002/003/004/006/008`
and `SF-0206-002/003/004/006/008`. Quick Open offers current-document pages,
authorized current-page Layers, a closed View-action set, scene-local recents,
and native All/Pages/Layers/Actions scopes. Filter and query state never enters
project packages or renderer content. The one full batch run executed 504/504
unit/integration passes and 79/81 UI passes. Its two test-contract failures
were corrected and passed exact focused reruns: keyboard focus traverses the
new Pages search stop; the Layer Type picker is queried in its own menu and
includes the structural Root among Frame-kind rows. Original-resolution
Elements, Layers, Quick Open, and Settings states were reviewed. The owner
directed no second broad run after exact focused repairs; do not describe
the original full run as green. See `docs/evidence/SF-AUTHORING-068-ELEMENTS-SEARCH.md`
through `docs/evidence/SF-AUTHORING-074-QUICK-OPEN-SCOPES.md`.

The combined checkpoint was committed as `73c653a` and pushed. The current
next action is the hosted correction described above; do not start a new
feature before its hosted result is known. No publication or release work is
authorized.

## Historical Layers search checkpoint

SF-AUTHORING-067 filters only the current Layers navigator targets by name
under bounded `SF-0205-002/003/004/006/008` and existing `SF-0402-002/006`.
Return selects through the established Layers command; Escape and Clear Search
leave canonical content untouched. The new policy and real-app journeys plus
the existing multi-selection keyboard journey passed focused 3/3. Three
original-resolution states were reviewed; see
`docs/evidence/SF-AUTHORING-067-LAYERS-SEARCH.md`. Preserve the preceding
owner-review tree. The later batch verification result is recorded above.

## Historical Pages search checkpoint

SF-AUTHORING-066 adds a scene-local native Pages search by page name or route
under bounded `SF-0205-002/003/004/006/008`. Return opens the first result;
Escape and Clear Search restore the full list; a no-result state can reveal the
selected page. The new model and native UI journeys and the affected existing
Pages keyboard-navigation journey passed focused 3/3. Three original-resolution
window states were reviewed. See `docs/evidence/SF-AUTHORING-066-PAGES-SEARCH.md`.
The later batch verification result is recorded above; no module-complete
claim is made.

## Historical application preference-group checkpoint

SF-AUTHORING-065 adds an explicit native Settings Reset tab for the existing
application-only Appearance and new-workspace Grid records (`SF-0206-002/003/004/006/008`
bounded). It stages one exact pair, rejects dirty/managed/stale state, resets
both with rollback on storage failure, and restores previous bytes within the
session. No project schema, document history, renderer, or live Grid state is
changed. Five exact model tests, the fresh-process group journey, and two
existing Settings journeys passed focused 8/8; five
original-resolution states were reviewed. See
`docs/evidence/SF-AUTHORING-065-APPLICATION-RESET.md`. Preserve the earlier
uncommitted SF-AUTHORING-063, SF-PRODUCT-UI-004, and SF-AUTHORING-064 work.
No new full gate, commit, push, or hosted result is claimed. Project-owned
Settings still require a concrete spec-backed preference choice; none was
invented in this application-only slice.

## Historical focused Canvas Settings checkpoint

SF-AUTHORING-064 adds a strictly decoded application-only default for Grid in
new workspaces under bounded `SF-0206-002/003/004/006/008` and `SF-0407-006`.
Existing scenes retain their independent toolbar/View-menu state; no project
content, renderer output, or recovery package stores the preference. Three
exact model tests and the new Canvas Settings, existing Appearance Settings,
and existing grid/artboard actual-app journeys passed focused 6/6. Five new
original-resolution states were reviewed. See
`docs/evidence/SF-AUTHORING-064-CANVAS-SETTINGS.md`. Preserve all earlier
uncommitted SF-AUTHORING-063/SF-PRODUCT-UI-004 work. No new full gate, commit,
push, hosted result, or release is claimed. Remaining module work includes
broader project preferences, scale/accessibility matrices, and release QA.

## Owner-approved local visual add-on

SF-PRODUCT-UI-004 packages the approved original SF AppIcon and refines native
frosted navigator/Inspector materials under `SF-0201-009`. Three exact unit
and three affected actual-app selectors passed; seven shell states and the
built icon were visually reviewed. The XCTest Dock capture remained generic
despite correct app-bundle icon keys/files, so confirm fresh Finder/Dock display
before claiming that particular surface. See
`docs/evidence/SF-PRODUCT-UI-004-BRANDING-SHELL.md`. Do not rerun the already
passed SF-AUTHORING-063 full gate merely for this add-on, and do not commit or
push this owner-review tree.

## Historical execution policy — reset 2026-09-27

Use the specification, editable publication copy, ADRs, OPEN_DECISIONS,
IMPLEMENTATION_STATUS, CODEX_QUEUE, and AGENTS.md as the authority hierarchy.
Every prompt is a bounded user-visible vertical slice with focused tests before
its local commit. `SF-AUTHORING-063` was Development Prompt 10 of 10. Its
post-repair `./sf verify` passed 486 unit/integration and 70 UI tests on
2026-09-29. The owner requested the verified tree remain uncommitted for review;
do not push or publish. Normative modules remain Partial unless fully proven.

## Historical asset-organization work

SF-AUTHORING-063 extends the existing ImageAsset and Assets pane with optional
schema-eleven project-local folder/tags/favorite metadata. Reuse
AssetOrganizationCommandRegistry and the existing resource/history path;
never derive paths or alter image bytes. Four model/migration/static-reference
tests and one native UI journey passed. Five original-resolution states were
reviewed. The full-gate unit/integration target passed 486/486; reconciled
historical tests passed focused 10/10 and affected Inspector journeys 3/3.
An earlier managed runner could not start the UI target because macOS denied
testmanagerd with sandbox error 159. A later direct run found the two
Mobile-preset failures below. The final post-repair full gate passed 556/556;
no commit or push has been made. See
`docs/evidence/SF-AUTHORING-063-ASSET-ORGANIZATION.md`.

A later direct UI target ran 70 tests (68 passed, two failed at Mobile preset
selection adoption). The clipped-selection correction now passes its focused
model regression and both affected native UI journeys (2/2), with original-
resolution artboard evidence reviewed. See
`docs/evidence/SF-RESPONSIVE-SELECTION-RECOVERY.md`. The subsequent full local
gate passed; retain the recovery evidence and leave this tree uncommitted for
owner review.

## Historical component-visibility work

SF-AUTHORING-062 adds strict `component.exposedVisibility.v1.*` definition-child
metadata and `component.instance.v1.visibility.*` instance overrides. Reuse
`ComponentCommandRegistry`, `ComponentGraphResolver`, and the existing Content
Inspector path; do not add a parallel component state or hidden virtual layer.
Instance override wins over definition default, which wins over the child’s
canonical hidden state when no binding exists. The derived `hidden` property
feeds layout, native/Preview rendering, accessibility, and closed static CSS.
See `docs/evidence/SF-AUTHORING-062-COMPONENT-VISIBILITY.md` for focused results.
That prior prompt-ten checkpoint has since passed its local full gate; the
current bounded post-checkpoint slice is SF-AUTHORING-064 above.

## Historical image-fill work

SF-AUTHORING-061 adds one optional local AssetID image fill for Frame/Section
under `style.fill.image.v1.*`, reusing the existing resource store, typed
property commands, image decoder and native Design Inspector. The image is
painted above authored solid/gradient layers, inside the shared corner clip;
opacity applies to the composite once. Image-node and image-fill references
both count for safe asset deletion. Exact model, raster, and actual-app
Inspector/reopen selectors passed 3/3; four retained native screenshots were
reviewed. See `docs/evidence/SF-AUTHORING-061-FRAME-SECTION-IMAGE-FILL.md`. Do not
claim broad SF-0508 or SF-0801/0802 completion or push before Prompt 10.

## Prior text-foreground checkpoint

SF-AUTHORING-060 adds optional normalized whole-object foreground channels to
the existing typography namespace for Text/Button/Link. The existing token
target registry binds local Color Tokens with literal fallback; omitted values
retain automatic color. The native Design Inspector, committed CATextLayer,
inline editor, and closed static output share resolution. Focused model,
render, and actual-app evidence is in
`docs/evidence/SF-AUTHORING-060-TEXT-FOREGROUND.md`. Do not infer rich-text
spans, responsive typography color, themes, or broad SF-0507/0508/0509
completion. Prompt 8 is next; no broad gate or push before Prompt 10.

## Prior appearance-token checkpoint

SF-AUTHORING-059 migrates schema-nine fill-only token bindings into a
target-keyed schema-ten namespace. The same ColorTokenID collection and
literal-backed transaction path now resolve authored Border and Outer Shadow
colors for the canvas and closed Frame/Section static output. The native Design
Inspector target chooser binds and unbinds each target. See
`docs/evidence/SF-AUTHORING-059-APPEARANCE-TOKENS.md`; no full gate or push is
permitted before Prompt 10. Do not claim themes, aliases, arbitrary style
bindings, or full SF-0509 acceptance.

## Prior sizing checkpoint

SF-AUTHORING-058 adds strict base-only Frame/Image min/max and aspect
properties under `layout.sizing.v1.*`. Its central command adjusts fixed
geometry atomically and the Layout Inspector retains drafts locally. Desktop
numeric and pointer resize use the same clamp policy; closed static output
projects validated declarations. Four focused selectors passed, with three
native window captures reviewed; see
`docs/evidence/SF-AUTHORING-058-SIZING-CONSTRAINTS.md`. Do not claim
responsive/intrinsic sizing or full SF-0505 acceptance from this slice.

## Prior local color-token checkpoint

SF-AUTHORING-057 adds schema-9 project-local solid RGBA tokens and a stable
solid-fill binding property. The token registry and existing DocumentSession
are the only canonical write path. A missing token preserves its literal fill;
unbind freezes the resolved color, and in-use deletion is rejected. Canvas,
Preview, and closed static Frame/Section output share token resolution. The
focused model/migration/static/UI selectors and limitations are recorded in
`docs/evidence/SF-AUTHORING-057-LOCAL-COLOR-TOKENS.md`. Do not claim full
SF-0509 theme/mode, alias, broad scale, or release acceptance from this slice.

## Historical native outer-shadow checkpoint

SF-AUTHORING-056 keeps outer-shadow geometry/color in the established typed
`style.box.v1` model and adds `shadow.enabled` only for Frame/Section. Omitted
state resolves to enabled; explicit false preserves the complete shadow value
without rendering it. The identity-gated registry is the only write path, and
native canvas, Local Preview, and typed static CSS all consume the same
resolution. Do not introduce a separate shadow model or raw CSS pathway.

## Historical native box-style checkpoint

SF-AUTHORING-055 extends the existing `style.box.v1` model only for Frame and
Section with uniform content padding and explicit content clipping. The central
registry remains the sole canonical write path; the document validator rejects
invalid or duplicate content-box keys. Structural child geometry uses authored
padding, the canvas applies ancestor clips consistently, and the static
projection emits only typed `padding` and `overflow: hidden` declarations.

Focused evidence passed on 2026-09-27:

- `TransformModelTests.testDesignBoxStyleContentPaddingAndClipAreTypedReversibleAndScoped`
- `CommandKernelTests.testMultiPageStaticBuildPlanProjectsClosedFrameBoxStyle`
- `SiteForgeLaunchTests.testDesignInspectorBorderRadiusShadowUndoRedoAccessibilityJourney`

The next dependency-ready slice is the earliest queue item after this local
checkpoint. Do not add per-edge padding, margin, per-corner radius, or raw CSS
without a separately bounded requirement and evidence.

SF-AUTHORING-054 reuses the existing versioned fill-layer model, native Design
Inspector, transactional registry, renderer compositor, package/recovery
paths, and accessibility journey. It adds a closed static Frame/Section fill
projection for solid and linear-gradient layers, including safe opacity and
stable interpolation ordering; no raw CSS or browser runtime is introduced.

The next focused selectors are
`CommandKernelTests.testMultiPageStaticBuildPlanProjectsClosedFrameAndSectionFillLayers`,
`TransformModelTests.testDesignFillLayerRegistryCommitsOrderedLayersWithExactHistoryAndPersistence`,
`CanvasRendererTests.testAuthoredFillLayerCompositorPreservesOrderDisabledLayersStopsAnglesAndOpacity`,
and `SiteForgeLaunchTests.testDesignInspectorOrderedFillLayersAccessibilityJourney`.
The first three passed 3/3 on 2026-09-27. The UI selector was attempted once
but XCTest timed out while enabling automation before the body ran; rerun it
only after the macOS automation service is healthy.

## Historical static authored-box checkpoint

SF-AUTHORING-053 adds only the fixed `box-sizing: border-box` declaration to
valid typed static geometry. This retains canonical width/height as the outer
output box without adding authored CSS, a layout mode, browser work, file
generation, or publishing.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CanvasRendererTests.testStaticLayoutOutputUsesStableRoundingAndExplicitVisibilityOverrides`.

## Historical static plan-integrity checkpoint

SF-AUTHORING-052 adds a deterministic SHA-256 digest to each immutable static
plan. Its input is a path-sorted, length-delimited in-memory file list, so no
source content is surfaced and no integrity file, writer call, canonical
mutation, browser mechanism, or publishing protocol is added.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testFormFieldsPreserveAtomicHistoryAndRemapSelectOptionsOnPageDuplicate`.

## Historical static semantic-outline checkpoint

SF-AUTHORING-051 adds parent NodeID provenance to immutable static tree nodes
and emits a validated `semantic-outline.txt` plan artifact. It has no effect
on static HTML nesting, canonical state, resource bytes, browser behavior, or
output writing. Only closed semantic types and known parent identities enter
the artifact.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testMultiPageStaticBuildPlanUsesAuthoredSemanticElementResolution`.

## Historical static semantic-resolution checkpoint

SF-AUTHORING-050 makes `CanonicalSemanticElement.resolved(for:)` the shared
typed semantic boundary for Inspector and immutable static output. It accepts
only the existing closed semantic vocabulary, preserves omitted/defaulted/
authored provenance, and never emits raw markup from canonical strings.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testMultiPageStaticBuildPlanUsesAuthoredSemanticElementResolution`.

## Historical static asset-manifest checkpoint

SF-AUTHORING-049 adds a deterministic `assets.manifest.txt` planning artifact
only when an Image has a verified content-addressed reference. It exposes only
AssetID, safe output path, and validated dimensions; it never carries bytes,
original filenames, Finder paths, EXIF, a resource write, or browser work.
Invalid/missing entries are safely absent from the manifest and retain the
existing missing-resource markup state.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference`.

## Historical static-image responsive-layout checkpoint

SF-AUTHORING-048 carries only validated `ImageAsset` dimensions into
`InternalStaticImage` and emits them as integer HTML sizing hints. The actual
Image frame and Tablet/Mobile visibility stay wholly within the existing typed
`StaticLayoutOutputEmitter` cascade; no intrinsic aspect-ratio rule, source
set, remote URL, resource write, transform, or browser execution is added.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference`.

## Historical static-image presentation checkpoint

SF-AUTHORING-047 adds `StaticImageStyleOutputEmitter`. It maps only the typed
canonical Fit/Fill/Stretch enum and bounded focal point to a fixed
`object-fit`/`object-position` rule on the existing NodeID selector. The
projection is static plan metadata: it preserves the referenced original
resource and creates no crop, rendition, transform, browser path, or generated
resource write.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference`.

## Historical static-image reference checkpoint

SF-AUTHORING-046 carries canonical Image metadata into the static tree through
`InternalStaticImage`. `MultiPageStaticBuildPlanner` accepts only existing
verified content-addressed export entries, mapping them to a safe `src`; a
missing or corrupt entry instead leaves an explicit missing-resource marker
while retaining the stable AssetID and escaped alt/decorative semantics. This
does not export bytes, use filesystem paths or remote URLs, or start a browser
image-loading path.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference`.

## Historical static-typography checkpoint

SF-AUTHORING-045 makes canonical plain Text content visible in the immutable
static tree and escapes it only at the Safe HTML boundary. Its stylesheet
projection maps the closed typography model to size, weight, line-height,
tracking, alignment, and portable `system-ui` for the canonical System family.
Any other installed-family intent is preserved canonically but omitted from
static CSS rather than being emitted as an arbitrary CSS string. Component
text defaults/overrides are not mutated or flattened in this slice.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CanvasRendererTests.testStaticTypographyOutputEscapesTextAndUsesAllowlistedCanonicalValues`.

## Historical static-layout plan checkpoint

SF-AUTHORING-044 makes the SF-AUTHORING-043 typed layout projection available
to `MultiPageStaticBuildPlanner` as a deterministic in-memory `styles.css`
file. The stylesheet is generated only from canonical document nodes using the
existing responsive resolver; it has no standalone state, file writer call,
HTML-shell link, browser runtime, raw CSS input, or publishing path.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testMultiPageStaticBuildPlanIncludesTypedLayoutStylesheet`.

## Historical static-layout checkpoint

SF-AUTHORING-043 adds `StaticLayoutOutputEmitter`, an immutable projection of
typed canonical base geometry, explicit Tablet/Mobile overrides, and
breakpoint visibility. It emits a fixed absolute-position CSS allowlist with
NodeID-derived selectors and canonical three-decimal rounding. Responsive
rules are emitted only for explicitly authored properties; base visibility
continues to cascade naturally until a breakpoint override is present. This
does not add raw CSS, browser execution, flex/grid/container-query authoring,
static-file export, or publishing.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CanvasRendererTests.testStaticLayoutOutputUsesStableRoundingAndExplicitVisibilityOverrides`.

## Historical static-navigation checkpoint

SF-AUTHORING-042 adds `StaticNavigationEmitter`, an immutable static-output
projection from the canonical navigator order. It includes only Home and
standard pages with an existing validated static route, derives a stable
PageID-backed link for each, emits escaped labels/hrefs, and applies
`aria-current=page` only to the output page being built. Not Found and
component-definition pages are intentionally absent. It is not a navigation
template, redirect, dynamic-routing, browser-runtime, static-file-export, or
publishing feature. Nested generated paths resolve relative links without
assuming a site-root router.

No tests were run under the owner-directed pause. The next allowed focused
selector is `CanvasRendererTests.testStaticNavigationProjectionPreservesPageOrderAndAccessibleCurrentState`.

## Historical static-control checkpoint

SF-AUTHORING-041 adds immutable static-tree projection for existing canonical
Button and Link controls. `InternalDocumentRenderTreeCompiler` is the sole
output boundary: it accepts only `CanonicalLinkTarget` values that already pass
canonical validation, resolves internal Page/Section references only against
the current package route map, escapes output, and leaves missing targets
inert. Static Buttons are deliberately emitted as disabled `type=button`
controls: no browser action or submission behavior exists. Typed new-context
Links emit only `target=_blank` with `rel=noopener noreferrer`.

No local test execution was performed for this checkpoint under the current
owner-directed test pause. The focused compiler regression
`CanvasRendererTests.testStaticControlCompilerEscapesTypedRoutesAndKeepsMissingTargetsInert`
now covers escaped external/section routes, stable anchors, missing targets,
and inert button output; it must be run before any runtime or export work.

## Historical checkpoint

SF-AUTHORING-038 adds fixed-breakpoint static CSS emission for canonical
geometry and visibility overrides. SF-AUTHORING-037 Local form-validation and
preview-state foundation v1 remains IN PROGRESS. `LocalFormValidationEngine` resolves only caller-owned,
non-Codable `FormVisitorValueSnapshot` input against canonical Form metadata.
Its results contain stable document/revision/form/field identities and failure
categories only; it has no command, history, package, autosave, recovery,
network, browser, or submission path. The Form Inspector presents its adopted
category-only empty-draft result without retaining input; focused model coverage
is 3/3. Do not make visitor values canonical. The next bounded Form task is
authored validation-rule configuration through the existing Inspector registry.

SF-AUTHORING-036 Accessible form authoring v1 remains IN PROGRESS. Form is now
an enabled Elements/Insert container and its Text children have native bounded
Content Inspector field controls. `FormInspectorCommandRegistry` is the sole
identity-gated canonical edit boundary; focused foundation plus current-slice
coverage is green (9/9). Actual-app UI evidence and all visitor/runtime
submission behavior remain deferred.

## Historical Form boundary

- Form field metadata is valid only on Text nodes owned by a Form node.
- Static output permits only escaped text/email/textarea/checkbox/select and
  disabled unconfigured-submit controls; it has no runtime submission path.
- Page duplication remaps stable select-option IDs but keeps labels and values.
- The next bounded task is actual-app keyboard, pointer, and accessibility
  evidence for Form insertion and field editing. Keep visitor values,
  submission destinations, validation rules, anti-abuse, generated-site
  runtime, scale, and release acceptance out of scope.

## Earlier delivered boundary

- `WorkspaceShellState` owns a scene-local `LocalPreviewState` containing an
  immutable `CanvasPreviewSceneSnapshot` captured only by Preview or Refresh.
- Preview renders authored Frame, Text, fill and Image content without editor
  selection, grid, guides or insertion chrome. It never writes document or
  history state.
- The Preview toolbar and Command-Shift-P route to the same state; Refresh
  adopts only a matching newer render revision; Done/Escape closes and restores
  editor focus.
- The constrained-window reveal helper aligns the live target, while retaining
  the approved 1100-point production window width on narrow displays.

## Evidence and invariants

- `docs/evidence/SF-AUTHORING-025-LOCAL-PREVIEW.md` records scope and focused
  tests. The UI journey retains `SF-AUTHORING-025 local preview authored
  snapshot` in its result bundle.
- `CanvasRendererTests.testLocalPreviewStateFreezesRevisionAndRejectsStaleRefreshes`
  and `SiteForgeLaunchTests.testLocalPreviewRefreshesOnlyOnExplicitRequestJourney`
  are the focused Preview checks.
- Do not turn preview scene state into canonical document/history state or add
  browser runtime, generated HTML/CSS/JS, export, publishing, routes, remote
  content or CMS. SF-1203 semantic authoring begins as its own bounded slice.

## Deferred scope

SF-1201 and SF-1202 remain Partial outside this bounded local-preview surface:
runtime bundles, generated render trees, export/preview parity, large-project
performance certification, broad accessibility matrices and release acceptance
remain future work.
