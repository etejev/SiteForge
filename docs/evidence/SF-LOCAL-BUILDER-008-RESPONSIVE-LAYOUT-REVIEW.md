# SF-LOCAL-BUILDER-008 — Responsive layout review

Current focused acceptance supersedes the historical source-only hold below:
all 10 new code methods pass in the focused 007–011 group. The real review journey
passes, latest91.284s; six originals were inspected after correcting retained
raster artboard masking. Keep IN PROGRESS;
full verification is deferred, not waived. No commit/push/install or owner-data
change. [Current focused results](SF-LOCAL-BUILDER-007-011-FOCUSED-ACCEPTANCE.md).

IMPLEMENTED IN SOURCE — ACCEPTANCE DEFERRED; OWNER TEST APPROVAL REQUIRED.
2026-10-29. No build, test, check/lint script, collector, readiness/smoke/UI/
visual journey, app/browser launch or verification executed in this workflow.
No commit/push/install/sign/schedule. Do not ask to lift the renewed hold merely
because source is ready. Mandatory future ./sf verify and original-resolution
visual acceptance are deferred, not waived. No screenshots or runtime budgets
are claimed. All existing dirty007 work and result artifacts are preserved.

## Requirements and bounded meaning

- SF-0606-002/003/004/006: inspect measured horizontal Review context and jump
  to the exact ordinary canonical element at the sampled width; stale/blocked
  navigation is truthful, with native keyboard/accessibility controls.
- SF-0606-007/008: reuse cancellable actor preparation and revision-scoped
  adoption, cap presented rows with explicit totals and sanitized diagnostics.
- SF-0602-002/003/004/006: use007's actual inspection width and existing gate,
  references/ranges and central commit path, not another responsive cascade.
- SF-0402-002/003/006 and SF-0701-003/006: existing Layers selection and Layout
  Inspector remain the correction path, with exact identity and winning source.

Modules remain Partial. This derived inspection slice does NOT implement
SF-0606-001/005 canonical authored finding/suppression records, persistence or
version comparison. It adds no schema or ignored-finding store and waives no
normative requirement. Collisions, tap-target thresholds, text/glyph truncation,
responsive auto-fixes, component internals, viewport-fixed/sticky subtrees,
managed navigation chrome and browser/export runtime parity are not evaluated.
Intent cannot be inferred from a crossed rectangle: every result is typed Review,
not an automatic error. Ordinary overflow-visible parents are not implicit clips.

## Production source path

`SiteForge/WorkspaceShellModel.swift`:

- Existing ResponsiveBreakpointReviewWorker consumes the immutable document and
  active PageID. For Desktop1440/Tablet768/Mobile390 and the distinct current
  custom sample it invokes WorkspaceScenePreparationWorker, the production
  canvas/Preview scene resolver. There is no second frame/layout calculation.
- ResponsiveLayoutReviewPolicy consumes those resolved object frames and clip
  rectangles. It checks left/right artboard crossings and opted-in inherited
  container clipping. Structural Root, managed chrome, effectively hidden nodes,
  absent rendered nodes and viewport-dependent subtrees are excluded. Parent
  coordinate/clip semantics are world-space, not reconstructed local offsets.
- Finding IDs include document/revision/page/node, exact sampled width,
  reference/current discriminator, boundary and edge. Reports retain measured
  object/containing bounds and source via CanonicalSizingConstraints resolution.
  Traversal/edge order is deterministic. At most200 rows per sample are presented;
  the full total is retained and the user is directed to a smaller Layers scope.
- Existing comparison request/scope/generation cancellation and adoption guards
  prevent stale results from being exposed as current. Progress, Refresh, Cancel,
  empty/unsupported/error guidance and bounded sanitized diagnostic fields are
  explicit. No full-page work is executed from SwiftUI body.
- Review element requires membership in the currently adopted report plus the
  original document/page/revision. Draft/IME gates run before exact-width adoption.
  Existing WorkspaceEditCommitRequest gains an opt-in clean-editor preflight;
  participating editors reject dirty drafts without committing them first. The
  default Save/Preview/context commit behavior is unchanged. This prevents a
  blocked review from first creating history and then rejecting a stale revision.
  Pending navigation waits for that scene/generation before selecting the real
  NodeID through existing Layers selection. Changed selection/document/viewport
  invalidates pending navigation rather than selecting a coincidental ID.
- On adoption, existing Layout controls and sizing provenance open; the visible
  artboard intersection is revealed using the existing viewport policy, without
  widening the sample or moving authored coordinates. Fully off-page selection
  remains inspection-only, without fabricated canvas content. No suggested fix is
  automatically applied, and inspection/navigation creates no document Undo entry.
