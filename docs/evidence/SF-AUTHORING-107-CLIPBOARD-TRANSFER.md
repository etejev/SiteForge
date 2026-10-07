# SF-AUTHORING-107 — Transactional clipboard and bounded cross-project transfer

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED** (2026-10-05)

## Bounded requirement coverage

- `SF-0308-001` through `SF-0308-008` are connected in production source for
  authored node-subtree Cut, Copy, Paste, Paste in Place, and Duplicate.
- The slice uses the existing document command/history owner, project resource
  package, color-token collection, selection scene, renderer adoption, native
  macOS menus/pasteboard, status announcements, and diagnostics. It does not
  create another document or resource store.
- All new source and test source is intentionally unrun under the owner testing
  pause. The module remains Partial until focused and full verification run.

## Connected production behavior

- `SiteForgeClipboardEnvelope` is a closed version-one JSON envelope carried by
  `com.siteforge.authored-objects.v1`. It contains only the selected canonical
  subtree closure plus required local raster-image bytes/metadata and used
  local color tokens. It is inert, capped at 10,000 nodes, 1,000 roots, 1,000
  dependencies, and 64 MiB encoded size, and rejects unknown keys, duplicate
  identities, malformed ownership, corrupt hashes, unsupported versions, and
  incomplete dependency closures before adoption.
- Copy prepares and validates the complete envelope before replacing the native
  pasteboard. Cut also validates and compiles one child-first removal batch
  before replacement, then executes it only after the native write succeeds,
  so pasteboard failure and cancellation cannot delete canonical content.
- Paste remaps every NodeID and PropertyID. Internal copied-node links, image
  AssetIDs/ResourceIDs, color-token IDs, form option IDs, and fluid-value IDs
  are remapped through their existing typed codecs. Same-content image assets
  and exact name/color tokens reuse destination equivalents; otherwise bytes
  are hash-verified, assigned fresh identities, staged through the lifecycle's
  rollback boundary, and adopted with the node batch. Root ordering, subtree
  sibling order, and relative child geometry remain stable. Paste offsets only
  root base X/Y by 20 points; Paste in Place preserves exact geometry.
- Duplicate uses the same remap and command compiler without replacing the
  user's clipboard, resolving selected roots back to their common original
  parent so a selected container cannot accidentally receive its own copy.
  An ambiguous multi-parent duplicate rejects without mutation. Paste,
  Duplicate, and Cut each create one existing history transaction and exact
  inverse; renderer/Layers/Inspector/accessibility update through normal
  document and selection adoption.
- Native Edit commands use standard Command-X/C/V, Shift-Command-V, and
  Command-D. An active native text responder retains normal NSText clipboard
  behavior. Layers and canvas contextual menus expose the same central routes,
  while the status bar publishes a readable accessibility announcement.
- Diagnostics retain requirement/operation/count/revision/failure category and
  bounded one-way object-identity digests. They never retain clipboard bytes,
  authored values, names, paths, bookmarks, history, credentials, or raw
  object identities.

## Dependency and conflict rules

1. Destination assets match by verified content hash, never filename or path.
2. Destination color tokens match by exact name and normalized color; a
   nonmatching name conflict receives a fresh identity and deterministic
   `Copy N` display suffix.
3. Internal section links to copied nodes remap to the copied identity. A
   cross-project link to the copied source page maps to the active destination
   page; external page/node dependencies reject rather than creating a
   dangling reference. Same-project references retain existing valid targets.
4. Cross-project component-instance/definition transfer is rejected with a
   typed recovery message in this bounded slice; same-project component
   references remain valid. This avoids silently copying only half of a
   definition/override graph.
5. Absolute paths, security-scoped bookmarks, workspace state, editor drafts,
   selection history, undo history, and unrelated project objects are excluded.

## Test source added (not executed)

- `ClipboardTransferTests.testEnvelopeRoundTripIsClosedBoundedAndRejectsMalformedGraphs`
- `ClipboardTransferTests.testSameProjectPasteAndDuplicateRemapStableIdentityAndUndoRedoExactly`
- `ClipboardTransferTests.testPasteInPlacePreservesRelativeGeometryAndCutRemovalIsOneAtomicBatch`
- `ClipboardTransferTests.testCrossProjectTransferDeduplicatesAssetsImportsTokensAndPreservesReferences`
- `ClipboardTransferTests.testStaleCancelledMalformedAndCrossProjectComponentInputsAreNeutral`
- `SiteForgeLaunchTests.testTransactionalClipboardDuplicateCutPasteUndoRedoAccessibilityJourney`

## Explicitly deferred

- Cross-project component-definition closure/import, page duplication through
  the clipboard, rich-text/foreign HTML parsing, arbitrary external image
  paste, connected/cloud clipboards, collaboration conflict resolution, and
  release-scale accessibility/performance/migration certification.
- Plain text continues to use the existing native inline editor clipboard. The
  authored-object envelope does not reinterpret arbitrary public text or image
  pasteboard types.
