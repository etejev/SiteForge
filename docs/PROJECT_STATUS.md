# SiteForge Project Status

Last updated: 2026-07-19.

Milestone 0 feature work is implemented through `SF-FOUNDATION-009`; the milestone-boundary integrity correction program is in progress.

- Verified foundation: native app/test targets, native shell, canonical command model, deterministic project packages, open/save/autosave/recovery, persisted bounded history, approved blank-project defaults, and the native launch/loading experience.
- Current blank baseline: Home `/`, then Not Found `/404`; one minimum root per page; no sample content; one clean non-undoable creation baseline.
- Compatibility: canonical schema v2 writes deterministically and reads supported schema-v1 packages with deterministic minimum-page/root migration where required.
- Launch/loading: deterministic real-operation stages cover welcome, blank creation, package read, canonical/history validation, atomic adoption, recovery detection, cancellation, failure, retry, and recovery selection while preserving the last valid project.
- Appearance: navigator, inspector, unified toolbar/title bar, viewport, status, recovery, and launch surfaces use centralized native materials with opaque Reduce Transparency fallback, stronger increased-contrast boundaries, dynamic light/dark appearance, inactive-window treatment, and pass-through hit testing.
- Audit correction: `SF-CORRECTION-001` resolves destructive-transition data loss and untitled crash recovery with one Save/Discard/Cancel boundary and app-owned recovery storage.
- Verification: `./sf verify` passed on 2026-07-19 with 93 unit tests and 14 UI tests after `SF-CORRECTION-001`.
- Next READY item: `SF-CORRECTION-002`, the identity-bound package/recovery filesystem boundary.
- Open release decisions: publisher/public bundle identity (`OD-001`) and distribution trust level (`OD-002`). No publishing, distribution signing, or notarization is authorized.

Detailed requirement evidence remains in `IMPLEMENTATION_STATUS.md`; ordered work remains in `CODEX_QUEUE.md`.
