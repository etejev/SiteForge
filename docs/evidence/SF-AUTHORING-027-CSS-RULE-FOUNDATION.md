# SF-AUTHORING-027 — CSS rule foundation v1

`css.rule.v1` is a typed authored marker. Its only v1 selector is derived from
the stable NodeID, so no raw CSS or selector text enters canonical content.
Absent is omitted/defaulted; authored state is strictly validated and survives
the existing property serialization path. CSS generation, browser runtime,
media/container queries, tokens, export and publishing remain deferred.

Focused compile/model verification:
`TransformModelTests.testSemanticElementRegistryValidatesMixedSelectionAndExactHistory`
passed after the CSS-rule validator joined canonical document validation.
