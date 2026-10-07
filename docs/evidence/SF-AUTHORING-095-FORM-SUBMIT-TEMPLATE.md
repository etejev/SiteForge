# SF-AUTHORING-095 — Form Submit template

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED.

Bounded requirements: `SF-0405-001/002/004/005/006`,
`SF-1006-001/002/004/005/006`, and `SF-1202-002/004`.

Submit is a Form-only Text-backed template with deterministic 160×44 geometry
and canonical `submit` metadata. Elements and Insert share the typed,
identity-gated insertion transaction. Until a future approved submission
destination exists, safe static output deliberately emits a disabled,
keyboard-visible button with `aria-disabled` and an unconfigured status; it
cannot navigate or exfiltrate visitor data.

Shared source tests cover the disabled output boundary, Form-only validation,
history, persistence, menu parity, and Content Inspector discovery in the
passing 640-test checkpoint. Destinations, consent, anti-abuse, retention,
connected services, and release acceptance remain deferred.
