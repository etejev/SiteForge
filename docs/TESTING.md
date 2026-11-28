# SiteForge Test Levels

Before first verification, run `/bin/zsh scripts/setup-verification-runtime.sh`.
The declared Pillow version lives in ignored `.build/verification-python`, not
global Python. Both repository checking and unattended preflight validate this
isolated runtime and print that setup command if missing or outdated. The owner
app packager checks the same prerequisite before preparing its testing provision.

The two actual-browser integration tests also require Google Chrome:
`SiteForgeTests/SupportSettingsTests/testFlowRuntimeActualBrowserDeformationFallbacksAndLifecycle`
(Flow runtime, `Tests/Tooling/flow_runtime_browser.py`, run against the Static
Release site and its one content-hashed `siteforge-runtime.<sha256>.js`) and
`SiteForgeTests/TransformModelTests/testInteractionAndMotionRuntimesActualBrowserFocusTrapEscapePlacementAndReveal`
(interaction and motion runtimes, `Tests/Tooling/interaction_runtime_browser.py`,
run against Development output; it reuses the Flow harness's owned browser). Install
the official macOS app in Applications, or set `SITEFORGE_CHROME` to its executable
path in the test environment. Hosted core verification explicitly provisions this
dependency before testing. A missing or non-executable browser produces a failed
case ledger with installation guidance, never a skipped or successful result.
Each test first runs its harness's pure helper checks, which need no browser:
`/usr/bin/python3 Tests/Tooling/test_flow_runtime_browser.py` and
`/usr/bin/python3 Tests/Tooling/test_interaction_runtime_browser.py`.

For UI journeys that inspect responsive output, enable **Show features for web
developers** in Safari’s **Settings → Advanced** before starting local
verification. Those journeys use Safari’s native Develop menu to open
Responsive Design Mode.

Use focused verification for new behavior and changes that need regression
coverage. Review documentation and routine edits with the smallest check that
can establish correctness. Reserve full verification for major feature
updates, broad UI redesigns, and before an owner-requested commit or GitHub
push. A broad UI redesign runs the full native UI suite.
For routine work, choose explicit focused selectors when the changed-scope
mapping cannot identify an affected subsystem.

Local feedback levels prepare which XCTest cases the native Testing window
will run. Open **Settings → Advanced → Open Testing** directly, or use a CLI
request below to open the same window with a scope ready to review. Press
**Start Regular Testing** for code tests or **Start UI Testing** for native
journeys. The window starts on **Affected features**. Use **Exact selectors**
when the changed scope is unresolved. **Start UI Smoke Test** runs three
native journeys covering keyboard launch, the minimum-size editor and canvas
input. Use it early on changes that touch the editor. **Start Full
Verification** explicitly requests repository checks and both complete
targets. A CLI request does not automatically press Start.

| Command | Coverage | Intended use |
| --- | --- | --- |
| `./sf test quick` | Stable metadata and architecture smoke tests | Very fast feedback while editing documentation or tooling |
| `./sf test focused <XCTest selector> [selector...]` | The exact named XCTest cases | Routine checks for a new or changed behavior |
| `./sf test changed [base]` | Tests mapped to changed production/test files; unresolved scope requires explicit selectors or full verification | Efficient feedback for a bounded implementation |
| `./sf test half` | The complete `SiteForgeTests` unit/integration target; UI tests are omitted | Broad logic validation before running UI journeys |
| `./sf test full` or `./sf test` | Every unit, integration, and UI test | Local acceptance and regression testing |

`changed` compares committed work with `origin/main` by default and also
includes staged, unstaged, and untracked paths. Pass another Git revision as
the optional base or set `SITEFORGE_TEST_BASE`. Mapping occurs at the
production-file/subsystem boundary rather than by parsing individual Swift
functions: this keeps renamed helpers, extensions, generated thunks, and
cross-file behavior from silently escaping coverage. Project changes, unknown
production files, and test-orchestration changes stop with guidance to choose
explicit focused selectors or intentionally run `./sf verify`; they never
automatically start the full suite.

On the Mac, `./sf verify` opens the native Testing window. **Start Full
Verification** runs repository checks, a test build and both suites for the
provisioned source fingerprint. Prefer focused selectors for bounded changes.
Hosted and headless verification retain their direct path.

Changed-path collection includes deletion and both sides of identical-content
renames, using NUL-delimited Git paths. Deleted suites never become executable
hints. Current class hints and mapped methods must resolve against freshly built
products before any selected case runs. Missing/renamed-away requests block the
whole selected execution; they never silently disappear. GUI `changed`/`impacted`
requests use the same native resolver and requested base. Headless changed-scope
execution uses the existing backend without a viewer and with the same built
inventory validation. Explicit full hosted verification remains unchanged.

For focused tooling regression, prepare
`SiteForgeTests/SupportSettingsTests/testAffectedScopeToolingGitAndInventoryRegressions`
in Testing and press Start Regular Testing. This single XCTest wrapper attaches
an exact nested tooling ledger and raw log. Those supplementary counts are
separate from the built XCTest inventory and included in the persistent report.
Its input files are copied with hashes beside the products, so the isolated test
host does not need direct checkout-folder access. Hosted/direct XCTest remains
supported through the normal checkout fallback.

This bounded workflow evidence supports `SF-1902-007` and `SF-1902-008`.

After Start, a small floating native progress monitor follows the detached
collector while the main Testing window can close safely. Preparation shows
the current operation and real compiler activity. Its animated bar represents
activity until exact methods are enumerated from freshly prepared products.
Case counts never come from history. Unexpected inventory retains confirmed
completions and withholds a misleading total. Labelled estimates use compatible
measured preparation timings and durations matched to the current inventory;
a first run without evidence explicitly shows an unavailable estimate.

Pause checkpoints terminal XCTest results and releases the owned test app
and runner before displaying Paused. Resume executes only unresolved methods
against the same products, with a separate result bundle per segment. Earlier
failures remain failures. Cancel asks for confirmation and also works while
paused. The summary remains until dismissed or a newer run replaces it.

The local collector enables XCTest's per-case timeouts. The existing scale
assertions still enforce their original performance budgets. The affected
scale cases stop after a failed assertion and have hard limits of one to
three minutes, depending on their fixtures. A passing full run still covers
all fixtures and both targets. The local collector builds for the Mac's
current test architecture.

The Testing window, floating monitor, installed app, developer launches and
CLI share reports and run ownership under
`~/Library/Application Support/SiteForge/TestingReports`.
Only one desktop collector may run at once. Reopen Testing to reconnect to an
active run or select retained history, **Open Report**, or **Reveal Logs**.
Reports include scope, source/harness fingerprints, timestamps, raw logs,
events, actual inventories, failure summaries, continuation result bundles and
exported screenshots. Tell Codex testing finished; it can read this directory
and compare the receipt with current source without pasted logs.

The owner-local app must be provisioned for the current checkout. Stale source,
unavailable tools or denied macOS checkout-folder access produce a retained
blocked report without launching test targets. If macOS requests Documents
access for this checkout, allow **SiteForge** access. Ad-hoc rebuilt local
candidates can prompt again. Opening or closing a viewer never abandons the
collector's existing partial results.

Hosted CI and SSH/headless commands retain direct testing without the GUI;
`SITEFORGE_TEST_MONITOR=0` selects that internal path for tooling harnesses.
Normal local CLI requests require the installed Testing window and report an
opening failure without silently starting tests elsewhere. The detached
backend still supports full/UI callers and code-only scopes.

`./sf watch` builds when sources change. It does not run tests automatically.
Choose a focused test command when the edit is ready for verification.
