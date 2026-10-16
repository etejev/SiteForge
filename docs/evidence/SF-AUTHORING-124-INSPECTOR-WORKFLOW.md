# SF-AUTHORING-124 — Practical Inspector workflow package

Status: SOURCE IMPLEMENTED, VERIFICATION DEFERRED; cycle Prompt 2/10.
Requirements (bounded): SF-0701-002/003/004/006/007/008,
SF-0702-002/004/005/006/008, SF-0703-002/003/004/005/006/008,
SF-0704-003/004/006. Existing geometry/responsive/history requirements are
supporting boundaries, not newly claimed complete. All modules remain Partial.

## Source workflow

- Native section discovery maps property terms to Design/Layout/Content/
  Interactions/Accessibility. Search/Return/Escape/Clear, horizontal readable
  result navigation and Pin/Unpin are window-local, not canonical/history state.
  Pins prioritize matching sections without hiding unmatched tabs or changing
  current selection. No-result recovery keeps the current Inspector usable.
- Component property-level discovery reuses 123 and its original typed editors;
  global discovery reveals the appropriate section rather than duplicating six
  component property implementations or filtering away retained conflicts.
- Layout's native property chooser offers Copy/Paste for X/Y/Width/Height in
  points. Copy reads the existing registry's whole applicable selection:
  Mixed/Unavailable cannot borrow primary values. Existing responsive-source
  provenance and mixed explanations are displayed.
- Private clipboard v1 contains only version, typed field and finite validated
  number, bounded to 2 KiB. Deterministic exact encoding rejects malformed,
  unsupported-version/field, unknown/duplicate keys, Boolean numeric input,
  nonfinite/out-of-range values and alternative encodings. No executable
  property names, resource/definition references, source IDs or paths are copied.
- Paste routes through the same identity-gated Geometry Inspector registry as
  native fields. It authors the copied resolved number at the destination's
  current breakpoint; it does not clone source provenance or reset inheritance.
  One atomic transaction/exact inverse; explicit skipped subset, stale/locked/
  hidden/missing/lifecycle rejection, history/persistence/renderer adoption reuse
  the existing owners. Copy/discovery produce no canonical edit. Invalid paste
  creates no transaction and offers copy-again recovery. No asynchronous paste
  result can target a later scene because this boundary is synchronous.
- Existing registry diagnostics stay content-free; neither search terms nor
  clipboard bytes/values are added to logs. Accessibility exposes scope, status,
  enabled copy/mixed state and pin state; native controls are keyboard-operable.

## New test source — unrun

- TransformModelTests.testInspectorPropertyClipboardStrictTypedRoundTripAndInvalidNeutrality
- TransformModelTests.testInspectorPropertyPasteAtomicHistoryPersistenceAndResponsiveIsolation
- TransformModelTests.testInspectorPropertyPasteRejectsStaleCancelledAndSelectionMismatch
- AppMetadataTests.testInspectorSectionDiscoveryPinsOrderAndSceneLocalNeutrality
- SiteForgeLaunchTests.testInspectorWorkflowSearchPinGeometryPasteUndoAndMixedJourney

Four deterministic tests plus one actual-app journey source cover strict wire
validation, exact history/serialization, responsive isolation, stale/cancel,
mixed and skipped subsets, section order/pins and native search/paste/undo/redo/
multi-selection. Existing geometry, package/recovery, component discovery and
mixed/inapplicable journeys remain adjacent regression acceptance, not waived.
No tests/build/compiler/parser/checker/UI automation executed; manual source
review only. Native focus, clipboard permission/interruption, compact/200% UI,
visual/AX/recovery/performance and accumulated acceptance remain pending.

## Explicit scope and next package

Section discovery is navigation, not hiding individual noncomponent fields.
Transfer is geometry-value copy/paste, not arbitrary style/compound/reference
transfer; those require typed scopes and remain outside this private format.
No new project schema, persistent pins, component ownership or exported editor
chrome. OD-018/019 and update trust are unchanged. No commits/external actions.

Next greatest local-builder gap: connected local website/output completion,
including truthful unsupported containing-layout recovery and native Preview/
local-export parity (110/121/122). See REMAINING_DEVELOPMENT_ROADMAP.md for
phase-one 5–8-package estimate and explicitly deferred service-heavy phase two.
