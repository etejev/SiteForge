# Final native UI consistency pass

The owner requested one more pass over SiteForge for consistency and UI quality. Finish the current affected-test scope correction and its verification before changing the presentation candidate. This review uses the approved native redesign and Testing window as the design baseline.

The latest owner color decision uses macOS default gray backgrounds for the app's native surfaces, including Testing and the floating monitor. Use semantic AppKit/SwiftUI window, content, control and separator colors so appearance and accessibility adapt naturally. This replaces the earlier explicitly black Testing palette. Recheck other hard-coded black chrome during this pass and update the visual contract and final screenshots to the new decision.

Applicable bounded requirements include SF-0201-003/006/008, SF-0203-006, SF-0206-003/006/008, SF-0303-006, SF-0701-006, SF-1503-006, SF-1505-006 and SF-1607-006/008. Inspect the exact clauses for each correction and record the relevant IDs in the queue and evidence.

## Initial observations

The composer reviewed the retained installed Testing-window, paused, and floating-monitor captures in `.codex-loop/testing-progress/closeout/captures`. Recheck these observations against the current build before editing.

| Surface | Observation to resolve |
| --- | --- |
| Testing actions | Start Regular Testing and Start UI Testing have different widths. Use the same native size, style and baseline for these peer actions, including disabled states. Preserve the approved equal Pause/Resume and Cancel/Confirm Cancel controls. |
| Testing scope | The exact selector appears in the input and immediately repeats underneath. Present the input and a concise useful scope summary. Preserve complete inspectable execution scope. |
| Testing status | The retained completed view repeats passed status above and within the results block. Reduce redundant status copy. Verify that terminal states do not retain preparation messages or an in-progress retaining-results message after persistence has finished. |
| Run history | Rows lead with opaque IDs and raw code/ui modes. Present a readable date/time, Regular or UI type and outcome, using consistent selection styling. Keep the original run ID available in details and preserve exact report routing and accessibility identity. |
| Progress appearance | Check that the main Testing window and compact monitor share the requested thin rounded blue progress treatment and readable count/elapsed labels in active, inactive, paused and terminal states. |

## Review and correction

Use `docs/coordination/APPROVED_NATIVE_UI_REDESIGN.md`, the current visual contract, approved capture bundle, latest native receipts and `SiteForgeVisualSystem`. Preserve the approved layout and information architecture. Make small corrections to observed inconsistencies and reuse native control configuration and semantic spacing values where appropriate.

Review Start and its loading, error and recovery states. Inspect the editor's tool rail, viewport bar, both sidebar tab strips, Pages rows and hover actions, inspector fields, menus, popovers, sheets and the empty artboard. Cover every App Settings destination and representative Website Settings page. Review Testing before a run, during preparation and execution, paused/resumed, cancelled, failed, completed, and when viewing a retained run.

Check peer button bounds and baselines, icon sizes and hit areas, row and field heights, label/value alignment, section rhythm, corner and separator treatment, semantic typography, focus rings, selected and disabled states, truncation and long labels. Keep both editor tab strips on their common 41-point treatment. Keep Page actions stable during hover and keyboard traversal. Check that useful empty or error actions are available and status text reflects actual state. Retain the clean empty artboard.

Inspect dark and light appearance, supported compact and normal widths, increased contrast, Reduce Transparency and larger text where relevant. Testing and the floating monitor use the same semantic macOS gray surface family as the native app chrome and respect the app's resolved appearance. Main test windows launch within the usable desktop, with menu bar and Dock available. Intentional compact or reference dimensions apply in named review phases.

Capture representative native windows before and after corrections at the same window size and scale. Review the actual final pixels and compare fixed chrome regions to the approved renders. Record any remaining clipping, contrast or alignment defect with a concrete source location. Each reported correction needs a final capture that reaches that state. Readable native title bars, clean desktop captures and accessible focus behavior are part of acceptance.

## Verification and installation

Run local checks through the native Testing window's Start buttons. Select tests for the changed presentation and interaction boundaries. Reuse unaffected green receipts. If the work expands into a broad UI redesign, apply the full verification policy in `AGENTS.md`.

Review the final diff, update the queue, changelog, requirement status and evidence with observed results, and refresh the owner-local app. Verify its signature and source/harness fingerprints. Inspect the installed windows to confirm the fixes reached the normal Settings, editor and Testing entry points. Respect the normal save and quit flow for an open owner app. Leave verified changes local and uncommitted.
