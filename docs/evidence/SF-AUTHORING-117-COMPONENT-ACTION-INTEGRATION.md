# SF-AUTHORING-117 — Native component actions and destination transfer

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED. Development Prompt 4 of 10 (2026-10-13).

## Requirements and dependency boundary

Bounded `SF-0902-001`–`008` and `SF-0905-001`–`008`; supporting
`SF-0308-003/004/005/008`, `SF-0806-002/003/004/006`,
`SF-1201-003/004`, and `SF-1203-003/004`.
Dependencies: SF-AUTHORING-111 component transfer, 113 override reconciliation,
116 action model and schema-v13 storage, and SF-PRODUCT-UI-008 shared chrome.
These normative modules remain Partial.

The owner explicitly prohibits tests, builds, compilers, linters, repository
checks, verification, UI automation and hosted/GitHub operations during this
prompt. Test source is added; no execution or visual acceptance is claimed.
Prompt 10 owns accumulated verification and source/runtime corrections.

## Delivered source behavior

- Content exposes/renames/removes a definition Button/Link action binding.
  The visible Edit Default Destination action opens the existing Interactions
  editor. Instance drafts use the same `NativeLinkDestinationFields` for None,
  page, section and validated external HTTP(S) destinations.
- Apply/Return commits through `ComponentCommandRegistry`. Cancel/Escape
  restores committed values. Drafts capture document/page/revision/scene/renderer
  identity, and the existing Inspector identity key discards replaced-context
  drafts. Mixed/inapplicable selection is explicitly inspection-only under the
  established local-component contract; it never borrows a primary value.
- Inherited/authored provenance, missing destinations, retained missing-binding
  conflicts, Reset Override, Reset Missing Action and Reset All Component
  Overrides are visible and accessible. Controls use the shared native group,
  spacing, validation and field roles.
- The strict action codec now decodes None as a real target rather than
  Optional.none and rejects oversized encoded input before decoding. Malformed
  URLs are rejected before encoding; credentials, non-HTTP(S), whitespace and
  control characters remain invalid.
- A complete-transaction transition guard protects retained action values from
  definition/source retargeting. Removing a binding retains explicit conflicts;
  reset removes authored presence and its exact inverse restores PropertyID,
  value and origin through the existing kernel/history.
- Dependency inspection lists exposed actions and destination pages, including
  retained missing-page intent. Native page-deletion impact counts include action
  overrides. Rename preserves stable references; deletion does not rewrite them.
  Page duplication remaps only its explicit copied page/node identities. Component
  creation refuses to strand inbound action references to converted children.
- Clipboard capture validates action namespaces, duplicate keys/identities and
  destinations. Equivalent-definition fingerprints normalize binding IDs but
  retain effective destination semantics. Reuse/import carries explicit action
  and definition-node mappings; differing defaults cannot silently reuse a
  destination definition.
- Same-project paste retains external/page references and remaps copied section
  targets. Cross-project paste remaps only the existing contextual source-page
  mapping, copied node mapping, or imported/equivalent definition mappings.
  Unknown pages, absent/non-section targets, wrong-page target ownership and
  missing bindings fail before canonical mutation. The precise sanitized
  `unmapped-action-destination` finding names the recovery without a URL, path,
  UUID or content value. System clipboard behavior is unchanged.
- Immutable graph resolution feeds canvas, Preview and static output. Preview
  validates virtual component section targets against the resolved graph and
  caches each referenced page's section identities within the request. Previous
  snapshots remain immutable. Existing Link navigation is supported; Button
  destination intent is retained with an explicit unavailable-execution message.

## Source defects corrected during integration

1. The optional None decoding ambiguity in the Prompt-3 codec.
2. Missing action-binding retarget validation at registry/kernel boundaries.
3. Missing action reference coverage in clipboard mapping/equivalence and page
   impact/duplication handling.
4. Preview marking valid virtual component sections missing because it searched
   only canonical IDs.
5. Existing schema-test source still replacing/asserting v12 after the v13
   model landed; current-header expectations now use v13 and future-header v14.
   Historical fixture payloads are unchanged.

## Pending focused selectors — not executed

New CommandKernelTests source (five selectors):

- `testComponentActionCodecRetainsNoneAndStrictDestinationIntent`
- `testComponentActionRegistryRejectsCancelledStaleMalformedAndMissingDestinations`
- `testComponentActionMissingBindingResetAllAndRetargetGuardPreserveExactHistory`
- `testComponentActionLinkDestinationReachesImmutablePreviewAndStaticOutput`
- `testComponentActionPageRenameRemovalAndDuplicationPreserveStableIntent`

New ClipboardTransferTests source (three selectors):

- `testComponentActionTransferReusesEquivalentBindingAndKeepsExactOverrideHistory`
- `testComponentActionTransferRejectsUnmappedPageIntentWithoutMutationOrDiagnosticsDisclosure`
- `testComponentActionTransferRemapsCopiedSectionAndNeverReusesDifferentDefault`

New actual-app source (one selector):

- `testComponentActionNativeInspectorDraftResetHistoryAndReopenJourney`

Also execute the existing Prompt-3
`testComponentActionOverrideResetHistoryRendererPersistenceAndValidation`,
affected link/clipboard/component/Preview/page tests, and the accumulated
Prompt-10 gate. Nine new tests were written; zero were executed.
The native journey retains named exposed/authored/cancelled-reset/reopened
window screenshots when it eventually runs; no new screenshots exist now.

## Manual review and remaining risk

Files changed for this slice:

- Production: `SiteForge/DocumentModel.swift`, `CommandKernel.swift`,
  `TransformModel.swift`, `ClipboardTransfer.swift`, `WorkspaceShellModel.swift`
  and `WorkspaceShellView.swift` (all six reside in `SiteForge/`).
- Test source: `Tests/SiteForgeTests/CommandKernelTests.swift`,
  `ClipboardTransferTests.swift`, `LinkAuthoringTests.swift`,
  `ProjectResourceTests.swift`, `InsertionModelTests.swift`,
  `SnappingGuideModelTests.swift`, plus
  `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift`.
- Documentation: queue, implementation/project status, changelog, Codex handoff,
  requirement evidence, visual contract, ADR-0018 addendum, SF-AUTHORING-116
  evidence clarification and this new evidence note.

Read-only source/diff inspection covered exhaustive edit/error branches,
namespace validation, codec bounds, URL privacy, captured draft identity,
binding transition guards, reference ownership, initializer mappings,
equivalence dependencies, native accessibility and shared visual roles.
No debug interface, alternate content store, direct view mutation, geometry
change, generated artifact, private reference media, commit or push was added.

Compilation, native popup/focus behavior, cancellation propagation, minimum-width
layout, app-only visual inspection, broad stale/missing/transfer matrices,
autosave/recovery integration and complete verification remain Prompt-10 risks.
Source inspection cannot substitute for those observations.

## Deferred and next recommendation

Arbitrary events/scripts/animation, remote execution/services, variants,
nested authoring, slots, broad preview/export parity and release/publication
remain deferred. Existing Button execution stays unavailable rather than
introducing an event engine. Prompt 5 should inspect and implement the next
bounded component slot/default-fallback authoring slice under SF-0902/SF-0905,
reusing ordered canonical children and the current graph/history ownership;
resolve any normative ownership decision through AGENTS.md before mutation.
