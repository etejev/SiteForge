# Local unattended testing and experimental Settings

Historical experimental direction is superseded by the owner's regular-app
Advanced delivery. See `SF-LOCAL-TESTING-002-OWNER-LOCAL.md` for current provisioning,
process ownership, reports and actual focused results. Preserve old reports;
do not create another experimental installation or restore workspace selection.

## Prompt-10 preparation — 2026-10-13

All accumulated app/test targets built successfully. Preparation fixed a typed
container-gap expression and an invalid call to private page validation while
preserving duplicate-identity rejection. Thirteen focused collector tests pass,
including actual-Xcode enumeration shape, duplicate ownership, continuation,
blocked build/preflight, cancellation, UI-only skip and retained failure reports.
The two ordinary Settings build/preference/resource-boundary tests pass 2/2;
the ordinary prepared bundle has no experimental testing resources. Native
experimental Settings/runtime/visual acceptance remains pending, not implied.

Actual Xcode tool discovery exposed an unsupported xcresult `--format` option
and a different enumeration `kind/name` tree. The collector now uses the actual
interfaces, retains export error logs, reconciles authoritative final counts,
records runtime warnings and writes `failed-selectors.json`. Prepared products
use a run-owned system-temporary DerivedData path to avoid source-folder Finder
metadata affecting test-build signing. No application was replaced or installed.
The native progress helper compiled successfully; no full/UI suite has run as
part of preparation. The single detached full launch is now recorded as run
`20261013-153433-e964329d`, under `.codex-loop/full-verification/`.
Collector PID 3870 and progress-owner PID 3871 were confirmed at launch. A
single later ownership read found the collector finished with exit 1 and its
process gone: build passed; repository/code failed; UI initialization timed out
enabling automation mode. Acceptance is pending owner-return repair, not passed.
No duplicate suite or ongoing agent monitoring is intended.

Owner add-on, not another development prompt. Counter remains 8/10.
Bounded supporting contract: SF-0206-001/003/004/005/006/008 and
SF-1607-004/006/008. No broader module acceptance is claimed.

## Source implementation

`./sf testing full|ui` starts one detached local collector and returns the
run directory. Direct `sf verify` remains synchronous and unchanged. Stages are
preflight, repository checks, one build-for-testing, code target and UI target.
The same prepared build feeds both targets. A failed runnable stage does not
suppress the next independent target; unavailable prerequisites are blocked.
No model call, repair loop, retry loop or agent watcher is involved.

Xcode test enumeration defines known totals; XCTest completion events define
running counts; authoritative xcresult summaries correct final counts. Unknown
totals remain indeterminate. Atomic state and final reports distinguish waiting,
running, passed, failed, blocked, cancelled and UI-only skipped stages. No-test
success without completion evidence becomes blocked, not a false pass.

Each ignored run retains revision/dirty content fingerprint, toolchain, times,
logs/events, inventories, summaries, failures and xcresult bundles. Exclusive
workspace lock prevents duplicate launch. Cancellation is explicit/confirmed and
signals only freshly created collector child process groups. Standard installed
SiteForge is never terminated; when process enumeration is available, an open
ordinary app blocks testing until safely closed. Scoped caffeinate ends with the
collector. Fixture cleanup uses only the established repository fixture directory.

Native progress has two truthful sections, never requests activation or app
attention, uses ordinary window level, does not close at completion and does
not cancel when closed. Position is lower-left; original-resolution placement
and interference review remain pending, not assumed safe from source alone.
Closing the final window terminates only the progress helper, not the detached
collector; Open Progress can create a fresh viewer for the same retained run.

Settings → Defaults exposes an off-by-default app-local Experimental Options
preference. Testing destination/launcher implementation is compiled only under
`SITEFORGE_EXPERIMENTAL`. Runtime also requires the explicit experimental bundle
marker/identity and preference. Official packaging rejects experimental resources.
A stale preference cannot create a route in a nonexperimental binary. Disabling
the preference repairs Testing selection to Defaults.

The Testing pane chooses a trusted repository via native folder panel/bookmark,
validates fixed workspace files, runs fixed collector modes (no arbitrary shell
input), and exposes status, Open Progress and Reveal Report. Bundled collector
and compiled helper work independently of the source script location. The
experimental controller uses a distinct bundle ID; tests prepare the ordinary
app in unique DerivedData, protecting controller documents and unsaved state.
All paths/preferences/bookmarks/report state are local, never canonical content.

## Written acceptance — unrun

`Tests/Tooling/test_unattended_verification.py`:

- test_completed_event_is_a_completion_not_a_start
- test_authoritative_inventory_is_target_scoped_and_deduplicated
- test_failed_blocked_and_cancelled_are_never_success
- test_state_is_atomic_and_unknown_inventory_remains_unknown
- test_failure_does_not_cancel_an_independent_stage
- test_confirmed_cancellation_targets_only_the_new_child_process_group

`SupportSettingsTests`:

- testExperimentalTestingRequiresBuildPreferenceAndResources
- testOrdinaryDistributionHasNoTestingDestinationEvenWithStalePreference
- Experimental-only: testTestingWorkspaceValidationDoesNotAcceptAnArbitraryFolder

Prompt 10 must additionally exercise actual duplicate launches, unavailable host,
failed/blocked stage continuation, final report completeness, reopen progress,
preference selection repair, Settings launch and official bundle exclusion.
No testing collector or test suite has run for this add-on.

## Build/install evidence

An explicit experimental app/helper build is authorized independently of the
test pause. Initial compilation exposed a private selection projection used by
the native organization Inspector; it is now a shared read-only projection, not
a canonical write path. Packaging exposed generated Finder metadata at signing;
the experimental script disables automatic signing, packages a metadata-free
copy in a unique temporary directory outside the source folder, then applies a
local ad-hoc signature. Only that generated temporary directory is cleaned.
No distribution
certificate, signing service, notarization, release or GitHub operation is used.
The final universal arm64/x86_64 app build and local native progress-helper
compilation passed. The experimental bundle was installed alongside the normal
app in the Applications folder, with ID `app.siteforge.SiteForge.Experimental`,
explicit experimental marker and bundled collector/progress executable. Normal
`app.siteforge.SiteForge` was left unchanged; no existing installation was
overwritten and no application was terminated. Non-test bundle inspection
confirmed identity, marker, resources and universal app executable. The app
was not launched or UI-automated; no functional/visual/test pass is implied.
The final refreshed installation preserves the previous experimental build as
an Applications-folder backup. Its inspected signature is ad-hoc, with no Team
Identifier. Final process inspection found no SiteForge app or xcodebuild process.

Run logs/results may contain local developer paths and test diagnostics. They
are ignored local evidence, not canonical project content or public support
exports. Review/redact before sharing. If an external process crash leaves an
exclusive lock, inspect its PID/report ownership before manual recovery; the
launcher does not guess a stale process or kill another session.
