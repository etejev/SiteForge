# SF-LOCAL-BUILDER-012 — usability and language source package

Status: IN PROGRESS — SOURCE IMPLEMENTED, UNVERIFIED. All execution paused by
owner after the frozen managed-title receipt. No tests, compilation, checks,
app/browser launches, visual inspection, performance measurement or full gate
were run for this package. No commit, push, installation or owner-data change.

## Contract and preserved boundaries

Bounded supporting SF-0202-003 (navigation without content mutation),
SF-0203-006 (shared commands and accessible labels), SF-0206-002 (preference
scope), SF-0701-002 (Inspector discovery), SF-0702-003 (draft/commit provenance),
SF-0703-003 (mixed/applicable values) and SF-0704-003 (winning source).
All normative modules remain Partial. No schema, command IDs, accessibility IDs,
property keys, enum raw values, stored content, resolver or transaction changes.
OD-018 supplied slot ownership and OD-019 conflict migration remain open and
unchanged. No new architecture decision is required for presentation-only work.

Read the specification clauses, AGENTS, ADR-0020, current queue/status/handoff,
001 friction record, selected-reference evidence and visual contract. References
01/05/12 inform the documented shell, responsive ownership and Settings roles.
Their original PNGs were not available in this checkout during this source pass;
this is not a new original-render comparison or visual acceptance claim.

## Pass 1 — workflow, then source review

Moved the one existing FormattingTransferControls surface from the collapsed
Inspector Tools disclosure into the shared selected-object header, across all
five Inspector destinations. No parallel actions or editors: the same Copy/Paste
commands, background dependency checks, identity gates, cancellation and atomic
registry preparation remain in use. Search/pinning/geometry transfer stay in
Inspector Tools. The detailed formatting contract moved to help; mixed, skipped,
failure, progress and cancellation feedback remains visible.

Source action paths, not measured click counts or elapsed-time savings:

| Task | Before | After/source finding |
| --- | --- | --- |
| Reuse text style/appearance from Inspector | Selected object → Inspector Tools → Reuse Formatting → command | Selected object → Reuse Formatting → same command; native Edit commands unchanged |
| Import an image | Assets → plus icon, discover name through help | Assets → visible Import Images… button; same import command/panel |
| Site/page metadata | Pages Site & Page Settings / Page Metadata / File Site Settings | Consistent Site & Page Settings entry names, same guarded sheet |
| Text/size/destination | Design Essentials already has Edit Text, size and destination | Retained; no duplicate text editor or additional tab detour |
| New/Open/first edit | Welcome/native File → validated document → Elements/Insert | Retained; failure recovery and New/Open ownership unchanged |
| Connected page Header/Section/Footer | Elements/Insert → existing role controls → Return/Apply | Retained; inner-spacing labels align with Layout/Design, no automatic conversion |
| Independent chrome reuse010 | Page/Header/Footer → Copy Header/Footer to Pages → target sheet | Retained; independent add-missing copies, not linked component propagation |
| Responsive007/008 | Width/Compare → exact node Layout/review → existing fields | Retained; header help distinguishes preview width from property editing scope |
| Components | Components → existing definition edit → Return to Instance | Retained; source values now say Uses component default / Set here · this instance |
| Save/reopen | File Save/Open → lifecycle and adoption | Retained, no new save route or completion claim |
| Safari/export | Preview → local build → Safari / Export | Retained; copy states supported output only, no publication or universal font/export claim |
| App Settings | Native Settings → seven destinations | Retained; shared header now visibly states preference scope |

First review: checked existing Design Essentials, page actions, connected-flow
copy, Quick Open and component navigation before adding shortcuts. Rejected
duplicate editors/actions. Unchanged Site Settings Apply remains a validated
no-op dismissal; destructive and recovery confirmations remain intact.

## Pass 2 — language, then source review

Small AuthoringLanguage presentation vocabulary in InsertionModel feeds existing
Layout/Design/connected-flow/typography-spacing controls and shared provenance:

| Technical concept | User-facing wording |
| --- | --- |
| Padding / gap | Inner spacing / Space between items; navigation uses Space between links |
| Fixed / fill / hug sizing | Exact size / Fill available space / Fit content |
| Fluid | Smooth scaling; changes gradually as the screen gets wider |
| Breakpoint | Screen size; Desktop/Tablet/Mobile identities and ranges unchanged |
| Preflight action | Check Website |
| Authored / inherited source | Set here / Uses Desktop / Uses component default / Uses website default |

Sizing names apply only to sizing, not Image Fit/Fill modes. Metadata winner
labels use the existing typed source rather than parsing or changing raw values.
Form field metadata and geometry/spacing presentation retain mixed/unavailable
states. Technical search aliases remain supported alongside the new terms.
Stable serialized strings and diagnostic failure categories are not renamed.
Stale geometry drafts explain that nothing changed and Escape cancels; spacing
validation includes the valid range and recovery. Output limitations remain
output findings, not claims that a document is broken.

Second review: caught and corrected raw sizing names in provenance, technical
terms in adjacent scaling help, component AX-help inconsistencies, old human-
label test expectations and a fluid-target test helper derived from raw names.
Assertions still require exact values, source identity, neutral cancellation and
history/selection preservation; only presentation expectations were updated.

## Pass 3 — hierarchy, then source review

Uses the existing flat Inspector groups and Settings card/header system. The
shared Settings header's previously unused scope is now visible and included in
its accessible label. Appearance/Canvas/Defaults/Updates/Support/Advanced identify
app-local scope; Accessibility truthfully uses macOS settings. Site & Page
Settings identifies saved project content separately. Updates explains why
installation is unavailable without enabling a feed/installer or changing trust.

Retained native materials, palette, empty-state centering, five navigator and
five Inspector destinations, adaptive viewport toolbar, bounded pane allocation,
Settings fixed geometry, scrolling, keyboard shortcuts and window lifecycle.
Third review: no new panel/card system, tab, theme or branding was added. Longer
help/scope rows allow vertical growth rather than shrinking text. Original-size,
compact, increased-text and dark/light visual review is still UNPERFORMED.

## Pass 4 — end-to-end source re-walk

Re-walked New/Open/recovery, Pages, structural insertion, inline text and
formatting, Assets, formatting reuse, independent chrome copy, width/comparison,
component edit/return, metadata/icons/links, Save/reopen, Preview/export and every
Settings destination. Source-only findings:

- New common formatting placement still calls the same registry-facing methods;
  no canonical writes were added in views, and text editing/IME clean gates stay.
- Mixed selection never borrows a primary value; compatible/skipped counts and
  unavailable reasons remain exposed. Copy Appearance stays distinct from Copy
  Text Style; independent page copies stay distinct from linked components.
- Scope/provenance changes only presentation. Base sizing, screen-size overrides
  and Smooth scaling still resolve through the existing winner rules.
- Escape/cancel, no-op Apply, native Save, reopen, resource ownership, prepared
  export identity and output-blocker semantics are unchanged.
- No owner Aurora package, recovery data, native gradient, installed application,
  coordinator/artwork files or accepted canvas composition was changed.

Fourth review: removed the test helper's obsolete formatting-disclosure detour,
kept common actions visible and details secondary, and updated exact native menu
locators rather than adding permissive old/new-label fallbacks. No new debug
logging, automation hooks, output capability, promise of bundled fonts or general
browser certification was introduced.

## Initial regression source — ALL UNRUN

New exact selectors:

- SiteForgeTests/AppMetadataTests/testPlainAuthoringVocabularyPreservesCanonicalKeysAndSizingValues
- SiteForgeTests/AppMetadataTests/testPlainInspectorDiscoveryRetainsTechnicalSearchAliasesAndMixedScope
- SiteForgeUITests/SiteForgeLaunchTests/testFormattingCommandsRemainVisibleAcrossInspectorDestinationsWithoutToolsDisclosureJourney

Initially two model methods and one native journey added, zero executed. Existing affected
source expectations in AppMetadata/InsertionModel/CanvasViewport/TransformModel
and native responsive, sizing, component and Site Settings journeys were adjusted
to the new human labels. Existing behavioral assertions remain. No build, parser,
lint, check script, test runner or verification has validated this later package.

## Frozen earlier receipt is separate

