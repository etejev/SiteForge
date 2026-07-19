# Milestone 0 and Authoring Runway Audit

- Audit date: 2026-07-19
- Audit branch: `audit/foundation-and-authoring-runway`
- Audited commit: `b16111dc0268f7aa3dbc7450de2d7d2f9d8ad668`
- Scope: Foundation work through `SF-FOUNDATION-009`, the claimed authoring architecture runway, source, tests, build/verification tooling, implementation records, open decisions, and ADRs
- Review mode: read-only production review; this report and correction queue entries are the only repository changes

## Executive assessment

Overall confidence is **low for the Milestone 0 exit claim, moderate for the bounded canonical-model/package/history foundation, and not yet established for Milestone 1 architecture**.

The repository builds and all 101 tests pass, and several core areas have strong adversarial tests. That green result does not prove the milestone boundary. Four confirmed P0 data-integrity paths can discard or overwrite user data, lifecycle concurrency has untested stale-result races, current-schema and file-access claims exceed the implementation, and the required `SF-AUTHORING-000` prototypes/benchmarks/ADRs do not exist. Production Milestone 1 implementation should not proceed yet.

## Repository and branch gate

- The initial working tree on `main` was clean. `git status --short --branch` reported no tracked or untracked changes.
- `main` and the audit branch point to `b16111d` (`Complete SF-FOUNDATION-009 native materials`). Local `main` was four commits ahead of `origin/main`; nothing was pushed.
- The committed Foundation implementation is present in `188a69d` and `b16111d`. The latter contains the 15 reviewed `SF-FOUNDATION-009` files.
- No generated build product, Derived Data, `xcuserdata`, certificate, provisioning profile, private key, developer-machine absolute path, or distribution-signing configuration is tracked. Debug uses credential-free ad-hoc identity; Release signing is disabled (`SiteForge.xcodeproj/project.pbxproj:231-238`).
- Because the tree was clean, switching branches could not lose local files. The local branch `audit/foundation-and-authoring-runway` was created and checked out safely.
- The premise that architecture-runway work was completed is not supported. No branch history, `SF-AUTHORING-000` entry, prototype, benchmark harness/result, OD-004/OD-011 record, or canvas/layout ADR exists. The current branch therefore contains the completed Foundation work, but no completed authoring-runway work.

## Method

Nine independent specialist passes reviewed:

1. specification and requirement traceability;
2. architecture and module boundaries;
3. canonical model, transactions, undo/redo, persistence, migration, autosave, and recovery;
4. Swift concurrency, actor isolation, cancellation, stale results, and main-thread responsiveness;
5. native macOS UX, keyboard, VoiceOver, appearance, visual states, and interaction consistency;
6. security, privacy, paths, diagnostics, signing boundaries, and repository hygiene;
7. unit, integration, UI, accessibility, migration, performance, and regression-test quality;
8. canvas/layout architecture and OD-004/OD-011;
9. maintainability, duplication, dead code, fragile assumptions, and technical debt.

The synthesis independently inspected the cited source/test bodies, Git history and tracked files, scheme/build settings, status records, ADRs, requirement text, test-result hierarchy, performance-fixture construction, and visual-evidence retention. No test was found that reads or pattern-matches production source text.

## Verification and evidence reconciliation

Baseline `./sf verify` passed repository checks, build, and both test targets on this branch before documentation changes.

| Evidence | Actual result |
|---|---|
| Executed tests | 101 passed; 0 failed; 0 skipped |
| Unit/integration target | 88 passed |
| UI target | 13 passed |
| Source test-method inventory | 88 unit/integration + 13 UI |
| Environment recorded by XCTest | arm64 MacBook Air, macOS 27.0 build 26A5378n, Xcode/macOS SDK 27.0 |
| Documented totals | 88 unit + 13 UI; totals match execution |
| Reproducible authoring-runway benchmarks | None present |
| Retained visual-inspection record | None; screenshots exist only as transient XCTest attachments |

The executed totals are accurate. The discrepancy is evidentiary scope: passing metadata, policy, preview-state, and fixture-construction tests are cited as proof of broader behavioral, accessibility, visual, and rendering-performance requirements that they do not exercise.

## Findings summary

| Severity | Count | Boundary consequence |
|---|---:|---|
| P0 | 4 | Immediate current/other-file data-loss paths |
| P1 | 10 | Release-blocking lifecycle, persistence, security, traceability, performance, and architecture gaps |
| P2 | 14 | Important evidence, accessibility, maintainability, scale, and recovery weaknesses |
| P3 | 2 | Local duplication and fixture-hygiene improvements |

## P0 findings

### M0-P0-01 — New, Open, and Revert can silently discard modified work

- **Severity:** P0
- **Evidence:** File commands invoke replacement directly (`SiteForge/WorkspaceShellView.swift:546-565`). New establishes a fresh baseline and clears lifecycle state (`SiteForge/DocumentLifecycle.swift:257-268`); Open adopts the incoming baseline (`SiteForge/DocumentLifecycle.swift:271-289`); Revert delegates to Open (`SiteForge/DocumentLifecycle.swift:329-332`). Only Close checks `isModified` (`SiteForge/DocumentLifecycle.swift:356-360`). Untitled documents also have no recovery autosave (`SiteForge/DocumentLifecycle.swift:386-393`).
- **Affected requirements:** `SF-0203-004`, `SF-0203-005`, `SF-0203-006`, `SF-0301-004`, `SF-0301-005`, `SF-0301-006`, `SF-0306-004`, `SF-0306-005`, `SF-0306-006`.
- **Reproduction/verification:** Create or open a project, make a command mutation, then use Command-N, successfully Open another project, or Revert to Saved. No Save/Discard/Cancel decision occurs and the prior canonical/history state is replaced.
- **Why it matters:** An untitled project can be irretrievably lost; saved-project edits can also be lost before a recovery write.
- **Bounded correction:** Route every document replacement through one native Save/Discard/Cancel boundary; preserve state on cancellation/failure and give Revert explicit destructive confirmation.
- **Tests required:** Unit and UI matrices for modified New/Open/Revert/Close across Save, Discard, Cancel, panel cancellation, save failure, keyboard shortcuts, VoiceOver focus, and exact unchanged state.

