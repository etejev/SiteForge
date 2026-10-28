# Aurora local-builder delivery

## Current verified source and installed review — 2026-10-21

Final full collector `20261021-034253-d689cac6` passes 682 code + 133 UI =
815 tests, zero failures/skips and all repository/build checks. New independent
page reuse/navigation/contextual editing and repaired launch/token paths are
included. The regular installed Study-copy/Safari/native-reopen journey passes
1/1 (158.722s), with seven inspected captures and fresh protected package and
resource hashes unchanged. App/source/testing-provision fingerprints match.
See the responsive-workflow evidence for exact bundles, captures and limitations.

Only the extra installed Settings visual comparison remains pending OD-025:
a later launch timed out before tests; native fallback captured blank but lost
its pipe entering Settings. No waiver, permissions or force quit. Older
IN PROGRESS/full-pending records below are historical, not the current gate result.

## Unlocked native and regular-app delivery — 2026-10-18

The lock is resolved (OD-022). Exact focused native results:
- `testAuroraPackagedSampleCreatesEditableFourPageWebsiteJourney`: 1/1,
  50.549s, `focused-eea5449e-09dd-4a5f-ac2e-84bc2c630a7d.xcresult`.
- `testProductionRecoveryDiscoverySupportsKeyboardRestoreAndDiscard`: 1/1,
  16.472s, `focused-19cb517a-caba-44ce-9d82-357b53addd22.xcresult`.
- `testCrashQualifiedRecoverySeparatesFirstCleanAndInterruptedLaunchJourney`:
  1/1, 24.468s, within `focused-3adeb698-7ee4-43f6-81f3-273c60770e02.xcresult`.
  That combined collection also contains a failed added menu-disappearance
  assertion in the sample test; it is not a fully green collection. Native
  inactive menu items remain in AX. The invalid extra assertion was removed;
  the real Layout control settles the menu before the final passing capture.

The crash test creates one real Frame and recovery through ordinary controls,
quits a clean isolated app normally, and force-terminates only the live Debug
process whose PID, run diagnostics and executable path match the test fixture.
The owner's installed app cannot pass that path check. It then proves automatic
recovery is offered after interruption, not first/clean launch, and Later leaves
the exact snapshot unchanged. All 69 original recovery hashes still match.

The regular app was normally Saved/Quit before its authorized update. Installed
source fingerprint: `0a76a510a64ab351504e740e23fda56b2eb218ad1bdf6660cc0370a4b160c24c`.
It includes the owner testing harness/provenance, packaged sample, clean/crash
qualification, shared output and compact Direction corrections. No extra named
app copy was introduced. Actual installed black-box checks pass:
- `testInstalledAuroraSampleIsIndependentAndOriginalReopens`: 1/1, 38.945s.
- `testReopenSavedAuroraAndBuildCorrectedArtifact`: 1/1, 51.691s.
- `testCreateWorkflowStudyThroughNativeSaveAsAndRemoveOnlyValidationRecents`:
  1/1, 27.786s. Native Save As creates the separate Workflow Study; the delivered
  Editorial package checksum remains exact. Only the two positively identified
  validation Recents entries were removed through visible controls; no project
  file, authorization, recovery or genuine recent project was deleted.

Original-resolution retained directories inspected: `aurora-packaged-settled-captures`
(Welcome and editable Home), `recovery-history-unlocked-captures` (manual review),
`recovery-crash-real-captures` (clean launch, crash offer and inspection), and
`aurora-installed-sample-captures` (regular Welcome, independent sample and
reopened original). The first sample capture had a native menu fade and was
rejected; the settled capture has no menu contamination. A clipped Blank Site
subtitle was corrected with intrinsic vertical sizing, not shortened copy.

Current installed output is retained as `aurora-installed-safari-current.png`,
`aurora-installed-safari-mobile-settled.png` (390×844), and
`aurora-installed-safari-mobile-menu-normal.png` (574-point normal browser).
Native Return opens the menu, Escape closes while retaining focus, and Journal
navigation produces the correct `Journal — AURORA` title. Safari responsive-mode
AX focus/coordinate attempts did not provide a settled menu result and are not
counted as website failures or accepted captures. No speculative website patch
was made. The composed Desktop remains accepted; large fixed-height Mobile
gaps remain the explicit authorized workflow follow-up, not a solved layout.

