# SF-AUTHORING-026 — Semantic HTML element authoring v1

## Bounded scope

Implements the canonical, authored semantic-element choice for current native
node kinds. `semantic.html.v1.element` is absent for a deterministic kind
default and is present only for an authored choice. The supported surface is
limited to structural landmarks for Frame/Section/Stack/Grid, paragraph and
headings for Text, and fixed native semantics for Image/Button/Link.

Raw HTML, custom attributes/elements, generated markup, browser runtime,
routes, CMS, export/publishing, and SF-1204 are excluded.

## Focused evidence

- `TransformModelTests.testSemanticElementRegistryValidatesMixedSelectionAndExactHistory`
  passes: defaults/provenance, compatible-subset edits, cancellation and stale
  neutrality, exact undo/redo PropertyID restoration, reset-to-default and
  canonical encode/decode.
- The native Design Inspector exposes `Semantic HTML`, an accessible Element
  picker and Reset action through the same identity-gated transaction registry.
- `SiteForgeLaunchTests.testSemanticHTMLElementInspectorKeyboardResetAndPreviewJourney`
  passed: a real Frame is inserted, the accessible picker authors `<article>`,
  and Reset returns its deterministic `<div>` provenance.
- `CanvasRendererTests.testLocalPreviewStateFreezesRevisionAndRejectsStaleRefreshes`
  passed after immutable preview objects began carrying their canonical
  semantic-element provenance as metadata only; it does not add pixels,
  editor chrome, or document/history writes.
- `ProjectPackageTests.testSemanticElementPersistsAcrossPackageReopenAndOwnedRecovery`
  passed: authored `<article>` preserves stable node/property identity through
  the real package encode/decode and owned recovery snapshot paths.
- `CommandKernelTests.testStaticPageDuplicateRemapsInternalLinksAndDeleteUndoPreservesIntent`
  passed with authored semantic metadata: page duplication creates fresh node
  and property identities while resolving the same `<a>` intent on the copy.

## Current checkpoint

Focused non-UI verification passed 4/4 on 2026-09-26. The retained native
Inspector journey passed before macOS XCTest later failed to enable automation
mode; that runner failure is external to semantic authoring and is not treated
as product evidence. SF-AUTHORING-026 remains IN PROGRESS until its separate
milestone gate is intentionally scheduled.
