# SF-LOCAL-BUILDER-012–016 — bounded focused acceptance

## Current focused closeout —2026-11-02, final full gate pending

All27 failures from the stable full inventory now have exact passing focused
receipts. OD-029 approved the bounded native repair in the existing host. Both
required native selectors pass511.484s/50.786s; final-source code4/4 and UI1/1
also pass.19 originals were visually reviewed. Canonical parent metadata now
gives Header/Footer their actual child-view ownership; decorative AX leaves no
longer intercept the genuine popup, which fills its resolved allocation. No
authored geometry, host, compiler/runtime, pointer assertion or pixel threshold
was changed. See [the native ownership repair receipt](SF-LOCAL-BUILDER-FULL-INVENTORY-20261102.md)
for exact selectors, results, removed hypotheses, geometry regression and visual
paths. Final authoritative verification and reviewed commit/push remain pending;
the earlier failed inventory/pause notes below are historical.

## Completed full inventory —2026-11-02, acceptance still blocked

The stable-source full gate completed exit65:1026 passed/27 failed/3 skipped.
Strict browser pixel journey passes1011.238s and grid/artboard passes44.329s;
native Header pointer still fails. No collector remains active. See the
[complete A/B/C repair inventory](SF-LOCAL-BUILDER-FULL-INVENTORY-20261102.md)
for exact counts,27 failed methods, runner kills, runtime warnings and next
focused boundaries. Earlier focused passes below remain scoped receipts, not
full acceptance. No commit/push or completion claim.

## Current browser correction and native limit —2026-11-02

SF-0806-006, SF-1203-003/006, SF-1211-004 remain bounded/Partial.
`testManagedHeaderFooterMenuReproductionUsesRealRoutesAndUnchangedRuntime` and
`testManagedMenuOverlayUsesIntrinsicContentAndCanonicalAlignment` pass2/2,0.116s
in `focused-f5d15c97-bf06-4f7f-9513-9cf65080cfab`.
Production shared CSS now uses intrinsic details-content grid overlap on
supporting engines. Header opens below, Footer above; panel alignment is derived
from canonical start/center/end. Older engines retain the positioned fallback.
Neither canonical state nor1944-byte shared navigation runtime changed.

Strict `testGeneratedWebsiteMenuEscapeStateAndPaintJourney` passes1/1,822.330s
in `focused-01d348fd-ecd6-45e0-a32f-8e6b3474ba13`. Measured320/430/768,
real destinations, Escape/focus/DOM/hit checks and unchanged pixel thresholds
pass. Each Header/Footer320/430 former-panel interior returns0/33600 changed,
allowed33. The earlier JSON failure was an Inspector AX transport defect:
long strings truncate and URL tokens split. Complete encoded bounded console
messages now reconstruct the same read-only JSON before assertions. Earlier
failed runs `focused-278198d9-ba1e-4f09-b9e8-ea341f299e20` and
`focused-be2e27c7-3fd1-486d-bddc-ee8653f59bce` are preserved, not passes.

Nine inspected originals in temporary `siteforge-overlay-browser-passing-20261102`:

|State|Original PNG|
|---|---|
|Header320 open|59FAE773-173A-4B91-B1E8-90C777B30BCE.png|
|Header320 closed|C79E4BA3-4E70-4C99-BE82-931D07800F9E.png|
|Footer320 open|05E29248-660E-4C87-B105-ABCA2F062A8F.png|
|Footer320 closed|60C00A49-3AF4-4948-A552-D4117E5B7B1B.png|
|Header430 open|A06F9C26-48BC-4D5E-8193-F3C94B6254DA.png|
|Header430 closed|DC7A9382-FE14-4ECE-93E5-C57752D2B4FC.png|
|Footer430 open|2A232064-F841-4A1E-95B1-D9CB15E25EBC.png|
|Footer430 closed|C1D289E2-2A30-4749-830F-D254C340B62E.png|
|Wider768|A3BFFB90-E82A-40DC-9F22-8233DA6537FA.png|

Visual review confirms upright readable menus, Header below/Footer above,
visible focus and no retained popup after Escape. Titles ellipsize; no universal
full-title or increased-text claim. This browser pass is NOT native acceptance.

`testNativePreviewMenuFitsActualHeaderAndFooterHostingBounds` passes0.036s;
ordinary Header pointer probe fails45.617s (`focused-5f879618-5042-485f-b2bf-4820fe2d6a5e`).
One row-clipping removal attempt also fails (`focused-c546046d-8ce0-4a4a-a4fd-de7c483d64e6`)
and is removed. Native cause remains unproven. All native assertions remain.
Full failure inventory is next; no complete gate/commit/push claim.


## Full-closeout diagnostic —2026-11-02, blocked before test execution

Repository checks passed, exit0, including security, traceability, architecture
and evidence checks. One serial focused launch of
`InsertionModelTests/testManagedHeaderFooterMenuReproductionUsesRealRoutesAndUnchangedRuntime`
built and started the host but entered no test method. The sampled host waits
in XCTest IDE-session preparation. Native inspection of Xcode revealed its
required system-components Install dialog. OD-028 records the owner action;
causality beyond this observed setup boundary is not claimed.

Evidence retained outside the repository: result bundle
`siteforge-full-closeout-fixture-20261102.xcresult`, matching `.log`,
`siteforge-full-closeout-host-sample-20261102.txt`, repository log
`siteforge-full-closeout-repository-20261102.log`.
The exact xcodebuild was interrupted; its host exited. Interruption left a
scheme-operation warning/stalled driver, so only that driver was terminated
(exit143). This is neither a passed test nor a product assertion failure.
No production candidate integrated, no full verification or Git mutation.
Historical native7/8 and strict browser pixel failure remain unchanged.


## Targeted grid-overlay candidate —2026-11-02, not integrated

SF-0806-006, SF-1203-003/006, SF-1211-004; bounded supporting
SF-0502-003, SF-1201-003, SF-1206-003. Existing ADR-0020 ownership remains;
no architecture or shared-output change is accepted. Modules remain Partial.

One private candidate replaces only the popup's absolute positioning with
native CSS Grid overlap through `details::details-content`: nonzero summary row,
intrinsic panel box, relative stacking, Header below/Footer-above rule, no
transform/GPU hack, forced repaint or menu runtime mutation. The first candidate
incorrectly applied a pseudo-element margin while closed and moved the summary;
that failure is retained as `grid-overlay-candidate-first.css` and first captures.
Refinement scopes overlay pseudo rules to open details. It is still PRIVATE.

Refined minimal Header actual viewport550×520 (not nominal548×516), host2x:
baseline/closed summary[412,51.063,90,17.875]; open[412,51.5,90,17.875].
Open popup[318,68.5,184,41], original placement at that viewport implies
[318,68.938,184,41]:0.438CSSpx/0.876device-pixel difference. Header remains
[0,0,550,120], document scrollHeight900 in baseline/open/closed/reopen. Real
panel center hit is owned by the panel, no invisible/zero-size hit proxy.
Pointer opens; trusted Escape closes DOM/expanded state and restores summary
focus; actual Space reopens and Escape closes visibly again. Eight originals
inspected. First baseline readout was stale pre-RDM state because that new
observer lacked a resize listener; its narrow numeric readout is excluded.
Refined observer updates resize and all refined states share one live load ID.

Private original image prefixes, same reproduction `captures/` directory below:
`grid-overlay-baseline/open/closed.jpg` (first candidate),
`grid-overlay-refined-baseline/open/closed.jpg`,
`grid-overlay-refined-keyboard-reopen.jpg`,
`grid-overlay-refined-keyboard-reclosed.jpg`.
`grid-overlay-native-receipts.txt`, CSS variants, observation scripts,
`compare-grid-interior.swift` and `grid-interior-observation.txt` retain exact
source/measurements. JPEG left panel interior excluding summary/pointer chrome:
open1081/6300 changed, closed0/6300, allowed6 at unchanged0.08channel tolerance.
This small diagnostic crop is NOT the strict full-panel XCTest gate and does
not supersede any earlier failure. No missing-browser-root-cause claim.

Added exact fixture/output method:
`InsertionModelTests/testManagedHeaderFooterMenuReproductionUsesRealRoutesAndUnchangedRuntime`.
The existing insertion fixture optionally adds real About before Header/Footer
insertion; its test checks two semantic menus, real About output/links, exact
unchanged runtime and canonical bytes, then retains compiler files for browser
proof. Source compiled, but method did NOT execute. One attempted focused command
is `focused-04359f9f-d785-44fa-9dea-d2448e410b55`; no Test Case began and no
Header/Footer artifact was produced. `siteforge-menu-overlay-fixture.log`
and `siteforge-menu-overlay-host-sample.txt` show host84055 waiting in
`XCTestDriver._prepareTestConfigurationAndIDESession`→`XCTFuture`/`XCTWaiter`,
not executing product/test code. On interrupt, xcodebuild emitted
`SchemeActionResultOperation started unexpectedly` and remained stuck. Verified
host exited; only exact xcodebuild83875 was then terminated, exit143. This is
interrupted initialization, not a test assertion failure or pass. No unchanged
retry, authentication/privacy action or inferred permission prompt.

Because real Footer/upward placement, two-menu exclusivity, real destination
navigation,320/430/wider and strict full-panel proof are missing, nothing was
integrated into ConnectedPageOutput. No new passing code/UI total. Historical
43-code/7of8-native plus prior separate1/1 compiler diagnostic remain unchanged.
Shared CSS/emitter/runtime bytes are unchanged in this task, and strict tests
remain intact. Closed the new diagnostic tab, preserved earlier AA63BA failure
tab320×820, stopped the loopback server. No run remains active, no owner-data,
coordinator, full gate, Git/install/release or next-feature work.

## Source-first minimal menu reproduction —2026-11-02

SF-0806-006, SF-1203-003/006, SF-1211-004. Diagnostic closed out;013 and
full application acceptance remain unresolved. No temporary production
instrumentation or speculative styling is retained.

Source audit of `runNarrowChromeBoundaryCompanion` confirms `result.dom=state()`
reads the live unique-role details/summary/nav. `eventTrace` separately retains
before-key and two-rAF snapshots; the helper does not present those alone as live
state. The screen is captured before Inspector, then both live and event state
are checked. Crop derives DOM panel displacement from the live AX summary and
screen backing scale; no demonstrated crop/query error was found. Production
Escape sets open=false/expanded=false and focuses summary, while passive observers
neither consume input nor close menus. Generated markup intentionally has inline
and popup links, but this reproduction has exactly one details/menu.

