# Codex Continuation Handoff

## Authoritative checkpoint — 2026-10-07

The bounded batch `SF-AUTHORING-075`–`105` (excluding `SF-AUTHORING-106`),
`SF-AUTHORING-107`, and `SF-PRODUCT-UI-005/006` is integrated. The
authoritative `./sf verify` passed every repository check and all 640 tests:
542 unit/integration plus the complete 98-journey UI target. The shared live
native text-control/focus correction also passed its exact focused 2/2 rerun.
After this checkpoint, the earliest dependency-ready product slice is
`SF-AUTHORING-106` using approved OD-016. Do not infer completion of explicitly
deferred normative scope from this bounded batch.

The source-only notes below are historical and no longer describe current test
execution status for the bounded slices above.

## Source-only continuation under owner testing pause

SF-AUTHORING-107 adds one strict `com.siteforge.authored-objects.v1`
pasteboard envelope and native Cut/Copy/Paste/Paste in Place/Duplicate routes.
The central clipboard registry normalizes selected roots, captures bounded
subtree/image/token closure, validates before Cut, remaps every destination
node/property and supported dependency identity, stages bytes through the
existing lifecycle rollback boundary, and emits one existing batch command.
Cross-project component closure is intentionally rejected. Model and actual-app
test source are unrun. Preserve this implementation and next implement
SF-AUTHORING-106 from approved OD-016: Blank Site plus one local neutral Starter
Site with exactly Home/About, semantic Header/Main/Footer, system typography,
no remote assets, explicit template provenance, and editable/removable copy.

SF-AUTHORING-105 adds path-free Recent Projects to the launch card. The new
app-local store retains only display name, stable recent ID, and the SHA-256
lookup key for the existing security-scoped bookmark owner. Reopen, stale
repair, coordination, package validation, recovery, and adoption remain in the
normal lifecycle. New source tests are unrun. OD-016 is now approved; after the
connected SF-AUTHORING-107 clipboard source, the next implementation slice is
SF-AUTHORING-106 local Starter Site creation. Use
`docs/evidence/SF-SOURCE-COMPLETENESS-AUDIT.md` as the ordered gap map and do
not infer full source completion from the large accumulated UI surface.

SF-PRODUCT-UI-006 replaces the launch hammer glyph with the approved packaged
AppIcon and establishes a bounded native toolbar hierarchy: Select, Frame,
Text, Image, and Component are persistent; Section, Stack, Grid, Button, Link,
and Form remain available in More Tools and the established Insert commands.
No command or insertion model was duplicated. Updated source tests are unrun.
Recent-project navigation was subsequently source-connected by SF-AUTHORING-105;
the current next slice is the approved SF-AUTHORING-106 Starter Site workflow.

SF-AUTHORING-104 adds a native Support settings tab with build/channel
provenance, explicit installed-distribution update limits, the existing
recovery contract, and cancellable redacted report generation/copy/export.
The report is controlled metadata only and never reads document content or
paths. New source tests are unrun. Continue the next exact Settings/update/
recovery requirement without adding an unsigned updater, collecting project
content, or duplicating lifecycle recovery. Plugin trust/distribution remains
an owner-decision boundary if a future slice requires enabling third-party
code.

SF-AUTHORING-103 adds isolated multi-page local Preview navigation over the
existing stable Link target and canvas scene systems. Preview owns page/history
state, Back/Forward, page selection, and missing-target recovery without
changing editor scene or canonical content. External targets remain non-
executing and host-only in status. New source tests are unrun. Continue the
next exact interaction/output gap without duplicating link targets, page
routes, scene preparation, or static navigation.

SF-AUTHORING-102 adds one canonical monotonic fluid-value model for supported
width/height, typography size/line height, and container padding/gap. It uses
the established responsive cascade, atomic property commands, immutable canvas
preparation, comparison, and closed static output. Explicit Tablet/Mobile
overrides win; removing fluid intent reveals the untouched fixed value. New
model/output/UI tests are unrun. Continue the next exact uncovered responsive
requirement without adding a parallel breakpoint or layout resolver.

SF-AUTHORING-101 adds a native responsive comparison sheet driven exclusively
by the established Desktop/Tablet/Mobile geometry, container-layout, and
visibility resolvers. It reviews the selected objects or active page and
switches only scene-local viewport preset; no document/history/package state is
introduced. New model/UI tests are unrun. Pages/routes and internal PageID/
Section navigation targets are already source-complete; continue the next
genuinely uncovered responsive or navigation requirement without duplicating
their command, resolver, Preview, or static-output paths.

