# Owner correction and regular local delivery

Status: DONE (bounded acceptance), 2026-10-15. Local commit authorized;
push, publication and distribution signing are not authorized.

## Final authoritative acceptance

Final `./sf verify` exits 0: 636/636 unit/integration and 119/119 UI =755 tests,
zero failures or skips. Repository/security/traceability/architecture/evidence
checks and build pass. Bundle `full-ccd26b85-b343-4b99-a179-af63921dd057.xcresult`.
All four prior interaction repairs pass in the full run; the compact native
overflow follow-up also passes. Its final full-run duration is 35.638 seconds.
Original-size visual review covers all twelve interaction captures and both
compact page captures, plus the installed-app evidence documented below.
Final installed source fingerprint:
`a3a19bf4a4b6af0fbe0dd89250519db92923abe15f137a8862c132dc3db6525e`.
The regular app is locally ad-hoc signed, not a distribution/release artifact.
Original recovery's 69 files remain hash-identical; no test runner remains.
No publish-during-view-update or invalid-geometry log was found. The result
still records 47 internal QoS warnings, not diagnosed as fixed by this slice.
No normative module, broad output parity or release gate is declared complete.
The chronology below preserves failed attempts; pending wording is historical.

## Contract and reviewed evidence

Bounded SF-0201-003/006/008, SF-0203-002/006/008, SF-0301-004/006,
SF-0306-003/004/005/008, SF-0307-003/005, SF-0502-003/005,
SF-0701-001/002/003/006/008, SF-1102-001–008, SF-1201-003/006/008,
SF-1203-003/006. No normative module or release gate is complete by this entry.

All three owner photos and reference renders 01, 05 and 12 were inspected.
The photos show intrinsic-width tabs leaving unused sidebar width, weak
Inspector grouping, repetitive implementation prose and inapplicable component
controls. Reference direction preserves the separately approved compact toolbar,
simple global Settings, centered bounded hint and self-service Advanced testing.

## Completed baseline collection

Run 20261015-103239-d7607136 completed with repository/build passing, 614/623
non-UI and 108/118 UI passing: 19 failures, 722/741 passing overall. The collector
continued through all selectors; no duplicate run or source edit occurred while
it was active. Persistent report, raw logs and both result bundles are retained
in the ordinary Testing Reports store. This is a failed baseline, not acceptance.

Initial diagnosis includes exact node-array order lost during removal Undo;
invalid or stale fixtures in static output, package version and multi-selection
tests; inaccessible/overscrolled Inspector controls; missing empty-state controls
on a nonblank fixture; and Header command availability. Each repair must retain
the underlying history, persistence, focus and accessibility assertion.

## Historical acceptance and repairs

### Complete collection and compact-menu follow-up — 2026-10-15

`full-52e53c3f-cf34-4ff2-9329-ec0a7a10d450.xcresult` completed: 636/636
model/integration and 118/119 UI passes (754/755); one compact static-page
journey incorrectly queried a direct Interactions tab. Its retained hierarchy
exposes the shipping `inspector.tab.overflow` MenuButton instead. The journey
now uses the existing native adaptive-tab helper; protected-page and live-target
assertions are unchanged. Exact follow-up passes 1/1 (36.095 seconds), result
`focused-05172bda-cd55-465f-ba93-97ba4fd1c3b4.xcresult`. Both captures in
`compact-static-page-overflow-captures` were reviewed at original resolution:
readable complete page sheet, selected Interactions overflow destination,
Contact target, fitted canvas and aligned Button. Final clean gate is pending.

### Focused native recovery and acceptance — 2026-10-15

Owner normal Xcode restart resolved OD-021. Result bundle
`focused-12051511-6976-4c42-8383-e2a1d9b8780e.xcresult` passes 4/4:
Inspector workflow (156.242s), Preview navigation (40.264s), minimum workspace
fill controls (90.162s), responsive layout/visibility (113.177s).
All twelve captures in `four-interaction-repairs-final-captures` were inspected
at original resolution. Tablet clips canonical off-artboard content; Mobile
keeps identity/status without ghost rendering; hidden Layers inspection is
truthful. Inspector controls remain readable and scrolling is intentional.
Preview visibly reaches Contact. No new composition correction was needed.
Regular app installation succeeded at fingerprint
`0b263c7be7cb3d46078795ad0a8caa3344885834fcc3100ef548fd3987791aef`.
Prior failed runs below remain failed history. Final complete verify is pending.

