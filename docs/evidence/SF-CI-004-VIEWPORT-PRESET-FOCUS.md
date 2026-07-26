# SF-CI-004 Viewport-Preset Focus Evidence

## Scope and requirements

This bounded escaped-defect regression covers `SF-0201-006`, `SF-0201-008`,
`SF-0203-006`, `SF-0203-008`, `SF-0602-006`, `SF-1902-006`, and
`SF-1902-008`. It does not change the shell traversal order, production
window geometry, or any automation-only composition boundary.

## Hosted evidence

GitHub Actions run `30203186204` on Xcode 26.5 completed all 203 unit tests
and 23 of 24 UI tests. The only failure was
`testKeyboardFocusTraversesWorkspaceForwardAndReverse`: Pages, Layers, Home,
and Not Found acquired actual accessibility keyboard focus in order, but the
next `canvas.viewport.preset` element existed as a menu button without
becoming the AppKit first responder. The retained focus diagnostic identified
the Not Found row as the last confirmed focused control before the bounded
preset wait expired. The hierarchy and screenshot contained no complete local
paths or authored project content.

Both a SwiftUI `Picker` and a SwiftUI `Menu` had previously passed local focus
tests while reproducing this hosted first-responder failure. The escaped
defect is therefore the mixed SwiftUI/AppKit focus-adoption boundary, not the
declared `ShellFocusTraversal` order or the visibility of the preset control.

## Correction

The viewport preset is a native `NSPopUpButton` embedded with
`NSViewRepresentable`. `WorkspaceShellState.viewportPreset` remains the only
preset state. Pointer and keyboard selection update that state through one
bounded index-to-preset contract. The native control retains the existing
110-point width, native focus ring, identifier `canvas.viewport.preset`, label
`Viewport preset`, and current preset as its accessibility value.

First-responder adoption is identity-bound to one scene, one `NSWindow`, and
one request token. Adoption is performed synchronously only after checking all
three identities, so no queued callback can outlive cancellation or scene
replacement; stale, wrong-scene, and wrong-window requests are neutral. Once
an adopted request relinquishes focus it cannot reclaim focus without a new
request. Native focus changes synchronize the scene-owned `ShellFocus`, and
Tab/Shift-Tab from the popup route to the unchanged adjacent entries without
synthetic keystrokes or sleeps.

## Automated acceptance

- Unit coverage: focus adoption; stale, wrong-scene, and wrong-window
  neutrality; focus-loss non-reclamation; new-request adoption; deterministic
  preset indexing; and accessibility identifier, label, and value.
- Running-app coverage:
  `testKeyboardFocusTraversesWorkspaceForwardAndReverse` verifies the complete
  forward and reverse order, including Not Found → viewport preset and
  viewport preset → Not Found using actual `hasKeyboardFocus`.
- Running-app preset coverage:
  `testViewportCommandsAreKeyboardAndAccessibilityOperable` verifies native
  pointer selection, keyboard selection, and accessibility metadata.
- Focus-repeat result: the final implementation passed 10/10 consecutive
  complete forward/reverse traversal runs, each with a fresh application
  launch and actual `hasKeyboardFocus` assertions.
- Preset result: one focused running-app journey passed pointer selection from
  Desktop to Tablet, keyboard selection from Tablet to Mobile, and the stable
  identifier, label, current value, and actual-focus assertions.
- Complete UI target: 24/24 tests passed in one invocation.
- Authoritative `./sf verify`: 206 unit and 24 UI tests passed with zero
  failures; repository, security, traceability, architecture, and retained
  evidence checks also passed.

## Limitations

Local XCTest does not prove behavior on every hosted macOS/Xcode combination.
A fresh execution of the exact committed SHA on GitHub Actions remains the
final hosted confirmation. Actual VoiceOver speech remains release QA; this
correction verifies accessibility semantics and actual keyboard focus.
