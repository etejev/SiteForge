# Open Decisions

## Current execution handoff — native XCTest authentication,2026-10-28

RESOLVED for this attempt: owner completed authentication; focused07cad6e0
executes and passes all three affected UI methods. No policy/settings change.
Final full-e7ee511e now passes785 non-UI/151 UI,0 failures,3 intentional owner
skips. No current authentication/verification blocker. Earlier handoff facts
below are historical; no push or installation is authorized.

No new product/architecture decision or security-policy waiver is requested.
The three remaining acceptance corrections compile; focused6c4a1ac5 executed
zero UI methods because testmanagerd requested “Enable UI Automation” through
LocalAuthentication at11:21:49-0400 and timed out11:22:49. Recommended default:
owner present for ONE isolated retry, handling Touch ID/Use Password only inside
the macOS dialog. Alternative: defer UI/final gate and local commit. Tradeoff:
only the latter leaves acceptance incomplete; neither authorizes changing privacy
settings, bypassing authentication or exposing credentials. Affected acceptance:
SF-0604-006,SF-1207-006,SF-0407-006 and the preserved source batch. Deadline:
before the next UI attempt/final gate. Safe assumption: preserve source, project
and recovery data, no unchanged retry/commit/push/install. Exact artifact and
failure-original review are in the ten-workflow integration receipt.

## OD-027 — Verification host cache eviction and retained evidence

Resolved scope, 2026-10-26: owner authorized build-cache cleanup only. With no
active app/test/build process, removed approximately 1.7 GiB from seven confirmed
regenerable directories: owner-local/experimental DerivedData Intermediates,
installed-review-runner Intermediates.noindex/SDKExplicitPrecompiledModules/
ModuleCache.noindex, and ci-ui-baseline Intermediates.noindex/ModuleCache.noindex.
All targets were inside ignored `.build/`; app products/backups, every project,
recovery candidate, result bundle and screenshot were preserved. Rebuild restores
these caches; no system service/privacy setting changed. One post-cleanup full
gate is authorized; cleanup is not proof that the OS eviction trigger is fixed.

Follow-up: one isolated retry passes 1/1, 99.566s, unchanged source. No runner
remains. Full gate is still failed and no broad retry/cleanup has been performed.

2026-10-26 full gate completed with 733 non-UI and 138 UI passes, one test runner
SIGKILL and three owner-session skips. macOS runningboard logs prove cache_delete
requested CacheDeleteAppContainerCaches termination of the active XCTest runner
at initial app readiness (02:27:30 -0400), before asset-authoring actions. No app
assertion or owner/agent cancellation caused this. Full gate remains failed.
Disk has 14 GiB free / 93% used; storage pressure as the trigger is not proved.
Retained ignored evidence occupies 22 GiB; regenerable local build data 4.3 GiB.

Recommended default: owner-authorized cleanup of only exact regenerable local
SiteForge build-cache directories after active testing ends, preserving every
project, recovery candidate, result bundle and screenshot. Alternative: owner
manages macOS storage/archives retained evidence to an owner-chosen destination.
Tradeoff: build cleanup needs rebuilding and may not prevent OS eviction; evidence
archival requires a trusted destination, and deleting retained evidence is not
assumed authorized. Do not disable cache_delete, change privacy/services or waive
the full gate. A concise owner choice was requested; no cleanup has occurred.
Affected: SF-LOCAL-BUILDER-006, SF-0801-005/006, SF-1201-004/006.
Deadline: before another broad verification attempt or installed delivery.
Safe assumption: preserve all data, finish one diagnosis-backed isolated retry,
leave the milestone IN PROGRESS and installed app unchanged.

## OD-026 — Local installed-build signature boundary

Resolved, 2026-10-26: owner explicitly allowed the existing local-only ad-hoc
signature. Use only the existing owner-local refresh workflow after genuinely
green full verification and normal Saved/Quit/source-identity checks. No Apple
certificate, Developer ID, notarization, publishing, commit or push is authorized.

The existing owner-local packaging/install workflow applies an ad-hoc signature
(`codesign --sign -`) with no certificate, Developer ID, notarization or publishing.
The current no-signing instruction may prohibit even this local step. A concise
owner clarification was requested; no signing or installation has been performed.
Recommended default: authorize only the existing local integrity signature after
the frozen full gate passes. Alternative: leave the installed build unchanged.
Tradeoff: the latter preserves the literal prohibition but delays installed
delivery; neither option changes canonical data or permits distribution signing.
Affected: SF-LOCAL-BUILDER-006 and SF-1201-004/006 local delivery evidence.
Decision deadline: before any installed refresh. Safe temporary assumption: finish
local verification only; retain the Saved owner project and existing installed app.

## OD-025 continuation — Native/XCTest discrepancy, 2026-10-25

Native comparison was performed by the agent through exact Test navigator actions;
owner action is no longer requested for that comparison. Reuse passes 1/1 and
corrected conversion passes 1/1. Conversion was an off-viewport AX query error;
bounded native scrolling fixes it without changing assertions. Ordinary native
identity differs from the earlier OwnerTesting CLI run; broader isolated-identity
parity is not inferred. Fresh full verification and installed delivery remain
pending; previous recommendations below describe the earlier handoff only.

