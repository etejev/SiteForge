# SiteForge autonomous work iteration

Follow `AGENTS.md` and treat the SiteForge specification as authoritative.

Use the current section at the top of `docs/CODEX_QUEUE.md`. Complete its
next unblocked stabilization slice. Lower dated entries document historical
work and future scope. If the active gate is waiting on desktop ownership,
record the blocker and preserve the running collector. Keep development on
this Mac through Codex.

For this iteration:

1. Inspect the requirement IDs, implementation, tests, and relevant decisions.
2. If an owner decision is genuinely required, record it in `docs/OPEN_DECISIONS.md` and stop.
3. Otherwise implement one coherent vertical slice.
4. Add or update focused tests for newly added or meaningfully changed behavior.
5. Verify the affected scope under the policy in `AGENTS.md`. Use `./sf verify` for major features, broad UI changes, or before an owner-requested commit or GitHub push.
6. Review the diff.
7. Update the queue, implementation status, evidence, and changelog.
8. Do not publish, sign, notarize, upload, purchase, or change external services.

Your final response must end with exactly one status line:

- `CODEX_LOOP_STATUS: CONTINUE` when the item passed verification and the active queue has another unblocked item.
- `CODEX_LOOP_STATUS: DONE` when verification passed and the active queue is complete.
- `CODEX_LOOP_STATUS: BLOCKED` when owner input or external authority is required.
- `CODEX_LOOP_STATUS: VERIFY_FAILED` when verification remains failing after reasonable diagnosis.

