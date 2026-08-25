# SF-AUDIT-001 — Post-Milestone Audit Corrections

Date: 2026-08-25

Requirements: bounded corrective evidence for `SF-0201-002`,
`SF-0201-003`, `SF-0201-006`, `SF-0201-008`, `SF-0301-004` through
`SF-0301-006`, `SF-0303-001`, `SF-0303-005`, `SF-0303-008`,
`SF-0405-007`, `SF-0407-006` through `SF-0407-008`, `SF-0503-007`,
`SF-0508-001` through `SF-0508-008`, `SF-1502-001`, `SF-1504-004`,
`SF-1702-008`, `SF-1802-008`, `SF-1804-008`, `SF-1902-008`, and
`SF-2002-008`.

## Outcome

The post-`SF-AUTHORING-013` audit was treated as an implementation pass, not
as a request for the owner to prioritize a finding list. Every confirmed
defect below was traced to its production boundary, corrected in the shared
working tree, and paired with regression coverage. These are completed
corrections and recurring-risk records, not an unfinished backlog.

The 2026-08-25 `SF-AUTHORING-013` gate remains historical evidence for its
named pre-audit tree. The reconciled post-audit tree passed its own final
`./sf verify` on 2026-08-25: 356 unit/integration tests and 41 UI tests (397
total), zero failures, with every repository gate green.

## Corrections and recurrence controls

