# SF-AUTHORING-060 — Native text foreground color foundation v1

Development Prompt 7 of 10. Requirements: bounded SF-0507-001–008,
SF-0508-001–008, SF-0509-001–008; supporting SF-0305/SF-0306,
SF-0701/SF-0702, and SF-1204. These normative modules remain Partial.

## Implemented contract

- Text, Button, and Link accept an optional complete four-channel normalized
  sRGB foreground under the established typography property namespace.
  Omission preserves the prior automatic foreground. Incomplete, nonfinite,
  or out-of-range channel sets fail document validation.
- Local Color Token bindings use the existing target-keyed registry and retain
  a literal foreground fallback. Binding, unbinding, recoloring, reset,
  missing-token resolution, and safe in-use deletion retain stable IDs and
  one typed transaction per committed edit with exact history.
- The native Design Inspector has a visible color well, hexadecimal field,
  Reset Color action, and Text Foreground token target. Drafts remain local;
  invalid input does not mutate the document. Mixed and incompatible
  selections report their state.
- The immutable native render plan, committed text layer, live inline editor,
  and closed static output use the same resolved sRGB foreground. Selection
  chrome remains editor-only. Neither text geometry nor inherited automatic
  contrast is changed by an omitted foreground.

## Focused evidence

- `TransformModelTests.testTextForegroundLiteralTokenFallbackHistoryAndValidation`:
  passed 1/1, including normalized validation, Text/Button intent, token
  recoloring and fallback, unbind, exact property-ID undo, persistence round
  trip, and typed static color declaration.
- `CanvasTextRenderingTests.testAuthoredTextForegroundSharesLiveLayerAndInlineEditorWithoutGeometryChange`:
  passed 1/1 at 25%, 100%, and 800% zoom, 1×/2× backing scale. A first run
  exposed an sRGB-versus-calibrated-color mismatch; the shared inline color
  construction was corrected and the exact test passed.
- `SiteForgeLaunchTests.testTextForegroundNativeInspectorTokenAndInlineParityJourney`:
  passed 1/1 in a fresh native process. It exercises hexadecimal Return,
  invalid draft and Escape, token creation/binding, live inline editor frame
  parity, unbind, and automatic reset.
- Four final original-resolution XCTest attachments were reviewed: authored red
  (`4EE2B785-B2B8-4964-8160-DA2EEB1920B3.png`), bound green
  (`7F81ADBB-06D7-410F-906D-4D6F8F11BCE2.png`), bound inline editor
  (`5C42FFFE-7EDD-477E-A59A-291A5525B590.png`), and automatic reset
  (`59115976-5484-49B2-A3B4-041185356939.png`). The normal window, readable
  Inspector, artboard/grid distinction, upright contained glyphs, selection
  alignment, and absence of ghost objects were visually checked. A visible
  camel-case target status found during review was corrected in production.

No full local gate or hosted check was run at Prompt 7. Broad rich-text spans,
paragraph/background color, hover/visited states, imported or variable fonts,
token themes/aliases/modes, arbitrary CSS, browser runtime, publishing, and
release acceptance remain deferred. Actual package save/close/reopen and
cross-platform color-profile acceptance are not claimed by this focused slice.