SF-AUTHORING-100 adds native component-definition rename. The existing central
component registry updates a stable definition plus linked instance display
names atomically; IDs, overrides, geometry, ordering, persistence, and exact
history remain intact. New model/UI tests are unrun. Assets organization,
replacement, usage filtering, portable static references, component creation,
linked insertion, edit-main, text/visibility properties, detach/delete, search,
and Quick Open were already source-complete and were not duplicated. Continue
the next exact uncovered Assets/Components requirement, not a second asset
store or component graph.

SF-AUTHORING-099 adds Heading as a semantic Text template in Elements and the
native Insert menu. It seeds deterministic geometry/content/typography and an
authored `<h2>` property through the existing insertion command; all later
editing and output stay on established systems. New model/UI tests are unrun.
Continue the next exact uncovered Elements/site-structure requirement without
inventing a node kind, automatic heading outline, or alternate renderer.

SF-AUTHORING-098 adds one canonical general-accessibility metadata namespace
for applicable Frame, Text, Section, Stack, Grid, Button, and Link nodes. The
Accessibility Inspector edits name/help through the existing identity-gated
transaction path; the immutable canvas accessibility snapshot and safe static
HTML projection consume the same authored values. Role remains derived from
the typed semantic-element registry. Image and Form remain on their dedicated
schemas. New model/output/UI tests are unrun. Next continue the highest-value
uncovered Elements/site-structure slice without adding a competing role, alt-
text, or Form schema and without claiming this slice verified.

SF-AUTHORING-097 adds directional native-canvas marquee selection through the
existing immutable scene and central selection registry. Left-to-right contains
visible clipped object geometry; right-to-left intersects; Shift/Command add or
toggle in stable paint order. The marquee never enters document data, history,
packages, renderer content, Preview, or static output. Model/UI test source is
unrun. Next reconcile the highest-value uncovered Inspector property slice;
do not duplicate established fills, typography, box style, responsive geometry,
structural layout, or Form field registries.

SF-AUTHORING-096 adds a canonical read-only Form Inspector presentation shared
by Content and Accessibility. It exposes accessible names, roles, requirement,
help, options, validation bounds, and provenance; mixed values stay Mixed until
the author resolves every shared draft. Form accessibility reuses the existing
scene-local validator and keeps Submit disabled/unconfigured. New model/UI test
source is unrun. Do not add a submission destination or visitor-value storage
without an approved specification/owner decision. The next safe action is the
deferred focused Forms gate and original-resolution visual/accessibility review,
not another competing Form schema.

SF-AUTHORING-091–095 add the remaining supported Form field templates through
the existing canonical Text/form-field path. Select options have deterministic
stable IDs; Submit is intentionally inert in safe output until a destination
is approved. The shared model/output/UI test source is unrun. Next inspect the
remaining SF-1006 authoring experience (field configuration, local validation,
accessibility semantics, and submit boundary) without duplicating the existing
SF-AUTHORING-036/037 registries.

SF-AUTHORING-090 adds Form-only Input insertion via the existing Text/form
field transaction, Elements category, and native Insert menu. The model and
actual-app test source is unrun. Continue with the next form-control slice;
do not claim Form output or visual acceptance before the deferred gate.

SF-AUTHORING-086–089 activate Divider and semantic Header/Navigation/Footer
templates through existing Frame/Section commands. Added model/UI test source
is unrun. Continue the remaining required Elements and Inspector/site-building
source without claiming visual or output parity before the later gate.

SF-AUTHORING-085 adds direct linked-instance insertion from Quick Open
definition results. Its new source assertions, including the prior reveal-
status correction, were not executed. Continue to the next dependency-ready
product slice without building, testing, committing, or pushing.

SF-AUTHORING-084 adds direct Quick Open Image insertion from a current-project
asset result. It is source implemented, not tested or committed. The owner has
paused all builds, tests, UI automation, verification, commits, and pushes while
the remaining specification-backed product source is implemented. Continue
from the existing dirty tree; do not describe 075–084 as verified.

## 2026-10-04 external XCTest automation blocker

