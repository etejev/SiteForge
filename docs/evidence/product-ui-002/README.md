# SF-PRODUCT-UI-002 product-navigation evidence

## Scope

This bounded evidence covers the native left-side destinations and the
truthful Elements catalogue. It does not claim storage/import, component
definitions, responsive authoring, general property editing, export, or
publishing.

## Reproduction

1. Run `./sf build` and `./sf dev`.
2. Create a blank project in the normal SiteForge window.
3. Inspect Pages and Layers, then Elements, Assets, and Components in light,
   dark, reduced-transparency, and constrained UI-test compositions.
4. In Elements, verify that Frame and Text expose `F`/`T` and arm only the
   existing insertion tooling. Verify that Section, Stack, Grid, Button,
   Link, Divider, Navbar, and Footer are disabled and expose their specific
   unavailable reason. Verify that Assets and Components have an explicit
   unavailable/empty explanation.
5. Run `./sf verify`.

## Retained automated evidence

- `AppMetadataTests.testElementsCatalogIsOrderedTruthfulAndDoesNotCreateCanonicalState`
  proves stable order, capability contracts, disabled semantic entries, and
  no document/history mutation from catalogue metadata/tool arming.
- `SiteForgeLaunchTests.testProductNavigatorProvidesTruthfulElementsAssetsAndComponentsDestinations`
  is the running-app journey for accessibility identifiers, enabled Frame/Text,
  disabled later entries, and Asset/Component unavailable surfaces.
- The existing material/appearance/constrained-display UI journeys continue to
  cover the surrounding shell; no screenshots or private project content are
  stored in this repository.

## Limitation

The screenshot attachment policy captures UI images on an XCTest failure. A
passing automated run does not claim manual VoiceOver speech or final
release-hardware accessibility acceptance.
