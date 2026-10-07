# SF-AUTHORING-094 — Form Select template

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED.

Bounded requirements: `SF-0405-001/002/004/005/006`,
`SF-1006-001/002/004/005/006`, and `SF-1202-002/004`.

Select is a Form-only Text-backed template with 240×36 geometry and two
deterministic default options. Each option receives a stable ID derived from
the field NodeID and its ordered slot; labels and values pass the canonical
select-options encoder. Re-preparing the same identity produces identical
metadata, while Content Inspector edits retain the established option IDs.
Safe output escapes ordered option labels/values.

Shared tests assert deterministic option identity/order, document round-trip,
exact history, native availability, Inspector discovery, and static output in
the passing 640-test checkpoint. Dynamic option sources remain deferred.
