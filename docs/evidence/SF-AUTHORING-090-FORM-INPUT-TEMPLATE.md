# SF-AUTHORING-090 — Form Input insertion template

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED.

Bounded requirements: `SF-0405-001/002/004/005/006` and
`SF-1006-001/002/004/005/006`. Normative modules remain Partial.

The Forms category now presents Input only as an action into a currently
selected, available Form. The native Insert menu offers the same command.
Both paths call the existing insertion registry and one canonical insert-node
transaction. The registry rejects a non-Form parent, cancellation, stale
identity, unavailable/locked/hidden parents, invalid geometry, and duplicate
NodeID before mutation. An Input is an existing Text node with a stable NodeID,
240×36 default frame, defaulted `content.text`, and defaulted `form.field.v1`
kind/label/name/required properties. Its valid, deterministic field name is
derived from NodeID, not user-local text. It remains editable in the existing
Content Inspector. Static-output compilation already consumes the same field
metadata for an escaped labeled native HTML input; no second field schema or
project-side visitor values are introduced.

Source tests added but **not run** under the owner's testing pause:
`InsertionModelTests.testInputTemplateRequiresFormParentAndPreservesFieldIdentityThroughHistory`
and `SiteForgeLaunchTests.testFormInputTemplateInsertsOnlyIntoSelectedFormJourney`.
The latter retains a window screenshot attachment for later visual review.
No compile, actual-app, output, persistence, accessibility, or full-gate pass
is claimed. Submission/runtime data handling, other form control kinds, and
release acceptance remain deferred.
