# SF-AUTHORING-098 — General authored accessibility metadata

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**

Requirements: bounded `SF-0701-002/004/006`, `SF-0702-002/004/005/006`, and
`SF-1203-002/003/004/005/006`.

## Delivered source contract

- `accessibility.v1.name` and `accessibility.v1.help` are canonical authored
  string properties with strict whitespace, control-character, length, origin,
  node-kind, and namespace validation.
- Frame, Text, Section, Stack, Grid, Button, and Link use the general schema.
  Image alternative text and Form accessibility retain their established
  dedicated schemas; semantic role remains derived from the typed HTML element.
- The Accessibility Inspector presents defaulted, authored, mixed, skipped,
  and unavailable states without borrowing the primary selection's value.
  Native fields support Return/focus-loss commit, Escape cancellation, empty-
  value removal, and Reset.
- `AccessibilityMetadataCommandRegistry` validates document, page, revision,
  scene, renderer, ordered selection, lifecycle, lock/hidden/availability, and
  applicable subset before preparing one existing canonical batch transaction.
  Existing PropertyIDs survive replacement and exact Undo/Redo.
- Immutable canvas accessibility snapshots receive the authored name/help.
  Safe static markup escapes them into `aria-label` and `aria-description`;
  editor selection and focus chrome never enter authored output.

## Added unrun evidence source

- `TransformModelTests.testAccessibilityMetadataRegistryCommitsMixedSubsetAndExactHistory`
- `CanvasRendererTests.testCanonicalAccessibilityMetadataReachesSafeStaticOutput`
- `SiteForgeLaunchTests.testGeneralAccessibilityMetadataInspectorUndoRedoJourney`

No build, test, UI automation, screenshot review, full verification, commit, or
push ran for this slice under the owner testing pause. These tests are evidence
source, not passing evidence.

## Deferred scope

ARIA relationships and live regions, author-controlled tab order, broader
landmark vocabularies, localization, comprehensive VoiceOver/Full Keyboard
Access certification, preview/export parity, capacity/release acceptance, and
the dedicated Image/Form accessibility workflows remain outside this slice.
