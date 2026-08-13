# ADR-0015: Structural Elements v1 Canonical Defaults

Status: Accepted — 2026-08-12

## Context

`SF-AUTHORING-010` makes Section, Stack, and Grid persisted canonical node
kinds. The specification requires deterministic container behavior but does
not choose initial numerical values. Those values affect package bytes,
history inverses, renderer geometry, hit testing, and later export semantics.

## Decision

Schema 4 stores the following defaulted v1 properties:

- Section: 960 × 320 points, vertical structural container, 48-point padding.
- Stack: 240 × 160 initial frame; vertical axis, start alignment, 24-point
  padding and gap.
- Grid: 240 × 160 initial frame; two equal columns, row-major placement,
  24-point padding and gap.

The document hierarchy (`parent` plus ordered `childIDs`) remains the sole
ownership/order source. `DocumentPage.resolvedStructuralGeometry()` derives
Stack/Grid child frames for renderer, selection, hit testing, and accessibility;
it does not persist a second geometry representation. Schema 3 remains readable
and re-saves deterministically as schema 4. Older documents contain no new node
kinds, so their content migration is identity-preserving.

## Consequences

Insertion is one existing typed atomic transaction and one inverse. Defaults
are persisted with `.defaulted` provenance; user property editing, responsive
overrides, automatic sizing, advanced alignment, export parity, and broad CSS
layout semantics remain explicitly outside this slice.

## Rationale and reversibility

This is the owner-approved OD-015 reversible product baseline. Future schema
versions may add property editing or new layout modes with explicit migrations;
they must preserve these v1 values for existing nodes.
