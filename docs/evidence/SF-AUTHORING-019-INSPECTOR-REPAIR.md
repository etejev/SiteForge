# Inspector autosave repair

Requirements: supporting SF-0502-002, SF-0505-002, SF-0801-005,
SF-0802-005 and SF-1902-008. Image milestone hosted acceptance remains pending.

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
runner remained active. Hosted main confirmation remains the final gate.