Delivery source/native proof is now present. The integrated package remains IN
PROGRESS: source workflow improvements are underway on the separate Study;
the one accumulated full gate is reserved for the integrated ready state.

## Crash-qualified recovery source — 2026-10-18

Bounded SF-0306-003/004/005/006, ADR-0024. Only new recovery packages receive
versioned session/project/document/revision evidence. A private held advisory
lock identifies live app ownership; normal AppKit termination marks the session
clean. Automatic Welcome offers require abandoned running evidence. Unqualified
legacy/clean/live data stays available through explicit Recovery History.
Existing filename/package/fingerprint validation and retirement ownership remain
unchanged. Session evidence never enters canonical history and durable saves
remove it. No prior owner files were modified or removed.

Focused result: 7/7, zero failures, bundle
`focused-8cebb442-2596-4507-89f1-d560022915b7.xcresult`:
- `DocumentLifecycleTests/testRecoverySessionEvidenceSeparatesLiveCrashCleanAndLegacyWithoutChangingContent`
- `DocumentLifecycleTests/testRecoverySessionEvidenceRejectsUnsafeMalformedAndMissingMarkers`
- `DocumentLifecycleTests/testCrashQualifiedDiscoveryPreservesLegacyAndDurableSaveExcludesSessionEvidence`
- `DocumentLifecycleTests/testAutosaveCoalescesAndCreatesNewerValidRecoveryCandidate`
- `DocumentLifecycleTests/testUntitledRecoveryDiscoveryRequiresCanonicalFilenameAndMatchingProjectIdentity`
- `DocumentLifecycleTests/testUntitledRecoverySurvivesRelaunchAndCleansUpAfterRestoreSaveAndDiscard`
- `LaunchExperienceTests/testWelcomeRecoveryReviewAndLaterPreserveBytesAndDoNotLoop`

Additional launch-controller acceptance passes 1/1:
`LaunchExperienceTests/testInitialRecoveryOffersAbandonedSessionButKeepsCleanExitManual`,
bundle `focused-eb3ae24b-9dc8-4159-99ba-8711d9192584.xcresult`. It proves the
actual startup controller offers abandoned work, does not offer clean-exit work,
and allows manual review/Later without changing either snapshot or baseline.
Thus eight distinct focused checks pass. Native journey source builds for
testing successfully without launch. Repository/security/traceability checks and
`git diff --check` pass; these are not the integrated final gate.

The first four-test checkpoint also passed 4/4; it overlaps this result and must
not be added to the total. The production autosave path is asserted to attach
evidence. Tests also prove copied-project evidence, unsafe permissions,
hardlinks/symlinks, malformed/missing markers and unrelated directories cannot
qualify, while restored durable content/history retains the normal boundary.
Read-only checksum validation confirms all 69 original owner recovery files
still match. The coordinator reviewed the real Safari desktop/mobile/menu
delivery captures. Native sample/install and real clean-quit/crash visual
acceptance remain blocked by the locked console; no native retry or final
full gate was attempted. The subsequent workflow redesign has not begun.

## Packaged sample checkpoint — 2026-10-18

Bounded SF-0204-002/004/005/006. The exact ordinarily UI-authored Aurora
package and resource sidecar now ship as a visible Welcome choice. The normal
package/resource readers validate the source, establish fresh document/project
identity, preserve internal references and discard source history from the new
creation baseline. ADR-0023 documents the explicit read-only bundle resource
mode; private resource-store permissions remain unchanged.

