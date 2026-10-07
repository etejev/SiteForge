# SiteForge source-completeness audit

Date: 2026-10-05

This is a source audit, not verification evidence. The repository contains a
large uncommitted source-only sequence; new and changed tests have not run.
Documentation, UI labels, and test names were not treated as proof unless a
production path was present and connected.

## Coverage map

### Connected production source

- Native application/document lifecycle, identity-bound package I/O,
  security-scoped access, recovery, bounded history, and stable canonical IDs.
- Pages, Layers, Elements, local raster Assets, local Components, Quick Open,
  command/menu routing, and the launch/workspace shell.
- Canvas viewport, selection/marquee, insertion, transforms, snapping/guides,
  drag/reorder, inline Text, immutable renderer/overlay adoption, and editor
  grid/artboard composition.
- Structural layout, responsive geometry/layout/visibility/fluid resolution,
  Design/Layout/Content/Interactions/Accessibility Inspector slices,
  typography, image authoring, local links/forms, static semantic output, and
  isolated local Preview navigation.
- Application appearance/canvas/reset/support Settings and redacted diagnostic
  report preparation.
- SF-AUTHORING-105 now connects authorized recent projects to the existing
  bookmark and lifecycle owners without persisting paths.
- SF-AUTHORING-107 now connects bounded transactional authored-object
  clipboard/duplication and supported image/token dependency transfer through
  the existing command, resource, selection, and diagnostics owners.

### Partial production source

- Onboarding has New Site/Open Project and recent projects, but no approved
  template catalogue, walkthrough, learning-state model, or reset workflow.
- Direct manipulation is substantial but focus/isolation/presentation modes
  (`SF-0409`) are absent as a coherent product surface.
- Styling covers fills, typography, bounded border/radius/shadow and tokens,
  but advanced positioning, reusable style classes, interaction states, and
  broad effects remain incomplete.
- Assets cover local raster images; audio/video, SVG/vector, font management,
  and remote/embed policy are not complete modules.
- Components cover local definitions/instances and bounded exposed values;
  slots, variants, libraries, documentation/examples, and full override reset
  remain incomplete.
- Links and local Preview exist; the general event graph, animation, scroll
  triggers, overlays, runtime variables, and custom-code boundary remain
  incomplete.
- Static semantic/CSS fragments exist, but complete CSS optimization,
  JavaScript bundling, asset export, SEO, build profiles, export adapters,
  compatibility reporting, publishing, domains, and rollback are incomplete.

### Source missing and dependency ordered

1. `SF-AUTHORING-106` — local Starter Site/onboarding model (`SF-0204`) using
   approved OD-016: Blank Site plus exactly one neutral Home/About template.
2. `SF-AUTHORING-108` — canvas focus/isolation/presentation modes (`SF-0409`)
   without creating a second selection or renderer model.
3. `SF-AUTHORING-109` — positioning and reusable/state style foundation
   (`SF-0504`, `SF-0510`, `SF-0511`) through existing property resolution.
4. `SF-AUTHORING-110` — complete static CSS/asset build diagnostics foundation
   (`SF-1204`, `SF-1206`, `SF-1208`, `SF-1211`) before any publication work.
5. Later dependency groups: cross-project component-definition clipboard
   closure; media/vector/font assets; component slots/variants;
   CMS/data/localization; general interactions/animation/runtime; snapshots,
   comparison and collaboration; plugins; full export/publishing; release and
   ecosystem acceptance.

### Owner or external blockers

- OD-016 is approved and no longer blocks local starter-template source.
- OD-001: supported macOS and reference hardware for release performance.
- OD-012/013: publisher identity, bundle identity, signing/notarization and
  distribution trust.
- OD-014: automatic reclamation of retained owned safety artifacts.
- Publishing/domains, connected services, marketplaces, remote libraries,
  collaboration infrastructure, and third-party plugin execution require the
  accounts, trust, privacy/security, or product decisions described by
  AGENTS.md before enablement.

## Audit corrections

The requirement evidence index covers only a subset of the 1,153 normative
IDs; absence from that index is not proof of missing source, and presence is
not proof of acceptance. Status now distinguishes previously verified bounded
evidence from the unrun SF-PRODUCT-UI-005/006 and SF-AUTHORING-075–105 source
sequence. Advanced modules remain Partial rather than being inferred complete
from nearby UI or output helpers.