Affected: SF-0806-003/005, SF-1201-004/006, SF-1203-003/004, SF-LOCAL-BUILDER-006.
Repository/build and 732 non-UI tests pass. UI had six passes, two assertions and
one deliberate cancellation. One diagnostic pair failed differently: Save now
succeeds but Preview discovery fails; conversion fails before editing. XCTest
loses frames/identifiers while read-only native inspection exposes the complete
shipping tree. Recordings and artifacts: latest 006 evidence. No security/privacy/
service settings changed, and no owner document was terminated.

Recommended owner action: run these through Xcode's normal Test navigator:
`SiteForgeLaunchTests/testAuroraRelatedPageReuseNativeCopyAndSafariJourney` and
`SiteForgeLaunchTests/testAuroraResponsiveContentConversionPreservesSelectionAndReflowsAcrossPresetsJourney`.
Alternative: owner-directed macOS/Xcode automation environment repair. Tradeoff:
native execution needs owner involvement; identical CLI retries add no diagnosis.
Deadline: before full acceptance or installed replacement. Safe assumption:
retain saved revision-245 website and all evidence; installed app stays unchanged,
full verification remains incomplete, and no further automated retry without new
evidence. No claim that the discrepancy exonerates every production path.

## OD-025 — Native acceptance / final collector host readiness

Current disposition: owner completed setup and the explicitly authorized
authentication retry passed. Subsequent public-control authoring runs execute
normally. The setup/authentication observations below remain historical evidence,
not an outstanding owner request. Final integrated verification remains pending
actual website acceptance; no full-pass or installed-update claim is made.

Fresh 2026-10-24 owner-completed setup supersedes the Install Required boundary:
selected `xcodebuild -checkFirstLaunchStatus` now exits 0, independently confirmed
in this task. No further request to repeat setup/authentication is warranted.
This is readiness evidence, not a new test/full-pass or installed-delivery claim.

Subsequent ONE alternate public-control owner-session UI audit builds, but its
fresh run fails before the method: testmanagerd's automation writer requires
authentication; LocalAuthentication requests Enable UI Automation and no completion
precedes the 60-second timeout. This is a fresh, separately evidenced owner
authentication boundary, not a request to repeat completed Xcode installation.
Bundle/log: ignored `.codex-loop/dark-flow-audit.xcresult` / `dark-flow-audit.log`.
Ordinary app remains running; no runner remains. Recommended default: one retry
only when the owner confirms readiness to complete macOS authentication personally.
Alternative: defer native authoring/verification without calling Dark Flow finished.
Safe assumption: preserve saved copy, original projects and recovery; no privacy,
service or authorization bypass. Affected SF-1902-004/006 and SF-0508-006;
deadline before public-control authoring/verification acceptance. No credentials
are requested in chat. Native SiteForge inspection also independently disconnects,
while Finder/Xcode native inspection works; no product cause is yet established.

Current observed boundary — 2026-10-24: supported native app inspection opened
the selected Xcode normally and found an actual **Install Required** dialog.
Its message says system-wide components must be installed to use Xcode and
manage shared resources such as simulators and connected devices. Visible
buttons: **Quit**, **Install**. Screenshot retained at ignored
`.codex-loop/xcode-readiness-20261024/install-required.png`. Dialog left open;
Install was NOT clicked. No agreement, authentication, component/platform choice,
download, installer, permission/service or global toolchain change was performed.

One concrete owner action: choose **Install** in this Xcode dialog and personally
complete Apple's ensuing setup/authentication. Credentials stay in macOS UI.
Recommended default: complete Apple's required components, then confirm the
read-only status succeeds before ONE accumulated collector retry. Alternative:
Quit/defer setup and retain incomplete verification/local delivery. Tradeoff:
system-wide installation is owner-controlled; deferral leaves required acceptance
blocked. Requirements SF-1902-004/006, SF-0201-006/008, SF-0206-006; deadline before
full-pass or installed-delivery claims. Safe assumption: preserve all work and
ordinary app/recovery; do not bypass preflight or repeat unchanged tests.
This concrete observation supersedes the earlier generic setup handoff. No
test or collector ran during inspection, and no new test/visual product evidence
is claimed. Prior focused results and fixed-template limitations remain unchanged.

Historical status, 2026-10-23 20:07: native authentication was no longer blocking.
Thirteen distinct focused UI workflows have passing results; the supported
accumulated full collector instead exits **blocked** at its mandatory Xcode
readiness check. `xcodebuild -checkFirstLaunchStatus` returns 69 without a
diagnostic. Selected Xcode is `/Applications/Xcode.app`, version 27.1/build
27A9275. This does not establish which Apple setup component is outstanding.
No current authentication/setup dialog was confirmed visible and no installer,
agreement, privacy/service or global toolchain change was performed.

Evidence: ignored `.codex-loop/full-verification/20261023-200720-8f1f5b4c/`
`state.json` / `REPORT.md`; preflight detail `xcode-first-launch-setup-required`,
exit 1, zero build/code/UI stages executed. Collector exited, no duplicate run.
Source fingerprint `d3b06b9d…`. Separately, repository/security/traceability/
architecture/evidence checks passed, with 440 bounded requirement records.