Five focused checks pass in
`focused-7aa6895b-665e-464c-a3ca-694ea4745e60.xcresult`:
`testAuroraPackagedTemplateCreatesIndependentEditableResourceBaseline`,
`testPackagedTemplateRejectsUnrelatedOrCorruptCreationResourcesWithoutMutation`,
`testPackagedTemplateMissingResourceCancellationAndSaveReopen`,
`testBundledTemplateResourceStoreIsReadOnlyAndCannotEscapeBundle`, and the
existing `testStarterCreationUsesSameAtomicLifecycleWithCanonicalTemplateProvenance`.
The accompanying resource collection passed 22/24 initially. Its two synthetic
historical fixtures still contained a schema-18 metadata member; corrected
historical fixture construction (not decoder relaxation) passes 2/2 in
`focused-1b633273-71f9-48e9-a43a-49c3d8e6d296.xcresult`:
`testSchemaTenAssetOrganizationMigrationAndVersionGuard` and
`testImageAssetInsertionInspectorUndoRedoAndSchemaMigration`.

New UI selector
`testAuroraPackagedSampleCreatesEditableFourPageWebsiteJourney` compiled. Its
first collection was interrupted at launch when read-only console diagnostics
confirmed both lock indicators. Result bundle
`focused-5fd1bcb7-d14a-4029-99c8-e91a5ebb77ab.xcresult` records zero passes and
one canceled test (`Testing was canceled`), not an app assertion failure or
visual acceptance. No duplicate run was launched. The regular installed app
was not terminated/replaced and no recovery data was changed. Installed sample
acceptance and crash-qualified recovery remain pending; no full gate claimed.

The delivered website's shared compiler fixes pass 3/3 in
`focused-371f7194-1d33-47fd-add6-1f670c423b0a.xcresult`. Real Safari final
captures are `aurora-delivery-safari-desktop.png`,
`aurora-delivery-safari-mobile.png`,
`aurora-delivery-safari-mobile-menu.png`, and
`aurora-delivery-safari-mobile-journal.png`, retained with owner-local evidence.
They supersede earlier loading-only and pre-correction output captures. The
current ordinary project/export and prior prototype remain preserved.

## Latest metadata/native restart checkpoint — 2026-10-18

Requirements SF-1207-001–006/008, bounded Partial. The project owns a versioned
optional metadata record with stable PageID overrides (document schema 18).
Native File > Site Settings captures its opening identity, keeps drafts local,
and uses one central typed transaction. Empty/reset restores inheritance;
Cancel/Escape is neutral. History schema 3 retains old adapters and compares
all canonical content, not just pages/guides. Output escapes metadata through
the existing static compiler; favicon references use existing resource export
and safe asset dependency handling. Authored Header titles are never rewritten.

Focused passing results (overlapping reruns are not a full-suite total):
- PersistedHistoryTests: 22/22, plus native
  `testSiteSettingsMetadataApplyCancelAndUndoJourney`: 1/1 (49.593s), bundle
  `focused-7ba8f30d-8230-4339-9b2c-190b95f35370.xcresult`.
- Additional `testWebsiteMetadataForgedRedoInverseCannotHideOutsidePageContent`
  and `testWebsiteFaviconDependencyDetachUndoAndMissingOutputAreTruthful`: 2/2,
  `focused-0dab2c4d-3685-4db8-89d6-9061d66cfda0.xcresult`.
- Existing CommandKernelTests static layout stylesheet, verified responsive
  image reference, authored semantic element, Frame/Section fills, Frame box
  style checks: 5/5, `focused-ad308f16-4a99-4943-9fdb-90aa903af578.xcresult`.

New metadata tests in PersistedHistoryTests also include:
`testWebsiteMetadataLegacySchemaMigrationAndStrictCurrentShape`,
`testWebsiteMetadataRegistryRejectsStaleCancelledAndInvalidEdits`,
`testWebsiteMetadataRejectsMalformedValuesAndPreservesPageRemovalInverse`,
`testWebsiteMetadataResolutionRoundTripAndExactHistory`,
`testWebsiteMetadataOutputUsesEscapedResolvedPageValues`,
`testWebsiteMetadataSaveReopenAndRecoveryPreserveCanonicalHistory`, and
`testWebsiteMetadataDefaultHeaderTitleDoesNotRewriteAuthoredText`.

