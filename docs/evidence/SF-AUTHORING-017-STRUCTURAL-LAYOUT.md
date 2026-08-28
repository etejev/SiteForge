# SF-AUTHORING-017 — Structural Layout Controls Evidence

Date: 2026-08-28

## Bounded contract

This milestone supplies bounded production evidence for `SF-0502-001` through
`SF-0502-008`, `SF-0503-001` through `SF-0503-008`, and the uniform structural
padding/gap portion of `SF-0506-001` through `SF-0506-008`. These normative
modules remain Partial overall.

The slice authors uniform Section padding; Stack direction, uniform padding,
gap, and cross-axis alignment; and Grid column count, uniform padding, and gap.
It intentionally excludes per-side/logical padding, separate row/column gaps,
wrapping, advanced distribution, flex growth/basis, explicit tracks, spans,
minmax/fractional tracks, named areas, non-row-major flow, responsive
container-layout overrides, preview/export parity, and release acceptance.

## Canonical and transaction behavior

- Existing schema-v4 `layout.padding`, `layout.gap`, `layout.axis`,
  `layout.align`, and `layout.grid.columns` properties remain the only canonical
  source. No parallel Inspector or renderer model was introduced.
- One typed `ContainerLayoutCommandRegistry` validates document, page,
  revision, renderer scene/generation, ordered selection, lifecycle, lock,
  visibility, availability, node kind, and finite bounded values before
  compiling one atomic property batch. Reset restores the canonical v1 default
  with `.defaulted` provenance rather than writing an authored lookalike.
- Existing stable property and NodeIDs survive set/reset, exact Undo/Redo,
  deterministic serialization, package reopen, and owned recovery. Inspector
  drafts remain scene-local and Escape leaves committed content unchanged.
- A single depth-first structural resolver computes Section, Stack, and Grid
  child frames. Immutable render objects, selection targets, hit testing,
  accessibility frames, Layers identity, and Inspector state consume that same
  result. Direction, spacing, alignment/stretch, and column changes never
  reorder or replace child identities. Oversized insertion defaults are fitted
  proportionally into the bounded content box while canonical child geometry
  remains unchanged, preventing authored surfaces from escaping Stack/Grid
  bounds.
- Bounded diagnostics retain requirement IDs, operation type, provenance,
  stable-ID digests, revisions, count, and typed outcome only. Authored values,
  paths, and secrets are excluded.

## Focused automated evidence

The following exact non-UI selectors passed with zero failures (5/5):

1. `TransformModelTests/testContainerLayoutRegistryValidatesMixesResetsAndPreservesExactHistory`
2. `InsertionModelTests/testStructuralResolverAppliesSectionPaddingStackAxisAlignmentAndSparseGrid`
3. `InsertionModelTests/testStructuralResolverFitsDefaultChildrenInsideBoundedContainers`
4. `ProjectPackageTests/testContainerLayoutPersistsAcrossPackageReopenAndOwnedRecovery`
5. `CanvasRendererTests/testContainerLayoutProjectionSharesResolvedChildGeometryAcrossCanvasSystems`

The actual-app selectors passed 2/2 with zero failures:

1. `SiteForgeLaunchTests/testStructuralLayoutInspectorReflowsSectionStackAndGridJourney`
2. `SiteForgeLaunchTests/testStructuralLayoutControlsRemainReachableAtPracticalMinimum`

They exercise a true blank project, visible Elements and Insert-menu actions,
Section child padding, vertical/horizontal Stack layout, gap/alignment, Grid
column changes with a sparse final row, Reset, Undo/Redo, accessible values,
and normal/practical-minimum Inspector reachability. Final result and milestone
gate totals are recorded below.

`./sf test half` passed 371/371 unit/integration tests. The repository's
changed-test mapper selected the full scope after the shared resolver change;
that suite passed 419/419 tests with zero failures. The final
documentation-inclusive `./sf verify` passed 372 unit/integration plus 47 UI
tests (419 total), zero failures, on 2026-08-28. Repository security,
traceability, architecture, migration/evidence, fixture-hygiene, and diff checks
all passed.

## Visual review contract

Original-resolution actual-app XCTest attachments cover Section padding, Stack
vertical and horizontal states, Stack gap/alignment, Grid two-column sparse and
three-column states, Reset/Undo/Redo, and the practical-minimum Inspector. The
review checks the normal maximized window, menu bar/Dock availability, readable
non-wrapping controls, clear page/grid/pasteboard hierarchy, stable child
identity/order, aligned selection and authored pixels, upright text, and no
ghost/debug content. The first visual pass found oversized default children
escaping bounded Stack/Grid surfaces; the shared resolver correction and
focused regression closed that defect. The final screenshots show bounded
vertical/horizontal Stack and two-/three-column Grid states with readable,
non-wrapping controls. Temporary screenshot/result locations are evidence only
and are never committed.

## Explicit deferred scope

Responsive container-layout overrides are deferred to a separate bounded
milestone: SF-AUTHORING-016's responsive resolver currently owns geometry
fields only, so this slice does not create a second cascade for container
properties. Custom breakpoints, responsive content/visibility, component
layout, container queries, advanced Stack/Grid semantics, preview/export
parity, cross-hardware performance acceptance, OS-level accessibility settings,
and release acceptance remain deferred.
