# SF-AUTHORING-021 — Static page management

## Bounded contract

Requirements: SF-0303-001–008, supporting SF-0306-005, SF-0307-001–005
and SF-1102-001–005. The normative modules remain Partial.

The Pages pane, native Page menu and row context menu share PageCommandRegistry.
New pages have fresh PageID/root identity and no rendered/sample content.
Names and routes are independent; new routes trim outer whitespace, normalize
ASCII case and accept slash-separated letters, digits, hyphens and underscores.
Empty segments, query/fragment/encoded/dynamic paths and reserved `/` or `/404`
are rejected. Names are bounded to 256 UTF-8 bytes, routes to 1024. Historical
valid routes remain readable, and exact inverses restore their spelling.
Home/Not Found roles and routes cannot be deleted/reassigned by authoring UI.

Page edits use existing canonical commands, document/revision/page identity,
native scene ownership and lifecycle availability. Snapshot autosave does not
disable editing. Invalid/stale drafts remain in the sheet; Escape cancels.
Route/reorder commands participate in strict persisted-history shape validation.
No document schema bump or second page/resource store is introduced.

Duplication preserves node order, styles, responsive data and asset references;
it regenerates page/node/property/guide identities and remaps self-page and
internal section links. Outbound intent and immutable resource bytes are reused.
Ordinary deletion reports object/inbound-link impact. Page guides are deleted
atomically; undo restores exact IDs, order and guide positions. Incoming links
remain repairable missing targets rather than being silently detached.
Switching pages cancels scene-local editors and repairs selection/render state.
Rename/route/reorder on the active page do not unnecessarily clear selection.

## Focused evidence

Passed initially: three independent CommandKernelTests and the actual-app
`testStaticPageManagementRoutesHistoryAndReopenJourney` (1/1). The first UI
attempt exposed a test query that ignored the shipping combined name/route AX
label; the corrected query retains exact route and stable-ID assertions.

Additional package/recovery and compact-menu/target tests passed (2/2):
`testStaticPagePackageRecoveryHistoryAndLegacyRouteInverse` and
`testStaticPageCompactProtectedRolesAndLiveLinkTargetJourney`.

Exact focused model selectors:
- `testStaticPageRoutesValidationIdentityAndAtomicHistory`
- `testStaticPageDuplicateRemapsInternalLinksAndDeleteUndoPreservesIntent`
- `testStaticPageStaleCancelledUnavailableAndNoOpAreNeutral`
- `testStaticPagePackageRecoveryHistoryAndLegacyRouteInverse`
- `testStaticPageDuplicateSectionTargetsGuidesAndBoundedNodeOrdering`

All five model selectors and both new UI journeys passed, as did the affected
prior `testButtonLinkInternalTargetControlsAtPracticalMinimum` journey.
The bounded-scale fixture covers 100 and 10,000 children; its initial missing
Section defaults were corrected rather than weakening canonical validation.
The strengthened invalid-name/diagnostic/guide-deletion selectors passed 3/3.
Repository/security/traceability checks and diff whitespace checks passed.
Final authoritative `./sf verify` passed 404 unit/integration + 54 UI tests
(458 total), zero failures. The result is
`full-45261c55-daad-4483-9e36-915e4c271bf1.xcresult`.
No separate complete UI run preceded this gate. Hosted acceptance follows
the authorized commit/push and is not inferred from the local result.
Final diff review caught a long-Unicode duplicate-name edge case. The shared
policy now truncates only at complete character boundaries within the UTF-8
limit, and its focused regression passed. The first full run was deliberately
interrupted after 404 non-UI passes so the final gate includes this correction;
that interrupted run is not milestone acceptance.

## Visual review

The maximized journey's five retained window attachments were inspected:
new empty page, invalid reserved route, duplicate/reorder, delete impact,
and reopened page. Canvas content is upright, fitted and free of stale
objects; page names/routes/actions are readable. The inspection identified
placeholder-only field labels, now replaced with persistent visible labels.
The confirmation uses native destructive-button semantics. Both compact
screenshots (page fields and live Button/Link page-target metadata) were also
reviewed: persistent labels, fields, buttons and full route metadata are legible.
Evidence is stored as XCTest attachments, not machine-specific repository files.
Retina backing-scale evidence is not claimed as full 200% accessibility text
scaling or VoiceOver certification; those broad matrices remain unverified.

## Deferred scope

Folders, CMS/dynamic routes, localization, redirects, role reassignment, SEO,
navbar/footer templates, runtime navigation, export/publication, full OS
accessibility/localization matrices and release acceptance are not implemented.
No future controls or sample content are fabricated.
