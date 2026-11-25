# Native UI consistency review — November 21

Bounded review of the approved design: SF-0201-003/006/008, SF-0203-006,
SF-0206-003/006/008, SF-0303-006, SF-0701-006, SF-1503-006, SF-1505-006,
SF-1607-006/008. This is presentation and window-role repair, not a redesign
or an expansion of module coverage. The affected-scope baseline remains in
[its receipt](SF-AFFECTED-TEST-SCOPE.md); earlier redesign and monitor receipts
remain available and are not represented as new full-gate results.

## Current acceptance — final verification and installation closeout

Final candidate source/harness fingerprint:
`9883ae6d6c5f068ff1346ac937918a75fea594ebd050c44067f89d441cfd4606`.
The exact installed identity is recorded below after packaging. All normal
application test runs started from the native Testing window's Start buttons.
Read-only native input/capture utilities have separate xcresult receipts and
are not counted as application acceptance methods.

Concrete corrections:

- Native Start, editor, Settings, Testing and monitor surfaces now use semantic
  macOS window/under-page/control/label/separator roles. The owner's latest gray
  decision supersedes fixed black/custom chrome colors. Website paper and
  authored website data are unchanged; approved geometry is retained.
- Start Regular/UI actions have equal label widths and native baselines.
  Pause/Resume and Cancel/Confirm Cancel remain equal, with stable frames
  through real pause/resume, confirmation, preview and cancellation of preview.
- Scope describes requested selectors without echoing the editable input.
  Complete selectors, built inventory, run ID and identity remain in details.
- One terminal outcome replaces repeated passed text. Export activity cannot
  leave a completed run saying Retaining results. Collector finalization clears
  transient activity. Paused detail fills reserved slots without moving controls.
- History has localized date/time, readable Regular/UI/Combined outcomes,
  native selection and live status refresh. Actual row selection reopened run
  `20261121-225700-55ef0b0a` and its exact source identity; Latest restored routing.
- The anchored workspace bridge restores its role after SwiftUI assigns a scene
  identifier, allowing the main window to fill the usable desktop. Auxiliary
  windows retain independent ownership. Named DEBUG-only Testing review phases
  share the existing UUID-scoped test geometry route, check native minima, and
  never assign Testing the document role. The maintained installed-entry journey
  now checks 720×552 and restoration to 900×692 with equal visible Start controls.
- The helper receives app appearance in its owned environment and source-bundle
  scoped live notifications. Actual Light preview and Cancel changed/restored
  both processes without changing global macOS preferences. Opaque semantic
  drawing updates with appearance; no captured initial CGColor remains.
- The native thin rounded progress bar keeps blue fill in inactive windows.
  Pixel measurement drove two tint refinements; the final five actual samples
  all exceed 3:1 against their adjacent semantic surfaces.

| Actual final surface | Fill RGB | Surface RGB | Contrast |
| --- | --- | --- | --- |
| Active Testing, Dark | 0,98,255 | 30,30,30 | 3.33:1 |
| Inactive Testing, Dark | 0,145,252 | 30,30,30 | 5.13:1 |
| Active Testing, Light | 0,98,255 | 255,255,255 | 5.01:1 |
| Inactive monitor, Dark | 0,145,252 | 30,30,30 | 5.13:1 |
| Inactive monitor, Light | 0,145,252 | 255,255,255 | 3.25:1 |

Measurements and crop provenance: `.codex-loop/ui-consistency/contrast-final.txt`,
`palette-4-attachments/manifest.json` under `/private/tmp/siteforge-ui-consistency`,
and matching owned CG window-bound attachments. The captures are actual native
pixels, not the SwiftUI design preview. Inactive AppKit tint differs slightly
from active tint while keeping the same blue/native geometry.

Final clean captures are in `.codex-loop/ui-consistency/final/`:
`start.png`, `opening.png`, `failure.png`, `recovery.png`,
`workspace-normal-dark.png`, all `workspace-compact-*`, `pages-hover.png`,
`inspector-*`, `website-settings-*`, every `settings-dark-*` and
`settings-light-*`, `testing-terminal-normal-clean.png`,
`testing-exact-normal-clean.png`, `testing-exact-compact-clean.png`,
`testing-history-exact-routing.png`, and `monitor-terminal-{dark,light}.png`.
The 720×552 view scrolls vertically to retain report actions; the normal view
and detailed view expose complete IDs. Before captures and failed diagnostic
utilities remain separately retained. Matching 1440×780 Start, 1440×800 workspace,
1100×700 compact, 860×470 Settings, 900×692 Testing and 428×140 monitor frames
were inspected against the approved reference geometry at 2× scale. Palette
comparison uses the new owner decision rather than the superseded black render.
Both 41-point sidebar strips, hover row frames, empty artboard, field baselines,
native sheets/popovers and active/inactive treatment retain the approved layout.

