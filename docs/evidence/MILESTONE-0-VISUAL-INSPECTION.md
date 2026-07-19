# Milestone 0 visual-inspection manifest

This manifest separates retained manual inspection from automated semantic assertions. It does not claim generated-site, real canvas-renderer, or release-channel acceptance.

| Date | Environment | Window and fixture | Settings/states | Inspected behavior | Automated companions |
|---|---|---|---|---|---|
| 2026-07-19 | MacBook Air, Apple silicon; macOS 27.0 build 26A5378n; Xcode 27.0 beta | SiteForge Debug; 1280×800 and 1100×700; standard and synthetic 10,000-page navigation fixture | Light, dark, Reduce Transparency fallback, Increased Contrast policy, active/inactive | No minimum-size panel overlap; native material boundaries remained readable; canvas hit target remained operable; launch welcome, progress, failure, and recovery fixtures retained keyboard targets | `testApplicationLaunchesCompleteNativeShellAtPracticalMinimumSize`, `testWorkspaceChromeUsesNativeMaterialWithoutInterceptingCanvasInput`, `testOpaqueHighContrastDarkAndInactiveMaterialStatesRemainOperable`, `testLaunchAndLoadingStatesRegressUnderOpaqueMaterialFallback` |
| 2026-07-19 | Same correction host and Debug composition | Immutable schema-v1 package bytes and repository-local recovery storage | Valid open, malformed failure, Retry, recovery Restore, recovery Discard | Production loader reached workspace only after validation; failure remained path-free; Return activated Restore; Discard returned to the clean workspace | `testProductionLoaderOpensRealPackageAndRetriesMalformedBytesWithoutPreviewState`, `testProductionRecoveryDiscoverySupportsKeyboardRestoreAndDiscard` |

Limitations: screenshots produced by UI tests remain ephemeral Xcode attachments rather than product-behavior proof. Actual VoiceOver speech output, OS-level Reduce Transparency/Increased Contrast toggles, generated-site output, and renderer frame pacing require later retained QA on the owner-approved OD-001 matrix.
