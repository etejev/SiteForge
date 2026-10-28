# SF-SOURCE-BATCH-20261027-02 — Header/Footer and navigation

Current receipt: the listed new model methods and actual-app journey have passed
current-source affected acceptance. Final full verification passes:785 non-UI,
151 UI,0 failures,3 intentional owner-session skips; full-e7ee511e is the
authoritative939-method result. The bounded local slice is accepted.
The implementation-time UNRUN/owner-hold text below is historical and superseded
by approved local acceptance. Exact correction results and inspected screenshots
are indexed in [the integration receipt](SF-SOURCE-BATCH-20261027-10-INTEGRATION.md).
Normative modules remain Partial; no push or installation is authorized.

**IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.**

IN PROGRESS, not verified/DONE. Relevant modules remain Partial. No tests, builds,
check scripts, UI automation, readiness probes, manual visual journeys or app/
browser acceptance launches occurred. Static source/diff inspection only.

## Scope and existing behavior

Bounded requirements: SF-0501-003/005, SF-0601-003, SF-0602-003/006,
SF-0806-002/003/005/006. ADR-0020 already defines connected Header first/Footer
after content, full available width, actual editable title/content/navigation
nodes, stable page links, exclusion by hiding rather than deleting, and native
mobile menus. Those behaviors, height/padding, title visibility/provenance,
included-page toggles, labels/destinations/order and content customization already
exist. They were inspected and preserved, not reimplemented from a stale roadmap.
No fixed/sticky positioning or external navigation policy was added.

## Concrete source gaps closed

- `SiteForge/DocumentModel.swift`: the shared navigation-gap projection reads the
  existing Navigation Stack's ordinary/responsive/fluid gap. The layout policy
  accepts that gap and bounds it to available width for zero/one/many links.
  Legacy direct-owner navigation retains its existing 16-point default.
- `SiteForge/InsertionModel.swift`: immutable structural child frames and connected
  CSS both consume the same projected gap. This replaces a hard-coded 16-point
  gap in each path; it does not patch generated owner output or object positions.
- `SiteForge/TransformModel.swift`: `PageStructureEdit.navigationGap` validates
  active scope, node/reference ownership, finite 0–10,000 values and captured
  identity through the existing registry. Desktop writes `layout.gap`; Tablet/
  Mobile write the existing responsive container key. Reset removes only that
  property and reveals inheritance/defaults. Fluid Desktop intent is not silently
  replaced. Existing command-kernel batching supplies exact inverses; unchanged
  stored values remain neutral. No canonical key/schema or history format added.
- The same registry adds `showContentImage` for an explicitly identified direct
  Image child of that Header/Footer's actual Contents Stack. It rejects unrelated,
  missing or locked nodes. Base hidden state changes only; AssetID, NodeID,
  geometry/order, descendants and device visibility overrides remain untouched.
  There is no separate logo catalogue or arbitrary-image auto-selection.
- `SiteForge/WorkspaceShellView.swift`: existing Header/Footer settings now show
  Inline Link Gap, Apply, Cancel Gap, current provenance and Reset/Reset Override.
  Numeric drafts remain local, Escape cancels, and scope changes refresh drafts.
  Validation remains visible outside collapsed customization. Existing fluid
  Desktop gap points to Layout instead of accepting an ignored edit.
- Actual Contents Images appear as named Image/Logo visibility toggles with
  explicit base-scope guidance. Select Contents provides the existing Image
  insertion/customization route; no fake logo/fixture is inserted. Long names
  retain full accessibility/help text. Existing native controls/Inspector scrolling
  and editor 01/05 hierarchy remain; Settings12 is not copied into a new scope.

Inline gap applies to the row of links. The real native collapsed mobile menu
keeps standard platform spacing and its established keyboard/focus/Escape behavior.
Visitor menu-open state remains noncanonical; no interaction handler was replaced.

## New acceptance source — six selectors, all UNRUN

1. `InsertionModelTests/testHeaderNavigationGapSharesResponsiveFramesCSSAndExactHistory`
2. `InsertionModelTests/testHeaderNavigationGapRejectsInvalidCancelledLockedAndWrongScope`
3. `InsertionModelTests/testNavigationGapPolicyHandlesZeroOneManyAndNarrowBounds`
4. `InsertionModelTests/testHeaderImageVisibilityRetainsResponsiveIntentAndExactInverse`
5. `InsertionModelTests/testHeaderIncludedLinksKeepIdentityAcrossZeroOneManyAndPageLifecycle`
6. `SiteForgeLaunchTests/testHeaderFooterInlineGapResponsiveResetAndDraftCancellationJourney`

Coverage intent: shared native/render-tree/CSS geometry; base/override/reset and
serializer/reopened output; exact property/child identity Undo/Redo; malformed,
nonfinite, cancelled, locked, stale-revision and wrong-breakpoint rejection;
bounded empty/single/many-link rows; image visibility preserving resources and
responsive intent; exclusion/reinclusion IDs; custom labels across rename,
missing destinations after delete and Undo; native Header/Footer fields,
validation/cancel, preset provenance and future named screenshots.

Existing title options, Header/Footer anchoring/full-width layout, mobile menu
keyboard/focus and package/history/reopen assertions are retained. After owner
approval, include the directly affected existing
`testConnectedHeaderFooterNavigationMenuHeightUndoAndReopenJourney` and
`testHeaderContentsTitleInclusionCustomizationAndExactHistory` alongside the
new affected selectors; do not treat their historical results as new acceptance.

## Limits and preservation

No runtime, pixel, original-resolution visual, practical-minimum layout, browser
or release acceptance is claimed. Image insertion/replacement/alt text still use
the existing Assets/Image workflow; the visibility list intentionally includes
only actual direct Contents Images. Nested custom Images remain editable through
their ordinary existing selection/Inspector, not guessed as a logo. Legacy Header/
Footer can use the existing explicit Add Editable Title and Navigation command;
opening a package does not convert it. Sticky/fixed roles, arbitrary menu
breakpoints and external destinations remain deferred per ADR-0020. OD-018/019
and all owner-decision boundaries are unchanged.

All prior dirty changes and owner projects/resources/recovery/evidence are
preserved. Dark Flow's approved gradient and saved website/export are untouched.
No installation, signing, commits, pushes, external writes or GitHub mutations.
Earlier partial gate (733 code +100 UI passes /3 skips /1 cancellation /38 UI
not reached) belongs to older source and does not verify these edits. All further
execution and the mandatory future full gate require explicit owner approval.