| Area | What the audit found and fixed | Recurring-risk control | Evidence available now |
| --- | --- | --- | --- |
| Ordered-fill schema and migration | The v1 fill namespace could accept malformed or partially owned state through permissive decoding. The decoder now distinguishes absent, explicit-empty, legacy-only, and valid-v1 state; validates exact keys, order, identity, kinds, values, angles, and stops; and rejects malformed current packages instead of interpreting them as legacy. Legacy solid resolution remains a read-only migration adapter and no compatibility command writes retired keys. | Every versioned nested namespace needs an exact-key decoder and a negative matrix at both model-validation and package-adoption boundaries. Compatibility defaults may be applied only by an explicitly selected historical adapter. | `TransformModelTests/testCanonicalFillLayerStrictDecoderDistinguishesAbsentEmptyLegacyAndValidStacks`, `TransformModelTests/testCanonicalFillLayerStrictDecoderRejectsMalformedNamespaceMatrix`, `ProjectPackageTests/testHistoricalSurfaceMigratesToOrderedLayersAcrossSaveReopenAndRecovery`, and `ProjectPackageTests/testChecksumValidCurrentPackageRejectsMalformedFillLayerOrder` passed in focused runs. |
| Fill Inspector numeric drafts | Invalid angle and stop-position text could disappear without explaining why. Angle and percentage drafts now validate explicitly; valid angles normalize canonically, percentages remain within 0–100, Return or focus loss commits, Escape restores, and invalid input remains visible with an accessible error. | Any native text field backed by a typed command needs an editor-only draft, explicit validation state, deterministic commit/cancel boundaries, and tests for empty, non-finite, out-of-range, and normalized values. | `TransformModelTests/testFillLayerNumericDraftValidationIsExplicitAndCanonical` passed 1/1 in its focused run. |
| Project-resource decoding and filesystem identity | Resource index/descriptor decoding admitted unknown fields or the wrong package-member role, and path validation could be separated from later blob access if the root name changed. The index is now exact-key/role strict. Blob reads and publication remain bound to a validated directory descriptor; owner, restrictive modes, link count, and extended ACL policy are checked at the descriptor boundary. A path exchange cannot redirect the operation. | Security checks must remain attached to the descriptor used for I/O. A validated path string is not an authorization token. Security-sensitive Codable records require exact keys, role validation, and adversarial swap/ACL fixtures. | `ProjectResourceTests/testResourceIndexRejectsUnknownFieldsAndIncorrectPackageRole`, `testResourceStoreRejectsExtendedACLsOnRootAndBlob`, and `testResourceStoreRemainsBoundToValidatedRootWhenPathIsExchanged` passed in the focused 8-test integration run. |
| Coordinated cancellation | Cancelling the outer task did not necessarily reach an in-flight Foundation file-coordination callback before its commit boundary. The outer cancellation is now relayed into coordinated work and the commit remains state-neutral after cancellation. | Callback-based platform APIs need an explicit cancellation relay and a deterministic barrier at the last mutation boundary; checking only before entering the API is insufficient. | `FileAccessBoundaryTests/testFoundationCoordinatorRelaysOuterCancellationBeforeCoordinatedCommit` passed in the focused 8-test integration run. |
| Large-grid preparation | Grid row offsets repeatedly read child heights while preparing a 10,000-object fixture. Row offsets are now computed in one linear pass with one height read per child. | Large-fixture tests must count primitive reads or visits, not merely assert elapsed time, so accidental quadratic work is deterministic and hardware-independent. | `InsertionModelTests/testGridRowOffsetsReadEveryLargeFixtureChildExactlyOnce` passed and asserted exactly 10,000 height reads in the focused 8-test integration run. |
| Production scene preparation | Canonical traversal, geometry resolution, renderer projection, selection projection, and viewport-object preparation still ran through a main-actor-owned orchestration path. They now consume an immutable request in `WorkspaceScenePreparationWorker`; only identity-gated adoption returns to the main actor. | A detached-looking task is not evidence of isolation. Large production work needs a non-main-actor owner and a deterministic active-work barrier proving the main actor advances before the worker is released. | `CanvasRendererTests/testProductionSceneProjectionAndRendererKeepMainActorResponsiveWhileWorkIsActive` passed with 10,000 objects; its barrier remained active while 20 main-actor heartbeat turns completed, then renderer adoption preserved the prepared scene identity and all 10,000 objects. |
| Diagnostic retention and privacy | Diagnostic arrays were independently managed and could grow without one shared retention/redaction contract. A fixed-capacity ring buffer now reports monotonic sequence and drop counts; stable identifiers use domain-separated SHA-256 tokens; unknown errors map to a closed category rather than serializing their descriptions. The affected canvas, viewport, selection, transform, snapping, drag/drop, text, lifecycle, package, history, launch, and command records use the shared support. | Every diagnostic producer must use one bounded retention primitive, domain-scoped opaque identifiers, and closed error categories. Tests must seed authored text, paths, UUIDs, and private error descriptions and prove they do not escape. | All three `DiagnosticSupportTests` passed in the focused 8-test integration run; the affected focused diagnostic regression run also passed. |
| Local alpha checksums | The generated checksum could retain the archive's source path, making it machine-specific after relocation. The checksum now records only the archive basename and remains verifiable after the archive and checksum move together. | Release-adjacent manifests must be relocatable and must not persist local machine paths. | `scripts/test-portable-checksum.sh` passed, including basename, no-path-leak, relocation, and verification assertions. |
| Portable headless compilation | Hosted run `32897836052` exposed a standalone Swift type-check timeout in the compact source-over fill expression even though the local Xcode build and behavioral tests passed. The compositor now calculates alpha and channel contributions as explicit typed steps without changing its arithmetic. | Every renderer helper included in a Foundation-only architecture slice must compile under both the project build and the standalone hosted compiler; avoid closure/array expressions whose inference cost is disproportionate to the operation. | Both fill-compositor selectors passed 2/2, the headless architecture gate passed, and the final post-correction `./sf verify` again passed 356 unit/integration plus 41 UI tests. |
| Hosted compact-window accessibility | Hosted runs `32899615186` and `32902335650` reached the complete UI target and exposed three display-height/identity assumptions: gradient-stop rows were too tall for reliable native-well reachability; the flexible Inspector tab strip could cover the overflow menu's pointer target; and SwiftUI could reuse the Assets unavailable branch after selecting Components. Gradient-stop controls now use a compact single-row layout and frame-directed scrolling; the overflow menu owns an explicit trailing overlay with reserved space; and Assets/Components are distinct view branches and accessibility subtrees. A follow-up hosted run rejected synchronously assigning `FocusState` from the selection button because it invalidated the AX subtree, so pointer selection remains a selection event and keyboard focus remains owned by the existing focus system. | Responsive native panes must reserve fixed trailing actions independently of flexible scroll content. Reused unavailable-state destinations require structural identity, and UI acceptance must prove that deep controls are reachable through the shipping scroll surface rather than assume a particular hosted display height. Selection and focus are related but distinct state boundaries and must not be co-published from a SwiftUI update callback. | The corrected app and UI targets compile; `AppMetadataTests` passed 14/14 and repository checks passed. A focused local UI launch was blocked before test bodies by the separately recorded macOS automation foreground denial; hosted Actions is the authoritative rerun for these three exact journeys. |
| Workspace role and minimum layout | Global window treatment could affect panels, sheets, child windows, or unrelated windows, and fixed-height header/Inspector layouts could hide real controls at the supported minimum. Workspace treatment is now opt-in for the actual document window; auxiliary windows are excluded. Viewport controls use intrinsic layout and the selected Inspector scrolls, with responsive fill-layer/stop rows at the 280-point Inspector width. | Window policy must be role-scoped, and UI acceptance must exercise the actual 1100×700 minimum with every implemented control visible and hittable rather than relying on accessibility-only or oversized-window assertions. | `WorkspaceMaterialPolicyTests/testWorkspaceWindowRoleExcludesPanelsChildrenAndUnmarkedAuxiliaryWindows` and `SiteForgeLaunchTests/testMinimumWorkspaceContainsViewportAndScrollableFillInspectorControls` passed. The minimum-window attachment was reviewed at original resolution. |
| Selection lifecycle repair | The synchronous undo/redo repair compared canonical children of the implicit structural root against the scene-level page container, briefly classifying a surviving selected node as removed. Repair now applies the same implicit-root-to-page projection used by scene preparation. | Synchronous lifecycle repair and asynchronous scene adoption must share one container projection; tests must assert selection identity as well as canonical geometry through undo/redo. | `TransformModelTests/testWorkspaceTransactionKeepsSelectionAndSynchronizesLayoutRendererAndUndo` and `testResolvedGeometryIsSharedAcrossRendererSelectionAccessibilityAndStyles` passed 2/2. The full selection UI journey also passed with semantic row identity and stable selection-count assertions. |
| Audit workflow | Audit output previously risked becoming a user-facing prioritization handoff instead of completed engineering work. The repository agent instructions treat findings as internal work: trace, fix, test, document, and report recurring patterns; stop only for a real owner decision or unavailable external dependency. | A confirmed editable-scope defect is not a terminal result. The completion report names what was fixed and its regression coverage; it does not ask the owner to rank already confirmed corrections. | `AGENTS.md` and the audit completion task in `docs/CODEX_HANDOFF.md` carry the completion rule. |

