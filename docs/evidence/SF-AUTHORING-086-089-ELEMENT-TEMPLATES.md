# SF-AUTHORING-086–089 — Divider and semantic site templates

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED.

Bounded `SF-0405-001/002/004/005/006`, `SF-0501-002`, `SF-0506-001/002`,
and `SF-1203-002` apply. Divider now uses an existing Frame node at 240×1
with no border expansion. Header, Navigation, and Footer use existing Section
nodes with deterministic dimensions and authored semantic `header`, `nav`,
and `footer` properties. The shared insertion registry still validates page,
parent, geometry, revision, lifecycle, and undoable command availability. No
new node kind or document schema was created. The Elements catalogue and
native Insert menu both expose the actions; no placeholder remains for these
four entries.

`InsertionModelTests.testDividerAndSiteSectionTemplatesUseCanonicalInsertionAndSemanticRoles`
and `SiteForgeLaunchTests.testDividerHeaderNavigationFooterInsertThroughNativeMenuJourney`
were added as source, including stable ID, parent, geometry, semantic property,
Undo/Redo, and canvas adoption assertions. They were not run. Original-
resolution visual inspection and preview/export output acceptance are also
deferred; no user-visible success is claimed by this note.

Advanced Divider styling, generated navigation links/legal copy, and release
acceptance remain outside these bounded templates. The broader normative
modules remain Partial.
