# LANE-V14b review — menus/shortcuts and full re-read of WorkspaceShellModel/View (2026-11-26)

Owner tag `lane-V14b`. Restore point before: RP-2026-11-26-V14 (pre-lane-V baseline RP-2026-11-26-V00, pre-lane baseline
RP-2026-11-26-11). No Swift toolchain on this PC: every finding below is by reading against the real declarations.
`check()` returned [] after every edit; `foreign_changes(30)` and `icloud_duplicates()` stayed [] throughout.

## Scope

- Item 4: every menu command and keyboard shortcut in `SiteForgeCommands` / `SiteForgeSupplementaryCommands`
  (`SiteForge/WorkspaceShellView.swift`), the view-level `.keyboardShortcut` uses in all SiteForge sources, and every
  `typeKey` in `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift`.
- Item 5: `SiteForge/WorkspaceShellModel.swift` (13,7xx lines, +1,732 since RP-11) and `SiteForge/WorkspaceShellView.swift`
  (19,8xx lines, +4,409 since RP-11). Whole-file mechanical passes (duplicate members by type chain + full signature,
  duplicate type names module-wide, brace/paren balance, undeclared identifiers in lane-added lines with
  `review/symcheck.py`, call labels with `review/labelcheck.py`, Sendable/actor crossings, debug artifacts, builder
  child counts, sheet/popover bindings, accessibility identifier duplicates, enum case additions) plus targeted reading
  of every lane-added presentation, command and concurrency region.
- Lane V reports read (Out-of-area / Suggested first checks / Remaining work sections, filtered for menus, shortcuts,
  builders and these two files): V01–V13, V12b, V16–V18.

## Item 4 — keyboard shortcuts and menus

Findings
- Since RP-2026-11-26-10 (before batch 17) exactly one shortcut was added: Edit ▸ Show History… ⌘Y (LANE-V13). No other
  ⌘Y exists; Redo stays ⇧⌘Z; ⌘Y for history matches Safari's History, so it follows macOS convention. Kept.
- Menu commands added since batch 17 (Site & Page Settings…, Collections…, Project Fonts…, Video & Audio…, Recolor
  Selected SVG…, Languages…, Project Upgrade Details…, Snapshots…, Compare Versions…, Component Libraries…) carry no
  shortcuts, so they cannot collide. Every member they call exists with the used signature
  (`DocumentLifecycleController.migrationReport` / `isMigrationDetailsPresented`, `presentProjectComparison(baseline:target:)`
  defaults, `canRecolorSVG(_:)` default, `presentHistoryList()`, the `can…` properties).
- `body: some Commands` still has exactly 10 children (fixed-arity CommandsBuilder). The `.saveItem` group has 15 view
  children; the pre-lane baseline already had 17 ViewBuilder blocks with more than 10 children (Insert menu 25) and uses
  the two-parameter `onChange`, so the toolchain/deployment target supports variadic ViewBuilder — no change needed.
- Four collisions with existing or system shortcuts (all older than lane V, none pressed by any UI test, none in docs):
  1. Selection ▸ Exit Isolation ⌥⌘Esc is the system Force Quit shortcut; the app never receives it.
  2. View ▸ Add Horizontal Guide ⌥⌘H is the app menu's Hide Others.
  3. View ▸ Add Vertical Guide ⌥⌘V equals Form ▸ Validate Selected Form Locally ⌥⌘V (and the Inspector's
     "Validate Empty Local Draft" buttons), documented as ⌥⌘V in `docs/evidence/SF-AUTHORING-037-…`.
  4. Build ▸ Build Diagnostics… ⇧⌘B equals Insert ▸ Insert Button at Center ⇧⌘B (Insert precedes Build, so the
     diagnostics shortcut only worked while button insertion was unavailable).

Fixes (file `SiteForge/WorkspaceShellView.swift`, struct `SiteForgeCommands` / `SiteForgeSupplementaryCommands`)
- Exit Isolation → ⇧⌥⌘Return (pairs with Isolate Selection ⌥⌘Return; inside the inline text editor a ⌘-Return variant
  commits the text, which is safe). Comment says why.
