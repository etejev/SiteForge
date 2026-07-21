# SF-AUTHORING-000 benchmark evidence

This directory retains the measured architecture runway for `SF-1901-001` through `SF-1901-008` and bounded downstream evidence for `SF-0401-001` through `SF-0401-008`, `SF-0407-001` through `SF-0407-008`, `SF-0501-001` through `SF-0501-008`, and `SF-1903-001` through `SF-1903-008`. It is architecture evidence, not a production canvas or layout implementation.

## Reproduce

From the repository root:

```sh
scripts/run-authoring-benchmarks.sh
scripts/check-authoring-runway.py
./sf verify
```

The first command compiles the isolated harness with `swiftc -O -swift-version 6` into ignored `.build/authoring-engine-runway/` storage and replaces `raw-results.json`. The JSON retains every timing sample, P50/P95, frame-interval exceedance count, resident-memory samples, correctness gates, environment, configuration, and limitations. The second command validates the retained evidence without rerunning a benchmark during every repository check.

## Environment and method

- Hardware: Mac16,13, Apple silicon arm64, 16 GiB physical memory.
- Software: macOS 27.0, Xcode 27.0 (27A5194q), SDK 27.0, Apple Swift 6.4.
- Build: optimized standalone executable, Swift 6 strict language mode.
- Canvas: 3 warm-ups and 20 retained samples per render/update alternative at 100 and 10,000 deterministic rectangles. A 16.67 ms reference interval is reported, not asserted as a release budget.
- Layout: 5 warm-ups and 30 retained samples for the Foundation-only engine. WebKit uses 2/10 warm-up/samples at 100 nodes and 1/5 at 10,000 nodes because each sample creates an ephemeral web view, loads exported HTML/CSS, and reads every DOM frame.
- Memory: resident bytes are sampled after warm-up and after repetitions; `ru_maxrss` retains the process-wide high-water mark. The alternatives run sequentially, so peak memory is not isolated per backend.
- Main-thread behavior: AppKit, SwiftUI, Core Animation, WebKit, and accessibility prototypes execute on the main actor. The retained count above 16.67 ms identifies potential stalls. The deterministic layout and hit-test cores have no UI dependency and can run away from the main actor.
- Correctness: 10,000 world/view/device round trips, cursor-anchored zooms, and pans use a `1e-9` point tolerance. HTML/CSS geometry uses a 0.51-point tolerance at widths 320, 768, and 1,440 and on the complete 100-/10,000-node fixtures.

The harness was run after the Milestone 0 base revision `05dc64b`. The generated timestamp and exact environment are in `raw-results.json`.

## Canvas results

Times are milliseconds from the retained run. “Over” is samples exceeding 16.67 ms.

| Alternative and operation | Objects | P50 | P95 | Over |
|---|---:|---:|---:|---:|
| AppKit immediate full raster | 100 | 0.838 | 0.900 | 0/20 |
| AppKit one-object dirty raster | 100 | 0.028 | 0.036 | 0/20 |
| SwiftUI Canvas full raster | 100 | 0.601 | 0.718 | 0/20 |
| SwiftUI Canvas one-change full raster | 100 | 0.593 | 0.679 | 0/20 |
| Core Animation layer-tree full raster | 100 | 0.914 | 1.026 | 0/20 |
| Core Animation one-layer transaction | 100 | 0.003 | 0.003 | 0/20 |
| AppKit immediate full raster | 10,000 | 17.363 | 17.633 | 20/20 |
| AppKit one-object dirty raster | 10,000 | 0.072 | 0.074 | 0/20 |
| SwiftUI Canvas full raster | 10,000 | 32.537 | 36.574 | 20/20 |
| SwiftUI Canvas one-change full raster | 10,000 | 27.850 | 29.244 | 20/20 |
| Core Animation layer-tree full raster | 10,000 | 16.734 | 18.183 | 12/20 |
| Core Animation one-layer transaction | 10,000 | 0.105 | 0.107 | 0/20 |

The 10,000-object AppKit and Core Animation full offscreen rasters cross one reference interval, so the recommendation depends on retained scene state, dirty-region/tile invalidation, and compositor transforms for pan/zoom—not full rerasterization per interaction. SwiftUI Canvas rerasterized the complete surface after a single model change and was materially slower at 10,000 objects. The Metal probe measured only buffer mutation and an empty command-buffer round trip (10,000-object P95 0.023 ms); it deliberately does not claim shader, texture, presentation, accessibility, or hit-test performance.

The sequential process high-water rose from about 40.9 MB after the 10,000-object SwiftUI phase to about 53.0 MB after the layer-per-object Core Animation phase and about 58.7 MB after constructing 10,000 virtual accessibility elements. Because allocations and framework caches persist between phases, these numbers show capacity and direction, not isolated backend deltas. A layer per canonical object is therefore a stress alternative, not the chosen production structure.

Uniform-grid hit testing was independent of rendering (10,000-object P95 0.000125 ms). Content digest remained unchanged when an editor overlay was added. A pass-through native `NSVisualEffectView` above the AppKit canvas preserved canvas hit testing. Constructing 10,000 AppKit accessibility elements measured below one reference interval in the retained raw result; VoiceOver speech and navigation were not measured.

## Layout and browser-oracle results

| Alternative | Nodes | P50 | P95 | Over |
|---|---:|---:|---:|---:|
| SiteForge deterministic subset | 100 | 0.024 | 0.030 | 0/30 |
| SiteForge deterministic subset | 10,000 | 2.602 | 2.657 | 0/30 |
| WebKit exported HTML/CSS oracle | 100 | 57.707 | 60.845 | 10/10 |
| WebKit exported HTML/CSS oracle | 10,000 | 132.764 | 134.745 | 5/5 |

The typed subset covers fixed, intrinsic, and fill sizing; min/max constraints; padding; gaps; start/center/end/stretch alignment; horizontal/vertical stacks; nesting; clip/visible overflow; and responsive widths. Identical inputs produced identical frame digests. Invalid constraints, structurally unsupported containers, cooperative cancellation, and stale revision results were rejected. Exported browser geometry matched the subset exactly (0-point maximum observed error) for the parity fixture and complete 100-/10,000-node fixtures.

WebKit remains valuable as a standards oracle and export-equivalent preview adapter. Its process/IPC/navigation cost and mutable browser state make it unsuitable as SiteForge’s canonical editable layout model.

## Resource fixture

The harness calls the production `ProjectResourceStore` and `ProjectResourceIndex` directly. It wrote 500 distinct non-empty 32-KiB resources (16,384,000 bytes total), produced a deterministic 95,417-byte index and 96,950-byte control package, stayed within the unchanged 8-MiB package parser limit, streamed integrity validation, and verified a lazy resource read. Resource insertion P95 was 1.395 ms per asset; complete streamed validation P95 was 38.295 ms; one-resource lazy read P95 was 0.090 ms. Resource construction and validation are separate measurements and are never labeled canvas or layout performance.

## Limitations and revisit evidence

- No WindowServer presentation, display-link pacing, Instruments signpost trace, energy measurement, or real scrolling/panning session is claimed.
- Memory is process-wide and sequential rather than isolated by child process.
- The layout subset does not yet include text shaping, CSS grid, percentage/calc expressions, baseline alignment, or browser-specific fallback behavior.
- The browser oracle measures geometry, not pixel/color/font parity.
- The Metal probe is intentionally incomplete because the native path already establishes a viable initial split; a production Metal prototype is required before adopting Metal.
- The single host cannot establish release budgets or lower-tier hardware behavior while `OD-001` remains open.

These limitations become explicit revisit triggers in ADR-0013 and ADR-0014.
