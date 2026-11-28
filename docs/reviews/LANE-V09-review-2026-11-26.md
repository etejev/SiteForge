# Lane V09 review — lane C (motion and interactions), 2026-11-26

Reviewer: lane V09 (`lane-V09`), on-device verification on SEA124-DUJL56QN (no Swift toolchain, no browser run).
Baseline: RP-2026-11-26-V00 (lane V start); lane C before-points RP-2026-11-26-11 / -C01…-C04, lane R RP-2026-11-26-R01.
Everything below is unverified: every change was re-read against the declarations it calls.

## Scope

- Batches: C01 (motion, ADR-0060), C02 (event graph, ADR-0061), C03 (variables and overlays, ADR-0062),
  C04 (lane C review fixes, ADR-0063), lane RC fixes (ADR-0064).
- Modules: SF-1101, SF-1103, SF-1104, SF-1105, SF-1106 (OD-039, OD-040).
- Diffed RP-2026-11-26-11 → V00 for every lane C file (ledger owners `lane-C`, `lane-RC`): `SiteForge/DecorativeEffects.swift`
  (+1072 lines, read in full), `SiteForge/DecorativeEffectsInspector.swift` (+392, read in full), lane C regions of
  `CanvasRendererCore.swift` (planner, `StaticBuildCompiler.compile` findings, `SafeHTMLEmitter.emit/emitNode`),
  `DocumentModel.swift` (validation call, error cases, schema-27 gate, list copies), `WorkspaceShellModel.swift`
  (preview operation names), `WorkspaceShellView.swift` (inspector placement), the seven `remappingTargets` call sites
  (ClipboardTransfer, CommandKernel, InsertionModel, TransformModel ×3, DocumentModel), and all lane C tests in
  `Tests/SiteForgeTests/TransformModelTests.swift`.
- Partial features in the manifest: C5, static-layout containers (RC gap R5), RC gaps R1–R4; C10 added by the owner at
  7:40 PM (harness files now readable).
- **First edits from Windows:** `Tests/Tooling/interaction_runtime_browser.py` and
  `Tests/Tooling/test_interaction_runtime_browser.py` are new files written from Windows (the existing
  `flow_runtime_browser.py`, `test_flow_runtime_browser.py`, `docs/TESTING.md` and `.github/workflows/ci.yml` were read
  for the first time from Windows and were **not** changed). `SupportSettingsTests.swift` is still an unreadable
  placeholder and was not touched.

## Verified without change

- `DecorativeEffectCommandRegistry.prepare`: every `DecorativeEffectEdit` case handled in both switches; root, form-field,
  click-kind and kind checks; one batch command; `noChanges`/`stale` paths.
- `CanonicalMotion`, `CanonicalEventGraph`, `CanonicalInteraction` (exact keys, canonical text round trip, bounds),
  `CanonicalVariableValue` (Bool before Double decoding is safe: JSONDecoder does not decode `1` as Bool, and the
  canonical round-trip check rejects any ambiguity), `CanonicalPageState.validate`, `CanonicalOverlay.resolve`.