### M0-P0-02 — Open can adopt bytes A while recording the fingerprint of bytes B

- **Severity:** P0
- **Evidence:** The package is read at `SiteForge/DocumentLifecycle.swift:94`, then the same path is reopened for fingerprinting at `SiteForge/DocumentLifecycle.swift:97` and `163-169`; package bytes are separately read at `SiteForge/ProjectPackage.swift:264-275`. There is no shared file descriptor/object identity.
- **Affected requirements:** `SF-0301-004`, `SF-0301-005`, `SF-0306-003`, `SF-0306-004`, `SF-1504-004`, `SF-1702-004`.
- **Reproduction/verification:** Pause after package read, replace the source with another valid package, and resume fingerprinting. SiteForge adopts A with B's fingerprint; a later Save sees B as expected and can overwrite it without conflict.
- **Why it matters:** A concurrent external valid version can be silently destroyed by a later SiteForge save.
- **Bounded correction:** Return validated package bytes, digest, metadata, and file identity from one bounded read snapshot; never fingerprint by reopening the path.
- **Tests required:** Barrier-controlled replace/delete/recreate during read, with exact document/fingerprint identity and preservation of both in-memory and disk state.

### M0-P0-03 — External modifications can be overwritten between conflict check and rename

- **Severity:** P0
- **Evidence:** Expected fingerprint is checked at `SiteForge/DocumentLifecycle.swift:122-125`, followed by awaited history/package work at `129-134`. The destination is unconditionally replaced later by `rename` at `SiteForge/ProjectPackage.swift:240-254`. The existing conflict test modifies the file only before Save begins (`Tests/SiteForgeTests/DocumentLifecycleTests.swift:57-71`).
- **Affected requirements:** `SF-0301-004`, `SF-0301-005`, `SF-0306-003`, `SF-0306-004`, `SF-1504-004`.
- **Reproduction/verification:** Insert a barrier after fingerprint validation, externally replace the destination, then release the write. The external bytes are overwritten.
- **Why it matters:** This directly contradicts ADR-0002's stated external-change guarantee and can lose another process's valid edits.
- **Bounded correction:** Coordinate expected-object/content validation and replacement as one commit operation, using stable file identity and a final precommit condition.
- **Tests required:** Deterministic concurrent replacement, deletion, recreation, and same-path/new-inode cases; typed conflict and byte-for-byte external-data preservation.

### M0-P0-04 — Predictable recovery-sidecar handling can overwrite or delete an unrelated file

- **Severity:** P0
- **Evidence:** Recovery uses sibling `.<project filename>.recovery` (`SiteForge/DocumentLifecycle.swift:150-152`). Autosave writes there without ownership proof (`396-410`). Successful Save removes that path unconditionally when clean (`323`), and recovery discovery removes valid-but-mismatched/non-newer content (`415-425`).
- **Affected requirements:** `SF-0301-004`, `SF-0306-004`, `SF-1504-004`, `SF-1603-004`, `SF-1702-004`.
- **Reproduction/verification:** Place a sentinel at `.Project.siteforge.recovery`, then save `Project.siteforge`; cleanup removes the sentinel. Autosave can replace a writable sentinel at the same name.
- **Why it matters:** Saving one project can destroy a file SiteForge did not create.
- **Bounded correction:** Use app-owned recovery storage keyed by stable project identity, or require strong ownership metadata and preserve every unowned/mismatched artifact.
- **Tests required:** Sentinel preservation, malformed/mismatched sidecars, collision handling, exclusive ownership creation, and cleanup of only proven SiteForge artifacts.

## P1 findings

### M0-P1-01 — Document switches do not invalidate in-flight save/autosave completions

- **Severity:** P1
- **Evidence:** Generation advances only for writes (`SiteForge/DocumentLifecycle.swift:305-319`, `396-410`). New/Open/Restore change active document/project state without advancing a lifecycle epoch (`257-289`, `336-348`). A delayed Save can then apply old project, URL, fingerprint, name, and phase at `319-324`. New/Open remain available during saving (`SiteForge/WorkspaceShellView.swift:546-562`).
- **Affected requirements:** `SF-0301-002`, `SF-0301-004`, `SF-0301-005`, `SF-0306-003`, `SF-0306-004`, `SF-0306-005`, `SF-1504-004`.
- **Reproduction/verification:** Delay Save for project A; New or Open B; allow A's save to complete. B's document may remain while lifecycle metadata is reattached to A.
- **Why it matters:** A subsequent Save can target the wrong project and corrupt lifecycle/history boundaries.
- **Bounded correction:** Use a lifecycle-wide epoch plus document/project/revision/destination identity on every async result; cancel/drain operations at all adoption boundaries.
- **Tests required:** Save/autosave crossed with New/Open/Revert/Restore/Close, asserting document, project, URL, fingerprint, phase, history, and disk coherence.

### M0-P1-02 — A pending autosave can supersede an explicit durable Save

