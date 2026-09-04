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

The milestone-closing `./sf verify` passed 390 unit/integration plus 49 UI tests
(439 total), zero failures, on 2026-09-04. Repository security, traceability,
architecture, migration, evidence, and fixture-hygiene checks also passed.

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
