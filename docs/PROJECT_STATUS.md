# SiteForge Project Status

Last updated: 2026-07-19.

Milestone 0 feature work is implemented through `SF-FOUNDATION-009`; the milestone-boundary integrity correction program is in progress.

- Bounded verified foundation slices: native app/test targets, native shell, canonical command model, deterministic project packages, open/save/autosave/recovery, persisted bounded history, approved blank-project defaults, and native launch/loading behavior. This is not an aggregate Milestone 0 release-verification claim.
- Current blank baseline: Home `/`, then Not Found `/404`; one minimum root per page; no sample content; one clean non-undoable creation baseline.
- Compatibility: canonical schema v2 writes deterministically and reads supported schema-v1 packages with deterministic minimum-page/root migration where required.
- Launch/loading: deterministic real-operation stages cover welcome, blank creation, package read, canonical/history validation, atomic adoption, recovery detection, cancellation, failure, retry, and recovery selection while preserving the last valid project.
- Appearance: navigator, inspector, unified toolbar/title bar, viewport, status, recovery, and launch surfaces use centralized native materials with opaque Reduce Transparency fallback, stronger increased-contrast boundaries, dynamic light/dark appearance, inactive-window treatment, and pass-through hit testing.
- Audit correction: `SF-CORRECTION-001` through `005` close the data-loss, recovery, filesystem-identity, lifecycle-race, schema/migration, and macOS file-access boundaries; `SF-CORRECTION-006` reconciles decision/requirement evidence, adds cooperative parser/history cancellation and complete recovery diagnostics, and replaces preview-only loader claims with real package/recovery UI journeys.
- File access: panel-selected projects receive app-scoped bookmarks in restrictive app-owned storage; subsequent open/revert/save resolves and repairs access, balances security-scope lifetime, coordinates actual package I/O, and detects external change/move/delete without replacing canonical content. The unsigned Release candidate declares App Sandbox and user-selected read/write; Debug/XCTest remains credential-free.
- Verification: `./sf verify` passed on 2026-07-19 with 133 unit tests and 16 UI tests after `SF-CORRECTION-006`.
- Next READY item: `SF-CORRECTION-007`, enforceable module and per-window document ownership boundaries.
- Open platform decision: minimum supported macOS and reference hardware (`OD-001`). Persistence representation (`OD-002`) is resolved by ADR-0001/0003/0007. Open release decisions are publisher/public bundle identity (`OD-012`) and distribution trust level (`OD-013`). No publishing, distribution signing, or notarization is authorized.

Detailed requirement evidence remains in `IMPLEMENTATION_STATUS.md`; ordered work remains in `CODEX_QUEUE.md`.
