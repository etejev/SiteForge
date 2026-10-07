# SF-AUTHORING-092 — Form Text Area template

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED.

Bounded requirements: `SF-0405-001/002/004/005/006`,
`SF-1006-001/002/004/005/006`, and `SF-1202-002/004`.

Text Area is a Form-only Text-backed template with a deterministic 240×100
frame and canonical `textarea` metadata. Elements and Insert use the same
validated atomic insertion and exact inverse. Content Inspector owns field
draft/configuration editing; static output uses the existing escaped,
labeled `<textarea>` path. No rich-text or visitor values are serialized.

The shared model/output/history and actual-app journeys are covered by the
passing 640-test checkpoint. Broader release acceptance remains deferred.
