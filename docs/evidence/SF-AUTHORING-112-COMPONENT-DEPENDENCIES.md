# SF-AUTHORING-112 — Local component organization and dependency inspection

Verification checkpoint (2026-10-08): repository/build gates and the complete
non-UI target ran; corrected non-UI coverage is green. The actual-app journey
remains unexecuted because XCTest timed out during runner initialization.

## Bounded contract

This source slice covers bounded `SF-0205-002/003/004/006/007/008`,
`SF-0901-003/004/005/006/007/008`, `SF-0902-002/004/006`, and the
inspection-oriented portions of `SF-0907-003/004/006/007/008`.

The specification does not define canonical component folders, tags,
favorites, or arbitrary authored documentation metadata. Organization is
therefore a reversible scene-local projection: normalized name search;
All/In Use/Unused/Issues filters; and Project Order/Name/Most Used sorting.
None of those controls change the document, history, package, or component
identity.

## Delivered source behavior

- `ComponentDependencySnapshot` is an immutable document/revision-tagged
  index with stable component, page, node, container, asset, token, reusable
  style, exposed-text, and exposed-visibility identities.
- A bounded utility-priority actor prepares the index away from the main
  actor. New document revisions cancel prior work, and request/document/
  revision guards reject stale adoption. Limits are 1,000 definitions and
  10,000 canonical nodes.
- Every definition reports deterministic Where Used locations, direct and
  transitive component references, assets, tokens, reusable styles, exposed
  properties, dependent definitions, unresolved resources, unsupported
  nesting, and cycles.
- The native Components pane provides accessible filter/sort controls,
  dependency status, and a Component Details sheet. Where Used changes only
  scene page/navigator/selection state; hidden instances open Layers without
  fabricating a canvas target or ghost.
- Existing rename remains the identity-preserving maintenance path. A valid
  unused definition can use the existing atomic remove command; a used valid
  definition can use the existing exact-inverse detach-and-delete command.
  Replacement is explicitly unavailable because compatible replacement
  semantics are not specified. Existing direct Delete confirmation remains
  available and unchanged for compatibility.
- Transfer readiness reuses the current supported local dependency contract
  from SF-AUTHORING-111. Static-output readiness points to the established
  SF-AUTHORING-110 Build Diagnostics boundary instead of introducing another
  compiler or readiness source.

## Source tests added, not executed

- `SelectionModelTests.testComponentOrganizationAndDependencySnapshotPreserveCanonicalIdentity`
- `SelectionModelTests.testComponentDependencySnapshotReportsNestedCyclesAndBoundedCapacity`
- `SiteForgeLaunchTests.testComponentOrganizationDependencyInspectionAndWhereUsedJourney`

The tests cover deterministic organization, usage/unresolved indexing,
dependency issues, safe-maintenance predicates, malformed nested cycles,
capacity rejection, native inspection, and Where Used navigation. They were
intentionally not run under the current owner pause. No XCTest, UI automation,
or `./sf verify` result is claimed.

## Checks actually run

- Swift parser check for the two production and two test files: passed.
- Universal macOS app compile through `./sf dev`: passed for arm64 and x86_64.
- Requirement-evidence JSON, traceability, security, and diff checks: recorded
  after documentation reconciliation.

## Explicit exclusions

Persistent folders/tags/favorites, authored component documentation/example
content, compatible definition replacement, nested-component authoring,
slots, variants, remote libraries, marketplace/cloud/collaboration,
arbitrary instance style overrides, cross-project global indexing, fuzzy
ranking, preview/export certification, broad performance/accessibility/
localization matrices, and release acceptance remain deferred. The normative
modules remain Partial.
