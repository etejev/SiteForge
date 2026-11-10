# Codex Work Queue

## SF-LOCAL-BUILDER-012-016-FOCUSED-ACCEPTANCE — IN PROGRESS

### Latest integrated receipt

Hosted CI for `955f910` stopped before tests on Xcode 26.6. The local
follow-up is limited to extracting the typed component-property row and
grouping the existing commands below the outer builder's child limit
(SF-0701-006, SF-0902-006, SF-0401-006). See the
[compile follow-up](evidence/SF-LOCAL-BUILDER-FULL-INVENTORY-20261102.md#hosted-compile-follow-up).
The clean Xcode 27.2 build passed; Xcode 26.6 confirmation remains pending.
No editor feature work or local suite rerun was performed.

OD-030 exact ordinary image replay passed 1/1, 171.265s. The subsequent
full run ended exit 65: 888 non-UI and 163 UI passed; four UI failed,
three opt-in UI skipped, zero unrun. The owner requested exact failure
replay only and deferred a fresh full run for this checkpoint. Do not
advance the usability/Header resize follow-up. Exact replay passed 4/4,
with zero failures or skips; eligible for the owner-authorized checkpoint
commit/push, not milestone completion. See the
[failure inventory](evidence/SF-LOCAL-BUILDER-FULL-INVENTORY-20261102.md).

The isolated November 9 full gate finished: 888 non-UI passed, 162 UI passed,
five UI failed, three owner opt-in UI journeys skipped; exit 65. See
`SF-LOCAL-BUILDER-FULL-INVENTORY-20261102.md` for the failure boundaries.
Four exact ordinary-identity replays passed unchanged. The fifth passed
after the native straight-edge drag correction, 418.426s. The final
ordinary-identity gate ended at the external automation boundary in OD-030:
888 non-UI and 69 UI passed, then a lost XCTest application connection
and canceled replacement-runner authorization. No green gate or push.
Keep the owner-requested language/Inspector and Header resizing
follow-up separate and pending until the baseline closes.

### November 9 follow-up

The November 2 collection exited 65: 888 non-UI and 96 UI passes, two
UI assertion failures, then an automation initialization timeout. The
suite did not finish. The exact component-return and Safari Escape focus
assertions now synchronize against live scene/element identity, without
relaxing geometry or focus. Focused replay passed 3/3, no skips
(`focused-b78ee9c0-bef4-4b3e-b46f-6aebf2ce9e7b.xcresult`).
The November 9 ordinary-identity full gate was interrupted after the Aurora
safety guard detected the open installed app. Repository/build and all 888
non-UI tests passed, but the full gate did not pass. Focused replay uses the
existing isolated OwnerTesting identity, without quitting the installed app.
Exact isolated replay passes after fixing native folder navigation:
158.051s, exit 0, `focused-e3dfceeb-f55c-40c0-b587-b3f38054e89a.xcresult`.
The isolated full gate is active; see the current handoff for its receipt.
The live entry below is historical.

### Owner-authorized full closeout cycle — IN PROGRESS,2026-11-02

LIVE: the original final `./sf verify` is running, result
`full-96d605e0-a34f-49f2-8fbb-165472e79ab7.xcresult`; temporary log
`siteforge-native-closeout-authoritative-20261102.log`.888 non-UI pass and the
repaired native/Safari journey passes523.336s inside this collector. UI continues;
do not duplicate the run or edit source/tests/tools. Final totals remain pending.

LATEST: all27 original failures have passing exact focused receipts. The adopted
native repair uses canonical Header/Footer ownership in the existing Preview
sheet, not a host replacement; its real popup fills the resolved allocation.
Both required UI selectors pass511.484s/50.786s; final-source focused checks
pass4 code plus1 UI. All19 originals were reviewed, with assertions intact.
OD-029 is no longer paused. No collector is active at this documentation update.
Next bounded step: one stable-source final `./sf verify`; inspect actual failures
if any, otherwise reconcile results, review scoped staging and the two ahead
commits, commit/push normally and monitor hosted checks. No new feature or
generated/coordinator artifact belongs in that commit. Prior notes below are
historical execution state, not pending approval or current test jobs.

OD-029 approval update: owner answered “next” to the explicit bounded native
accessibility investigation AND repair proposal. Plan: reproduce only the short
Header boundary, compare Header/Footer owning control and cell contracts, fix
the first demonstrated mismatch in the existing host, add focused regression,
then run both remaining selectors and the stable-source final gate. Preserve
all prior passing receipts; no unrelated browser replay or feature work.

Latest outcome: original browser comparison PASS1/1,972.799s, all four pixel
comparisons zero; Aurora/Related Page storage-backed retries PASS2/2,
68.844s/255.725s. All23 new original screenshots were reviewed.25/27 original
failed methods now have passing focused receipts; only the two native Header
methods remain paused under OD-029. No collector is active;11GiB is available.
Do not repeat passing tests or the exhausted native diagnostic. The next owner
decision is separate authorization for native AX ownership/activation
investigation, or continued pause. The execution notes below are chronological
history, not current pending runs. Full verification/commit/push remain pending.

Current phase: focused repairs after completed stable-source full inventory.
Owner storage action is confirmed: live workspace volume11GiB free, Xcode setup
ready, no active runner at resumption. The2.7GiB notes below are historical.
Next bounded plan: preserve the browser's full viewport/Escape/focus/exclusivity/
pixel contract, replace repeated receipt-chunk AX round trips with one public
immutable snapshot, run its original exact selector, inspect baseline/closed
originals, then retry each cache-service-killed selector once if capacity remains
safe. Do not rerun passing groups or the paused native Header probes. See the
two-row current remaining-failures table in the linked evidence.
Post-inventory exact replay passes6/6 non-UI and9/9 UI. Search/filter controls
now use the standard inset section; both search-overflow journeys pass. A
separate eight-method interaction/browser group completed6 passed/2 failed.
Where Used then passed1/1,33.692s after its bounded visible row hit-shape fix;
the test retains exact instance identity and now requires sheet dismissal.
No collector is active. The presentation replay now passes after its contaminated
ordinary Footer baseline was replaced with the actual all-closed baseline.
Native Header remains unresolved after the authorized read-only probe:
AppKit hits the real visible control, while XCTest rejects its AX target.
Temporary tracing is removed; OD-029's restriction on speculative changes remains.
The prior2.7GiB storage blocker was resolved before the successful targeted runs.
Storage cleanup by
macOS killed two original runners; owner space action is pending. See current
handoff/repair receipt. No completion/commit/push claim.

`./sf verify` exits65: repository/build pass;880/886 non-UI pass (6 failed),
146/170 UI pass (21 failed,3 explicit owner-session skips). Combined1026 passed,
27 failed,3 skipped. That full collector is finished. Follow the
[ordered A/B/C inventory](evidence/SF-LOCAL-BUILDER-FULL-INVENTORY-20261102.md);
two signal-killed runners are attributed to CacheDeleteAppContainerCaches,
not product assertion failures. Native Header pointer remains unresolved;
component search horizontal overflow is repaired and passes exact replay.
Repair exact failed expectations/fixtures/interaction paths; no
unchanged broad rerun or speculative host/control/AX experiments. Final green
documentation-inclusive gate remains required before reviewed commit/push.

Passing browser evidence: strict generated-browser journey passes1/1,822.330s
(`focused-01d348fd-ecd6-45e0-a32f-8e6b3474ba13`), all four320/430 Header/Footer
pixel checks0/33600, wider768 and destinations pass; nine originals reviewed.
Native Header ordinary pointer remains failed; real-host sizing passes, and
ineffective row-clipping removal is reverted. No further speculative native
experiments. See the single CURRENT EXECUTION handoff and current focused
receipt. Full inventory proceeds despite that named failure; completion/commit/
push still require green final gates. In the full inventory the strict browser
journey also passes1011.238s, and grid/artboard passes44.329s. No new feature work.

Latest: owner resolved OD-028; Xcode readiness check exits0 and the blocked
fixture now passes1/1 (0.057s). The subsequent production overlay/fixture checks
pass2/2 (0.116s); native/full acceptance remains pending. Private real Header/
Footer candidate was inspected at320/430/550, including Footer upward opening,
keyboard reopening and real About navigation. Shared output now uses supported
intrinsic details-content grid overlap, retaining legacy positioning only as a
feature-detected fallback; canonical data/runtime remain unchanged. Strict
browser replay exposed truncated Web Inspector AX JSON before reaching pixels;
the helper now reads bounded complete chunks, with visual assertions unchanged.
No commit/push or full-green claim. Ignored independent audit/artwork archive is
preserved and excluded; final gate must use this post-cleanup workspace.

Earlier external boundary (resolved): OD-028. Repository checks passed (exit0).
The one serial focused fixture attempt built/launched its host but executed
zero test methods; sampling shows XCTest IDE-session preparation waiting.
Native Xcode inspection shows the required system-components Install dialog.
The exact stalled xcodebuild was interrupted, then terminated after interruption
left its scheme operation stuck (exit143); its test host exited. No duplicate
run, full-gate result, production popup integration, commit or push. Owner must
complete Xcode's visible setup before another launch. Existing native pointer
and strict browser pixel failures remain blocking, not reclassified as passes.

Explicit one-cycle permission: full local testing/verification, reviewed commit
and normal current-branch push after green gates. Plan: reconcile actual dirty
tree/two ahead commits and exclusions; finish private popup Footer/geometry/
closure proof before production integration; resolve strict native pointer
behavior; run affected focused checks then one final authoritative `./sf verify`
and strict supplemental menu regressions; inspect original visuals, reconcile
factual docs, review/stage explicit coherent paths, commit and push only green
source; observe hosted checks. SF-0806-006, SF-1203-003/006, SF-1211-004 plus
actual bounded012–016 requirements remain Partial. No owner data, coordinator
ledger, installation/release, settings/security changes or unrelated features.
Current startup failures are diagnosed once, not retried unchanged in a loop.
No green/completion claim or push while blocking visual/runner proof is missing.

### Targeted popup overlay candidate — blocked at fixture test initialization,2026-11-02

Private grid/details-content overlay closes visibly in the minimal Header case,
including pointer Escape and Space reopen/Escape. Refined summary/panel delta
is0.438CSSpx, Header frame and scrollHeight unchanged; sampled left panel
interior returns0/6300 changed (open1081). This is not the strict full-panel gate.
First candidate had a closed-state pseudo margin causing summary movement;
private refinement scopes it to open details. Eight originals reviewed/retained.
No shared production correction integrated: Footer, exclusivity, destinations and
320/430/wider remain unproven. New exact Header/Footer fixture test compiled but
executed0 tests, waiting in XCTestDriver._prepareTestConfigurationAndIDESession.
After interrupt/cancellation warning, exact xcodebuild83875 terminated, exit143;
host84055 exited. Result `focused-04359f9f-d785-44fa-9dea-d2448e410b55`, log/sample
retained. No unchanged retry. Native Header/strict pixel failures preserved.
New tab closed, temporary server stopped; full verification deferred, no Git.

SF-0806-006, SF-1203-003/006, SF-1211-004; existing connected layout/output
ownership under ADR-0020. Plan: prove one standards-based grid-overlay candidate
in the retained private compiler fixture before shared output edits. Preserve
summary/panel placement, Header below/Footer above, stacking/clipping, document
height and surrounding frames, real pointer/keyboard/reopen/closure. No static
inline replacement, zero-area hit workaround, repaint/visibility hack or runtime
rewrite. Integrate only after candidate geometry AND pixels pass; otherwise
retain the failed candidate receipt privately and remove it from production.
No native Header replay, failed XCTest startup retry, broad/full gate or Git.

### Source-first minimal menu reproduction — diagnostic finished, acceptance unresolved,2026-11-02

Result: new minimal real-compiler fixture test1/1,0.034s in
`focused-f7087ab2-0fab-41d4-9b02-3bb5b8a1a716`. Generated unchanged and observed
cases retain a panel after trusted Escape; stock plain/observed controls close
visibly. Generated position:static variant closes but changes intended popup
layout; stable unconditional absolute variant still fails visually. No safe
product fix or observation bug established. Source audit confirms live state
separate from cached event history. Same-page readout eliminates sole reliance
on selected Inspector world; adding it does not repair paint. Six-case private
README,19 captures (18 valid reviewed,1 excluded navigation attempt), AX receipts
and manifest retained. Actual readout547×515, nominal RDM548×516/100%.
No production CSS/runtime rewrite, UI-test startup retry or broad test run.
New tab closed/server stopped; native Header and strict pixel failures retained.
Historical43-code/7-of8-native scope unchanged; one new diagnostic code pass
is separate. See focused acceptance receipt's source-first reproduction section.

SF-0806-006, SF-1203-003/006, SF-1211-004. Plan: audit live/cached
measurement, event/capture ordering and resource identity; generate one minimal
real-compiler Header fixture and a clearly separate stock details control in
private temporary storage. Compare uninstrumented and observational-readout
variants at one measured viewport using genuine click/Escape. Retain originals
and strict failures. Fix only a demonstrated source/helper boundary and run its
exact regression. No repeated XCTest initialization, native Header host work,
speculative CSS, full gate, Git/install, owner data or coordinator changes.

### Same-artifact Safari presentation/context comparison — diagnostic finished, acceptance unresolved,2026-11-02

Outcome: direct native comparison of the retained same artifact at actual548×516
in ordinary Safari and RDM reproduces painted panels after trusted Escape in both.
Explicit main-page context, top/frame count, persistent passive observer, public
window identity and simultaneous original screenshots correlate the observation;
no alternate frame/world was found. Later capture322s after closure still shows
residue. No demonstrated correctable production boundary; stop speculative
experiments. Strict pixel failure remains authoritative and013 remains Partial.
Two exact comparison UI launches timed out in automation-mode initialization,
zero tests executed. Final build-for-testing passes; no third unchanged retry.
All13 native originals inspected; observer removed, Auto context and320×820
restored, Inspector closed, retained page untouched. See the focused receipt's
Same-artifact native Safari presentation comparison section. No active run,
new production CSS/runtime/host change, full gate, Git/install or owner-data edit.

SF-0806-006, SF-1203-003/006, SF-1211-004 and immutable shared output delivery.
Confirmed no active test runner. Plan: audit the actual Inspector execution
target/frame and visible browser presentation, then run one compact same-artifact
ordinary-Safari/RDM comparison at an honestly measured common hamburger width.
Keep the same Inspector/context through each real click/Escape episode, record
viewport/scroll/scale/context identity and original baseline/open/closed pixels.
Preserve the strict pixel gate and all historic failures. Correct only a proven
test/context/capture or shared-output cause. No native Header rerun, speculative
CSS, full gate, Git/install, owner data or coordinator-ledger changes.

### Real website Escape closure — IN PROGRESS,2026-11-02

FINAL: the new actual-pixel gate fails1/1,106.962s in
`focused-8bc86f35-54f4-494c-985e-15d9244794b0`:1855/33600 former-panel
pixels differ after Escape (allowed33), while DOM/focus/hit checks pass. A unique
visible fixture prefix rules out an older Home document; the exact recording
frame shows the same residue. Earlier assertion-only passes below are NOT the
current method's acceptance. No active run; no accepted visual fix. Preserve
this failure and the pixel gate. See the focused receipt's Final pixel gate
section for original filenames, interrupted scaling attempt and next bounded
same-artifact/non-RDM investigation. No full gate/Git/install was run.

Newer receipt: actual shared script HTTP200/JavaScript MIME/1944 bytes and trusted
Escape execution are proven. DOM closure, aria-expanded=false, focus restoration,
frame timing and exclusion of all navigation links from hit testing agree.
Screen-before-Inspector assertions pass1/1,243.967s at320/430/768, but original
pixels still paint panels. A normal Tab does not clear them (bounded320 diagnostic
1/1,136.423s). No duplicate visible navigation is found. Explicit closed CSS was
ineffective and removed; do not invent a runtime/host/security repair. New HTTP
unit passes0.073s; current distinct code43, native7/8 unchanged. Full evidence and
original filenames are in the newest012–016 receipt; visual acceptance stays open.

SF-0806-006, SF-1203-003/006, SF-1211-004 and existing immutable Preview/output
boundaries. No runner active. Plan: use the existing private Safari fixture to
observe actual script URL/response/MIME/bytes, DOM open/expanded/focus/visibility,
real Escape delivery and rendered-frame timing. A passive test-only observer may
record the event, never consume/dispatch it or close menus. Fix only the first
demonstrated app or query/capture boundary, add exact regression, then prove
Header/Footer closure/reopen/one-open/navigation at measured320/430 and wider.
Preserve every failure and native Header's pending strict assertions. No denied
AX retry, new host/security changes, broad/full gate, Git/install or owner data.

### Current bounded pointer probe — diagnostic complete; acceptance pending

SF-0806-006, SF-1203-003/006, SF-1211-004. Preserve strict013 unchanged.
Plan: one short private-fixture companion observes unique live native Menu and
same-sheet standard-control geometry/hierarchy, attempts read-only external AX
hit discovery, then calls ordinary XCUIElement.click without a readiness guard.
Separate pointer actions, keyboard/focus and external discovery receipts. Reach
Footer/destinations independently where possible; preserve any failure. Correct
only a demonstrated boundary; no new host, coordinate activation, broad retries,
full gate, Git/install, owner-data or coordinator changes. Rerun full013 only
after a meaningful improvement in the short probe.

Outcome2026-11-02: ordinary Header click still fails, while independent Footer
ordinary click, keyboard/Escape/focus and About navigation work. Native local/
window/application hits and coordinate conversion identify the correct cells;
public cross-process hit API returns-25211. No new production cause is proven.
Temporary observation and the failed borderless-fit hypothesis are removed.
Current-control regression passes1/1,0.628s. Browser-only companion passes1/1,
167.058s at measured CSS320/430/768 after correcting empty-identifier Width
querying and replacing universal+1 with one measured rounding correction.
Original native assertions remain strict. Final test compilation succeeds.
Visual review of all nine browser originals still finds panels painted after
Escape, so focus assertions are not closure acceptance. Next bounded diagnostic:
read details.open/aria-expanded/script load across real Escape; compare Header/
Footer remote hit identity only if an already-authorized public client permits.
Do not launch that automatically, repeat long013, change privacy or invent a
host/offset fix. No active runner. Exact failures/filenames are in the receipt;
42 passing code/7 of8 primary native baseline unchanged. Three extra diagnostic
UI methods do not replace013 or change its status. No full gate/Git/install/017.

### 013 native focus/key dispatch — bounded correction retained; acceptance pending

Trace complete: no Safari misdispatch; the earlier frame was post-teardown due
unlimited extraction tolerance. Correct Down reached the active sheet's focus
proxy without opening. A genuine native popup/cell now passes actual Header
keyboard opening/Escape focus, and exact control/modal code checks pass2/2.
Initial pointer hittability still fails84.206s; no waiver or013 acceptance claim.
Current distinct code42 (one added method) versus original41 baseline; native
baseline remains7/8. All temporary logging removed, no active run. Strict pointer,
Footer/destinations and measured-Safari proof remain open; no new experiment.

Historical bounded plan:

Owner authorizes one correlated trace within restored hosting (SF-0806-006,
SF-1203-003/006, SF-1211-004). No active runner at start. Plan: inspect keyboard
and native/browser action paths, add opt-in Debug-only redacted observation to
the existing local event monitor and action boundaries, then run only the exact
failed013 journey once. Correlate foreground/key/main/sheet/first-responder and
event modifiers with action order before any production repair. Remove temporary
trace code after preserving evidence; add/run an exact regression for a proven
bounded cause. Preserve strict native/Safari assertions and rejected-host removal.
No broad/full gate, new host, Git/install, owner data or new feature.

### SF-LOCAL-BUILDER-013-PREVIEW-HOST-EXPERIMENT — REJECTED; CLEANUP VERIFIED

The host did not improve strict actual-app013 activation/hittability. Removed
only its controller/presenter wiring and two orphan diagnostic tests; archived
their exact source outside the repository. Incremental cleanup compile and the
surviving modal regression pass1/1,0.640s. No active process. Original41 code and
7/8 native receipts remain baseline, not new host acceptance. Recommended next
single diagnostic: correlate foreground/key-window/first-responder/modifier state
around the first native opening key, since the recording switches from focused
SiteForge Preview to Safari before the Safari test branch. NOT started. No new
architecture/feature, full gate, Git/install or test waiver.

Historical approved plan:

Bounded SF-0806-006, SF-1203-003/006, SF-1211-004 and originating-window
modal/focus restoration. No runner active at start. Plan: an AppKit-owned sheet
controller replaces only native Preview presentation, preserving immutable
snapshots, geometry, existing actions and Safari/compiler/output paths. Add exact
host/lifecycle regressions before the strict013 app journey; retain only a
demonstrated improvement, then check the named Save/repair/modal neighbors and
inspect originals. No full gate/Git/install, root-window policy, security change,
owner data, assertion waiver or new feature. See OPEN_DECISIONS approval/limits.

Baseline modal-restoration check passes3/3 (one code, native Save/reopen and
015 repair), all seven originals inspected.013 remains unresolved after the
rejected host experiment. Do not repeat unchanged runs or waive its strict checks.

Owner explicitly authorizes bounded compilation, exact new/directly affected
tests and original-resolution native/current-Safari review. Supersedes only the
execution hold for this acceptance, not full verification/Git/install/signing.
Plan: confirm no runner; build-for-testing once; execute30 inventoried exact code
methods plus six named direct neighbors; retain every failure; fix concrete
causes and rerun only affected methods. Then four distinct new native journeys
serially and four named existing Design/component neighbors, extending013 with
minimal Footer coverage. Inspect actual normal1280/minimum1100/wider and measured
browser originals; distinguish supported actual text-scale review from fixtures.
Exact manifest/results: [focused receipt](evidence/SF-LOCAL-BUILDER-012-016-FOCUSED-ACCEPTANCE.md).
Bounded requirements remain those mapped in012–016: SF-0201-009, SF-0202-003,
SF-0203-006, SF-0206-002, SF-0701-002/003/006, SF-0702-003/004,
SF-0703-003, SF-0704-003, SF-0302-004, SF-0308-004, SF-0501/0502/0505,
SF-0601/0602, SF-0806, SF-0901/0902/0903/0905 and SF-1202/1203/1204/1211
only at the exact bounded clauses in that receipt; modules remain Partial.
No017, ./sf verify, whole-target/class suites, broad sweeps, commit/push/GitHub,
installation/signing/release/scheduling/evidence deletion or owner-data changes.

Current result: build-for-testing passed after one test type-inference fix;
initial36 code methods31 pass/five fail, only those five reran after concrete
fixture/one-ULP corrections and pass5/5. Distinct passing code36/36,0 skips.
The first exact012 UI attempt timed out before execution; its authentication
receipt remains historical. The controlled owner-present continuation initialized
without a new prompt. All eight native methods executed; four direct neighbors
plus012 formatting,014 Inspector and015 repair pass. Only013 native menu interaction remains under correction; retained
originals distinguish real viewport/native-menu defects from ambiguous queries.
Four additional directly affected code methods pass in3+1 runs; a new modal
canvas accessibility/action regression also passes (distinct current code41).
013's correct geometry does not prove activation: native Space/Down and pointer
acceptance remain unresolved while the same sheet's standard controls work.
See the new Preview-host architecture decision in OPEN_DECISIONS before replacing
that approved host; no window-policy or assertion waiver is authorized.
Private-control diagnostic probes were retired with the custom bridge;
actual slot/owner geometry checks now run in the strict native journey.
014's compact caption correction passes401.678s; nine originals inspected.
No duplicate run, broad gate or new feature. Reference01/05/12 originals found
externally and inspected; actual150/200% app text scaling not claimed.
Keep IN PROGRESS; bounded acceptance has not passed. Owner-present native
continuation only; do not rerun unchanged code groups, full suites or start017.

## SF-LOCAL-BUILDER-016-SOURCE-INTEGRATION-CLOSEOUT — IN PROGRESS

SOURCE ONLY. Preserve dirty007–015, frozen receipts and owner/coordinator data.
Plan: trace public create/edit/responsive/reuse/save/reopen/Preview/repair/export
entry points and current cross-feature diff; fix only concrete integration
defects, especially clean-only versus commit-capable draft gates, ephemeral
availability and asynchronous receipt/artifact ownership. Re-walk ordinary user
paths independently, add meaningful UNRUN regressions for actual fixes, then
consolidate one factual current summary and finite acceptance matrix. No017.
Bounded SF-0202-003, SF-0203-006, SF-0302-003/004, SF-0303-003/004,
SF-0701-002/003/006, SF-0806-003/004, SF-1202-003/004/006,
SF-1203-003/004/006, SF-1204-003/004/006 and SF-1211-004/006;
cite narrower additional existing requirements only if an actual fix needs them.
Modules stay Partial. No tests/builds/parser/lint/check/verify, collectors,
app/browser/UI/screenshots, commit/push/install/sign/schedule, owner-data or
coordinator-ledger edits. Acceptance is deferred, not waived; no automatic run.

Source closeout and independent re-walk finished2026-11-01. Actual fixes under
SF-0702-003/004, SF-0202-003, SF-0302-004, SF-1203-004, SF-1204-004 and
SF-1211-004/006 cover Design draft retention/ownership and pre-snapshot commits,
strict shadow tuple input, live-project Preview artifact actions and preserving
active local writes when Check Website is invoked. Equivalent box edits also
acknowledge typed no-change without history. Seven new code methods and one
refined existing015 native journey are UNRUN. Current summaries consolidated;
[016 evidence/matrix](evidence/SF-LOCAL-BUILDER-016-SOURCE-INTEGRATION-CLOSEOUT.md)
owns the finite acceptance handoff and historical boundaries. Remaining work is
acceptance-only; ready to REQUEST owner authorization, not permission to run.
Keep IN PROGRESS, no017, no completion/runtime/install claim or Git operation.

## SF-LOCAL-BUILDER-015-PREVIEW-REPAIR-WORKFLOW — IN PROGRESS

SOURCE ONLY; preserve007–014 and frozen acceptance. No tests/builds/checks/verify,
apps/browsers/screenshots, commit/push/install/sign/schedule or owner-data edits.
Plan: capture finding receipts independently of successful Preview artifacts;
share exact receipt-membership/context/clean-editor validation between Preview
and Check Website. Prepare real target availability before navigation, reuse
existing page/original-component/selection adoption and conservative typed
Inspector destinations, and close panels only after live target adoption.
Show severity/explanation/repair plus one safe action; distinguish old successful
output from latest findings, keep explicit Refresh/export/cancel boundaries.
Second source review covers stale/foreign/missing/no-target, drafts/IME, cancelled
preparation, component context and export. Add meaningful UNRUN model/controller
and one native journey source; no016 or automatic acceptance.
Bounded SF-0202-003, SF-0203-006, SF-0701-002/003/006,
SF-1202-003/004/006, SF-1203-003/004/006, SF-1204-003/004/006,
SF-1211-004/006; modules stay Partial. OD-018/019 and trust decisions unchanged.

Source implementation and second review finished2026-11-01. Independent attempt
receipts, shared exact-target/clean-editor preparation, existing page/original/
Layers adoption and conservative Inspector mapping now back both panels. Preview
separates retained successful output from current findings; immutable Export and
explicit Refresh remain. Five code methods and one native journey added UNRUN.
No build/check/visual/gate receipt. Keep IN PROGRESS; exact coverage and remaining
acceptance: [015 evidence](evidence/SF-LOCAL-BUILDER-015-PREVIEW-REPAIR-WORKFLOW.md).
No016 or automatic execution; preserve prior work and coordinator files.

## SF-LOCAL-BUILDER-014-STABLE-INSPECTOR-LAYOUT — IN PROGRESS

SOURCE ONLY; preserve013 and all older work. Execution remains paused: no
tests/builds/checks/verify, app/browser/UI launch or screenshots; no commit/push,
installation/signing, owner-data changes or015. Modules remain Partial.
Bounded SF-0201-009, SF-0202-003, SF-0203-006 and SF-0701-002/003/006.
Plan: (1) inspect actual pane/tab allocation and shared section framing; use
measured complete labels and available pane geometry, preserving canvas minimum
and explicit accessible overflow below the fit boundary; (2) stabilize the
selected-object header and Header/Footer, Text typography/appearance, Component
Content controls with shared full-width fields/adaptive actions, preserving
draft/focus/transaction ownership; (3) independently source-review empty/mixed/
locked/missing/error/scale/pane-resize paths; add bounded UNRUN allocation,
history/draft-neutrality and native geometry/focus journey source; document exact
boundaries and deferred acceptance. No theme, Settings, schema or engine redesign.
OD-018/019 stay open and unchanged; no supplied-slot or migration decisions here.

Source implementation and second review finished2026-11-01. Shared label/font
measurement now informs bounded pane minima and actual strips; row height grows
for enlarged text. Full-width leading section framing, identity-stable adaptive
fields/actions, Header/Footer controls, Text typography/appearance and Component
Content/recovery are refined without changing commands or authored state.
Four new code methods, one affected existing method and one future native journey
are UNRUN. No compilation/check/visual/full-gate receipt. Keep IN PROGRESS, not
DONE. Exact fit equation, matrix, source findings and deferred acceptance:
[014 source evidence](evidence/SF-LOCAL-BUILDER-014-STABLE-INSPECTOR-LAYOUT.md).
No015 dispatch, execution or owner-data changes.

## SF-LOCAL-BUILDER-013-NARROW-CHROME-LAYOUT — IN PROGRESS

SOURCE ONLY; execution remains paused. Preserve007–012 and the separately frozen
title receipt. No tests/builds/check scripts/UI/browser/verification, commit,
push, installation, signing, scheduling or next task.

Bounded SF-0501-003/004/005/006, SF-0502-003/005, SF-0505-003,
SF-0601-003/006, SF-0602-003/006, SF-0806-002/003/004/006,
SF-1202-003, SF-1203-003, SF-1204-003 and SF-1211-004; modules stay Partial.
Plan: trace final structural sizing and both connected CSS paths; reserve the
existing native menu width before shrinking only default title space in eligible
automatic mobile rows. Reuse one allocation intent for final immutable geometry
and continuous browser flex rules; preserve authored/custom constraints and add
concise guidance to existing Header/Footer settings when they cannot fit.
Suppress decorative menus without usable links, retain hidden-title/no-link,
hamburger-off, identity, truncation, clipping and unsupported-output guards.
Add UNRUN width/state/history/package/compiler and public-control journey source,
then source-review and record exact supported/excluded cases. No new schema,
breakpoint, chrome hierarchy, global owner, data migration or owner-site edit.

Source implemented: final shared menu-first geometry, continuous static/fluid
CSS, availability-based menu display and adopted-snapshot Inspector guidance.
Nine code methods and one native/Safari journey are UNRUN. No build/check/visual
or full gate. [013 source receipt](evidence/SF-LOCAL-BUILDER-013-NARROW-CHROME-LAYOUT.md)
records eligibility, custom escape, 320-probe limit and selectors. IN PROGRESS.

2026-11-01 source continuation finished both usability passes. Destination
availability now also gates width reservation and menu-room preflight, using the
same ephemeral document/route context in native geometry and both browser paths.
Empty link lists have no navigation slot; broken links keep disabled intent,
not a phantom Menu budget. Existing settings explain empty/missing destinations
and constrained custom rows. Same9+1 coverage refined, all UNRUN. Source review
finished; compilation/focused execution/Footer/compact/browser visuals/final gate
remain deferred, not waived. No014 or automatic acceptance dispatch.

## SF-LOCAL-BUILDER-012-USABILITY-AND-LANGUAGE — IN PROGRESS

SOURCE ONLY; all execution is paused after the frozen title receipt. No tests,
builds, checks, UI/browser launches, verification, commit, push or installation.
Bounded supporting SF-0202-003, SF-0203-006, SF-0206-002, SF-0701-002,
SF-0702-003, SF-0703-003 and SF-0704-003; modules remain Partial.

Plan: (1) expose existing common formatting commands without a disclosure detour,
and source-walk existing authoring paths; (2) share plain-language labels/help
without changing canonical keys, identities, command gates or authored content;
(3) align native Inspector/Settings scope and hierarchy without changing window
geometry or palette; (4) re-walk workflows and review mixed, stale, invalid and
cancelled states. Review source after each pass. Add UNRUN regression source and
factual before/after action paths. No new editor, responsive engine, schema,
branding, theme or future capability. The prior title tests do not verify012.

Four source passes and their second reviews are recorded in the
[012 source receipt](evidence/SF-LOCAL-BUILDER-012-USABILITY-AND-LANGUAGE.md).
Common formatting commands are outside Inspector Tools; Import Images is visibly
labeled; shared sizing/spacing/scaling/screen-size terminology, winning-source
labels, property-search aliases and Settings scope are implemented in source.
Five new code methods and one native journey are UNRUN; affected human-label
expectations were updated without relaxing behavior. No compile/check/visual or
full-gate result exists for012. Keep IN PROGRESS; execution remains paused.

Continuation plan — remaining language/discovery coverage: trace component
original/copy commands, reset/recovery guards, fallback-only contents, reusable
solid-color sampling versus009 full-family transfer, and responsive comparison/
reset/conversion. Translate visible labels/help and search aliases without
changing command scope or machine identities; add UNRUN exact presentation and
guard regressions, then independently re-walk source and document before/after
coverage. Supporting bounded SF-0901-003, SF-0902-003, SF-0903-003, SF-0905-004,
SF-0510-003 and SF-0308-004 only clarify existing behavior. OD-018/019 remain
open; no retargeting, supplied-slot contents or new output capability. All
execution, commit/push and owner-data changes remain prohibited.

Continuation implemented and independently source-walked: original/copy/reset
scope and counts, missing-value recovery, fallback-only default contents,
solid-color/opacity reusable-style sampling, comparison counts and responsive
reset/conversion now have consistent visible/AX help. The shared original-edit
action also works directly from Content, with the same command and AX identity.
Three additional code methods and an extension to the existing012 native journey
are UNRUN (total5+1). No acceptance or whole-app completion is claimed; preserve
the execution pause and frozen earlier receipt. See the012 coverage tables.

## Current execution boundary — title receipt frozen,012 source unverified

Targeted title repair: six code methods and one matched-width native/Safari
journey pass; all15 originals inspected. Final exact run3/3, no runner. Read the
frozen focused receipt for actual1440/430/320CSS measurements and limitations.
Owner now pauses all execution during the following usability source package:
no tests/builds/check/lint scripts/collectors/readiness/app/browser/UI/performance/
verify or automatic final cycle. Source/diff review and test source edits only.
No commit/push/install/sign/release/schedule or owner package/recovery changes.

## Historical scoped acceptance — SF-LOCAL-BUILDER-007–011, before012

Owner approved the new/minimally affected exact-selector acceptance only. This
supersedes the historical source-only holds below for that bounded execution;
all five items remain IN PROGRESS. Plan and exact 56 model/integration plus six
native selectors: [focused manifest](evidence/SF-LOCAL-BUILDER-007-011-FOCUSED-ACCEPTANCE.md).
Capture the first complete failure inventory before fixes; rerun only affected
methods after concrete changes, inspect original screenshots, and distinguish
infrastructure failures. No whole target/class, broad gate, ./sf verify, commit,
push, installation, signing, owner-data changes or next feature is authorized.
Mandatory full verification is deferred, not waived. Preserve historical receipts.

Scoped residual repair plan (owner approved): trace the managed title's actual
CATextLayer/CanvasTextLayout and typed HTML/CSS projections; compare the same
private document/revision at measured1440/430/320CSS widths and browser zoom.
Derive bounded overflow from existing authored geometry/typography, preserving
multiline/Hug/semantic identity; no new schema, fixture shortening or global
nowrap. Add exact compiler/metrics regressions and one narrow public-control
native/Safari comparison, inspect originals, and record actual results only.
Applicable bounded SF-0507-003/004/006/008, SF-0604-003/006, SF-0806-003/006,
SF-1202-003/004, SF-1203-003/006, SF-1204-003/004, SF-1211-003/004/008.
No other journey/group rerun or broad gate, commit/push/install/owner-data change.

Pre-title-repair result: focused code70/70 pass (all56 new+14 directly affected existing).
Native automation now initializes. All eight distinct focused native journeys
pass (six new plus both existing neighbors). Scoped compositor3/3 and HTTP3/3
also pass. Originals exposed Safari's long fixed-height header-title mismatch;
the later frozen targeted receipt above resolves that measured path. Broader
browser parity remains deferred. No broad gate or workflow completion
claimed; see the manifest. No runner remains.

## SF-LOCAL-BUILDER-011-CONNECTED-FLUID-OUTPUT — IN PROGRESS

SOURCE ONLY. No tests/builds/checks/lints/scripts/collectors/readiness/performance/
UI/app/browser/verify execution; no commit/push/install/sign/release/schedule or
next prompt. Preserve007–010 and incomplete acceptance. This ID grants no gate.
Bounded SF-0604-003/004/005/006/008; supporting SF-0501-003/004, SF-0502-003,
SF-0503-003, SF-0505-003, SF-1202-003/004/008, SF-1204-003/004/008,
SF-1206-003/004 and SF-1211-003/004/008. Modules remain Partial.

Plan: trace canonical fluid/cascade, connected typed layout and immutable build/
Preview/export boundaries. Add a closed browser-flow adapter in the existing
connected CSS emitter using shared container policy and allowlisted continuous
clamp expressions, never preset-sampled child offsets. Preserve override winners
and native-managed/latent intent. Prove support conservatively; retain precise
blockers for unrepresented sizing/containing combinations and existing root/
positioning/clipped-menu/dependency failures. Keep no-fluid output unchanged.
Add meaningful UNRUN math/policy/graph/compile-lifecycle/persistence/native journey
source and factual evidence/docs/ADR clarification. No editor/canonical migration,
second graph/compiler/writer or owner-site edits. Future native/Safari visual
review and mandatory verification remain deferred, not waived.

IMPLEMENTED IN SOURCE — ACCEPTANCE DEFERRED; OWNER TEST APPROVAL REQUIRED.
The existing compiler now has a closed connected-flow scalar/CSS adapter and
neutral semantic layout wrappers. Continuous clamp math, cascade and typed
container policy are reused; unsupported containing/sizing combinations retain
precise node findings and whole-plan rejection. No-fluid output remains on its
old path. Eleven code methods plus one native Safari/export-cancel journey are
UNRUN. No builds/tests/checks/UI/browser/verification execution or visual claims.
Exact scope, limitations and selectors: [011 source receipt](evidence/SF-LOCAL-BUILDER-011-CONNECTED-FLUID-OUTPUT.md).

## SF-LOCAL-BUILDER-010-PAGE-CHROME-REUSE — IN PROGRESS

SOURCE ONLY — no builds/tests/checks/lints/scripts/collectors/UI/app/browser/
performance/verify execution; no commit/push/install/sign/schedule/next dispatch.
Bounded SF-0303-002/003/004/005/006, SF-0304-002/003/004/005/006,
SF-0308-002/003/004/005/006/008, SF-0806-002/003/004/005/006; existing connected
SF-0501/0504 and component/resource reference behavior only where exercised.
All modules remain Partial. Preserve007/008/009 and their incomplete acceptance.

Plan: extract the existing page-duplication graph remapper for independent
Header/Footer subtree copies; use one captured immutable source/targets revision,
off-main dependency preparation and one existing command batch/exact inverse.
Add native Page/Header/Footer action and compact target sheet with explicit
independent-copy semantics, per-role add-missing skips and cancellation. Existing
chrome is never replaced in this bounded slice: no ambiguous merge or inbound
reference deletion. Preserve routes/body/order/metadata and same-project resource
and component identity; remap only copied internal section references. Gate drafts/
IME and stale scene/selection/revision before mutation; announce only adopted
results and offer ordinary target-page navigation. Add meaningful UNRUN model,
persistence/output and native journey source, factual evidence/docs and read-only
diff review. Mandatory future acceptance is deferred, not waived. Owner packages,
recovery/revision245/gradient, OD-018/019 and coordinator/artwork files untouched.

IMPLEMENTED IN SOURCE — ACCEPTANCE DEFERRED; OWNER TEST APPROVAL REQUIRED.
Shared page/subtree clone, same-project dependency validation, one atomic
add-missing batch, guarded preparation/adoption and native Page/Header/Footer
sheet are present. Existing roles are counted and kept; replacement/merge is not
offered. Eleven code methods plus two native journeys are UNRUN. No compile,
check, visual or verification execution. See [010 source receipt](evidence/SF-LOCAL-BUILDER-010-PAGE-CHROME-REUSE.md)
for exact symbols, reference semantics, limits and mandatory future acceptance.

## SF-LOCAL-BUILDER-009-FORMATTING-REUSE — IN PROGRESS

SOURCE ONLY, renewed owner no-testing/no-build/check/UI/verify hold remains.
No commit/push/install/sign/schedule or next self-dispatched workflow.
Bounded SF-0702-002/003/004/005/006/008, SF-0703-002/003/004/005/006/008,
SF-0308-002/003/004/005/006/008; supporting existing SF-0506/0507/0508/0509/0510
resolution only for fields actually transferred. Modules remain Partial.

Plan: inspect existing private clipboard, exact property transactions and style
registries; add one closed versioned formatting envelope with bounded raw canonical
intent, never computed-width/token literals. Copy requires an unambiguous common
family bundle; Paste validates the live identity/dependencies and prepares one
atomic property batch through Design Inspector/CommandRegistry with exact inverse
and neutral repeat. Preserve geometry/content/component bindings and unrelated
families. Add compact native Edit/Inspector Copy/Paste Text Style and Appearance,
truthful subset/reason feedback and no ordinary Cmd-C/V interception. Same-project
token/named-style/image-fill references stay references; unsafe cross-project
transfer is unavailable, not silently flattened. Add UNRUN model/persistence/
renderer/native journey source, factual docs/evidence, and read-only diff review.
007 failed partial receipts and latest fixture corrections stay unverified;
008 completed its bounded source scope with10 code+1UI UNRUN, not acceptance.
Preserve all dirty source, owner revision245/resources/recovery and coordinator/
artwork files. Mandatory future verification and visual acceptance are deferred.

IMPLEMENTED IN SOURCE — ACCEPTANCE DEFERRED. Private bounded canonical family
transfer, background resource validation, identity-gated Design property batch,
target-owned layer/stop IDs, exact existing inverse/no-op semantics and native
Edit/Inspector actions are present. Fifteen code methods plus one native journey
are UNRUN; no build/check/visual/verify execution occurred. Same-project/base
Default state only; mixed sources reject, incompatible paste targets are named.
Read [009 source receipt](evidence/SF-LOCAL-BUILDER-009-FORMATTING-REUSE.md) for
exact selectors, deferred live acceptance and unsupported transfer scope.

## SF-LOCAL-BUILDER-008-RESPONSIVE-LAYOUT-REVIEW — IN PROGRESS

SOURCE DEVELOPMENT ONLY, owner renewed the no-testing hold on 2026-10-29.
No builds/tests/checks/lints/collectors/UI/app/browser acceptance or verification;
no commit/push/install/sign/scheduling. One source workflow, no next dispatch.

Bounded SF-0606-002/003/004/006/007/008, SF-0602-002/003/004/006,
SF-0402-002/003/006 and SF-0701-003/006. Plan: first preserve/fix007 fixture
setup using complete structural defaults, owned temporary recovery paths and
real viewport initialization. Extend the existing actor-backed comparison with
typed revision/page/node/width-tagged horizontal geometric Review findings from
shared resolved snapshots. Distinguish clipped containment from uncertain
off-artboard intent, excluding structural/hidden/editor objects and supported
overflow. Add native Review element navigation through the existing draft/IME,
width, Layers/selection and Layout Inspector boundaries; do not author fixes.
Invalidate on revision/scope changes; cancellation/progress/error/empty states
remain scene-local. Add meaningful UNRUN policy/integration/native journey source.
Update factual evidence/status/traceability; no acceptance/completion claim.
Exclusions: canonical finding/suppression storage (SF-0606-001/005), collision,
tap-target or glyph-truncation heuristics, automatic responsive fixes and browser/
export runtime parity. OD-018/019, owner revision245/resources/recovery unchanged.

IMPLEMENTED IN SOURCE — ACCEPTANCE DEFERRED; OWNER TEST APPROVAL REQUIRED.
[Source receipt](evidence/SF-LOCAL-BUILDER-008-RESPONSIVE-LAYOUT-REVIEW.md).
Shared scene findings, typed Review identity/measurements, native exact-width
Review element, Inspector context and guarded refresh/cancel/error states are
implemented. Ten new code methods plus one native journey are UNRUN. Rows are
capped200/sample with explicit total/scope guidance. Linked component internals,
viewport-fixed/sticky subtrees and managed navigation chrome are not evaluated.
Only source/API/diff inspection occurred; no acceptance or runtime-budget claim.

007 historical execution: build succeeded; initial nine methods3 passed/6 failed
(focused3133a465). Fixture correction rerun d3dafe44 executed six:4 passed/2
failed (missing initial viewport adoption in two fixtures, subsequent assertions
also failed). Both artifacts are retained. Latest initialization corrections
are SOURCE ONLY, unverified. No runner remains; do not relaunch under this hold.

## SF-LOCAL-BUILDER-007-CUSTOM-RESPONSIVE-WIDTH — IN PROGRESS

ACCEPTANCE INCOMPLETE — renewed owner no-testing hold applies.
The preceding authorization was superseded on2026-10-29. Historical build
succeeded; focused3133a465 ran9 with3 passes/6 failed methods; fixture rerun
d3dafe44 ran6 with4 passes/2 failed methods. Latest source corrections initialize
the real viewport before text/selection commands; they are not re-executed.
One development workflow only. Prior checkpoint ba342938 is locally verified:
785 non-UI/151 UI passes,0 failures,3 intentional owner-session skips. Historical
authentication/hold receipts below are not blockers for that checkpoint.

Bounded SF-0602-002/003/004/006/008, SF-0601-003/006, SF-0604-003/006,
SF-0401-003/006. Plan: keep CSS inspection width in the existing scene viewport
bounds; native labeled width draft with Return/blur commit and Escape restore;
reuse existing ranges/cascade and draft/IME gate. Audit active width consumers,
immutable scene preparation, Inspector contexts, placement and native Preview.
Reuse comparison policy with an explicit current-width sample on a cancellable,
identity-gated worker. Add UNRUN validation/boundary/layout/context/history/
persistence and native accessibility journey source. Presets remain exact
reference actions; no new breakpoint/schema, preferences, canonical geometry,
export sampling path or responsive authoring system. Fit commits keep the
artboard centered with pasteboard gutters and retain NodeIDs/selection.

No execution of tests/builds/check scripts/UI/collectors/verify or app/browser
acceptance; no commit/push/install/sign/schedule/new workflow. OD-018/019,
owner Aurora/Dark Flow revision245, resources/recovery and gradient unchanged.
Broader modules remain Partial. Future ./sf verify and original-resolution
visual acceptance remain mandatory after separate owner approval.

Source receipt: [custom responsive width](evidence/SF-LOCAL-BUILDER-007-CUSTOM-RESPONSIVE-WIDTH.md).
Nine model/integration methods have partial failed execution above; the native
journey remains UNRUN. Existing
focus traversal and exact static media-query expectations are updated, not
waived. Static layout and appearance now share the existing half-open ranges
for fractional CSS widths; no new export compiler or canonical property.
No current-source acceptance, visual, performance or completion claim.

## Current acceptance authorization — 2026-10-27

FINAL VERIFIED RECEIPT,2026-10-28: `./sf verify` exits0. Result
`full-e7ee511e-a6f5-4449-a0dd-15680fe3a7c8.xcresult`:939 total,936 passed,
0 failures,3 intentional owner-session skips; non-UI785 passed, UI151 passed.
Repository/security/traceability440/architecture/build checks passed. The three
repaired journeys also pass focused3/3; nine original changed-state screenshots
were inspected. Source batches01–10 and Page Background's bounded local slice
are accepted; normative modules and broader owner delivery remain Partial.
Review/stage the approved coherent paths for one LOCAL checkpoint commit only.
Preserve/exclude coordinator notes and superseded Aurora bitmap/prompt. No push,
installation, owner project mutation, schedule or prompt11. Earlier pending,
failure and authentication paragraphs below are historical, not current blockers.

LATEST,2026-10-28: owner authentication completed; the corrected three journeys
pass3/3 in `focused-07cad6e0-4c7b-46f8-a4ad-30572e50049a.xcresult`.
All nine retained originals were inspected: native fields readable/focused,
fluid/provenance correct, Mobile off-artboard selection truthful without ghost,
blank Root structural only and real Frame/selection aligned. Freeze the coherent
source/docs snapshot for ONE final ./sf verify; no edits beneath it. The prior
authentication handoff and failed full receipt below remain historical evidence.

Current external handoff,2026-10-28: the three corrections compile, but focused
`6c4a1ac5-8556-4392-a72c-d4d7bc602622` executed ZERO UI methods, exit65.
At11:21:49-0400 testmanagerd requested LA evaluatePolicy2, “Enable UI Automation”,
requester XCTest; at11:22:49 it timed out before automation initialization.
No runner remains; no unchanged retry, full rerun or commit is justified yet.
Owner must be present for the current macOS authentication dialog during one
isolated retry, entering credentials only in macOS. No privacy setting or
security bypass is requested. Source corrections and failure originals retained.

2026-10-28 completed full receipt: `full-8731db4c-98c8-45fa-afe0-5bb9337913c6.xcresult`
finished FAILED: 939 total, 933 passed, three failed, three intentional
owner-session skips. All785 non-UI passed; UI148 passed/3 failed/3 skipped.
No runner remains. Earlier pending/full784 wording below is historical.
Bounded correction plan: inspect retained screenshots/hierarchies; reuse native
scroll/reveal and fresh field queries for fluid enable and Site Settings focus
(SF-0604-002/006, SF-1207-002/006); update the obsolete blank Layers expectation
to allow structural Page structure while requiring zero authored/rendered objects,
no Root overlay and real insertion/adoption (SF-0304-003/006, SF-0407-003/006,
SF-0701-003/006). Run only those three journeys during repair, inspect originals,
then freeze one final ./sf verify snapshot. Review and commit locally only after
green; no push, installation, owner project mutation or new feature.

Latest affected evidence: readiness1/1; all twelve new/prerequisite UI methods
have passed after targeted corrections. Exact native page-surface paint,
solid/gradient/opacity regressions and Page Background UI pass5/5. Visual review
caught and corrected missing Root paint and calibrated-RGB color conversion.
The initial four-pass/eight-failure group is historical, not a current blocker.
See the integration receipt for exact results and inspected original screenshots.

The owner explicitly approved full local testing, necessary corrections, and one
reviewed local checkpoint commit. This supersedes the historical testing/commit
hold below for Page Background and source batches 01–10. Finish batch 10 before
freezing the acceptance snapshot. No push, GitHub operation, installation,
publication, scheduled follow-up or prompt 11 is authorized. Historical pass
counts do not verify the changed source. Current verification remains pending.

Current result: approved full attempt finished, exit 65. Repository/build checks
passed; 784 non-UI methods ran (781 passed, three failing methods), then UI
initialization failed before any UI method while macOS requested automation
authentication. All three editable non-UI causes are corrected and pass 3/3
affected coverage. The five new integration methods separately pass 5/5.
[Exact artifacts and diagnosis](evidence/SF-SOURCE-BATCH-20261027-10-INTEGRATION.md).
Owner authentication retry succeeded; affected acceptance and visual correction
are complete. Prepare one coherent final full gate; no local commit yet.

## SF-SOURCE-BATCH-20261027-10 — Preview/export source integration — DONE (bounded local acceptance)

Bounded SF-1201-003/004/006, SF-1202-003/004, SF-1203-003/004,
SF-1204-003/004, SF-1206-003/004, SF-1211-003/004/006. Actual gaps:
browser open repeats draft preparation; export does not pin the plan before its
native panel or cancel its writer task; local writing uses a captured cancellation
flag; native Refresh/export write omit the draft boundary; resource extraction
is duplicated/on-main; stale static-build catches can replace newer feedback.
Plan: one output action boundary, existing package-backed resource resolution on
workers, captured immutable export request, tracked/cooperatively cancellable
staging and guarded adoption; preserve loopback security/shared compiler; add
unrun integration/cancellation/native acceptance and exact ten-workflow inventory.
Page Background is an explicit prerequisite, not item 11. Source integration
and six new methods are recorded in
[the ten-workflow inventory](evidence/SF-SOURCE-BATCH-20261027-10-INTEGRATION.md).
Owner has approved current-source full local acceptance and a local commit;
verification is pending. No push, installation or further workflow is authorized.

## SF-SOURCE-BATCH-20261027-09 — Global Settings and lifecycle usability — DONE (bounded local acceptance)

IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.
Cancel adopts latest saved preferences without replaying foreign history; a
global native notice keeps drafts discoverable across existing Settings pages.
Recent updates are ordered within the launch controller and retain last-valid
presentation on error. Async Open/New/cancel publication is identity-gated;
untitled current projects retain a Return action after Open failure. Cancelled
history review exits loading, and failed discard retains its recovery surface.
Six new non-UI methods plus one native journey are UNRUN.
[Evidence](evidence/SF-SOURCE-BATCH-20261027-09-SETTINGS-LIFECYCLE.md).
Settings geometry/testing/updater/recovery trust policy unchanged; no observed
runtime/build/visual acceptance or normative module completion is claimed.

Bounded SF-0204-003/004/006, SF-0206-002/003/005/006,
SF-0301-003/004 and SF-0306-003/004. Existing fixed Settings geometry,
global destinations, manual Advanced testing and crash-qualified recovery remain
authoritative. Actual gaps: Cancel replays cached preferences after external
changes; hidden Settings drafts lack cross-destination guidance; recent-list
mutations race and open completion can publish after an awaited stale operation;
cancelled history review can remain loading and failed discard enters workspace.
Plan: latest-committed cancel/restore guards, one observed navigation owner and
native draft notice, serialized existing recent-store operations, guarded async
launch publication and truthful recovery action results; add unrun preference,
recent/lifecycle, clean/crash/cancel and native accessibility source coverage.
No new preference scope, window policy, channel, update trust, recovery format or
testing launcher. OWNER HOLD ALL TESTING; source inspection/editing only.

## SF-SOURCE-BATCH-20261027-08 — Practical component source editing — DONE (bounded local acceptance)

IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.
Organized properties now navigate directly to their typed definition source and
retain the existing exact Return to Instance context. Entry/return completes one
edit/IME boundary, and rejected entry cannot enqueue a definition selection.
Definition text retains paired label/default drafts across immutable adoption,
detects binding replacement and supports native Return/blur/cancel. Rename pins
its opening scope. Clean instance text fields omit redundant Apply/Cancel rows.
Four new model/integration methods and one native journey are UNRUN.
[Evidence](evidence/SF-SOURCE-BATCH-20261027-08-COMPONENT-WORKFLOW.md).
No runtime/visual/module-completion claim; SF-0904 variants remain deferred.

Bounded SF-0901-002/003/005/006, SF-0902-002/003/005/006 and
SF-0905-003/004/005/006. Existing named creation, definition/return context,
organized exposed text/media/action/choice/visibility/fallback controls and
retained-conflict recovery remain authoritative. Concrete gaps: definition text
editors reset on every revision; property-source navigation is recovery-only and
can enqueue a target even when definition entry is rejected; Rename lacks an
opening context. Plan: retained paired text/default drafts with identity/binding
conflict checks, direct typed property-source navigation and exact return,
context-pinned Rename, scoped native feedback and unrun history/renderer/output/
navigation acceptance source. No variant-axis model (SF-0904 remains deferred),
supplied-slot ownership, retargeting, remote libraries or schema change. OD-018/
019 unchanged. OWNER HOLD ALL TESTING: source inspection/editing only.

## SF-SOURCE-BATCH-20261027-07 — Local image usability — DONE (bounded local acceptance)

IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.
Per-property mixed Image controls, exact untouched focal coordinates, captured
alt/focal drafts and atomic details edits now use the existing Image registry.
Repeated authored values are neutral. Current immutable resource status explains
scoped recovery; the reuse chooser no longer inherits navigator filters, and
empty filtered Assets has a native Clear Search and Filters action. Four new
model/integration methods and one native journey remain UNRUN.
[Evidence](evidence/SF-SOURCE-BATCH-20261027-07-LOCAL-IMAGES.md).
No build/runtime/visual/scale acceptance or module upgrade is claimed.

Bounded SF-0802-002/003/005/006 and SF-0807-002/003/004/005/006;
supporting SF-0801-004/005. Existing Assets import, organization/search, scoped
reuse/import, global replacement confirmation, dependency inventory and native
placement remain authoritative. Actual gaps: mixed Images lose all controls;
alt/focal drafts are refreshed away or commit with newly reconstructed context;
missing-resource recovery lacks an explicit selected-image status; unchanged
Image edits can create history; navigator filters incorrectly hide reuse choices.
Plan: per-property mixed projection, native
applicable-subset controls, captured draft/focus-loss/cancel ownership, truthful
immutable-resource status and neutral repeats through the existing Image registry;
add unrun history/reference/byte/output/native regression source. No new store,
schema, import/placement architecture or remote/SVG/media expansion. Preserve
Header/Footer visibility, component and favicon references. OWNER HOLD ALL TESTING.

## SF-SOURCE-BATCH-20261027-06 — Reusable visual style links — DONE (bounded local acceptance)

IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.
Ordered Link/Unlink/Earlier/Later actions preserve other style links; confirmed
shared updates disclose authored usage scope. Explicit Use Linked Fill/Opacity
removes only local appearance, protects None/token/image fills and validates the
opening context. Inspector projections use existing effective appearance; opacity
typing captures context so queued focus loss cannot bake an old linked value.
Four new model/integration methods and one native journey are UNRUN.
[Evidence](evidence/SF-SOURCE-BATCH-20261027-06-REUSABLE-STYLES.md).
No build/runtime/visual acceptance or module-coverage upgrade is claimed.

Requirements: bounded SF-0510-002/003/005/006, supporting SF-0508-003/005/006
and SF-0509-003/005/006. Existing shared definitions support solid fill/opacity,
not gradient/box-style bundles. Concrete gaps: Apply replaces every prior link,
mixed links cannot Detach, Update immediately changes project-wide users, and
capture can silently turn a mixed/gradient fill into an omitted definition field.
Plan: typed add/remove/reorder link operations; explicit local fill/opacity reset
to linked values with None/token/image guards; validated common-solid capture,
visible supported scope and confirmed global updates pinned to context; unrun
history/None/token/mixed/renderer/output/native source coverage. Preserve token
definitions/bindings, local overrides and stable layer/stop/style identity. No
reusable gradient/border/shadow schema, custom CSS or parallel style resolver.
OWNER HOLD ALL TESTING; source inspection/editing only, no execution or install.

## SF-SOURCE-BATCH-20261027-05 — Practical installed typography — DONE (bounded local acceptance)

IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.
The real installed-font chooser now exposes discovered upright weight choices;
each applies family/weight atomically through the existing typography registry.
Chooser context is captured, failed/cancelled choices retain drafts, and text-role
guidance distinguishes semantics from appearance. Five new acceptance methods
plus the expanded package/recovery method are UNRUN.
[Evidence](evidence/SF-SOURCE-BATCH-20261027-05-INSTALLED-TYPOGRAPHY.md).
No new font/rich-text schema or verified runtime/visual/module coverage.

Requirements: bounded SF-0507-002/003/004/005/006, supporting
SF-0406-005/006 and SF-0805-003/004/006. Existing Heading/Paragraph semantics,
font catalogue/weight intersection, numeric drafts, wrapping and shared text
metrics are present. Concrete gap: installed-family choice commits only family,
retaining a potentially unavailable previous weight; the chooser cannot explicitly
apply an installed family and upright named weight atomically. Plan: add one typed
family/weight edit using existing properties/transaction validation, real native
installed-weight choices, captured chooser context, preserved failed/cancelled
drafts and clear text-role guidance; add unrun multi-selection/history/fallback/
renderer-inline/output/native source coverage. No rich-text/range model, font
import/download, new font identity/schema or browser font-availability promise.
OWNER HOLD ALL TESTING: source inspection/editing only; no execution or install.

## SF-SOURCE-BATCH-20261027-04 — Responsive visibility and fluid styling — DONE (bounded local acceptance)

IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.
Fluid/visibility callbacks now validate captured scope/revision; queued focus loss
cannot commit a replacement draft. Fluid property selection survives commits;
mixed fallbacks open explicit blank ranges instead of borrowing primary values.
Equivalent ranges present as common while retaining distinct FluidValueIDs.
Current effective source/value and rendered typography are visible; native
Typography navigation opens existing Layout controls. Six new acceptance methods
are UNRUN. [Evidence](evidence/SF-SOURCE-BATCH-20261027-04-RESPONSIVE-FLUID.md).
Broader modules remain Partial; no runtime/build/visual acceptance claimed.

Requirements: bounded SF-0602-003/006, SF-0603-002/003/005/006,
SF-0604-002/003/005/006; supporting SF-0507-003/006. Existing presets, visibility
overrides, explicit responsive conversion and fluid typography/spacing models
remain. Concrete gaps: fluid drafts and visibility callbacks rebuild fresh
identity at commit and can outlive their opening context; fluid removal always
announces fixed restoration even when a device override still wins; Design
typography shows only fixed fallback values with no effective readout/editor
navigation. Plan: pin and validate scene-local edit scopes/revisions, guard queued
focus-loss work, share effective fluid source/value projection, expose current
typography and native Layout navigation, and add unrun boundary/hidden-flow/
stale-context/history/output/native-control regression source. No responsive
content-swap model, cascade/schema change or automatic conversion. OWNER HOLD
ALL TESTING; no execution, launches, installation, commits or external writes.

## SF-SOURCE-BATCH-20261027-03 — Connected structural layout — DONE (bounded local acceptance)

IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.
Container values/provenance now pass current viewport width to the existing
resolver. Desktop spacing controlled by a fluid record rejects ignored fixed
edits/reset without removing that record. Native Edit Fluid Values navigation
reaches the existing editor, including padding/gap on connected containers;
flow-owned dimensions remain unavailable. Seven new acceptance methods are
UNRUN. [Evidence](evidence/SF-SOURCE-BATCH-20261027-03-CONTAINER-LAYOUT.md).
No runtime, visual, performance, build or module-completion claim.

Requirements: bounded SF-0501-003/005/006, SF-0502-003/006,
SF-0503-003/006, SF-0505-003/005. Connected insertion/reorder, direction,
cross-axis alignment, Grid columns, gap/padding, sizing/visibility and explicit
legacy conversion already exist. Concrete gap: Container Layout reads fluid
gap/padding without viewport width and permits Desktop fixed edits that fluid
resolution ignores. Plan: share effective viewport resolution/provenance, reject
ignored fixed mutations truthfully, expose a native jump to existing Fluid Values
commands, and add unrun nesting/Hug/constraints/hidden/history/output matrices.
No new wrapping/distribution/track model or schema; Grid/horizontal/vertical Stack
remain the safe existing alternatives. Testing/builds/checks/UI execution held.

## SF-SOURCE-BATCH-20261027-02 — Header/Footer navigation — DONE (bounded local acceptance)

IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.
Shared inline-link gap now projects the Navigation Stack's existing responsive
layout into native frames/CSS; dedicated Apply/Cancel/Reset controls use the
existing typed registry. Actual Contents Images have base visibility toggles;
responsive intent and assets remain intact. Six new acceptance methods UNRUN.
[Evidence](evidence/SF-SOURCE-BATCH-20261027-02-HEADER-FOOTER.md). No execution or
visual acceptance; keep all modules Partial and testing held.

Requirements: bounded SF-0501-003/005, SF-0601-003, SF-0602-003/006,
SF-0806-002/003/005/006. Existing connected roles, inclusion toggles, title,
alignment, link editing/order and mobile behavior are already present; preserve
them rather than adding parallel controls. Plan: expose missing inline-link gap
through the existing Navigation Stack layout/responsive property cascade and
central PageStructure registry; derive canvas/CSS gap from that same value;
surface existing content Images as explicit base visibility controls (no invented
logo reference); add unrun edge/history/output/identity/native workflow coverage.
No fixed/sticky policy, external destinations or schema change. OWNER HOLD ALL
TESTING: no builds/checks/tests/automation/acceptance launches or installation.

## SF-SOURCE-BATCH-20261027-01 — Site and page setup — DONE (bounded local acceptance)

IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.
Pages entry, per-page indexing/reset, pinned draft preview, provenance/route and
missing-favicon guidance now reuse existing metadata/transaction/output paths.
Five new acceptance methods are UNRUN; existing empty-override omission was
preserved, not claimed as a new defect. No social-image schema expansion.
Evidence: [source slice](evidence/SF-SOURCE-BATCH-20261027-01-SITE-SETUP.md).

Requirements: SF-1207-001/002/003/004/005/006/008; bounded supporting
SF-0303-003/004/005/006 for current-page identity, route and navigation context.
Plan: reuse existing WebsiteMetadata/WebsiteSettingsView and metadata registry;
expose Site & Page Settings from Pages; close draft/default and page-indexing
override gaps; pin snippet context to the opening snapshot; expose actual route,
navigation-name meaning, provenance and missing-favicon recovery; preserve the
existing ResourceStore/dependency and shared head-emission paths. Add unrun
transaction/no-op/stale/persistence/reference/output and native UI test source.
No social-image schema exists; do not invent social SEO fields for this slice.
All testing/builds/check scripts/UI/app launches remain on owner hold. No
installation, signing, commit or GitHub mutation. Broader modules remain Partial.

## SF-LOCAL-BUILDER-006 — Aurora Dark Flow public-control authoring — IN PROGRESS

### Accepted local slice: Page Background discoverability — DONE

Source implementation now present: direct Pages/empty-Design navigation to the
exact canonical Root; shared solid/gradient/token editor; atomic Transparent /
None; structural-vs-hidden Layers presentation; document/page-scoped draft guard.
Seven prerequisite methods, including exact native page-surface pixels, are
covered by the final green local gate785 non-UI/151 UI,3 intentional owner-session
skips. Authored solid/None originals were inspected. Immutable page paint,
invalidation/Preview digest and explicit sRGB are shared without adding canvas
objects or changing geometry. Evidence:
[accepted bounded note](evidence/SF-LOCAL-BUILDER-006-PAGE-BACKGROUND.md).
No installation, schema/output-theme or owner-data mutation. The parent owner
website delivery remains broader than this accepted local source slice.

Requirements: SF-0508-002/003/005/006 and SF-0701-003/006. Existing Layers and
shared output are preservation boundaries, not new claims of drag/drop,
clipboard, preview or export module completion. OD-018/019 remain untouched.
Plan: resolve the sole supported canonical page Root without guessing; expose
Page Background from Pages and the empty Inspector; reuse the existing Design
fill/gradient/token editor; distinguish structural ownership from hidden state;
add an atomic transparent/none fill operation and unrun regression source for
identity, history, tokens, persistence and shared output. No schema/theme change.
IMPLEMENTED IN SOURCE — NOT BUILT/TESTED is the required eventual disposition;
owner approval is required before any test, build-for-testing or visual journey.
No install/commit/push; preserve all owner packages, exports and recovery.

**OWNER HOLD ALL TESTING.** Explicit approval required before any further test,
UI automation, readiness/visual journey, collector or full verification. Exact
owned authoritative run cancelled safely with SIGINT; no runner remains. Retained
733 non-UI +100 UI passes /3 owner-session skips /1 cancelled UI /38 UI not run;
not a green gate. No install, new feature, commit or push. Remaining plan is
preservation and factual non-testing reconciliation only until owner approval.
This supersedes automatic testing/install plans below (latest006 evidence).

Readiness resolved: owner-assisted native exact shell method passes 1/1, zero
failures/skips (`Test-SiteForge-2026.10.27_01-10-46--0400.xcresult`). Automation
enabled and actual app launched, same unchanged4b3301f6… source. No runner remains.
Remaining plan: freeze factual docs/source; one ordinary-identity authoritative
./sf verify; after green, approved safe local app refresh and identity/smoke check.
No additional readiness/broad retry while this gate runs, no commit/push.

Latest native comparison completed: zero UI methods executed, one automation-mode
initialization timeout, no app assertion. Exact existing shell method selected;
bundle `Test-SiteForge-2026.10.27_00-55-21--0400.xcresult`. No runner or current
authentication surface remains. Readiness NOT demonstrated; no full retry/install.
Smallest remaining step is owner-present completion of the real macOS Touch ID/
Use Password dialog during one coordinated exact-method attempt. Do not infer
completion from “next” or a vanished dialog. Earlier waiting notes historical.

Startup diagnosis continuation: compare existing CLI session/runner configuration
with the known working ordinary Xcode scheme, then invoke only
`testApplicationLaunchesCompleteNativeShellAtPracticalMinimumSize` through the
native Test navigator. No broad retry until actual UI execution demonstrates
readiness; retain any concrete owner-only prompt rather than assuming one.
Applicable: SF-1201-004/006, SF-1203-003/004, SF-0806-003/005,
SF-0201-002/006/008. Preserve source, owner projects and accepted website review.

2026-10-27 remaining plan: retain the completed post-cleanup gate and diagnose
the external XCTest initialization boundary before another authoritative run;
only after a genuinely green gate perform the approved safe local refresh.
Latest gate: 733/733 non-UI pass, zero UI methods executed, one automation-mode
initialization failure, zero skips. No runner remains; no unchanged broad retry.
OD-026/027 resolved; installed app unchanged. Exact evidence is in the newest
006 evidence section. Older pending/full-result notes below are historical.

Owner continuation, 2026-10-26: OD-026/027 resolved. Build-cache-only cleanup
completed (about 1.7 GiB, seven ignored compiled intermediate/module-cache
directories); projects/recovery/evidence/app products/backups untouched. Source
4b3301f6… unchanged. Plan: one frozen post-cleanup ./sf verify, then existing safe
local app refresh with explicitly allowed ad-hoc signature only if the gate passes.
No services/privacy changes, publication, commit or push. Prior failed full gate
remains failed; storage cleanup does not itself prove the OS trigger repaired.

Current disposition: interrupted asset method passes the one isolated retry,
1/1 (99.566s), same frozen source 4b3301f6…. No app/test/build runner remains.
All nine product regressions have focused passes; final full result remains
871 passed / 1 OS-issued runner kill / 3 skips, NOT green. Whitespace and 440-record
traceability pass after docs. Hold further broad retry/install at OD-026/027;
no deletion/signing/system change/commit/push. Earlier active-run notes historical.

Latest full gate completed: repository/build and 733/733 non-UI pass; 138 UI pass,
one UI runner killed by macOS CacheDeleteAppContainerCaches during initial Window
readiness, three owner-session skips. Aggregate 871 passed / 1 failed / 3 skipped,
exit 65, no SiteForge assertion failure; NOT full green. Source fingerprint stayed
4b3301f6… throughout. One diagnosis-backed isolated asset retry is running; no
duplicate/broad retry. Exact OS request and artifact in latest 006 evidence.
Owner storage/cache-retention decision OD-027 and local-signature OD-026 pending.
No installed update, deletion, service/privacy change, commit or push. All earlier
pending/full-gate wording below is historical; milestone remains IN PROGRESS.

Current: all nine failed UI methods have passing focused repairs, plus two
affected model methods. Native Layers menu observes live state in its own host;
rename ends its sheet focus before dismissal, preventing stale text-Undo routing.
Other document-history tests explicitly leave native field editing through the
real preset control. Strict assertions/native text Undo remain intact. Original-
resolution corrected captures reviewed; exact selectors/timings in 006 evidence.
Next: freeze the reconciled source/docs for one final full ./sf verify. Installed
refresh remains gated on green and clarification of the local ad-hoc-signature
boundary; no signing/install has occurred. Earlier failed/running notes below
are historical and superseded by this paragraph, not erased.

2026-10-26 current gate outcome (supersedes pending/earlier totals below): the
ordinary-identity full run completed without cancellation: 861 passed, 10 failed,
3 explicitly owner-session-only cases skipped. Non-UI: 731/732; UI: 130/139
executed passed, plus those three skips. Both original native-comparison journeys
and previously cancelled Button/Link coverage pass. Installed app unchanged.
Repair plan: prove content-independent privacy diagnostics, distinguish native
text Undo from document Undo using a real nonediting focus destination, and trace
Layers context-menu availability against canonical nesting. Keep every mutation,
identity, history, persistence and enabled-state assertion. Focused privacy and
exact nesting model regressions pass 2/2; nested-layout menu Undo/Redo passes 1/1.
Eight remaining affected UI methods are running, not claimed passed. Full gate
must be repeated only after focused corrections and factual reconciliation.

Native comparison complete: related-page reuse 1/1 (235.493s); conversion 1/1
(97.941s) after correcting off-viewport geometry-readout discovery with bounded
Inspector scrolling/live queries. Assertions and canonical behavior unchanged.
Retained original-resolution evidence reviewed. Next: frozen full ./sf verify
with the native comparison's ordinary app identity, including previously cancelled
coverage; no early agent cancellation. Full/installed delivery still pending.

Bounded comparison plan: use native Xcode Test navigator to select only related-page
reuse and responsive-content conversion, retain first failures/runner identity,
compare their actual Save/Preview/selection boundaries with CLI evidence, then fix
only the proven shared production or test-driver cause. One active input driver;
no accepted website/Safari replay, broad test launch, or installed replacement
before a genuinely green frozen full gate. Requirements: SF-0806-003/005,
SF-1201-004/006, SF-1203-003/004. The prior cancelled case was explicitly stopped
by the agent after failures, not a discovered collector continue-on-failure bug.

Newest gate: repository/build and 732/732 non-UI pass. UI: six pass, two assertion
failures, one cancellation; NOT complete. Diagnostic pair 0/2 fails at changing AX
boundaries (Save now passes, Preview discovery fails; conversion fails before
editing). Native inspection exposes the real tree while XCTest loses frames/IDs.
OD-025 requests exact Xcode-normal execution, not another CLI/authentication loop.
No runner or installed update. Latest 006 evidence contains artifacts/recordings.

Current 2026-10-25: direct native Open/Preview/Export works; no further XCTest
initialization retry. Revision 245 export and original-resolution Contact/Not Found
1440/390 review confirm dark viewport coverage and natural mobile scroll/Footer.
The shared viewport minimum needed real authored root fills as well: both short
pages now bind an editable root solid layer to the existing Dark Surface token
through Design controls. Saved and normal Quit confirmed; no canonical geometry,
content, Home gradient or original project/recovery changes. Twenty-six affected
code methods pass. Reconcile/freeze then ONE final ./sf verify; installed delivery
remains gated on green verification. Older checkpoints below are historical.

Latest: direct browser review resumed without authoring replay; Home captured at
eight actual responsive widths and the corrected white navigation works. A
320-wide wrapped Menu affordance led to a shared intrinsic/alignment correction.
Two affected code tests and native re-export pass (UI 1/1, 71.683s), using the
fresh Website Reviewed destination. Mac then locked again before its visual
confirmation; physical unlock only is needed. No test remains running. Finish
browser functions/all-page review, then the frozen full gate and safe installed
delivery. No commit/push or completion claim.

Newest observed checkpoint: all five pages now have real editable content.
Journal confirmed responsive flow passes 1/1 (105.475s), About 1/1 (451.458s),
Contact/Not Found 1/1 (1176.261s), Home expansion 1/1 (549.457s), normally saved.
Original-resolution native captures were reviewed. Twenty-four distinct affected
code methods pass. Final review reached real history, close/reopen, exact gradient,
Safari preview and native export Cancel/retry; final Safari input timed out when
native inventory reported the Mac locked. Capture the run result and await unlock,
then review exported output at required widths. Final frozen verification and safe
installed delivery remain pending. Older blocked/run paragraphs are historical.

Current: owner authentication retry succeeded. Native Home foreground/flow
authoring passed 1/1 (549.781s), saved through normal controls. Text raster
placeholder cleanup passes three affected pixel methods; shared dark navigation
foreground/surface passes two code methods. Historical authentication/setup
paragraphs below are not current blockers. Remaining: other-page editorial
content, additional Home content, original-resolution/browser/output/reopen
acceptance, then the one frozen authoritative gate and safe installed delivery.
Preserve every original project/resource and recovery candidate. No commit/push.

Latest demonstrated boundaries: long article typing now completes after bounded
availability reuse; exact native Select All passes 1/1 (36.669s). The subsequent
Bounds screenshot shows no modal blocker: Text numeric bounds are truthfully
unsupported. Resume Journal using a real Stack column, not disabled-field input;
do not repeat permission/setup requests. Exact draft assertions and normal text
Save checkpoints are required before remaining website/visual/output acceptance.

Fresh continuation: owner completed Xcode setup; read-only readiness exits 0.
No repeated setup/authentication request. Saved project remains authoritative;
SiteForge native inspection still disconnects, so resume through supported
public-control XCTest where possible without force quit or package mutation.

Actual alternate-route result: opt-in owner-session audit builds; ONE exact
run stops before its method at a fresh Enable UI Automation authentication
timeout, exit 65. No gradient edit occurred, no runner remains. Owner readiness
requested for one isolated authentication retry; do not repeat Xcode setup or
loop unchanged tests. Exact fresh diagnostics and preserved copy: 006 evidence.

Owner-authorized independent website and measured authoring workflow. Preserve
Aurora Editorial, Workflow Study, their resources and genuine recovery. Bounded
SF-0508-002/003/005/006, SF-0502-003/005, SF-0507-003/005,
SF-0602-003/005/006, SF-0806-002/003/005/006 and
SF-1201-003/004/006, SF-1203-003/004 only where actually exercised.
Observed supporting corrections additionally exercise SF-0406-002/006 and
SF-0408-002/003/005/006: native text command focus, existing canonical container
nesting eligibility, stable selected-node scope and exact move history.

Plan: create/save an independent editable project using public native commands;
author real content/navigation and responsive flow; review shared loopback/output
at practical widths; keep a small factual action/friction ledger. Owner refinement:
ONE ordinary native linear gradient, exactly three stops: 0% #160D2B,
50% #6A36C8, 100% #C52E53, smooth diagonal, dark behind the heading.
No bitmap wallpaper (including the supplied/generated drafts), stacked glow
layers, handwritten package/output or application-wide theme change. Use the
existing fill registry, stable stops, history and shared HTML/CSS projection.

No new rendering/persistence architecture, commit or GitHub operation. Installed
delivery is allowed only after the frozen full gate is green and normal owner
Saved/Quit plus source/provision checks are proved. Earlier Xcode Install Required
and automation authentication requests are resolved; no broad retry or full-pass
claim. Native website/visual acceptance remains pending, not proved by this plan.

## SF-LOCAL-BUILDER-005 — Connected edit/action integration polish — IN PROGRESS

Current owner boundary, 2026-10-24: native inspection confirms Xcode's actual
**Install Required** system-wide components dialog, with Quit/Install buttons.
Owner must choose Install and personally handle subsequent Apple setup/authentication.
Dialog left open, no installation or test/collector retry performed. OD-025 and
005 evidence retain the screenshot. After owner completion, confirm read-only
readiness before ONE collector retry; no bypass, global change, unchanged focused
test loop, commit or GitHub action. Preserve current source and ordinary owner work.

Latest focused evidence: all 13 distinct native workflows have passing serial results;
nine directly affected code methods pass. Connected image/typography, native
export Cancel/retry/reopen and real Safari mobile navigation are complete in
focused scope. Eight-width browser captures were inspected; fixed authored
template clipping at 320/1024 is explicitly retained/documented, not silently
converted or called universal responsive parity. Current evidence lists exact
bundles/screenshots. Freeze for ONE supported accumulated collector, then safe
installed delivery only with normal Saved/Quit proof. No new feature/commit/GitHub.

Earlier focused result: viewport ownership/responder correction passes 3 code
regressions and the complete responsive sizing UI journey (1/1), with inspected
Tablet/reopen captures. Twelve distinct UI workflows now pass; the last connected
image/typography method is running. Initial cancellation hypotheses were disproven
and removed: the actual boundary was failed refocus after the native preset.
No current authentication, broad gate, installed update or completion claim.

Earlier acceptance: eleven distinct native workflows now have passing focused
results. Two connected journeys remain active after concrete repairs: alignment
menu ownership and geometry Escape field-editor write-back. Five affected code
regressions pass; the final changed-tree collector has not run. Full result
history and original-resolution visual findings are in the 005 evidence. No
current authentication prompt, new feature, commit, push or installed replacement.

Historical first accumulated group: five of nine passed (two component/history journeys
and three Settings journeys). Four concrete failures are being repaired and
rerun: native-text versus document Undo preconditions in image/sizing tests;
truthful Image/Text accessibility labels in the connected journey; and Bounds'
outdented native disclosure frame, now using the existing production accessible
disclosure style. No containment/history/identity assertion is removed. Inspect
new screenshots, finish browser/compact acceptance, then freeze for one gate.

Current bounded follow-up: accumulated native/visual acceptance under SF-1902-004/006,
SF-0201-006/008 and SF-0206-006, plus the existing 002/003/004/005 requirement
mappings below. The 17:19 retry initialized and created the named component;
the test queried Design-only provenance while Layout was selected. Plan:
select the actual Design control and assert its selected state, review remaining
navigation preconditions, rebuild the isolated OwnerTesting target, run that exact
workflow first, repair demonstrated failures, then continue the existing focused
acceptance inventory and visual/browser/Settings review. Freeze for one integrated
gate only when ready. No new feature, commit, push, privacy/service change or
installed replacement over unknown owner work.

Historical diagnosis (superseded by successful 17:19 initialization):
diagnose native initialization under SF-1902-004/006,
not product authoring. Plan: export the existing failed xcresult diagnostics,
compare last-good session/toolchain and identical warnings, inspect narrow
automation/authentication system-log slices and read-only session/configuration
state. No unchanged test rerun. Correct only a demonstrated repository boundary;
otherwise identify the exact owner authentication prerequisite, independently
of computer-use transport. No permissions/services/global toolchain changes.

Diagnosis: runner/control-session authorization succeeded; the automation-mode
writer then required device-owner authentication. LocalAuthentication requested
“Enable UI Automation” and did not complete before timeout. Current Developer
mode is enabled, and provision/tool/architecture checks show no launcher mix.
The simulator warning also accompanies the passing code target, so it is not
established as the cause. No source fix/control test/unchanged retry is justified.
Owner readiness for system authentication is requested; see current OD-025.

2026-10-23 acceptance continuation (no new feature): owner authorizes ONE fresh
isolated XCTest route reassessment, independently of the historical computer-use
transport failure. Regenerate/check current OwnerTesting identity/fingerprint and
private fixtures before one pending native selector. If healthy, finish the
authoritative 005 acceptance inventory and visual/Safari review, then freeze for
one integrated gate. If externally blocked again, retain fresh evidence and stop
that route; no permission/service reset, ordinary-app termination or installation
over unknown owner work. This supersedes only the prior unchanged-route retry
prohibition, not preservation, verification or no-commit/GitHub boundaries.

Fresh outcome: current isolated build/provision checked at fingerprint `f601b53b…`.
The exact component UI selector ran no method: automation-mode initialization
timed out (one runner error, exit 65). Separate computer-use tooling is not exposed.
Complete private code-only target passes 717/717, zero failures/skips; no full
collector/unchanged UI retry. Protected Aurora packages/sidecars match fresh 4/4
hashes. Installed build 26.10.21 remains older and untouched. OD-025 stays open;
single current evidence/inventory: `evidence/SF-LOCAL-BUILDER-005-INTEGRATION.md`.

Owner-authorized final source-polish package, 2026-10-22. Preserve 002/003/004,
their overlapping focused evidence and OD-025 independently; the historical
815-test baseline predates these sources. Bounded SF-0203-002/003/004/005/006,
SF-0301-003/004/005/006, SF-0306-003/004/005/006,
SF-0307-003/005/006, SF-0702-002/003/004/005/006 and
SF-0705-003/004/006 only where exercised; modules remain Partial.

Plan before code: (1) inspect/test retained component/layout/typography drafts
at Save/Save As, Preview, context, Close and native Undo boundaries; use small
scene-local event adapters to existing validators, never a second draft store;
(2) fix demonstrated stale operation/feedback ownership using existing request
and immutable revision gates, retaining last-valid resources/output;
(3) focused isolated state/history/package/cancellation tests plus compile one
connected public-control journey; (4) consolidate one current pending native/
visual/Safari/Settings/installed inventory and factual source evidence.

No known-hanging native/automation retry, privacy/service change, app replacement,
original Aurora/recovery mutation, new persistence/reclamation policy, commit,
GitHub or release work. No new component architecture under OD-018/019. Native
and full acceptance remain pending; after this bounded package return to that
acceptance/local delivery rather than starting unrelated authoring categories.

Reviewed source checkpoint: action-boundary editor validation, native text Undo,
panel-origin checks, current preview adoption and async feedback ownership are
implemented. A demonstrated shared export alias bug is corrected with containment
checks intact. Supporting SF-1201-003/004 and SF-1206-003/004 are bounded/Partial.
Final affected group passes 24/24 code tests (ten new, fourteen regressions);
app/UI targets compile. Existing connected/native journeys are extended but
NOT executed. Exact results and ONE current acceptance inventory:
`evidence/SF-LOCAL-BUILDER-005-INTEGRATION.md`. No new visual/full/installed pass.
Repository/security/architecture/evidence checks and 440-record traceability
pass; `git diff --check` passes. No focused process remains; work is uncommitted.

## SF-LOCAL-BUILDER-004 — Practical image reuse and typography — IN PROGRESS

Owner-authorized connected source package, 2026-10-21. Keep 002/003 IN PROGRESS
and OD-025 independent. Bounded SF-0801-002/003/004/005/006,
SF-0802-003/004/005/006, SF-0807-002/003/004/005/006,
SF-0507-002/003/004/005/006 and font-fallback SF-0805-003/004/006; modules Partial.
Existing importer/resources, organization, image/fill/component media commands,
CoreText typography and immutable output are inputs, not missing capabilities.

Plan before code: (1) make selected-use asset choosing/import available beside
Image/fill/exposed media controls, routing captured identity through existing
registries and one atomic import/reference transaction; (2) make global Replace
All explicit, confirm current reference scope, revalidate before/after the native
panel and consolidate existing usage projection/reveal coverage; (3) add local
installed-family search and truthful available-weight/fallback presentation,
retaining scene-local typography drafts across unrelated adoption and guarding
context changes; (4) focused scope/import/history/package/font/output regressions,
compile one connected native journey, update factual source/pending evidence.

No new asset store, schema, renderer, command stack, font import/distribution or
licensing policy. No privacy/native retry, app refresh, Aurora/recovery changes,
commit/GitHub/release/signing. Prior 815 gate is historical. Native/visual/Safari,
pending components/responsive/Settings and accumulated full gate await access.

Source checkpoint: scoped chooser/import, explicit global replacement/reference
inventory, adoption-safe usage reveal, resource-aware thumbnail invalidation and
installed-family/available-weight controls with retained typography drafts are
implemented. Final focused group passes 22/22 code tests (seven new); app/UI
targets compile. New native journey is NOT executed. Exact tests/results and one
pending native/visual/Safari/Settings/full inventory:
`evidence/SF-LOCAL-BUILDER-004-ASSETS-TYPOGRAPHY.md`. No completion claim,
installation, commit or GitHub operation. Earlier 815 gate remains historical.
Repository/security/hygiene/architecture/evidence checks and 425-record
traceability pass; `git diff --check` passes. Focused processes have completed.

## SF-LOCAL-BUILDER-003 — Practical responsive sizing workflow — IN PROGRESS

Owner-authorized connected source package, 2026-10-21. Preserve component reuse
IN PROGRESS and OD-025 independently. Bounded SF-0501-003/005/006,
SF-0502-003/005/006, SF-0505-002/003/004/005/006,
SF-0601-002/003/004/005/006, SF-0602-003/005/006 and SF-0604-003/005/006
only where exercised; modules Partial. ADR-0025, `layout.sizing.v1`, existing
responsive/fluid resolvers, registries, native metrics and output stay authoritative.

Plan before code: (1) expose effective sizing winner/source without concealing
numeric overrides, operation-specific mode eligibility, exact dimension reset
and conversion scope/skips through existing registries; (2) consolidate Layout
size/geometry/container controls into consistent adjacent cards; stabilize only
matching numeric drafts across unrelated adoption, identity-gate commit and
retain conflicts on selection/breakpoint changes; (3) exercise realistic nested
content across 320/375/390/430/574/768/1024/1440 widths, exact override/reset/history,
package/recovery and immutable output, fixing demonstrated shared defects;
(4) compile one connected public-control journey, run affected code/repository
checks, record native/Safari/installed/full gate pending until access is restored.

No automatic conversion, legacy default changes, measured geometry writes,
second cascade, width/Image Hug, sample-specific CSS or browser-parity claims.
No known-hanging native retry, current-app replacement, original Aurora/recovery
change, commit, GitHub, release or signing. OD-018/019 remain excluded. Final
changed-tree accumulated verification follows actual native/visual acceptance;
the historical 815 pass does not verify either new package.

Source checkpoint: effective sizing/provenance and exact dimension reset,
counted conversion disclosure, adjacent Layout cards and retained numeric drafts
implemented. Shared Grid/CSS numeric precedence and continuous connected fluid
projection corrected. 23 unique code tests pass (11 new); subsequent strengthened
height/reset selectors pass 2/2 without increasing that count. Both app/test
targets compile; new public-control UI journey remains unrun. Native/visual/
Safari, component/Settings inventory, installed refresh and final accumulated
gate remain pending. Evidence: `evidence/SF-LOCAL-BUILDER-003-RESPONSIVE-SIZING.md`.
Repository/security/hygiene/architecture/evidence checks, 425-record traceability
and `git diff --check` pass. No test/collector remains. Work stays uncommitted.

## SF-LOCAL-BUILDER-002 — Practical component reuse — IN PROGRESS

Owner-authorized package, 2026-10-21. Supersedes the previous Settings-only
closeout's prohibition on starting this package; OD-025 remains independently
pending. Preserve the 815-test baseline as historical evidence for unchanged
source, not a pass for this new slice. No commit/push/install, original Aurora
or recovery changes; leave the current verified regular app intact.

Requirements: bounded SF-0901-003/005/006, SF-0902-003/005/006,
SF-0905-003/005/006 and inspection-oriented SF-0907-003/006. Modules Partial.
Existing creation/placement, definition editing, six exposed property types,
grouping/discovery, conflict reset, Details/Where Used, immutable expansion and
output are reused; older source-only records do not mean absent implementation.

Plan before code: (1) named creation through the existing component registry,
with truthful eligibility/empty-state action and one atomic inverse; (2) typed
scene-only definition-return context validating document/page/source identities,
restoring the original selection through existing adoption or reporting safe
fallback; clear mode and Return to Instance/Page; (3) reuse grouped controls on
Design as well as Content, preserve stable text editor identity across commits,
native Return/focus-loss and Escape without bypassing identity gates;
(4) connected two-instance propagation/reset/history/package/output regressions
plus focused eligibility/navigation/draft tests and a public-control UI journey;
(5) focused code/build checks only while native automation is unavailable;
record native/browser/action-audit results only when executed. Final changed-tree
full gate and safe installed refresh wait for native access and saved/quit proof.

Exclude supplied/nested slots, retarget/conversion (OD-018/019), nested components,
variants, remote libraries and new serialization architecture. Do not repeat the
broken native binding or broad suite. No new sample-specific authoring path.

Focused source checkpoint: named creation, shared eligibility, typed definition
return, shared Design/Content property controls and stable text drafts implemented.
Final focused group passes 17/17 code tests, including seven new regressions;
application and UI test target compile. New public-control journey is compiled,
not run. Native/Safari/visual/action-audit acceptance and final changed-tree full
gate remain pending OD-025; the old 815 pass is not reused for these edits.
Evidence: `evidence/SF-LOCAL-BUILDER-002-COMPONENT-REUSE.md`.
Repository/security/architecture/evidence checks, 425-record traceability and
`git diff --check` pass. No collector or test runner remains. Work is uncommitted.

### 2026-10-21 — SF-LOCAL-BUILDER-001 final verification PASSED; installed Settings review pending

Current closeout: one fresh native binding still fails with a closed pipe; no
UI action, test or app replacement followed. Current user work is unknown, not
assumed blank. Owner normal Quit/reopen/Settings “visible” or screenshots is the
only next delivery action (OD-025). All seven requested Settings destinations
remain uninspected; source/full acceptance is not undone. Evidence:
`evidence/SF-LOCAL-BUILDER-001-INSTALLED-VISUAL-DELIVERY.md`.
After delivery, the next already-listed package is Practical component reuse,
building on existing media/action/reset/navigation source, excluding OD-018/019
architecture. Do not start it here or treat old source-implemented items as absent.

The final changed-tree unattended full gate `20261021-034253-d689cac6` PASSED:
repository/build, 682 code + 133 UI = 815 tests, zero failures/skips, empty failed
selectors. No test/collector remains. All new workflow selectors pass in the
full target. Installed Aurora/native browser/reopen passes 1/1, seven captures
reviewed; app/provision/source fingerprints and protected package/resource hashes
match. This supersedes historical full-gate-pending records below.

Do not repeat the broad suite. The remaining whole-checklist item is OD-025:
an extra installed Settings run executed zero tests (automation-mode timeout),
then native inspection lost its pipe after Settings while Finder stayed readable.
Live blank screenshot retained and inspected; app main thread sampled idle.
Owner normal reopen/Settings confirmation or screenshot is needed, not a privacy
grant or product workaround. Keep the package IN PROGRESS only for that final
installed visual comparison; implementation/full verification are complete.
All work uncommitted, no GitHub/new feature/original/recovery cleanup authorized.

### Historical 2026-10-21 — Independent reuse and contextual editing — now verified above

Regular installed-app review now passes 1/1 (158.722s); all seven installed
captures inspected. Native Save As preserves the existing Study; fresh hashes
match Editorial, Study and both resource sidecars. App/provision/source fingerprint
match. Final changed-tree accumulated gate is next, not yet passed.

The approved follow-up is implemented, not yet integrated/installed acceptance.
Named opt-in current-page copying reuses duplication and copies page metadata
atomically; Header/Footer Include All Pages reuses the identity-gated registry;
plain-Text selection defaults to Text Foreground beside Typography. Shared title
resolution now reports its actual authored/site/Home/stored-default provenance.
No live-linked Header/Footer model, new schema or original-site conversion.
Bounded SF-0303-002/003/004/005/006, SF-0308-002/003/005/006,
SF-0507-003/005/006, SF-0509-003/006, SF-0806-002/003/005/006,
and SF-1207-003/005 remain Partial.

Focused model coverage passes 8/8 plus the title-provenance regression 1/1.
Three controls journeys pass 3/3; the existing foreground/token journey passes.
The additional normal-Aurora/native-Safari/save-reopen journey passes 1/1
(142.149s), `focused-8c05cb14-7563-40ec-b918-4fb401a850ed.xcresult`.
Nine control and seven Aurora captures inspected. Matched real pointer actions:
related page 10 -> 6; two missing navigation destinations 2 -> 1. No elapsed-time
or universal authoring reduction is claimed. Latest helper fixes address Safari
link title (not label) and native file-panel autocompletion entering the resource
sidecar; select the exact project in its parent folder, never bypass native Open.
Next: safe regular-app refresh and native review on an independent Study copy,
then the final accumulated checkpoint for the changed tree. No commit/push.

### Historical 2026-10-21 — SF-LOCAL-BUILDER-001 targeted checkpoint repair

Integrated checkpoint `20261021-002649-dee2b04f` PASSED: repository/build,
675 code + 129 UI = 804 tests, zero failures/skips/expected failures. Both
repaired selectors pass in the full run. No publish-during-update or invalid
view-geometry message; retained Apple QoS diagnostics are not reclassified.
No collector/runner remains. Continue the approved workflow follow-up now:
named independent page copy via existing duplication (including document-owned
page metadata), atomic current-Header/Footer Include All Pages, contextual color
target/default plus native Return/Tab/Escape proof. Measure matched public UI
actions, preserve source pages/NodeIDs and original Aurora, then focused visual
acceptance and a final integrated gate for the changed production tree. No
new sharing model, schema field, commit/push or owner-data rewrite.

Repairs validated: isolated pinned verification runtime plus missing/valid
prerequisite regression checks pass; approved icon and all repository checks
pass. Recovery and foreground/token journeys pass 2/2 (25.368s, 178.210s),
`focused-8fb70684-3db1-4096-af4f-853a1d7339b5.xcresult`. Seven captures reviewed.
No product behavior or focus assertion weakened: actual artifact/run/PID guards
replace obsolete hard-coded app lookup; strict viewport containment replaces
hittability-only reveal for the clipped token field. Integrated result pending.

The subsequent preparation was cancelled before build/tests for an observed
progress-helper Swift actor-entry compile error. Explicit main-actor ownership
and a pre-launch type-check now fix that boundary. Affected collector tooling
passes 21/21, including failure/no-spawn/no-lock regression; helper type-check
passes. No additional product/UI source change or repeated UI run was needed.

Finished collector `20261020-213032-8c1fc557`: FAILED, repository Pillow missing,
build passed, code 675/675; UI 127/129, zero skipped. No active runner. Bounded
plan: (1) pinned isolated image-check runtime and prerequisite regression;
(2) recovery test exact launched artifact/run/PID ownership, SF-0306-003/004/005/006;
(3) fully reveal the token editor before real pointer focus, SF-0507-003/005/006;
(4) affected focused checks and two exact native journeys with screenshot review;
(5) integrated unattended checkpoint, then queued workflow consolidation only
after a genuinely green result. No historical banner/lock assumption, no test
weakening, no original Aurora/recovery edits, no commit/push.

### Historical 2026-10-20 — Verify and continue the Aurora simplification

Fresh owner-clear acceptance: unchanged
`testButtonLinkInternalTargetControlsAtPracticalMinimum` passes 1/1 (52.649s),
bundle `focused-75b3a453-d776-44f2-8d7c-cb50f82a0b96.xcresult`. Pointer Undo
restores Home; both retained captures show a clear toolbar. OD-024 is resolved.
Evidence is in ignored `.codex-loop/full-verification/owner-clear-focused/`.
No Undo/command/history correction or assertion relaxation was needed. Next is
one unattended accumulated checkpoint, then the already planned consolidation;
no integrated pass or milestone completion is claimed yet.

Owner confirmed the current screen is clear (2026-10-20). OD-024 is no longer
an owner-action blocker; the exact pointer journey must now be tested afresh.
Historical temporary artifacts are unavailable, not evidence of a current
notification. New evidence stays in ignored local report storage.

Historical external blocker: OD-024. A prior screenshot showed an unrelated system
notification covers title-bar Undo; the compact Button/Link test's click fell
back to its center under that banner and its post-Undo assertion failed. The
accumulated attempt passed 675 models and eight UI journeys, then was stopped,
not passed. No collector remains. Owner was asked to dismiss only that banner.
Next: exact `testButtonLinkInternalTargetControlsAtPracticalMinimum` after normal
dismissal, then accumulated verification. Do not weaken its Undo assertion or
change command routing based on an obstructed pointer event.

Preserve SF-LOCAL-BUILDER-001 and all owner data. Pending structural acceptance
is restored: both exact UI selectors pass 2/2 in
`focused-20923f31-5b20-456e-9592-6237107acb48.xcresult`; earlier activation failures
occurred before feature assertions. Strict actual-segment bounds remain intact.
The prior full attempt passed 675 models and 116 UI journeys before the
outdented-wrapper assertion. It is not a complete passing gate.

Plan: (1) close the accumulated full checkpoint before further product edits;
(2) inventory actual old/new public-control actions, separating product friction
from automation mistakes; (3) reuse existing page duplication in a named/route
creation sheet and existing navigation commands for predictable page inclusion,
without inventing cross-page live-linked Header/Footer semantics; (4) consolidate
safe contextual typography/color/direct edits using existing registries and
scene drafts, preserving Return/Tab/Escape, stale/invalid neutrality and atomic
Undo; (5) focused native/Safari checks on a normal duplicate, preserve the eight
widths, inspect original-resolution evidence, refresh the installed source and
testing provision safely; final integrated gate after additional production
changes are ready. Bounded SF-0303-002/003/004/005/006, SF-0308-002/003/005/006,
SF-0502-003/005,
SF-0507-003/005, SF-0602-003/005, SF-0701-002/003/004/005/006,
SF-0702-003/004/005/006, SF-0806-002/003/005/006. Modules remain Partial.
No commits, pushes, new sharing architecture or destructive original conversion.

### Historical owner-authorized Aurora workflow follow-up — implementation verified 2026-10-21

Latest integration correction: all 675 model/integration checks pass. A later
dark-editor UI assertion still used obsolete 300/340-point pane caps; it now
requires the approved 324/356 minima, 360/420 maxima, canvas remainder and no
overflow. Two policy tests plus the real visual journey pass 3/3 in
`focused-994388ba-9214-4f86-bb87-f74f60f28987.xcresult`; all five captures reviewed.
The stopped red full attempt is not a pass. Final gate remains required.

Dependency checkpoint: the real Aurora is saved/exported; the installed editable
sample, real Safari output/navigation, manual legacy recovery and isolated
first/clean/crash startup paths now have focused native proof. Preserve that
original. A separate Workflow Study was created through native Save As, and
the original package checksum is unchanged. No authoring replay or app copy.

Requirements: bounded SF-0201-003/006, SF-0501-001/003/004/005/006,
SF-0502-003/005, SF-0505-001/002/003/004/005/006,
SF-0507-003/005, SF-0602-003/005, SF-0701-002/003/004/005/006,
SF-1203-003/004/006 and SF-1207-003/004/006. Modules remain Partial.

Plan: (1) allocate pane minima from measured five-label rows at normal widths;
keep explicit constrained/large-text adaptation and canvas minimum; make
unchanged Site Settings Apply close neutrally with specific feedback;
(2) measure Inspector heading/field/scroll geometry across the documented update
sequence and fix demonstrated instability; expose contextual essential edits
through shared registries/components and compare real action counts;
(3) add explicit opt-in Fill/Hug sizing and shared intrinsic text measurement,
parent propagation and browser/native resolution, preserving deliberate fixed
overrides; validate 320/375/390/430/574/768/1024/1440 widths on the Study;
(4) use existing explicit page/chrome reuse only where the approved contract
supports it; retain any precise remaining owner decision;
(5) focused tests and original-resolution comparison during corrections, then
the one accumulated integrated final gate when source, native evidence and docs
are ready. No commit/push/publication. Detailed before-state friction remains
in `evidence/SF-LOCAL-BUILDER-001-AUTHORING-FRICTION.md`.

Focused checkpoint: four sizing/transaction/native-font checks and the real
Fill/Hug control journey pass. Measured five-row Layout states and neutral
Site Settings Apply have native passes. Contextual Design Essentials label,
size, destination, invalid draft/Escape and Undo/Redo pass 1/1. The isolated
Aurora opt-in conversion/preset journey now passes 1/1; two earlier
attempts incorrectly matched Touch Bar confirmation controls. Installed Study
conversion/padding and real save/reopen checks pass; all eight browser widths
were reviewed after fixing shared flex-basis and intrinsic-grid output defects.
All 84 NodeIDs and base frames remain exact (revisions 183 → 185); the original
Aurora and 69 original recovery files remain checksum-identical. Schema 19 and
the single sizing/text/output authority are recorded in ADR-0025. Exact
evidence/remaining work: `evidence/SF-LOCAL-BUILDER-001-RESPONSIVE-WORKFLOW.md`.
Source/installed/browser focused acceptance is ready for the accumulated final
gate. Do not mark DONE until it passes. Preserve original Aurora and recovery.
The attempted integrated gate exposed six stale fixture/announcement expectations
and Settings defaults; affected models now pass 6/6 and grouped Settings 1/1.
An additional strengthened historical chrome rejection passes 1/1. After the
owner reported no prompt, the exact appearance journey passed 1/1 (37.828s),
`focused-4de2a0c3-86e7-45cb-a6de-acd755018b88.xcresult`. OD-023 is resolved
without permission changes. Next: accumulated final integrated gate.
No full-gate success is claimed.

## SF-LOCAL-BUILDER-001 — Aurora authoring and Safari delivery — IN PROGRESS

Owner-authorized integrated local-builder package, 2026-10-16. Preserve accepted
`ab18c66`, existing residual-diagnostic documentation and all genuine user data.
No commit, push, publication or distribution signing is authorized.

Requirements: bounded SF-0201-002/006/008, SF-0204-002/005/006,
SF-0206-002/003/006, SF-0306-003/004/005/008, SF-0402-003/006,
SF-0405-003/006, SF-0407-003/008, SF-0501-003/005, SF-0502-003/005,
SF-0503-003, SF-0506-003/005, SF-0507-003/005, SF-0508-003/005,
SF-0601-003, SF-0602-003/005, SF-0603-003, SF-0604-003,
SF-0701-002/006, SF-0702-003/006, SF-0801-002/004/005,
SF-0802-003/005, SF-1201-002/003/004/006/008, SF-1202-003,
SF-1203-003/004, SF-1204-003/004, SF-1205-003/004,
SF-1206-003/004, SF-1207-001/002/003/004/005/006/008,
SF-1208-003/004/006/008. Coverage stays Partial until evidenced.

Plan and durable acceptance checklist:
- [x] Translate original render 01's composition into the owner-selected dark
      editor using shared semantic tokens; preserve explicit appearance choices,
      native accessibility and unchanged pale website content. Installed blank,
      Aurora/Inspector and Safari captures reviewed; Settings is separated below.
- [ ] Complete all installed Settings destinations against render 12 (OD-025).
      Fresh binding failed; current user work is unknown. No forced Quit/retries.
- [x] Review full recording sequences, screenshots and approved renders; map
      observed owner actions and render-1 authoring gaps before tool changes.
- [x] One-click Safari loopback preview serves the existing compiled export
      artifact, with bounded secure routing, cancellation, last-good output,
      revision status and native Open Again/Refresh/Stop controls.
- [x] Crash-only automatic recovery; explicit legacy history access; isolate
      validation recents/session ownership without deleting genuine snapshots.
- [x] Shared Inspector sections and native selected/keyboard focus behavior;
      readable supported property controls; no authored structural labels.
- [x] Transactional Site Settings and page title/description/favicon output.
- [x] Author Aurora using installed production controls, assets and ordinary
      commands; save/reopen the editable package and optional sample/template.
- [x] Validate real Safari navigation/mobile menu and compare app/browser at
      matching viewports, recording actual fidelity limits and missing tools.
- [x] Focused regressions, completed full collector (815 passes), safe regular-app
      update and factual evidence. Visual review is complete except Settings above.

Explicit exclusions: remote publishing/accounts, paid/licensed acquisition,
distribution/release work, arbitrary HTML/CSS injection, screenshot-as-website,
sample-specific rendering branches and unproved full-module completion.
Evidence/checklist: `evidence/SF-LOCAL-BUILDER-001-AURORA.md`.

### Historical implementation chronology — superseded by the current checklist

Aurora authoring checkpoint, 2026-10-18: the existing ordinary project now has
four editable pages, independent image/overlay/text/actions, authored responsive
geometry/fluid typography and native Safari/export evidence. The remaining
startup-sample source (bounded SF-0204-002/004/005/006) loads that exact
UI-authored package through the existing package/resource readers, establish a
fresh document/project and clean history baseline, and expose a visible native
Welcome choice. It must not embed a hand-authored model fixture, write into the
application bundle or mutate the delivered original. Validate resource identity,
missing/corrupt input, cancellation and save/reopen with focused checks before
installed-app acceptance. Crash qualification and the final collector remain.
The separate subsequent streamlining review is recorded in
`evidence/SF-LOCAL-BUILDER-001-AUTHORING-FRICTION.md`; do not substitute it for
this delivery or begin its UI redesign here.

Sample source checkpoint: five focused template/resource/lifecycle checks pass;
two corrected historical resource fixtures pass. ADR-0023 records the read-only
bundled resource boundary. The actual-app sample test compiled but its only
attempt was canceled at launch after macOS reported a locked console. No native
acceptance is claimed and no runner remains (OD-022). Recheck unlock, run the
exact sample journey, then inspect/install safely before crash qualification
and the integrated final gate. Preserve the delivered ordinary Aurora original.

Crash qualification plan (bounded SF-0306-003/004/005/006): retain the existing
validated recovery/retirement authority; attach a versioned session identifier
only to new recovery packages; hold an advisory session lock until process exit;
mark normal AppKit termination clean using fixed-size descriptor writes; require
an abandoned running session for automatic Welcome recovery. Keep all legacy
snapshots byte-for-byte and expose explicit native Recovery History review.
Strip session evidence from durable saves, never canonicalize session/UI state,
and test live/clean/crash, unsafe files, manual legacy access and exact
restore/save before native acceptance. Source is implemented; seven focused
recovery/autosave/ownership checks pass in
`focused-8cebb442-2596-4507-89f1-d560022915b7.xcresult`. All 69 original hashes
match. The additional launch-controller clean/crash branch check passes 1/1
(`focused-eb3ae24b-9dc8-4159-99ba-8711d9192584.xcresult`), giving eight distinct
focused checks. Native journey source compiles (`build-for-testing` exit 0).
No full gate or installed recovery acceptance is claimed. Native work is
pending normal unlock; no activation retry loop was started.

Next implementation chunk (SF-1207-001–006/008): one versioned canonical
website-metadata record, with stable PageID-keyed overrides; transactional Site
Settings distinct from application preferences; shared title/description/favicon
resolution for Header defaults and the existing compiler. Preserve omitted versus
authored values, migrate historical documents/history explicitly, keep drafts
local and cancellation neutral, and include favicon asset dependency safety.
Use focused codec/history/resource/output checks before the native settings
journey. Social/structured data, public-domain configuration and release SEO
acceptance remain explicitly outside this bounded chunk. Crash qualification
and UI-authored Aurora remain required in the same package, not abandoned.

2026-10-18 metadata checkpoint: canonical schema 18/history 3, identity-gated
Site Settings, stable page overrides, exact undo/reset, escaped static metadata,
favicon dependency safety and default Header title resolution are implemented.
Focused history/metadata suite passes 22/22; two additional dependency/adversarial
checks pass 2/2; affected existing output checks pass 5/5. Native Apply/Cancel/
Undo/Redo journey passes 1/1 (49.593s); both final captures reviewed and search
preview remains visible outside scrolling fields. Save/reopen and explicit
recovery metadata/history checks pass. This is not integrated completion;
crash-qualified launch recovery, finished UI-authored Aurora, actual mobile
Safari fidelity and safe installed-app delivery remain next in this package.

2026-10-17 focused checkpoint: shared dark appearance/palette checks pass 10/10;
primary pointer Preview and actual Safari journeys pass 2/2, with all three
original-resolution captures reviewed. OD-022 is resolved. Shared Accessibility
sections and keyboard/pointer focus refinement are under focused acceptance;
the full package, installed dark Aurora and final gate remain IN PROGRESS.
Current evidence supersedes the historical lock/context-menu checkpoint below.

2026-10-18: native overflow is now visibly painted and keyboard/AX operable;
dark section/fill-layer checks pass 2/2 plus native overflow/default reset 2/2.
Complete adaptive keyboard traversal and dark visual journey pass 2/2. Latest
paper-ink/material 3/3 and Accessibility/Safari 2/2 pass. Captures reviewed at
original resolution. Source remains IN PROGRESS: crash qualification, metadata,
finished Aurora/mobile Safari, regular installation and integrated gate are due.

Earlier focused checkpoint: browser core 5 distinct tests, sandbox 1, raster/
pointer-coordinate 3 and connected-output 4 pass. Real Safari journey passes;
primary-command four-journey group records 3 passes and one obsolete context
menu failure, now corrected but not accepted. Native pointer confirmation is
blocked by positively confirmed macOS screen lock (OD-022), not waived.
The ordinary installed-app Aurora starting project and image fill are saved;
three black-box inspection/authoring steps pass and captures are reviewed.
Main Preview routes to Safari; native device preview remains separate. Finished
sample, remaining owner corrections, new output visuals and final gate remain
required. All source changes remain uncommitted; no runner active at handoff.

## SF-PRODUCT-UI-010 — owner correction and local delivery — DONE

Final acceptance — 2026-10-15: `./sf verify` exited 0. Repository/security,
traceability, architecture, evidence and build checks pass; 636/636 model and
119/119 UI tests pass (755 total, no skips). Result bundle:
`full-ccd26b85-b343-4b99-a179-af63921dd057.xcresult`.
Four repaired native journeys pass 4/4 and compact native overflow follow-up
passes 1/1; fourteen final captures reviewed at original resolution, in addition
to installed-app evidence. All 69 original recovery files remain unchanged.
Regular owner app is installed; one local commit authorized, no push.
Counter stays 2/10; no next feature started. Normative modules remain Partial.
Xcode still records 47 internal QoS inversion warnings; these are not claimed
resolved. No publish-during-view-update or invalid-view-geometry log appeared.

### Historical acceptance chronology (superseded by final result above)

Latest complete collection: 636/636 models +118/119 UI; compact page test
updated to use shipping native Inspector overflow rather than absent direct
tab. Exact follow-up passes 1/1, two captures reviewed. Final gate remains due.

Focused acceptance — 2026-10-15: owner Xcode restart resolved OD-021; four
interaction journeys pass 4/4 (399.845 seconds), twelve original-resolution
captures reviewed. Installed app refreshed to accepted interaction source.
Final complete verify and reviewed local commit remain pending. Earlier
blocked/full-failure entries below are retained historical evidence.

Current boundary: latest full attempt records 636 model + 93 UI passes, four
UI assertion failures and one subsequent XCTest initialization timeout. Four
bounded interaction repairs compile; their focused normal/prebuilt UI attempts
execute zero tests because automation mode cannot initialize. OD-021 requests
normal Xcode restart. Preserve edits/recovery; no completion or local commit yet.
Exact selectors and next action are authoritative in `CODEX_HANDOFF.md`.

Requirements: bounded SF-0201-003/006/008, SF-0203-002/006/008,
SF-0301-004/006, SF-0306-003/004/005/008, SF-0307-003/005,
SF-0502-003/005, SF-0701-001/002/003/006/008, SF-1102-001–008,
SF-1201-003/006/008 and SF-1203-003/006. Modules remain Partial.

Owner clarifies full-width balanced sidebar tabs, distinct contextual Inspector
sections, non-destructive recovery deferral, and practical Header/Footer title,
page inclusion, menu and customization controls. Preserve compact toolbar,
centered bounded hint, global Settings and regular-app self-service testing.
Additional approved Settings correction uses one non-resizable secondary window,
no sidebar collapse toolbar, native titlebar clearance and the narrower common
Support form width across all seven destinations. Preferred content dimensions
are 970×740 points, sidebar 250, form 680 (632-point cards after page insets),
with one bounded per-display policy on smaller screens; native evidence pending.

Plan: preserve the completed collector evidence; repair its nine code and ten
UI failures; implement shared tab/Inspector layout and contextual controls;
retain unresolved recovery with a welcome route; extend existing canonical
page-flow/navigation commands and projections, history and output; run affected
tests and inspect installed app captures; run one accumulated collector and
repair failures before local delivery and a reviewed local commit. No push.

Baseline run 20261015-103239-d7607136 finished failed: repository/build passed,
614/623 non-UI and 108/118 UI passed (722/741, 19 failures). No active test
process remained at the post-run inspection. Do not count this as acceptance.
Evidence: `evidence/SF-PRODUCT-UI-010-OWNER-CORRECTION.md`. Counter stays 2/10.

Nested-layout expectation correction passes 1/1 (105.140 seconds), four captures
reviewed: five real nodes per Header/Footer, 14 Desktop/Tablet render objects,
12 Mobile surfaces with closed-menu links retained only canonically/in Layers.
The count predicate now rejects prefix matches. No product geometry changed.
The final complete gate remains required; interrupted attempts are not passes.

Latest final-gate repair: 636/636 model tests passed before the Settings concept
journey exposed root accessibility identity propagation. Explicit root
containment fixes the shipping sidebar/content semantics; its unchanged focused
journey passes 1/1 (24.021 seconds), all seven captures reviewed. The interrupted
full attempt is not a pass. Installed confirmation and the final gate follow.

Current handoff: owner action OD-020 is resolved; the subsequent recording has
no system permission prompt. Retained text AX value passes. The actual native
reset sheet now has semantic heading/Reset/Cancel assertions instead of an
incorrect XCUI Alert-container assumption, preserving Escape and exact history.
Bundled legacy fixtures and app-owned temporary data avoid checkout permissions.
Four related model checks and repository checks pass. The exact native recovery
rerun passed 1/1 (211.793 seconds); all four settled captures were visually
reviewed. Expanded Header/Footer title/page/Preview/reopen acceptance also passed.
Regular owner-local packaging/install succeeded with recoverable backup and
unchanged existing recovery bytes. Installed interaction remains pending because
the Computer Use native pipe closes even after a fresh kernel. Final accumulated
verification and local commit are not yet claimed. A later full attempt passed
635/635 unit/integration and fourteen UI journeys before exposing a missing
component-instance group inset. The shared-section correction passes discovery
and retained-recovery native checks 2/2; all five resulting captures were
inspected at original resolution. The two-instance text/history/reopen follow-up
passed 1/1 (283.374 seconds); all five follow-up captures were inspected.
The regular app has now been safely refreshed with matching source/provision
fingerprint. Production black-box native acceptance passes 1/1 (222.566 seconds),
including real Save/Close/Open, Preview and static output, with six final captures
reviewed. That review exposed and corrected Preview title truncation through the
shared text-layer factory; three focused metric/ink/navigation checks pass.
Installed Settings/Header/Footer/owned recovery checks passed 3/3 (308.387 seconds).
All 17 captures passed original-resolution review; all 69 recovery hashes match.
No runner remains active. Final complete verification and the
reviewed local commit remain pending; retain failed/interrupted evidence as such.

## Historical owner-local delivery correction — superseded by 2026-10-21 checkpoint

Focused evidence now green: 19 collector checks, eleven distinct model checks,
nine affected UI journeys and two installed actual-window Testing checks.
One bundled-fixture staging check and four script harness scenarios also passed.
The standard Cmd-W command, canonical empty-page logic and gradient caption
layout were repaired. Regular app safely installed with source provenance and
recoverable previous bundles. Finish the remaining installed connected-site/
Preview/local-export smoke and surface matrix; do not begin another feature.
Bounded launch checks are intentionally cancelled, not full-suite passes.

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

Codex processes the first READY item whose dependencies are satisfied. Keep items small enough to implement and verify in one focused iteration.

## ACCUMULATED VERIFIED CHECKPOINT — 2026-10-12

The bounded `SF-AUTHORING-106`, `108`–`113`, `SF-PRODUCT-UI-005/006/007`,
and fail-closed `SF-PLATFORM-UPDATE-001` source batch completed its authorized
gate. Repository, security, traceability (409 records), architecture, AppIcon,
and retained-evidence checks passed. The final documentation-inclusive
`./sf verify` passed 567 unit/integration tests and 104 actual-app UI journeys
(671 total, zero failures). Normative modules remain Partial wherever their
evidence lists deferred scope; update installation remains blocked by
`OD-017`.

## Execution policy — reset 2026-09-27

### SF-PRODUCT-UI-009 — selected-reference visual add-on (counter stays 2/10)

Owner selected actual renders 01 main editor, 05 responsive/other editor and
12 Settings; 04 superseded. Preserve approved loading. Bounded SF-0201-003/006/008,
SF-0203-006/008, SF-0206-003/006/008, SF-0407-003/006, SF-1505-006/008,
SF-1605-006/008. Shared matte palettes, proportional pane allocation, flat
Inspector sections, separate Settings cards, readable native tools and compact
management/disclosure source implemented. Two experimental builds passed,
3 focused model checks and 2 UI journeys passed before the latest refinement.
Affected visual matrix now running; broader accumulated gate still failed/pending.
Native computer-use pipe disconnected, despite rebind/reset; XCTest remains
available. Evidence/mapping: `evidence/SF-PRODUCT-UI-009-SELECTED-REFERENCES.md`.
No commit/GitHub/manual signing/install/release authorized. Runtime focused
builds/launch/UI are now authorized; old owner-away prohibitions below are history.

### SF-AUTHORING-124 — SOURCE IMPLEMENTED, verification deferred (cycle Prompt 2/10)

Practical Inspector workflow package. Requirements: bounded
SF-0701-002/003/004/006/007/008, SF-0702-002/004/005/006/008,
SF-0703-002/003/004/005/006/008 and SF-0704-003/004/006.
Dependencies: 123 discovery, existing geometry/responsive registry and history.
Plan: native section search/navigation/pins plus supported typed geometry
copy/paste, strict clipboard validation, explicit mixed/subset/provenance status,
one identity-gated atomic edit, test source and concise package evidence.
Search/pins remain scene-local; source values are resolved from the whole
applicable selection, never borrowed from the primary. Transfer scope is native
Layout X/Y/Width/Height in points at the current breakpoint; arbitrary properties
and resource/definition references are not accepted by this clipboard format.
No collector ownership file exists at the single pre-edit read. No execution,
commits or external operations authorized while owner is away.
Four deterministic tests and one native journey are written, not executed.
Evidence: `evidence/SF-AUTHORING-124-INSPECTOR-WORKFLOW.md`.
Phase-one delivery is now estimated at 5–8 complete packages after 124;
the old 19–32 micro-prompt range is superseded, not normative scope removal.

## Upcoming cohesive local-builder packages (supersede fragmented roadmap)

1. **Connected local website/output completion** — containing layouts, truthful
   compatibility recovery, navigation/Preview/local-export parity, assets and
   semantic metadata in one end-to-end workflow (121/122/110 dependency).
2. **Practical component reuse** — coherent variants/definition navigation and
   existing media/action/fallback workflows; supplied slots/retargeting only
   after OD-018/019 approval.
3. **Responsive styling completion** — existing cascade, practical breakpoint
   authoring and renderer/Preview/output agreement, not another parallel model.
4. **Assets/typography workflow completion** — local resource usability and
   bounded supported fonts/vector needs, preserving original bytes and intent.
5. **Local-builder polish/recovery/Settings** — native keyboard/AX, compact
   layouts, empty/error states and project lifecycle, plus accumulated acceptance
   repairs. Do not subdivide into standalone picker/reset/documentation prompts.

CMS, collaboration/comments/roles, plugins and remote/publishing work move to
phase two. Normative requirements remain unchanged/Partial, not waived.

### SF-AUTHORING-123 — SOURCE IMPLEMENTED, verification deferred (new cycle Prompt 1/10)

Component-property discovery/navigation. Requirements: SF-0902-006/007 and
bounded SF-0701-002/003/004/006/007/008. Depends on 119 organization and
120 retained-conflict projection; no dependency on OD-018/019 approval.
Plan: derive stable filtered rows from existing bindings/provenance; expose
native scene-local search, result navigation and clear recovery; keep retained
conflicts discoverable and disclose unfiltered reset scope. Add source tests
for all six types, ordering, live changes, context replacement and keyboard/AX.
Acceptance: source review now; compilation/tests/native visual and accessibility
acceptance deferred by owner. No schema changes or new mutation paths.
Source adds three model tests and one native keyboard/AX journey, all unrun.
Evidence: `evidence/SF-AUTHORING-123-COMPONENT-DISCOVERY.md`.
Remaining ordered inventory/conditional estimates: `REMAINING_DEVELOPMENT_ROADMAP.md`.

Prior collector 20261013-153433-e964329d finished with exit 1; the single
read-only ownership check found its process gone. Build passed; repository and
code stages failed; UI initialization timed out enabling automation mode.
Reports remain retained. Accumulated acceptance awaits owner return; no relaunch.

Historical launch: Prompt 10 accumulated acceptance was **RUNNING**, not verified. One detached
`./sf testing full` collector owns run `20261013-153433-e964329d` under
`.codex-loop/full-verification/`; collector PID 3870 and progress owner PID
3871 were confirmed at launch handoff. Preparation passed 13 collector tests
and 2 ordinary Settings boundary tests; all app/test targets built successfully.
No duplicate gate, commit, push or installation was started. Stop agent
monitoring and await the owner's final report. Native experimental Settings,
visual review and accumulated acceptance remain pending.

Development Prompt 9/10: **SF-AUTHORING-122 — SOURCE IMPLEMENTED, verification deferred**.
Requirements: SF-0501-003/004/005/006/008, SF-0502-003/005,
SF-0503-003/004, SF-0504-003/004, SF-0601-003, SF-0602-003,
SF-0701-003/006, SF-0806-002/003/004/006/008,
SF-0304-003/005, SF-0308-004/008, SF-1201-003,
SF-1203-003/006 and SF-1204-003/004.
Dependencies: 121, ADR-0020, existing structural/responsive/style/link/Preview
and transfer paths; preserve both local-testing add-ons. Plan: share container
policy and resolved geometry; emit nested ownership for connected pages with
one authoritative geometry stylesheet, complete navigation visibility/spacing/
keyboard state, retain precise unsupported-state findings, write meaningful
unrun containment/history/persistence/menu/transfer/native acceptance source.
Acceptance: nested containing width/height/padding/order follows the same
snapshot at each breakpoint; no repeated origins or latent positioning rules;
Header first/Footer after visible flow, role-specific navigation stays usable;
free Frames and unconverted legacy pages retain prior output. Compatibility:
no new schema or automatic conversion; exact identifiers/history retained;
isolated managed transfer and component ownership remain fail-closed.
Exclude external navigation, fixed/sticky roles, supplied component slots,
arbitrary authored code, broad browser/release certification and publication.
No execution, builds, checks, installation, signing, commits or GitHub operations.
Prompt 10 owns accumulated acceptance through the detached collector once.

Source result: shared container policy/resolved snapshots, nested semantic
ownership and authoritative connected geometry CSS, padded root height
expansion, bounded fitted minima, visible-only markers, navigation row/spacing/
visibility/current/context semantics, working menu state/focus and precise
incompatible-output findings. Seven new unit/integration selectors and one
actual-app selector are written and unrun. Prior nested-output and fixture-page
assertions were corrected without removing identity/history proof. Evidence:
`docs/evidence/SF-AUTHORING-122-CONNECTED-OUTPUT-INTEGRATION.md`.
Counter is 9/10; no execution or installation occurred. Next is accumulated
acceptance, not another feature: `docs/PROMPT-10-ACCEPTANCE.md`. Launch one
detached full collector only when authorized, give its report directory to the
owner, and leave it to finish without agent polling. No commit/push is authorized.

Development Prompt 8/10: **SF-AUTHORING-121 — SOURCE IMPLEMENTED, verification deferred**.
Owner-approved connected Header/body Section/Footer flow replaces the proposed
property-search slice. Requirements: bounded SF-0501-001/003/004/005/006/008,
SF-0502-003/005, SF-0504-003/004, SF-0505-003, SF-0601-003, SF-0602-003,
SF-0701-003/006, SF-0806-001/002/003/004/005/006/008,
SF-0304-003/005, SF-0308-004/008, SF-1201-003 and SF-1203-003/006.
Plan: opt-in canonical role metadata on existing Sections; shared dynamic flow
and navigation projection; anchored insertion/reorder and explicit legacy
conversion; dedicated native settings/page links; functional Mobile hamburger
Preview/output; exact central transactions, safe transfer and unrun coverage.
Acceptance: full available width, adjustable height, connected body ordering,
Header first/Footer after content, responsive layout and shared geometry,
stable navigation identities, keyboard/accessible menu and exact history/reopen.
Legacy Sections remain unchanged on open. Exclude fixed/sticky roles, arbitrary
responsive navigation policies, external links, component flow/transfer,
browser runtime certification and publication. Publication DOCX synchronization
and all builds/tests/checks/visual acceptance are deferred to Prompt 10.

Source result: schema-v16 optional Section roles, shared resolved page flow,
anchored insertion/height/reorder, captured native settings, stable PageID link
editing, native Mobile Preview menu and bounded structured static output.
Six new selectors plus one updated selector are written and unrun.
Unsupported isolated nested static flow fails closed. Evidence:
`docs/evidence/SF-AUTHORING-121-CONNECTED-PAGE-STRUCTURE.md`.
Counter is 8/10. Independent unattended-testing and experimental Settings
add-ons do not advance it. An experimental local build/install is the only
current build exception; test execution and verification remain deferred.

Owner add-on **SF-LOCAL-TESTING-001 — SOURCE IMPLEMENTED; acceptance deferred**
(SF-0206-001/003/004/005/006/008, SF-1607-004/006/008). Plan/result: one
detached staged collector, Xcode inventory/completion-based dual progress,
atomic run reports/scoped cancellation, experimental-only native Settings and
separate controller identity. An explicit local app/helper build passed;
tooling/Settings tests and actual testing runs are intentionally unrun.
Evidence: `docs/evidence/SF-LOCAL-TESTING-001-EXPERIMENTAL.md`. This add-on
does not increment the feature counter. Official exclusion/native progress
interference and runner integration require Prompt-10 acceptance.

Development Prompt 7 of 10: **SF-AUTHORING-120 — SOURCE IMPLEMENTED, verification deferred**.
Requirements: bounded SF-0902-004/005/006/008 and SF-0905-003/004/005/006/008;
supporting SF-0901-004, SF-0308-004/008, SF-1201-003 and SF-1203-003.
Dependencies: 113 stable override guards, 117 typed action/transfer, 119 grouped
presentation, ADR-0018 and SF-PRODUCT-UI-008. Plan: one derived conflict projection;
confirmed identity-gated reset-one/reset-conflicts; original definition/source
navigation and truthful restore guidance; dependency/transfer/output findings;
meaningful unrun history/persistence/failure/native coverage.
Acceptance: retained typed values and IDs survive missing definitions/bindings,
confirmation/cancel/stale boundaries, exact undo/redo and reopen; output/transfer
fail closed with redacted findings; no guessed target/type/override migration.
Exclusions: schema migration, binding tombstones, retargeting/conversion semantics,
supplied slots, runtime/visual/recovery certification before Prompt 10.
No tests/builds/checks/scripts/automation/commits/pushes/GitHub operations.
Seven new selectors are written and unrun. Evidence/Prompt-10 targets:
`docs/evidence/SF-AUTHORING-120-COMPONENT-OVERRIDE-RECOVERY.md`.
OD-019 records future retarget/conversion semantics; no decision blocks the
implemented confirmed-reset/original-source recovery. OD-018 remains open.

Development Prompt 6 of 10: **SF-AUTHORING-119 — SOURCE IMPLEMENTED, verification deferred**.
Requirements: bounded SF-0902-001–008 and SF-0905-003/004/005/006;
supporting SF-0308-003/004/005/008, SF-1201-003 and SF-1203-003.
Dependencies: 113–118 typed bindings/overrides, ADR-0018, SF-PRODUCT-UI-008.
Plan: definition-owned flat group/order metadata keyed by existing binding type;
central atomic organization edits; shared ordered grouped instance fields;
transfer/projection cleanup and meaningful unrun history/schema/native tests.
Acceptance: six property types use stable identities and deterministic order;
group/reorder/reset/cancel preserve values, geometry and conflicts; metadata
round-trips and transfers without duplicate stores or identities.
Exclusions: nested/collapsible groups, conditional property UI, bulk organization,
supplied slots (OD-018), runtime/visual/recovery acceptance before Prompt 10.
No tests, builds, checks, automation, commits or GitHub operations in this slice.
Six new selectors are written and unrun; source evidence and exact Prompt-10
targets: `docs/evidence/SF-AUTHORING-119-COMPONENT-PROPERTY-ORGANIZATION.md`.
OD-018 remains open; ADR-0018 childless instances and fallback ownership are unchanged.

Development Prompt 5 of 10: `SF-AUTHORING-118` Component slots/default fallback
is **SOURCE FALLBACK IMPLEMENTED — VERIFICATION DEFERRED; SUPPLY BLOCKED BY OD-018**. Exact
requirements: bounded `SF-0902-001`–`008`, `SF-0903-001`–`008`,
`SF-0905-001`–`008`; supporting `SF-0304-001/003/005`,
`SF-0308-003/004/005/008`, `SF-1201-003` and `SF-1203-003`.
Dependencies: ADR-0018, SF-AUTHORING-111/113/117 and shared UI-008 controls.
Plan: preserve canonical ownership; expose stable named definition containers
with ordered fallback children; add native Apply/Cancel/remove and linked
fallback inspection/edit routes; resolve through the existing immutable graph;
integrate transfer/dependency/detach/history/schema boundaries; add meaningful
test source. Acceptance: exact fallback order/identity, neutral invalid/stale/
cancel input, exact metadata history, stable package/transfer identity, and
truthful unavailable supplied-content state. OD-018 blocks instance-owned
supplied content, not this safe fallback slice. Excludes nested slots,
supplied-content storage/crop/events, arbitrary constraints, variants, remote
libraries, broad Preview/export certification and release work. No test/build/
compiler/checker/script/automation/GitHub operation, commit or push is allowed
before the authorized Prompt-10 boundary.

Source result: stable definition fallback bindings, native name/inspect/edit
routes, exact metadata history, immutable ordered projection, dependency/
transfer/detach integration and schema-v14 compatibility are implemented.
Six new selectors are written and unrun. Full supplied-content acceptance is
not claimed; see `docs/evidence/SF-AUTHORING-118-COMPONENT-SLOT-FALLBACK.md`.

Prompt 4 owner override: `SF-AUTHORING-117` Component action controls and
destination transfer is **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**. Requirements:
`SF-0902-001`–`008`, `SF-0905-001`–`008`, supporting
`SF-0308-003/004/005/008`, `SF-0806-002/003/004/006`,
`SF-1201-003/004` and `SF-1203-003/004`. Dependencies: 111, 113, 116 and
the UI-008 shared visual system. Plan: share the existing native destination
fields; add captured-identity definition/instance drafts and explicit resets;
guard binding retargeting; integrate action dependencies into clipboard
preflight/equivalence/mapping and immutable Preview/output resolution; write
history, invalid/stale/cancel, transfer and native UI acceptance source.
Acceptance: no silent redirect, stale mutation or lost override; readable
inherited/authored/conflict states and accessible Apply/Cancel/Reset; exact
history/package identity. Excludes arbitrary events/scripts, remote execution,
slots/variants/nesting and publication. Tests/builds/checks/automation remain
prohibited until Prompt 10. No commit or push is authorized.

Source result: native captured-identity action drafts, missing-binding recovery,
reset-all participation, transition guards, dependency/page-impact handling,
explicit clipboard action/target remapping and fail-closed findings, and virtual
section Preview resolution are present. Nine new focused test selectors are
written and unrun; the inherited Prompt-3 selector also remains pending.
See `docs/evidence/SF-AUTHORING-117-COMPONENT-ACTION-INTEGRATION.md`.

The specification, editable publication copy, ADRs, OPEN_DECISIONS,
IMPLEMENTATION_STATUS, this queue, and AGENTS.md are the authority hierarchy.
Each development prompt is one bounded user-visible vertical slice with exact
requirements, canonical model, native macOS UI, renderer/preview/output,
persistence/history/accessibility/cancellation, focused evidence, and factual
documentation. Run focused affected tests before each local commit; do not run
the full gate or hosted CI per slice.

`SF-AUTHORING-063` is Development Prompt **10 of 10**. After its focused feature commit, run one
authoritative `./sf verify`, repair failures, commit, push main, and monitor
hosted CI until green. Debug-only owner add-ons do not increment this cadence.
Until that checkpoint, commits stay local and no external GitHub/release action
is permitted. Normative modules remain Partial unless their full acceptance is
actually evidenced.

Owner override (2026-09-29): the post-repair local `./sf verify` passed
486 unit/integration and 70 UI tests. Leave this verified tree uncommitted for
owner review; do not push or publish. An earlier managed UI launch lacked
testmanagerd authorization, and the two product failures exposed by a later
direct UI run passed focused recovery before the final gate.

Owner batch override (2026-09-30): SF-AUTHORING-065–074 are the next ten
development slices. The one end-of-batch `./sf verify` executed 504/504
unit/integration passes and 79/81 UI passes. Its two UI test-contract failures
passed exact focused reruns after correction; do not rerun the complete suite
for unchanged coverage. Review the combined diff and portable repository
checks, then create the expressly authorized local batch commit and push
main. This does not authorize a release or imply a single wholly green full
run. `SF-0205` and `SF-0206` remain Partial.

Hosted checkpoint correction (2026-09-30): commit `73c653a` reached the CI
job's 60-minute limit while XCTest was still progressing. The log also exposed
two actual-app pointer targets that were not hittable on the 1024-point hosted
display: a redundant Pages-tab click after Quick Open cancellation and the
scrollable Inspector's snapping checkbox. The exact affected selectors passed
locally 2/2 after retaining the selected-tab assertion and revealing the real
Inspector controls before clicking. The workflow now allows 90 minutes of
bounded runner headroom without lengthening XCTest waits or shrinking the
production window. The resulting hosted failure is detailed below.

Second hosted correction: Actions run `36674126611` completed the full UI
target with 78/81 passes and 504/504 non-UI passes. The retained artifact
showed the Dock covering the final Inspector checkbox at the 1100-point
minimum window on a 1024×768 display, an AX readiness query exceeding five
seconds only for the 10,000-page fixture, and a typography test helper
scrolling the wrong way when its field met the Inspector bottom edge. The
Inspector now has editor-only bottom scroll clearance; the three exact
affected journeys passed locally 3/3 after bounded fixture-specific readiness
and geometry-directed reveal corrections. A new hosted run is required before
calling this checkpoint green.

Third hosted correction: Actions run `36680840818` improved to 504/504
non-UI and 80/81 UI passes. The remaining failure was the text-foreground
token journey clicking an AX-present but offscreen "New Color Token" button;
the native draft form therefore never appeared. The journey now swipes the
real Inspector scroll view according to target position, requires the button
to be hittable before clicking, and requires the draft field to appear and
be hittable. Its exact selector passed locally 1/1. The next hosted result
is pending; no green full gate is claimed.

## VERIFIED AUTHORING CHECKPOINT — 2026-10-07

The accumulated bounded slices `SF-AUTHORING-075`–`105` and
`SF-AUTHORING-107`, plus `SF-PRODUCT-UI-005/006`, are integrated. The
authoritative `./sf verify` passed all repository checks and 640 tests: 542
unit/integration plus the complete 98-journey UI target. The two inline-editor
failures from the preceding run were stale XCTest native-control proxies; the
shared helper now resolves the live NSTextView while preserving its automatic
first-responder state. Normative modules remain Partial where the evidence
notes list deferred scope. Historical “unrun” wording below is superseded by
this checkpoint.

- [x] `SF-AUTHORING-075`–`105` (excluding `106`) — verified bounded slices.
- [x] `SF-AUTHORING-107` — verified bounded clipboard slice.
- [x] `SF-PRODUCT-UI-005/006` — verified bounded product-UI slices.

## VERIFIED BOUNDED SLICES

The source-era descriptions in this section are retained as implementation
records. Their “deferred/unrun” wording is superseded by the 671-test checkpoint
above for `SF-AUTHORING-106`, `108`–`113`, and `SF-PRODUCT-UI-005/006/007`.
`SF-PLATFORM-UPDATE-001` is verified only through its fail-closed boundary and
remains owner-blocked for installation by `OD-017`.

- [ ] `SF-AUTHORING-106` Starter templates and onboarding state (`SF-0204-001`–`008`) — **SOURCE IMPLEMENTED — VERIFICATION DEFERRED** under the owner testing pause. OD-016 is implemented as Blank Site plus exactly one deterministic local Starter Site with ordinary Home/About pages, semantic Header/Main/Footer Sections, System typography, neutral editable/removable copy, responsive in-artboard geometry, no assets, explicit template provenance, and no user-visible Not Found/404 starter page. Both native launch choices use the same prevalidated clean lifecycle boundary; focused model/lifecycle/accessibility/actual-app test source is present but unrun. Additional templates, remote/licensed content, branded copy, walkthroughs, learning-task state, catalogue search/filtering, downloads, publishing, and release acceptance remain excluded. See `docs/evidence/SF-AUTHORING-106-STARTER-SITE.md`.

## READY

- [x] `SF-AUTHORING-114` Image-fit component choice property (bounded `SF-0902-001`–`008`, supporting `SF-0905-001`–`008`) — **FOCUSED SLICE COMPLETE; MODULES PARTIAL**. Plan delivered: add one stable typed enum binding for an Image definition node's canonical Fit/Fill/Stretch value; expose inherited/authored provenance and Reset through a native picker; compile definition and instance edits through the identity-gated component registry; resolve the choice into the immutable expanded graph used by canvas and static output; preserve exact history and package round-trip; and remap stable choice identities during component transfer. Focused command/history/persistence/render-resolution coverage passed 1/1. Media replacement, arbitrary user-defined enums, action/slot properties, variants, nesting, broad actual-app/accessibility matrices, and release acceptance remain deferred. See `docs/evidence/SF-AUTHORING-114-COMPONENT-IMAGE-FIT-CHOICE.md`.
- [ ] `SF-AUTHORING-115` Local-image component media property (bounded `SF-0902-001`–`008`, supporting `SF-0905-001`–`008`, `SF-0801-004/005/008`) — **DEVELOPMENT PROMPT 2 OF 10 — SOURCE IMPLEMENTED, VERIFICATION DEFERRED**. Plan delivered in source: expose an Image definition node's canonical local AssetID through one stable typed media property; let linked instances choose a project image through a native accessible picker with inherited/authored provenance and Reset Override; resolve the effective asset through the immutable component graph consumed by canvas/static output; preserve exact history, schema-v12 persistence, safe asset deletion, dependency inspection and cross-project resource/property remapping; and reject stale, cancelled, missing-asset or retargeted intent without mutation. Acceptance source covers atomic expose/set/reset, serializer and renderer projection, invalid/cancel neutrality, native Inspector accessibility, asset-use safety, and the existing real-app local-image journey. Dependencies: `SF-AUTHORING-019`, `SF-AUTHORING-111`, `SF-AUTHORING-113`, and `SF-AUTHORING-114`. Excludes remote media, responsive source sets, crop/rendition properties, arbitrary media types, action/slot properties, variants, nesting, preview/export certification and release acceptance. Test source is added but MUST NOT run before Development Prompt 10 under the owner-directed cadence. See `docs/evidence/SF-AUTHORING-115-COMPONENT-MEDIA.md`.
- [ ] `SF-AUTHORING-116` Component link action property (bounded `SF-0902-001`–`008`, supporting `SF-0905-001`–`008`) — **DEVELOPMENT PROMPT 3 OF 10 — MODEL/COMMAND/RESOLUTION SOURCE IMPLEMENTED, VERIFICATION DEFERRED**. A Button or Link definition can expose its canonical destination through one stable action identity; linked instances store a strict path-free none/page/section/external value, author/reset it through the identity-gated component registry, and resolve it into the immutable component graph. Schema-v13 persistence, exact command inverses, provenance/conflict projection, and focused source coverage are present. Native instance controls and destination transfer are subsequently source-implemented by SF-AUTHORING-117; all runtime acceptance remains deferred. Slots, arbitrary event graphs, animations, remote actions, nesting, preview/export certification and release acceptance remain deferred. Tests/builds are intentionally unrun until Prompt 10. See `docs/evidence/SF-AUTHORING-116-COMPONENT-ACTION.md`.
- [ ] `SF-AUTHORING-117` Native component action controls and destination transfer (`SF-0902-001`–`008`, `SF-0905-001`–`008`; supporting `SF-0308-003/004/005/008`, `SF-0806-002/003/004/006`, `SF-1201-003/004`, `SF-1203-003/004`) — **DEVELOPMENT PROMPT 4 OF 10 — SOURCE IMPLEMENTED, VERIFICATION DEFERRED**. Captured-identity native drafts, Apply/Cancel/Reset/provenance/conflict recovery, exact binding/history guards, dependency/page handling, explicit clipboard mapping/equivalence/rejection and immutable Link Preview/output integration are source-complete. Nine new selectors are written and unrun; the Prompt-3 selector is also pending. Dependencies/exclusions/acceptance are recorded in the Prompt-4 plan above and `docs/evidence/SF-AUTHORING-117-COMPONENT-ACTION-INTEGRATION.md`. No tests/builds/checks/automation/GitHub action, commit or push is claimed; Prompt 10 owns verification.
- [ ] `SF-AUTHORING-118` Named component slots and default fallback (`SF-0902-001`–`008`, `SF-0903-001`–`008`, `SF-0905-001`–`008`; supporting `SF-0304-001/003/005`, `SF-0308-003/004/005/008`, `SF-1201-003`, `SF-1203-003`) — **DEVELOPMENT PROMPT 5 OF 10 — SOURCE FALLBACK IMPLEMENTED, VERIFICATION DEFERRED; SUPPLY BLOCKED BY OD-018**. Stable definition slots reuse ordered canonical child ownership, native name/inspect/edit routes, exact metadata history, immutable projection/output, dependency/clipboard/detach handling and schema-v14 gating. Six new selectors are written and unrun. Full supplied-content ownership/cardinality/reset/conflict acceptance is not implemented pending the documented owner decision. Dependencies/acceptance/exclusions are in the Prompt-5 plan and `docs/evidence/SF-AUTHORING-118-COMPONENT-SLOT-FALLBACK.md`. No tests/builds/checks/automation/GitHub operations, commit or push occurred.
- [ ] `SF-AUTHORING-119` Component-property grouping and ordering (`SF-0902-001`–`008`, `SF-0905-003/004/005/006`; supporting `SF-0308-003/004/005/008`, `SF-1201-003`, `SF-1203-003`) — **DEVELOPMENT PROMPT 6 OF 10 — SOURCE IMPLEMENTED, VERIFICATION DEFERRED**. Definition-owned stable typed references and flat group/order metadata in schema v15 reuse central atomic history, strict identity gates, native captured drafts/reset, grouped instance fields, dependency inspection, equivalence/remapping and projection/detach cleanup. Six new selectors are written and unrun. Plan/acceptance/dependencies/exclusions are recorded above and in `docs/evidence/SF-AUTHORING-119-COMPONENT-PROPERTY-ORGANIZATION.md`. All values, overrides, child layout and slot ownership remain intact; OD-018 is unresolved. No tests/builds/checks/automation/commits/pushes/GitHub operations occurred.
- [ ] `SF-AUTHORING-120` Component override conflict recovery (`SF-0902-004/005/006/008`, `SF-0905-003/004/005/006/008`; supporting `SF-0901-004`, `SF-0308-004/008`, `SF-1201-003`, `SF-1203-003`) — **DEVELOPMENT PROMPT 7 OF 10 — SOURCE IMPLEMENTED, VERIFICATION DEFERRED**. One derived projection owns retained typed intent, native confirmation/reset-one/reset-conflicts, original definition/source reveal, dependency findings and fail-closed transfer/Preview/static output. Valid conflicts persist in schema v15 with exact history and no new recovery store. Seven new selectors are written and unrun. Retargeting/conversion are excluded pending OD-019; OD-018 remains open. Plan/dependencies/acceptance/Prompt-10 risks: `docs/evidence/SF-AUTHORING-120-COMPONENT-OVERRIDE-RECOVERY.md`. No tests/builds/checks/automation/commits/pushes/GitHub operations occurred.
- [ ] `SF-PRODUCT-UI-008` Concept-aligned visual-system correction (`SF-0201-002/003/006/007/008`, `SF-0203-006`, `SF-0205-006/007`, `SF-0206-006/007`, `SF-0407-006/007`, `SF-1505-006/007/008`, `SF-1605-002/006/007/008`) — **OWNER ADD-ON — SOURCE IMPLEMENTED, VERIFICATION DEFERRED; DOES NOT INCREMENT PROMPT CADENCE**. The Settings Appearance render anchors a single reusable semantic system: an explicit 8-point-derived rhythm, semantic row/field/status surfaces, coordinated 320-point editor panes, a 240-point Settings sidebar with bounded detail width, restrained tab chrome, and canonical launch composition. Launch, shell, canvas, pane, Inspector and Settings consumers retain native materials, light/dark resolution, opaque accessibility fallbacks, single-row navigation, and existing canonical geometry. Follow-up migration applies shared native groups to every Inspector/Settings destination, shared selection/hover/inactive rows to Pages/Layers/Assets/Components/tabs, semantic spacing/field/validation roles to remaining chrome, and a read-only inherited Accessibility Settings page. Every concept image was reviewed; the evidence contains the complete production-surface matrix. New Settings-sidebar and inherited-preference test source plus existing material/navigation source assertions remain unrun; the full Prompt-10 matrix owns original-resolution visual review. No reference screenshots or recording are committed. See `docs/evidence/SF-PRODUCT-UI-008-CONCEPT-CONVERGENCE.md`.

- [ ] `SF-AUTHORING-108` Canvas focus/isolation/presentation modes (`SF-0409-001`–`008`) — **SOURCE IMPLEMENTED — VERIFICATION DEFERRED** under the owner testing pause. One strict canonical isolation-root marker and identity-gated atomic command project only its stable subtree through the existing immutable renderer/selection/hit-test/Layers/accessibility scene. Native breadcrumb exits restore valid selection/viewport/pane context; Focus and Presentation-over-Preview are scene-local. Focused test source is present but unrun. Excludes native full-screen ownership, multi-window synchronization, component-definition changes, comparison panes, remote Preview, output/export parity, collaboration, broad OS accessibility/performance matrices, and release acceptance. See `docs/evidence/SF-AUTHORING-108-CANVAS-MODES.md`.
- [ ] `SF-AUTHORING-109` Positioning plus reusable/state style foundation (`SF-0504-001`–`008`, `SF-0510-001`–`008`, `SF-0511-001`–`008`) — **SOURCE IMPLEMENTED — VERIFICATION DEFERRED** under the owner testing pause. One closed canonical positioning vocabulary, stable reusable definitions/references, bounded hover/focus/pressed/disabled variants, indexed resolution, identity-gated exact-inverse transactions, immutable canvas/static-output adoption, native Inspector controls, scene-local forced preview, and redacted diagnostics are source-connected. Focused model/history/persistence/renderer/output/accessibility/actual-app test source is present; parser-only syntax inspection passed, but runtime execution remains deferred. Excludes arbitrary CSS/selectors, visited/custom states, transitions/animation authoring, remote style libraries, responsive style overrides, scripting, broad browser/output matrices, and release acceptance. See `docs/evidence/SF-AUTHORING-109-POSITIONING-REUSABLE-STATES.md`.
- [x] `SF-PRODUCT-UI-007` Whole-app visual convergence (bounded `SF-0201-002/003/006/008`, `SF-0203-006/008`, `SF-1505-006`–`008`, `SF-1605-002/006`–`008`) — **DONE (BOUNDED)**. Plan delivered: use the owner-selected Settings Appearance render as the primary direction; share cohesive gray-blue chrome and an 8-point-derived spacing/card/type system across launch, shell, and Settings; balance navigator/Inspector at the same ideal/range widths; keep destinations on one row with constrained scroll/overflow; establish a dynamic pasteboard/grid/artboard hierarchy; replace the authored-looking centered blank card with the explicit compact “Your canvas is empty” message plus Frame/Text actions; and preserve canonical geometry. Original-resolution normal/selected/minimum/dark/light/Reduce-Transparency screenshots and the final blank reference were reviewed. Focused keyboard, responsive, structural-layout, Form accessibility, and native-tab regressions pass. The final documentation-inclusive `./sf verify` passed 567 unit/integration tests plus 104 actual-app UI journeys (671 total, zero failures). No commit, push, or hosted result is claimed. See `docs/evidence/SF-PRODUCT-UI-007-VISUAL-CONVERGENCE.md`.
- [ ] `SF-PLATFORM-UPDATE-001` Safe application-update foundation (`SF-1507-001`–`008`) — **SOURCE IMPLEMENTED — VERIFICATION AND OWNER SIGNING DECISION DEFERRED**. Plan delivered: isolate public HTTPS release metadata behind a typed service; model stable/preview channels, version ordering, cancellation, stale-request rejection, recovery states, redacted diagnostics, and a native Settings > Updates surface; then keep the installation boundary fail-closed behind explicit signature, integrity, bundle, channel, rollback, compatibility, and owner-policy validation. The integrated universal build passed and focused test source is present but unrun. `OD-017` blocks signed feed/installer enablement, so no feed URL, automatic network schedule, artifact download, install, relaunch, or rollback is enabled or claimed. See `docs/evidence/SF-PLATFORM-UPDATE-001-SAFE-UPDATES.md` and `ADR-0019`.
- [ ] `SF-AUTHORING-110` Closed static CSS/asset build diagnostics (`SF-1204-001`–`008`, `SF-1206-001`–`008`, `SF-1208-001`–`008`, `SF-1211-001`–`008`) — **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**. The existing immutable multi-page HTML/CSS plan now feeds versioned scene-local Development and Static Release profiles, referenced-only content-addressed image export, deterministic text/binary integrity, and a contained sibling-staged writer at an explicit user destination. One typed redacted compatibility model drives the native Build Diagnostics sheet with profile, preflight/build/cancel, copyable summary, and safe object navigation. Request/revision guards reject stale work; closed findings cover missing/corrupt/unsupported assets and policy-blocked form submission without paths or content. Parser checks and one universal arm64/x86_64 app build passed. Focused model and actual-app test source is present but unrun; the full gate is deferred. Publishing, domains, uploads, remote services, arbitrary code/CSS/JS, credentials, signing, CDN, browser certification, and release acceptance remain excluded. See `docs/evidence/SF-AUTHORING-110-STATIC-BUILD-DIAGNOSTICS.md`.
- [ ] `SF-AUTHORING-111` Transactional cross-project component-definition transfer (`SF-0308-001`–`008`, bounded `SF-0901-001`–`008`, `SF-0902-001`–`008`, applicable `SF-0905`) — **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**. Clipboard envelope v2 now captures the complete currently supported definition graph plus image/resource, color-token, reusable-style, exposed text, and visibility dependencies; rejects malformed/cyclic/dangling/oversized or unsupported graphs; reuses only deterministic structural equivalents; remaps imported stable page/node/property/binding identities and conflict names; and commits definition/dependency plus instance insertion as one existing atomic batch and exact inverse. A native accessible preflight discloses imported/reused/renamed definitions before mutation; cancel and stale confirmation remain neutral. Parser/static checks and one universal arm64/x86_64 app build passed. Focused model and actual-app test source is present but unrun; the full gate is deferred. Nested component definitions remain invalid in the current canonical model. Page/site transfer, foreign formats, remote libraries, marketplace/connected clipboards, collaboration, future slots/variants/media/enum/action properties, plugin payloads, performance/accessibility matrices, and release acceptance remain excluded. See `docs/evidence/SF-AUTHORING-111-COMPONENT-TRANSFER.md`.
- [ ] `SF-AUTHORING-112` Local component organization and dependency inspection (bounded `SF-0205-002/003/004/006/007/008`, `SF-0901-003`–`008`, `SF-0902-002/004/006`, inspection-only `SF-0907-003/004/006/007/008`) — **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**. The Components pane now has scene-local All/In Use/Unused/Issues filters and Project Order/Name/Most Used sorting over one cancellable immutable document/revision index. Native Component Details reports stable Where Used locations, direct/transitive definitions, assets, tokens, reusable styles, exposed properties, dependents and typed issues; Where Used navigates without history mutation and hidden instances never create canvas ghosts. Safe predicates expose unused removal or the existing atomic detach-and-delete path, while compatible replacement remains truthfully unavailable. Transfer readiness reuses SF-AUTHORING-111 and static-output readiness points to SF-AUTHORING-110 Build Diagnostics. Parser checks and the universal arm64/x86_64 app build pass. Two model tests and one actual-app journey were added but not run; XCTest and the full gate remain prohibited. Persistent component metadata, authored documentation/examples, replacement semantics, nesting, slots, variants, remote libraries and release acceptance remain deferred. See `docs/evidence/SF-AUTHORING-112-COMPONENT-DEPENDENCIES.md`.
- [ ] `SF-AUTHORING-113` Stable component overrides, reset, and definition-update reconciliation (bounded `SF-0905-001`–`008`, supporting `SF-0901-003`–`008`, `SF-0902-002`–`008`, `SF-1204-004/006/008`) — **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**. One bounded immutable projection now derives versioned stable paths and inherited/authored/conflict provenance from the existing canonical definition, source-node, typed-property, instance and stable property identities without a second store. Definition binding removal preserves authored instance intent as an explicit resettable conflict; stable-ID retargeting remains rejected. The identity-gated component registry adds reset-all visibility and reset-all component operations with exact existing-command inverses. Native Inspector recovery, dependency counts, strict all-or-nothing transfer mapping, and redacted fail-closed static-output findings share the same model. Swift parser inspection and one universal arm64/x86_64 app build passed. Focused model/output/actual-app test source is present but unrun; XCTest and the full gate remain prohibited. Text and Boolean visibility are the bounded property types; media/enum/action/style properties, slots, variants, nesting, remote libraries, collaboration, runtime mutation, broad certification and release acceptance remain excluded. See `docs/evidence/SF-AUTHORING-113-COMPONENT-OVERRIDES.md`.

## HISTORICAL SOURCE-BATCH RECORD

- [ ] `SF-AUTHORING-105` Authorized recent projects on the native launch surface (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0201-002/003/004/006`, `SF-0204-002/003/004/006`, supporting `SF-1504-001/003/004/006`). Plan delivered in source: persist only a versioned bounded display-name plus the existing SHA-256 bookmark lookup key; record successful user-authorized Open; resolve and refresh through the existing security-scoped file-access owner; reopen through the normal lifecycle; retain missing authorization with Locate recovery; and let users remove recency without revoking access. Focused file-access/controller/actual-app test source is added but unrun. Raw paths, duplicate bookmark bytes, cloud recents, telemetry, predictive ranking, workspace restoration, and multi-window behavior remain excluded. See `docs/evidence/SF-AUTHORING-105-RECENT-PROJECTS.md`.

- [ ] `SF-AUTHORING-107` Transactional clipboard and bounded cross-project transfer (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; `SF-0308-001`–`008`). Plan delivered in source: one closed versioned native-pasteboard envelope captures only selected subtree/dependency closure; Copy validates before replacing clipboard content; Cut mutates only after a successful clipboard write; Paste/Paste in Place/Duplicate remap stable node/property/asset/resource/token/form-option/fluid identities and compile through one existing atomic command/inverse; same-content image/token dependencies deduplicate; cross-project components reject truthfully rather than creating a partial graph; menus/contextual actions/text-responder routing, selection adoption, bounded redacted diagnostics, unit/integration/security/history and actual-app test source are connected. New tests are unrun. Cross-project component-definition closure, page clipboard transfer, arbitrary foreign HTML/images, connected clipboards, collaboration, release-scale matrices, and release acceptance remain excluded. See `docs/evidence/SF-AUTHORING-107-CLIPBOARD-TRANSFER.md`.

- [ ] `SF-PRODUCT-UI-006` Reconcile launch identity and essential authoring toolbar hierarchy (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0201-006/009` and `SF-0203-003/006`). Plan delivered in source: replace the generic launch glyph with the approved packaged application icon; tighten the welcome hierarchy around visible New Site/Open Project actions and local/privacy/recovery assurances; keep Select, Frame, Text, Image, and Component persistently visible in the native toolbar; and place Section, Stack, Grid, Button, Link, and Form in one adjacent accessible More Tools menu while retaining the established Insert menu and keyboard commands. Tool selection remains scene-local and every insertion still uses the existing typed registry. Focused policy and actual-app test source is updated but unrun. Recent-project persistence, template gallery, toolbar customization, shortcut rebinding, focus mode, multi-window navigation, broad 200-percent/VoiceOver matrices, and release acceptance remain excluded. See `docs/evidence/SF-PRODUCT-UI-006-LAUNCH-TOOLBAR.md`.

- [ ] `SF-AUTHORING-104` Native Support settings, redacted diagnostics, and recovery/update boundaries (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0206-004/006/008`, `SF-1507-003/004/006`, `SF-1602-004/006`, `SF-1607-002/003/004/006/008`). Plan delivered in source: add one native Support settings tab with current build/channel provenance, an explicit non-installing update boundary, truthful recovery policy, and asynchronous cancellable generation of a reviewable content-free JSON support report. Copy and native user-selected export operate only after review; stale work is ignored, failures use closed categories, and reports exclude project data, paths, authored values, credentials, and raw identifiers. Focused model and actual-app test source is added but unrun. Network update feeds, signing/notarization, install/relaunch/rollback, crash-log collection, project-content attachment, plugin health, retention editing, remote support upload, publishing, and release acceptance remain excluded. See `docs/evidence/SF-AUTHORING-104-SUPPORT-DIAGNOSTICS.md`.

- [ ] `SF-AUTHORING-103` Isolated local Preview navigation (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-1102-002/003/004/006`, `SF-1201-001/002/003/004/006`, supporting `SF-1202-003/004`). Plan delivered in source: compile all website pages through the existing immutable scene resolver; project only validated stable Link targets; expose native Preview page, Back, Forward, Refresh, and Done controls; keep navigation/history scene-local; retain missing targets with repair status; and share artboard geometry with canvas preparation. Focused state/compiler/actual-app test source is added but unrun. Generic action graphs, Button actions, authored hover/focus/pressed states, downloads/prefetch, external-browser execution, runtime data, generated JavaScript, broad browser/output parity, performance/accessibility matrices, publishing, and release acceptance remain excluded. See `docs/evidence/SF-AUTHORING-103-PREVIEW-NAVIGATION.md`.

- [ ] `SF-AUTHORING-102` Fluid responsive values (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0604-001`–`SF-0604-006`, `SF-0604-008`, supporting `SF-0601-003`, `SF-0602-003/004/006`). Plan delivered in source: one versioned `responsive.fluid.v1.<target>` property with stable FluidValueID owns a monotonic linear minimum/preferred/maximum clamp at the product Mobile/Tablet/Desktop widths. Width, height, Text/Button/Link font size and line height, and Section/Stack/Grid padding/gap resolve through the existing responsive/layout/typography paths; explicit Tablet/Mobile literals remain higher precedence. A native Layout Inspector surface keeps drafts scene-local, reports mixed/inapplicable state, commits one identity-gated transaction, and removes the property to restore the fixed value. Breakpoint comparison, immutable canvas preparation, and closed static CSS consume the same model. Focused codec/registry/history/persistence/resolver/output and actual-app test source is added but unrun. Custom viewport anchors/curves, non-monotonic interpolation, tokens, tracking, fluid X/Y, columns, responsive style/content/assets/components, container queries, simultaneous preview graphs, broad output/browser parity, performance/accessibility matrices, and release acceptance remain excluded. See `docs/evidence/SF-AUTHORING-102-FLUID-VALUES.md`.

- [ ] `SF-AUTHORING-101` Responsive breakpoint comparison (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0601-003/006`, `SF-0602-002/003/004/006/008`, `SF-0603-002/003/006`). Plan delivered in source: the viewport and View menu expose a native Compare Breakpoints sheet that reads the existing Desktop/Tablet/Mobile geometry, container-layout, and visibility resolvers for either the ordered selection or the active page. Cards show visible counts, exact override categories, Desktop differences, primary resolved frame, and inherited/authored provenance; Review switches only scene-local viewport preset and cannot mutate the document or history. Focused pure-policy and actual-app test source is added but unrun. Custom breakpoints, simultaneous canvases, orientation/safe areas, fluid values, container queries, responsive style/content/assets/components, broad preview/export parity, and release acceptance remain excluded. See `docs/evidence/SF-AUTHORING-101-RESPONSIVE-COMPARISON.md`.

- [ ] `SF-AUTHORING-100` Component definition rename and linked-name propagation (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0901-001/002/003/004/005/006`, supporting `SF-0902-002/005/006`). Plan delivered in source: every local definition row exposes a native Rename sheet with scene-local draft, Return/Apply, Escape/Cancel, validation, and accessible status. One identity-gated component transaction renames the stable definition and every linked instance display name without changing PageID, NodeID, overrides, geometry, or child data; duplicate/empty/stale/cancelled edits remain neutral and exact Undo/Redo/package round-trip restore the graph. Focused model and actual-app test source is added but unrun. Slots, variants, nested components, media/enum/action properties, arbitrary style overrides, bulk instance editing, remote libraries, cross-project marketplaces, browser runtime, and release acceptance remain excluded. See `docs/evidence/SF-AUTHORING-100-COMPONENT-RENAME.md`.

- [ ] `SF-AUTHORING-099` Semantic Heading element template (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0405-001/002/004/005/006`, `SF-0507-001/002`, `SF-1203-002/003/004/006`). Plan delivered in source: Heading is a visible Basic Elements row and native Insert action that creates one existing Text node with deterministic 360×48 geometry, default text, bold 32/38 typography, and authored `<h2>` semantic intent through the established insertion transaction. Content, Typography, semantic role, selection, history, persistence, accessibility, canvas, and safe static output remain on their existing canonical paths; no Heading node kind or duplicate renderer exists. Focused model and actual-app test source is added but unrun. Heading-level outline auditing, automatic hierarchy selection, rich-text spans, responsive typography, preview/export parity, broad accessibility certification, and release acceptance remain excluded. See `docs/evidence/SF-AUTHORING-099-HEADING-TEMPLATE.md`.

- [ ] `SF-AUTHORING-098` General authored accessibility metadata (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0701-002/004/006`, `SF-0702-002/004/005/006`, `SF-1203-002/003/004/005/006`). Plan delivered in source: applicable Frame, Text, Section, Stack, Grid, Button, and Link selections expose native Accessible name and Description fields with defaulted/authored/mixed provenance, Return/focus-loss commit, Escape cancellation, Reset, identity-gated atomic history, stable property identity, package round-trip, canvas accessibility projection, and escaped semantic static attributes. Semantic role remains derived from the existing typed HTML element. Image alt text and Form accessibility retain their dedicated schemas, so no second source of truth is introduced. Focused model/output/actual-app test source is added but unrun. ARIA relationship editing, landmarks beyond the existing semantic-element vocabulary, live regions, tab-order authoring, broad assistive-technology certification, localization, preview/export parity, and release acceptance remain excluded. See `docs/evidence/SF-AUTHORING-098-GENERAL-ACCESSIBILITY.md`.

- [ ] `SF-AUTHORING-097` Directional canvas marquee selection (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0402-002/003/004/006/008`). Plan delivered in source: blank-canvas pointer drags use the existing immutable selection scene and central registry; left-to-right contains visible clipped object geometry, right-to-left intersects it, and Shift/Command preserve additive/toggle semantics in stable paint order. The AppKit overlay is editor-only, Escape/cancellation and stale identity preserve the last valid selection, and committed selection remains shared by canvas, Layers, Inspector, status, and accessibility. Focused model and actual-app test source is added but unrun. Component drill-in, selection persistence, alternate lasso shapes, touch gestures, release-scale performance, and OS-level assistive-technology acceptance remain excluded. See `docs/evidence/SF-AUTHORING-097-MARQUEE-SELECTION.md`.

- [ ] `SF-AUTHORING-096` Form authoring accessibility and validation completion (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0701-002/004/006`, `SF-0702-002/004/006`, `SF-0705-002/004/006`, `SF-1006-002/003/004/006`). Delivered source plan: Content and Accessibility share a read-only canonical field projection with exact defaulted/authored/mixed provenance; mixed drafts never borrow the primary value; form-level accessibility reports configuration and safe-submit status and exposes the established scene-local category-only validator. All writes remain in the SF-AUTHORING-036 registry. Model/UI test source is added but unrun. Connected destinations, visitor-data persistence, consent/anti-abuse, broad assistive-technology certification, and release acceptance remain excluded. See `docs/evidence/SF-AUTHORING-096-FORM-ACCESSIBILITY-VALIDATION.md`.
- [ ] `SF-AUTHORING-091` Form Email field template (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0405-001/002/004/005/006`, `SF-1006-001/002/004/005/006`, `SF-1202-002/004`). Email is a Form-only 240×36 Text-backed field with canonical `email` metadata, native Elements/Insert parity, exact history, Content Inspector editing, and safe labeled output. Shared test source is unrun. See `docs/evidence/SF-AUTHORING-091-FORM-EMAIL-TEMPLATE.md`.
- [ ] `SF-AUTHORING-092` Form Text Area template (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; same bounded requirements as 091). Text Area uses the shared field command, deterministic 240×100 geometry, canonical `textarea` metadata, Inspector integration, and escaped semantic output. Shared test source is unrun. See `docs/evidence/SF-AUTHORING-092-FORM-TEXT-AREA-TEMPLATE.md`.
- [ ] `SF-AUTHORING-093` Form Checkbox template (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; same bounded requirements as 091). Checkbox uses stable Text/form-field identity and 240×28 geometry; no visitor checked value enters the project. Shared test source is unrun. See `docs/evidence/SF-AUTHORING-093-FORM-CHECKBOX-TEMPLATE.md`.
- [ ] `SF-AUTHORING-094` Form Select template (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; same bounded requirements as 091). Select seeds two ordered options whose IDs deterministically derive from the field NodeID, round-trips through the canonical encoder, and remains editable in Content Inspector. Shared test source is unrun. See `docs/evidence/SF-AUTHORING-094-FORM-SELECT-TEMPLATE.md`.
- [ ] `SF-AUTHORING-095` Form Submit template (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; same bounded requirements as 091). Submit uses the same Form-only insertion path; safe static output remains explicitly disabled/unconfigured until a future approved destination exists. Shared test source is unrun. See `docs/evidence/SF-AUTHORING-095-FORM-SUBMIT-TEMPLATE.md`.
- [ ] `SF-AUTHORING-090` Form Input insertion template (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0405-001/002/004/005/006`, `SF-1006-001/002/004/005/006`). Plan delivered in source: Input is enabled in Elements and Insert only for a selected Form; one Text child with deterministic field metadata is inserted through the existing identity-gated transaction. Model/UI test source covers parent rejection, stable identity, history, Content Inspector, and rendered adoption but is unrun under the owner pause. Excludes a new node kind or submission flow. See `docs/evidence/SF-AUTHORING-090-FORM-INPUT-TEMPLATE.md`.
- [ ] `SF-AUTHORING-086` authored Divider template (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0405-001/002/004/005/006`, `SF-0506-001/002`, `SF-1203-002`). Plan delivered in source: formerly inert Divider now inserts a one-point authored Frame with no border through the existing registry, with exact geometry/identity/history. Excludes a parallel Divider node schema and advanced rule styling. See `docs/evidence/SF-AUTHORING-086-089-ELEMENT-TEMPLATES.md`.
- [ ] `SF-AUTHORING-087` semantic Header section template (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0405-001/002/004/005/006`, `SF-0501-002`, `SF-1203-002`). Plan delivered in source: Header is a real Section with deterministic size and authored semantic header element, exposed in Elements and Insert. Excludes automatic content or new responsive cascade. See the same evidence note.
- [ ] `SF-AUTHORING-088` semantic Navigation section template (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0405-001/002/004/005/006`, `SF-0501-002`, `SF-1203-002`). Plan delivered in source: Navigation is a real Section with semantic nav identity and native insertion actions. Excludes generated links or route invention. See the same evidence note.
- [ ] `SF-AUTHORING-089` semantic Footer section template (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0405-001/002/004/005/006`, `SF-0501-002`, `SF-1203-002`). Plan delivered in source: Footer is a real Section with semantic footer identity and native insertion actions. Excludes generated legal/site content. See the same evidence note.

- [ ] `SF-AUTHORING-085` Quick Open direct component instance insertion (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0205-002/003/004/006/008`, `SF-0901-002/004/005/006`, `SF-0902-002`). Plan delivered in source: each definition result has separate Reveal and Insert Instance actions. Insert revalidates PageID and live insertion parent, calls the existing component command, and dismisses only when the document revision advances. The actual-app source journey asserts two linked render objects and Undo/Redo. Excludes creating definitions, cross-project libraries, or alternate geometry rules. See `docs/evidence/SF-AUTHORING-085-QUICK-OPEN-COMPONENT-INSERT.md`; no test/build was executed under the owner pause.

- [ ] `SF-AUTHORING-084` Quick Open direct Image insertion from an asset result (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; bounded `SF-0205-002/003/004/006/008`, `SF-0405-002/004/005/006`, `SF-0801-002/003`, `SF-0802-002/004`). Plan delivered in source: each current-project asset result has separate Select and Insert actions. Insert revalidates AssetID and current insertion availability, invokes the existing Image command, and restores the prior scene asset selection if the command does not advance the document revision. The affected actual-app source journey now asserts one Image and Undo/Redo. Excludes path-based identity, background import, or a second command path. See `docs/evidence/SF-AUTHORING-084-QUICK-OPEN-IMAGE-INSERT.md`; no test/build was executed under the owner pause.

2026-10-04 gate interruption: repository checks and all 513 non-UI tests passed.
The macOS console locked during the UI target; after unlock, an exact new
Quick Open UI selector failed before test launch because XCTest timed out
enabling automation mode. The ten slices below remain unverified and are not
DONE. Resume UI acceptance and the checkpoint only after the external
automation service is available; do not begin the next two ten-slice batches
before this one is committed and pushed.

The following owner-directed half-batch is in progress. Source and test cases are added, but execution and commits are deferred by the explicit 2026-09-30 batch instruction; none is verified or DONE.

Final five slices of this ten-slice cycle are ordered below. Asset search already exists in the native Assets pane, so `SF-AUTHORING-081` adds the missing used/unused discovery filter instead of duplicating that field. Source/test additions precede the single owner-authorized full local gate.

- [ ] `SF-AUTHORING-079` Quick Open New Page (SOURCE IMPLEMENTED, UNVERIFIED; bounded `SF-0205-002/003/004/006/008`, `SF-0303-002/004/005/006`). Plan: expose the existing native New Page editor as a named action with live page availability, preserving its draft/transaction/cancel path. Source and test are written; execution deferred. Excludes automatic route invention beyond the established page editor.
- [ ] `SF-AUTHORING-080` Components navigator search (SOURCE IMPLEMENTED, UNVERIFIED; bounded `SF-0205-002/003/004/006/008`, `SF-0901-002/003/006`). Plan: filter canonical component definitions by displayed name with stable PageIDs/order, native clear/no-results/keyboard recovery, and no mutation until a row action. Source and test are written; execution deferred. Excludes cross-project component indexing.
- [ ] `SF-AUTHORING-081` Assets used/unused filter (SOURCE IMPLEMENTED, UNVERIFIED; bounded `SF-0205-003/004/006/008`, `SF-0801-002/003/006`). Plan: compose an All/Used/Unused native picker with existing Assets search/folder/tag/favorite projection using live usage counts; preserve AssetIDs and selected asset. Source and test are written; execution deferred. Excludes automatic deletion or canonical usage metadata.
- [ ] `SF-AUTHORING-082` Quick Open image-asset results (SOURCE IMPLEMENTED, UNVERIFIED; bounded `SF-0205-002/003/004/006/008`, `SF-0801-002/003/006`, `SF-0802-002/006`). Plan: project only current-document assets by name/filename and stable AssetID; opening selects the real asset and reveals Assets, leaving insertion explicit. Source and test are written; execution deferred. Excludes cross-project indexing or path-based identity.
- [ ] `SF-AUTHORING-083` Quick Open component-definition results (SOURCE IMPLEMENTED, UNVERIFIED; bounded `SF-0205-002/003/004/006/008`, `SF-0901-002/003/006`, `SF-0902-002/006`). Plan: project available current-document definitions by stable PageID/name; opening reveals the definition in Components with an explicit Insert action, preserving canonical authoring validation. Source and test are written; execution deferred. Excludes automatic instance creation from search or cross-project libraries.

- [ ] `SF-PRODUCT-UI-005` Package owner-approved v2 gradient SF icon (SOURCE IMPLEMENTED — VERIFICATION DEFERRED; `SF-0201-009`). Plan: bind the exact owner-supplied bytes at `docs/design-assets/siteforge-app-icon-sf-gradient-approved-v2.png`, remove only the edge-connected exterior white matte, deterministically produce every macOS AppIcon size, and use the packaged icon for native launch/welcome/About identity. The exact source digest, ten RGBA renditions, exterior alpha, preserved enclosed white SF pixels, catalog membership, and Debug/Release selection pass the allowed static checker. Runtime AppMetadata and fresh launch/About/Finder/Dock inspection remain deferred by the owner testing pause. Excludes artwork reinterpretation, project/export content, signing, notarization, publication, and release.
- [ ] `SF-AUTHORING-075` Quick Open Frame/Text insertion (SOURCE IMPLEMENTED, UNVERIFIED; bounded `SF-0205-002/003/004/006/008`, `SF-0405-002/004/005/006`). Plan: expose two named insertion actions in the existing Actions scope, validate live availability, and call `performDefaultInsertion` once; add projection and actual-app test source. The source and tests are written but unrun. Excludes a second command path and cross-project search.
- [ ] `SF-AUTHORING-076` Quick Open structural insertion (SOURCE IMPLEMENTED, UNVERIFIED; bounded `SF-0205-002/003/004/006/008`, `SF-0405-002/004/005/006`, `SF-0502-002`, `SF-0503-002`). Plan: add Section, Stack, and Grid to that closed action projection, reusing their canonical default insertion and active-parent validation. The source and tests are written but unrun. Excludes new layout defaults or responsive rules.
- [ ] `SF-AUTHORING-077` Quick Open site-control insertion (SOURCE IMPLEMENTED, UNVERIFIED; bounded `SF-0205-002/003/004/006/008`, `SF-0405-002/004/005/006`). Plan: add Button, Link, and Form actions, preserve disabled/invalid neutrality, and add focused source assertions. The source and tests are written but unrun. Excludes control behavior editing and publishing.
- [ ] `SF-AUTHORING-078` Quick Open image actions (SOURCE IMPLEMENTED, UNVERIFIED; bounded `SF-0205-002/003/004/006/008`, `SF-0405-002/004/005/006`, `SF-0801-002`, `SF-0802-002`). Plan: expose selected-asset insertion only when an asset is selected and native Import and Insert through the existing file-panel path; cancellation remains neutral. The source and tests are written but unrun. Excludes asset management or image-style changes.

## BATCH ACCEPTED — LOCAL CHECKPOINT

- [x] `SF-AUTHORING-074` Quick Open explicit result scopes (P1; batch slice 10 of 10).
  - Requirements: bounded `SF-0205-003/004/006/008`, supporting existing page/Layers/View actions. `SF-0205` remains Partial.
  - Dependencies: SF-AUTHORING-070/071/072/073 unified Quick Open results and existing stable target identity. No project schema or owner decision is required for an editor-only query scope.
  - Plan: add a native All/Pages/Layers/Actions scope control that filters the same current-document authorized projections, including recents; keep deterministic order and Return/Cancel behavior, empty recovery, accessibility labels, and no canonical mutation. Add focused policy/actual-app coverage. This is the tenth batch slice; afterward run the authoritative full gate, repair failures, inspect screenshots, reconcile all evidence, and commit/push only if clean.
  - Exclusions: persisted query objects, cross-project search, fuzzy ranking, arbitrary/destructive command execution, and release acceptance.
  - Status: policy and actual-app selectors passed in the batch. Original-resolution Actions/Layers scopes were visually reviewed. The one full gate recorded 504/504 unit/integration and 79/81 UI passes; the two failed UI tests passed exact focused reruns after test-contract corrections. No second full-gate pass is claimed. See `docs/evidence/SF-AUTHORING-074-QUICK-OPEN-SCOPES.md`.

## BATCH ACCEPTED — LOCAL CHECKPOINT

- [x] `SF-AUTHORING-073` Quick Open recent current-page layers (P1; batch slice 9 of 10).
  - Requirements: bounded `SF-0205-003/004/006/008` and existing `SF-0402-002/006` Layers selection. `SF-0205` remains Partial.
  - Dependencies: SF-AUTHORING-072 bounded recency and SF-AUTHORING-067 authorized layer targets. No project schema or owner decision is required for scene-local NodeID visits.
  - Plan: record only successful Layers selection of stable NodeIDs, bound/deduplicate by document identity, show available current-page recent layers ahead of broad results for an empty query, and open through selectLayer. Add focused policy/UI test source without executing it before the tenth-slice gate.
  - Exclusions: hidden/unavailable target exposure, persistent visit history, cross-page/project recents, predictive ranking, telemetry, and release acceptance.
  - Status: bounded current-document NodeID recency passed model and actual-app selectors in the batch; the recent-Layers screenshot was inspected at original resolution. See `docs/evidence/SF-AUTHORING-073-RECENT-LAYERS.md`.

## BATCH ACCEPTED — LOCAL CHECKPOINT

- [x] `SF-AUTHORING-072` Quick Open recent pages (P1; batch slice 8 of 10).
  - Requirements: bounded `SF-0205-003/004/006/008` and existing `SF-0303-002/006` page navigation. `SF-0205` remains Partial.
  - Dependencies: SF-AUTHORING-070 Quick Open and stable PageID selection. No project schema or owner decision is required for bounded scene-local recency.
  - Plan: remember only explicit page navigation in a bounded, deduplicated scene list tied to the current document identity; show recent pages ahead of broad results for an empty Quick Open query; revalidate IDs against current pages and open through selectPage. Add focused policy/UI coverage without executing tests until the batch gate.
  - Exclusions: persistent usage history, cross-project recents, predictive ranking, telemetry, cloud sync, and release acceptance.
  - Status: bounded, deduplicated, document-identity-scoped page recency passed model and actual-app selectors in the batch; the recent-pages screenshot was inspected. See `docs/evidence/SF-AUTHORING-072-RECENT-PAGES.md`.

## BATCH ACCEPTED — LOCAL CHECKPOINT

- [x] `SF-AUTHORING-071` Quick Open View actions (P1; batch slice 7 of 10).
  - Requirements: bounded `SF-0205-002/003/004/006/008`; supporting existing `SF-0407-002/006` viewport commands. `SF-0205` remains Partial.
  - Dependencies: SF-AUTHORING-070 native Quick Open and established scene-local View actions; no new document command or project schema is needed.
  - Plan: expose a closed list of existing Fit Document, Actual Size, and Grid actions in Quick Open with stable names and deterministic query order. Route activation through the same viewport/grid state methods as the View menu, with no authored content mutation; add focused policy and actual-app coverage without executing individual-slice tests until the batch gate.
  - Exclusions: arbitrary commands, file/network/destructive actions, saved recents, fuzzy ranking, external integrations, and release acceptance.
  - Status: closed native View-action list passed model and actual-app selectors in the batch; the Actions screenshot was inspected. See `docs/evidence/SF-AUTHORING-071-QUICK-OPEN-ACTIONS.md`.

## BATCH ACCEPTED — LOCAL CHECKPOINT

- [x] `SF-AUTHORING-070` Native Quick Open for pages and current-page layers (P1; batch slice 6 of 10).
  - Requirements: bounded `SF-0205-002/003/004/006/008`, supporting existing `SF-0303-002/006` page and `SF-0402-002/006` Layers navigation. `SF-0205` remains Partial.
  - Dependencies: SF-AUTHORING-066/067 local search projections and deterministic active-window command target ownership. No new project schema is needed for an editor-only command surface.
  - Plan: expose a native View-menu/keyboard Quick Open command and visible navigator entry; search current-document pages followed by current-page authorized layers, preserve stable IDs/order, and dispatch activation only through existing selectPage/selectLayer paths. Provide empty/cancel/keyboard recovery; add focused policy and actual-app test source without executing individual-slice tests until the batch gate.
  - Exclusions: cross-project indexing, arbitrary command execution, saved recents, fuzzy ranking, hidden/unavailable nodes, remote search, and release acceptance.
  - Status: native Quick Open and deterministic page/current-Layers projection passed model and actual-app selectors in the batch; original-resolution sheet states were inspected. See `docs/evidence/SF-AUTHORING-070-QUICK-OPEN.md`.

## BATCH ACCEPTED — LOCAL CHECKPOINT

- [x] `SF-AUTHORING-069` Layers object-type filter (P1; batch slice 5 of 10).
  - Requirements: bounded `SF-0205-003/004/006/008`, supporting existing `SF-0402-002/006` Layers selection. `SF-0205` remains Partial.
  - Dependencies: `SF-AUTHORING-067` authorized Layers search projection and stable canonical `NodeKind` values. No new project schema or owner choice is required for a scene-local filter.
  - Plan: add a native type picker to Layers, compose it with name search over the same authorized target list, preserve paint order/NodeID/selection, expose count and reset/no-result states, and add focused policy/UI coverage. Do not execute individual-slice tests under the current batch policy.
  - Exclusions: persisted filters, cross-page search, hidden target exposure, fuzzy ranking, command palette, and release acceptance.
  - Status: model selector passed in the batch. The UI journey passed on exact focused rerun after scoping its native picker item and correcting the fixture count for the structural Root; filtered/restored screenshots were inspected. See `docs/evidence/SF-AUTHORING-069-LAYERS-TYPE-FILTER.md`.

## BATCH ACCEPTED — LOCAL CHECKPOINT

- [x] `SF-AUTHORING-068` Native Elements catalogue search (P1; batch slice 4 of 10).
  - Requirements: bounded `SF-0205-002/003/004/006/008`, supporting existing `SF-0405-002/006` insertion availability. `SF-0205` remains Partial.
  - Dependencies: stable `ElementCatalogItem` identities, native Elements catalogue rows, and established insertion-command routing. No project schema or owner decision is needed for a local discovery query.
  - Plan: add a native scene-local catalogue field that filters stable title/category metadata without changing canonical content or the availability of unsupported items; retain category grouping and source order, expose counts/no-result/clear recovery and keyboard operation, and route activation through existing rows only. Add focused policy and actual-app coverage without executing tests until the owner-directed end-of-batch gate.
  - Exclusions: fuzzy ranking, cross-project search, saved queries, hidden insertion paths, command palette, and release acceptance.
  - Status: policy and actual-app selectors passed in the batch; filtered, unavailable, and empty-state screenshots were inspected. See `docs/evidence/SF-AUTHORING-068-ELEMENTS-SEARCH.md`.

## FOCUSED LAYERS-SEARCH CHECKPOINT — OWNER REVIEW PENDING

- [x] `SF-AUTHORING-067` Native Layers navigator node search (P1; batch slice 3 of 10).
  - Requirements: bounded `SF-0205-002/003/004/006/008` and existing `SF-0402-002/006` selection semantics. `SF-0205` remains Partial.
  - Dependencies: `SF-AUTHORING-066` scene-local Pages search, stable `SelectionTargetSnapshot` IDs/names/paint order, Layers selection command path. No project schema or owner decision is required for a scene-local layer query.
  - Plan: search the current page’s existing Layers targets by displayed name without mutating the canonical graph or selection; preserve paint order, show a readable count and no-result/reveal-selection recovery, and let Return select the first matching NodeID through the existing Layers command. Escape clears only the query. Add focused projection/identity tests and one actual-app keyboard/pointer journey, inspect screenshots, and update bounded evidence.
  - Exclusions: cross-page/project indexing, hidden/unavailable node exposure beyond the current Layers contract, fuzzy ranking, saved queries, command palette, and release acceptance.
  - Status: focused checkpoint. The new pure policy/unit and actual-app journey plus the affected existing Layers multi-selection keyboard journey passed 3/3. Three original-resolution filtered, no-result, and cleared states were reviewed. Layer search is a scene-local authorized-target projection and does not mutate the document or selection until Return explicitly selects a result. No broad gate, commit, push, or hosted result is claimed. See `docs/evidence/SF-AUTHORING-067-LAYERS-SEARCH.md`.

## FOCUSED PAGE-SEARCH CHECKPOINT — OWNER REVIEW PENDING

- [x] `SF-AUTHORING-066` Native Pages navigator search (P1; batch slice 2 of 10).
  - Requirements: bounded `SF-0205-002`, `SF-0205-003`, `SF-0205-004`, `SF-0205-006`, and `SF-0205-008`; existing page identity and navigation under `SF-0303-002/006`. `SF-0205` remains Partial.
  - Dependencies: canonical stable PageID/name/route, native Pages navigator, selection and page-opening commands. No project schema or owner product decision is required for a scene-local search query.
  - Plan: filter the current in-memory website pages by case/diacritic-insensitive name or route in canonical order; expose a native Pages search field, clear/empty-result/reveal-selected states, Return to open the first result, Escape to clear, and truthful accessibility counts. Preserve selected PageID and document revision when filtering; test current-document updates and real keyboard/pointer behavior.
  - Exclusions: cross-project search, node indexing, persisted recent queries, fuzzy ranking, command palette, remote search, and release acceptance.
  - Status: focused checkpoint. The new model and actual-app journeys plus the affected existing Pages keyboard-navigation journey passed 3/3. Three original-resolution states were reviewed: route result, no result, and cleared search. Search never changes project revision or selected PageID until an explicit open action. No post-063 full gate, commit, push, or hosted result is claimed. See `docs/evidence/SF-AUTHORING-066-PAGES-SEARCH.md`.

## FOCUSED APPLICATION SETTINGS CHECKPOINT — OWNER REVIEW PENDING

- [x] `SF-AUTHORING-065` Native application preference-group reset (P1).
  - Requirements: bounded `SF-0206-002`, `SF-0206-003`, `SF-0206-004`, `SF-0206-006`, and `SF-0206-008`. `SF-0206-001/005` project-canonical settings are not claimed.
  - Dependencies: existing application-only Appearance Settings (`SF-AUTHORING-023`) and Canvas Grid default (`SF-AUTHORING-064`); ADR-0006 keeps both outside project content. The specification names “reset a preference group” but does not select a concrete project-owned preference, so this slice resets only the two existing application defaults rather than inventing project behavior.
  - Plan: expose one native Settings group action with an explicit pending/confirm/cancel boundary; capture both exact stored records, reject managed/stale/draft states before mutation, reset both synchronously with rollback on storage failure, and offer bounded exact restoration. Refresh the existing tabs from committed storage; prove unrelated defaults and projects unchanged, keyboard/accessibility, relaunch, failure neutrality, and a real-app journey.
  - Exclusions: project-canonical settings, bulk cross-project edits, preferences not yet implemented, global settings profiles, import/export, release acceptance.
  - Status: focused local checkpoint. Five exact Canvas/Application Settings model tests passed 5/5; the fresh-process group journey and both affected existing Appearance/Canvas Settings journeys passed 3/3 (8/8 total). Five original-resolution Settings states were reviewed, including a small label refinement. Repository and traceability checks passed. No post-063 full gate, commit, push, or hosted result is claimed. Preserve all pre-existing uncommitted work. See `docs/evidence/SF-AUTHORING-065-APPLICATION-RESET.md`.

## FOCUSED LOCAL CHECKPOINT — OWNER REVIEW PENDING

- [x] `SF-AUTHORING-064` Native Canvas Settings: default world-grid visibility (P1; first post-063 user-visible slice).
  - Requirements: bounded `SF-0206-002`, `SF-0206-003`, `SF-0206-004`, `SF-0206-006`, `SF-0206-008`; supporting existing canvas presentation contract under `SF-0407-006`. The SF-0206 module remains Partial; canonical project preferences and release acceptance are outside this slice.
  - Dependencies: native Appearance Settings (`SF-AUTHORING-023`), scene-local grid toggle and world-grid policy, and the completed local SF-AUTHORING-063 checkpoint. No open owner decision blocks an application-local default.
  - Plan: add one versioned, app-local Canvas Settings record for whether the grid appears in newly created workspaces; expose a native Settings pane with draft, Apply, Cancel/Escape, Reset, provenance, and accessible status; initialize each new workspace from the committed preference while keeping the toolbar/View-menu grid toggle scene-local; prove strict decoding, stale/cancel neutrality, persistence, scene independence, and the actual-app Settings path with focused tests and retained visual evidence.
  - Exclusions: project-canonical preferences, changing already-open workspaces when the default changes, grid spacing/color controls, responsive settings, profiles, preview/export content, and release acceptance.
  - Status: focused local checkpoint. Three exact model tests and the new actual-app Settings journey passed 4/4; the existing Appearance Settings journey and grid/artboard journey passed 2/2 after explicitly selecting the relevant tab and Grid-on state. Five original-resolution Canvas Settings/workspace states were reviewed. No new full gate, commit, push, or hosted result is claimed. Preserve the existing uncommitted SF-AUTHORING-063 and SF-PRODUCT-UI-004 changes. See `docs/evidence/SF-AUTHORING-064-CANVAS-SETTINGS.md`.

## LOCAL VISUAL REVIEW — OWNER REVIEW PENDING

- [x] `SF-PRODUCT-UI-004` Original AppIcon and adaptive frosted shell (P1; owner-approved local visual slice; not a new ten-prompt counter item).
  - Requirements: `SF-0201-009`; bounded supporting `SF-0201-003`, `SF-0201-006`, `SF-1505-006`, and `SF-1605-002`/`006`.
  - Plan: package only the approved SiteForge SF artwork as a static macOS AppIcon asset catalog; configure the existing Xcode app target; refine the existing native `WorkspaceMaterialPolicy`/`workspaceChrome` boundary for legibility and non-interception, with opaque Reduce Transparency and stronger Increased Contrast treatment; inspect actual normal/minimum-window states and focused asset/material/accessibility evidence. Icon and shell remain app UI, never canonical document or exported content.
  - Exclusions: Adobe marks or copied assets, alternate branding, authored-site style changes, full-screen Space, signing, notarization, release, and publication.
  - Status: ten macOS AppIcon variants, Debug/Release asset-catalog selection, native frosted side panes, opaque Reduce Transparency fallback, and increased-contrast separators are implemented. Focused app-metadata/material tests passed 3/3 and affected actual-app journeys passed 3/3. Seven original-resolution shell states and the built icon were reviewed; the XCTest Dock capture still showed a generic icon despite correct bundle icon files/keys, so fresh Finder/Dock presentation remains to be confirmed. See `docs/evidence/SF-PRODUCT-UI-004-BRANDING-SHELL.md`. The later batch verification result is recorded above.

## LOCAL VERIFIED — OWNER REVIEW PENDING

- [x] `SF-AUTHORING-063` Native Asset Library organization foundation v1 (P1; Development Prompt 10 of 10; local gate passed, uncommitted).
  - Requirements: bounded `SF-0801-001`–`008`; supporting `SF-0305`/`SF-0306`, `SF-0701`/`SF-0702`, and `SF-1204` where existing asset uses are affected.
  - Plan: add versioned, strictly validated project-local folder/tags/favorite metadata to existing ImageAsset records without changing resource identity; route edits through revision-guarded existing asset history commands; expose native Assets search, favorite/folder/tag filters and compact editable controls; prove migration, exact history, safe existing use/deletion accounting, output neutrality, and an actual-app journey. After the feature commit, perform the reset-policy full local and hosted checkpoint.
  - Exclusions: filesystem folders, remote/cloud libraries, smart collections, bulk edits, drag reorder, media types beyond existing raster imports, image transformation, browser runtime, and release work.
  - Current evidence: optional schema-eleven organization, guarded asset history, and native pane controls are implemented; model/migration/static-reference selectors passed 4/4, the exact native import/organize/filter/undo/reopen journey passed 1/1, five original-resolution attachments were reviewed, and repository checks passed. Ten reconciled historical tests passed focused 10/10 and three affected Inspector journeys passed focused 3/3. Final post-repair `./sf verify` passed 486 unit/integration and 70 UI tests (556 total, zero failures) on 2026-09-29; see `docs/evidence/SF-AUTHORING-063-ASSET-ORGANIZATION.md`. No commit, push, hosted CI, or release claim is made.
  - Checkpoint recovery: an earlier direct macOS UI target executed 70 tests (68 passed, two failed). Both failures exposed one selection-adoption bug when Mobile clipped a selected Frame. The production correction passed one focused selection-model test and both affected native UI journeys (2/2) with reviewed Tablet/Mobile/Reveal screenshots; the final local gate then passed. See `docs/evidence/SF-RESPONSIVE-SELECTION-RECOVERY.md`.

- [x] `SF-AUTHORING-062` Component Boolean visibility-property foundation v1 (P1; Development Prompt 9 of 10; focused local checkpoint).
  - Requirements: bounded `SF-0901-001`–`008`, `SF-0902-001`–`008`, `SF-0905-001`–`008`; supporting `SF-0305`/`SF-0306`, `SF-0701`/`SF-0702`, and `SF-1204`.
  - Plan: extend existing definition-child bindings and instance override namespace with a stable typed Boolean visibility property; validate name/default/ownership and block destructive removal while overrides exist; resolve once during component expansion so renderer, Preview, output, hit testing, and accessibility share effective visibility; expose native definition/instance Inspector controls and focused model/render/UI evidence.
  - Exclusions: slots, enums, media/action props, variants, nested authoring, arbitrary style/expressions, per-breakpoint visibility properties, browser runtime, and release acceptance.
  - Evidence: four exact unit/integration selectors and one fresh-process native Inspector/reopen selector passed 5/5. Five original-resolution screenshots were reviewed: definition default, inherited-hidden, authored-visible, reset-inherited, and reopened-visible. An initial XCTest automation initialization timeout was external; the later native checkbox-value mismatch was corrected in the test without weakening state assertions. See `docs/evidence/SF-AUTHORING-062-COMPONENT-VISIBILITY.md`. Full/hosted gates remain reserved for Prompt 10.

- [x] `SF-AUTHORING-061` Native Frame/Section image-fill foundation v1 (P1; Development Prompt 8 of 10; focused local checkpoint).
  - Requirements: bounded `SF-0508-001`–`008`, `SF-0801-001`–`008`, `SF-0802-001`–`008`; supporting `SF-0305`/`SF-0306`, `SF-0701`/`SF-0702`, and `SF-1204`.
  - Plan: represent one optional stable AssetID and Fit/Fill mode in a strictly validated versioned Frame/Section property namespace; compile Inspector mutations through the existing identity-gated transaction and safe asset-deletion boundaries; resolve immutable asset snapshots into native canvas, Preview, and closed static output with documented paint order and missing-resource fallback; add focused model/render/static/actual-app evidence and update factual status.
  - Exclusions: multi-image layers, masks, blending, filters, crop/focal adjustment, remote resources, responsive sources, browser runtime, publishing, and release acceptance.
  - Evidence: exact model, 1×/2× pixel, and fresh-process native Inspector/reopen selectors passed 3/3. Four original-resolution screenshots were reviewed; the Frame image stays clipped and aligned across Fill, Fit, and reopen. Existing SwiftUI publication/QoS runtime warnings remain separately observable. See `docs/evidence/SF-AUTHORING-061-FRAME-SECTION-IMAGE-FILL.md`. Full and hosted gates remain reserved for Prompt 10.

- [x] `SF-AUTHORING-060` Native text foreground color foundation v1 (P1; Development Prompt 7 of 10; focused local checkpoint).
  - Requirements: bounded `SF-0507-001`–`008`, `SF-0508-001`–`008`, `SF-0509-001`–`008`, with `SF-0305`/`SF-0306`, `SF-0701`/`SF-0702`, and `SF-1204` integration.
  - Plan: add a strictly validated optional whole-object literal foreground for Text/Button/Link; extend the existing target-keyed local Color Token binding and typed typography transaction; resolve token → literal → automatic foreground once for native canvas, inline editor, Preview, and closed static output; expose accessible Inspector author/reset/bind controls and focused history/render/UI evidence.
  - Exclusions: rich-text spans, paragraph/background color, hover/visited states, font import/axes, token aliases/modes, arbitrary CSS, browser runtime, publishing, and release acceptance.
  - Evidence: optional whole-object RGBA and target-keyed token bindings resolve through the existing typography/color registries for Text, Button, and Link; native Design controls edit and reset foreground, while committed/live text and closed static output consume the same resolved color. Focused model and native render checks passed; the real-app Inspector/inline journey passed and four original-resolution captures were reviewed. See `docs/evidence/SF-AUTHORING-060-TEXT-FOREGROUND.md`. The prompt-ten full gate has not run.

- [ ] `SF-AUTHORING-059` Local color-token appearance bindings v1 (P1; Development Prompt 6 of 10).
  - Requirements: bounded `SF-0509-001`–`008`, `SF-0506-001`–`008`, `SF-0508-001`–`008`, with applicable `SF-0305`/`SF-0306`, `SF-0701`/`SF-0702`, and `SF-1204` integration.
  - Plan: migrate the existing fill-only binding into one typed target-keyed property namespace; extend the central token transaction and resolver to authored Border and Outer Shadow color while retaining each literal fallback; expose a compact accessible native target chooser and bind/unbind route; verify model/history/migration, renderer/Preview/static parity, and an actual-app Inspector journey.
  - Focused checkpoint: target-keyed schema-ten bindings, reversible Border/Outer Shadow edits, native target chooser, and shared canvas/Preview/closed-static resolution are implemented. Four exact model selectors (including existing Fill compatibility) and two actual-app selectors passed; three original-resolution Border/Shadow captures were visually reviewed. The tenth-prompt full gate has not run. Evidence: `docs/evidence/SF-AUTHORING-059-APPEARANCE-TOKENS.md`.
  - Exclusions: text/gradient/image/opacity bindings, token aliases or modes, remote libraries, arbitrary CSS, publishing, and release acceptance.

- [ ] `SF-AUTHORING-058` Native sizing constraints and aspect-ratio foundation v1 (P1; Development Prompt 5 of 10).
  - Requirements: bounded `SF-0505-001`–`008`, with fixed-geometry `SF-0403`, responsive base/cascade `SF-0601`/`SF-0602`, renderer `SF-0701`/`SF-0702`, and closed static `SF-1204` integration.
  - Plan: add a strictly validated canonical base-only min/max/aspect property group; resolve fixed geometry edits and pointer resize through the existing identity-gated command paths; expose scene-local native Layout Inspector drafts/reset; project safe closed static sizing declarations; add focused model, renderer/static, and actual-app tests.
  - Focused checkpoint: Frame/Image base bounds and aspect lock, native Layout controls, clamped numeric/pointer geometry, and closed static declarations are implemented. Four exact focused selectors passed; three original-resolution native window captures were reviewed. The tenth-prompt full gate has not run. Evidence: `docs/evidence/SF-AUTHORING-058-SIZING-CONSTRAINTS.md`.
  - Exclusions: responsive constraint overrides, hug/fill/intrinsic/percentage/viewport-unit sizing, container constraints, rotation/skew, arbitrary CSS, browser runtime, publishing, and release acceptance.

- [ ] `SF-AUTHORING-057` Local solid color tokens (P1; Development Prompt 4 of 10).
  - Requirements: bounded `SF-0509-001`–`008`, `SF-0302-001`–`008`, `SF-0305-001`–`008`, `SF-0306-001`–`008`, with applicable Inspector and static output requirements.
  - Plan: add stable project-local RGBA token records and strict validation to the canonical document; compile create/edit/rename/delete and solid fill binding through existing history and identity gates; resolve bound colors into the shared canvas, Preview, and static snapshots; expose a compact accessible native token and binding surface.
  - Focused checkpoint: schema-9 token records, reversible bind/unbind, native Inspector controls, and shared render/static resolution are implemented. Focused model, migration, static-output, and actual-app selectors passed; retained bound/unbound screenshots were visually inspected. The tenth-prompt full gate has not run. Evidence: `docs/evidence/SF-AUTHORING-057-LOCAL-COLOR-TOKENS.md`.
  - Exclusions: aliases, themes/modes, other token types, remote libraries, arbitrary CSS variables, browser runtime, and release acceptance.

- [ ] `SF-AUTHORING-056` Native bounded outer-shadow authoring foundation (P1; Development Prompt 3 of 10).
  - Requirements: bounded implementation/evidence for `SF-0506-001`–`008`,
    `SF-0508-001`–`005`, `SF-0701-001`–`005`, `SF-0702-001`–`005`,
    `SF-0305-001`–`005`, `SF-0306-001`–`005`, `SF-0407-003`–`005`, and
    applicable `SF-1204-003`–`004`.
  - Plan: retain the existing typed outer-shadow value and add explicit,
    reversible enabled/default/authored provenance for Frame/Section only;
    resolve it once through the Design transaction registry, native canvas,
    Local Preview, and closed static output vocabulary.
  - Exclusions: multiple, inner, inset, or layered shadows; blend/filter
    effects; arbitrary CSS; browser runtime; unsupported node kinds;
    publishing and release acceptance.
  - Evidence: focused typed-registry, closed static-output, production-tile,
    and native Inspector selectors passed 4/4 on 2026-09-27; see
    `docs/evidence/SF-AUTHORING-056-OUTER-SHADOW.md`.

- [ ] `SF-AUTHORING-055` Native spacing, border, corner-radius, and content-clipping authoring foundation (P1; Development Prompt 2 of 10).
  - Requirements: bounded implementation/evidence for `SF-0506-001`–`008`,
    `SF-0701-001`–`005`, `SF-0702-001`–`005`, `SF-0305-001`–`005`,
    `SF-0306-001`–`005`, `SF-0407-003`–`005`, and `SF-1204-003`–`004`.
  - Plan: extend the existing typed `style.box.v1` transaction and strict
    document validator with uniform Frame/Section content padding and content
    clipping; share it with resolved structural geometry, immutable canvas
    clipping, native Design controls, and closed static output projection.
  - Exclusions: independent/logical sides, margin, per-corner radius,
    corner smoothing, layered/inner shadows, arbitrary raw CSS, browser
    runtime, and release acceptance.
  - Evidence: focused model, static-output, and actual native Inspector
    selectors passed 3/3 on 2026-09-27; see
    `docs/evidence/SF-AUTHORING-055-BOX-STYLE-FOUNDATION.md`.

- [ ] `SF-AUTHORING-054` Native solid-fill and bounded linear-gradient authoring foundation (P1; Development Prompt 1 of 10).
  - Requirements: bounded implementation/evidence for `SF-0508-001`–`005`,
    `SF-0701-001`–`005`, `SF-0305-001`–`005`, `SF-0306-001`–`005`, and
    applicable `SF-1204-003`–`004` output mapping.
  - Plan: reuse the versioned typed fill-layer model, identity-gated Design
    registry, native Inspector controls, renderer compositor, persistence and
    existing UI journey; add the missing closed Frame/Section static-output
    projection with exact opaque/alpha/gradient ordering. Keep drafts
    scene-local and preserve cancellation, mixed-state, history, and
    diagnostic behavior through existing central paths.
  - Exclusions: raw CSS, arbitrary gradient syntax, image fills, browser
    runtime, remote assets, publishing, unsupported node-kind static styling,
    and release acceptance.
  - Evidence: closed Frame/Section static projection and three focused unit
    selectors passed 3/3 on 2026-09-27. The existing Inspector UI selector was
    attempted once but XCTest automation timed out before its body ran; retain
    the assertion and rerun only with a healthy macOS automation service.

- [ ] `SF-AUTHORING-053` Static authored-box parity foundation (P1).
  - Requirements: bounded compiler evidence for `SF-1204-003`–`004`.
  - Plan: retain canonical typed width/height as the static outer box through
    one fixed nonauthorable box-model declaration.
  - Exclusions: authorable CSS, layout modes, browser rendering, generated
    output files, publishing, and release acceptance.

- [ ] `SF-AUTHORING-052` Static plan-integrity foundation (P1).
  - Requirements: bounded compiler evidence for `SF-1206-003`–`004`.
  - Plan: derive a deterministic content-free digest from the exact immutable
    in-memory static plan with no additional output file or writer call.
  - Exclusions: generated integrity files, signatures, browser verification,
    resource-byte export, publishing, and release acceptance.

- [ ] `SF-AUTHORING-051` Static semantic-outline foundation (P1).
  - Requirements: bounded compiler evidence for `SF-1203-003`–`004` and
    `SF-1206-003`–`004`.
  - Plan: carry canonical parent NodeID provenance into immutable static nodes
    and expose a deterministic content-free semantic outline plan artifact.
  - Exclusions: nested browser DOM generation, arbitrary HTML/attributes,
    browser execution, file writes, source maps, publishing, and release
    acceptance.

- [ ] `SF-AUTHORING-050` Static semantic-element resolution foundation (P1).
  - Requirements: bounded compiler evidence for `SF-1203-001`–`004`.
  - Plan: share the existing typed semantic resolver between the Inspector and
    immutable static tree so authored supported roles reach safe output while
    omitted/invalid metadata retains deterministic fallback behavior.
  - Exclusions: semantic Inspector UI changes, arbitrary HTML/attributes,
    browser execution, generated-site packaging, publishing, and release
    acceptance.

- [ ] `SF-AUTHORING-049` Static asset-manifest integrity foundation (P1).
  - Requirements: bounded compiler evidence for `SF-0801-003`–`004` and
    `SF-1206-003`–`004`.
  - Plan: add an immutable, deterministic Image reference manifest to the
    existing static plan using only stable AssetID, verified content-addressed
    path, and validated dimensions.
  - Exclusions: resource-byte writes, generated-site packaging, browser
    loading, remote providers, source sets, transforms, publishing, and
    release acceptance.

- [ ] `SF-AUTHORING-048` Static Image dimension and responsive-layout parity foundation (P1).
  - Requirements: bounded compiler evidence for `SF-0802-003`–`004`,
    `SF-0601-003`, `SF-0603-003`, and `SF-1203-003`/`SF-1204-003`–`004`.
  - Plan: retain verified Image intrinsic dimensions as safe HTML sizing hints,
    while reusing the existing typed NodeID-scoped geometry and visibility
    cascade as the only responsive Image layout source.
  - Exclusions: responsive source sets, remote loading, image transforms,
    arbitrary CSS, browser execution, generated resource writes, publishing,
    and release acceptance.

- [ ] `SF-AUTHORING-047` Static Image fit/focal output parity foundation (P1).
  - Requirements: bounded compiler evidence for `SF-0802-003`–`004` and
    `SF-1204-003`–`004`.
  - Plan: map only typed canonical Fit/Fill/Stretch and finite normalized
    focal coordinates into fixed `object-fit`/`object-position` CSS on the
    existing stable Image selector. Keep resource intent and geometry intact.
  - Exclusions: image editing/crops/renditions, arbitrary transforms/CSS,
    responsive source sets, browser loading, generated resource writes,
    publishing, and release acceptance.

- [ ] `SF-AUTHORING-046` Static Image resource-reference parity foundation (P1).
  - Requirements: bounded compiler evidence for `SF-0801-003`, `SF-0802-003`,
    and `SF-1203-003`–`004`.
  - Plan: carry canonical Image AssetID/alt/decorative intent through the
    immutable static tree, resolve only a verified content-addressed path from
    the existing resource planner, and retain a safe missing-resource state
    when no entry is available.
  - Exclusions: resource byte export/writes, image transforms or editing,
    remote URLs/providers, raw HTML attributes, browser image loading,
    responsive source sets, publishing, and release acceptance.

- [ ] `SF-AUTHORING-045` Static typography-output parity foundation (P1).
  - Requirements: bounded compiler evidence for `SF-0507-003`–`004`,
    `SF-1203-003`, and `SF-1204-003`–`004`.
  - Plan: retain canonical Text semantics and escaped plain content in the
    static tree, then project only closed, validated typography values into a
    deterministic NodeID-scoped stylesheet. The canonical System family maps
    to portable `system-ui`; arbitrary installed family names are safely
    omitted rather than becoming raw CSS.
  - Exclusions: rich text/spans, raw HTML/CSS, custom/remote font loading,
    browser rendering, component expansion, responsive typography, generated
    document shells, export/publishing, and release acceptance.

- [ ] `SF-AUTHORING-044` Static multi-page layout-plan integration (P1).
  - Requirements: bounded compiler evidence for `SF-1204-003`–`004` and
    `SF-1206-003`, reusing the responsive cascade from `SF-0601-003` and
    `SF-0603-003`.
  - Plan: attach the immutable typed layout projection to the existing
    multi-page build plan as one deterministic stylesheet. It remains a plan
    artifact, shares NodeID selectors and canonical geometry with SF-043, and
    never becomes an authored CSS or browser/runtime path.
  - Exclusions: generated-site packaging/writes, HTML document-shell linking,
    raw CSS, browser execution, arbitrary media/layout syntax, publishing, and
    release acceptance.

- [ ] `SF-AUTHORING-043` Static layout-output parity foundation (P1).
  - Requirements: bounded compiler evidence for `SF-1204-001`–`005`, with
    typed responsive resolution from `SF-0601-003` and `SF-0603-003`.
  - Plan: project only validated canonical base geometry, explicit Tablet/
    Mobile overrides, and visibility provenance into a deterministic,
    NodeID-scoped CSS allowlist. Base rules always establish a stable absolute
    frame; breakpoint rules only contain explicitly authored overrides.
  - Exclusions: arbitrary CSS or media strings, browser/runtime layout,
    authored flex/grid/container queries, static-file export, publishing, and
    release acceptance.

- [ ] `SF-AUTHORING-042` Static navigation-output foundation (P1).
  - Requirements: bounded compiler evidence for `SF-0202-001`–`006`,
    `SF-0303-001`–`006`, and `SF-1102-001`–`006`.
  - Plan: derive deterministic accessible navigation only from ordered persisted
    Home/standard pages and validated static route mappings. Preserve PageID/
    route provenance and current-page semantics; omit Not Found, component, or
    unavailable routes without writing canonical state. Nested output paths use
    validated relative links rather than assuming a root-routing server.
  - Exclusions: authored navigation templates, redirects, dynamic routes,
    scripts, browser runtime, publishing, static-file export, and release
    acceptance.

- [ ] `SF-AUTHORING-041` Static Button and Link output parity foundation (P1).
  - Requirements: bounded compiler evidence for `SF-0806-001`–`005`,
    `SF-1102-001`–`005`, and `SF-1203-001`–`005`.
  - Delivered foundation: immutable static-tree projection now resolves only
    typed canonical Link targets. Valid external and package-owned page/section
    targets become escaped static hrefs; missing targets stay inert and
    accessible. Button output is explicitly `type=button` and disabled because
    browser runtime/action semantics are not part of this slice. A valid Link
    target authored for a new context emits only `target=_blank` with
    `rel=noopener noreferrer`.
  - Evidence: `docs/evidence/SF-AUTHORING-041-STATIC-CONTROLS.md`. No local
    tests were run in this checkpoint under the owner-directed test pause.
    `CanvasRendererTests.testStaticControlCompilerEscapesTypedRoutesAndKeepsMissingTargetsInert`
    is the queued focused regression for the next permitted test run.
  - Deferred: editor-side browser navigation, actions, submission, arbitrary
    HTML attributes, generated-site accessibility, static file export, and
    release acceptance.

- [ ] `SF-AUTHORING-038` Responsive static-output parity foundation v1 (P1).
  - Requirements: bounded compiler evidence for `SF-0601-001`–`005`,
    `SF-0602-001`–`005`, and `SF-0603-001`–`005`.
  - Delivered: fixed Tablet/Mobile media rules derive only from typed canonical
    geometry and visibility overrides. Custom breakpoints, arbitrary CSS/media,
    browser runtime, container queries, and fluid typography remain deferred.
    Focused compiler evidence: 1/1 (2026-09-27).

- [ ] `SF-AUTHORING-037` Local form-validation and preview-state foundation v1 (P1).
  - Requirements: bounded noncanonical evidence for `SF-1006-001`–`005`,
    `008`; `SF-1006` remains Partial.
  - Plan: resolve canonical Form field configuration against an explicit,
    caller-owned visitor-value snapshot. Bind results to document/page/form/
    revision/scene/renderer identity; return only stable result identities and
    failure categories. No document, history, package, autosave, recovery,
    server, browser, destination, or submission write path.
  - Delivered checkpoint: required/text/email/select/checkbox validation and
    an optional authored 1…4,096 maximum-length rule for text-like fields,
    deterministic field/form identities, cancellation/stale/schema rejection,
    static-output compatibility indicator, package-reopen input proof,
    Inspector-facing scene-local result adoption, keyboard/menu validation
    command, accessibility-focused category-only summary, and strict value
    redaction. Focused non-UI evidence is 2/2 for this checkpoint
    (2026-09-26).
  - Next bounded task: deterministic static-output compatibility reporting and
    explicitly disabled Form submission across multi-page builds.
  - Static-output checkpoint: canonical maximum-length metadata now emits a
    native `maxlength` constraint, and the multi-page planner can derive a
    stable, content-redacted Form compatibility report. Submit controls remain
    explicitly disabled with no route or data handling.
  - Exclusions: network/server/browser runtime, real submission/destinations,
    anti-abuse, analytics, visitor-value persistence, UI automation, generated
    runtime success/error UI, performance/release acceptance.

- [ ] `SF-AUTHORING-036` Accessible form authoring v1 (P1).
  - Requirements: bounded implementation evidence for `SF-1006-001`–`006`,
    `008`; `SF-1006` remains Partial pending visitor/runtime behavior and a
    native app journey.
  - Completed user-facing slice: Form is enabled in Elements and Insert and
    creates an empty canonical 320×180 container through the shared insertion
    registry. Selecting the Form gives a truthful Content summary; selecting a
    Text child gives native Field kind, label, machine name, help, required,
    and ordered Select-options controls. Submission, destination, validation,
    and visitor data are explicitly unavailable.
  - Integrity boundary: `FormInspectorCommandRegistry` validates document,
    page, revision, scene, renderer, selection, parent, lock/hidden/
    availability, and typed field data before a single invertible generic
    document command. Drafts remain local; cancellation/stale/invalid input is
    nonmutating. Focused non-UI evidence is 4/4 (2026-09-26).
  - Next bounded task: actual-app accessibility/pointer/keyboard evidence for
    Form and field editing. SF-AUTHORING-037 separately owns ephemeral local
    validation. Visitor values, submission routing, validation/
    anti-abuse, runtime success/error behavior, performance and release
    acceptance remain excluded.

- [ ] `SF-AUTHORING-035` Local build profiles and compatibility diagnostics v1 (P1).
  - Bounded SF-1208/SF-1211 noncanonical development/production build reports.

- [ ] `SF-AUTHORING-034` SEO and static metadata foundation v1 (P1).
  - Bounded `SF-1207-001`–`008` internal typed metadata/head emission.

- [ ] `SF-AUTHORING-033` Portable static asset-export foundation v1 (P1).
  - Bounded project-owned PNG/JPEG content-addressed export planning only.

- [ ] `SF-AUTHORING-032` Multi-page static-output foundation v1 (P1).
  - Bounded SF-1206/SF-0303/SF-0306 route planning for static persisted pages.

- [ ] `SF-AUTHORING-031` Local static-site build foundation v1 (P1).
  - Bounded internal plan evidence for SF-1202/1203/1204/1206. Deterministic
    controlled staged output writer is implemented; multi-page routing remains
    the successor work.

- [ ] `SF-AUTHORING-030` Safe CSS emission foundation v1 (P1).
  - Requirements: bounded internal evidence for `SF-1204-001`–`008`; fixed
    geometry declaration allowlist only. No raw CSS, files, runtime or export.

- [ ] `SF-AUTHORING-029` Safe HTML emission foundation v1 (P1).
  - Requirements: bounded internal evidence for `SF-1203-001`–`008`; fixed
    semantic vocabulary and NodeID-derived attributes only. No files/runtime.

- [ ] `SF-AUTHORING-028` Render-tree compilation foundation v1 (P1).
  - Requirements: bounded internal evidence for `SF-1202-001`–`008`; immutable
    adopted-scene compilation only, with NodeID provenance, semantic intent and
    deterministic derived CSS selector metadata. No generated files/runtime.

- [ ] `SF-AUTHORING-027` CSS-rule authoring foundation v1 (P1).
  - Requirements: bounded model-first evidence for `SF-1204-001`–`008`.
    Typed `css.rule.v1` intent derives a stable NodeID selector; no raw CSS,
    generated files, browser runtime, export or publishing is included.
  - SF-AUTHORING-026 remains IN PROGRESS pending its separately scheduled UI
    and hosted gate.

- [ ] `SF-AUTHORING-026` Semantic HTML element authoring v1 (P1).
  - Requirements: bounded implementation of `SF-1203-001`–`008` for the
    existing authored node kinds only. Plan: add a canonical versioned
    semantic-element value with omitted/defaulted/authored provenance; resolve
    it through the existing identity-gated Inspector transaction path; expose
    a native, accessible inspector control; and prove history, package,
    recovery, preview provenance and renderer adoption with focused evidence.
  - Exclusions: raw HTML, arbitrary attributes, custom elements, DOM/script
    authoring, generated HTML/CSS files, browser runtime, routing, export,
    publishing, accessibility-tree generation and release acceptance.

- [ ] `SF-CANVAS-POINTER-001` Shared native pointer/compositor placement repair (P1, hosted pointer-sampling correction).
  - Bounded SF-0401-001/003/008, SF-0405-002/003/008 and SF-0407-001/003/008.
  - Plan: establish native event/view/layer conversion numerically, remove the
    duplicate container inversion, prove preview/commit movement independently
    against pointer pixels, retain upright text and exact canonical geometry.
    Run affected focused tests, then one combined SF024 verification gate.
  - No per-tool offsets, persisted coordinate changes, new authoring scope or
    editor chrome in authored output. Preserve the existing immutable adoption.
  - All ten affected renderer tests have passing focused evidence; the native
    pointer journey passes, with twelve reviewed captures. Combined final
    verification passed 429 non-UI + 61 UI = 490 tests, zero failures.
    Evidence: `docs/evidence/SF-CANVAS-POINTER-001.md`. Hosted confirmation pending.
  - Run `34742950348` passed 429 non-UI and 60/61 UI tests. The new pointer
    journey sampled pasteboard on the narrow hosted display and mistook the
    correctly clipped AX rectangle for a placement error. Bound test samples
    to the visible artboard; retain every pixel/geometry assertion. Add narrow
    sampling regression and rerun only these affected selectors before push.
  - Narrow sampling passes 1/1. On September 20 the desktop was unlocked and
    the XCTest runner launched, but XCTest timed out enabling Automation Mode
    before the pointer test body. This is a recurrence of the separately
    closed SF-TEST-HARNESS-001 service failure, not a product assertion.
    Do not retry unchanged locally; run the exact selector from Xcode's Test
    navigator once macOS UI Automation is healthy, then commit/push this
    test-only correction and inspect CI.

- [x] `SF-AUTHORING-025` Local Preview v1 (P1, hosted verified).
  - Requirements: bounded evidence for `SF-1201-001`–`008` and
    `SF-1202-001`–`008`; `SF-1203`/`SF-1204` remain explicitly deferred.
  - Delivered: freeze an immutable revision-tagged authored render snapshot at
    deliberate Preview/Refresh boundaries; display it in an editor-chrome-free
    native sheet using the existing canvas object contract, with visible
    loading/empty/error state and stale-result rejection. Reuse canonical
    geometry, fills, images and text; the preview never writes document or
    history state.
  - Acceptance: Preview command/toolbar/accessibility opens a readable local
    page snapshot, Refresh adopts only a newer matching revision, Close/Escape
    returns focus, and visible diagnostics identify unsupported runtime
    features. Snapshot tests and a native visual journey cover editor-chrome
    exclusion, immutable adoption and supported-object rendering.
  - Exclusions: publishing, export files, HTML/CSS generation, JavaScript,
    runtime routing/CMS/remote content, browser deployment, preview/export
    parity, and release acceptance.
  - Evidence: immutable snapshot model, Preview/Refresh UI journey, narrow
    display pointer regression, and the formerly failing component journey all
    pass. The final gate passed 430 unit/integration + 63 UI = 493 tests,
    zero failures; repository checks passed. The native journey retains the
    original-resolution `SF-AUTHORING-025 local preview authored snapshot`
    attachment. See `docs/evidence/SF-AUTHORING-025-LOCAL-PREVIEW.md`.
    SF-1201/SF-1202 stay Partial outside this deliberately local preview.
    Hosted Actions `36166584811` passed at `1ab912e` with the same 430
    unit/integration + 63 UI = 493 tests after closing SF-CI-025.

## DONE

- [x] `SF-CI-025` Hosted native-interaction stabilization (P1).
  - Hosted run `36106023892` exposed constrained title-bar drag clamping and
    OpenPanel Go-to-Folder confirmation. Shared helpers now re-query live AX
    state after each genuine action, make one bounded corrective drag, and use
    the native Go button only when its field remains visible. Product width,
    import behavior and strict hit-target assertions remain unchanged.
  - Actions `36166584811` passed at `1ab912e`: 430 non-UI + 63 UI = 493 tests,
    zero failures. This closes the hosted confirmation for SF-AUTHORING-025.

- [x] `SF-AUTHORING-024` Exposed component text properties and instance reset (locally verified).
  - Bounded SF-0902-001–008 and SF-0905-001–008; broad modules remain Partial.
  - Plan: extend ADR-0018's canonical definition graph with stable exposed
    plain-text bindings and instance overrides; reuse identity-gated commands,
    exact history and derived expansion. Add native definition/instance controls,
    focused migration/resolution/history/resource/UI evidence and visual review,
    then one authoritative verification gate.
  - Acceptance: named Text property, independent values in two linked instances,
    valid authored empty text, default propagation, reset one/all by removal,
    cancel/invalid/stale neutrality, exact undo/redo, safe binding removal,
    duplication/remapping, effective-text detachment and save/recovery/reopen.
    Virtual expanded nodes remain noncanonical. Existing v7 components migrate
    without invented exposed properties or lost references.
  - Removal policy: reject source/property removal while authored overrides
    depend on it; retain unresolved loaded overrides and report missing bindings.
    No destructive automatic migration of instance content.
  - Exclusions: media/boolean/enum/action props, slots, variants, nested
    components, arbitrary style overrides, remote libraries, export/release.
  - Settings baseline `b50375c` is separate; hosted run `34252345248` passed.
    No unchanged Settings or baseline rerun is required.
  - Focused acceptance: 11/11 non-UI + 1/1 two-instance UI journey;
    five original-resolution captures reviewed. The draft/adoption race is
    covered by an independent regression. Combined final `./sf verify` passed
    429 non-UI + 61 UI = 490 tests, zero failures; repository checks passed.
    Hosted confirmation pending. No SF-AUTHORING-025 implementation started.

- [x] `SF-AUTHORING-023` Native application Appearance Settings (locally verified).
  - Bounded SF-0206-002/003/004/006/008 evidence; module remains Partial.
  - Plan: typed versioned app-local appearance preference under ADR-0006;
    native Settings with draft preview, Apply, Cancel/Escape, Reset and exact
    restoration; focused persistence/validation/UI tests and visual review,
    then one authoritative verification gate.
  - Acceptance: Follow macOS/Light/Dark, explicit application scope and
    default/authored provenance, invalid/future data preserved with safe
    fallback, cancellation and close rollback, persisted choice after reopen,
    accessible native keyboard controls and truthful diagnostics.
  - Exclusions: canonical project preferences (SF-0206-001), canvas/code/
    publishing/experimental preferences, profiles, document-history changes,
    and broad module/release acceptance. No document or package mutation.
  - Focused acceptance: 6/6 model + 1/1 actual-app journey; five original-size
    Settings screenshots reviewed. Native Close/Command-W rollback and AX
    value semantics are covered. Final `./sf verify` passed 420 unit/integration
    + 59 UI = 479 tests, zero failures; repository checks passed. Hosted CI
    passed at `b50375c` in Actions `34252345248`. Evidence:
    `docs/evidence/SF-AUTHORING-023-APPEARANCE-SETTINGS.md`.

- [x] `SF-AUTHORING-022` Reusable local components (hosted verified).
  - Requirements: bounded `SF-0901-001`–`008`, supporting `SF-0905-003`–`005`
    identity, inheritance and exact history. These modules remain Partial.
  - Plan: first repair SF-AUTHORING-021's narrow-display pointer journey;
    then implement canonical definitions/linked instances, shared resolution,
    definition editing, detach/delete and native Components controls through
    existing transactions. Add focused model/package/render/UI evidence and
    visually review the real workflow before one integrated final gate.
  - Preserve stable identities, resource references and independent instance
    placement; no serialized expanded copies or blank-project fixtures.
  - Exclusions: nested authoring, variants, slots, per-child overrides, remote
    libraries, export/runtime/publishing and release acceptance.
  - Earlier SF-AUTHORING-021 hosted failure: run
    `34003323869` exposed Pages outside the narrow display's leading edge.
    The pointer repair passed two focused window-policy tests and the exact
    native-Xcode page journey (1/1, 112.949 seconds); five retained images were
    reviewed. Managed automation initialization failed before the test body,
    so those earlier attempts are not product failures. The integrated hosted
    checkpoint below subsequently passed.
  - Component progress: five focused command/resolution/history/context tests pass,
    including detachment across all three breakpoints. The real create/link/
    edit/detach/reopen journey passed after visual corrections (1/1, 96.221
    seconds). Five original-resolution images were reviewed; the definition
    breadcrumb and inherited-instance Inspector are now readable. See
    `docs/evidence/SF-AUTHORING-022-LOCAL-COMPONENTS.md`.
    Two additional strict-schema/budget/cancellation/collision checks passed,
    and the resource save/recovery check passed after correcting its incomplete
    Image fixture. Historical migration checks passed 3/3, placement/schema
    checks passed 2/2, and both final component UI journeys passed independently.
    Original-resolution maximized and compact images were reviewed.
    Final integrated verification passed 413 unit/integration + 56 UI = 469
    tests, zero failures; all repository gates passed.
    Run `34165188350` passed 413 non-UI and 54/56 UI tests; the two
    narrow-display pointer failures and focused corrections are recorded in
    the component evidence. Do not restart unrelated feature work.
    Follow-up `34169229028` passed the component workflow but exposed a
    constrained-placement observer lock and an ambiguous image-panel query.
    Both boundaries are corrected with six passing affected selectors,
    including a real native window-movement regression. Actions `34172995329`
    for `bb5992f` passed final `./sf verify`: 414 unit/integration + 58 UI =
    472 tests, zero failures. This also closes SF-AUTHORING-021's hosted gate.
  - Subsequent owner-authorized batch: after this coherent checkpoint, create
    a specification-backed completion roadmap and continue up to three
    dependency-ready user-visible slices. Preserve separate commit/CI identity;
    do not treat the historical handoff's stop instructions as current policy.

- [x] `SF-AUTHORING-021` Static page management and route editing (hosted verified).
  - Requirements: bounded `SF-0303-001`–`008`, supporting `SF-0306-005`,
    `SF-0307-001`–`005` and `SF-1102-001`–`005`. OD-003 special-page roles
    and ADR-0003/0004 identity/history invariants remain authoritative.
  - Plan: extend existing page commands with validated route/reorder edits;
    prepare identity-gated create/duplicate/delete operations; expose native
    Pages controls with drafts and deletion impact; verify links, exact history,
    packages and focused actual-app workflows before the final full gate.
  - Preserve Home `/` and Not Found `/404`; ordinary pages start with only a
    non-rendered root. Duplicate nodes get fresh identities; internal duplicate
    links remap, outbound links and immutable resources remain shared.
  - Exclusions: folders, CMS/dynamic routes, localization, redirects, role
    reassignment, SEO, navigation templates, runtime navigation, export and
    publishing. Normative modules remain Partial outside this bounded slice.
  - Evidence: five focused model selectors and two new actual-app journeys
    pass, plus the affected prior Button/Link compact target journey. Seven
    retained window images were reviewed. Final `./sf verify` passed 404
    unit/integration + 54 UI = 458 tests, zero failures. Hosted verification
    passed in integrated run `34172995329` at `bb5992f` (472/472). See
    `docs/evidence/SF-AUTHORING-021-STATIC-PAGES.md`.

- [x] `SF-AUTHORING-020` Implement Button and Link authoring.
  - Active evidence: `docs/evidence/SF-AUTHORING-020-BUTTON-LINK.md`.
    Focused model, migration, history, glyph and all three new UI journeys
    passed; maximized/compact visuals were reviewed. Final local gate passed
    399 unit/integration + 52 UI = 451 tests, zero failures. Actions
    `34000476753` passed the same 451 tests for pushed checkpoint `85615b9`.
  - Requirements: bounded evidence for `SF-0806-001` through
    `SF-0806-008` and `SF-1102-001` through `SF-1102-008`, plus the existing
    insertion, content, typography, style, responsive, persistence, history,
    recovery, accessibility, and diagnostic contracts exercised by this slice.
    Both normative modules remain Partial outside this local authoring path.
  - Plan: extend the existing typed node/property and identity-gated insertion
    architecture with Button and Link; add one versioned label/link-target
    codec and one central content/interaction transaction registry; resolve
    internal PageID/NodeID and external HTTP(S) targets without editor
    navigation; render upright accessible controls through immutable snapshots;
    then prove validation, broken-target recovery, exact history, package/
    recovery, mixed applicability, and the actual maximized/compact workflow.
  - Explicit exclusions: embeds and remote previews, downloads, network
    fetching, custom protocols, analytics, runtime navigation, state styling,
    multi-action graphs, animation, export/publishing, advanced variants,
    CMS/data binding, components, broad performance/accessibility matrices,
    and release acceptance.

- [x] `SF-AUTHORING-019` Final native Save availability follow-up.
  - Requirements: `SF-0301-005`, `SF-0306-003`–`005`, supporting
    `SF-0801-005` and `SF-0802-005`.
  - Actions `33986611685` attempt 2 passed 392 non-UI and 48/49 UI tests;
    typography exposed disabled Save during recovery autosave/menu tracking.
  - Native Save remains enabled during recovery autosave using the existing
    cancel/drain boundary. Its strengthened deterministic lifecycle regression
    and typography persistence journey passed individually (2/2).
  - Hosted job headroom permits completion/artifact retention beyond measured
    30-minute runtime; no XCTest timeout or assertion changes.
  - Actions `33991018406` passed final production correction `f951df7`:
    392 unit/integration plus 49 UI tests (441/441), zero failures; repository
    checks passed. Reviewed reopen evidence confirms Saved status, preserved
    typography, upright text and aligned selection. No local broad rerun.

- [x] `SF-AUTHORING-019` Close the hosted Inspector/autosave correction.
  - Requirements: supporting `SF-0502-002`, `SF-0505-002`,
    `SF-0801-005`, `SF-0802-005`, and `SF-1902-008`; the bounded
    local-raster scope and explicit exclusions below remain unchanged.
  - Root cause: snapshot autosave disabled the shared Inspector validation
    context between native pointer and keyboard events. Editing now remains
    available during immutable-snapshot saving/autosaving with existing
    revision, conflict, and read-only guards intact.
  - Native Save accepts already-Saved state without requiring an enabled
    command; narrow displays preserve the 1100-point window minimum. Helpers
    re-query live fields and operate genuine enabled, safely visible segments.
    Alignment has a readable single-line label at compact Inspector widths.
  - Evidence: seven distinct affected selectors passed; the three original
    failing journeys passed three consecutive fresh-process groups (9/9).
    Final local and hosted verification each passed 392 unit/integration plus
    49 UI tests (441/441), zero failures. Repository checks and diff hygiene
    passed. Original-resolution persistence and alignment evidence was reviewed.
  - Hosted acceptance: Actions `33982941555` passed for production commit
    `f6c58ef`. See
    `docs/evidence/SF-AUTHORING-019-INSPECTOR-REPAIR.md`.
  - Test-only follow-up: Actions `33984707264` passed all 49 UI tests but
    exposed an unordered-task assumption in one save-lifecycle unit test.
    Its artificial delay/yield was replaced by the existing filesystem
    checkpoint barrier; exact save/revision assertions were strengthened.
    The corrected test and adjacent save-race regression passed 2/2. No
    production code changed and no broad local suite was repeated.

- [x] `SF-AUTHORING-019` Initial local image assets and Image authoring checkpoint.
  - Requirements: bounded production evidence for `SF-0801-001` through
    `SF-0801-008` and `SF-0802-001` through `SF-0802-008`, plus only the
    existing insertion, canvas, Inspector, persistence, history, recovery,
    accessibility, and diagnostic contracts exercised by this vertical slice.
    Both normative media modules remain Partial outside this local-raster path.
  - Plan: extend the existing content-addressed `ProjectResourceStore` and
    package resource index with one versioned canonical image-asset catalogue;
    import validated local raster bytes off the main actor through the native
    open panel; add one typed Image node/reference and identity-gated insertion
    path; snapshot decoded image content into the immutable renderer; expose a
    searchable accessible Assets pane and bounded Image Inspector for asset,
    fit/fill/stretch, focal point, and alt/decorative semantics; then prove
    transactional rename/replace/delete recovery, history, persistence,
    missing-resource behavior, geometry parity, and the actual maximized and
    practical-minimum running-app workflow before one authoritative gate.
  - Explicit exclusions: folders, tags, favorites, bulk organization, remote
    or stock providers, SVG/video/audio/font assets, advanced image editing,
    filters, masks, multiple crops/renditions, responsive source sets, metadata
    policy UI, image fills on non-Image nodes, preview/export parity, and
    release acceptance.
  - Result: schema-v5 owns stable image-asset descriptors and Image-node
    references while the existing content-addressed resource sidecar preserves
    original bytes. The native Assets pane and open-panel import path,
    Elements/Insert commands, bounded Image Inspector, immutable renderer,
    history, persistence, recovery, missing-resource placeholder, and
    accessibility geometry form one production path.
  - Evidence: focused resource/insertion/command/package/renderer coverage
    passed 116/116; affected architecture, metadata, transform, navigator, and
    actual-app image journeys passed. Hosted stabilization then proved the
    three affected journeys independently (3/3) and across three consecutive
    grouped runs (9/9), followed by the complete UI target (49/49). The final
    `./sf verify` passed 391 unit/integration plus 49 UI tests (440 total), zero
    failures, with repository, security, traceability, architecture, migration,
    and evidence checks green on 2026-09-04. Six original-resolution
    maximized-window states passed visual review; see
    `docs/evidence/SF-AUTHORING-019-LOCAL-IMAGE-AUTHORING.md`.
    Hosted stabilization passed in Actions `33942209770`, which passed the
    complete 391 unit/integration plus 49 UI gate after the shared structural
    pointer helper required controls to be inside the usable display rather
    than trusting an obscured `isHittable` result. The subsequent
    foreground-ownership follow-up is tracked above.

- [x] `SF-AUTHORING-018` Add responsive container layout and breakpoint
  visibility.
  - Requirements: bounded continuation of `SF-0601-001` through
    `SF-0601-008`, `SF-0602-001` through `SF-0602-008`, and `SF-0603-001`
    through `SF-0603-008`, with supporting `SF-0502`/`SF-0503` evidence; the
    normative responsive modules remain Partial outside this slice.
  - Result: the existing stable Desktop/Tablet/Mobile cascade now authors and
    resets breakpoint-specific Section padding, Stack direction/gap/padding/
    alignment, Grid columns/gap/padding, and visibility for Frame, Text,
    Section, Stack, and Grid. One identity-gated transaction path preserves
    exact inverses and one resolved scene feeds layout, renderer, selection,
    hit testing, inline editing, Layers, and accessibility. Hidden subtrees do
    not participate in authored canvas behavior, while Layers retains stable
    identity and an explicit inspect/restore route.
  - Evidence: seven focused non-UI selectors and the fresh-process responsive
    journey passed; the practical-minimum Inspector remains covered by the
    existing structural journey. Final hosted `./sf verify` passed 379 unit/
    integration plus 48 UI tests (427 total), zero failures, with repository,
    security, traceability, architecture, migration, and evidence checks green
    on 2026-08-31. Hosted follow-up also proved nested insertion remains
    available during immutable-snapshot autosave and every container Reset
    control remains visible at the practical Inspector width. Seven
    original-resolution maximized-window states passed
    visual review; see
    `docs/evidence/SF-AUTHORING-018-RESPONSIVE-LAYOUT-VISIBILITY.md`.
  - Explicit exclusions: custom or overlapping breakpoint management,
    responsive fills/box styles/typography/content/assets/components,
    comparison panes, orientation/safe-area simulation, container queries,
    fluid typography, alternate source sets, preview/export parity,
    cross-hardware/OS accessibility matrices, and release acceptance.

- [x] `SF-AUTHORING-017` Implement production Section, Stack, and Grid layout
  controls.
  - Requirements: bounded production evidence for `SF-0502-001` through
    `SF-0502-008`, `SF-0503-001` through `SF-0503-008`, and the spacing portion
    of `SF-0506-001` through `SF-0506-008`; these normative modules remain
    Partial outside this structural-layout authoring slice.
  - Result: native Layout controls author/reset Section padding; Stack axis,
    uniform padding/gap, and start/center/end/stretch alignment; and Grid
    columns, uniform padding/gap, and deterministic row-major placement. One
    identity-gated registry supplies exact history and truthful mixed/applicable
    results. The shared resolver preserves stable child identity/order and
    proportionally fits oversized insertion defaults inside bounded container
    content boxes without rewriting canonical child geometry.
  - Evidence: five focused model/renderer/package selectors and two actual-app
    journeys passed; `./sf test half` passed 371/371. Final `./sf verify` passed
    372 unit/integration plus 47 UI tests (419 total), zero failures, with every
    repository gate green on 2026-08-28. Original-resolution maximized and
    practical-minimum states passed visual review. See
    `docs/evidence/SF-AUTHORING-017-STRUCTURAL-LAYOUT.md`.
  - Explicit exclusions: responsive container-layout overrides, per-side or
    logical padding, separate row/column gaps, wrapping, advanced distribution,
    non-row-major auto-flow, explicit/minmax/fractional tracks, named areas,
    responsive content/visibility, custom breakpoints, component layout,
    container queries, preview/export parity, and release acceptance.

- [x] `SF-AUTHORING-016` Implement responsive breakpoint geometry overrides and
  live device authoring.
  - Requirements: bounded production evidence for `SF-0601-001` through
    `SF-0601-008` and `SF-0602-001` through `SF-0602-008`; both normative
    modules remain Partial outside the geometry-authoring slice.
  - Plan: establish stable Desktop/Tablet/Mobile breakpoint identities and
    deterministic non-overlapping width resolution; store typed per-node
    geometry overrides with explicit authored/inherited provenance; extend the
    identity-gated Layout registry so set/reset is one exact transaction;
    project one resolved geometry snapshot into layout, renderer, selection,
    hit testing, inline editing, and accessibility; expose inherited source and
    Reset Override in native Layout controls; prove history, package/recovery,
    preset/custom-width resolution, accessibility, and actual-app parity before
    one authoritative verification gate.
  - Explicit exclusions: custom breakpoint management, overlapping ranges,
    responsive style/fill/typography/visibility/content, comparison panes,
    orientation and safe-area simulation, container queries, fluid typography,
    component responsiveness, preview/export parity, and release acceptance.
  - Result: stable fixed Desktop/Tablet/Mobile identities resolve deterministic
    non-overlapping ranges. Desktop remains the base geometry source; native
    Layout fields author isolated Tablet/Mobile X/Y/Width/Height overrides,
    label inherited/authored provenance, and remove overrides through a visible
    Reset action. One responsive resolver feeds immutable renderer, selection,
    hit-test, accessibility, package, recovery, history, and inline geometry.
  - Evidence: four focused model/renderer/package selectors and one actual-app
    journey passed 5/5. Original-resolution maximized-window screenshots were
    reviewed for Desktop inheritance, visible Tablet/Mobile overrides, reset,
    undo/redo, artboard/grid clarity, aligned selection, readable controls, and
    absence of ghost/debug content. Final `./sf verify` passed 367 unit/
    integration plus 45 UI tests (412 total), zero failures, with every
    repository gate green on 2026-08-28. See
    `docs/evidence/SF-AUTHORING-016-RESPONSIVE-GEOMETRY.md`.

- [x] `SF-AUTHORING-015` Implement bounded production typography controls and
  consistent text rendering.
  - Requirements: bounded evidence for `SF-0507-001` through `SF-0507-008`.
    The normative module remains Partial for imported/web fonts, licensing,
    variable axes, rich-text ranges, lists/links, advanced paragraphs,
    responsive overrides, tokens, preview/export parity, scale acceptance, and
    release acceptance.
  - Plan: add one typed versioned canonical typography namespace for plain Text;
    resolve installed families and deterministic fallback without changing
    authored intent; compile family, weight, size, line-height, tracking, and
    alignment drafts through one identity-gated transaction registry; snapshot
    the resolved metrics into immutable render objects shared by committed tile
    text and the native inline editor; prove strict validation, mixed/applicable
    subsets, exact history, package/recovery, accessibility, compact layout, and
    running-app visual parity before one authoritative verification gate.
  - Explicit exclusions: font import/licensing, variable axes, rich-text spans,
    lists, links, advanced paragraph controls, vertical/path text, responsive
    typography, design tokens, preview/export parity, and release acceptance.
  - Result: strict `style.typography.v1` properties and one identity-gated
    registry now author plain-Text family, bounded weight, size, explicit line
    height, tracking, and leading/center/trailing alignment. Installed-font
    resolution preserves authored intent while exposing deterministic system
    fallback; committed tiles and the live native editor share one metric and
    geometry contract.
  - Verification: focused registry/history, render/layout, package/recovery,
    and actual-app Save/reopen coverage passed 4/4. The authoritative
    `./sf verify` passed 363 unit/integration plus 44 UI tests (407 total), zero
    failures, on 2026-08-28; all repository gates passed. Six original-resolution
    maximized-window states were visually reviewed. Evidence:
    `docs/evidence/SF-AUTHORING-015-TYPOGRAPHY.md`.

- [x] `SF-AUTHORING-014` Implement bounded Design Inspector border, uniform
  corner-radius, and single-shadow authoring.
  - Requirements: bounded production evidence for `SF-0506-001` through
    `SF-0506-008`; the normative module remains Partial for spacing/margin,
    independent/logical edges, per-corner radii, layered shadows, clipping UI,
    corner smoothing, preview/export parity, scale acceptance, and release
    acceptance.
  - Plan: add one typed canonical box-style namespace for applicable Frame,
    Section, Stack, and Grid nodes; compile native Inspector drafts through one
    identity-gated transaction registry; snapshot the resolved border, uniform
    radius, and one shadow into immutable renderer objects; composite shadow,
    clipped fills, and border deterministically while keeping selection chrome
    separate; prove invalid/cancel/stale/mixed/history/package/recovery behavior
    and the actual maximized/minimum-width running-app workflow before one
    authoritative verification gate.
  - Explicit exclusions: margin/padding editing, per-edge borders, per-corner
    radius, ordered multiple shadows, inner shadows, corner smoothing,
    responsive overrides, image/effect work, preview/export parity, and release
    acceptance.
  - Result: typed `style.box.v1` properties and one identity-gated registry now
    author an optional border, uniform corner radius, and one drop shadow for
    Frame, Section, Stack, and Grid. Immutable renderer snapshots composite
    shadow, radius-clipped fills, and border while interaction geometry and
    editor chrome remain separate.
  - Verification: focused registry/history, package/recovery, raster/tile, and
    two actual-app Inspector journeys passed 7/7. The authoritative
    `./sf verify` passed 360 unit/integration plus 43 UI tests (403 total), zero
    failures, on 2026-08-26; all repository gates passed. Original-resolution
    unstyled, border/radius, shadow, undo/redo, and practical-minimum Inspector
    attachments were visually reviewed. Evidence:
    `docs/evidence/SF-AUTHORING-014-BOX-APPEARANCE.md`.
  - Hosted follow-up: Actions `32931557907` and `32933185609` passed all
    repository and unit/integration checks plus 42/43 UI journeys. Retained
    screenshot/frame evidence proved the practical-minimum journey's supported
    1100-point window was left-aligned on the 1024-point hosted display, placing
    the Inspector's trailing Add controls beyond the physical screen; vertical
    scrolling could not expose that horizontal edge. This explicitly named
    compact pointer journey now uses the established right-edge test placement
    and live measured scrolling. Production and generic window policy are
    unchanged. Actions `32934689112` passed the complete 360 unit/integration
    plus 43 UI test gate (403 total) at `65571dc`.

- [x] `SF-AUDIT-001` Complete the post-milestone implementation audit by fixing
  every confirmed editable-scope defect before reporting it.
  - Requirements: bounded corrective evidence for `SF-0201-002`,
    `SF-0201-003`, `SF-0201-006`, `SF-0201-008`, `SF-0301-004` through
    `SF-0301-006`, `SF-0303-001`, `SF-0303-005`, `SF-0303-008`,
    `SF-0405-007`, `SF-0407-006` through `SF-0407-008`, `SF-0503-007`,
    `SF-0508-001` through `SF-0508-008`, `SF-1502-001`, `SF-1504-004`,
    `SF-1702-008`, `SF-1802-008`, `SF-1804-008`, `SF-1902-008`, and
    `SF-2002-008`.
  - Result: confirmed issues were corrected at their production
    boundaries: strict fill-v1 and package decoding, explicit fill numeric
    draft validation, descriptor-bound resource I/O with role/ACL/path-exchange
    rejection, coordinated cancellation relay, linear Grid row preparation,
    off-main production scene/renderer projection, bounded/privacy-preserving
    shared diagnostics, portable checksum output, document-window-only material
    policy, and minimum-width viewport/Inspector layout. The Codex workflow
    treats findings as internal work to
    fix and test rather than a user-facing prioritization handoff.
  - Focused evidence: the strict fill decode/migration/package selectors and
    numeric-draft selector passed; the resource/cancellation/Grid/diagnostic
    integration group passed 8/8; the 10,000-object active-work main-actor
    heartbeat regression passed; and the portable-checksum regression passed.
    See `docs/evidence/SF-AUDIT-001-CORRECTIONS.md` for exact selectors and
    recurring-risk controls. The minimum-window and normal-maximized running-app
    journeys passed 2/2 and their original-resolution window attachments were
    reviewed against the visual contract. The selection/geometry follow-up
    passed 3/3.
  - Completion gate: final `./sf verify` passed 356 unit/integration plus 41 UI
    tests (397 total), zero failures, on 2026-08-25. Repository, security,
    portable-checksum, traceability, architecture, migration, evidence, and
    fixture-hygiene checks passed. Hosted Actions `32917355488` at `3c90e33`
    passed the same 397-test gate after the compact-window accessibility
    follow-up.

- [x] `SF-AUTHORING-013` Implement bounded ordered fill layers and linear gradients.
  - Requirements: bounded continuation of `SF-0508-001` through `SF-0508-008` following `SF-AUTHORING-012`.
  - Result: `style.fill.layers.v1` provides stable ordered solid and linear-gradient layers and gradient-stop identities for Frame, Section, Stack, and Grid. Central registry transactions cover add, remove, reorder, enable, angle, stop position/order, and native colour edits with exact inverses. Immutable renderer snapshots composite enabled layers in authored order, clip to authored geometry, and apply object opacity once. First v1 write retires legacy schema-v4 fill keys; save/reopen and recovery preserve exact identities and values. Exact shared multiple selections remain editable, mixed stacks expose no borrowed rows, and incompatible objects are counted and skipped.
  - Verification: focused multi-selection passed; the corrected Inspector accessibility journey passed 1/1 and its original-resolution attachment was reviewed for readable controls, centered artboard geometry, and normal maximized-window presentation. Final `./sf verify` passed 331 unit/integration plus 39 UI tests (370 total), zero failures, on 2026-08-25. Repository, security, traceability, architecture, migration, evidence, and fixture-hygiene checks passed. Evidence: `docs/evidence/SF-AUTHORING-013-FILL-LAYERS-CHECKPOINT.md`.
  - Post-gate note: the later `SF-AUDIT-001` gate supersedes this 370-test
    historical result as evidence for the current tree.
  - Explicit exclusions: image fills, blend/filter effects, borders, shadows, tokens, broad color-profile work, responsive overrides, preview/export parity, OS-level VoiceOver/settings acceptance, cross-hardware performance budgets, and release acceptance. The normative SF-0508 module therefore remains Partial overall.
  - Dependencies: completed after `SF-AUTHORING-012`. No subsequent feature item is READY; the next bounded slice must be selected from the specification without silently expanding these exclusions.

- [x] `SF-AUTHORING-012` Implement bounded Design Inspector solid-fill and opacity editing.
  - Requirements: bounded evidence for `SF-0508-001` through `SF-0508-008`; the normative module remains Partial because layered fills, gradients, images, blending, filters, broad color-profile behavior, preview/export parity, and release acceptance are deferred.
  - Plan: retain typed canonical `NodeProperty` storage and the central transaction registry as the sole style authority. Resolve legacy `style.fill = surface` deterministically as a default neutral RGBA fill, then add normalized `style.fill.rgba` and `style.opacity` properties for applicable structural nodes. Keep color/opacity drafts scene-local, validate and atomically commit one property operation at a time, and render the resolved style without contaminating editor overlays. Add bounded model/UI/persistence evidence before full verification.
  - Result: `CanonicalSolidColor` stores finite normalized RGBA channels and `style.opacity` stores normalized opacity for Frame, Section, Stack, and Grid. A central identity-gated Design registry prepares each fill or opacity transaction and exact inverse; native NSColorWell/Colors-panel, hexadecimal, percentage field, and NSStepper paths share it. Drafts, picker preview, selection, grid, and editor chrome remain noncanonical.
  - Verification: focused registry/migration acceptance 3/3, pixel/coordinate acceptance 4/4, selection-clipping acceptance 4/4, Grid/preset visual journey 1/1, and native Design Save/Close/Open journey 2/2 passed. After the window-owned command-target correction, the Save, geometry/Escape, and insertion/adoption journeys passed individually and together (3/3); the complete UI target passed 38/38. Final `./sf verify` passed 323 unit/integration plus 38 UI tests (361 total), zero failures, on 2026-08-24. Repository/security/traceability/architecture/migration/evidence checks passed. Evidence: `docs/evidence/SF-AUTHORING-012-DESIGN-INSPECTOR.md`.
  - Explicitly deferred: layered fills, gradients, images, borders, shadows, blending/filters, typography, tokens, broad color-management, responsive overrides, preview/export parity, release acceptance, OS-level VoiceOver/settings exercise, and style-editing performance budgets.
  - Focused visual correction: an immutable render-plan viewport snapshot is now required for native tile adoption. A newer viewport generation withholds an older raster instead of compositor-transforming it against live selection/accessibility geometry. Authored pixels, selection chrome, transform handles, and accessibility all use the matching artboard intersection; an off-artboard selection retains identity and exposes Reveal Selection without a pasteboard ghost. Named header/menu insertion is one-shot and leaves the insertion session inactive, preventing a dashed preview from surviving a committed Frame or Text insertion.
  - Focused evidence: `CanvasViewportTests/testSelectionBadgePlacementRemainsInsideAllArtboardEdges`, `CanvasViewportTests/testSelectionBadgePlacementUsesCompactFallbackAndSuppressesOffArtboard`, `SelectionModelTests/testOffArtboardSelectionRetainsIdentityAndSuppressesGhostOverlay`, and `SelectionModelTests/testPartialArtboardClipLimitsTransformChromeToVisibleAuthoredGeometry` passed 4/4; `SiteForgeLaunchTests/testWorldGridArtboardHierarchyVisualJourney` passed 1/1 on 2026-08-21. The seven original-resolution retained screenshots are listed in `docs/evidence/SF-AUTHORING-012-DESIGN-INSPECTOR.md`; they were visually inspected and show the fitted Desktop gutter, Tablet clip with artboard-contained selection badge, Mobile off-artboard state, Reveal Selection, Grid On/Off, pan/zoom, and Fit.

- [x] `SF-AUTHORING-011` Implement production Layout Inspector fixed-geometry editing.
  - Requirements: bounded evidence for `SF-0403-001` through `SF-0403-008`. Fixed numeric geometry provides only a partial foundation toward `SF-0505-002`, `SF-0505-004` through `SF-0505-006`, and `SF-0505-008`; size modes, min/max constraints, aspect ratio, auto sizing, and responsive sizing remain explicitly deferred, so the `SF-0505` module remains Partial overall.
  - Plan: retain `layout.x`, `layout.y`, `layout.width`, and `layout.height` as the sole canonical geometry. Add a Foundation-only fixed-geometry inspector registry that validates stable document/page/revision/scene/renderer/selection identity, field applicability, finite bounded values, and typed subset outcomes before compiling one atomic existing-property batch. Keep locale-formatted text drafts in the Inspector only; Return/focus-loss commits and Escape restores without canonical mutation. Replace temporary one-pixel Inspector actions with native accessible X/Y/Width/Height fields for supported Frame, Text, Section, Stack, and Grid selection, and prove renderer/overlay/Layers/accessibility/history/package adoption.

  - Result: native X/Y/Width/Height text fields expose authored/defaulted or mixed state and use locale-aware presentation with strict complete-number validation. Their draft state is scene-local/noncanonical; Return and native focus-loss submit one typed atomic command, Escape restores the committed display. Inapplicable selected node kinds are explicitly reported as unchanged; canonical NodeID/frame, renderer, selection overlay, Layers, Inspector summary, history, package, autosave/recovery, and reopen behavior continue through the existing central transaction path.
  - Verification: focused model coverage passed 16/16; the real pointer/keyboard/focus-loss/Escape/undo/redo/accessibility Inspector journey passed 1/1 with a retained XCTest window attachment; `./sf test half` passed 306/306 unit/integration tests; final `./sf verify` passed 306 unit/integration plus 33 UI tests (339 total), zero failures, on 2026-08-13. Repository, secret, traceability, architecture, migration, evidence, and fixture-hygiene checks passed. Evidence: `docs/evidence/SF-AUTHORING-011-LAYOUT-INSPECTOR.md`.
  - Explicitly deferred: responsive overrides, size modes, aspect/min/max constraint UI, automatic sizing, rotation/skew, typography/rich text, broad property editing, export/publishing, OS-level VoiceOver/settings acceptance, cross-hardware budgets, and release acceptance.

- [x] `SF-CANVAS-VISUAL-001` Repair blank-pasteboard presentation and shared inline-text geometry.
  - Requirements: bounded evidence for `SF-0401-001`, `SF-0401-003`, `SF-0401-005`, `SF-0405-006`, `SF-0406-001`, `SF-0406-002`, `SF-0406-006`, `SF-0406-008`, and `SF-1902-008`; normative product typography and release visual acceptance remain Partial.
  - Result: fresh/adopted documents center their noncanonical pasteboard at the existing 100% zoom after a usable native viewport is available. The visible blank-state card is centered and cannot intercept surrounding canvas input. `CanvasTextLayout` supplies the same viewport object rect, text insets, font, line fragment, and vertical placement to tile rasterization and live `NSTextView`; the tile draw boundary remains the only Y conversion.
  - Verification: focused text-layout matrix and viewport-center tests, actual-app native-canvas adoption, and inline draft/commit/cancel journeys passed. `./sf test half` and final local/hosted `./sf verify` passed repository/security/traceability/architecture/evidence checks, 303 unit/integration tests, and 33 UI tests (336 total) on 2026-08-13. Hosted evidence: Actions `31675543875` at `f449813`. Retained XCTest window screenshots cover blank/insertion and draft/commit/cancel text states. No fixture/debug object is added to blank projects.

- [x] `SF-CI-007` Preserve constrained pointer-test trailing-edge geometry and deterministic failure artifacts.
  - Requirements: bounded regression coverage for `SF-0201-002`, `SF-0201-006`, `SF-0201-008`, `SF-0203-006`, `SF-0406-001`, `SF-0406-002`, `SF-0406-006`, `SF-0406-008`, `SF-0407-002`, `SF-0407-003`, `SF-0407-006`, `SF-0407-008`, and `SF-1902-008`.
  - Result: explicit constrained Debug/UI-test placement retains 1100-point physical width, fits only height within both usable-display safe edges, and exposes its named horizontal/vertical edge. Right alignment deliberately permits leading off-screen extent so trailing controls remain pointer-accessible; the text-status journey requests right/bottom. Production, generic UI-test, and Release presentation remain unchanged.
  - Verification: four-placement unit proof, deterministic result/log roots, all four real pointer journeys, and final local/hosted `./sf verify` passed on 2026-08-13: 303 unit/integration plus 33 UI tests. Hosted evidence: Actions `31675543875` at `f449813`; see `docs/evidence/SF-CI-007-CONSTRAINED-TRAILING-EDGE.md`.

- [x] `SF-AUTHORING-010` Implement the bounded structural Elements foundation: Section, Stack, and Grid.
  - Requirements: bounded evidence for `SF-0405-001`–`008`, `SF-0501-001`–`008`, `SF-0502-001`–`008`, and `SF-0503-001`–`008`; all remain Partial overall pending property editing, broad standards parity, responsive behavior, export, and release acceptance.
  - Result: canonical schema v4 adds typed `section`, `stack`, and `grid` node kinds with stable `NodeID`, ordered ownership, and explicit `.defaulted` v1 properties. Section inserts as a 960×320 structural container with 48-point padding. Stack resolves supported children vertically from 24-point padding/gap and start alignment. Grid resolves supported children row-major in two equal columns with 24-point padding/gap. Existing typed insertion commands, one-transaction inverses, history, package persistence, recovery, renderer, Layers, selection, Inspector, hit testing, and accessibility adopt the same canonical node and resolved geometry. Schema-v3 packages remain readable and re-save as v4; no blank-project fixture or fallback content is introduced.
  - Verification: focused schema/default/migration tests passed 3/3; actual-app structural catalog/Insert-menu nesting, renderer adoption, and undo/redo journey passed 1/1; focused inline-text regression passed 1/1; `./sf test half` passed 301/301 unit/integration tests; final `./sf verify` passed on 2026-08-12 with 301 unit/integration and 33 UI tests (334 total), zero failures. Repository, secret, traceability, architecture, migration, evidence, and fixture-hygiene checks passed. Evidence: `docs/evidence/structural-elements-foundation/` and retained XCTest screenshots/attachments.
  - Explicitly deferred: property editing, automatic sizing, broad CSS/layout parity, responsive overrides, Button/Link/Divider/Navbar/Footer behavior, assets/components, rich text, export/publishing, OS-level VoiceOver/settings acceptance, cross-hardware performance budgets, and release acceptance.
  - Dependencies: `SF-PRODUCT-UI-003`; OD-015 approved; ADR-0015.

- [x] `SF-PRODUCT-UI-003` Establish Inspector navigation, visible selected-frame presentation, normal maximized-window launch, and tiered local testing foundations.
  - Requirements: bounded evidence for `SF-0201-002`, `SF-0201-003`, `SF-0201-006`, `SF-0201-008`, `SF-0203-006`, `SF-0203-008`, and `SF-1505-006` through `SF-1505-008`. The normative modules remain Partial where general property editing, interaction authoring, responsive behavior, export, and release acceptance are unproven.
  - Bounded scope: align Inspector navigation with the visual contract while retaining working selection/layout, geometry, guide, snapping, and accessibility summaries; make fresh canonical Frames visibly legible with deterministic surface defaults while retaining editor-only selection context; launch into a normal maximized `NSScreen.visibleFrame` window (menu bar and Dock remain available) and preserve a later user move/resize; retain deterministic constrained Debug/UI-test geometry; and document tiered local feedback versus final full gates. Do not implement property mutation, responsive editing, effects, export, or publishing.
  - Result: Inspector order is Design, Layout, Content, Interactions, Accessibility. Content/Interactions are accessible truthful unavailable destinations with no canonical/history/package mutation. Blank project roots remain structural and nonvisual; the empty canvas offers real named Frame/Text actions. Those actions construct current document/page/revision identity before arming, execute one canonical insertion transaction, and explicitly request identity-gated scene/renderer adoption; Frame/Text, Layers, selection, accessibility, undo/redo, and persistence therefore share the inserted `NodeID` and frame. Fresh Frames store deterministic neutral surface/border defaults; blue outline/context stay editor-only. Canonical world/viewport/device space is top-left/Y-down and the tile boundary is the only Core Graphics text conversion, keeping Frame labels/plain Text upright. Production launch is normal maximized `NSScreen.visibleFrame`, never native full-screen; Debug/UI-test placement remains Release-isolated.
  - Verification: focused chain regression passed 1/1 and asserts availability → committed revision → matching render-plan revision/NodeID → Layers/selection → redacted diagnostic → undo/redo for both Frame and Text. Focused actual-app blank/renderer, material/canvas, and selected-Frame journeys passed 3/3. Final `./sf verify` passed on 2026-08-12 with 297 unit and 32 UI tests (329 total), zero failures; repository, secret, traceability, architecture, migration, evidence, and fixture-hygiene checks passed. Evidence: `docs/evidence/product-ui-003/README.md`.
  - Explicitly deferred: general property editing, interaction authoring, responsive controls, gradients/effects, assets/components workflows, production typography, export/publishing, OS-level VoiceOver/settings acceptance, cross-hardware visual/performance acceptance, and release acceptance.
  - Dependencies: `SF-PRODUCT-UI-002`.

- [x] `SF-PRODUCT-UI-002` Establish product navigation, native menu architecture, and a truthful Elements-pane foundation.
  - Requirements: bounded evidence for `SF-0201-002`, `SF-0201-006`, `SF-0201-008`, `SF-0203-006`, and `SF-1505-006` through `SF-1505-008`. The normative modules remain Partial where later elements, content editing, assets, components, export, and release acceptance are unproven.
  - Result: Pages/Layers remain functional; Elements is a scene-local noncanonical catalogue with stable identities, category/order, icon, keyboard path, availability, and capability contract. Only Frame and plain Text arm the existing verified insertion path. Section, Stack, Grid, Button, Link, Divider, Navbar, Footer, Assets, and Components expose truthful unavailable reasons and cannot mutate canonical document, history, or package state. The native menu names the existing tool group Insert, and the expanded navigator participates in complete forward/reverse keyboard traversal.
  - Verification: focused catalogue plus keyboard/navigator UI journeys passed 3/3. `./sf verify` passed on 2026-08-10 with 291 unit and 30 UI tests (321 total), zero failures; repository, security, traceability, architecture, migration, evidence, and fixture-hygiene checks passed. Evidence: `docs/evidence/product-ui-002/README.md`.
  - Explicitly deferred: actual Section/Stack/Grid/Button/Link/Divider/Navbar/Footer authoring, asset storage/import, component definitions/instances, property editing, responsive behavior, gradients/effects, export, publishing, OS-level VoiceOver/settings acceptance, and release acceptance.

## BLOCKED

- [x] `SF-TEST-HARNESS-001` Investigate intermittent macOS XCTest accessibility-service loss.
  - Scope: non-product verification infrastructure only. The 2026-08-24 documentation-inclusive `./sf verify` retry completed its unit/integration checks, then its UI runner lost the AX service: one journey reported a helper connection loss and seven subsequent fresh app launches reported `Not authorized for performing UI testing actions`. The same product tree had already completed the full UI target 38/38 earlier that day, and the three command-routing regressions passed individually and together (3/3). Treat this as a separate runner authorization/connection issue; do not alter product assertions or command behavior to mask it.
  - Evidence: the retained local `full-34f78057-3015-4113-b4d4-1ddaa4afc560.xcresult` and matching `.log` in the SiteForge test-results root (diagnostic output outside the repository).
  - Resolution: the owner enabled macOS Automation Mode without per-run authentication. A stale `testmanagerd` instance was terminated once, after which focused UI execution and final `./sf verify` completed normally. The 2026-08-25 gate passed all 39 UI tests, so this environment-specific blocker is closed without changing product behavior or weakening assertions.

- [x] `SF-PRODUCT-UI-001` Establish the full-window launch and final-product visual-system foundation.
  - Requirements: bounded evidence for `SF-0201-002`, `SF-0201-003`, `SF-0201-006`, `SF-0201-008`, `SF-1505-006` through `SF-1505-008`, and `SF-1605-002`, `SF-1605-006` through `SF-1605-008`. These normative requirements remain Partial where later authoring, performance, and release acceptance is unproven.
  - Result: welcome, loading, recovery, failure, and workspace share one normal native macOS window. First launch uses `NSScreen.visibleFrame` (menu bar/Dock respected; no full-screen Space); native autosave restores valid user geometry and falls back from malformed/off-screen/under-minimum restoration. Explicit Debug/UI-test edge placement remains higher priority and Release-isolated. `docs/product-ui/VISUAL_CONTRACT.md` defines the native menu, unified chrome, navigation/inspector architecture, material/contrast/focus/spacing rules, and truthful future-capability boundary.
  - Verification: `./sf verify` passed on 2026-08-09 with 290 unit and 29 UI tests, zero failures; repository/security/traceability/architecture/migration/evidence checks passed. `docs/evidence/product-ui-001/README.md` retains the reproducible visual-state review route.
  - Explicitly deferred: Elements/Assets/Components implementation, Content/Interactions editing, gradients/effects, responsive/CMS, export, publishing, release accessibility QA, and final hardware performance budgets.


- [x] `SF-AUTHORING-009` Implement the bounded drag-and-drop authoring foundation.
  - Requirements: `SF-0408-001` through `SF-0408-008` (bounded local reorder/nest/place slice; the normative module remains Partial overall).
  - Acceptance: establish one scene-owned drag session with stable source, destination, insertion-point, document, page, revision, and renderer identities; route the implemented pointer, contextual, named-accessibility, and automation paths through one typed transactional registry; preserve exact preview/commit parity, cancellation and stale-result neutrality, undo/redo, persistence/recovery, deterministic ordering, accessibility, redaction, and bounded scale. External imports, connected resources, cross-project transfer, broad asset-library work, and export generation require separately bounded acceptance.
  - Dependencies: `SF-AUTHORING-004` through `SF-AUTHORING-008`.
  - Plan and result: use the existing canonical `DocumentNode.parent`, `DocumentPage.rootNodeIDs`, and `DocumentNode.childIDs` as the only ownership and ordering representation. `document.node.move` is one atomic command with an exact inverse. The headless registry validates document/page/revision/scene/renderer identities, source/destination availability, frame-only nesting, same-parent insertion-index adjustment, cycles, depth, locks, visibility, lifecycle, cancellation, and revision exhaustion before preparing that command. Scene-owned previews/sessions/payloads/indicators remain noncanonical. The source-level Layers pointer capability provides a bounded same-page “before row” placement, including compatible cross-parent placement; contextual actions, named accessibility actions, and automation provenance use the same registry for supported reorder/nesting. The transfer type is an explicitly declared internal UTI, so generic text/Finder input cannot accidentally become a move.
  - Supported: bounded source-level same-page pointer before-row placement/reorder; registry-backed move into a compatible frame container through contextual/named-accessibility/automation paths; deterministic destination adjustment; exact transaction/history/package behavior; noncanonical preview/session isolation; typed rejection; retained Layers reorder screenshot; reproducible 100-/10,000-node preparation evidence.
  - Explicitly unsupported or unproven: end-to-end native pointer terminal cleanup when a drag exits all rows, native pointer nesting, production keyboard and application-menu drag commands, Finder/external and asset drags, cross-window/project transfer, component ownership, responsive editing, autoscroll beyond the local list, incremental spatial indexing, final interactive frame pacing, OS-level VoiceOver/settings acceptance, cross-hardware budgets, export generation, and release acceptance.
  - Evidence: the 2026-07-31 checkpoint had 6 focused drag model tests and one running-app Layers contextual reorder/undo/redo accessibility journey; the final audit adds model regressions for cross-parent pointer capability, invalid-hover repair, malformed parent cycles, unavailable accessibility feedback, and payload-free diagnostics. The historical complete UI target was 29/29 and `./sf verify` was 248 unit + 29 UI tests, zero failures; final audit totals are recorded in `docs/audits/FINAL_IMPLEMENTATION_AUDIT.md`. `docs/evidence/drag-drop-foundation/` retains raw samples, environment/memory/limitations, and the reviewed screenshot. No next feature item was ready at that checkpoint.

- [x] `SF-CI-006` Stabilize constrained-display text and history pointer journeys.
  - Requirements: bounded regression coverage for `SF-0201-006`, `SF-0201-008`, `SF-0203-006`, `SF-0203-008`, `SF-0405-006`, `SF-0405-008`, `SF-0406-006`, and `SF-1902-008`.
  - Plan: retain the production 1100×700 content minimum and Release placement unchanged; replace the one-axis Debug/UI-test placement request with an explicit horizontal/vertical safe-edge request and a window-local AppKit placement coordinator that reapplies only when the requested window, screen, or frame changes; fit every explicitly placed Debug/UI-test frame to a hosted display whose usable height is shorter than the titled production-minimum frame while retaining the complete requested width and selected safe edges; prove left/right/top/bottom policy, the constrained 1024×737 usable frame, and Release composition isolation; keep the general inline-text journey on its production Command-Return commit path while adding a dedicated bottom-aligned pointer journey that clicks the real status Commit and Cancel controls; retain the existing right-aligned Undo/Redo pointer journey and diagnose its state with stable identifiers, sanitized geometry, history labels/availability, text phase, responder class, and window identity; then repeat both hosted failures with fresh processes, run history/constrained-display regressions, the complete UI target, and authoritative verification before checkpointing and pushing.
  - Hosted evidence: Actions run `30415629157` passed repository/security/architecture/traceability/migration/evidence checks, all 241 unit tests, and 25 of 27 UI tests on macOS 26.4/Xcode 26.5. Its retained hierarchy placed status Commit/Cancel at y 761–777 on a 768-point display. The Redo hierarchy exposed value `Insert Node` without a disabled state, but its x range was 1034–1071 on the 1024-point display; the requested right-edge origin had been constrained back to x 16. These are separate status-bottom and toolbar-right geometry failures, not evidence of stale history.
  - Hosted follow-up: Actions `30572053725` at `dfe78ec` passed all 242 unit tests and 27 of 28 UI tests. Both original `30415629157` failures passed, proving right-edge Redo and the generic keyboard text journey. The new dedicated status-pointer test alone failed: macOS kept the 1100×752 titled frame at y 31, so Commit remained at y 761. The follow-up fits only the bottom-aligned Debug/UI-test frame to the 737-point usable height and leaves production/Release metrics unchanged.
  - Second hosted follow-up: Actions `30575084659` at `21e1b93` passed all 242 unit tests and 24 of 28 UI tests. The initial constrained-height policy had lowered the AppKit minimum for every UI-test placement, allowing ordinary top-aligned windows to shrink to 677 points and destabilizing the large-fixture and Layers/material journeys. Its bottom window frame compressed, but the SwiftUI workspace retained the 700-point content minimum, so the canvas interaction was clipped. The final bounded correction applies the reduced AppKit and SwiftUI minimum only to the explicit bottom-aligned Debug/UI-test composition; top/left/right and Release composition retain 1100×700.
  - Third hosted follow-up: Actions `30578634561` at `a412a69` passed all 242 unit tests and 24 of 28 UI tests. The four failures all used ordinary top placement: the large fixture measured a 677-point frame, and the page/Layers accessibility subtrees became unavailable. The coordinator had cached that already screen-constrained frame as its requested size. It now derives the intended frame once from the requested 1100×700 content size plus the bound window's actual chrome inset, then applies bottom-only fitting afterward.
  - Fourth hosted follow-up: Actions `30581883646` at `b3999f6` passed all 242 unit tests and 25 of 28 UI tests. The intended titled frame was correctly derived, but top-aligned Debug/UI-test composition still retained the production content constraint and asked AppKit for a 752-point frame on a 737-point visible screen. AppKit independently reduced it to 677 points; the large-fixture assertion and two Layers accessibility queries failed from that same truncation. The bounded follow-up now fits every explicit Debug/UI-test vertical placement to the usable display height before AppKit can apply an origin-dependent constraint. Release and non-test composition retain 1100×700.
  - Fifth hosted follow-up: Actions `30584649437` at `9088931` passed all 242 unit tests and 26 of 28 UI tests. Every Layers/material regression passed. The only failures were the minimum and large-fixture journeys retaining a literal 700-point runtime-frame assertion after the explicit Debug/UI-test fit correctly produced 661 points from the hosted 677-point AppKit visible height minus the 16-point safe inset. Those journeys now assert the exact constrained-display threshold from the test runner's native visible frame; production/unit coverage continues to require the unchanged 1100×700 content minimum, and Release/non-test composition cannot use the fit.
  - Local evidence: the final placement contract passed 11/11 focused tests; the five-journey matrix covering all three `30581883646` failures, the earlier page-row regression, and the real bottom Commit/Cancel pointer path passed 15/15 across three fresh-process repetitions; the native-screen minimum and large-fixture journeys passed 6/6 across three fresh-process repetitions; the complete UI target passed 28/28; and authoritative `./sf verify` passed 242 unit plus 28 UI tests with every repository, security, architecture, traceability, migration, and retained-evidence check green. Earlier evidence retained each original `30415629157` failure at 3/3 and 56 command/history/insertion/text unit tests plus six constrained/history UI journeys.
  - Final hosted evidence: Actions run `30599626407` at `94a372b` passed the complete macOS 26.4/Xcode 26.5 gate. The Verify job completed successfully, failure diagnostics were correctly skipped, and `SF-AUTHORING-009` remains the first READY item.

- [x] `SF-AUTHORING-008` Implement the bounded inline plain-text editing foundation.
  - Requirements: `SF-0406-001` through `SF-0406-008` (bounded plain-text editing slice; rich text and production shaping remain later work).
  - Plan: retain the existing versioned `content.text` `NodeProperty` as the sole canonical text source; add a Foundation-only typed edit registry and scene-owned inactive/drafting/previewing/composing/committing/cancelled/failed session keyed by document, page, revision, renderer generation, session, and stable text-node identity; validate node kind, page ownership, visibility, locking, availability, lifecycle, UTF-8/control-input limits, selection/range boundaries, cancellation, and stale identities before compiling one exact `setProperty` transaction and inverse; bridge the native canvas to one AppKit text editor that owns caret, selection, clipboard, newline, and marked-text behavior while its draft/composition remain noncanonical; route pointer, keyboard, menu, contextual, accessibility, and automation activation through the same registry; then prove one-transaction history, Escape restoration, save/reopen/autosave/recovery, renderer/layout/selection adoption, shortcut isolation, accessibility, redaction, and bounded 100-/10,000-object preparation without adding rich text, advanced typography, responsive editing, or export generation.
  - Supported: one native `NSTextView` draft/composition session over a stable plain-text node; pointer double-click, keyboard, menu, contextual, accessibility, and automation activation; native caret, selection, insertion/deletion/replacement, newline, copy/cut/paste, and marked-text semantics; exact UTF-16 range validation and the existing 64-KiB limit; one atomic `content.text` transaction/inverse; exact undo/redo and deterministic package/history round trips; selection, Layers, layout, renderer, hit-test, dirty-region, autosave/recovery, focus, and announcement adoption after commit.
  - Explicitly unsupported: rich-text spans and range styling, font browsing/installation, production shaping/typography, advanced paragraph layout, vertical or path text, responsive text overrides, collaboration, export generation, OS-level IME/VoiceOver acceptance, localization acceptance, incremental indexing, cross-hardware budgets, and release acceptance. Draft text, caret/selection, composition, clipboard state, and editor overlays remain noncanonical and excluded from packages, history, preview, and export-facing snapshots.
  - Evidence: thirteen focused unit/integration tests and one actual-app pointer/keyboard/clipboard/commit/cancel/undo/redo/accessibility journey; headless architecture and nonserialization checks; deterministic package/history coverage; retained native-window draft/commit/cancellation screenshots; and two validated capacity measurements. On Mac16,13 in the Debug test composition, command preparation P95 was 0.819 ms at 100 nodes and 2.419 ms at 10,000 nodes, with 108,314,624-byte resident-memory high water. These measurements exclude native input, layout, rasterization, package I/O, and autosave and are not release budgets.
  - Dependencies: completed after `SF-AUTHORING-005`, `SF-AUTHORING-006`, and `SF-AUTHORING-007`. `SF-AUTHORING-009` is next READY.

- [x] `SF-AUTHORING-007` Implement deterministic snapping, guides, rulers, and measurement foundations.
  - Requirements: `SF-0404-001` through `SF-0404-008` (bounded snapping/measurement slice; the normative module remains Partial overall).
  - Plan: retain `layout.x`, `layout.y`, `layout.width`, and `layout.height` as the only canonical node geometry; extend the versioned canonical document only for explicitly authored page-owned guides with typed stable identity, axis, finite position, provenance, and deterministic order; migrate older schemas to an empty guide collection; add typed atomic create/move/remove guide commands with exact inverses; layer a Foundation-only editor snap resolver over the verified transform preparation boundary using 6-point entry and 9-point exit thresholds, authored-guide → object-edge → object-center priority, axis-independent resolution, stable distance/identity/feature tie-breaking, and previous-winner hysteresis; exclude hidden, clipped, unavailable, cross-page, selected, stale, and incompatible candidates while retaining locked objects as immutable reference geometry; keep candidates, winners, rulers, measurements, suppression, and previews noncanonical; render bounded native overlays and accessibility alternatives; then prove persistence/history/recovery/migration, preview/commit parity, cancellation/stale neutrality, dirty-region isolation, and 100-/10,000-object scale.
  - Supported: deterministic edge, center, and authored-guide snapping for supported move/resize previews; 6/9-point zoom-aware hysteresis; independent axes; stable priority and tie-breaking; native rulers, smart-guide and bounded distance overlays; Option and accessible suppression; stable page-owned horizontal/vertical authored guides; pointer plus keyboard/menu/contextual/accessibility/automation adapters; one atomic guide transaction/inverse; exact undo/redo; deterministic schema-v3 package/history round trips and schema-v2 migration; redacted diagnostics.
  - Explicitly unsupported: text-baseline/glyph and distribution snapping, rotation/skew snapping, responsive breakpoint editing, layout-distribution commands, export generation, incremental spatial indexing, final interactive renderer/frame-pacing acceptance, OS-level VoiceOver/settings acceptance, localization acceptance, cross-hardware budgets, and release acceptance. Snap candidates, winners, measurements, ruler interaction, suppression, and transform previews remain noncanonical.
  - Evidence: six focused unit/integration tests plus one actual-app ruler/guide/suppression/accessibility journey; complete regression suite; headless import and editor-state non-serialization checks; strict schema-v3/schema-v2 migration coverage; retained native window screenshots; and two validated optimized capacity measurements. On Mac16,13, resolver P95 was 0.972 ms at 100 objects and 40.341 ms at 10,000 objects, with 109,428,736-byte resident-memory high water. The 10,000-object bounded full scan exceeds one 60 Hz interval and is not an incremental or release-budget pass.
  - Dependencies: completed after `SF-AUTHORING-006`. `SF-AUTHORING-008` is next READY.

- [x] `SF-AUTHORING-006` Implement deterministic geometry-transform sessions for selected nodes.
  - Requirements: `SF-0403-001` through `SF-0403-008` (bounded move/resize slice; the normative module remains Partial overall).
  - Plan: retain canonical `layout.x`, `layout.y`, `layout.width`, and `layout.height` properties as the only authored geometry source; add a Foundation-only typed transform registry and scene-owned draft/validate/preview/commit session keyed by document, page, revision, renderer generation, session, and stable node identities; compile one compatible ordered selection into one atomic batch command with exact property inverses; route pointer, keyboard, menu, contextual, accessibility, and automation adapters through the same validation; render editor-only move/resize previews and bounded handles through the overlay layer; adopt committed revisions through the existing selection, layout, renderer, hit-test, dirty-region, persistence, autosave/recovery, and history boundaries; retain deterministic 100-/10,000-object measurements, UI evidence, architecture checks, and explicit unsupported semantics.
  - Supported: exact move and eight-handle resize geometry; horizontal/vertical constraints; stable session/document/page/revision/renderer identities; ordered compatible multiple movement with explicit multiple-resize rejection; typed locked/hidden/unavailable/missing/cross-page/stale/invalid failures; pointer, keyboard, menu, contextual, accessibility, inspector numeric, and automation adapters; editor-only previews and native accessible handles; one atomic transaction and inverse; undo/redo and deterministic package/history round trips; selection/Layers/layout/renderer/hit-test/dirty-region adoption; redacted diagnostics.
  - Explicitly unsupported: rotation, skew, snapping, guides, rich-text transforms, responsive breakpoint editing, broad inspector property-system editing, export generation, 10,000-object simultaneous selection, final incremental layout/render performance, OS-level VoiceOver/settings acceptance, and owner-approved release hardware budgets. Transform sessions and previews are noncanonical and non-`Codable`; the current schema-v3 representation keeps the preexisting transform geometry fields unchanged.
  - Evidence: thirteen focused unit/integration tests plus one actual-app pointer/keyboard/numeric/undo/redo/accessibility journey; headless import/typecheck and non-`Codable` enforcement; deterministic package/history and schema-v1 regression coverage; retained native-handle/preview/commit screenshots; and two validated capacity measurements. On Mac16,13, preparation P95 was 0.629 ms in a 100-object project and 28.493 ms in a 10,000-object project, with 110,804,992-byte resident-memory high water. The large result exceeds one 60 Hz interval and is not an incremental or release-budget pass.
  - Dependencies: completed after `SF-AUTHORING-004` and `SF-AUTHORING-005`. `SF-AUTHORING-007` is next READY.

- [x] `SF-CI-005` Make mixed-framework Tab routing window-native.
  - Requirements: bounded regression coverage for `SF-0201-006`, `SF-0201-008`, `SF-0203-006`, `SF-0203-008`, `SF-0602-006`, `SF-1902-006`, and `SF-1902-008`.
  - Plan: replace the escaped SwiftUI-to-AppKit viewport-preset handoff with one scene-owned, window-bound local keyboard router that intercepts only unmodified Tab/Shift-Tab events whose source or destination is the native preset; reject wrong-window, inactive-window, sheet, menu, popover, text-editing, stale, and detached contexts; transfer genuine first responder directly when entering the popup and return through the unchanged `ShellFocusTraversal` when leaving it; remove monitors and observers deterministically; retain sanitized focus/responder/window diagnostics for hosted failures; preserve popup pointer/arrow operation, canvas input, accessibility, and every non-boundary key event; then repeat the complete traversal, run the viewport journey, full UI target, and authoritative verification before checkpointing and pushing.
  - Evidence: Actions run `30213209340` passed 206/206 unit and 23/24 UI tests; its failure hierarchy proved that forward Tab from Not Found wrapped actual AX focus to `navigator.tab.pages` while `canvas.viewport.preset` remained present but unfocused in the main workspace window. The artifact did not retain the AppKit responder class, so this correction adds a Debug/UI-test-only, content-free responder/window/route probe for future failures. Three routing/lifecycle unit tests and the complete 12-test focus/control contract passed; the unchanged full traversal passed 10/10 with a fresh app process per repetition; the dedicated viewport pointer/keyboard/accessibility journey passed; and the complete UI target passed 24/24. Hosted run `30214993143` then proved both mixed-framework boundary directions and failed only when the same journey pointer-clicked offscreen Inspector Accessibility at x=1021 on the approximately 1024-point runner display; the journey now adds actual-focus assertions for the full Layout → Style → Advanced → Accessibility keyboard path instead of relying on that unrelated pointer geometry. Follow-up hosted run `30215756810` passed the complete gate on Xcode 26.5 at `a1328ea`.

- [x] `SF-CI-004` Make viewport-preset focus AppKit-deterministic.
  - Requirements: bounded regression coverage for `SF-0201-006`, `SF-0201-008`, `SF-0203-006`, `SF-0203-008`, `SF-0602-006`, `SF-1902-006`, and `SF-1902-008`.
  - Plan: replace only the viewport-preset SwiftUI menu with a visually equivalent `NSPopUpButton` bridge whose state remains owned by `WorkspaceShellState`; bind real first-responder adoption to a typed scene, window, and request identity so stale or wrong-window requests remain neutral and a relinquished request cannot steal focus back; synchronize native pointer/keyboard focus with the existing `ShellFocusTraversal`, hand Tab and Shift-Tab back to the adjacent SwiftUI controls without changing traversal order, preserve the stable accessibility identifier/label/value, add focused model and running-app regressions, repeat the hosted failure ten times, run the complete UI target and authoritative verification gate, and retain sanitized hosted-failure evidence without changing the production layout or automation boundaries.
  - Evidence: supplied Actions run `30203186204` passed all 203 unit tests and 23 of 24 UI tests, with only the SwiftUI viewport menu failing to adopt the real AppKit first responder after Not Found. The replacement native popup synchronously adopts focus only for the current typed scene/window/request, never reclaims a relinquished request, and uses the unchanged central traversal order. Three focused unit tests passed; the final implementation passed ten consecutive complete forward/reverse traversal runs; the viewport journey passed native pointer and keyboard preset selection plus identifier, label, value, and actual-focus assertions; and the complete UI target passed 24/24. Final `./sf verify` evidence is recorded in project status.

- [x] `SF-CI-003` Stabilize constrained-display history and focus journeys.
  - Requirements: bounded regression coverage for `SF-0201-006`, `SF-0201-008`, `SF-0203-006`, `SF-0203-008`, `SF-0405-006`, `SF-0405-008`, `SF-0602-006`, `SF-1902-006`, and `SF-1902-008`.
  - Plan: keep insertion undo/redo assertions on the production keyboard command path rather than offscreen toolbar geometry; add a dedicated right-aligned pointer journey for the Undo/Redo toolbar controls and verify their safe visible bounds; replace the mixed SwiftUI/AppKit viewport-preset focus boundary with one native SwiftUI menu control inside the scene-owned `ShellFocusTraversal`; retain exact forward/reverse focus assertions including Not Found to viewport preset and the native canvas boundary; attach expected/current focus identifiers, a content/path-redacted accessibility hierarchy, and a screenshot on focus failure; preserve Release isolation and the 1100×700 production layout; repeat both formerly failing journeys five times, run the complete UI target, then run the full verification gate.
  - Evidence: the supplied hosted Xcode 26.5 result passed 203 unit and 21 of 23 UI tests, leaving only an offscreen Redo pointer click in the generic insertion journey and a mixed-framework first-responder handoff after the Not Found row. The insertion journey now uses the production Command-Z/Command-Shift-Z path; a dedicated right-aligned journey inserts through keyboard/pointer input and clicks both toolbar history controls inside the safe edge. The native menu-based viewport selector participates in the same SwiftUI focus system as adjacent controls, while the AppKit canvas explicitly returns Tab traversal to the scene-owned focus model. Both formerly failing journeys passed five consecutive iterations (10/10); the complete UI target passed 24/24. Focus failures retain expected/current identifiers, a content/path-redacted hierarchy, and a screenshot. Final `./sf verify` evidence is recorded in project status.

- [x] `SF-CI-002` Make UI readiness independent of display width.
  - Requirements: bounded regression coverage for `SF-0201-006`, `SF-0201-008`, `SF-0203-006`, `SF-0203-008`, `SF-1505-006`, `SF-1505-008`, `SF-1602-006`, `SF-1602-008`, `SF-1605-006`, `SF-1605-008`, `SF-1902-006`, and `SF-1902-008`.
  - Plan: replace the shared Preview-hittability launch gate with the complete shell's stable accessible readiness boundary; reactivate and predicate-wait for the workspace window after welcome transitions; attach redacted accessibility hierarchy and screenshot diagnostics on readiness failure; preserve the 1100×700 production minimum while adding Debug/UI-test-only deterministic left/right placement for displays narrower than the window; retain Preview-specific keyboard, accessibility, presentation, and pointer coverage; update the official artifact action to its supported Node 24 major; repeat the affected UI regressions three times and run the complete verification gate.
  - Evidence: the supplied GitHub Actions run `30189435425` executed all 202 unit tests successfully and failed fourteen UI journeys at the same shared `toolbar.preview` hittability wait. Its approximately 1024-point test display could not show the far-right Preview control in the intentionally 1100-point-minimum window. The corrected helpers instead wait for the labeled `workspace.shell` root, and failure attachments retain a screenshot plus path-redacted accessibility hierarchy. Sixteen affected/focused UI journeys passed three consecutive runs (48/48) without sleeps; focused unit coverage proves deterministic left/right placement in a simulated 1024-point visible frame, unchanged 1100×700 sizing, and Release composition isolation. Preview retains keyboard/accessibility/presentation coverage and a dedicated pointer journey using right-edge test placement. Final `./sf verify` evidence is recorded in project status.

- [x] `SF-TOOLING-001` Add explicit local test levels for efficient development feedback.
  - Requirements: bounded workflow support for `SF-1902-007` and `SF-1902-008`.
  - Plan: preserve `./sf verify` and bare `./sf test` as full unit/UI gates; add named quick, changed, half, and full levels; map changed production files conservatively to dependent test classes; escalate unknown, project, and orchestration changes to the full suite; self-test the selector during repository verification; and document that narrower levels are feedback rather than completion evidence.
  - Evidence: `scripts/select-test-scope.py --self-test` covers subsystem, UI, direct-test, documentation-only, and full-fallback decisions. `./sf test quick`, `./sf test half`, and authoritative `./sf verify` passed on 2026-07-26; full verification executed 202 unit tests and 21 UI tests with zero failures. `./sf verify` and CI remain unconditionally full.

- [x] `SF-CI-001` Stabilize deterministic macOS UI verification before authoring continues.
  - Requirements: `SF-0201-006`, `SF-0201-008`, `SF-0203-006`, `SF-0203-008`, `SF-1505-006`, `SF-1505-008`, `SF-1602-006`, `SF-1602-008`, `SF-1605-006`, `SF-1605-008`, `SF-1902-006`, and `SF-1902-008`.
  - Plan: preserve the five failed UI journeys as behavioral regressions; make launch/workspace readiness, progress semantics, toolbar hittability, and keyboard-focus transitions observable through stable accessibility state; constrain and center Debug-only UI-test windows within the available screen; terminate every launched test application deterministically; retain Release isolation for all test injection; upgrade supported checkout actions; and preserve the single `./sf verify` pipeline while uploading redacted failure logs and XCTest result bundles for diagnosis.
  - Evidence: GitHub Actions logs for `48b907a` showed five runner-only failures involving an absent indeterminate-progress element, immediate focus reads, and a Preview toolbar control positioned at the runner display edge. The exact five tests passed locally before correction, confirming runner sensitivity, then passed three consecutive focused post-correction runs (15/15) without sleeps or assertion weakening. `./sf build` and `./sf test` passed on 2026-07-26 with 202 unit and 21 UI tests; the final authoritative `./sf verify` result is recorded in project status. CI now records its macOS/Xcode environment and retains the redacted verify log plus `.xcresult` only on failure.

- [x] `SF-AUTHORING-005` Implement transactional insertion foundations for frame and text nodes.
  - Requirements: `SF-0405-001` through `SF-0405-008` (bounded frame/text insertion slice; the normative module remains Partial overall).
  - Plan: retain canonical document schema v2 and represent frame/text geometry, initial style, and bounded plain text through the existing ordered `NodeProperty` model so absence, `.defaulted`, and `.authored` remain distinct; add a Foundation-only typed insertion registry and scene-owned session that validate exact document/page/revision/generation identity, parent ownership/state, order, geometry, depth/node/text limits, cancellation, and lifecycle availability before compiling one atomic document transaction with an exact stable-ID inverse; connect Frame/Text tools, pointer/default keyboard placement, menus, contextual actions, and accessibility to that registry, then adopt committed nodes through the existing selection, Layers, renderer, preview/package/history/autosave/recovery boundaries while previews remain editor-only; add deterministic unit/integration/UI, migration-compatibility, scale/evidence, redaction, and regression coverage without adding transforms, handles, snapping, rich text, inspector editing, or export generation.
  - Supported: stable-ID frame and bounded plain-text insertion at exact ordered root or nested-frame positions; deterministic 240×160 frame and 120×24 `Text` defaults marked `.defaulted`; pointer click/default keyboard, toolbar, menu, contextual, accessibility, and automation adapters through one typed registry; inactive/armed/previewing/committing/cancelled/failed scene-owned sessions; typed identity, ownership, route, lifecycle, generation, geometry, depth/node/text, cancellation, and revision validation; one transaction and inverse; exact undo/redo identity/order/content; successful post-commit selection; active-page Layers/layout/renderer/hit-test updates; deterministic package/history round trips and schema-v1 compatibility through the existing migration adapter; redacted diagnostics and optimized capacity evidence.
  - Explicitly unsupported: drag-to-create, production typography/shaping or editable rich text, transforms, resize handles, snapping/guides, media/components, inspector property editing, responsive breakpoint editing, effects/animation, export generation, publishing/plugins, release signing, incremental layout indexes, interactive frame-pacing acceptance, cross-hardware budgets, and OS-level VoiceOver/settings acceptance. The editor-only preview is neither canonical nor serialized, and schema v2 did not require a format change.
  - Evidence: 11 focused unit/integration tests and one actual-app UI journey cover deterministic defaults/provenance, all input paths, disabled and invalid states, cancellation, exact inverse/history behavior, package round trip, editor-session isolation, post-commit selection/undo repair, layout/render/hit-test/dirty regions, diagnostics, stable Layers rows, and 100-/10,000-object capacity. Retained Mac16,13 measurements record insertion-command P95 of 0.756/44.961 ms, layout P95 of 0.897/68.002 ms, and renderer preparation P95 of 1.289/93.654 ms at 100/10,000 objects, with 159,596,544-byte resident-memory high water, raw samples, methodology, environment, and limitations. Running-app screenshots for inserted frame, inserted text, and cancelled preview remain in the XCTest result. The 10,000-object layout/render results exceed one 60 Hz interval and do not prove final interactive or incremental performance.
  - Dependencies: completed after `SF-AUTHORING-004`, using the canonical command/persistence, layout, renderer, and selection foundations. `SF-AUTHORING-006` is next READY.

- [x] `SF-AUTHORING-004` Implement the deterministic selection model and renderer-overlay integration.
  - Requirements: `SF-0402-001` through `SF-0402-008` (bounded selection slice; the normative module remains Partial overall).
  - Plan: add a Foundation-only, scene/window-owned selection snapshot and central typed registry keyed by stable `NodeID`, exact renderer identity, active page/container scope, ordered identities, primary/anchor identity, and provenance; define replacement/add/toggle/clear/traversal/Escape semantics, typed availability and state-neutral rejection, and deterministic lifecycle repair without adding `Codable`, document commands, history, or package members; plan selection-only old/new overlay invalidation separately from authored render plans and connect the existing AppKit viewport, Layers navigator, inspector/status summaries, menu/contextual/keyboard/accessibility paths through that one registry; retain 100-/10,000-object timing/memory evidence and running-app empty/single/multiple visual evidence while keeping transforms, insertion, inspector editing, export generation, and release budgets explicitly outside the slice.
  - Supported: stable ordered single/multiple selection with primary and anchor identity; replacement, Shift-add, Command-toggle, clear, Escape, and cyclic next/previous traversal; exact renderer-generation adoption; document/page/save/reopen/autosave/recovery/undo/redo repair; hidden/clipped/unavailable rejection; locked inspection selection; reverse-paint-order pointer hits; synchronized canvas/Layers/inspector/status/menu/contextual/accessibility adapters; primary/secondary editor outlines; bounded old/new overlay invalidation; noncanonical, undo-neutral selection.
  - Explicitly unsupported: authored selection persistence, marquee, component drill-in UI, insertion, transforms, handles, snapping/guides, inspector editing, text shaping, image decoding, component authoring, export generation, publishing/plugins, interactive Instruments budgets, and OS-level VoiceOver/settings acceptance.
  - Evidence: eight `SelectionModelTests`, one actual-app UI journey with retained empty/single/multiple screenshots, headless architecture enforcement, and four retained optimized measurements cover identity/order, command parity, invalid/stale/cancelled inputs, lifecycle repair, canonical/history/preview/export exclusion, overlay isolation, diagnostics, and 100-/10,000-object scale. On Mac16,13, selection-command P95 was 0.073/3.803 ms and overlay-planning P95 was 0.014/0.958 ms at 100/10,000 objects; process high-water memory was 61,177,856 bytes. These are capacity measurements, not final incremental or release-budget acceptance. `./sf build`, `./sf test`, and `./sf verify` passed on 2026-07-21 with 191 unit tests and 20 UI tests, zero failures.
  - Dependencies: completed after `SF-AUTHORING-003`; follows ADR-0014. `SF-AUTHORING-005` is complete and `SF-AUTHORING-006` is next READY.

- [x] `SF-AUTHORING-003` Implement the AppKit/Core Animation canvas renderer and editor-overlay boundary.
  - Requirements: `SF-0407-001` through `SF-0407-008` (bounded renderer slice; the normative module remains Partial overall).
  - Plan: define a Foundation-only immutable render-scene contract with typed object/surface/overlay/accessibility/request identities, deterministic paint and clip rules, reverse-order hit testing, bounded tiling/cache/virtualization, dirty-region diffing, compositor-only viewport updates, typed failures, cancellation, exact adoption gates, and redacted diagnostics; adapt the existing AppKit viewport to bounded Core Animation content-tile and editor-overlay containers while keeping SwiftUI as chrome and keeping preview/export inputs structurally overlay-free; exercise the real running surface plus 100-/10,000-object fixtures, retain named-environment timing/memory/frame/stall and visual-inspection evidence, and preserve later canonical editing, selection, export generation, and Metal work as explicit exclusions.
  - Supported: immutable document/revision/scene/scene-generation/viewport-generation/scale-tagged scenes; stable object/surface/overlay/accessibility identities; deterministic paint order; visibility and clipping; reverse paint-order hit testing; bounded 512-device-pixel tile membership; two-generation/96-MiB cache policy; 256-element visible accessibility virtualization; old/new dirty regions; compositor-only pan/zoom; Retina scale invalidation; separate authored and editor Core Animation trees; overlay-free preview snapshots; cancellation, typed failure, exact stale adoption, last-valid display preservation, keyboard/pointer focus, native-material pass-through, and redacted diagnostics.
  - Explicitly unsupported: canonical render-pass properties or history, element selection/editing, insertion, transforms, snapping/guides, inspector mutations, text shaping, image/resource decoding, effects, export generation, Metal, offscreen accessibility navigation policy, and owner-approved release budgets. The 10,000-object full/dirty planner exceeds one 60 Hz interval and therefore remains a later incremental-indexing optimization.
  - Evidence: 11 `CanvasRendererTests`, one actual-app UI renderer journey, headless architecture enforcement, and schema-v1 retained evidence cover deterministic rendering/hit-test/overlay/accessibility separation, focus preservation and deterministic repair, invalid/cancelled/stale inputs, cache/tile/virtualization bounds, main-actor responsiveness, 100-/10,000-object scale, raw timing/memory, and an idle display-link cadence probe. P95 was 1.084/75.980 ms for full 100/10,000-object plans, 1.172/113.634 ms for one-object dirty plans, and 0.001/0.107 ms for hit tests; all 10,000-object planning samples missed 16.67 ms. `./sf build`, `./sf test`, and `./sf verify` passed on 2026-07-21 with 183 unit tests and 19 UI tests, zero failures.
  - Dependencies: completed after `SF-AUTHORING-001` and `SF-AUTHORING-002`; follows ADR-0014. `SF-AUTHORING-004` is next READY.

- [x] `SF-AUTHORING-002` Implement the deterministic layout-engine foundation subset.
  - Requirements: `SF-0501-001` through `SF-0501-008` (bounded engine slice; the requirements remain Partial overall).
  - Plan: add a Foundation-only production layout snapshot and engine keyed by canonical typed identities; validate the complete bounded graph before computing immutable revision/generation/viewport-tagged frames and provenance; define exact fixed/intrinsic/fill, constraints, stack, nesting, alignment, gap, padding, overflow, and responsive-width rules with explicit unsupported cases and resource limits; isolate deterministic intrinsic measurements and HTML/CSS browser-oracle adapters from canonical state; exercise cancellation, stale adoption, diagnostics, repeated determinism, 100-/10,000-node scale, and representative browser parity; retain named-environment measurements and enforce the headless dependency boundary without integrating renderer, editor, or inspector behavior.
  - Supported semantics: fixed, immutable-catalog intrinsic, and fill sizing; min/max constraints with recorded provenance; nonnegative padding and gap; start/center/end/stretch cross-axis alignment; horizontal and vertical stacks; bounded nesting; visible and clip overflow; deterministic child order; and responsive containing-block widths. Rooted graph validation rejects duplicates, missing nodes, multiple parents, cycles, orphans, excessive depth/count, nonfinite values, contradictory constraints, missing intrinsic measurements, arithmetic overflow, cancellation, and stale document/revision/generation/viewport identity.
  - Explicitly unsupported: percentage and automatic sizing, baseline alignment, scrolling overflow, children without a stack axis, platform text shaping/fallback, CSS grid, absolute positioning, wrapping, transforms, and browser-specific fallback behavior. Unsupported values return typed errors and are never approximated.
  - Evidence: 11 `LayoutEngineTests` cover stable serialization/identity, exact frames and provenance, fixed/intrinsic/fill, min/max, padding, gap, alignment, both stack axes, nesting, overflow, responsive widths, graph/schema/value rejection, cancellation, stale revision/generation adoption, actor responsiveness, diagnostics redaction, repeated digests, and 100-/10,000-node fixtures. `scripts/check-architecture-boundaries.py` type-checks the production core headlessly with no SwiftUI, AppKit, WebKit, or Metal imports. Retained optimized evidence on Mac16,13 records 0.232 ms production P95 at 100 nodes and 22.290 ms at 10,000 nodes, raw samples and memory, exact WebKit-oracle geometry parity at widths 320/768/1,440 and for both scale fixtures, plus stable digests/cancellation/stale gates. The 10,000-node result exceeds one 60 Hz interval and is not a renderer, incremental-layout, or release-budget pass. `./sf build`, `./sf test`, and `./sf verify` passed on 2026-07-21 with 172 unit tests and 18 UI tests, zero failures.
  - Dependencies: completed after `SF-AUTHORING-001`; follows ADR-0013. Canonical layout-property commands/persistence, inspector/accessibility UI, production text shaping, renderer integration, incremental layout, preview/export UI, and owner-approved hardware budgets remain later work.

- [x] `SF-AUTHORING-001` Implement the deterministic canvas coordinate system and viewport.
  - Requirements: `SF-0401-001` through `SF-0401-008` (bounded viewport slice; canonical authored world-point editing remains Partial).
  - Plan: introduce Foundation-only phantom-typed world/viewport/device geometry and deterministic transform rules; keep one scene-owned viewport outside canonical project content; route zoom/reset/fit/pan through a typed registry; host native AppKit pointer, magnification, keyboard, drawing, focus, and accessibility semantics inside the existing SwiftUI shell; prepare immutable revision/generation-tagged scene inputs in an actor; reject cancellation and stale adoption; exercise scale, precision, fit, resize, lifecycle, accessibility, and 100-/10,000-object boundaries without adding layout, editing, selection, overlays, or a production renderer.
  - Evidence: `CanvasViewportTests` provides 11 deterministic tests for typed conversion, invalid/overflow input, Retina scales, cursor anchoring from 25–800%, bounded pan, resize, reset/fit, 10,000 repeated conversions, per-window ownership, document/revision/scene/generation identity, cancellation/stale adoption, accessibility announcements, redacted diagnostics, and deterministic 100-/10,000-object preparation. UI coverage exercises native commands, values/actions, bidirectional focus, minimum layout, material/appearance compatibility, and launch/loading regressions. `scripts/check-architecture-boundaries.py` headlessly type-checks the production viewport with no UI-framework import. `./sf verify` passed on 2026-07-21 with 161 unit tests and 18 UI tests, zero failures. Retained inspection records default/minimum sizes, 100%/125% zoom, positive/negative pan, light/dark, Retina scale, Reduce Motion, and active/inactive policy states.
  - Dependencies: completed after `SF-AUTHORING-000`; follows ADR-0014. Renderer, layout, hit testing, editor overlays, selection, insertion, snapping, transforms, and export remain outside this item.

- [x] `SF-AUTHORING-000` Produce the missing measured authoring-engine architecture runway and resolve `OD-004`/`OD-011`.
  - Severity: `P1` prerequisite gap (`M0-P1-07`).
  - Requirements: `SF-1901-001` through `SF-1901-008`; bounded downstream evidence for `SF-0401-001` through `SF-0401-008`, `SF-0407-001` through `SF-0407-008`, `SF-0501-001` through `SF-0501-008`, and `SF-1903-001` through `SF-1903-008`.
  - Plan: keep all experiments outside the production application; build a Foundation-only typed coordinate/layout core with deterministic 100-/10,000-object fixtures, cancellation and stale-result seams, then compare real SwiftUI rasterization, AppKit drawing, Core Animation layers, and bounded Metal command/buffer work in a standalone macOS harness; use isolated WebKit only as an exported HTML/CSS geometry oracle; benchmark the existing resource-index-v1 store independently with 500 non-empty assets; retain raw JSON, environment, methodology, commands, percentiles, memory/stall limitations, and a concise comparison; record OD-004/OD-011 in separate ADRs, reconcile bounded evidence, and queue three production slices without implementing them.
  - Evidence: `./sf verify` passed on 2026-07-21 with 150 unit tests and 17 UI tests, zero failures. The reproducible optimized harness retained 25 raw measurement series plus environment and correctness records. On the named Mac16,13 run, AppKit dirty raster and Core Animation incremental transactions stayed below 0.11 ms P95 at 10,000 objects while full AppKit/Core Animation rasters crossed the 16.67 ms reference interval and SwiftUI Canvas full reraster reached 36.574 ms P95. The deterministic layout subset measured 2.657 ms P95 at 10,000 nodes and matched exported WebKit geometry exactly on the retained fixtures; the real resource store exercised 500 non-empty assets. Five focused unit tests cover coordinates, layout, cancellation/stale results, invalid/unsupported semantics, hit testing, and overlay isolation. `docs/evidence/authoring-engine-runway/` retains raw samples, method, commands, environment, memory fields, and limitations. ADR-0013 resolves OD-004; ADR-0014 resolves OD-011.
  - Dependencies: completed after `SF-CORRECTION-001` through `SF-CORRECTION-008`; no production authoring implementation is included.

- [x] `SF-CORRECTION-008` Close the residual accessibility, stable-row identity, repository scanning, asset-capacity, and fixture-hygiene findings.
  - Severity: residual `P2`/`P3` work (`M0-P2-03`, `M0-P2-08`, `M0-P2-11`, `M0-P2-12`, `M0-P3-01`, and `M0-P3-02`).
  - Requirements: `SF-0201-006`, `SF-0202-006`, `SF-0202-008`, `SF-0303-001`, `SF-0303-006`, `SF-0303-008`, `SF-0407-007`, `SF-0501-007`, `SF-1505-006`, `SF-1601-007`, `SF-1602-006`, `SF-1605-006`, `SF-1702-008`, `SF-1901-007`, `SF-1903-007`, and `SF-2002-008`.
  - Acceptance: complete forward/reverse keyboard traversal and retained accessibility evidence; PageID-derived stable row identifiers; repository-wide credential/artifact scanning with safe exclusions; a versioned secure resource-capacity decision and representative 500-asset fixture without weakening package limits; one native open-panel path; and centralized, residue-free test-fixture construction.
  - Plan: define one deterministic forward/reverse shell focus order with PageID-derived navigator-row identifiers and role exposed independently; consolidate native project selection behind one panel adapter and retain truthful accessibility inspection evidence; add a redacting repository scanner with runtime-assembled synthetic positives and a safe tracked negative fixture to local and CI verification; introduce a versioned deterministic resource index plus immutable content-addressed sidecar blobs so a realistic 500-asset project remains portable without relaxing the package control-plane bounds; centralize repository-local XCTest fixture allocation/cleanup and verify residue handling; then run the complete verification suite and reconcile every residual audit row and requirement-evidence claim.
  - Evidence: `./sf verify` passed on 2026-07-19 with 145 unit tests and 17 UI tests, zero failures. Behavioral tests prove complete forward/reverse pane traversal, shortcuts, Escape/default actions, Preview focus restoration, scene-local focus, stable PageID-derived row identity and separate role semantics. Seven resource tests exercise 500 non-empty 32-KiB assets, deterministic index/package round trips, legacy no-index compatibility, bounded streamed validation, one-resource lazy read, cancellation, restrictive store/blob/link metadata, recovery, version/capacity/metadata rejection, and missing/corrupt resource preservation without changing the control package. Repository verification exercises eight runtime-assembled synthetic patterns across seven credential categories plus four sensitive-name policies, leaves no contiguous positive value tracked, proves private temporary-fixture cleanup on success/failure/interruption, produces zero negative/binary-fixture findings, and keeps the production scan clean; it also proves singular Open-panel ownership, headless resource compilation, and centralized fixture construction. ADR-0012 records the versioned resource boundary; retained accessibility evidence names the real environment, settings, observations, and limitations without claiming VoiceOver speech or OS-setting exercise that did not occur.
  - Dependencies: completed after `SF-CORRECTION-007`; `SF-AUTHORING-000` is now first READY.

- [x] `SF-CORRECTION-007` Establish enforceable core, command, persistence, and application test seams before authoring growth.
  - Severity: necessary `P2` architecture correction (`M0-P2-06` and `M0-P2-07`).
  - Requirements: `SF-1801-001`, `SF-1801-002`, `SF-1801-003`, `SF-1801-004`, `SF-1801-008`, and `SF-1802-008`.
  - Acceptance: headless canonical model/command and persistence boundaries build without SwiftUI/AppKit; dependency direction is checked; each document window owns its own lifecycle/session state; test scenarios, large fixtures, and appearance overrides are injected only through an explicit Debug/test composition seam and are ignored by Release builds.
  - Plan: replace the app-global shell/lifecycle objects with one scene-owned `WorkspaceDocumentContext` per native window and route menu commands through the focused window; centralize fixture, preview, recovery, appearance, window-size, and modified-document arguments behind a Debug-only composition policy whose Release resolution is always production-default; define explicit Core and Persistence source slices that typecheck headlessly without SwiftUI/AppKit and add repository checks for allowed imports, dependency direction, cycles, scene ownership, and Release isolation; add two-context behavioral isolation plus Debug/Release composition tests; retain the production loader and native UI smoke journeys; then update bounded SF-1801/SF-1802 evidence and record the lasting ownership/dependency decision in an ADR.
  - Evidence: `./sf verify` passed on 2026-07-19 with 136 unit tests and 16 UI tests, zero failures. Three focused tests prove independent scene canonical/lifecycle identity and convenience state, enabled Debug injection, and disabled/Release override rejection. Repository verification independently type-checks the canonical model and command/persistence engine without UI frameworks, rejects forbidden imports and direct argument bypasses, and checks scene ownership/Xcode membership. Retained UI journeys exercise the same centralized Debug composition. ADR-0011 records the ownership and source-slice boundary.
  - Dependencies: completed before the first production Milestone 1 authoring slice.

- [x] `SF-CORRECTION-006` Reconcile requirement/decision traceability and replace overstated evidence with reproducible proof.
  - Severity: `P1` (`M0-P1-08` through `M0-P1-10`) plus necessary evidence corrections (`M0-P2-01` through `M0-P2-03`, `M0-P2-05`, `M0-P2-09`, and `M0-P2-13`).
  - Requirements: `SF-0201-006` through `SF-0201-008`; `SF-0301-006` through `SF-0301-008`; `SF-0303-003`, `SF-0303-006`, `SF-0303-008`; `SF-1505-006` through `SF-1505-008`; `SF-1602-006` through `SF-1602-008`; `SF-1605-002`, `SF-1605-006` through `SF-1605-008`; `SF-1902-002`, `SF-1902-003`, `SF-1902-007`, `SF-1902-008`; and `SF-2002-001`, `SF-2002-003`, `SF-2002-008`.
  - Acceptance: the specification and project records use one non-colliding decision namespace; requirement rows distinguish bounded implementation from full requirement verification; Milestone 0 aggregate status reflects unresolved acceptance criteria; evidence maps to named behavioral tests or retained manual/measurement records; preview-state, metadata, and policy tests are labeled at their actual scope.
  - Evidence and tests required: a machine-checkable traceability index; real end-to-end launch/recovery UI journeys; complete keyboard/focus and accessibility-announcement coverage; retained visual-inspection manifests; named-environment performance methodology with warm-up, repetition, percentiles, frame/stall and memory measures; repository checks that reject unknown or unsubstantiated completed IDs.
  - Plan: restore the specification's canonical `OD-001…OD-011` meanings, move the two release-only questions to new non-colliding IDs, and link persistence to its resolving ADR; replace aggregate/full-requirement Verified claims with bounded statuses and explicit uncovered acceptance criteria; add cooperative cancellation checkpoints inside package parsing, canonical validation, and persisted-history validation with deterministic barrier tests; instrument every lifecycle intent across success, failure, and cancellation with redacted identities; add production-flow UI/accessibility coverage and a retained visual-inspection manifest; create one machine-readable requirement-to-named-test/artifact index plus a repository lint that rejects unknown IDs, missing evidence, conflicting decisions, and unsupported Verified claims; and capture repeatable named-environment foundation measurements while explicitly reserving renderer/object/asset claims for `SF-AUTHORING-000` and preserving the 8-MiB package security limit.
  - Dependencies: completed after corrections 001–005; full `./sf verify` passes with 133 unit and 16 UI tests.

- [x] `SF-CORRECTION-005` Implement and verify the real macOS file-access security boundary before claiming `SF-1504` Verified.
  - Severity: `P1` (`M0-P1-05`) and the remaining security-scope/coordination portion of `M0-P1-06`.
  - Requirements: `SF-1504-001` through `SF-1504-008`, plus `SF-1603-004`.
  - Plan: introduce one actor-isolated file-access service above the identity-bound package store; configure the unsigned Release candidate for App Sandbox, user-selected read/write, and app-scoped bookmarks while leaving local Debug/XCTest credential-free; persist versioned bookmarks in restrictive app-owned storage; resolve and repair stale or relocated bookmarks; balance every security-scope lifetime around off-main `NSFileCoordinator` access; register a native file presenter for move/change/delete events; route panel-selected open/save and subsequent reopen/revert/save through that boundary; declare the SiteForge package type; add real Foundation bookmark round trips plus deterministic injected denial/stale/relocation/coordination/lifetime/redaction/lifecycle tests; and downgrade full SF-1504 release verification until an owner-approved signed distribution configuration is exercised.
  - Evidence: `./sf verify` passed on 2026-07-19 with 129 unit tests and 14 UI tests. Ten new tests exercise a real Foundation security-scoped bookmark across service recreation; parent-scoped creation and relaunch of a newly saved project; restrictive bookmark-store permissions; stale repair and relocation; balanced scope success, denial, and coordinated failure; lifecycle selected-open/relaunch; `NSFilePresenter` change/move/delete behavior; exact canonical preservation during external change/relocation; entitlement and project-type declarations; and redacted diagnostics. Retained lifecycle, identity-bound filesystem, native panel, keyboard, and accessibility tests remain green. Release build settings declare App Sandbox, user-selected read/write, and app-scoped bookmarks while distribution signing remains disabled. ADR-0010 records the boundary and its portability/release limits.
  - Status boundary: the correction fixes the audit's absent implementation and overclaim by classifying the bounded local file-access slice as Verified, while the complete generated `SF-1504-001…008` module acceptance and signed sandboxed distribution exercise remain Implemented/Not fully Verified pending later external-asset authoring scope and owner-approved distribution configuration.
  - Dependencies: owner-approved publisher/trust configuration is still required before final distributed-build verification; no credential or signing action was taken.

- [x] `SF-CORRECTION-004` Harden current-schema decoding, revision bounds, and historical migration evidence.
  - Severity: `P1` (`M0-P1-04`) with necessary migration evidence from `M0-P2-05`.
  - Requirements: `SF-0301-004`, `SF-0301-005`, `SF-0303-005`, `SF-0303-008`, `SF-0307-004`, `SF-1702-004`, `SF-1702-008`, `SF-1902-004`, and `SF-1902-008`.
  - Plan: make schema v2 decode through strict current DTOs with every canonical field required; isolate schema-v1 decoding and deterministic empty/rootless migration in an explicit legacy adapter; reserve the terminal revision and use checked command arithmetic with a typed non-mutating exhaustion failure; add immutable tracked schema-v1 empty/rootless golden packages with provenance and checksums; then prove strict rejection, deterministic identities, save/reopen, history isolation, revision boundaries, and unchanged lifecycle state before updating compatibility evidence.
  - Evidence: `./sf verify` passed on 2026-07-19 with 119 unit tests and 14 UI tests. Current schema v3 rejects absent creation/template/page/node/guide metadata and unexpected current keys, plus empty and rootless current pages. The schema-v2 adapter adds only an empty guide collection, while a schema-v1-only adapter migrates two immutable package-v1 golden fixtures whose decoded SHA-256 checksums are retained beside their Base64 bytes; tests prove exact project/document/page/root identities, approved structure, invalid legacy variants, deterministic save/reopen, and clean missing-history isolation. Maximum and near-maximum revision tests prove typed exhaustion, checked arithmetic, exact committed-state preservation, and retained undo/redo state without overflow. ADR-0009 records the strict schema and terminal-revision boundary.
  - Dependencies: none.

- [x] `SF-CORRECTION-003` Scope asynchronous lifecycle work by document epoch, destination, revision, and intent.
  - Severity: `P1` (`M0-P1-01` and `M0-P1-02`) plus the related autosave-coalescing portion of `M0-P2-04`.
  - Requirements: `SF-0301-002`, `SF-0301-004`, `SF-0301-005`; `SF-0306-003`, `SF-0306-004`, `SF-0306-005`; `SF-1504-004`; and `SF-1902-004`.
  - Plan: assign every asynchronous lifecycle operation a typed intent and immutable identity containing epoch, operation ID, document/project identity, canonical revision, and sanitized destination identity; advance the epoch and cancel or drain prior read/save/autosave/recovery work at every document-adoption boundary; make stale success, failure, and cancellation state-neutral; serialize manual saves after deterministically draining autosave; preserve a captured durable revision when edits occur during Save while keeping the newer active revision modified and recoverable; and prove exact state, disk, write-count, and revision ordering with injected debouncers and actor barriers.
  - Evidence: `./sf verify` passed on 2026-07-19 with 115 unit tests and 14 UI tests. Eleven new deterministic lifecycle race tests cover Save and executing autosave crossed with New, Open, Revert, Restore, and Close; pending and executing autosave followed by Save; exact burst coalescing and separated revision order; edit during Save; Save As during pending autosave; stale successful and failed completions; cancellation before preparation and before filesystem commit; complete operation identity; and diagnostic redaction. Existing autosave/recovery integration tests now use the injected debouncer rather than wall-clock sleeps. ADR-0008 records the lifecycle epoch and intent boundary.
  - Dependencies: `SF-CORRECTION-002` supplies the retained identity-bound conditional filesystem commit.

- [x] `SF-CORRECTION-002` Make package reads, conditional replacement, and recovery artifacts one identity-bound filesystem boundary.
  - Severity: `P0` (`M0-P0-02` through `M0-P0-04`) plus the filesystem portion of `M0-P1-06`, bounded-fingerprint correction `M0-P2-10`, and recovery-state correction `M0-P2-14`.
  - Requirements: `SF-0301-004`, `SF-0301-005`, `SF-0306-003`, `SF-0306-004`, `SF-1504-003`, `SF-1504-004`, `SF-1603-004`, `SF-1604-004`, and `SF-1702-004`; supporting diagnostic/accessibility evidence also maps to `SF-0301-007`, `SF-0306-006`, `SF-0306-008`, `SF-1504-007`, and `SF-1603-007`.
  - Plan: introduce one no-follow descriptor-based package I/O boundary that returns validated bytes, digest, bounded metadata, and stable device/inode identity from one read; stage deterministic bytes with secure metadata and conditionally commit by exclusive create or atomic swap plus post-swap identity verification and rollback; preserve current ownership, mode, extended ACL, and an explicit approved-xattr allowlist without broadening new-file permissions; validate app-owned recovery directory/file ownership before replacement or deletion; retain typed candidate state when deletion fails; and prove source, destination, inode, symlink, ancestor, size, sparse-file, metadata, collision, deletion, interruption, and unchanged-state behavior with controllable asynchronous checkpoints.
  - Evidence: `./sf verify` passed on 2026-07-19 with 104 unit tests and 14 UI tests. Eleven new barrier-controlled unit/integration tests use no timing sleeps and cover a source replaced by a symlink after snapshot capture; destination replacement; delete/recreate with identical bytes and a new inode; destination and ancestor symlink swaps; same-inode external writes before commit and after atomic swap; rollback of a changed displaced object; oversized sparse files; hard links and owner policy; mode, extended ACL, and approved-xattr preservation; mismatched and malformed recovery collisions; deletion failure with retained candidate and successful retry; and exact canonical/disk preservation after a lifecycle conflict. Existing interrupted-write and static-symlink tests remain green. ADR-0007 records the identity-bound commit and metadata policy.
  - Dependencies: none. Completed before another lifecycle or persistence feature.

- [x] `SF-CORRECTION-001` Guard every destructive document transition and recover untitled work.
  - Severity: `P0` (`M0-P0-01`) with the related untitled-recovery gap (`M0-P1-03`).
  - Requirements: `SF-0203-004`, `SF-0203-005`, `SF-0203-006`; `SF-0301-004`, `SF-0301-005`, `SF-0301-006`; `SF-0306-004`, `SF-0306-005`, `SF-0306-006`; `SF-1902-004`, `SF-1902-005`, and `SF-1902-006`.
  - Plan: centralize New, Open, Revert, recovery Restore, and Close behind one asynchronous Save/Discard/Cancel authorization boundary; inject the native save destination so cancellation and failure are deterministic in tests; preserve a complete lifecycle snapshot until authorization and incoming validation succeed; store both titled and untitled autosave candidates in an app-owned recovery directory keyed by stable project identity; discover valid untitled candidates on launch; expose one keyboard- and VoiceOver-operable native prompt; and verify every decision branch, relaunch recovery, cleanup, and exact-state preservation before updating evidence.
  - Evidence: `./sf verify` passed on 2026-07-19 with 93 unit tests and 14 UI tests. Five new lifecycle tests cover exact-state cancellation for New/Open/Revert/Close, Save/Discard/save-panel-cancel decisions, save failure with separate actionable reporting, recovery-restore cancellation, and app-owned untitled recovery across relaunch/restore/durable-save/discard. The native UI journey verifies stable accessibility identifiers, keyboard Escape cancellation, Return default Save, native save-panel cancellation, and destructive discard. All production document replacements now use the shared authorization boundary; recovery artifacts are stored under Application Support by stable project identity rather than beside user projects. UI recovery tests use isolated repository-local fixture directories, and the test command removes the exact shared fixture root on success, failure, or interruption.
  - Dependencies: none. Completed before other production corrections.

- [x] `SF-FOUNDATION-009` Replace opaque workspace chrome with native translucent materials.
  - Requirements: `SF-0201-002`, `SF-0201-003`, `SF-0201-006`, `SF-0201-007`, `SF-0201-008`; `SF-1505-006`, `SF-1505-007`, `SF-1505-008`; `SF-1605-002`, `SF-1605-006`, `SF-1605-007`, and `SF-1605-008`.
  - Acceptance: the navigator, inspector, toolbar/title-bar, and status surfaces use native macOS translucent/glass materials that visibly reveal appropriate canvas content behind them while preserving region boundaries and native window behavior; Reduce Transparency selects an intentional opaque fallback, increased-contrast and appearance modes retain legible text/icons and non-color-only state, keyboard focus and VoiceOver semantics remain intact, minimum-window layouts do not clip, and standard/large fixtures demonstrate responsive scrolling, resizing, and canvas interaction without material-rendering regressions.
  - Dependencies: `SF-FOUNDATION-008` is verified; launch/loading and workspace surfaces now share the same resolved appearance and fallback policy.
  - Plan: define one semantic material policy for title bar, navigator, inspector, viewport, status, recovery, and launch regions; render it through pass-through native `NSVisualEffectView` surfaces and the unified macOS toolbar; resolve Reduce Transparency, increased contrast, appearance, and active-window state centrally; keep canvas interaction independent; add responsive minimum-size layout plus standard/10,000-page fixtures; and verify policy, accessibility, focus, hit testing, scrolling, appearance, performance, and launch/loading regressions.
  - Evidence: `./sf verify` passed on 2026-07-19 with 88 unit tests and 13 UI tests, all with zero failures. Nine focused material tests verify exact requirement mapping, deterministic region/material selection, opaque fallback, stronger increased-contrast boundaries, native light/dark appearance behavior, inactive-window de-emphasis, valid resized/minimum layouts, UI-only canvas interaction, and 10,000-resolution/10,000-page performance budgets (0.011 seconds in the verification run). UI coverage verifies default and minimum layouts, keyboard and VoiceOver semantics, material pass-through canvas hit testing, navigator switching, scrolling a 10,000-page fixture, light/dark/Reduce Transparency/increased-contrast/inactive states, and every launch/loading state under the opaque fallback. Retained screenshots and the launched app were inspected for default/minimum sizing, all appearance/accessibility states, and standard/large fixtures; an initially bright dark-mode toolbar backing and clipped minimum-size canvas copy were found and corrected. Diff review found no generated products, machine paths, credentials, signing changes, publication actions, or unrelated canvas/publishing/plugin scope.

- [x] `SF-FOUNDATION-008` Implement the approved SiteForge launch and project-loading experience.
  - Requirements: `SF-0201-004`, `SF-0201-006`, `SF-0201-007`, `SF-0201-008`; `SF-0301-002`, `SF-0301-004`, `SF-0301-006`, `SF-0301-007`, `SF-0301-008`; `SF-1602-004`, `SF-1602-006`, `SF-1602-007`, and `SF-1602-008`.
  - Acceptance: launch and project-open operations match the approved visual specification and expose intentional initial, determinate/indeterminate progress, current-operation status, safely cancelable, non-cancelable, failure, and recovery states; cancellation or failure preserves the last valid project and presents a specific next action; material state changes are announced accessibly, keyboard focus remains operable, Reduce Motion is respected, and loading work remains off the main actor without UI stalls; automated and manual evidence cover state transitions, recovery, diagnostics, and representative performance.
  - Dependencies: `SF-FOUNDATION-007` is verified; launch/create/open states use the approved blank baseline and verified package/history/recovery boundaries.
  - Plan: introduce one deterministic main-actor launch presentation coordinator over the actor-isolated lifecycle backend; emit real read, canonical validation, history validation, atomic adoption, and recovery-check progress without simulated animation; expose native welcome, blank-create, open, cancelable/non-cancelable, failure, retry/choose-another, and recovery-choice surfaces; retain the current document until validated adoption; centralize privacy-preserving state diagnostics, accessibility announcements, preferred focus, and motion/transparency/contrast adaptations; then cover transitions, preservation, compatibility, recovery, responsiveness, performance, and UI states without implementing workspace materials.
  - Evidence: `./sf verify` passed on 2026-07-19 with 79 unit tests and 9 UI tests, all with zero failures. Fourteen focused launch tests cover every state transition, approved blank creation, real determinate/indeterminate stages, cancelability boundaries, cancellation and failure preservation, malformed/incompatible packages, Retry, Restore/Discard recovery, accessibility messages, deterministic focus, Reduce Motion, main-actor responsiveness, redacted diagnostics, and a 100-page loading budget. UI coverage verifies initial actions, all progress modes, non-cancelable disclosure, failure/recovery actions, static reduced-motion treatment, and the existing shell. Welcome, determinate history-loading, and recovery-selection states were manually inspected at the practical window minimum in dark appearance with no clipping or overlap. Diff review found no generated products, fixture residue, private paths, credentials, distribution signing, publication, translucent-material scope drift, or unrelated feature expansion.

- [x] `SF-FOUNDATION-007` Seed blank projects with the approved default page and navigator structure.
  - Requirements: `SF-0301-001`, `SF-0301-002`, `SF-0301-005`, `SF-0301-006`, `SF-0301-008`; `SF-0303-001`, `SF-0303-003`, `SF-0303-005`, `SF-0303-006`, and `SF-0303-008`.
  - Acceptance: creating a blank project produces the exact ordered page, route, home/error-role, and navigator structure approved in `OD-003`, with stable typed identities and explicit default provenance; creation establishes one valid project baseline; package save/reopen and history/recovery boundaries preserve the same structure deterministically; the Pages navigator exposes the seeded hierarchy through keyboard and accessibility paths; tests distinguish blank-project defaults from templates and prove no empty page list is produced.
  - Dependencies: `SF-FOUNDATION-006` is verified; `OD-003` was approved on 2026-07-19.
  - Plan: extend canonical schema v2 with typed routes, roles, creation provenance, and template identity; create Home and Not Found with one minimum root each as one clean baseline; enforce non-empty page lists and unique routes at validation/transaction boundaries; migrate schema-v1 empty or rootless documents deterministically; preserve identities through package, lifecycle, history, autosave, and recovery; replace the Pages placeholder with ordered, selectable, keyboard-operable accessible rows; and verify exact defaults, invalid states, persistence, migration, history, and UI behavior.
  - Evidence: `./sf verify` passed on 2026-07-19 with 65 unit tests and 5 UI tests. Focused coverage proves exact names/routes/roles/order/provenance, stable typed page/root identities, minimum roots, blank/template separation, unique-route and non-empty invariants, deterministic historical schema-v2/package round trips, schema-v1 package migration, clean undo baseline, autosave/recovery identity, and Pages navigator accessibility/arrow navigation. Current packages now write schema v3; its schema-v2 adapter adds no authored guides. Diff review found no generated products, fixture residue, machine-specific paths, credentials, distribution signing, publication, or unrelated feature expansion.

- [x] `SF-FOUNDATION-006` Integrate persisted document history with save and recovery boundaries.
  - Requirements: `SF-0306-002`, `SF-0306-004`, `SF-0306-005`, `SF-0306-008`, `SF-0307-001`, `SF-0307-002`, `SF-0307-003`, `SF-0307-004`, `SF-0307-005`, `SF-0307-006`, and `SF-0307-008`.
  - Acceptance: committed transaction metadata and supported inverses survive package save/reopen within the supported schema; recovery establishes a valid durable-revision boundary; undo/redo never crosses an incompatible, discarded, or superseded recovery boundary; rejected history is isolated without losing the canonical document.
  - Dependencies: `SF-FOUNDATION-005` is verified. Blank-project defaults, launch visuals, responsive design, and canvas behavior remain out of scope.
  - Plan: add an optional independently versioned deterministic `history.json` package member; capture stable transaction identity, ordering, revisions, typed command, registry-derived label, timestamp, affected identifiers, and inverse data in `DocumentSession`; encode and validate snapshots in an actor with entry/byte retention limits and redacted diagnostics; require revision, identity, ordering, and forward/inverse round-trip consistency before installing history; treat missing or rejected history as a clean compatibility baseline; inject snapshots into atomic durable and recovery writes; filter recovery history at the durable revision; and verify reopen, branch, corruption, legacy, recovery, retention, determinism, responsiveness, and shell command boundaries.
  - Evidence: `./sf build`, `./sf test`, and `./sf verify` passed on 2026-07-19 with 57 unit tests and 4 UI tests. Twelve focused history tests cover stable transaction metadata, save/reopen undo and redo, complete ordering, branch invalidation, compatible/incompatible/discarded recovery boundaries, legacy/missing history, corrupt/oversized/unsupported/reordered/duplicate/mismatched history, canonical survival, deterministic member/package bytes, retention/size limits, diagnostic redaction, and shell availability. Reopen and recovery flows were inspected through the integration suite and launched shell; diff review found no fixture residue, generated products, machine paths, credentials, signing changes, or excluded-feature scope drift.

- [x] `SF-FOUNDATION-005` Integrate native open, save, autosave, and recovery-candidate flows.
  - Requirements: `SF-0301-002`, `SF-0301-004`, `SF-0301-005`, `SF-0301-006`, `SF-0301-008`, `SF-0306-001`, `SF-0306-002`, `SF-0306-003`, `SF-0306-004`, `SF-0306-005`, `SF-0306-006`, `SF-0306-008`, `SF-1504-001`, `SF-1504-004`, `SF-1504-006`, and `SF-1504-008`.
  - Acceptance: native document commands open and save the package from `SF-FOUNDATION-004`; autosave writes committed revisions away from the main actor; interruption produces a newer-only recovery candidate with explicit restore/discard/inspect choices; cancellation, denial, stale access, external change, conflict, malformed data, and I/O failure preserve the last committed in-memory document and durable package.
  - Dependencies: `SF-FOUNDATION-004` is verified. Persisted transaction history remains scoped to `SF-FOUNDATION-006`.
  - Plan: add a main-actor lifecycle coordinator over an actor-isolated backend and the verified atomic package store; expose native New/Open/Save/Save As/Revert/Close commands and typed project panels; fingerprint durable saves for external-change detection; debounce immutable committed snapshots into same-directory recovery packages with revision generations that suppress stale work; adopt opened/recovered documents only after complete validation; expose explicit document, failure, close, and recovery states with keyboard and accessibility semantics; and verify success, cancellation, denial, conflict, recovery, concurrency, redaction, and unchanged-state boundaries in repository-local fixtures.
  - Evidence: `./sf build`, `./sf test`, and `./sf verify` passed on 2026-07-19 with 45 unit tests and 4 UI tests. Ten lifecycle tests cover clean new documents, validated open, cancellation, Save/Save As, coalesced autosave, stale-save suppression, recovery freshness/restore/discard/malformed data, external conflict, permission/stale-scope/I/O failure, unchanged state, revert, unsaved close, diagnostic redaction, and main-actor responsiveness. UI coverage verifies native command availability, status accessibility, and existing keyboard focus behavior. The launched app and native File menu were inspected locally; diff review found no fixture residue, generated products, machine paths, credentials, distribution signing, or persisted-history scope drift.

- [x] `SF-FOUNDATION-004` Implement deterministic project-package persistence.
  - Requirements: `SF-0301-001`, `SF-0301-003`, `SF-0301-004`, `SF-0301-008`, `SF-1702-001`, `SF-1702-004`, and `SF-1702-008`.
  - Acceptance: a versioned package manifest and canonical document payload write atomically to a repository-local temporary fixture, round-trip deterministically, preserve unknown optional package members, and reject missing, corrupt, incompatible, or path-escaping input without changing a valid package.
  - Dependencies: `SF-FOUNDATION-003` is verified. Native open/save UI, autosave/recovery, and persisted history remain explicitly out of scope in `SF-FOUNDATION-005` and `SF-FOUNDATION-006`.
  - Plan: define a versioned deterministic container with a canonical JSON manifest, schema-v1 document payload, stable project identity, RFC 3339 metadata, compatibility minima, declared resource/optional members, byte counts, and SHA-256 integrity; isolate read/write work in an actor; stage, synchronize, and atomically replace regular files without following symbolic links; validate the complete bounded package before returning a document; preserve opaque optional members; return typed redacted failures; and exercise all success, interruption, compatibility, integrity, size, duplicate, path, symlink, and unchanged-state boundaries with repository-local fixtures.
  - Evidence: `./sf build`, `./sf test`, and `./sf verify` passed on 2026-07-19 with 35 unit tests and 3 UI tests. Thirteen persistence tests prove deterministic bytes, version/identity/metadata/integrity declarations, successful round trips, atomic replacement, simulated interruption, opaque optional/resource preservation, required-member validation, corrupt manifest/document handling, unsupported package/schema/reader versions, traversal, symbolic-link, duplicate, oversized, malformed-metadata, integrity, unchanged-state, diagnostic-redaction, and exact requirement-traceability behavior. Diff review found no fixture residue, generated products, Xcode user data, machine-specific paths, credentials, signing changes, or native open/save/autosave/history scope drift.

- [x] `SF-FOUNDATION-003` Implement the command registry and transactional document-model skeleton.
  - Requirements: `SF-0203-001`, `SF-0203-004`, `SF-0203-005`, `SF-0203-006`, `SF-0203-008`; `SF-0302-001`, `SF-0302-004`, `SF-0302-005`, `SF-0302-008`; `SF-0303-001`; `SF-0304-001`, `SF-0304-004`; `SF-0305-001`; `SF-0306-001`, `SF-0306-004`, `SF-0306-005`, `SF-0306-008`; `SF-0307-001`, `SF-0307-004`, `SF-0307-005`, `SF-0307-006`, `SF-0307-008`; `SF-1607-008`; `SF-1702-001`, `SF-1702-004`, `SF-1702-008`; and `SF-1902-001`, `SF-1902-004`, `SF-1902-005`, `SF-1902-006`, `SF-1902-008` for this bounded kernel.
  - Acceptance: tests prove stable typed identity, explicit ownership, registered validation and disabled reasons, valid execution, rejection and cancellation rollback, inverse correctness, undo/redo ordering and branch invalidation, deterministic versioned serialization and round trips, invalid or unknown schema rejection, diagnostic redaction, and shell command enablement; `./sf verify` passes.
  - Dependencies: `SF-FOUNDATION-001` and `SF-FOUNDATION-002` are verified; package persistence, autosave/recovery files, and history/recovery integration remain explicitly out of scope.
  - Plan: add a UI-independent canonical document/page/node/property model with typed identifiers and graph validation; add deterministic schema-versioned serialization; implement an exhaustive typed registry whose commands validate and mutate a draft inside one atomic transaction; retain explicit inverses in undo/redo stacks with branch invalidation; emit in-memory redacted diagnostics; connect only the existing shell Undo/Redo surfaces; then add focused unit and UI coverage, verify, audit, document, and queue the next three persistence/recovery slices without implementing them.
  - Evidence: `./sf build`, `./sf test`, and `./sf verify` passed on 2026-07-19 with 22 unit tests and 3 UI tests. Seventeen command-kernel tests cover typed stable identity, graph ownership, exhaustive registry validation, valid execution, invalid and cancelled rollback, exact node/property inverses, undo/redo order, redo-branch invalidation, deterministic schema-v1 data, round trips, corrupt/unknown schemas, diagnostic redaction, and real shell history enablement. Diff review found no derived products, Xcode user data, machine paths, credentials, signing changes, or persistence/recovery scope drift.

- [x] `SF-FOUNDATION-002` Implement the application shell with document window, toolbar, navigator, canvas placeholder, inspector, and status bar.
  - Requirements: `SF-0201-002`, `SF-0201-004`, `SF-0201-006`, `SF-0201-008`, `SF-0203-006`, `SF-0203-008`, `SF-0602-002`, `SF-0602-006`, `SF-1902-006`, and `SF-1902-008`.
  - Acceptance: UI tests verify all shell regions, toolbar command states, minimum window sizing, and keyboard focus order; `./sf verify` passes; the rendered shell is inspected at default and minimum practical sizes.
  - Dependencies: `SF-FOUNDATION-001` is verified; no owner decision blocks reversible local shell placeholders.
  - Plan: retain the verified native project; add reusable state, command, navigator, canvas, inspector, and status components; host them in a native restorable window with a native toolbar and menus; expose stable accessibility identifiers and intentional selected, disabled, empty, and focus states; test the bounded shell without introducing document mutation or canvas engines; then verify and visually inspect the running app.
  - Evidence: `./sf build`, `./sf test`, and `./sf verify` passed on 2026-07-19 with five unit tests and three UI tests. Automated coverage verifies stable regions and requirement mapping, practical minimum/default window metrics, tool and undo/redo states, zoom bounds, toolbar interaction, Preview presentation, and navigator-to-viewport keyboard focus order. The launched app was inspected at its default size and enforced 1100×700 minimum content size; the native toolbar, split regions, tab controls, placeholders, and status content remained visible without clipping or overlap.

- [x] `SF-FOUNDATION-001` Create the native macOS Xcode project and test targets.
  - Requirements: `SF-1501-008`, `SF-1802-008`, `SF-1902-006`, and `SF-1902-008` for the bounded application, build/test, accessibility, and automated-smoke foundation.
  - Acceptance: `./sf build`, `./sf test`, and `./sf verify` pass with repository-local source and project files and Derived Data outside the checkout.
  - Dependencies: uses the reversible development bundle identifier `app.siteforge.SiteForge`; final publisher identity and distribution channel remain governed by `OD-012` and `OD-013`.
  - Plan: audit and retain the valid partial project; finish the Swift 6/macOS 14 app, unit-test, and UI-test targets in one shared scheme; add identity, requirement-traceability, accessibility, and launch smoke coverage; use credential-free local ad-hoc signing only where XCTest requires it; keep Release distribution signing disabled; and make command-line project discovery and build output portable.
  - Evidence: `./sf build` succeeded; `./sf test` executed two unit tests and one UI test with zero failures; `./sf verify` passed repository checks, build, and both test targets on 2026-07-19 using Xcode 27.0 beta, including from an isolated copy containing only tracked and non-ignored source files. Project review found no generated products, `xcuserdata`, absolute machine paths, development team, provisioning profile, certificate, or distribution-signing requirement.
