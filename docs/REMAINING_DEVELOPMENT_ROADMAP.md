# Remaining SiteForge development — 2026-10-13

## Current delivery policy — cohesive packages, cycle Prompt 2/10

Owner priority: a polished native **local website builder** first, advanced
specification expansion second. This changes packaging/prioritization, not any
normative requirement. The fragmented estimates below are historical and
superseded; neither a prompt batch nor phase one completes the specification.

### Phase one: local-builder delivery

124 combines the old Inspector micro-slices (search/pin/copy/paste/reset/mixed
handling) into one workflow. After 124, provisionally **5–8 complete development
packages**, not 19–32 micro-prompts:

| Priority | Complete workflow | Dependencies / old slice mapping | Packages |
| --- | --- | --- | --- |
| Next | Connected website to local output: containing layouts, navigation, Preview, asset export, semantic metadata, truthful diagnostics/recovery | 110/121/122; old rows 6–8; SF-0504/0505, SF-1201–1209/1211 | 1–2 |
| Then | Practical component reuse: variants, definition editing/navigation and existing media/action/fallback integration | 113–123; old rows 2–3; SF-0901–0905/0907 | 1–2 |
| Then | Responsive website authoring: practical breakpoint/cascade workflows and Preview/output agreement | existing 016–018/101/102; old row 4; SF-0601–0606 | 1 |
| Then | Local assets, typography and styling usability: supported local resources, missing-resource recovery, complete native controls and output agreement | existing resource/style registries; old row 5 and general styling; SF-0506–0511, SF-0801–0805 | 1–2 |
| Before acceptance | Builder polish, Settings/lifecycle/recovery, compact/keyboard/AX workflows and coordinated visual correction | preceding packages; SF-0201/0203/0206, SF-1502/1505/1506 | 1 |

Each package includes its model, native UI, typed history/persistence, renderer/
Preview/output implications, failure/cancellation/accessibility and test source.
Do not reserve another prompt for a routine picker/reset/integration/doc task.
Supplied slots and explicit conflict retargeting remain conditional OD-018/019
work, not silently required to finish already-useful safe component reuse.

### Phase two: advanced specification expansion

Defer CMS/data/localization depth (§10), general animation/event/runtime depth
(§11), collaboration/comments/roles/version-comparison breadth (§13), plugin
execution/tooling (§14), remote libraries/providers and publishing (§8/9.6/12.10).
These remain normative Partial/deferred boundaries. Preliminary **7–12 larger
packages** is a planning horizon only; connected-service/security/ownership
decisions prevent a reliable fixed total. No implementation is authorized by
this roadmap alone. Full-spec/release completion cannot be claimed at phase-one
acceptance or after ten development prompts.

### Acceptance and owner boundaries (not hidden in package estimates)

The failed accumulated run requires bounded repository/code repair and native
automation authorization after owner return. Source-only 115–124/UI-008/testing
work needs compilation, focused/full execution and original-resolution review.
Preserve OD-018/019, OD-001/012/013/014/017, DOCX synchronization, supported
hardware/browser/IME/VoiceOver/recovery/privacy/security and release checklists.
Signing, notarization, publication and update installation stay prohibited.
No source package is verified while these relevant gates are unrun or failing.

## Historical fragmented inventory (superseded estimates, retained scope)

This is a planning inventory, not a completion claim or newly approved product
scope. Contract: SiteForge-Specification.md; evidence: IMPLEMENTATION_STATUS,
REQUIREMENT_EVIDENCE, SF-SOURCE-COMPLETENESS-AUDIT and milestone evidence below.
The older audit predates 115–123: its statements that component actions/media
are missing must not be mistaken for the current bounded implementation.

## Implemented but not accepted

115–117 component media/actions, 118 fallback slots, 119 organization,
120 retained-conflict recovery, 121/122 connected page/output and 123 discovery
have source paths and test source. UI-008 visual convergence and experimental
testing/Settings also remain incompletely accepted. The accumulated collector
finished with repository/code failures and UI automation initialization failure;
building is not acceptance. Preserve its report for bounded repair when allowed.
See each numbered evidence file and PROMPT-10-ACCEPTANCE.md. Older verified
567-unit/104-UI evidence is historical, not proof of these subsequent edits.

Do not count acceptance-only repair, publication-copy synchronization, screenshot
review, test execution or owner add-ons as new development prompts. A repair
that introduces a new product capability needs its own bounded queue entry.

## Ordered native-authoring/local-output backlog

Each row is a family of dependency-ordered vertical prompts, not a single huge
task. Choose exact normative IDs/acceptance before creating each queue item.
Ranges estimate the existing prompt-sized vertical slices, not tests or days.

