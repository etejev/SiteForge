# SF-AUTHORING-101 — Responsive breakpoint comparison

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**

Requirements: bounded `SF-0601-003/006`, `SF-0602-002/003/004/006/008`, and
`SF-0603-002/003/006`.

## Reconciled existing coverage

SiteForge already owns stable Desktop, Tablet, and Mobile identities, strict
non-overlapping ranges, breakpoint geometry/container/visibility properties,
authored/inherited provenance, set/reset transactions, immutable scene
adoption, package/recovery/history behavior, responsive static-layout rules,
and a maximized native viewport preset control. Pages already support stable
PageID create/rename/route/duplicate/delete/reorder operations, protected Home
and Not Found roles, link-impact reporting, and deterministic static routes.
Button and Link already author PageID/Section targets and preserve missing
targets for repair. This slice does not duplicate any of those systems.

## Delivered source contract

- A visible **Compare** viewport action and **Compare Breakpoints…** View-menu
  command open one native, scrollable comparison sheet.
- The sheet reviews either the ordered current selection or all positioned
  objects on the active page. For Desktop, Tablet, and Mobile it reports the
  standard viewport width, visible/total objects, geometry/container/
  visibility override counts, differences from Desktop, and the primary
  object's resolved frame and provenance.
- `ResponsiveBreakpointReviewPolicy` calls the existing structural geometry,
  effective visibility, geometry, container-layout, and visibility resolvers.
  It stores no document state and cannot compile a command.
- Review actions switch only `WorkspaceShellState.viewportPreset`; they do not
  author, copy, reset, or normalize a breakpoint value. Stable PageID/NodeID,
  selection, document revision, history, and packages remain unchanged.
- Cards have semantic labels/values and adapt their fact row vertically when
  horizontal space is constrained. The sheet remains independently scrollable
  at the practical minimum window size.

## Added unrun evidence source

- `TransformModelTests.testResponsiveBreakpointReviewProjectsResolvedDifferencesWithoutMutation`
- `SiteForgeLaunchTests.testResponsiveBreakpointComparisonReviewsLiveSelectionWithoutMutationJourney`

No build, test, UI automation, screenshot review, verification, commit, or
push ran under the owner pause. These are test sources, not passing evidence.

## Deferred scope

Freeform/custom breakpoint management, simultaneous live canvases, orientation
or safe-area simulation, fluid typography, container queries, responsive
styles/content/assets, component responsiveness, broad preview/export/browser
parity, performance/accessibility matrices, and release acceptance remain
deferred. The comparison sheet intentionally reviews existing deterministic
presets rather than introducing canonical comparison state.
