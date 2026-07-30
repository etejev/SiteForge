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

## Hosted acceptance

Pending the next GitHub Actions Xcode 26.5 run. Local success does not close `SF-CI-006`; `SF-AUTHORING-009` must not begin until the complete hosted gate passes.
