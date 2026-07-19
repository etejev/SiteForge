# SiteForge autonomous work iteration

Follow `AGENTS.md` and treat the SiteForge specification as authoritative.

Complete the next highest-priority item marked READY in `docs/CODEX_QUEUE.md`.

For this iteration:

1. Inspect the requirement IDs, implementation, tests, and relevant decisions.
2. If an owner decision is genuinely required, record it in `docs/OPEN_DECISIONS.md` and stop.
3. Otherwise implement one coherent vertical slice.
4. Add or update tests.
5. Run `./sf verify`.
6. Review the diff.
7. Update the queue, implementation status, evidence, and changelog.
8. Do not publish, sign, notarize, upload, purchase, or change external services.

Your final response must end with exactly one status line:

- `CODEX_LOOP_STATUS: CONTINUE` when the item passed verification and another READY item exists.
- `CODEX_LOOP_STATUS: DONE` when verification passed and the READY queue is empty.
- `CODEX_LOOP_STATUS: BLOCKED` when owner input or external authority is required.
- `CODEX_LOOP_STATUS: VERIFY_FAILED` when verification remains failing after reasonable diagnosis.

