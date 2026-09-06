# Codex Continuation Handoff

Active work: SF-AUTHORING-020 on the preserved feature branch. Do not restart
the completed SF-AUTHORING-019 repair. Compact/internal-target and separated
object visuals are reviewed. Final verification passed 399 non-UI + 52 UI
tests (451 total). Integrate/push this coherent checkpoint and inspect its
hosted run before reporting delivery complete. The Button/Link registry,
six model tests, control glyph test and actual-app journeys are implemented;
see `docs/evidence/SF-AUTHORING-020-BUTTON-LINK.md`. Do not start another feature.

Final SF-AUTHORING-019 Save availability acceptance: production `f951df7` is
hosted-green in Actions `33991018406` (392 unit/integration + 49 UI = 441,
zero failures). Recovery autosave does not disable native Save; the existing
cancel/drain operation owns durable saving. Both focused follow-up checks
passed. Preserve the separate pre-existing Button/Link work; no new feature
was included in this repair. See the Inspector repair evidence for chronology.

## Current checkpoint

`SF-AUTHORING-019` and the hosted Inspector/autosave repair are
**VERIFIED AND DONE** within the bounded local-raster scope.
The existing schema-v5 resource catalogue, Image references, native Assets /
Inspector workflow, immutable renderer, history, recovery, and persistence
remain unchanged by the repair.

The actual shared defect was disabling Inspector validation during immutable
snapshot saving/autosaving. Editing now remains available with revision guards,
as insertion and inline editing already did. Native Save handles already-Saved
state; window assertions preserve the 1100-point production minimum; helpers
query and operate the genuine enabled, safely visible field/segment.
The compact Alignment label is separately readable on one line.

Seven distinct affected selectors passed. The three originally failing UI
journeys passed three consecutive fresh-process groups (9/9). Final local and
hosted verification each passed 392 unit/integration plus 49 UI tests
(441/441), zero failures. Actions `33982941555` verified production commit
`f6c58ef`. Repository checks and reviewed original-resolution persistence /
alignment evidence are recorded in
`docs/evidence/SF-AUTHORING-019-INSPECTOR-REPAIR.md`.

The later documentation-only run passed all UI tests but exposed an unrelated
save-test ordering assumption. The test now uses the existing filesystem
checkpoint barrier, not a delay/yield; its focused pair passed 2/2 with stronger
write-order and final-state assertions. Production code is unchanged. Preserve
this deterministic synchronization when extending lifecycle tests.

Do not discard the separate pre-existing Button/Link branch work; it was
deliberately excluded from this repair. Main has no next READY item. Do not
create another asset store or expand into image fills, remote providers,
responsive source sets, or export without an authorized bounded queue item.

`SF-AUTHORING-018` is **VERIFIED AND DONE**. The current tree extends the
existing breakpoint cascade rather than adding a parallel responsive system:
Tablet/Mobile overrides cover Section padding, Stack direction/gap/padding/
alignment, Grid columns/gap/padding, and visibility for Frame, Text, Section,
Stack, and Grid. Hidden descendants retain canonical identity/data but do not
participate in layout, authored rendering, hit testing, inline editing, canvas
accessibility, or selection chrome; Layers remains the explicit inspection and
recovery route. Seven focused non-UI selectors and the fresh-process responsive
journey are green, and seven original-resolution maximized-window states passed
visual review. Final hosted `./sf verify` passed 379 unit/integration plus 48
UI tests (427 total), zero failures, with every repository gate green. Hosted
follow-up coverage also proves nested insertion remains available during
background autosave and container Reset controls remain visible at the
practical Inspector width. No subsequent
feature item is READY; do not create another responsive/property cascade or
invent an unspecified feature.

`SF-AUTHORING-017` is **VERIFIED AND DONE**. The current tree retains existing
schema-v4 layout properties as the only canonical source and implements one
identity-gated container-layout registry, native Layout Inspector controls,
and one shared Section/Stack/Grid resolver. Focused registry/history/
diagnostic, resolver, renderer-geometry, and package/recovery evidence passed
5/5; actual-app maximized/practical-minimum acceptance passed 2/2; `./sf test
half` passed 371/371; and the mapped full suite passed 419/419 with zero
failures. Final `./sf verify` passed 372 unit/integration plus 47 UI tests (419
total), zero failures, with every repository gate green. Original-resolution
evidence passed visual review after the shared
resolver was corrected to keep oversized insertion-default children within
bounded Stack/Grid content boxes without changing canonical geometry.
Responsive container-layout overrides are deliberately deferred because the
existing responsive cascade currently owns geometry only; do not introduce a
parallel cascade.

`SF-AUTHORING-016` is **VERIFIED AND DONE**. The current tree implements the
bounded responsive geometry-authoring slice through stable Desktop, Tablet,
and Mobile identities, deterministic width resolution, Desktop-base
inheritance, isolated Tablet/Mobile X/Y/Width/Height overrides, one
identity-gated transaction registry, and one immutable resolved geometry used
by renderer, selection, hit testing, accessibility, inline text, packages,
recovery, and history. Focused acceptance passed 5/5 and five
original-resolution maximized-window states passed visual review. The
authoritative `./sf verify` passed 367 unit/integration plus 45 UI tests (412
total), zero failures, with every repository gate green. Do not expand this
slice into custom breakpoint management, responsive styling/content/
visibility, comparison panes, safe-area simulation, container queries,
component responsiveness, preview/export parity, or release acceptance. No
subsequent feature item is READY; the remaining action is the authorized
commit/push/hosted-CI boundary.

