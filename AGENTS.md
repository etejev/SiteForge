# SiteForge Agent Instructions

## Mission

Build SiteForge as a production-quality native macOS application. Work like a responsible senior product engineer: understand the requirement, inspect existing behavior, make the smallest coherent change, verify it, document it, and leave the repository healthier.

## Sources of truth

1. `docs/SiteForge-Specification.md` is the searchable implementation contract.
2. `docs/SiteForge-Specification.docx` is the editable publication copy.
3. `docs/architecture-decisions/` records approved architectural choices.
4. `docs/OPEN_DECISIONS.md` records unresolved product or architecture choices.
5. `docs/IMPLEMENTATION_STATUS.md` records requirement coverage.
6. `docs/CODEX_QUEUE.md` is the ordered work queue.

Every implementation task must cite its `SF-…` requirement IDs. Do not invent competitor behavior when the specification is silent.

## Autonomous work loop

For each ready queue item:

1. Read the item, linked requirements, relevant implementation, tests, and decisions.
2. Confirm that no unresolved owner decision blocks it.
3. Write a short implementation plan in the task entry.
4. Implement one bounded vertical slice.
5. Add or update tests before declaring the slice complete.
6. Run `./sf verify`.
7. Review the diff for unrelated changes, debug artifacts, secrets, accessibility regressions, and architectural drift.
8. Update `docs/IMPLEMENTATION_STATUS.md`, `docs/CHANGELOG.md`, and the queue item.
9. Continue to the next ready item while the current Codex run has sufficient context and verification remains green.

Do not stop merely because the first happy path works. Check empty, loading, error, cancellation, keyboard, accessibility, persistence, undo/redo, and migration behavior when applicable.

## When to ask the owner

Stop and write a concise entry in `docs/OPEN_DECISIONS.md` when work requires:

- a product decision not answered by the specification;
- changing or waiving a normative requirement;
- a materially different architecture with broad downstream impact;
- Apple enrollment, agreements, certificates, notarization, or publication;
- a purchase, paid service, external account, production deployment, or public release;
- disclosure or rotation of credentials;
- a legal, privacy, licensing, or security-policy decision;
- an irreversible or incompatible data migration.

State the recommended default, alternatives, tradeoffs, affected requirements, decision deadline, and safe temporary assumption. Do not block on questions that can be answered by repository inspection or a reversible local choice.

## Change discipline

- Keep content mutations transactional and test undo/redo where applicable.
- Preserve stable identifiers and backward-compatible project data.
- Keep UI state separate from the canonical document model.
- Use native macOS conventions and accessibility APIs.
- Perform expensive work away from the main actor.
- Never silently weaken a test, performance budget, security boundary, or requirement.
- Never commit credentials, certificates, private keys, derived data, release archives, or local machine paths.

## Documentation discipline

After each meaningful change:

- update the requirement status and evidence link;
- update the changelog for user-visible behavior;
- add an ADR for consequential architectural decisions;
- update the specification only when approved product behavior changes;
- keep implementation comments focused on why, not on restating the code.

## Required verification

Run `./sf verify` before reporting completion. If it fails, diagnose and fix it. If the failure is external or pre-existing, record exact evidence and do not claim the item is complete.

## Release safety

`./sf release-local` may create a local unsigned alpha artifact. Never publish a GitHub Release, upload to Apple, sign with a distribution identity, notarize, or modify production update feeds without explicit owner authorization.

