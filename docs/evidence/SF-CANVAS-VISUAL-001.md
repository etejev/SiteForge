# SF-CANVAS-VISUAL-001 Canvas Visual Contract Evidence

Date: 2026-08-13

Requirements: bounded evidence for `SF-0401-001`, `SF-0401-003`,
`SF-0401-005`, `SF-0405-006`, `SF-0406-001`, `SF-0406-002`, `SF-0406-006`,
`SF-0406-008`, and `SF-1902-008`.

## Corrected boundaries

- A fresh or adopted document waits for the real AppKit canvas size, then
  centers the noncanonical pasteboard at the existing 100% initial zoom. The centered pasteboard survives
  resize/pane changes until explicit viewport navigation; canonical node
  coordinates and package/history content are unchanged.
- The blank state is a compact centered material card with hit testing disabled.
  It cannot shield the surrounding native canvas from insertion, selection,
  pan, or contextual input.
- `CanvasTextLayout` supplies one viewport object rectangle, scaled font,
  insets, line fragment, and glyph bounds to both native tile rasterization
  and `InlineCanvasTextView`. The only Y conversion remains at the tile
  drawing boundary.

## Focused evidence

- `CanvasTextRenderingTests.testSharedTextLayoutKeepsGlyphsInsideOneViewportRectAcrossMatrix` passed at 25%, 100%, and 800% zoom; 1×/2× backing scale; and positive/negative viewport origins. It verifies device-pixel-tolerant glyph containment and vertical centering plus the single tile conversion.
- `CanvasViewportTests.testFreshWorkspaceFitsPasteboardWithoutMutatingAuthoredCoordinates` passed, proving the first usable canvas size centers the pasteboard at the existing 100% zoom without canonical mutation.
- Actual-app `testNativeCanvasRendererAdoptsAuthoredObjectsAndPreservesInput` and `testInlinePlainTextEditingCommitCancelUndoRedoAndAccessibilityJourney` passed. Their retained XCTest attachments cover truthful blank state, inserted object adoption, native text draft/commit/cancel, selection, undo/redo, and accessibility.
- Owner-supplied visual reports were inspected before this correction. They showed a top-pinned empty state and glyphs rendered below the selected text rect; neither is treated as acceptable evidence after this change.
- `./sf test half` passed 303 unit/integration tests and final local `./sf verify` passed all repository checks, 303 unit/integration tests, and 33 UI tests on 2026-08-13. The final XCTest result bundle retains app-window screenshots for the native draft, committed, and cancelled text states; the external automation overlay is not treated as application evidence.

## Limits

This is native bounded plain text, not production text shaping or release visual
acceptance. Cross-hardware visual review, OS-level VoiceOver settings, rich
text, responsive typography, export rendering, and final performance budgets
remain unproven.
