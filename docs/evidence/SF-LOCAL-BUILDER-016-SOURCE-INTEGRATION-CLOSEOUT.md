# SF-LOCAL-BUILDER-016 — local-usability source integration closeout

IN PROGRESS — source closeout finished, acceptance-only handoff. No tests,
compiler/parser, build/check/lint scripts, collectors, apps/browsers/UI,
screenshots, performance or verification executed. No commit/push/install/sign,
scheduled work, owner package/resource/recovery or coordinator-ledger edits.
This closes source scope, not the milestone, installed app or specification.
Modules remain Partial. Do not start017 or automatically execute acceptance.

## Contract and inspected authority

Read AGENTS, actual dirty implementation/diff,007–015 receipts and the focused
acceptance manifest, current visual contract, ADR-0020 and OD-018/019. Bounded
workflow review: SF-0202-003, SF-0203-006, SF-0302-003/004, SF-0303-003/004,
SF-0701-002/003/006, SF-0806-003/004, SF-1202-003/004/006,
SF-1203-003/004/006, SF-1204-003/004/006, SF-1211-004/006.
Actual draft fixes additionally exercise SF-0702-003/004; this is not new
coverage for entire referenced modules or new box-style/output capability.

OD-018 supplied component content and OD-019 retained-conflict migration remain
open, unchanged and outside this batch. Their conservative fallback/reset rules
still apply. No new owner/security/architecture decision blocks this bounded
source closeout. No specification/DOCX or updater trust policy was changed.

## Pass A — production path and concrete fixes

| Path traced through actual entry points | Source result |
| --- | --- |
| Welcome/native New/Open → lifecycle/session → page selection | Existing lifecycle transition identities, guarded package adoption and page selection remain. No alternate document/store added. |
| Elements/Insert → automatic Header/flow Section/Footer → inline text/Image import → Inspector | Existing insertion registry, scene adoption, text/IME boundary and off-main image/resource preparation remain.012 visible import and direct common controls call those same paths. |
| Desktop/custom width → shared layout → canvas/selection/Inspector |007's one scene width and immutable preparation remain authoritative.014 layouts depend on actual pane/label metrics, not draft text; they neither recreate fields on width changes nor publish canonical geometry. |
| Formatting reuse / independent chrome copy |009/010 still use clean-only preflight, captured identities, actor dependency preparation and one registry batch; rendered success waits for adoption. Independent copies retain shared resource references without becoming linked chrome. |
| Save/Save As/Cancel → reopen | Native commands resolve the existing live window state and preflight before lifecycle snapshot/panel. Existing package/history/resource write and reopen paths are unchanged. The Design draft gap below is corrected at that preflight, not by changing persistence. |
| Preview → findings → editor → edit → Refresh → Safari/Export |015 retains exact attempt membership and conservative actual-target navigation. The additional live-project artifact guard below closes the deferred replacement interval without conflating last-successful and latest-finding identities. |

### 1. Legacy Design draft ownership and pre-snapshot commit

**SF-0702-003/004, SF-0202-003, SF-0302-004.**015 compared a group of raw display
strings with a reset-time baseline. `resetDrafts` overwrote every legacy string
on display refresh, including unrelated invalid drafts. Their delayed focus-loss
handlers could then operate without the original edit context. Commit-capable
Save/Preview preflight did not synchronously drain these fields or opacity before
taking its snapshot; clean-only repair rejected them but did not solve ownership.

`InspectorTextDraftState` is scene-local, not Codable/canonical. Six existing
fields (fill, border width, radius, content padding, shadow tuple and text color)
now capture original document/page/scene/revision/ordered selection/screen-size/
actual-width context and committed display. Clean/default/mixed fallback displays
read current projections and do not manufacture drafts. Dirty strings survive
refresh; changed ownership/value marks a conflict. A successful field commit
acknowledges only that field; unrelated text remains. Escape removes local drafts
and reloads current projections. Unchanged focus transitions create no property
edit and no spurious empty/default validation failure. Fill/text-color AX values
now expose actual unfinished text rather than falsely announcing committed color.
An equivalent box-style value now acknowledges the registry's typed no-change
result as successful without history, matching existing typography/fill policy;
a formatting-only numeric difference cannot leave a valid field stuck dirty.

Clean-only repair/reuse/copy requests reject dirty/conflicted/marked editors and
never commit. Existing commit-capable Save/Preview/context requests synchronously
submit a valid owned changed field or opacity through the existing typed registry,
reject invalid/stale/composing input and retain it. Queued Return/focus-loss work
checks captured context/draft equality; it cannot replay after that synchronous
commit or Escape. No registry is bypassed or mutation moved into a binding.
As with existing participant-based preflight, separately valid edits may commit
before a different participant rejects; no save/build snapshot is taken until
the whole preflight accepts. This is not a new multi-field history transaction.

