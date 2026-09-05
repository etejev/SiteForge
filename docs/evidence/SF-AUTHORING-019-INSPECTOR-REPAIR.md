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