The existing ten-slice dirty tree remains uncommitted and unpushed. Repository
checks and 513/513 non-UI tests passed in the interrupted `./sf verify`. The
macOS console locked at 12:58:32 EDT during the UI target, and app activation
then failed. The exact new Quick Open insertion journey was attempted after
unlock; `SiteForgeUITests-Runner` timed out in
`XCUIInitializeForUITesting` before SiteForge launched. No SiteForge test
process remains. The completed built-app AppIcon test passed 1/1, and
`scripts/check-app-icon.py` passed. Resume only when macOS XCTest automation
is available; run the exact new UI journeys, then an authoritative full gate,
review visuals and diff, reconcile factual status, commit, and push. Begin the
owner-requested two further ten-slice batches only after this checkpoint is
clean and pushed. Do not mistake the interrupted run for a green gate.

## Ten-slice source cycle awaiting one local gate (2026-09-30)

SF-PRODUCT-UI-005 plus SF-AUTHORING-075–083 are source-complete in the dirty
working tree, not verified. The final five slices provide New Page from Quick
Open, Components search, Assets usage filtering, and Quick Open asset/component
reveal. The pre-existing Assets name search was not duplicated. The approved
`SF-0201-009` wording is synchronized from Markdown to the editable DOCX;
rendered publication pages 40–42 were visually checked. See
`docs/evidence/SF-AUTHORING-079-083-QUICK-OPEN-DISCOVERY.md` and the prior
half-batch note below. Owner direction: run the complete local suite once now,
repair failures with exact failed selectors/new regressions only, reconcile
docs with actual results, review diff, then make one local commit and push
origin/main if green. No PR, release, signing, notarization, or settings change.

## Current source-only half-batch (2026-09-30)

SF-PRODUCT-UI-005 and SF-AUTHORING-075–078 are implemented in the dirty local
tree but not verified. The gradient AppIcon source is
`docs/design-assets/siteforge-app-icon-sf-gradient-approved-v1.png`; the
offline packager `scripts/package_app_icon.py` removes only its exterior matte
and writes ten static catalog variants. Quick Open adds closed insertion
actions for basic, structural, site-control, and image workflows and routes
through existing active-scene commands. New policy/UI/icon test source is
unrun. The owner forbids tests, UI automation, full verification, commits,
pushes, and GitHub during this half-batch. Next action when authorized: run
only affected AppMetadata/SelectionModel selectors and the new Quick Open
insertion journey, inspect original-resolution icon/app screenshots, repair
any issue, synchronize the editable specification publication copy with the
approved `SF-0201-009` Markdown wording, then run the applicable milestone gate. Do not describe these
source changes as verified or modify project content from Quick Open itself.

## Hosted checkpoint correction (2026-09-30)

Commit `73c653a` was pushed, but Actions run `36669009531` hit its 60-minute
job cap while UI tests were still progressing. Its log identified two
offscreen/not-hittable pointer interactions on the 1024-point hosted display.
The exact Quick Open and snapping/guide selectors now pass locally 2/2 after
the test uses live selected-state and scroll-to-reveal assertions. The checked-
in CI job has a 90-minute cap; no production minimum-window reduction or
individual XCTest timeout increase was made in that first correction. Its
hosted result is recorded below; do not claim a green gate until one actually
completes successfully.

That next run (`36674126611`) completed 504/504 non-UI and 78/81 UI. Its
artifact proved the Inspector's last control was trapped behind the Dock on
the 1024×768 hosted display; the large fixture displayed a real workspace but
its first AX query exceeded the ordinary five-second bound; and a text-field
reveal helper chose the wrong scroll direction at the lower edge. The product
Inspector gained bottom scroll clearance; only the 10,000-page fixture gets
a 30-second readiness bound while retaining the exact window/shell assertion.
The three exact UI selectors passed locally 3/3. Push this correction and
inspect the next hosted result before starting another slice.

The next run (`36680840818`) passed 504/504 non-UI and 80/81 UI. The only
remaining hosted failure was an AX-present but offscreen New Color Token
button in the text-foreground journey; its click did not reveal the form.
The corrected journey requires a real native-scroll reveal, a hittable button,
and an actual hittable draft field. It passed focused 1/1 locally. Push this
single-selector correction and wait for a genuinely green hosted gate.

## Current ten-slice local checkpoint (2026-09-30)

SF-AUTHORING-065–074 deliver application Settings reset plus native Pages,
Layers, Elements, and Quick Open search under bounded `SF-0205-002/003/004/006/008`
and `SF-0206-002/003/004/006/008`. Quick Open offers current-document pages,
authorized current-page Layers, a closed View-action set, scene-local recents,
and native All/Pages/Layers/Actions scopes. Filter and query state never enters
project packages or renderer content. The one full batch run executed 504/504
unit/integration passes and 79/81 UI passes. Its two test-contract failures
were corrected and passed exact focused reruns: keyboard focus traverses the
new Pages search stop; the Layer Type picker is queried in its own menu and
includes the structural Root among Frame-kind rows. Original-resolution
Elements, Layers, Quick Open, and Settings states were reviewed. The owner
directed no second broad run after exact focused repairs; do not describe
the original full run as green. See `docs/evidence/SF-AUTHORING-068-ELEMENTS-SEARCH.md`
through `docs/evidence/SF-AUTHORING-074-QUICK-OPEN-SCOPES.md`.

