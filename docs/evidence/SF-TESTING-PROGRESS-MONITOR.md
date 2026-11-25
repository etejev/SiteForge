# Floating local testing progress

November 21, 2026. Bounded support for SF-0206-002/003/004/006/008,
SF-1607-002/004/008, and SF-1902-007/008. This tooling slice does not
mark the surrounding preference or diagnostics modules complete.

Delivered as owner-local build **26.11.22**, with strict app/helper signatures
and matching source/provision fingerprints. The bounded native acceptance and
installed report retrieval pass; no permission dependency remains. Earlier
failures below are retained diagnostics, not current blockers.

The redesign was verified and installed before applying the approved monitor
packet. Its full-gate receipt is in [the redesign evidence](SF-NATIVE-UI-REDESIGN.md).
The monitor started from the reviewed patch with SHA-256
`a2082b594d7c95d97c0a0d6cb399b36501944b3d4a00e9fa9aaccec97629e8c1`.

The AppKit helper presents a nonactivating black panel with the native blue
progress indicator, current method, remaining count, active elapsed time, and
measured ETA. Its controls share fixed dimensions. Confirmation and requests
use the run-owned files; the rest of the running monitor is click-through.
Terminal summaries retire when another run becomes current.

The shared collector records starts separately from terminal events, normalizes
selector spelling, retains confirmed results, and detects unexpected selectors.
Pause waits for the current case where practical, interrupts the owned process
group, verifies release of the prepared UI app and runner, then acknowledges
Paused. Resume selects only unresolved prepared methods and creates a new
xcresult segment. Earlier failure evidence cannot become a pass. Cancellation
while paused does not launch a continuation. Paused time is excluded from the
active elapsed display.

Normal local CLI testing resolves the existing scope and opens the native
Testing window for review and Start. Its detached collector builds once,
enumerates selected products, and executes those products without rebuilding.
Source changes during preparation stop testing. The app and CLI share
persistent report ownership. Hosted and headless commands retain direct
execution. The watch command builds only; unmapped changed scope stops with
explicit focused/full guidance.

## Retained integration checkpoint

Automated evidence so far:

- 29 collector tests pass, including real subprocess interruption, continuation
  arguments, retained pre-pause failure, cancellation while paused, prelaunch
  cancellation, process ownership, and inventory/accounting regressions.
- Eight foreground-plan tests pass: exact focused scope, full two-target
  enumeration order, missing inventory, source mutation, original build and test exit codes, target isolation, interrupted launch,
  and the whole-product enumeration regression.
- Swift 6 type checking passes. Nine progress state/timing fixtures pass.
  Native offscreen assertions pass for the blue rounded indicator, matching
  Pause/Resume/Cancel frames, confirmation and expiration, requests, frozen
  paused elapsed time, click-through properties, and terminal state.
- Three command-boundary tests pass, including hosted/SSH direct execution,
  all plan scopes, unmapped-scope refusal, and two build-only watch cycles.
  The existing shell lifecycle harness passes its four scenarios.

The reproducible Python commands are:

```
/usr/bin/python3 -m unittest discover -s Tests/Tooling -p test_unattended_verification.py
/usr/bin/python3 -m unittest discover -s Tests/Tooling -p test_testing_foreground.py
/bin/zsh scripts/test-sf-test-harness.sh
```

Native helper fixtures and verification logs are retained under the ignored
`.codex-loop/testing-progress/acceptance` directory. Scope and watch behavior
were also checked in the prepared packet; integrated checks are still pending.

The final native foreground run `68b83af768754742b404680145865437` exited
0 with 21/21 code tests and 2/2 UI journeys, with no failures. Its source
fingerprint before and after was
`477d4745c87a62a364aa29a0d985a6ae01cc1eb2f2d4a3d6bda9d23650097ff3`.
The run's report, event log, inventory, result segments, and
`native-pause-receipt.json` are in the persistent TestingReports directory.

