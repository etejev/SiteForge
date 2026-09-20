# SF-CANVAS-POINTER-001 — Native pointer/compositor parity

## Contract and diagnosis

Bounded SF-0401-001/003/008, SF-0405-002/003/008 and SF-0407-001/003/008.
The owner's September 8 recording shows the pointer above its Text preview
at fitted 66% zoom; the original-resolution frame at 3.33 seconds was reviewed.

An independent native AppKit probe identified the first divergence: AppKit
already flips the viewport backing layer. Flipping each owned container again
reflects local Y. In a 400-point host, (100,80) became (100,320); an unflipped
container preserves (100,80). NSEvent and world/viewport conversion were correct.

## Correction

Content, authored-text and overlay containers are unflipped. Leaf tile/text
APIs retain their local drawing conversions. No per-tool offsets or canonical
coordinate changes are introduced. The empty card and convenience header row
yield while a creation tool is armed, avoiding obscured previews and resizing
at first commit. Shared clipping, selection, hit testing and AX remain resolved
from the same geometry; editor decoration remains noncanonical.

The preceding SF024 run passed 428/428 non-UI and 59/60 UI tests. The only
failure was a compact tab click asking XCTest to scroll a clipped 25-point
strip. The journey now uses the existing visible native overflow menu and
passes in 54.269 seconds, with authoring/target assertions unchanged.

## Focused results

`CanvasTextRenderingTests/testNativePointerPreviewAndOwnedLayersShareUnreflectedViewportCoordinates`
passes across 25/66/100/200/800% zoom, 1x/2x, two nonzero origins, four directions
and every insertion kind. It checks real NSEvent/NSView/layer conversion, not
two copies of one renderer formula. The affected tile/text/opacity suite and
the native pointer journey are in final focused validation.

`SiteForgeLaunchTests/testNativePointerPreviewAndFrameTextCommitFollowScreenCoordinates`
drives real menus/mouse, checks blue pixels on all four expected edges and
compares committed AX bounds against the independent pointer screen position.
It includes fitted, actual, panned/zoomed and artboard-edge states. Its first
pixel check exposed the empty-card obstruction, corrected in production.

The first complete pointer journey passed 1/1 (238.625 seconds). Screenshot
review nevertheless caught an upside-down native Frame label. The tile's
AppKit helper falsely declared its already-top-left CGContext unflipped. It
now describes that basis truthfully; this does not add another transform.
The label pixel regression now checks the exact authored frame and top inset,
rather than an overly broad reflected range. Revalidation passed: two affected
label/control pixel tests and the native pointer journey (238.042 seconds).
Across the focused iterations all ten affected CanvasTextRenderingTests have
known passing results; only changed/failed selectors were rerun. The compact
Inspector overflow journey also passed. No full or hosted acceptance is claimed.

The solid-fill pixel regression also removed an obsolete reflected expected
rect: the bitmap reader already converts scanlines to top-left once. Exact
alpha/channel tolerances and outside-paint exclusions are unchanged and pass.
The shadow geometry regression passes with the same direct viewport contract.

## Final visual review

All twelve original-resolution captures from
`focused-a7db3f30-d720-47e2-8c08-e0925dbaaadd.xcresult` were inspected:

| State | Preview PNG | Committed PNG |
| --- | --- | --- |
| Fitted 66% Frame | DDFCDDEC-2325-4271-8882-B94CC29D9A8B.png | AFFACC62-283A-4CC7-B01A-91DCEEAB72B0.png |
| Fitted 66% Text | 5FF63D0E-4B41-42F6-9A30-E8AE1FC6923A.png | 721523AA-1E70-4CE8-926A-D33A968EB769.png |
| Actual 100% Frame | 6A5BF6BE-9442-42C4-ADC9-882890BEDBE9.png | 93608FDC-2969-4746-B3D0-887A8DA7D35F.png |
| Actual 100% Text | 5FE8029F-F9E9-418B-8FA1-33225A1DA72D.png | 3ED24A2A-4458-4EF1-A07F-559D49F76E69.png |
| Panned 80% Frame | F8B29BC8-BEDF-4E01-A0B3-771C8246CD73.png | 57B6DD2A-9FC6-415F-8034-2460DAF786E7.png |
| Panned 80% Text | F323206A-BC38-4AA0-80B9-151A78E2EE57.png | D0710D4C-BF1D-4DAF-A82B-F3182E8854A3.png |

Frame labels and Text glyphs are upright, inside aligned selection bounds.
Dashed previews become exactly one committed object without a ghost preview;
empty guidance no longer obscures them. Fitted gutters/grid and labeled
viewport controls remain intact. Explicit 100%/pan views intentionally show
only part of the artboard; they do not change authored coordinates. Native
overflow remains available for existing clipped tab-strip choices. No new
Inspector clipping or debug objects were observed. The passing focused log
contains no publish-during-view-update or invalid-geometry warning.

## Authoritative combined gate

September 13: `./sf verify` passed 429 unit/integration and 61 UI tests,
490 total with zero failures. The UI target completed in 2782.502 seconds;
the pointer journey passed within that gate in 237.556 seconds. Repository,
security, traceability, architecture, migration and evidence checks passed.
Result: `full-20d3f1fe-cbca-4099-b029-d9a9c449e92c.xcresult`.
The full log contains no publish-during-view-update or invalid-geometry warning.
Hosted confirmation is pending; no unchanged full rerun is needed.

## Hosted narrow-display follow-up

Actions `34742950348` at `3f8e61f` passed all 429 non-UI and 60/61 UI tests.
The sole failure was the newly added pointer journey at actual size: a fixed
65-point local X lay 63 points left of the visible artboard. The preview was
at screen X 228; the committed AX rectangle correctly began at the artboard
edge X 291. The retained hosted screenshot
`E7A33650-8BE5-4C4F-A10F-E7BAC53BD820.png` confirms pasteboard sampling, not
canonical movement or compositor reflection. Artboard clipping must not be
weakened to make an off-page AX frame equal the full authored rectangle.

The test now plans all six positions inside the intersection of the actual
viewport and Desktop artboard, with sufficient room for the full object.
Right/down/left/up and an edge sample remain; exact mouse-screen/pixel/AX
assertions are unchanged. `testNativePointerSamplesStayInsideVisibleArtboardAtNarrowWidths`
independently covers 500/1044-point viewports, positive/negative artboard
origins, 28/66/80/100% scale and Frame/Text sizes. No production code changes
are required. The narrow-sampling regression passed 1/1 (0.038 seconds).
On September 20, the desktop was confirmed unlocked and the runner started,
but XCTest timed out enabling Automation Mode before the test body:
`Failed to initialize for UI testing ... Timed out while enabling automation
mode.` This is a recurrence of the separately tracked test-harness service
failure, not a placement assertion. Result:
`focused-e4a19d23-d14e-4925-9d10-ebffb3665cf7.xcresult`.
No SiteForge runner remains active. Do not retry unchanged locally; run the
exact selector from Xcode's Test navigator once macOS UI Automation is healthy.
The follow-up remains uncommitted pending native validation and a new SHA's
hosted gate. Do not repeat unchanged broad suites.
