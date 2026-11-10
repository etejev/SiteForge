# SF-LOCAL-BUILDER-013 — narrow automatic chrome, SOURCE ONLY

IN PROGRESS. No compilation, tests, scripts, app/browser launch, screenshots or
verification performed. Earlier title acceptance is frozen and does not verify
this source. Execution remains paused; no commit, push, installation, signing,
owner-data edit or next dispatch.

## Contract and first divergence

Bounded SF-0501-003/004/005/006, SF-0502-003/005, SF-0505-003,
SF-0601-003/006, SF-0602-003/006, SF-0806-002/003/004/006,
SF-1202-003, SF-1203-003, SF-1204-003 and SF-1211-004. Modules remain Partial.

At 320 points, the ordinary automatic row has 224 points after owner padding.
The default 200-point title plus 24-point gap consumed that budget before the
nested navigation received usable space. The first divergence was shared
structural allocation, not title paint or selection. Browser flex shrink also
had no menu floor. The previous title line-budget repair remains unchanged.

## Source correction and limits

One derived `AutomaticMenuRow` policy runs after structural/responsive sizing.
It reserves the existing native Preview's 90-point Menu budget, fixed siblings
and spacing before shrinking default title space. Default gap can reduce when
necessary; authored gaps do not. Hidden titles reserve no title width/extra gap.
Native render/selection/hit geometry and Preview consume those final shared
frames. Static and connected-fluid CSS use matching flex priorities and a
continuous containing-box gap expression; existing wrapper/padding applies once.
No canonical mutation, new breakpoint, schema or preset-sampled coordinates.

Eligibility is closed: automatic horizontal rows, base/default title width,
fixed non-navigation children and supported default navigation typography.
Custom rows, authored sizing, fluid title/container spacing and larger/custom
fonts retain existing intent/path. Existing Header/Footer settings explain
insufficient width/height from the adopted scene snapshot rather than computing
layout during view construction. Fixed logos retain their dimensions.

Menu requires a visible available destination. Hidden/empty links, missing
destinations and hamburger-off preserve IDs/preferences. Per-breakpoint CSS uses
actual document page availability, including hidden-valid/visible-broken links.
A helper without document context only knows its own page. The same ephemeral
availability input now reaches final native geometry, Preview, static render-tree
geometry, connected snapshots, both CSS adapters and menu-room preflight. It is
not another stored catalogue. A row without visible links reserves no navigation
width or gap; broken visible links retain their disabled inline intent without
reserving a 90-point Menu. Availability changes do not rewrite content or history.
Empty-link rows lose the absent slot even with Menu switched off; the preference
is not changed. Fixed sibling budgets accumulate in authored child order, not
dictionary iteration order, keeping derived numeric/CSS output deterministic.
Existing positioning,
containing-block and clipped-menu output blockers remain. A 320-point compatibility
probe rejects known insufficient rows with repair guidance; it is not a new
breakpoint or certification below 320. Native allocation uses actual width.
Universal custom-font, sub-320 browser and cross-engine parity are not claimed.

## Added acceptance source — ALL UNRUN

`SiteForgeTests/InsertionModelTests/`:

1. `testAutomaticChromeMenuFirstAllocationAtPhoneFractionalAndLargerWidthsIsReadOnly`
2. `testAutomaticChromeHiddenEmptyLongAndMultilineTitleRetainsIdentityAndLinePolicy`
3. `testAutomaticChromeMenuCardinalityVisibilityAndOffPreferenceRemainTruthful`
4. `testAutomaticChromeMissingDestinationsDoNotCreateDecorativeMenu`
5. `testNarrowChromeCustomSizingSpacingFontsAndFluidIntentAreNeverRewritten`
6. `testAutomaticChromeFixedLogoAndAuthoredGapUseSameInnerBudget`
7. `testAutomaticChromeStaticAndFluidAdaptersKeepSharedContinuousAllocationAndBlockers`
8. `testAutomaticChromeNativeSceneSelectionHitAndPreviewShareFinalMenuFrame`
9. `testAutomaticChromeEditsCopiesUndoPackageAndRecoveryKeepAllocationNoncanonical`

Source covers 320/360/390/430/599.5/600/768/1024/1440 and custom/fractional
widths; Header/Footer, title states, links, logos/custom constraints, immutable
adoption, compiler blockers, copy/history/package/recovery. None is a pass receipt.

`SiteForgeUITests/SiteForgeLaunchTests/testAutomaticNarrowChromeNativeAndMeasuredSafariMenuJourney`
is one future fresh-process native/current-Safari journey using real controls,
measured viewport/DOM bounds, title identity, menu Escape/focus/destination checks
and screenshots. UNRUN: no new visual or browser acceptance exists. Compact-window
and broader browser review, focused execution and final verification remain
deferred, not waived. Do not reuse earlier passes as evidence for this package.

Owner revision/recovery, installed app, OD-018/019, resources, original routes,
stable identities, command ownership and all prior work remain preserved.

## 2026-11-01 continuation: two source-only usability passes

Pass A traced insert Header/Footer → edit title/include pages/menu → change
screen width through shared final sizing, native scene/Preview and both output
paths. The remaining inconsistency was width reservation using visible link nodes
while the Menu used actual destination availability. Both now use the same
document/route-derived availability set. Empty navigation has no phantom slot;
independent copies still resolve valid original-page destinations. Authored empty
Text remains an actual editable node, not an implicit visibility edit. Hidden
titles use existing visibility and reserve no title slot. Full text and the frozen
semantic title/line budget remain unchanged.

Pass B reviewed existing title provenance, Menu help, include-page toggles,
individual missing-link repair, custom layout, numeric validation, Cancel/Escape,
disabled fluid controls and mixed/applicability gates. Menu help now describes
narrow screens and available pages rather than implying any link node creates a
Menu. Empty/unavailable destinations get a concise explanation beside existing
controls. Constrained custom rows say Select Contents to reduce sizes/spacing;
no second settings hierarchy or new command path. Existing field IDs, link repair,
atomic commands and custom values remain. No broader browser/custom-layout
certification or new component decision is implied.

The same nine code methods were refined (not executed): missing-link tests now
cover actual static/fluid CSS and no phantom budget; empty-link source checks
verify title-only allocation; worker coverage includes unavailable destinations;
copy coverage supplies real document availability. One native/Safari journey
remains UNRUN. The journey measures Header bounds; separate Footer/compact visual
review remains in the deferred acceptance inventory. Source implementation and
consistency review are finished, not compiled/visually accepted/verified. No014.
