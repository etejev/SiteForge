# Approved native interface redesign

[Approved reference and acceptance packet](../coordination/APPROVED_NATIVE_UI_REDESIGN.md)

## Starting candidate and references

All ten approved PNGs and the SwiftUI preview source match the SHA-256
values in the approval packet. The starting candidate was the installed
SF-0907 checkpoint, with source/test/tool diff SHA-256
`16ac0d194c36884fce132d4663503b705e37c6d025205de306172c8627d3577f`.

## Start and project lifecycle

Start uses the approved 224-point rail, three native template controls,
authorized recents, recovery entry, and the existing application Settings
window. The welcome shell, real loading progress, error-specific actions,
and recovery actions use the same palette and layout. The component uses
the byte-identical coastal asset already packaged in Aurora. Blank Site
retains the default launch focus and Return action.

The recovery-details sheet sits on the shared window root so the same
Inspect action works from Start and the workspace. Start discard asks for
confirmation and checks the original candidate fingerprint. The existing
controller and lifecycle remain responsible for permission, cancellation,
recovery ownership, and document adoption.

Bounded requirements include SF-0201-002/003/006/008,
SF-0204-002/003/006/008, SF-1502-002/003/006, and SF-1505-006.

The first focused run compiled and passed all 59 Launch Experience and
Workspace Material Policy core tests. Its UI runner reported failure to
activate SiteForge while the macOS console was locked. The owned collector
was interrupted with exit 75 to avoid repeating the same unavailable
desktop path. Its receipt is
`focused-15402019-9990-406f-a9b3-fc4a044ad1fe.xcresult`, with candidate
diff SHA-256 `724022feb7a22273dfb90eb8fe81424103bd62320f01231fc15e362d3fcc1256`.
The unlocked run produced the first four Start states and passed the real
open/retry and confirmed recovery discard journeys. It found inherited
SwiftUI accessibility identifiers on the recent-project row and recovery
details. The corrected replay
`focused-f5eba50c-032a-498c-afbf-7267be6272d2.xcresult` passed all four
selected journeys. Actual title-bar height required an 11-point content
alignment adjustment. Captures are 2880×1560 for Start and 2200×1400 for the
other states. Color comparisons use the embedded profiles converted to sRGB.

## Workspace and page actions

The first native workspace run
`focused-ff24d9bb-326b-432d-84d2-ae5b3b1dcf0e.xcresult` captured dark
Blank, dark Aurora About with pointer-revealed actions, and light Compact.
The Aurora, contrast/material, Pages arrow, protected-route, and canvas input
journeys passed. The compact navigator needed a narrower internal tab inset.
The AppKit preset boundary skipped the last page's row actions. Page Background
also needed the approved default Design tab to be visible in a fresh workspace.

The corrected replay
`focused-3c7ab3b7-6ef9-40e2-9535-64733530390e.xcresult` passed forward and
reverse keyboard traversal, Page Background fill with Undo/Redo, real viewport
commands, and native canvas input. It also identified two assumptions in the
earlier color tests and a toolbar test that still expected Component on the
rail. Those expectations were revised for the approved palette and tool order.

Bounded requirements include SF-0201-002/003/006, SF-0203-002/003/006,
SF-0303-002/003/004/005/006, SF-0405-002/006, SF-0701-003/006, SF-1503-006,
and SF-1505-006.

## Settings and test-window presentation

App Settings and the project-scoped Website Settings use the 201-point sidebar
and flat forms. Apply still enters the canonical Website Metadata command once.
Opening and switching between page drafts has no project effect. Test-window
presentation is Debug-only and uses the AppKit visible frame before the
specifically requested reference or safe-edge phase.

Bounded requirements include SF-0206-002/003/006/008, SF-0303-004/005/006,
SF-1207-002/003/004/005/006, SF-0201-003/006/008, and SF-1505-006.
Focused Settings and window tests, final captures, and the full gate are pending.

