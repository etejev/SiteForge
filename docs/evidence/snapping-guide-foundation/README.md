# SF-AUTHORING-007 Snapping and Guide Evidence

This evidence covers the bounded `SF-0404-001` through `SF-0404-008` slice.

## Reproduction

```sh
scripts/run-snapping-guide-evidence.sh
xcodebuild -project SiteForge.xcodeproj -scheme SiteForge -destination platform=macOS \
  -only-testing:SiteForgeUITests/SiteForgeLaunchTests/testSnappingRulersAuthoredGuidesSuppressionAndAccessibilityJourney
./sf verify
```

The retained JSON names the environment, optimized configuration, raw samples,
resident-memory reading, methodology, and limitations. Resolver P95 was 0.972 ms
for 100 objects and 40.341 ms for 10,000 objects; maximum resident memory was
109,428,736 bytes. The actual-app XCTest journey produced window-only captures;
`rulers-and-authored-guide.png` retains the ruler and selected-guide state, while
`snapping-suppressed.png` retains the explicit accessible suppression state.
Both were inspected in dark appearance for alignment, readable panel separation,
selection/status synchronization, clipping, and unrelated desktop content.
Behavioral tests cover stable
candidate resolution, priority, ties, hysteresis, zoom-aware thresholds, typed
failure, transform parity, transactional guides, undo/redo, schema migration,
deterministic serialization, accessibility identifiers, and diagnostic redaction.

The 10,000-object full-scan result is capacity evidence, not proof of final
incremental indexing, renderer frame pacing, OS-level VoiceOver speech, or a
cross-hardware release budget. Smart-guide and measurement overlays are exercised
through production planner/rendering behavior rather than retained mid-gesture
screen captures; visual appearance across light/high-contrast/Reduce Transparency
and OS-level accessibility settings remains proportional downstream acceptance.