### Current native automation boundary — OD-021

Latest accumulated attempt `full-db6ab2ec-5194-4f39-822e-bba96d12dac6`
finished failed: 636/636 model tests, 93 UI passes, four UI assertion failures,
and one subsequent runner initialization failure (729/734 recorded total).
The four assertions were inspected independently rather than classified as
infrastructure:

- `testInspectorWorkflowSearchPinGeometryPasteUndoAndMixedJourney`: retained
  hierarchy proves both selection rows and Mixed geometry are correct, while
  the contextual Inspector Tools disclosure is collapsed (`value: 0`). The test
  now reveals the actual disclosure before requiring the mixed explanation,
  disabled Copy, atomic Paste, and preserved selection.
- `testMinimumWorkspaceContainsViewportAndScrollableFillInspectorControls`:
  Add Gradient was considered AX-hittable but lay below the scroll viewport.
  Add Gradient/Add Stop now use the existing complete-frame, live-query pointer
  helper. Full containment, six-stop state and compound-row assertions remain.
- `testResponsiveContainerLayoutAndBreakpointVisibilityJourney`: the columns
  field was below the scroll viewport and typing had no keyboard owner. The
  existing safe reveal/focus/field-owned replacement helper now drives gap and
  columns. No fake controls, direct commands, sleeps or relaxed focus checks.
- `testLocalPreviewFollowsAuthoredPageLinkWithBackForwardAndNoEditorMutation`:
  retained recording shows Home still displayed after the Link button click.
  Transparent native raster text did not establish a SwiftUI plain-button hit
  region. The production link label now explicitly defines its authored
  rectangle as the button content shape. Canonical links/geometry are unchanged.
  This repair still requires actual native navigation acceptance.

All corrections compile. Both the ordinary focused invocation
(`focused-9de73577-ad31-4609-9ed0-c172a87333fc`) and supported already-built route
(`four-interaction-repairs-native-prebuilt`) executed zero tests: XCTest timed
out after 60 seconds enabling automation mode. No SiteForge runner/app/xcodebuild
remains active; console inspection shows an unlocked logged-in session. No TCC
reset, permission broadening or shared system-service termination was attempted.
OD-021 requests a normal owner Xcode restart before resuming the four selectors.

Focused non-UI follow-up passed 4/4, zero failures (0.075 seconds), in
`focused-b7d655bf-06d6-49f7-add5-049194f47f72`:

- `CanvasTextRenderingTests.testFittedPreviewTextSharesCanvasMetricsWithoutNativeFontTruncationOrChrome`
- `CanvasRendererTests.testPreviewNavigationScalesLayoutAndHitBoundsInsideAuthoredOwner`
- `CanvasRendererTests.testResponsiveContainerVisibilityExcludesHiddenChildAndReflowsSharedScene`
- `TransformModelTests.testContainerLayoutRegistryValidatesMixesResetsAndPreservesExactHistory`

The latest installed bundle predates these last interaction corrections. Earlier
installed visual passes are retained as evidence for their exact source snapshots,
not proof of the unexecuted repairs. Final full gate/local commit remain pending;
all normative modules stay Partial. Nothing was pushed.
Repository/security/traceability/architecture/evidence checks and `git diff --check`
pass after reconciliation. All 69 original owner recovery hashes still match.
No test runner is active at the owner-action handoff.

The subsequent full attempt (`full-346d27df-755c-4005-9112-497139f6b8a6`)
passed 636 model tests and the repaired Settings journey, then exposed obsolete
single-node Header/Footer expectations in the nested-layout journey. Current
Header and Footer each contain five canonical editable nodes. Desktop/Tablet
therefore resolve 14 objects after nested insertion; Mobile resolves 12 because
its two closed-menu Home links remain canonical/Layers entries but deliberately
have no canvas paint/hit/AX surfaces. The focused corrected journey passed 1/1
(105.140 seconds), preserving stable selection, positive geometry, provenance,
Undo/Redo and Desktop → Tablet → Mobile → Desktop checks. Its four captures in
`nested-chrome-final-captures` were inspected at original resolution: bounded
artboard/pasteboard, aligned nested selection, upright content, truthful Mobile
menus and no ghost link surfaces. The shared count predicate now matches the
complete semantic field (1 cannot accept 12), strengthening adoption assertions.
No product geometry or hierarchy was changed to satisfy these expectations.
This interrupted full attempt is retained as failed, not accepted.