The Inspector journey exercised real controls, keyboard edits, Undo/Redo,
tabs, and viewport changes with the monitor visible. After that case, the
collector stopped its owned process group and runner. The pause receipt
contains no owned processes. After 3.135 seconds paused, Resume selected only
`SiteForgeUITests/SiteForgeLaunchTests/testWebsitePreviewBuildsAuthoredOutputAndOpensActualSafari`
and used a new xcresult path against the same prepared products. That journey
passed and asserted Safari was foreground. Both result segments exported
attachments successfully. The deliberately interrupted segment records exit
75; the continuation records exit 0. All terminal case outcomes are retained.

Earlier attempts remain diagnostic evidence. The initial focused class ran
21 passing tests but correctly withheld a pass because Xcode enumerated 895
methods. The fix intersects built leaves with resolved selectors and separately
enumerates targets. A later attempt exposed a `/var` versus `/private/var`
runner ownership bug. Its pause receipt was rejected; that run was cancelled.
The collector now checks both the supplied and canonical product path, with a
symlink regression fixture. The abandoned owned runner was terminated and its
release verified before the final passing run.

Native attachments show the real thin blue inactive progress indicator and
aligned controls over SiteForge and foreground Safari. Those captures also
show an unrelated “Enable ChatGPT Computer Use Permissions” window, so they
are retained as diagnostic captures rather than clean final screenshots.
Direct CUA observation timed out before the owner confirmed an unlocked Mac
and again on retry. The native test log and captured window identify the
Computer Use permissions setup as the remaining blocker for live button and
click-through inspection. That was the earlier checkpoint assessment. Native XCTest subsequently
established a working route independent of the CUA prompt, as recorded below.
Installed Settings smoke and installation remain pending. The installed owner
app remains the verified redesign build.

The repository check completed all other checks but failed on new evidence
symbols. Those symbols were corrected to the actual text in this document;
`scripts/check-traceability.py` then exited 0. Its retained follow-up log and
`git diff --check` cover the documentation correction. No test or gate was
weakened.

OC-001 ended with provider/runtime errors and no patch or completed tests.
[The evaluation](SF-OPENCODE-EVALUATION.md) records unchanged isolated source;
no worker integration is pending. Deleted/renamed scope handling remains a
later bounded tooling fix. This chat owns the monitor files, local installation, and the sole
desktop collector. No commits, pushes, or external GitHub changes were made.

## November 21 native Testing window continuation

The owner expanded this slice to SF-0206-002/003/004/006/008,
SF-1607-002/004/008 and SF-1902-007/008. Settings now opens a native Testing
window before a run exists. Its shared store previews regular/code, UI,
exact/affected and explicit full scopes, reconnects active/retained reports,
and exposes Open Report and Reveal Logs. Local graphical CLI requests open
that same window with a prepared scope; Start remains an actual native button.
Hosted/headless execution remains operational.

The owner-reported repeated build label and unhelpful preparation ETA are
addressed in source: phase and real compiler activity have separate fields;
unknown inventory is labelled activity; compatible measured preparation and
per-case durations produce labelled estimates. Only freshly built selected
inventory supplies totals. Added/deleted/new methods are reconciled with that
inventory; missing timing evidence explicitly withholds an estimate. Early
source checking now publishes owned, cancellable state before accessing the
checkout and preserves stale/unavailable/cancelled reports.

Focused bootstrap verification passes 49 tooling tests: 35 collector,
two CLI-to-native review bridge and 12 foreground/command/Swift-native fixture
checks. The shell lifecycle harness also passes. Logs are under
`.codex-loop/testing-progress/closeout/`. This is supplementary evidence;
it does not replace actual native Start acceptance.

Native XCTest operates independently of the unavailable CUA helper. Earlier
actual pointer checks established running/paused click-through, foreground
retention, stable equal control frames and Resume against unresolved methods.
A real defect made the helper exit after its child button windows disappeared
at completion; monitor-mode termination now requires explicit dismissal or
superseding. A later real failed run left the corrected helper visible after
the collector exited. Final clean captures and cancellation checks remain due.

