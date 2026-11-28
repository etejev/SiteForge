# Quick candidate integration, November 26, 2026

The working tree combines prior Codex work, Quick changes, generated evidence,
and this integration pass. The starting tracked diff against `013393965a49`
was about 84,000 additions and 18,000 deletions across 71 files, alongside
119 untracked paths. This is a worktree measurement. The Quick-only count
and elapsed engineering time would require a common baseline and the Windows
write ledger. The [Quick activity log](../coordination/CODE_FORGE_ACTIVITY.md)
and the [lane R](LANE-R-SUMMARY-2026-11-26.md) and
[lane V reports](LANE-V-SUMMARY-2026-11-26.md) preserve claimed scope and
Windows restore-point identifiers. Those restore points were reported by Quick.

## Verification map

| Area | Requirements | Automated evidence to inspect in the full run |
|---|---|---|
| Editor and reusable authoring, batches 01–08 | SF-0405, SF-0506, SF-0508, SF-0602, SF-0903 | Native minimum-width and launch journeys, fast styling and responsive fill, slots and variants, transform and clipping regressions |
| Project packages and local history, batches 09–17 and lanes A, E, I | SF-0204, SF-0306, SF-0307, SF-0309, SF-0906, SF-1301, SF-1306 | Package failure and reopen cases, migration backups, undo transactions, library identity, native File menu snapshot and compare journey |
| Assets, lanes B and F | SF-0803–SF-0807 | Resource validation and SVG, font, audio/video fixtures, used-assets accounting, retarget and undo |
| Interactions and localization, lanes C and E | SF-1007, SF-1101, SF-1103–SF-1106, SF-1506 | Runtime browser checks, canonical undo, keyboard and reduced motion, translation fallback, RTL geometry, localized exports |
| Collections and imports, lane D | SF-1001–SF-1005 | Strict collection data, published item pages, responsive lists, CSV/JSON rejection and bounds, undo and persisted history |
| Static output and release settings, lane H and cross-tree changes | SF-1204, SF-1206, SF-1208, SF-1211 | Output integrity, deterministic asset manifest, budgets, generated runtime, actual-browser narrow/wide output |
| Native testing | SF-1902-007/008 | Collector failure diagnostics, exact inventory selection, test outcomes and saved run evidence |

Lane reports provide test-level pointers. They are source review evidence.
The current source contains 1,150 regular and 181 native UI test method
declarations. The full run uses Xcode's executable inventory for its totals.
Native VoiceOver, on-device scale measurements, and user-visible verification
for the later authoring features require separate evidence where the automated
suite lacks journeys. No requirement is promoted based on documentation alone.

The current app and both XCTest targets passed `build-for-testing`.
All 37 collector tooling tests passed, and the floating progress helper
type-checked in Swift 6 mode.

## Integration findings

- The Swift compiler caught workspace initialization ordering, visibility across
  renderer/package files, malformed test literals, and tests that invoked
  main-actor document APIs outside that actor. Snapshot view implementation
  now lives in its own source file with the native menu journey covering its
  connection to the workspace and the version comparison sheet.
- Project-open capacity accounting retains only the largest encoded page
  size. Unsnapped transform preview reuses prepared geometry and uses an
  indexed selection lookup. No measured latency improvement is claimed.
- Collection images count toward the used-assets filter and retargeting.
  Reveal Usage and the global replacement disclosure use a separate inventory
  that omits those references. An image used only in a collection can be
  reported as unused there. Add collection-item identity and native reveal
  routing in a subsequent SF-0807 slice, with a collection-only fixture.
- The installed app's November 26 receipt `20261126-200200-62e81d55` rejected
  the current source fingerprint. The separate November 25 full run
  `20261125-201801-d8042c0e` reached UI discovery, where XCTest returned an empty
  inventory after an automation startup timeout despite reporting success.
  Neither XCTest target executed on that full run. The collector now displays
  the distinct causes and retains the original discovery diagnostics.

