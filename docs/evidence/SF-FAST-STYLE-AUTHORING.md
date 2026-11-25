# Fast visual styling — work in progress

Owner packet: [FAST_STYLE_AUTHORING](../coordination/FAST_STYLE_AUTHORING.md).
Bounded SF-0506-001–008, SF-0508-001–008, SF-0701-001–008;
SF-0305/SF-0306 history/persistence and SF-1204-003/004 output where exercised.
No module completion or final delivery is claimed yet.

## Baseline, November 22

Installed verified starting source is
`9883ae6d6c5f068ff1346ac937918a75fea594ebd050c44067f89d441cfd4606`.
The native Testing Start UI button initiated retained run
`20261122-002839-6d7be934` for the existing ordered-fill and border/radius
journeys. Source remains unchanged while that collector runs.
The first input controller supplied comma-separated selectors and correctly
left Start unavailable; a corrected space-separated request started the run.
That input-controller error did not run product tests.

Inspection confirms common box controls follow advanced styles and semantics,
Add Stop always inserts legacySurface at 50%, and Colors actions immediately
commit through device RGB. These are inspected facts, not a diagnosed cause of
the owner’s gradient appearance. Actual native pixel reproduction is pending.
Baseline file snapshots are retained in `.codex-loop/fast-style/baseline`.

## Reproduced native geometry defect

Baseline native run `20261122-002839-6d7be934` passed both UI methods.
Its exported native before captures are under
`.codex-loop/fast-style/before/ui-attachments` (manifest retained).
The border capture shows specialist sections above everyday styling and
truncated peer controls at the supported compact width.

Before changing paint code, added
`CanvasTextRenderingTests.testNativeGradientDirectionAndContinuityMatchPhysicalCSSGeometry`
and ran it with the real Testing Start Regular button:
`20261122-003442-e2ddb950`, source
`9468b0ab1541a1b8e64b471dab924c13ceae0a743cbbe964dd62846eb52ef276`.
The one native test failed with 36 pixel assertions. It paints through the
production `CanvasContentTileLayer`/CALayer hierarchy, with wide/tall shapes,
0/45/90/135 degrees, 1×/1.25× zoom and four adjacent tiles.
Exported images/manifest: `.codex-loop/fast-style/before/native-pixels`.
The 240×80, 45-degree image has broad flat endpoint areas and a compressed
transition. Native bytes differ materially from physical CSS gradient projection
(e.g. tall 135-degree interior red 12 vs expected 79.69).

The inspected native path first shortened a unit-square gradient line then
scaled X/Y independently by box size. That changes physical direction and
compresses transition extent. The candidate now computes projected extent in
physical box coordinates, matching CSS's magic-corner geometry. Intentional
coincident stops and authored ordering remain separate. This reproduces one
concrete cause of flat gradient regions; it does not establish that every
owner-observed independently filled section had the same cause.

## Candidate verification underway

New source builds, with common active fill/gradient, border hex/alpha and
width/corner numeric controls above secondary sections. Owned previews use
validated cloned document data for paint preparation, then one canonical
command on completion. The candidate includes explicit zero border state,
identity-preserving layer conversion and largest-gap interpolated stop insertion.
Focused acceptance is pending; no new installation or final pass is claimed.
The first focused input controller timed out enabling XCTest automation before
its body ran, without creating a collector. The native route is being retried;
no current permission prompt was observed in the native window inventory.

The third focused launcher retry reached native Settings/Testing and pressed
Start Regular successfully after macOS completed automation authentication.
Current frozen run: `20261122-004955-a81c4a6b`, source
`f5f5cadfd1eb1277077cb2b69e81ca99429261eb2ab08cc2428afe2111f153e5`,
nine exact model/renderer/history/output selectors in
`.codex-loop/fast-style/focused-selectors.txt`. Its outcome is pending.
No CUA setup or global macOS preference change was needed.

Focused source `f5f5cadfd1eb1277077cb2b69e81ca99429261eb2ab08cc2428afe2111f153e5`
completed `20261122-004955-a81c4a6b`: **9/9 passed**, no skipped or failed
methods. The original 36 native physical-gradient pixel failures now pass.
The before and corrected 240×80/45-degree native images were visually inspected.
Corrected exported attachments are in `.codex-loop/fast-style/first-focused-attachments`.
This receipt also covers preview history/cancel/stale ownership, interpolated
stop insertion, existing fill/box registries and closed Frame/Section output.

