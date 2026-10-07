# SF-AUTHORING-091 — Form Email field template

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED.

Bounded requirements: `SF-0405-001/002/004/005/006`,
`SF-1006-001/002/004/005/006`, and `SF-1202-002/004`.

Email is a Form-only Elements and native Insert action. It inserts one existing
Text node through `InsertionCommandRegistry` with stable NodeID, 240×36
default geometry, deterministic defaulted label/name/required metadata, and
canonical `email` field kind. The existing Content Inspector edits that same
metadata; the safe output compiler emits a labeled escaped
`<input type="email">`. Non-Form, stale, hidden, locked, unavailable,
invalid, and cancelled commands remain mutation-neutral.

Source coverage is shared by
`testFormFieldTemplatesPreserveKindsOptionsHistoryAndSafeOutput` and
`testFormFieldTemplateMenuParityInspectorAndHistoryJourney`. Both are covered
by the passing 640-test checkpoint. Connected submission handling and release
acceptance remain deferred.
