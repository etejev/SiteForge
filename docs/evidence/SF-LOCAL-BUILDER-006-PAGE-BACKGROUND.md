# Page Background discoverability — development-only source slice

**Bounded local acceptance complete — affected model, renderer and real-app
acceptance passed; final ./sf verify passes785 non-UI/151 UI,0 failures,
3 intentional owner-session skips.** Parent owner delivery remains IN PROGRESS.
Full-e7ee511e is authoritative; earlier unrun notes below are historical.

The shared immutable scene/plan now includes a separate structural page surface
at actual artboard bounds. Tile paint/invalidation and native Preview consume
it without adding canvas objects, hit targets, overlays or accessibility nodes.
`CanvasTextRenderingTests/testStructuralPageBackgroundPaintsExactPixelsWithoutCanvasObject`
adds exact sRGB pixel and exclusion coverage at 1x/2x. Authored channel values
are explicitly sRGB; Transparent/None does not author white. The real-app
journey now verifies page pixels after fill/Undo as well as None/Redo.
Five affected renderer/UI checks pass in
`focused-0a6d433e-7084-4273-a900-7ea68229d21e.xcresult`.
See the ten-workflow integration receipt for retained visual evidence.

Requirements: SF-0508-002/003/005/006 and SF-0701-003/006. This is a bounded
discoverability continuation of SF-LOCAL-BUILDER-006, not completion of those
normative modules. Clipboard/drag-and-drop candidate requirements do not describe
new behavior in this slice and are not claimed. OD-018/019 remain unchanged.

## Concrete source changes

- `SiteForge/TransformModel.swift`: `PageBackgroundPolicy` recognizes only a
  website page's single geometry-less Frame Root with exact page ownership.
  Multiple roots, geometry-bearing roots and component-definition graphs are
  not guessed. Hidden/locked Roots provide an explicit unavailable reason.
- `SiteForge/WorkspaceShellModel.swift`: Page Background navigation selects that
  Root through existing Layers selection and opens Design. It rejects a stale
  page action; it does not create a background node or mutate content. The
  existing Inspector context key now includes document/page identity as well as
  selection/revision, so queued fill drafts cannot cross page/document changes.
- `SiteForge/WorkspaceShellView.swift`: visible Page Background entry in Pages,
  the native Page Actions menu and the empty Design Inspector. Root inspection
  uses the existing appearance card, solid/gradient layer controls and color-token
  controls, with a concise effective summary and guidance. Object-only style/
  semantic cards and workflow controls are omitted in this context. Existing
  adaptive Pages button layout and scrollable Inspector remain in use.
- `SiteForge/SelectionModel.swift` and scene preparation: distinguish structural
  Root ownership from hidden visibility. Even an otherwise blank page's Root
  can be inspected in Layers as “Page structure”; explicit hidden state still
  says “Hidden at current breakpoint.” Structural Roots remain excluded from
  canvas traversal/overlays and do not acquire fabricated object geometry.
- The existing typed fill-layer registry adds `clearAll`. Transparent / None
  atomically removes fill layers and the fill-token binding, but not the token
  definition, other target bindings, opacity, geometry or child styles. An empty
  authored layer order prevents legacy surface revival. Repeating None on an
  already omitted/empty background is neutral. Existing command-kernel inverses
  retain the original PropertyIDs, origins, layer identities and token binding.
- `SiteForge/DocumentModel.swift`: shared appearance resolution honors an explicit
  empty canonical layer stack as None instead of revealing an inherited reusable
  solid. Reusable definitions/bindings and opacity remain intact. Unrun source
  coverage includes this inherited-fill case and exact restoration.

No parallel background property, schema migration, hardcoded dark color, output
CSS patch or owner-package edit was introduced. Shared output continues to read
the canonical Root; no renderer/compiler was rewritten for discoverability.
This source-only change does **not** establish new canvas pixel parity, visual
acceptance, performance, recovery or browser/export acceptance.

## Added acceptance source — all UNRUN

1. `TransformModelTests/testPageBackgroundPolicyRequiresSingleStructuralWebsiteRoot`
2. `TransformModelTests/testPageBackgroundTransparentNonePreservesTokenHistoryAndPersistence`
3. `TransformModelTests/testPageBackgroundGradientProjectsThroughSharedCompilerWithoutMutation`
4. `TransformModelTests/testPageBackgroundEntrySelectsStructuralRootWithoutCanvasGhostOrMutation`
5. `SelectionModelTests/testStructuralRootPresentationDoesNotConflateOwnershipWithHiddenState`
6. `SiteForgeLaunchTests/testPageBackgroundEntryUsesSharedFillEditorAndTransparentHistory`

The model source covers no-op/cancel/stale page/revision neutrality, exact undo/
redo, token retention, serializer round-trip and immutable shared output. The UI
source uses actual visible controls and retains future authored/transparent
screenshots. Existing assertions are preserved. No new screenshots exist yet.

## Verification boundary and next action

No build, test, test/check script, UI automation, readiness probe or manual visual
journey was run for this slice. Static source/diff review only. Compilation and
all six selectors remain pending explicit owner approval. Then run affected
selectors, inspect real minimum/maximized UI and authored canvas/preview output,
and address any concrete failure before the required future full gate. Do not
install, sign, commit or push on this source-only evidence.

Historical frozen-source partial gate remains 733 non-UI +100 UI passes, three
owner-session skips, one owner-requested cancellation and38 UI not reached. It
does not verify these newer source edits and is not a full pass. Existing owner
website/export at revision245, original projects/resources and recovery remain
untouched. SF-LOCAL-BUILDER-006 stays IN PROGRESS with testing on owner hold.
