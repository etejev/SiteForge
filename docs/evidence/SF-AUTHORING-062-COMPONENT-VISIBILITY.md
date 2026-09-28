# SF-AUTHORING-062 — Component Boolean visibility property v1

Requirements: bounded SF-0901-001–008, SF-0902-001–008, and SF-0905-001–008;
supporting SF-0305/SF-0306, SF-0701/SF-0702, and SF-1204. These modules remain
Partial outside the bounded property workflow.

## Implemented contract

- An eligible non-root component-definition child may own one stable typed
  Boolean visibility binding with an authored label and explicit default.
  Existing schema-ten documents without this namespace remain unchanged;
  older schema headers cannot smuggle the new keys. An unbound child continues
  to use its canonical hidden state.
- A linked instance may author `true` or `false` under the binding's stable ID.
  Authored override wins over the definition default; Reset removes the
  override and restores inheritance. Definition removal is rejected while
  retained instance overrides would lose their source. Orphaned historical
  overrides are retained for repair rather than silently reassigned.
- `ComponentCommandRegistry` enforces live document/page/revision/scene/renderer
  and selected-node identity. One operation creates one typed property-command
  transaction and exact inverse. Draft cancellation and malformed input do not
  mutate the document. Text and visibility binding names share a collision
  check within one definition.
- Component expansion materializes one effective `hidden` property on derived
  children without rewriting authored definition or instance data. Existing
  structural layout, native canvas/Preview visibility, hit-testing and
  accessibility consume the resulting immutable graph. The closed static plan
  expands that same graph and emits deterministic `display` declarations.
  A hidden virtual child remains discoverable by name and state under its
  selected instance in Layers, but is not a canvas ghost or hit target.
- Native Content controls expose definition name/default and linked-instance
  visibility, provenance, reset, removal, and status. Scene-local definition
  drafts cancel through Escape/Cancel. Stable AX identifiers and native
  checkbox values support keyboard/accessibility operation.

## Focused evidence

Exact new selectors:

- `CommandKernelTests/testComponentVisibilityDefaultOverrideResetHistoryAndPersistence`
- `CommandKernelTests/testComponentVisibilityStrictValidationStaleCancellationAndRemovalGuard`
- `CommandKernelTests/testComponentVisibilityRendererAccessibilityAndStaticOutputShareEffectiveState`
- `CommandKernelTests/testComponentVisibilityDuplicationAndDetachPreserveIntentAndStableIDs`
- `SiteForgeLaunchTests/testComponentVisibilityDefinitionInstanceResetAndReopenJourney`

The model/renderer selectors cover strict metadata and typed overrides,
cancel/stale neutrality, exact history, package round trip, duplicate/detach,
immutable native scene adoption, accessibility exclusion, and closed static
visibility. The fresh-process native journey covers expose, inherited hidden,
authored visible, undo/redo, reset, save, and reopen. Retained screenshot
attachments: hidden definition default, inherited-hidden instance,
authored-visible instance, reset-inherited instance, and reopened-visible
instance. Original-resolution review found readable controls, upright text,
correct page/pasteboard distinction, a selected Frame without a ghost Text
child when hidden, and a visible Text child confined to the Frame when shown.

The first UI attempt failed before executing due to XCTest automation-mode
initialization timeout. A later attempt reached the controls and found that
macOS exposes the native checkbox state as `NSNumber(0/1)`, not a string; the
test now asserts the actual checkbox state alongside visible provenance. The
next fresh-process run passed. Neither issue changed the product visibility
contract. The five exact new focused selectors passed 5/5 (four unit/integration
tests and one native UI test), zero failures. The final combined result bundle
for the Inspector refinement passed 2/2 and retained five named screenshots.
Visual review confirmed the irrelevant empty Component Text panel is absent
for a visibility-only instance; checkbox provenance and Layers agree; hidden
children leave no ghost; reopened visible content is upright and inside its
selected Frame. The result recorded an existing AppKit QoS priority-inversion
warning; this slice does not claim to fix the broader scheduling boundary.

`git diff --check`, JSON parsing, the seeded secret scanner, repository
security scan, portable checksum tests, authoring runway, and focused layout/
renderer/selection/insertion/transform/snapping/inline/drag evidence checks
passed. The aggregate repository check remains non-green because of existing
stale/duplicate traceability entries outside SF-0902/SF-0905 and the legacy
headless canvas-renderer slice's incomplete source list. This slice's new
headless canonical-model dependency was corrected and no SF-0902/SF-0905
traceability errors were reported. These broader checks are not a substitute
for the Prompt 10 `./sf verify` gate, which has not run.

## Deferred

Media/enum/action properties, slots, variants, nested component authoring,
bulk/mixed instance editing, arbitrary styling or expression properties,
per-breakpoint component visibility bindings, browser runtime, broad scale
and assistive-technology matrices, publishing, and release acceptance. The
prompt-ten full local gate and hosted checkpoint have not run for this slice.
