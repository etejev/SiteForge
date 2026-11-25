# OpenCode local-model evaluation

The owner authorized an Ollama `gemma4:12b` coding trial on November 21, 2026, supporting SF-1902-007 and SF-1902-008. The established workflow is in [OpenCode coordination](../coordination/OPENCODE_WORKFLOW.md). This evidence concerns development tooling and model capability.

## Assignment and method

Build SiteForge OC received OC-001 through the running OpenCode server. The two-file assignment concerned deleted and renamed paths in `scripts/select-test-scope.py`, including staged, unstaged, committed and untracked changes. It required real temporary Git fixtures, focused checks, a diff and a handoff. The isolated copy preserved the main native-app verification candidate. Its runtime record is in the ignored `.codex-loop/opencode-evaluation/current.json` file.

Build SF Prompts received the workflow for composing and dispatching future tasks, checking ownership and recording actual receipts. Both OpenCode sessions have a durable workflow instruction. The main Codex build chat received the same coordination information and retained ownership of the native app and desktop collector.

The composer independently reproduced the scope issue with twelve Git-fixture checks. Three baseline cases passed and nine failed. These were a baseline and future assessment harness. The worker's target source SHA-256 was `58d1773e4ac408cfab6f6191cfedeb19c95db9daa15eaf6d81c242627d684441`.

## Observed result

The trial ran for approximately nineteen minutes after dispatch. Its first provider request timed out waiting for response headers. The retry read the workflow and task, recovered from using Python in a JavaScript tool, and read the target source. The subsequent response ended with the provider error `OpenAI Chat stream ended without finish_reason`. Ollama restarted its runner. The composer interrupted automatic retries after confirming that the isolated source had the original digest, an empty diff, and no added test or handoff files.

The worker produced no source patch or completed tests. Code readability and correctness therefore remain unassessed. The observed runtime reliability and turnaround did not meet the needs of this focused assignment. Codex continues implementation. The evaluation result was saved to both OpenCode chats without starting another model turn. Future task routing can be reconsidered after the runtime completes a coding trial and its output passes independent review.

## Verification and integration

The prompt delivery and durable instruction writes returned successful receipts. The isolated Git state and source digest were checked after interruption. Repository diff whitespace checks passed for the workflow documentation. No worker implementation was integrated from this trial. The production scope-selection issue remains an outstanding tooling fix for a later scoped task.

During this coordination work the Codex build chat reconciled the retained redesign result. It installed build 26.11.21 after accounting for 895 core passes, 167 UI passes, and three approved skips. Its installation report records strict signature and source-fingerprint verification. The structured result bundle has a missing object, as recorded in the [redesign evidence](SF-NATIVE-UI-REDESIGN.md). The full log and matching source fingerprints support that installation.
