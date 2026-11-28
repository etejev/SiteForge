# ADR-0071 — Local CMS collections and the Collections editor

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-035 (approved by the owner 2026-11-26 1:30 PM EST)
- Requirements: SF-1001-001 … SF-1001-008, SF-1002-001 … SF-1002-008

## Context

OD-035 chooses local, project-stored collections with typed fields (text,
rich text, number, date, image, reference), a collection editor window, and
template pages that generate one static page per item at export (D3). No
server; content lives in the project package.

## Decision

- Model (`SiteForge/DocumentModel.swift`): `ContentCollection` (id, name,
  address `slug`, ordered `fields`, ordered `items`), `CollectionField` (id,
  expression `key`, label, type, `isRequired`, `referencedCollectionID` only
  for references), `CollectionItem` (id, `slug`, `status` draft/published,
  `values` sorted by field id, at most one per field), `CollectionFieldValue`
  (`{"type", "value"}`; dates as `YYYY-MM-DD`, numbers finite). Every record
  has exact keys. New stable identifier domains: `collection`,
  `collection-field`, `collection-item`.
- `CanonicalDocument.collections` is optional in the file: the key is written
  only when there is at least one collection; an empty list or null is
  refused. Still document schema 27 (unreleased); a schema 26 file with
  collections is refused.
- Rules (`CanonicalCollections.issues`, enforced by `CanonicalDocument.validate`
  as `ModelValidationError.invalidCollections`): at most 100 collections,
  64 fields and 10,000 items each; unique ids; non-blank trimmed names (128
  bytes) unique case-insensitively; addresses `[a-z0-9]` with single hyphens
  (64 bytes) unique per level; field keys start with a lowercase ASCII letter,
  then letters, digits or `_` (40 bytes), not an expression keyword and not
  `slug status id collection item page site`; references must point at an
  existing collection; values must match their field type; text at most
  64 KiB without NUL; published items need every required field (drafts may
  be incomplete). Each issue names the collection, field and item by id;
  messages never contain values.
- Data safety (SF-1001 critical invariant): removing a field shows how many
  items lose a value first; a field's type can change only between text and
  rich text, or when no item has a value; a collection that another
  collection's reference field points to cannot be deleted; deleting an item
  that others reference leaves a visible "missing item" reference. Deleting an
  image asset used by a collection item is refused, and such assets are not
  "unused".
- Editing: one `DocumentCommand.setCollections` (`document.collections.set`,
  "Edit Collections") replaces the whole list; its inverse restores the
  previous list. Persisted history keeps schema 4 and validates the payload
  keys. `CollectionEditing` holds pure draft operations (new collection with
  a required Title field, add/remove/move/retype fields, new/duplicate items,
  Publish Ready Drafts, search and status filter, display title) and `prepare`
  (busy, stale revision, invalid, unchanged checks) used by the editor.
- UI: File > Collections… opens a sheet (`CollectionsEditorView`): collection
  sidebar, Items (search, status filter, list, form with one control per
  field, invalid number/date text kept as typed without replacing the last
  valid value), Fields (label, name, type, required, order, remove) and
  Settings (name, address, delete). Rules are checked live; Apply commits the
  draft as one undoable step, Cancel discards it. Removals are confirmed with
  the affected counts.
- Expressions (ADR-0070): `ContentCollection.expressionSchema(in:)` and
  `expressionContext(for:in:)` expose `slug`, text/rich text/number/date
  fields by key, and for references `key.slug` plus the referenced
  collection's fields.
- Snapshot restore, snapshot comparison and new-from-template carry collections.
- Diagnostics: `CollectionEditDiagnostic` (requirement id, operation, sorted
  collection ids, item count, duration, failure category; no names or values).

## Consequences

- Collections do not appear in Preview or export until template pages (D3).
- Scheduling metadata and authors (SF-1002 primary objects) are not modelled
  in this slice; status is draft/published only.
- CSV/JSON import (OD-037) is batch D4.

## Reversal

Hide File > Collections… and stop writing the key; keep reading schema 27
documents that contain collections.