Final source's maintained UI replay:
`20261121-234252-9115caa4` — one exact OwnerLocalSettings journey passed, including
live descriptive case/details, Settings→Testing, minimum/normal frames and peers.
The preceding gray candidate passed 53 core + 88 nested cases and five appearance
journeys. Its unaffected functional/model receipts are reused. Nine broader
native journeys (including long inspector/component recovery) passed before the
palette update. Final exact-source tooling replay and installed smoke follow
below. No new full-gate claim is made; the completed redesign's full receipt
remains linked in its evidence.

Native review utilities `palette-final-4.xcresult` and `after-1.xcresult` passed.
The latter covers all seven Settings destinations in both appearances, Start/
loading/failure/recovery, normal/compact editor, Pages hover, native Page menu,
three inspector tabs, Website/Home sheets and contrast/opaque/larger-text variants.
Earlier capture controllers failed on assumed window positions/previous sizes;
those did not change application acceptance results. The final named native
review phases and exact report routing passed. A read-only terminal helper was
explicitly dismissed through its native Close control; persisted results remain.

The new native contrast fixture initially assumed an accessibility appearance
name would remain distinct with Increase Contrast off. AppKit normalizes it to
Aqua/Dark Aqua on this Mac. The corrected fixture verifies the appearance AppKit
actually returns and opaque window/control invariants; it does not claim to have
enabled a global setting. The app-scoped increased-contrast and opaque native
journeys/captures passed. The failed 87/88 receipt remains failed; its focused
1/1 + 88/88 replay is separately retained. No CUA permission is required by this
native test/capture route.

## Installed closeout — November 22

Final source's Start Regular run `20261121-235142-c7e95d3e` passed 1/1 XCTest
and 88/88 nested tooling cases, no failures/skips. Its original xcresult and all
exports completed successfully. Exact inventory/events/ledger/logs are in
`~/Library/Application Support/SiteForge/TestingReports/20261121-235142-c7e95d3e`.
`final-receipt.json` reconciles identical source before/after for both final runs.
The prior failing contrast-fixture and capture-controller receipts remain
unchanged; they are not counted as passing acceptance.

`scripts/package-owner-local-app.sh --install` refreshed `/Applications/SiteForge.app`
as build 26.11.22 and recoverably preserved its predecessor. No running app or
owner document was terminated. Strict deep app signature and strict helper
signature pass; installed Info.plist, installation.json and current source all
match `9883ae6d6c5f068ff1346ac937918a75fea594ebd050c44067f89d441cfd4606`.
The collector equals repository bytes. Helper SHA-256 is
`3ad3ff4ce2d56fabbb8728029b368cc513c19f5d967b1668c92dea814fd2aff3`;
collector SHA-256 is
`1b4721de3a22b936c11f4d12e80c0d622df3df5fa8b1860364234999dc4dccb0`.
See `install.log` and `installed-receipt.json` in the ignored evidence tree.

`installed-smoke-2.xcresult` passed actual installed Settings→Testing, actual
installed helper path/Light preview/restoration, normal CLI exact-scope review,
1-selector summary/equal enabled/disabled peers, report opening, Finder log
reveal, compact report actions and retained reopen. The CLI exited 0 and neither
changed current run nor created active.json. The input XCTest runner's sandbox
rejected xcrun in the first smoke controller; the local shell then used the
packaged viewer route. The installed app itself has no new permission blocker.
`installed-editor-2.xcresult` also passed installed 1440×800 editor Dark/Light
preview/restore inspection. Its explicit document-window query prevents a
Settings window from being mislabeled as an editor capture. Final actual pixels
were inspected against the approved workspace geometry and new gray decision.
Installed editor, Settings, Testing and monitor captures are under the final
capture directory, including `installed-editor-{dark,light}.png`,
`installed-testing-{dark,light}-clean.png` and `installed-monitor-{dark,light}.png`.
Reports and complete IDs remain inspectable without pasted logs. No active
collector remains and work is local/uncommitted.

## Before inspection

Baseline installed build 26.11.22, source/provision fingerprint
`8cdff9ffb3af7cffdeefd9d19c0e9be9ee94997f52e6379e5d4088b2c52933d6`.
Native audit utilities are outside the repository under
`/private/tmp/siteforge-ui-consistency`; they exercise real windows and controls
with isolated project/recovery/recent fixtures. No project model was edited.

The retained initial Start/loading/failure/recovery captures and 30 additional
workspace/Settings/Website/Testing captures are in
`.codex-loop/ui-consistency/before`. Export manifest:
`/private/tmp/siteforge-ui-consistency/before-5-attachments/manifest.json`.
That read-only tour passed one utility XCTest; this is audit evidence, not the
application's normal acceptance-run count. Its first reference-size assertions
failed and are retained in before-1 through before-4 logs and xcresults.
The workspace remained 1100×700: native lifecycle diagnostics showed SwiftUI's
scene identifier replacing the document marker, so document presentation and
named geometry were skipped. These captures are explicitly compact, despite
the original utility's normal-state filenames. Start was captured at 1440×780;
App Settings at 860×470 and Testing at 900×692, all at 2× backing scale.
A stale ChatGPT screen-recording prompt polluted the full-desktop menu capture;
it is not clean visual acceptance or a dependency of window capture/XCTest.

