# SF-AUTHORING-103 — Isolated local Preview navigation

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED** (2026-10-05)

## Bounded contract

This slice advances `SF-1102-002`–`SF-1102-004`, `SF-1102-006`, and
`SF-1201-001`–`SF-1201-004`, `SF-1201-006`, with supporting
`SF-1202-003`–`SF-1202-004`. The existing stable `CanonicalLinkTarget`,
Interactions Inspector, canvas scene resolver, and safe multi-page output stay
authoritative.

## Delivered source behavior

- An actor-isolated compiler resolves every website page through
  `WorkspaceScenePreparationWorker`, producing one immutable, revision-owned
  Preview runtime. Component-definition pages never enter visitor navigation.
- Validated Link objects carry a read-only Preview projection of the same
  stable page/section target and context that safe static output consumes.
  Editor canvas input still never follows authored navigation.
- Native Preview controls expose current page/route, Back, Forward, page menu,
  Refresh, and Done. Activating an internal Link updates only scene-local
  Preview history. It never changes the editor page, selection, document,
  revision, package, autosave, or command history.
- Missing targets remain inert with a specific repair message. External
  targets remain bounded and disclose only the host in Preview status; local
  Preview does not launch a browser or execute authored code.
- Preview fits the actual breakpoint artboard rather than deriving a false
  page boundary from authored object union. Selection, grid, guides, handles,
  badges, and other editor overlays remain excluded.

## Added focused source evidence (not executed)

- `CanvasRendererTests.testLocalPreviewRuntimeNavigatesStableTargetsWithoutMutatingDocumentState`
- `CanvasRendererTests.testScenePreparationCarriesOnlyValidatedLinkNavigationIntoPreview`
- `SiteForgeLaunchTests.testLocalPreviewFollowsAuthoredPageLinkWithBackForwardAndNoEditorMutation`

No test, build, UI automation, or verification command ran under the active
owner testing pause.

## Explicit remaining scope

Generic trigger/action chains, Button actions, hover/focus/pressed authored
state, downloads, prefetch, browser launching, scroll-position restoration,
runtime data/fixtures, custom viewport controls inside Preview, animation,
embeds, generated JavaScript, browser/export parity, performance and assistive-
technology matrices, publishing, and release acceptance remain deferred.
`SF-1101`, `SF-1102`, `SF-1201`, and `SF-1202` remain Partial.