- Add Horizontal Guide → ⌃⌘H, Add Vertical Guide → ⌃⌘V (free; avoids VoiceOver's ⌃⌥ prefix). Form validation keeps ⌥⌘V.
- Build Diagnostics… → ⌥⌘B (free). Insert Button keeps ⇧⌘B, consistent with ⇧⌘F/T/L/M insert shortcuts.
- Full map checked after the change: no duplicate key+modifier pair remains among menu items; view-level ⌥⌘V buttons run
  the same action as the Form menu item.

UI tests that press shortcuts (⌘Z, ⇧⌘Z, ⌘N, ⇧⌘N, ⇧⌘O, ⌥⌘P, ⌥⌘3, ⌥⌘I, ⌘D, ⌘0, ⌘[, ⌘], ⌃→, ⌥→, plain f/t, ⌘Return,
⌘A/X/C/V, ⇧⌘V) all still hit the same commands; none used a shortcut changed here.

## Item 5 — WorkspaceShellModel.swift / WorkspaceShellView.swift re-read

Findings with no defect
- No duplicate member (type chain + full parameter list) in either file or module-wide; no duplicate top-level type
  names; braces and parentheses balance; no `TODO`/`print`/`try!`/`as!`/force-unwrap/`static var` in lane-added lines.
- symcheck over lane-added lines: only SDK names and property-wrapper storage (`_issues`, `_model`, `_newName`,
  `_report`, `_selectedCollectionID` — each matches its `@State`/`@StateObject`). labelcheck: only SDK modifiers and
  generic helpers (`fieldBinding`, `itemBinding`, `localeBinding`, `binding`) whose labels match.
- Concurrency: `WorkspaceShellState` is `@MainActor`; lane `Task.detached` sites pass only Sendable values
  (`CollectionImportTable/Mapping/Preview`, `ProjectComparison*`, `ProjectPackage`, `Data`); font/media workers and
  `ProjectFontCanvasSession` are actors; `ProjectComparisonModel` is `@MainActor`.
- No enum in these files gained cases; no accessibility identifier gained a duplicate; every new `is…Presented` /
  request state has exactly one presentation point.

Defects fixed
1. `WorkspaceShellModel.swift`, `WorkspaceShellState.presentHistoryList()`: Edit ▸ Show History… (⌘Y) did nothing in
   Focus Mode — the popover hangs on the status-bar History button, which Focus Mode removes — and the flag stayed true,
   so the popover appeared later out of context. Fix: leave Focus Mode (`toggleFocusMode()`, announced) before
   presenting. Test `testShowHistoryCommandLeavesFocusModeSoTheListIsVisible`.
2. `WorkspaceShellView.swift`, `MigrationNoticeButton` / new `MigrationDetailsPresentation` (private ViewModifier):
   File ▸ Project Upgrade Details… did nothing in Focus Mode because its sheet hung on the status-bar notice. Fix: the
   sheet moved to the workspace shell (`.modifier(MigrationDetailsPresentation(state: state))`, observes the lifecycle
   like `WorkspaceDocumentTitle`); the notice button only sets the flag.
3. `WorkspaceShellModel.swift`, `presentCollectionsEditor()` and `presentLanguagesEditor()`: the only two project sheets
   that skipped the workspace edit boundary (`prepareForWorkspaceAction(.context)`) every other sheet uses, so an
   unfinished Inspector/text draft could commit after the sheet captured its opening revision (Apply then refused as
   stale) or stay open under the modal sheet. Fix: same guard after the availability check. Test
   `testProjectSheetsWaitForTheWorkspaceEditBoundary` (Collections, Languages and History stay closed while a commit
   request is rejected, open afterwards); `import Combine` added to the test file for `sink`.
4. `WorkspaceShellView.swift`, `WorkspaceShellView.body`: lanes grew the root modifier chain from 10 to 18
   presentation/task modifiers (LANE-V08 asked to check its type-check time). Fix: the nine project sheets
   (Collections, Fonts, Video & Audio, SVG recolor, Languages, Snapshots, Quick Open, Compare Versions, Component
   Libraries) moved unchanged into the private ViewModifier `WorkspaceProjectSheets`, applied with one `.modifier(…)`.
5. Stale comments naming a non-existent "Site ▸" menu (the commands live in the File menu): `WorkspaceShellModel.swift`
   (`isProjectMediaPresented` doc), `WorkspaceShellView.swift` (Assets Video & Audio / Recolor buttons),
   `Tests/SiteForgeTests/ProjectResourceTests.swift` (SF-0803-006 comment), `docs/architecture-decisions/ADR-0050-…`.

## Requirement table (touched requirements)

| Requirement | Status | Evidence |
|---|---|---|
| SF-0307-006 History accessible operation | Met | Edit ▸ Show History… ⌘Y + status-bar button, now also in Focus Mode; `DocumentLifecycleTests/testShowHistoryCommand…` (2 tests) |
| SF-0309-002 Upgrade details | Met | File ▸ Project Upgrade Details… and the notice share one shell-level sheet |
| SF-0309-006 Accessible operation | Met | Menu command works with the status bar hidden; notice keeps label/value/hint/identifier |
| SF-1001-005 / SF-1007-002 sheet commits | Met | Edit boundary before opening; `testProjectSheetsWaitForTheWorkspaceEditBoundary` |

## New/changed test selectors

- `SiteForgeTests/DocumentLifecycleTests/testShowHistoryCommandLeavesFocusModeSoTheListIsVisible` (new)
- `SiteForgeTests/DocumentLifecycleTests/testProjectSheetsWaitForTheWorkspaceEditBoundary` (new)
- `Tests/SiteForgeTests/ProjectResourceTests.swift`: comment only.

## Remaining work (blocked only)

- Compile and run on a Mac (no toolchain here): the two new tests, the two new ViewModifiers, and the four shortcut
  changes in the live menu bar.
- UI confirmation on a Mac that the history popover opens when the status bar reappears in the same update that leaves
  Focus Mode (needs the macOS UI runner; no new UI test added because an unrun UI test would put CI at risk).

## Out-of-area notes (no change made)

- View ▸ Move Selection Right 1 px uses ⌃→, which is macOS's default Mission Control "Move right a space" shortcut on
  most Macs; a UI test presses it (XCUITest injects the event, so it passes). Codex may want ⌃⌥→ or plain arrow nudging.
- Canvas `keyDown` treats Return with any modifiers as "begin text editing", so a disabled ⌥⌘Return / ⇧⌥⌘Return falls
  through to text editing when a text node is selected (older behavior, harmless).

## Intended doc changes for the coordinator (lane V15)

- Plan, lane V table: `V14b — menus/shortcuts + WorkspaceShell re-read: 5 fixes (Focus Mode Show History…, Focus Mode
  Project Upgrade Details…, Collections/Languages edit boundary, root sheet chain split, stale "Site ▸" comments) and 4
  shortcut collisions resolved (Exit Isolation ⇧⌥⌘Return, guides ⌃⌘H/⌃⌘V, Build Diagnostics ⌥⌘B); remaining: Mac
  compile/UI run.`
- Activity log (newest first): `2026-11-26 lane V14b — menus/shortcuts and WorkspaceShellModel/View cross-check;
  shortcut collisions fixed (⌥⌘Esc Force Quit, ⌥⌘H Hide Others, ⌥⌘V and ⇧⌘B duplicates), Show History… and Project
  Upgrade Details… work in Focus Mode, Collections…/Languages… use the workspace edit boundary, project sheets moved to
  WorkspaceProjectSheets. Report docs/reviews/LANE-V14b-review-2026-11-26.md.`
- If a user-facing shortcut list exists or is added (docs/TESTING.md has none), list: Exit Isolation ⇧⌥⌘Return, Add
  Horizontal Guide ⌃⌘H, Add Vertical Guide ⌃⌘V, Build Diagnostics… ⌥⌘B, Show History… ⌘Y.
- No new OD.

## Suggested first checks for Codex

1. `MigrationDetailsPresentation.init(state:)`: `_lifecycle = ObservedObject(wrappedValue: state.lifecycle)` with
   `let state` assigned first (same pattern as `MigrationNoticeButton`/`StatusBarView`).
2. `WorkspaceProjectSheets.body(content:)`: `$state.isQuickOpenPresented`, `onDismiss: state.completeSnapshotsDismissal`,
   `onDismiss: state.completeQuickOpenDismissal`, the `Binding(get:set:)` SVG sheet — moved verbatim, now inside a
   `ViewModifier` with `@ObservedObject var state`.
3. `.keyboardShortcut(.return, modifiers: [.command, .option, .shift])`, `.keyboardShortcut("h"/"v", modifiers:
   [.command, .control])`, `.keyboardShortcut("b", modifiers: [.command, .option])` — and the menu bar shows them.
4. `DocumentLifecycleTests`: `import Combine`; `state.editCommitRequests.sink { $0.reject() }`; `state.toggleFocusMode()`
   on a controller-backed `WorkspaceShellState`.
5. `presentCollectionsEditor()` / `presentLanguagesEditor()` guard order: availability first (keeps the busy/variant
   message), then `prepareForWorkspaceAction(.context)`; existing PersistedHistoryTests Languages test still opens.
