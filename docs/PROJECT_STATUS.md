# SiteForge Project Status

Last updated: 2026-07-21.

Milestone 0 feature work and audit corrections are complete. The bounded authoring runway is accepted, and `SF-AUTHORING-001` now supplies the first production Milestone 1 viewport foundation.

- Bounded verified foundation slices: native app/test targets, native shell, canonical command model, deterministic project packages, open/save/autosave/recovery, persisted bounded history, approved blank-project defaults, and native launch/loading behavior. This is not an aggregate Milestone 0 release-verification claim.
- Current blank baseline: Home `/`, then Not Found `/404`; one minimum root per page; no sample content; one clean non-undoable creation baseline.
- Compatibility: canonical schema v2 writes deterministically and reads supported schema-v1 packages with deterministic minimum-page/root migration where required.
- Launch/loading: deterministic real-operation stages cover welcome, blank creation, package read, canonical/history validation, atomic adoption, recovery detection, cancellation, failure, retry, and recovery selection while preserving the last valid project.
- Appearance: navigator, inspector, unified toolbar/title bar, viewport, status, recovery, and launch surfaces use centralized native materials with opaque Reduce Transparency fallback, stronger increased-contrast boundaries, dynamic light/dark appearance, inactive-window treatment, and pass-through hit testing.
- Audit correction: `SF-CORRECTION-001` through `008` close the data-loss, recovery, filesystem-identity, lifecycle-race, schema/migration, macOS file-access, traceability, headless dependency, per-window ownership, accessibility evidence, stable navigator identity, secret scanning, resource-capacity, Open-panel ownership, and fixture-hygiene findings.
- Resource capacity: resource-index v1 keeps package control data at the unchanged 8-MiB/4-MiB/256-member limits while a deterministic content-addressed sidecar supports up to 2,000 resources, 16 MiB each, and 2 GiB total with streamed validation. Native move/copy integration remains downstream authoring work and is not claimed here.
- File access: panel-selected projects receive app-scoped bookmarks in restrictive app-owned storage; subsequent open/revert/save resolves and repairs access, balances security-scope lifetime, coordinates actual package I/O, and detects external change/move/delete without replacing canonical content. The unsigned Release candidate declares App Sandbox and user-selected read/write; Debug/XCTest remains credential-free.
- Authoring runway: isolated native prototypes and a deterministic layout subset retain 25 raw measurement series at 100/10,000 objects, exact browser-geometry parity on the supported subset, a real 500-asset storage exercise, environment/memory/limitations, and five focused behavioral tests. ADR-0013 selects a SiteForge-owned layout engine with an isolated standards oracle; ADR-0014 selects SwiftUI chrome plus an AppKit viewport and bounded Core Animation composition, with Metal optional.
- Canvas viewport: Foundation-only typed world/viewport/device geometry drives a scene-owned AppKit viewport with 25–800% cursor-anchored zoom, bounded pan, deterministic fit/resize, Retina-aware conversion, keyboard and accessibility commands, and revision/generation-scoped actor preparation. Viewport convenience state does not enter canonical project persistence.
- Verification: `./sf verify` passed on 2026-07-21 with 161 unit tests and 18 UI tests, zero failures.
- Next READY item: `SF-AUTHORING-002`, the deterministic layout-engine foundation subset, followed by the native renderer/overlay slice.
- Open platform decision: minimum supported macOS and reference hardware (`OD-001`). Persistence representation (`OD-002`) is resolved by ADR-0001/0003/0007. Open release decisions are publisher/public bundle identity (`OD-012`) and distribution trust level (`OD-013`). No publishing, distribution signing, or notarization is authorized.

Detailed requirement evidence remains in `IMPLEMENTATION_STATUS.md`; ordered work remains in `CODEX_QUEUE.md`.
