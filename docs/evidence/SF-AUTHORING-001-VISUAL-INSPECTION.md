# SF-AUTHORING-001 visual inspection

Date: 2026-07-21

## Environment

- MacBook Air `Mac16,13`, Apple M4 (10 cores)
- macOS 27.0 build `26A5378n`
- Built-in 2880×1864 Retina display; application-reported backing scale 2×
- Local Debug application built by `./sf build`; reversible bundle identifier `app.siteforge.SiteForge`
- No distribution signing, publication, credentials, or external project data

## Method

The production Debug application was launched with the repository's explicit Debug composition arguments. The accessibility hierarchy and captured application surface were inspected after each state change. Zoom and pan were driven through the real native controls and View-menu keyboard shortcuts. Existing UI automation also retains screenshots for minimum size, light/dark, material, inactive, and accessibility fallback variants.

## States genuinely inspected

| State | Observation |
|---|---|
| Default window, dark appearance, active policy | Navigator, viewport controls, canvas, inspector, status bar, and unified toolbar remained separated and readable. The 1440×900 bounded artboard clipped naturally inside the viewport without overlapping chrome. |
| Minimum 1100×700 content size | All viewport controls, both sidebars, the status bar, and the centered bounded placeholder remained present without clipping or overlap. |
| 100% and 125% zoom | Artboard size and origin changed coherently; the accessible value changed from 100% to 125%. Cursor-anchor invariance is proven deterministically in unit tests rather than inferred visually. |
| Positive and negative pan | Repeated Option–Right reached world origin `+626.4`; repeated Option–Left reached `-1958.0`, near the declared `-2048` padding bound. Chrome remained fixed while canvas content moved. |
| Light appearance | Native materials, white artboard, separator, placeholder, navigator selection, and status content remained distinguishable; no new static glass simulation appeared. |
| Dark appearance | Artboard, canvas surround, overlay placeholder, materials, selection, and status remained distinguishable. |
| Retina scaling | The app ran on the built-in 2× Retina display; the artboard separator remained one device pixel and coordinate status stayed stable. Additional 1×/1.5×/2×/3×/4× conversion behavior is automated. |
| Reduce Motion | The Debug Reduce Motion override produced the same immediate viewport state changes with no viewport animation. Loading-state static-progress regression coverage remained present. |
| Active and inactive policy | Both normal active capture and the explicit inactive-window material policy were exercised; viewport input semantics and region separation remained present. |

## Accessibility observations and limitations

The native viewport exposed a group role, the label “Canvas viewport,” current zoom/origin/interaction value, usage hint, and Zoom In, Zoom Out, and Reset View actions. Controls exposed independent labels and stable identifiers, and automation traversed the viewport controls and canvas in both directions.

This inspection did not run VoiceOver speech, change the system Reduce Motion setting, test an external non-Retina display, or establish owner-approved minimum/reference hardware. Debug appearance and motion overrides plus semantic automation are bounded engineering evidence, not release accessibility certification. Real rendered-object accessibility virtualization belongs to `SF-AUTHORING-003`.

## Result

No clipping, overlap, stale visual adoption, canvas/chrome hit-test interception, or appearance regression was observed in the inspected states. The surface remains an intentionally bounded viewport foundation: it draws only an artboard and placeholder and does not claim production layout, rendering, selection, overlays, or editing.