- `remappingTargets` in all six copy paths plus list copies (as lane RC found); `variable`/`value` fields survive.
- Schema-27 gate covers the `motion.`, `event.`, `state.`, `overlay.` prefixes; validation runs every resolver.
- Exhaustive switches over `DecorativeEffectEdit`, `ActionKind`, `Trigger`, `Easing`, `EntranceEffect`, `Kind`.
- Lane RC fixes 1–4 re-read and still correct; fix 5 (`interaction-container-flat`) superseded by real support below.
- Both runtimes are Swift raw strings (`#"""`): no `"""#` or `\#(` inside after the edits (checked by script).

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/DecorativeEffectsInspector.swift` | `VariableValueField.submit`, `RuntimeStateInspector` name field | An invalid number (`1.5`, `1,000`), over-long or control-character text, an invalid or duplicate variable name was dropped silently (RC R1). | The entry stays in the field with a caption (`identifier + ".validation"`); new `problem` hook; `nameProblem(_:index:)` checks name rules and uniqueness. | Validation failure must give a specific recovery (SF-1106-002/004). |
| 2 | `SiteForge/DecorativeEffects.swift` | `EventGraphRuntime.javascript` | Scrolled Into View interactions never ran without IntersectionObserver (R2). | They run once at load in that case. | No silent loss of authored actions. |
| 3 | `SiteForge/ClipboardTransfer.swift` | `definitionFingerprint`, new `interactionMaterial` | Interactions were hashed as raw text (random interaction ids, raw node ids), so an identical definition from another project was never reused (R3). | Interactions described without ids, targets inside the definition by position, pages/outside nodes through the transfer maps. | Component reuse (SF-1101-005, OD-034). |
| 4 | `SiteForge/TransformModel.swift` | `ComponentCommandRegistry.creationSourceIDs`, `inboundInteractionReason` | Create Component silently broke interactions elsewhere that target moved contents (R4). | Refused with a specific reason; a target on the container itself is kept (the instance keeps its id). | Same policy as inbound section links. |
| 5 | `SiteForge/DecorativeEffects.swift`, `CanvasRendererCore.swift` | new `FlatContainerOutput`; `EventGraphOutput.PageOutput.memberAttributes/htmlAttributes`; planner stylesheet; `SafeHTMLEmitter.emit` form branch; both runtimes | On static-layout pages hiding/showing/opening a container, its reveal, and a modal's focus trap did not include its contents (R5; RC only warned). | See ADR-0065: `data-siteforge-within` / `data-siteforge-flat`, one sibling hide rule per container (works without JS), contents reveal with the container, runtime groups for focus/trap/outside clicks/z-order/placement, flat modals centred by the runtime. Warning `interaction-container-flat` retired. | SF-1101-004, SF-1104-004, SF-1105-004/006. |
| 6 | `SiteForge/DecorativeEffects.swift` | `MotionRuntime.javascript` (`reveal`, `focus`) | Found in this review: a revealed container on a static-layout page left its contents unanimated, and keyboard focus inside contents did not reveal a pending container. | Contents get `sf-motion-entered` with their container; focus in contents reveals it. | SF-1104-004/006. |
| 7 | `Tests/SiteForgeTests/TransformModelTests.swift` | `testInteractionOutputHiddenRuleFirstRenderOverlayConditionsAndStaticLayoutContainers` | The test asserted the old limitation (`interaction-container-flat`) and an overlay tag without the new `data-siteforge-within`. | Asserts the supported behaviour (no warning, `within` on the Root's contents, the sibling rule) and the new tag suffix. | Test was wrong after the feature; nothing weakened. |

Comments added explain why only. `check([...])` returned [] after every edit; `foreign_changes(30)` and
`icloud_duplicates()` stayed [] throughout.

## Features finished

- **C5 (ADR-0065, OD-039):** `CanonicalOverlay.Placement` / `overlay.v1.placement` (popover and menu only; modal refused),
  inspector "Opens" picker (`inspector.overlay.placement`; choosing Modal Dialog clears it), output
  `data-siteforge-placement`, runtime `place` (below/above/start/end, flip, RTL, clamp, re-place on resize/scroll,
  `translate`), menu Arrow Down/Up/Home/End. One transaction per edit, property identities kept, undo/redo, persistence,
  schema gate, forged-value validation — all tested.
- **Static-layout containers (RC R5, ADR-0065):** as fix 5/6.
- **RC gaps R1–R4:** fixes 1–4.
- **C10 (ADR-0065):** browser-run tests of the interaction and motion runtimes: focus trap (Tab / Shift-Tab wrap), Escape
  closes and restores focus, modal backdrop and centring, menu placement below and flip above at the viewport edge, menu
  arrow keys, reveal on scroll including container contents, Reduce Motion and JavaScript-off visibility. Pattern: the
  Flow harness pair (harness + pure helper tests), invoked from an XCTest wrapper with fixtures compiled by
  `MultiPageStaticBuildPlanner`; the new harness imports `flow_runtime_browser.py` for the owned Chrome, DevTools client
  and server instead of copying them. A separate file per runtime matches the existing "one harness per runtime"
  structure; the Flow files were not edited, so the Flow test (whose wrapper is in the unreadable
  `SupportSettingsTests.swift`) is unaffected.

No new CanonicalDocument key; document schema 27, persisted-history schema 4, WebsiteMetadata 3 unchanged.

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-1101-001 | Met | `CanonicalEventGraph` closed canonical JSON, schema-27 gate; `testEventGraphTypedValidationHistoryClickPolicyAndSchemaGate` |
| SF-1101-002 | Partial | Inspector with preview then commit; key-press trigger and page overview not built (C7, not started) |
| SF-1101-003 | Partial | Deterministic order, focus-loop / unreachable findings; no overview or provenance surface (C7) |
| SF-1101-004 | Met | Missing targets kept and reported; static-layout containers supported (ADR-0065); Create Component refuses inbound targets |
| SF-1101-005 | Met | One undo entry, identity, persistence, six copy paths; definition reuse with interactions (`testComponentTransferReusesDefinitionWithEquivalentInteractions`) |
| SF-1101-006 | Partial | Click only on buttons/links, `interaction-pointer-only`; no UI tests; runtime changes not announced |
| SF-1101-007 | Partial | Hard bounds (8×8, 16 KiB); no performance fixture |
| SF-1101-008 | Met (not yet run) | Findings by node id; unit tests; browser harness (C10) `testInteractionAndMotionRuntimesActualBrowser…` |
| SF-1103-001 | Met | `testMotionTypedValidationHistoryPropertyIdentityAndSchemaGate` |
| SF-1103-002 | Partial | Inspector and website Preview; no canvas scrub/timeline (outside the OD-040 slice) |
| SF-1103-003 | Partial | Deterministic CSS; reusable transitions blocked (C9, OD-071 open) |
| SF-1103-004 | Met | Invalid values refused without mutation |
| SF-1103-005 | Met | Undo/redo and property identity test |
| SF-1103-006 | Met | Labelled native controls; Reduce Motion honoured (browser case 8) |
| SF-1103-007 | Partial | CSS only; no performance fixture |
| SF-1103-008 | Partial | Output tests and browser reveal case; no motion-specific findings |
| SF-1104-001 | Met | Entrance group typed and gated |
| SF-1104-002 | Partial | Parallax / scroll progress blocked (C9, OD-071) |
| SF-1104-003 | Met | Trigger line → `rootMargin`; page-end and focus fallbacks |
| SF-1104-004 | Met | No IntersectionObserver / Reduce Motion / page end reveal everything; contents reveal with their container |
| SF-1104-005 | Met | Same registry and tests as SF-1103 |
| SF-1104-006 | Met | Focus (also inside contents) reveals; visible without scripts, in print, with Reduce Motion (browser case 8) |
| SF-1104-007 | Partial | Opacity/transform only; no performance fixture |
| SF-1104-008 | Met (not yet run) | Browser case `reveal-on-scroll-includes-container-contents` |
| SF-1105-001 | Met | `CanonicalOverlay` exact keys incl. optional placement; never on the Root |
| SF-1105-002 | Met | Placement relative to the trigger with flip (C5); `testOverlayPlacementMenuKeysAndStaticLayoutContainerContents`; browser cases 5–6 |
| SF-1105-003 | Partial | Stack policy, `overlay-condition-ignored`; no provenance surface beyond findings |
| SF-1105-004 | Met | `overlay-unreachable`, `overlay-unnamed`; overlays with contents on static-layout pages work (ADR-0065) |
| SF-1105-005 | Met | Undo, redo and persistence tests (C03 test and the new test) |
| SF-1105-006 | Met | Focus trap, Escape, focus restore, `role="dialog"`/`aria-modal`, menu arrow keys (browser cases 2–5) |
| SF-1105-007 | Partial | Bounded; no performance fixture |
| SF-1105-008 | Met (not yet run) | Browser harness cases 1–6 |
| SF-1106-001 | Met | Typed values, canonical JSON, limits |
| SF-1106-002 | Partial | Visibility bindings with validation captions; value (text) bindings not built (C6, not started) |
| SF-1106-003 | Partial | Condition-over-Start-hidden precedence defined; no provenance surface |
| SF-1106-004 | Met | Removed/retyped variables kept and reported (`state-binding-invalid`) |
| SF-1106-005 | Met | Undo and persistence tests |
| SF-1106-006 | Partial | Labelled controls; runtime visibility changes not announced |
| SF-1106-007 | Partial | 16 variables, 16 KiB; no performance fixture |
| SF-1106-008 | Partial | Unit tests; session/URL scopes blocked (OD-070 open) |

Totals: Met 23, Partial 17, Missing 0.

## Remaining work (blocked only)

1. C8 session and URL-parameter variables — blocked: OD-070 is Open.
2. C9 reusable transitions, scroll progress, parallax — blocked: OD-071 is Open.
3. C6 (text value bindings) and C7 (key-press trigger, page overview) — blocked: not started plan items (no partial code
   exists), outside this verification's "finish partial features" scope while the tree returns to the Codex-review pause.
4. Performance fixtures for SF-1101/1103/1104/1105/1106-007 and announcements of runtime visibility changes
   (SF-1101-006, SF-1106-006) — blocked: new work that needs a Mac to time and VoiceOver to check; same pause.
5. Running the Swift tests and both Python harnesses — blocked: no Mac/Swift toolchain/Chrome on this PC (commands below).

## Intended plan / OD status-line changes (for the coordinator)

- Plan, lane C table: C5 → `done (V09, ADR-0065, unverified)`; C10 → `done (V09, ADR-0065, unverified; browser harness not yet run)`;
  C6, C7 stay `todo`; C8, C9 stay blocked.
- OD-039 Implementation status: replace "Not in this slice: session/persistent/URL variables, trigger-relative overlay
  positioning." with "Not in this slice: session/persistent/URL variables (OD-070)." and append: "Lane V09 (2026-11-26,
  ADR-0065): popover/menu placement relative to the trigger with flip, menu arrow keys, static-layout container contents
  hide/show/open/reveal with their container (`interaction-container-flat` retired), Scrolled Into View without
  IntersectionObserver, validation captions for variable fields, definition reuse and Create Component checks for
  interactions, browser-run runtime tests (C10). Still unverified."
- OD-040 Implementation status, append: "Lane V09 (2026-11-26, ADR-0065): on static-layout pages a container's contents
  reveal with it; browser-run reveal and Reduce Motion checks added. Still unverified."
- Activity log entry title suggestion: `## Lane V09 — 2026-11-26 (lane C verification, C5/C10/R1–R5, OD-039/OD-040, unverified, complete)`.