See SF-LOCAL-BUILDER-007-011-FOCUSED-ACCEPTANCE.md: six distinct managed-title
code methods and one native/Safari journey passed, final run3/3, UI205.263s.
Fifteen originals were inspected at measured1440/430/320CSS widths, scale1.
That receipt predates these012 source edits and does not prove this tree builds.
The preexisting320navigation exhaustion and older-browser/custom-fluid-type/
cross-engine certification limits remain explicit. No new012 screenshots exist.

## Remaining acceptance / next action

Keep012 IN PROGRESS. Do not automatically run acceptance, another workflow,
tests/build/check scripts, UI/browser review, full verification or Git operations.
When separately authorized: compile, run only affected exact selectors, inspect
normal/compact/increased-text originals against available references, resolve any
real failures, then perform the required full gate before claiming completion.

## Continuation — component, recovery, style and responsive discovery

SOURCE ONLY, UNVERIFIED. The initial four passes did not cover every visible
component/recovery/style string. This continuation implements those remaining
surfaces rather than treating the earlier vocabulary work as whole-app coverage.
Supporting bounded SF-0901-003, SF-0902-003, SF-0903-003, SF-0905-004,
SF-0510-003 and SF-0308-004 were read alongside the existing012 requirements.
OD-018/019 are still open; no supplied contents, migration, retargeting or guessed
source repair is added. No command/state/store/schema architecture changed.

### Before/after wording and actual scope

| Before | Source implementation after continuation | Scope preserved |
| --- | --- | --- |
| Edit Definition / Return to Instance / Detach Instance | Edit original component / Back to this copy / Make independent | Same existing navigation/return/detach commands; original edits update linked copies, independent copies do not stay linked |
| Reset Override on a valid component value | Use original value, with removal/recovery help | Removes just that copy's value; an unavailable original is not repaired |
| Reset All Component Overrides / Reset All Visibility Overrides | Reset copy changes (N) / Reset visibility changes (N) | Counts existing custom values; filtered-out values remain in reset scope; visibility-only does not reset other properties |
| Retained Override Recovery / Reset Retained Override | Custom values needing attention / Remove custom value… | Existing identity-captured confirmation and exact Undo; removing custom data is not a restore operation |
| Reset Missing Value/Override/Action | Remove custom text/visibility/destination | Original reference and other values remain; recover with Undo/original project or explicitly remove the affected custom value |
| Inherited fallback: N roots / Edit Definition Fallback | Default contents: N top-level items / Edit default contents | Original-owned existing child order only; custom contents per copy remain unavailable |
| Destination missing — choose replacement or Reset Override | Choose an available destination or original value if available; deleted pages are not restored | Existing real destination editor and guards, no conflict remapping by label |
| Snapshot: … RGBA8 solid/opacity only | Color/opacity sample, Create Color Style, concise limit/help | Existing solid-only reusable-style capture/create/update/link semantics; not009's full-family transfer |
| Geometry/Layout/Visibility counts | Custom size/position/layout/visibility: N objects | Counts objects with screen-size custom values; scaling counts ranges; zero is not a visual check |
| Reset screen Overrides / Reset Visibility Override | Use inherited size and position / Use Desktop visibility | Remove only current-screen properties; geometry reveals Smooth scaling where present, otherwise Desktop; parent visibility can still hide a child |
| Convert and Remove Dimension Overrides | Convert to automatic sizing | Same explicit confirmation, eligible descendants, Width/Height customization/range removal and exact inverse; not a preview-only change |
| Authored page navigation | Website page navigation | Same visitor links and accessibility hierarchy, no altered authored labels |

The earlier012 scaling announcement used “saved” immediately after a transaction.
It now says “applied”; only the existing document lifecycle owns Saved status.
The geometry reset announcement also no longer incorrectly promises Desktop when
a Smooth scaling range is the next winning source.

### Surface coverage and second source walk