## Reconciliation classification

- Preserved production corrections: canonical model/package/history, file and
  resource identity, lifecycle/cancellation, diagnostics, renderer/viewport,
  selection/transform/insertion/drag/text/snapping, window/material, and shell
  integration changes. New Swift sources are members of the app and test
  targets and every headless architecture slice that consumes them.
- Integrated intent: focused model, filesystem, renderer, performance, window,
  and actual-app coverage; portable checksum tooling; visual-contract and
  requirement evidence updates. Headless model validation now owns a
  Foundation-only exact fill-namespace validator instead of depending on the
  UI-facing Design registry.
- Removed residue: the obsolete local-model handoff was deleted and replaced
  by `docs/CODEX_HANDOFF.md`; no Ollama/Aider command, cache, history, generated
  result bundle, Derived Data, or local-machine path is part of the change set.
- Corrected unsupported/inconsistent changes: accessibility geometry tests now
  honor bounded viewport virtualization while canonical/render/selection
  geometry remains full-world; visible authored Layers—not the implicit Root—
  own keyboard traversal and semantic selection assertions.

## Visual review

The minimum-window journey and normal-maximized ordered-fill journey passed
2/2. Their original-resolution window attachments were inspected against
`docs/product-ui/VISUAL_CONTRACT.md`: menu bar/Dock-compatible maximized
presentation, persistent labeled viewport controls, readable unwrapped
navigator/Inspector tabs, scrollable layer/gradient controls at minimum width,
distinct pasteboard/grid/artboard layers, upright content, aligned selection,
and no ghost or debug artifacts were confirmed. The minimum journey explicitly
reactivates SiteForge before pointer assertions so unrelated developer-tool
occlusion is not misreported as product clipping.

## Scope boundary

These corrections harden already implemented boundaries. They do not add image
fills, blend/filter effects, borders, shadows, responsive overrides,
preview/export parity, publishing, OS-level VoiceOver/settings acceptance,
cross-hardware budgets, signing, notarization, or release acceptance. Those
capabilities remain governed by their existing specification and queue state.
