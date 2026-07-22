# SF-AUTHORING-005 frame/text insertion evidence

Run `scripts/run-insertion-foundation-evidence.sh` from the repository root to execute the production insertion command validator, layout engine, and native renderer against 100- and 10,000-object fixtures. The command replaces `measurements.json` only after the focused XCTest succeeds, records five raw monotonic-clock samples per operation and capacity, and validates the retained record. `scripts/check-insertion-foundation-evidence.py` validates retained evidence during `./sf verify` without rerunning the benchmark.

The retained JSON names hardware, processor, OS, Xcode configuration, methodology, raw samples, nearest-rank P95 values, process resident-memory high-water mark, and limitations. Fixtures contain real canonical nodes, ownership edges, non-empty geometry, renderer tiles, accessibility snapshots, and deterministic digests; they do not substitute empty policy objects for authored capacity.

The running-app UI journey `testFrameTextInsertionCancellationUndoRedoAndSelectionJourney` retained screenshots in its XCTest result for committed frame, committed plain text, and cancelled editor-only preview states. It exercised toolbar/pointer insertion, Escape, undo, redo, stable Layers identities, and the production shell. The screenshots are retained in the `.xcresult` produced by `./sf test`; this repository does not copy machine-generated result bundles into source control.

This bounded evidence does not establish production text shaping, rich text, move/resize transforms, inspector editing, incremental layout, export parity, cross-hardware budgets, or release acceptance. The 10,000-object full layout and renderer measurements exceed one 60 Hz interval and therefore do not prove final interactive frame pacing.
