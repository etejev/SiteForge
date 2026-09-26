# SF-AUTHORING-036 — Form model and safe-control output v1

Bounded evidence for `SF-1006` and the existing internal static-output safety
boundary. Canonical text-field metadata now recognizes `text`, `email`,
`textarea`, `checkbox`, `select`, and `submit`. Select options are a strict,
ordered typed payload with stable option IDs, nonempty unique values, bounded
labels/values, and deterministic encode/decode validation. Form-field metadata
is valid only on a Text node owned by a Form node.

The internal safe HTML emitter accepts only a known Form owner, escapes all
field/help/option values, emits ordered `<select>` options, and marks submit
controls disabled and `data-siteforge-submission="unconfigured"`. It never
emits a destination or runtime submission behavior.

The static-build compiler now projects a validated canonical page into the
internal render tree before emission, retaining the canonical parent/child
relationship rather than treating fields as top-level markup. Generic document
transactions provide atomic property history; page duplication regenerates
select option IDs while retaining option labels and values; package and owned
recovery round trips preserve field identity and ordered options.

Focused evidence passed 5/5 on 2026-09-26:

- `CanvasRendererTests.testSafeHTMLEmitterSafelyEmitsCheckboxSelectAndUnconfiguredSubmit`
- `CanvasRendererTests.testSafeHTMLEmitterRejectsNonFormOrMalformedSelectControls`
- `CanvasRendererTests.testCanonicalFormSelectOptionsPreserveStableOrderAndRejectUnsafeValues`
- `CommandKernelTests.testFormFieldsPreserveAtomicHistoryAndRemapSelectOptionsOnPageDuplicate`
- `ProjectPackageTests.testFormPackageRoundTripPreservesOrderedControlMetadata`

Deferred: native Form/field insertion and Inspector controls, a form-specific
identity-gated edit registry and diagnostics, accessible app journeys,
visitor-entered values, validation rules, submission destinations, success or
error surfaces, anti-abuse controls, runtime behavior, scale evidence, and
release acceptance. No completion claim is made for SF-AUTHORING-036.