The shadow tuple also previously discarded malformed components with compactMap,
allowing a five-part string containing garbage to become four valid numbers.
The shared `ShadowInspectorDraftParser` now requires exactly four nonempty finite
components and existing canonical bounds; it never coerces an invalid component.
This is input validation under SF-0702-004, not new effects or spacing support.

### 2. Retained artifact belongs to the live project at the action boundary

**SF-1211-004/006, SF-1204-004, SF-0302-004.**Session replacement forwards its
derived Preview invalidation on the next main event turn. Before that callback,
the retained plan/URL and captured export intent could still belong to the prior
project. `BrowserPreviewController.build` now accepts an independent live-document
predicate. Its successful artifact retains that predicate; build adoption,
Open Again, export-intent creation, export start and completion publication check
it synchronously. The shell supplies its current session's DocumentID.

This deliberately does NOT require latest revision for a retained successful
artifact: edits may leave Safari/Export on the explicitly named older revision.
Exact immutable plan/request validation, cancellation, writer safety and staged
bytes remain unchanged. Already authorized output is never retargeted to a new
project; a replaced project's completion cannot publish current success.

### 3. Check Website does not restart an active local write

**SF-1203-004, SF-1211-004.**The panel disabled Check while writing, but the
native command could call `startStaticBuildPreflight`, silently canceling that
write. Both Check entry points now reopen the existing running status and give
Wait/Cancel guidance without changing snapshot, request, phase or writer. Actual
Cancel remains the existing explicit operation. Silent panel dismissal now
transitions to Cancelled rather than leaving a taskless Writing phase, and the
running-only Wait guidance clears on completion/cancellation. No new writer or
retry loop. The same regression sources both reopen-after-cancel and absence of
contradictory Wait text after successful output.

## Pass B — independent source re-walk and friction

Revisited empty/default/single/mixed/locked displays, valid/invalid/stale draft,
Return/focus loss/Escape/IME, resize and screen-size changes, genuine field commit
followed by Save, canceling native panels, same-revision Preview failure, project
replacement, active Export/write, panel dismissal and asynchronous adoption.
No reset path now uses draft text to choose layout or silently overwrites a dirty
legacy Design field. Known stale input explains Escape/reload; no extra wizard,
settings pane or duplicate editor was added. Check during writing now exposes
the actual ongoing operation rather than requiring the user to discover why it
was canceled. Saved website properties remain distinct from app preferences.

013 availability is derived per immutable document/route snapshot and effective
visible links, not retained in a manual catalogue: page/link create, rename,
hide, remove, clone and Undo flow through the current document. Native preparation,
compatibility findings, static and connected-fluid adapters receive that same
availability input. Fixed logos, authored title constraints, unsupported
containing/positioning/menu clips and missing destinations remain truthful;
no additional source defect was found here. That observation is not browser
parity or a test pass. Existing exact missing-destination/copy/undo tests remain
in the finite acceptance inventory below.

All new/changed production signatures and call sites were manually inspected:
the Browser build parameter has a backward-compatible default for existing
controller fixtures, while the actual shell provides live document ownership;
the shared string state is used by all six controls, their resets/escapes and
command preflight; shadow parsing has one production caller. Optional/mixed
values and all five finding severities retain explicit branches. No debug logs,
force unwrap, direct canonical view write, test-only interface, new dependency,
schema change or owner-site special case was added. This was read-only source/
diff review, not a compiler, checker or runtime-warning clearance.

## One finite current acceptance matrix — NOT authorized to execute

Exact selector lists are owned once by the linked receipts, not copied into a
new broad suite. Expand only the rows approved by the owner, deduplicate shared
neighbors, and compile before treating a source method as runnable. No class,
whole-target or automatic historical-group rerun is requested by this document.

