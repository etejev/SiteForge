# SF-AUTHORING-106 — Starter Site and onboarding choice

Verification checkpoint (2026-10-08): repository/build gates and the complete
non-UI target ran; corrected non-UI coverage is green. The actual-app journey
remains unexecuted because XCTest timed out before enabling automation mode.

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED** (2026-10-08)

Requirements: bounded `SF-0204-001`–`SF-0204-008`; supporting
`SF-0301-001/002/005`, `SF-1201-003`, and `SF-1203-002/003/004`.

## Delivered source contract

- The welcome surface preserves the established **Blank Site** action and adds
  exactly one local **Starter Site** choice. Blank remains the default keyboard
  action. Both choices have visible descriptions, stable accessibility
  identifiers, meaningful labels/hints, and specific launch announcements.
- `StarterSiteTemplate` is ordinary canonical project data, not a launch-time
  renderer fixture. It owns one stable `TemplateID`; every page, node, and
  property identity is deterministically derived from the new `DocumentID`.
- The template contains exactly two ordinary pages: Home at `/` with role
  `home`, and About at `/about` with role `standard`. Both record page
  provenance `template`. No Not Found/404 page is presented as starter content.
- Each page has one ordinary Root Frame containing editable Header, Main, and
  Footer Sections. Typed semantic properties resolve those landmarks; each
  contains one ordinary Text node with neutral removable copy and canonical
  System-family typography. The template stores no image assets, remote URLs,
  branded identity, hidden debug objects, or special non-editable nodes.
- Desktop base geometry plus existing Tablet/Mobile responsive geometry keys
  keep each authored Section inside the corresponding product artboard. The
  existing responsive resolver remains the only cascade.
- `DocumentLifecycleController.requestNewDocument` accepts a complete proposed
  canonical document, validates it before authorization or document-boundary
  work, and then establishes it through the existing clean, non-undoable
  lifecycle baseline. Invalid input returns the typed malformed-package result
  without changing the current lifecycle snapshot.
- Launch diagnostics now cite all `SF-0204-001`–`008` requirements and retain
  only the existing sanitized document identity, operation, duration, result,
  and closed failure category.

## Test source added or refined

- `BlankProjectTests.testStarterSiteHasStableTemplateProvenanceSemanticStructureAndNoNotFoundPage`
- `BlankProjectTests.testStarterSiteResponsiveGeometryStaysInEveryProductArtboard`
- `BlankProjectTests.testStarterLifecycleIsAtomicCleanEditableUndoableAndRoundTrips`
- `LaunchExperienceTests.testStarterCreationUsesSameAtomicLifecycleWithCanonicalTemplateProvenance`
- `LaunchExperienceTests.testStarterCreationCancellationPreservesCurrentProjectAndReportsCancellation`
- `SiteForgeLaunchTests.testStarterSiteCreatesOrdinaryHomeAboutSemanticWorkspaceJourney`
- Existing launch focus/announcement tests now require both explicit creation
  choices while retaining Blank Site as the Return-key default.

These tests are source-only in this slice. No build, test selector, UI
automation, or `./sf verify` was run because the owner currently prohibits
local execution. They must not be cited as passing evidence.

## Static review

- The existing `ProjectCreationKind.template`, `TemplateID`, page provenance,
  strict canonical serializer, property origins, responsive resolver,
  semantic resolver, typography resolver, command history, and package owner
  are reused. No schema version or migration is required.
- Blank Site still produces its approved Home plus Not Found minimum roots.
- Starter content has no local path, credential, remote dependency, image
  bytes, licensed copy, test launch argument, or alternate document model.
- New edits remain regular node/property transactions after creation; the
  initial selected template is one clean lifecycle baseline rather than an
  undoable collection of bootstrap commands.

## Explicitly deferred

Additional templates, catalogue search/filtering, template downloads or
updates, remote/licensed assets, branded copy, walkthroughs, hints, learning
tasks and reset state, sample-project management, publishing/output parity,
large catalogue/performance matrices, broad localization/VoiceOver/200-percent
scaling acceptance, and release acceptance remain deferred. The normative
`SF-0204` module therefore remains **Partial**.
