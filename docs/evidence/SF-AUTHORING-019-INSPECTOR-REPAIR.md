# Inspector autosave repair

Requirements: supporting SF-0502-002, SF-0505-002, SF-0801-005,
SF-0802-005 and SF-1902-008. Correction and final native Save availability
follow-up are verified and complete.

| Symptom | Evidence and cause | Correction | Regression |
|---|---|---|---|
| Y field loses focus before typing | Actions 33947877755; transform validation disabled native controls when autosave began. | Permit revision-guarded edits during immutable snapshot saves; query and focus the live field before typing. | `testGeometryTransformPointerKeyboardNumericUndoRedoAndAccessibilityJourney` |
| Center segment disabled | Same run's retained screenshot visibly shows disabled Inspector controls; AppKit window remains key/main and has no sheet. Earlier AX-container-only diagnosis was incomplete. | Shared transform validation keeps Inspector editing available during saving/autosaving, as insertion and inline text already do. | `testStructuralLayoutInspectorReflowsSectionStackAndGridJourney` |
| Recovery regression setup fails | Ad hoc temporary recovery directory fails the owned filesystem boundary. | Use established ApplicationOwnedTestFixture; preserve filesystem security checks. | `testInspectorEditsRemainAvailableDuringBackgroundAutosave` |

The new autosave regression passed 1/1 locally. It asserts an active autosave,
enabled geometry/alignment controls, two canonical edits with stable selection,
and exact undo restoration. The two UI selectors compiled but the local runner
timed out enabling automation before either body executed. No product result
is claimed from that attempt. No local runner remains active.

The allowlisted Inspector diagnostic workflow runs only these three selectors
and retains logs/results on success or failure. It does not replace ordinary
main/PR verification or constitute full milestone acceptance. No unrelated
UI suite is repeated during this repair.

Hosted focused confirmation: Actions `33980431383` passed all three selectors
(one model regression and two UI journeys, zero failures). This confirms the
autosave availability correction under the hosted environment that exposed the
defect. It does not replace the final integrated milestone gate.

Original-resolution hosted attachments confirmed the geometry fields and
selected Center segment adopted the requested values. They also exposed a
compact Inspector defect: Alignment wrapped into three lines beside four
segments. Its shipping label now occupies a separate single-line row above
the unchanged native segmented control. The structural journey asserts the
label's readable dimensions. Its first focused rerun exposed a redundant
pointer-readiness check on the noninteractive radio-group container after the
title was separated. The journey now reveals the actual native Center segment;
enabled, hittable, safe-display and exact committed-value assertions remain.
The corrected structural journey passed 1/1 in
`focused-3d840f45-be6f-4425-b547-b9b675307aa5.xcresult`. Its retained
Alignment and reopen images were reviewed: the label occupies one readable
line, Center is selected, authored surfaces remain aligned, and reopened
layout reports Saved.

The typography and image persistence journeys passed together locally (2/2)
in `focused-b2c63ae3-b28a-412a-b2a5-0e0788be24ad.xcresult`. Their retained
reopen images show Saved status, preserved authored properties, upright text
and image pixels, and aligned selection geometry. The targeted immutable-save
revision and 1024-point-display policy regressions also passed (2/2), alongside
the new Inspector autosave regression and geometry UI journey. No broad suite
was repeated during these corrections.

Final focused coverage: seven distinct affected selectors passed (three
model/lifecycle/window-policy regressions and four UI journeys). The initial
hosted diagnostic additionally passed its three allowlisted selectors. Final
integrated verification passed: `./sf verify` completed with 392 unit/integration
and 49 UI tests (441 total), zero failures, in
`full-b7d9246a-569f-4741-ad2b-f724a4d6a03e.xcresult` on 2026-09-05.
Repository/security/traceability/evidence checks passed, and no SiteForge
runner remained active. Actions `33982941555` then passed the same full
392 unit/integration and 49 UI tests (441/441), with repository checks green,
for production commit `f6c58ef`:
https://github.com/etejev/SiteForge/actions/runs/33982941555

