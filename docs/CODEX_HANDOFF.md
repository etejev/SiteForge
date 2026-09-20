# Codex Continuation Handoff

## Active milestone

SF-AUTHORING-024 exposes component plain-text properties and instance reset.
The implementation is on `codex/sf-authoring-024-component-text-properties`.
Focused acceptance passes 11 non-UI tests plus one native two-instance journey;
five original-resolution captures passed visual review. The authoritative
milestone verification passed 429 non-UI + 61 UI = 490 tests, zero failures.
SF-CANVAS-POINTER-001 additionally repairs duplicate native layer inversion,
empty-card obstruction and a misdeclared AppKit label drawing basis. Ten
affected renderer tests and the native pointer journey pass; twelve final
pointer captures passed visual review. Hosted confirmation remains pending.
Hosted run `34742950348` passed 429 non-UI and 60/61 UI tests; the only failure
was the new pointer journey sampling pasteboard at 100% on a narrow display.
The production AX clip was correct. The follow-up changes only test sample
planning and documentation; do not repeat unchanged product suites. Run the
two affected pointer selectors, then repository checks and inspect the new
pushed SHA's hosted result. Preserve exact pixel and bounds assertions.
The narrow-coordinate regression passes 1/1. On September 20 the desktop was
unlocked and the runner launched, but XCTest timed out enabling Automation
Mode before the test body. This is a recurrence of SF-TEST-HARNESS-001, not a
product assertion. Do not retry unchanged locally: use Xcode's Test navigator
to run only `testNativePointerPreviewAndFrameTextCommitFollowScreenCoordinates`
once Automation Mode is healthy. The test-only follow-up is preserved
uncommitted. No SiteForge runner remains active.

The preceding SF-AUTHORING-023 checkpoint `b50375c` is pushed and hosted-green:
Actions `34252345248` passed. Its local gate was 420 unit/integration plus
59 UI tests (479 total). No predecessor repair or unchanged rerun is needed.

## Authoritative files and invariants

- `docs/CODEX_QUEUE.md` defines bounded SF-0902/0905 acceptance and exclusions.
- `docs/evidence/SF-AUTHORING-024-COMPONENT-TEXT.md` records exact selectors,
  observed failures/corrections, visual evidence and gate status.
- ADR-0018 owns canonical definitions and schema-v8 exposed text bindings.
- `SiteForge/DocumentModel.swift` validates stable binding IDs and overrides.
  Existing `content.text` remains the sole definition default.
- `SiteForge/TransformModel.swift` compiles identity-gated component edits;
  `CommandKernel.swift` enforces exact inverses and dependent-intent protection.
- `SiteForge/InsertionModel.swift` derives effective instance text and detach
  output without persisting virtual expanded nodes.
- `SiteForge/WorkspaceShellModel.swift` gates drafts on adopted revision and
  renderer generation. `WorkspaceShellView.swift` contains native Content
  controls; drafts are never canonical before Apply/Return.
- `SiteForge/CanvasRendererCore.swift` publishes immutable effective text to
  rendering and accessibility without changing object geometry.

Empty text is authored, not inherited. Reset removes an override. Renaming a
binding preserves its identity. Removal cannot silently destroy dependent
instance values. Unresolved loaded intent stays visible and recoverable.
Do not bypass the registry, duplicate defaults, weaken stale identity checks,
or introduce a second component/render/resource system.

Preserve centered pasteboard, upright text, normal maximized window policy,
blank-project emptiness, exact command/window ownership and editor-only chrome.

## Next bounded action

The authoritative gate is complete in
`full-20d3f1fe-cbca-4099-b029-d9a9c449e92c.xcresult`. Do not repeat unchanged
local suites. Finish documentation-only checks, the explicitly authorized
coherent commit, safe main integration and ordinary push. Inspect the exact
new SHA's hosted result separately from SF023; fix concrete failures only.
Do not begin SF-AUTHORING-025 or another feature.

## Deferred scope and boundaries

SF-0902/0905 remain Partial: media/boolean/enum/action properties, slots,
variants, nesting, arbitrary style overrides, bulk instance editing, remote
libraries, preview/export/runtime parity and release acceptance are deferred.
Earlier milestone history remains in the queue and per-milestone evidence,
not in contradictory current-task instructions.

Follow AGENTS.md for genuine product/architecture/security owner decisions.
Never commit generated results, caches, secrets or machine-specific paths.
No force push, destructive reset, release, signing, notarization or publication.
