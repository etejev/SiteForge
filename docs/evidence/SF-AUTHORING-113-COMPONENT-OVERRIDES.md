# SF-AUTHORING-113 — Stable component overrides and reconciliation

Status: source implemented; focused model coverage is reconciled, while UI and
the full gate remain blocked by the current macOS automation service.

Requirements: bounded `SF-0905-001`–`008`, supporting `SF-0901-003`–`008`,
`SF-0902-002`–`008`, `SF-0308-003/004/008`, and `SF-1204-004/006/008`.

## Delivered source behavior

- `ComponentOverridePathV1` derives one stable address from the canonical
  component-definition ID, source `NodeID`, and typed text/visibility property
  ID. The existing instance property and its stable `PropertyID` remain the
  sole serialized authored value; no UI or duplicate path store was added.
- `CanonicalComponentOverrides` produces one bounded immutable projection of
  inherited, authored, and conflicted values. An exposed-binding removal now
  preserves an authored instance value as an explicit missing-property
  conflict. Reusing the same property identity for a different definition
  source remains rejected so intent cannot be silently retargeted.
- The existing identity-gated `ComponentCommandRegistry` owns reset-one,
  reset-all-text, reset-all-visibility, and reset-all-component operations.
  Existing property IDs and ordinary command inverses preserve exact history;
  reset removes the authored property and reveals the definition default.
- Content Inspector controls expose explicit conflict recovery and accessible
  reset-all actions. Component Details reports authored override and conflict
  counts through the same immutable dependency index.
- Cross-project transfer now fails closed if any text or visibility override
  lacks a complete property-identity mapping. Static Build Diagnostics blocks
  unresolved component overrides with a redacted stable-node finding rather
  than emitting ambiguous output.

## Source tests added or updated

- `CommandKernelTests.testComponentOverridePathConflictPreservesIntentAndResetRestoresExactHistory`
- `CommandKernelTests.testComponentVisibilityStrictValidationStaleCancellationAndConflictRecovery`
- `CanvasRendererTests.testStaticBuildCompilerReportsRedactedComponentOverrideConflict`
- `SiteForgeLaunchTests.testComponentTextPropertiesTwoInstancesResetHistoryAndReopenJourney`
- `SiteForgeLaunchTests.testComponentVisibilityDefinitionInstanceResetAndReopenJourney`

These cover stable path/provenance, authored-value identity, conflict retention,
exact reset history, serialization, redacted output diagnostics, and native
reset-all controls. Their non-UI coverage was included in the reconciled model
run; actual-app journeys still require an authorized XCTest UI runner.

## Checks actually run

- Swift parser inspection of all affected production and test sources: passed.
- One universal macOS app build through `./sf dev`: passed for arm64 and x86_64.
- JSON/traceability, secret/path hygiene, and diff checks: recorded in the
  completion handoff after the documentation update.

The standalone architecture-boundary probe now compiles the actual headless
canonical dependency closure. Forbidden UI-framework imports remain checked
across every source file, and the architecture plus repository gates pass.

The authoritative gate reached repository/build and the 566-test non-UI target,
where three unrelated contract failures were corrected and passed exact 3/3
regressions. UI automation could not initialize and executed zero SiteForge
journeys, so no complete `./sf verify`, commit, push, or hosted run is claimed.

## Local owner-evaluation build

The repository-owned local-alpha packager was used in its explicit build-only
review mode because the owner testing pause prohibits the packager's normal
full verification gate. It produced
`.build/local-alpha/SiteForge-0.1.0-unsigned-alpha.zip` plus its portable
SHA-256 file. The checksum, archive paths, bundle structure, bundle identifier
`app.siteforge.SiteForge`, version `0.1.0` (build `1`), arm64/x86_64 executable,
ad-hoc signature, compiled `Assets.car`, `AppIcon.icns`, and approved AppIcon
v2 source/catalog all validated. The bundle contains only normal app metadata,
executables, compiled resources, and the ad-hoc signature; no project sources,
tests, recovery data, credentials, or private keys were found.

The prior `/Applications/SiteForge.app` was retained until the staged
replacement passed validation. The new local build is installed at
`/Applications/SiteForge.app`; one ordinary isolated launch succeeded and only
that review process was closed. Existing projects, preferences, recents, and
recovery data were not read or modified. This is an unsigned/ad-hoc local
development build, not notarized, publicly released, or eligible for the
disabled trusted-update path.

## Deferred scope

Media, enum, action and arbitrary style properties; slots; variants; nested
components; compatible replacement; bulk instance editing; remote libraries; collaboration; runtime
mutation; broad scale/accessibility/localization matrices; preview/export
parity beyond the explicit fail-closed compatibility finding; and release
acceptance remain deferred. The next bounded component slice should address
variant/property expansion only after the accumulated source-only gate runs.
