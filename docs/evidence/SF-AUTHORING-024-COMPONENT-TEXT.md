# SF-AUTHORING-024 — Exposed component plain text

## Bounded contract

Bounded SF-0902-001–008 and SF-0905-001–008 remain Partial. This slice exposes
one plain-Text source as a named stable property, with independent string
overrides on single linked instances. Definition content is the sole default;
empty strings are authored, while absence inherits. Apply/Return commits one
identity-gated atomic operation; Cancel/Escape changes no canonical data.
Reset one/all removes override properties, not equivalent literals.

ADR-0018 documents schema v8, stable definition/property addressing, limits,
the shared derived resolver and the non-destructive removal policy. Every
canonical command result is checked before publication: sources/bindings may
not be removed or retargeted while surviving overrides depend on them. Loaded
unresolved values remain preserved and inspectable, with explicit reset.
Detach requires resolvable intent and materializes effective text. Metadata is
excluded from derived website nodes; virtual children are not command targets.

The existing package/resource/history/recovery architecture is unchanged.
`Tests/Fixtures/Legacy/schema-v7-linked-text-document.json` is a checked-in
historical-format document with fixed IDs, two instances and one defaulted
Text source, not a fixture synthesized inside the test. Older schemas gain no
bindings; historical namespace smuggling is rejected. Resource references and
bytes survive linked page duplication, save and owned recovery.

## Focused results

Passing focused model evidence in `CommandKernelTests`:

- `testComponentTextV7MigrationAndStrictBindingValidation`
- `testComponentTextIndependentEmptyOverridesDefaultPropagationAndExactResetHistory`
- `testComponentTextStaleCancelledInvalidAndVirtualTargetsAreNeutral`
- `testComponentTextSourceRemovalGuardAndUnresolvedIntentPreservation`
- `testComponentTextEffectiveDetachAndPageDuplicationPreserveStableIntent`
- `testComponentTextImmutableRendererAndAccessibilityUseEffectiveRevision`
- `testComponentTextMultipleBindingsResetAllAndNoOpPreserveExactPresence`
- `testComponentTextDraftIdentityWaitsForAdoptedRevision`

Affected existing checks also pass:

- `CommandKernelTests/testComponentExpansionBudgetCancellationAndCollisionAreMutationNeutral`
- `ProjectResourceTests/testComponentDefinitionResourcesSurviveLinkedDuplicationSaveAndRecovery`
- `ProjectPackageTests/testCanonicalPackageBytesAreDeterministicAndVersioned`

The native two-instance journey passed 1/1 (227.775 seconds):
`SiteForgeLaunchTests/testComponentTextPropertiesTwoInstancesResetHistoryAndReopenJourney`.
Its first execution reached definition exposure, independent instance text,
default propagation, reset/undo/redo and Escape. A zero-timeout test waiter
interrupted AX snapshot evaluation; the helper now queries the live exact
text value without a zero-duration waiter. Assertions and application behavior
were not weakened. A later run exposed a real draft/adoption race following
Undo/Redo: the Inspector captured a renderer generation before the current
canonical revision was adopted. Draft identity is now available only for a
matching document/revision/scene snapshot, and the Inspector refreshes when
that generation is adopted. The independent draft-identity regression and
the complete UI journey pass. Total unique focused acceptance: 11 non-UI
tests (eight new, three affected) plus one UI journey, 12/12.

## Visual review and milestone gate

Five original-resolution window captures from the passing journey were reviewed:

- `45D3E503-4ED1-42B8-B209-55EBBB2F7B88.png`: exposed definition text.
- `E137A538-5890-4DE1-BBDE-655AF7A9577E.png`: independent instance override.
- `061FBD91-3AB0-4EA3-B99D-24A5321C7D00.png`: default propagation preserves override.
- `44891D56-ACA5-4833-8B7F-255A700F9A34.png`: reset history and cancelled draft.
- `71837DFA-2D96-4638-B41F-8E9667B43F1F.png`: reopened linked properties.

The Content controls and provenance are readable; text is upright and agrees
with each independent instance, selection outlines remain aligned, and the
artboard/pasteboard hierarchy is preserved. No new ghost objects or Inspector
clipping was observed. The existing navigator overflow remains unchanged.
Captures are retained in the focused result bundle
`focused-b33e3c6e-6399-4b3a-9bbd-a86d4d9f30b4.xcresult`.
The passing log contains no publish-during-view-update or invalid-geometry warning.
The first authoritative gate found one outdated package-manifest assertion
expecting schema 7 rather than 8 (427/428 non-UI tests passed). That already
failed run was interrupted before wasting a complete UI pass. The exact
package assertion now checks schema 8 and its focused selector passes 1/1;
historical decoding/rejection and byte determinism assertions remain intact.
The corrected gate passed 428/428 unit/integration tests. Its first UI journey
could not activate SiteForge (Running Background); direct native-app inspection
confirmed the Mac was locked and could not be automatically unlocked. The run
was interrupted instead of repeating activation failures. Unlocking the Mac is
required before the remaining UI/full gate can complete. The retained result is
`full-49654d23-bb4e-4ba1-b3d8-845894046ec7.xcresult`. This is not full or hosted
acceptance; SF024 remains IN PROGRESS and uncommitted.

After unlock, the next completed gate passed 428/428 non-UI and 59/60 UI tests.
The compact Inspector tab journey alone failed on XCTest's horizontal-scroll
hit-point lookup; its existing native overflow-menu route subsequently passed
1/1 (54.269 seconds), with all authoring assertions intact. The separately
reported pointer/composition defect is tracked in SF-CANVAS-POINTER-001 and
shares the next authoritative gate. No unchanged SF024 focused rerun is needed.

## Final combined gate

Final local acceptance on September 13: the combined `./sf verify` passed
429 unit/integration + 61 UI = 490 tests, zero failures. The component-text
journey passed in 253.353 seconds within the gate. Repository/security,
traceability, architecture, migration and evidence checks passed. Result:
`full-20d3f1fe-cbca-4099-b029-d9a9c449e92c.xcresult`. The log contains no
publish-during-view-update or invalid-geometry warning. Hosted confirmation
is pending; the prior failures above are historical and corrected.

## Explicit exclusions

Media, boolean, enum and action properties; slots; variants; nested components;
arbitrary style/per-child overrides; multi-instance bulk property editing;
remote libraries; preview/export/runtime parity; broad localization/assistive
technology/performance certification and release acceptance remain deferred.
The existing expansion budget and keyboard/accessibility paths are retained;
this evidence does not claim the full normative component modules complete.
