# ADR-0036 — App-scoped feature flags

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-047 (approved by the owner 2026-11-26 1:30 PM EST)
- Requirements: SF-1803-001 … SF-1803-008

## Context

OD-047 chose compile-time and launch-argument flags with an owner and removal
date per flag and no remote experimentation. SF-1803 also asks for a way to
disable a failing feature, and states that flags never fork persisted schema.

## Decision

- Flags are app-scoped, not project data. `FeatureFlagRegistry.definitions`
  is the single list. Each `FeatureFlagDefinition` has a typed
  `FeatureFlagID` (lowercase dotted, at most 64 bytes), title, summary,
  owner, introduced and remove-by dates (`FeatureFlagDate`, `yyyy-MM-dd`),
  default and requirement IDs.
- Resolution (`FeatureFlagResolver`): launch argument
  `-SiteForgeFeature.<id> YES|NO` (debug builds only, through
  `DebugTestComposition`) → this Mac's saved choice → SiteForge default.
- This Mac's choices are one versioned record, `SiteForgeFeatureFlags.v1` in
  UserDefaults (`FeatureFlagOverrides`, version 1, exact keys). Only explicit
  choices are stored, so omitted and explicitly-default are distinct. Valid
  unknown identifiers (another SiteForge version) are kept. A record that is
  not exactly version 1 is ignored with a visible finding; defaults apply and
  the next Apply replaces it.
- Settings → Advanced → Features: one toggle per flag with source, owner and
  removal date; Use Default per flag; Restore Defaults; draft with Cancel
  (also Escape) and Apply. Launch-argument flags are shown read-only.
- Drafts never change behavior; `isEnabled` reads committed state only.
- `FeatureFlagRegistry.issues(in:today:)` reports duplicates, missing
  title/owner/requirement, a removal date not after introduction, and expiry.
  A unit test runs it against the real date, so an expired flag fails the
  test until it is removed or renewed with a reason.
- Diagnostics: `FeatureFlagDiagnostic` (SF-1803-008: operation, flag
  identifiers, duration, failure category; no values).
- First flag: `export.zip-archive` (batch 15 zip export, default on, remove by
  2027-03-31). It hides Export Zip… and Build Zip Archive… when off.

## Rules for later flags

- A flag may gate UI and behavior only. It must not change what is written to
  a project file; schema changes still need their own migration.
- Remove the flag and its old path by the removal date.

## Consequences

- No document schema, clipboard, history or project-file change.
- The support report is unchanged (its key set is covered by tests this copy
  could not read); flag state is in the Settings pane and the diagnostic.

## Reversal

Delete the registry entry and the gate; delete the saved record key.