## Current native run

The separate owner-local build's Testing window started Full Verification
run `20261126-234542-c730ff8e` against fingerprint `8904b8567a4f`.
Source preflight passed on the original checkout after macOS resolved its
Documents access prompt. Repository verification and compilation passed.
XCTest discovered 1,150 regular tests. The UI runner timed out during
automation authorization; the macOS test service logged that authentication
was required. The collector held both targets, so neither suite executed.

The November 27 repair lets an unfiltered full run execute a ready target
when discovery blocks the other target. The overall result still requires both.
Explicit selector lists retain all-or-nothing validation. All 39 collector
checks passed, including regressions for both paths.

Retry `20261127-092146-994865f2` ran from the Testing window against an
isolated source copy matching fingerprint `ecbc5d638369`. Preflight,
repository checks, compilation and both inventories passed. XCTest found
1,150 regular and 181 native UI methods. The regular target executed first.

The SF-0904-007 scale test measured component resolution at 18.38 seconds
for 4,999 copies (10-second budget) and 72.09 seconds for 9,990 copies
(20-second budget). Sampling located a full page scan for each node in fixed
structural geometry's navigation-owner lookup. The working tree now builds a
per-page owner index for that loop. The active full run uses the pre-fix
snapshot. Replay the scale test and affected native navigation journeys before
claiming a performance improvement.

The SF-0605-007 container-query scale test measured 242.03 seconds for 3,300
copies against a 10-second budget. Sampling found a separate page-wide
sizing and output-mode scan for every queried container. Evaluation now
resolves the page's output mode and fluid adapter once, reusing them for each
inset calculation. Static export already knows it is emitting static output.
Replay the existing container-query scale and canvas/preview/export parity
tests on the same candidate as the navigation change.
The working tree with both performance fixes passed `build-for-testing`;
timing and native acceptance for those fixes remain pending.

The regular target completed all 1,150 cases with 14 failures. Two scale
cases alone consumed 29 minutes. The follow-up adds three exact native
smoke selectors, uses affected scope by default, and enables XCTest timeouts.
Selected scale checks retain their original thresholds and stop the current
case on the first failure. The connected exporter also reuses the
navigation-owner index. The active full run is a baseline for the earlier
source and does not validate these changes.

The app and both test targets compiled with `ONLY_ACTIVE_ARCH=YES`.
The three built executables contained only arm64 on this Mac. The 39
collector checks passed, including the build architecture and enabled
execution-timeout arguments. All three smoke selectors resolved against
the existing 181-case native inventory. Recorded case durations add up
to 28 seconds for the three smoke cases, excluding preparation. The new
smoke action and timed scale cases still need a native Testing replay
after the active desktop run releases ownership.

## Regular-suite failure triage

The frozen run completed all 1,150 regular cases with 14 failures and kept
running the native target. Repairs in the working tree:

