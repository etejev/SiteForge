# SF-SOURCE-BATCH-20261027-05 — Practical installed typography

Current receipt: the listed new model methods and actual-app journey have passed
current-source affected acceptance. Final full verification passes:785 non-UI,
151 UI,0 failures,3 intentional owner-session skips; full-e7ee511e is the
authoritative939-method result. The bounded local slice is accepted.
The implementation-time UNRUN/owner-hold text below is historical and superseded
by approved local acceptance. Exact correction results and inspected screenshots
are indexed in [the integration receipt](SF-SOURCE-BATCH-20261027-10-INTEGRATION.md).
Normative modules remain Partial; no push or installation is authorized.

**IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.**

Queue IN PROGRESS; normative modules remain Partial. Static source/diff inspection
only. No tests, builds/build-for-testing, check/lint scripts, UI automation,
readiness/authentication work, app/browser acceptance launch or visual inspection.
No screenshots were captured; attachment names below are future test instructions.

## Bounded requirements and inspected behavior

- SF-0507-002/003/004/005/006: actual installed family/weight selection, explicit
  fallback, typed validation/history and native keyboard/accessibility actions.
- Supporting SF-0406-005/006: preserve plain text, role, caret/selection and existing
  editor/commit semantics; this does not implement rich-text/range formatting.
- Supporting SF-0805-003/004/006: installed metadata and missing-face recovery
  navigation only, not imported/versioned font assets or licensing/embedding.

Existing Heading/Text templates, Semantic HTML choices, installed-family search,
common installed weight intersection, four canonical weights, size/line-height/
tracking/alignment drafts, explicit fluid controls and paragraph wrapping were
already present. Prompt-4 effective typography/fluid navigation and stale-context
work are preserved, not counted as new here. ADR-0025 still governs one Core Text
resolution/measurement path shared by committed rendering and inline NSTextView.
Existing StaticTypographyOutputEmitter remains the output path.

## Concrete remaining gap and implementation

The installed chooser previously committed family alone. If the previous weight
was not installed for the chosen family, it deliberately retained that weight and
native resolution could select a nearest face. That existing intent/fallback
behavior remains available and is now clearly described, but there was no explicit
one-transaction installed family+upright weight choice.

### Canonical transaction

`SiteForge/TransformModel.swift`: new ephemeral
`TypographyEdit.fontFace(family:weight:)` validates the complete next style and
compiles the two existing `style.typography.v1.family/weight` properties into the
same atomic property batch. It preserves existing PropertyIDs, origins through
exact inverse, node/content/semantic identity, per-node size/line-height/tracking/
alignment, geometry, visibility and fluid records. Compatible selections apply
atomically; ordinary incompatible nodes are explicitly skipped through the
existing result. Invalid/stale/cancelled/unavailable input never commits a partial
font pair. Identical authored properties return existing no-change semantics.
No new serialized font record, history format, schema or migration.

### Native authoring

`SiteForge/WorkspaceShellView.swift`: installed family rows retain the existing
family-only action and add a native Weights menu containing only named upright
weights discovered for that family. Menus, labels/help, full accessible family
names and validation are real shipping controls. Long names stay one line with
full help/AX information; the weight action retains intrinsic width. The existing
off-main Core Text catalogue and virtualized/searchable list are reused. No font
download, registration, import or test-specific controls.

The chooser first honors the existing edit-commit boundary. Pending native edits
must complete or cancel; marked/invalid work is not silently discarded. It then
captures prompt-4's scene-only context/revision. Failed/stale choices preserve
the family draft and show bounded validation inside the popover; drafts are
removed only after success. Cancel/Escape dismisses the chooser without a font
command. A normal native focus-loss commit preceding opening is a separate edit,
not something chooser cancellation undoes. No native text Undo/clipboard/caret
or marked-text implementation was replaced.

`SiteForge/WorkspaceShellModel.swift`: paired choices still enter the central
typography registry; an optional captured context prevents a retained picker from
overwriting a later scene/revision. Typography also projects its existing semantic
role: Heading level, Paragraph, other element or Mixed. Choosing a font cannot
infer/rewrite heading level. Layout retains Fixed/Fill/Hug ownership; font metrics
may reflow automatic text without rewriting authored sizing intent. Mixed objects
retain their own roles/alignment rather than borrowing primary values.

