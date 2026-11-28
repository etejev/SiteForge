# ADR-0145 — Export target capability check and export diagnostics

- Status: Proposed (implemented as an unverified Code Forge candidate by lane V06; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-042 (approved by the owner 2026-11-26 1:30 PM EST); review follow-ups for OD-041 and OD-047
- Requirements: SF-1209-003, SF-1209-004, SF-1209-008; SF-1107-004, SF-1107-005; SF-1803-002, SF-1803-004
- Builds on: ADR-0035 (zip export target), ADR-0036 (feature flags), ADR-0037 (custom code)

## Context

Batch 15 (ADR-0035) added the zip adapter but left SF-1209's critical
invariant half done: "unsupported capabilities are reported before build".
A plan over the ZIP32 limits was only refused while writing, after the whole
archive had been assembled in memory. Exports also left no diagnostic record,
which SF-1209-001/008 require. The lane V06 review of batches 15–17 found
further defects in the custom code and feature flag work.

## Decision

- **Adapter contract.** `StaticExportTarget.unsupportedReason(for:)` returns
  `nil` when the target can carry the plan, otherwise a user-facing reason.
  The folder target has no limit. The zip target uses
  `StaticSiteZipArchive.canArchive(_:)`: at most 65,535 entries, names of at
  most 65,535 bytes, and `archivedByteCount(_:)` (the exact archive size:
  76 bytes plus twice the name per entry, plus the data, plus 22) within
  4 GiB. `archivedByteCount` equals `archive(_:).count`; a test proves it.
- **Reported before writing.** Check Website's **Build Zip Archive…** and
  Browser Preview's **Export Zip…** are disabled when the reason is not `nil`,
  and show it as help text and accessibility hint. The writer checks the same
  rule before it allocates the archive and throws `archiveTooLarge`, so the
  check and the write never disagree.
- **Export diagnostics.** `StaticExportDiagnostic` (requirement
  `SF-1209-008`, operation `export`, target, sanitized document token from
  `DiagnosticStableIdentifier`, revision, file count, duration in ms, failure
  category). No destination path, file name or content. Categories come from
  the closed `LocalStaticBuildWriteError.diagnosticCategory`. It is published
  as `WorkspaceShellState.lastStaticExportDiagnostic` and
  `BrowserPreviewController.lastExportDiagnostic` after every export of the
  current request, success or failure.
- **Zip wording.** Check Website's unsafe-destination message for a zip says to
  choose a new `.zip` name, because a zip never replaces a folder.
- **Custom code review fixes (OD-041).** Duplicating a page now copies its
  custom code in the same undoable step (`PageCommandRegistry`, page
  duplicate). The page form's **Use website defaults** resets search metadata
  only and keeps the page's custom code. `custom-code-script` is emitted once
  per affected block: site code without an output path, page code with the
  page's output file, so the finding names the affected object.
- **Feature flag review fixes (OD-047).** `FeatureFlagID` anchors its pattern
  with `\z`; `$` also matched before a final line break, so `"export.zip\n"`
  was accepted. Unapplied feature choices are a pending draft of the Settings
  window: `SettingsDraftNotice(…, featuresDirty:)` lists Advanced, and
  **Cancel Drafts** also cancels the feature draft.

## Not in this decision

- Saving a preferred export target or adapter settings in the project:
  OD-145 (recommended default: keep the target a per-export choice).
- One hashed runtime script (plan item E2, blocked: harness files unreadable).
- Publishing, domains, hosting and rollback (SF-1210, deferred by OD-042).

## Consequences

- No document schema, website metadata, clipboard, history or project-file
  change. Document schema 27, persisted history 4, website metadata 3.
- Two new `@Published` diagnostic properties; no UI shows them yet.

## Reversal

Remove the capability check from the two buttons and the writer guard (the
archive itself still refuses oversized plans), and drop the diagnostic
properties. The custom code and flag fixes should stay.
