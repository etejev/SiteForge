# ADR-0037 — Custom head, CSS and body code

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-041 (approved by the owner 2026-11-26 1:30 PM EST)
- Requirements: SF-1107-001 … SF-1107-008

## Context

OD-041 allows site- and page-level custom HTML and CSS, clearly marked as
unvalidated, excluded from Preview by default, with no authored JavaScript
running in the editor.

## Decision

- `CustomCodeBlock` (`headHTML`, `bodyHTML`, `css`; exact keys) is stored in
  website metadata: `WebsiteMetadata.customCode` for every page and
  `PageWebsiteMetadata.customCode` for one page. Website metadata becomes
  version 3; versions 1 and 2 still decode with no custom code. Page custom
  code in a version 1 or 2 record is refused. The page key is written only
  when set and may not be null. Still document schema 27 (unreleased); a
  schema 26 file with custom code is refused.
- Text is kept exactly as typed (no trimming or Unicode normalization). A
  field is absent or non-blank, at most 64 KiB, without NUL. Head code may
  not contain `</head`, `<body`, `</body` or `</html`; body code may not
  contain `</body` or `</html`; CSS may not contain `</style` (any case), so
  it cannot end SiteForge's own markup early. Nothing else is checked.
- Editing goes through the existing Website Settings draft and
  `setWebsiteMetadata` command: one undoable transaction, persisted history,
  page removal removes the page's code in the same undoable step.
- Output (`CustomCodeOutput`, `MultiPageStaticBuildPlanner.plan(…,
  includesCustomCode:)`): site head HTML, page head HTML, then one
  `<style data-siteforge-custom-code>` with site CSS then page CSS, all after
  SiteForge's stylesheet link and before `</head>`; site then page body HTML
  just before `</body>`.
- `StaticBuildCompiler.compile(…, includesCustomCode:)` defaults to true
  (Check Website builds). Browser Preview passes false, so authored code never
  runs in Preview or in Export from Preview.
- Findings (no authored text): `custom-code-unvalidated` (warning),
  `custom-code-script` (warning, when HTML has `<script`, `javascript:` or an
  `on…=` attribute), `custom-code-excluded-from-preview` (information, Preview).
- UI: Website Settings → Website and each page gain a Custom Code section
  (Head HTML, CSS, End of body HTML; monospaced editors, notice, invalid and
  script notes). "custom-code" is no longer listed as a deferred capability.

## Consequences

- Custom code is the author's responsibility; it can break the built page.
- Preview and Export from Preview differ from a Check Website build when
  custom code exists; the information finding says so.

## Reversal

Stop emitting the code and hide the section; keep reading version 3 records.

## Amendment 1 — reviewed custom code and the release policy (Code Forge lane V17, 2026-11-26)

Status: Proposed, unverified (no compiler on the authoring machine). Scope:
OD-041 (custom code) with OD-042 / OD-120 (build settings and release policy,
ADR-0122). Document schema stays 27, WebsiteMetadata stays version 3,
persisted history stays schema 4, no new `CanonicalDocument` key.

**Problem.** Under the "Block Static Release on warnings" release policy
(`warnings-block-release`), `custom-code-unvalidated` (and `custom-code-script`)
are warnings that SiteForge can never clear, because custom code is never
checked. A project with custom code could therefore never be written with
Static Release under that policy unless the code was deleted.

**Decision.**

- The author can mark the custom code, exactly as it is now, as reviewed.
  `BuildProfileSettings` (inside `ProjectPreferences.build`, ADR-0122) gains the
  optional `reviewedCustomCodeDigest` (strict key, omitted when unset, null
  refused; `BuildProfileSettings.currentVersion` stays 1, so earlier files open
  unchanged). It stores only a SHA-256 (`CustomCodeReview.digest`) of the site
  block and every page block with its page identity, field by field with byte
  lengths — never the code.
- `CustomCodeReview.status(_:)`: `noCustomCode`, `notReviewed`, `reviewed`,
  `changedSinceReview`. The review counts only while the digest matches the
  current code, so any change to any block (including moving code to another
  field or page) ends it without rewriting the project.
- While reviewed, `custom-code-unvalidated` and `custom-code-script` are still
  reported (same codes, outputs and requirement IDs) but with severity
  `information`, and the explanation says the code is marked as reviewed. They
  therefore no longer count for `release-policy-warnings`. Unreviewed or
  changed code is a warning again (the explanation says when it changed after a
  review).
- Marking is an existing H03 repair action: `StaticBuildRepairAction`
  `.acknowledgeCustomCode(digest:)` ("Mark Custom Code as Reviewed", value-free
  identifier `acknowledge-custom-code`, accessibility hint) is offered beside an
  unreviewed `custom-code-unvalidated` finding of the current check.
  `WorkspaceShellState.buildRepairAction(for:)` passes the checked document's
  digest; `applyBuildRepair(_:)` refuses a digest that no longer matches
  (`stale-context`, status names the repair) and otherwise saves one undoable
  `document.projectPreferences.set` through `saveBuildSettings` (operation
  `review-custom-code`, setting identity `project.build.customCodeReview`,
  value-free `BuildSettingsDiagnostic`). Undo withdraws the review; Redo
  restores it.
- Check Website → Build settings shows the review state
  (`build.settings.customCodeReview`) and offers **Clear Custom Code Review**
  (`build.settings.customCodeReview.clear`, a draft like every other build
  setting). **Use SiteForge Defaults** resets the settings but keeps the review
  (`BuildProfileSettings.keepingCustomCodeReview`).
- Development and the default `errors-only` policy are unchanged: they were
  never blocked by custom code.

**Tests.** `SiteForgeTests/CanvasSettingsTests/testCustomCodeReviewUnblocksStrictStaticReleaseUntilTheCodeChanges`
(blocked without a review, allowed after, findings kept as information,
re-blocked when the code changes, stale review refused, no-change refused,
undo/redo, save and reopen, strict key, value-free diagnostics and findings).
Lane V14c added: `SiteForgeTests/CanvasSettingsTests/testProjectSettingsPaneKeepsGridDraftAcrossBuildSettingChanges`
(a review saved while a Settings → Project grid draft is pending rebases the
draft; the pane's Reset and Apply keep the review) and
`SiteForgeTests/ProjectPackageTests/testVersionComparisonMatchesByIdentitySeparatesMovesFromRecreationAndIsBounded`
(a review alone is compared as "Build settings").

**Consequences.** A reviewed project can be released under the stricter
policy; the information findings keep the custom code visible in every check.
The digest is project data (it is copied with the project, compared as
"Build settings" and restored with snapshots, like every build setting).

**Reversal.** Ignore `reviewedCustomCodeDigest` (report the findings as
warnings again); keep decoding the key.
