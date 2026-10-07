# SF-AUTHORING-100 — Component definition rename

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**

Requirements: bounded `SF-0901-001/002/003/004/005/006`, with supporting
`SF-0902-002/005/006`.

## Reconciled existing coverage

The project already contains one canonical local component graph: stable
definition PageIDs and linked instance NodeIDs, create/insert/edit-main,
plain-text and Boolean visibility properties with inheritance/reset, immutable
renderer expansion, detach and safe delete, responsive geometry/visibility,
search/Quick Open discovery, persistence/recovery, and safe static projection.
Assets already own import, stable AssetID/content hashes, organization/search/
usage filters, rename/replace/delete accounting, insertion, fit/focal/alt,
image fills, missing-resource preservation, package bytes, and portable static
references. This slice does not duplicate those source-complete systems.

## Delivered source contract

- Each definition row has a visible native Rename action and focused sheet.
  Its draft is scene-local; Cancel/Escape is noncanonical and invalid/duplicate
  names retain the sheet with a specific recovery message.
- `ComponentCommandRegistry` validates live identity, stable definition
  identity, UTF-8 name bounds, and uniqueness before compiling one transaction.
- Definition PageID, linked instance NodeIDs, overrides, geometry, descendants,
  and ordering remain stable while all linked display names update atomically.

## Added unrun evidence source

- `CommandKernelTests.testComponentRenamePropagatesStableIdentityPersistsAndUndoesExactly`
- `SiteForgeLaunchTests.testComponentDefinitionRenamePropagatesToLinkedInstancesJourney`

No build, test, UI automation, screenshot review, verification, commit, or push
ran under the owner pause. These tests are source, not passing evidence.

## Deferred scope

Slots/content projection, variants/states, nested components, media/enum/action
properties, arbitrary style overrides, bulk instance editing, remote/cloud or
cross-project libraries, browser runtime, performance/accessibility matrices,
preview/export acceptance, and release work remain deferred.