- **Severity:** P1
- **Evidence:** Edits schedule autosave at `SiteForge/DocumentLifecycle.swift:380-393`; manual Save does not cancel/drain it (`305-324`). Both use the same generation stream and backend `newestGeneration` (`65`, `115-121`, `396-410`).
- **Affected requirements:** `SF-0301-005`, `SF-0306-003`, `SF-0306-004`, `SF-0306-005`.
- **Reproduction/verification:** With backend delay longer than 250 ms, edit then immediately Save. The later-waking autosave receives a newer generation and can cause the explicit Save to return `.conflict`.
- **Why it matters:** Ordinary Command-S timing can fail because recovery I/O is treated as newer durable user intent.
- **Bounded correction:** Cancel/drain pending autosave before manual Save and scope stale tokens by destination and operation intent.
- **Tests required:** Manual Save before/after debounce wake, simultaneous recovery/durable writes, edits during Save, failed autosave, and deterministic latest-revision durability.

### M0-P1-03 — Modified untitled documents have no crash-recovery path

- **Severity:** P1
- **Evidence:** New projects set `fileURL = nil` (`SiteForge/DocumentLifecycle.swift:257-268`), while autosave scheduling exits when `fileURL` is nil (`386-393`). Existing new-document coverage asserts clean state only (`Tests/SiteForgeTests/DocumentLifecycleTests.swift:14-22`).
- **Affected requirements:** `SF-0301-004`, `SF-0301-005`, `SF-0306-004`, `SF-0306-005`, `SF-1702-004`, `SF-1902-005`.
- **Reproduction/verification:** Create an untitled project, edit it, wait beyond debounce, and inspect recovery locations; no candidate is produced.
- **Why it matters:** A crash or forced termination before first Save loses all work.
- **Bounded correction:** Store untitled recovery under an app-owned location keyed by stable project identity and promote/clean it safely after first durable Save.
- **Tests required:** Untitled create/edit/relaunch/restore/discard, stale and malformed recovery, first-Save promotion, collision, and cleanup.

### M0-P1-04 — Current-schema decoding is permissive and maximum revisions can crash mutation

- **Severity:** P1
- **Evidence:** `DocumentPage.init(from:)` defaults missing route/role/provenance/roots (`SiteForge/DocumentModel.swift:205-224`) and `CanonicalDocument` replaces empty pages (`298-309`) regardless of envelope schema. Both schema 1 and 2 use the same decoder (`600-623`). Validation does not reserve `UInt64.max` (`428-455`), while commit performs trapping `revision + 1` (`SiteForge/CommandKernel.swift:659-675`).
- **Affected requirements:** `SF-0301-004`, `SF-0301-005`, `SF-0303-005`, `SF-0307-004`, `SF-1702-004`, `SF-1702-008`.
- **Reproduction/verification:** Open a schema-v2 payload missing current fields and observe silent legacy defaults; open revision `UInt64.max`, then execute a valid command and observe overflow trapping.
- **Why it matters:** Corrupt current data can be silently adopted/migrated, and a validly opened hostile package can make editing crash.
- **Bounded correction:** Use strict schema-specific DTOs and explicit migrations; reject non-incrementable revisions with typed compatibility/validation errors.
- **Tests required:** Missing v2 fields, empty/rootless v2, schema-v1 migrations, max/near-max revision, command rejection without trap, and unchanged state.

### M0-P1-05 — SF-1504 is marked Verified without its sandbox/security-scope implementation

- **Severity:** P1
- **Evidence:** The specification defines entitlements, bookmarks, file coordination/presentation, stale repair, and relocation (`docs/SiteForge-Specification.md:19544-19555`). The Xcode target has no sandbox entitlement file (`SiteForge.xcodeproj/project.pbxproj:231-238`); no security-scoped access, bookmark, `NSFileCoordinator`, or `NSFilePresenter` implementation exists. `staleSecurityScope` is only an injectable fault (`SiteForge/DocumentLifecycle.swift:59-77`, `154-160`). Nevertheless `docs/IMPLEMENTATION_STATUS.md:11` marks selected SF-1504 requirements Verified.
- **Affected requirements:** `SF-1504-001` through `SF-1504-008`, `SF-1603-004`.
- **Reproduction/verification:** Enable App Sandbox/user-selected file access and reopen after relaunch; access persistence and stale-bookmark repair do not exist. Current tests only inject an enum fault (`Tests/SiteForgeTests/DocumentLifecycleTests.swift:73-84`).
- **Why it matters:** A distributed sandboxed build cannot satisfy the claimed persistent-access behavior.
- **Bounded correction:** Reclassify status and introduce one file-access service owning scopes, bookmarks, coordination, relocation, and entitlements.
- **Tests required:** Entitlement inspection, panel-selected access, relaunch resolution, stale repair, balanced scope lifetime, coordination, relocation, denial, and redaction.

### M0-P1-06 — Filesystem no-follow and confidentiality-metadata protections are check-then-use or absent

- **Severity:** P1
- **Evidence:** Read checks with `lstat` (`SiteForge/ProjectPackage.swift:480-487`) then reopens by path (`264-274`). Write checks destination/ancestors (`489-514`) before a separate path-based staging write/rename (`240-254`). Staging uses plain `Data.write` and replacement does not preserve or enforce destination owner, mode, ACL, or approved xattrs (`240-254`). Tests cover static symlinks only (`Tests/SiteForgeTests/ProjectPackageTests.swift:217-239`).
- **Affected requirements:** `SF-0301-004`, `SF-1504-003`, `SF-1504-004`, `SF-1603-004`, `SF-1604-004`, `SF-1702-004`.
- **Reproduction/verification:** Swap a validated source/destination/ancestor to a symlink before use; separately save over a `0600`/ACL-protected destination and compare metadata.
- **Why it matters:** Local races can redirect I/O, and atomic replacement can broaden confidentiality or discard user security metadata.
- **Bounded correction:** Bind operations to opened directory/file descriptors with no-follow identity and apply an explicit secure creation/preservation policy at commit.
- **Tests required:** Source/destination/ancestor swaps, inode identity, hard-link policy, `0600`, ACL/xattr, owner mismatch, staging cleanup, and no external-target modification.

