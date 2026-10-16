# SiteForge Codex Starter Kit

This folder is designed to become the root of the SiteForge Git repository.

## First use

1. Copy the contents into the SiteForge repository root.
2. Keep the specification files in `docs/`.
3. Initialize Git and create a private GitHub repository if desired.
4. Run `./sf status`.
5. Run `./sf next` to let Codex take one ready work item, or `./sf loop 3` for up to three verified iterations.

## Everyday commands

### Prompt-10 unattended testing (do not launch during the current testing pause)

Launch once with `./sf testing full` (or `./sf testing ui` for the complete UI
target only). It returns the run directory immediately. The independent local
collector attempts repository checks, one prepared build, code tests and UI
automation separately; a code-test failure does not suppress runnable UI tests.
No agent session or repeated polling is needed. Leave the Mac unlocked and
report completion to Codex after reading the persistent native progress window.

Reports live under `.codex-loop/full-verification/<run-id>/`: `REPORT.md`,
atomic `report.json`, `state.json`, `failures.json`, logs/events, authoritative
Xcode inventories and `.xcresult` bundles. Unknown totals are indeterminate;
blocked/failed/cancelled are not a pass. `active.json` prevents duplicate runs.
Closing the progress window does not stop testing; use its confirmed Cancel
Run action. `./sf verify` remains the direct synchronous gate used by scripts/CI.

The owner-local **regular SiteForge app** exposes Settings → Advanced → Testing.
Its installer provisions the development checkout and source fingerprint; no
website-project or source-folder chooser is required. Full Testing prepares and
runs both complete targets; UI Automation prepares and runs the full UI target.
Detached runs use a separate test-app identity and isolated website fixtures,
not the installed app or open documents. Closing Settings/app does not cancel.
Use explicit Cancel Testing. Open Progress, Open Latest Report and Reveal Logs
remain available after relaunch. Keep the Mac unlocked; legitimate Xcode/macOS
automation authorization may be required once.

Installed-app reports persist under the user's Application Support directory at
`SiteForge/TestingReports/<run-id>/`. CLI runs retain their repository-local
location above. Before repairing a report, compare its source revision and
fingerprint to the current checkout; never assume it belongs to current code.
Missing or changed provisioned source gives an explicit unavailable/blocked
report rather than running stale tests. Ordinary public distributions without
development resources do not claim to contain executable test targets.
The explicitly authorized owner-local packager is
`scripts/package-owner-local-app.sh --install`; it preserves the previous bundle
and refuses to replace a running installed app. It uses only local ad-hoc signing,
not distribution signing/notarization/publication.

```text
./sf dev
./sf verify
./sf watch
./sf next
./sf loop 5
./sf status
```

`./sf watch` continuously rebuilds and tests after source changes. `./sf loop` lets Codex edit the repository in bounded iterations. It stops for an owner decision, failed verification, an empty queue, or the requested iteration limit.

## Safety model

Codex receives workspace-write access, not unrestricted machine access. Repository instructions prohibit releases, signing, notarization, purchases, external publication, and credential handling without owner authorization.

The unsigned-alpha GitHub workflow creates a temporary workflow artifact only. It does not publish a GitHub Release.

