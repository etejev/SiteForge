# SF-AUTHORING-096 — Form accessibility and validation completion

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**

Bounded requirements: `SF-0701-002/004/006`, `SF-0702-002/004/006`,
`SF-0705-002/004/006`, and `SF-1006-002/003/004/006`.

## Implemented source contract

- Content and Accessibility now consume one read-only projection of canonical
  `form.field.v1` metadata. It reports control type, accessible name, machine
  name, required state, help, options, validation bound, and property
  provenance without creating a second writable model.
- Mixed field selections report `Mixed` instead of copying the primary
  field's value. A shared configuration can commit only after every mixed
  draft is resolved deliberately; incompatible selected objects remain named
  as skipped and unchanged.
- The form-level Accessibility surface reports configured, required, and
  submit-control counts; links back to the canonical Content controls; and
  exposes the existing category-only local-validation action and result.
- Validation drafts and results remain scene-local and contain no visitor
  value in history, packages, recovery, announcements, or diagnostics.
- Submit output retains the established safe boundary: semantic static output
  is keyboard reachable but remains disabled, `aria-disabled`, and explicitly
  unconfigured until an approved destination capability exists.
- All metadata writes still pass through `FormInspectorCommandRegistry` with
  document/page/revision/scene/renderer/selection identity, strict typed
  validation, one atomic command, exact inverse, and stable property/option
  identities. Escape restores the committed projection.

## Added source evidence

- `TransformModelTests.testFormInspectorAccessibilityPresentationPreservesMixedValuesAndProvenance`
- `SiteForgeLaunchTests.testFormAccessibilityValidationAndContentInspectorJourney`

The actual-app journey edits a real Email field through Content, inspects its
canonical accessible role/name/required state, validates the owning Form via
Accessibility, checks the safe submit boundary, and exercises Undo/Redo.

No build, test, UI automation, visual review, `./sf verify`, commit, push, or
hosted check was executed for this source-only slice. The cited requirements
remain Partial pending the deferred gate.

## Explicit exclusions

Connected submission destinations, visitor-data persistence, network or
server behavior, success routing, consent/anti-abuse policy, analytics,
advanced repair automation, broad VoiceOver/localization matrices, scale
certification, preview/export parity beyond the existing safe static emitter,
and release acceptance remain deferred. No owner decision is required because
the implementation preserves the existing unconfigured-submission boundary.
