# SF-AUTHORING-016 — Responsive Geometry Evidence

Date: 2026-08-28

## Bounded contract

This milestone supplies bounded production evidence for `SF-0601-001` through
`SF-0601-008` and `SF-0602-001` through `SF-0602-008`. It implements fixed
Desktop, Tablet, and Mobile breakpoint identities, deterministic width ranges,
Desktop-base inheritance, and per-node X/Y/Width/Height overrides for Frame,
Text, Section, Stack, and Grid. Both normative modules remain Partial overall.

Scene viewport selection, pan, zoom, and fit state remain noncanonical. Custom
breakpoint management, responsive style/typography/content/visibility,
comparison panes, orientation and safe-area simulation, container queries,
fluid typography, component responsiveness, preview/export parity, performance
budgets, and release acceptance are excluded.

## Canonical and transaction behavior

- Stable typed breakpoint IDs resolve non-overlapping ranges: Mobile below 600
  points, Tablet from 600 through 1023 points, and Desktop at 1024 points and
  wider. The same resolver accepts arbitrary finite viewport widths.
- `responsive.geometry.v1.<breakpoint-id>.<field>` is the sole override
  namespace. Desktop continues to own the existing base `layout.*` values.
- Layout drafts remain scene-local. The identity-gated Geometry Inspector
  registry validates document, page, revision, scene, renderer, selection,
  lifecycle, node kind, visibility, lock, and finite bounds before compiling
  one exact set/remove transaction. Reset removes properties and reveals the
  next valid Desktop source.
- Scene preparation resolves structural/base layout and then applies the
  selected breakpoint snapshot once. Render objects, selection targets,
  hit-testing, accessibility frames, and inline text placement consume that
  immutable geometry. Viewport clipping does not make a retained active-page
  selection canonically uneditable or fabricate an offscreen hit target.
- Current schema-v4 packages need no incompatible schema bump because their
  versioned property map is extensible. Strict validation rejects unknown
  breakpoint/field keys, unsupported node kinds, malformed values, nonfinite
  numbers, dimensions below one, and out-of-range geometry. Older packages
  omit the namespace and deterministically inherit Desktop values.

## Focused automated evidence

The following exact selectors passed with zero failures:

1. `TransformModelTests/testResponsiveGeometryOverridesResolveAtomicallyResetAndRoundTrip`
2. `TransformModelTests/testResponsiveGeometryRejectsStaleCancelledAndPreservesIndependentBreakpoints`
3. `CanvasRendererTests/testResponsiveProjectionSharesResolvedGeometryWithRendererSelectionAndAccessibility`
4. `ProjectPackageTests/testResponsiveGeometryPersistsAcrossPackageReopenAndOwnedRecovery`
5. `SiteForgeLaunchTests/testResponsiveBreakpointGeometryAuthoringUndoResetAndAccessibilityJourney`

The model/package group passed 4/4. The fresh-process actual-app journey passed
1/1. It exercises normal maximized-window presentation, Desktop inheritance,
independent Tablet and Mobile keyboard edits, live renderer/selection adoption,
visible source labels, Reset Override, Undo/Redo, and accessibility values.

Final milestone verification passed 367 unit/integration plus 45 UI tests (412
total), zero failures. Repository security, traceability, architecture,
migration, evidence, fixture, build, and diff checks all passed.

## Visual review

Original-resolution attachments were exported from the passing UI result to
`/tmp/siteforge-responsive-016-final.DsIsoZ/` for local review. The reviewed
states are Desktop base, Tablet authored X, Mobile authored X/Width, Mobile
reset to inheritance, and responsive Undo/Redo.

The maximized window retains the menu bar and Dock, the breakpoint/zoom/Fit/Grid
header remains readable, navigator and Inspector labels do not wrap, artboard
and grid gutters remain distinct, authored Frame pixels and selection chrome
coincide, and the Inspector clearly distinguishes inherited and authored field
sources. Mobile overrides visibly place the same stable Frame inside the Mobile
artboard; reset truthfully returns it to its unchanged Desktop geometry and
off-artboard status without ghost chrome or responsive reflow.

Temporary result bundles and screenshots are evidence locations only and are
not repository artifacts.
