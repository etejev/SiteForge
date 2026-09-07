# SF-AUTHORING-022 focused implementation evidence

Status: LOCALLY VERIFIED; hosted checkpoint acceptance pending.
Requirements: bounded SF-0901-001–008 and SF-0905-003–005;
the normative modules remain Partial.

## Authoritative final local gate — 2026-09-07

`./sf verify` passed 413 unit/integration and 56 UI tests (469 total), zero
failures. Repository, security, traceability, architecture, migration and
evidence checks passed. Both component journeys passed in this integrated run:
compact overflow/cancellation in 25.941 seconds and create/link/edit/detach/
reopen in 114.137 seconds. The repaired page-management journey passed in
120.417 seconds. No SiteForge test app or runner remained after completion.
Earlier failures and authentication incidents below are historical evidence,
not the current acceptance status. Hosted status follows the pushed SHA.

Hosted run `34164363270` for `e20b6d2` failed during UI-test compilation under
Xcode 26.6, before executing XCTest. Two nested MainActor helpers captured the
non-Sendable XCTestCase; the newer local compiler accepted that capture. They
now use the existing actor-isolated instance-helper pattern, passing the live
application explicitly. No application behavior, wait, or assertion changed.
The exact affected journey subsequently passed 1/1, zero failures. The prior
469-test product gate remains authoritative; this test-helper-only correction
does not trigger another unchanged local full suite. Hosted compilation and
verification must pass for the corrective SHA before acceptance.

Narrow-display review also identified that right-aligning a 1100-point window
on a 1024-point display can put the leading Components overflow off-screen.
The component pointer helper now reveals the actual control by dragging the
native title bar, then re-queries and requires enabled/hittable in-display
bounds. The explicitly constrained navigator journey uses leading placement.
Production minimum sizing and generic launch policy are unchanged. Both exact
journeys passed together 2/2; the updated compact overflow/cancellation images
were inspected at original resolution and retain readable controls, centered
artboard and aligned Frame selection. The eight attachments remain in the
focused result bundle rather than in source control.

## Observed corrections

Hosted run `34165188350` passed all 413 non-UI tests and 54/56 UI tests.
The reopened component journey clicked Pages beyond the display's leading
edge; it now uses the same live native pointer-reveal helper as earlier steps.
The Pages journey completed deletion, but its 10-point toolbar-reveal drag
left the native window unchanged. The retained recording confirms that the
dialog closes and the application is enabled again: this is not failed
canonical deletion. Both helpers now align the complete 1100-point window
to the required display edge rather than applying a tiny control-only delta.
The new deterministic 1024-point display regression retains full control
containment and the production minimum width. No pointer, identity, history
or persistence assertion was removed.

That hosted gate reached test completion approximately 39 minutes after job
start, leaving insufficient room in the 40-minute job for cleanup and retained
failure artifacts. The orchestration ceiling is now 50 minutes; XCTest waits,
application performance budgets and assertions are unchanged. This headroom
does not classify the two failed assertions as infrastructure success.

The correction's focused group passed 3/3, zero failures:
`testNarrowDisplayPointerAlignmentPreservesWindowAndRevealsBothEdges`
(0.086 seconds), `testLocalComponentsCreateLinkEditDetachAndReopenJourney`
(96.661 seconds), and `testStaticPageManagementRoutesHistoryAndReopenJourney`
(125.259 seconds). Retained reopened-page/component images show Saved,
upright content and bounded artboard/grid composition without serialized
selection. Repository checks and whitespace checks pass; no runner remains.
The earlier 469-test full product gate remains authoritative locally; the
additional geometry selector raises the next hosted inventory to 470 tests.

The pointer boundary additionally waits for the foreground application and
enabled live control before starting a title-bar gesture. The hosted recording shows
the delete sheet transitioning from disabled content to an enabled workspace;
canonical row removal alone is not a native sheet-dismissal readiness signal.
The guard uses the existing bounded wait and captures the live hierarchy on
failure, without retrying gestures or bypassing the visible control.
An exploratory Window AXEnabled guard failed both focused journeys before
interaction: macOS reports the non-control Application/Window containers as
Disabled even while their genuine controls are enabled and usable. The guard
therefore uses application activation plus the actual control's enabled state,
not a container attribute. Those exploratory failures are not passing evidence.
The corrected active-app/control guard passed both affected journeys 2/2:
component create/link/edit/detach/reopen in 114.927 seconds and page management
in 131.555 seconds. All existing pointer, history and persistence assertions
remain intact. No production behavior changed.

- Definition editing uses the active canonical graph for insertion and
  selection context, without exposing definitions as website pages.
- The definition breadcrumb has an explicit accessibility container so its
  identifier does not replace the Exit Definition button identifier. It
  composites above native canvas backing layers, as viewport controls do.
- Linked instances expose inherited-appearance information and native Edit
  Definition / Detach actions rather than misleading empty style fields.
- Detachment materializes supported breakpoint child geometry and preserves
  instance-owned geometry property identity. Undo restores the exact graph.

## Focused results

All five selectors in `SiteForgeTests/CommandKernelTests` passed:

- `testComponentCreateResolveDetachAndExactHistory`
- `testComponentInstancesPropagateAcrossPagesAndSafeDeleteRestoresExactGraphs`
- `testComponentInvalidCancelledAndStaleIdentityRemainNeutral`
- `testComponentDetachPreservesEveryBreakpointAndInstancePropertyIdentity`
- `testComponentDefinitionContextUsesAuthoringGraphWithoutWebsiteNavigation`

The first four ran as a 4/4 focused group; the final context test passed 1/1
after adding real definition-context insertion coverage.

