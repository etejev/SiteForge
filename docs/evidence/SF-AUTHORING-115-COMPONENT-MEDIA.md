# SF-AUTHORING-115 — Local-image component media property

## Scope and cadence

Development Prompt 2 of 10 implements bounded `SF-0902-001`–`SF-0902-008`,
supporting `SF-0905-001`–`SF-0905-008` and `SF-0801-004/005/008`. The normative
modules remain **Partial**. Owner direction defers every test/build/verification
command until Development Prompt 10; this note records source evidence only.

## Source behavior

- `CanonicalComponentMedia` gives each exposed Image asset property a stable
  `ComponentMediaPropertyID`, label, source NodeID, and canonical default
  AssetID. Instance values are authored only under the versioned media override
  namespace; local paths and bytes never enter the component node.
- `ComponentCommandRegistry` exposes/removes definitions and sets/resets
  instance assets through the existing document/page/revision/scene/renderer/
  selection identity gate. Missing assets, cancellation, stale identity, and
  stable-ID retargeting remain mutation-neutral.
- Schema v12 writes the media namespace. Older schema 11 packages remain
  readable, while forged v11 media properties fail closed. Exact property IDs,
  Undo/Redo, save/reopen, recovery, and reset-to-inheritance use the existing
  command and serializer architecture.
- `ComponentGraphResolver` applies the effective AssetID before immutable
  canvas/static-output preparation. Selection and editor chrome remain outside
  authored image content.
- Cross-project component transfer includes media-referenced resource bytes,
  remaps AssetID and stable media-property identity together, and normalizes
  binding identity for structural reuse. Dependency inspection and safe asset
  deletion count media overrides; explicit detach removes only the override.
- The Content Inspector uses a native project-image picker with visible names,
  inherited/authored provenance, Reset Override, accessible label/value/hint,
  and bounded missing-asset wording. Definition drafts remain scene-local and
  Escape/Cancel preserve the committed property.

## Test source added, not run

- `CommandKernelTests.testComponentImageMediaOverrideResetHistoryRendererPersistenceAndValidation`
  covers expose/set/reset, effective renderer projection, exact history,
  schema-v12 round-trip, forged older-schema rejection, missing asset, and
  cancellation.
- `SiteForgeLaunchTests.testLocalImageAssetImportAuthoringUndoRedoAndReopenJourney`
  now continues through real component-definition Image insertion, media
  exposure, linked-instance picker/accessibility, and retained visual evidence.
- Existing cross-project component transfer and asset-deletion tests compile
  against the media dependency/remapping path and are verification targets for
  Prompt 10.

No selector was executed in this prompt. Required Prompt-10 targets include
the new command test, the local-image actual-app journey, cross-project
component transfer, safe asset deletion, schema compatibility, then the single
accumulated `./sf verify` gate.

## Deferred

Remote/cloud media, audio/video/vector/font properties, responsive source
sets, crop/rendition editing, arbitrary media types, actions, slots, variants,
nested components, broad assistive-technology/performance matrices,
preview/export certification, and release acceptance.