`SF-AUTHORING-015` is **VERIFIED AND DONE**. The current tree implements
bounded production plain-Text typography through strict canonical properties,
one identity-gated transaction registry, immutable renderer snapshots, shared
committed/inline text metrics, native Design controls, package/recovery, and a
fresh-process Save/close/reopen journey. Focused acceptance passed 4/4 and six
original-resolution screenshots passed visual review. The authoritative
`./sf verify` passed 363 unit/integration plus 44 UI tests (407 total), zero
failures, with all repository gates green. Do not expand the slice
into font import, variable axes, rich text, automatic sizing, responsive
typography, tokens, or preview/export work.

`SF-AUTHORING-014` is **VERIFIED AND DONE**. The current tree implements the bounded
uniform border, uniform corner radius, and one drop-shadow Design Inspector
slice through canonical `style.box.v1` properties, the shared transaction
registry, immutable renderer snapshots, native controls, package/recovery, and
focused actual-app evidence. Do not expand this into margins/padding,
independent borders, per-corner radii, multiple/inner shadows, clipping UI, or
preview/export work. Focused acceptance passed 7/7 and the authoritative
`./sf verify` passed 360 unit/integration plus 43 UI tests (403 total), zero
failures. Hosted Actions `32934689112` passed the same complete gate at
`65571dc` after the compact-window pointer placement correction.

`SF-AUDIT-001` is **VERIFIED AND DONE**. Confirmed audit defects were fixed at
their production boundaries rather than returned to the owner as a
prioritization list. Focused integration and running-app visual review passed;
the final 2026-08-25 `./sf verify` passed 356 unit/integration tests plus 41 UI
tests (397 total), zero failures, with repository/security/traceability/
architecture/migration/evidence checks green.
Hosted Actions `32917355488` subsequently passed the same 356 unit/integration
plus 41 UI test gate at `3c90e33`, including the compact-window Inspector and
navigator accessibility corrections.

`SF-AUTHORING-013` remains a **VERIFIED BOUNDED** historical milestone. Its
broader deferred scope is unchanged.

## Authoritative files

- `SiteForge/TransformModel.swift`: canonical `style.fill.layers.v1` codec,
  migration adapter, and `DesignInspectorCommandRegistry` layer operations.
- `SiteForge/CanvasRendererCore.swift`: immutable renderer-facing layer data
  and deterministic compositing policy.
- `SiteForge/WorkspaceShellModel.swift`: identity-gated command submission
  and renderer snapshot preparation.
- `SiteForge/WorkspaceShellView.swift`: native tile compositing and visible
  Design Inspector Fill Layers controls.
- `SiteForge/FillLayerListInspectorView.swift`: per-layer and per-stop native
  colour controls plus accessible gradient-stop ordering actions.
- `Tests/SiteForgeTests/TransformModelTests.swift`,
  `Tests/SiteForgeTests/CanvasRendererTests.swift`,
  `Tests/SiteForgeTests/ProjectPackageTests.swift`, and
  `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift`: focused evidence.
- `docs/evidence/SF-AUTHORING-013-FILL-LAYERS-CHECKPOINT.md`: verified bounded
  milestone evidence and visual review.
- `docs/evidence/SF-AUDIT-001-CORRECTIONS.md`: exact post-gate corrections,
  focused evidence, and recurring-risk controls.
- `SiteForge/ProjectResources.swift`, `SiteForge/FileAccessBoundary.swift`,
  `SiteForge/InsertionModel.swift`, and `SiteForge/DiagnosticSupport.swift`:
  resource identity, cancellation, large-Grid, and diagnostic corrections.
- `SiteForge/WorkspaceShellModel.swift`: off-main production scene, renderer,
  selection, and viewport projection with identity-gated main-actor adoption.
- `SiteForge/WorkspaceMaterialPolicy.swift`,
  `SiteForge/WorkspaceShellView.swift`: document-window policy and minimum
  workspace/canvas integration corrections.

## Invariants that must not change

1. `DocumentNode.properties` is the sole canonical style source. `v1` wins
   whenever its order key exists; legacy v4 solid properties are read only
   before first v1 write and must never be written alongside v1.
2. Layer/stop identity and authored order are stable. The renderer may make a
   local stable position sort for interpolation, but may not rewrite model
   order.
3. All edits use `DesignInspectorCommandRegistry`; views, test code, and
   renderer code may not mutate canonical properties directly.
4. Renderer snapshots are immutable and identity-gated. Object opacity applies
   once to the complete authored layer stack. Editor chrome is separate from
   authored and preview-facing compositing.
5. Preserve the existing centered pasteboard, top-left/Y-down coordinate
   convention, normal maximized window policy, blank-project emptiness, and
   focused command/window ownership behavior.

## Next task

No queue item is READY. Establish the next specification-backed bounded slice
before implementation; do not silently expand SF-AUTHORING-019 into advanced
asset organization, remote sources, preview/export, or
release acceptance.

## Stop/escalate conditions

Stop and record an entry in `docs/OPEN_DECISIONS.md` only for an unresolved
product choice with broad downstream effect or an incompatible migration.
Do not commit generated artifacts, local result bundles, secrets, or machine
paths. External signing, notarization, publication, credentials, or a genuinely
unavailable external dependency remain owner boundaries. Do not begin a
feature beyond SF-AUTHORING-019 until a READY queue item defines its scope.
