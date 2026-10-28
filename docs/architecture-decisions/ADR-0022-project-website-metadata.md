# ADR-0022 — Project-owned website metadata

- Status: Accepted for the bounded local-builder slice; integrated acceptance pending
- Date: 2026-10-18
- Requirements: SF-1207-001 through SF-1207-006 and SF-1207-008

## Decision

Document schema 18 adds one optional, versioned `websiteMetadata` record.
Global site name, title pattern, description, favicon AssetID and indexing
intent are canonical project content, not application preferences. Page
overrides use stable PageIDs and deterministic identity ordering. Absence
means inheritance/default resolution; reset removes a value. Text is bounded
and normalized. The closed `{page}`/`{site}` grammar substitutes names once,
never interpreting them recursively or as HTML.

Historical schema 1–17 inputs retain explicit adapters. Schema 17 keeps its
old closed document shape; current schema requires the metadata key, including
explicit null when omitted. Unsupported/malformed records fail before adoption.
Owner packages are not rewritten until an ordinary save.

Site Settings captures its opening document/page/revision/scene/render identity.
The central registry validates that identity and prepares one typed command.
Drafts/previews stay local. Apply is atomic, Cancel/Escape is neutral, and the
inverse restores exact record presence and values. Page deletion removes its
override atomically and Undo restores it.

History schema 3 admits metadata commands; schemas 1/2 migrate in memory.
Older history cannot contain the new command. Round-trip validation compares
the entire canonical document except revision, including assets, tokens and
metadata, rather than only pages/guides. Its closed command validator also
recognizes existing typed image-asset and color-token commands.

## Output and dependencies

The existing static compiler consumes resolved page metadata, escapes all
text/attributes and exports favicons through the existing verified image
resource planner. Default Header/Footer wordmarks resolve site name without
rewriting authored text. Missing favicon identity is retained and output fails
with a bounded repair finding. Asset usage, Reveal Usage and explicit detach/
delete include the favicon; direct deletion of a referenced asset is rejected.

## Limits

SF-1207 remains Partial: social cards, structured data, public-domain canonical
configuration, language authoring, broad metadata policies, scale and release
SEO acceptance are deferred. Focused evidence belongs to SF-LOCAL-BUILDER-001;
this decision does not claim integrated full-gate or installed-app acceptance.