Native Xcode selector
`SiteForgeUITests/SiteForgeLaunchTests/testLocalComponentsCreateLinkEditDetachAndReopenJourney`
passed 1/1, zero failures, 96.221 seconds after visual corrections. It uses
real menus, Components navigation, Inspector fill editing, cross-page
insertion, definition return, detach, keyboard undo/redo, native Save and a
fresh-process package reopen. No direct canonical UI-test mutation was added.

Five original-resolution window attachments were inspected:

- SF-AUTHORING-022 original linked instance
- SF-AUTHORING-022 definition editing
- SF-AUTHORING-022 propagated second instance
- SF-AUTHORING-022 detached undo redo
- SF-AUTHORING-022 reopened detached instance

The corrected breadcrumb and linked Inspector are readable; Frame and Text
remain upright and aligned with selection. Reopen shows Saved and no
serialized editor selection. The existing horizontal tab strip uses its
native overflow menu; the trailing Components label is partially clipped
until scrolled. Compact component-specific visual acceptance remains pending.

Repository hygiene/security/traceability/architecture/evidence checks passed,
as did `git diff --check`. No broad test gate was run for this focused step.

## Remaining acceptance

Additional completion-boundary checks passed independently:

- `CommandKernelTests/testComponentExpansionBudgetCancellationAndCollisionAreMutationNeutral`
- `CommandKernelTests/testComponentSchemaRejectsHistoricalSmugglingCyclesAndPreservesMissingReferences`
- `ProjectResourceTests/testComponentDefinitionResourcesSurviveLinkedDuplicationSaveAndRecovery`

The first two passed together (2/2). The resource test initially rejected an
incomplete test Image before component mutation. Its fixture now includes the
same required fit, focal-point, alt and decorative defaults as production
insertion, and validates the source document first. The corrected focused run
passed 1/1, proving referenced original bytes survive linked page duplication,
durable save/reopen and recovery. Production validation was not relaxed.

Additional placement/cycle checks passed 2/2. Placement now uses the visible
parent/artboard intersection without changing definition geometry. The cycle
test uses unique IDs and asserts incompatible child ownership explicitly.
Historical migration checks passed 3/3: immutable schema-one empty package,
schema-four legacy-surface package and schema-five control fixture. The package
checks assert that no component definitions are synthesized. Expansion counting
precedes placement and output allocation; resource/recovery and missing-reference
serialization are covered above.

Revised safe-delete cancellation and a new constrained minimum-window
Components overflow/cancellation journey remain unaccepted. Native Xcode
attempt `Test-SiteForge-2026.09.07_15-48-04--0400.xcresult` failed before a test
body: “The test runner failed to initialize for UI testing” / “Timed out while
enabling automation mode.” It produced no screenshots or product assertions.
The old green navigator row was stale; the xcresult is authoritative.

Startup diagnosis is confirmed by the scoped testmanagerd system log: the
runner requested automation at 15:48:33, the writer daemon required
authentication, and LocalAuthentication requested “Enable UI Automation”.
The active console owner and selected Xcode installation were consistent;
there was no remaining SiteForge runner or app. Owner authentication is needed
before another unattended attempt. No privacy/security state was changed and
no unrelated process was terminated.

Headless architecture verification exposed a renderer dependency in the new
component budget check. The unchanged 20,000-node limit now lives in the shared
model policy; renderer preparation consumes it, and expansion has its own typed
errors. Neither headless slice imports the other's implementation. Repository
checks and the final exact budget/cancellation/collision test (1/1) passed after
this correction. Native build-for-testing also passed for
the new UI selectors. Next: run
`testLocalComponentsConstrainedMinimumOverflowAndCancellationJourney` and
`testLocalComponentsCreateLinkEditDetachAndReopenJourney` once native automation
is available, inspect original-resolution images, then run the integrated final
gate and authorized checkpoint/hosted sequence. Do not mark DONE from the
focused counts or preceding UI run.

Nested component authoring, variants, slots, per-child overrides, remote
libraries, preview/export/runtime and release acceptance remain excluded.

## Final focused visual acceptance — 2026-09-07

Owner authentication subsequently enabled native XCTest. The constrained
overflow/cancellation journey passed 1/1. The main journey exposed an ambiguous
Cancel locator; the genuine confirmation Cancel now has the production
`components.delete.cancel` accessibility identifier. Its exact rerun passed
1/1 (125.877 seconds), retaining all identity, cancellation and persistence
assertions. The preceding two-test group was not a clean pass.

Six final main-journey images were reviewed: original linked instance, safe
delete confirmation, definition editing, propagated second instance, detached
undo/redo and reopened detached instance. The two compact overflow/cancellation
images were also reviewed. Text is upright, surfaces and selection coincide,
definition context and inherited appearance are readable, and reopen has no
serialized selection. The existing horizontal navigator overflow remains the
route to trailing labels at narrow widths; it is visible and operable.

The final main result contains one internal QoS runtime warning. It contains no
failed product assertion; do not describe runtime diagnostics as warning-free.
Integrated final verification and hosted acceptance remain pending.

The first integrated gate built successfully and passed repository checks, but
413 non-UI tests reported five assertions in two pre-component applicability
tests. Both still used Component as an unsupported kind. Coverage now explicitly
includes Component geometry and retains no-target/partial-subset assertions
using omitted geometry instead; visibility likewise tests a node without a
complete frame. The already-failed gate's remaining UI run was interrupted
before completion to avoid redundant unrelated testing. Its exact runner/app
processes exited. This attempt is not a passing full gate.
Both corrected exact selectors subsequently passed 2/2, zero failures:
`testGeometryInspectorSupportsOnlyDeclaredNodeKindsAndRedactsDiagnostics` and
`testResponsiveContainerAndVisibilityRegistriesSetResetValidateAndPreserveExactHistory`.
