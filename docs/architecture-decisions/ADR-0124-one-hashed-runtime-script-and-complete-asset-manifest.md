# ADR-0124 — One content-hashed runtime script in Static Release; complete asset manifest (SF-1205, SF-1206)

- Status: Proposed (implemented as an unverified Code Forge candidate by lane V12b; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-042 (approved by the owner 2026-11-26 1:30 PM EST: "generated runtime JS emitted as one hashed
  file"); plan item E2 (lane E, re-assigned to lane V12b by the owner at 7:55 PM). Asset manifest: lane V08 finding.
- Builds on: ADR-0120 (Static Release CSS), ADR-0121 (integrity manifest, cache policy, reference audit), ADR-0123
- Requirements: SF-1205-003 (deterministic bundle, provenance per page), SF-1205-004 (isolated runtime failures),
  SF-1205-007, SF-1205-008; SF-1206-001 (asset manifest), SF-1206-003 (cache policy), SF-1206-004 (references resolve)

## Context

The multi-page planner writes up to four generated runtime files — `siteforge-navigation.js` (menus),
`siteforge-effects.js` (Flow effects), `siteforge-motion.js` (reveal on scroll) and `siteforge-events.js`
(interactions) — with stable names, and each page links the ones it uses. OD-042's recommended default, which the
owner approved, is one hashed runtime file. ADR-0121 left this open because the harness and
`SupportSettingsTests.swift` were unreadable iCloud placeholders; all of them are readable since 7:55 PM.
Separately, `assets.manifest.txt` listed only images, although the build also exports fonts, video, audio and
captions (lane V08).

## Decision

- **Static Release only.** `LocalBuildProfileCompiler.compile` runs `StaticRuntimeBundle.bundle` before the CSS
  optimizer. Development and Local Preview keep the readable per-runtime files exactly as the planner writes them,
  the same split as ADR-0120 (readable Development stylesheet, optimized Static Release stylesheet). The planner is
  unchanged, so Preview, the existing planner tests, the interaction browser harness and Development builds are
  byte-identical.
- **One file.** `StaticRuntimeBundle` (`SiteForge/CanvasRendererCore.swift`, section "SF-1205 one content-hashed
  runtime file") concatenates the runtime files the site uses, in the fixed order navigation, effects, motion,
  events, into `siteforge-runtime.<sha256>.js`, named by the SHA-256 of its bytes (identical text, identical name;
  any changed byte, a new name). The four readable files are not written in Static Release.
- **Same code per page.** Each page's first generated runtime tag becomes
  `<script src="<prefix>siteforge-runtime.<sha256>.js" data-siteforge-runtime="<parts>" defer></script>`, where the
  prefix is the page's own folder depth (language trees, collection item and list pages, nested routes; the
  planner's formula) and `<parts>` names the parts that page linked before; its other runtime tags are removed. The
  bundle reads `document.currentScript` and runs only the named parts, so a page runs exactly the code it ran
  before (for example, the Flow runtime's document observer never starts on a page without Flow). The interaction
  state element (`data-siteforge-state`) stays where it was.
- **Isolated failures.** Every part is fixed SiteForge code already wrapped in its own function; the bundle wraps
  each once more in `try`, reports a thrown error with `reportError` (or rethrows it asynchronously where that is
  missing) and continues with the next part. Separate files had the same isolation; strict mode and scope inside
  each part are unchanged.
- **Listed and cached.** `manifest.txt` names the bundle instead of the files it replaces; the integrity manifest
  and the per-file report list it (kind `script`); `StaticOutputCachePolicy.policy(for:)` marks
  `siteforge-runtime.<64 hex>.js` `immutable`, like content-addressed assets. The reference audit
  (`StaticOutputReferenceAudit`) finds every page's bundle reference resolved.
- **Browser evidence.** `SupportSettingsTests.testFlowRuntimeActualBrowserDeformationFallbacksAndLifecycle` now
  writes the Static Release site for the harness, so the eleven browser cases exercise the bundle; the harness
  accepts the Flow runtime from either Development's `siteforge-effects.js` or a content-hashed bundle that names
  the `effects` part (`loads_effects_runtime`, unit-tested in `test_flow_runtime_browser.py`). The interaction and
  motion browser harness (`interaction_runtime_browser.py`, ADR-0065) keeps running Development output.
- **Complete asset manifest.** `StaticAssetManifestEmitter.emit` lists every exported asset, sorted by asset
  identity: `<asset id>\t<output path>\t<detail>`, where the detail is the pixel size for images (unchanged format;
  SVG images and video posters are images) and the media type for fonts (`font/woff2`, `font/ttf`), video, audio
  and captions (`text/vtt`). Only exported files are listed (fonts with declared web rights that have a verified
  file, media an output page plays); no names or file names. A site whose only exported files are fonts or media now
  gets an `assets.manifest.txt`.

## Alternatives considered

- Bundle in the planner for every profile: changes Preview and about forty planner-level assertions in other lanes'
  tests for no user benefit; Development output is meant to be readable.
- One bundle per page (only that page's parts): many files with near-identical content, defeating long-lived
  caching; rejected.
- Running every part on every page: changes behavior on pages that never loaded a runtime; rejected.

## Consequences

- Static Release pages that use a runtime change (one tag instead of up to four); Static Release writes one script
  instead of up to four; Development, Preview and HTML without a runtime are unchanged. ADR-0120's "every non-CSS file
  is unchanged" now has this exception.
- Profile comparison (ADR-0123) shows the readable runtime files as "only Development" and the bundle as "only Static
  Release"; a changed runtime appears as one removed and one added file in the rebuild summary (its name follows its
  bytes, as for assets).
- No schema change: document 27, persisted history 4, WebsiteMetadata 3; no new command or setting.
- Not built: source maps and per-part size breakdown in Check Website (the per-file report shows the bundle size),
  code splitting beyond the per-page part list, custom author modules (SF-1205-001/002 authored bundle state has no
  model; OD-042 approved static generated runtime only).

## Verification

`SiteForgeTests/CanvasRendererTests/testStaticReleaseWritesOneContentHashedRuntimeEveryPageReferences`,
`SiteForgeTests/SupportSettingsTests/testStaticReleaseFlowRuntimeIsOneHashedFileInEveryLanguageTree`,
`SiteForgeTests/SupportSettingsTests/testFlowRuntimeActualBrowserDeformationFallbacksAndLifecycle` (needs Google
Chrome), `python3 Tests/Tooling/test_flow_runtime_browser.py`, asset manifest assertions in
`SiteForgeTests/ProjectResourceTests/testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound` and
`SiteForgeTests/ProjectResourceTests/testProjectFontsExportOnlyWithDeclaredWebRightsAndUseFallbackStacks`. Not compiled
or run by Code Forge. The bundle text was checked outside the app (Node): it parses with the four real runtimes, runs
only the named parts, keeps each part's strict mode and continues after a failing part.
