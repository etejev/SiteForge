# Connected Header/Footer spacing

The model and native spacing journey passed desktop replay. The full local
run also passed both selectors. [Full-run evidence](SF-LOCAL-BUILDER-FULL-INVENTORY-20261102.md#november-14-desktop-closeout-replay)

Focused desktop replay on the compiled fingerprint below passed both exact
spacing selectors. The model passed in 0.108s and the native journey in
145.183s in `focused-538593ee-0244-43a7-82f2-edd97b615173.xcresult`
under the temporary results directory `siteforge-desktop-closeout-20261114`.

Process-scoped Xcode 27.2 `build-for-testing` exited 0 with
`TEST BUILD SUCCEEDED` using the existing local ad hoc build signing.
The transcript is `siteforge-connected-spacing-build-final-20261114.log`
in the temporary directory. No XCTest methods or app/browser launches ran.
Candidate base `013393965a49f925d42fd5d8ba82497bdd83c79b`, source/test/tool
diff SHA-256 `a0b37eb809ea0dd9eb9985b4ab86e5044094e58532842e225591d57a71e0b458`.
Use the fingerprint command in the local acceptance inventory. The earlier
height build receipt still describes its own candidate.

Bounded SF-0501-003/004 cover Inner Spacing precedence and safe recovery.
SF-0502-003 covers the navigation Stack’s resolved Link Spacing. SF-0602-003/004
cover exact viewport ownership, including free widths within a breakpoint.
SF-0702-003/004/006 cover Inspector provenance, validation and keyboard recovery.

The previous Inner Spacing field refreshed on document/selection identity
and submitted with the live breakpoint. A width change can retain that
identity, leaving old text in the field. The previous Link Spacing field
carried a breakpoint and the registry rejected mismatches. Its viewport
observer reset the spacing draft, title draft and custom Contents gap.

Both spacing fields now use the existing scoped numeric draft, refresh
clean display values through the current responsive resolver, and preserve
conflicted text with an Escape/Cancel recovery message. Return and Apply
use the displayed scope or the captured draft scope. Use Default/Inherited
uses the displayed scope. The model rejects stale scopes and submissions
during renderer adoption before invoking the typed command. Width changes
leave unsubmitted title and Contents drafts intact.

The same commands still write owner `layout.padding` or the responsive
padding key, and the navigation Stack’s base or responsive gap key.
Design-sourced padding retains priority and the fallback property.
Desktop fluid gap stays controlled by Layout. The structural layout and
connected CSS still resolve those canonical values through
`ConnectedPageLayoutSnapshot`, `CanonicalPageFlow.padding` and
`CanonicalPageChrome.navigationGap`. Native Preview consumes the rendered
geometry. No schema or output change.

Verified selectors:

- `SiteForgeTests/InsertionModelTests/testConnectedSpacingRejectsStaleViewportAndKeepsExactOverrideHistory`
- `SiteForgeUITests/SiteForgeLaunchTests/testHeaderFooterInlineGapResponsiveResetAndDraftCancellationJourney`

The model fixture covers cross-breakpoint padding rejection, same-breakpoint
free-width rejection before and after renderer adoption, exact inherited-value
overrides, scoped reset and Undo/Redo. The extended UI journey checks draft
retention, stale Apply, Cancel and title retention while retaining its
existing responsive reset and independent Footer assertions.
