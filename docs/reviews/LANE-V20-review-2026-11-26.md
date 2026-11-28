# LANE-V20 review — nudge shortcut and modified Return on the canvas (2026-11-26)

Owner tag `lane-V20`. Restore point before: RP-2026-11-26-V19. Owner decision: `OWNER_DECISIONS_LANE_V.md`, 9:55 PM EST,
item 3 (change View ▸ Move Selection Right 1 px off Control-Right Arrow). No Swift toolchain on this PC: every finding is by
reading against the real declarations. `check()` returned [] after every edit; `foreign_changes(30)` and
`icloud_duplicates()` stayed [] before the first write and at the end. Only lane V20 edits are in the changed files.

## Scope

- Inputs: `docs/reviews/LANE-V14b-review-2026-11-26.md` (shortcut findings and both out-of-area notes).
- Every nudge command and every shortcut-bearing command: `SiteForge/WorkspaceShellView.swift`
  (`SiteForgeCommands`, `supplementaryAndViewportCommands`, `SiteForgeSupplementaryCommands`, the canvas context menu,
  `NativeCanvasViewportView.keyDown`, its accessibility custom actions), `SiteForge/WorkspaceShellModel.swift`
  (`CanvasTool.shortcut`, `transformAvailability`, `performTransform`), `TransformPolicy.keyboardStep/keyboardLargeStep`,
  `TextEditKeyRoutingPolicy` (`InlineTextEditingModel.swift`).
- Tests: every `typeKey` with an arrow or Return in `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift`; unit tests that
  build `NativeCanvasViewportView` or key events (`CanvasTextRenderingTests`, `InsertionModelTests`).
- Docs: `docs/TESTING.md`, `docs/product-ui/VISUAL_CONTRACT.md`, `docs/IMPLEMENTATION_STATUS.md`, `docs/CHANGELOG.md`,
  `docs/evidence/*`, all ADRs, in-app help/tooltips/accessibility help. None names Control-Right Arrow or any nudge
  shortcut; no ADR recorded the nudge shortcuts, so the record is a new amendment to ADR-0014 (the canvas ADR whose
  SF-AUTHORING-006 checkpoint owns keyboard transforms).

## Current shortcut table (built from the code before the change)