All seven App Settings destinations were captured in dark and Light preview;
preview was cancelled. Website and Home metadata sheets, editor tool rail,
viewport, both tab strips, Pages hover (stable row frame), three inspector tabs,
light/dark/opaque/increased-contrast/larger-text compact editor were inspected.
The shared 41-point strip baseline, centered empty artboard, field alignment,
icon treatment and native sheets remain the approved design. Long Settings
content scrolls; screenshots of its initial viewport do not imply hidden rows
were absent. More detailed inspector and interaction coverage uses the focused
native journeys and retained full redesign receipt.

Testing visibly repeated its exact editable selector and passed outcome,
retained a terminal export message, used different Start widths, and led history
with opaque IDs/raw modes. These observations drove the bounded correction.
The blue progress filters were already identical in window and monitor; no
speculative tint change was made.

## Correction and verification in progress

- Equal Start label widths use a shared visual token. Native Pause/Resume and
  Cancel/Confirm Cancel keep their existing equal dimensions and behavior.
- Scope summary describes requested selection count; exact selectors and built
  inventory remain inspectable in Run Details and report routing is unchanged.
- Terminal outcome is stated once; old receipts with export activity no longer
  imply ongoing retention. New collector finalization clears transient activity.
- History uses localized date/time, readable test type/outcome and native List
  selection. Full run identity remains in accessibility value, tooltip/details,
  row identifier and URL. Combined focused scopes are labelled distinctly.
- The anchored configurator reasserts document ownership after SwiftUI assigns
  its scene identifier. Auxiliary panels retain their separate window policy.

Initial candidate `ef4e878c704d6e860d781bdf8aa27a4c60692981a5e7da2df3ef804b6fc694c9`
was prepared and Start Regular Testing launched
`20261121-223148-548bca01` for SupportSettingsTests and WorkspaceMaterialPolicyTests.
The native input controller passed equal Start frames and concise scope text.
A live preparation-to-Pause check found equal 94×20 AX button dimensions but a
46-point vertical shift when activity/phase labels disappeared. That utility
assertion failed honestly; the active collector was preserved and resumed
before any further source correction. Final receipt and installation follow
once the stable header correction and focused acceptance pass.

## Retained pre-palette acceptance and owner color update

Run `20261121-223653-e76bc5c3` passed 52/52 core methods and 87/87 nested
checks with no skips/failures. Native Pause/Resume then passed unchanged
94×20 AX button frames across the acknowledged pause, and native Start peers
were equal. `20261121-223958-cfcae527` passed all nine exact UI journeys in
`.codex-loop/ui-consistency/ui-selectors.txt` (723.5 seconds): all Settings,
loading, failure/recovery, Start focus, appearance/accessibility/inactive states,
Settings→Testing/live exact case, Website Settings, Light preview/restore, and
normal/compact inspector/component recovery. These receipts share source
`ee4dbc4250e1b5dbecab19a6fdaebd4515ebb27261857a07109e6e31e8701b31`.
`pre-gray-receipt.json` reconciles its source before/after and exact UI inventory.

The owner subsequently requested “use macos default grays instead of black
backgrounds.” The current palette decision replaces the previous black Testing
surface and fixed native chrome RGB colors. Semantic window/under-page/control,
label and separator roles now supply native UI surfaces; authored website paper
and data colors are unchanged. The old custom palette's numeric RGB-distance
checks were explicitly superseded by this owner decision: maintained tests now
check native semantic identity, neutral grays, opaque fallback, actual role
separation and unchanged website paper. No performance/security gate was waived.
The updated contract records that distinction.

The app sends a scoped appearance choice with the existing helper launch
and live preview/cancel notifications filtered by source bundle. System choice
uses native automatic appearance. No system preferences are changed. The
helper draws semantic background/separator colors on appearance changes, rather
than freezing a CGColor from its initial appearance. Start/control geometry and
collector ownership are unchanged. A native monitor appearance fixture joins
the exact nested ledger (88 cases expected).

The blue progress filter is identical in Testing and the monitor. The prior
solid blue sampled at RGB(4,53,255), 2.96:1 against black; retaining the native
green channel makes the same thin rounded blue treatment readable on the new
gray surfaces. Final captures measure the resulting actual fill and surface.
A subsequent visual review also drove live history refresh and useful paused
copy in the already reserved status slots, preserving the verified no-jump
layout. Unknown legacy modes now say Recorded testing rather than implying
unverified Full Verification.

Current gray candidate: `49df67f3719cc67ab0260388abcd0e476a8be68e8dce7ad175e63497ad1ff254`.
Regular Start run `20261121-225700-55ef0b0a` selects SupportSettingsTests and
WorkspaceMaterialPolicyTests. Gray/live-appearance acceptance and installation
are still in progress; no delivery claim is made by this checkpoint.

Final documentation checks: traceability (441 bounded records), architecture
boundaries, repository security scan and whitespace validation passed. The full
redesign gate is historical evidence; this focused pass does not certify a new
full gate for the final source. No module coverage was promoted.