| Failure area | Working-tree change | Focused replay |
|---|---|---|
| Empty component slots restore defaults on detach | Apply slot projection when a copy has an empty marker but no supplied children | `CommandKernelTests/testDetachKeepsTheCopysOwnSlotContentsAndDetachUsesAndDeleteIncludesThem` |
| Automatic sizing fixture fails validation | Supply the Stack's required layout fields while preserving both position assertions | `CanvasRendererTests/testSlotContentsKeepSlotLocalPositionsWhenThePageUsesAutomaticSizing` |
| Collection item titles only escape one angle bracket | Use the shared HTML escaper for typed SEO metadata | `PersistedHistoryTests/testCollectionTemplatePageBuildsOneEscapedPagePerPublishedItem` |
| Authored overlay controls are disabled in Chrome | Enable ordinary buttons after installing user-triggered handlers; dialog and menu test items have authored dismiss actions | `TransformModelTests/testInteractionAndMotionRuntimesActualBrowserFocusTrapEscapePlacementAndReveal` |
| Capacity and package replacement fixtures | Use the clean-draft transition directly and require the validated fingerprint for deliberate replacements | `DocumentLifecycleTests/testProjectFileCapacityIsMeasuredWhenAProjectIsOpened`, `DocumentLifecycleTests/testSnapshotsSheetCreatesRenamesRestoresKeepingCurrentHandsOffCompareAndRecoversDamagedStorage`, `PersistedHistoryTests/testProjectPreferencesPersistAtLargeFixtureAndRespectPackageLimitAtStress` |
| Current packages with snapshots fail lifecycle reopen | Reuse the parser's validated migration payload and assert the direct read boundary in the two failing journeys; the reopen failure still needs a replay | `DocumentLifecycleTests/testLegacyOpenKeepsOriginalAsSnapshotBeforeUpgradedSaveAndBackupRestoresUndoably`, `DocumentLifecycleTests/testNamedSnapshotsSaveReopenRestoreToANewHeadUndoAndRecover` |
| Responsive audit exceeds its scale budget | Share the renderer's already expanded and evaluated page | `CanvasRendererTests/testResponsiveAuditStaysWithinBoundsOnStandardAndLargeFixtures` |

The app and both test targets compiled with these repairs. The six
interaction browser helper tests and JavaScript syntax check passed. A
standalone runtime probe confirmed that a click handler enables its button
and executes the action, while load-only and submit controls remain disabled.
The actual browser interaction journey, package reopen, and remaining scale
receipts are pending. The active UI run uses the earlier source copy.

## Native regression triage

The frozen UI run exposed failures in document history, Preview, component
insertion, responsive comparison, Inspector reachability and keyboard
traversal. The working-tree fixes target the shared causes:

- SF-0306-005: toolbar Undo and Redo use committed document transactions even
  while a native field retains focus. Replay the three failing toolbar journeys.
- SF-0901-004: the Component submenu observes the live workspace and disables
  self-insertion while the component is open. Insertion also rejects it at the
  command boundary. Replay nested insertion and two independent copies.
- SF-0401-006 and SF-0508-006: Inspector tests reveal native controls within
  the actual viewport before interacting. The minimum pane width and
  keyboard traversal still require native confirmation. The traversal
  journey requires each toolbar command exactly once in each direction and
  checks that the observed AppKit order reverses.
- SF-1201-004 and SF-1301-006: Preview and Snapshots journeys use stable
  accessibility identifiers and retain content assertions and failure
  diagnostics. Preview also clamps the range endpoint before incrementing it.
- SF-1101-007 and SF-1206-003: static preflight expands each page once for
  event and page-flow findings and indexes the first use of each image.
  The existing motion scale budget remains the acceptance check.
- SF-1902-008: exported per-case results must exactly match the enumerated
  selection, across resumed segments, before a successful exit can pass.
  All 43 collector checks passed. The hosted gate uses the same skip rules.

The frozen run provides the failure list. Replays are still needed for
the source changes and for unresolved keyboard traversal, comparison-width
restoration, and the two snapshot package reopen failures.
At this checkpoint the frozen run recorded 18 failures and three approved
owner-only skips among its first 128 of 181 UI cases. The app and both test
targets compiled, repository checks passed, and the staged test bundle
verified against source fingerprint `968b33bf25a6`. Requirement acceptance
and the installed app remain at their earlier checkpoint.

The frozen run finished at 2:06 p.m. Eastern with 1,136 passed and 14
failed regular cases, plus 154 passed, 24 failed, and three approved
owner-only skips in UI. The last six UI failures cover Inspector
reachability, project grid settings, responsive audit, semantic HTML,
value tracing, and the Welcome-to-Settings journey. The first exact regular
replay (`20261127-142529-a3dc2f20`) blocked on source-folder access before
building. The retry (`20261127-142815-da0666b6`) started the same 14 selectors
through Testing from a verified source copy, passed preflight, and entered
compilation. The 24 UI failures are retained in the frozen run's
failed-selector report for the follow-up UI replay.

