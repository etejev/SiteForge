# ADR-0066 — Lane V18: text bound to page variables, key-press triggers, page interactions overview, lane C performance and announcements

- Status: Proposed (implemented as an unverified Code Forge candidate by lane V18; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-039 (approved by the owner 2026-11-26 1:30 PM EST: "bounded runtime variables … compiled to a small
  generated runtime script"; event graph with click, hover, scroll, keyboard and load triggers); owner choice 2026-11-26
  8:09 PM EST to build plan items C6 and C7, lane C 007 performance fixtures and 006 announcements before the Codex hand-off.
- Builds on: ADR-0061 (event graph), ADR-0062 (variables and overlays), ADR-0065 (placement, static-layout containers, browser tests)
- Requirements: SF-1101-001 … SF-1101-008, SF-1106-001 … SF-1106-007; SF-1103-007, SF-1104-007, SF-1105-007

## Context

Lane C left two plan items unstarted: C6 (bind a text's content to a page variable, typed and hydration-safe) and C7 (a
key-press trigger on a focused object and a page overview of every interaction with jump-to-object). The lane C 007
requirements had no performance fixture and 006 had gaps: refused motion/interaction edits were not spoken, variable field
captions were not spoken, and the generated runtime set `aria-expanded` only on buttons and only after first use.

## Decision

### C6 — text value bindings (SF-1106-002/003/004)
- A node property, no new `CanonicalDocument` key: `state.v1.text` on a Text = canonical JSON `{"variable":"<UUID>"}`
  (`CanonicalTextBinding`; exact key, at most 1 KiB, re-encoding must match, Text only, never a form field;
  `ModelValidationError.invalidRuntimeState` otherwise). It lives in the `state.` namespace, so the schema-27 gate already
  covers it (schema 26 files with it are refused); still document schema 27, persisted history 4, WebsiteMetadata 3.
- Edit: `DecorativeEffectEdit.textBinding(CanonicalTextBinding?)` through the shared effect registry: one undoable
  transaction, property identity kept when re-pointed, `noChanges` for the same value, refused on other kinds
  (`CanonicalTextBinding.unsupportedReason`) and when the page has no such variable
  (`missingVariableReason`); a binding that stopped resolving can still be removed.
- Types and formatting: every variable type can be shown, with the variables' canonical text
  (`CanonicalVariableValue.text`): whole numbers without grouping (`-42`, `1000000`), text as is, `true`/`false`. The same
  text in the static HTML and in the runtime (`String(value)`), in every language (variable values are not translated).
- Hydration: the build writes the variable's starting value as the text (`CanonicalTextBinding.outputPage`, called on
  every page the planner writes) and marks the element `data-siteforge-text-variable="<lowercase id>"`
  `aria-live="polite" aria-atomic="true"`. With scripts off the page shows the starting value; the runtime replaces the text
  (`textContent`, never markup) when the variable changes, and the live region announces it.
- Precedence (the rule): a resolving binding wins over the authored text, over the text's translations in every language
  tree and over a collection field on item and list pages (`outputPage` runs after translation and item filling). The
  authored text and its translations stay in the document: the canvas shows them, and the website shows them whenever
  the page has no such variable. Then the attribute is left out and Check Website reports `state-text-binding-missing`
  (warning, SF-1106-004, node id only). Translations of a bound text stay in the translation report because they are the
  fallback.
- Identity and copies: the binding stores the variable's stable id; renaming a variable keeps the binding, nothing is ever
  matched by name. Variables are page-scoped and the id contains no NodeID/PageID, so no copy path remaps it: paste on the
  same page, page duplicate (CanonicalPageGraphClone copies the Root's variables with their ids), Create Component and
  component expansion (on the page that has the variable) keep it valid; a copy to another page or project keeps the
  reference, is reported and shows its own text until the author chooses a variable of that page.
- Inspector: Overlay and Visibility section of a Text — "Show a variable's value" (`inspector.textBinding.enabled`),
  "Shows" picker with "Missing variable" for a stale id (`inspector.textBinding.variable`) and a status line that says
  which value the website shows and why (`inspector.textBinding.status`, red when the variable is missing).

### C7 — key-press triggers and the page overview (SF-1101-001/002/003/006)
- New `CanonicalInteraction.Trigger` cases `key-enter`, `key-escape`, `key-arrow-up`, `key-arrow-down`,
  `key-arrow-left`, `key-arrow-right` (`keyboardKey` gives the DOM key). Same interaction JSON shape (exact keys
  unchanged); unknown names stay invalid.
- Focusability rule: key presses run only while their own object has keyboard focus (`event.target === element`, no
  Alt/Control/Command, not while composing text). Buttons and links already take focus. Any other supported object is
  made focusable by the website (`tabindex="0"`) and Check Website warns `interaction-key-focus-added` (SF-1101-006),
  because a button or link is announced better; the Inspector shows the same note under the trigger. Nothing is refused.
- Arrow keys call `preventDefault` so the page does not scroll; a menu's own arrow-key navigation steps aside when a key
  interaction already handled the key. Enter on a button also clicks it and Escape inside an open overlay also closes it
  (browser behaviour, kept). Key presses count as keyboard access for `interaction-pointer-only`.
- Page overview: `PageInteractionOverview.summaries` lists every trigger with its actions on the page in Layers order
  (depth first), described with the names authors see, with actions the website leaves out counted. The page background
  shows it as "Page Interactions" (`inspector.pageInteractions.<n>`); every row is a plain button (Tab, Space, VoiceOver)
  that selects its object (`WorkspaceShellState.revealInteractionObject`, announced without authored names). The
  Interactions section links to it ("Show All Interactions on This Page"). Lane C has no feature flag, so none is added.

### Lane C 007 — performance
- `TransformModelTests.testMotionAndInteractionChecksAndOutputStayWithinBoundsOnStandardAndLargeFixtures`: 100 and
  10,000 objects (motion, three interactions per text incl. key presses, a page-long Focus In loop, conditions, bindings,
  popovers): validation, one registry edit, interaction/motion/container output, findings, overview, `outputPage` and a
  full build within 10 s / 120 s safety bounds (the existing pattern).
- The focus-loop check searched from every object (quadratic on a long chain); it now finds loop members with an
  iterative Tarjan pass, linear in objects and edges, with the same findings.

### Lane C 006 — announcements
- App: a refused motion, interaction, overlay, visibility, variable or text-value edit is now spoken
  (`previewDesignStyle` posts the reason for `.effect` edits, as commits already were); variable field captions are spoken.
- Website runtime: a button or link that opens an overlay gets `aria-haspopup="dialog"` and `aria-expanded="false"` at load;
  one that shows or hides an object gets its starting `aria-expanded`; links now also get `aria-expanded` updates; the modal
  backdrop is `aria-hidden="true"`; focus return on close was already in place; bound text is a polite live region.

### Browser checks
`Tests/Tooling/interaction_runtime_browser.py` gains three cases (11 in total): `key-press-runs-only-on-the-focused-object`,
`bound-text-starts-with-value-and-follows-variable` (live region, starting value with JavaScript off, updates),
`openers-announce-popup-and-expanded-state`; the Swift fixture gains a "Key panel" frame and two bound texts.

## Consequences
- A bound text's static layout box is sized from the authored text on the canvas; a longer value can overflow it.
- Key-press interactions on non-controls add Tab stops; Check Website says so.
- Nothing here ran on a Mac: no Swift compiler, VoiceOver or browser ran these changes.

## Reversal
Stop writing the attribute and the starting value and hide the Inspector controls; keep reading `state.v1.text` and the
key trigger names so documents stay valid.
