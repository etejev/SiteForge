# Milestone 0 Correction Verification

Last updated: 2026-07-19.

This is the live disposition ledger for every actionable finding in `MILESTONE-0-AND-AUTHORING-RUNWAY-AUDIT.md`. A finding is marked Resolved only when its bounded correction and named evidence pass `./sf verify`. `SF-AUTHORING-000` and audit finding `M0-P1-07` remain outside this correction program.

## Verification baseline

- Branch: `fix/milestone-0-audit-corrections`
- Completed checkpoint: `SF-CORRECTION-001` (`SF-CORRECTION-001 guard destructive transitions and recover untitled work`)
- Command: `./sf verify`
- Result: passed on 2026-07-19 with 93 unit tests and 14 UI tests, zero failures
- Release/publication actions: none

## Finding disposition

| Finding | Severity | Status | Production change | Tests and evidence | Commit | Remaining limitation |
|---|---:|---|---|---|---|---|
| M0-P0-01 | P0 | Fixed | One typed authorization boundary guards New, Open, Revert, recovery Restore, and Close while preserving a complete lifecycle snapshot. | Exact-state unit tests cover Cancel and failed Save; the native UI journey covers Save/Discard/Cancel, Escape, Return, and save-panel cancellation. | `SF-CORRECTION-001 guard destructive transitions and recover untitled work` | None for this finding. |
| M0-P0-02 | P0 | Pending | None yet. | Assigned to `SF-CORRECTION-002`. | — | Same-file-object read/fingerprint barriers remain required. |
| M0-P0-03 | P0 | Pending | None yet. | Assigned to `SF-CORRECTION-002`. | — | Conditional replacement must be coordinated at commit. |
| M0-P0-04 | P0 | Partial | Recovery moved from predictable sibling names into app-owned project-ID storage. | Untitled recovery round-trip and cleanup tests pass. | `SF-CORRECTION-001 guard destructive transitions and recover untitled work` | `SF-CORRECTION-002` must prove collision, identity, and deletion safety under adversarial swaps. |
| M0-P1-01 | P1 | Pending | None yet. | Assigned to `SF-CORRECTION-003`. | — | Document-epoch and operation-intent scoping remain required. |
| M0-P1-02 | P1 | Pending | None yet. | Assigned to `SF-CORRECTION-003`. | — | Explicit-save/autosave ordering and deterministic draining remain required. |
| M0-P1-03 | P1 | Fixed | Modified titled and untitled documents write app-owned recovery candidates; launch discovers valid untitled candidates and Restore/Discard are explicit. | `testUntitledRecoverySurvivesRelaunchAndCleansUpAfterRestoreSaveAndDiscard` plus launch discovery integration. | `SF-CORRECTION-001 guard destructive transitions and recover untitled work` | None for this finding. |
| M0-P1-04 | P1 | Pending | None yet. | Assigned to `SF-CORRECTION-004`. | — | Strict schema DTOs and revision-overflow rejection remain required. |
| M0-P1-05 | P1 | Pending | None yet. | Assigned to `SF-CORRECTION-005`. | — | Sandbox/security-scope boundary and honest status downgrade remain required. |
| M0-P1-06 | P1 | Pending | None yet. | Assigned across `SF-CORRECTION-002` and `005`. | — | No-follow filesystem and confidentiality-metadata policy remain required. |
| M0-P1-07 | P1 | Excluded | None; intentionally outside this program. | Remains queued as `SF-AUTHORING-000`. | — | Architecture-runway evidence remains pending. |
| M0-P1-08 | P1 | Pending | None yet. | Assigned to `SF-CORRECTION-006`. | — | Decision namespaces remain unreconciled. |
| M0-P1-09 | P1 | Partial | Aggregate Milestone 0 status is now In progress instead of Verified. | Status documents name the active correction program. | `SF-CORRECTION-001 guard destructive transitions and recover untitled work` | Full requirement-claim reconciliation remains in `SF-CORRECTION-006`. |
| M0-P1-10 | P1 | Pending | None yet. | Assigned to `SF-CORRECTION-006`. | — | Retained, named-environment performance evidence remains required. |
| M0-P2-01 | P2 | Pending | None yet. | Assigned to `SF-CORRECTION-006`. | — | Real parser/history cancellation probes remain required. |
| M0-P2-02 | P2 | Partial | One real destructive-transition UI journey replaces preview-only evidence for that flow. | `testUnsavedTransitionDecisionIsNativeKeyboardAndAccessibilityOperable`. | `SF-CORRECTION-001 guard destructive transitions and recover untitled work` | Real create/open/fail/retry/recovery journeys remain in `SF-CORRECTION-006`. |
| M0-P2-03 | P2 | Partial | Native decision controls have stable accessibility identifiers and keyboard roles. | UI journey proves hittability, Escape, Return, save-panel cancellation, and discard. | `SF-CORRECTION-001 guard destructive transitions and recover untitled work` | Durable VoiceOver-notification and visual-inspection evidence remains in `SF-CORRECTION-006`. |
| M0-P2-04 | P2 | Pending | None yet. | Assigned to `SF-CORRECTION-006`. | — | Deterministic coalescing assertions remain required. |
| M0-P2-05 | P2 | Pending | None yet. | Assigned to `SF-CORRECTION-004`. | — | Immutable schema-v1 golden packages and rootless coverage remain required. |
| M0-P2-06 | P2 | Pending | None yet. | Assigned to `SF-CORRECTION-007`. | — | Independent lifecycle/session state per window remains required. |
| M0-P2-07 | P2 | Partial | UI scenario injection is compiled only into the app Debug configuration. | Release project configuration has no `DEBUG` compilation condition. | `SF-CORRECTION-001 guard destructive transitions and recover untitled work` | Enforceable headless modules and complete composition checks remain in `SF-CORRECTION-007`. |
| M0-P2-08 | P2 | Pending | None yet. | Assigned after `SF-CORRECTION-007`. | — | Stable PageID-derived accessibility identifiers remain required. |
| M0-P2-09 | P2 | Pending | None yet. | Assigned to `SF-CORRECTION-006`. | — | Complete lifecycle/recovery diagnostic operation coverage remains required. |
| M0-P2-10 | P2 | Pending | None yet. | Assigned to `SF-CORRECTION-002`. | — | Bounded streaming/file-object fingerprinting remains required. |
| M0-P2-11 | P2 | Pending | None yet. | Assigned after `SF-CORRECTION-007`. | — | Broader tested secret scanning remains required. |
| M0-P2-12 | P2 | Pending | None yet. | Assigned to `SF-CORRECTION-006`. | — | Secure 500-asset representation and corrected scalability claims remain required. |
| M0-P2-13 | P2 | Pending | None yet. | Assigned to `SF-CORRECTION-006`. | — | Machine-checkable behavioral traceability remains required. |
| M0-P2-14 | P2 | Pending | None yet. | Assigned to `SF-CORRECTION-002`. | — | Typed recovery-deletion failure and unchanged candidate state remain required. |
| M0-P3-01 | P3 | Pending | None yet. | Assigned after `SF-CORRECTION-007`. | — | Duplicate/dead open-panel presentation remains. |
| M0-P3-02 | P3 | Partial | UI tests use isolated repository-local recovery directories; `./sf test` and `verify` clean the exact shared fixture root on success, failure, or interruption. | Full `./sf verify` leaves no `.siteforge-test-fixtures` residue. | `SF-CORRECTION-001 guard destructive transitions and recover untitled work` | Fixture construction remains duplicated and must be consolidated after `SF-CORRECTION-007`. |

## SF-CORRECTION-001 proof summary

The correction introduces one typed transition intent and one asynchronous authorization path for every production replacement. Cancel and failed Save compare a full lifecycle snapshot containing canonical document, persisted history snapshot, project identity, URL, durable fingerprint, phase, display name, failure, and recovery candidate. The UI alert is attached above launch/workspace switching so it remains available during New and Open. Save destination selection is injected for deterministic cancellation and failure coverage; the production default remains native `NSSavePanel`.

Recovery packages now live below the app-owned Application Support recovery directory and use stable project identity in the filename. Automated evidence creates only isolated repository-local injected recovery directories; `./sf test` and `./sf verify` clean their exact fixture root even when testing exits unsuccessfully. Relaunch discovery validates candidates off the main actor before presenting Restore or Discard, and successful durable save removes the corresponding app-owned candidate.

## Continuation gate

Milestone 1 feature work must not begin. Continue with `SF-CORRECTION-002`; do not mark any pending row resolved until its adversarial tests and a fresh `./sf verify` pass.
