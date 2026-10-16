# SF-AUTHORING-123 — Component-property discovery/navigation

Status: SOURCE IMPLEMENTED, VERIFICATION DEFERRED. New cycle Prompt 1/10.
Requirements: SF-0902-006/007; bounded SF-0701-002/003/004/006/007/008.
No normative module is promoted from Partial.

## Delivered source behavior

- `ComponentPropertyDiscovery` filters existing ordered organization entries by
  name, group, type and computed inherited/default/authored/conflict provenance.
  Case/diacritic-insensitive, whitespace-token AND matching preserves definition
  order and identities. Search processes at most 256 characters and never
  inspects user text values, destinations, asset contents or retained values.
- Native instance Inspector search, result count, conflict-only filter, Clear,
  Previous/Next and Return-to-first-result use the existing Inspector scroll
  owner. Property group focus supports up/down traversal; Tab continues into
  the original editor controls. Escape in search clears discovery only.
- Search/navigation/focus are view-local and reset on document/instance/
  definition replacement. Live metadata is reprojected, not copied. Removed
  filtered anchors lose navigation focus; stable surviving identities remain.
  Discovery's parent identity no longer changes with document revisions; value
  draft/recovery children still refresh against the adopted renderer identity,
  preserving stale-operation guards without clearing the search after a commit.
- All six existing field kinds retain their original central registry editors:
  text, visibility, choice, media, action and slot-fallback inspection. Missing
  bindings and orphan conflicts remain in unfiltered recovery. A hidden-conflict
  count explains why no match does not imply no retained conflict.
- Reset All explicitly discloses whole-instance scope, including filtered rows
  and conflicts. Filtering changes no transaction, revision, package, renderer,
  canonical property, reset input or supplied-slot policy. Locked/unavailable
  values remain inspection-only; discovery remains usable.

## Test source added — not executed

CommandKernelTests:

- `testComponentPropertyDiscoveryAllTypesGroupedOrderAndValuePrivacy`
- `testComponentPropertyDiscoveryConflictsRemainDiscoverableAndResetScopeUnfiltered`
- `testComponentPropertyDiscoveryTraversalLiveDefinitionAndContextReplacement`

SiteForgeLaunchTests:

- `testComponentPropertyDiscoveryNativeSearchClearTraversalAndContextJourney`

Three deterministic tests cover all kinds, grouped ordering, normalized search,
provenance, orphan conflicts, unfiltered scope, traversal boundaries, replacement
and serialization neutrality. One native journey source covers search/Return/
Tab, no-results, Escape recovery and definition-context replacement. Broader
native conflict, editing/history/reopen and accessibility/scale matrices reuse
119/120 evidence and remain required, not assumed passed.

## Prior accumulated acceptance and remaining risks

One saved-state/ownership read found collector `20261013-153433-e964329d`
finished, exit 1, no live collector. Build passed; repository and code stages
failed. UI runner initialization timed out enabling automation mode. Reports
remain under the ignored local full-verification directory; no relaunch or
repair of that accumulated gate is claimed in this independent source slice.

No tests/builds/compiler/parser/linters/checkers/UI automation or GitHub actions
ran for 123. Manual source review only. Native focus/scroll behavior, localization,
compact and increased-text rendering, accessibility announcements, retained
conflict recovery and performance still need execution after owner return.
Filtering unmounts excluded draft editors without committing their drafts;
canonical values stay intact, but draft/focus behavior requires native review.
No screenshot has been captured or visually accepted for this slice.

OD-018 supplied slots, OD-019 retargeting and OD-017 update signing stay blocked.
Remaining ordered development inventory: `../REMAINING_DEVELOPMENT_ROADMAP.md`.