### M0-P1-07 — SF-AUTHORING-000, OD-004, and OD-011 evidence is absent

- **Severity:** P1
- **Evidence:** Before this audit the READY queue was empty; no `SF-AUTHORING-000` appeared. `docs/OPEN_DECISIONS.md:1-32` has no OD-004/OD-011 entry; ADRs end at ADR-0006. The specification requires OD-004 before Milestone 1 and OD-011 during architecture runway (`docs/SiteForge-Specification.md:26937`, `26944`) and requires every spike to end with evidence and a decision (`24008-24165`). No prototype, benchmark harness/result, layout oracle, HTML/CSS parity fixture, or renderer comparison exists.
- **Affected requirements:** `SF-1901-001` through `SF-1901-008`; downstream `SF-0401-001` through `SF-0401-008`, `SF-0407-001` through `SF-0407-008`, `SF-0501-001` through `SF-0501-008`, `SF-1903-001` through `SF-1903-008`.
- **Reproduction/verification:** Search repository and all local branches for the item/decision IDs, prototypes, raw results, or ADRs; none are present.
- **Why it matters:** Production canvas/layout work would make consequential technology and canonical-layout choices implicitly.
- **Bounded correction:** Complete the isolated measured runway, retain environment/commands/raw results, and write OD-004/OD-011 ADR outcomes before production authoring.
- **Tests required:** Coordinate, pan/zoom, render/hit test, overlay, accessibility, incremental update, deterministic layout, HTML/CSS/browser parity, memory, and main-thread benchmarks on 100/10,000 objects.

### M0-P1-08 — The decision-register namespace conflicts with the specification

- **Severity:** P1
- **Evidence:** The specification defines OD-001 as minimum macOS/reference hardware and OD-002 as persistence representation (`docs/SiteForge-Specification.md:26934-26935`). `docs/OPEN_DECISIONS.md:3-19` reuses OD-001 for publisher/bundle identity and OD-002 for distribution trust; `docs/PROJECT_STATUS.md:14` repeats those meanings. ADR-0001 does not identify itself as resolving specification OD-002.
- **Affected requirements:** `SF-1801-003`, `SF-1801-008`, `SF-1901-003`, `SF-1901-008`, `SF-2002-001`, `SF-2002-003`, `SF-2002-008`.
- **Reproduction/verification:** Compare the two decision registers by ID.
- **Why it matters:** An approval can be attributed to the wrong decision, while the real minimum-platform and persistence decisions appear resolved when they are not.
- **Bounded correction:** Restore one canonical ID namespace, preserve aliases/history, link ADRs to the correct IDs, and assign new IDs to publisher/distribution questions.
- **Tests required:** Documentation lint for duplicate/conflicting IDs, missing ADR resolution links, unknown requirement IDs, and due-but-unrecorded decisions.

### M0-P1-09 — Requirement and Milestone 0 status claims exceed implemented acceptance criteria

- **Severity:** P1
- **Evidence:** `docs/IMPLEMENTATION_STATUS.md:16` marks the whole foundation Verified. No implementation/evidence satisfies full `SF-1902-002`, `SF-1902-003`, or `SF-1902-007` acceptance (`docs/SiteForge-Specification.md:24233-24265`, `24318-24333`). `SF-0303-003` is marked Verified via defaults although no route-rule provenance/explanation surface exists (`SiteForge/WorkspaceShellView.swift:459` remains inspector placeholder). SF-1505/SF-1605 rows are cited for materials, while those modules require complete pointer-free operation/custom canvas semantics and accessible generated-site release gates (`docs/SiteForge-Specification.md:19729-19892`, `21059-21193`).
- **Affected requirements:** `SF-0303-003`, `SF-1505-006` through `SF-1505-008`, `SF-1605-002`, `SF-1605-006` through `SF-1605-008`, `SF-1902-002`, `SF-1902-003`, `SF-1902-007`, `SF-1902-008`.
- **Reproduction/verification:** Trace each claimed ID to behavioral source/test evidence and compare the full normative acceptance text.
- **Why it matters:** The milestone gate is reported green despite P0/P1 defects and missing mandatory paths.
- **Bounded correction:** Downgrade aggregate/requirement statuses to bounded Implemented/Partial, record exact uncovered criteria, and require named behavioral evidence before Verified.
- **Tests required:** Machine-readable requirement-to-test/artifact mapping and a gate that rejects completed/Verified claims without executable or retained evidence.

### M0-P1-10 — Performance is marked Verified without measuring the claimed behavior

- **Severity:** P1
- **Evidence:** The material test times 10,000-page construction and 10,000 pure policy resolutions (`Tests/SiteForgeTests/WorkspaceMaterialPolicyTests.swift:95-107`); the fixture is pages, not rendered objects (`SiteForge/WorkspaceShellModel.swift:111-133`); the UI test scrolls once with no time/frame/memory observation (`Tests/SiteForgeUITests/SiteForgeLaunchTests.swift:262-279`). The 100-page launch check is one wall-clock sample without warm-up, repetitions, percentile, or memory (`Tests/SiteForgeTests/LaunchExperienceTests.swift:204-218`). Status/queue records call this representative responsiveness/material rendering evidence.
- **Affected requirements:** `SF-0201-007`, `SF-0301-007`, `SF-1505-007`, `SF-1602-007`, `SF-1605-007` and corresponding `-008` evidence requirements.
- **Reproduction/verification:** Inspect or instrument the cited tests; no renderer, frame time, memory watermark, event-loop stall, or 10,000-object canvas workload participates.
- **Why it matters:** These tests cannot support release budgets or OD-011 technology selection.
- **Bounded correction:** Relabel them as fixture/policy smoke tests and add reproducible named-environment benchmarks with warm-up, repeated P50/P95, memory, frame/stall, and representative objects/assets.
- **Tests required:** 100/10,000-object render, update, hit-test, scroll, resize, material composition, accessibility-tree, main-thread, and memory benchmarks.

