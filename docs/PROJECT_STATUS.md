# SiteForge Project Status

Last updated: 2026-07-19.

Milestone 0 foundation is in progress through verified work item `SF-FOUNDATION-008`.

- Verified foundation: native app/test targets, native shell, canonical command model, deterministic project packages, open/save/autosave/recovery, persisted bounded history, approved blank-project defaults, and the native launch/loading experience.
- Current blank baseline: Home `/`, then Not Found `/404`; one minimum root per page; no sample content; one clean non-undoable creation baseline.
- Compatibility: canonical schema v2 writes deterministically and reads supported schema-v1 packages with deterministic minimum-page/root migration where required.
- Launch/loading: deterministic real-operation stages cover welcome, blank creation, package read, canonical/history validation, atomic adoption, recovery detection, cancellation, failure, retry, and recovery selection while preserving the last valid project.
- Verification: `./sf verify` passed on 2026-07-19 with 79 unit tests and 9 UI tests.
- Next READY item: `SF-FOUNDATION-009`, native translucent workspace materials and their accessibility/performance fallbacks.
- Open release decisions: publisher/public bundle identity (`OD-001`) and distribution trust level (`OD-002`). No publishing, distribution signing, or notarization is authorized.

Detailed requirement evidence remains in `IMPLEMENTATION_STATUS.md`; ordered work remains in `CODEX_QUEUE.md`.