Further interaction refinements (shared native ramp painter, explicit numeric
draft save/cancel handling, native gamut clipping and stable editor identities)
are now frozen in UI run `20261122-005625-3b754e95`, fingerprint
`7a59b11224bea976a21962e86dd256ad5393d77c8c9c6ce308597650fe5f3207`.
Three exact native methods are recorded in `.codex-loop/fast-style/ui-selectors.txt`;
the current result is pending. A new alpha/hard-stop/group-opacity native
regression compiles with these products but has not yet executed.

First real visual pass `20261122-005625-3b754e95` completed: compact
reachability passed, existing solid/opacity journey failed its visible decrement
arrow assertion, and the new styling journey reached native gradient conversion
but found zero separately addressable ramp handles. No UI acceptance is claimed.
Direct numeric enabling, width increment and border hex/radius edits were reached.
Exported captures, AX snapshots and screen recordings are retained in
`.codex-loop/fast-style/visual-1-attachments`. Faithful video frames at
`.codex-loop/fast-style/visual-1-opacity-failure.png` and
`visual-1-gradient-failure.png` were inspected.

The pass also exposed a wrapped Fill type label and truncated Remove peers.
The next candidate hides the redundant segmented-control label, uses fixed icon
affordances with complete accessibility names, moves Image Fill below everyday
appearance and explicitly contains the ramp's accessibility children. Native
stepper update reasserts current target/action and avoids resetting a value during
tracking; source reasons for rejected color previews now remain visible. These
corrections require replay. The gradient capture is visibly continuous; its
selected-stop text did not retain the attempted new value, so that boundary now
has an explicit semantic assertion and must be diagnosed before closeout.

Owner explicitly requires visible slider-plus-number controls for corners,
border width and opacity; the coordination packet and queue plan now include
that acceptance boundary. Replay `20261122-010906-c269a58c` was cancelled with
2/3 methods completed (compact passed, opacity failed, new workflow unresolved).
No collector remains. Inputs may now change; this interrupted run is retained
and is not claimed as a passing visual receipt.

Slider candidate source
`ce00ee4da8e3123e0b78335650d854dad5dfb1e5b59436a83cb8d61c4219dfbe`
was built and Start UI initiated `20261122-012449-8843483a`. Exact selectors
are in `.codex-loop/fast-style/slider-ui-selectors.txt`. Native sliders use a
fixed range throughout tracking, owned typed previews and release/key-up history
boundaries. Corner convenience range is geometry-derived and expands to retain
valid authored values. The complete numeric range remains available. Outcomes
are pending.

Run `20261122-012449-8843483a` ended failed. Its real UI actions reached
all three slider drags and one-step undo/redo; direct CGEvent posting from the
sandboxed UI runner was unavailable. The Escape assertion is moving to actual
AppKit window/key dispatch on the production slider, with canvas and history
rollback asserted, rather than requesting a new permission. Gradient stop edits,
three-stop ramp, pointer movement/undo and actual Safari preview were reached;
Save then exposed a first-save fixture without a destination. The fixture now
opens a retained project and will close/reopen its saved bytes. All observations
remain distinct from a passing whole-method receipt.

Regular run `20261122-014129-dff73fd7` failed build before executing any of
six cases: Swift 6 rejected captured NSEvents crossing actor isolation. Corrected
fixture constructs each event on MainActor and uses a keyed native window. Source
`647965deb484bfb6b33572093589c359802daa099efc15946b67e35cf610941f`
builds and is being launched again through Start Regular. No installation or
full-gate result is claimed.


### Native event/pixel receipt — November 22, 02:13

Regular Start run `20261122-015104-7b3b2920`, source
`647965deb484bfb6b33572093589c359802daa099efc15946b67e35cf610941f`,
completed all six selected methods: four passed, two failed, no skips. Native
Colors-panel close, accessibility getter/value separation, alpha-gradient stop
insertion/hard stops/grouped fill opacity and owned preview/history checks passed.
The real paint fixture measured a 4pt border's fourth inside pixel as blue
(fill), edge alpha192 versus interior128. This establishes the half-inside
centered stroke and separately composited border opacity. The candidate now
uses a clipped double-width stroke and one surface transparency group including
shadow, fill/image and border; verification is pending.

The native Escape fixture dispatched values and cancelled once without history
changes, but failed its before-Escape canvas-observation assertion. Its timers
were installed without explicit future fire dates; all events completed in
0.098s despite intended 0.1/0.6/0.8s delivery. Assigning explicit future fire
dates corrects that fixture timing. The timed actual native gesture still needs
a fresh receipt; no cancellation acceptance is claimed from this failure.