The combined checkpoint was committed as `73c653a` and pushed. The current
next action is the hosted correction described above; do not start a new
feature before its hosted result is known. No publication or release work is
authorized.

## Current Layers search checkpoint

SF-AUTHORING-067 filters only the current Layers navigator targets by name
under bounded `SF-0205-002/003/004/006/008` and existing `SF-0402-002/006`.
Return selects through the established Layers command; Escape and Clear Search
leave canonical content untouched. The new policy and real-app journeys plus
the existing multi-selection keyboard journey passed focused 3/3. Three
original-resolution states were reviewed; see
`docs/evidence/SF-AUTHORING-067-LAYERS-SEARCH.md`. Preserve the preceding
owner-review tree. The later batch verification result is recorded above.

## Current Pages search checkpoint

SF-AUTHORING-066 adds a scene-local native Pages search by page name or route
under bounded `SF-0205-002/003/004/006/008`. Return opens the first result;
Escape and Clear Search restore the full list; a no-result state can reveal the
selected page. The new model and native UI journeys and the affected existing
Pages keyboard-navigation journey passed focused 3/3. Three original-resolution
window states were reviewed. See `docs/evidence/SF-AUTHORING-066-PAGES-SEARCH.md`.
The later batch verification result is recorded above; no module-complete
claim is made.

## Current application preference-group checkpoint

SF-AUTHORING-065 adds an explicit native Settings Reset tab for the existing
application-only Appearance and new-workspace Grid records (`SF-0206-002/003/004/006/008`
bounded). It stages one exact pair, rejects dirty/managed/stale state, resets
both with rollback on storage failure, and restores previous bytes within the
session. No project schema, document history, renderer, or live Grid state is
changed. Five exact model tests, the fresh-process group journey, and two
existing Settings journeys passed focused 8/8; five
original-resolution states were reviewed. See
`docs/evidence/SF-AUTHORING-065-APPLICATION-RESET.md`. Preserve the earlier
uncommitted SF-AUTHORING-063, SF-PRODUCT-UI-004, and SF-AUTHORING-064 work.
No new full gate, commit, push, or hosted result is claimed. Project-owned
Settings still require a concrete spec-backed preference choice; none was
invented in this application-only slice.

## Current focused Canvas Settings checkpoint

SF-AUTHORING-064 adds a strictly decoded application-only default for Grid in
new workspaces under bounded `SF-0206-002/003/004/006/008` and `SF-0407-006`.
Existing scenes retain their independent toolbar/View-menu state; no project
content, renderer output, or recovery package stores the preference. Three
exact model tests and the new Canvas Settings, existing Appearance Settings,
and existing grid/artboard actual-app journeys passed focused 6/6. Five new
original-resolution states were reviewed. See
`docs/evidence/SF-AUTHORING-064-CANVAS-SETTINGS.md`. Preserve all earlier
uncommitted SF-AUTHORING-063/SF-PRODUCT-UI-004 work. No new full gate, commit,
push, hosted result, or release is claimed. Remaining module work includes
broader project preferences, scale/accessibility matrices, and release QA.

## Owner-approved local visual add-on

SF-PRODUCT-UI-004 packages the approved original SF AppIcon and refines native
frosted navigator/Inspector materials under `SF-0201-009`. Three exact unit
and three affected actual-app selectors passed; seven shell states and the
built icon were visually reviewed. The XCTest Dock capture remained generic
despite correct app-bundle icon keys/files, so confirm fresh Finder/Dock display
before claiming that particular surface. See
`docs/evidence/SF-PRODUCT-UI-004-BRANDING-SHELL.md`. Do not rerun the already
passed SF-AUTHORING-063 full gate merely for this add-on, and do not commit or
push this owner-review tree.

## Execution policy — reset 2026-09-27

