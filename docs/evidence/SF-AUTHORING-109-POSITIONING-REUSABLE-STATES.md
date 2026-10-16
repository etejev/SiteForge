# SF-AUTHORING-109 — Positioning, reusable styles, and interaction states

Verification checkpoint (2026-10-08): repository/build gates and the complete
non-UI target ran; corrected non-UI coverage is green. Static output now emits
the authoritative token-resolved fill layer without its obsolete literal
fallback. The actual-app journey remains blocked before UI execution.

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED** (2026-10-08)

Requirements: `SF-0504-001`–`008`, `SF-0510-001`–`008`, and
`SF-0511-001`–`008` (bounded foundation; normative modules remain Partial).

## Delivered source contract

- `layout.position.v1.*` stores a closed static/relative/absolute/fixed/sticky
  mode, finite insets, integer stacking layer, provenance, and stable property
  identities. One resolver feeds renderer, selection, hit testing, and AX.
- `style.reusable.v1.*` stores stable named definitions and ordered references.
  Resolution is deterministic: referenced definitions in authored order, then
  local values. Missing, duplicate, malformed, and cyclic-by-reference input
  is rejected before adoption.
- `style.state.v1.*` stores stable hover/focus/pressed/disabled variants.
  Forced state preview is scene-local; committed variants remain canonical.
- `AdvancedStyleCommandRegistry` validates document/page/revision/scene/
  renderer/selection identity, lifecycle availability, supported subsets,
  cancellation, values, and stable identities before producing one existing
  atomic document transaction with its normal exact inverse.
- Immutable canvas preparation resolves positioning, z-order, reusable
  appearance, and forced state before renderer adoption. The closed static
  emitter maps only typed modes and approved pseudo-classes; no raw selector,
  style name, or authored CSS crosses the output boundary.
- Native Layout and Design Inspector controls keep incomplete drafts local,
  expose containing-block/provenance status, create/apply/update/detach/delete
  reusable styles, author bounded states, cancel with Escape, and announce
  material changes. Diagnostics retain only closed categories and hashed IDs.

## Source evidence

- `SiteForge/DocumentModel.swift`: `CanonicalPositioning`,
  `CanonicalReusableStyleIndex`, `CanonicalResolvedAppearance`.
- `SiteForge/TransformModel.swift`: `AdvancedStyleCommandRegistry` and redacted
  diagnostic factory/buffer.
- `SiteForge/WorkspaceShellModel.swift`: immutable canvas adoption and the
  identity-gated workspace command route.
- `SiteForge/WorkspaceShellView.swift`: native positioning, reusable-style,
  state-authoring, and forced-preview controls.
- `SiteForge/CanvasRendererCore.swift`: immutable static projection and
  `StaticAdvancedStyleOutputEmitter`.
- `TransformModelTests.testAdvancedStyleRegistryHistoryPersistenceAndSafeStaticProjection`
- `TransformModelTests.testAdvancedStyleMixedSelectionStaleValidationAndRedactedDiagnostics`
- `CanvasRendererTests.testAdvancedStyleProjectionAdoptsPositionZOrderAndForcedStateAtomically`
- `SiteForgeLaunchTests.testPositioningReusableStyleAndInteractionStateAuthoringJourney`

The changed Swift sources and focused test sources pass a parser-only syntax
check. Runtime XCTest, app-host visual review, performance fixtures, and the
repository gate were not executed under the owner testing pause; no verified
completion is claimed.

## Explicitly deferred

Arbitrary CSS/selectors, visited/custom states, transitions and animation,
remote style libraries, responsive style overrides, scripting, broad browser
and output parity, large/stress performance evidence, OS-level accessibility
certification, and release acceptance remain deferred.
