# Deleted and renamed affected-test scope

Bounded SF-1902-007/008 support. The surrounding module status is unchanged.
The native Testing/monitor receipt remains in
[the monitor evidence](SF-TESTING-PROGRESS-MONITOR.md); this is a separate
focused correction, preserving the redesign full-gate receipt.

## Implementation and acceptance plan

Git paths are collected with NUL delimiters, deletion coverage and disabled
rename detection. Both old and new paths survive identical-byte renames across
committed, index, worktree and untracked changes. Sorting and deduplication are
deterministic; whitespace and missing-base fallback remain supported.
Root-aware mapping rejects deleted test files and missing mapped regression
suites. Unknown scope keeps the existing FULL sentinel, interpreted as an
unresolved request requiring explicit owner choice, never automatic full tests.

Filename classes remain coverage hints; no Swift parser was added. Every
requested class/method must match the fresh built inventory before any selected
case executes. A mixed valid/stale request blocks rather than silently dropping
the stale part. Executable selection contains exact surviving built methods.
The requested scope and any unresolved prefixes remain in the report.

Local CLI changed-scope requests open the native affected resolver with the
requested base. UI and CLI use the same selector script. An unresolved request
stays visible with disabled target Start actions and explicit recovery choices.
Hosted/headless CLI retains its line-based selection and refusal semantics.

A focused XCTest bridge runs maintained Python tooling fixtures from Regular
Testing. Its named log and JSON ledger retain every nested case, outcome,
duration and count. Those supplementary tooling counts do not replace or inflate
the authoritative XCTest inventory. Exported ledgers also appear in report.json
and REPORT.md. The collector prepares Git-listed tooling inputs beside the
products, records their source fingerprint and individual hashes, and supplies
the prepared location in the isolated test app's metadata. Hosted/direct XCTest
retains its checkout fallback. Source drift still blocks execution.

## Observations during verification

Native Start acceptance first created run `20261121-201952-d8cc0668`, with a
19-case inventory. Its isolated test host then requested Documents access while
reading the checkout. Native automation captured the exact prompt but stalled
on the click. The run was cancelled through its owned request, retaining partial
results and releasing the lock/test host before inputs changed. This was not a
passing receipt. Privacy settings were not reset or broadened.

The prepared-input change removes that direct checkout read from the local
fixture host. Replacement run `20261121-202910-d7eb6fff` prepared 57 files with
hashes and began through the real Start Regular Testing button. Native captures
confirm the unresolved affected preview and its explicit focused alternative.
Final check outcomes and installation identity are recorded below when observed.

Replacement run `20261121-202910-d7eb6fff` completed all 19 XCTest cases.
Eighteen passed, including the native custom-base/resolved/unresolved store
integration. The tooling wrapper failed because two old assertions still
expected broad-target execution and execution without inventory. Its exported
ledger retained 81/83 passing nested checks and both exact failures. Those
assertions now require complete exact built-method coverage and zero execution
when inventory is unavailable; they were strengthened rather than removed.

Replay `20261121-203521-9ce1ad51` passed its exact wrapper and all 84 nested
checks, including the actual sf plan CLI in a real Git fixture. That report
contains the raw log, exported ledger, input manifest, exact executable selector
and source fingerprint `9d4e72b07fed242dedf4dd2a6721dcb840e0604a1e863ac21fdfadff60e8ca48`.
The 18 unaffected passing native methods remain retained separately.

Final review identified the direct headless changed-scope bypass. Only that
mode now uses the existing inventory-validating backend with its viewer disabled.
Plan-only APIs, explicit focused/full hosted invocation, exit codes and shared
ownership remain intact. Added fixtures check routing, absence of a GUI viewer,
default bases and the impacted alias. Final focused replay is in progress.


## Verified result and installation

Final run `20261121-204414-92a7e8a0` passed its exact XCTest wrapper and
**87/87 nested tooling checks**, with zero failures or skips. Its source and
provision fingerprint match the installed candidate:
`8cdff9ffb3af7cffdeefd9d19c0e9be9ee94997f52e6379e5d4088b2c52933d6`.
The 18 unaffected passing native SupportSettings methods, including the real
custom-base store integration, are retained from `20261121-202910-d7eb6fff`.
The later changes only add headless routing and tooling regression expectations.
No broader/full-suite success is inferred.

The final nested ledger is
`attachments/code/0/` within the run's persistent report directory. `report.json`
links its exact file and embeds all named case results; REPORT.md gives its
separate 87-check count. `tooling-inputs.json` records the prepared source files
and hashes. Raw stage logs, fresh inventory, exact executionSelectors, the
xcresult bundle and exported log/ledger are retained alongside it. The primary
XCTest count remains 1/1 for this wrapper; nested checks are clearly separate.

Owner-local build 26.11.22 was refreshed with
`scripts/package-owner-local-app.sh --install`. Strict/deep app and strict helper
signatures pass. Installed Info.plist, harness provision and current source
fingerprints match; the collector bytes match. The previous bundle is preserved,
and no running app/document was terminated. The ignored
`.codex-loop/scope-selection/installed-receipt.json` records verification.

The installed normal `./sf test changed HEAD` opened review without creating
another run. Native input acceptance verified the requested HEAD base, actionable
unresolved explanation, disabled Regular/UI starts and available explicit Full
Verification choice. The owner may choose exact selectors intentionally. The
capture and XCTest receipt are under the ignored scope-selection evidence tree.
Whitespace/traceability checks pass. No active collector remains; no isolated
host Documents permission is now needed for these prepared tooling checks.
The earlier cancelled/failed receipts are retained without conversion to passes.

The original assessment's twelve checks were read as baseline evidence; no
OpenCode patch was integrated. All work remains local and uncommitted. The
approved native UI consistency review is the next bounded item.