Use the specification, editable publication copy, ADRs, OPEN_DECISIONS,
IMPLEMENTATION_STATUS, CODEX_QUEUE, and AGENTS.md as the authority hierarchy.
Every prompt is a bounded user-visible vertical slice with focused tests before
its local commit. `SF-AUTHORING-063` was Development Prompt 10 of 10. Its
post-repair `./sf verify` passed 486 unit/integration and 70 UI tests on
2026-09-29. The owner requested the verified tree remain uncommitted for review;
do not push or publish. Normative modules remain Partial unless fully proven.

## Current asset-organization work

SF-AUTHORING-063 extends the existing ImageAsset and Assets pane with optional
schema-eleven project-local folder/tags/favorite metadata. Reuse
AssetOrganizationCommandRegistry and the existing resource/history path;
never derive paths or alter image bytes. Four model/migration/static-reference
tests and one native UI journey passed. Five original-resolution states were
reviewed. The full-gate unit/integration target passed 486/486; reconciled
historical tests passed focused 10/10 and affected Inspector journeys 3/3.
An earlier managed runner could not start the UI target because macOS denied
testmanagerd with sandbox error 159. A later direct run found the two
Mobile-preset failures below. The final post-repair full gate passed 556/556;
no commit or push has been made. See
`docs/evidence/SF-AUTHORING-063-ASSET-ORGANIZATION.md`.

A later direct UI target ran 70 tests (68 passed, two failed at Mobile preset
selection adoption). The clipped-selection correction now passes its focused
model regression and both affected native UI journeys (2/2), with original-
resolution artboard evidence reviewed. See
`docs/evidence/SF-RESPONSIVE-SELECTION-RECOVERY.md`. The subsequent full local
gate passed; retain the recovery evidence and leave this tree uncommitted for
owner review.

## Current component-visibility work

SF-AUTHORING-062 adds strict `component.exposedVisibility.v1.*` definition-child
metadata and `component.instance.v1.visibility.*` instance overrides. Reuse
`ComponentCommandRegistry`, `ComponentGraphResolver`, and the existing Content
Inspector path; do not add a parallel component state or hidden virtual layer.
Instance override wins over definition default, which wins over the child’s
canonical hidden state when no binding exists. The derived `hidden` property
feeds layout, native/Preview rendering, accessibility, and closed static CSS.
See `docs/evidence/SF-AUTHORING-062-COMPONENT-VISIBILITY.md` for focused results.
That prior prompt-ten checkpoint has since passed its local full gate; the
current bounded post-checkpoint slice is SF-AUTHORING-064 above.

## Current image-fill work

SF-AUTHORING-061 adds one optional local AssetID image fill for Frame/Section
under `style.fill.image.v1.*`, reusing the existing resource store, typed
property commands, image decoder and native Design Inspector. The image is
painted above authored solid/gradient layers, inside the shared corner clip;
opacity applies to the composite once. Image-node and image-fill references
both count for safe asset deletion. Exact model, raster, and actual-app
Inspector/reopen selectors passed 3/3; four retained native screenshots were
reviewed. See `docs/evidence/SF-AUTHORING-061-FRAME-SECTION-IMAGE-FILL.md`. Do not
claim broad SF-0508 or SF-0801/0802 completion or push before Prompt 10.

## Prior text-foreground checkpoint

SF-AUTHORING-060 adds optional normalized whole-object foreground channels to
the existing typography namespace for Text/Button/Link. The existing token
target registry binds local Color Tokens with literal fallback; omitted values
retain automatic color. The native Design Inspector, committed CATextLayer,
inline editor, and closed static output share resolution. Focused model,
render, and actual-app evidence is in
`docs/evidence/SF-AUTHORING-060-TEXT-FOREGROUND.md`. Do not infer rich-text
spans, responsive typography color, themes, or broad SF-0507/0508/0509
completion. Prompt 8 is next; no broad gate or push before Prompt 10.

## Prior appearance-token checkpoint

SF-AUTHORING-059 migrates schema-nine fill-only token bindings into a
target-keyed schema-ten namespace. The same ColorTokenID collection and
literal-backed transaction path now resolve authored Border and Outer Shadow
colors for the canvas and closed Frame/Section static output. The native Design
Inspector target chooser binds and unbinds each target. See
`docs/evidence/SF-AUTHORING-059-APPEARANCE-TOKENS.md`; no full gate or push is
permitted before Prompt 10. Do not claim themes, aliases, arbitrary style
bindings, or full SF-0509 acceptance.

## Prior sizing checkpoint