Both final original-resolution sheet captures were inspected:
`D61D5E58-29E3-4BB9-A3AA-AB713A2265E7.png` (draft) and
`9B77BF7B-60CD-4E20-B2FE-4282D7C34040.png` (restored canonical values), retained
in collector directory `site-settings-preview-final-captures`. Initial review
found the snippet below the scroll fold; the production preview now stays
visible above Cancel/Apply. Native fields are readable, no debug controls or
ghost authored content appear. Lower form fields intentionally scroll.

After normal owner Xcode restart, dark-editor and actual Safari journeys pass
2/2 (65.560s), `focused-5e3d2b6d-4c10-42c6-8081-12046844b910.xcresult`.
All eight captures in `owner-restart-dark-safari-captures` were reviewed at
original resolution. Dark shell/slim panes, white paper and native Settings
remain coherent. Safari stays pale. Native long-title truncation and default
purple/underlined Safari navigation remain observed output differences.
No publish-during-update or invalid-geometry messages were found in these
focused logs; Apple service/QoS messages remain, so runtime cleanliness is not
claimed. The first metadata test compile attempted a private helper and a
later UI compile named a nonexistent wait helper; both were corrected before
the passing real persistence/native runs. No failed build is counted as a pass.

This does not close SF-LOCAL-BUILDER-001. Crash-qualified automatic recovery,
completed UI-authored Aurora, mobile Safari fidelity, regular installed-app
delivery and the integrated final gate remain required. Social/structured
data, public-domain canonical configuration, language authoring, scale and
release SEO remain outside this bounded metadata checkpoint. No commit/push.

Repository/security/architecture/migration/evidence checks and `git diff
--check` pass after this documentation update. All 69 original owner recovery
hashes still match. No test runner remains active; the regular installed app
has not been replaced or terminated. These checks are not `./sf verify`.

Status: IN PROGRESS, 2026-10-16. No new acceptance or commit claimed.

## Dark render-01 direction — 2026-10-17, acceptance pending

### Current bounded visual checkpoint — 2026-10-18

The earlier failed experiments below are superseded by these observed results;
the integrated package and regular installed-app delivery remain IN PROGRESS.

- Native overflow/default-reset model checks: 2/2; dark sections and real fill-
  layer editing: 2/2, bundle
  `focused-68f535f0-3614-4054-8804-366328353e01.xcresult`.
- Native dark sections plus complete adaptive forward/reverse keyboard traversal:
  2/2 (117.685s), bundle `focused-8b449d08-fbaf-44f5-8873-4ed15b957d78.xcresult`.
- Latest paper-ink/material checks: 3/3; actual Accessibility edit/history and
  actual Safari Preview: 2/2, bundle
  `focused-527077e8-1cd7-47c3-bf58-4d5d1a6e42a8.xcresult`.
- Previous appearance/palette checks pass 10/10; focus identity model checks 2/2.
  These overlap later checkpoints; do not sum them as a new full-suite total.

Five latest captures inspected at original resolution:
`40BA3F44-FB23-49FB-ABFF-FC727F21B8A7.png` (blank),
`3C81153C-B567-4C7E-A3DC-C33EBCABDFA0.png` (Content),
`F984C535-59F2-43F4-AF64-3FA3599B2F8C.png` (Accessibility),
`969757D1-9514-4726-9CB3-546E4A668DDE.png` (Design), and
`29E9A121-2035-4F70-9E56-14EFE2D81C18.png` (Settings).
The final overflow ellipses are visibly painted; earlier native menus were
operable but invisible because a pull-down paints its first menu item's image,
not NSButton.image. The shipping control now configures that displayed item.

Compared with render 01: slimmer panes and a dominant fitted artboard now match
its structural direction, with a deliberate charcoal/slate surround. Toolbar
labels, white paper, upright text, restrained selection, readable native sections
and fixed Settings are preserved. No clipped accessible-name or reusable-style
create label remains in these captures. More destinations use explicit native
overflow instead of wrapping. Real keyboard/AX traversal proves its operation.
Website ink ignores editor appearance; latest focused logs show no publishing-
during-update or invalid-geometry warning (not a claim of no Apple diagnostics).

