# SiteForge Project Status

Last updated: 2026-07-19.

Milestone 0 feature work is implemented through `SF-FOUNDATION-009`; every actionable audit correction except the intentionally separate authoring-runway finding is complete.

- Bounded verified foundation slices: native app/test targets, native shell, canonical command model, deterministic project packages, open/save/autosave/recovery, persisted bounded history, approved blank-project defaults, and native launch/loading behavior. This is not an aggregate Milestone 0 release-verification claim.
- Current blank baseline: Home `/`, then Not Found `/404`; one minimum root per page; no sample content; one clean non-undoable creation baseline.
- Compatibility: canonical schema v2 writes deterministically and reads supported schema-v1 packages with deterministic minimum-page/root migration where required.
- Launch/loading: deterministic real-operation stages cover welcome, blank creation, package read, canonical/history validation, atomic adoption, recovery detection, cancellation, failure, retry, and recovery selection while preserving the last valid project.
- Appearance: navigator, inspector, unified toolbar/title bar, viewport, status, recovery, and launch surfaces use centralized native materials with opaque Reduce Transparency fallback, stronger increased-contrast boundaries, dynamic light/dark appearance, inactive-window treatment, and pass-through hit testing.
- Audit correction: `SF-CORRECTION-001` through `008` close the data-loss, recovery, filesystem-identity, lifecycle-race, schema/migration, macOS file-access, traceability, headless dependency, per-window ownership, accessibility evidence, stable navigator identity, secret scanning, resource-capacity, Open-panel ownership, and fixture-hygiene findings.
- Resource capacity: resource-index v1 keeps package control data at the unchanged 8-MiB/4-MiB/256-member limits while a deterministic content-addressed sidecar supports up to 2,000 resources, 16 MiB each, and 2 GiB total with streamed validation. Native move/copy integration remains downstream authoring work and is not claimed here.
- File access: panel-selected projects receive app-scoped bookmarks in restrictive app-owned storage; subsequent open/revert/save resolves and repairs access, balances security-scope lifetime, coordinates actual package I/O, and detects external change/move/delete without replacing canonical content. The unsigned Release candidate declares App Sandbox and user-selected read/write; Debug/XCTest remains credential-free.
- Verification: `./sf verify` passed on 2026-07-19 with 145 unit tests and 17 UI tests after `SF-CORRECTION-008`.
- Next READY item: `SF-AUTHORING-000`, the measured canvas/layout architecture runway. The audit's `M0-P1-07` remains intentionally assigned to that item.
- Open platform decision: minimum supported macOS and reference hardware (`OD-001`). Persistence representation (`OD-002`) is resolved by ADR-0001/0003/0007. Open release decisions are publisher/public bundle identity (`OD-012`) and distribution trust level (`OD-013`). No publishing, distribution signing, or notarization is authorized.

Detailed requirement evidence remains in `IMPLEMENTATION_STATUS.md`; ordered work remains in `CODEX_QUEUE.md`.
