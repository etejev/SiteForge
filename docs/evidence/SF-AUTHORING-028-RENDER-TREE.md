# SF-AUTHORING-028 — Render-tree compilation foundation v1

`InternalRenderTreeCompiler` is pure and consumes immutable adopted Preview
snapshots. It preserves source NodeID/paint order and derives semantic intent
and collision-free CSS selector metadata. It generates no files and cannot
mutate documents, history, packages, preview state, or UI state.