New exact code selector:
`./sf test focused SiteForgeTests/InsertionModelTests/testMinimalManagedMenuCompilerReproductionPreservesRuntimeAndDocument`.
Passed1/1,0.034s; `focused-f7087ab2-0fab-41d4-9b02-3bb5b8a1a716`, exit0.
It derives one Header and owned descendants from the existing insertion fixture,
removes Footer/body only in a test document copy, invokes the real multipage
planner, asserts one details/no Footer, exact shared runtime and document/session
neutrality, and retains private compiler files. This adds one diagnostic code
pass separately from the historical43-code/7-of8-native scope. No UI-test launch,
native Header rerun,43-test batch or full verification was run.

Private self-contained directory:
`/var/folders/1s/tc4zxv1124n2py3v1rlrd5dw0000gn/T/SiteForgeMenuReproduction-41F1A718-E32B-48C3-8474-9E630892498A/`.
`README.md` provides portable loopback startup, all case differences and outcomes;
`evidence-manifest.json` hashes files and original captures;
`native-case-receipts.txt` and `cleanup-receipt.txt` retain actual native states.
Focused command log: `siteforge-menu-reproduction-focused.log`.
Real diagnostic GET returns the original1944-byte runtime, SHA256
`75ae8ee421798d73d1dc8e4e349262ed163766e7b6dbfc7d5f2e804661c8c6c1`.
The private standard-library server binds only127.0.0.1 and is not a new production
server/security implementation. Original compiler HTML/CSS/runtime are unchanged.
The reproduction has one Home link rather than the older two-page/Header/Footer
artifact; it is diagnostic reduction, not full output acceptance.

| Case / capture prefix | After real Escape | Observation |
| --- | --- | --- |
| `generated-plain` | panel remains visible | native AX off, summary focused |
| `generated-observed` | panel remains visible | same-page live closed/expanded=false/focused/trusted Escape |
| `stock-plain` | link disappears | native AX off, summary focused |
| `stock-observed` | link disappears | same-page live closed/expanded=false/focused/trusted Escape |
| `generated-static-panel` | panel disappears | only popup position:absolute→static changed |
| `generated-stable-position` | panel remains visible | absolute positioning moved to unconditional popup rule |

Stock is explicitly labeled diagnostic/non-SiteForge HTML and uses no generated
CSS/runtime. Its own small ordinary Escape handler supplies closure/focus (no
built-in details Escape behavior is assumed). Observational variants add only
one passive readout script, with unique load ID and live pointer to that same
details. No Inspector was open during the comparison. Nominal native RDM fields
548×516 at100%/1x; same-page readouts honestly report547×515. Uninstrumented
inner dimensions were not independently queried, so no exact548 claim is made.
No width sweep, repaint/reload workaround or fabricated closed state.

All18 valid original JPEG captures were inspected at original resolution.
Each prefix has `-baseline.jpg`, `-open.jpg`, `-closed.jpg`, except the valid
observed generated baseline is `generated-observed-loaded-baseline.jpg`.
An additional `generated-observed-baseline.jpg` is preserved but EXCLUDED:
the attempted address shortcut did not focus the field, and Return reopened the
previous menu instead of navigating. Fresh URL/AX observation caught it; later
cases click the actual address field and verify URL/readout before capturing.
This is an observed native-input sequencing issue, not proof the earlier strict
XCTest state/pixel failure was wrong. Strict pixel gate remains unchanged.

First narrowed condition: absolute popup positioning in the generated details
presentation participates in the visible closure failure. Static positioning
removes the residue but also places/clips the panel differently; it is not an
acceptable production fix. Unconditional absolute positioning does not repair
it, so a simple open→closed position switch is not sufficient explanation.
The exact remaining boundary is generated absolute-popup layout/paint invalidation
versus visible/captured content after native details closure. A specific WebKit
internal cause, capture fault or standards violation is NOT established. No safe
owning-boundary correction is demonstrated; stop further experiments here rather
than replace popup navigation with inline content or relax its acceptance.

Closed only the newly created diagnostic tab; the earlier AA63BA cached failure
tab remains at320×820 with both summaries off. Temporary server stopped, no run
active, private evidence preserved, no observer inserted into production/owner
pages. No owner package/resources/recovery, coordinator, Git, install/signing,
full gate or next-feature changes. Native Header pointer, strict browser visual
closure, repeat/one-open/full destination coverage remain unaccepted.

## Same-artifact native Safari presentation comparison —2026-11-02

Bounded requirements: SF-0806-006, SF-1203-003/006, SF-1211-004.
Diagnostic finished, visual acceptance unresolved. No production correction is
claimed. The first demonstrated divergence remains closed layout/AX/hit state
versus presented/captured pixels. Ordinary Safari also exhibits it, so it is not
an RDM-only finding. Neither a particular Safari compositor defect nor a capture
defect is proven. No further speculative CSS, runtime or host experiment retained.

### Actual context and presentation

Used the retained private AA63BA Home artifact, not a substitute page or owner
document. Its server had stopped after the earlier XCTest teardown; no reload,
navigation or new HTTP/hash receipt is claimed in this comparison. The historical
1944-byte runtime/hash receipt below remains the delivery evidence. One passive
observer persisted across native mode/zoom changes, alongside matching fixture
owners and URL. Inspector was docked right throughout click/Escape/capture and
explicitly selected `index.html`, not automatic or LinkPresentation worlds.
Public context menu exposed Auto, index.html and four MetadataProvider contexts;
there is no unique Inspector protocol target ID in this public hierarchy.
Page reports top=true, child frames=0, scroll0/0, visible, viewport scale1.
Window public ID ends `1BB59EE7-0FF5-4778-99A7-5FE5BD292B55`, outer1709×994pt.
These observations correlate more than URL/prefix alone, but are not a claim
that an unavailable private rendering-process identity was inspected.

Ordinary Safari's native175% page zoom yields actual548×516 CSS, DPR3.5.
RDM with page zoom reset and native fields548×516 yields actual548×516, DPR1.
Both use the same retained document and observer (timeOrigin differs only by1ms
at the reported precision). A548×820 RDM probe actually measured547×819 at95%;
it was rejected rather than relabeled. A549 probe measured549, and an ordinary
200% probe measured479×452, not480. A resize drag did not change the native
window frame and establishes no Safari minimum-width limit. The final test
helper removes that speculative resize path, matches height as well as width,
uses bounded native Zoom In, and retains exact dimensions and strict pixels.

### Original-resolution visual evidence

Directory `siteforge-012-016-acceptance.eJiZ5V/same-artifact-native-comparison/`.
Original native captures are JPEG3418×1988, not renamed/reencoded PNG evidence.
All13 originals were inspected. For each prefix below the three files are
`-baseline.jpg`, `-open.jpg`, `-closed.jpg`:

- `ordinary-548-header`
- `ordinary-548-footer`
- `rdm-548-header`
- `rdm-548-footer`

Additional `rdm-548-footer-closed-later-read.jpg` still shows both panels322s
after the genuine Footer Escape. All corresponding closed images visibly retain
panel text/surfaces while the adjacent Inspector records closed/expanded=false,
visibility=false and focused own summary after trusted Escape. Open images also
contain the panel; their crop metrics match closed images. This is not evidence
for a one-frame delay that could safely be repaired by a sleep or extra frame.

Read-only comparison of the original JPEG panel interiors (8CSSpx inset,
sRGB channel delta>0.08) reports baseline→open AND baseline→closed:
ordinary Header3682/102900, Footer3691/102900 (allowed102);
RDM Header2165/33600, Footer2166/33600 (allowed33). Later Footer2166/33600.
These JPEG observations support visual review, not replacement of the strict
XCTest PNG gate's authoritative1855/33600 failure below. Ordinary host screenshot
scale3.5 and RDM host scale2 were mapped separately; emulated DPR1 is not host
capture scale. `pixel-observations.txt`, `compare-original-pixels.swift`,
`native-accessibility-receipts.txt` and `native-cleanup-receipt.txt` retain the
numeric rectangles, capture file times, context/event trees and cleanup.

### Focused execution and cleanup

New exact selector:
`SiteForgeUITests/SiteForgeLaunchTests/testGeneratedWebsiteMenuEscapePresentationContextComparison`.
Two attempts built but executed zero tests: automation-mode initialization timed
out, exit65, results `focused-c5d29128-c7ac-4b30-b9c3-07a6901a8471` and
`focused-5de28963-63b3-4cba-84f8-d9276e366395`. Logs are the sibling
`website-same-artifact-presentation-first.log` and
`website-same-artifact-presentation-after-inspection-reset.log`.
The second follows a concrete native inspection transport reset, not a claim
that reset repairs XCTest. No third unchanged launch, privacy change or inferred
authentication request. Final `xcodebuild build-for-testing` succeeds, exit0;
log `same-artifact-native-comparison/final-build-for-testing.log`.
Native comparison observations are not XCTest passes. Five diagnostic UI methods
now exist, four have historical execution evidence; distinct passing code43 and
primary native7/8 remain unchanged.

Removed only the passive observer (receipt confirms observer=false), restored
Auto Inspector context, RDM320×820 and100% page zoom, closed Inspector and left
the retained cached tab intact. Both summaries report off. No runner remains
active. No native Header replay, owner document/resource/recovery change,
coordinator edit, full suite/verify, Git, install or signing action occurred.
Full verification remains mandatory/deferred. Preserve the unresolved pixel
regression; no safely correctable owning boundary was established by this bounded
comparison. Stop new experiments rather than invent another production patch.

## Real website Escape correlation —2026-11-02, visual acceptance still open

### Final pixel gate — FAIL, retained (no active run)

The same exact UI method now compares a real screen baseline before opening with
the actual closed-state screen, within the former panel interior (8 CSS-pixel
inset excludes the summary focus ring). AX points map through the primary screen
to Retina pixels; screenshot NSImage.size itself is physical pixels on this
runtime. Tolerance: sRGB channel delta>0.08 counts changed; at most0.1% or4 pixels
may differ. A visible per-run six-character fixture prefix confirms the screenshot
and measured document are the same private fixture, not an older Home tab.

Result `focused-8bc86f35-54f4-494c-985e-15d9244794b0`:1 executed,1 failure,
106.962s, exit65. At320 Header,1855/33600 interior pixels remain changed versus
the closed baseline (allowed33). All prior trusted Escape, closure, focus,
rendered-frame, all-navigation visibility and former-panel hit assertions pass.
The first demonstrated divergence is between browser layout/hit state and
presented/captured pixels, not missing JavaScript or duplicate live links.
This does NOT yet identify a specific Safari compositor/framework defect or
justify rewriting production navigation. No repaint, reload, timeout or DOM
mutation workaround is added.430/768 are intentionally still in the test but
not reached after this new truthful visual failure. Earlier logical-only passes
are historical, not the current method's acceptance result.

