# LANE-V21 review — View > Pan must not take Option-arrows from text input (2026-11-26)

Owner tag `lane-V21`. Follow-up to lane V20 (out-of-area note 1 in `docs/reviews/LANE-V20-review-2026-11-26.md`).
No Swift toolchain on this PC: every finding is by reading against the real declarations. `foreign_changes(30)` and
`icloud_duplicates()` were [] before the first write and at the end; `check()` returned [] after every edit. No schema
change (document 27, persisted history 4, WebsiteMetadata 3). No new Swift file. Shortcuts unchanged.

## Scope

- `SiteForge/WorkspaceShellView.swift`: `SiteForgeCommands` (`nativeTextResponderIsActive`, `routePasteboardAction`,
  `supplementaryAndViewportCommands` View > Pan Left/Right/Up/Down and V20's Move Selection Right 1 px),
  `NativeCanvasViewportView.keyDown` (Option-arrow pan on the focused canvas), `updateTextEditor` / `InlineCanvasTextView`
  (inline editor focus), every `.focusedValue(\.siteforgeNativeTextEditor, …)` text input.
- `SiteForge/CanvasViewport.swift`: `CanvasViewportCommandName`, `CanvasViewportCommandRegistry` (read only).
- Tests: every `typeKey` with an arrow and every `componentMenu("View", "Pan …")` in
  `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift`; `CanvasViewportTests` / `CanvasTextRenderingTests` pan and key tests.
- Docs: ADR-0014 V20 amendment.

## Finding (confirmed by reading)

The four Pan items were declared as SwiftUI menu commands with `.keyboardShortcut(.leftArrow/.rightArrow/.upArrow/.downArrow,
modifiers: .option)` and no `.disabled` at all, so they were enabled in every focus state. AppKit offers a key-down to the
key window's and the main menu's key equivalents before the first responder's `keyDown`/`interpretKeyEvents`, so an enabled
Pan item takes Option-Left/Right (`moveWordLeft:`/`moveWordRight:`) and Option-Up/Down (`moveBackward:`+
`moveToBeginningOfParagraph:` / `moveForward:`+`moveToEndOfParagraph:`) from Inspector fields, the viewport width field,
sheets, `TextEditor`s and the inline canvas text editor (`InlineCanvasTextView`, an NSTextView). The other text-sensitive
commands already gate on focus: pasteboard commands on `nativeTextResponderIsActive`, Insert tools / Edit Selected Text /
V20's nudge on `textEditingSession.isActive`.

## Fixes

| File | Symbol | Defect | Fix |
| --- | --- | --- | --- |
| `SiteForge/WorkspaceShellView.swift` | new `@MainActor enum ViewportPanCommandPolicy.isMenuPanEnabled(focusedNativeTextEditor:firstResponder:inlineTextEditingIsActive:)` | No enable condition for Pan. | Pure, testable condition: off when a SwiftUI text input reports `siteforgeNativeTextEditor == true`, when the key window's first responder is an `NSTextView` (field editor of any NSTextField/SwiftUI TextField, TextEditor, inline editor), or when inline text editing is active. The same three signals as `nativeTextResponderIsActive`. |
| same | `ViewportPanCommandPolicy.textMovementSelectors(for:)` | — | The standard Option-arrow text bindings per Pan command (exhaustive switch over `CanvasViewportCommandName`; zoom/fit return []). |
| same | `SiteForgeCommands.viewportPanMenuIsEnabled`, `performViewportPan(_:)` | Menu validation can run on a snapshot taken before a field took focus. | `viewportPanMenuIsEnabled` feeds the live `focusedNativeTextEditor`, `NSApp.keyWindow?.firstResponder` and `commandState`/`state` `textEditingSession.isActive`. `performViewportPan` re-checks at action time; if text input owns focus it sends the text movement selectors up the responder chain (same routing idea as `routePasteboardAction`) instead of panning. |
| same | `supplementaryAndViewportCommands`, Buttons "Pan Left/Right/Up/Down" | Never disabled; stole Option-arrows from text input. | Actions call `performViewportPan(.panX)`; each item gets `.disabled(!viewportPanMenuIsEnabled)`. Titles, shortcuts and order unchanged. With the canvas focused all three signals are false, so Pan stays on (menu and `NativeCanvasViewportView.keyDown`). |
| `Tests/SiteForgeTests/CanvasTextRenderingTests.swift` | new `testViewPanMenuIsDisabledWhileTextInputOrInlineTextEditingHasFocus` | No test of the enable condition. | Canvas first responder / nil → enabled; field editor, plain NSTextView, focused SwiftUI input, inline editing → disabled; every pan selector is one `NSTextView` responds to; zoom/fit map to []; exact selectors for Pan Left / Pan Down. |
| `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift` | `testViewportCommandsAreKeyboardAndAccessibilityOperable` (extended) | Journey only proved Option-Right pans. | After the existing pan, clicks `canvas.viewport.width`, waits for keyboard focus, presses Option-Right in the field and asserts the canvas value does not change (2 s `waitForValueToChange` → false). Existing assertions unchanged. |
| `docs/architecture-decisions/ADR-0014-appkit-core-animation-authoring-canvas.md` | V20 amendment | Table said Pan is "unchanged" in every focus. | Pan row now notes the text-input gate; short "Lane V21 note" paragraph with the reason, the policy, the fallback and the tests. |

UI tests that rely on Pan: `testViewportCommandsAreKeyboardAndAccessibilityOperable` presses Option-Right with the viewport
preset/zoom buttons focused (no text input) and `testNativePointerPreviewAndFrameTextCommitFollowScreenCoordinates`
clicks View > Pan Down/Right after Escape + Undo ended any inline edit. No test pans while a text field is focused.

## Requirement table (affected requirements)

| Requirement | Status | Evidence |
| --- | --- | --- |
| SF-0401-006 Accessible operation | Met (by reading; Mac run pending) | Pan keyboard commands no longer break standard text navigation; canvas Option-arrows still pan. |
| SF-0401-008 Diagnostics and tests | Met (by reading; Mac run pending) | Unit test of the enable condition + UI journey step. |

## New/changed test selectors

- New: `SiteForgeTests/CanvasTextRenderingTests/testViewPanMenuIsDisabledWhileTextInputOrInlineTextEditingHasFocus`
- Changed: `SiteForgeUITests/SiteForgeLaunchTests/testViewportCommandsAreKeyboardAndAccessibilityOperable`

## Remaining work (blocked only)

- Mac: compile, run the two tests above, and confirm by hand that Option-Left/Right in an Inspector field, a sheet field and
  the inline canvas editor move by word while View > Pan shows disabled, and that Option-arrows pan with the canvas focused
  (needs the Mac/Xcode runner).

## Out-of-area notes (no change made)

- Insert tool shortcuts (plain V/1/2/3/F/T/I/B/L/M/C) and Selection > Edit Selected Text (plain Return) are gated only on
  `textEditingSession.isActive`, not on a focused text field. If AppKit gives plain-key menu equivalents precedence over a
  focused field on the Mac, typing those letters or Return in an Inspector field would select a tool / begin canvas text
  editing. Existing UI tests type into fields and press Return in `canvas.viewport.width`; if they pass on the Mac the
  concern is moot. Check on the Mac; if confirmed, gate them on `nativeTextResponderIsActive` like the pasteboard commands.
- V20 note 2 stays true: Option-Command-Right on the focused canvas with Move Selection Right disabled pans (harmless).

## Intended doc changes for the coordinator (lane V15)

- Plan, lane V table: `V21 — View > Pan (Option-arrows) disabled while a text field/text view/inline text editing has focus
  (ViewportPanCommandPolicy; stale-snapshot fallback sends the standard text movement); unit test + UI journey step;
  ADR-0014 V20 amendment note; remaining: Mac compile/UI run.`
- Activity log (newest first): `2026-11-26 lane V21 — View > Pan Left/Right/Up/Down no longer take Option-arrows from text
  input: items disabled while SwiftUI text input, an NSTextView first responder or inline text editing is active; action
  re-checks and forwards moveWord*/paragraph movement; CanvasTextRenderingTests and the viewport UI journey extended;
  ADR-0014 note. Report docs/reviews/LANE-V21-review-2026-11-26.md.`
- CHANGELOG (if a Nov 26 entry is written): `Option-arrow keys move by word or paragraph again in text fields and while
  editing canvas text; View ▸ Pan is unavailable while text has focus.`
- No OPEN_DECISIONS change (bug fix inside the V20/owner item 3 scope; shortcuts unchanged).

## Suggested first checks for Codex

1. `ViewportPanCommandPolicy.textMovementSelectors(for:)`: switch expression with `[Selector]` return type, `[]` branch and
   `Selector(("moveWordLeft:"))` literals type-checks; switch is exhaustive over `CanvasViewportCommandName`.
2. `@MainActor enum ViewportPanCommandPolicy` called from `SiteForgeCommands` (main-actor via `Commands`; the struct already
   calls the `@MainActor` `WorkspaceCommandTargetRegistry`) and from the `@MainActor` `CanvasTextRenderingTests`.
3. `firstResponder: NSApp.keyWindow?.firstResponder` (`NSResponder?`) and `firstResponder is NSTextView`.
4. `NSApp.sendAction(selector, to: nil, from: nil)` result unused (same as the existing undo:/redo: routing).
5. UI journey: after clicking `canvas.viewport.width`, `waitForKeyboardFocus(viewportWidth, in:)` succeeds and
   `XCTAssertFalse(waitForValueToChange(canvas, from: beforeTextFieldOptionArrow))` holds (no late render update changes
   the canvas value in that 2 s window); then View > Fit Document still changes the value.
6. Stale-disabled risk: the gate reads `NSApp.keyWindow?.firstResponder`, which SwiftUI does not observe (same as the
   existing Paste in Place / Duplicate gates). After inline editing ends, `textEditingSession` publishes and later state
   publishes re-evaluate the commands; confirm Pan re-enables promptly on the canvas after Escape/commit.
