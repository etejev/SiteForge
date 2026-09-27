# SF-AUTHORING-037 — Local form-validation and preview-state foundation v1

Bounded noncanonical evidence for `SF-1006-001`–`005` and `SF-1006-008`.
`LocalFormValidationEngine` resolves canonical Form field metadata against an
explicit caller-owned `FormVisitorValueSnapshot`. The snapshot is deliberately
not Codable and is never accepted by a command, history, package, autosave or
recovery API.

The resolver covers required text, a default bounded 4,096-character text input,
local syntax-only email validation, required checkbox consent, and Select
membership. Each result identifies only document revision, Form NodeID and
field NodeID, and reports category-only failures. It rejects cancellation,
stale document/page/scene/renderer identity, unavailable Forms and malformed
field schemas without mutating canonical content. Its static-output indicator
states `unavailableSubmission`; validation neither submits nor stores a
destination. The existing native Form Inspector exposes one scene-local
`Validate Empty Local Draft` action and category-only result/status surface.
It never accepts or stores visitor input in canonical state.

The same operation is available through the native Form menu using
Command-Option-V. Its accessibility summary has a stable label, category/count
value, and submission-unavailable hint; no field labels or visitor values
cross that boundary.

The Form Inspector also canonically stores an optional authored maximum-length
rule for Text, Email, and Text Area fields. The rule is omitted when unset,
strictly bounded to 1…4,096, and compiles through the existing atomic
Form Inspector transaction with an exact inverse. Required, Select membership,
and Checkbox consent retain their existing typed rules.

Focused evidence passed 3/3 on 2026-09-26:

- `TransformModelTests.testLocalFormValidationResolvesValidInvalidControlsAndRedactsValues`
- `TransformModelTests.testLocalFormValidationRejectsCancelledStaleAndInvalidSchemasWithoutMutation`
- `CanvasRendererTests.testLocalFormValidationPreviewStateAdoptsOnlyCurrentCategorySnapshot`
- `TransformModelTests.testFormInspectorValidationBoundCommitsAndRejectsInvalidKinds`
- `CanvasRendererTests.testLocalFormValidationAccessibilitySummaryIsRedactedAndSceneLocal`

Deferred: real visitor-input controls and actual-app accessibility/UI evidence,
visitor value persistence, network/browser/server submission, destinations,
anti-abuse, analytics, success/error runtime surfaces, performance certification
and release acceptance. `SF-1006` remains Partial.
