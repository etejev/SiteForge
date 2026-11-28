# Lane V04 verification review — batches 09–11 (2026-11-26)

Owner tag `lane-V04`. Verification was by careful reading on the Windows PC (no Swift toolchain). Nothing was built or
run; every item below is **unverified until Codex builds and runs the listed selectors**.

## Scope

- Batch 09 — container queries, SF-0605, ADR-0031.
- Batch 10 — responsive audit, SF-0606, ADR-0032.
- Batch 11 — relative multi-object geometry edits, SF-0703.
- Diff: RP-2026-11-26-07 → RP-2026-11-26-08 (shared with batches 07–14; hunks attributed by symbol), then the
  current code of every changed region and its declarations/call sites.
- Files read: `SiteForge/DocumentModel.swift` (`CanonicalContainerQueries`, `CanonicalContainerQueryRule`,
  `CanonicalResponsiveAuditSuppression`, schema-27 gate, page validation, `invalidContainerQueryState`),
  `SiteForge/InsertionModel.swift` (`ContainerQueryFinding`, `ContainerQueryEvaluation`, `evaluated`, `setting`,
  `cssDeclaration`), `SiteForge/CanvasRendererCore.swift` (`StaticContainerQueryOutputEmitter`, `ResponsiveAudit*`,
  `CanonicalResponsiveAudit`, stylesheet assembly), `SiteForge/TransformModel.swift` (`ContainerQueryCommandRegistry`,
  `ResponsiveAuditSuppressionRegistry`, `GeometryInspectorRelativeInput`, `GeometryInspectorCommandRegistry.prepare`),
  `SiteForge/WorkspaceShellModel.swift` (scene hook, `ResponsiveAuditRunner`, workspace members,
  `commitGeometryInspectorValue`), `SiteForge/WorkspaceShellView.swift` (`ContainerQueryInspectorView`,
  `ContainerQueryRuleView`, `ResponsiveAuditSection`, `ResponsiveAuditFindingRow`, geometry field),
  `SiteForge/ClipboardTransfer.swift` (version 8), all batch 09–11 tests and both UI journeys, ADR-0031/0032.
- Prior review: none (batches 09–11 were never reviewed). Mid-run input from lane V03 (SF-0605-008 diagnostics with
  hashed IDs) is incorporated as fix 6.

## Fixes made

