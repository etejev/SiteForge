# Milestone 0 bounded performance methodology

Current measurements are foundation smoke budgets, not authoring-engine or release performance evidence.

- Environment must record hardware model, architecture, OS/build, Xcode/SDK, configuration, fixture, and power state.
- A release claim requires warm-up, at least 10 measured repetitions, P50/P95, peak resident memory, main-thread/event-loop stall observations, and—where rendering exists—frame pacing.
- The existing 100-page load and 10,000-page policy/fixture tests exercise decoding, model construction, policy resolution, and navigation only. They do not exercise 100 or 10,000 rendered canvas objects, accessibility-tree scale, hit testing, or incremental renderer updates.
- Package-v1 control data remains securely bounded to 8 MiB total and 4 MiB per member. ADR-0012 now represents 500 non-empty 32-KiB assets through a deterministic resource index and bounded streamed content-addressed sidecar without relaxing those limits. Renderer/object percentile, memory, stall, and frame evidence still belongs to `SF-AUTHORING-000`.
- Reproducible foundation command: `./sf verify`. Raw timing is retained in the Xcode result bundle for a run; promotion into a release baseline is prohibited until OD-001 is approved and a repository-local capture command retains the named-environment percentile/memory result.

The 2026-07-19 correction run used a MacBook Air (Apple silicon), macOS 27.0 build 26A5378n, and Xcode 27.0 beta. Its results are verification evidence only; they are intentionally not copied into a release-performance table because the current tests do not collect the required repeated percentile and memory metrics.
