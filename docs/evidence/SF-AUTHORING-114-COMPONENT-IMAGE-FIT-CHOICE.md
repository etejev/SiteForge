# SF-AUTHORING-114 — Image-fit component choice property

## Scope

Bounded evidence for `SF-0902-001`–`SF-0902-008` and supporting
`SF-0905-001`–`SF-0905-008`. The normative modules remain **Partial**.

## Delivered behavior

- A component-definition Image can expose its canonical Fit mode as one stable
  typed choice property with a user-facing label.
- Linked instances show a native Fit/Fill/Stretch picker with truthful
  inherited/authored provenance and a Reset Override action.
- Definition and instance mutations use `ComponentCommandRegistry`, its live
  document/page/revision/scene/renderer/selection identity checks, and the
  existing atomic property transactions and exact inverses.
- `ComponentGraphResolver` applies the effective choice before immutable
  canvas/static-output planning, while leaving the definition and asset bytes
  unchanged.
- Package round-trip, Undo/Redo, missing-binding conflict projection, Reset All,
  and cross-project component transfer preserve or remap stable choice IDs.

## Focused verification

`SiteForgeTests/CommandKernelTests/testComponentImageFitChoiceOverrideResetHistoryRendererAndPersistence`
passed 1/1. It covers default resolution, authored override, immutable expanded
graph adoption, exact Undo/Redo, Reset inheritance, serializer round-trip, and
stale identity rejection.

Result bundle:
`focused-2e33efc2-5cca-42f4-9e15-9192a4b2f1c0.xcresult`.

The existing component reset/history regression and the cross-project
component-definition transfer regression each also passed 1/1, for three
focused selectors and three passing tests across the affected boundaries. No
complete gate was rerun for this bounded slice; the immediately preceding
baseline is the 671-test verified checkpoint.

A subsequent required gate attempt passed repository/build checks and all 568
unit/integration tests, then macOS XCTest failed before executing any UI test
with `Timed out while enabling automation mode`. Result bundle:
`full-788bd61f-04f1-4071-ab01-260195fd373b.xcresult`. This is external runner
evidence, not a SiteForge assertion failure, and no full-gate completion is
claimed for this follow-on slice.

## Deferred

Media asset replacement properties, arbitrary authored enum option sets,
action and slot properties, variants, nested components, broad actual-app and
assistive-technology matrices, preview/export certification, performance
acceptance, and release acceptance.