The first real window-started regular run was
`20261121-180839-f1282c81`, source
`21ecd1af7cc0ae3b19fe99884213ad9321d4585c63b3085caef7c8ec409c57cc`.
Its isolated build passed in 80.724 seconds and fresh inventory selected 16
SupportSettings methods. Fifteen passed; one history test failed two assertions
because a directory URL differed only in trailing-slash representation. The
fixture now compares standardized filesystem paths. This is a failed retained
run, not a passing receipt. It also established process-scoped Xcode fallback
and actual Documents-folder permission handling. The owner explicitly allowed
SiteForge access; rebuilt ad-hoc candidates may prompt again. The previous
verified redesign remains installed until final acceptance and packaging.


The updated real Start Regular Testing run
`20261121-184808-94d3c4ff` passed 17/17 SupportSettings methods with fresh
inventory and no mismatch. Source and provisioned harness both match
`a0bd9ae53140e0ee1204002b1b0323da9dc9d191757bf74948cf0ef41bf8091b`.
The native input-controller acceptance passed: Settings → Open Testing,
prepared exact code scope, disabled UI target, actual Start, duplicate-start
prevention, safe preparation Pause, equal native control frames, viewer close
and reopen, Resume, normal viewer quit, and detached terminal completion.
Paused time was 5.929 seconds. The build measured 99.316 seconds; its prior
80.724-second measurement provided an explicitly estimated preparation phase.
No old count supplied the new 17-case inventory (the donor had 16 methods).
The controller xcresult and clean preparation/reconnected-paused captures are
retained in the ignored closeout captures/log folder and the persistent run
report’s `viewer-screenshots` directory. Final artifact paths will be recorded after installation.


Native confirmed-cancellation acceptance also passed. Runs
`20261121-185047-f21e72d5` (active preparation) and
`20261121-185054-1944600a` (paused) ended cancelled, released the shared lock,
and retained reports. The first click did not cancel; the second confirmed it.
Both confirmations retained identical native frames. The paused capture
exposed a still-animating main-window indicator and stale compiler detail;
those presentation issues are corrected in the next candidate. Small native
controls also allow the full Confirm Cancel label inside the approved width.
These later visual changes are subject to final installed acceptance.

The actual two-method UI Start run `20261121-185412-9aa6f4bf` retained
2/2 terminal outcomes against source/harness
`0269c709fb9bfe77740c86c66e660fca7fb33dca01b5c27b75b1b0441e80025c`.
Safari passed with the floating panel and its fresh 1/2 count visible. Settings
passed the descriptive live-title check, then failed its exact-selector query:
the test clicked the macOS disclosure label, leaving the native arrow collapsed
(AX value 0). The focused repair clicks the arrow and waits for an accessible
selector. The failed run remains failed; only Settings needs replay. No test
assertion or coverage was removed. Its raw logs, built inventory, result bundle,
UI hierarchy and exported screenshots remain in the persistent report.

Shipping-helper native input acceptance now passes in
`native-controls-13.xcresult` (ignored closeout log/capture directory). It uses
the current helper executable in a test-only signed wrapper and the real
Collector with deterministic subprocess case output. These four synthetic
cases are not counted as product XCTest passes. The helper's Mach-O UUID
matches the packaged helper: `E1DEEEB5-9B83-3E4C-83D4-66CD5D8EFFCD`.
Actual pointer events verify body click-through and retained foreground,
94×24-point views (96×26 AX outset), 8-point spacing, stable frames through
Pause/Resume/Confirm Cancel, frozen active time, exact unresolved continuation,
partial-result preservation on execution and paused cancellation, terminal
persistence, and retirement when superseded. Clean running, paused,
confirmation, passed and cancelled captures are under the ignored
`closeout/captures/monitor-*.png` paths. Their native black/blue geometry
matches the approved monitor preview; the real Safari capture independently
shows the same panel over the foreground browser.

