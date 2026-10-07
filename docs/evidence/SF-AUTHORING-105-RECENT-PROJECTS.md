# SF-AUTHORING-105 — Authorized recent projects

Status: **SOURCE IMPLEMENTED — VERIFICATION DEFERRED**

## Bounded requirements

- `SF-0201-002/003/004/006`
- `SF-0204-002/003/004/006`
- supporting `SF-1504-001/003/004/006`

All modules remain Partial. This slice adds a launch convenience for projects
whose access the user already authorized; it is not template, multi-window,
workspace-restoration, or release acceptance.

## Connected production behavior

Successful user-selected Open records at most eight recent entries in an
app-owned versioned file. Each entry stores only a deterministic SHA-256
bookmark lookup key, bounded display name, and derived stable recent ID. It
never stores an absolute path or duplicates security-scoped bookmark bytes.

The welcome card loads this list away from canonical project state. Choosing a
recent item asks the existing `FileAccessService` to resolve and, when needed,
refresh the retained security-scoped bookmark; the normal lifecycle then
coordinates, validates, and adopts the project. Missing or stale access keeps
the entry and offers the real Open Project panel to restore authorization.
Removing a recent entry changes only the recency file and deliberately retains
the underlying authorization record.

The bounded list is keyboard/pointer accessible, labels every row as an
authorized local project, discloses no path, and remains subordinate to New
Site and Open Project. Store corruption produces a path-free recovery message
without blocking either primary action.

## Source evidence

- `SiteForge/RecentProjects.swift`
- `SiteForge/FileAccessBoundary.swift` — `resolveAuthorizedProject(bookmarkKey:)`
- `SiteForge/DocumentLifecycle.swift` — lifecycle/backend bridge
- `SiteForge/LaunchExperience.swift` — loading, recording, open, forget, and recovery UI
- `Tests/SiteForgeTests/LaunchExperienceTests.swift` — bounded policy and fresh-controller reopen
- `Tests/SiteForgeTests/FileAccessBoundaryTests.swift` — stale repair without unbalanced scope
- `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift` — fresh-process welcome reopen journey

Test source is unrun under the owner execution pause. No runtime, visual, or
assistive-technology acceptance is claimed.

## Exclusions

Recent entries do not contain thumbnails, raw paths, project content, cloud
state, telemetry, templates, or predictive ranking. Finder aliases, arbitrary
workspace session restoration, multiple simultaneous project windows, and
cross-device recency remain deferred.
