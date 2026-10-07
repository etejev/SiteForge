# SF-AUTHORING-104 — Native Support settings and redacted diagnostics

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**

## Bounded requirements

`SF-0206-004/006/008`, `SF-1507-003/004/006`, `SF-1602-004/006`, and
`SF-1607-002/003/004/006/008`.

## Delivered source contract

- Settings has one native Support tab. It presents the installed product
  version/build/channel and explicitly states that this build neither downloads
  nor installs updates. This is a truthful boundary, not an updater simulation.
- Recovery text reflects the existing lifecycle invariant: recovery snapshots
  belong to edited projects and a durable save retires them. Restore, Discard,
  and cancellation remain owned by the launch/lifecycle UI.
- Generate Report creates one versioned deterministic JSON report on utility
  priority. A monotonically identified request adopts only its own result;
  cancellation, stale completion, encoding failure, copy failure, export
  cancellation, and write failure have bounded recovery messages.
- The report contains controlled build, OS compatibility, document-schema,
  retention, recovery-policy, and requirement metadata only. It does not read
  document/package state and excludes paths, authored values, credentials,
  raw stable identifiers, and diagnostic payload content.
- Copy and native user-selected Export remain disabled until a report is ready
  and reviewable. Export uses an atomic write outside the main actor.

## Focused evidence source (not executed)

- `SupportSettingsTests.testRedactedReportIsDeterministicUsefulAndContentFree`
- `SupportSettingsTests.testSupportStoreAdoptsLatestReportAndExposesTruthfulDistributionBoundary`
- `SupportSettingsTests.testUnavailableShareIsNeutralAndActionable`
- `SiteForgeLaunchTests.testSupportSettingsGeneratesReviewableRedactedReportJourney`

No build, test, UI automation, screenshot review, or `./sf verify` was run under
the owner pause. The normative modules remain Partial.

## Explicitly deferred

Network update feeds, signed-download verification, installer/relaunch/
rollback, signing/notarization, crash-log collection, project-content
attachments, plugin diagnostics, configurable retention, remote support upload,
performance/accessibility matrices, publishing, and release acceptance.
