# SF-AUTHORING-118 — Named component slots and definition fallback

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED (Development Prompt 5 of
10). Supplied instance content remains blocked by OD-018; the full milestone
is not complete. Date: 2026-10-13.

## Contract and owner decision

Bounded requirements: `SF-0902-001`–`008`, `SF-0903-001`–`008`,
`SF-0905-001`–`008`; supporting `SF-0304-001/003/005`,
`SF-0308-003/004/005/008`, `SF-1201-003` and `SF-1203-003`.
Dependencies: ADR-0018, component transfer/override/action work (111/113/117),
and the shared SF-PRODUCT-UI-008 native visual components.

Specification §9.3 requires slot cardinality, constraints, projected identity,
ordered content and fallback. It does not choose supplied-content storage or
cardinality. ADR-0018 and canonical validation explicitly keep linked instances
childless; ordinary child ownership is single-parent and ordered. Changing that
contract has broad insertion/history/transfer/layout/selection consequences.
OD-018 records the recommended instance-owned graph approach, alternatives,
tradeoffs, affected IDs, decision deadline and safe assumption. This prompt
implements the largest useful slice supported by existing ownership: named
fallback slots, not a second encoded subtree store or an invented supply model.

## Delivered source behavior

- A non-root Frame/Section/Stack/Grid in a definition can expose its existing
  ordered children as a named slot. Stable `ComponentSlotPropertyID`, label and
  closed `ordered-fallback-children` metadata are stored in schema v14.
  `childIDs` remains the sole serialized order/ownership/default source.
- Native Content controls expose/rename/remove the binding with captured
  identity, Apply/Return and Cancel/Escape. Removal deletes metadata only;
  fallback containers, child IDs, content, ordering and geometry remain intact.
  Linked instances show inherited fallback, empty state and ordered child names.
  Edit Definition Fallback opens/selects the actual canonical container; existing
  Insert/Elements and Layers commands add/reorder real fallback children.
  The Inspector previews at most eight ordered roots and names the remaining
  count; the definition's existing Layers view owns complete child inspection.
- Mixed selection is explicit inspection-only. Read-only/inapplicable controls
  retain explanations. Supplied instance content is visibly unavailable pending
  OD-018. No working-looking supply, reset-to-inheritance or migration button is
  fabricated for a state that cannot yet be authored. An inherited instance is
  already using fallback.
- The component registry/kernel retain document/page/revision/scene/renderer
  validation, exact metadata inverses and stable selection return paths.
  Labels are bounded/unique across exposed property types. Root/nested slots,
  duplicate bindings/ownership, cycles and forged supplied state are rejected.
  Retargeting a retained slot ID to a different source while instances survive
  is guarded at the complete-transaction boundary.
- Immutable component expansion already owns fallback ordering, layout, hit
  testing, accessibility, Preview and static output. Slot metadata is stripped
  from the expanded/detached graph; virtual children retain their existing
  deterministic instance/source IDs. No authored coordinates or painter
  transforms were changed.
- Dependency details count/list named fallback slots. Clipboard validates slot
  topology, compares fallback graphs/metadata structurally, remaps imported
  slot IDs and child identities, reuses equivalent definitions and rejects
  supplied/nested slot payloads with `unsupported-slot-content` before mutation.
  Same-project stale binding reuse is rejected. Detach and confirmed definition
  deletion retain the existing complete graph/history path.
- Schema v14 reads supported earlier documents unchanged; older headers cannot
  contain the new slot namespace. Unsupported supplied namespaces remain
  invalid rather than being dropped. Existing current/future schema assertions
  now use v14/v15; historical fixtures were not rewritten.

## Pending tests — six new selectors, zero executions

CommandKernelTests:

- `testComponentSlotFallbackBindingOrderingHistoryAndSchemaRoundTrip`
- `testComponentSlotFallbackRejectsCancelledStaleNestedCyclicAndSuppliedOwnership`
- `testComponentSlotFallbackDefinitionUpdatesDetachAndOutputKeepChildIdentity`

ClipboardTransferTests:

- `testComponentSlotFallbackTransferImportsAndReusesOwnedOrderedGraph`
- `testComponentSlotTransferRejectsUnsupportedSupplyBeforeMutation`

Actual-app source:

- `testComponentSlotFallbackNativeAuthoringCancelHistoryAndReopenJourney`

The native journey uses real menus/fields to create fallback content, expose
the slot, cancel a name draft, inspect inheritance, open/edit the canonical
fallback, undo insertion/binding removal, save and relaunch the package. Named
window screenshots are attached only when the journey eventually runs. No new
captures or runtime results exist in this prompt.

Prompt 10 must run these selectors, affected component/action/transfer,
schema/history/recovery and rendering tests, native visual inspection and the
accumulated gate. The owner prohibits tests/builds/parser or compiler checks,
linters/scripts/repository checks, UI automation and hosted/GitHub work now.

## Source review and files

Manual source/diff review covered namespace/type/schema gating, childless
instance compatibility, ordered single-parent ownership, root/nesting/cycle
constraints, stable binding transitions, exact inverse paths, transfer mapping,
renderer metadata stripping, captured native draft identity and redacted
diagnostics. No test weakening, alternative node store, hidden mutation control,
generated data, private path, icon/update change, commit or push was added.

- Production: `DocumentModel.swift`, `CommandKernel.swift`, `TransformModel.swift`,
  `InsertionModel.swift`, `ClipboardTransfer.swift`, `WorkspaceShellModel.swift`,
  `WorkspaceShellView.swift` under `SiteForge/`.
- Test source: CommandKernel/ClipboardTransfer/LinkAuthoring/ProjectResource/
  InsertionModel/SnappingGuideModel tests and SiteForgeLaunchTests.
- Docs: queue, implementation/project status, changelog, handoff, requirement
  evidence, visual contract, ADR-0018 fallback clarification, OD-018 and this note.

## Remaining scope and next action

Supplied-content authoring/ordering/reset, authored empty versus inheritance,
allowed-type/cardinality authoring, slot conflict migration, nested slots,
supplied-content transfer/detachment and associated runtime semantics await
OD-018. Broader Preview/export parity, variants, nesting, remote libraries and
release acceptance remain deferred. Compilation, keyboard/AX focus, minimum
layout, screenshots, autosave/recovery and actual verification are Prompt-10
risks; source review is not a substitute.

Recommended Prompt 6: complete supplied slot content only after the OD-018
ownership/cardinality decision. If the decision is still open, the independent
next slice is bounded component property grouping/ordered Inspector presentation
under SF-0902, keeping slot supply gated and reusing stable property paths.