The intervening all-navigation/normal-Tab diagnostic passed1/1,136.423s in
`focused-b3d255f0-f488-4cea-8f94-9f6898d551ce`, but Tab did not clear the
visible residue. Both inline navigation and popup descendants report invisible;
elementsFromPoint at the former panel center returns underlying authored content,
not A/NAV. The first pixel attempt `focused-b8886ed7-d5e6-4dac-af4c-86806bb9e636`
was deliberately interrupted (exit75) before menu acceptance to correct the
Retina mapping; it is not counted as a pass/failure result.

Final original evidence directory:
`siteforge-012-016-acceptance.eJiZ5V/website-escape-pixel-regression-final/`.
Baseline `0F152F65-5B47-4781-92C1-099CB611A2BA.png`;
closed `28DFE927-F120-45D4-98C0-B2902E6A7FEF.png`;
after genuine Tab `EE31AB24-0235-4606-8B29-709028AB4F42.png`;
recording `6D9418C9-C023-4475-93BA-DBDDCAB8613C.mp4`.
Original baseline and closed images were inspected. The recording independently
shows the same panel in `closed-recording-exact.png`, requested94.9s,
actual94.846667s of106.646667s (zero extraction tolerance). No ambiguous
post-teardown frame is used. Canonical owner project/recovery data is untouched.

Next bounded investigation, not an accepted fix: correlate the same private
artifact outside Safari Responsive Design Mode to distinguish browser presentation
from capture/compositing behavior. Do not relax the pixel gate, repeat unchanged
long tests, revive the ineffective CSS or change native hosts/security settings.
No full verification, Git, install or broader architecture action was performed.

Bounded requirements: SF-0806-006, SF-1203-003/006, SF-1211-004;
immutable shared Preview/output delivery is preserved.

- New exact unit:
  `InsertionModelTests/testManagedNavigationRuntimeReferenceAndHTTPBytesMatchRootAndNestedOutput`.
  Root and nested HTML reference the same emitted runtime using the correct
  relative URL. Real Preview HTTP responses are200, JavaScript MIME,1944 bytes;
  SHA256 `75ae8ee421798d73d1dc8e4e349262ed163766e7b6dbfc7d5f2e804661c8c6c1`.
  Canonical bytes/revision remain unchanged. Passed0.073s in
  `focused-532da70b-44e4-49f0-88f9-cb03e9eebef3`.
- New exact UI:
  `SiteForgeLaunchTests/testGeneratedWebsiteMenuEscapeStateAndPaintJourney`.
  A passive test observer records actual trusted Escape, toggle events, focus,
  open/expanded state and two animation frames; it never dispatches or consumes
  input, closes menus or changes production state. Inspector observation between
  opening and Escape initially disturbed focus: retained failure
  `focused-8e9b9692-79c0-4b10-a697-62d9c2cfc3ea`,98.017s. That intervening
  query is removed.
- Unperturbed Escape reaches SUMMARY, is trusted/default-prevented by the real
  runtime, closes both details, sets expanded=false and restores summary focus.
  Fetching the actual runtime confirms the same bytes/MIME/hash above.
  DOM-only comparison passed120.787s in
  `focused-fb4d2aad-4b5c-40e3-b391-7b6b6f0acb51`; paired screen/window
  comparison passed122.140s in `focused-532da70b-44e4-49f0-88f9-cb03e9eebef3`.
  These are assertion passes, NOT visual closure acceptance.
- An explicit closed-menu display:none CSS experiment passed its assertions at
 320/430/768 but still painted panels in original screenshots
  (`focused-d275171b-3ae3-4920-8c52-4c4be8aa8cb4`,UI229.855s).
  The unproven production rule and temporary CSS assertions are removed.
  No runtime/CSP/compiler alteration is justified by correct script delivery.
- Capturing the real screen BEFORE Inspector/window capture also passed1/1,
 243.967s, at measured320/430/768 in
  `focused-df540da6-304c-4cb1-894e-d9aadc4e8dbf`.
  Event-frame wall times precede capture; fresh AX reports collapsed, DOM
  details are closed and checkVisibility=false. Nevertheless all four closed
  originals still visibly contain panels. Capture order alone is NOT the cause.

Retained root: `siteforge-012-016-acceptance.eJiZ5V/`.
Latest originals: `website-escape-screen-before-inspector/`:
Header320 `EDF0DBD9-0671-46CC-A212-E21404AC9303.png`;
Footer320 `76003427-0DD9-40E2-BB1F-0939D8A76320.png`;
Header430 `862351CB-B20B-4F12-A347-0858EA2D52D5.png`;
Footer430 `154F67A3-1DFB-42BA-B588-FB67DB68EC3E.png`;
wider `81DC70F1-585E-4690-92E0-B6E922800918.png`.
All five were inspected at original resolution. Wider inline links are upright
and separated; narrow closed screenshots FAIL visual acceptance. Long titles
ellipsize; no complete-title/larger-text claim.

Distinct passing non-UI methods now43 (35 new +8 existing); this is accumulated
evidence, not one43-test run. Primary native baseline stays7/8; strict013 Header
pointer failure remains. Four independent diagnostic UI methods are separate
from primary acceptance. Full verification remains mandatory/deferred; no Git,
install, owner project/recovery or coordinator mutation authorized.

## Current integration boundary

### Current short pointer isolation —2026-11-01/02, diagnostic closeout

Requirements: bounded SF-0806-006, SF-1203-003/006, SF-1211-004. Strict013 native
readiness/pointer assertions are unchanged. A diagnostic companion calls ordinary current
XCUIElement.click without an isHittable guard or coordinate fallback.

- `testNativePreviewHeaderPublicPointerBoundaryProbe` fails46.212s in
  `focused-c7381090-86bf-433c-8a6f-ca04c0d34a9b`: one enabled Header Menu,
  XCUI frame754,456,92,26; standard Done is hittable. The ordinary Menu click
  attempts scrolling then fails Not hittable. This is not merely a false flag
  with a demonstrated successful ordinary click. The preceding compile-only
  attempt failed a test subscript line break; fixed before execution.
- Same exact probe with bounded read-only native observation fails46.159s in
  `focused-89d7b407-aa85-42c5-b0f7-8d7bc60eebc2`. External public hit discovery
  returns AXError -25211; no permission/settings changes or repeated external
  API attempts. Native Header screen center800,638 equals the AppKit public
  screen helper and live activation point. At backing2, main screen1710×1107,
  conversion to XCUI top-left coordinates gives800,469, exactly its XCUI center.
  Actual control, sheet-window and application hit tests all return the SAME
  native Header cell. Footer likewise returns its own cell at800,478 native.
  Inverting a point twice hits the other control, not evidence of a production
  flip. All view ancestors are unhidden; the actual control bounds are fully
  visible. The native AX chain is cell → ScrollArea → sheet hosting group →
  real Sheet → parent document Window → application. Disabled container metadata
  is observed but is NOT independently proven causal; standard Done works in
  that same sheet. No role/frame/parent/window/hittability override is added.
- Temporary native observation is archived outside the repo and removed from
  production before the independent Footer/Safari companion. No production
  correction is justified by these observations yet; no long013 retry is run.

Originals/logs/recordings/hierarchy and diagnostic-source archive:
`siteforge-012-016-acceptance.eJiZ5V/public-pointer-probe-failure/` and
`siteforge-012-016-acceptance.eJiZ5V/public-pointer-native-hit/`.
Reviewed original PNG `905DFB96-CA7A-42E0-8761-8B644EE24308.png` and exact
recording frame `public-pointer-native-hit/click-failure-exact.png`
(requested43s, actual42.995s of45.595s) show a readable upright Header and
Footer Menu inside their pale authored areas and the real document-modal sheet;
appearance alone does not prove pointer operation. Footer/Safari independent
observations below are separate, not counted as strict013 acceptance.

Independent Footer/browser companion first result:
`focused-e6981426-62e9-4383-b1b8-a02889529008`,91.194s, FAIL at Safari width
entry. Footer's ordinary click DOES open the genuine checked Home/About menu;
Escape restores its own focus. Down/Escape/reopening and actual About navigation
also pass before Safari is reached. These are independent observations, not a
passing013 replacement. Original pointer-open, keyboard-open and About-destination
PNGs under `footer-safari-companion-first/` were inspected: readable native
menus/focus, correct About destination/status, no ghost content. Long authored
titles visibly ellipsize in the narrow native presentation; full-title runtime
acceptance is not claimed.

The browser failure is a proven query defect: Safari's real Width field is
present by label/title but its identifier is empty. The SiteForge-owned-field
helper re-queries by identifier, yielding no match before typing. The companion
now uses the same unique semantic Width query and asserts real keyboard focus;
no width measurement/persistence/navigation assertion is relaxed.

A narrow borderless-bezel fit hypothesis was rejected before any app retry:
`testNativePreviewNavigationFitsCompactAuthoredRowWithoutClippedBezel` fails
its two containment cases in0.223s (`focused-5853a5c1-4283-4bb8-a2cf-0894549efbe4`).
Native cell geometry still exceeds its NSView frame; removing the bezel does
not establish a fit correction. Both that unproven production edit and its
diagnostic-only test were removed; exact source and failed receipt retained
outside the repo. It is NOT added to current passing counts. No second host or
further control rewrite follows from this rejected hypothesis.

#### Independent browser result and final boundary

`focused-2b1e92e9-483e-4d97-a71f-52ed5027dd3c`: current native-control regression
passes1/1,0.628s after observation/bezel cleanup. The combined Footer/browser
companion fails at exact430 width after passing Footer pointer/keyboard/About
and measured320 browser actions. Its universal RDM +1 assumption produced
actual431, not430. That failure and all originals remain retained.

`testMeasuredSafariNarrowChromeBoundaryCompanion` then passes1/1,167.058s in
`focused-f763b692-92bb-4b29-8840-4ade17445037` (exit0). No Footer tour is repeated
in this browser-only selector. The shared real-field helper queries unique
Width label/title, asserts enabled/hittable/focus, and uses keyboard editing.
It enters the requested width, reads actual innerWidth, and allows ONE real-field
correction only for an observed one-pixel rounding difference. Final exact
width/scale assertions stay320/430/768 and1. At768 the first DOM result was767;
the one measured correction produced768. No script sets window/page geometry.
Both Header/Footer title identities/allocations are measured; native browser
menu clicks and focus assertions pass at320/430; actual About navigation is
confirmed by `/new-page.html` and unchanged loopback host.768 shows inline links.
The same query/calibration correction is shared with strict013's browser stage;
its native assertions are untouched and the whole strict test is NOT rerun.
Final build-for-testing succeeds (exit0), including that final test-source change.