Recommended owner action: inspect Xcode's own first-launch/setup state and
personally complete any required Apple setup, agreement or device authentication.
Keep credentials exclusively in Apple's UI. Then reassess the required collector
once host readiness changes. Alternative: leave full acceptance and installed
delivery deferred. Changing or bypassing this mandatory preflight is not approved.
Affected requirements: SF-1902-004/006, SF-0201-006/008, SF-0206-006. Deadline:
before any accumulated full-pass or installed-update claim. Safe assumption:
preserve all uncommitted work and the ordinary installed app/owner recovery;
do not repeat unchanged broad tests or install over unknown owner work.

Historical status: authentication stall bypassed by the single 2026-10-23 17:19 retry;
native acceptance remains pending a concrete test-navigation correction; no waiver.

Latest observation supersedes the owner-action request below: the one authorized
retry initialized and executed the component workflow. Owner reports no prompt;
none was confirmed visible. It failed at line 5644 querying Design-only provenance
while Layout remained selected. No privacy/security change or owner authentication
action is currently requested. See the evidence's Single isolated retry section.

Affected bounded requirements: SF-1902-004/006 and pending SF-0201-006/008,
SF-0206-006. Source remains unchanged at `f601b53b…`; the existing 717 code
passes and repository checks were NOT rerun during this diagnosis.

The failed xcresult's session/daemon logs and narrow archived system-log slice
prove the boundary, before any product test method:

- 04:51:15.624: runner session initiated successfully.
- 04:51:15.625: test-daemon authorization succeeded.
- 04:51:15.656: testmanagerd requested UI Automation from Apple's writer service.
- 04:51:15.669: LocalAuthentication returned -1004, “User interaction is required.”
- 04:51:15.671: interactive device-owner authentication requested, labeled
  “Enable UI Automation”; the UI service reported showing UI without an error.
- No authentication completion is present before the runner's 60-second timeout.

This proves an incomplete authentication prerequisite, not why the user interaction
failed to complete or whether a prompt is visible now. It is not a SiteForge AX,
window, property, document or permission-dialog implementation failure. Reopening
SiteForge is NOT a demonstrated test-manager repair; the earlier suggestion is
withdrawn for this blocker. Normal saved/quit proof remains a separate future
installation safeguard.

Read-only alternatives checked: selected developer/tool/framework paths consistently
use Xcode.app; no DEVELOPER_DIR/TOOLCHAINS/SDKROOT/architecture override is inherited;
runner is universal arm64/x86_64 and the actual destination was arm64. Fresh app/
runner/provision identities and source fingerprint match. Test-manager authorization
succeeded, so an initial runner connection/authorization rejection is ruled out.
Developer mode is already enabled. Current GUI registry reports a logged-in console
session; no locked-console denial appears in the relevant trace. No unsupported
permission, signing-policy, architecture or global toolchain change is justified.

The simulator mismatch also appears in the successful 717-code run. The last
successful UI session (Xcode 27.0) completed its automation handshake in about
8 ms; the failed session uses Xcode 27.1. The warning is not proven causal to the
authentication stall, and no simulator/OS/Xcode update is prescribed. A read-only
first-launch check exits 69; pending setup is recorded, not assumed to explain
this boundary. No first-launch installer/license action was run.

One necessary owner action: be present at the Mac and complete macOS's own
“Enable UI Automation” authentication during ONE isolated pending-selector retry.
Credentials/Touch ID stay entirely in the system dialog, never in chat. Owner
readiness has been requested; no further native launch occurs before that changed
prerequisite. No privacy reset, service restart or security bypass is offered.
The alternative is to defer native acceptance and preserve all current work.
Deadline: before any changed-build native/full/installed acceptance claim.

The earlier computer-use transport limitation is separate; it does not explain
XCTest authentication. No independent control target was needed: the trace already
locates failure before project test execution, and another unattended control would
hit the same unresolved authentication gate. No additional test run, owner-data
operation, ordinary-app termination or installed update occurred during diagnosis.

Evidence and current acceptance inventory:
`evidence/SF-LOCAL-BUILDER-005-INTEGRATION.md` (Native initialization diagnosis).
Private ignored extracts: `.codex-loop/native-initialization-diagnosis-20261023/`.
Historical October 21 full gate (815) and October 23 code gate (717) remain valid
only for their respective scopes; neither is current native acceptance. Installation
remains the older 26.10.21 app; all source work stays uncommitted.

## OD-024 — Dismiss system notification covering native test controls

Status: Resolved — 2026-10-20. Owner confirmed the screen is clear, then the
unchanged pointer journey passed 1/1 in 52.649s, bundle
`focused-75b3a453-d776-44f2-8d7c-cb50f82a0b96.xcresult`. Native toolbar Undo
restored Home after target removal. Both fresh screenshots were visually
inspected; no banner covers the toolbar. No command/history changes or weaker
assertions were necessary. This is focused acceptance, not a full gate.
Historical temporary
captures are no longer available, an evidence-retention limitation only.
No further dismissal request is needed. No product waiver or privacy
change requested. The Mac is unlocked and both pending structural selectors pass
2/2. The next integrated attempt fails the compact Button/Link Undo assertion
at line 5769. Its fresh capture shows an unrelated calendar notification covering
the title-bar Undo/Redo area; the log reports a center-point fallback for Undo
at screen point (1580, 76), inside that banner. The final target remains removed.
This is not accepted as proof of a command/history defect or a passing gate.

