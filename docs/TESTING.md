# SiteForge Test Levels

SiteForge provides four local feedback levels. They change only which XCTest
cases `./sf test` selects; they never weaken the authoritative verification
gate.

| Command | Coverage | Intended use |
| --- | --- | --- |
| `./sf test quick` | Stable metadata and architecture smoke tests | Very fast feedback while editing documentation or tooling |
| `./sf test changed [base]` | Tests mapped to changed production/test files, with full-suite fallback for unknown or cross-cutting changes | Efficient feedback for a bounded implementation |
| `./sf test half` | The complete `SiteForgeTests` unit/integration target; UI tests are omitted | Broad logic validation before running UI journeys |
| `./sf test full` or `./sf test` | Every unit, integration, and UI test | Local acceptance and regression testing |

`changed` compares committed work with `origin/main` by default and also
includes staged, unstaged, and untracked paths. Pass another Git revision as
the optional base or set `SITEFORGE_TEST_BASE`. Mapping occurs at the
production-file/subsystem boundary rather than by parsing individual Swift
functions: this keeps renamed helpers, extensions, generated thunks, and
cross-file behavior from silently escaping coverage. Project changes, unknown
production files, and test-orchestration changes automatically escalate to
`full`.

`./sf verify` always runs repository checks, a clean build, and `full` tests.
CI invokes that same command. A passing narrower level is useful feedback, but
is not completion evidence for a queue item.

This bounded workflow evidence supports `SF-1902-007` and `SF-1902-008`.