The next full attempt (`full-5a081030-30dd-4e29-930b-b56b7d274067`)
passed repository/build and 636/636 model tests, then exposed a genuine Settings
accessibility-container defect. Settings was visibly open in the retained
hierarchy, but SwiftUI forwarded the outer `settings.root` identifier onto both
native scroll views, replacing distinct sidebar/content identities. The root
now explicitly contains its accessibility children. The unchanged
`testConceptAlignedSettingsSidebarAndInheritedAccessibilityJourney` passed 1/1
(24.021 seconds), retaining all seven destination, geometry and inherited-
preference assertions. All seven captures in `settings-root-container-captures`
were inspected at original resolution and preserve the approved fixed layout.
The failed full attempt was interrupted after the connected Header journey
passed, rather than continuing an already-red gate; it is not a full pass.
The regular app was safely refreshed again with source fingerprint
`215dcbd91f5aacd8a64dcd92f9d48980cc2dffa33efa6774ce2c9f8d3a40c1c6`.
Its exact installed rerun passed 1/1 (23.627 seconds), exit 0, with seven
destination screenshots retained in `installed-settings-root-container-captures`.
All 69 original recovery hashes still match after this installed run.

Latest installed evidence supersedes earlier pending descriptions below. The
final full gate and reviewed local commit remain pending, not accepted yet.

### Installed production smoke and Preview text correction

The refreshed regular installed artifact and its provision match source
fingerprint `4e67f9b22548c30b17b88585e01d9d4a642c53e778c570a4b28dfc283326ecd5`.
Safe replacement retained a recoverable previous bundle and refused active-app
replacement until the owner quit normally. All 69 previously recorded recovery
files still match their original hashes after the installed smoke.

Computer Use remains unavailable specifically for SiteForge (Finder works).
Acceptance therefore used a copied standard native XCTest runner targeting the
actual installed app, not the temporary development product. The ephemeral
black-box `InstalledOwnerSmoke/testInstalledWelcomeConnectedSiteSavePreviewExportAndReopen`
imports no SiteForge code and supplies no product launch arguments, fixtures or
mutation hooks. It passed 1/1, 222.566 seconds, exit 0, in
`installed-production-shared-preview-final.xcresult`: own blank project, genuine
Header/Section/Footer, title edit, native Save, Preview, actual local static HTML
containing the title/header/footer, Close/Open, retained title and normal Quit.
The initial production launch also exposed Welcome and Review/Later without
restoring/discarding owner recovery. When macOS restored a closed-window state
after an aborted modal attempt, the smoke used the actual File > New command;
no preferences or restoration/recovery data were deleted.

The first smoke helper incorrectly used app-level Command-A in native modal
fields and an ambiguous Open title also present in Touch Bar. It now uses the
repository's ordinary field-owned keyboard selection with exact value equality,
then the native OKButton identifier. A forwarded Go-to-Folder field can report
inherited AX disabled while keyboard-focused and operable; real field input and
exact value replacement are required, not a model shortcut. Those failed smoke
attempts remain retained; they are not counted as product passes.

Original-resolution review caught a genuine Preview defect despite successful
Save/output: SwiftUI's unscaled native Text truncated the fitted Header title
and fabricated default text backgrounds/borders. `CanvasPreviewTextView` now
uses `CanvasAuthoredTextLayerFactory` and `CanvasTextLayout`; text stays upright,
fully visible and metrically consistent, with group opacity applied once and
native link pointer ownership preserved. No canonical geometry or data changed.

Focused regression run passed 3/3, exit 0:

- `CanvasTextRenderingTests.testFittedPreviewTextSharesCanvasMetricsWithoutNativeFontTruncationOrChrome`
- `CanvasTextRenderingTests.testDefaultWebsiteTextInkIgnoresEditorAppearanceAndMatchesInlineLayout`
- `CanvasRendererTests.testPreviewNavigationScalesLayoutAndHitBoundsInsideAuthoredOwner`

The new test covers 0.125/0.25/0.58/1/8 presentation scales, 1×/2× backing,
visible glyph pixels, exact shared metrics (floating epsilon tolerance), no
invented text box, opacity, pointer non-interception and invalid geometry.
It does not claim complete Preview/export parity.

All six captures from `installed-production-final-captures` were inspected at
original resolution, with readable unwrapped tabs, contextual Inspector groups,
upright complete title, aligned selection, fitted page/pasteboard, truthful Saved
status and no external automation overlay or stale authored object:

- `F1712F7B-CD7B-4CC2-89AF-B633FAF20CD3.png`: native initial blank surface.
- `2CBD4975-9B5D-4BE8-84A1-31EE17A02479.png`: edited title and Inspector.
- `41E64546-E022-482E-B6AE-9BF2DB7BBB4F.png`: connected fitted page.
- `8766D606-F58A-4472-AD60-857CFD0268B0.png`: corrected Preview.
- `2F6EA457-0E2A-4FC3-8956-167DECDC8546.png`: successful static output.
- `A913A4C4-9388-412B-9051-AB25891FCC02.png`: native reopened Saved project.

The installed native group passed 3/3, exit 0, in
`installed-settings-header-recovery-final.xcresult`:

- `testConnectedHeaderFooterNavigationMenuHeightUndoAndReopenJourney`: 258.445 seconds.
- `testFixedSettingsSharesCardWidthTitlebarClearanceAndReopenGeometryJourney`: 33.977 seconds.
- `testProductionRecoveryDiscoverySupportsKeyboardRestoreAndDiscard`: 15.965 seconds.

All 17 captures in `installed-settings-header-recovery-captures` were reviewed
at original resolution: seven connected Header/Preview/reopen states, seven
Settings destinations plus reopening, and two welcome/recovery states. Cards
share the fixed window/sidebar geometry with readable labels and titlebar
clearance; Mobile navigation is bounded, text upright and selection aligned.
No ghost object or external automation overlay appears. Advanced truthfully
retains the failed baseline Testing report; that historical report is not a new
execution or a fabricated green result. The run log contains no publishing-
during-view-update or invalid-view-geometry warning. All 69 original recovery
hashes still match. No runner remains active. Final accumulated gate pending.

Shared full-width tabs and contextual Inspector hierarchy; preserved recovery
with a welcome/Later route; dedicated Header/Footer title/page/menu/custom layout
editing through existing typed commands; focused tests and original-resolution
installed-app screenshots; actual save/reopen/Preview/local output; one green
accumulated collector including repository/build/code/UI checks; reviewed local
commit. No success or final totals are claimed yet.

## Focused repairs observed

All nine previously failing code selectors passed across the nine-test repair
run and the corrected Image fixture follow-up. Removal Undo now restores both
ownership order and canonical node-array order via an optional historical-command
storage index. Invalid current-schema fixtures no longer stand in for legitimate
unsupported targets; mixed paste fixtures now select both intended nodes.

The shared sidebar allocation and recovery Review/Later model tests passed 2/2.
The actual geometry/keyboard/Undo/Redo/accessibility journey passed after adding
proper inset Geometry grouping; its screenshot was reviewed. Follow-up source
refines the remaining shared section surfaces and measured label insets.
Twenty collector tests passed, including a real temporary Git-index staging
test proving source fingerprints change for content, not tracked-file ordering.

All three additional Settings photos were inspected. The root now uses a fixed
sidebar instead of NavigationSplitView; the existing 680-point Support form is
the shared width. Preferred logical content is 970×740, with 250-point sidebar,
20-point detail gutters and 24-point page insets (632-point card width). The
native policy removes resize/full-screen/zoom and restored frame-size ownership
only for the marked Settings window. Smaller displays use one bounded geometry,
not destination-specific widths. Model and native acceptance passed as recorded
below; regular installed-app acceptance remains pending.