## New/changed test selectors

```
SiteForgeTests/TransformModelTests/testOverlayPlacementMenuKeysAndStaticLayoutContainerContents            (new)
SiteForgeTests/TransformModelTests/testInteractionAndMotionRuntimesActualBrowserFocusTrapEscapePlacementAndReveal (new, launches Chrome)
SiteForgeTests/ClipboardTransferTests/testComponentTransferReusesDefinitionWithEquivalentInteractions       (new)
SiteForgeTests/TransformModelTests/testInteractionOutputHiddenRuleFirstRenderOverlayConditionsAndStaticLayoutContainers (changed)
```

Commands for Codex (Mac):

```
./sf test focused SiteForgeTests/TransformModelTests/testOverlayPlacementMenuKeysAndStaticLayoutContainerContents \
  SiteForgeTests/TransformModelTests/testInteractionAndMotionRuntimesActualBrowserFocusTrapEscapePlacementAndReveal \
  SiteForgeTests/TransformModelTests/testInteractionOutputHiddenRuleFirstRenderOverlayConditionsAndStaticLayoutContainers \
  SiteForgeTests/ClipboardTransferTests/testComponentTransferReusesDefinitionWithEquivalentInteractions \
  SiteForgeTests/TransformModelTests/testRuntimeVariablesOverlaysOutputHydrationRuntimeAndDiagnostics \
  SiteForgeTests/TransformModelTests/testRuntimeVariablesOverlaysAndVisibilityTypedValidationHistoryAndSchemaGate \
  SiteForgeTests/TransformModelTests/testEventGraphOutputCompilesFixedActionsStartHiddenAndDiagnostics \
  SiteForgeTests/TransformModelTests/testMotionOutputIsReducedMotionSafeProgressiveDeterministicAndReleaseStable \
  SiteForgeTests/SupportSettingsTests/testFlowRuntimeActualBrowserDeformationFallbacksAndLifecycle
/usr/bin/python3 Tests/Tooling/test_interaction_runtime_browser.py
/usr/bin/python3 Tests/Tooling/test_flow_runtime_browser.py
```

