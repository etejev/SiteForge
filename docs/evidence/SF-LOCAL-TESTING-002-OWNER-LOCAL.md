# Regular owner-local testing delivery

## Bounded contract

Owner supersedes the separate experimental app and workspace chooser. This is
bounded SF-0206-002/003/004/005/006/008, SF-1607-002/004/006/008 and supporting
SF-0201-003/006/008 evidence. Modules remain Partial; no publication, signed
remote installation or release acceptance is claimed. Feature counter stays 2/10.

## Production path

The regular app has one Advanced destination containing Run Full Testing, Run UI
Automation, current/last status, Open Progress, Open Latest Report, Reveal Logs
and explicit Cancel Testing. No Experimental Options switch, preference-scope
selector, preference-provenance badge or update-channel selector remains.
Existing preference records are preserved. Updates uses internal stable policy;
signature/integrity/compatibility and OD-017 installation boundaries stay closed.

`scripts/package-owner-local-app.sh --install` builds a normal owner-local app,
provisions its source location automatically in generated installation metadata,
and stamps source revision, fingerprint, dirty state and build time. Generated
absolute paths are local installation data, never committed source or website
content. It uses local ad-hoc signing only, preserves recoverable previous
bundles and refuses to replace a running installed app. The normal installed
bundle is the intended application; test products have separate owned identity.

The collector verifies the provisioned source fingerprint before launching and
after preparation. Missing/stale dependencies produce truthful unavailable or
blocked states. Tests use `app.siteforge.SiteForge.OwnerTesting`, unique derived
data, isolated website fixtures and generated test metadata with document-handler
rank None. They do not target the installed controller or owner documents.
Full mode selects the entire code and UI targets; UI mode selects the entire UI
target and marks unrequested code skipped, including interrupted preparation.
No model/chat, GitHub or downloaded executable code participates.

## Persistent reports and repair

Installed-app reports live in the user's Application Support directory at
`SiteForge/TestingReports/<run-id>/`. `current.json` identifies the latest run;
`state.json`, `report.json`, `REPORT.md`, stage logs, events, inventories,
failed-selector summaries and result bundles retain actual outcomes. Reports
contain installed/test identities, revision and source fingerprints. Unknown
totals are indeterminate, never fabricated. Cancellation records partial results
and terminates only the collector-owned process group. Closing progress or
Settings does not cancel the detached collector.

Before agent repair, compare report revision/fingerprint with the current tree.
Do not confuse a deliberately cancelled bounded launch check with a full pass.
Keep the Mac unlocked and avoid keyboard/pointer use during UI stages. Full Xcode
and legitimate one-time macOS/Xcode automation authorization remain prerequisites.

## Native document-title regression

`testNativeSaveAsUpdatesLiveDocumentWindowTitleJourney` passed 1/1 after a
direct lifecycle-observation correction. Native Save As writes the intended
package, publishes Saved, updates the actual clean window title and preserves
the rendered object. Original-resolution capture confirms the title and status.
The native title query is `windows[title]`; AXLabel alone is not AXTitle.
No persistence or window-presentation behavior was changed to satisfy the test.

Latest compact capture review additionally exposed a selected last-tab label
clipped by the horizontal tab scroller. Intrinsic sizing plus selected-tab reveal
passed the practical-minimum journey. The actual selected Components and
Accessibility labels are fully visible; offscreen destinations use the native
overflow menu. The test no longer mistakes an offscreen AX child for a visible
pointer target.

Installed connected-site inspection found two additional actual defects:
native Select All was missing and modern SwiftUI draft fields were classified
only as classic NSTextView; flow Inspector's resolved row read retained
insertion defaults. Native focused-value routing and adopted-frame presentation
correct these boundaries. The Desktop/Tablet/Mobile model regression passed;
the expanded page-draft/geometry native regression passed: actual Select All,
Escape, forward/reverse Tab with default provenance preserved, Return commit
and exact Undo. Native field-editor reconciliation writes the displayed string
on focus transfer; those untouched writebacks no longer author a default or
advance revision. Explicit Return still supports authored-value intent.
Installed-site continuation acceptance is in progress. Temporary responder
tracing and the ineffective classic-notification observer were removed.

`sf` also supports the explicit isolated OwnerTesting identity and matching
metadata for the direct gate. Four controlled harness scenarios passed: narrow
process matching, permission fallback/failure propagation, identity propagation
and rejection of unsupported identifiers. It does not broaden process cleanup.

## Protected-folder fixture correction

The isolated integration app's launch stalled before AX discovery. Retained
testmanager diagnostics confirmed session authorization succeeded and both app
PIDs reached foreground; TCC then requested Documents-folder access because the
historical base64 fixture was read directly from the checkout. No broad folder
permission was granted or reset. Historical fixtures are now bundled with the
UI target and staged byte-for-byte in its existing private temporary lease.
The fixture staging/0600-permission regression passed, and the blocked journey
subsequently reached native authoring controls. The production loader and golden
package bytes are unchanged. Remaining journey results are pending.