SF-AUTHORING-058 adds strict base-only Frame/Image min/max and aspect
properties under `layout.sizing.v1.*`. Its central command adjusts fixed
geometry atomically and the Layout Inspector retains drafts locally. Desktop
numeric and pointer resize use the same clamp policy; closed static output
projects validated declarations. Four focused selectors passed, with three
native window captures reviewed; see
`docs/evidence/SF-AUTHORING-058-SIZING-CONSTRAINTS.md`. Do not claim
responsive/intrinsic sizing or full SF-0505 acceptance from this slice.

## Prior local color-token checkpoint

SF-AUTHORING-057 adds schema-9 project-local solid RGBA tokens and a stable
solid-fill binding property. The token registry and existing DocumentSession
are the only canonical write path. A missing token preserves its literal fill;
unbind freezes the resolved color, and in-use deletion is rejected. Canvas,
Preview, and closed static Frame/Section output share token resolution. The
focused model/migration/static/UI selectors and limitations are recorded in
`docs/evidence/SF-AUTHORING-057-LOCAL-COLOR-TOKENS.md`. Do not claim full
SF-0509 theme/mode, alias, broad scale, or release acceptance from this slice.

## Current native outer-shadow checkpoint

SF-AUTHORING-056 keeps outer-shadow geometry/color in the established typed
`style.box.v1` model and adds `shadow.enabled` only for Frame/Section. Omitted
state resolves to enabled; explicit false preserves the complete shadow value
without rendering it. The identity-gated registry is the only write path, and
native canvas, Local Preview, and typed static CSS all consume the same
resolution. Do not introduce a separate shadow model or raw CSS pathway.

## Current native box-style checkpoint

SF-AUTHORING-055 extends the existing `style.box.v1` model only for Frame and
Section with uniform content padding and explicit content clipping. The central
registry remains the sole canonical write path; the document validator rejects
invalid or duplicate content-box keys. Structural child geometry uses authored
padding, the canvas applies ancestor clips consistently, and the static
projection emits only typed `padding` and `overflow: hidden` declarations.

Focused evidence passed on 2026-09-27:

- `TransformModelTests.testDesignBoxStyleContentPaddingAndClipAreTypedReversibleAndScoped`
- `CommandKernelTests.testMultiPageStaticBuildPlanProjectsClosedFrameBoxStyle`
- `SiteForgeLaunchTests.testDesignInspectorBorderRadiusShadowUndoRedoAccessibilityJourney`

The next dependency-ready slice is the earliest queue item after this local
checkpoint. Do not add per-edge padding, margin, per-corner radius, or raw CSS
without a separately bounded requirement and evidence.

SF-AUTHORING-054 reuses the existing versioned fill-layer model, native Design
Inspector, transactional registry, renderer compositor, package/recovery
paths, and accessibility journey. It adds a closed static Frame/Section fill
projection for solid and linear-gradient layers, including safe opacity and
stable interpolation ordering; no raw CSS or browser runtime is introduced.

The next focused selectors are
`CommandKernelTests.testMultiPageStaticBuildPlanProjectsClosedFrameAndSectionFillLayers`,
`TransformModelTests.testDesignFillLayerRegistryCommitsOrderedLayersWithExactHistoryAndPersistence`,
`CanvasRendererTests.testAuthoredFillLayerCompositorPreservesOrderDisabledLayersStopsAnglesAndOpacity`,
and `SiteForgeLaunchTests.testDesignInspectorOrderedFillLayersAccessibilityJourney`.
The first three passed 3/3 on 2026-09-27. The UI selector was attempted once
but XCTest timed out while enabling automation before the body ran; rerun it
only after the macOS automation service is healthy.

## Current static authored-box checkpoint

SF-AUTHORING-053 adds only the fixed `box-sizing: border-box` declaration to
valid typed static geometry. This retains canonical width/height as the outer
output box without adding authored CSS, a layout mode, browser work, file
generation, or publishing.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CanvasRendererTests.testStaticLayoutOutputUsesStableRoundingAndExplicitVisibilityOverrides`.

## Current static plan-integrity checkpoint

SF-AUTHORING-052 adds a deterministic SHA-256 digest to each immutable static
plan. Its input is a path-sorted, length-delimited in-memory file list, so no
source content is surfaced and no integrity file, writer call, canonical
mutation, browser mechanism, or publishing protocol is added.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testFormFieldsPreserveAtomicHistoryAndRemapSelectOptionsOnPageDuplicate`.

## Current static semantic-outline checkpoint