## Editable contents integration (focused acceptance ongoing)

New schema-17 Header/Footer contents use ordinary Stack/Text/Link nodes. Title
visibility/text, page inclusion, hamburger and content layout route through
PageStructureCommandRegistry and the existing atomic kernel. Page inclusion
preserves hidden link identity; conversion is explicit for legacy containers.
Page duplication remaps the three role references, while old schema packages
remain unchanged on load. ADR-0020 records this extension.

The new title/inclusion/customization/exact-history and explicit legacy-upgrade
selectors passed together (2/2). The independent duplication/static-navigation
selector passed in the affected InsertionModel matrix. The native template
insertion/Undo/Redo journey passed after using the current visible menu names
and exact five-node default Header/Footer subtrees. Native navigation exposed
a duplicate menu projection on outer and nested surfaces; source now attaches
it only to the Navigation Stack. Focused rerun is active; no pass is claimed.

Settings model policy passes. Native checks confirmed identical 632-point cards
on Appearance/Canvas and fixed window size, but exposed a missing read-only
Accessibility group in the accessibility tree. The production static section
now has its own containment semantics; its native rerun remains pending.
The adopted-frame test now waits for the matching viewport generation, rather
than assuming an arbitrary number of executor yields completes renderer work.

The fixed Settings journey subsequently passed (1/1). All eight original-
resolution captures (seven destinations plus reopen) were inspected: common
card bounds, native titlebar clearance, persistent sidebar and readable labels
are consistent. Typography and Button/Link save/reopen native journeys passed.
Their native captures show upright text and aligned selection geometry.

The affected follow-up retained useful failures: native disclosure triangles
were still collapsed (AXValue 0) after label-center clicks; a state-color field
was below the usable Inspector viewport despite reporting hittable; a canvas-
center click intentionally landed on the bounded empty hint. Corrections now
use a full-width native Button disclosure row with explicit Expanded/Collapsed
semantics, preserve scene-local expansion, use balanced child-section padding,
bounded pointer-safe scrolling and test canvas input outside the hint. The
earlier arrow-relative click experiment did not fix native action bounds and
was replaced, not retained as an offset workaround. Mixed Content, positioning
and canvas-input journeys subsequently passed 3/3; the slot-fallback journey
also passed through cancellation/history/reopen. No focus/expansion/history
assertion was removed. Retained-recovery text accessibility still needs repair.

Visual review also found redundant typography commits displayed as a red error
and old Mobile navigation links rasterized as ellipses. The responsive scene
now projects one Menu surface while retaining canonical member IDs in Layers;
its new focused model test passes. Repeated equal typography commits now report
"Typography unchanged" without a validation error or extra history entry; its
new exact-Undo regression passes. Final native captures still require follow-up
before acceptance.

The expanded focused run completed with six passing selectors and one retained-
text accessibility failure: three model checks, slot fallback, two linked text
instances and Header/Footer title visibility/page inclusion/Preview/reopen passed.
The retained value's identifier belonged to a wrapper while its value belonged
to nested selectable text. The shared value surface now publishes one explicit
semantic value without changing canonical recovery or weakening its assertion.
Original-resolution Header/component captures show upright content, contained
selection, readable labels and Preview navigation to About. Customization now
groups its children into one inset section and gives Gap a persistent label.

The first follow-up was cancelled, not passed: a process sample stopped in
Data(contentsOf:) and macOS TCC recorded a Documents-folder permission prompt
for the isolated model-test host. No privacy permission was granted or reset.
Historical fixtures are now copied into the unit-test bundle, just as they were
already bundled for UI tests; the three raw checkout-reading model helpers use
those immutable resources. Compatibility hashes/assertions are unchanged. The
focused fixture/recovery rerun must finish before any acceptance claim.

Follow-up results: recovery/history and the immutable legacy-package fixture
passed 2/2. Strict legacy Button/Link decoding and the temporary-fixture
allocator passed 2/2; the allocator now asserts application-owned containment.
Repository/security/architecture/423-record traceability checks passed, and
git diff --check passed.

