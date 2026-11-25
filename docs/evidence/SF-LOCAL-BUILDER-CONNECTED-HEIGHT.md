# Connected Header/Footer height

The model and native height journey passed desktop replay. The full local
run also passed both selectors. [Full-run evidence](SF-LOCAL-BUILDER-FULL-INVENTORY-20261102.md#november-14-desktop-closeout-replay)

Initial desktop replay on the later spacing fingerprint
`a0b37eb809ea0dd9eb9985b4ab86e5044094e58532842e225591d57a71e0b458`
passed the model selector in 0.095s. The native journey failed when a drag
anchored to the Header's virtual AX group edge left the Inspector at its
starting value. The replay now targets the real named bottom resize handle
and keeps all width/height, Undo, identity, Preview and reopen assertions.
The initial bundle is `focused-538593ee-0244-43a7-82f2-edd97b615173.xcresult`
in the temporary `siteforge-desktop-closeout-20261114` results folder.

Process-scoped Xcode 27.2 `build-for-testing` exited 0 with
`TEST BUILD SUCCEEDED`. The local transcript is
`siteforge-connected-height-build-final-20261114.log` in the temporary
directory. Xcode used the project’s existing local ad hoc build signing.
No XCTest methods or app/browser launches ran. Candidate base
`013393965a49f925d42fd5d8ba82497bdd83c79b`, source/test/tool diff SHA-256
`5b49cdb975deb7bf3b24d5da9b60af1cdfa7d7d62d6ca0ef48ed61149410c021`.
Use the fingerprint command in the earlier acceptance inventory.

Bounded SF-0403-002/003/004/006 cover the bottom-edge preview, commit,
cancellation and equivalent Inspector input. SF-0501-003/004 cover the
scope-specific structural height and fallback. SF-0602-003/004 cover the
viewport context. SF-0702-003/004/006 cover the height field, provenance
and stale-draft recovery.

A viewport-width change already cancels the active page-flow gesture
before publishing the new width. The remaining pointer failure was a
drag returning to its starting height. The old commit still offered the
inherited value to the typed registry, which could author a new override.
The height gesture now starts only with a current renderer scene, retains
its exact opening scope, and drops a zero-effect release. The Inspector
captures the same scope with the first typed edit and rejects stale
submissions with the existing Escape recovery. An explicit Apply Height
can still author an override equal to its inherited value. Calculated
heights keep their existing read-only presentation and explain their source
and current screen size.

The existing page-structure command owns the write and history. Layout
placement, responsive cascade, native Preview and static projection still
use the same canonical data. The shared Footer path receives the same
guards. Section reorder and ordinary transform paths retain their behavior.

Verified selectors:

- `SiteForgeTests/InsertionModelTests/testConnectedHeightGestureAndDraftKeepResponsiveScopeAndExactHistory`
- `SiteForgeUITests/SiteForgeLaunchTests/testConnectedHeaderFooterNavigationMenuHeightUndoAndReopenJourney`

The model fixture covers cancellation on width switch, stale scope
rejection, a zero-effect drag, an explicit inherited-value override and
exact Undo/Redo. The UI journey adds a native Header bottom-edge drag,
checks the Inspector and stable identity, and undoes the drag before its
existing numeric edit and Preview/reopen checks.
