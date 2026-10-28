# SF-SOURCE-BATCH-20261027-01 — Site and page setup

Current receipt: the listed new model methods and actual-app journey have passed
current-source affected acceptance. Final full verification passes:785 non-UI,
151 UI,0 failures,3 intentional owner-session skips; full-e7ee511e is the
authoritative939-method result. The bounded local slice is accepted.
The implementation-time UNRUN/owner-hold text below is historical and superseded
by approved local acceptance. Exact correction results and inspected screenshots
are indexed in [the integration receipt](SF-SOURCE-BATCH-20261027-10-INTEGRATION.md).
Normative modules remain Partial; no push or installation is authorized.

**IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.**

Queue remains IN PROGRESS. SF-1207 and supporting page/asset modules remain
Partial. No build, test, check script, UI automation, app/browser launch or manual
acceptance journey was performed for this slice. Static inspection only.

## Applicable bounded contracts

- SF-1207-001/002/003/004/005/006/008: existing typed metadata, native authoring,
  inheritance/reset, stale/cancel neutrality, history/persistence and unrun tests.
- SF-0303-003/004/005/006: preserve current-page identity, route validation,
  navigation-label intent and transactional page commands.
- Existing asset boundaries (not newly completed): SF-0801-001/004/005 resource
  identity/original-byte retention, dependency handling and missing references.
- ADR-0022 governs the existing metadata version and local output. No new schema
  or architecture decision. OD-018/019 and external-service boundaries unchanged.

## Inspection findings: preserved versus new

Already implemented and preserved: site name, closed browser-title pattern,
default/page description, favicon AssetID, page title, canonical per-page indexing,
route/name/reorder/duplicate/delete commands, exact metadata history, favicon
dependency usage/deletion guard, sidecar resource storage and shared escaped
title/description/robots/icon emission. Empty current-page overrides were already
omitted by the view; this is not reported as a newly discovered runtime defect.

Concrete gaps closed in source:

1. `SiteForge/WorkspaceShellView.swift`: Pages exposes **Site & Page Settings…**;
   current Page Actions exposes **Page Metadata…** without choosing another page.
   Existing File > Site Settings remains available. Existing adaptive Pages
   controls and native grouped/scrollable sheet are reused, not a new Settings
   destination or app-wide redesign.
2. Existing per-page indexing is now editable as Inherit / Allow / Discourage.
   Reset Page Overrides removes page title, description and indexing overrides
   while preserving site defaults and every other page's record. The UI explicitly
   says robots preferences do not guarantee search indexing/removal.
3. The sheet retains its opening canonical document as a scene-local copy-on-write
   snapshot. Preview and favicon choices cannot silently retarget as observed
   workspace state changes; Apply still uses the original identity-gated
   `WebsiteMetadataCommandRegistry`. No direct canonical view write was added.
4. The local draft snippet shows title/description provenance, page route and
   navigation-name guidance. Page name remains the default navigation label;
   explicitly authored link labels remain independent. Rename/Edit Route continue
   through their existing validated commands in Page Actions.
5. Missing favicon guidance retains the AssetID and offers the existing image
   picker/None repair path. Imported original bytes remain owned by ResourceStore;
   no path field, re-encoding or duplicate asset store is introduced.
6. `SiteForge/DocumentModel.swift`: `WebsiteMetadata.replacingPageOverride` shares
   the existing omission/sorting rule between native drafts and acceptance source.
   No metadata fields/version or persisted package shape changed.

## Shared output/resource inspection

`WebsiteMetadataResolver` is still used by both the native draft preview and
`MultiPageStaticBuildPlanner`. `StaticSEOEmitter` escapes the resolved title and
description and emits the committed robots preference. Favicon output paths
come from the existing static image-resource planner. `StaticBuildCompiler`
reports missing favicon/resource identity rather than silently changing content.
`ProjectResources.swift` inventories favicon uses; the command kernel prevents
direct deletion of a referenced image. These paths were inspected, not executed.

## New acceptance source — five selectors, all UNRUN

- `PersistedHistoryTests/testSiteSetupPageIndexingResetPreservesOtherOverridesAndExactHistory`
- `PersistedHistoryTests/testSiteSetupRouteRenamePreservesPageMetadataAndLinkIntentInOutput`
- `ProjectResourceTests/testSiteFaviconUsesTrackedResourceAndKeepsOriginalBytesAcrossMetadataUndo`
- `TransformModelTests/testSiteSetupOpeningPageIdentityCannotCommitAfterPageSwitch`
- `SiteForgeLaunchTests/testPagesSiteSetupPageIndexingResetAndCancelJourney`

Coverage intent: atomic reset/exact inverse, inherited indexing/provenance,
serializer round-trip, stable page/link IDs across rename/route edits, collision
rejection, immutable escaped output, tracked favicon byte preservation/deletion
guard/missing repair, stale opening-page rejection, and native picker/Apply/
Escape/Undo. Future UI captures are declared in test source; none were generated.
Existing metadata cancellation/stale/malformed, package/recovery, favicon and
page-command assertions remain in place. No assertion was weakened.

## Limits and next acceptance boundary

No social-image reference model currently exists; ADR-0022 explicitly defers
social cards. This slice does not add Open Graph images, structured data, remote
SEO accounts, live indexing checks, language/domain policy or publishing.
It does not claim completed preview/export parity, large-scale performance,
minimum-width visual acceptance or release readiness. Compilation, the five
selectors, native visual inspection and the mandatory full gate require separate
owner approval. No installation/signing/commit/push or other GitHub mutation.

All earlier dirty work, owner projects/resources/recovery and approved Dark Flow
content/export are preserved. Historical 733 code +100 UI passes /3 skips /1
cancelled case /38 UI not reached remain partial evidence for older source, not
verification of this slice or the preceding Page Background source changes.