SF-AUTHORING-051 adds parent NodeID provenance to immutable static tree nodes
and emits a validated `semantic-outline.txt` plan artifact. It has no effect
on static HTML nesting, canonical state, resource bytes, browser behavior, or
output writing. Only closed semantic types and known parent identities enter
the artifact.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testMultiPageStaticBuildPlanUsesAuthoredSemanticElementResolution`.

## Current static semantic-resolution checkpoint

SF-AUTHORING-050 makes `CanonicalSemanticElement.resolved(for:)` the shared
typed semantic boundary for Inspector and immutable static output. It accepts
only the existing closed semantic vocabulary, preserves omitted/defaulted/
authored provenance, and never emits raw markup from canonical strings.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testMultiPageStaticBuildPlanUsesAuthoredSemanticElementResolution`.

## Current static asset-manifest checkpoint

SF-AUTHORING-049 adds a deterministic `assets.manifest.txt` planning artifact
only when an Image has a verified content-addressed reference. It exposes only
AssetID, safe output path, and validated dimensions; it never carries bytes,
original filenames, Finder paths, EXIF, a resource write, or browser work.
Invalid/missing entries are safely absent from the manifest and retain the
existing missing-resource markup state.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference`.

## Current static-image responsive-layout checkpoint

SF-AUTHORING-048 carries only validated `ImageAsset` dimensions into
`InternalStaticImage` and emits them as integer HTML sizing hints. The actual
Image frame and Tablet/Mobile visibility stay wholly within the existing typed
`StaticLayoutOutputEmitter` cascade; no intrinsic aspect-ratio rule, source
set, remote URL, resource write, transform, or browser execution is added.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference`.

## Current static-image presentation checkpoint

SF-AUTHORING-047 adds `StaticImageStyleOutputEmitter`. It maps only the typed
canonical Fit/Fill/Stretch enum and bounded focal point to a fixed
`object-fit`/`object-position` rule on the existing NodeID selector. The
projection is static plan metadata: it preserves the referenced original
resource and creates no crop, rendition, transform, browser path, or generated
resource write.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference`.

## Current static-image reference checkpoint

SF-AUTHORING-046 carries canonical Image metadata into the static tree through
`InternalStaticImage`. `MultiPageStaticBuildPlanner` accepts only existing
verified content-addressed export entries, mapping them to a safe `src`; a
missing or corrupt entry instead leaves an explicit missing-resource marker
while retaining the stable AssetID and escaped alt/decorative semantics. This
does not export bytes, use filesystem paths or remote URLs, or start a browser
image-loading path.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference`.

## Current static-typography checkpoint

SF-AUTHORING-045 makes canonical plain Text content visible in the immutable
static tree and escapes it only at the Safe HTML boundary. Its stylesheet
projection maps the closed typography model to size, weight, line-height,
tracking, alignment, and portable `system-ui` for the canonical System family.
Any other installed-family intent is preserved canonically but omitted from
static CSS rather than being emitted as an arbitrary CSS string. Component
text defaults/overrides are not mutated or flattened in this slice.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CanvasRendererTests.testStaticTypographyOutputEscapesTextAndUsesAllowlistedCanonicalValues`.

## Current static-layout plan checkpoint

SF-AUTHORING-044 makes the SF-AUTHORING-043 typed layout projection available
to `MultiPageStaticBuildPlanner` as a deterministic in-memory `styles.css`
file. The stylesheet is generated only from canonical document nodes using the
existing responsive resolver; it has no standalone state, file writer call,
HTML-shell link, browser runtime, raw CSS input, or publishing path.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CommandKernelTests.testMultiPageStaticBuildPlanIncludesTypedLayoutStylesheet`.

## Current static-layout checkpoint

SF-AUTHORING-043 adds `StaticLayoutOutputEmitter`, an immutable projection of
typed canonical base geometry, explicit Tablet/Mobile overrides, and
breakpoint visibility. It emits a fixed absolute-position CSS allowlist with
NodeID-derived selectors and canonical three-decimal rounding. Responsive
rules are emitted only for explicitly authored properties; base visibility
continues to cascade naturally until a breakpoint override is present. This
does not add raw CSS, browser execution, flex/grid/container-query authoring,
static-file export, or publishing.

No local test execution was performed under the owner-directed pause. The
next allowed focused selector is
`CanvasRendererTests.testStaticLayoutOutputUsesStableRoundingAndExplicitVisibilityOverrides`.

## Current static-navigation checkpoint

SF-AUTHORING-042 adds `StaticNavigationEmitter`, an immutable static-output
projection from the canonical navigator order. It includes only Home and
standard pages with an existing validated static route, derives a stable
PageID-backed link for each, emits escaped labels/hrefs, and applies
`aria-current=page` only to the output page being built. Not Found and
component-definition pages are intentionally absent. It is not a navigation
template, redirect, dynamic-routing, browser-runtime, static-file-export, or
publishing feature. Nested generated paths resolve relative links without
assuming a site-root router.

