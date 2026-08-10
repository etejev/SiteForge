# SF-PRODUCT-UI-001 visual review manifest

This bounded visual review uses the native Debug application composition and
does not claim OS-level VoiceOver speech or release-hardware acceptance.

| State | Evidence route | Expected observation |
| --- | --- | --- |
| Launch | `-SiteForgeLaunchScenario welcome` | One normal window with the native launch card and New/Open actions. |
| Loading | `-SiteForgeLaunchScenario loadingDeterminate` | Progress and specific operation status stay inside the same window. |
| Recovery | `-SiteForgeLaunchScenario recovery` | Restore, Discard, and Inspect Recovery remain readable and keyboard reachable. |
| Empty workspace | New blank project | Pages/Layers, empty inspector, canvas, and status chrome have distinct native surfaces. |
| Selected workspace | Select a rendered node | Selection overlay, Layers, inspector summary, and status remain aligned. |
| Light / dark | `-SiteForgeAppearance light` / `dark` | Native dynamic material preserves contrast and visual hierarchy. |
| Constrained display | explicit `-SiteForgeUITestWindowAlignment` and vertical alignment | Debug-only edge placement exposes requested controls; Release does not read the arguments. |

The automated evidence is deliberately text-based and reproducible: UI tests
capture Xcode attachments on failure, and the launch/material/constrained
journeys are part of `./sf verify`. No desktop-wide screenshots are retained
because they could capture unrelated user content.
