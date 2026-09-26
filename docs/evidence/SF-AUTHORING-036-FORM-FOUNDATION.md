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

Focused evidence: `SiteForgeTests/CanvasRendererTests/`
`testSafeHTMLEmitterEmitsAccessibleTextField`,
`testSafeHTMLEmitterSafelyEmitsCheckboxSelectAndUnconfiguredSubmit`,
`testSafeHTMLEmitterRejectsNonFormOrMalformedSelectControls`, and
`testCanonicalFormSelectOptionsPreserveStableOrderAndRejectUnsafeValues`
passed 4/4 on 2026-09-26.

Deferred: native Form/field insertion and Inspector controls, command/history
editing, runtime visitor values/submission destinations, package migration,
and actual-app UI journeys. No completion claim is made for SF-AUTHORING-036.
