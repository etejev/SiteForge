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
