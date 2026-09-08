# SF-AUTHORING-023 — Application Appearance Settings

## Bounded contract

Application-only appearance implements bounded SF-0206-002, SF-0206-003,
SF-0206-004, SF-0206-006 and SF-0206-008. SF-0206 remains Partial.
ADR-0006 explicitly keeps appearance out of canonical projects. This slice
does not claim SF-0206-001 project preferences or SF-0206-005 document history.

Native Settings (SiteForge menu, Command-comma) offers Follow macOS, Light and
Dark. Each radio selection previews native application appearance; Apply is
the only persistence boundary. Cancel/Escape and closing Settings restore the
saved choice. Reset previews removal of the authored override, not a literal
replacement. Restore Previous restores the exact preceding stored record.
The panel labels application/this-Mac scope and default/authored/preview state.

## Persistence and recovery

One version-1 application preference record contains stable preference identity,
authored origin and a typed appearance. Omission follows macOS. Unknown versions,
invalid identities/origins and malformed records resolve safely to macOS while
preserving the original bytes until explicit Apply/Reset. Exact prior bytes
remain available to session restoration. Transactions include operation,
stable preference ID, local actor, timestamp and exact before/after records;
restoration retains at most 32 operations. No project, history, recovery package,
renderer model or website content is traversed or modified.

External changes reject stale drafts; reopening refreshes the stored choice.
Managed preferences reject writes. Native dynamic colors/materials and system
accessibility settings remain authoritative. Diagnostics use fixed requirement,
operation and failure text, not arbitrary preference payloads or paths.

## Focused results

Six focused tests pass in `AppearanceSettingsTests` (6/6, zero failures):

- `testAppearanceStrictRecordsAndUpgradeFallbackPreserveIntent`
- `testAppearancePreviewCancelCloseAndNoOpAreNeutral`
- `testAppearanceApplyResetRestorationAndRelaunchPersistence`
- `testAppearanceNativeResolutionAndBoundedRestorationHistory`
- `testAppearanceStaleExternalChangeRejectsDraftWithoutOverwriting`
- `testAppearanceNativeWindowReattachmentPreservesPreviewButCloseCancels`

Actual-app selector:
`SiteForgeUITests/SiteForgeLaunchTests/testApplicationAppearanceSettingsPreviewApplyCancelResetJourney`.
It uses native Command-comma, radio controls, Return, Escape, close/reopen,
Reset, Restore Previous, and fresh-process persistence. Original application
appearance is restored at the end. Native static text exposes its content as
AX value; assertions read that value, not the unrelated label. The initial
query failures did not indicate failed preference mutation. Native Close now
also supplies Command-W, which was absent from the existing File menu.
Window-close notifications own cancellation; view reattachment cannot reset
an active preview. All control paths use the same application preference owner.

The actual-app journey passed 1/1 in 30.966 seconds. Model evidence:
`focused-bc7156f0-6ac2-4583-bfc3-fedd19c67ba8.xcresult`; UI evidence:
`focused-692b0f9e-6f7a-4386-a8b2-8378ff8c0b7e.xcresult`.
Six model tests plus one UI journey = 7/7 focused checks. The UI run emitted
no publish-during-view-update or invalid-geometry warning.

## Visual review

Five original-resolution 920-by-836 native Settings window captures were
reviewed. Light/dark native materials, all choices, provenance and preview/
saved/cancelled state are legible. Buttons do not wrap or clip. The window is
compact and standard windowed, not a full-screen Space. These are Settings
captures, not a claim of new broad canvas visual coverage.

- Dark preview: `7A95F40E-4F71-4F8D-AD89-05205F2A3937.png`
- Light committed: `55BC3FA2-502A-4434-BDFB-FA4ABBA99CDD.png`
- Close/reopen cancellation: `C283C0F8-3B9B-4B4C-8EF4-F0348E0367FB.png`
- Reset default: `3230EE1D-40BF-401D-8DDE-4BC333758674.png`
- Fresh-process persisted choice: `BD189C86-91E6-4042-AD13-3969B8643BCB.png`

## Final local verification

The single authoritative `./sf verify` passed: 420 unit/integration + 59 UI =
479 tests, zero failures. Repository, security, traceability, architecture,
migration and evidence checks passed. Result bundle:
`full-76e8b023-1e59-451f-a249-cffb7dd91d87.xcresult`.
The final diff contains only this Settings slice, tests, target membership and
documentation. No canonical/project schema, renderer or existing product test
was weakened or rewritten. All temporary tracing was removed.

The bounded local milestone is DONE. Hosted CI is pending the checkpoint push;
local verification does not imply hosted success. Documentation reconciliation
uses repository checks, not another unchanged full UI run.

## Explicit exclusions

Project-scoped preferences and migration, canvas/code/publishing/experimental
groups, profiles, project Undo/Redo/version comparison, cross-device settings
sync, broad module-scale/OS matrix and release acceptance remain deferred.
Appearance is native editor convenience, never authored website styling.