Remaining deviations: finished Aurora is not yet composed; native long titles
can truncate, browser link/font styling still needs real-sample comparison,
routine Inspector copy can be quieter, and installed owner-app captures plus
metadata, crash qualification and mobile browser acceptance remain due.

Latest focused result: 10/10 appearance/palette checks pass, bundle
`focused-33a1c98b-a441-4f7d-94bc-a19af7c0bed5.xcresult`.
The two Preview journeys pass 2/2 (51.205 seconds), bundle
`focused-4a13268d-bc6f-4e99-96e4-f68eb103b089.xcresult`.
Original-resolution captures reviewed: `608B8A19-DEC4-4CEF-9C36-5515648D7C20.png`
(dark editor/Header), `4C375D3B-19EF-49DF-9681-B0A89D172CBD.png` (Safari),
`97C16A12-BD3C-4B1A-ACAB-092B78263BCA.png` (Preview controls).
Safari's navigation now occupies the remaining trailing row and its title does
not wrap. Website colors stay light. Native long-title truncation and denser,
wider panes than render 01 remain actual deviations, not accepted parity.

Section/focus iteration retained failures rather than weakening assertions:
GroupBox labels flattened Reset into static text; moved Reset into its content.
Removing focusable lost native keyboard ownership; restored it and gate only
the native visual effect by window-owned input modality. A canvas layout-priority
experiment narrowed tabs into overflow while old traversal still targeted absent
buttons; the experiment was removed pending coherent overflow-aware routing.
Latest mixed run passes the new dark visual journey 1/1 (41.373s), but keyboard
fails on the hidden Assets target, so it is not a two-test pass. Exact rerun is
required after removing that experiment. All work remains uncommitted.

Owner explicitly chose a dark editor preserving original render 01's structure.
Reference re-inspected at original resolution: slim navigator, spacious central
artboard, persistent compact header and orderly Inspector. Existing shared
semantic palette and native appearance preference are reused; no second theme
or website recoloring path is introduced. Unset appearance resolves Dark, while
explicit Follow macOS/Light/Dark choices persist unchanged. New focused checks
exercise default/no-write behavior, exact saved intent and opaque palette/paper
separation. First run: 8/9 passed; the palette test caught calibrated RGB drift.
Dark colors now use explicit sRGB and Reset preview shares the default resolver;
rerun pending. Installed dark visual acceptance is not yet claimed.

Unlocked pointer retry `focused-f8d03d40-2c8b-4d34-938c-949c79cd0436.xcresult`
executed zero tests: XCTest timed out enabling automation mode. This is separate
from the previously confirmed screen lock. Owner restarted Xcode; exact retry
remains required. No owner app or recovery data was terminated or changed.
Authoritative plan/requirement IDs: SF-LOCAL-BUILDER-001 in CODEX_QUEUE.md.
Baseline: accepted `ab18c66`, 755/755 prior tests; those do not establish this
new end-to-end authoring/browser workflow. Residual QoS documentation preserved.

## Installed baseline

Regular application: app.siteforge.SiteForge, build 26.10.16. Installed source
fingerprint `a3a19bf4a4b6af0fbe0dd89250519db92923abe15f137a8862c132dc3db6525e`.
Build records pre-checkpoint source d7f5894 with dirty flag, not an invented
ab18c66 build identity. No replacement/termination of owner work yet.

## Observed owner evidence

The 135.608-second recording and its two screenshots are the acceptance input.
Reviewed all nine continuous contact-sheet pages, comprising 272 frames at
half-second intervals, both original screenshots and the three supplied concept
renders. This samples the complete timeline; it does not prove every video frame.

