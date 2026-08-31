# SF-AUTHORING-018 — Responsive Layout and Visibility Evidence

Date: 2026-08-28

## Bounded contract

This milestone supplies bounded production evidence for `SF-0601-001` through
`SF-0601-008`, `SF-0602-001` through `SF-0602-008`, and `SF-0603-001` through
`SF-0603-008`, with supporting Section/Stack/Grid evidence under `SF-0502` and
`SF-0503`. The normative responsive modules remain Partial overall.

The slice authors breakpoint-specific Section padding; Stack direction, gap,
padding, and cross-axis alignment; Grid columns, gap, and padding; and
breakpoint visibility for authored Frame, Text, Section, Stack, and Grid
objects. It intentionally excludes custom breakpoint management, responsive
fills/box styles/typography/content/assets, comparison panes, orientation and
safe-area simulation, container queries, fluid typography, components,
alternate source sets, preview/export parity, and release acceptance.

## Canonical and resolution behavior

- Desktop remains the canonical base. Versioned
  `responsive.container.v1.<BreakpointID>.<field>` and
  `responsive.visibility.v1.<BreakpointID>.visible` properties exist only for
  explicitly authored Tablet/Mobile overrides. Reset removes the current
  override and reveals Desktop inheritance; the selected preset remains
  scene-local.
- Existing typed, identity-gated transaction paths validate document, page,
  revision, scene/generation, ordered selection, lifecycle, lock, availability,
  supported kind, and bounded value domains before one exact property batch.
  Undo/Redo restores exact property presence and identity. Draft strings remain
  scene-local and cancellation/stale input is neutral.
- One responsive structural resolver supplies Section/Stack/Grid child frames
  to immutable renderer, selection, hit testing, inline editing, Layers,
  guides, and accessibility projections. Hidden children do not consume
  Stack/Grid layout slots. Hiding a container suppresses its complete subtree
  without deleting, moving, or rewriting descendants.
- Hidden authored objects have no canvas pixels, hit target, inline editor,
  canvas accessibility object, selection outline, handle, or ghost badge.
  Layers retains stable NodeID/order and exposes a visible `Hidden here` state;
  a Layers-origin selection may inspect and restore/reset the object while
  canvas-origin selection remains unavailable.
- Bounded responsive-visibility diagnostics retain requirement IDs, operation,
  provenance, stable-ID digests, revisions, object count, duration, and typed
  outcome only. Authored content, paths, and secrets are excluded.

## Focused automated evidence

The focused acceptance selectors are:

1. `TransformModelTests/testResponsiveContainerAndVisibilityRegistriesSetResetValidateAndPreserveExactHistory`
2. `TransformModelTests/testResponsiveSectionAndGridOverridesResolveAndResetIndependently`
3. `SelectionModelTests/testHiddenBreakpointSelectionIsLayersInspectableWithoutCanvasChrome`
4. `CanvasRendererTests/testResponsiveContainerVisibilityExcludesHiddenChildAndReflowsSharedScene`
5. `CanvasRendererTests/testResponsiveVisibilityResolutionIsBoundedForStandardAndLargeFixtures`
6. `ProjectPackageTests/testContainerLayoutPersistsAcrossPackageReopenAndOwnedRecovery`
7. `SiteForgeLaunchTests/testResponsiveContainerLayoutAndBreakpointVisibilityJourney`
8. `SiteForgeLaunchTests/testStructuralLayoutControlsRemainReachableAtPracticalMinimum`

All seven focused non-UI selectors passed after one production recovery-message
correction, and the fresh-process responsive journey passed 1/1 after its
stable-NodeID Layers query was made explicit. The previously retained
`@MainActor` XCTest helper annotations compile in this Swift 6 UI target and
remain assertion-neutral. Final `./sf verify` passed 377 unit/integration plus
48 UI tests (425 total), zero failures, with repository, security, traceability,
architecture, migration, and evidence checks green on 2026-08-28.

## Visual review contract

Original-resolution actual-app attachments cover Desktop Stack/Grid base
layout, Tablet Stack/Grid overrides, Mobile Stack override, hidden Layers
inspection without canvas chrome, visibility restoration with Undo/Redo, and
the practical-minimum Inspector. Review checks a normal maximized window with
menu bar and Dock available; readable non-wrapping controls; explicit
inherited/authored provenance; clear grid/pasteboard/artboard boundaries;
bounded children; stable identity; aligned selection; upright text; and no
ghost, fixture, or debug content. Temporary XCTest attachment locations are
evidence only and are never committed.

Visual review passed all seven maximized-window states. It also found and
corrected stale breakpoint-operation feedback: Inspector success messages are
now scoped to the exact ordered selection and breakpoint that produced them,
without publishing extra state during a SwiftUI selection/preset update.
Desktop container provenance reads `Desktop base`; Tablet/Mobile inherited and
authored sources remain explicit.

## Compatibility note

The pre-existing local `@MainActor` annotations on nested XCTest UI helpers are
retained. They are a Swift 6/Xcode concurrency correction: the helpers call
main-actor-isolated `XCUIElement` APIs, compile cleanly in the UI target, and do
not change production behavior or test assertions.

## Explicit deferred scope

Custom breakpoint creation/deletion/reordering, overlapping user ranges,
responsive styles/typography/content/assets, responsive component behavior,
comparison panes, orientation/safe-area simulation, container queries, fluid
typography, alternate source sets, preview/export parity, cross-hardware and
OS-level accessibility matrices, and release acceptance remain deferred.