- Evidence: `full-77de4af7-db9f-4e5c-a724-33f7a8e611e4.xcresult`, compact target
  capture `B8968276-F03D-4D09-A472-C0CF402CEFEE.png`, retained owner-locally.
- Recommended default: owner dismisses that one upper-right notification normally.
  No notification preferences, Focus settings, TCC or system services are changed.
- Alternative: owner may wait until the banner disappears and confirm it is gone.
  Changing product Undo or replacing the pointer assertion would hide the cause.
- Tradeoff: the banner obstructs genuine native input and contaminates title-bar
  screenshots; it does not require changing project/recovery data.
- Native inspection exposes only the Notification Center calendar widget, not a
  standard dismiss target for this banner. No blind cross-app click was attempted.
- Affected requirements: bounded SF-0201-006/008, SF-0702-006 and local-builder
  visual/runtime acceptance. Deadline: before the exact compact Button/Link rerun.
- Safe temporary assumption: preserve source, original Aurora and all recovery;
  no collector remains. Resume one exact selector after dismissal, then the
  accumulated gate. Phase-two production consolidation has not started.

## OD-023 — Dismiss unrelated macOS Safari-control permission request

Status: Resolved — 2026-10-18. Owner reported no prompt visible. The exact
appearance journey then passed 1/1 (37.828s), bundle
`focused-4de2a0c3-86e7-45cb-a6de-acd755018b88.xcresult`. No permission was
granted or reset by the agent. The following modal evidence is historical,
not a current blocker. No product waiver requested.
The final integrated attempt exposed six stale model/fixture expectations and
two Settings journeys. Corrected historical fixture shapes, Welcome announcement
and owner-selected Dark-default expectations pass all six focused model checks
and the grouped Settings journey. The remaining appearance journey is blocked
by a real UserNotificationCenter dialog, not an inferred product-disabled state.
Its retained recording explicitly shows “ChatGPT wants access to control Safari”
covering Settings; the failed AX path marks Application/Window Disabled.
Bundle: `focused-2e1209c7-8cce-445c-9940-443f39f64599.xcresult`.

- Recommended default: owner chooses **Don’t Allow** on that system prompt.
  Existing native accessibility/browser inspection does not need this extra
  Apple Events permission; do not grant broader access for a test.
- Alternative: owner may independently choose Allow if desired. The agent will
  not make a security/privacy permission choice or reset permissions.
- Tradeoff: dismissing the modal restores normal input; leaving it open blocks
  native UI verification. No canonical project or recovery data is implicated.
- Affected requirements: bounded SF-0206-006, SF-1203-006 and SF-LOCAL-BUILDER-001.
- Deadline: before rerunning the exact appearance journey and integrated gate.
- Safe assumption: preserve every edit and all owner data; no active test/build
  is left running, no full verification pass or completion is claimed.

## OD-022 — Unlock macOS for remaining local-builder UI acceptance

Status: Resolved normal owner unlock — 2026-10-18. No product decision or waiver.
Console was checked once as unlocked, with no stale owned runner. The Aurora
sample journey passes 1/1 (final settled capture rerun, 50.549s), legacy-history
restore/discard passes 1/1 (16.472s), and real isolated first/clean/forced-crash
startup passes 1/1 (24.468s). The ordinary app was then saved/quit normally and
safely updated; installed sample/original-reopen passes 1/1 (38.945s), followed
by installed responsive/Preview/export acceptance 1/1 (51.691s). No lock/privacy
bypass, genuine recovery deletion, or owner-app force termination occurred.
The following locked attempt is historical, not a current blocker.

Previously owner action required again — 2026-10-18. No product decision or waiver.
The new exact Aurora packaged-sample journey compiled, but its launch stalled
while read-only console inspection reported both lock indicators. The single
attempt was safely interrupted; its result records `Testing was canceled`,
zero passes. Bundle: `focused-5fd1bcb7-d14a-4029-99c8-e91a5ebb77ab.xcresult`.
No test runner remains; the ordinary Aurora app and all recovery are preserved.
Recommended default: unlock normally and keep the Mac awake for the native
sample/visual acceptance. No privacy setting changes or credentials are needed.
The following successful restart and earlier evidence remain historical.

Previously resolved owner action — 2026-10-17. No product decision or waiver.
Owner unlocked the Mac and restarted Xcode after a distinct automation-mode
initialization timeout. Both exact Preview journeys then passed 2/2 (51.205s),
including the previously blocked pointer action and actual Safari content.
Bundle: `focused-4a13268d-bc6f-4e99-96e4-f68eb103b089.xcresult`.
The following lock evidence is historical, not a current blocker.

- Context: focused native tests resumed successfully after the Xcode restart.
  Later runs lost Safari's accessibility tree and then failed before SiteForge
  activation with Running Background. Read-only IORegistry inspection confirms
  both `IOConsoleLocked = Yes` and `CGSSessionScreenIsLocked = Yes`; this is not
  an inferred product failure or a request to alter window presentation.
