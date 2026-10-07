# SF-AUTHORING-099 — Semantic Heading template

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**

Requirements: bounded `SF-0405-001/002/004/005/006`, `SF-0507-001/002`, and
`SF-1203-002/003/004/006`.

## Delivered source contract

- Heading is a visible Basic Elements row and native `Insert Heading at Center`
  action. Both invoke the existing identity-gated Text insertion transaction.
- The template creates one stable Text NodeID with 360×48 geometry, `Heading`
  default content, System Bold 32-point type with 38-point line height, and an
  authored typed `<h2>` semantic element.
- Content, Typography, semantic-element editing, renderer adoption, selection,
  Layers, accessibility, package serialization, and exact Undo/Redo use their
  existing canonical paths. There is no Heading node kind or output fork.
- Invalid parent, stale scene/revision, cancellation, node limits, lifecycle
  unavailability, and transaction rejection retain the insertion registry's
  established neutral behavior and sanitized diagnostics.

## Added unrun evidence source

- `InsertionModelTests.testHeadingTemplateUsesCanonicalTextSemanticAndTypographyDefaults`
- `SiteForgeLaunchTests.testHeadingTemplateElementsMenuTypographyAndHistoryJourney`

No build, test, UI automation, screenshot review, full verification, commit, or
push ran under the owner testing pause. These sources are not passing evidence.

## Deferred scope

Automatic heading-level selection, outline validation/repair, generated table
of contents, rich-text ranges, responsive typography, preview/export parity,
large-fixture and assistive-technology certification, and release acceptance
remain outside this bounded template slice.
