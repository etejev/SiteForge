# SF-SOURCE-BATCH-20261027-03 — Connected structural layout

Current receipt: the listed new model methods and actual-app journey have passed
current-source affected acceptance. Final full verification passes:785 non-UI,
151 UI,0 failures,3 intentional owner-session skips; full-e7ee511e is the
authoritative939-method result. The bounded local slice is accepted.
The implementation-time UNRUN/owner-hold text below is historical and superseded
by approved local acceptance. Exact correction results and inspected screenshots
are indexed in [the integration receipt](SF-SOURCE-BATCH-20261027-10-INTEGRATION.md).
Normative modules remain Partial; no push or installation is authorized.

**IMPLEMENTED IN SOURCE — NOT BUILT/TESTED; OWNER TEST APPROVAL REQUIRED.**

Queue remains IN PROGRESS; normative modules remain Partial. No tests, builds,
check/lint scripts, UI automation, readiness probes, app/browser acceptance
launches, screenshot capture or runtime/visual review were performed for this
slice. Static source/diff inspection only. No new accepted screenshot exists.

## Bounded contracts and inspected existing behavior

- SF-0501-003/005/006: shared geometry/provenance, exact history and native
  operation of existing layout state.
- SF-0502-003/006 and SF-0503-003/006: truthful computed Stack/Grid spacing and
  keyboard/accessibility access to the command which actually owns that value.
- SF-0505-003/005: preservation/regression source for containing width, Hug,
  min/max/aspect intent and history; not completion of all sizing combinations.

ADR-0020 already supplies explicit connected Section insertion/conversion,
Header/Footer anchoring, canonical child order and reversible flow reorder.
ADR-0025 supplies containing-width-first Fill/Hug measurement and shared text
metrics. Existing native direction/alignment, Grid columns, gap/padding, sizing,
responsive visibility and reset commands were inspected, not reimplemented.
Free Frames and unconverted legacy pages retain their existing opt-in behavior.

Wrapping, space-between/distribution, advanced tracks and spanning are not in
this bounded canonical container model. Existing horizontal/vertical Stack,
start/center/end/stretch cross-axis alignment, and equal-column row-major Grid
remain the supported alternatives. No placeholder controls or new schema.

## Concrete source correction

`SiteForge/TransformModel.swift`: ContainerLayoutCommandRegistry inspection now
accepts viewport width and passes it to ResponsiveContainerLayoutResolver. The
previous call omitted width, so fluid padding/gap inspection read fixed fallback
values while layout/output already evaluated the fluid record. Preparing a
Desktop fixed spacing edit/reset now rejects with typed `fluidValueWins` when
that property has a fluid record. Validation/cancellation/identity checks remain
ahead of mutation. One fluid member rejects the whole attempted fixed edit;
other selected members do not get a partial transaction. A fixed field never
silently removes fluid intent. Sanitized diagnostics add only the closed failure
category `fluid-value-wins`, not authored values or content.

`SiteForge/WorkspaceShellModel.swift`: value and source projections use the same
current preset width as layout. The resolver also accepts supplied widths, but
this slice does not add a native custom-width control. Existing fluid metadata remains canonical;
sampled values are read-only. Connected structure exposes only its supported
fluid padding/gap targets in the existing editor, retaining dimension ownership.
Tablet/Mobile fixed overrides still win through the existing responsive resolver;
Reset Override removes only that device property and restores fluid inheritance.

`SiteForge/WorkspaceShellView.swift`: Container Layout shows the effective value,
explicit source, readable explanation and a native Edit Fluid Values button.
The button scrolls to the real existing Fluid Value card; its help explains the
property picker. Managed Section/Stack/Grid spacing is no longer hidden behind
the all-managed-structure exclusion. Unsupported managed width/height controls
remain absent. The card starts at an applicable target, not an unsupported Width
for a managed Section. Existing local draft, Apply/Remove, Escape, central fluid
registry and history paths are reused. Source labels have stable accessibility
identifiers, explicit values and full help. No hidden automation path/direct view
write or parallel layout calculation was added.

Existing renderer and shared connected CSS already use the responsive/fluid
container resolver with width. They were preserved rather than given a second
formula or generated-output patch. Existing Design box-padding precedence is
unchanged; this bounded correction concerns fluid versus fixed container values,
not a new composition or style-cascade architecture.

## New acceptance source — seven methods, all UNRUN

1. `TransformModelTests/testContainerFluidSpacingInspectionUsesViewportAndReportsMixedValues`
2. `TransformModelTests/testContainerFluidSpacingCommandsPreserveOverridesAndExactHistory`
3. `TransformModelTests/testContainerFluidSpacingMixedRejectionIsAtomicAndRedacted`
4. `TransformModelTests/testEmptyFluidContainersResolveHugWithinBoundsWithoutRewritingFallbacks`
5. `InsertionModelTests/testManagedSectionFluidPaddingUsesLiveInspectorAndPreservesFlowHistory`
6. `InsertionModelTests/testNestedFluidContainersShareHugConstraintsHiddenChildrenAndOutputGeometry`
7. `SiteForgeLaunchTests/testConnectedContainerFluidSpacingNavigationOverrideResetAndCancelJourney`

Intended coverage: six widths (320/390/574/768/1024/1440), fluid and explicit-device
precedence, mixed/applicable/skipped presentation, ignored Desktop edit/reset
rejection, invalid/cancel/stale neutrality, separate override/reset/fluid-removal
history, exact PropertyID/origin restoration, serializer reopening and unchanged
fixed fallback. Empty Stack/Grid Hug heights stay bounded; nested Section/Grid/
Stack uses real containing width, wrapped text, Image aspect/min/max intent,
breakpoint-hidden children and immutable native render frames. Shared CSS retains
fluid expressions and Hug behavior without rewriting authored data. Connected
reorder preserves Header/Footer anchors and exact Undo/Redo.

The native journey source uses real Elements/Inspector/preset/menu controls:
connected Section plus real Frame, fluid creation, displayed effective spacing,
disabled ignored fixed field, navigation to Fluid Value, invalid draft/Escape,
Tablet override/reset/Undo/Redo and explicit fluid removal/Undo. Its three named
screenshot attachments are future evidence only; none has been captured or
visually accepted. No test execution or passing total is inferred from source.

After separate owner approval, run these exact affected selectors and the
existing `testContainerLayoutRegistryValidatesMixesResetsAndPreservesExactHistory`,
`testResponsiveCardSubtreeReflowsAtFreeWidthsWithoutRewritingIntent` and
`testStructuralLayoutInspectorReflowsSectionStackAndGridJourney` as appropriate.
Then required runtime/pixel/visual and final integrated verification remain.

## Preserved boundaries / remaining acceptance

No architecture/data migration or new owner decision was required. OD-018/019
remain unchanged. No owner package, approved Dark Flow gradient, project resource,
export, recovery, screenshot, cache or installed app was changed. No signing,
commit, push, external/GitHub mutation or scheduled follow-up was performed.
Editor references 01/05 inform the reused compact card/field hierarchy; Settings12
is not copied into an unrelated scope. Their actual visual conformity, compact
layout, keyboard/focus behavior, renderer pixels, browser parity, scale and
performance remain unverified until owner-approved execution. The historical
cancelled partial gate does not cover this source. Full verification remains
mandatory before any completion claim; the testing hold is not waived.
