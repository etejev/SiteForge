# SF-PRODUCT-UI-005 — Owner-approved AppIcon v2

Verification checkpoint (2026-10-08): deterministic AppIcon and repository
checks pass. Runtime UI inspection remains blocked by XCTest automation-mode
initialization and no release/publication claim is made.

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**

Requirements: bounded `SF-0201-009`.

## Delivered source contract

- The exact owner-supplied 1254×1254 RGB source is retained at
  `docs/design-assets/siteforge-app-icon-sf-gradient-approved-v2.png` with
  SHA-256
  `9baa1876ffa52edd5cc2d591b582d5c02eb9b4a1aafbada64b5e24f4a7fe9070`.
- `scripts/package_app_icon.py` converts to RGBA, flood-fills only
  edge-connected pixels whose RGB channels are all at least 230 to transparent,
  and resizes that cutout with Lanczos to the ten required macOS renditions:
  16, 32, 128, 256, and 512 points at 1× and 2×.
- Enclosed white pixels remain opaque, preserving the SF monogram. The
  gradient/letter artwork is not redrawn, generated, or color-adjusted.
- `SiteForge/Assets.xcassets/AppIcon.appiconset/Contents.json` maps the ten
  files to the standard macOS point/scale slots. Both Debug and Release select
  `AppIcon` in `SiteForge.xcodeproj`.
- The welcome surface uses `NSApp.applicationIconImage`. AppKit's standard
  About presentation plus Dock/Finder resolve the same bundle AppIcon; there is
  no second hardcoded brand image.
- The icon is application UI only. It is absent from canonical projects,
  authored rendering, documents, export, and test fixtures.

## Allowed static evidence

`python3 scripts/check-app-icon.py` passed. It proves:

- the approved source digest and 1254×1254 dimensions;
- exterior corner transparency after matte removal;
- more than 100,000 enclosed near-white source pixels remain fully opaque;
- exact catalog coverage without duplicate or non-mac slots;
- correct RGBA pixel dimensions for all ten files;
- pixel equality between every checked-in rendition and the deterministic
  transform of the approved source;
- AppIcon resource membership and exactly two Debug/Release target selections.

The 1024-pixel rendition was inspected at original resolution. It shows the
upright white SF monogram and unchanged blue-to-purple field with transparent
exterior matte and no replacement artwork.

`scripts/sync_spec_publication_icon.py` synchronized the revised normative
paragraphs into `docs/SiteForge-Specification.docx`. Rendered publication pages
40–42 were inspected at original resolution after the edit; headings, the v2
source path, acceptance text, and the following checklist remain readable and
unclipped.

## Deferred acceptance

No build, XCTest, UI automation, or `./sf verify` ran under the owner testing
pause. `AppMetadataTests` now also requires a valid non-empty native
`NSApplication.applicationIconImage`, but that source assertion is unrun.
Fresh launch/welcome/About plus Finder/Dock review, broad hardware/appearance
coverage, signing, notarization, publication, and release remain deferred.