| Approximate time | Action / observed result | Required correction / validation |
| --- | --- | --- |
| 0–14s | Welcome shows smoke-project recents and recoverable work | Separate test state; automatic UI only for qualifying interrupted session; preserve legacy bytes |
| 22.5–32s | Header insertion; implementation prose dominates Layout | Keep genuine blank and ordinary flow; concise usable Inspector |
| 32–51s | Header fill edited; selected surface heavily tinted | Authored color must remain judgeable; chrome separate from authored pixels |
| 54–76s | Mobile preset and navigation alignment/menu controls | Real Safari responsive navigation, single canonical layout/output |
| 80–119s | Footer/Section insertion, height drag and title editing | Clear child editing, stable layout/history, no fake structural text |
| 120.5–135.6s | Repeated zoom changes lose authored surfaces/text while selection persists; content later returns | Inspect adoption/raster path at 50/100/175/high zoom; no stale pixels |
| Still images | Content boxed heading/divider differs from Accessibility; outer selected-tab focus ring | Shared section component and pointer versus keyboard focus |

## Next bounded implementation

Complete recording review and production-tool authoring attempt; implement
browser preview by reusing StaticBuildCompiler/LocalStaticBuildPlan, never the
native canvas Preview as the website. Then crash-session classification,
Inspector/tool gaps, project metadata and UI-authored sample in dependency order.

## First production-tool authoring attempt

The regular installed app created a new blank project, inserted a real Header,
changed its title to AURORA through Content/Return, inserted a connected Section
and Footer, fitted the document and saved with the native Save As panel.
One black-box journey passed (61.084 seconds), bundle
`aurora-first-production-tools.xcresult`. The owner-accessible prototype is
`SiteForge Projects/Aurora Authoring Attempt 537111FB.siteforge` beneath the
owner's home folder. This is an editable starting point, not the finished
Aurora design. No project bytes were synthesized or changed outside the app.
All four original-resolution captures were reviewed.

| Observed gap | Next implementation/authoring step |
| --- | --- |
| Header/Section/Footer role names appear inside raster surfaces | Keep names in Layers/selection context, not authored pixels |
| Selected containers are visibly blue-tinted | Remove settled transform wash; retain outline/handles and a restrained live preview |
| Content sections retain long implementation narration and differing box styles | Shared Inspector section consumer and concise user-facing copy |
| Hero is still an empty Section; title/nav are defaults except wordmark | Exercise real image/text/button, typography, child editing and page creation; record any actual missing control |
| Toolbar Preview still invokes the native snapshot | Accept the new Safari path, then route the primary command there and retain native device preview separately |
| Settings lack site metadata/favicon | Implement the bounded canonical metadata/transaction/output path |

## Acceptance not yet performed

Browser/sample proof and the integrated collector remain pending.
Exact photograph/font availability and sample fidelity remain to be established.

## Native execution recovery

After the owner restarted Xcode, the already-built black-box runner executed.
An initial diagnostic failed because the existing Welcome surface was exposed
temporarily as a Dialog rather than Window. A normal application reopen event
restored the Window role without terminating SiteForge or modifying recovery.
The original window-existence assertion then passed: one test, zero failures,
1.529 seconds, `aurora-owner-window-restored.xcresult`. The retained full-screen
capture was visually reviewed: Welcome, menu bar and Dock visible; genuine
recovery remains available. This is launch inspection, not feature acceptance.

Browser-preview foundation has explicit app target membership and a successful
initial Debug build. Four focused tests passed twice, most recently after
wiring a secondary native Safari preview command/panel:
`testBrowserPreviewHTTPRoutesExactExportBytesAndHead`,
`testBrowserPreviewHTTPRejectsTraversalRebindingAndInvalidArtifacts`,
`testBrowserPreviewLoopbackServesImmutablePlanAndStops`, and
`testBrowserPreviewStoppedServerCannotRestart` (CanvasRendererTests).
Bundles: `focused-47eccc2d-a818-4b47-a8c8-e40ec03fe7cf.xcresult` and
`focused-9bd70269-c205-44d2-918d-f9674b0d50d3.xcresult`.
These establish core HTTP/loopback behavior, not native Safari UI acceptance.
Main Preview remains the existing canvas snapshot until that replacement is
visually accepted. Resource validation/building executes on a worker actor
from an immutable package copy; no client request is translated into a file URL.

## Focused browser and raster results

