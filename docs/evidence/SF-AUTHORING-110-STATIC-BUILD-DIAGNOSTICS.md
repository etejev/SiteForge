# SF-AUTHORING-110 — Closed static build diagnostics

Verification checkpoint (2026-10-08): repository/build gates and the complete
non-UI target ran; corrected static-output coverage is green. The actual-app
journey remains unexecuted because XCTest timed out during runner initialization.

## Scope

This source-only slice advances bounded portions of `SF-1204-001`–`008`,
`SF-1206-001`–`008`, `SF-1208-001`–`008`, and `SF-1211-001`–`008` without
introducing arbitrary CSS, JavaScript, publishing, credentials, or a second
document/output model. The normative modules remain **Partial**.

## Delivered source contract

- `StaticBuildCompiler` captures one immutable canonical document revision,
  resolves the existing closed HTML/CSS projection, exports only referenced
  verified image resources under content-addressed names, and returns a typed
  compatibility result before any write.
- Development and Static Release are explicit versioned, scene-local profiles.
  Ordering and integrity digests are deterministic; the release profile only
  performs closed exact-line CSS deduplication rather than semantic rewriting.
- `LocalStaticBuildWriter` contains every relative output path, stages text and
  binary files beside the chosen destination, rejects stale/cancelled/unsafe
  work, and replaces an existing user-confirmed destination without retaining
  a backup artifact.
- Build Diagnostics is a native sheet reached from the Build menu. It exposes
  profile, preflight, cancellation, compatibility findings, safe node reveal,
  a content-free copyable summary, and an explicit native destination panel.
- Missing, corrupt, unsupported, policy-blocked, cancelled, stale, permission,
  and space failures are closed typed states. Diagnostics include stable
  categories and sanitized identifiers, never source values, local paths,
  original filenames, resource bytes, or credentials.
- Compilation and writes run through an actor; request identity plus document
  revision prevent stale adoption. Build profile and result UI remain
  noncanonical and create no document history.

## Source evidence

- `SiteForge/CanvasRendererCore.swift`: `StaticBuildCompiler`,
  `LocalBuildProfileCompiler`, `LocalStaticBuildWriter`.
- `SiteForge/WorkspaceShellModel.swift`: `StaticBuildWorker` and scene-owned
  preflight/write lifecycle.
- `SiteForge/WorkspaceShellView.swift`: `StaticBuildDiagnosticsView` and native
  Build commands.
- `SiteForge/DiagnosticSupport.swift`: the `static-build` identifier domain.

## Added test source (not executed under the owner testing pause)

- `CanvasRendererTests.testStaticBuildCompilerProfilesAreDeterministicRedactedAndCancellationNeutral`
- `CanvasRendererTests.testStaticBuildCompilerExportsOnlyReferencedVerifiedAssetsAndWriterContainsPaths`
- `SiteForgeLaunchTests.testStaticBuildDiagnosticsPreflightProfileCancelAndAccessibilityJourney`

Swift parser inspection passed for all affected production and test sources.
One universal arm64/x86_64 app build passed. XCTest and `./sf verify` were not
run and are not claimed.

## Deferred scope

User-authored CSS/JavaScript, arbitrary code, remote services, domains,
uploads, deployment, hosting/CDN integration, credentials, signing,
minification beyond closed lossless CSS-line deduplication, broad browser and
assistive-technology matrices, export certification, performance budgets, and
release acceptance remain deferred.