## P2 findings

### M0-P2-01 — Advertised cancelable stages do not check cancellation inside real parsing/history work

- **Severity:** P2
- **Evidence:** Package decode (`SiteForge/ProjectPackage.swift:264-275`) and history validation (`SiteForge/PersistedHistory.swift:136-245`) contain no cancellation checkpoints. Backend checks only before/after calls (`SiteForge/DocumentLifecycle.swift:91-102`), while those stages are labeled cancelable (`SiteForge/LaunchExperience.swift:13-31`). The test cancels during an artificial pre-read sleep (`Tests/SiteForgeTests/LaunchExperienceTests.swift:57-82`).
- **Affected requirements:** `SF-0201-004`, `SF-0301-004`, `SF-0301-007`, `SF-1602-004`, `SF-1602-007`.
- **Reproduction/verification:** Cancel after entering maximum-size decode/history validation; work continues until the synchronous stage returns.
- **Why it matters:** Adoption remains safe, but Cancel can appear unresponsive.
- **Bounded correction:** Add cooperative checkpoints to bounded loops and propagate cancellation distinctly from corruption.
- **Tests required:** Barrier cancellation inside container decode, canonical validation, and history validation with latency and no-adoption assertions.

### M0-P2-02 — Launch UI tests exercise preview states rather than real workflows

- **Severity:** P2
- **Evidence:** `launchScenario` injects `-SiteForgeLaunchScenario` (`Tests/SiteForgeUITests/SiteForgeLaunchTests.swift:24-42`). Progress/failure/recovery tests inspect fabricated states (`175-209`); preview Restore transitions to workspace without a real candidate (`SiteForge/LaunchExperience.swift:243-245`).
- **Affected requirements:** `SF-0201-004`, `SF-0201-006`, `SF-0301-004`, `SF-0301-006`, `SF-1602-004`, `SF-1602-006` and corresponding `-008` requirements.
- **Reproduction/verification:** Run the UI tests; no package is opened and no recovery bytes are restored.
- **Why it matters:** Coordinator/backend wiring, preservation, Retry, and focus transfer can fail while preview UI stays green.
- **Bounded correction:** Keep previews as visual fixtures but add repository-local end-to-end production-loader journeys.
- **Tests required:** Real open/cancel/noncancelable/malformed/incompatible/Retry/Restore/Discard flows and resulting canonical/lifecycle assertions.

### M0-P2-03 — Keyboard, VoiceOver, and visual-inspection evidence is incomplete and transient

- **Severity:** P2
- **Evidence:** Focus traversal stops at Pages → Layers → viewport (`Tests/SiteForgeUITests/SiteForgeLaunchTests.swift:126-142`); menu coverage uses a click and checks existence (`144-159`); appearance variants assert existence/hittability then attach screenshots (`240-259`). Announcement tests only check nonempty strings (`Tests/SiteForgeTests/LaunchExperienceTests.swift:144-169`) rather than the posted notification (`SiteForge/LaunchExperience.swift:455-463`). `sf:53-55` does not retain a stable result bundle or inspection manifest.
- **Affected requirements:** `SF-0201-006`, `SF-0301-006`, `SF-0303-006`, `SF-1505-006`, `SF-1602-006`, `SF-1605-006` and corresponding `-008` requirements.
- **Reproduction/verification:** Suppress announcements or reduce rendered contrast; most cited assertions still pass.
- **Why it matters:** Full Keyboard Access, VoiceOver announcements, inactive appearance, clipping, and contrast are not reproducibly proven.
- **Bounded correction:** Separate semantic automation from retained manual QA and record OS/settings/window/fixture/reviewer metadata.
- **Tests required:** Full forward/reverse traversal, shortcuts, Escape/default actions, focus restoration, announcement observer, roles/labels/values/actions, active/inactive and actual accessibility settings, clipping, and retained visual records.

### M0-P2-04 — Autosave coalescing is not asserted

- **Severity:** P2
- **Evidence:** The coalescing test performs two edits, sleeps, and checks only final recovery content (`Tests/SiteForgeTests/DocumentLifecycleTests.swift:87-105`). It never observes write count. Multiple recovery/history tests rely on fixed 600–650 ms sleeps.
- **Affected requirements:** `SF-0301-005`, `SF-0303-005`, `SF-0306-003`, `SF-0306-005`, `SF-0307-005`.
- **Reproduction/verification:** An implementation that writes both edits can still pass if the second wins.
- **Why it matters:** Excess writes amplify races and fixed sleeps create CI fragility.
- **Bounded correction:** Inject a controllable clock/debouncer and observing backend.
- **Tests required:** Exact write count/generation/revision for burst, separated, canceled, Save-racing, and document-switch cases without wall-clock sleeps.

### M0-P2-05 — Migration claims lack immutable golden packages and rootless coverage

- **Severity:** P2
- **Evidence:** The schema-v1 test synthesizes data through current helpers and covers only empty pages (`Tests/SiteForgeTests/ProjectPackageTests.swift:77-96`). No tracked historical `.siteforge` fixture exists, while queue/changelog claim empty and rootless migration and `SF-1702-008` requires golden readability.
- **Affected requirements:** `SF-0301-005`, `SF-0303-005`, `SF-0303-008`, `SF-1702-008`.
- **Reproduction/verification:** `git ls-files` finds no golden package; test search finds no nonempty rootless legacy package.
- **Why it matters:** Current encoder/test helpers can drift with the decoder and hide compatibility breaks.
- **Bounded correction:** Add tiny immutable schema-v1 golden bytes with provenance/checksum for empty and rootless documents.
- **Tests required:** Golden decode, deterministic IDs, save/reopen, invalid variants, history isolation, and fixture immutability.