Menu bar (SwiftUI `.keyboardShortcut`): New ⌘N · Open… ⌘O · Close Window ⌘W · Save ⌘S · Save As… ⇧⌘S · Undo ⌘Z ·
Redo ⇧⌘Z · Show History… ⌘Y · Select All ⌘A · Cut ⌘X · Copy ⌘C · Paste ⌘V · Paste in Place ⇧⌘V · Duplicate ⌘D ·
Insert tools (plain) V Select, 1 Section, 2 Stack, 3 Grid, F Frame, T Text, I Image, B Button, L Link, M Form,
C Component · Insert Frame/Text/Button/Link/Form at Center ⇧⌘F/T/B/L/M · Insert Section in Flow ⌥⌘1 · Stack ⌥⌘2 ·
Grid ⌥⌘3 · Insert Selected Image ⇧⌘I · Import and Insert Image… ⌥⌘I · New Page… ⇧⌘N · Isolate Selection ⌥⌘Return ·
Exit Isolation ⇧⌥⌘Return · Edit Selected Text Return · Commit Text Edit ⌘Return · Select Next/Previous Object ⌘] / ⌘[ ·
Quick Open… ⇧⌘O · Compare Breakpoints… ⌥⌘R · Zoom In ⌘+ · Zoom Out ⌘- · Actual Size ⌘0 · Fit Document ⌘1 ·
Pan Left/Right/Up/Down ⌥←/⌥→/⌥↑/⌥↓ · **Move Selection Right 1 px ⌃→** · Add Horizontal Guide ⌃⌘H ·
Add Vertical Guide ⌃⌘V · Remove Selected Guide ⌥⌘Delete · Enable/Suppress Snapping ⌥⌘S ·
Validate Selected Form Locally ⌥⌘V (+ two Inspector buttons, same action) · Preview Website in Safari ⇧⌘P ·
Canvas Device Preview ⌥⌘P · Toggle Focus Mode ⇧⌥⌘F · Presentation Mode ⇧⌥⌘P · Build Diagnostics… ⌥⌘B.
Sheets use only `.defaultAction` / `.cancelAction`.
Focused canvas (`NativeCanvasViewportView.keyDown`): Tab/Shift-Tab traversal, Escape, Return/Enter begin text editing,
⌘] / ⌘[ select next/previous, arrows nudge 1 px, Shift-arrows nudge 10 px, Option-arrows pan.
Window monitor (`route`): ⌘Return commit and Escape cancel while editing text, Tab routing.

Nudge commands found: View ▸ Move Selection Right 1 px (the only menu nudge command, ⌃→); context menu "Move Right 1 px"
(no shortcut); canvas accessibility actions "Move Right 1 px" / "Move Down 1 px" (no shortcut); canvas arrows/Shift-arrows.
There are no Move Selection Left/Up/Down menu commands and no menu 10 px variants.

## Choice

The whole Control-arrow family is taken by macOS Mission Control (⌃← / ⌃→ move a space, ⌃↑ Mission Control,
⌃↓ Application windows), so a Control pattern cannot be kept for any direction. The design-app convention already fits the
existing keyboard handling and stays as it is: plain arrows nudge 1 px and Shift-arrows 10 px when the canvas has focus.
For the menu variant, Option-arrows are View ▸ Pan and Shift-arrows are the canvas 10 px step (and text selection), so
neither the Option- nor the Shift-arrow variant is free. Command-arrows and Shift/Option-Shift-arrows are text navigation
and selection; Control-Option is the VoiceOver modifier. **Option-Command-arrows** have no macOS system default
(Mission Control, Spotlight ⌘Space/⌥⌘Space, Force Quit ⌥⌘Esc, screenshots ⇧⌘3/4/5, input sources ⌃Space/⌃⌥Space,
accessibility Zoom ⌥⌘8/=/-), no app-menu standard (Hide ⌘H, Hide Others ⌥⌘H, Quit ⌘Q, Settings ⌘,), no text-system
binding, and no SiteForge command uses them. View ▸ Move Selection Right 1 px is now ⌥⌘→; ⌥⌘← / ⌥⌘↑ / ⌥⌘↓ (and ⇧⌥⌘ for
10 px) are reserved in the ADR for any later menu nudge commands. Full table re-checked: no duplicate key+modifier pair.

## Fixes

| File | Symbol | Defect | Fix |
| --- | --- | --- | --- |
| `SiteForge/WorkspaceShellView.swift` | `SiteForgeCommands.supplementaryAndViewportCommands`, Button "Move Selection Right 1 px" | ⌃→ is the macOS Mission Control "Move right a space" default and never reached the app on default Macs (owner item 3). | `.keyboardShortcut(.rightArrow, modifiers: [.command, .option])`, with a why-comment. |
| `SiteForge/WorkspaceShellView.swift` | same Button, `.disabled(...)` | With a reachable shortcut, the key could move the object under an active inline text editor (the item was only gated on transform availability). | `.disabled(state?.textEditingSession.isActive == true \|\| state?.transformAvailability(...).isEnabled != true)` — same gate the Insert tool shortcuts use. |
| `SiteForge/WorkspaceShellView.swift` | `NativeCanvasViewportView.keyDown(with:)` | Return/Enter with ANY modifiers began text editing, so a disabled ⌥⌘Return (Isolate Selection), ⇧⌥⌘Return or ⌘Return outside editing fell through into the editor (V14b out-of-area note 2). | Begin only when `event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty` (Caps Lock, keypad, Fn ignored) — matches Selection ▸ Edit Selected Text (plain Return); modified Returns fall through to `super.keyDown`. |
| `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift` | `testGeometryTransformPointerKeyboardNumericUndoRedoAndAccessibilityJourney` | Pressed ⌃→; comment called it a Selection-menu shortcut (it is in View). | Presses `[.command, .option]` Right Arrow; comment names View ▸ Move Selection Right 1 px and why. Assertions unchanged. |
| `Tests/SiteForgeTests/CanvasTextRenderingTests.swift` | new `testNativeCanvasReturnBeginsTextEditingOnlyWithoutModifierKeys` | No regression test for modified Return. | Six modified Returns × keyCodes 36/76 begin nothing; plain Return, keypad Enter (`.numericPad`) and Return with Caps Lock begin three times. |
| `docs/architecture-decisions/ADR-0014-appkit-core-animation-authoring-canvas.md` | Amendment 2026-11-26 (lane V20) | No ADR recorded the nudge shortcuts. | Amendment with the nudge/pan/Return table, the reasoning, the reserved family and the tests. |

Accessibility identifiers, menu titles, the context-menu item and the canvas accessibility actions are unchanged.
No schema change (document 27, persisted history 4, WebsiteMetadata 3). No new Swift file.

## Requirement table (affected requirements)

| Requirement | Status | Evidence |
| --- | --- | --- |
| SF-0403-006 Accessible operation | Met (by reading; Mac run pending) | Menu nudge now has a reachable non-colliding shortcut ⌥⌘→, same `transformAvailability` validation as the context menu; canvas arrows/Shift-arrows; AX actions unchanged. |
| SF-0403-008 Diagnostics and tests | Met (by reading; Mac run pending) | UI journey presses ⌥⌘→ and keeps move + Undo/Redo assertions. |
| SF-0406-006 Accessible operation | Met (by reading; Mac run pending) | Canvas Return begins editing exactly like Edit Selected Text (plain Return); disabled modified commands no longer bypass validation into text editing. |
| SF-0406-008 Diagnostics and tests | Met (by reading; Mac run pending) | `CanvasTextRenderingTests/testNativeCanvasReturnBeginsTextEditingOnlyWithoutModifierKeys`. |

## New/changed test selectors

- New: `SiteForgeTests/CanvasTextRenderingTests/testNativeCanvasReturnBeginsTextEditingOnlyWithoutModifierKeys`
- Changed: `SiteForgeUITests/SiteForgeLaunchTests/testGeometryTransformPointerKeyboardNumericUndoRedoAndAccessibilityJourney`

## Remaining work (blocked only)

- Mac: compile, run the two tests above, and confirm in the menu bar that View ▸ Move Selection Right 1 px shows ⌥⌘→ and
  moves a selected frame by 1 px on a Mac with default Mission Control shortcuts (needs the Mac/Xcode runner).

## Out-of-area notes (no change made)

- View ▸ Pan Left/Right/Up/Down (⌥-arrows) have no `.disabled` gate. If AppKit matches these menu key equivalents before
  a focused text field or the inline editor sees the key, ⌥← / ⌥→ (move by word) would pan instead. Check on a Mac; if
  confirmed, gate them like the Insert tools (`textEditingSession.isActive`) or on `nativeTextResponderIsActive`.
- When ⌥⌘→ reaches the focused canvas with the menu item disabled (nothing movable selected), `keyDown` treats it as
  Option-arrow and pans — harmless, older behavior.

## Intended doc changes for the coordinator (lane V15)

- Plan, lane V table: `V20 — nudge shortcut (owner 9:55 PM item 3): View ▸ Move Selection Right 1 px ⌃→ → ⌥⌘→ (off during
  inline text editing); canvas Return begins text editing only without Shift/Control/Option/Command; ADR-0014 amendment;
  remaining: Mac compile/UI run.`
- Activity log (newest first): `2026-11-26 lane V20 — View ▸ Move Selection Right 1 px moved from ⌃→ (macOS Mission Control
  "Move right a space") to ⌥⌘→, disabled during inline text editing; canvas keyDown begins text editing only on unmodified
  Return/Enter (V14b note); UI journey updated, regression test added; ADR-0014 amended. Report
  docs/reviews/LANE-V20-review-2026-11-26.md.`
- OPEN_DECISIONS (record item 3 under the next free OD number): Status `Approved by the owner 2026-11-26 9:55 PM EST —
  View ▸ Move Selection Right 1 px uses Option-Command-Right Arrow (was Control-Right Arrow, the macOS Mission Control
  "Move right a space" default); plain/Shift arrows keep nudging 1/10 px on the focused canvas. Built by lane V20
  (ADR-0014 amendment 2026-11-26).`
- CHANGELOG (if a Nov 26 entry is written): `View ▸ Move Selection Right 1 px is now Option-Command-Right Arrow;
  Control-Right Arrow switched Spaces on most Macs. Return with a modifier no longer starts text editing on the canvas.`
- V14b's shortcut list item: add `Move Selection Right 1 px ⌥⌘→`.

## Suggested first checks for Codex

1. `supplementaryAndViewportCommands`: `.disabled(state?.textEditingSession.isActive == true || state?.transformAvailability(.move(delta: .init(dx: 1, dy: 0), constraint: .horizontal)).isEnabled != true)` type-checks (`InlineTextEditingSession.isActive` is a computed `Bool`; `state` is `@FocusedObject WorkspaceShellState?`).
2. `.keyboardShortcut(.rightArrow, modifiers: [.command, .option])` — the View menu shows ⌥⌘→; no other menu item uses it.
3. `NativeCanvasViewportView.keyDown`: `if event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty { … }`.
4. The new unit test: `NSEvent.keyEvent(… windowNumber: 0 …)!` is non-nil; modified Returns reach `super.keyDown` (a beep with no responder) and `beginRequests` ends at 3.
5. The UI journey on the macOS runner: `application.typeKey(.rightArrow, modifierFlags: [.command, .option])` after the Layers row and Layout tab clicks changes `inspector.transform.geometry`, then ⌘Z / ⇧⌘Z.