All nine final original Safari PNGs were inspected at original resolution under
`siteforge-012-016-acceptance.eJiZ5V/safari-independent-final/`:

| State | Original filename |
| --- | --- |
|320 Header open|486112ED-88CB-43DD-860B-5BF71BA67FCA.png|
|320 Footer open|4FAEB9FB-F876-4583-8AD8-53158BDD4331.png|
|320 after Escape/focus assertions|2B7925AD-683B-440B-A0D1-65554755E03D.png|
|320 About destination|E57420CA-93D5-4798-A0A3-5FAE23030024.png|
|430 Header open|8D397D16-582C-4B14-9630-BB3750004BEF.png|
|430 Footer open|DA216424-6DBC-411D-8E6E-2E665932CA47.png|
|430 after Escape/focus assertions|90B42D8F-05E8-41A1-9767-A8701C0FF7CF.png|
|430 About destination|0AA690C8-40BB-4169-887B-BAA64135A223.png|
|768 inline layout|3C3F45DB-D7CE-42E0-8331-7B035BF01D5F.png|

Visual findings: upright, separated title/navigation areas; readable native
browser menus and focus rings; real About destination; no editor grid/selection
chrome in website output. Long titles ellipsize, so full-title visual acceptance
is not claimed. IMPORTANT: the after-Escape originals still show painted menu
panels (430 shows both). Passing focus assertions do NOT prove panel closure.
It is not yet established whether this is live `details.open` state, missing
script behavior or stale browser paint; do not label it fixed or infer its cause.
The newly reached browser result is automated partial proof, NOT complete visual
acceptance. About is the fixture's otherwise blank legacy page with generated
route links, not a fabricated authored object.

The three questions are now separated:

- A — ordinary XCUI pointer: Header FAIL; Footer opens its actual menu PASS at320.
- B — native keyboard: Header Down/Escape/focus has prior actual evidence;
  Footer Down/Escape/focus and About navigation pass independently here.
- C — external readiness: Header remains false despite unique live identity,
  correct native coordinate/hit results; public cross-process API is unavailable
  (-25211), so its actual remote hit target remains unobserved. No framework
  fault, privacy change or successful ordinary Header click is inferred.

Safe next bounded actions, NOT started: correlate browser `details.open`,
`aria-expanded` and script-load state around actual Escape before changing output;
obtain a public remote hit-target comparison for Header versus Footer only from
an already-authorized client, or document that capability boundary. No new host,
AX role/window spoof, native offset/clip assortment or another unchanged long013
retry is justified. All temporary collectors are removed; no active run remains.
Current42 distinct passing code methods and7/8 primary native baseline remain
unchanged; three extra diagnostic UI methods are separate, not primary passes.
No full suite/verify, Git, installation, new feature or owner-data edits.
Final targeted diff whitespace review and requirement-evidence JSON parsing pass;
focused run logs contain no publish-during-view-update or invalid/negative-geometry
warning matches. No xcodebuild/UI runner remains active. This is bounded diagnostic
closeout, not milestone completion or a claim that all runtime issues are absent.

