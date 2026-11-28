# ADR-0130: Document migration registry, dry run, backup and refusal

- Status: Proposed
- Date: 2026-11-26
- Requirements: SF-0309-001 through SF-0309-005, SF-0309-008 (bounded)
- Related: ADR-0009 (strict schema decoding), ADR-0003 (history), ADR-0038 (named snapshots)

## Context

`DocumentSerializer` already upgrades every schema from 1 to 27 through
schema-specific decoders, but the upgrade was silent: nothing described the
steps, nothing checked that stored pages and elements survived, and the first
save replaced the older file with no copy of the original document.

## Decision

- `DocumentMigrations.steps` is a closed, ordered registry with exactly one
  `DocumentMigrationStep` per schema from `minimumSupportedSchemaVersion` to
  `currentSchemaVersion`; `validateRegistry()` proves the chain is contiguous
  and `path(from:)` returns the steps for one source schema. The registry only
  describes the conversions `DocumentSerializer` performs; it is not a second
  conversion path. Still document schema 27; no schema 28.
- `DocumentMigrations.dryRun(_:)` reads one stored document without changing
  anything and returns a `DocumentMigrationReport` (source/target schema, steps,
  page and element counts before and after, bytes). It refuses with a typed
  `DocumentMigrationRefusal` (newer schema, unsupported schema, malformed,
  lost content, unstable result) when a stored page or element identity would
  be missing after the upgrade, or when the upgraded document does not encode
  and decode identically (step summaries checked against `DocumentSerializer`
  and ADR-0015 in review RI, 2026-11-26). Identities are read from the raw JSON so the check
  does not depend on the decoders it verifies. Properties are not compared:
  some upgrades legitimately rewrite them (the schema-4 surface fill).
- Opening a package whose manifest declares an older schema runs the dry run in
  the lifecycle backend (`DocumentLifecycleBackend.migrationCandidate`) before
  adoption. A refusal fails the open (`incompatiblePackage` or
  `malformedPackage`), so the current document and the file stay unchanged.
  Current-schema packages skip the extra work.
- Backup before upgrade: on adoption the controller keeps the unchanged stored
  document bytes as a named snapshot, "Before upgrade from schema N", with
  `documentSchemaVersion` N (`ProjectSnapshots.creatingMigrationBackup`). It is
  held in the in-memory project, so closing without saving leaves the file as
  it was; the next save makes it durable, and the Snapshots sheet restores it
  as one undoable transaction through the existing migrating snapshot decoder.
  Opening does not mark the project modified.
- When the backup cannot be kept (10-snapshot limit or the 2 MiB / 75 % budget),
  the project still opens and the status bar says no backup was kept and
  suggests Save As.
- `migrationReport`, `migrationNotice` and redacted
  `DocumentMigrationDiagnosticRecord`s (requirement ID, operation, schema
  numbers, duration, failure category; no names, paths or content) are on
  `DocumentLifecycleController`. The status bar shows the notice with the
  report and step lines as help text and accessibility value.

## Consequences and limits

- No document schema, package version, history schema or snapshot format change.
- Recovery reads (`readRecovery`) do not run the dry run or keep a backup;
  a legacy recovery artifact still restores as before.
- Since ADR-0133 the refusal reason and its recovery suggestion are the failed
  status text (`migrationRefusal`), and the upgrade notice opens a details
  sheet with the steps, the backup status and Restore Original.
- Importing external markup/assets (other parts of SF-0309) is not covered here.

## Reversal

Remove the dry-run call and the backup step; the serializer behaves exactly as
before and existing backup snapshots remain ordinary named snapshots.