| # | File | Symbol | Defect | Fix | Why |
|---|---|---|---|---|---|
| 1 | `SiteForge/CanvasRendererCore.swift` | `CanonicalResponsiveAudit.findings` (new nested `shownHorizontalSpan`) | Every scene object's `clipRect` starts at the page bounds (`inheritedContentClip` starts from `viewport.contentBounds`), and overflow intersected the frame with it first, so overflow was **never** reported; `testResponsiveAuditReportsEachKindAtItsExactWidthAndHonorsSuppression` and the UI journey would fail. A fully clipped object also fell back to its whole frame. | Overflow uses the frame narrowed only by ancestors that clip content (`DesignBoxStyleCommandRegistry.contentBoxKinds` + `clipsContent`, frames from the drawn objects), then compares with the page sides; nothing shown → no finding. | SF-0606-003 correctness; test failure. |
| 2 | `SiteForge/CanvasRendererCore.swift` | `StaticContainerQueryOutputEmitter.emit` | A rule hiding text/button/link emitted `[sel] { display: none; }`, which loses to `[sel][data-siteforge-node] { display:flex }` and `[sel]:is(a,button) { display:flex }` from typography output, so the hide never worked in export. | Hide goes into its own block `@container … { [sel][data-siteforge-node] { display: none; } }`; other settings stay in the plain block; show stays plain `display: block;`. | SF-0605-003 / SF-1204-003 canvas–export agreement. |
| 3 | `SiteForge/WorkspaceShellModel.swift` | `runResponsiveAudit` | The generic `catch` had no cancellation guard: a superseded/cancelled run ending with `WorkspaceScenePreparationError.cancelled` cleared `isRunningResponsiveAudit` and overwrote the status of the run that replaced it (or of Cancel). | `guard !Task.isCancelled, let self else { return }` in the generic catch. | SF-0606-004 interruption. |
| 4 | `SiteForge/WorkspaceShellModel.swift` | `LocalPreviewRuntimeCompiler` doc comment | Batch 10 inserted `ResponsiveAuditRunner` between the actor and its doc comment, so the Preview comment documented the runner. | Moved the comment back above `actor LocalPreviewRuntimeCompiler`. | Comments must describe their symbol. |
| 5 | `SiteForge/WorkspaceShellView.swift` | `ContainerQueryRuleView`, new `ContainerQueryValueRow`, new `addSettingMenu` | Partial feature: a rule's values could only be removed. A new rule starts from the object's current value, so only Visibility rules could do anything; no way to add a second setting. | Each setting row edits its value in place (Hidden/Shown picker or number field; Return commits, Escape restores); "Add Setting" menu adds an unused queryable setting. Both through `ContainerQueryCommandRegistry` (one transaction, same refusals). | SF-0605-002 create/modify; finish partial feature. |
| 6 | `SiteForge/WorkspaceShellModel.swift` | new `ResponsiveAuthoringDiagnostic` (`category(for:)`), `lastResponsiveAuthoringDiagnostic`, `recordResponsiveAuthoringDiagnostic`; calls in `performContainerQueryEdit`, `runResponsiveAudit`, `cancelResponsiveAudit`, `setResponsiveAuditFinding` | No diagnostics: `ContainerQueryEdit.diagnosticOperation` was declared and never used; the audit had none (also reported by lane V03). | Sanitized record per operation: requirement ID, operation, identities hashed with `DiagnosticStableIdentifier.sanitize(_, domain: .document, kind: "responsive-target")` (V03 pattern), finding count, duration, closed failure category. | SF-0605-008, SF-0606-008. |
| 7 | `SiteForge/WorkspaceShellModel.swift` | `containerQueryEvaluation` | The Inspector expanded every component of the page on the main actor once per revision even when no rule existed anywhere. | Return (and cache) `.empty` when no page or definition has rules. | SF-0605-007 main-actor responsiveness. |
| 8 | `SiteForge/WorkspaceShellModel.swift` | `commitGeometryInspectorValue` | Relative edits skip objects whose own result is out of range, but the announcement called them "unsupported selections". | Relative edits say "N unchanged (out of range or not editable)". | SF-0703-004 specific recovery text. |
| 9 | ADR-0031, ADR-0032 | Consequences | ADRs did not record the hide specificity, the overflow measurement rule, diagnostics or the content-box question. | Added consequence bullets; new ADR-0143. | Dev-doc coverage. |

## Features finished

- Container-query rule value editing and "Add Setting" (SF-0605-002) — ADR-0143.
- Container-query and responsive-audit diagnostics (SF-0605-008, SF-0606-008) — ADR-0143.
- Finished up to a decision boundary: container width basis for padded/bordered containers — OD-143 (proposed) in
  ADR-0143 (see Remaining work).

## Requirement table

