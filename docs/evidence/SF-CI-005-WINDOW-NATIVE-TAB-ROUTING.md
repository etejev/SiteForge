# SF-CI-005 Window-Native Tab Routing Evidence

Date: 2026-07-26

Requirements: bounded regression evidence for `SF-0201-006`, `SF-0201-008`, `SF-0203-006`, `SF-0203-008`, `SF-0602-006`, `SF-1902-006`, and `SF-1902-008`.

## Hosted failure

GitHub Actions run `30213209340` used hosted Xcode 26.5. All 206 unit tests and 23 of 24 UI tests passed. The sole failure was the unchanged forward/reverse workspace traversal at the Not Found page-row to viewport-preset boundary.

The downloaded failure hierarchy established:

- expected accessibility identifier: `canvas.viewport.preset`;
- actual focused accessibility identifier: `navigator.tab.pages`;
- window: the main `workspace-AppWindow-1` workspace window at 1100 by 752 points;
- the native preset remained present as an unfocused `PopUpButton` with its current Desktop value.

The event therefore escaped the mixed SwiftUI/AppKit handoff and the native focus loop wrapped to Pages. The retained artifact did not report the AppKit first-responder class, so no responder class is inferred from it.

## Correction

One `WorkspaceWindowTabRouter` is owned by each `WorkspaceShellView`. It installs a local key event monitor only while bound to that shell's exact `NSWindow`. The router consults the existing `ShellFocusTraversal`, and consumes only unmodified Tab or Shift-Tab when the source or destination is `viewportPreset`.

Entering the native popup uses `NSWindow.makeFirstResponder`. Leaving it relinquishes the popup and adopts the adjacent SwiftUI focus target through the existing binding. Events pass through unchanged for another window, an inactive window, stale window generation, an attached sheet, active text editing, an active menu, a missing logical focus, or a non-boundary transition. The host remembers its bound window so a SwiftUI detach cannot strand the local event monitor; teardown and window migration remove it deterministically. Closures capture the router weakly.

Debug UI-test composition exposes a content-free diagnostic accessibility value containing only stable logical identifiers, responder class names, key/main/sheet booleans, and route outcome. Release composition ignores automation arguments and does not install the diagnostic probe.

## Automated acceptance

- `AppMetadataTests`: 12/12 passed, including three new routing-policy and lifecycle tests.
- `testKeyboardFocusTraversesWorkspaceForwardAndReverse`: 10/10 passed with application relaunch enabled for every repetition.
- `testViewportCommandsAreKeyboardAndAccessibilityOperable`: passed; pointer selection, Up/Down keyboard selection, identifier, label, value, and surrounding commands remained operational.
- Complete `SiteForgeUITests`: 24/24 passed.
- `./sf verify`: 209 unit and 24 UI tests passed with zero failures.

No assertion, traversal order, production minimum-window size, control layout, or timeout was weakened. No sleep, synthetic repeated Tab, coordinate click, or Debug-only focus behavior was introduced.

## Limitation

Local tests prove the production routing behavior and monitor lifecycle on the named local environment. A new hosted execution of the pushed commit is still required to confirm the original Xcode 26.5 environment. If it fails, the new diagnostic probe makes the logical focus, responder class, window state, and last route outcome available without project content or file paths.
