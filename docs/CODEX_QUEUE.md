# Codex Work Queue

Codex processes the first READY item whose dependencies are satisfied. Keep items small enough to implement and verify in one focused iteration.

## READY

- [ ] `SF-FOUNDATION-001` Create the native macOS Xcode project and test targets.
  - Requirements: map to the approved Milestone 0 requirement IDs before implementation.
  - Acceptance: `./sf build` and `./sf test` pass on a clean checkout.
  - Dependencies: confirm the bundle identifier in `docs/OPEN_DECISIONS.md` or use the reversible local default `app.siteforge.SiteForge`.
  - Plan: pending.
  - Evidence: pending.

- [ ] `SF-FOUNDATION-002` Implement the application shell with document window, toolbar, navigator, canvas placeholder, inspector, and status bar.
  - Requirements: application shell, navigation, command system, macOS windowing, accessibility.
  - Acceptance: UI test verifies window regions and keyboard focus order.
  - Dependencies: `SF-FOUNDATION-001`.
  - Plan: pending.
  - Evidence: pending.

- [ ] `SF-FOUNDATION-003` Implement the command registry and transactional document-model skeleton.
  - Requirements: command system, canonical identity, transactions, undo/redo, diagnostics.
  - Acceptance: unit tests prove command validation, atomic mutation, inverse, and stable serialization.
  - Dependencies: `SF-FOUNDATION-001`.
  - Plan: pending.
  - Evidence: pending.

## IN PROGRESS

None.

## BLOCKED

None.

## DONE

None.

