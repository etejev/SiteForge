# Lane RC review — lane C (motion and interactions), 2026-11-26

Reviewer: lane R reviewer C (`lane-RC`), on-device review on SEA124-DUJL56QN under the review freeze.
Baseline: RP-2026-11-26-R01 (pre-lane RP-2026-11-26-11). Everything below is unverified: there is no Swift
compiler on Windows, so every change was re-read against the declarations it calls.

## Scope

- Batches: C01 (motion, ADR-0060), C02 (event graph + runtime, ADR-0061), C03 (page variables, overlays,
  ADR-0062), C04 (lane C review fixes, ADR-0063).
- Modules: SF-1101, SF-1103, SF-1104, SF-1105, SF-1106 (OD-039, OD-040).
- Code read in full: `SiteForge/DecorativeEffects.swift` (`DecorativeEffectEdit`, `DecorativeEffectCommandRegistry.prepare`,
  `CanonicalMotion`, `MotionOutput`, `MotionRuntime`, `CanonicalInteraction`, `CanonicalEventGraph` + `remappingTargets`,
  `EventOutputConfiguration`, `CanonicalVariableValue`, `CanonicalStateVariable`, `CanonicalPageState`, `CanonicalOverlay`,
  `EventGraphOutput`, `EventGraphRuntime`), `SiteForge/DecorativeEffectsInspector.swift` (`MotionInspector`,
  `InteractionInspector`, `RuntimeStateInspector`, `VariableValueField`), lane C parts of `CanvasRendererCore.swift`
  (`MultiPageStaticBuildPlanner.plan`, `StaticBuildCompiler.compile` interaction findings, `SafeHTMLEmitter.emit/emitNode`),
  `DocumentModel.swift` (validation call, `ModelValidationError` cases + descriptions, schema-27 gate), the seven
  `remappingTargets` call sites, `WorkspaceShellModel` preview operation names, `WorkspaceShellView` placement, lane H's
  `StaticCSSOptimizer` / `LocalBuildProfileCompiler`, and all lane C tests in `Tests/SiteForgeTests/TransformModelTests.swift`.

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/CanvasRendererCore.swift` | `MultiPageStaticBuildPlanner.plan` (`needsHiddenCSS`) | The `[data-siteforge-node][hidden] { display:none !important; }` rule was written only when some object started hidden. Static layout emits `display: block;` for every object (`StaticLayoutOutputEmitter.baseRule`), which beats the browser's `[hidden]` rule, so Hide, Show or Hide and a condition that becomes false did nothing on such pages (and on containers with an explicit `display`). | `needsHiddenCSS` is also set when `events.needsRuntime`. | SF-1101-003/004 and SF-1106 bindings must actually hide. |
| 2 | `SiteForge/DecorativeEffects.swift` | `EventGraphOutput.page` | A visibility condition on an overlay was emitted; the runtime's `render()` then showed or hid the overlay outside the overlay stack (no backdrop, focus trap or Escape). | Overlays never get `data-siteforge-visible-when`. New warning `overlay-condition-ignored` (SF-1105-003) in `EventGraphOutput.findings`; `RuntimeStateInspector` shows a note instead of the condition toggle on an overlay without a condition. | SF-1105 invariant: modal focus contained, defined stacking. |
| 3 | `SiteForge/DecorativeEffects.swift` | `EventGraphRuntime.javascript` (`run`), `EventGraphOutput.findings` (`opened`) | Show, Hide and Show or Hide aimed at an overlay set `hidden` directly (same breakage as #2), and `overlay-unreachable` fired for overlays opened by Show. | Runtime: Show or Show or Hide on a hidden overlay calls `open`, Hide or Show or Hide on an open overlay calls `close`, otherwise nothing. Findings count Show and Show or Hide as openers. | Same invariant; no false warning. |
| 4 | `SiteForge/DecorativeEffects.swift` | `EventGraphOutput.page` (`isBound`) | Start hidden plus a condition that is true at the start wrote `hidden`, but `render()` shows the object on load: the first render did not match the runtime state. | A valid condition decides the initial `hidden`; Start hidden applies only to unbound objects. | SF-1106 invariant: initial render is hydration-safe. |
| 5 | `SiteForge/DecorativeEffects.swift` | `EventGraphOutput.findings` | On pages without page flow or automatic sizing (`!page.usesConnectedOutput`) `SafeHTMLEmitter` writes every object as its own absolutely placed element, so a container's contents are not inside its HTML element: hiding, showing or opening it (and a modal's focus trap and portal) does not include them. This was not diagnosed. | New warning `interaction-container-flat` (SF-1101-004) for containers with children that are hidden, shown, opened, conditioned or Start hidden on such pages. Real support is remaining work (gap R5). | SF-1101-004 / SF-1105-004: no silently broken output. |
| 6 | `Tests/SiteForgeTests/TransformModelTests.swift` | new `testInteractionOutputHiddenRuleFirstRenderOverlayConditionsAndStaticLayoutContainers` | Fixes 1-5 had no coverage. | New test in the existing style (local helpers `openingTag`, `builtPage`), placed before the C01 motion output test. | Regression coverage. |
| 7 | `docs/architecture-decisions/ADR-0064-lane-c-review-r-fixes.md` | - | - | New ADR (lane C range) recording 1-5. | Output behaviour of ADR-0061/0062 changed. |

Comments added only explain why (static layout `display`, condition versus Start hidden, overlay stack). No schema,
CanonicalDocument key, clipboard or project-file change; still document schema 27, history schema 4, WebsiteMetadata 3.
`check([...])` returned [] after every edit; `foreign_changes(30)` was [] throughout.

### Verified without change

- `CanonicalEventGraph.remappingTargets` is used in all six copy paths plus collection list copies: `ClipboardTransfer`
  paste (around L1000), `TransformModel` definition graph copy (L1614), slot contents (L1845), Create Component (L2433),
  `CanonicalPageGraphClone.prepare` page duplicate (CommandKernel L135), `InsertionModel` component expansion (L1902,
  `freshIdentity: false`) and `CollectionTemplates.expand` list copies (DocumentModel L11596, `freshIdentity: false`). It
  decodes and re-encodes `CanonicalInteraction`, so C03's `variable` and `value` fields survive; page variable UUIDs need
  no remap (page duplicate copies the Root's variables verbatim).
- Interaction findings run on `ComponentGraphResolver.resolvedPage`; non-instance nodes are appended unchanged, so ids match.
- Lane H's `StaticCSSOptimizer` keeps every lane C rule: `isUnused` never removes a rule with `(` (`:not(...)`) or without
  an object id (`hiddenCSS`, `.sf-overlay-backdrop`, the modal rule, the motion hide rule), keyframe children are never
  removed, and the motion and transition rules name ids that the HTML contains. `LocalBuildProfileCompiler` does not touch
  `.js` files.
- Generated JavaScript: both runtimes are Swift raw multi-line strings (`#` delimiters), so the regex `/[:\\]/` reaches JS
  exactly as written and nothing is interpolated. Read for syntax (optional `catch {}`, arrow functions, `for...of`,
  `element.before` / `replaceWith`), focus trap (Tab / Shift-Tab wrap, no-focusable fallback, `focusin` return), Escape
  closes the top overlay, modal portal (comment placeholder, restored in reverse order), `prefers-reduced-motion` (motion
  CSS gated, reveal-all on Reduce Motion, `scrollIntoView` with `auto`). Node ids are lowercase
  (`StableIdentifier.description`), as the runtime's `find` requires.
- Lane C assertions in `TransformModelTests` re-derived against the exact strings produced (`events(for:)` relies on
  `data-siteforge-events` directly before `data-siteforge-node`; overlay tag suffix; keyframe, animation and transition
  lines; runtime substrings; finding codes). All still match after the fixes.
- Exhaustive switches: `DecorativeEffectEdit` (registry, and `WorkspaceShellModel` preview names with `default`),
  `ModelValidationError.errorDescription` (the only switch in the tree), `CanonicalInteraction.ActionKind` in `compile`,
  `reshaped` and `actionEditor`.

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-1101-001 | Met | `CanonicalEventGraph`: closed `event.v1.` canonical JSON, exact keys, schema-27 gate; `testEventGraphTypedValidationHistoryClickPolicyAndSchemaGate` |
| SF-1101-002 | Partial | Interactions inspector with preview then commit; chained actions. Key-press trigger and page overview missing (C7) |
| SF-1101-003 | Partial | Deterministic authored order, focus-loop and unreachable-action findings; no provenance or overview surface (C7) |
| SF-1101-004 | Met | Deleted targets kept and reported (`interaction-target-missing`); forged data refused; `interaction-container-flat` (this review) |
| SF-1101-005 | Met | One undo entry, property identity, persistence, remap in all copy paths; `testCopiedInteractionsFollowCopiedTargetsAndKeepOutsideTargets` |
| SF-1101-006 | Partial | Click only on buttons and links, `interaction-pointer-only`, labelled controls; no UI tests; runtime changes not announced |
| SF-1101-007 | Partial | Hard bounds (8 interactions x 8 actions, 16 KiB); no standard, large or stress fixture timing |
| SF-1101-008 | Partial | Node-id-only findings and unit tests; no browser-run runtime tests (C10) |
| SF-1103-001 | Met | `CanonicalMotion` all-or-nothing groups, ranges, schema gate; `testMotionTypedValidationHistoryPropertyIdentityAndSchemaGate` |
| SF-1103-002 | Partial | Inspector and website Preview; no canvas preview, scrub or timeline (outside the OD-040 slice) |
| SF-1103-003 | Partial | Deterministic sorted CSS; reusable transitions missing (C9, OD-071) |
| SF-1103-004 | Met | Invalid values refused without mutation; unsupported kinds and form fields skipped with reasons |
| SF-1103-005 | Met | Undo/redo and property identity test |
| SF-1103-006 | Met | Native controls with labels and identifiers; Reduce Motion honoured |
| SF-1103-007 | Partial | CSS only, one observer per trigger line; no performance fixture |
| SF-1103-008 | Partial | Output test; no browser test and no motion findings |
| SF-1104-001 | Met | Entrance group (effect, duration, delay, distance, offset, easing) typed and gated |
| SF-1104-002 | Partial | Scroll preview only in website Preview; parallax and scroll progress missing (C9) |
| SF-1104-003 | Met | Trigger line maps to `rootMargin`; page-end and focus fallbacks; asserted by runtime substrings |
| SF-1104-004 | Met | Missing IntersectionObserver, Reduce Motion and page end reveal everything |
| SF-1104-005 | Met | Same registry and tests as SF-1103 |
| SF-1104-006 | Met | No scroll trapping; focus reveals; content visible without scripts, in print and with Reduce Motion |
| SF-1104-007 | Partial | Opacity and transform only (no layout shift); no performance fixture |
| SF-1104-008 | Partial | No browser test (C10) |
| SF-1105-001 | Met | `CanonicalOverlay` exact two keys, never on the Root; tests |
| SF-1105-002 | Missing | Position relative to the trigger not built (C5) |
| SF-1105-003 | Partial | Stack policy defined; `overlay-condition-ignored`; Show and Hide routed through the stack (this review) |
| SF-1105-004 | Partial | `overlay-unreachable`, `overlay-unnamed`; overlays on static-layout pages are only diagnosed (R5) |
| SF-1105-005 | Met | Undo and persistence tests |
| SF-1105-006 | Partial | Focus trap, Escape, focus restore, `role="dialog"` / `aria-modal`; arrow-key menus missing (C5) |
| SF-1105-007 | Partial | Bounded; no performance fixture |
| SF-1105-008 | Partial | No browser test (C10) |
| SF-1106-001 | Met | Typed boolean, whole-number and text values; canonical JSON; limits |
| SF-1106-002 | Partial | Visibility bindings; value (text) bindings missing (C6) |
| SF-1106-003 | Partial | Condition-over-Start-hidden precedence now defined (this review); no provenance surface |
| SF-1106-004 | Met | Removed or retyped variables kept and reported (`state-binding-invalid`) |
| SF-1106-005 | Met | Undo and persistence tests |
| SF-1106-006 | Partial | Labelled controls; visibility changes are not announced at runtime |
| SF-1106-007 | Partial | 16 variables, 16 KiB; no performance fixture |
| SF-1106-008 | Partial | Unit tests; no browser test; session and URL scopes blocked (OD-070) |

## Remaining gaps (easiest to hardest)

1. R1 `VariableValueField.submit` silently drops an invalid number or text (for example `1.5`): show an inline validation
   caption as `EffectNumberControl` does.
2. R2 Scrolled Into View interactions never run without IntersectionObserver: run them once at load in that case.
3. R3 The `ClipboardTransfer` definition fingerprint material (around L1385-1408) hashes `event.v1.interactions` as raw text,
   so identical definitions from another project never match; map targets through `nodeIndex` and leave out interaction ids.
4. R4 Create Component refuses inbound section links to moved children but not inbound interaction targets (they become
   `interaction-target-missing`); add the same refusal or a remap.
5. R5 Static-layout pages (`!usesConnectedOutput`): containers do not contain their children in HTML. Plan: emit
   `data-siteforge-within="<controlled ancestor ids>"` on descendants plus one rule per controlled container,
   `:root:has([data-siteforge-node="X"][hidden]) [data-siteforge-within~="X"] { display:none !important; }` (the optimizer
   keeps it because it contains `(`), propagate initial `hidden` at build time, and either refuse modals on static-layout
   pages or write the overlay subtree nested with coordinates relative to the overlay.
6. Plan items C5-C10 (trigger-relative placement and menu arrow keys, value bindings, key-press trigger and overview,
   OD-070 scopes, OD-071 motion, browser-run tests), plus performance fixtures for SF-110x-007.

## Intended OD status-line changes

- OD-039 Implementation status, append: "Lane R review (RC) 2026-11-26, ADR-0064: hidden rule on every page with the
  runtime; overlays ignore visibility conditions and Show/Hide go through the overlay stack; a condition decides the first
  render; new warnings `overlay-condition-ignored` and `interaction-container-flat`; static-layout container support open
  (unverified)."
- OD-040: no change needed (optionally append "reviewed by lane RC 2026-11-26, no defects").

## New/changed test selectors

```
SiteForgeTests/TransformModelTests/testInteractionOutputHiddenRuleFirstRenderOverlayConditionsAndStaticLayoutContainers
```

No existing test was changed; the existing lane C assertions still hold after the fixes (re-derived).

## Suggested first checks for Codex

- `EventGraphOutput.page`: `let overlay = try CanonicalOverlay.resolve(node)`, `if let overlay {`, then
  `if overlay == nil, let condition = try CanonicalPageState.condition(node), ...` and `if graph.startsHidden, !isBound`.
- `EventGraphOutput.findings`: `[.openOverlay, .show, .toggle].contains(action.kind)` and the five-element variant (type
  inference), `var controlled = overlays`, `page.usesConnectedOutput` (DocumentPage extension in InsertionModel.swift),
  `node.childIDs`.
- `EventGraphRuntime.javascript`: the lines from `const overlay = target.hasAttribute('data-siteforge-overlay');` to the
  `continue;` inside `for...of` within `try` (browser check: Show on a modal opens it with its backdrop; Hide closes it and
  restores focus).
- `RuntimeStateInspector.body`: the new `if overlay != nil && condition == nil { ... } else if ... else ...` chain.
- New test: overlay tag suffix ` data-siteforge-overlay="popover" role="dialog" hidden>`, text tag without ` hidden`
  (Start hidden plus a true condition), `interaction-container-flat:<root>` (the fixture page uses static layout), and
  `hiddenCSS` present with no start-hidden object.
- Any snapshot or size test of `styles.css` for pages with interactions now sees the hidden rule line.