The new harness's pure helpers (case list, key events, union, centring, generated in-page programs) were exercised here
against a stripped copy and both new Python files compile; the unittest file and the browser cases were not run.

## Suggested first checks for Codex

- `CanonicalOverlay.resolve`: `keys == [kindKey, dismissKey] || keys == [kindKey, dismissKey, placementKey]` (Set vs array
  literal), and `var placement: Placement? = nil` keeping `CanonicalOverlay(kind:dismissesOnOutsideClick:)` callers valid.
- `FlatContainerOutput.members`: `while case .node(let id) = parent, seen.insert(id).inserted, let ancestor = byID[id]`;
  `Groups(visibility:)` memberwise init; `try CanonicalMotion.resolve(node)?.entrance`.
- `EventGraphOutput.PageOutput.htmlAttributes` (`attributes.merging(memberAttributes) { $0 + $1 }`) and the planner call
  `attributes: events.htmlAttributes`; `let motion = try [MotionOutput.css(…), FlatContainerOutput.css(stylePages)]…`.
- `SafeHTMLEmitter.emit` form branch now appends `extraAttributes[node.id] ?? ""`.
- `ComponentCommandRegistry.creationSourceIDs`: `if case .string(let text)? = node.insertionProperty(…)?.value, … contains(where:)`.
- `VariableValueField` memberwise order `type, value, label, identifier, commit, problem` (trailing closures bind to
  `commit`); `nameProblem` uses `variables.indices.contains { … }`.
