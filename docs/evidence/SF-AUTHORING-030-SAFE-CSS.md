# SF-AUTHORING-030 — Safe CSS emission foundation v1

Safe CSS emission is pure and in-memory. Its only declarations are ordered
`height`, `left`, `position`, `top`, and `width`, derived from validated typed
render-node geometry and keyed by the stable NodeID selector. Raw CSS, URLs,
at-rules, tokens, files, browser runtime and export remain deferred.