The static-text accessibility representation fixes the exact retained-value
assertion. The subsequent recovery UI run failed at its real confirmation
assertion, not at the retained value. Original-resolution inspection of its
recording shows the genuine reset dialog with a stale macOS Documents access
prompt above it. This is not a missing production alert. No prompt was approved
or security setting changed. Computer Use explicitly refuses the protected
UserNotificationCenter app; OD-020 records the necessary owner dismissal.
The failed result bundle ends in a1a39010-3c9f-4620-b0a2-2620445dd16d; its
recording attachment is 454056B0-4D74-4B39-844B-C4F5DB85924F. This recording is
diagnostic evidence, not a settled app-window visual acceptance image.
No test runner remains active. Final gate, installed smoke and local commit
remain pending; genuine owner recovery and the regular installed app are intact.

The owner then handled the permission prompt. The next recording confirms it is
absent; OD-020 is resolved. Native confirmation is a Sheet, not XCUI Alert, and
its destructive action also has a Touch Bar counterpart. The journey now scopes
the exact stable confirm/cancel IDs to the visible sheet, requires its heading,
one enabled/hittable action for each choice, Escape dismissal and unchanged
retained content. Restore-original/Undo and save/reopen already reached their
assertions before the Touch Bar ambiguity was corrected. The final same-selector
rerun passed: 1/1, zero failures, 211.793 seconds. The retained-value,
Cancel/Escape, original-binding restore, exact Undo/Redo and actual package
reopen assertions all passed. Four settled original-resolution window captures
were inspected: retained conflict, restored authored title, reopened intent and
confirmed reset. Labels are upright/readable and selection matches content;
no ghost or external overlay appears. The result bundle identifier is
focused-851c4d0f-9116-4bae-ad45-4d6a119d49ac.

The regular owner-local universal app subsequently built and installed
successfully with a recoverable prior bundle. Its source fingerprint is
be79d113640c3e03c8ac4885312ce3bf73c09392eee7932b0f1f2c44470fd3c1.
The 69 existing recovery files were byte-identical before and after normal
Quit. Installed interactive smoke is not yet accepted: two Computer Use binds,
including a fresh kernel, returned “Sky Computer Use native pipe closed before
response.” No alternate input mechanism or privacy-setting bypass was used.
Final accumulated verification and local commit remain pending.

The first direct final verification attempt did not reach tests because its
invocation mistyped the temporary DerivedData path; no product defect is inferred.
After correcting that invocation, repository/build passed and 634/635 non-UI
tests passed. One older Header test still expected navigation on the outer
Header instead of the canonical nested Navigation Stack. The run was deliberately
interrupted after that known failure (not a passing full run); the exact
xcodebuild exited and no isolated runner/app remained. The assertion now requires
the nested stable Navigation ID, outer owner ID, exact ordered links, hamburger
state and no duplicate outer menu. Its focused rerun passed 1/1 in 0.105 seconds.
No production mutation or original persistence/history assertion was weakened.

The following final attempt passed 635/635 unit/integration tests and fourteen
UI journeys before exposing an actual component-instance Inspector layout issue:
the top-level search field's native frame extended one point beyond each side
of its scroll viewport. Scrolling cannot repair horizontal containment. That
instance-property group now uses the existing shared inset section surface,
matching the other contextual groups. Pointer containment is unchanged; failures
also retain the real control/window diagnostics. The failed gate was explicitly
interrupted and its exact process exited; focused acceptance is running before
another final attempt. This is not an accumulated pass.

The inset correction's discovery journey passed (113.476 seconds) and retained-
recovery journey passed (213.818 seconds), 2/2 with no failures. All five settled
original-resolution captures were inspected: the focused search field and native
focus ring are fully inset, contextual groups/readable controls remain coherent,
and recovery/default/authored text stays upright inside aligned selection bounds.
No external overlay or ghost appeared. The two-instance text history/reopen
journey subsequently passed 1/1 (283.374 seconds); all five of its retained
original-resolution captures were also inspected with matching instance text,
selection, readable authored/inherited context and a truthful cancelled draft.
No runner remained after these checks. The regular updated universal package
built successfully, but installation correctly refused while the owner app was
still running; normal owner Quit was requested, not a process termination.