- `RuntimeStateInspector.overlayControls` (`@ViewBuilder`), `.tag(CanonicalOverlay.Placement?.none)`.
- Runtime (browser): `place` with `style.translate`, flat modal centring (`entry.flat`), `focusables` visibility filter,
  menu key block before the Tab trap; motion `members`/`reveal` recursion.
- New test assertions: menu tag suffix `… data-siteforge-placement="end" data-siteforge-within="<root>" data-siteforge-flat hidden>`,
  content tag `data-siteforge-within="<root> <frame>">`, and the member animation line
  `animation:sf-entrance-<root> 600ms ease-out 0ms both;` (page Root with the default entrance).
- Browser harness: DevTools key events use `rawKeyDown` with `windowsVirtualKeyCode`; the JavaScript-off case reads
  computed styles through `DOM.enable` + `CSS.enable` + `CSS.getComputedStyleForNode`.

## Out-of-area notes (not changed)

- `docs/REQUIREMENT_EVIDENCE.json` lists only the Flow tooling files; the new harness files may need an entry (owned by the
  evidence index, not lane C).
- `scripts/select-test-scope.py` maps `DecorativeEffects.swift` to `TransformModelTests`/`CanvasRendererTests`; changes to
  `Tests/Tooling/*` fall to explicit selectors (existing behaviour).
