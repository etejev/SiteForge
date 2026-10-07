# SF-PRODUCT-UI-006 — Launch identity and authoring toolbar hierarchy

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**

## Bounded requirements

- `SF-0201-006` — keyboard and accessibility semantics for the launch/window workflow.
- `SF-0201-009` — approved static SiteForge identity and adaptive native chrome.
- `SF-0203-003` — deterministic command placement and selection provenance.
- `SF-0203-006` — equivalent accessible authoring command operation.

These requirements remain Partial. This slice does not claim complete window,
route, command, scale, localization, assistive-technology, or release
acceptance.

## Delivered source contract

The launch card now displays the packaged application icon selected by the
app target rather than an unrelated system tool glyph. The first decision is
named directly as **New Site** or **Open Project…**, while concise local,
private-by-default, and recovery-protected assurances describe existing
behavior without inventing cloud or template capabilities. The launch state
remains part of the same native window lifecycle.

The workspace toolbar reserves persistent positions for Select, Frame, Text,
Image, and Component at the practical-minimum window. Section, Stack, Grid,
Button, Link, and Form remain adjacent in one native **More Tools** menu. Every
entry changes only the scene-local selected tool; actual insertion continues
through the established Insert menu, keyboard commands, and typed insertion
registry. No toolbar state enters the document, history, package, renderer, or
website output.

## Source evidence

- `SiteForge/LaunchExperience.swift` — approved application icon, direct
  launch actions, and adaptive assurances.
- `SiteForge/WorkspaceShellModel.swift` — deterministic primary/additional
  tool partition.
- `SiteForge/WorkspaceShellView.swift` — persistent authoring controls and
  accessible native More Tools menu.
- `Tests/SiteForgeTests/AppMetadataTests.swift` — exact ordering,
  completeness, disjointness, and noncanonical tool-selection assertions.
- `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift` — launch identity/action
  semantics and essential/overflow toolbar journey source.

The focused tests above were not executed under the owner testing pause. No
runtime screenshot or accessibility acceptance is claimed.

## Explicit exclusions

Recent-project persistence, security-scoped bookmark navigation, a template
gallery, toolbar customization, shortcut rebinding, focus mode, multi-window
navigation, broad 200-percent/VoiceOver/localization matrices, and release
acceptance remain deferred. The welcome surface does not synthesize recents or
templates from raw local paths.
