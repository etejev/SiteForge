# Quick batch integrity repair — November 25

Owner-authorized repairs following the read-only review of Quick batches 01–06.
Bounded SF-0903-003/005/008, SF-0304-003/005, SF-0308-003/005,
SF-0602-003/008, SF-0204-004/008, SF-1201-004 and SF-1902-007/008.
No module completion, runtime acceptance or new installation is claimed.

## Repairs and regression coverage

- Slot coordinate conversion now creates responsive x/y overrides when changing
  coordinate domains would otherwise change inherited positions. Existing property
  identities stay stable. Reparent commands include new properties rather than
  comparing only the zipped old/new prefix. Regression:
  `CommandKernelTests.testSlotCoordinateConversionMaterializesOnlyRequiredResponsiveOverrides`
  checks all breakpoints, unchanged inheritance where possible, undo/redo and
  document serialization.
- Slot origins resolve through the same expanded/sized page geometry used by
  painting instead of a definition-sized cached layout. This includes copies with
  different sizes and slots belonging to supplied nested instances. Regression:
  `CommandKernelTests.testSlotOriginsMatchRenderedLayoutForDifferentlySizedCopies`.
- The Aurora Flow recipe now requires a frame for every expected visible non-root
  object, including links and QR images, rather than skipping missing frames and
  checking only text/stack/grid objects.
- The browser harness validates an executable Chrome prerequisite and gives
  installation/environment guidance. Missing and non-executable override checks
  are included in its helper suite. Hosted core setup explicitly provisions Chrome;
  no hosted action was run or published.
- Compiling the previously uncompiled Quick tests found an overlapping-access
  error in the nested-missing-definition fixture. The missing ID is captured before
  mutating the fixture's pages; all assertions remain intact.
- Compilation also exposed a nearly-matching optional WebKit delegate callback.
  Its decision-handler closure now has the SDK-required MainActor isolation so the
  intended local-preview navigation policy implements the protocol requirement.
  Navigation is restricted to the owned preview document. Regression:
  `CanvasTextRenderingTests.testFlowPreviewRegistersNavigationGuardAndRejectsExternalDestinations`
  checks the Objective-C callback registration and local/external URL policy.

## Verification checkpoint

The repaired app initially built successfully through the owner-local packager
without installation. Python harness/helper AST syntax checks and whitespace
review passed. The first full build-for-testing caught the Swift exclusivity
error described above; it was corrected and the second build-for-testing passed
for both architectures. The final build, including the added navigation
regression, also passed for Apple silicon and Intel.
Logs and before-edit file copies are retained under the ignored
`.codex-loop/review-integrity/` directory.

Final prepared source fingerprint:
`a2f3281261421253f31d6851fb075588b8541d2ec149a14a87006f3bff76900b`.
The staged bundle under Documents acquired iCloud/Finder extended attributes and
failed strict signature inspection. A clean ad-hoc candidate copy outside iCloud
passes strict signature verification and retains the same source fingerprint.
The installed application was not replaced.

After the owner unlocked the Mac and desktop access became available, Codex
pressed the real Start Regular Testing button. Run
`20261125-195113-0d258f7a` executed 19 exact selectors at the fingerprint
above: collector ledger 15 passed, four failed. Selectors and the candidate location are retained
in the ignored review directory. Native journeys and the final full gate remain
pending. No headless route was substituted, no passing test receipt was fabricated,
and no owner project/recovery or commit was changed.

## Failure diagnosis and replay

The first run confirmed the inherited-coordinate fix, navigation delegate guard,
actual native/WebKit alpha parity, and history/resource paths. It also exposed:

- Paste preparation clears `childIDs` before building insertion commands, so
  traversing those arrays skipped descendants during coordinate conversion.
  The traversal now follows the already-remapped parent references, while still
  stopping at component boundaries.
- The new resized-copy Stack fixture omitted its required gap. The fixture now
  supplies the complete structural contract; validation remains strict.
- Bounds assertions found navigation overflow. New footer rows give the title
  content-fitting width and navigation remaining width. The sample Header uses
  equivalent sizing. Assertions account for actual collapsed-menu members, as
  the native renderer does, while retaining coverage of normal links/images.
- Browser captures showed JavaScript masking a static-output positioning bug:
  the advanced style emitter overwrote fixed absolute geometry with an omitted
  positioning mode's default static. Only authored static may now override it.
  `SupportSettingsTests.testFixedOutputPreservesDefaultPlacementAndHonorsAuthoredStatic`
  adds explicit coverage alongside the actual-browser comparisons.
- An attached crash report exposed a separate stale test-array index after
  removal. The fixture now re-finds its slot by stable ID before mutation.

Run `20261125-195942-86018531` stopped in preflight: Git source enumeration
timed out after 120 seconds. It executed no test methods and provides no product
pass/failure evidence. The native Cancel confirmation was requested during this
preflight, but the saved terminal outcome is Blocked rather than Cancelled.

The repaired candidate builds and has a clean, strictly verified ad-hoc copy
outside iCloud. Native Start Regular replay `20261125-200321-c945f41f` completed
19/20 passed. Geometry, clipboard, real-browser fallback/hit testing, navigation
policy and history checks passed. The recipe failed because horizontal Hug sizing
is not supported; the model correctly rejected that authored value.

Replay `20261125-200750-8b8b58df`, source
`a055c0ca04a7c6a6253cfe16e56923ae9f2c768fb83ea2c45e84976d0e968bee`,
again passed 19/20. All responsive bounds passed; export preflight reported four
findings. The narrow-menu allocator requires default title provenance and refuses
an authored sizing constraint even when fixed. The candidate now leaves the
default title untouched and sets only navigation to Fill; export failures also
report finding codes directly. No validation rule was waived.

Native Start Regular final affected replay `20261125-201323-26ef8307` passed
4/4, no failed or skipped methods, at source
`d6a378aef12b3efbacc06a4bbfd9364e5e936e198751b5b87e1941df72f13f01`.
It covers recipe generation/responsive bounds/QR/save/template loading, footer
reuse, the actual-browser runtime ledger and explicit/default positioning. The
earlier unchanged geometry/clipboard/history paths retain their separate 19/20
receipt; that receipt is not represented as a complete green run.

The actual Start Full Verification button launched `20261125-201801-d8042c0e`
for repository checks and both complete targets at this same frozen source.
Repository checks and compilation passed. XCTest returned an empty UI inventory
after failing to enable automation mode, and neither test target executed. Native
UI acceptance and owner-local installation remained pending. See the
[November 26 integration review](../reviews/QUICK-INTEGRATION-2026-11-26.md)
for the larger candidate.