### M0-P2-06 — All windows share one app-level document session

- **Severity:** P2
- **Evidence:** `SiteForgeApp` constructs one `WorkspaceShellState`/lifecycle and injects it into every `WindowGroup` window (`SiteForge/SiteForgeApp.swift:5-19`). Close helpers act on `NSApp.keyWindow` (`SiteForge/DocumentLifecycle.swift:370-377`).
- **Affected requirements:** `SF-0201-001`, `SF-0201-004`, `SF-0201-005`, `SF-0301-004`, `SF-0301-005`, `SF-1801-003`.
- **Reproduction/verification:** Open a second workspace window; both observe/mutate the same canonical session and lifecycle metadata.
- **Why it matters:** Multiwindow close/save/focus can target the wrong document as native document behavior expands.
- **Bounded correction:** Give each window/document scene an independently owned session/lifecycle and address close actions to its own window.
- **Tests required:** Two-window independent edit/save/close/recovery/focus/restoration tests.

### M0-P2-07 — Module boundaries and test seams are not enforceable

- **Severity:** P2
- **Evidence:** Every production file is in one app target (`SiteForge.xcodeproj/project.pbxproj:219-222`); no core/persistence target or dependency rule exists. `DocumentLifecycle.swift:1-457` mixes filesystem, history/package orchestration, diagnostics, testing faults, AppKit panels, and presentation. UI-test fixture/scenario/appearance arguments are compiled into normal product startup (`SiteForge/SiteForgeApp.swift:8-13`, `SiteForge/LaunchExperience.swift:145-192`, `SiteForge/WorkspaceMaterialPolicy.swift:93-145`).
- **Affected requirements:** `SF-1801-001` through `SF-1801-004`, `SF-1801-008`, `SF-1802-008`.
- **Reproduction/verification:** A headless model/persistence build cannot be made from existing targets; a Release app accepts synthetic scenario/fixture flags.
- **Why it matters:** Milestone 1 growth can couple UI to canonical/layout semantics, and tests can pass through behavior users never execute.
- **Bounded correction:** Establish acyclic Core/Commands/Persistence/App seams and an explicit Debug/test composition adapter ignored by Release.
- **Tests required:** Independent builds, forbidden-import/cycle checks, Release flag rejection, test injection, and app integration.

### M0-P2-08 — Standard page rows do not expose unique stable accessibility identifiers

- **Severity:** P2
- **Evidence:** Row identifiers use only `PageRole` (`SiteForge/WorkspaceShellView.swift:328-334`), so every standard page is `navigator.page.standard`.
- **Affected requirements:** `SF-0202-006`, `SF-0202-008`, `SF-0303-001`, `SF-0303-006`, `SF-0303-008`.
- **Reproduction/verification:** Create two standard pages or launch the large fixture and query `navigator.page.standard`; multiple elements match.
- **Why it matters:** Accessibility automation and future page-specific focus restoration/actions cannot target stable identity.
- **Bounded correction:** Include typed `PageID` in the identifier and expose role through label/value.
- **Tests required:** Multiple standard pages, unique/stable IDs through save/reopen, selection and arrow focus.

### M0-P2-09 — Lifecycle diagnostics omit declared recovery operations

- **Severity:** P2
- **Evidence:** `LifecycleOperation` declares revert/restore/discard (`SiteForge/DocumentLifecycle.swift:33`), but recording occurs only through backend read/write (`83-143`). Controller operations at `329-354` emit no matching record; diagnostic tests inspect save records only (`Tests/SiteForgeTests/DocumentLifecycleTests.swift:183-194`).
- **Affected requirements:** `SF-0301-008`, `SF-0306-008`, `SF-1504-008`, `SF-1607-008`.
- **Reproduction/verification:** Revert, Restore, or Discard, then inspect diagnostic records; no matching operation exists.
- **Why it matters:** Recovery auditability and taxonomy completeness are overstated.
- **Bounded correction:** Centralize exhaustive operation instrumentation.
- **Tests required:** Success/failure/cancellation/redaction for every operation and exhaustive enum coverage.

### M0-P2-10 — Lifecycle fingerprinting bypasses package size bounds

- **Severity:** P2
- **Evidence:** Package reads enforce 8 MiB (`SiteForge/ProjectPackage.swift:264-274`), but fingerprint uses unbounded `Data(contentsOf:)` (`SiteForge/DocumentLifecycle.swift:163-169`).
- **Affected requirements:** `SF-0301-004`, `SF-0301-007`, `SF-1504-004`, `SF-1504-007`, `SF-1603-004`, `SF-1603-007`.
- **Reproduction/verification:** Replace a destination with a very large/sparse regular file before fingerprinting.
- **Why it matters:** Hostile external input can cause disproportionate memory/CPU despite package limits.
- **Bounded correction:** Stream a bounded digest tied to validated file identity.
- **Tests required:** Oversized/sparse/swap-to-large cases, bounded memory, cancellation, unchanged state.

### M0-P2-11 — Repository secret scanning covers only a narrow legacy subset

- **Severity:** P2
- **Evidence:** `scripts/check-repository.sh:24-29` detects private-key headers, two Apple variables, and `ghp_` tokens, but not fine-grained GitHub tokens, other common token classes, `.env`/secret configs, or a maintained scanner. `.gitignore:1-16` has no `.env` policy.
- **Affected requirements:** `SF-1603-008`, `SF-1802-008`.
- **Reproduction/verification:** Test the regex with fake `github_pat_`, `gho_`, cloud-key, or `.env` fixtures; verification remains green.
- **Why it matters:** The mandatory hygiene gate can miss recognizable credentials.
- **Bounded correction:** Add a maintained scanner or broader tested patterns and secret-file policy with safe placeholders.
- **Tests required:** Positive/negative fake credentials, entropy cases, binary/doc exclusions, and CI enforcement.