Subsequent focused runs passed native Design Save/Close/Reopen and the connected
Header/Footer/navigation journey. The latter now restores keyboard focus after
the genuine native menu closes. Captures obscured by a retained system permission
dialog are not counted as visual acceptance; clean installed-window captures and
local output acceptance remain required.

## Website text ink correction

Bounded SF-0406-001/002 and SF-0507-003: automatic website text ink is now neutral
black rather than the editor appearance's label color. Explicit authored RGBA
and filled-button contrast remain authoritative. Committed text and the inline
editor share CanvasTextLayout; local Preview preserves explicit authored ink.
`testDefaultWebsiteTextInkIgnoresEditorAppearanceAndMatchesInlineLayout` and
`testAuthoredTextForegroundSharesLiveLayerAndInlineEditorWithoutGeometryChange`
passed together, 2/2, including actual glyph pixels in light/dark appearances.
No authored geometry, typography property or package schema was changed.

Installed continuation exposed native Open being disabled after closing the last
document: its focused launch controller no longer existed. New/Open now transfer
one native request to the next window's live controller; cancellation does not
queue a request. `testNativeLaunchRequestTransfersOnceWithoutReplacingPendingIntent`
passed, proving consume-once and pending-intent preservation. The expanded
Save As journey also passed last-window Close/Open, Saved status and renderer
adoption, 1/1. Its clean reopened-window capture was reviewed: readable native
controls, centered paper/grid boundaries, upright Frame and no system overlay.

Installed Preview inspection additionally exposed unscaled intrinsic navigation
width and an outer accessibility-ignore group. Display-space layout now uses a
validated common projection, constrains the preview viewport and retains native
navigation children. The deterministic scale/bounds regression passed; final
actual-window navigation and visual acceptance remain in progress.

## Focused checks observed

- 19/19 collector tests in `Tests/Tooling/test_unattended_verification.py`: exact
  target inventory, full/UI selection, duplicate ownership, continuation after
  failures, cancellation, persistent reports, stale source, source changes during
  preparation and non-owning document metadata.
- Eleven distinct XCTest model checks passed: Advanced discovery, automatically
  provisioned source/report persistence and duplicate/cancel neutrality, missing
  harness/fixed update policy, pane allocation, seven Settings destinations and
  configured application identity, and canonical empty-page recognition that
  does not mistake hidden/off-artboard content for a blank page, adopted flow
  Inspector geometry, bounded Preview navigation, appearance-independent ink
  and consume-once native launch requests after last-window closure.
- Nine distinct affected UI journeys passed: centered empty hint/real insertion/
  Advanced/Close Window, light Settings preview/cancel, appearance Return/Escape/
  reset/relaunch, practical-minimum fill Inspector, grid/artboard presets,
  native Save As title, native Select All/Tab reconciliation, Design persistence
  and connected Header/Footer/navigation.
  Latest checks assert actual viewport center, pointer input outside the hint,
  complete normal-width destination containment and one-line gradient labels.
- The isolated OwnerTesting build passed two model checks and the real centered-
  hint/Settings UI journey. Arbitrary generated Info keys were not emitted by
  Xcode; explicit plist configuration fixes the identity propagation.

## Installed actual-window check

The regular installed app was inspected with an independently prepared, temporary
XCTest UI runner attached to the verified already-running installed executable.
This runner is not part of the application's full automation target and adds no
production hook. It never force-launches/terminates the owner's app or mutates
website content. `testAdvancedTestingUsesProvisionedHarnessAndSurvivesSettingsClose`
passed: automatic availability, real UI button, duplicate disabling, detached run,
native Settings close/reopen, explicit cancellation and retained report actions.
The original recovery candidate remained available across a normal native Quit
and relaunch. Source/artifact fingerprints matched in the actual retained report.
`testFullTestingButtonCreatesFullModeAndRetainsPartialReport` also passed through
the installed real Full Testing button, explicit cancellation, Open Progress,
Open Latest Report and Reveal Logs. Both modes produced persistent partial
reports, not false full-suite success. Six installed-window captures were
reviewed: ready, running and cancelled UI mode; running/cancelled full mode and
report actions. Labels are upright, controls readable and unavailable states
truthful. No owner website content was modified by these checks.

The initial installed check exposed a missing standard Close command: replacing
the new-item command group erased it. The production command now sends native
`performClose:` through the responder chain, preserving document close guards;
Appearance no longer registers a competing Cmd-W shortcut. Both affected
repository UI journeys passed afterward.

Native computer-use repeatedly crashes in SkyComputerUseService while reading
Settings (Swift Array.remove assertion), not in SiteForge. XCTest remained usable
for installed-window controls and app-only captures. The bounded launch checks
deliberately cancel before complete suites. Final full gate, broad connected-site
manual acceptance and accumulated source-only feature coverage remain pending;
this document does not declare the application or accumulated milestones complete.
