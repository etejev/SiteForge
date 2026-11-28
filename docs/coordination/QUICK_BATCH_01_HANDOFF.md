# Code Forge batch 01 — handoff to Codex (candidate, NOT verified)

Author: AWS Quick "Code Forge" assistant, working for the owner on 2026-11-25 from a
Windows PC against this iCloud working copy. **No Swift toolchain was available: none of
this has been compiled or executed.** Treat every change as a candidate until Codex or
hosted CI produces exact-source receipts. Codex remains the orchestrator, verifier,
installer and sole owner of Testing receipts. Code Forge did not commit or push.
On 2026-11-25 the owner explicitly authorized publishing this work to the feature
branch `quick/batch-01` with a draft pull request for hosted CI; the owner performs
the commit, push and PR in GitHub Desktop (the AGENTS.md GitHub boundary is kept as
an owner action). `main` is not changed.

Restore point (taken before any edit, SHA-256 verified): `RP-2026-11-25-01`, kept
outside the repository on the owner's PC with a `RESTORE_POINT.md` and per-file
manifests. `.build/` and `.codex-loop/` were not edited.

## Constraint observed

`SiteForge.xcodeproj` is not materialized on Windows, so **no new Swift files were
added** (they could not be registered in the project). All Swift changes extend files
that are already target members. `Samples/Aurora/AuroraTemplate` is a folder reference,
so sample bytes placed inside it are bundled without a project edit.

## Changed files (5)

| File | Change | Requirements |
|---|---|---|
| `scripts/ci-ui-timings.txt` | Added the two fast-style UI journeys that were missing from the hosted timing manifest (`ci-test-accounting.py discover` requires exact UI parity, so hosted CI would fail discovery without them). Durations **150 s / 210 s are estimates** from neighbouring journeys; refresh from the next full receipt. | SF-1605-008, SF-1902-007/008 |
| `.github/workflows/ci.yml` | Safari pre-open selector regex also matches `FastStyleVisibleColors` (that journey hands off to Safari). | SF-1605-008 |
| `SiteForge/PackagedSiteTemplate.swift` | `BundledSiteTemplates.auroraFlowID` (`02040000-0000-4000-8000-000000000222`, the ID reserved in the draft recipe) and `auroraFlowURL(in:)` → `AuroraTemplate/AuroraFlow.siteforge`. | SF-0204-002/004/005/006 |
| `SiteForge/LaunchExperience.swift` | `.auroraFlow` creation choice, `createAuroraFlowProject[AndWait]()`, focus, Start card (“Aurora Flow · Interactive template”, SF Symbol `wind`, id `launch.newAuroraFlowProject`) with native static gradient/glass art. **The card is shown only when the bundled sample exists**, so current UI journeys and geometry are unchanged until bytes are added. Uses the same `PackagedSiteTemplateLoader` and atomic creation lifecycle. | SF-0204-002/003/004/006, SF-0201-003 |
| `Tests/SiteForgeTests/LaunchExperienceTests.swift` | Two new core tests and a reproducible `AuroraFlowShowcaseRecipe` (see below). | see below |

## New core selectors (Start Regular)

```
SiteForgeTests/LaunchExperienceTests/testAuroraFlowShowcaseRecipeBuildsCompilesSavesAndLoadsEditableTemplate
SiteForgeTests/LaunchExperienceTests/testAuroraFlowStartChoiceUsesSharedLifecycleWhetherOrNotSampleIsBundled
```

1. **Recipe test** builds the showcase in memory, then asserts: canonical validation;
   template provenance/ID; Home/About/Contact (+ Not Found); six tokens each with a
   valid dark variant; exactly one Flow (Home hero) on an eligible literal gradient;
   glass header + cards with opaque light/dark fallbacks; one Header/Footer per page with
   About Us / Contact Us / Scan-to-explore groups; QR payload `https://example.com`
   decoded by `ProjectQRCodeVerifier` and shared as one content-addressed asset; no
   localhost destinations; stack/grid/text frames inside 1440/768/390; shared
   `StaticBuildCompiler` output `canWrite` with `siteforge-effects.js ==
   DecorativeEffectRuntime.javascript`, `data-siteforge-flow`, header/footer/h1 and no
   remote script; serializer round trip; ordinary `requestNewDocument` + `save(to:)`;
   two `PackagedSiteTemplateLoader` loads give independent documents with identical pages.
   It attaches (`keepAlways`) the **saved `AuroraFlow.siteforge` container and every
   `AuroraFlow.siteforge.resources-v1/<sha>.blob`** for review. It never writes Samples.
2. **Start-choice test** exercises `createAuroraFlowProjectAndWait()`: while unbundled it
   must fail visibly without mutating the current document; once bundled it must create
   a clean template workspace (`templateID == auroraFlowID`, no undo, no file URL).
   No XCTSkip is used (hosted accounting rejects unapproved skips).

