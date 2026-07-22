# SF-AUTHORING-002 deterministic layout evidence

This directory retains production-representative evidence for the bounded `SF-0501-001` through `SF-0501-008` layout-engine foundation. It does not claim the later canonical property-editing, inspector, renderer, preview, export UI, typography, or release-hardware acceptance work.

## Reproduce

From the repository root:

```sh
scripts/run-layout-foundation-evidence.sh
scripts/check-layout-foundation-evidence.py
./sf verify
```

The first command compiles `SiteForge/DocumentModel.swift` and the production `SiteForge/LayoutEngine.swift` with `swiftc -O -swift-version 6`. WebKit is linked only into the standalone evidence executable, where an ephemeral web view evaluates an isolated HTML/CSS adapter. The production application and headless layout slice do not import WebKit. The schema-v1 JSON retains every timing sample, P50/P95, resident-memory samples, deterministic digests, environment, configuration, correctness gates, and limitations.

## Environment and results

- Hardware: Mac16,13, Apple silicon arm64, 16 GiB physical memory.
- Software: macOS 27.0, Xcode 27.0 (27A5194q), SDK 27.0, Apple Swift 6.4.
- Production layout: 5 warm-ups and 30 retained samples, including graph validation, immutable frame/provenance construction, and digest generation.
- Browser oracle: 1 warm-up; 5 retained 100-node samples and 3 retained 10,000-node samples. Navigation, style/layout, IPC, and frame extraction are included.
- 100 nodes: production P50 0.215 ms, P95 0.232 ms; resident sample 10.17→10.35 MB.
- 10,000 nodes: production P50 19.940 ms, P95 22.290 ms; resident sample 82.35→82.61 MB. This is off-main capacity evidence and exceeds the 16.67 ms reference interval; it is not a release frame-budget pass.
- WebKit oracle: 100-node P95 114.523 ms; 10,000-node P95 96.481 ms. WebKit is intentionally asynchronous and noncanonical.
- Geometry parity: 0-point maximum observed difference at responsive widths 320, 768, and 1,440 and across the complete 100-/10,000-node fixtures, within the declared 0.51-point tolerance.

Fixture construction is excluded from measurements. The large fixture is a real 10,000-node vertical stack with stable typed identities, varied fixed heights, fill cross sizing, padding, gap, clipping, full validation, immutable results, and digest work. It is deliberately not a renderer or text-shaping benchmark.

## Limitations

- One named host cannot establish minimum/reference-hardware budgets while `OD-001` remains open.
- Resident-memory values are process samples; peak resident memory is shared across sequential production and WebKit phases.
- Browser parity covers geometry for the declared subset, not fonts, pixels, colors, international typography, or unsupported CSS.
- Intrinsic text sizes are deterministic adapter inputs; platform shaping and fallback integration remain later work.
- The engine is not yet connected to canonical layout-property mutations, transactions, persistence, inspector UI, rendering, preview, or export UI.
- The 10,000-node production P95 is above one 60 Hz interval, but execution is actor-isolated and never adopted after cancellation or identity mismatch. Incremental layout remains later work.