| Surface inspected | Actual source changes / review result | Deliberately retained term and explanation |
| --- | --- | --- |
| Components navigator, native Component menu, Design/Content Inspector, return | Same original-edit action now sits in the shared component Inspector, with the existing AX ID. Content → Design → edit-original detour becomes Content → edit-original. Return retains captured exact-copy identity and ordered selection. | Component remains the product concept; original vs linked copy vs independent copy is explained once in the shared Inspector. |
| Property search and empty/mixed/unavailable states | Plain-language aliases added alongside authored/override/inherited/fallback. Empty search points to unfiltered recovery; conflict counts remain outside filtered results. Labels/help preserve the applicable scope. | Technical aliases remain searchable; user-authored names and values are not translated. |
| One-value, all-value and visibility-only reset | Healthy actions say Use original value; bulk actions name scope/count. Existing enabled predicates, confirmation conditions and registry operations are unchanged. | Stable property IDs, command names and diagnostic namespaces remain machine contracts. |
| Missing original/property/image/destination recovery, dependency inspection | Explains custom intent is kept, what is unavailable, and Undo/original-project/remove choices. Dependency findings use a presentation property, not renamed raw values. Existing source navigation and Content recovery remain the only paths. | Color token means an existing shared color reference; missing references are not silently replaced. Stable technical descriptions remain optional help. |
| Fallback-only contents, original contents editing | Default contents/top-level items wording in visible labels, values, empty states and help. Existing contents source action remains direct; no supplied-content UI is fabricated. | “Slot” remains in the heading/name help as a named default-contents property; no per-copy custom contents capability is implied. |
| Reusable styles: create/update/reuse/unlink | Color/opacity sample is named distinctly from Copy Appearance/Text Style. Limits are one short helper plus native help. Update confirmation, affected uses, link order, protected None/tokens and deletion guards are retained. Row buttons stay compact to avoid new width pressure. | Hexadecimal color is a deterministic editable representation; RGBA/channel precision remains implementation data, not the main explanation. |
|009 formatting copy/paste | Existing richer bundle, resource validation, skipped/mixed status and atomic registry remain unchanged; visible Reuse Formatting is the route for full-family transfer. | Text Style/Appearance are separate supported families, not a promise of universal exported output. |
| Responsive comparison/reset/conversion | Counts and zero meaning agree in visible cards/AX values. Customization reset names the next source. Conversion still requires explicit confirmation and names the properties/objects it changes. Long spacing labels move above fields; Smooth scaling header/picker stack using existing spacing tokens. | Aspect ratio, CSS pixels and Desktop/Tablet/Mobile remain useful terms; no new screen-size identities or automatic canonical repositioning are created. |

Second independent source walk revisited Components → original → exact copy;
missing property/image/destination; reusable-style capture/create/update/reuse;
full formatting transfer; and responsive review/reset/conversion. It found and
corrected the Content-to-Design original-edit detour, a stale empty-search
explanation, residual raw dependency labels, misleading immediate “saved” wording,
and long-label pressure in existing field rows. No parallel editor/action registry
was introduced. Existing focus/draft/IME and stale-identity guards, confirmed
recovery, history/resource tests and preservation of missing intent stay intact.
This is a source-derived action-path improvement, not a measured click/time or
visual result. No app, owner document, installed build or recovery data was opened.

### Additional UNRUN coverage and exact limits

Three additional code methods were added:

- SiteForgeTests/AppMetadataTests/testPlainComponentRecoveryStyleSampleAndReviewCountsNameTheirLimits
- SiteForgeTests/CommandKernelTests/testPlainComponentDiscoveryFindsCopyOriginalAndDefaultContentsWithoutMutation
- SiteForgeTests/CommandKernelTests/testPlainRecoveryRemovalPreservesConfirmationScopeIdentityAndExactUndo

The existing new012 native journey was extended through real Content → original
→ exact-copy return, retaining its selection/frame assertions. Existing native
component recovery sheet title, singular count, destructive action, menu and
automatic-sizing confirmation locators now use exact new labels. No old/new
label fallback was added. Existing stale/cancel/duplicate/unconfirmed recovery,
style capture limits, exact inverse, persistence/resource and full formatting
tests remain present and unweakened.

Total012 added source coverage is now **5 code methods + 1 native journey**, all
UNRUN. No compilation/check/lint/parser/script/test/collector/visual/performance
or verification executed. No new screenshots exist. Prior title6+1,70/70 and
eight-native receipts predate these edits and do not accept this tree. Keep012
IN PROGRESS and all modules Partial; await the coordinator's separately authorized
consolidated acceptance prompt. No automatic execution, next feature, commit,
push, installation, signing, schedule or owner-data change is authorized.
