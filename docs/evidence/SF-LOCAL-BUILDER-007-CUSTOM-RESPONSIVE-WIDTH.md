# SF-LOCAL-BUILDER-007 — Custom responsive inspection width

Current focused acceptance supersedes the historical source-only hold below:
all 9 new code methods pass in the focused 007–011 group. The real width journey
passes, latest114.753s; seven retained originals were inspected after the shared
native layer resize correction. Keep IN PROGRESS;
full verification is deferred, not waived. No commit/push/install or owner-data
change. [Current focused results](SF-LOCAL-BUILDER-007-011-FOCUSED-ACCEPTANCE.md).

Latest2026-10-29: owner renewed the NO TESTING hold, superseding the prior direct
approval. Status IN PROGRESS; built historically, focused acceptance FAILED.
No current acceptance or screenshots are claimed. The owner hold prohibits builds, tests, check
scripts, UI/browser acceptance, collectors, verification, commit and push.
The earlier ba342938 checkpoint's green results do not verify these changes.

## Actual historical execution and source correction

- focused-3133a465-4a20-4bbe-83ee-f0ebb348b383.xcresult: build succeeded;
  nine code methods executed,3 passed/6 failed. Five fixture-dependent methods
  rejected incomplete structural defaults; recovery-path setup also failed.
- Added the complete Section/Stack/Grid default contract without weakening model
  validation. Recovery now uses ApplicationOwnedTestFixture and a child recovery
  directory, preserving canonical /private/var ownership/symlink checks.
- focused-d3dafe44-8b7d-4604-a84c-aa7b7657dc6d.xcresult: six affected methods,
  four passed/two failed. The remaining text/geometry fixtures awaited a scene
  before any real viewport initialization, then failed dependent assertions.
- Latest SOURCE correction explicitly resizes the viewport before awaiting
  adoption/starting text or selection commands. Assertions and budgets remain
  unchanged. No execution followed this correction under the renewed hold.
- Both result bundles and matching logs remain retained in the existing external
  TestResults directory. No runner remains. The nine methods are NOT all UNRUN
  or all accepted;007 native UI source remains UNRUN. Subsequent008 source also
  changes comparison behavior, so old partial passes are not current verification.

## Bounded contract

SF-0602-002/003/004/006/008: native scene-local CSS width entry; deterministic
preset/custom-width scope; cancellation, validation, accessibility and diagnostics.
SF-0601-003/006: reuse stable breakpoints and expose the effective range.
SF-0604-003/006: shared fluid-value sampling and accessible current-width review.
Supporting SF-0401-003/006: shared viewport transform and header focus traversal.
These modules remain Partial. No schema, breakpoint, cascade, canonical width,
responsive content or preference system is introduced. OD-018/019 unchanged.

## Source implementation

- Existing CanvasViewportState.contentBounds.width is the sole inspection-width
  authority. Desktop/Tablet/Mobile actions select exactly 1440/768/390; the
  effective breakpoint follows Mobile <600, Tablet 600..<1024, Desktop >=1024.
  CSS width is independent of canvas zoom, backing scale and window dimensions.
- Native Width text field uses locale parsing, Return/valid focus-loss commit,
  Escape restore, explicit invalid/stale feedback and existing draft/IME gate.
  Finite numeric domain is the existing 1...1,000,000,000 dimension budget;
  viewport fitting may reject otherwise valid dimensions without replacing the
  last valid viewport. Incomplete or malformed input is never canonical.
- Successful width commits atomically prepare the next viewport and Fit Document
  presentation before publication, retaining NodeIDs, authored coordinates,
  properties, selection identity and history. Active gesture previews are cancelled.
- Immutable preparation, Inspector scopes/provenance, insertion, responsive
  layout, fluid typography and native Preview use actual width, not a nearby
  preset anchor. Native Preview adoption additionally guards scene/generation/width.
- Responsive comparison resolves off-main through an actor. Request, document,
  revision, page, scene, selection, width and viewport-generation guards reject
  obsolete results. Three fixed references remain separate from a fourth current
  width sample, including when its width equals a reference. Work is cancellable;
  no synchronous body-time layout calculation is introduced.
- Existing static layout/appearance emitters share the same half-open media
  conditions, closing fractional-width gaps at 599.5/1023.5. No generated output
  files or second compiler path are edited. Browser/export runtime parity is UNPROVEN.
- Diagnostics retain one sanitized scene identity, operation, requirement,
  duration and fixed failure category; input text and document content are omitted.

## Acceptance methods — partial historical execution above

In Tests/SiteForgeTests/CanvasViewportTests.swift:

1. testCustomViewportWidthValidationLocaleAndHalfOpenRanges
2. testCustomViewportWidthIsSceneLocalAcrossZoomWindowScaleAndPresetActions
3. testCustomWidthSharedLayoutRenderInspectorHitSelectionAndTextMatrix
4. testCustomWidthRejectsInvalidStaleAndPendingContextsWithoutMutation
5. testCustomWidthPendingIMERejectsThenAllowsExplicitRetry
6. testCustomWidthTargetsEffectiveOverrideAndKeepsExactUndoRedo
7. testCustomWidthComparisonCoalescesRapidChangesAndRejectsReplacement
8. testCustomWidthInsertionPreviewPackageAndStaticOutputRemainTruthful
9. testCustomWidthConnectedFlowAndReferenceComparisonShareActualSample

Width matrix: 320,430,599,600,601,900,1023,1024,1025,1440; parser/range checks
also cover fractional boundaries, locale, nonfinite and out-of-budget input.
Package identity/timestamps are held constant for byte comparison; owned recovery
read/write uses a fresh isolated temporary directory in the future test only.

In Tests/SiteForgeUITests/SiteForgeLaunchTests.swift:
testCustomResponsiveViewportWidthEntryComparisonAndCancellationJourney.
Future real-control journey covers maximized presentation, entry/blur/Escape,
invalid neutrality, insertion identity, exact boundaries and current comparison.
Six named screenshots are requested by source, but NONE exist from this workflow.
Existing AppMetadataTests focus traversal and shell keyboard journey include Width;
CanvasRendererTests/CommandKernelTests retain exact half-open CSS assertions.

## Next acceptance, only after owner approval

Compile first; run the nine exact CanvasViewportTests selectors and the one new
SiteForgeLaunchTests selector, plus directly affected focus/static-output methods.
Inspect all retained originals at normal and practical-minimum header widths;
check labels/focus, fitted gutters, unchanged canonical identities, upright text,
selection clipping, comparison progress and current-width accuracy. Validate
fractional media behavior using the existing output/browser acceptance path.
Then perform mandatory ./sf verify before any completed/verified claim.

No further tests/builds/scripts/checks/UI/app/browser acceptance or visual
inspection occurred after the renewed hold. No commit, push, installation,
owner project/resource/recovery mutation, signing or scheduled follow-up occurred.
