# ADR-0029 — Property-only component variants

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Requirements: SF-0904-001, SF-0904-002, SF-0904-003, SF-0904-004, SF-0904-005, SF-0904-006, SF-0904-007, SF-0904-008; supporting SF-0901-001/003/005, SF-0905-003/004, SF-0308-003/004, SF-1204-003

## Context

SF-0904 requires variant axes, values, allowed combinations, a default and
per-copy selection, with removed values migrating or surfacing repair. The owner
approved OD-033 (2026-11-25): property-only variants on one definition, and
(2026-11-26) editing inside the variant, with structure edited only in the base.
ADR-0018 keeps one definition graph per component; OD-034 nesting and OD-018
slot content already resolve through `ComponentGraphResolver.expand`.

## Decision drivers

- One resolution point so canvas, in-app Preview, Browser Preview, export,
  detach and Customize agree.
- No new structure model: every variant has the same objects and identities.
- Older projects open unchanged; older builds never silently drop variant data.
- No new history command: every edit is ordinary property commands.
- References that transfer remaps (tokens, assets, reusable styles, links) never
  sit inside keys that transfer does not remap.

## Considered options

1. One separate definition per variant, linked into a set. Rejected: duplicated
   structure and settings, and shared edits must be repeated per definition.
2. Structural variants (any object may differ). Rejected for now: needs a graph
   per variant; owner chose property-only.
3. Property-only variants on one definition with typed overrides. **Chosen.**

## Decision

- Storage (document schema 26, namespace `component.variant.v1.`): the
  definition root holds ordered axes (`axes`, `axis.<id>.name|values|default`,
  `value.<id>.name`) and optional `disallowed` combinations (sorted keys, value
  IDs in axis order joined by `+`). Any definition node may hold
  `override.<target>.<key>` (a value) and `unset.<target>.<key>` (`true`: absent
  in that variant); a target is one axis value or one exact combination.
- Limits: 4 axes, 2–16 values per axis, 256 combinations, 4,096 override
  properties per definition, 64 stored choices per copy.
- Variant-capable keys: `layout.x/y/width/height`, `hidden`, `content.text`, the
  control label and `style.*`, except reusable styles, color-token bindings and
  image-asset references. Everything else is the same in every variant.
- Precedence: base < each chosen axis value in axis order < the exact
  combination. Overridden properties keep the base identity; properties a
  variant adds use the override's identity.
- Copies store `component.instance.v1.variant.<axis>` = value ID. No choice
  means the axis default. A choice for a removed axis or value, or a combination
  that is no longer allowed, is kept and reported (`variant-axis-unavailable`,
  `variant-value-unavailable`, `variant-combination-not-allowed`); the copy shows
  the default (per axis, or the default combination). Output is not blocked.
- Resolution: `CanonicalComponentVariants.resolvedDefinition(_:for:)` runs at the
  start of `ComponentGraphResolver.expand`, so nested copies keep their own
  choice and slot projection is unaffected. Inspector inherited values use it too.
- Validation: strict metadata decoding, override targets must exist (combination
  targets must be allowed), and every distinct variant that authored overrides
  produce is validated with the same page rules as the base
  (`componentVariantResolvesInvalid`).
- Authoring: `ComponentVariantCommandRegistry` edits axes, values, defaults,
  allowed combinations, a copy's choice (a copy still at its variant's size takes
  the new variant's size) and Use Base Value. Removing a value or axis removes its
  settings; reordering axes re-keys combination settings. Editing inside a
  variant: the workspace presents the open definition as that variant
  (`authoringDocument`) and installs `DocumentSession.authoringTransform`, the
  one conversion point (`CanonicalComponentVariants.rewrite`) that turns property
  edits into that target's overrides and refuses structure edits and settings
  that are the same in every variant. Undo and redo replay converted commands.
- Transfer: clipboard version 7 when variant data travels; variant storage is
  definition-owned, so objects copied out of a definition carry none. Variant
  IDs are scoped to their definition and are not remapped.

## Consequences

### Positive

- One rule everywhere, no new structure or history model, older files unchanged.
- Repair is visible and never discards a copy's intent.

### Negative or risky

- `WorkspaceShellModel` reads `authoringDocument` instead of
  `documentSession.document` (412 sites, textual replacement; identical outside
  variant editing). Code that compares document values sees the presented
  definition while a variant is edited.
- An edit to a value target can be hidden by an existing combination override in
  the preview combination; the Inspector names the winning rule.
- Validation cost grows with the number of distinct authored variants.
- Size changes of a copy follow the variant only while the copy still has its
  current variant's size.

## Verification

Selectors are listed in `docs/coordination/CODE_FORGE_ACTIVITY.md` (Batch 07):
model, schema, resolution, invalid variants, commands, edit conversion, copy
choice, workspace, rendering parity, scale (standard/large/stress), clipboard,
detach/duplicate, and one UI journey. Nothing has been compiled or run yet.

## Verification amendments (lane V03, 2026-11-26)

Read-only verification of Batch 07 (no compiler) found and fixed:

- Website Preview, its export and Check Website / local output compiled
  `authoringDocument`. While a variant is edited that document presents the open
  definition as the variant (override storage hidden), so every copy of the
  component would have been written with the edited variant's values. They now
  compile the stored project (`documentSession.document`); revision checks are
  unchanged because both documents share identity and revision. The canvas and
  the in-app Preview still show the presented variant (what the author edits).
- Undo, Redo, a history jump or a revert could remove the variant being edited
  while editing continued; `rewrite` then passed edits through to the base.
  `rewrite` now refuses edits of the open definition with `stale` when the target
  is no longer editable (`CanonicalComponentVariants.isEditable`), and the
  workspace returns to Base on the next document publication, with an
  announcement.
- Enabling the controls of the Variants popover ran the full registry commit
  path per control (whole-document validation and a scan of every page for
  copies needing repair). Availability now uses `prepare(..., forCommit: false)`;
  the commit still validates the whole document once.
- Variant operations emitted no diagnostics. `ComponentVariantDiagnostic`
  (requirement ID, operation, hashed document and component identities,
  failure category, duration) is recorded for every variant edit, entering or
  leaving a variant, and the return to Base above.
- Remove Property is disabled with the registry's reason like the other
  controls; the arrow buttons have spoken labels.

Open (owner decision, proposed as OD-142): a variant's own text
(`content.text` or the control label) is not translatable. In a language tree
the base text is translated but a variant's text override shows the default
language.

## Reversal

Remove the variant namespace and choice keys from validation and the schema-26
gate, drop `resolvedDefinition` from `expand`, and restore
`documentSession.document` reads. Projects that use variants would need a
migration that detaches or flattens them; schema-25 projects are unaffected.