The first App/Website Settings and test-window run
`focused-9e9b82eb-4032-4afc-97d0-f38d7bea86f8.xcresult` passed the Start
visible-frame check, recent reopening, compact and safe-edge journeys, and
website metadata, cancellation, and history. The full Advanced destination
pass was held by Support retaining a redundant nested inset. Support now uses
the same scroll viewport as the other forms. The first light Appearance and
dark Website Settings images are 1720×940 and 1720×960 backing pixels.

The captured native Start frame is (0, 34, 1710, 990) in AX points. The
3420×2214 screen image includes the menu bar and Dock. The Start journey
returns to the same visible desktop geometry before keyboard adoption.
The repository checks passed (exit 0).

## Native captures and comparative replay

The revised native capture bundle
`focused-4118f2b9-778f-4fca-b6f8-442e1e7cfd96.xcresult` contains all ten
approved windows at their specified 2× dimensions. Both sides of the
comparison were converted from their embedded profiles to sRGB for
sampling. Sampled light Appearance, rail, sidebar, and compact pasteboard
pixels match exactly. Sampled dark panel, form, and rail channels are
within one RGB level of the approved source. The documented artboard
samples show the actual Aurora fixture and the true transparent Home
background. The native AppKit title bars, rulers, current document status,
and real testing availability are visible. The test build correctly shows
owner-local testing as unavailable.

The visual pass reduced the workspace viewport controls to one row at the
review sizes, added the current artboard name outside the authored content,
and tightened the Settings form hierarchy. The later polish pass
`focused-89de3ca2-8647-41b2-a935-3eab25c7a462.xcresult` captured the visible
Website Settings and Preview buttons, the compact 252-point Inspector
with text-only More, and the untruncated None fill value. The Support
diagnostics report journey passed with both generation and copying performed
through revealed controls in the real scroll view. The exact keyboard
traversal, Aurora, contrast, larger text, and toolbar journeys passed.
The page action replay identified an AppKit press sequence that could change
hover state between targeting and button dispatch. The reserved action
targets now stay available during that transition.

The final targeted native replay
`focused-b12ec478-7d0a-4b58-b70c-f6077e7ed79a.xcresult` exited 0. Dark
Editorial, Minimum Workspace and Page Management passed in 38.578,
78.964 and 153.052 seconds respectively. Minimum Workspace confirmed the
252-point Inspector and a contained, scrollable native gradient editor.
Page Management verified pointer Duplicate and Delete, the confirmation
and cancel path, Undo/Redo, saved reopen, and stable PageID with a long
name and revealed actions. The full stable-source gate is underway.

## Full gate

The first full attempt, `full-6135d123-a6ea-48c6-964f-91936d19cecc.xcresult`,
passed repository checks and the build. The core suite recorded 894 passes
and one failure. The invalid-draft test had requested the new default
Design tab while expecting an actual tab change. The owned run was
interrupted after the failure, with exit 73. The setup now selects Layout
before creating the draft, preserving the rejection, stale scope,
cancellation, and preview assertions. The exact core replay passed in
`focused-763d8ee7-2604-4e41-a8e8-69a25fe78034.xcresult`, and the full
suite restarted on that stable candidate.

The restarted full run,
`full-2c5de65e-3c64-4a09-8ddd-6990b05ae0ab.xcresult`, passed repository
checks, the build, 895 core tests, and 106 native UI tests, including the
long Safari menu and paint journeys. The Page Editor Select All journey
passed its native selection, replacement, cancel, and page-identity
checks. Its later numeric Inspector check still assumed Layout was
selected. The test now explicitly selects Layout before exercising the
existing width and height focus sequence. The next XCTest runner timed
out while enabling automation on the locked console. The collector
exited 65. One UI selector failed and 63 expected UI selectors remained
unrun. The runner failure is also recorded separately in the result bundle.

On November 16 the exact corrected Page Editor journey passed in 41.179
seconds in `focused-b3b037b9-a5db-44fe-8cbf-41250fffcb3a.xcresult`. The
full gate restarted on the same source with a scoped keep-awake assertion.

