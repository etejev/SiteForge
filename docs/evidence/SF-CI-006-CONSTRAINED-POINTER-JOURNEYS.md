# SF-CI-006 Constrained-Display Pointer Evidence

Date: 2026-07-30

Requirements: bounded regression evidence for `SF-0201-006`, `SF-0201-008`, `SF-0203-006`, `SF-0203-008`, `SF-0405-006`, `SF-0405-008`, `SF-0406-006`, and `SF-1902-008`.

## Hosted failures

GitHub Actions run `30415629157` used macOS 26.4 arm64 and Xcode 26.5. Repository, security, architecture, traceability, migration, and evidence checks passed; all 241 unit tests passed; and 25 of 27 UI tests passed.

The downloaded `.xcresult`, screenshots, and accessibility hierarchies established two independent geometry failures:

- inline-text Commit existed at y 761–777 in a 768-point test display because the 1100-by-752-point workspace window was top aligned; Cancel shared the same offscreen status-bar band;
- after a successful pointer Undo, Redo had value `Insert Node` and no disabled state, but its x range was 1034–1071 on the approximately 1024-point display. The requested right alignment had been constrained back to x 16.

The second failure was not stale history publication. The production command state was enabled; only the control's geometry was outside the visible display.

## Correction

Debug UI-test composition now requests horizontal and vertical safe-edge placement independently. One window-local AppKit configuration view reapplies the complete requested frame after attachment, key-window adoption, screen changes, moves, resizes, and application activation. It observes only its bound window, coalesces updates, avoids reapplying an equal frame, captures itself weakly, and removes every observer on detach. Release composition ignores both placement arguments. The production 1100-by-700-point content minimum is unchanged.

Actions follow-up `30572053725` at `dfe78ec` passed all 242 unit tests and 27 of 28 UI tests. Both original hosted failures passed: the generic inline-text journey completed through Command-Return, and pointer Undo/Redo succeeded at the right edge. The new bottom-pointer journey alone failed because macOS 26.4 kept the titled 1100-by-752-point frame at the title-bar-safe y 31; Commit was still enabled at y 761 but not hittable. This proves the vertical failure was AppKit frame constraint, not text-editor or command state.

The bounded follow-up keeps top/left/right journeys at the full production-minimum frame. Only a bottom-aligned Debug/UI-test frame is fitted when the display's usable height is shorter than that titled frame. The coordinator lowers only that test window's minimum frame height, restores the original minimum when detached, and retains the full requested width. Release composition cannot read these arguments, and `WorkspaceMetrics.minimumWindowSize` remains 1100 by 700.

Actions `30575084659` at `21e1b93` passed all 242 unit tests and 24 of 28 UI tests. That run proved the first constrained-height follow-up was broader than intended: it lowered the AppKit minimum for every UI-test placement, allowing normal top-aligned windows to shrink to 677 points and destabilizing the large-fixture and Layers/material journeys. For the explicit bottom journey, AppKit compressed the frame while SwiftUI still enforced its 700-point content minimum, clipping the canvas interaction. The final policy restores the production minimum for top/left/right test composition and applies the reduced AppKit and SwiftUI minimum together only to the explicit bottom-aligned Debug/UI-test composition.

Actions `30578634561` at `a412a69` passed all 242 unit tests and 24 of 28 UI tests. The four failures were ordinary top-aligned journeys: the large fixture measured a 677-point frame instead of the 700-point content minimum, one page-row query lost the navigator subtree, and two Layers queries found no published rows after switching tabs. The coordinator had cached the already screen-constrained frame produced during initial attachment. The final follow-up derives the intended frame once from the requested 1100-by-700 content size plus the exact bound window's current chrome inset; bottom-only fitting is applied only after that derivation. This avoids repeated resizing and does not rely on a machine-specific title-bar constant.

Actions `30581883646` at `b3999f6` passed all 242 unit tests and 25 of 28 UI tests. The intended 1100-by-752 titled frame was derived correctly, but ordinary top-aligned Debug/UI-test composition still retained the production content constraint on a 737-point visible screen. AppKit independently reduced the resulting frame to 677 points. The large-fixture test recorded that exact height, and the selection and material journeys lost the Layers accessibility subtree after switching tabs. The follow-up fits both top- and bottom-aligned explicit Debug/UI-test frames to the usable display height before AppKit can apply its own origin-dependent constraint. The full width and chosen safe edges remain deterministic; Release and non-test composition cannot relax the production minimum.

The general inline-text journey now commits through the production Command-Return path, because status-bar pointer geometry is not its subject. A dedicated bottom-aligned journey clicks the real Commit and Cancel controls, proves both are inside the screen-edge envelope, and reopens the editor to prove Cancel retained the last committed text. Existing dedicated right-aligned journeys continue to click Preview, Undo, and Redo.

Pointer-failure attachments contain stable control identifiers, enabled/hittable/focused state, sanitized control/window/display geometry, Undo/Redo availability and operation name, the non-content text-editing phase, and the responder/window diagnostic value. Missing accessibility elements remain diagnostic-neutral. No text content, clipboard data, absolute path, or secret is recorded.

## Local acceptance

Environment: Mac16,13, arm64, macOS 27.0 build 26A5388g, Xcode 27.0 build 27A5194q.

- Fourteen focused placement/composition tests passed, including left-top, right-top, left-bottom, right-bottom, and Release isolation.
- Each original hosted failure passed three consecutive fresh-process runs after the final diagnostic change.
- The dedicated bottom-aligned real Commit/Cancel pointer journey passed.
- Fifty-six command/history/insertion/text unit tests and six history/constrained-display UI journeys passed together (62/62).
- The complete `SiteForgeUITests` target passed 28/28.
- Repository security, traceability, architecture, migration, evidence, and fixture-hygiene checks passed.
- Authoritative `./sf verify` passed 242 unit tests and 28 UI tests with zero failures.
- After inspecting hosted `30572053725`, the revised constrained-height policy passed 14/14 focused tests, the real bottom Commit/Cancel journey passed 3/3 fresh-process runs, the complete UI target passed 28/28, and authoritative `./sf verify` passed 242 unit plus 28 UI tests.
- After inspecting hosted `30575084659`, the final bottom-only policy passed the real Commit/Cancel journey 3/3 fresh-process runs, a five-journey matrix covering both original failures plus minimum and Layers/material regressions passed 5/5, the complete UI target passed 28/28, and authoritative `./sf verify` passed 242 unit plus 28 UI tests. The dedicated journey uses the real Text/Select toolbar controls, canvas pointer insertion, Selection menu activation, and real status Commit/Cancel clicks so its setup does not depend on unrelated first-responder timing.
- After inspecting hosted `30578634561`, 11/11 focused placement/material tests passed; the four hosted failures plus the bottom pointer journey passed 15/15 across three fresh-process repetitions; the complete UI target passed 28/28; and authoritative `./sf verify` passed 242 unit plus 28 UI tests with every repository gate green.
- After inspecting hosted `30581883646`, the final placement contract passed 11/11; the three hosted failures, earlier page-row regression, and bottom pointer journey passed 15/15 across three fresh-process repetitions; the complete UI target passed 28/28; and authoritative `./sf verify` passed 242 unit plus 28 UI tests with every repository gate green.

## Hosted acceptance

Pending the next GitHub Actions Xcode 26.5 run after the locally verified all-placement constrained-height follow-up. Local success does not close `SF-CI-006`; `SF-AUTHORING-009` must not begin until the complete hosted gate passes.