- Ordinary atomic edits and Undo/Redo invalidate the report's revision/context.
  Status does not present old geometry as current after selection/revision changes.
  Diagnostics retain fixed operation/failure category, sanitized document/page/node
  identity and duration only; names, text, paths and site content are not logged.

`SiteForge/WorkspaceShellView.swift`:

- Existing Compare sheet/cards gain measured Review rows, visible context,
  accessible Review element controls and Refresh/Cancel/status. Existing dark card
  and spacing rules are reused; no new main-toolbar audit panel or fake control.
- Review opens the existing Layout sizing section using its ScrollViewReader.
  Measured context sits with the real sizing controls; Inspector/canvas state is
  still scene-local. Labels wrap as readable prose, not clipped control labels.

`SiteForge/FillLayerListInspectorView.swift`: existing gradient numeric drafts
participate in the same clean-editor preflight; no styling behavior, registry or
canonical fill property changes. No new ADR is needed: ADR-0013/0014/0015/0020/
0025's shared resolution, scene ownership and existing command policies remain.

## Added test source — UNRUN, not passing evidence

`Tests/SiteForgeTests/CanvasViewportTests.swift`:

1. testResponsiveLayoutReviewDeterministicWidthMatrixAndScope
2. testResponsiveLayoutReviewUsesCanvasClipsAndAllowsVisibleOverflow
3. testResponsiveLayoutReviewConnectedChromeUsesSharedScene
4. testResponsiveLayoutReviewReportsFixedFluidAndOverrideWinnersWithoutAuthoredChanges
5. testResponsiveLayoutReviewStandardAndLargeSnapshotsHaveBoundedRows
6. testResponsiveLayoutReviewCancellationAndBoundedPresentation
7. testResponsiveLayoutReviewNavigatesExactNodeWidthWithoutHistoryOrPackageMutation
8. testResponsiveLayoutReviewRejectsStaleDraftIMEAndReplacement
9. testResponsiveLayoutReviewRefreshesAfterAtomicEditUndoRedo
10. testResponsiveLayoutReviewRedactsDiagnosticsAndRejectsForeignOrigin

Exact future selector prefix for these methods: `SiteForgeTests/CanvasViewportTests/`.

Matrix320/430/599.5/600/900/1023.5/1024/1440, selected/all-page scope,
connected Header/Section/Footer shared geometry, nested clips/visible overflow,
hidden/structural exclusions, fixed/fluid/explicit winner and100/10,000 object
fixtures are sourced. Scale/cancellation assertions are not runtime measurements.
007's rapid update/replacement source remains preserved; its later execution is
also deferred. No original assertion was removed to manufacture acceptance.

`Tests/SiteForgeUITests/SiteForgeLaunchTests.swift`:
`SiteForgeUITests/SiteForgeLaunchTests/testResponsiveLayoutReviewJumpsToExactElementAndRefreshesAfterFixJourney`.
Later fresh-process normal-window journey uses real Width, Compare, Review element,
Layers, existing X control and native Undo/Redo. It requests six named screenshots:
Desktop fixed Frame; custom Mobile measured boundary; exact-node Layout/provenance;
atomic Mobile fix refreshed; Undo review restored; Redo corrected geometry.
NONE were captured or inspected in this source-only workflow. Comparison helpers
re-query/reveal genuine lazy card controls before asserting/interacting;007 and
the existing comparison journey retain their identity/provenance assertions.

## Prerequisite007 fixture correction and real historical results

Build succeeded in the interrupted prior authorized turn. Initial focused result
3133a465-4a20-4bbe-83ee-f0ebb348b383 ran9:3 passed/6 failed. Complete structural
default properties and ApplicationOwnedTestFixture recovery paths were then fixed;
d3dafe44-8b7d-4604-a84c-aa7b7657dc6d ran6:4 passed/2 failed. The remaining fixtures
awaited an initial scene without a real viewport event. Latest SOURCE adds resize
before their text/selection commands. This correction is NOT rerun or verified;
dependent assertion failures are not declared fixed from inspection alone.
Both xcresults/logs remain retained; no test process remains.007's UI is UNRUN.
The earlier fully accepted ba342938 936-pass receipt validates only its baseline,
not007 or008 source. See the separate007 evidence for exact historical artifacts.

## Review and next acceptance boundary

Read-only source/API/diff review only; no tools were run to compile, validate,
lint, test or visually accept these changes. After separate owner approval,
compile and execute only the affected exact selectors, inspect original normal/
compact screenshots and fix real defects before mandatory full verification.
Do not claim DONE, green, runtime parity, scale budgets or owner-installed delivery.
No next workflow is dispatched. OD-018/019 and Aurora/Dark Flow revision245 with
its native45-degree stops0#160D2B/50#6A36C8/100#C52E53 remain untouched, as do owner
resources, recovery, ordinary installed app and coordinator/obsolete art files.