### M0-P2-12 — Package v1 cannot represent the specification's large asset fixture

- **Severity:** P2
- **Evidence:** Package limits are 8 MiB total and 4 MiB/member (`SiteForge/ProjectPackage.swift:197-199`); ADR-0001 acknowledges resource scaling needs a new version/external design (`docs/architecture-decisions/ADR-0001-deterministic-project-package-container.md:42-46`). The performance fixture requires 10,000 nodes and 500 assets (`docs/SiteForge-Specification.md:26786-26795`), while the current large fixture has no representative assets (`SiteForge/WorkspaceShellModel.swift:121-132`).
- **Affected requirements:** `SF-0407-007`, `SF-0501-007`, `SF-1601-007`, `SF-1901-007`, `SF-1903-007`.
- **Reproduction/verification:** Attempt to persist a member over 4 MiB or representative 500-asset set over 8 MiB; it is rejected.
- **Why it matters:** Runway results without assets can understate decode, memory, invalidation, layout, and render cost.
- **Bounded correction:** Record this runway limitation and decide versioned/lazy resource storage before asset authoring; do not casually relax security bounds.
- **Tests required:** 500-asset fixtures, lazy/streamed access, migration, corruption/missing assets, atomic recovery, and memory.

### M0-P2-13 — Traceability tests duplicate metadata rather than prove acceptance

- **Severity:** P2
- **Evidence:** Requirement sets are copied into production types (`SiteForge/CommandKernel.swift:541`, `ProjectPackage.swift:192`, `DocumentLifecycle.swift:208`, `PersistedHistory.swift:108`, `LaunchExperience.swift:163`) and tests compare duplicated arrays (`Tests/SiteForgeTests/AppMetadataTests.swift:12-17`, `DocumentLifecycleTests.swift:14-22`, `WorkspaceMaterialPolicyTests.swift:109-115`).
- **Affected requirements:** `SF-1801-002`, `SF-1801-008`, `SF-2002-001`, `SF-2002-003`, `SF-2002-008` and the cited `-008` IDs.
- **Reproduction/verification:** Remove a behavior but retain its ID string; the exact-traceability test remains green.
- **Why it matters:** Metadata checks inflate coverage and drift across copies.
- **Bounded correction:** Maintain one machine-readable requirement-to-named-behavior/artifact index; keep metadata checks labeled as such.
- **Tests required:** Reject unknown IDs, missing/stale evidence, duplicate ownership, and completed requirements without behavioral proof.

### M0-P2-14 — Discard Recovery reports success even when deletion fails

- **Severity:** P2
- **Evidence:** `discardRecovery()` suppresses deletion errors, clears the candidate/failure, and marks clean (`SiteForge/DocumentLifecycle.swift:350-354`). Existing coverage tests only successful removal (`Tests/SiteForgeTests/DocumentLifecycleTests.swift:129-143`).
- **Affected requirements:** `SF-0301-004`, `SF-0306-004`, `SF-0306-006`, `SF-0306-008`.
- **Reproduction/verification:** Make the candidate undeletable or inject remove failure, then Discard; the UI reports clean although stale recovery remains.
- **Why it matters:** The same candidate can reappear and the user's explicit recovery choice is misrepresented.
- **Bounded correction:** Clear state only after owned-artifact deletion succeeds; otherwise show a typed actionable failure without losing candidate metadata.
- **Tests required:** Permission/I/O failure, retry, candidate retention, diagnostics, keyboard/VoiceOver status.

## P3 findings

### M0-P3-01 — Open-panel presentation is duplicated and one path is dead

- **Severity:** P3
- **Evidence:** `DocumentLifecycleController.presentOpenPanel()` exists at `SiteForge/DocumentLifecycle.swift:436-445`, while app commands use `LaunchExperienceController.presentOpenPanel()` (`SiteForge/LaunchExperience.swift:259-269`, `SiteForge/WorkspaceShellView.swift:549`).
- **Affected requirements:** `SF-0203-006`, `SF-0203-008`, `SF-1504-001`, `SF-1504-008`, `SF-1801-002`, `SF-1801-008`.
- **Reproduction/verification:** Search call sites; the lifecycle panel path has no caller.
- **Why it matters:** Type filtering, security scope, and cancellation behavior can diverge.
- **Bounded correction:** Own panel behavior in one file-access command adapter and remove the dead path.
- **Tests required:** Launch/menu/retry/keyboard Open all use the same adapter.

### M0-P3-02 — Test fixture infrastructure is duplicated and can leave unignored residue

- **Severity:** P3
- **Evidence:** Package tests use ignored `Tests/Fixtures/.tmp` (`Tests/SiteForgeTests/ProjectPackageTests.swift:10-21`), while lifecycle/launch/history create separate root-dot directories (`DocumentLifecycleTests.swift:206-213`, `LaunchExperienceTests.swift:8-18`, `PersistedHistoryTests.swift:8-19`) not covered by `.gitignore`; setup/cleanup uses suppressed errors.
- **Affected requirements:** `SF-1702-008`, `SF-1802-008`.
- **Reproduction/verification:** Terminate a test after fixture creation; root residue can remain untracked.
- **Why it matters:** It weakens clean-checkout reproducibility and can hide teardown failures.
- **Bounded correction:** Use one throwing per-test fixture helper under the ignored fixture root.
- **Tests required:** Parallel isolation, setup failure propagation, crash residue detection/cleanup, post-suite clean-tree check.

## Areas with strong supporting evidence