Build preparation initially waited on Documents access for two provisioned
SiteForge build-worker identities. Bounded native XCTest permission inspection
allowed only the currently requested owned source-folder access. Asset and Swift
compilation then resumed and build-for-testing succeeded. No CUA permission or
global preference change was needed. Permission-inspection receipts and logs are
retained under `.codex-loop/fast-style/build-permission*.log` and the temporary
native controller xcresults. This is setup evidence, not extra product tests.

The owner expanded delivery to the interactive gradient, footer/QR and editable
Aurora showcase packet. Its dependent queue plan and ADR-0026 are recorded.
No expanded implementation or final installation/commit is claimed yet.


### Retained visual inspection — native Preview discrepancy

Inspected actual earlier UI attachments at matching provenance:
`slider-1-attachments/1F83A338-5F1F-4E6D-88CB-B8153C9C2212.png`
shows native Local Preview's rounded box as a flat purple surface, while
`3D4B7FD9-A4FF-405A-A51B-35850FA72085.png` shows Safari's smooth red-to-blue
diagonal gradient. `LocalPreviewObject.previewFill` explicitly samples only
`(0.5, 0.5)` before filling a Color. This separate production projection defect
remains pending replacement with shared native authored-gradient painting and
visual replay. The browser screenshot establishes static gradient appearance,
not native Preview parity or final acceptance.

The slider inspector capture `345DC73E-A49E-4C58-B801-748A353C3722.png`
shows visible border/corner/opacity sliders and their values at the constrained
width. It does not clearly show the selected box in the canvas; final gesture
captures must keep the selected geometry visible and show live change, not only
successful inspector assertions. Alpha percent also needs a visible label.


### Follow-up native receipt and fixture correction

Regular run `20261122-021621-ed062098`, source
`b30bdc2af1376cad4a105ec4386d5701831716bee20468c0d8b900604dbea1f2`,
completed six methods with five passing and the synthetic-event method failing.
The actual border width/opacity pixel regression is now green; the four prior
passing cases stayed green. The synthetic mouse fixture still returned before
its scheduled Escape: locally constructed NSEvents do not hold hardware mouse
button state through NSSlider's cell tracking. This receipt does not prove a
production Escape failure, and does not establish held-preview acceptance.

The replacement fixture dispatches Escape synchronously inside the actual native
cell's preview action while the production gesture owner is active. A separate
native keyboard gesture remains open across asynchronous scene preparation,
asserts visible renderer adoption, then cancels through native key dispatch and
checks exact document/history rollback. Existing real UI mouse drags and their
undo/redo assertions remain intact. Fresh execution is pending.

Native Local Preview now uses a shared authored-fill NSView rather than a
midpoint Color, with border and shadow inside its object-opacity group. A native
surface pixel regression checks spatial gradient and alpha. Shared color controls
now visibly label Alpha and offer the same native slider-plus-number pattern.
These later edits have no passing receipt yet; final visual/full/install gates
remain pending.


### Seven-method native follow-up — green

Regular Start run `20261122-022231-93b36eba`, exact source
`f99fb92e7398b7f2d935f999e40e4543845ca32f09ef3c032f5afc6c5f7e9f8a`,
passed all seven selected methods, no failures, skips or unrun. Includes actual
native device-Preview gradient/alpha pixels, full authored inside border thickness
and single opacity, shared Colors close, native accessibility value separation,
alpha/hard-stop/insertion pixels, native Escape dispatch during the production
tracking action plus asynchronous keyboard-preview cancellation, and owned
preview/history/stale-context boundaries. The exact inventory and native
attachments are retained in that persistent report. Real UI replay and expanded
feature acceptance are still pending; this focused receipt is not a full gate.


### Real native UI receipt — two green journeys, opacity arrow still failing

UI Start run `20261122-022559-aa5c2bdc`, same exact source `f99fb92e7398…`,
completed all three selected journeys. Slider drag/undo/redo/full-range numeric/
keyboard/save and gradient/color/stop-drag/native Preview/Safari/save-reopen
journeys passed. Old SolidFillOpacity failed only its actual decrement click.
Inspected `attachments/ui/0/073F449B-2003-4316-B900-3B0DA52EFD46.png`:
the rounded selected box is now clearly visible after Fit Document, with visible
radius/border/opacity and Alpha sliders at the supported compact width.
Inspected native Preview `EC48C834-7C51-4548-B739-3AAA219A8B84.png`:
the smooth gradient is restored; its radius was visibly larger than scaled
geometry. Native Preview now scales radius, stroke/dashes and shadow metrics and
keeps its exterior shadow outside the content clip. Fresh pixels are pending.

