# ADR-0025 — Opt-in responsive sizing and shared native text metrics

Status: Implemented for focused acceptance; integrated delivery remains pending.

Requirements: bounded SF-0501-003, SF-0502-003/005,
SF-0505-001 through SF-0505-006, SF-0507-003/005, SF-0602-003/005.

## One canonical authority

Extend `layout.sizing.v1` with typed width/height mode properties. Omitted
modes resolve to Fixed without inserting properties or rewriting old geometry.
Width supports Fixed/Fill; height supports Fixed/Fill/Hug. Width Hug and Image
Hug remain unavailable. Explicit numeric breakpoint and fluid dimensions win
over inherited automatic modes. The existing fixed geometry is retained as
intent/fallback, not repeatedly overwritten with measured values.

Document schema 19 gates the added semantics; schemas 1–18 retain their existing
read adapters and cannot smuggle the new modes through an older envelope.
History stays at version 3 because the existing typed property commands and
exact inverses already represent these changes. No parallel sizing record,
responsive cascade, document store or command system is introduced.

## Resolution and transactions

Resolve containing widths before measuring wrapped heights, then propagate
intrinsic container heights and place children in canonical child order.
Stack/Grid padding/gaps and effective visibility remain shared with existing
layout. Free Frames without authored padding do not acquire structural default
padding only in output. A Hug flow container with a Fill-height participant is
rejected rather than resolved through a circular percentage-height dependency.

Ordinary mode edits preserve deliberate dimension overrides. The separately
confirmed Make Content Responsive action converts supported selected subtrees
atomically and explicitly removes their width/height breakpoint/fluid overrides.
Container maximum widths preserve base width. Images, fixed-size Button/Link
controls, managed chrome, empty Frames and aspect-locked nodes are skipped.
Content, styles, X/Y intent, stable identities and ownership are retained.
One Undo restores exact property presence, values, provenance and IDs.

## Native and browser text

Core Text resolves the font and measures wrapping away from AppKit view
ownership. Native committed text and the inline editor toll-free bridge that
actual CTFont into NSFont. They never recreate private Apple system fonts by
PostScript name: that API silently substitutes Times. Optical size stays tied
to authored font size during canvas zoom, avoiding zoom-dependent line breaks.
The four-point horizontal inset and authored line height are shared.

Static output uses containing-block/flex/grid rules for opted-in content,
rather than sampling a fixed height at three presets. Browser shaping can
still differ by installed fonts/platform; actual matching-width visual review
is required and is not replaced by CSS-string assertions.

Each connected breakpoint resets the complete flex basis when direction
changes: a horizontal width basis must never become a vertical height. Fixed
Button/Link controls retain their native flex label alignment. Opt-in free-Frame
overlay grids use content-sized rows aligned at the start, avoiding Safari's
oversized earlier intrinsic auto-track measurement after text wrapping.

## Limits and evidence

SF-LOCAL-BUILDER-003 further shares effective winner/provenance with the
Inspector. Exact dimension reset delegates to existing geometry/fluid registries.
Grid track defaults cannot overwrite explicit numeric dimensions. Connected CSS
preserves winning fluid values with a continuous expression composed from the
existing two clamp segments rather than preset samples. No new cascade/schema
or legacy default change. Source-focused evidence and pending native/Safari/full
acceptance: `../evidence/SF-LOCAL-BUILDER-003-RESPONSIVE-SIZING.md`.

See `../evidence/SF-LOCAL-BUILDER-001-RESPONSIVE-WORKFLOW.md`. Focused coverage
does not imply completed SF-0505, all intrinsic layout combinations, browser
parity, release acceptance or the final integrated verification gate.
