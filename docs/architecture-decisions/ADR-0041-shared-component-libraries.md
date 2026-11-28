# ADR-0041 — Shared component libraries (exported package, read-only copy, update/compare)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-046 (approved by the owner 2026-11-26 1:30 PM EST)
- Requirements: SF-0906-001 … SF-0906-008 (first slice: local library files; no live linking, no dependency resolution between libraries)
- Builds on: ADR-0038 (package members for project records), ADR-0040 (structural comparison)

## Context

OD-046: a library is an exported, versioned package of component definitions
and tokens that other projects import as a read-only copy with update/compare;
no live linking across projects in the first slice. SF-0906's invariant:
updates are explicit and reversible; unresolved dependencies keep last
known-good content.

## Decision

- Library file (JSON, format `app.siteforge.component-library`, version 1,
  exact keys): `libraryID`, `name`, `libraryVersion` (semantic
  `major.minor.patch`, `ComponentLibraryVersion`), `exportedAt` and `document`
  — a complete canonical carrier document (`DocumentSerializer` encoding,
  base64) whose component definitions and color tokens are the library. The
  carrier's document ID is the library ID. Reading validates and migrates it
  with the normal document decoder. Limit: 4 MiB (the member limit).
- Export takes every component definition the project owns (not copies from
  a library) and the color tokens they use. Refused, naming the component: no
  own components; a component that uses an image, plays video or audio, has
  translations, uses a font stored in the project, links to a page of the
  project, or applies a reusable style defined outside the exported
  components (none of these are carried in this slice; ADR-0042); a component
  that uses an item from an imported library (detach it first).
  The project records what it last exported (`published`: library ID, name,
  version); the next export keeps the ID and needs a higher version. The file
  is written first; a failed write records nothing.
- Project record: optional package member `libraries/index-v1.json`
  (`ComponentLibraryIndex`, version 1, exact keys, document ID, `published`,
  `imported` — at most 32). Each `ComponentLibraryImport` keeps library ID,
  name, version, import time, the definition and token IDs it owns (every
  identity any imported version delivered, so after Undo of an update the
  earlier version is still recognised and stays read-only; lane R review
  2026-11-26), and up to 16 known versions with content digests. No document schema, package version
  or history change: the copies are ordinary document content. Damaged or
  foreign records: `corrupt`; repair is Remove All Library Records (removes
  only `libraries/` members; the copies become ordinary content).
- Import adds the definitions (after all pages) and tokens (after all tokens)
  with their stable identities in one `batch` command, so it is one Undo step.
  Refused: the project's own library, a library already imported (use
  Update), an identity already in the document (for example a copy made
  earlier), more than 32 libraries, a record larger than 256 KiB
  (`recordTooLarge`). Import, update and Apply wait while a component variant
  is being edited (ADR-0042).
- Read-only: `DocumentSession.commitGuard` (new; checked inside `commit` for
  new commands only, after model validation) is installed by
  `DocumentLifecycleController`. A command may not change or remove a library
  definition or token that existed before it; moving a component in the page
  list is allowed. The refusal is `CommandExecutionError.disabled` with a
  message naming the library and the two ways out (update or detach). Undo and
  redo are not checked, so an import or update can always be undone.
- Update: choose a file of the same library; `previewingUpdate` compares the
  version in the document with the file's (`ProjectComparer`, by identity),
  lists components the new version drops and counts copies on pages that would
  show as missing components. Nothing changes until Apply Update. Apply is one
  command (the guard is bypassed for exactly that command) that replaces the
  library's definitions in place and its tokens; the record moves to the new
  version and keeps the old one as known. Same version and content:
  `unchanged`. An older file is allowed and labelled as a downgrade.
- Status per library: current version; earlier known version (an update was
  undone); changed (matches no known version); missing (the import was undone).
- Detach ends the link: the items stay as editable content and no longer
  receive updates.
- UI: File menu **Component Libraries…** opens a sheet: imported libraries
  with status, Update… / Detach… (confirmed); the update review with the
  comparison, removal warning, Apply Update / Cancel; Import Library… (open
  panel, JSON); Export section with name, version (suggested next minor) and
  Export Library… (save panel), disabled without own components. Announcements
  for every result.
- Lifecycle API: `componentLibraryIndex()`, `componentLibraryRows()`,
  `exportComponentLibrary(named:version:write:)`,
  `importComponentLibrary(_:)`, `previewComponentLibraryUpdate(_:)`,
  `updateComponentLibrary(_:)`, `detachComponentLibrary(_:)`,
  `removeAllComponentLibraryRecords()`. Record changes mark the project
  modified (like snapshots) and become durable with the next save. Refused
  (`unavailable`) during a save, open or other transition.
- Diagnostics: `ComponentLibraryDiagnosticRecord` (SF-0906-008, operation,
  sanitized library ID, duration, result, failure category); no names or
  content.

## Consequences

- No images, fonts or nested library dependencies in libraries yet; such
  components are refused with a reason. Token name clashes between a library
  and the project are left to model validation (the import is then refused).
- Copies are read-only only while the record exists; Undo of an import leaves
  the record with status "missing" (Redo or Detach resolves it).
- Restoring a snapshot taken before an import, or any batch that would remove
  library copies, is refused by the read-only rule until the library is
  detached.
- Library files are read on the main actor (limit 4 MiB); the update
  comparison is bounded by `ProjectComparer.maximumChanges`.
- Feature flag `components.shared-libraries` (`FeatureFlagID.componentLibraries`,
  default on, remove by 2027-03-31, SF-0906; owner decision 2026-11-26 6:01 PM
  EST, batch A04) gates the menu item and `presentComponentLibraries`. It does
  not gate the read-only rule: with the flag off, imported copies stay
  read-only. No linked or cached remote libraries, pinning UI or provenance
  beyond the record.

## Reversal

Remove the menu item, sheet and commit guard; `libraries/` members are then
preserved unknown optional members and the copies stay ordinary content.
