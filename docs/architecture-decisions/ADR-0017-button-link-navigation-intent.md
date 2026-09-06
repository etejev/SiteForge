# ADR-0017 — Versioned Button/Link navigation intent

Status: Accepted for the bounded SF-AUTHORING-020 implementation.

## Context

SF-0806 and SF-1102 require stable authored link intent, exact history and
recoverable missing destinations. Presentation strings and copied routes
would create a second source of truth when pages are renamed or removed.

## Decision

Schema 6 adds Button and Link node kinds. Existing typed NodeProperty storage
owns the closed `content.control.v1.label` and `interaction.link.v1.*`
namespaces. Labels, target and browsing context independently preserve
defaulted/authored/omitted property provenance. Page and Section targets use
stable PageID/NodeID; external targets are credential-free validated HTTP(S).
Missing internal destinations preserve intent and offer replacement/removal.

The shared registry compiles one existing-property transaction per committed
edit. Reset removes properties; kernel inverses restore exact presence,
PropertyID, value, order and origin. Scene-local drafts and editor selection
are never persisted. Diagnostics omit labels and destination strings.

Schema 1–5 input retains its existing migration path and cannot smuggle new
node kinds under a historical version. Encoding writes only current schema;
no destructive package migration or duplicate model/store is introduced.
The checked-in schema-v5 fixture proves the historical decoder boundary.

## Consequences

Button labels reuse shared text layout over the authored fill. Link labels
reuse plain-text rendering. Selection never follows navigation. Runtime
navigation, remote previews, embeds and export/publishing remain deferred;
the normative modules therefore remain Partial.
