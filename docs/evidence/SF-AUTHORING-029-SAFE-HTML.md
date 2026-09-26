# SF-AUTHORING-029 — Safe HTML emission foundation v1

The emitter accepts only the typed internal render tree, fixed supported tags,
and deterministic NodeID-derived `data-siteforge-node`/class attributes. It
never emits text, raw attributes, scripts, handlers, URLs, files, or runtime.