The first Settings replay `20261121-190119-0fd455f4` remained failed because
the disclosure's AX bounds did not align with its rendered arrow. The retained
recording and AX value 0 establish that it never expanded. Rather than add a
coordinate offset, the header is now one native SwiftUI button with a shared
label/chevron click target, an Expanded/Collapsed accessibility value, and
view-owned disclosure state. The exact-selector existence and identity checks
remain in the journey. This bounded accessibility correction is being replayed
on the final candidate; it does not alter project data or collector behavior.


## Verified installation and final acceptance

The final source fingerprint is
`1c3bb00f2c512d96b51bdcb75f70a803c111a93dd15fa81db01478d8ded30dcb`.
`scripts/package-owner-local-app.sh --install` installed build **26.11.22**.
Strict/deep app verification and strict helper verification exited 0. Installed
Info.plist, OwnerTesting installation.json and the current checkout match;
the provisioned collector bytes match the repository. The previous verified
bundle was preserved recoverably; no running app or document was terminated.
The receipt is `closeout/installed-receipt.json` in the ignored evidence tree.

| Check | Observed result |
| --- | --- |
| Final Settings UI replay `20261121-190627-2b525677` | 1/1 passed; descriptive live title, exact selector details, unavailable debug harness and native Settings behavior |
| Installed regular run `20261121-191113-10a30223` | 17/17 passed; same source/provision fingerprint, fresh inventory, no mismatch, exit 0 |
| Safari in `20261121-185412-9aa6f4bf` | Passed, foreground browser with determinate 1/2 progress; reused because subsequent changes only affected Testing details/presentation and its Settings assertions |
| Tooling | 35 collector + two CLI bridge + 12 foreground/command/native-fixture checks passed; their inputs are unchanged in the delivered source |
| Native monitor controls | Input-control acceptance passed, including both confirmed cancellation paths and partial-result retention; synthetic fixture counts are separate from product tests |
| Repository | Complete check exited 0, including traceability for 440 records; final documentation traceability and diff checks pass |
| Installed CLI/reports | Normal focused CLI opened review without starting a run; native report handler and Finder retrieval passed, with current run ID unchanged |

The installed run was paused for 465.797 seconds, excluded from active time.
A temporary controller initially misread a button's generic AX value. It quit
the viewer normally while leaving the prepared run paused. The next native
controller reopened that same run, checked full Confirm Cancel text and equal
frames, allowed unconfirmed cancellation to expire, closed/reopened Testing,
resumed and quit normally. All 17 exact methods then passed against the same
prepared products. This was not a replacement run or a rebuilt continuation.
The paused main-window animation is stopped and stale compiler detail hidden.

The final Settings replay and installed regular run both match the delivered
fingerprint. The unaffected Safari, historical 21-code/two-UI continuation and
redesign full-gate receipts are retained with their original source identities.
No redesign full-suite rerun or new full-gate success is claimed.

Persistent reports are under
`~/Library/Application Support/SiteForge/TestingReports/<run-id>`.
They retain scope, source/harness identity, raw logs/events, actual inventories,
all result segments, exports, failures and terminal status. Installed captures
and their provenance manifest are also in the final regular run's
`viewer-screenshots` directory. Stable ignored copies are in
`.codex-loop/testing-progress/closeout/captures/`, including:

- `installed-testing-cli-review-and-retained-result.png`
- `installed-paused-clean.png` and `installed-confirm-cancel-equal-controls.png`
- `monitor-running.png`, `monitor-paused.png`, `monitor-passed.png`
- `monitor-cancelled-running.png`, `monitor-cancelled-paused.png`
- `safari-running-exact-count.png`

No active collector remains. The owner can use Settings → Advanced → Open
Testing, press the appropriate Start button, then tell Codex testing finished.
Codex reads these same reports and compares their source fingerprint before
repairing anything. Native XCTest required no CUA-helper permission. The exact
SiteForge Documents prompt was allowed under the owner's authorization;
privacy settings were not reset or broadened. The earlier default XCTest
permission denial and failed disclosure attempts remain visible as failures.
OpenCode is archived with no patch to integrate. Deleted/renamed affected-scope
mapping remains a separate bounded tooling item. No commits or external GitHub
actions were performed.
