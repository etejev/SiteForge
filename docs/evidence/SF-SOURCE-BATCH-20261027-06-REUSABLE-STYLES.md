# SF-SOURCE-BATCH-20261027-06 — Reusable visual style links

Current receipt: the listed new model methods and actual-app journey have passed
current-source affected acceptance. Final full verification passes:785 non-UI,
151 UI,0 failures,3 intentional owner-session skips; full-e7ee511e is the
authoritative939-method result. The bounded local slice is accepted.
The implementation-time UNRUN/owner-hold text below is historical and superseded
by approved local acceptance. Exact correction results and inspected screenshots
are indexed in [the integration receipt](SF-SOURCE-BATCH-20261027-10-INTEGRATION.md).
Normative modules remain Partial; no push or installation is authorized.

**IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.**

Queue remains IN PROGRESS; modules remain Partial. Static source inspection and
editing only. No compiler, tests, verification/check scripts, UI automation,
readiness probe, app/browser launch, install, signing, commit or external action.
There are no new screenshots or observed runtime results. Historical cancelled
verification does not cover this source.

## Bounded contract

SF-0510-002/003/005/006: edit/apply linked styles, predictable precedence,
transaction/history/persistence and accessible operations. Supporting
SF-0508-003/005/006 and SF-0509-003/005/006: appearance resolution, existing
token bindings, noncanonical drafts and explicit cancellation. Existing definitions
store solid RGBA8 fill and opacity only. Shared gradients, borders/shadows,
token aliases, stylesheet editing and broad module acceptance are not added.
Application theme is separate from authored visual styles.

## Gaps and source changes

Previously Apply replaced the complete link array, mixed links disabled Detach,
Update immediately affected all uses, and capture could silently omit a mixed or
gradient fill. Normal fill/opacity fields could disagree with inherited rendering.

- `SiteForge/TransformModel.swift`: typed link/unlink/adjacent-reorder edits use
  the existing applied-list property and identity-gated atomic registry. Later
  specified values win through the existing resolver. Repeat/boundary operations
  are neutral. Exact inverses retain PropertyIDs, order, presence and provenance.
- Explicit Use Linked Fill removes only local fill namespace/legacy fill keys;
  Use Linked Opacity removes only local opacity. They require an actual supplying
  linked definition. Explicit None (empty/disabled layers or legacy none), fill
  token bindings and image fills reject fill-reset atomically. Active gradient
  removal requires the visible confirmation; Undo retains exact layer/stop IDs.
- Capture requires a common resolved single solid and common opacity across the
  applicable subset. Mixed, None, image, gradient and layered captures are rejected
  instead of flattened/partially stored. The captured color uses the existing
  RGBA8 definition codec; original source colors and token bindings are unchanged.
  Capturing a token-resolved color stores a snapshot, explicitly not a live alias.
- `SiteForge/WorkspaceShellModel.swift`: effective appearance projection, source
  summaries and authored usage counts reuse existing canonical resolution. Usage
  counts nodes/pages/definitions, not rendered component-instance multiplicity.
  Context/revision/current-renderer checks guard confirmations and queued opacity
  commits. Equal inherited opacity remains omitted rather than becoming a literal.
- `SiteForge/WorkspaceShellView.swift`: native Link/Unlink/Earlier/Later,
  explicit inheritance actions, visible supported-scope/source explanations,
  capture validation and confirmed shared update with usage disclosure. Controls
  route through the registry, never direct property writes. Mixed Detach explicitly
  removes all selected links, not local styles. Delete remains blocked while used.
  Opacity typing owns a scene-local numeric draft/opening context; unchanged focus
  loss is neutral, stale/invalid drafts remain visible until corrected or escaped.
  A queued earlier draft cannot overwrite a later shared-style value.

No schema, style store, token store, output renderer, migration or history format
was introduced. Existing immutable native preparation and static compiler remain
the consumers. Transparent/None continues to defeat inherited fill; token and
image ownership is not silently detached. Existing state variants are preserved.

## Acceptance source — all UNRUN

`Tests/SiteForgeTests/TransformModelTests.swift`:

1. `testReusableStyleLinksPreserveMixedOrderingAndExactHistory` — additive links,
   applicable subset, order, no-op/cancel, exact history, serialization, redaction.
2. `testReusableResetProtectsNoneAndTokensAndRestoresGradientIdentities` — atomic
   protected reset, local opacity isolation, layer/stop/property inverse, no-bake
   inherited opacity and None after shared update.
3. `testReusableCaptureRejectsMixedComplexAndNoneWithoutDetachingTokens` — common
   capture, token preservation, mixed/gradient/None rejection.
4. `testReusableLinksAdoptSharedAppearanceWithoutRevivingNoneOrTokenOverrides` —
   multi-page shared update, immutable renderer/Inspector/output agreement, None,
   token-local override, stale confirmation/focus-loss neutrality, serialization.

`Tests/SiteForgeUITests/SiteForgeLaunchTests.swift`:

5. `testReusableStyleLinksInheritanceScopedUpdateAndNonePreservationJourney` —
   real controls, link order, inheritance confirmation/cancel, global update
   confirmation/cancel, None protection, Undo/Redo and future named attachments.

Future execution must explicitly approve testing first; run these exact focused
selectors, compile and inspect native original-resolution attachments before any
acceptance claim. Existing positioning/reusable-style journey remains a regression
dependency. Dedicated package/autosave/recovery, performance, localization,
VoiceOver and compact-layout execution are not proven by these source additions.
No tests or visual results are inferred from code inspection.
