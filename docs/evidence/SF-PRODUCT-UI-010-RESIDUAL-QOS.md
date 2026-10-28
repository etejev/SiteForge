# Residual runtime diagnostic classification

## Current bounded checkpoint observation — 2026-10-28

Final full-e7ee511e passes939 total:936 passes,0 failures,3 intentional
owner-session skips. XCTest records72 runtime QoS warning entries. No
publish-during-view-update or invalid-view-geometry message was found in the
current application/run log. The current summary supplies warning messages,
not enough new worker stacks for a stronger attribution or elimination claim.
Historical baseline stacks/classification below remain evidence for that
baseline only. No unrelated performance rewrite or warning suppression was
introduced; exact current artifact is indexed in the source-batch integration
receipt. Normative scale/performance/release acceptance is not implied.

Date: 2026-10-16. Read-only follow-up to accepted local checkpoint `ab18c66`.
Requirements: bounded diagnostic evidence for SF-1201-006/008 and native
accessibility/runtime observation under SF-0201-008. No new feature coverage.

## Accepted baseline remains unchanged

Inspected `full-ccd26b85-b343-4b99-a179-af63921dd057.xcresult`, its exported
diagnostics, test summaries, application output and session log. Result:
755 passed (636 model/integration +119 UI), zero failures/skips, zero build
errors/compiler warnings/analyzer warnings. The 47 runtime warnings are
separate from those build/result counts. No publish-during-view-update or
invalid-view-geometry message appears in the application/runner output.

## All 47 warning stacks inspected

Retrieved every warned test's `ActionTestSummary.warningSummaries` with
`xcresulttool get object --legacy`, including its timestamp and complete
`sourceCodeContext.callStack`. Symbolicated the shared Apple frames using
`atos` against AppKit/Foundation. All 47 have the same leading pair:

1. Foundation `-[NSConditionLock lockWhenCondition:beforeDate:]` +80.
2. AppKit `_getDataDetectorsScanner` +292.

| Count | Demonstrated triggering call path |
| --- | --- |
| 37 | `NSMenu(Accessibility)` attribute-count inspection → `_openForInspection:` → `_simulateOpening:` → Services menu population → `_NSMenuContext` Data Detectors filtering → scanner wait |
| 10 | `NSTextCheckingController` substring/check request → `NSSpellChecker checkString:…` → `NSSpellCheckerCheckString` → `checkDataDetectors` → scanner wait |

The first family includes `_NSMenuContext filterEntriesByDataDetectors:`
at +204 and `_NSServicesPrincipalMenuUpdater updateVisibilityOfServicesItemsForMenu:isForDisplay:`.
The second includes `checkDataDetectors` +148 and
`NSSpellCheckerCheckString` +5612. No SiteForge application frame or
project-owned file-coordination/render/save queue appears in these stacks.

Example correlations:

- `testButtonLinkContentTargetsUndoRedoAndReopenJourney`, 21:59:23.517 EDT:
  warning recorded immediately after a real Control label field double-click
  and live AX query; stack is native menu inspection, not the canonical edit.
- `testDesignInspectorMixedAndInapplicableSelectionJourney`, 22:36:08.658 EDT:
  native text-checking stack, not the mixed-selection transaction registry.

The exported system log retains 43 matching raw events (not a replacement for
the 47 complete XCTest warning records). All 43 come from the SiteForge
process, reported by Apple's `libRPAC.dylib`, subsystem
`com.apple.runtime-issues`, category `Hang Risk`, with antipattern trigger
`-[NSCondition waitUntilDate:]`. Thus these are Apple framework diagnostics
inside the application process, not simply warnings originating in Xcode's
own process. The captured waiter is user-interactive and the diagnostic
identifies lower-priority Default work. The worker's own stack/queue label is
not supplied; no more specific worker ownership is claimed.

## Other retained system messages

Application output also contains automatic `com.apple.linkd.autoShortcut`
registration/connection failures (NSCocoaErrorDomain 4097), CursorUI ViewBridge
disconnect messages, and XCTest automation-support `kAXErrorInvalidUIElement`
attribute requests during native element replacement. These are not hidden or
claimed absent. They produced no failed test, persistent AX loss, canonical
mutation failure, or demonstrated SiteForge-owned defect in this completed run.
SiteForge does not implement an AppIntents registration path to repair here.

## Disposition and validation

No production/test/source change is justified by these captured stacks. Do not
disable spelling, Data Detectors, Services menus, accessibility inspection or
runtime diagnostics to erase the warnings. Do not adjust application QoS on
speculation or alter shared macOS services/privacy settings.

Read-only checks: all 47 warning records inspected; two stack families account
for 47/47; final result and output cross-checked. No tests or full verification
were rerun for this documentation-only classification. The accepted 755/755
gate remains the baseline, not a newly executed result. Only evidence/handoff/
status notes changed, uncommitted for owner review. Installed app, canonical
data, history and recovery remain untouched. No owner action is required.

Reopen as a product defect only with a SiteForge-owned blocking frame/queue,
measurable product stall, failed semantic assertion or persistent accessibility
failure. A future macOS/Xcode update may change these framework diagnostics;
this inspection does not claim they have been fixed.
