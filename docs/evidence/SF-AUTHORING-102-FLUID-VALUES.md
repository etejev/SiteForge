# SF-AUTHORING-102 — Fluid responsive values

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**

Requirements: bounded `SF-0604-001`–`SF-0604-006`, `SF-0604-008`; supporting
`SF-0601-003`, `SF-0602-003`, `SF-0602-004`, and `SF-0602-006`.

## Bounded contract

- `responsive.fluid.v1.<target>` is one versioned closed JSON property with a
  stable `FluidValueID`, schema version, finite minimum/preferred/maximum, and
  the allowlisted linear curve. Existing fixed values remain untouched.
- Product reference widths are 390, 768, and 1440 points. Resolution is a
  monotonic piecewise-linear interpolation from minimum to preferred to
  maximum, clamped outside that range.
- Supported targets are Frame, Text, Image, Section, Stack, Grid, Button, and
  Link width/height; Text, Button, and Link font size
  and line height; and Section/Stack/Grid padding plus Stack/Grid gap.
- Explicit Tablet/Mobile geometry or container values win over fluid values.
  Fluid intent wins over the fixed fallback only when no explicit breakpoint
  literal exists. Removing fluid intent removes its property and reveals the
  original fixed value rather than writing a visually equivalent literal.
- Typography validation checks the resolved size/line-height pair at all three
  reference widths. Malformed, non-finite, inverted, out-of-range, stale,
  cancelled, hidden, locked, missing, or unsupported input cannot mutate the
  document.
- The native Layout Inspector owns incomplete drafts, reports authored,
  defaulted, mixed, applicable, and skipped state, and converges pointer,
  keyboard, focus, and accessibility operation on one identity-gated command.
- Scene preparation, structural layout, typography snapshots, breakpoint
  comparison, Preview planning, and safe static CSS read the same canonical
  value. Static output emits closed allowlisted two-segment `clamp()` rules;
  responsive literals remain later and therefore retain precedence.

No schema-number migration is required: the existing versioned scalar property
envelope already preserves unknown omission, property origin, and stable
property identity. Older packages contain no fluid property and therefore keep
their exact fixed appearance. Page duplication regenerates the embedded
`FluidValueID` while preserving the values and curve.

## Focused evidence source (not executed)

- `TransformModelTests.testFluidValueCodecResolutionValidationAndRoundTrip`
- `TransformModelTests.testFluidValueRegistryCommitsApplicableSubsetPersistsAndRestoresExactInverse`
- `TransformModelTests.testFluidValueFeedsLayoutTypographyContainerAndSafeStaticOutputWithOverridePrecedence`
- `CommandKernelTests.testPageDuplicateRemapsFluidValueIdentityAndPreservesFixedFallback`
- `SiteForgeLaunchTests.testFluidResponsiveValueAuthoringPreviewResetAndAccessibilityJourney`

The actual-app source covers native authoring, Mobile resolution, breakpoint
comparison, Escape cancellation, removal, accessibility identifiers, and
original-resolution screenshot attachment. No build, test, UI automation, or
visual acceptance ran under the owner pause.

## Explicitly deferred

Custom viewport anchors or curves, intentional non-monotonic values, token
binding, tracking, X/Y position, Grid columns, responsive style/content/assets
or components, custom breakpoints, container queries, simultaneous graph/canvas
previews, broad browser/export parity, large-fixture budgets, OS-level assistive
technology certification, localization matrices, and release acceptance remain
outside this slice. The normative SF-0604 module remains Partial.
