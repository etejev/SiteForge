# ADR-0013 — SiteForge-owned deterministic layout engine

- Status: Accepted; resolves OD-004
- Date: 2026-07-21
- Owners: Architecture / Engineering
- Requirements: SF-1901-001–008, SF-0501-001–008, SF-1903-001–008

## Context

SiteForge needs predictable editable layout, atomic authoring transactions, stable provenance, accessibility, deterministic persistence, and portable HTML/CSS output. OD-004 asked whether an existing standards engine should supply canonical layout or whether SiteForge should own deterministic semantics and use a browser at a boundary.

## Decision drivers

- Canonical layout must be UI-independent, deterministic, revision-scoped, cancelable, and testable without a web process.
- Browser preview and exported HTML/CSS must remain close enough to detect unsupported or divergent behavior.
- Browser mutable state, DOM identity, process lifecycle, and asynchronous reflow must not become a second editable document model.
- The initial architecture must preserve a reversible path to broaden standards coverage.

## Decision

SiteForge will own a typed, deterministic, UI-independent layout engine as the canonical computed-layout implementation. Canonical document properties remain the authored source; layout consumes immutable revision-tagged snapshots and returns stable-ID keyed frames. Invalid, unsupported, cancelled, and stale work is rejected without adoption.

HTML/CSS generation is an explicit adapter. An ephemeral standards engine (initially WebKit on macOS) is used as an oracle in tests and as an isolated preview/export runtime, never as canonical authoring state. Parity fixtures compare SiteForge frames with exported browser frames at representative widths and scales.

The production engine will begin with the measured fixed/intrinsic/fill, min/max, padding, gap, alignment, stack, nesting, overflow, and responsive-width subset. Unsupported semantics must remain typed and visible until deliberately added; the engine must not approximate them silently.

## Evidence

`scripts/run-authoring-benchmarks.sh` produced the retained schema-v1 results in `docs/evidence/authoring-engine-runway/raw-results.json` on the named Mac16,13 environment. The optimized SiteForge subset measured 0.030 ms P95 at 100 nodes and 2.657 ms P95 at 10,000 nodes. The WebKit load/style/layout/IPC/frame-read oracle measured 60.845 ms and 134.745 ms P95 respectively. Repeated SiteForge layout digests were stable. Exported browser frames had 0-point maximum observed divergence on the responsive 320/768/1,440 fixture and complete 100-/10,000-node fixtures. Cancellation, stale revision, invalid constraints, and unsupported structure were rejected.

The measurements are not release budgets. Their environment, raw samples, memory fields, method, and limitations are retained beside this ADR.

## Alternatives considered

1. Make WebKit/DOM/CSS canonical. Rejected because authoring identity, transactions, provenance, deterministic serialization, cancellation, and recovery would depend on mutable asynchronous browser state and IPC.
2. Embed a third-party standards engine as canonical. Deferred because it adds dependency, licensing, sandbox, update, semantic-mapping, and deterministic-versioning costs before the required subset demands them.
3. Use a SiteForge engine with no browser oracle. Rejected because export drift would go undetected.
4. Use the chosen deterministic core plus an isolated browser oracle/preview/export adapter.

## Tradeoffs and consequences

- Positive: fast headless computation, exact revision ownership, deterministic tests, explicit unsupported states, and no browser dependency in canonical modules.
- Positive: browser parity remains measurable at the export boundary instead of assumed.
- Negative: SiteForge owns layout correctness, migrations, and expansion work; standards coverage must be built deliberately.
- Negative: text shaping and more advanced CSS behavior can expose parity gaps that the current subset does not address.
- Accessibility: stable layout identities and geometry are available without DOM traversal; preview accessibility remains separately testable in WebKit/export output.
- Performance: layout can run away from the main actor. WebKit work remains asynchronous and cannot block canonical editing or adoption.
- Preview/export: exported HTML/CSS is generated from the same typed semantics, then verified against browser geometry; DOM state never writes back into the model.

## Failure modes

- A supported property produces browser geometry beyond the declared tolerance.
- An unsupported value is silently coerced.
- A stale/cancelled result is adopted.
- Platform text/font behavior introduces nondeterminism.
- Export adapter logic diverges from canonical resolution rules.

Each failure requires a regression fixture before expanding the supported subset.

## Reversibility and revisit triggers

The engine and browser adapter are protocol boundaries. A future embedded engine can replace or supplement computation for a versioned subset without changing canonical document identity, provided deterministic migration and parity evidence exist.

Revisit this decision when text shaping, CSS grid, complex intrinsic sizing, or international layout cannot meet parity; when supported cases exceed 0.51-point geometry error; when the engine misses an owner-approved hardware budget; or when maintaining the subset costs more than a bounded embedded alternative. Any replacement requires equivalent cancellation, stale-result, accessibility, deterministic serialization, and 100-/10,000-node evidence.