Requirement scope (bounded, no module promotion): SF-0204-002/004/005/006,
SF-0508-001/004/005, SF-1101-003/004, SF-1204-003/004, SF-0502-003/005,
SF-0602-003/004, SF-0604-003/004, SF-0802-002/005, SF-1102-003.

## Recipe design (`AuroraFlowShowcaseRecipe`, test target)

Built on a normal `DocumentSession` using shipped command paths only:
`InsertionCommandRegistry` (Header/Footer/body Sections), `FooterContentWorker`
(About → Contact → QR; later groups target `first.columnsID`, matching the footer test),
`LocalColorTokenCommandRegistry` (`.create`, `.darkVariant`, `.bindTarget`),
`DecorativeEffectCommandRegistry` (`.flow`, `.glass`), `DecorativeEffectPropertyCommands
.replace` for the closed fill-layer namespace, and validated `.setProperty`/`.insertNode`
batches using the same canonical keys `FooterContentCommandRegistry` uses for ordinary
Stack/Grid/Text/Link nodes. No raw JSON, no sample-only CSS/JS, no bitmap artwork.

Per page: page Root solid fill bound to *Page background*; glass Header (fill bound to
*Glass tint*, glass blur 20, title/nav text bound to *Primary text*); hero Section with a
literal 3-stop gradient (Flow only on Home: radius 320, strength 0.6, response 9,
return 1.1 s) → vertical Stack (padding 88/56/28) with eyebrow, h1, lead and a CTA Link;
body Section → Stack with h2, intro and a 3/2/1-column Grid of three glass card Stacks
(radius 24, 1 pt border bound to *Glass edge*, fill bound to *Glass tint*); Footer with
About/Contact/QR groups, fill bound to *Surface*. Sections use `heightMode: hug`; no
fluid values (avoids the strict fluid adapter). All copy is fictional; contact uses the
reserved `auroraflow.example` domain and `https://example.com`.

Fixed draft defects (from `.codex-loop/interactive/aurora-recipe-draft.swift`):
`WebsiteMetadata(description:)` → `defaultDescription:`; every Footer group was created
with `createColumnsConfirmed: true` and no grid; card borders lacked the required
`border.color` channels; token text bindings were attempted before any literal
foreground existed (bind requires one); nested body *Sections* inside a Grid replaced by
ordinary Stacks (a nested Section would acquire a page-flow body role).

## What Codex should do next

1. Build both architectures; fix any compile error in these five files first (likely
   spots if any: type inference in recipe helpers, `XCTAttachment` init).
2. Start Regular with the two selectors above. If the recipe test fails, its message
   includes `compilation.redactedSummary` or the failing node/page/width.
3. Export the two attachments from the passing run, open the `.siteforge` in the
   installed app, and do the required native + Safari visual passes (1440/768/390 and
   boundaries, Light/Dark, Reduce Motion/Transparency, keyboard focus). Adjust the
   recipe, not the bytes, then regenerate.
4. Only after visual acceptance: copy `AuroraFlow.siteforge` and
   `AuroraFlow.siteforge.resources-v1/` into `Samples/Aurora/AuroraTemplate/`, add a
   provenance README section, then rerun the Start-choice test (bundled branch), the
   existing Aurora packaged-template tests and Start-screen UI journeys (a fourth card
   now appears). Add/extend a UI journey for `launch.newAuroraFlowProject` and give it a
   timing entry.
5. Fast styling: the premultiplied-alpha candidate (`alpha-fix` selectors) still needs
   its receipt; Code Forge reviewed `NativeAuthoredFillPainter` (CGFunction retain/
   release, extend flags, uniform-alpha fast path) and found no defect, without running it.
6. Then the existing plan: final exact-source Full Verification, install, staged-scope
   review and the owner-authorized local commit.

## Hosted CI note

The `quick/batch-01` branch carries this whole working tree (Codex's uncommitted
Nov 15–22 work plus batch 01), prepared in the owner's Windows clone. Because the
Mac's `SiteForge.xcodeproj` could not be read there, the branch's `project.pbxproj` is
the committed `0133939` version plus entries for `DecorativeEffects.swift`,
`DecorativeEffectsInspector.swift`, `FastStyleControls.swift`, `FooterContent.swift` and
`TestingWindow.swift` (app target; IDs `…F8`–`…FC`). Reconcile it with the Mac's real
project before the next commit from the Mac. CI cannot install the app or perform
visual acceptance; it does not replace the native Testing window receipts required
by AGENTS.md.

## Update — November 25, 1:11 PM

The owner deleted draft PR #1 and branch `quick/batch-01` before run #127 finished.
In that run the build step had passed on UI shards 1 and 2; no test results were kept.
This working tree is again the place where Code Forge edits appear, as uncommitted
changes. See [CODE_FORGE_ACTIVITY](CODE_FORGE_ACTIVITY.md) for the current record.