| Requirement | Status | Evidence |
|---|---|---|
| SF-0605-001 Authoritative state | Met | `CanonicalContainerQueries.rules(on:)`/`validate` strict, `ContainerQueryRuleID`, schema-27 gate; `CommandKernelTests/testContainerQueriesUseOneStrictEncodingAndRequireSchemaTwentySeven` |
| SF-0605-002 Create and modify | Met (after fix 5) | `ContainerQueryCommandRegistry`, `ContainerQueryInspectorView`, `ContainerQueryValueRow`; `testContainerQueryEditsAreOneUndoableTransactionEachWithSpecificRefusals`; UI journey extended |
| SF-0605-003 Resolution rules | Partial | Ordered, nearest-first, later wins, statuses/winners shown (`testContainerQueryEvaluationIsOrderedNearestFirstAndBeatsBreakpointValues`); export hide fixed (fix 2). Open: content-box vs frame width (OD-143) |
| SF-0605-004 Failure and recovery | Met | Specific refusals, damaged-rule refusal, unknown names kept and reported, Hug fallback (`testContainerQueriesFollowEachCopysContainerOnCanvasPreviewAndExport`) |
| SF-0605-005 History and persistence | Met | One transaction per edit, undo/redo, clipboard v8, schema 27 |
| SF-0605-006 Accessible operation | Met | Labels/identifiers on every control, Return/Escape, announcements; registry-only edits |
| SF-0605-007 Performance and scale | Met | `testContainerQueriesStayWithinBoundsOnStandardLargeAndStressFixtures`; off-main scene evaluation; fix 7 |
| SF-0605-008 Diagnostics and tests | Met (after fix 6) | `ResponsiveAuthoringDiagnostic`; `testContainerQueryAndAuditDiagnosticsAreSanitizedAndCategorized` |
| SF-0606-001 Authoritative state | Met | `CanonicalResponsiveAuditSuppression` strict; stable `ResponsiveAuditFinding.id`; `testResponsiveAuditSuppressionIsStrictAndOneUndoableChange` |
| SF-0606-002 Create and modify | Met | Run/Cancel, Show (jump to width + select), Intentional/Report Again; UI journey |
| SF-0606-003 Resolution rules | Met (after fix 1) | `CanonicalResponsiveAudit.findings`; `testResponsiveAuditReportsEachKindAtItsExactWidthAndHonorsSuppression`, `testResponsiveAuditOverflowIgnoresThePageClipAndHonorsClippingParents` |
| SF-0606-004 Failure and recovery | Met (after fix 3) | Stale report hidden; last report kept on failure; copy objects refused with reason |
| SF-0606-005 History and persistence | Met | Suppression is one property command; schema 27; clipboard v8 |
| SF-0606-006 Accessible operation | Met | Labels, identifiers, announcements, buttons |
| SF-0606-007 Performance and scale | Partial | Off main actor, cancellable; standard (100) and large (10,000) bounded in `testResponsiveAuditStaysWithinBoundsOnStandardAndLargeFixtures`. Stress fixture not covered (blocked: needs executed timing on named hardware) |
| SF-0606-008 Diagnostics and tests | Met (after fix 6) | `ResponsiveAuthoringDiagnostic`; tests above |
| SF-0703-001 Authoritative state | Met | Mixed values via `GeometryInspectorCommandRegistry.value`; relative delta is transient command input, no new persisted state |
| SF-0703-002 Create and modify | Met | `GeometryInspectorRelativeInput`, `relativeDelta`; `TransformModelTests/testRelativeGeometryEditChangesEachObjectFromItsOwnValueInOneTransaction` |
| SF-0703-003 Resolution rules | Met | Each object from its own value at the breakpoint; out-of-range skipped, never clamped |
| SF-0703-004 Failure and recovery | Met (after fix 8) | `noApplicableTargets`, skipped subset reported |
| SF-0703-005 History and persistence | Met | One batch transaction; undo test |
| SF-0703-006 Accessible operation | Met | Field hint/help/accessibility hint name `+=`/`-=`; announcement |
| SF-0703-007 Performance and scale | Met | Existing transform capacity evidence covers the same registry path |
| SF-0703-008 Diagnostics and tests | Met | `recordGeometryInspectorDiagnostic` on every commit; unit test |

Totals: 22 Met, 2 Partial, 0 Missing.

## Remaining work (blocked only)

- OD-143 (proposed): container width basis for `@container` when the container has CSS padding or border. Blocked on an
  owner/architecture decision, and the recommended fix needs a shared inset helper across `StaticLayoutOutputEmitter`,
  `StaticSizingOutputEmitter` and `StaticBoxStyleOutputEmitter` that cannot be checked safely without a compiler.
- SF-0606-007 stress fixture (20,000 objects): blocked on executed timing evidence; no toolchain here.
- `docs/REQUIREMENT_EVIDENCE.json` records for SF-0605/0606/0703: blocked on executed evidence (no Code Forge batch since
  07 adds records before Codex runs the tests).

## Intended plan / OD status-line changes (for the coordinator)

- `docs/OPEN_DECISIONS.md` — add:
  `## OD-143 — Container query width basis for padded or bordered containers`
  `Status: Open — raised by Code Forge lane V04, 2026-11-26. Implementation status: the frame width is used on the canvas (current behavior) as the safe temporary assumption; ADR-0143.`
  `- Affected requirements: SF-0605-003, SF-1204-003.`
  `- Context: browsers evaluate @container against the container's content box; the canvas uses its frame. They differ by the CSS padding and border export emits (horizontal and Hug-height Stacks, Sections, Grids, Frames with box padding, CSS borders).`
  `- Recommended default: the canvas measures the content box through one shared inset helper also used by the layout and box-style emitters.`
  `- Alternative: keep the frame width and document the difference.`
  `- Tradeoff: the default makes canvas and browser switch at the same width but touches three emitters; the alternative is free but padded containers switch slightly differently.`
  `- Safe temporary assumption: the frame width (no change).`
