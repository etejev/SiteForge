# SF-AUTHORING-116 — Component Link Action Property

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED (Development Prompt 3 of 10)

Requirements: bounded `SF-0902-001`–`008`, supporting `SF-0905-001`–`008`.

## Delivered source

- Stable `ComponentActionPropertyID` and definition metadata for Button/Link destinations.
- Strict path-free encoding for none, page, section, and validated external URL values.
- Identity-gated expose, author, and reset commands using the existing atomic property transaction path.
- Schema-v13 persistence, authored/inherited/conflict projection, and immutable graph resolution for canvas/static-output consumers.
- Focused source coverage for author/reset, undo/redo, package round trip, malformed input, and resolved child identity.

## Deferred

The native controls and destination-transfer integration below are now
source-implemented by SF-AUTHORING-117. Its nine new test selectors and the
Prompt-3 selector remain unrun; see
`SF-AUTHORING-117-COMPONENT-ACTION-INTEGRATION.md`. This supersedes the prior
implementation gap without claiming verification.

Slots, arbitrary event graphs, animations, remote actions, nested components,
preview/export certification and release acceptance remain deferred. Native
action/transfer source integration is recorded by SF-AUTHORING-117. Per owner
policy no test, build, checker, UI automation or verification command was
executed; Prompt 10 owns the accumulated gate.
