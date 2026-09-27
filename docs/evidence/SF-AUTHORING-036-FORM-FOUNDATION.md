# SF-AUTHORING-036 — Form model, insertion, and field Inspector v1

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

The native editor exposes Form in Elements and Insert, creating an empty 320×180
canonical Form container through the shared insertion transaction. Its Content
destination truthfully explains that submission, destination, validation, and
visitor data are unavailable. A selected Text child of Form receives native
Field controls for kind, label, machine name, help, required, and ordered
Select options. Local drafts use `FormInspectorCommandRegistry`, which gates
document/page/revision/scene/renderer/selection identity, validates ownership
and typed field data, applies only applicable children, and emits one
invertible generic command. Invalid, cancelled, stale, locked, hidden,
unavailable, missing, duplicate, and inapplicable input is neutral.

Focused evidence passed 9/9 on 2026-09-26:

- `CanvasRendererTests.testSafeHTMLEmitterSafelyEmitsCheckboxSelectAndUnconfiguredSubmit`
- `CanvasRendererTests.testSafeHTMLEmitterRejectsNonFormOrMalformedSelectControls`
- `CanvasRendererTests.testCanonicalFormSelectOptionsPreserveStableOrderAndRejectUnsafeValues`
- `CommandKernelTests.testFormFieldsPreserveAtomicHistoryAndRemapSelectOptionsOnPageDuplicate`
- `ProjectPackageTests.testFormPackageRoundTripPreservesOrderedControlMetadata`
- `InsertionModelTests.testFormInsertionIsCanonicalEmptyContainerWithStableIdentity`
- `TransformModelTests.testFormInspectorRegistryCommitsExactMetadataHistoryAndMixedSubset`
- `TransformModelTests.testFormInspectorRegistryRejectsInvalidCancelledAndStaleEdits`
- `ProjectPackageTests.testFormInspectorTransactionPersistsThroughPackageAndRecovery`

Deferred: native actual-app UI automation and visual evidence; visitor-entered
value persistence, submission destinations, success/error surfaces, anti-abuse
controls, runtime behavior, scale evidence, and release acceptance. Pure local
visitor validation is now tracked separately by SF-AUTHORING-037. No completion
claim is made for SF-AUTHORING-036.