The full run `full-b2efadc8-c56c-47b1-b67d-9683eec742d9.xcresult`
reconciled all 1,065 expected cases, including all 63 previously unrun UI
selectors. It recorded 895 core passes, 165 UI passes, three owner opt-in
skips, two UI failures, and zero unrun. The UI selector inventory matched
the hosted timings inventory. The formerly interrupted Page Editor
journey passed in 39.670 seconds.

The Inspector strip journey measured the superseded 12-point labels and
32-point row. It now measures 10.5-point labels, 6-point outer insets, a
41-point row, and adjoining controls. Its small native drag correction
starts outside the resize grip's dead zone and retains the original
two-point tolerance. The corrected journey passed in 426.655 seconds in
`focused-7f76f966-7142-4ddd-ad31-daad3887cf21.xcresult`.

The reusable-style name field repeatedly failed to take mouse focus after
the test positioned the frame outside the canvas. The journey now starts
through native Blank, creates and applies the shared style on the same
Frame before repositioning, replays Undo and Redo, commits the absolute
offset, and returns to Design to verify the same object still carries the
interaction values. The original after-position click order remains
unverified. Temporary pointer instrumentation and a trial scroll identity
change were removed. The revised journey passed in
`focused-e5de8c00-2ec5-4ce8-9f31-d0da281af25f.xcresult`. The next full gate
uses these test changes and the previously captured application source.

The next full attempt,
`full-f37c6eb7-3b68-498e-9073-6726c652ae14.xcresult`, passed all 895 core
tests and 115 native UI journeys. It recorded three approved skips, two
failed UI selectors, and 50 expected UI selectors left unrun. The next
XCTest runner timed out while enabling automation. The Mac console was
locked, despite the running scoped keep-awake assertion.

The Safari attachment shows the collapsed Footer disclosure with
keyboard focus. Its AX identifier was empty. The test now queries the
exact live disclosure by role and label and checks expansion before Escape
and both collapse and focus after Escape. The style journey passed through
the absolute offset and the committed style assertions. Its last lookup
used the viewport's visible objects to check an off-artboard frame. The
test now checks the same selected stable ID in Layers. Both changes are
test-only. Exact native replay and a passing full gate precede installation.

The requested native replays passed on the unlocked desktop. Presentation
Context Comparison passed in 789.907 seconds and Positioning, Reusable
Style and Interaction State passed in 151.018 seconds. The separate
Automatic Narrow Chrome replay showed WebKit did not reliably expose an
expanded value or a hittable About link at that point in the narrow footer
presentation. The exact companion now checks its original click and Escape
path, with focus and collapse resolved together on the same named Safari
disclosure. The strict Presentation Context comparison retains its
independent DOM and pixel checks. The Automatic Narrow Chrome replay
passed in `focused-ab954427-b456-44cb-a004-3a9e90be3773.xcresult`.
The full gate restarted with those test-only changes.

## November 21 reconciliation and installation

The retained full gate finished on November 17 with exit 0 in
`full-d21f7db1-51b6-4005-aabc-31c8c1a660b1.xcresult`.
Repository checks and the build passed. The complete retained XCTest log
contains 1,065 unique terminal cases, with 895 core passes, 167 UI passes,
three approved owner skips, and zero failures, duplicate cases, or unrun.
All 170 UI identifiers match the source and hosted timing inventory.
The before, after, and November 21 current source fingerprints all equal
`eff35c8d14c4f8d9d7ac5c9b85a5b3c32604b76b61254d74eb19d80983fe9859`.

The retained xcresult bundle now reports a missing internal object when
xcresulttool reads its structured tests report. The reconciliation therefore
uses the complete command log, command exit receipt, and equal fingerprints.
The log inventory is retained beside the run as final-log-inventory.json.
This artifact limitation does not change the recorded test outcomes.

The owner-local packager installed build 26.11.21 on November 21.
Strict deep codesign verification passed. The installed Info.plist and
OwnerTesting installation.json both match the verified source fingerprint.
The install preserved the preceding bundle. Changes remain local and
uncommitted. The floating monitor starts from this installed checkpoint.
