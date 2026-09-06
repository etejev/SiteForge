# SF-AUTHORING-020 — Button and Link authoring

Status: locally verified. Hosted acceptance is checked after the commit.

Final `./sf verify` passed on 2026-09-05: 399 unit/integration + 52 UI =
451 tests, zero failures. Repository/security/traceability checks passed.
Result bundle: `full-baa4d050-37a0-4e41-9c16-965ad9fa6653`.
The findings below retain failed-run chronology rather than masking it.

## Bounded contract

SF-0806-001–008 and SF-1102-001–008 remain Partial. This slice adds
local Button/Link label and navigation-intent authoring, not navigation in
the editor or published website runtime behavior.

Button and Link use schema-v6 node kinds, the existing insertion registry,
property transactions, immutable renderer snapshots, and geometry/visibility
resolution. Labels and targets use closed `content.control.v1` and
`interaction.link.v1` namespaces. Targets reference PageID and optional
Section NodeID, or a validated credential-free HTTP(S) URL. Missing internal
targets remain representable; removing a target reveals omitted/no-target
semantics without deleting its owner. Reset removes properties, and inverses
retain property identity, order, values, and provenance.

The checked-in `Tests/Fixtures/Legacy/schema-v5-blank-document.json` was
produced by the historical encoder at `70e7c42`. Historical documents remain
empty until actual insertion. Schema-v5 payloads cannot introduce new kinds.

## Focused findings and corrections

- The Elements action now inserts Button/Link through the same one-shot
  transaction as Insert menu actions. Tool-based pointer insertion and
  cancellation also recognize the new kinds.
- Native field bezels require padding inside the Inspector scroll viewport;
  the clipping assertion remains unchanged.
- Button label foreground resolves from the immutable fill snapshot to avoid
  light dark-mode text over a light Button surface. Text geometry is unchanged.
- Return and native focus-loss callbacks share scene-local drafts. Identical
  binding notifications must not mark an already-consumed draft dirty again.
- Persisted history previously rejected legitimate revision gaps after
  undo/redo and branching. Validation now permits gaps but rejects overlaps,
  reversed order, future revisions, and invalid exact inverses.

## Evidence so far

All six `LinkAuthoringTests`, the control glyph pixel test, all fifteen
`PersistedHistoryTests`, two Inspector/catalog metadata checks, and twenty-one
insertion tests passed in the affected 46-test run. The remaining insertion
test exposed a scheduler-dependent yield count; it now awaits actual scene
and selection publications and passed independently (1/1). No assertion was
removed or changed to accept stale state.

The fresh-process
`SiteForgeLaunchTests.testButtonLinkContentTargetsUndoRedoAndReopenJourney`
passed (1/1), including a second visual-evidence run with separately positioned
objects. `testButtonLinkMixedAndIncompatibleContentJourney` passed (1/1),
proving atomic compatible edits, partial applicability, and unavailable
Text-only selection. The refined mixed journey and
`testButtonLinkInternalTargetControlsAtPracticalMinimum` then passed together
(2/2). The latter proves native page/context selection, target removal and
undo at the 1100-point practical minimum.
Retained recordings exposed the bezel overflow,
label contrast, and duplicate end-edit status issues above. These were treated
as defects, not accepted visual evidence. An initial automation-mode timeout
occurred before the app launched; after owner intervention XCTest launches
normally. No broad gate has been run for this incomplete feature.

## Remaining acceptance

Focused acceptance is complete: 46 affected non-UI selectors passed across
the group and corrected event-based rerun; all three new UI journeys passed.
The final repository-inclusive milestone gate subsequently passed (above).
Only post-commit hosted acceptance remains to be checked.

The initial gate exposed two stale toolbar/schema expectations; both were
corrected to the explicit new contract and passed (2/2). The subsequent
gate passed all 399 non-UI tests but exposed an older shadow pointer helper
accepting a field below the Inspector viewport. That journey now uses the
existing safe-intersection/live-query/focus helper for border, radius,
shadow and Escape. Its focused rerun passed (1/1), without changing authored
behavior or weakening focus, shadow commit, cancellation or undo assertions.
The first two failed gates were stopped before running unchanged remaining UI tests.

The completed integration run passed 399 non-UI and 50/52 UI tests. Its only
failures were pre-feature expectations that Button/Link and all Content/
Interactions remained unavailable. The catalogue assertions now require the
new controls enabled while Divider/Navbar/Footer remain disabled. Empty
Inspector selection retains its explicit Nothing Selected state and no
editable control; incompatible selected-node coverage remains unchanged.
No invalid-geometry or publish-during-view-update warning was found in that
run. Both corrected selectors passed independently. The empty-state message
now exposes one semantic accessibility element instead of duplicate labeled
children. Final clean verification then passed all 451 tests.

## Visual review

Original-resolution XCTest attachments were inspected for Button label,
external target, cancellation, separately positioned Link, reopened document,
compatible mixed, partial and unavailable selection, and compact internal
page target/removal undo. Native Inspector controls are legible and contained;
labels are upright and within selection bounds; the fitted artboard/grid
hierarchy remains intact. Controls do not follow authored navigation.

Retained attachment bundle identifiers (temporary results stay outside Git):
`focused-aa1efc97-5cb1-4d36-8a6f-74389fa5df10` for label/target/reopen;
`focused-9601dd8f-1fca-4446-afa7-2dada3e4ac64` for compact and mixed states.
Key attachment names are `SF-AUTHORING-020 link selected`,
`SF-AUTHORING-020 reopened`, `SF-AUTHORING-020 compact internal page target`,
`SF-AUTHORING-020 compatible mixed labels`, and
`SF-AUTHORING-020 incompatible selection`.

Deferred: embeds, remote previews, network fetching, downloads/custom schemes,
analytics/runtime navigation, state styling, multi-action graphs, animation,
export/publishing, advanced variants, CMS/data binding, components, broad
performance/accessibility matrices, and release acceptance.