- Recommended default: owner unlocks the Mac normally and keeps it awake for
  the remaining exact focused UI checks. No credentials are requested.
- Alternative: defer native acceptance until the next unlocked local session.
- Tradeoff: owner presence versus waiting; the agent will not unlock the Mac,
  change lock/privacy settings, or terminate shared system services.
- Affected requirements: SF-1201-002/003/006/008, SF-0401-003/006,
  SF-0405-003/006 and SF-LOCAL-BUILDER-001 visual/native acceptance.
- Deadline: before remaining browser/authoring visuals and the integrated gate.
- Safe temporary assumption: preserve every edit, the saved ordinary Aurora
  project and genuine recovery. No commit, push, app replacement or completion
  claim. The final failed focused process exited; no test runner remains.

## OD-021 — Recover native XCTest automation availability

Status: Resolved owner action — 2026-10-15. No product requirement waiver.
The owner quit/reopened Xcode and confirmed ready. The four exact native
journeys subsequently passed 4/4 (399.845 seconds), with twelve original-size
captures reviewed. No privacy reset or shared-service termination was used.
The following records the historical failure and recovery recommendation.

- Context: the latest complete attempt passed 636 model tests and 93 UI
  journeys, recorded four concrete UI failures, then its next runner timed out
  enabling automation mode. After bounded corrections compiled, both the normal
  focused route and supported already-built route failed at the same 60-second
  initialization handshake before executing any test. Console inspection shows
  an unlocked logged-in session; no SiteForge test/app/xcodebuild process remains.
- Recommended default: owner saves any Xcode work, quits Xcode normally and
  reopens it with the Mac unlocked, then resumes the four exact focused journeys.
  This is a recovery attempt, not an assurance that restarting Xcode fixes macOS.
- Alternative: owner performs a normal system restart after saving work if the
  native Xcode route remains unavailable. Do not reset TCC or broaden permissions.
- Tradeoff: temporary interruption versus preserving system privacy and other
  applications; the agent will not terminate shared testmanagerd/WindowServer.
- Affected requirements: SF-0201-008, SF-0407-006/008, SF-0602-006/008,
  SF-0701-006/008 and SF-1201-006/008; SF-PRODUCT-UI-010 acceptance/delivery.
- Deadline: before the remaining native acceptance and authoritative full gate.
- Safe temporary assumption: retain all edits and original recovery; no commit,
  push or completion claim until focused native checks and final verification pass.

## OD-020 — Dismiss outstanding macOS test-host Documents prompt

Status: Resolved owner action — 2026-10-15.
The owner answered the original permission request with "done". The subsequent
native recording confirms that the system permission prompt is absent. No
agent changed a privacy permission; no product-policy change was requested.

- Context: the isolated test host's old raw checkout fixture read triggered a
  macOS Documents permission prompt. A process sample and TCC logs confirm the
  request. After fixtures moved into test resources/application-owned temporary
  storage, the focused model checks pass without that access. The later native
  recovery recording still shows the outstanding system prompt above the real
  reset confirmation, preventing its accessibility query. Computer Use refuses
  access to UserNotificationCenter for safety; no workaround is authorized.
- Recommended default: the owner dismisses the outstanding prompt with
  **Don't Allow**. The corrected fixture paths do not need Documents permission.
- Alternative: owner explicitly allows Documents access for that local test
  host; this grants broader access than the fixture checks now require.
- Tradeoff: denial keeps the test host narrowly scoped; allowing avoids that
  individual prompt but is unnecessary for the corrected test architecture.
- Affected requirements: focused SF-0701-006 and SF-0308-006 acceptance;
  SF-PRODUCT-UI-010 local verification/delivery. No requirement is waived.
- Deadline: before resuming the recovery UI journey and final accumulated gate.
- Safe temporary assumption: preserve all changes and genuine owner recovery;
  no commit, installation replacement or completion claim. All focused test
  runners exited; the owner's regular installed app remains untouched.

## OD-019 — Explicit migration of retained component override conflicts

Status: Open — 2026-10-13

- Needed by: future retargeting/conversion beyond SF-AUTHORING-120 recovery.
- Context: SF-0902-004/005 and SF-0905-003/004/005 require stable or migrated
  intent but do not define candidate eligibility, value conversion, source
  tombstones or collision resolution. Current override keys retain definition
  and typed property IDs, not a deleted binding's original source/label.
  Guessing a new source violates SF-AUTHORING-113's transition guards.
- Recommended default: retain reset/restore-original/navigation only until the
  owner approves explicit same-type target selection, collision policy and
  preview/confirmation. Reject cross-type conversion; never select by label.
- Alternatives: add versioned source tombstones for original-binding restore
  (broader persistence/transfer obligations), or approve authored mappings with
  explicit typed conversions (requires individual conversion specifications).
- Tradeoffs: conservative recovery preserves all intent and exact history but
  requires original project/history to restore a removed binding. Migration
  could improve convenience but introduces ambiguity and loss/privacy risks.
- Affected requirements: SF-0902-004/005, SF-0905-003/004/005, SF-0308-004/008.
- Decision deadline: before enabling any retarget/convert control or serialized
  migration metadata. No decision blocks the independent safe recovery slice.
