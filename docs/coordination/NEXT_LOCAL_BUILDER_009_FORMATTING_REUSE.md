# Prepared next development prompt — practical formatting reuse

Status: **SENT** after the owner said “next” on2026-10-29. Workflow008 (turn `01a185d0-b066-7ee3-8bc5-22edf7622919`) completed its source scope; its final report, evidence and named source paths were reviewed before dispatch. Acceptance remains deferred, not waived. This document creates no automation or broader batch; do not send this prompt again.

## Prompt to send on GPT-6.1 Sol medium

**SF-LOCAL-BUILDER-009-FORMATTING-REUSE — make everyday website authoring faster and coherent.**

Owner priority: deliver a usable native local website builder, not a collection of unfinished panels. Complete one substantial workflow: style one element, reuse its formatting on other compatible elements, adjust the result with ordinary controls, and undo the paste as one action. The Aurora authoring-friction record documents repeated typography and appearance edits. Current source inspection found InspectorGeometryTransfer and Copy Value/Paste Value for geometry, but no corresponding complete formatting-reuse workflow. Inspect the current tree to confirm the remaining gaps before implementation; reuse any capability already present rather than duplicating it.

### Execution policy and predecessor

Read AGENTS.md, current queue/status, specification, ADRs, OPEN_DECISIONS and008's final source report. Source development is authorized; **ALL TESTING REMAINS ON HOLD**. No tests, builds, build-for-testing, verification/lint/check scripts, collectors, readiness/smoke/visual journeys, app/browser launches or performance runs. Add meaningful tests but leave them unrun. No asking to test merely because source work is ready. No commit, push, installation, signing, release, scheduled monitoring or more self-dispatched development.

Checkpoint `ba342938` passed785 code+151UI,0 failures,3 intentional skips. It does not accept007/008/009 edits. Keep007's executed failures and subsequent source corrections truthful; inspect the latest receipt rather than repeating stale totals.008 must have completed its bounded source scope before starting this workflow. No duplicate work on its active comparison/review worker.

### Requirement and scope discipline

Candidate bounded contracts: SF-0702-002/003/004/005/006/008 (compound value controls and copy/paste); SF-0703-002/003/004/005/006/008 (compatible mixed selections); SF-0308-002/003/004/005/006/008 (strict transfer and dependencies); supporting SF-0506, SF-0507, SF-0508, SF-0509 and SF-0510 only where existing canonical registries support the exact fields. Read and cite the precise applicable IDs. Add a short queue implementation plan first. Keep modules Partial; this is not complete specification/release delivery.

### Coherent source implementation

1. Expose obvious, compact **Copy Text Style / Paste Text Style** and **Copy Appearance / Paste Appearance** actions through the established command/menu and contextual Inspector patterns. Include keyboard accessibility and meaningful enabled/disabled reasons. Do not add a new tool window or giant action cards. Do not intercept ordinary Command-C/V inside native text fields or inline text/IME editing. Avoid inventing conflicting shortcuts.

2. Text Style should reuse supported canonical family, weight, size, line-height, tracking, alignment and foreground/token intent as an understandable bundle. Appearance should reuse supported canonical fill layers, opacity, border/corners and effects where the current registry already supports them. Preserve the distinction between omitted/inherited, explicit None, authored literals, token references and named-style links. Do not silently bake computed responsive/fluid/token values into literals. If a supported field cannot transfer its semantics safely, explain the unavailable field and its recovery, not a misleading full-style success.

3. Use the existing strict private clipboard/transfer and property-preparation machinery. Extend it narrowly with a bounded, typed, versioned formatting envelope; no second content model or arbitrary dictionary write path. Copy captures a snapshot and does not modify source nodes. Validate bytes, versions, fields, numeric bounds, supported enum values, nesting/collection budgets and dependency references before preparation. Malformed, oversized, unknown, missing-reference and foreign-document payloads fail safely.

4. Prepare the entire requested paste through the established property registries and execute ONE atomic canonical transaction with an exact inverse. Do not sequentially commit one field per target and leave half-applied formatting after failure. Preserve target NodeIDs, text/content, links, assets not included in the requested family, geometry/layout, component bindings and unrelated styling. A repeated paste with identical canonical intent is history-neutral. Return/focus-loss and Undo/Redo must retain the normal native-text/document boundary.

5. Multi-selection uses explicit per-family applicability: never borrow an arbitrary primary value from a mixed source selection or force unsupported targets. Copy from one unambiguous source; for a multi-source selection, enable only a genuinely common bundle or show a clear reason. Paste should show the applicable/skipped target counts through compact existing feedback and apply one transaction to the supported subset only under the documented selection policy. Do not claim every selected object changed. Clean safe pastes should not require a modal confirmation per field.

6. Respect current breakpoint, state and component contexts. Capture document/page/revision/scene/ordered selection and relevant responsive/style identity at action preparation. An operation cannot land on a different page, instance definition or replacement selection after an awaited step. Preserve explicit responsive overrides; Desktop-only supported properties must be clearly scoped rather than falsely presented as Mobile edits. Do not create per-instance arbitrary properties or retarget missing bindings to match labels.

7. Token, named-style and image-fill references must remain valid. Reuse existing dependency closure, equivalence/remapping and reference validation where supported. Do not add remote fetches, font import/embedding, new asset storage, source paths or new schema merely for convenience. Cross-project resource-bearing transfer may remain explicitly unavailable when existing mapping cannot preserve intent; same-project formatting reuse must remain useful and complete. Do not silently copy source IDs into a foreign project or omit referenced fills while claiming success.

8. The pasted result must use the existing renderer, inline text metrics, native Preview and shared HTML/CSS compiler, not a sample-specific formatting or export patch. Existing controls should immediately read the new canonical state and provenance. Keep compact shared cards/headings/spacing, stable labels and all five sidebar destinations visible at normal supported sizes. Do not redesign the app or add diagnostic clutter in this workflow.

### Unrun coverage and handoff

Add source coverage in existing targets for full bundle copy/paste; one and mixed-compatible selections; omitted vs explicit None/inherited/token/link intent; unchanged-paste neutrality; atomic failure/rollback and exact Undo/Redo; stale context; native pending text/IME; component definition/instance boundaries; malformed/oversized payloads and missing/foreign references; package/recovery round-trip; immutable renderer/inline/compiler projection agreement; and one ordinary native keyboard/pointer journey for later screenshots. Reuse real canonical constructors and safe owned temporary-path helpers. Do not execute any test or compile to check these sources.

Update queue/status/changelog and concise evidence. State implemented source paths, actual supported formatting fields/context/dependency limitations, intended UNRUN selectors and deferred acceptance honestly. Label **IMPLEMENTED IN SOURCE — ACCEPTANCE DEFERRED; OWNER TEST APPROVAL REQUIRED**. Future `./sf verify` and visual acceptance remain mandatory, not waived. Do not claim a usable verified installed application from source inspection.

Preserve all existing edits, owner projects/recovery/resources/evidence and regular installed app. Preserve Aurora/Dark Flow revision245 and its editable45-degree three-stop native gradient; no authoring macros or saved website/output edits. OD-018/019 and updater/distribution/security decisions unchanged. Do not stage/delete coordinator notes or superseded artwork. Finish this complete source workflow, not just a clipboard model, picker, plan or findings list.