### Renderer/output/persistence implications

No new text renderer or measurement formula. Immutable render snapshots consume
the committed family/weight via existing shared metrics; inline editor receives
the same CanvasTextLayout and attributed font. Static output emits the canonical
family with its system fallback, weight, spacing/alignment and pre-wrap rules.
Installed fonts are not packaged or assumed installed on a visitor's device.
Unknown authored family names remain recoverable intent with System fallback;
the typed family field is not restricted to the local catalogue. Named weights
remain the existing bounded model, not variable axes/PostScript-face persistence.

Existing property commands provide save/reopen, persisted history and owned
recovery behavior. Diagnostics stay on the existing sanitized command paths;
new operation labels are fixed strings, not font names/content/debug output.

## Acceptance source — five new methods, all UNRUN

1. `TransformModelTests/testFontFamilyWeightChoiceIsAtomicForMixedTextAndPreservesExactHistory`
2. `TransformModelTests/testFontFamilyWeightChoiceRejectsInvalidStaleCancelledAndUnavailableTargets`
3. `CanvasTextRenderingTests/testChosenFontPairSharesRendererInlineAndCompilerParagraphMetrics`
4. `CanvasTextRenderingTests/testFontChooserCapturedContextPreservesMissingIntentAndNoOpHistory`
5. `SiteForgeLaunchTests/testInstalledFontPairChooserCancelAtomicUndoAndHeadingSemanticsJourney`

One existing method expanded, also UNRUN:
`ProjectPackageTests/testTypographyPersistsAcrossPackageReopenAndOwnedRecovery`.
All previous assertions remain; additional paired edit checks cover deterministic
package resave, owned recovery, stable property identity and exact Undo/Redo.

Intended new coverage: mixed Text/Button with incompatible subset, per-node
alignment/role/fluid preservation, strict family syntax, invalid/cancelled/stale/
unavailable neutrality, one history entry, exact inverses, branch invalidation,
missing-family fallback and unchanged authored pair neutrality. Shared renderer/
inline frame/font/insets/tracking/caret and authored-layer separation are asserted
at 25/100/800% with 1x/2x backing; compiler CSS/heading markup and canonical reopen
must agree. These are source assertions, not passing or pixel/visual evidence.

The future native journey uses the genuine installed-font popover/Weights menu,
Cancel, keyboard family entry, semantic Heading2, repeated unchanged choice,
single Undo/Redo restoring both properties and live inline frame agreement. Named
chooser/committed-heading/inline screenshots must later be extracted and inspected
at original resolution, including practical-minimum control layout. None exists
for this slice yet. Existing directly affected future selectors include
`testInstalledFontCatalogOffersOnlyDiscoveredWeightsAndPreservesMissingIntent`,
`testCanonicalTypographySharesRendererAndInlineMetricsAcrossZoomAndAlignment`
and `testDesignInspectorTypographyInlineUndoRedoAccessibilityJourney`.

## Deferred / preservation boundaries

No new type presets, automatic responsive conversion, rich text/spans/lists,
variable/italic axes, local/web font import, font packaging/licensing workflow,
font asset catalogue/schema, remote fonts, output-font availability guarantee,
browser parity or release acceptance. SF-0406/0507/0805 remain Partial. Native
runtime, IME/field Undo, glyph pixels, compact/increased-text visuals, scale and
final integrated verification still require separately approved execution.

No new architectural/irreversible migration decision was needed; OD-018/019 and
external/Apple/legal boundaries remain unchanged. Editor 01/05 card/label/scroll
patterns are reused; Settings12 is not copied into a new Inspector scope. No owner
project, approved Dark Flow gradient, export, resource, recovery, cache or retained
runtime evidence was altered. No signing, installation, commit, push, GitHub mutation or
scheduled follow-up. Existing dirty changes are preserved; the deleted schedule
remains deleted. Required verification is deferred, not waived or reported green.
