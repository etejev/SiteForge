# SF-AUTHORING-019 Local Image Asset Authoring Evidence

## Scope

This bounded milestone provides local raster-image import and Image-node
authoring evidence for `SF-0801-001` through `SF-0801-008` and `SF-0802-001`
through `SF-0802-008`. Both normative modules remain Partial beyond the local
PNG/JPEG/GIF/TIFF/HEIC workflow described here.

## Delivered behavior

- The Assets navigator has a searchable native image library, actionable empty
  state, multi-select import, thumbnails, names, dimensions, format, byte size,
  usage count, rename, identity-preserving replacement, usage reveal, and
  explicit in-use deletion resolution.
- Exact original bytes live in the existing content-addressed project-resource
  sidecar. Canonical schema-v5 asset descriptors store stable `AssetID` and
  `ResourceID`, deterministic SHA-256, dimensions, type, byte count, and display
  metadata without local paths. Missing bytes preserve authored identity.
- Image is an available Elements and Insert command. Selected-asset insertion
  uses the existing identity-gated node transaction, stable NodeID/AssetID,
  in-artboard defaults, exact history, duplication, package/recovery, and
  missing-resource behavior.
- Immutable render plans snapshot the matching resource bytes and draw upright
  Fit, Fill, or Stretch content clipped to authored geometry. Selection, hit
  testing, accessibility, and Layout geometry share the same frame. Missing or
  corrupt bytes produce an in-bounds editor placeholder without changing the
  reference.
- The Design Inspector exposes the asset identity and Replace action, native
  Fit/Fill/Stretch control, bounded Fill focal X/Y with Reset, and explicit alt
  text/decorative semantics through one identity-gated registry. Draft state is
  noncanonical; invalid, cancelled, stale, removed, and incompatible edits are
  neutral and diagnostic identifiers remain sanitized.

Tool selection without an imported asset is deliberately nonmodal: it opens
the Assets destination and announces the required action. Only the visible
Import Images and Import and Insert commands own `NSOpenPanel`, so keyboard,
accessibility, and programmatic tool selection cannot block in a modal panel.

## Focused automated evidence

- `ProjectResourceTests`, `InsertionModelTests`, `CommandKernelTests`,
  `ProjectPackageTests`, and `CanvasRendererTests`: 116 tests passed, zero
  failures. The new coverage proves exact-byte import, corrupt rejection,
  descriptor validation, sidecar/missing-resource round trips, staged-byte
  rollback, rename/replacement identity, insertion and Inspector history,
  migration, invalid/stale/inapplicable neutrality, bounded thumbnails,
  explicit in-use deletion, Fit/Fill/Stretch/focal geometry, and immutable
  renderer adoption.
- `AppMetadataTests/testElementsCatalogIsOrderedTruthfulAndDoesNotCreateCanonicalState`:
  1 test passed after the modal tool-selection defect was corrected.
- `SiteForgeLaunchTests/testLocalImageAssetImportAuthoringUndoRedoAndReopenJourney`:
  1 fresh-process actual-app test passed. It uses the real native open panel,
  Assets library, selected-asset insertion, Image Inspector, Undo/Redo, native
  Save, termination, and fresh-process reopen.

Hosted Actions run `33912627892` then exposed three UI assumptions rather than
canonical image defects: Save can already be disabled after autosave reaches
the truthful Saved state; a 1024-point display cannot equal the supported
1100-point production width; and a retained screenshot can yield activation
while SwiftUI replaces an Inspector field's accessibility proxy. The corrected
tests re-query live status/menu/field objects, retain the persistence and focus
assertions, and attach bounded activation/sheet/window/field/focus diagnostics
on readiness failure. The production normal-window policy now preserves its
1100-point minimum and aligns the trailing edge on narrower displays.

The three affected journeys passed independently (3/3) and together across
three consecutive fresh-process repetitions (9/9). The complete UI target
passed 49/49. The final `./sf verify` passed 391 unit/integration plus 49 UI
tests (440 total), zero failures, on 2026-09-04. Repository security,
traceability, architecture, migration, evidence, and fixture-hygiene checks
also passed.

Actions `33922908106` subsequently passed all 391 non-UI tests and exposed five
UI-only assumptions. The typography persistence journey observed Save after
autosave had already made it unnecessary. Four other journeys targeted leading
navigator or Assets controls while the unchanged 1100-point product window was
aligned to the trailing edge of a 1024-point runner. The correction re-queries
live Save/status elements and accepts only the truthful states: already Saved,
or Modified with Save enabled. Leading-control journeys use the established
left-edge test placement only below the product minimum. Final local
`./sf verify` again passed 391 unit/integration plus 49 UI tests (440 total).
Hosted confirmation for the replacement commit remains required.

