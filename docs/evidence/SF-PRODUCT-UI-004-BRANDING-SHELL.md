# SF-PRODUCT-UI-004 — Original AppIcon and adaptive native shell

Historical evidence: the icon artwork described below was superseded by the
owner-approved gradient source in `SF-PRODUCT-UI-005`. See
`docs/evidence/SF-PRODUCT-UI-005-QUICK-OPEN-INSERTIONS.md` for current
source-only packaging work. Its tests and fresh Finder/Dock visual review are
still pending.

Requirements: `SF-0201-009`; bounded supporting `SF-0201-003`,
`SF-0201-006`, `SF-1505-006`, `SF-1605-002`, and `SF-1605-006`.

## Delivered local slice

- The owner-approved SiteForge SF artwork is packaged as ten standard macOS
  AppIcon size/scale PNGs in `SiteForge/Assets.xcassets/AppIcon.appiconset`.
  `SiteForge.xcodeproj` selects `AppIcon` in Debug and Release. The built local
  app contains both `AppIcon.icns` and `Assets.car`, and its bundle metadata
  names `AppIcon` for `CFBundleIconFile` and `CFBundleIconName`. The exterior
  matte was removed for a transparent cutout; the monogram and border were
  preserved. The approved source and cutout are in `docs/design-assets`.
- `WorkspaceMaterialPolicy` uses native behind-window sidebar blending for
  navigator and Inspector, within-window blending for other chrome, and an
  opaque fallback for Reduce Transparency. Increased Contrast strengthens
  separators. Native material views remain pointer-pass-through and absent
  from the accessibility tree. None of this is canonical project content.

## Focused evidence

- `AppMetadataTests.testAppIconCatalogCoversEveryMacSizeAndIsSelectedByBothAppConfigurations`
- `WorkspaceMaterialPolicyTests.testFrostedSidePanesKeepOpaqueAccessibilityFallbackAndCanvasSeparation`
- `WorkspaceMaterialPolicyTests.testNativeMaterialDecorationDoesNotInterceptPointerOrAccessibility`

The three exact unit selectors passed 3/3 with zero failures. The existing
actual-app selectors
`SiteForgeLaunchTests.testWorkspaceChromeUsesNativeMaterialWithoutInterceptingCanvasInput`,
`testOpaqueHighContrastDarkAndInactiveMaterialStatesRemainOperable`, and
`testMinimumWorkspaceContainsViewportAndScrollableFillInspectorControls`
passed 3/3 with zero failures. This local visual slice did not rerun the
556-test SF-AUTHORING-063 gate, and no hosted result is claimed.

Original-resolution XCTest screenshots were extracted and reviewed for
`default`, `light`, `dark`, `reduce-transparency`, `increased-contrast`,
`inactive`, and `minimum` states. The normal window retains the menu bar and
Dock; pane text, header controls, canvas grid, artboard, and empty state remain
legible. Light and dark material surfaces are distinct from the canvas;
Reduce Transparency presents opaque panes. No material surface intercepts
canvas input in the affected UI journey. At the practical minimum, the
navigator's long tab labels use the existing overflow affordance; the full
label list is not simultaneously visible.

The built `AppIcon.icns` was also extracted and visually inspected: its SF
lettering, flat dark field, and inset gradient border match the approved
artwork. A Dock screenshot from XCTest still displayed a generic icon even
though the tested app bundle had the correct icon files and Info.plist keys.
This may be a Launch Services/Dock cache or test-launch artifact; a fresh
Finder/Dock observation outside XCTest remains unproven and is not claimed.

## Scope boundary

The app icon is static application artwork, not an authored canvas element.
This slice does not claim broad hardware, OS-level VoiceOver, Finder/Dock cache,
signing, notarization, release, or publication acceptance. The existing
SF-AUTHORING-063 tree remains uncommitted for owner review.