The real Safari journey `testWebsitePreviewBuildsAuthoredOutputAndOpensActualSafari`
passes 1/1 (27.563 seconds), bundle
`focused-1f12e6fb-5996-4ea0-aa44-bd72c9edaeb0.xcresult`. It uses the isolated
OwnerTesting application, real Header/title controls and Preview menu, then
asserts the authored title in Safari's live web content and stops the service.
Both original-resolution captures were reviewed. The first attempt exposed a
real SwiftUI parent-identifier propagation defect; standard containing-group
accessibility now preserves the actual URL/status/button identities.

Browser delivery is working, but visual parity is not yet accepted: Safari's
default title wraps and its navigation sits beside the title rather than at
the intended trailing edge. The target Aurora page is not built by this test.
The preview controls are readable; routine informational compiler narration
still needs refinement. Primary toolbar replacement remains pending.

`testBrowserPreviewWorkerWritesSameCompilerArtifactInsidePrivateOwnership`
passes 1/1, bundle `focused-5685352d-ab23-4aea-9b2c-dac9c8933f99.xcresult`.
It compares HTTP-plan bytes, compiler bytes and actual written artifact bytes,
asserts owner-private 0700 output-parent permissions and verifies cleanup.
Together with the four HTTP/network cases, this is five distinct focused
browser foundation tests. Sandbox entitlement policy separately passes 1/1.

`testNativeTileStructuralNamesNeverEnterAuthoredPixels`,
`testNativeViewportRetainsWorldAlignedRasterDuringZoomAndClearsAtArtboardChange`,
and `testNativePointerPreviewAndOwnedLayersShareUnreflectedViewportCoordinates`
pass 3/3, bundle `focused-79ba0ece-85de-442e-8bb5-456556e14298.xcresult`.
The shared compositor retains compatible world-layout content during pan/zoom
and clears it for changed artboard bounds/document identity. Top-left anchors
match the transform's coordinate basis. No authored coordinates are rewritten.
Settled transform outlines no longer add a blue fill; live preview wash is
reduced to 2.5%. Native visual confirmation of this final wash change is pending.

Repository/security/traceability/architecture/evidence checks and diff whitespace
checks pass after updating the current traceability symbol. All 69 original
owner recovery file hashes still match. No integrated final gate is claimed.

## Coastal asset

Generated a standalone landscape coast image with the built-in image-generation
tool and reviewed the result. It contains no UI or baked website text.
Portable source/provenance: `Samples/Aurora/Assets/aurora-coast.png` and its
adjacent README. Normal Assets import and independent authored overlay/text
remain required; this is not a screenshot website or special rendering path.

The actual installed-app continuation imported this image through its native
open panel, assigned it with the existing Section Image Fill menu, changed
height to 800 and saved. `testContinueOwnedAuroraWithOrdinaryImageFill` passes
1/1 (25.004 seconds), `aurora-existing-tools-image-fill.xcresult`. Its capture
was reviewed at original resolution: upright image, exact selected Section
bounds, ordinary connected Header/body/Footer. The installed app still has
the baseline embedded role labels; it has not yet received the pending repair.

## Latest integration and external pause

Primary toolbar Preview now opens the website in Safari. The native snapshot
is explicitly Canvas Device Preview (Command-Option-P); website preview uses
Command-Shift-P. The changed four-journey batch records three passes: authored
website/primary toolbar (25.132s), native snapshot refresh (20.429s), and native
keyboard/status (18.718s). Its fourth context-menu attempt failed and was
removed in favor of real primary-pointer browser acceptance with a unique
authored title. No pointer pass is claimed yet.

New output correction: native automatic chrome filled its owner/remaining row
while CSS used stored 600-point widths and a legacy leading default. Shared
alignment resolution and matching managed widths now pass four focused checks:
`testAutomaticChromeNavigationSharesTrailingDefaultAndRemainingWidthWithStaticOutput`,
`testConnectedNestedContainerOutputUsesResolvedOwnershipAtAllBreakpoints`,
`testConnectedHorizontalStackMinimaRemainBoundedAndOutputHasSingleOwner`,
`testConnectedOutputRejectsPositionedOrClippedMenusWithoutDroppingIntent`.
Bundle `focused-c96861b4-f27e-4035-9c0c-686e5ae50cd4.xcresult`, 4/4 in 0.296s.
Actual new browser layout screenshots remain pending.