## Workflow evaluation

Quick produced useful models, fixtures, domain-specific tests and a detailed
handoff across multiple subsystems. Integration uncovered mandatory repair
and native validation work. The available logs do not measure a net speedup.
Record authoring time, repair time and first green result separately in a small
future pilot. Quick remains paused. A useful pilot would assign one independent
test or pure model change, with exact files, requirement IDs, a frozen baseline
and a verification command. Assign one writer per file and let Codex run the
Mac acceptance before any second assignment.

## November 27 whole-checkout audit

### Scope and assurance

This audit covers the current worktree at source fingerprint
`c8b053f770353957f51137748b5f69fcfc3afadcc5d890f40487d62390acea17`
over commit `0133939`. There were 71 tracked edits and 121 untracked paths,
including review notes and generated evidence. Review used risk-based source
inspection, automated parsing, repository gates and the frozen run receipts.
This was a subsystem audit; it was not a line-by-line manual review or
certification that all enabled features pass. No production code was changed
during this audit.

The exact current source compiled the app and both test targets in the preceding
repair pass. A fresh repository check passed, including the credential scan,
headless architecture boundaries and 441 traceability records. All Swift
product and XCTest sources parsed, as did 33 Python and 23 shell files.
The older source in run `20261127-092146-994865f2` completed 1,150
regular tests, with 1,136 passes and 14 failures. UI execution was still in
progress, with 32 of 181 cases complete and seven failures at the audit
checkpoint. The run uses fingerprint `ecbc5d638369`; it cannot verify repairs
or clear findings on the audited source.

### Open findings by priority