| Source item | Exact selector manifest | Deferred native/browser/visual coverage | Source blocker / historical evidence |
| --- | --- | --- | --- |
|007–011 width, Review, reuse, copy, connected output | [Frozen focused manifest](SF-LOCAL-BUILDER-007-011-FOCUSED-ACCEPTANCE.md), exact56+14 code/eight native methods plus named compositor/HTTP/title neighbors | Current changed paths only: width/focus/IME, independent copies/resources, real save/reopen, actual Safari CSS widths/menu/title and export cancellation | No new source blocker; historical70/70, eight distinct native passes, compositor3/3 and HTTP3/3 preceded012–016. Not current acceptance. |
|012 language/discovery | [012 exact source selectors](SF-LOCAL-BUILDER-012-USABILITY-AND-LANGUAGE.md), five code and one native method | Direct common actions, normal/compact/enlarged Inspector, component original/copy/reset and Settings-vs-website scope | All five+one UNRUN for this package; frozen title receipt predates it. |
|013 menu-first automatic chrome | [013 exact source selectors](SF-LOCAL-BUILDER-013-NARROW-CHROME-LAYOUT.md), nine code and one native/Safari method | Header AND Footer,320/430/fractional/current widths, pages/links unavailable or hidden, compact browser, actual CSS viewport and keyboard Menu/Escape | All nine+one UNRUN. Larger/custom fonts, sub320 and cross-engine certification not implied. |
|014 stable Inspector | [014 exact source selectors](SF-LOCAL-BUILDER-014-STABLE-INSPECTOR-LAYOUT.md), four code/one native plus two named existing layout neighbors | Normal/minimum/wider panes,150/200% text, focused dirty editor, component recovery, contrast/materials and no clipping | New four+one and refined overflow neighbor UNRUN. Original01/05/12 concepts absent from inspected checkout. |
|015 findings/repair/artifact identity | [015 exact source selectors](SF-LOCAL-BUILDER-015-PREVIEW-REPAIR-WORKFLOW.md), five code/one native and named export/component neighbors | Both panels, keyboard/pointer action, actual source/original entry/return, scroll/focus, stale/locked/no-target, retained output vs failed attempt and Safari Refresh | New five+one UNRUN; native journey refined by016 remains one method, not another tour. |
|016 integration fixes | Seven exact code methods listed below; one existing015 native method refined | Invalid Design draft blocking Preview/Escape, valid Save/Preview snapshot, opacity, equivalent-value acknowledgement, unrelated-draft retention, project replacement and active-write native status | Seven new code methods UNRUN; no known remaining editable source blocker after this closeout. |
| Milestone completion | Required final `./sf verify`, only after separately approved focused/visual acceptance | Original-resolution normal maximized and practical-minimum evidence; menu bar/Dock, upright text, frame/selection/clip, no ghost content, readable native panels | Mandatory and deferred, not waived. No installed delivery or full-spec completion. |

### Seven new016 exact code selectors — all UNRUN

`SiteForgeTests/TransformModelTests/`:

- `testLegacyDesignTextDraftCleanDefaultsMixedAndDisplayRefreshDoNotBlockNavigation`
- `testLegacyDesignTextDraftRetainsInvalidInputAndRejectsEveryChangedOwnershipBoundary`
- `testLegacyDesignTextDraftAcknowledgementNeverDiscardsAnotherFieldAndEscapeReloads`
- `testShadowInspectorDraftRejectsEmptyExtraMalformedAndNonfiniteComponentsWithoutCoercion`

`SiteForgeTests/CanvasRendererTests/testBrowserRetainedArtifactCannotOpenOrExportAfterImmediateProjectReplacement`

`SiteForgeTests/InsertionModelTests/testCheckWebsiteEntryDoesNotCancelOrRetargetAnActiveStaticWrite`

`SiteForgeTests/InsertionModelTests/testLegacyDesignEquivalentBoxCommitIsSuccessfulAndHistoryNeutral`

Refined native source (already counted in015):
`SiteForgeUITests/SiteForgeLaunchTests/testPreviewAndCheckWebsiteFindingRepairUsesExistingEditorJourney`.
Adds real invalid hexadecimal → native Preview rejected → text retained → Escape
reload before the existing repair/undo/Check/Refresh/Safari journey. Requested
attachments are future evidence, not files captured in016.

Additional existing event-boundary neighbors, each once, UNRUN against this tree:

- `SiteForgeUITests/SiteForgeLaunchTests/testDesignInspectorSolidFillOpacityKeyboardUndoRedoJourney`
- `SiteForgeUITests/SiteForgeLaunchTests/testDesignInspectorNativeSaveCloseReopenPersistsFillAndOpacityJourney`
- `SiteForgeUITests/SiteForgeLaunchTests/testDesignInspectorBorderRadiusShadowUndoRedoAccessibilityJourney`

The015 export/component neighbors and014 layout neighbors are referenced only
through their owning rows above; do not duplicate them in a new blanket suite.
Later012–016 new-source inventory:30 code methods and four distinct native
journeys, all UNRUN;016 adds no fifth native journey. Existing affected neighbors
and historical title/compositor/HTTP methods are separate, not added pass totals.

## Historical verification and stop point

`ba342938` owns the earlier full local gate:785 non-UI +151 UI passes =936,
zero failures, three intentional owner-session skips (939 total). Later007–011
focused results and the final frozen title run `focused-4cb5a055-d0fc-4c60-b300-8c405153fef0`
(3/3; six distinct title-related code methods across runs, one native/Safari
journey205.263s,15 originals at actual1440/430/320CSS widths) are bounded dirty-tree
historical receipts, not a committed SHA or verification of012–016. Existing
manifest retains exact artifacts and visual limitations; none were deleted.

Remaining work for this checkpoint is **acceptance-only**, not another feature
or a currently required owner product decision. Source is ready to REQUEST
bounded acceptance authorization; authorization is not assumed or requested
automatically by this file. Compilation may reveal issues; native/browser review
may reveal defects. Fix those only when execution is approved, then complete the
mandatory gate before any DONE/verified/delivery claim. Stop here, preserve all
work, and do not auto-start017, run tools, commit, push or alter installed data.
