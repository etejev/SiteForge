# SF-AUTHORING-003 native canvas-renderer evidence

This directory retains production-representative evidence for the bounded `SF-0407-001` through `SF-0407-008` renderer foundation. It does not claim canonical render-pass editing or persistence, selection behavior, export generation, production text/image rasterization, stress-limit acceptance, VoiceOver speech, or release performance.

## Reproduce

```sh
scripts/run-canvas-renderer-evidence.sh
scripts/check-canvas-renderer-evidence.py
./sf verify
```

The optimized harness compiles the production Foundation-only renderer contract. It measures complete initial planning, one-object dirty planning, and reverse-order hit testing at 100 and 10,000 objects. Fixture construction is excluded. Planning includes full validation, paint ordering, bounded tile membership, accessibility virtualization, dirty-region policy, and digest creation; it excludes AppKit layer adoption, WindowServer presentation, and GPU compositor work. The running-app UI test separately exercises the real AppKit viewport and Core Animation tile surface.

## Named environment and results

- Hardware: Mac16,13, Apple silicon arm64, 16 GiB physical memory.
- Software: macOS 27.0, Xcode 27.0 (27A5194q), SDK 27.0, Apple Swift 6.4.
- Method: `swiftc -O -swift-version 6`; 5 warm-ups and 30 retained preparation samples; 2,000 retained hit-test samples.
- Full plan P95: 1.084 ms at 100 objects and 75.980 ms at 10,000 objects.
- One-object dirty plan P95: 1.172 ms at 100 objects and 113.634 ms at 10,000 objects.
- Reverse paint-order hit-test P95: 0.001 ms at 100 objects and 0.107 ms at 10,000 objects.
- The 10,000-object full and dirty planning series missed the 16.67 ms reference interval in all 30 retained samples. This is not an incremental-planning or release-budget pass. AppKit adoption redraws bounded affected tiles rather than the complete scene, but scene diff/validation remains whole-snapshot work.
- The viewport required at most 12 content tiles and virtualized accessibility to 256 visible elements under the declared policy. Cache retention is limited to two generations and 96 MiB.
- An idle 250 ms Core Video display-link observation recorded 15 callbacks and zero intervals longer than twice the 60 Hz reference. This is cadence evidence only, not an interactive Instruments trace.
- Process resident samples and high-water readings are retained per series in `raw-results.json`; they are sequential process readings, not isolated backend allocations.

## Correctness and visual inspection

Automated evidence proves stable repeated digests, reverse-order hit testing, clipping/visibility, overlay-free preview snapshots, cancellation, exact stale identity rejection, old/new dirty regions, compositor-only pan/zoom with no dirty regions, deterministic cache eviction, bounded tiles, and stable accessibility virtualization. The focused UI journey launched the actual application, observed two rendered blank-project root objects in the native canvas accessibility value, focused/clicked the AppKit surface, and preserved input delivery through native materials.

Manual inspection on the named environment covered the default workspace in the current dark appearance at 100% Retina scale: authored root-object surfaces appeared inside the existing artboard; navigator, inspector, viewport controls, status materials, and focus ring remained readable; clicking the canvas focused the native surface. The retained [`default-workspace.png`](default-workspace.png) captures only the SiteForge window. Light, Reduce Transparency, increased contrast, inactive-window, minimum-size, 100-/10,000-object fixture, and interactive scrolling behavior retain existing automated regression coverage but were not all manually re-inspected in this checkpoint.

## Limitations

- `OD-001` remains open, so the named-host data cannot define minimum/reference-hardware release budgets.
- The 10,000-object whole-snapshot diff path exceeds a frame interval and requires later indexing/incremental-validation optimization.
- The display-link probe is idle and short; it does not replace Instruments, WindowServer, or interactive frame-pacing evidence.
- Tile drawing currently covers bounded placeholder rectangles, clipping, appearance-derived colors, and focus; production text shaping, images, effects, and resource decoding remain later work.
- Accessibility elements are stable and virtualized, but actual VoiceOver speech and offscreen navigation were not manually exercised.
- Editor overlay infrastructure is separate and export-facing snapshots cannot contain overlays; the later selection engine is intentionally absent.