- `docs/coordination/CODE_FORGE_ACTIVITY.md` batch headings: `## Batch 09 — … (container queries, SF-0605, verified by lane V04 read-check, 5 fixes, OD-143 open)`;
  `## Batch 10 — … (responsive audit, SF-0606, verified by lane V04 read-check, 4 fixes)`;
  `## Batch 11 — … (relative multi-object geometry edits, SF-0703, verified by lane V04 read-check, 1 fix)`.
- `DEVELOPMENT_PLAN.md` lane V04 row: `V04 batches 09–11 — done 2026-11-26: 9 fixes, 2 features finished (ADR-0143), 22 Met / 2 Partial (OD-143, SF-0606-007 stress evidence) / 0 Missing; report docs/reviews/LANE-V04-review-2026-11-26.md.`
- `scripts/ci-ui-timings.txt`: `testContainerQueryContainerRuleStatusAndUndoJourney 70` stays an estimate; the journey gained ~4 actions (suggest re-measuring).

## New/changed test selectors

- New `SiteForgeTests/CommandKernelTests/testContainerQueryExportHidesTextAboveItsDisplayRule`
- New `SiteForgeTests/CommandKernelTests/testContainerQueryAndAuditDiagnosticsAreSanitizedAndCategorized`
- New `SiteForgeTests/CanvasRendererTests/testResponsiveAuditOverflowIgnoresThePageClipAndHonorsClippingParents`
- Changed `SiteForgeUITests/SiteForgeLaunchTests/testContainerQueryContainerRuleStatusAndUndoJourney` (Add Setting → Opacity row, three Undos)

## Suggested first checks for Codex

1. `CanonicalResponsiveAudit.findings`: nested `shownHorizontalSpan(of:)` — `while case .node(let id)? = parent, let ancestor = nodes[id], …` with `parent: NodeParent?`; returns an unlabeled tuple into `(minX:, maxX:)?`.
2. `StaticContainerQueryOutputEmitter.emit`: `$0.property.value == .boolean(true)` inside `rule.values.contains`; the new CSS string in `testContainerQueryExportHidesTextAboveItsDisplayRule`.
3. `ResponsiveAuthoringDiagnostic.category(for:)`: exhaustive `switch` over `CommandExecutionError` (4 cases); `error is WorkspaceScenePreparationError`.
4. `ContainerQueryValueRow.body`: `switch value` in an `HStack` builder with `Picker(title, selection: Binding(get:set:))` and `TextField`; `addSettingMenu` (`Menu` + `ForEach` with a local `let`).
5. `testContainerQueryAndAuditDiagnosticsAreSanitizedAndCategorized`: `WorkspaceShellState(documentSession:)` selects the fixture's Home page by default; the async wait on `isRunningResponsiveAudit`.
6. Tuple key paths that predate this lane: `values.map(\.key)` / `applied.mapValues(\.1)` in `CanonicalContainerQueryRule` and `evaluated`, `parsed.values.map(\.key)` in tests.
7. UI: `…["inspector.containerQuery.rule.addSetting.0"].menuItems["Opacity"]` resolves on the SwiftUI `Menu`.

## Out-of-area issues (not fixed)

- `StaticLayoutOutputEmitter.baseRule` / `responsiveRule` (SF-0601/0602, InsertionModel.swift): `display: none;` on the
  plain selector loses to typography's `[sel][data-siteforge-node] { display:flex }` and `[sel]:is(a,button)` for text and
  controls if those nodes are emitted, so desktop- or breakpoint-hidden text may show in export. Connected output already
  uses `[data-siteforge-node]`; needs a check of whether hidden nodes reach the HTML tree.
- `ResponsiveAuditRunner` and `LocalPreviewRuntimeCompiler` build `CanvasViewportState` with the default
  `worldOrigin (-128, -96)`; fixed/sticky positioning (`positionedFrame` uses `visibleWorldRect`) may be offset in Preview
  and the audit. Not verified.

## Write problems

- One `edit()` call outlived the 65 s sandbox timeout and completed in the background; a retry hit `AnchorError` because
  the first had already applied. Verified single application by content and ledger. A network error and a device
  disconnect interrupted two later calls; both were re-checked and re-applied exactly once. No `ICloudRenameError`,
  no `foreign_changes` hits, `icloud_duplicates()` empty.