- **Canonical model and transactions:** Typed stable document/page/node/property identifiers, parent/child ownership validation, draft validation before commit, rollback, inverse correctness, undo/redo ordering, branch invalidation, deterministic serialization, and diagnostic redaction are behaviorally tested (`Tests/SiteForgeTests/CommandKernelTests.swift:87-325`).
- **Bounded package parser:** Deterministic bytes, atomic pre-replacement interruption, opaque-member preservation, missing/corrupt/incompatible members, traversal names, duplicates, size bounds, static symlink rejection, integrity, unchanged state, and redaction have unusually broad adversarial tests (`Tests/SiteForgeTests/ProjectPackageTests.swift:41-285`). The race/ownership findings above are outside those tests.
- **Persisted history:** Save/reopen undo and redo ordering, branch invalidation, recovery boundaries, missing/corrupt/oversized/reordered/mismatched history isolation, retention, deterministic bytes, and canonical-document survival are exercised (`Tests/SiteForgeTests/PersistedHistoryTests.swift:37-280`).
- **Blank baseline:** Exact Home/Not Found defaults, stable IDs, nonempty/unique-route invariants, minimum roots, template distinction, clean history baseline, and deterministic round trip are directly tested (`Tests/SiteForgeTests/BlankProjectTests.swift:6-119`).
- **Native shell evidence:** The running UI test proves approved page order/labels/selection/arrow focus (`Tests/SiteForgeUITests/SiteForgeLaunchTests.swift:86-104`) and material pass-through hit testing by clicking the canvas through chrome (`219-238`).
- **Concurrency structure:** Swift 6 strict concurrency is enabled; persistence/history/lifecycle backends are actors and UI coordinators are main-actor isolated. Launch progress/result callbacks reject mismatched operation IDs. The findings concern semantic operation identity and race windows, not compile-time actor violations.
- **Appearance architecture:** `WorkspaceMaterialPolicy` centralizes native material/fallback resolution and its `NSVisualEffectView` subclass declines hit testing. ADR-0006 deliberately keeps chrome renderer-independent, which is a useful OD-011 runway boundary.
- **Repository safety:** No credential, certificate, private key, provisioning profile, tracked generated product, developer absolute path, distribution signing/notarization, or unauthorized publishing action was found. CI permissions are read-only.

## Specification coverage gaps

1. `SF-1902-002`, `SF-1902-003`, and `SF-1902-007` have no complete Foundation acceptance path despite the aggregate Verified status.
2. `SF-0303-003` lacks the specified route-resolution provenance/explanation surface.
3. `SF-1504` sandbox/bookmark/file-coordination semantics are not implemented; synthetic faults cover only controller error mapping.
4. Full `SF-1505` and `SF-1605` acceptance is not established by material-policy and element-presence tests.
5. Recovery for untitled projects, destructive-command confirmation, and recovery-artifact ownership are incomplete.
6. Current-schema strictness, revision overflow, and immutable historical migration fixtures are incomplete.
7. Real end-to-end launch/recovery UI journeys, complete keyboard/VoiceOver paths, retained visual evidence, and meaningful performance measurements are incomplete.
8. `SF-1901-001` through `SF-1901-008`, OD-004, OD-011, and the measured canvas/layout runway are wholly absent.

## Architecture-decision consistency

- ADR-0001's deterministic bounded container and ADR-0003's isolatable history are supported by strong tests, but ADR-0001's no-follow/atomic guarantees do not cover object-identity races or metadata preservation.
- ADR-0002 states that fingerprints prevent external overwrite and generations prevent stale replacement. M0-P0-02, M0-P0-03, M0-P1-01, and M0-P1-02 disprove those guarantees at concurrency boundaries.
- ADR-0004's migration policy is reasonable, but the shared permissive decoder applies legacy behavior to current schema and lacks golden rootless evidence.
- ADR-0005's adoption boundary is sound, but “safely cancelable” overstates cancellation latency inside parsing/history work.
- ADR-0006's centralized native-material/hit-test policy aligns with the specification; only its performance/visual evidence is overstated.
- Specification OD-001/OD-002 conflict with the project register's reused IDs. OD-004/OD-011 remain unresolved and have no ADR proposals.

## Milestone decision and ordered corrections

**Milestone 1 production implementation should not proceed.** Complete the READY items in `docs/CODEX_QUEUE.md` in dependency order:

1. `SF-CORRECTION-001` — destructive-command/untitled recovery safety;
2. `SF-CORRECTION-002` — identity-bound atomic file/recovery boundary;
3. `SF-CORRECTION-003` — lifecycle epochs and Save/autosave ordering;
4. `SF-CORRECTION-004` — strict schema/revision/migration compatibility;
5. `SF-CORRECTION-005` — real macOS file-access security boundary and status correction;
6. `SF-CORRECTION-006` — decision/requirement/evidence reconciliation;
7. `SF-CORRECTION-007` — enforceable modules, per-window ownership, and test seams;
8. `SF-AUTHORING-000` — measured OD-004/OD-011 runway and ADRs.

The recommended next branch is `fix/lifecycle-integrity-boundary`, starting with `SF-CORRECTION-001`; `SF-CORRECTION-002` may use a separate `fix/atomic-file-identity` branch if reviews must remain smaller.

## Owner decisions

No new owner decision is required to begin the corrective work. Reversible safe defaults are sufficient.

After traceability IDs are reconciled, the owner will still need to approve:

- the specification's actual OD-001 minimum supported macOS and reference-hardware tiers before a valid Milestone 0 exit/performance claim;
- OD-004 and OD-011 after `SF-AUTHORING-000` produces measured evidence;
- separately renumbered publisher/bundle and distribution-trust decisions before external distribution.

No publishing, push, signing, notarization, release, credential use, or production change occurred during this audit.
