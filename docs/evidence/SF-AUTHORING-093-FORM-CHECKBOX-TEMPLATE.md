# SF-AUTHORING-093 — Form Checkbox template

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED.

Bounded requirements: `SF-0405-001/002/004/005/006`,
`SF-1006-001/002/004/005/006`, and `SF-1202-002/004`.

Checkbox is a Form-only Text-backed template with deterministic 240×28
geometry, stable identity, defaulted label/name/required metadata, and
canonical `checkbox` kind. Native Elements/Insert actions share one command
path. Safe output emits an escaped labeled checkbox; project state contains
no visitor checked value.

Shared tests cover insertion, validation, exact undo/redo, serialization,
output, Inspector discovery, and menu availability in the passing 640-test
checkpoint. Runtime submission and visitor-state behavior remain deferred.
