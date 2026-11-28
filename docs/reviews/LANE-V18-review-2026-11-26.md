# Lane V18 review — lane C follow-up (C6, C7, 007 performance, 006 announcements), 2026-11-26

Reviewer: lane V18 (`lane-V18`), on-device work on SEA124-DUJL56QN (no Swift toolchain, no git, no browser).
Owner decision: 2026-11-26 8:09 PM EST — build C6, C7, lane C 007 performance fixtures and 006 screen-reader
announcements now, before the Codex hand-off (`_quick-scratch/review/OWNER_DECISIONS_LANE_V.md`). Scope: OD-039 only.
Everything below is unverified: every changed region was re-read against the declarations it calls; `check()` returned
[] after every edit; `foreign_changes(30)` and `icloud_duplicates()` stayed [] throughout.

## Scope

- Plan items: C6 (text bound to a page variable, SF-1106), C7 (key-press trigger on a focused object and a page overview of
  all interactions with jump-to-object, SF-1101), lane C 007 performance (SF-1101/1103/1104/1105/1106-007), lane C 006
  announcements (SF-1101-006, SF-1105-006, SF-1106-006). C8 (OD-070) and C9 (OD-071) stay blocked.
- Read first: LANE-V09 and LANE-RC reviews, ADR-0060 … ADR-0065, OD-039, the lane C plan rows, SF-1101 and SF-1106 (all eight
  requirements), V09's browser harness pair, LANE-V08/V12 for the performance-test pattern.
- Files changed (all through `forge_io.edit`, owner `lane-V18`):
  - `SiteForge/DecorativeEffects.swift` — `DecorativeEffectEdit.textBinding`, registry cases, key-press triggers,
    `CanonicalTextBinding`, `CanonicalPageState.validate`, `EventGraphOutput.page/findings`, `loopMembers`,
    `PageInteractionSummary`/`PageInteractionOverview`, `EventGraphRuntime.javascript`.
  - `SiteForge/DecorativeEffectsInspector.swift` — text value controls, key-press note, overview link,
    `PageInteractionsOverview`/`PageInteractionRow`, spoken `VariableValueField` captions.
  - `SiteForge/WorkspaceShellModel.swift` — `revealInteractionObject`, `text-binding` operation name, spoken refusals.
  - `SiteForge/CanvasRendererCore.swift` — one line in `MultiPageStaticBuildPlanner` (`CanonicalTextBinding.outputPage`).
  - `Tests/SiteForgeTests/TransformModelTests.swift`, `Tests/SiteForgeTests/ClipboardTransferTests.swift` — new tests; the
    browser fixture and case list.
  - `Tests/Tooling/interaction_runtime_browser.py`, `Tests/Tooling/test_interaction_runtime_browser.py` — three cases, helpers.
  - New: `docs/architecture-decisions/ADR-0066-text-bindings-key-press-triggers-overview.md`, this report.
- No new Swift file, no new `CanonicalDocument` key, no new enum case in `NodeKind`, `CommandName`, `DocumentCommand` or
  `ModelValidationError` (the binding reuses `.invalidRuntimeState`). Document schema 27, persisted history 4,
  WebsiteMetadata 3 unchanged.

## Features finished (ADR-0066)

### C6 — text value bindings
- Model: `state.v1.text` on a Text = canonical JSON `{"variable":"<UUID>"}` (`CanonicalTextBinding`, exact key, ≤ 1 KiB,
  canonical re-encoding, Text only, never a form field). In the `state.` namespace, so the schema-27 gate, snapshots and
  comparisons already cover it.
- Edit: `DecorativeEffectEdit.textBinding(_:)` through `DecorativeEffectCommandRegistry.prepare` — one transaction,
  property identity kept, `noChanges`, refused on other kinds (`CanonicalTextBinding.unsupportedReason`) or when the page has
  no such variable (`missingVariableReason`); a stale binding can always be removed.
- Formatting (typed, consistent with the variable types): `CanonicalVariableValue.text` — whole numbers without grouping,
  text as is, `true`/`false`; the runtime writes the same text (`String(value)`).
- Hydration: `CanonicalTextBinding.outputPage` writes the starting value into every page the planner writes (after
  translations and collection items); `EventGraphOutput.page` adds `data-siteforge-text-variable="<id>" aria-live="polite"
  aria-atomic="true"`; the runtime replaces `textContent` on change. JavaScript off: the starting value is shown.
- Rule for localized trees and item pages: a resolving binding wins over the authored text, its translations (every
  language) and a collection field. When the page has no such variable the text's own (or translated / item) content is
  written, the attribute is left out, and Check Website reports `state-text-binding-missing` (SF-1106-004).