Replacement Actions `33927510205` passed all 391 non-UI tests and reduced the
UI failures to two system-control differences. On the hosted macOS build, a
full file path could complete the native open-panel import before the retired
Import button proxy became enabled. The journey now requires either the real
asset row or a freshly queried enabled Import action. The structural layout
journey now selects Center through the live native popup's standard keyboard
path when its transient menu item is absent from AX. The two affected journeys
passed together locally (2/2); the prior 440-test `./sf verify` remains the
authoritative full local gate because no production code changed.

Actions `33929806075` passed every repository and non-UI gate plus 48/49 UI
journeys. The remaining image failure was an offscreen trailing Redo toolbar
button after the journey deliberately left-aligned the 1100-point window to
reach native leading import controls on a 1024-point display. The journey now
uses the standard macOS Command-Z and Shift-Command-Z paths and asserts the live
alt-text value changes and restores exactly. This preserves the product minimum
and strengthens history proof without relying on offscreen chrome; the focused
image journey passed 1/1.

Actions `33931671075` passed all repository and non-UI gates and 47/49 UI
journeys. Its log proved that Go to Folder selected the exact image but did not
activate the open panel's default action, and that popup type-ahead did not
commit Center on the hosted OS. The image journey now waits for the native path
sheet to close and activates the panel's default Import action; the structural
journey uses Down Arrow and Return on the live alignment popup. The corrected
image journey passed 1/1 in
`focused-eb0993c6-03f5-4713-bad9-0c2f7155a22c.xcresult`; the structural
journey passed 1/1 in the immediately preceding two-test focused run.

Actions `33933806330` passed every repository and non-UI gate plus 48/49 UI
journeys. Image import passed. The structural journey's production command
published `Alignment committed`, but its following assertion retained a stale
popup query and depended on presentation capitalization. The assertion now
re-queries the live SwiftUI/AppKit replacement control and compares the
semantic accessibility value case-insensitively. The exact structural journey
passed 1/1 in
`focused-8a3bef0d-5ce9-4ba7-a54f-f0a4cba63314.xcresult`.

Actions `33935713623` again passed all repository/non-UI gates and 48/49 UI
journeys. Its sole trace showed the popup was clicked, but Down Arrow and
Return were synthesized against the application and no commit announcement
followed. Both keys now target the re-queried live popup. The exact structural
journey passed 1/1 in
`focused-a0219a8d-e4f3-4169-abe0-eeb819c73755.xcresult`.

Actions `33937301726` passed every repository/non-UI gate. Its first attempt
lost the workspace AX boundary before product assertions; the one justified
retry reached the structural control and proved that even popup-targeted key
events did not commit the transient hosted AppKit menu. The production Stack
alignment control now uses a persistent native segmented picker, matching the
existing direction control and retaining the same canonical registry path.
The practical-minimum control journey passed 1/1 in
`focused-0a9e4685-c6b4-46e7-8fe0-b91a0764d3e6.xcresult`; the complete
structural journey clicks the visible Center segment, requires the canonical
commit announcement, re-queries the live semantic group value, and passed 1/1
in `focused-0a15d65a-83d5-45b6-8064-c113cadddacd.xcresult`.

## Visual inspection

The actual-app journey retained these named original-resolution states:

- `SF-AUTHORING-019 empty Assets.png`
- `SF-AUTHORING-019 imported asset list.png`
- `SF-AUTHORING-019 Image Fit.png`
- `SF-AUTHORING-019 Image Fill focal alt.png`
- `SF-AUTHORING-019 Image undo redo.png`
- `SF-AUTHORING-019 Image reopened.png`

Review found a normal maximized visible-frame window with menu bar and Dock
available; a readable Assets empty state and imported row; upright image pixels;
truthful Fit letterboxing and Fill focal placement; aligned render/selection
geometry; readable, nonwrapping Inspector controls; and exact reopened state.
No ghost/debug content or editor-chrome contamination was present. The asset
metadata row was then split into filename and dimensions/type/size lines to
retain readability at the practical navigator width.

## Explicit deferred scope

Folders, tags, favorites, bulk organization, drag-to-artboard, remote/stock
providers, SVG, video, audio, font assets, advanced editing, filters, masks,
multiple crops or renditions, responsive source sets, metadata-policy UI,
image fills on non-Image nodes, preview/export parity, cross-hardware scale and
OS-level accessibility matrices, and release acceptance remain deferred.
