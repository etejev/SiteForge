# ADR-0027 — Project-scoped preferences

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-25
- Owners: Product / Engineering
- Requirements: SF-0206-001, SF-0206-002, SF-0206-003, SF-0206-004, SF-0206-005, SF-0206-006, SF-0206-007, SF-0206-008

## Context

Module 0206 requires preferences with an explicit scope, canonical identity, typed
validation, versioned serialization and history. Until now every implemented
preference was application-scoped and stored on this Mac only (ADR-0006,
SF-AUTHORING-023/064/065), so SF-0206-001 and SF-0206-005 had no project-owned
preference to satisfy them. The owner asked that project-specific settings, such as
grid layout, live with the project, while app settings such as appearance or text
size live with the app, and that both be available in the Settings window.

## Decision drivers

- Scope is explicit and visible: the user can tell which rule supplies a value.
- Project values travel with the file and participate in undo, autosave, recovery,
  save/reopen and duplication; app values never enter a project package.
- Older projects open unchanged; older builds never silently drop newer data.
- No new canvas behavior is invented to have something to store.

## Considered options

1. Store project preferences inside `WebsiteMetadata`. Rejected: website metadata
   is published output (title, description, indexing); editor preferences are not.
2. Store them as node properties on the page root. Rejected: preferences belong to
   the project, not to a page, and must not be copied with page content.
3. A separate optional, versioned `ProjectPreferences` record on `CanonicalDocument`
   with its own document command. **Chosen.**

## Decision

- `CanonicalDocument.projectPreferences` is an optional `ProjectPreferences` record
  (version 1) introduced in document schema 22. It is omitted when nothing is set;
  an empty record and explicit nulls are invalid, so "nothing set" has one form.
- Fields are individually optional. v1 holds `gridVisibleOnOpen` (Bool) and
  `gridSpacing` (whole points 4–128; minor interval at 100% zoom, major = 4×).
- Precedence (`ProjectPreferenceResolver`): authored project value, then this Mac's
  application default where one exists (new-workspace Grid), then the SiteForge
  default (Grid shown, 16 pt). Settings shows the winning source for each value.
- Edits go through `ProjectPreferencesCommandRegistry` and the new
  `DocumentCommand.setProjectPreferences`: one validated transaction with an exact
  inverse. Persisted history schema 4 owns the command; v3 and older histories
  remain readable and cannot carry it.
- A workspace adopts an authored Grid value when the project opens, and re-applies
  the resolved value when that preference changes (Apply, Undo, Redo). Unrelated
  edits never override the scene-local Grid toggle, which never writes the project.
  Grid spacing always follows the resolved value.
- The shared Settings window gains a **Project** pane after Canvas. It edits the
  active workspace's project (the same target as the File and View commands) through
  a draft with Apply, Cancel/Escape and Reset; a stale, different or closed project
  never receives a draft. With no project open it explains the first action.
- Application preferences remain in their existing panes and storage.
- **Invalid values recover safely (SF-0206-004).** Structural violations (unknown
  key, wrong type, explicit null, unsupported version, empty record, non-finite
  number) are rejected like every closed SiteForge schema. A value that only breaks
  its value rule (for example a spacing of 200 pt) keeps the project openable: it is
  retained byte-for-byte, resolution reports `invalidProjectValue` and uses the
  SiteForge default, and Settings states the rule and offers **Use SiteForge
  Default**. Unrelated preferences stay editable around it; no commit can introduce
  a new invalid value, and Undo of a repair restores the stored intent.
- Each preference has a stable identity (`project.canvas.gridVisibleOnOpen`,
  `project.canvas.gridSpacing`). Settings diagnostics record requirement IDs per
  operation, the operation, a sanitized document token, affected preference
  identities, duration and a failure category; never values or content.
- Grid drawing never gets denser than the default grid's densest band (8 screen
  points between minor lines), so a fine spacing cannot multiply line count when
  zoomed out (SF-0206-007).
- Preferences are editor-only: preview planning and static output are identical
  with and without them, so no export compatibility finding is needed.
- While a project is busy (Preview open, file conflict), the pane keeps the draft,
  shows the reason and disables Apply. With no project open it offers
  **Open or Create a Project…**, which brings a SiteForge window forward.

## Consequences

### Positive

- SF-0206-001/005 now have a project-owned preference with history and persistence.
- The scope rule is reusable: future project preferences add optional fields to the
  same record (bumping its version only for incompatible changes).

### Negative or risky

- Every save now writes document schema 22, so builds that predate this change
  cannot open newly saved projects (the same trade-off as earlier schema bumps).
- The workspace Grid can now change when a project's Grid preference changes.

## Verification

Unit tests cover resolution, strict coding, the schema-22 gate, validation, the
registry's rejections, undo/redo, workspace adoption, the Settings store's draft,
stale and no-project states, diagnostics and large-fixture responsiveness. History
tests cover save, reopen, recovery and history v4. Scale tests use the standard
(100), large (10,000) and stress fixtures; stress fills the documented 20,000-node
canonical budget and checks persistence against the package v1 4 MiB member cap. One UI journey covers the
Settings pane, Escape, Apply, workspace adoption and Undo. None has been executed
when this ADR was written; see `docs/coordination/CODE_FORGE_ACTIVITY.md`.

## Reversal

If project preferences should live elsewhere, schema 22 projects can be migrated by
moving the record; because the record is optional and isolated, removing it only
requires a new schema that drops the field after an explicit migration.
