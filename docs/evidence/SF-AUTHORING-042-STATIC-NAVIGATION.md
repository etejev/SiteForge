# SF-AUTHORING-042 — Static navigation-output foundation

## Bounded scope

This checkpoint adds a pure static-navigation projection covering bounded
compiler evidence for SF-0202-001–006, SF-0303-001–006, and SF-1102-001–006.
It reads the existing canonical page/route model but never writes document,
history, scene, or browser state.

## Delivered behavior

- `StaticNavigationEmitter` preserves persisted website-page order and stable
  PageID/route provenance.
- Home and standard pages with a validated generated route emit escaped links
  inside one labeled navigation landmark.
- The exact generated page receives `aria-current="page"`.
- Not Found and component-definition pages are intentionally omitted; a page
  without a validated static route or safe label is omitted rather than
  producing a fabricated destination.
- Nested generated paths produce validated relative hrefs, so the bounded
  output does not assume a root-routing server.

## Verification status

`CanvasRendererTests.testStaticNavigationProjectionPreservesPageOrderAndAccessibleCurrentState`
was added as focused coverage but not run because the owner has paused local
test execution and UI automation.

## Deferred scope

Navigation templates, page visibility/metadata authoring, redirects, dynamic
routes, scripts, browser runtime, generated-file export, publishing, broad
generated-site accessibility certification, performance certification, and
release acceptance remain deferred.