The three originally failing journeys then passed three consecutive focused
groups on the unchanged production commit `f6c58ef` (9/9, zero failures).
Each journey launched a fresh app process. Retained result bundles:

- `focused-518e7ce6-903c-4764-bfae-599ae530b33c.xcresult` — 3/3.
- `focused-f3956cde-a6d4-428d-9d11-70555e777dc7.xcresult` — 3/3.
- `focused-259ed511-5b60-434f-841e-fea181b6c8ff.xcresult` — 3/3.

These repetitions ran only typography persistence, local-image authoring /
reopen, and structural Inspector layout. No complete local suite was repeated.

## Deterministic save-order test follow-up

The documentation-only Actions run `33984707264` passed all 49 UI journeys
but exposed one non-UI failure at `DocumentLifecycleTests.swift:206` in
`testStaleSaveSuppressionAndMainActorResponsiveness`. Its 200 ms backend delay
and one `Task.yield()` did not establish that the first save had entered before
the second task was created. Task creation order is not operation-entry order.
The second Boolean assertion failed while the final document-content assertion
still passed; this is not evidence of lost persisted content.

The test now reuses `LifecycleBackendProbe` to hold the actual first snapshot
at `beforeFilesystemWrite`, then runs real main-actor work and authors the
second revision. It retains the second-save and exact-document assertions and
adds successful first-save, ordered written revisions, final revision, and clean
phase assertions. No production implementation changed, and no timing delay,
retry, or relaxed assertion was added.

Only the corrected selector and
`DocumentLifecycleRaceTests/testEditDuringSaveKeepsSavedRevisionDurableAndNewerRevisionRecoverable`
were rerun: 2/2 passed in
`focused-74dfcced-68ff-4bfb-bc5a-a77025ac1c33.xcresult`.
The production-tree full verification and original-failure repetitions above
remain the evidence for unchanged application code.

## Native Save availability during recovery autosave

Actions `33986611685` attempt 1 reached 392 non-UI and 45 UI passes without
assertion failures before the 30-minute job deadline. Its single justified
retry completed all tests: 392 non-UI and 48/49 UI passed. Typography failed
at the native Save availability assertion during File-menu tracking. The
job deadline then interrupted failure-artifact upload; the run log is retained.

`DocumentLifecycleController.canSave` still excluded `.autosaving`, although
recovery autosave does not make the document durably Saved. The native menu
could therefore open with Save disabled while recovery ran. Manual `save()`
already cancels/drains recovery before taking its durable snapshot. The
availability predicate now permits that existing safe operation. Clean durable
documents and active manual saves remain disabled. No helper assertion changed.

`testExecutingAutosaveIsCancelledAndDrainedBeforeManualSave` now additionally
asserts clean-disabled, modified-enabled, executing-autosave-enabled, and
saved-disabled states around its real backend checkpoint. It passed 1/1 in
`focused-7148e99f-42fe-4e26-9b52-af3e2340272d.xcresult`.
The paired UI attempt was obstructed at the Design tab by an unrelated macOS
notification, confirmed from its recording, before reaching Save.
After diagnosing that obstruction, the unchanged typography journey passed
1/1 in `focused-23485c04-5d91-41a2-89d3-f81bab7ffb73.xcresult` (70.138 seconds).
Its reopened screenshot `D0AB8830-C84B-4B9B-9301-A66D83FA4A84.png` was reviewed:
Saved status, preserved typography intent/fallback, upright text, and aligned
selection remain visible. No additional local full suite was run.

The hosted job has 40-minute bounded headroom because two measured full runs
reached its former 30-minute cutoff, including artifact upload. Individual
XCTest waits, test selection, assertions, and performance budgets are unchanged.

Final hosted acceptance: Actions `33991018406` passed for production commit
`f951df7`: 392 unit/integration and 49 UI tests (441/441), zero failures,
repository checks green. Typography's real native Save/reopen journey passed
in 74.338 seconds. This validates the final production availability correction;
no additional local broad suite was run for the focused follow-up.
https://github.com/etejev/SiteForge/actions/runs/33991018406
