# SF-AUTHORING-057 — Local solid color tokens

Bounded evidence for SF-0509-001–008, SF-0302, SF-0305, and SF-0306. The
normative SF-0509 module remains Partial.

## Delivered local slice

- Schema 9 adds stable project-local ColorTokenID, name, and normalized RGBA
  records. Schema 8 projects migrate to an empty token collection; the current
  decoder rejects unknown token fields. No file paths or color values enter
  token diagnostics.
- The Design Inspector can create, rename/recolor, select, and delete unused
  tokens. A selected token can bind an existing enabled solid fill on a Frame,
  Section, Stack, or Grid. In-use deletion is rejected with a use count.
- Binding retains the literal fill as a safe fallback. Missing token references
  keep their stable identity and render that literal. Unbinding freezes the
  currently resolved color into the literal fill in one reversible transaction.
  While bound, the Inspector displays the resolved token color and disables
  literal/layer color editing with an explicit unbind hint.
- Canvas, scene-local Preview, and closed static Frame/Section output resolve
  the same token color without serializing editor chrome or introducing CSS
  variable/runtime state. Token record and binding changes use existing
  DocumentSession history and exact inverses.

## Focused verification

- `TransformModelTests.testLocalColorTokenCreateBindRecolorUnbindHistoryAndPersistence` — passed.
- `TransformModelTests.testLocalColorTokenSchemaEightMigrationAndStrictCurrentDecode` — passed.
- `TransformModelTests.testLocalColorTokenRegistryRejectsStaleCancelledAndInapplicableEditsWithoutMutation` — passed.
- `TransformModelTests.testLocalColorTokenResolvesAllSupportedStructuralKindsAndMissingFallback` — passed.
- `CommandKernelTests.testStaticSolidFillResolvesLocalColorTokenWithoutChangingLiteralFallback` — passed.
- `SiteForgeLaunchTests.testLocalColorTokenInspectorCreateBindAndUnbindJourney` — passed after correcting revision-keyed Inspector draft recreation. The test retains original-resolution “bound local color token” and “unbound literal fill” window attachments; both were visually inspected. The Frame remains inside its selection outline, the artboard/grid remain distinct, and token controls remain readable and accessible in the normal maximized window.

No broad `./sf verify` or hosted gate was run in this development prompt. That
gate is reserved for the tenth-prompt checkpoint by the current owner policy.
`git diff --check` and JSON syntax passed. The repository-wide traceability
checker still reports stale symbols, duplicate SF-0507 entries, and a
verified-bounded/uncovered inconsistency outside SF-0509; no SF-0509 evidence
entry was flagged. These existing index issues require a separate bounded
documentation correction before the tenth-prompt gate.
The architecture script's canonical-model slice passes after locating the
shared RGBA value in the headless document layer. Its later canvas-renderer
slice still fails because its source list omits existing renderer dependencies
such as fill-layer/box-style types and static asset planners; that script
boundary is not claimed green by this focused checkpoint.

## Deferred

Theme/mode switching, aliases, non-color token types, remote libraries,
arbitrary CSS variables, broad scale/performance and accessibility matrices,
actual-app save/reopen, browser runtime, export parity, and release acceptance
are not claimed by this slice.