The last exact pointer rerun failed during launch activation before its feature
assertions: Running Background, 61.852 seconds,
`focused-e8afad5a-5837-4e2b-bbac-f151a8ded003.xcresult`.
Read-only OS diagnostics confirm `IOConsoleLocked = Yes` and
`CGSSessionScreenIsLocked = Yes`. OD-022 requests normal owner unlock; no privacy
or lock settings were changed. No test process remains active. The next action
is that exact pointer selector, not another broad suite. Finished Aurora,
crash-only recovery, shared Inspector, metadata and the integrated collector
remain incomplete; no final verification, installation, commit or push claimed.

## Installed-app Aurora authoring continuation — 2026-10-18

The earlier locked-screen pause above is superseded. The owner unlocked the
Mac, and the regular installed app was updated safely after truthful Saved and
normal Quit. No recovery candidate was restored or discarded.

The existing ordinary prototype was continued exclusively through shipping
controls using an external black-box XCTest driver (no SiteForge module/model
access). Home now has an image-filled connected Section, independent pale
Frame overlay, vertical content Stack, separate purple eyebrow, two-line Georgia
headline, supporting Text, horizontal action Stack and two styled linked Buttons.
Journal, About and Contact are real editable pages. Header/Footer Included Pages
and mobile menus were authored on every page. Fluid font size/line height and
Tablet/Mobile geometry overrides were edited through Layout controls; Mobile
actions stack vertically. Desktop geometry and stable identities remain intact.

Known passing authoring checkpoints, not a full-suite total:
- `testAuthorAuroraHomeHeroOverlayAndCopy`: 1/1, 411.62s;
  `aurora-home-overlay-editorial-copy-radio.xcresult`.
- `testFinishAuroraDestinationPagesAndHeroActions`: 1/1, 597.608s;
  `aurora-destinations-actions.xcresult`.
- `testAuthorAuroraNavigationAndResponsiveHero`: 1/1;
  `aurora-navigation-responsive-settings-noop.xcresult`.
- `testSaveAuroraEditorialAndPreviewExportSameArtifact`: 1/1, 46.584s;
  `aurora-editorial-safari-export.xcresult`.

Native Save As created `Aurora — Editorial.siteforge`, preserving the prototype.
Native Export created `Aurora Website` from the same compiled revision used by
loopback preview. Home, destination and all three breakpoint captures were
visually inspected: upright text, independent overlay, aligned bounds, readable
actions and no ghost content. The generated coast differs from render 01's
specific photograph. Destination pages intentionally use simple editorial copy.

Actual Safari inspection exposed output gaps, so export is not yet accepted:
plain-text line breaks collapsed; typed Button destinations remained inert; and
Button borders were omitted. Shared output corrections preserve pre-wrapped
text, emit validated navigation as native anchors, keep unconfigured Buttons
disabled, and resolve box style using the existing native applicability set.
Focused checks pass 3/3 in `focused-7ede4b22-3834-423c-927d-38e1a674ad18.xcresult`:
`testTargetedButtonOutputRetainsSafeNavigationAndAuthoredBorder`,
`testStaticControlCompilerEscapesTypedRoutesAndKeepsMissingTargetsInert`,
`testStaticTypographyOutputEscapesTextAndUsesAllowlistedCanonicalValues`.
The compact Direction label also now has its own intrinsic-width row.

Safari XCTest exposes only a Disabled application despite a loaded visible
website; ordinary macOS accessibility inspection can read its native window and
web area. No browser-navigation pass is claimed from the failed XCTest locator.
The initial Safari capture was taken during loading and is explicitly rejected
as visual evidence. Corrected installed-output review, real browser navigation/
mobile menu, final save/reopen, startup sample, crash-qualified recovery and the
integrated final collector remain required. SF-LOCAL-BUILDER-001 stays IN PROGRESS.