| Order | Remaining development | Dependency / specification | Estimated prompts |
| --- | --- | --- | --- |
| 1 | Inspector discovery beyond linked instances, section pinning and applicable copy/paste | 123; SF-0701–0704, existing transactional property registries | 2–3 |
| 2 | Component variants, bounded nesting and documentation/examples | 113–123 identities, dependency/cycle budgets; SF-0901/0902/0904/0906 | 3–5 |
| 3 | Supplied slot content and retained-conflict explicit migration | **Owner approval OD-018/019 first**; SF-0903/0905 | 2–4 |
| 4 | Remaining responsive breakpoint management/style-content/source behavior | existing geometry/container cascade; SF-0601–0605 | 2–3 |
| 5 | Local font/vector/media capabilities and resource policy | existing ResourceStore/Image; SF-0802–0805, SF-0507 | 3–5 |
| 6 | Unsupported connected output containing/positioned/fluid/multiple-root cases | accepted 121/122 resolver; SF-0504/0505, SF-1202/1204/1211 | 2–4 |
| 7 | Full semantic metadata/SEO and accessibility output | connected output/resources; SF-1203/1207, SF-1605 | 2–3 |
| 8 | Bounded production runtime bundling, output profiles/adapters and browser parity | rows 5–7; SF-1201/1205/1206/1208/1209/1211 | 3–5 |

Subtotal: **19–32 additional development prompts**, excluding this 123 source
slice and acceptance-only work. This is a useful local-authoring/output planning
horizon, **not completion of the full specification**. It includes owner-blocked
rows; safe independent rows may proceed without silently skipping dependencies.

## Broader normative scope, not part of that subtotal

Current bounded controls do not prove these whole modules. The source audit,
current status limitations and specification §§8–14 explicitly leave substantial
scope. Extend the queue only after inspecting each concrete dependency.

| Subsequent family | Dependencies / specification | Additional estimated prompts |
| --- | --- | --- |
| Remaining general styling, effects and typography breadth | existing 013–018/109 foundations; SF-0506–0511 | 2–4 |
| Additional approved onboarding/catalogue/learning workflow | approved neutral starter policy, owner-approved content; SF-0204/0205 | 1–3 |
| CMS/data schemas, bindings, collections and local dynamic output | resource/semantic/renderer contracts; specification §10 | 4–8 |
| General interactions, animation, scroll/runtime variables and safe custom code | bundling first, security decisions; specification §11 | 4–8 |
| Localization and localized content/output | stable content/data bindings; applicable §10 and SF-1506 | 2–4 |
| Versions/comparison/comments, collaboration and roles | persistence plus approved service/conflict/security model; §13 | 4–8 |
| Plugin lifecycle, sandbox, UI/document/runtime APIs and tooling | permissions/ABI/security decisions; §14 | 4–8 |
| Remote libraries/providers and publishing/domains/rollback | output adapters plus owner account/security approval; SF-0801/0906/1210 | 2–4 |

Additional estimate **23–47**; combined planning envelope **42–79 development
prompts** for the currently identified specification-wide feature gaps. This is
a provisional decomposition, not a guaranteed finite route to release: broader
performance, interoperability and service decisions can split or change slices.
The full agreed specification cannot honestly be reduced to ten prompts or to
the local-authoring subtotal. Re-estimate after accepted evidence for each family.

## Owner-blocked / final acceptance work

- OD-018 canonical supplied-slot ownership/cardinality; OD-019 explicit retained
  override migration. Safe fallback inspection/reset remains available.
- OD-001 supported OS/reference hardware; OD-012 publisher identity; OD-013
  distribution trust; OD-017 signed feed/key/installer ownership. No signing,
  update installation or distribution is enabled by this inventory.
- OD-014 trusted retained-artifact reclamation remains separately governed.
- Connected accounts, publishing, plugin execution/service models and legal/
  licensing choices require the owner under AGENTS.md; do not invent credentials
  or silently substitute a local mock for a production service.
- Accumulated failure repair, DOCX publication alignment, original-resolution
  native and browser visual review, keyboard/VoiceOver/IME/localization/recovery,
  migration/history matrices, reference-hardware scale/performance, browser/
  export parity, privacy/security review and release checklist §§16–20 are
  acceptance work. They remain explicit and uncounted in the feature estimates.

Next dependency-safe candidate after 123 source review: bounded Inspector
section discovery/pinning, using SF-0701-002/003/006/007 and existing scene-local
presentation. Do not infer approval for canonical pinned project metadata or
arbitrary property copy/paste without inspecting their exact contracts first.