**Preceding control-repair closeout: keyboard/focus correction retained;013 NOT accepted.**
No run remains active. The native popup owns real focus and opens Home/About
with Down; Escape returns focus in the actual app. Its real AX cell carries the
identifier/label (the NSControl view's native role is Unknown), with no role or
window spoof. Its computed activation point is live screen geometry; a preceding
exact test proved the default point outside its frame. This independent metadata
correction did NOT resolve XCTest's remaining initial-hittability failure.
The AppKit host experiment remains removed. Safari/compiler/output bytes and
canonical data/actions remain unchanged; temporary tracing is removed.

Current affected receipts:

- `CanvasTextRenderingTests/testNativePreviewNavigationOwnsFirstResponderAndRejectsStaleMenuItems`
  and existing `testNativeCanvasAccessibilityModalOwnershipRejectsRetainedActionsAndRestoresAfterDismissal`
  pass2/2 in `focused-1008cad5-c590-46de-a56f-82fa6a7204b6` (0.576s/0.624s).
  New coverage includes native first responder, genuine cell hit identity,
  frame-contained activation point following movement, current/missing/stale
  items, deferred tracking updates and teardown neutrality. One new method,
  not multiple counts for its cases/retries:42 distinct current code methods
  with passing evidence, versus original41 baseline.
- Existing `CanvasRendererTests/testPreviewNavigationScalesLayoutAndHitBoundsInsideAuthoredOwner`
  passes0.001s in `focused-fc5269f4-cb1e-4f6e-8379-13009ed08b30`; its two code
  neighbors passed but the then-new control test correctly failed its mistaken
  NSControl-view role expectation. It now asserts the actual native MenuButton
  cell role, without changing the platform's role. The earlier test compile
  failure was the renamed `NSMenu.items` API and was corrected before execution.
- `focused-871f8254-28b8-4c7d-8996-753dd2d00571`: actual01384.267s reaches
  real Down opening/About existence/Escape/focus restoration, then fails the
  added initial pointer-readiness assertion. Before/after Tab the Menu is not
  hittable; same sheet Done/page picker are. No coordinate bypass is used.
- `focused-8a8c84d9-68b9-495f-ae4f-3ee659fffc11`: exact new code test fails
  the real cell's activation-point containment. Corrected point passes0.617s
  in `focused-c9dbfaa3-e05d-4c56-bd1d-7e90676104b4` and the final2/2 above.
  This uses [AppKit's screen-coordinate activation-point contract](https://developer.apple.com/documentation/appkit/nsaccessibility-c.protocol/accessibilityactivationpoint?language=objc),
  not a synthetic hittability flag or an expanded hit surface.
- `focused-a8ed2b38-bbec-4b0b-a0a2-f950b5f943a0`: actual01384.206s still
  fails that strict initial hittability assertion, after successful native
  keyboard opening/Escape. The original subsequent pointer/menu/destination
  assertions remain unchanged and unreached; no full013 pass is claimed.

Latest original recording retained at
`siteforge-012-016-acceptance.eJiZ5V/native-popup-activation-final-failure/6BF1487B-9600-406A-99A5-F95429A5B91C.mp4`.
Reviewed zero-tolerance originals `native-menu-open-81.png` (actual80.670s) and
`native-menu-escape-82.5.png` (actual81.987s) show readable upright title/Menu,
real checked Home/About popup, then closed popup with restored focus, visible
Footer Menu, normal maximized root/menu bar/Dock and no new ghost/proxy paint.
This is Header keyboard evidence only: Footer activation, pointer destinations,
430/768 measured states and the Safari tail were not reached. Larger-text runtime
remains unreviewed. No privacy/keyboard setting, host, root lifecycle or owner data
changed. Source reference search confirms all temporary trace/host types absent;
targeted whitespace review of the touched product/test files passes.

Only affected code neighbors were rerun. Historical Save/reopen and primary
Safari/Check Website repair passes were not needlessly repeated: this retained
correction changes only the native content control, not their command/lifecycle/
browser paths. Their receipts remain baseline, not proof of the unaccepted native
pointer path. No full target,41-method sweep, ./sf verify, Git/install or017.

### Correlated key dispatch — first proven boundary

`focused-5f33968e-2339-4a19-82c1-95896482aba8` executes only013 and fails82.655s.
Its opt-in trace proves Down125 arrives at the correct owned sheet, active
SiteForge foreground before/after, first responder `KeyViewProxy`, modifier
flags8388608 (Function only), physical flags0. There is no native-follow,
browser-open request or browser-opener invocation before failure. The workspace
router observes and passes this event; it does not consume or retarget it.
Thus Safari misdispatch/stuck Command/Shift is NOT demonstrated.

Correcting prior visual interpretation: AVAssetImageGenerator's default unlimited
time tolerance returned actual78.208s for requested75s from the old78.725s movie.
That frame is after t77.74 teardown/termination. Zero-tolerance extraction returns
actual74.542s, visibly still SiteForge Preview. The apparent Safari transition
was teardown exposing the prior browser, not the menu key invoking Safari.
Both originals/extractions and the sanitized trace are retained outside the repo.

The demonstrated local boundary is focus-proxy ownership without native menu
activation, not scene/window/browser routing. Bounded repair: remove the extra
SwiftUI focus proxy around the content Menu and give one genuine NSPopUpButton
native key-view/accessibility/action ownership within the restored sheet. No
new host or key forwarding; immutable navigation values/actions stay unchanged.
Its current-page/availability/stale-item projection gets an exact AppKit
regression before rerunning the strict actual app journey. Temporary tracing
will be removed, not retained as always-on production logging.

## Retained chronological diagnostic ledger — historical states

Everything below preserves earlier plans/results, not current execution state,
current control implementation or renewed authorization. The closeout above is
authoritative; do not replay old running/pending experiments or count retired
probe passes as current product coverage.

Owner approved **SF-LOCAL-BUILDER-013-PREVIEW-HOST-EXPERIMENT** after the
documented architecture decision. This temporarily supersedes the pending-choice
text in the historical ledger below, not any strict acceptance assertion.
**Outcome: rejected and surgically removed.** The immediately preceding SwiftUI
Preview sheet/dismiss/focus path is restored. No controller/presenter or orphan
diagnostic test references remain. All unrelated dirty work and the independently
validated modal canvas accessibility correction survive. Retired diagnostic
tests: `CanvasTextRenderingTests/testNativePreviewOwnedSheetRoutesPointerKeyLoopEscapeAndRepeatedDismissal`
passes1.253s (`focused-38d061b1-f0c8-4e9c-972d-8e05cf94221f`);
`testNativePreviewOwnerCloseAndControllerReleaseLeaveOtherDocumentUntouched`
passes1.099s (`focused-0310d219-4ac9-4c2b-b04d-b517ceea6b17`). These exercise
real native pointer/key events, repeated modal dismissal, close/release and
two-document isolation. They do not prove the actual SwiftUI content menu.
Initial compilation rejected the controller's `owner` property collision with
NSWindowController; renamed to originatingWindow. Initial fixture assumptions
about global activation/push-button Tab and closing a modal parent were corrected:
unit tests exercise native text-field key loops and actual lifecycle close;
the real-app journey retains strict live activation/focus/hittability assertions.
No privacy/keyboard setting changed. The host explicitly requests key ownership.
The exact013 app journey `focused-9073df19-a811-4a41-a928-39031ca5dcf0`
failed78.950s at the added real Down Arrow/About opening assertion (line9087).
The unchanged strict pointer assertion remains later in the method. Peer values
before that key remain menuHittable=false, doneHittable=true and pagePickerHittable=true.
Thus neither the original pointer nor the new keyboard boundary improved. No
measured Safari portion was reached. These retired test passes are NOT added to
the current41-code baseline or treated as acceptance for the restored presenter.

Cleanup verified by one exact existing regression:
`./sf test focused SiteForgeTests/CanvasTextRenderingTests/testNativeCanvasAccessibilityModalOwnershipRejectsRetainedActionsAndRestoresAfterDismissal`
exits0,1/1 pass0.640s in `focused-2d577279-bfbb-4918-b48e-71c3eb12a6bf`.
This incremental build compiles the restored product/test sources; targeted
source-reference search finds no removed host/probe names in SiteForge/Tests.
`git diff --check -- SiteForge/WorkspaceShellView.swift Tests/SiteForgeTests/CanvasTextRenderingTests.swift`
passes. No whole target/class/full gate or unchanged failing UI rerun occurred.
Process inspection after completion finds no xcodebuild/UI runner active.

Historical experiment source and test excerpts are retained at
`siteforge-012-016-acceptance.eJiZ5V/retired-appkit-host-source/`:
`controller.swift.txt`, `tests.swift.txt`, `presentation-context.swift.txt`.
They are outside the repository and not target members. Original logs/results
remain retained, including initial compiler failure `focused-c547b08b-0aa2-498a-a66e-10c96d2251f1`,
fixture failures `focused-0d252ca0-d983-4043-916c-0f5150c61b73`, and the
corrected isolated receipts above. No evidence was deleted.

Original-resolution visual/recording review under `appkit-preview-host-actual-failure/`:

- `DA81CA04-328A-4B46-8CB3-2AB2801C2876.png`: actual320-wide authored
  Header/Footer, upright title/menu paint, aligned selection, readable persistent
  controls; this is editor paint, not Menu interaction proof.
- `371180D4-811B-4C56-840B-3ED09957B858.mp4`: original recording retained.
  Extracted `preview-host-screen-5s.png` shows normal maximized SiteForge with
  menu bar/Dock;65s shows the actual width draft before commit;72s shows the
  native sheet with one readable Header/Menu and Footer/Menu and focused Menu.
  No duplicate proxy paint or new ghost is visible. The75s extracted image
  (`preview-host-native-menu-75s.png`) instead shows Safari foreground, despite
  the app journey not yet reaching its Safari branch. Do not mislabel that frame
  an app-only Preview screenshot or proof of responsive browser output.

ONE recommended next diagnostic, not started: correlate redacted frontmost-app
identity, NSApp activation, key/main/sheet identity, first-responder class and
event modifiers immediately before/after the first native opening key within
the restored presenter. The log issues Down at74.26s; the recording switches
from SiteForge at72s to Safari at75s. This observed dispatch/foreground boundary
requires tracing before any more host changes; it does not prove why it happens
or establish a framework bug.013 remains unaccepted, historical native baseline
7/8; larger-text runtime and remaining native/Safari visual proof remain open.
No further diagnostic or production experiment was started during cleanup.

Seven of eight distinct native journeys have passing evidence.013 remains under
exact native/Safari acceptance. The custom NSPopUpButton bridge and experimental
canvas AX rerouting are removed: ADR-0020 already specifies an AppKit-backed
SwiftUI Menu. That native control now owns menu tracking, modal accessibility and
scene-local focus. The real pointer/hittability/Escape/navigation assertions are
retained, with additional Tab traversal. No false hit state or coordinate bypass
is accepted. Forty-one current code methods have passing evidence. Experimental
private-cell and headless virtual-AX probes were retired with the custom bridge;
they are not counted as current passes. Slot/owner geometry is now asserted
through the real native journey, comparing live authored-canvas and Preview
Header/navigation frames within one device pixel, with no new coordinate offset.
The same existing hit/Tab/Escape/route assertions remain required.

### Document-modal canvas accessibility boundary

`CanvasTextRenderingTests/testNativeCanvasAccessibilityModalOwnershipRejectsRetainedActionsAndRestoresAfterDismissal`
passes in `focused-da2e7a06-ac94-4de6-9f2a-487877c4b355` (0.622s), and its
strengthened direct-hit exclusion passes in the subsequent targeted run. This
brings current distinct passing code evidence to41 (33 new/eight existing), not
a single41-test run. The window-local canvas stops exposing children/actions or
returning an accessibility hit during its attached document-modal sheet; retained
actions reject invocation and restore after dismissal. Other windows stay usable.
This independently tested modality correction does NOT resolve013: the first
exact native rerun fails81.179s at the unchanged pointer-hittability assertion;
the direct-hit-exclusion rerun also fails there. Live Header/menu geometry and
Tab focus pass. The first original retained failure screenshot shows one readable
upright Menu per owner with genuine visible focus and no duplicate raster label.
No pointer success or Safari acceptance is claimed. The next exact diagnostic
compares standard controls in the same sheet and tests genuine Space/Escape menu
operation before the unchanged strict pointer assertion. No coordinate bypass,
privacy change, owner-data operation or broad suite is authorized.

Further exact diagnostics (all failures retained):

- `focused-ea9d842a-8140-4654-a295-485b99cb5f91`: modal regression0.629s
  passes;01381.069s fails strict hittability.
- `focused-51fe675a-107d-4f41-b392-b34e4b90b8c7`: Space does not expose
  About after real Tab focus; no pointer assertion was removed.
- `focused-82e87407-b7e7-481e-a0ff-2b3377cba27b`: removing the explicit
  focus wrapper makes Tab focus fail81.693s; wrapper restored.
- `focused-dd0c5deb-6aa4-457b-9bd9-5153c666ec5d`: Down Arrow does not open
  About79.395s. Original peer attachment reports `menuHittable=false`,
  `doneHittable=true`, `pagePickerHittable=true` in the same owned sheet.
- `focused-c1ee0d64-becb-46ec-a210-9fae8b1a9bc5`: two existing Preview
  geometry tests pass; replacing drawing transforms with native Layout placement
  does not fix activation (013 fails78.590s; same peer results). A preceding
  experiment failed compilation on WorldPoint/WorldSize-to-CGRect conversion;
  explicitly corrected before this run. The ineffective Layout experiment was
  removed, not shipped or counted as a root fix.

The current journey retains its strict pointer assertion and now also requires
genuine native Down Arrow menu opening/Escape restoration before that pointer
path. Diagnostics are bounded bool/rectangle/fixture hierarchy attachments, not
canonical mutations. The framework/root cause remains unproven; do not call the
failure external merely because geometry tests pass. A broader native Preview
host replacement is recorded for owner decision in OPEN_DECISIONS. Current
Save/reopen and015 targeted checks validate modal canvas restoration, not013.

Final direct-neighbor check `focused-50745293-98c5-455e-8e97-54aec3176938`
exits0: modal regression0.622s, native Save/close/reopen64.999s,015 repair117.126s
pass3/3. No process remains active. Distinct coverage stays41 code/7 of8 native;
repeated passes do not increase those unique-method counts. Full verification is
deferred, not run. All seven new original-resolution PNGs were inspected in
`siteforge-012-016-acceptance.eJiZ5V/modal-direct-neighbor-passes/`:

- `CC60AD5D-EAC2-4A2D-B170-F7F3B70D55F6.png`: reopened package, actual Saved
  status, #315A7C99/60% and aligned Frame surface/selection.
- `53D7F379-85A9-417F-94DB-A95963ADE57D.png`: appearance edit before native
  Save; correctly shows Modified despite the historical attachment name.
- `95DEC040-4950-4BAA-9156-6A88875CB74B.png`: successful revision6 local
  website, explicit Refresh and enabled Export; no publication.
- `2825B3B9-7954-482B-9E47-177AA3E2DCF3.png`: Check Website's readable
  specific clipping finding and real Open Design repair.
- `B0811BB3-5C80-4356-8171-2646607937DF.png`: exact Header selected in existing
  Design editor, upright title/link, aligned surface/selection, readable clipping
  control. Inspector is intentionally scrolled; its preview-state opacity draft
  placeholder is truncated, so this image is not broad Inspector-label acceptance.
- `84765719-85DB-49DB-8E5E-FE9B2DE488A8.png`: blocked Preview truthfully
  retains the last output state and names the same repair.
- `7A4DD135-B875-40DE-B782-07ADC3FCB322.png`: #GG draft retained, visible
  validation and bottom paused-action explanation, no canonical fill mutation.

Reviewed native shell proportions, persistent unwrapped tab labels, canvas grid
gutters and visible boundaries remain coherent; no new stale/ghost content or
upright-text regression appears in these originals. The hidden legacy frame in
the Save fixture is intentional migration input, not a genuine blank project.
These are app-window captures, not independent proof of menu-bar/Dock state.
013's native activation and its unreached measured-Safari tail remain unaccepted.
Owner decision is requested before changing the approved Preview host; all dirty
work/evidence remains preserved, no Git/install/full-gate/017 action occurred.

All following run-by-run notes are a retained chronological diagnostic ledger,
not instructions to restart an old run or a claim that an old experiment shipped.
No whole-target test, full verification, Git/delivery or owner-data change is
authorized. Keep all items IN PROGRESS and modules Partial.

## Controlled native continuation — owner present,2026-11-01

Owner authorizes ONE fresh exact012 native attempt. Process inspection found no
runner/app/xcodebuild active. Ordinary app identity remains app.siteforge.SiteForge;
the existing test executable16:37:26 is newer than UI source16:36:57, and no
production behavior has changed since the compiled products/code receipts.
Use existing My Mac xctestrun/products with test-without-building, no clean or
incremental rebuild needed. Start only the exact012 selector; observe any NEW
authentication promptly. If it initializes, continue the seven named native
methods serially; if authentication times out again, stop attempts and retain
the external handoff. Thirty-six code passes are preserved, not rerun. All
original no-Git/full-gate/install/owner-data restrictions remain.

Current continuation **initialized without a new authentication request**.
`native-f109a6c3-5384-46bf-9160-2f34fc525a76` executed the exact012 method and
failed at an ambiguous Copy Appearance locator: native Edit and the open
Inspector menu both legitimately expose that title. Target the shipping
`formatting.copy.appearance` / `formatting.copy.textStyle` identifiers instead,
retaining enabled/disabled and actual-command assertions. Added two named
app-only screenshot checkpoints to that same journey, not a second tour.
Incremental rerun `focused-b6f4530a-c4f8-40da-a062-6ce9912e7a2b` initialized and
failed earlier on a1.5-point screen-Y difference after a tab switch. The exact
equality is retained. Bounded snapshot-vs-live object/canvas/viewport attachments
are being added to trace whether initial adoption or actual layout diverges;
no production offset, tolerance increase or sleep has been applied.

The seven listed methods completed serially in
`native-ee087949-dffb-45ea-8b25-8b97754b5230` (parallel testing disabled):
four pass (component original/return173.907s, border/radius/shadow72.020s,
native Save/reopen63.352s, fill/opacity66.940s); three fail (narrow native menu
hittability73.235s, repair summary AX query67.905s, compact Text label query129.020s).
All seven executed; none skipped. The last two failures retain real screenshots:
repair summary visibly says no successful website, while Text's shipping canvas
label is `Text object`. Correct the query boundaries, not the product state.
Attachments and original recordings are in `native-seven/` under the root below.

Exact012 diagnostic rerun `focused-fdf54509-7d56-4fec-9c1d-9b1e5de94ac6`
fails19.868s and proves the canvas height changes879→882, top119→116 while
window geometry is unchanged. Both cached and fresh initial object frames agree;
this is actual viewport-header geometry, not a stale AX proxy. Reserve the
existing28-point compact-control minimum for both adaptive toolbar groups;
larger intrinsic content remains free to grow. Exact equality remains unchanged.
013's bounded hit-state diagnostic retry is running; no menu action is bypassed.
Runtime preparation already uses the correct320-point page width; the full-page
fit shrinks the native menu. Its actual paint/hit boundary still needs diagnosis,
not an invented Desktop-width fix.

`focused-012663ba-949c-4ff7-9c5f-a4638f3737e8` retains the next concrete
diagnostic: native menu exists/enabled but hittable=false, screen rect29.3×9.28
inside a620×329 Preview. Original `menu-failure-original.png` and the exported
`narrow-menu-diagnostic/` confirm an unusable full-height-fitted thumbnail, not
an authentication or missing-destination failure. Native Preview now fits width
at most1:1 and scrolls tall pages, preserving immutable authored bounds.
New direct regression:
`SiteForgeTests/CanvasRendererTests/testNativePreviewFitsWidthAndScrollsTallPagesWithoutChangingAuthoredBounds`
plus the existing navigation layout/hit-bounds neighbor will run before native
revalidation. These two results are pending. No broader renderer sweep authorized.
The corrected012/014/015 exact native group
`focused-3dbbb978-ac23-4974-88f8-7cfd1435b587` completed0/3:012 advances through
all five tabs with exact unchanged geometry, then Settings is disabled55.486s;
015 advances through artifact status then keyboard activation fails77.049s;
014 advances through real Text insertion and compact invalid draft, then its
nonempty validation query reads label instead of native text value162.912s.
Failures/recordings remain in `three-targeted-followup/`. No assertion removed:
use the real Text object label and semantic validation value. Settings availability
now uses the same window-owned document state as invocation, not the unrelated
focused LaunchExperience.015's hierarchy/recording proves Open Design is keyboard
focused but Space leaves the sheet unchanged; its shipping focus interaction is
now explicitly activation, not editable focus.

`focused-f952806e-c3c9-45f1-a14b-1e2fa98ba80d` passes3/3,0 skipped: new Preview
width/scroll regression, existing scaled navigation geometry regression, and
`TransformModelTests/testWebsiteSettingsNoChangeIsNeutralAndStillRejectsStaleIdentity`.
Distinct code methods with passing evidence now39 (31new/eight neighbors), not
a single39-method invocation. Four impacted new UI methods are running in
`focused-037ed994-76d8-4b28-899d-65c0b684ce35`; passing direct neighbors are not
rerun. No duplicate process or broad gate.

Further concrete review corrects two provisional diagnoses above. The retained
File-menu recording shows Settings visibly enabled; the failed locator has only
a query chain, not a disabled target. AppKit's displayed ellipsis does not match
the title-only query. Restore the original launch availability guard (the
speculative removal did not fix the failure), give the real shipping command
`menu.siteSettings`, and resolve that semantic ID in the existing helper.

Native Preview's navigation object also retains `plainText = "☰ Menu"` for canvas
rasterization. The view painted that text host *after* the real native Menu,
duplicating its label and covering its interaction surface. Native navigation
now replaces this canvas proxy rather than painting both. Ordinary authored
Text still uses the shared text renderer. A direct regression verifies this
production predicate without rewriting snapshot text or identity:
`CanvasRendererTests/testNativePreviewNavigationReplacesCanvasProxyTextButPreservesOrdinaryText`
(pending). Width fitting/scrolling remains the separate readability correction.

The activate-only focus experiment excludes the repair button from ordinary Tab
traversal on this Mac; its next failure is retained. Use discoverable focus with
a shipping Space key handler consuming one key-down and invoking the same real
Button action. Pointer/VoiceOver use that same callback/registry. No test-only
control, model shortcut or relaxed keyboard assertion is introduced.

`focused-ba78611d-e3e9-45f9-b0ea-3e0d437cf461` stopped at compile: the new
KeyPress callback requires an explicit ignored argument. Corrected `_ in`;
the exact new proxy-text regression reran in
`focused-b4b93aa5-3efa-4e3f-978d-bd65607b035d` and passes1/1. Distinct code
passing evidence40 (32new/eight direct neighbors),0 skips. No code sweep rerun.

`focused-037ed994-76d8-4b28-899d-65c0b684ce35` finishes0/4 with retained
81.581/54.923/74.930/215.174-second failures. It confirms width fitting alone
does not fix the menu: Menu is now92×26 yet an overlaid canvas text host visibly
duplicates its label. It also exposes014's second query error: several Header/
Footer titles legitimately share `Text object`; capture the newly **selected**
insertion after live adoption, not the first title in paint order. Selection
assertions remain exact, and the recording visibly retains the intended Text.
The next four exact native methods are active in
`focused-11b28129-8a80-43b1-8077-702849a85796`; no duplicate run or auth request.

That run now records015 repair PASS116.964s, including keyboard Space activation,
exact Header editor adoption, real undo/redo, Check Website and successful Safari
refresh.014 continues.012's ID experiment did not resolve the command (Commands
does not expose that SwiftUI identifier); remove it and query the two exact
native title/label ellipsis spellings with a uniqueness assertion. No command
availability change remains.013 still fails native hittability after duplicate
paint removal; retain that failure and add an exact AppKit hosting/hit-boundary
test, not an offset, test button or bypass click. Five distinct native methods
have passing evidence so far; three remain under correction.

`focused-11b28129-8a80-43b1-8077-702849a85796` finishes2/4:015 passes116.964s
and014 passes380.077s.012 fails54.545s and013 fails81.725s. Six distinct native
methods now have passing evidence,0 skips; only012/013 remain. Originals are
exported to `repair-and-inspector-passes/`. The native Preview image confirms
duplicate Menu glyphs are gone and controls are readable; reported hittability
still fails. The new real-AppKit host/hit test is running in
`focused-e388cf5a-aad8-45f7-8586-4b3523171674`; do not infer interaction success
from correct painting. No passing native method is being repeated.

Native follow-up `focused-36dbbfd6-d2a5-47a3-b81f-bc1b5beab6b7` completed1/3:
013's fresh role-specific query still fails76.766s.012's exact native title query
finds two global matches49.273s; scope it to the opened File menu and keep the
uniqueness/enabled assertions.014 is rerun only because original-resolution
review found clipped token captions: wrap them and assert actual bounds for
those/effective-typography captions at compact width.015 is not repeated.
014 passes401.678s, including those new containment assertions. All nine named
Inspector originals in `compact-caption-followup/` were inspected. The invalid
draft image `C5C22AAC-3324-4C5A-B8BA-71E93C01D07B.png` also shows the wrapped
token captions fully readable; the later full-width/strips image is actually
on Accessibility after tab traversal and is not typography evidence. Compact
copy/recovery text wraps without clipped actions, normal Header/Footer paint
aligns with selection, and empty/1280/wider states retain distinct artboard/grid.

The new actual NSHostingView/native-control test retained three diagnostic
failures (`e388cf5a`, `ccea9a59`, `f6970599`). Its original hitTest fixture passed
local coordinates to an API requiring superview coordinates. Per-ancestor
conversion proved the native control is the true physical hit target; correct
that single AppKit conversion, not production coordinates. Exact rerun
`focused-8d2bf2c4-3a6c-4552-ab21-c9c7d9eb90c9` passes1/1. A temporary sanitized
AX target-class diagnostic is pending to locate the remaining accessibility
boundary. Native Menu update also rebuilt NSMenu on every unrelated publication;
retain menu/item identity for an unchanged immutable navigation snapshot, with
actual NSPopUpButton/NSMenu identity/current-page/no-action regression assertions
added to that same exact AppKit method. These added assertions are not yet run.
The added assertions now pass1/1 in
`focused-880ebbc9-2d9d-4c89-ab20-d1e713d53809` (0.040s). This brings distinct
code evidence to41 (33new/eight neighbors), across the recorded targeted runs.
Temporary AX class output reports the native cell from the button and the
hosting view from the host; it does not prove remote XCTest hittability and
has been removed. The exact012/013 native follow-up is active;014/015 and the
four passing direct native neighbors are not repeated.
`focused-3a7867e8-40a1-4755-9ba2-ec7a2ad6f5e5` completed1/2:012 passes69.995s;
013 still fails76.933s. The Settings fix is strictly a live File-menu-scoped
query, retaining one-match/enabled/click/cancel checks; production availability
was already correct. Both012 originals in `formatting-pass-menu-followup/`
were inspected: formatting remains visible without Tools, selection/paint align,
and exact copy return shows readable original/copy semantics. Seven of eight
distinct native methods now have passing evidence; only013 remains.

The multi-object native Preview has decorative absolute-positioned surfaces
beside real links/navigation. Noninteractive paint now explicitly declines
input, preserving authored link buttons and native navigation as the only
interactive Preview content. The real-host regression includes a later Footer
surface; the exact code/native follow-up is running. This is not a claim that
remote native-menu hittability has passed.
`focused-d419fb53-9244-4b88-a48b-a2fd896157f4`: the multi-object AppKit method
passes0.039s;013 still fails75.974s. The following bounded experiment preserves
object-local paint/clipping bounds before page placement (offset rather than a
page-sized position wrapper), with a second real Footer menu added to the host
fixture. `focused-c7874efb-06ea-4822-ac7b-3696360d15b9`: that code method
passes0.038s;013 still fails. Neither change alone proves the remote AX cause.
A real center-pointer diagnostic is added before the unchanged failing
hittability assertion to distinguish actual occlusion from remote hit reporting;
only013 is rerun in `focused-89661848-8d6b-4de3-bfd6-04849eb8c391`.
That diagnostic opens the actual native Home/About menu at its own center;
original `real-pointer-diagnostic/3D39D657-49D0-4FE5-8A09-BE8DB95012DF.png`
was inspected. Thus the control is not physically covered. The unchanged
hittability assertion still fails. The two unproven input/placement experiments
above were removed, preserving established geometry. Native menu update
idempotence remains independently covered. The next narrowly scoped correction
explicitly exposes the genuine NSPopUpButton view as an accessibility element;
the same code/native methods are running, with no weakened hit/focus assertion.
`focused-b12294dd-6a12-453b-a9b8-01db2e8f8d45`: code1/1 passes0.041s;
explicit view exposure alone changes the remote role so the exact native
MenuButton query no longer finds it. Set the genuine pull-down's standard
menu-button role as well and assert that role in the real AppKit regression.
The next exact two-method run is active. No change to query type, hit/focus
requirements, native menu tracking or navigation callback was made.
`focused-dee02ece-7205-40ed-8a0f-f70e33e18307` retains the failed explicit
view/role experiment; it was removed. Direct system AX read from the UI runner
is denied (`-25211`) in `focused-faa9767a-b734-429d-838f-53a13a01366e`;
no privacy/authentication change or retry of that API was attempted.

The exact in-process AppKit trace passes in
`focused-7b8b97cb-01d9-40f2-91e6-221c8a6719b1` and identifies a concrete
mismatch: lookup metadata is on the ignored control view (`AXUnknown`), while
the real hit target is `NSPopUpButtonCell` with no identifier. Its trace is
retained in `native-ancestor-hit-trace/`. Shipping configuration now gives that
actual native cell the same identifier/label/help. The regression asserts the
actual accessibility hit cell's identifier, label and standard menu-button role,
alongside physical hit geometry and menu identity. All temporary pointer/system
AX/in-process trace code is removed. The exact code/native rerun is active;
remote hittability remains unaccepted until it passes unchanged.
`focused-ff5c8a0c-5dbe-433e-897a-443a95b7c61a`: code passes0.041s;
013 still fails76.040s. Identity alone was not sufficient. The added activation
point assertion was not in that already-compiled test product. Its first actual
execution in `focused-15a4ff5a-95bb-46d1-87cd-b5657e271ede` fails numerically:
native cell activation=(0,0), actual screen frame=(209,300,92,26). That is the
first proven incorrect interaction geometry, despite correct authored/paint/hit
rects. The actual-cell parent trace is retained in `native-hit-cell-parent-trace/`.

A genuine NSPopUpButtonCell subclass now derives its activation point on demand
from its current native accessibility screen frame. No page coordinate, fixed
offset, synthetic visible state or test branch is involved. The regression
requires point/frame/physical-center agreement and rechecks after moving the
owned window. Native metadata and unchanged-menu identity coverage remain.
Temporary traces have been removed; the exact code/native follow-up is active.
`focused-c9e61b17-37a5-4680-9897-0c94bdea1c69`: the corrected cell regression
passes0.043s, but native013 still fails76.081s. Expanding the assertion to the
representable view in `focused-b56ba36c-91ac-45bf-b308-a03bc13d0dc6` proves
its separate default remains(0,0), versus real screen center(255,313). The native
view now delegates to the cell's single live activation-point calculation, with
both paths asserted before/after owned-window movement. This closes the two
proven metadata boundaries without changing geometry or accepting stale input;
the current exact two-method run is still pending native acceptance.
`focused-988e5edf-4c51-4bc6-b5ec-34ddb7b372a9`: code passes0.041s;
013 still fails76.305s. Explicit SwiftUI center-point metadata
(`focused-b478c66a-010b-48d0-8640-3d82fc7431c0`) and truthful native
interaction metadata (`focused-a8f7e747-f4a7-40bd-b3fe-833ecbc159aa`) do not
alone resolve the remote hit result. The journey now additionally requires real
Tab traversal before its unchanged pointer/hit/Escape assertions, scoped to the
live Preview sheet. `focused-0e5e5717-0ed9-4133-859a-a1179ff860e7` fails that
new focus boundary78.300s.

`focused-2bb9b90b-29c7-47d4-9620-e07bba767a73` proves the native control's
`canBecomeKeyView` is false in the AppKit regression. Fresh key-event diagnostics
also prove the workspace router correctly passes events to its attached sheet
(workspace key=false, attachedSheet=true, menu tracking=false), rather than
stealing Tab. The older attachment-only focus snapshot was stale and cannot be
used to claim a window-ownership defect. That temporary event tracing is removed.
The native control now participates in the key-view loop, its cell permits first
responder, and replacement preserves the original native bezel/border/font.
Only the exact host and013 methods are running after this concrete correction.
The QoS warning in two runtime records is retained for backtrace inspection,
not yet assigned to product or runner. No publish/invalid-geometry clearance is
claimed merely because a log search found no such text.

First-failure attachments/recording are retained in
`siteforge-012-016-acceptance.eJiZ5V/native-first-failure/`; second geometry
failure in `native-formatting-geometry-failure/` under the same root. Inspected
the original recording frame `formatting-menu-ambiguity-original.png` and live
exact-build screenshot at full resolution: all five tab names fit, native
controls/formatting header are readable, artboard/grid are distinct and Frame
paint/selection align. This bounded state does not accept compact/other states.
Second recording frames `insertion-original.png` (empty state before insertion)
and `design-original.png` show upright fields, coherent panes and selected Frame;
numeric initial-vs-live divergence still needs its new diagnostic receipt.
Videos remain intact; frame extraction reads them via AVFoundation, not a
replacement app/browser screenshot or modified authored content. No owner data,
installed app, code-group rerun, full gate or Git action occurred.

IN PROGRESS. Owner authorizes compilation, exact scoped tests and actual native/
current-Safari original-resolution review. No full suite/whole class/target,
`./sf verify`, broad checks, Git operations, installation, signing, release,
scheduling, evidence deletion or owner package/resource/recovery edits. Preserve
all dirty work, frozen historical receipts and coordinator files. No017.

## Plan and requirement scope

Initial process inventory: no existing xcodebuild, sf test, SiteForge runner or
test app was found (only the inventory command itself). Use existing ordinary
SiteForge scheme/My Mac destination and app identity, no privacy/toolchain change.
Build-for-testing once, then30 exact new code methods plus six direct neighbors.
Record complete failures before repairs; rerun only impacted methods after a
concrete change. Four distinct new native methods run serially, then four exact
direct Design/component neighbors. Extend013's existing journey for Footer
rather than adding a broad duplicate. Review retained failure and success images
at original resolution and measured CSS viewport sizes, not outer window sizes.

Requirement scope is inherited, not module completion:
SF-0201-009; SF-0202-003; SF-0203-006; SF-0206-002;
SF-0701-002/003/006; SF-0702-003/004; SF-0703-003; SF-0704-003;
SF-0302-004; SF-0308-004; SF-0501-003/004/005/006;
SF-0502-003/005; SF-0505-003; SF-0601-003/006; SF-0602-003/006;
SF-0806-002/003/004/006; SF-0901-003; SF-0902-003; SF-0903-003;
SF-0905-004; SF-0510-003; SF-1202-003/004/006;
SF-1203-003/004/006; SF-1204-003/004/006; SF-1211-004/006.
OD-018/019 and updater/security decisions are unchanged. All modules Partial.

## New code inventory —30 exact selectors confirmed in source

- `SiteForgeTests/AppMetadataTests/testPlainAuthoringVocabularyPreservesCanonicalKeysAndSizingValues`
- `SiteForgeTests/AppMetadataTests/testPlainInspectorDiscoveryRetainsTechnicalSearchAliasesAndMixedScope`
- `SiteForgeTests/AppMetadataTests/testPlainComponentRecoveryStyleSampleAndReviewCountsNameTheirLimits`
- `SiteForgeTests/CommandKernelTests/testPlainComponentDiscoveryFindsCopyOriginalAndDefaultContentsWithoutMutation`
- `SiteForgeTests/CommandKernelTests/testPlainRecoveryRemovalPreservesConfirmationScopeIdentityAndExactUndo`
- `SiteForgeTests/InsertionModelTests/testAutomaticChromeMenuFirstAllocationAtPhoneFractionalAndLargerWidthsIsReadOnly`
- `SiteForgeTests/InsertionModelTests/testAutomaticChromeHiddenEmptyLongAndMultilineTitleRetainsIdentityAndLinePolicy`
- `SiteForgeTests/InsertionModelTests/testAutomaticChromeMenuCardinalityVisibilityAndOffPreferenceRemainTruthful`
- `SiteForgeTests/InsertionModelTests/testAutomaticChromeMissingDestinationsDoNotCreateDecorativeMenu`
- `SiteForgeTests/InsertionModelTests/testNarrowChromeCustomSizingSpacingFontsAndFluidIntentAreNeverRewritten`
- `SiteForgeTests/InsertionModelTests/testAutomaticChromeFixedLogoAndAuthoredGapUseSameInnerBudget`
- `SiteForgeTests/InsertionModelTests/testAutomaticChromeStaticAndFluidAdaptersKeepSharedContinuousAllocationAndBlockers`
- `SiteForgeTests/InsertionModelTests/testAutomaticChromeNativeSceneSelectionHitAndPreviewShareFinalMenuFrame`
- `SiteForgeTests/InsertionModelTests/testAutomaticChromeEditsCopiesUndoPackageAndRecoveryKeepAllocationNoncanonical`
- `SiteForgeTests/WorkspaceMaterialPolicyTests/testMeasuredSidebarTabsHonorActualPaneBudgetAtNormalCompactAndIncreasedText`
- `SiteForgeTests/WorkspaceMaterialPolicyTests/testInspectorActionFlowKeepsLongActionsOrderedContainedAndNonoverlapping`
- `SiteForgeTests/WorkspaceMaterialPolicyTests/testInspectorFieldColumnsUseCompleteMinimumsInsteadOfSqueezingOrTinyType`
- `SiteForgeTests/CanvasViewportTests/testInspectorPanePresentationPreservesDraftSelectionHistoryAndCanonicalBytes`
- `SiteForgeTests/InsertionModelTests/testOutputFindingTargetUsesExactReceiptMembershipTypedEditorsAndReadOnlyIdentity`
- `SiteForgeTests/InsertionModelTests/testPreviewAndCheckWebsiteRevealExactCrossPageObjectAfterSceneAdoptionWithoutHistoryOrPackageMutation`
- `SiteForgeTests/InsertionModelTests/testOutputRepairRejectsOldForeignPageChangedAndProjectReplacedReceiptsWithoutPartialNavigation`
- `SiteForgeTests/InsertionModelTests/testOutputRepairCleanEditorIMEAndCancellationGuardsNeverCommitUnrelatedDrafts`
- `SiteForgeTests/CanvasRendererTests/testBrowserFindingReceiptIsIndependentOfRetainedSuccessfulArtifactAndExportIntent`
- `SiteForgeTests/TransformModelTests/testLegacyDesignTextDraftCleanDefaultsMixedAndDisplayRefreshDoNotBlockNavigation`
- `SiteForgeTests/TransformModelTests/testLegacyDesignTextDraftRetainsInvalidInputAndRejectsEveryChangedOwnershipBoundary`
- `SiteForgeTests/TransformModelTests/testLegacyDesignTextDraftAcknowledgementNeverDiscardsAnotherFieldAndEscapeReloads`
- `SiteForgeTests/TransformModelTests/testShadowInspectorDraftRejectsEmptyExtraMalformedAndNonfiniteComponentsWithoutCoercion`
- `SiteForgeTests/CanvasRendererTests/testBrowserRetainedArtifactCannotOpenOrExportAfterImmediateProjectReplacement`
- `SiteForgeTests/InsertionModelTests/testLegacyDesignEquivalentBoxCommitIsSuccessfulAndHistoryNeutral`
- `SiteForgeTests/InsertionModelTests/testCheckWebsiteEntryDoesNotCancelOrRetargetAnActiveStaticWrite`

## Six directly affected existing code neighbors

Two014 layout, three015/016 artifact/export and one exact original/return boundary:

- `SiteForgeTests/WorkspaceMaterialPolicyTests/testNativeOverflowPaintsTheDisplayedPullDownItemAndRetainsAccessibleControl`
- `SiteForgeTests/WorkspaceMaterialPolicyTests/testNormalPaneMinimaFitAllFiveMeasuredDestinationLabelsWithoutOverflow`
- `SiteForgeTests/CanvasRendererTests/testBrowserExportPanelIntentCannotRetargetReplacementBuild`
- `SiteForgeTests/CanvasRendererTests/testBrowserPreviewPendingIdentityCancelsReplacementAndRevisionWithoutOpeningBrowser`
- `SiteForgeTests/CanvasRendererTests/testBrowserPreviewExportUsesExactSnapshotAndSupersededCompletionKeepsStoppedStatus`
- `SiteForgeTests/CommandKernelTests/testComponentPropertySourceTransitionReturnsExactInstanceAndGuardsRenameContext`

## Four new native journeys — serial

- `SiteForgeUITests/SiteForgeLaunchTests/testFormattingCommandsRemainVisibleAcrossInspectorDestinationsWithoutToolsDisclosureJourney`
- `SiteForgeUITests/SiteForgeLaunchTests/testAutomaticNarrowChromeNativeAndMeasuredSafariMenuJourney`
- `SiteForgeUITests/SiteForgeLaunchTests/testStableInspectorStripsFieldsDraftsAndComponentRecoveryAtNormalAndCompactWidthsJourney`
- `SiteForgeUITests/SiteForgeLaunchTests/testPreviewAndCheckWebsiteFindingRepairUsesExistingEditorJourney`

Four justified existing native neighbors: real Save/reopen, legacy box fields,
fill/opacity keyboard/undo and exact original/return:

- `SiteForgeUITests/SiteForgeLaunchTests/testDesignInspectorNativeSaveCloseReopenPersistsFillAndOpacityJourney`
- `SiteForgeUITests/SiteForgeLaunchTests/testDesignInspectorBorderRadiusShadowUndoRedoAccessibilityJourney`
- `SiteForgeUITests/SiteForgeLaunchTests/testDesignInspectorSolidFillOpacityKeyboardUndoRedoJourney`
- `SiteForgeUITests/SiteForgeLaunchTests/testComponentDirectPropertySourceRetainsDefinitionDraftAndExactInstanceJourney`

## Results / visual inventory

Initial build-for-testing failed on one new014 test expression: ambiguous
`.infinity` in CGSize. Explicit `CGFloat.infinity` fixes type inference without
changing the invalid-input assertion. Incremental build-for-testing then passed.
Logs: `siteforge-012-016-acceptance.eJiZ5V/build-for-testing.log` and
`build-for-testing-compile-fix.log` in that same directory. Existing unrelated
warnings and a nonblocking CoreSimulator version warning remain recorded; no
toolchain/privacy setting, clean build or cache deletion was used.

Initial exact36 code run `focused-327fe399-86c1-4466-b655-71bcd971afa6`:
36 executed,31 passed,5 failed,0 skipped;15 assertion records,0 unexpected.
Both `.xcresult` and matching `.log` are under
`siteforge-012-016-acceptance.eJiZ5V/TestResults/`.

Complete failure inventory/correction:
- `testAutomaticChromeMenuCardinalityVisibilityAndOffPreferenceRemainTruthful`:
  its global CSS absence assertion matched the fixture's independent valid
  Footer. Scope absence to the actual affected Header navigation selector.
- `testAutomaticChromeMissingDestinationsDoNotCreateDecorativeMenu`: same
  Header-versus-Footer fixture error in both adapters; exact target checks remain.
- `testOutputRepairCleanEditorIMEAndCancellationGuardsNeverCommitUnrelatedDrafts`:
  fixture awaited scene adoption before a real viewport initialization.
- `testOutputRepairRejectsOldForeignPageChangedAndProjectReplacedReceiptsWithoutPartialNavigation`:
  same missing viewport event. Both now resize before awaiting/using the scene,
  retaining exact identity/draft/cancel assertions and existing four-second bound.
- `testMeasuredSidebarTabsHonorActualPaneBudgetAtNormalCompactAndIncreasedText`:
  computed499.99999999999994 vs500, one CGFloat ULP, not a visible budget failure.
  Assertion permits exactly the adjacent representable lower value, not a pixel
  or point-sized relaxation; fit/overflow/containment assertions remain unchanged.

Only those five methods reran after these fixes:
`focused-4dc55448-c910-44f2-9ec3-bb2fd51f5672` passes5/5,0 failures/0 skips.
Latest distinct scoped code evidence:36/36 (30 new+six neighbors); no unchanged
whole-group rerun. Initial failures and their full results/logs are retained.

Native status: first exact012 journey started in
`focused-0a74e582-05f4-455d-813b-6e5bdbb5eddf` (same TestResults root).
At16:38:12 current coreauthd records a new XCTest Enable UI Automation
authentication request. Owner notified once during that active run; no bypass,
privacy change, inferred lock state or duplicate/unchanged retry. No native pass
or screenshot acceptance claimed yet.
The request timed out16:39:12; xcodebuild exited65 at16:39:18 after66.588s.
Zero actual UI methods executed. xcresult reports one synthetic runner-error
record (`SiteForgeUITests-Runner (40383) encountered an error`), NOT a failing
product journey or a test skip. All eight distinct planned native methods remain
unexecuted/unaccepted. Process inventory after completion found no runner,
SiteForge test app or xcodebuild remaining. No retry was launched.
013's one journey now includes real Footer title/menu focus and measured Safari
Footer bounds alongside Header.014's one journey adds actual1280 and restored
wider-window captures before its existing1100 dirty-editor case. No new tour.

Original reference images01/05/12 were found and inspected at original resolution
in the established external `SiteForge Original Renders` folder beside the repo:
`01-editorial-canvas.png`, `05-responsive-mobile-canvas.png`,
`12-settings-canvas-accessibility.png`. This supersedes only the earlier source
passes' unavailable-reference observation, not their lack of runtime visuals.
Reference direction: dominant bounded artboard, quiet native panes/field groups,
explicit responsive source and separate app Settings; unimplemented mock controls
are not new authorizations/capabilities.

Actual larger-text mechanism audit: inspected macOS Accessibility > Display >
Text Size without changing preferences. The current panel lists supported Apple
apps, not SiteForge. Preferred reading size remained Default;150/200% native
acceptance is NOT claimed from policy test constants. Returned System Settings
to its prior Network page. Actual app text-scale review remains a named limitation
unless a supported per-app mechanism is available during native acceptance.

Historical007–011/title receipts remain separate and do not validate this tree.
Normal1280/minimum1100/wider, supported actual larger-text mechanism/scale,
Header AND Footer, explicit repairs, measured browser widths/interactions and
all requested original-resolution evidence remain to be observed. Reference
originals01/05/12 must be located at established paths if available; otherwise
report that limitation without claiming concept-match acceptance.

Full verification and installed delivery remain mandatory/deferred boundaries;
this scope never authorizes them or a DONE declaration.

## Historical first-attempt handoff / distinct totals

The following records the earlier authentication timeout only. The controlled
continuation and later targeted results at the top supersede its next-step and
zero-execution statements; do not replay that authentication handoff.

- Compilation: passed after one explicit test type annotation; normal test
  products only, no installation/manual signing or cache cleanup.
- Code:36 distinct executed,36 have passing evidence after targeted fixes,
  zero remaining failed methods and zero skips. Initial31/36 and rerun5/5 are
  separate retained receipts, not a fabricated single green36-test invocation.
- Native:zero methods executed/passed/skipped; one runner initialization error.
  Four new and four named directly affected native journeys remain, along with
  the required real app/Safari/compact/focus/visual review. Source extensions
  for Footer and1280/wider were compiled, not executed.
- Runtime originals: none captured by this attempt because XCTest never entered
  a method. Original references01/05/12 were actually inspected, not substituted
  for app evidence. Their names are recorded above. No native/render/DOM parity
  or absence of runtime warnings is inferred from these code results.
- Actual larger-text coverage remains unperformed for the supported-mechanism
  reason above; model12/18/24-point checks do not become150/200% runtime evidence.

The bounded acceptance has **not passed**: code is green, native/visual proof is
externally blocked on owner-completed macOS authentication. Next safe step, only
with owner present for a fresh observed request, is the same exact012 native
selector, then the remaining seven serial selectors from this manifest. No
duplicate process, unchanged retry loop, privacy/security setting change or
request to send credentials. Native authentication is entered only in macOS.
No full gate/Git/install/new feature is authorized. All work remains uncommitted;
source changes after passing code receipts are only comments/native test source
and documentation, not new production changes invalidating those code passes.