- Copies: the stored id contains no NodeID/PageID; variables are page-scoped and copied with their ids by page duplicate.
  Paste on the same page, page duplicate, Create Component and component expansion keep it valid; paste to another page or
  project keeps the reference (never matched by name), reported, own text shown (tested for paste, page duplicate, Create
  Component + expansion; definition graph copy and slot contents copy properties verbatim like visibility conditions).
- Inspector (Overlay and Visibility section of a Text): `inspector.textBinding.enabled`, `.variable` (with "Missing
  variable"), `.status` (which value wins and why; red when missing). Renaming a variable keeps the binding.

### C7 — key-press triggers and page overview
- Triggers `key-enter`, `key-escape`, `key-arrow-up/down/left/right` (`CanonicalInteraction.Trigger.keyboardKey`).
- Focusability rule: runs only while the object itself has focus; buttons and links already do; any other object gets
  `tabindex="0"` and the warning `interaction-key-focus-added` (SF-1101-006) plus an Inspector note
  (`inspector.interactions.<n>.keyFocus`). Arrow keys do not scroll; key presses count as keyboard access for
  `interaction-pointer-only`.
- Page overview: `PageInteractionOverview.summaries` (Layers order, author names, unavailable actions counted) shown on the
  page background as "Page Interactions" (`inspector.pageInteractions.<n>`, `.empty`); each row is a keyboard-reachable
  button with an accessibility label and hint that selects its object through `WorkspaceShellState.revealInteractionObject`
  (spoken, no authored names). "Show All Interactions on This Page" (`inspector.interactions.pageOverview`) opens it.
  Lane C has no feature flag; none added.

### Lane C 007 — performance fixtures
- `testMotionAndInteractionChecksAndOutputStayWithinBoundsOnStandardAndLargeFixtures` (100 / 10,000 objects; 10 s / 120 s
  safety bounds; pattern of `testResponsiveAuditStaysWithinBoundsOnStandardAndLargeFixtures` and LANE-V08/V12).

### Lane C 006 — announcements
- App: refused effect edits are spoken; variable field captions are spoken. Website: `aria-haspopup="dialog"` and starting
  `aria-expanded` on openers, `aria-expanded` on links too, backdrop `aria-hidden="true"`, bound text live region; focus
  return on close was already in place (V09 browser case 4).

### Browser harness (V09's files)
- Three new cases (11 total): `key-press-runs-only-on-the-focused-object`, `bound-text-starts-with-value-and-follows-variable`,
  `openers-announce-popup-and-expanded-state`; `Enter` key code, `element_text`, `Page.outer_html`, `__sf.keyPanel/bound`.
  Both Python files compile (checked here); the pure helpers were exercised on a stripped copy; the browser was not run.

## Fixes

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/WorkspaceShellModel.swift` | `previewDesignStyle` (catch) | A refused motion, interaction, overlay, visibility or variable edit set `lastDesignInspectorAnnouncement` but was never spoken (commits were). | Posts the reason for `.effect` edits. | SF-1101-006, SF-1106-006 announcements. |
| 2 | `SiteForge/DecorativeEffects.swift` | `EventGraphOutput.findings` / former `reaches` | Focus-loop detection searched from every object: quadratic on a long Focus In chain (10,000 objects). | `loopMembers`: iterative Tarjan, linear, same findings (checked against the old search on 3,000 random graphs here). | SF-1101-007. |
| 3 | `SiteForge/DecorativeEffects.swift` | `EventGraphRuntime.javascript` (`expand`, `open`, new `describe`) | Openers had no `aria-haspopup` and no `aria-expanded` before first use; links never got `aria-expanded`; the modal backdrop was exposed to screen readers. | `describe` at load, links included, backdrop `aria-hidden`. | SF-1105-006, SF-1101-006. |
| 4 | `SiteForge/DecorativeEffectsInspector.swift` | `VariableValueField.submit` | Validation captions were shown but not spoken. | `reject(_:)` shows and posts the caption (`AccessibilityAnnouncementPoster.native`). | SF-1106-006. |

## Requirement table (SF-1101, SF-1106; lane C 007 rows)

| Requirement | Status | Evidence |
|---|---|---|
| SF-1101-001 | Met | Typed triggers incl. key presses, canonical JSON, schema-27 gate; `testKeyPressTriggersFocusabilityOutputAndPageInteractionsOverview`, `testEventGraphTypedValidationHistoryClickPolicyAndSchemaGate` |
| SF-1101-002 | Met (UI journey test needs a Mac) | Inspector create/modify/remove with key triggers; page overview with jump-to-object; one transaction per edit |
| SF-1101-003 | Met | Deterministic order; overview lists trigger → actions in Layers order with unavailable actions; focus-loop, unreachable and key-focus findings |
| SF-1101-004 | Met | Missing targets kept and reported; overview counts them |
| SF-1101-005 | Met | Undo/redo, persistence, copy paths (V09) incl. key triggers |
| SF-1101-006 | Met (VoiceOver pass needs a Mac) | Key presses only on focused objects, focusable rule with warning, spoken refusals, opener `aria-haspopup`/`aria-expanded`, backdrop `aria-hidden`, browser cases 9 and 11 |
| SF-1101-007 | Met | 100/10,000 fixture; linear focus-loop check |
| SF-1101-008 | Met (not yet run) | Unit tests; browser harness 11 cases |
| SF-1106-001 | Met | Typed values; `state.v1.text` exact canonical JSON; schema gate; `testTextValueBindingTypedValidationHistoryPersistenceAndInspectorStatus` |
| SF-1106-002 | Met | Visibility and value bindings; Inspector controls with identifiers |
| SF-1106-003 | Met | Precedence rule (variable > translation/item field > own text; fallback when missing) with the Inspector status line; `testTextValueBindingOutputIsHydrationSafeAcrossLanguagesItemPagesAndMissingVariables` |
| SF-1106-004 | Met | Missing/renamed/deleted variables: reference kept, `state-text-binding-missing`, Inspector "Missing variable", fallback text; paste test |
| SF-1106-005 | Met | Undo/redo, property identity, persistence, page duplicate, Create Component, paste tests |
| SF-1106-006 | Met (VoiceOver pass needs a Mac) | Polite live region for bound text; spoken captions and refusals; browser case 10 |
| SF-1106-007 | Met | 16 variables / 1 KiB binding bounds; 100/10,000 fixture |
| SF-1106-008 | Partial | Unit, integration, performance and browser tests; session/URL scopes blocked (OD-070 open) |
| SF-1103-007 | Met | Motion CSS in the 100/10,000 fixture |
| SF-1104-007 | Met | Reveal CSS and container groups in the fixture |
| SF-1105-007 | Met | Overlays in the fixture (bounded stack unchanged) |

Totals for these rows: Met 18, Partial 1, Missing 0.

## Remaining work (blocked only)

1. C8 session and URL-parameter variables — blocked: OD-070 is Open.
2. C9 reusable transitions, scroll progress, parallax — blocked: OD-071 is Open.
3. Running the Swift tests, the two Python harnesses in Chrome, XCUITest journeys for the new Inspector controls and the
   overview, and a VoiceOver pass — blocked: needs a Mac (no Swift toolchain, Chrome or VoiceOver on this PC).

No owner decision beyond OD-039 was needed; no new OD is proposed.

## Intended plan / OD status-line changes (for the coordinator, lane V15)

- Plan, lane C table: C6 → `done (V18, ADR-0066, unverified)`; C7 → `done (V18, ADR-0066, unverified)`; C8, C9 stay blocked.
  Lane C notes: "007 performance fixtures and 006 announcements: done (V18, ADR-0066, unverified)."
- OD-039 Implementation status, append: "Lane V18 (2026-11-26, ADR-0066): text bound to a page variable (`state.v1.text`,
  starting value in the static HTML, wins over translations and collection fields, missing variables reported); key-press
  triggers (Enter, Escape, arrow keys) on a focused object, other objects made focusable with a warning; page interactions
  overview with jump-to-object; 100/10,000-object performance fixture and linear focus-loop check; spoken refusals and
  captions, opener `aria-haspopup`/`aria-expanded`, live regions. Still unverified."
- Activity log entry title suggestion: `## Lane V18 — 2026-11-26 (lane C C6/C7/007/006, OD-039, ADR-0066, unverified, complete)`.

## New/changed test selectors

```
SiteForgeTests/TransformModelTests/testTextValueBindingTypedValidationHistoryPersistenceAndInspectorStatus            (new)
SiteForgeTests/TransformModelTests/testTextValueBindingOutputIsHydrationSafeAcrossLanguagesItemPagesAndMissingVariables (new)
SiteForgeTests/TransformModelTests/testTextValueBindingStaysValidThroughPageDuplicateAndCreateComponent                 (new)
SiteForgeTests/TransformModelTests/testKeyPressTriggersFocusabilityOutputAndPageInteractionsOverview                   (new)
SiteForgeTests/TransformModelTests/testMotionAndInteractionChecksAndOutputStayWithinBoundsOnStandardAndLargeFixtures   (new)
SiteForgeTests/ClipboardTransferTests/testPastedTextValueBindingKeepsItsVariableOnItsPageAndFallsBackElsewhere         (new)
SiteForgeTests/TransformModelTests/testInteractionAndMotionRuntimesActualBrowserFocusTrapEscapePlacementAndReveal     (changed: fixture, 11 cases)
Tests/Tooling/interaction_runtime_browser.py, Tests/Tooling/test_interaction_runtime_browser.py                        (changed)
```

Commands for Codex (Mac):

```
./sf test focused SiteForgeTests/TransformModelTests/testTextValueBindingTypedValidationHistoryPersistenceAndInspectorStatus \
  SiteForgeTests/TransformModelTests/testTextValueBindingOutputIsHydrationSafeAcrossLanguagesItemPagesAndMissingVariables \
  SiteForgeTests/TransformModelTests/testTextValueBindingStaysValidThroughPageDuplicateAndCreateComponent \
  SiteForgeTests/TransformModelTests/testKeyPressTriggersFocusabilityOutputAndPageInteractionsOverview \
  SiteForgeTests/TransformModelTests/testMotionAndInteractionChecksAndOutputStayWithinBoundsOnStandardAndLargeFixtures \
  SiteForgeTests/ClipboardTransferTests/testPastedTextValueBindingKeepsItsVariableOnItsPageAndFallsBackElsewhere \
  SiteForgeTests/TransformModelTests/testInteractionAndMotionRuntimesActualBrowserFocusTrapEscapePlacementAndReveal \
  SiteForgeTests/TransformModelTests/testEventGraphOutputCompilesFixedActionsStartHiddenAndDiagnostics \
  SiteForgeTests/TransformModelTests/testEventGraphTypedValidationHistoryClickPolicyAndSchemaGate \
  SiteForgeTests/TransformModelTests/testRuntimeVariablesOverlaysOutputHydrationRuntimeAndDiagnostics \
  SiteForgeTests/TransformModelTests/testRuntimeVariablesOverlaysAndVisibilityTypedValidationHistoryAndSchemaGate \
  SiteForgeTests/TransformModelTests/testOverlayPlacementMenuKeysAndStaticLayoutContainerContents \
  SiteForgeTests/TransformModelTests/testInteractionOutputHiddenRuleFirstRenderOverlayConditionsAndStaticLayoutContainers \
  SiteForgeTests/ClipboardTransferTests/testComponentTransferReusesDefinitionWithEquivalentInteractions
/usr/bin/python3 Tests/Tooling/test_interaction_runtime_browser.py
/usr/bin/python3 Tests/Tooling/interaction_runtime_browser.py --root <dir with interactions/> --report report.json --captures captures/
```

(The last line is what the XCTest wrapper runs; run the wrapper rather than the harness by hand.)

## Suggested first checks for Codex

- `EventGraphOutput.loopMembers`: nested `func enter` capturing `index`, `low`, `counter`, `stack`, `onStack`, `work`;
  `while let (node, next) = work.last` on `[(node: NodeID, next: Int)]`; `work[work.count - 1].next = next + 1`.
- `CanonicalInteraction.Trigger.keyboardKey` switch expression with a `nil` branch; `let keyboard = Set(…filter…).union([.focusIn, .focusOut, .click])`.
- `CanonicalTextBinding` (Codable struct with `static let key`), `resolve` guard chain, `outputPage` (`try? resolve(…)` flattening).
- `DecorativeEffectCommandRegistry.prepare`: `case .textBinding(let binding)` throwing before `namespace/values/kinds` are assigned.
- `RuntimeStateInspector.textBindingControls` (`@ViewBuilder`, `let` declarations, `foregroundStyle(missing ? SiteForgeVisualSystem.danger : .secondary)`).
- `PageInteractionsOverview` / `PageInteractionRow` (`Button(action:)` with a label closure, `.buttonStyle(.plain)`), and
  `AccessibilityAnnouncementPoster.native.post` called from `VariableValueField` (Swift 6 isolation of the static).
- `WorkspaceShellState.previewDesignStyle`: `if case .effect = edit { … }`; `revealInteractionObject` (`selectionState.orderedIDs`).
- Planner: `let page = CanonicalTextBinding.outputPage(entry.page)` (language loop of `MultiPageStaticBuildPlanner`).
- Test expectations most likely to need adjusting: text element emission `…>Ready &lt;now&gt;` up to the next `<`; item page
  path `posts/first.html`; exact `output.attributes[fixture.frame] == " tabindex=\"0\""`; Create Component not refusing a
  container whose text carries `state.v1.text`; `ComponentGraphResolver.resolvedPage` keeping the binding on the expanded
  text; overview order `[text, frame×3, button]`; the 10,000-object build within 120 s.
- Browser: DevTools `rawKeyDown` for Enter dispatches `keydown` with `key: "Enter"` (no click on the frame); `DOM.getOuterHTML`
  with scripts disabled.

## Out-of-area notes (not changed)

- `docs/REQUIREMENT_EVIDENCE.json` lists only the Flow tooling files; the interaction harness (V09, now 11 cases) may need
  an entry (owned by the evidence index).
- `docs/TESTING.md` does not list the interaction harness or the new selectors (owned by the testing doc / V15).