- Safe temporary assumption: canonical conflicts remain serializable; explicit
  confirmed reset removes only identified authored values. Original stable IDs
  can be restored through existing Undo or original package/definition data.
  Available definitions/sources are inspectable; no automatic reassignment.

## OD-018 — Canonical ownership of supplied component slot content

Status: Open — 2026-10-13

- Needed by: supplied-content authoring in `SF-AUTHORING-118` under
  `SF-0902`, `SF-0903` and `SF-0905`.
- Context: §9.3 requires ordered projected content, constraints, fallback and
  stable identity but does not choose storage ownership or slot cardinality.
  ADR-0018 and the shipped canonical rules explicitly require linked instances
  to be childless; ordinary children have exactly one ordered canonical parent.
  Enabling instance children changes insertion, history, transfer, selection,
  layout and rendering boundaries and is a consequential architecture change.
- Recommended default: approve instance-owned canonical child subtrees with
  explicit stable slot membership and ordered roots, reusing the document graph
  and command kernel. Supplying content replaces only that slot's fallback in
  derived projection; the definition never acquires instance-owned nodes.
  Slot removal must retain supplied content as a recoverable conflict until an
  explicit migration/reset/detach transaction. Approve zero-or-more supplied
  roots and an authored empty state separately from inheritance.
- Alternatives: separate instance-content graphs (keeps instances childless but
  adds graph-role/persistence/navigation complexity); or retain fallback-only
  slots (safe and useful, but cannot complete supplied-content requirements).
  A serialized secondary node store in a property is not recommended because
  it duplicates the canonical graph and mutation rules.
- Tradeoffs: canonical children reuse existing ownership/history but require
  explicit projection-aware eligibility and conflict repair. Separate graphs
  isolate storage but broaden lifecycle and transfer integration.
- Affected requirements: `SF-0304-001/003/005`, `SF-0902-001`–`008`,
  `SF-0903-001`–`008`, `SF-0905-001`–`008`, and `SF-0308-003/004/005`.
- Decision deadline: before supplied-content mutations or any migration that
  makes linked instances canonical parents.
- Safe temporary assumption: SF-AUTHORING-118 exposes non-root existing
  Frame/Section/Stack/Grid definition containers as named fallback slots.
  Their current ordered childIDs remain the sole content/ownership source;
  instances inherit and inspect/edit the definition fallback. Nested slots
  and supplied-content storage are unavailable, with no fake controls or
  silent conversion. Older packages remain readable.

## OD-016 — Initial starter-template catalogue and canonical content

Status: Approved — 2026-10-05

- Needed by: the first production template/onboarding slice under `SF-0204`.
- Context: the specification requires choosing a template, editable/removable
  examples, stable template identity, migration, Preview/output behavior, and
  resettable learning state, but it does not define the initial template set or
  authorize SiteForge to invent branded page copy/assets. Those choices become
  persistent product content and cannot be inferred from competitor products.
- Approved decision: retain **Blank Site** as the neutral existing creation
  path and add exactly one local **Starter Site** template. The Starter Site
  contains exactly two ordinary pages, **Home** and **About**, with semantic
  Header/Main/Footer structure, system typography, no remote assets, explicit
  template provenance, and entirely editable/removable neutral generic copy.
  It does not present a Not Found/404 page as starter content. Existing internal
  missing-route/404 handling remains separate where the specification requires
  it.
- Alternatives: ship only Blank Site (simpler but does not satisfy “choose a
  template”); approve several vertical templates (more useful but creates a
  larger content, localization, migration, and visual-review commitment); or
  defer the entire template catalogue while keeping New Site direct.
- Tradeoffs: one curated local starter proves the canonical workflow with low
  maintenance and no licensing/network dependency, but its content establishes
  visible product direction. Multiple templates improve discovery but broaden
  quality and accessibility obligations immediately.
- Affected requirements: `SF-0204-001`–`SF-0204-008`, supporting
  `SF-0301-001/002/005`, `SF-1201-003`, and `SF-1203-002/003/004`.
- Decision deadline: before SF-AUTHORING-106 writes any canonical template
  fixture or migration.
- Implementation consequence: SF-AUTHORING-106 is unblocked. Keep New Site's
  Blank Site option unchanged and do not add branded identity, licensed
  content, remote media, or additional template/page choices.

## OD-015 — Initial structural-element defaults

Status: Approved — 2026-08-12

- Needed by: the first persisted Section, Stack, and Grid authoring slice.
- Context: `SF-0502-001` and `SF-0503-001` require explicit, versioned
  defaults that distinguish defaulted from authored values. The specification
  defines the required semantics but does not select numerical starting values
  for a Section's padding/size, a Stack's gap/padding/alignment, or a Grid's
  columns/gap/padding. These values would become canonical package data,
  migration behavior, layout results, undo/redo results, and exported-layout
  semantics, so they must not be silently invented in implementation.
- Recommended default: Section — 960 × 320 points, 48-point padding, vertical
  structural container; Stack — vertical axis, 24-point gap, 24-point padding,
  start alignment; Grid — two equal columns, 24-point gap, 24-point padding,
  row-major placement. All values would be stored as `.defaulted`, with no
  property editor in this bounded slice.
- Alternatives: compact defaults (24-point Section padding and 16-point
  Stack/Grid spacing) for denser composition; or defer concrete geometry until
  an inspector-property milestone, leaving these catalogue entries unavailable.
