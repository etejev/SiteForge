# Codex Continuation Handoff

## Execution policy — reset 2026-09-27

Use the specification, editable publication copy, ADRs, OPEN_DECISIONS,
IMPLEMENTATION_STATUS, CODEX_QUEUE, and AGENTS.md as the authority hierarchy.
Every prompt is a bounded user-visible vertical slice with focused tests before
its local commit. `SF-AUTHORING-059` is Development Prompt 6 of 10; Prompt 10
triggers the next full verification and hosted checkpoint. Until then do not
push or run broad gates. Normative modules remain Partial unless fully proven.

## Current appearance-token checkpoint

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
