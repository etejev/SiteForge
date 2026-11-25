# Archived SiteForge OpenCode workflow

The owner ended OpenCode development on November 21, 2026. SiteForge Development Prompts composes the work and SiteForge Development implements it through Codex. OpenCode sessions are idle and their evaluation is closed.

The first trial ended after runtime failures with no code produced. [Evaluation evidence](../evidence/SF-OPENCODE-EVALUATION.md)

The workflow and dispatch table below are historical records.

## Roles and current ownership

| Chat | Responsibility |
| --- | --- |
| SiteForge Development Prompts in Codex | Compose tasks, review code and test evidence, approve integration, and decide whether the local model is effective for each scope |
| SiteForge Development in Codex | Own the active native app candidate, desktop testing, full verification when required, and verified owner-local installation |
| Build SF Prompts in OpenCode | Read the current queue and receipts, prepare scoped implementation prompts, and relay work to Build SiteForge OC using this workflow |
| Build SiteForge OC in OpenCode | Implement the assigned scope, run focused checks, review its diff, and return the code and reproducible evidence |

Read `AGENTS.md`, applicable specification clauses, the queue entry, current evidence, and relevant source before planning. Use the latest files, since a previous prompt can describe work that has already landed. Cite the applicable SF requirement IDs. Resolve routine reversible choices and escalate owner decisions through the established decision file.

Use the exact SiteForge repository when a chat opens at the parent GitHub directory. Follow each task's assigned working directory and edit paths. Record the baseline, active owner, scope, changed paths, and commands. One writer owns a given file at a time. Use an isolated working copy for an overlapping assignment, initialized from the current working content. Deliver a patch and a report for review. Preserve existing edits and untracked files. Prepare and verify the integrated installed candidate through the Codex build chat.

Build SF Prompts can send an explicit user-authorized task to Build SiteForge OC after checking the dispatch table. Keep one active task in that worker until its receipt is reviewed. Include the task ID, requirements, current-source anchors, expected behavior, edit scope, exact focused checks, and completion evidence. If the owner supplies a new task there, inspect current ownership and reconcile its scope with the active packet before dispatch. Record completion as awaiting review until the main composer accepts the result. Use the supported OpenCode session tools or API for messaging. Report whether a message was actually delivered.

## Verification and delivery

Use focused model, tooling, and native tests for new or meaningfully changed behavior. Record exact commands, exit codes, counts, and result paths. Check failures, invalid input, cancellation, persistence, Undo and Redo, keyboard access, and accessibility where applicable. Reserve full `./sf verify` for major features, broad UI changes, and before an owner-requested commit or GitHub push. One desktop collector runs at a time. Check whether a candidate is in verification before editing its inputs. The main test window fills the AppKit usable desktop, with compact dimensions applied in deliberate test phases.

Review real code for correctness, compatibility, readability, scope control, and existing conventions. Independently rerun the checks appropriate to the change. Compare the amount of repair needed, whether the model found relevant dependencies, the accuracy of its report, and total turnaround time. A small tooling trial establishes evidence for similar work. Swift model or native UI assignments require evidence in those areas before expanding delegation.

After accepted integration and applicable checks, refresh `/Applications/SiteForge.app` through the established owner-local packager and verify its signature and source fingerprint. Local commits and external GitHub work follow the owner's explicit authorization boundary in `AGENTS.md`.

## Dispatch

| Task | Worker | Scope | State |
| --- | --- | --- | --- |
| OC-001 | Build SiteForge OC | Deleted and renamed file handling in test-scope selection, evaluated in the isolated copy named by `.codex-loop/opencode-evaluation/current.json` | Ended after runtime failures, source unchanged |
| Approved native redesign | SiteForge Development | Reconcile retained full-gate result, finish verification evidence, and install the verified candidate | Verified and installed as local build 26.11.21 |
| Floating test monitor | SiteForge Development | Continue the approved packet after redesign installation | In progress in Codex |

OC-001 supports SF-1902-007 and SF-1902-008. Its worker may edit `scripts/select-test-scope.py` and `Tests/Tooling/test_select_test_scope.py` within its assigned isolated copy, plus its local handoff report. The main composer owns shared queue, status, and integration updates for this assessment.
