# ADR-0006: Centralized native workspace material policy

- Status: Accepted
- Date: 2026-07-19
- Requirements: SF-0201-002, SF-0201-003, SF-0201-006, SF-0201-007, SF-0201-008; SF-1505-006, SF-1505-007, SF-1505-008; SF-1605-002, SF-1605-006, SF-1605-007, SF-1605-008

## November 22 owner palette clarification

The owner-selected macOS default grays replace fixed custom native chrome RGB
values and the earlier black Testing/monitor palette. Semantic system roles,
app appearance, native separators and opaque accessibility fallback remain the
central policy. Authored website colors remain canonical project data. The
independent owner-local progress helper receives presentation through its
provisioned launch and scoped live appearance bridge, without global preference
changes. Geometry and input ownership are unchanged.
[Acceptance](../evidence/SF-NATIVE-UI-CONSISTENCY.md).

## Context

SiteForge chrome must reveal appropriate content through native macOS translucency without turning appearance into scattered panel-specific styling. The same surfaces must remain readable and operable under Reduce Transparency, increased contrast, light/dark appearance, accent changes, inactive windows, minimum sizing, and large projects. Visual effects must not become an input layer over the canvas.

## Decision

One semantic policy resolves each approved chrome region—title bar, navigator, inspector, viewport controls, status, recovery, and launch card—into a native material, presentation mode, separator strength, and active-window emphasis. SwiftUI views consume that policy through one modifier. The modifier hosts an `NSVisualEffectView` using within-window blending; its subclass always returns `nil` from hit testing so controls, splitters, scrolling, and the canvas retain ownership of input.

Reduce Transparency changes every region to an opaque dynamic system-color backing instead of simulated blur. Increased contrast strengthens system separators. Light/dark and accent changes continue through dynamic macOS colors and controls. Inactive state removes recovery emphasis while preserving a visible boundary. The unified AppKit toolbar/title bar remains system-owned so macOS supplies the appropriate active, inactive, appearance, and accessibility rendering.

Appearance state is UI convenience state only and never enters the canonical document or project package. Bounded standard and 10,000-page fixtures plus deterministic launch arguments exist only for automated accessibility, layout, performance, and visual inspection.

## Consequences

- New chrome regions must be added to the exhaustive semantic policy rather than styled independently.
- Native material choice and accessibility fallback can be unit tested without inspecting pixels.
- UI tests retain semantic and screenshot evidence while VoiceOver receives no test-only appearance elements.
- Material surfaces cannot intercept pointer events; hit testing remains with controls and canvas content.
- The window remains responsible for native unified-toolbar rendering, restoration, resizing, and inactive appearance.
- Future canvas content may extend behind chrome without changing the material contract.

## November 15 native redesign

The approved Start, workspace, and Settings use flat chrome colors from a
shared light and dark palette. Increased Contrast strengthens the section
rules and quiet text. The system keeps ownership of the title bar, focus,
menus, and material where used. This visual decision follows the
[approved redesign](../coordination/APPROVED_NATIVE_UI_REDESIGN.md).
