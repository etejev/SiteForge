# SF-AUTHORING-064 — Native Canvas Settings default

## Bounded contract

This application-local slice covers `SF-0206-002`, `SF-0206-003`,
`SF-0206-004`, `SF-0206-006`, and `SF-0206-008`, with the existing accessible
Grid presentation under `SF-0407-006`. It does not claim the full SF-0206
module. ADR-0006 keeps application convenience preferences out of canonical
projects.

Settings now has a native Canvas tab. Its Grid checkbox is a draft until
Apply; Cancel/Escape rolls the draft back, Reset removes the authored record,
and Restore Previous restores the exact prior bytes within the current
settings session. A version-one record stores stable preference identity,
authored provenance, and the Boolean default. Omission and unknown/malformed
versions safely start new workspaces with Grid visible without overwriting
unknown bytes. Managed or stale preferences reject edits with bounded,
value-free diagnostics. Changing the default does not alter open workspaces;
their toolbar and View-menu Grid command remain scene-local. No document,
history, recovery package, preview, or authored renderer data is changed.

## Focused results (2026-09-29)

- `CanvasSettingsTests.testGridDefaultStrictRecordFallbackAndExplicitReset`
- `CanvasSettingsTests.testGridDefaultDraftCancelStaleAndNewWorkspaceIsolation`
- `CanvasSettingsTests.testGridDefaultApplyResetRestoreAndRelaunchPersistence`
- `SiteForgeLaunchTests.testCanvasSettingsGridDefaultAppliesOnlyToNewWorkspacesJourney`
- `SiteForgeLaunchTests.testApplicationAppearanceSettingsPreviewApplyCancelResetJourney`
- `SiteForgeLaunchTests.testWorldGridArtboardHierarchyVisualJourney`

Each exact selector passed (6/6 total, zero failures). The three UI journeys
ran in separate tracked result bundles. The pre-existing Appearance journey
now explicitly selects its native tab; the pre-existing grid journey explicitly
enables Grid when an application default starts it off. Neither assertion was
removed. No full suite was rerun after the previously recorded 556-test
SF-AUTHORING-063 checkpoint.

## Original-resolution visual review

The new Canvas Settings journey retained five named XCTest window attachments:

| State | Attachment file |
| --- | --- |
| Initial Canvas Settings | `5AE94B58-102B-42EB-80B0-5A37EA3936F5.png` |
| Uncommitted Grid-off draft | `300BBE04-FA4D-49AF-9EDB-8B22B4277734.png` |
| Applied Grid-off default | `9FEA72C7-187F-4AA9-8444-8B7DEB09A45C.png` |
| New workspace, Grid off | `F4B19CAA-C4F3-48F0-A7BB-BEE13533AB62.png` |
| Same workspace, live Grid on | `6EFA2B50-365F-40F3-A18A-FE81EB718CA2.png` |

All five were inspected at original resolution. The native tabs, scope copy,
checkbox, provenance, and Apply controls were legible without wrapping or
clipping. The new workspace had a distinct page/pasteboard without grid
marks; toggling Grid in that workspace revealed world-aligned marks without
moving authored content or changing the saved default. Normal windowed shell
presentation and editor-only canvas hierarchy remained intact. The result
bundle is `focused-a389e95e-a95a-49c1-8fd3-0e302b12f36e.xcresult`; the
extracted attachments are local test artifacts, not project resources.

## Deferred and known boundaries

Project-canonical preferences, applying a new default to already-open scenes,
grid spacing/color configuration, broad scale/localization/VoiceOver matrices,
and release acceptance remain deferred. The Settings journeys still emit an
existing SwiftUI publish-during-view-update runtime warning also recorded in
earlier SiteForge evidence; no new runtime-health fix or absence-of-warning
claim is made for this bounded preference slice.
