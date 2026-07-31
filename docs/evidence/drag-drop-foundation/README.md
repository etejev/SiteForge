# SF-AUTHORING-009 Drag-and-Drop Foundation Evidence

This directory retains reproducible capacity evidence for the bounded local
reorder/nesting foundation mapped to `SF-0408-001` through `SF-0408-008`.

Run:

```sh
scripts/run-drag-drop-foundation-evidence.sh
scripts/check-drag-drop-foundation-evidence.py
```

The benchmark exercises the production Foundation-only drag registry against
real canonical 100- and 10,000-node sibling hierarchies. It records raw
monotonic-clock samples, environment, resident-memory high water, methodology,
and limitations. It is not a renderer, native drag tracking, or final 60 Hz
budget. Drag previews, hover state, payloads, indicators, and sessions are
editor-only and never serialised into packages, history, recovery, preview, or
export snapshots.

`layers-contextual-reorder.png` is the retained 2026-07-31 running-app
evidence from `testLayersContextualReorderShowsAccessiblePreviewAndUndoRedo`.
It shows the Layers navigator after a shared-registry reorder, the authored
canvas, native chrome, inspector summary state, and status bar. The capture
contains no project-file paths or authored text. It is evidence for the
contextual/accessibility adapter and undo/redo adoption; it does not claim that
XCTest synthesized a native AppKit drag gesture.

Verification on 2026-07-31: six focused drag model tests, the retained
running-app journey, complete UI target (29/29), and `./sf verify` (248 unit +
29 UI tests) passed. The verifier also validated this evidence shape, the
headless drag registry boundary, repository hygiene, security scanning,
traceability, and migration checks.