Candidate follow-up keeps NSStepper AXValue numeric and exposes units/provenance
through AXValueDescription; the real arrow replay must determine whether this
addresses its failure. Shared owned color editing now covers advanced solid/
gradient layers, text foreground and shadow as well as the quick controls.
Mixed shadow/text states stay explicit; failed commits retain valid drafts.
Active fill/stop/type changes resolve editor ownership first. Numeric display
retains authored precision rather than rounding all values to whole or tenths.
No passing receipt covers these follow-up changes yet.


### Shared-color follow-up — observed results, not closed

UI Start `20261122-023908-c6c23e18`, source
`fbaf1de0b14359c2dd00200a10c20f9ba630462198f75a87512266f137bc2d51`,
completed four selected journeys. Gradient editing/native Preview/Safari/save-
reopen passed again with scaled Preview metrics. Three failed: the old advanced
layer fixture selected the new quick ramp via a global `.angle` match; the old
text foreground fixture still requested the former global validation identifier;
and the actual opacity decrement still did not change its field. The first two
fixtures now target their exact intended controls. Numeric AXValue alone did
not fix the opacity event, and is not recorded as its cause.

An explicit DEBUG-only test argument now exposes a bounded native stepper event
trace in its accessibility label. Only the failing fixture enables it and attaches
the actual mouse location/bounds, native values, action dispatch and announcement
before asserting. This is targeted diagnosis; ordinary owner launches do not
expose the trace. Await that native receipt before further opacity changes.

### Native color reconciliation correction — November 22

The source-frozen Settings → Testing → Start UI run
`20261122-033811-f11bc3de` passed the exact
`SiteForgeUITests/SiteForgeLaunchTests/testDesignInspectorSolidFillOpacityKeyboardUndoRedoJourney`
(1/1, no skips, exit 0), source
`8b7e454339525a5f6e4c070eb3615632a2dd69fec4da990f2e57df3a90bb2c7d`.
The real native decrement dispatched correctly in prior failures. An unchanged
hex binding reconciliation reparsed the displayed eight-bit hex of a native
floating-point color and opened a hidden fill preview. Committing that preview
advanced the revision before opacity could prepare. The binding now ignores
unchanged displayed text. The strengthened journey undoes opacity, then the
actual color edit, then redoes both, detecting an intervening hidden color edit.
Temporary trace instrumentation was removed afterward; that cleanup and later
effect additions require their own receipts. This receipt does not certify the
expanded effects/footer/showcase work or an installation.

### Actual native/browser alpha reproduction

Native Start Regular run `20261122-071658-eedfaf1a`, source
`b956e4a1c9d1820070d224086b441d0c33045e08a0f3c1e355a1b5b1241e3380`,
executed four methods. Colors close/order-out ownership, numeric/color native
accessibility and native slider Escape/history passed. The new actual WebKit
versus production Core Graphics alpha-pixel comparison failed six assertions:
transparent red → opaque blue introduced a pink native transition, while the
browser correctly retained blue as alpha increased over white. Pixel samples at
20%, 50% and 80% confirmed the difference. Both actual PNGs were inspected.
Retained code attachments: native `11EEE7CB-7A67-4ABE-BC99-7983FEFD3662.png`,
WebKit `FFC0E5A9-667B-424C-8922-494B3ACDAC14.png` under this run's
`attachments/code/0`. This is an observed renderer discrepancy, not speculation
from a midpoint helper.

The candidate now uses premultiplied sRGB interpolation for headless sampling
and Add Stop. Native varying-alpha/color ramps use a Core Graphics axial
shading function with the same interpolation; opaque/uniform-alpha ramps keep
the existing CGGradient path. Canonical authored stops and identities remain
unchanged. New-stop regression expectations now follow premultiplied color.
The correction is compiling; passing comparison/alpha insertion/hard-stop and
geometry receipts are still required. The runtime's generated ramp already uses
explicit premultiplied interpolation. Static projection is also corrected to
include every already-supported fill kind, including stacks/grids/buttons;
its focused output regression is pending. No final acceptance/install claim.
