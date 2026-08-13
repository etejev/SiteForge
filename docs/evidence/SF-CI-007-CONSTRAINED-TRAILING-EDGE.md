# SF-CI-007 Constrained Trailing-Edge Evidence

Date: 2026-08-13

Requirements: bounded regression evidence for `SF-0201-006`, `SF-0201-008`, `SF-0203-006`, `SF-0406-006`, and `SF-1902-008`.

## Hosted root cause

GitHub Actions `31668705143` passed the repository checks and all 301 unit/integration tests, then failed four pointer journeys after `ae7dfc7` reduced an explicitly constrained 1100-point workspace window to the hosted display width. The affected right-edge Preview, Inspector, Undo/Redo, and bottom status paths are intentionally real pointer coverage: they require a full-width window whose leading edge can extend off a narrower display while the requested trailing and bottom edges remain visible.

## Corrected policy

- `WorkspaceMetrics.effectiveMinimumWindowSize` returns 1100 by 1 only for an explicitly named constrained UI-test placement. The product's 1100 by 700 minimum remains unchanged.
- `uiTestWindowFrame` retains the requested width and fits height only within both vertical safe edges. Right alignment is `visibleFrame.maxX - windowFrame.width - inset`; bottom alignment is `visibleFrame.minY + inset`.
- The text-status pointer journey requests both right and bottom placement, exposing the real Commit and Cancel controls at the safe trailing/bottom edge.
- `sf` writes XCTest result bundles and their matching logs to an explicit `SITEFORGE_TEST_RESULTS_ROOT` when supplied, otherwise `$RUNNER_TEMP/SiteForge/TestResults` in Actions, otherwise the existing local TMPDIR root. CI uploads both artifact types on failure.

## Verified local results

Environment: local macOS arm64 Xcode-beta test destination.

- `WorkspaceMaterialPolicyTests.testConstrainedDisplayPlacementPreservesProductionMetricsAndExposesEveryRequestedEdge` passed, covering left/top, right/top, left/bottom, and right/bottom; right/bottom retains 1100 points, exposes the trailing edge, and fits vertically.
- `./sf test half` passed 301 unit/integration tests.
- A project-root override test wrote both a matching `.xcresult` and `.log` to a temporary override root.
- Each of the four affected journeys passed in a fresh local application process: status Commit/Cancel, Inspector destinations, Preview pointer presentation, and toolbar Undo/Redo pointer interaction.
- Hosted run `31671468329` then proved the lower window edge alone was insufficient: its real Commit button extended below the test-safe inset. The four-placement policy reserves both vertical insets. Hosted run `31673619911` showed that the welcome surface still imposed a 700-point SwiftUI content minimum across the welcome-to-workspace transition, preventing the constrained AppKit frame from taking effect. The launch surface now consumes the same explicit constrained Debug/UI-test minimum policy as the workspace; production and generic UI tests retain 1100×700.
- Complete local `./sf verify` passed on 2026-08-13: repository/security/traceability/architecture/migration/evidence checks, 303 unit/integration tests, and 33 UI tests. Hosted Actions `31675543875` then passed the same Verify workflow at `f449813`.

No production window behavior, Release composition, or command availability was changed by this correction.
