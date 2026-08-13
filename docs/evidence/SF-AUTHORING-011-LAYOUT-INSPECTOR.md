# SF-AUTHORING-011 — Fixed Layout Inspector geometry evidence

## Scope

This bounded slice adds native Inspector draft fields for `X`, `Y`, `Width`,
and `Height` on canonical Frame, Text, Section, Stack, and Grid nodes. The
fields use the existing `layout.x`, `layout.y`, `layout.width`, and
`layout.height` properties; they do not add a second geometry store, size
modes, constraints, responsive overrides, rotation, skew, or automatic sizing.

## Contract and verification

- `GeometryInspectorCommandRegistry` validates typed document/page/revision,
  canvas scene/renderer generation, selection identity, availability, locks,
  visibility, finite canonical numeric bounds, and applicable node kinds before
  preparing one existing-property batch command.
- Locale-formatted strings remain scene-local draft state. Return commits;
  complete drafts also commit on native focus loss; Escape restores the last
  committed display value. Empty, partial, malformed, nonfinite, out-of-range,
  and non-positive width/height values are rejected without mutation.
- The central document session supplies the exact transaction/inverse, history,
  renderer, selection, Layers, accessibility, persistence, autosave, recovery,
  and reopen adoption behavior. Inspector-only drafts and announcements do not
  serialize.
- A mixed selection exposes `Mixed`; incompatible selected kinds are named as
  unchanged rather than coerced. The applicable subset is committed as one
  atomic batch.
- Inspector diagnostics have their own `geometry-inspector.<field>` operation
  type, stable-ID digests, duration, revision transition, count, typed result,
  and failure category. They do not contain authored values, text, paths, or
  raw identifiers.

## Commands and results

On 2026-08-13 (local macOS Debug/XCTest composition):

| Command | Result |
|---|---|
| `./sf test focused SiteForgeTests/TransformModelTests` | 16 unit tests passed |
| `./sf test focused SiteForgeUITests/SiteForgeLaunchTests/testGeometryTransformPointerKeyboardNumericUndoRedoAndAccessibilityJourney` | 1 actual-app UI journey passed; retained attachment `SF-AUTHORING-011 fixed geometry fields` |
| `./sf test half` | 306 unit/integration tests passed |
| `./sf verify` | 306 unit/integration + 33 UI tests passed (339 total); repository, security, traceability, architecture, migration, evidence, and fixture-hygiene checks passed |

The retained XCTest attachment was reviewed for readable X/Y/Width/Height
fields, selected-object geometry, native inspector contrast, and normal
maximized-window composition. It is an XCTest result attachment, not a tracked
machine screenshot path.

## Limits

The `SF-0403` and `SF-0505` normative modules remain Partial overall. This
slice does not prove responsive provenance, size modes, min/max constraint UI,
aspect ratio, auto sizing, rich-text geometry, broad property editing,
OS-level VoiceOver/settings acceptance, cross-hardware performance budgets,
export, or release acceptance.
