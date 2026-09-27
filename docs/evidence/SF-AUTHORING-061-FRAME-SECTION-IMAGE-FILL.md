# SF-AUTHORING-061 — Frame/Section local image fill foundation v1

Development Prompt 8 of 10. Bounded evidence for SF-0508-001–006,
SF-0801-001–006, and SF-0802-001–006. The normative modules remain Partial.

## Implemented contract

- Frame and Section may author one local image background using a stable
  `AssetID` and Fit/Fill mode under `style.fill.image.v1.*`. Omission retains
  the prior fill. An absent resource preserves the reference and displays a
  recoverable Inspector status; malformed/unsupported properties fail model
  validation. The existing asset resource store remains authoritative.
- The native Design Inspector offers Choose Image, Fit/Fill, and Remove. Its
  commands pass document/page/revision/scene/renderer/selection guards and
  commit through typed property transactions. Mixed applicable/incompatible
  selections report skipped objects; undo restores prior property identity.
- The immutable canvas render plan and local Preview paint the image above
  existing fill layers inside the authored rounded clip. Object opacity
  applies once to the completed composite. Static output uses the existing
  content-addressed asset path, with a bounded missing-reference fallback.
  Selection and grid remain editor-only.
- Asset usage includes both Image nodes and image-fill references. An explicit
  destructive choice detaches in-use fills and removes Image nodes plus the
  asset in one reversible batch; cancellation is neutral.

## Focused results and visual review

- `TransformModelTests.testFrameSectionImageFillIsAtomicScopedAndMissingSafe`:
  1/1 passed. Frame/Section mutation, mode, cancellation, malformed state,
  unavailable resource, safe deletion, exact undo property identity, encode/
  decode, and closed static-path projection are covered.
- `CanvasTextRenderingTests.testFrameImageFillPaintsInsideAuthoredBoundsAtNativeScale`:
  1/1 passed at 1× and 2×. Exact inside/outside pixels and 50% grouped
  opacity are asserted.
- `SiteForgeLaunchTests.testLocalImageAssetImportAuthoringUndoRedoAndReopenJourney`:
  1/1 passed in a fresh native app process, extending the existing image
  journey through Frame image fill, Fit/Fill, undo/redo, Save, and actual
  close/reopen. The real asset menu and native mode pop-up were used.
- Four original-resolution retained XCTest captures were reviewed: empty
  (`9DCBD460-DE83-406D-BFEB-C4223DF7B3BB.png`), authored Fill
  (`98C9C7FA-878A-43CF-AF4C-4E52C22542B6.png`), Fit
  (`7F18E017-D39F-431F-8293-CF42686B9865.png`), and reopened Fit
  (`A965B500-C631-456F-8B11-F32D9F9B7641.png`). The normal window,
  labeled Inspector, page/grid boundary, image crop, Frame bounds, and
  selected-object identity are legible; no insertion-preview ghost remains.

The focused UI result bundle reports existing SwiftUI view-publication and
QoS-inversion runtime warnings. This slice does not claim to resolve them.
`git diff --check`, JSON parsing, and repository secret scanning passed.
The aggregate repository check is not green: the traceability index still
contains pre-existing stale/duplicate evidence entries, and its legacy
headless renderer type-check omits current renderer dependencies. Neither
failure was introduced or waived by this image-fill slice; Prompt 10's
authoritative verification must resolve or explicitly account for them.
No full local gate or hosted run was performed at Prompt 8. Multi-image layers,
masks, filters, arbitrary crop/focal adjustment, responsive sources, remote
resources, browser runtime, broad color-profile/accessibility/performance
matrices, publishing, and release acceptance remain deferred.