- Tradeoffs: the recommended values create calm, legible first results and are
  easy to explain, but they establish persistent product behavior before a
  broader layout-property editor exists. Compact values reduce whitespace but
  offer less visual separation. Deferral avoids a decision but prevents the
  requested real insertion capability.
- Approved decision: adopt the recommended defaults as the canonical v1
  structural-element baseline. Schema v4 persists them with `.defaulted`
  provenance; supported schema-v3 documents decode unchanged and re-save as
  v4 because they contain no Section, Stack, or Grid nodes. Any later schema
  reader must retain these exact values when such a node is present. ADR-0015
  records the resulting persistent boundary.
- Affected requirements: bounded evidence for `SF-0405-001`–`008`,
  `SF-0501-001`–`008`, `SF-0502-001`–`008`, and `SF-0503-001`–`008`.
- Decision deadline: before canonical schema or package migration work begins
  for `SF-AUTHORING-010`.

## OD-001 — Minimum supported macOS release and reference hardware tiers

Status: Open

- Needed by: Milestone 0 exit and any release-level performance claim.
- Recommended default: support the current and previous two major macOS releases, with Apple silicon as the primary reference tier.
- Safe temporary assumption: the reversible local project continues to target macOS 14.0, while evidence is labeled with the exact OS, SDK, Xcode, architecture, and hardware on which it was gathered.
- Owner decision: final supported OS range and reference hardware tiers.
- Affected requirements: `SF-0201-007`, `SF-0301-007`, `SF-1505-007`, `SF-1602-007`, `SF-1605-007`, `SF-1902-007`, and `SF-2002-003`.

## OD-002 — Persistence store and project package representation

Status: Approved — 2026-07-19

- Decision: use the deterministic versioned single-file control container defined by ADR-0001, with bounded persisted history from ADR-0003, identity-bound atomic replacement from ADR-0007, and versioned content-addressed resource storage from ADR-0012.
- Reversibility: a later package version may adopt a directory or standard archive while retaining an explicit migration reader for package v1.
- Scale boundary: package-v1 control data remains limited to 8 MiB total and 4 MiB per member. Resource-index v1 retains those limits and bounds its immutable sidecar to 2,000 resources, 16 MiB per resource, and 2 GiB total; native move/copy integration remains downstream authoring work.
- Affected requirements: `SF-0301-001`, `SF-0301-003`, `SF-0301-004`, `SF-1702-001`, `SF-1702-004`, and `SF-1702-008`.

## OD-012 — Publisher identity and bundle identifier

Status: Open

- Needed by: first distributable build
- Recommended default: use `app.siteforge.SiteForge` locally and replace it before public distribution.
- Owner decision: publisher’s legal identity, public product name, and final reverse-DNS bundle identifier.
- Safe temporary assumption: local development identifier only; do not register or publish externally.
- Affected areas: signing, entitlements, update feed, saved preferences, crash identifiers.

## OD-013 — Initial distribution trust level

Status: Open

- Recommended default: GitHub-hosted unsigned alpha during development; Developer ID signing and notarization before public beta.
- Options: unsigned technical alpha, Developer ID direct distribution, Mac App Store, or both signed channels.
- Safe temporary assumption: local and GitHub prerelease artifacts only; no claim that Gatekeeper will trust them.

## OD-014 — Trusted app-owned artifact retention and reclamation

Status: Open — non-blocking safety boundary

- Needed by: before any automatic cleanup policy for retained package staging/quarantine files or recovery tombstones.
- Context: the identity-bound filesystem intentionally does not reverse a completed swap, reopen an ambiguous displaced name, or unlink a name after a raced replacement. Recovery Discard performs logical retirement through an owned tombstone. These choices preserve unknown external data at the tested seams but can leave owned artifacts for later maintenance.
- Recommended default: retain these artifacts under verified app-owned directories; expose no automatic deletion beyond the identity-bound retirement path until a maintenance operation can prove an owned trusted root and define user-visible recovery semantics.
- Alternatives: bounded age/size reclamation under a verified app-owned root; explicit user-initiated cleanup with diagnostics; or a future platform primitive that offers expected-inode conditional unlink/rename.
- Tradeoffs: automatic reclamation limits disk use but risks deleting an artifact after ownership has changed; conservative retention preserves safety but needs a size/visibility policy.
- Safe temporary assumption: logical retirement, typed retry, and retained staging/quarantine artifacts only. Do not claim universal protection against a hostile same-UID process racing the final macOS rename/unlink syscall.
- Affected requirements: `SF-0301-004`, `SF-0301-005`, `SF-0306-003`, `SF-0306-004`, `SF-1504-003`, `SF-1504-004`, `SF-1603-004`, `SF-1604-004`, and `SF-1702-004`.

## OD-017 — Signed update feed and installer ownership

Status: Open — blocks trusted update installation, not metadata inspection

- Needed by: enabling the SF-1507 installer handoff or publishing a production update feed.
- Recommended default: Developer ID signing and notarization with Sparkle 2,
  an EdDSA-signed appcast derived from owner-controlled GitHub Releases, stable
  and preview feeds, monotonic upgrades, and a retained last-known-good app.
