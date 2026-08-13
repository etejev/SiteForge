# Structural Elements Foundation Evidence

`SF-AUTHORING-010` exercised true blank-project insertion through Elements and
the native Insert menu, nesting a Stack and Grid beneath a Section, then adding
children and using undo/redo. The retained XCTest attachment is named
`SF-AUTHORING-010 nested section stack grid`; it is captured after the settled
running-app step, not from external automation chrome.

The checked-in raw samples in `measurements.json` were produced by
`./sf test half` on 2026-08-12. They cover the existing insertion/layout/render
capacity fixture at 100 and 10,000 authored objects. The 10,000-object full
work exceeds one 60 Hz frame, so it is capacity evidence only, not an
incremental-layout or renderer-performance claim.

Focused proof before the full gate:

- `InsertionModelTests.testStructuralContainerDefaultsAreCanonicalAndDeterministic`
- `InsertionModelTests.testStackAndGridResolveChildrenFromCanonicalDefaults`
- `InsertionModelTests.testStructuralElementsPersistInSchemaFourAndSchemaThreeRemainsReadable`
- `SiteForgeLaunchTests.testStructuralElementsNestThroughCatalogAndInsertMenuJourney`

Final gate: `./sf verify` passed on 2026-08-12 with 301 unit/integration tests
and 33 actual-app UI tests (334 total), zero failures. Repository, security,
traceability, architecture, migration, evidence, and fixture-hygiene checks
also passed. The screenshot attachment is retained by the final XCTest result
bundle; it contains the settled SiteForge window only and no external
automation overlay is treated as product evidence.