1. **P1, the local gate can pass with the wrong completed selectors (SF-1902-008).**
   The collector records an inventory mismatch when a test event belongs to a
   different method. Completion can then be replaced by summary counts, with
   the final gate only rejecting zero or too few completions. An unexpected
   method can substitute for a missing method. Skips and expected failures can
   also satisfy the local completion count without a policy check. Compare
   normalized method identities and outcomes across all result bundles,
   including resumptions. Apply an explicit skip policy. The hosted gate
   already checks exact identities and outcomes.
   [Local detection](../../scripts/unattended-verification.py#L448),
   [local final gate](../../scripts/unattended-verification.py#L700),
   [hosted gate](../../scripts/ci-test-accounting.py#L139).
2. **P1, Website Preview's byte-range math can trap (SF-0803-004, SF-1201-004).**
   The loopback HTTP responder accepts a parsed inclusive upper bound and
   increments it before applying the file-size clamp. At the largest
   representable integer the increment overflows, terminating the preview
   process rather than returning a response. Clamp before converting to a
   half-open range. Review the extreme endpoints, suffix and open-ended policy
   together.
   [Range parser](../../SiteForge/BrowserPreview.swift#L95).
3. **P1, snapshot-bearing projects have failed to reopen (SF-0309-004,
   SF-1301-005).** The frozen run recorded `malformedPackage` after a named
   snapshot save and after saving an upgraded project with its migration
   backup. The candidate removes the duplicate archive parse and now tests
   the direct package read before the lifecycle open. The underlying failure
   boundary and the repaired save/reopen flow still need a targeted run.
   Ordinary Save/Open/Save As and the standalone snapshot package round trip
   passed on the frozen source. Keep this a delivery blocker until both
   lifecycle journeys pass.
   [Lifecycle adoption](../../SiteForge/DocumentLifecycle.swift#L1734),
   [named snapshot journey](../../Tests/SiteForgeTests/DocumentLifecycleTests.swift#L1000).
4. **P1, the export replacement decision is bound to a path, without checking
   the selected item's identity (SF-1206-004, SF-1209-004).** A folder or ZIP
   that changes at the selected destination while the build stages files can
   still be replaced. A native save-panel confirmation and path existence
   check give no proof that the item present at promotion is the approved
   one. Carry the selected destination's identity through staging and use the
   established replacement boundary, or require a fresh confirmation after it
   changes. Test ordinary external replacement during staging for both targets.
   [Folder promotion](../../SiteForge/CanvasRendererCore.swift#L1519),
   [ZIP promotion](../../SiteForge/CanvasRendererCore.swift#L1869),
   [Preview handoff](../../SiteForge/BrowserPreview.swift#L683).
5. **P2, unreadable component-library records silently disable copy protection
   (SF-0906-004/005).** The commit guard converts an invalid or unsupported index
   into an empty protection set. A project can edit previously tracked
   definitions and tokens before the owner explicitly removes the damaged
   records. Surface retained damage and require the recovery action before
   permitting mutations that cannot be checked. A project with no library
   records should still edit normally.
   [Commit guard](../../SiteForge/DocumentLifecycle.swift#L1407),
   [index reader](../../SiteForge/ProjectPackage.swift#L2727).
6. **P2, a collection template without published items can leave a dead link
   (SF-1003-003/004).** Static output initially assigns every ordinary page
   a route. An active template stops emitting that page, yet the old route
   survives if there is no published item to supply a replacement. A direct
   link may then point to an absent file. The collection model produces a
   no-published-items finding but the build compiler does not consume it.
   Derive available destination routes from emitted pages and carry the
   collection finding into the build report.
   [Route planning](../../SiteForge/CanvasRendererCore.swift#L2385),
   [template link targets](../../SiteForge/DocumentModel.swift#L11147),
   [collection findings](../../SiteForge/DocumentModel.swift#L11248).
7. **P2, asset usage and replacement disclosure disagree with collection usage
   (SF-0807-001/002/003).** The bulk used-asset scan includes collection items.
   Reveal Usage, the per-asset Uses menu and replacement disclosure derive
   from a scan that omits them. A collection-only asset can report zero
   uses and hide Use Another Asset Instead. Use one reference index with
   stable collection/item identity for disclosure and navigation.
   [Reference scan](../../SiteForge/ProjectResources.swift#L56),
   [collection-aware used scan](../../SiteForge/ProjectResources.swift#L109),
   [Uses menu](../../SiteForge/WorkspaceShellView.swift#L6802).
8. **P2, asset reference work still scales with assets multiplied by nodes
   (SF-0807-007, SF-1201-007).** The first per-asset Uses query on each
   document revision scans every page. The build compiler independently
   tests every asset against every output node. Build the lookup once for
   the current document or plan, then look up each asset. Benchmark projects
   with many assets and item pages, where output multiplication matters.
   [Editor cache](../../SiteForge/WorkspaceShellModel.swift#L7432),
   [export reference scan](../../SiteForge/CanvasRendererCore.swift#L4690).

### Coverage and remaining evidence

| Subsystem | Audit scope and remaining coverage |
|---|---|
| Canonical document, commands, persisted history | Reviewed schema gates, command transaction and undo boundaries, and history snapshot validation. Frozen transaction coalescing and history retention passed. Re-run migration, snapshot restore and identity-bound fixture cases on the candidate. |
| Package, file access, resources, recovery | Reviewed limits, staged replacement, descriptor validation, sidecar reads and writes, and snapshot/library storage. Ordinary Save/Open/Save As passed on the frozen run. Reopen and export destination identity remain unresolved. The existing platform boundary for hostile same-user rename races is documented in ADR-0007. |
| Canvas, editor, layout and authoring | Reviewed component expansion, slots, audit projection, responsive geometry, chrome and style controls. The first minimum-size UI journey passed. Frozen failure groups include component editing, link inspector state and Preview readiness. Re-run the compact editor smoke, slot geometry and scale budgets. |
| CMS, expressions and localization | Reviewed item routing and binding, localization output trees and metadata. A frozen localized export passed. Check empty collections, collection-only image usage and generated destinations. |
| Browser Preview, static output, export | Reviewed loopback confinement and request validation, runtime hydration, static output assembly, staged writes and asset integrity. The frozen asset-integrity case passed. Chrome modal/focus, native Safari preview, range handling and concurrent destination replacement still need evidence. |
| SVG, fonts, media and clipboard | Reviewed bounded import and parsing, canonical references and browser delegation. The frozen regular run reported no failures in the resource and clipboard suites. Fresh runtime media and SVG presentation, plus broader manual accessibility checks, remain unverified. |
| Local testing, packaging and hosted CI | Reviewed selector resolution, timing, startup authentication, results, packaging identity and hosted shard accounting. The current native smoke/timeout changes have build and tooling evidence; the exact local gate finding remains open. No hosted run was started. |

### Delivery order

First fix local test accounting and the Preview range trap, then replay the
snapshot reopen tests and prove safe folder and ZIP replacement. Next repair
library recovery, empty-template links and asset reference reporting. Run the
scale cases and the native smoke action on that candidate before reserving a
new full-suite run. Compare frozen UI failures with fresh focused journeys and
retain their artifacts. A green full run and installed-bundle fingerprint are
required for delivery of the broader candidate. Quick remains useful for
bounded scaffolding and test drafting. There is still no measured net speedup
for its large batch.

## November 27 focused delivery scope

The owner requested failed tests only for this commit. The local replay scope
is the 14 regular and 24 UI failures from `20261127-092146-994865f2`.
`20261127-142815-da0666b6` passed 11 of those regular selectors. The 24 UI
selectors will be replayed exactly. The three approved skips are outside the
failed-selector list. The hosted gate remains in force.

The three-case diagnostic replay `20261127-144916-4eabe05c` at
`098e7540922c60370d4ae0571f05315c39cba53e3435b3a2f7aa5e590952934c`
reproduced both snapshot failures inside the coordinated package reader.
It returned `ProjectPackageError.unsafeDestination` before resource
attachment, migration, history validation or adoption. Direct reads of
the same saved fixtures and the snapshot indexes passed. The candidate
preserves the requested canonical private path when the coordinator
returns its exact system alias. Descriptor-relative no-follow validation
still applies below that path. The revisit asserts the reopened path and
restored history alongside the original persistence and migration checks.
Both reopen selectors passed in `20261127-145357-166f25e7` at
`f2067f5be2266b8bc6a11f34001dfe9069241f24065cd203d0a0084a1c8a9ca1`.

The browser diagnostic in that replay passed eight of eleven checks.
The focus check timed out after Enter with the document ready and hidden.
Binding and popup checks subsequently timed out waiting for animation frames
on the hidden page. An independent probe of the compiled fixture reproduced
the hidden state when Chrome DevTools received the optional native virtual key
code. Removing that field kept the page visible while real Enter dispatch
updated the text binding. The fixture then passed all eleven checks in the
independent probe. The XCTest replay uses the existing isolated Chrome profile
and still sends real keyboard events and checks all eleven behaviors.
`20261127-151559-9508dcf9` passed the browser journey, project-file capacity,
and Snapshots sheet round trip at
`31fbf5fea43c2a25116a418b314ff981681f791f405b04c9e7c8450cb46eb38b`.
Together with the preceding receipts, all 14 original regular failures
have passing results.

Native baseline evidence shows an offscreen project-grid Apply control,
a value-source disclosure exposing its expansion number instead of its
provenance on that AX element, and a responsive audit row whose group
omits the explanation from its AX value. The candidate anchors Project
preference actions outside the form scroll, exposes the winner on the
keyboard-operable Value Sources button, and identifies the visible
explanation in the Responsive Audit row. The welcome journey also scrolls
Advanced into the actual sidebar viewport with preference drafts retained.
Native Testing started all 24 exact failed selectors in
`20261127-152034-6a7f2402` at
`0645982b053189991d085e59c24fc4066edfa79ac27db30b44bdf6a06c71ccda`.
The collector reports, XCTest results, and attachments are retained under
`~/Library/Application Support/SiteForge/TestingReports`.

The first segment reached four failures before the collector released the
desktop at a case boundary. Test recordings show a Privacy & Security
notification over the trailing toolbar during Preview and Undo clicks.
macOS attributed the notification to a Chrome helper launched during the
preceding regular browser test. The notice was dismissed through Notification
Center, and Testing resumed the 20 unresolved selectors on the same prepared
products. The earlier four results remain in the report and require a replay
on the clear desktop.

The resumed run completed all selected methods with 11 passes and 13
failures. Project grid Apply, component retention and two-instance history,
the deliberate minimum-width link test, and the Welcome Settings route
passed. The four toolbar methods were restarted on the same fingerprint
after reboot in `20261127-214654-e8cb63a6`. macOS timed out enabling
XCTest automation before any method executed. After the owner authorized
automation, the Testing window started the 13 unresolved selectors in
`20261127-215622-86b1f7fd` at
`e2169d1a97f4b213a55e5756040bc942ebd0b43f59023cb0d5d893e61c233ef3`.
Both Aurora journeys, Safari Preview refresh and stop, and Button Link
Undo/Redo and reopen passed after the desktop was clear.

The container command treated a previously unnamed object as inactive when
choosing its feedback, even with an independent width. Naming now checks
width eligibility and the active-container predicate still requires a name.
The native replay also checks the semantic text exposed by AppKit, authors a
Desktop width before asserting authored provenance, measures the compact
pane from the canvas divider and window edge, and includes History in
forward and reverse traversal. The comparison test checks the current
sample's exact viewport field because its description also mentions the
Desktop reference width.

The 13-selector replay finished with nine passes and four failures.
Responsive comparison and audit, keyboard traversal, semantic HTML, and
Value Sources passed along with the four toolbar journeys. The container
rule successfully hid its child when the range matched, so the journey now
retains the child's Layers identity, confirms the render change, and
reselects the hidden child to inspect the matching rule. The mixed-fill
check now scrolls its explanatory text fully into view. The compact pane
now supplies an explicit viewport size to the Inspector scroll view, and
the visible Compare Versions sheet exposes its controls under one named
accessibility group. These four methods are in `20261127-221824-6546a6d7`
at `b6026ba9fb8dc4896899a9aa5ba2ad53bbf2d9dd332a3c9113ad1cff4865f299`.

Container query status and Snapshots-to-Compare passed. Both remaining
checks reached the intended controls. The mixed-fill reason used the
current background-fill text, and the compact check had been looking up
the quick ramp instead of the separate list with six stop rows. The two
test assertions were corrected and replayed in `20261127-222758-966af0e1`
at `42b2890597aeedac1c954b10446700914134bc803c444ff70b684fcedcd3180c`.
Both passed. The union of passing selectors matches the original 14
regular and 24 UI failures exactly. The final run includes the compact
Inspector image `attachments/ui/0/8D3361E5-B41A-43AF-A3B3-44CF9CECAED4.png`.
The owner-local packager installed build `26.11.28` with the same source
fingerprint. The app and progress helper passed strict signature verification.
The installed harness script matched the checkout and the harness manifest
matched the installed app and final report.
The staged audit then found line endings in three added ADRs and extra
terminal newlines in two Swift sources and one Markdown file. The two
Inspector selectors passed again in `20261127-223727-68efdf0a` after this
whitespace-only cleanup. The final installed build and harness match
`8f1d7ae12b92050568c82339681e26d3355fddc7a046b5fcd065b5650894bff0`.
The final run's compact Inspector image is
`attachments/ui/0/957F7D32-4AA8-487A-8F5D-99A8CE079FA3.png`.