No tests were run under the owner-directed pause. The next allowed focused
selector is `CanvasRendererTests.testStaticNavigationProjectionPreservesPageOrderAndAccessibleCurrentState`.

## Current static-control checkpoint

SF-AUTHORING-041 adds immutable static-tree projection for existing canonical
Button and Link controls. `InternalDocumentRenderTreeCompiler` is the sole
output boundary: it accepts only `CanonicalLinkTarget` values that already pass
canonical validation, resolves internal Page/Section references only against
the current package route map, escapes output, and leaves missing targets
inert. Static Buttons are deliberately emitted as disabled `type=button`
controls: no browser action or submission behavior exists. Typed new-context
Links emit only `target=_blank` with `rel=noopener noreferrer`.

No local test execution was performed for this checkpoint under the current
owner-directed test pause. The focused compiler regression
`CanvasRendererTests.testStaticControlCompilerEscapesTypedRoutesAndKeepsMissingTargetsInert`
now covers escaped external/section routes, stable anchors, missing targets,
and inert button output; it must be run before any runtime or export work.

## Current checkpoint

SF-AUTHORING-038 adds fixed-breakpoint static CSS emission for canonical
geometry and visibility overrides. SF-AUTHORING-037 Local form-validation and
preview-state foundation v1 remains IN PROGRESS. `LocalFormValidationEngine` resolves only caller-owned,
non-Codable `FormVisitorValueSnapshot` input against canonical Form metadata.
Its results contain stable document/revision/form/field identities and failure
categories only; it has no command, history, package, autosave, recovery,
network, browser, or submission path. The Form Inspector presents its adopted
category-only empty-draft result without retaining input; focused model coverage
is 3/3. Do not make visitor values canonical. The next bounded Form task is
authored validation-rule configuration through the existing Inspector registry.

SF-AUTHORING-036 Accessible form authoring v1 remains IN PROGRESS. Form is now
an enabled Elements/Insert container and its Text children have native bounded
Content Inspector field controls. `FormInspectorCommandRegistry` is the sole
identity-gated canonical edit boundary; focused foundation plus current-slice
coverage is green (9/9). Actual-app UI evidence and all visitor/runtime
submission behavior remain deferred.

## Current Form boundary

- Form field metadata is valid only on Text nodes owned by a Form node.
- Static output permits only escaped text/email/textarea/checkbox/select and
  disabled unconfigured-submit controls; it has no runtime submission path.
- Page duplication remaps stable select-option IDs but keeps labels and values.
- The next bounded task is actual-app keyboard, pointer, and accessibility
  evidence for Form insertion and field editing. Keep visitor values,
  submission destinations, validation rules, anti-abuse, generated-site
  runtime, scale, and release acceptance out of scope.

## Earlier delivered boundary

- `WorkspaceShellState` owns a scene-local `LocalPreviewState` containing an
  immutable `CanvasPreviewSceneSnapshot` captured only by Preview or Refresh.
- Preview renders authored Frame, Text, fill and Image content without editor
  selection, grid, guides or insertion chrome. It never writes document or
  history state.
- The Preview toolbar and Command-Shift-P route to the same state; Refresh
  adopts only a matching newer render revision; Done/Escape closes and restores
  editor focus.
- The constrained-window reveal helper aligns the live target, while retaining
  the approved 1100-point production window width on narrow displays.

## Evidence and invariants

- `docs/evidence/SF-AUTHORING-025-LOCAL-PREVIEW.md` records scope and focused
  tests. The UI journey retains `SF-AUTHORING-025 local preview authored
  snapshot` in its result bundle.
- `CanvasRendererTests.testLocalPreviewStateFreezesRevisionAndRejectsStaleRefreshes`
  and `SiteForgeLaunchTests.testLocalPreviewRefreshesOnlyOnExplicitRequestJourney`
  are the focused Preview checks.
- Do not turn preview scene state into canonical document/history state or add
  browser runtime, generated HTML/CSS/JS, export, publishing, routes, remote
  content or CMS. SF-1203 semantic authoring begins as its own bounded slice.

## Deferred scope

SF-1201 and SF-1202 remain Partial outside this bounded local-preview surface:
runtime bundles, generated render trees, export/preview parity, large-project
performance certification, broad accessibility matrices and release acceptance
remain future work.
