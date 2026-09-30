# SF-AUTHORING-065 — Application preference-group reset

## Contract and scope

This focused application-only slice covers bounded `SF-0206-002`,
`SF-0206-003`, `SF-0206-004`, `SF-0206-006`, and `SF-0206-008`. The
specification explicitly names resetting a preference group, but does not
name a concrete project-owned preference; this slice therefore resets only
the two existing app-local Appearance and new-workspace Grid records under
ADR-0006. It does not claim `SF-0206-001/005` project-canonical settings.

The native Settings Reset tab presents both current values and application
scope. A staged reset needs explicit confirmation; Escape/Cancel, leaving the
Reset tab, and closing Settings abandon the stage without changing storage.
The group captures exact prior bytes, rejects dirty drafts, managed values,
and storage changed since staging, and removes both values synchronously.
Failure to store the target attempts exact rollback and reports whether that
rollback succeeded. A bounded session transaction records exact before/after
snapshots; Restore Previous recovers the prior pair. Existing Appearance and
Canvas tabs then reload committed storage. The Appearance default follows
macOS; new workspaces show Grid. Already-open workspace Grid state, projects,
document history, recovery packages, renderer output, and static output are
unchanged. Diagnostics report bounded categories, not preference values.

## Focused results (2026-09-29)

- `CanvasSettingsTests.testApplicationDefaultGroupResetRestoreAndRelaunch`
- `CanvasSettingsTests.testApplicationDefaultGroupRejectsDraftAndStaleStorageWithoutMutation`
- Existing `CanvasSettingsTests` selectors (three) also passed in the same
  exact class run: five model tests, zero failures.
- `SiteForgeLaunchTests.testApplicationSettingsGroupResetCancelRestoreAndRelaunchJourney`
  passed 1/1 in a fresh app process after the final visual-label refinement.
- Existing `testApplicationAppearanceSettingsPreviewApplyCancelResetJourney`
  and `testCanvasSettingsGridDefaultAppliesOnlyToNewWorkspacesJourney` each
  passed in separate fresh-process focused runs after the Settings tab addition.
  All affected exact selectors passed 8/8, zero failures.

The actual-app journey edits both preferences through the native tabs,
cancels staged group resets by Escape and tab switch, confirms a reset, restores the exact
prior pair, resets again, relaunches, and observes Follow macOS plus Grid-on
defaults before restoring the test machine's original preferences through the
public Settings controls. The model tests prove unrelated UserDefaults and a
canonical project round trip are unchanged, including malformed future-record
preservation until explicit confirmation. Result bundle:
`focused-840ac192-a723-4c31-86d1-bd8f38588dc9.xcresult`.

## Original-resolution visual review

Five retained attachments were inspected at original resolution:

| State | Attachment file |
| --- | --- |
| Dark / Grid Off before reset | `DF4AC3FC-DC36-41BF-A602-28BA8E618692.png` |
| Explicit pending confirmation | `D16F1F5C-9141-424B-95A5-C0D578D9452E.png` |
| Follow macOS / Grid On after reset | `4B87BF92-DD57-4213-8283-A719087904DD.png` |
| Previous values restored | `0E1F3094-5D24-4286-8EE1-583D982783CA.png` |
| Defaults retained after relaunch | `9EE80D73-88CB-45BC-B23D-03732F5C97CB.png` |

The native Settings toolbar, scope copy, values, status, Cancel/Confirm, and
Restore Previous fit without clipping or wrapping. The first visual pass
revealed a duplicated “Grid” word in the summary; the value was shortened to
“On”/“Off”, then the exact journey was rerun and all five states reviewed.
These screenshots are local XCTest attachments, not project assets.

## Remaining boundaries

Project-owned preference choices, settings profiles/import/export, broader
scale/localization/VoiceOver matrices, and release acceptance remain deferred.
No full suite was rerun: the change is confined to application UserDefaults
and the native Settings scene, with no shared document schema/migration,
renderer, transform, or global workspace-shell change. The earlier 556-test
SF-AUTHORING-063 gate is not claimed as verification of this later slice.