- Owner decision: final publisher/bundle identity; Developer ID team; who owns
  and rotates the private update-signing key; exact GitHub repository/feed URL;
  stable/preview promotion policy; minimum supported macOS; rollback and
  emergency-revocation policy.
- Alternatives: Mac App Store delivery (store-owned update trust); a fully
  SiteForge-owned signed downloader/installer (substantially larger security
  surface); metadata-only checking with manual download (current safe state).
- Tradeoffs: Sparkle is mature and MIT-licensed but adds a binary/package
  dependency and key/appcast maintenance. A custom installer avoids that
  dependency but creates a security-critical long-term maintenance burden.
- Safe temporary assumption: public HTTPS metadata may be inspected without
  authentication; download/install remains policy-blocked and the running app
  is never replaced.
- Decision deadline: before any public beta or enabling the Install action.
- Affected requirements: `SF-1507-001`–`SF-1507-008`, plus OD-001, OD-012, and OD-013.

## OD-003 — Blank-project default page set

Status: Approved — 2026-07-19

- Needed by: before `SF-FOUNDATION-007` implementation begins.
- Recommended default: seed `Home` at `/` and `Not Found` as the designated error page at `/404`, in that navigator order, with no authored content beyond the minimum valid page roots.
- Alternatives: seed only `Home` for the smallest project; or add content-oriented pages such as `About` and `Contact`, which improves immediate discoverability but embeds product assumptions and increases deletion work for users who do not need them.
- Tradeoffs: `Home` plus `Not Found` exercises the specification's home/error-page model and provides a practical baseline without turning a blank project into a template; `Home` alone is simpler but defers the error-page path; a larger set is more instructive but less neutral.
- Affected requirements: `SF-0301-001`, `SF-0301-002`, `SF-0301-005`, `SF-0301-008`, `SF-0303-001`, `SF-0303-003`, `SF-0303-005`, `SF-0303-006`, and `SF-0303-008`.
- Decision deadline: before the first code or migration fixture for `SF-FOUNDATION-007`; changing the set after persisted projects exist requires an explicit migration/default-provenance policy.
- Approved decision: seed `Home` at `/`, followed by `Not Found` at `/404`; assign the home and not-found roles respectively; give each page only one minimum valid root node; add no sample text, sections, or template content.
- Implementation consequence: blank-project creation is a single clean baseline with explicit blank-default provenance. Template creation remains a separate provenance path. Schema-v1 empty/rootless documents receive deterministic minimum identities during compatibility migration.

## OD-004 — Layout engine implementation versus embedding an existing standards engine

Status: Approved — 2026-07-21

- Decision: use a SiteForge-owned, typed, deterministic, UI-independent layout engine for canonical authoring computation. Generate HTML/CSS through an adapter and use WebKit only as an isolated preview/export runtime and standards oracle.
- Evidence: the optimized runway subset produced deterministic results at 100 and 10,000 nodes, rejected invalid, unsupported, cancelled, and stale work, and matched exported WebKit geometry on the retained responsive and complete fixtures. Methodology and raw measurements are retained in `docs/evidence/authoring-engine-runway/`.
- Reversibility: the engine and export adapter are protocol boundaries. A versioned embedded alternative may replace or supplement a subset only with equivalent deterministic migration, cancellation, identity, accessibility, and parity evidence.
- Revisit triggers: unsupported text shaping, grid, intrinsic sizing, or international-layout behavior cannot meet the declared parity tolerance; an owner-approved performance budget is missed; or maintaining the owned subset exceeds the cost of a bounded embedded alternative.
- Architecture record: ADR-0013.
- Affected requirements: `SF-0501-001` through `SF-0501-008`, `SF-1901-001` through `SF-1901-008`, and `SF-1903-001` through `SF-1903-008`.

## OD-011 — Canvas technology split among SwiftUI, AppKit, Core Animation, and Metal

Status: Approved — 2026-07-21

- Decision: retain SwiftUI for workspace chrome; use a dedicated AppKit viewport for native input, focus, accessibility, coordinate ownership, hit testing, and invalidation; use bounded Core Animation tiles/surfaces and overlay layers for composition. Do not require a layer per object. Keep Metal behind an optional renderer boundary rather than adopting it initially.
- Evidence: the retained 10,000-object run showed fast AppKit dirty-region and Core Animation incremental work, while every full-render alternative crossed or approached the reference frame interval and SwiftUI Canvas rerasterized after a one-object change. The Metal probe intentionally measured only buffer/command overhead and is not treated as end-to-end renderer proof.
- Reversibility: typed immutable scene snapshots isolate the viewport, renderer, overlays, hit testing, and accessibility. Metal can replace tile rasterization without changing canonical or interaction semantics when production evidence justifies it.
- Revisit triggers: production display-link traces miss an owner-approved budget; tile/cache memory exceeds its bound; required effects cannot be expressed efficiently; or framework improvements provide equivalent incremental, input, accessibility, material, and stress evidence.
- Architecture record: ADR-0014.
- Affected requirements: `SF-0401-001` through `SF-0401-008`, `SF-0407-001` through `SF-0407-008`, `SF-1901-001` through `SF-1901-008`, and `SF-1903-001` through `SF-1903-008`.
