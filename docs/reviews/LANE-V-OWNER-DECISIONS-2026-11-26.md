# Lane V — owner decisions log (copied verbatim from _quick-scratch, 2026-11-26 11:29 PM EST)

Authoritative record of every owner decision taken during lane V. `docs/OPEN_DECISIONS.md` was NOT updated per decision
(the coordinator lane V15 never ran: the owner handed the tree to Codex at 11:28 PM). Apply these entries to
OPEN_DECISIONS.md when convenient.

---

# Owner decisions during lane V (for the coordinator, lane V15)

## 2026-11-26 7:35 PM EST — lane A library export with reusable styles
Owner: send the lane V02 out-of-area finding to lane V07 and fix it inside OD-046 (carry used reusable styles in the
library package as read-only copies, or refuse up front with a specific error). Steered into V07.

## 2026-11-26 7:40 PM EST — OD-141 approved (recommended default)
Owner approved the recommended default of proposed OD-141 (docs/reviews/LANE-V02-review-2026-11-26.md,
"Proposed OD-141 — Nested override paths and slot filling of inner instances (SF-0905, SF-0903)"):
an override path is the ordered list of stable instance node IDs from the outer definition down to the inner instance
(at most `CanonicalComponentGraph.maximumNestingDepth` − 1 steps), stored on the page copy as
`component.path.v1.<path>.<typed property key>`; deepest authored value wins (page path value, then the value authored
inside the outer definition, then the inner default); a path that stops resolving becomes the existing retained conflict
(reset / restore / navigate, OD-019); slot markers and membership of inner instances use the same path.
Coordinator actions:
- Add OD-141 to docs/OPEN_DECISIONS.md with Status: **Approved by the owner 2026-11-26 7:40 PM EST (recommended default)**,
  Implementation status: "Not built. Needs document schema 28, a clipboard version bump, remapping in all six copy paths
  and an ADR-0018 amendment; scheduled as the first batch after Codex has verified the lane V candidate (lane V stays on
  schema 27)."
- Add a plan row (next lane after the Codex pause) for OD-141 with that note. Do NOT build it in lane V.

## 2026-11-26 7:40 PM EST — iCloud placeholders
Owner is making the five placeholder files available offline (.github/workflows/ci.yml, docs/TESTING.md,
Tests/SiteForgeTests/SupportSettingsTests.swift, Tests/Tooling/flow_runtime_browser.py,
Tests/Tooling/test_flow_runtime_browser.py). Phase 2 (cross-tree lane V14) must re-test readability and, if readable,
check them (FeatureFlagID switches and expectations in SupportSettingsTests for the 5 flags; CI selectors; TESTING.md
selector lists) and, if the harness files are readable, unblock C10 (browser-run motion/interaction tests) and E2 (one hashed
runtime script) in the lanes that own them or report them precisely.
UPDATE 7:55 PM: SupportSettingsTests.swift is readable too (no feature-flag tests in it; flag coverage sent to V06).
E2 was re-assigned to follow-up lane V12b (V12 had finished before the file became readable).

## 2026-11-26 8:00 PM EST — proposed ODs from lane V approved (recommended defaults)
Owner approved the recommended default of every proposed OD below. Coordinator: add each to docs/OPEN_DECISIONS.md
(AGENTS.md format, text from the named report) with Status: **Approved by the owner 2026-11-26 8:00 PM EST
(recommended default)**, and the Implementation status shown. Anything needing a schema/format change is NOT built in
lane V (lane V stays on schema 27); add a plan row for it as work after the Codex pause.
- OD-142 (LANE-V03): translations of text that a component variant overrides — approved; Implementation status:
  "Not built; needs a new translation storage form (schema change). Scheduled after Codex verifies lane V."
- OD-050 (LANE-V07): rendered/visual snapshot diff, automatic snapshots with pruning, images and fonts inside component
  libraries — approved; Implementation status: "Not built in lane V (library package format and snapshot policy change);
  scheduled after Codex verifies lane V."
- OD-060 (LANE-V08): WOFF2 files macOS can't read are refused with the specific message — approved; Implementation status:
  "Built (lane V08, unverified): the specific refusal is the shipped behavior."
- OD-101 (LANE-V08): project files nothing uses are never removed automatically — approved; Implementation status:
  "Built (current behavior, unverified); images, fonts and media share the 2,000-file limit."
- OD-121 (LANE-V12): browser targets Safari 17, Chrome 120, Edge 120, Firefox 121 — approved; Implementation status:
  "Built (lane V12, ADR-0123, unverified): the browser support table uses these targets."
- New OD for SF-1204 authored CSS-rule model and "which rule wins" view (LANE-V12; coordinator assigns the next free
  lane H OD number, OD-122 unless taken) — approved recommended default: defer; Implementation status: "Deferred by
  approved decision; not built."
- Plus the already-approved OD-141 above.
NOT decided (still open, coordinator records as Open with the reports' recommendation): whether the per-lane menu
commands/sheets (Project Fonts…, Video & Audio…, Recolor SVG…, and the other lanes' sheets) join the central command
registry (SF-xxxx-006, LANE-V08). Also still open unless approved later: OD-100 16 MB media limit (recommended default in use).
Any further OD proposed by lanes still running (V01, V04–V06, V09–V11, V12b, V13) is NOT covered by this approval:
record it as Open with its recommended default and list it in the final summary for the owner.

## Notes for phase 2 (V14 cross-tree, V15 docs)
- LANE-V01 lists "batch 02 browser harness unreadable" as blocked — stale: Tests/Tooling/flow_runtime_browser.py and
  test_flow_runtime_browser.py have been readable since 7:40 PM. V14 must verify the batch 02 harness + bridge test.
- V07, V08, V10, V12 (and V01 on-device) could not run pydantic validation (cloud sandbox at capacity); V15 re-validates
  every LaneVResult against the schema before using it.
- OD-080 (LANE-V10: CMS field defaults, translated field values, scheduling/authors, canvas binding display, export) is
  proposed after the 8:00 PM approval → record as Open with its recommended default and list it for the owner.

## 2026-11-26 8:04 PM EST — OD-080 approved (recommended default)
Supersedes the note above. Owner approved the recommended default of OD-080 (text in docs/reviews/LANE-V10-review-2026-11-26.md).
Coordinator: add OD-080 with Status **Approved by the owner 2026-11-26 8:04 PM EST (recommended default)** and Implementation
status "Not built in lane V (several parts need a schema change); scheduled after Codex verifies lane V." Add a plan row for it.

## 2026-11-26 8:06 PM EST — OD-143, OD-144, OD-130 approved (recommended defaults)
Coordinator: add each with Status **Approved by the owner 2026-11-26 8:06 PM EST (recommended default)**.
- OD-143 (LANE-V04): the canvas measures a container's content box (inside padding and border), like the browser, for
  container-query rules. No schema change → BUILT IN LANE V by follow-up lane V16. Implementation status: per V16 report.
- OD-144 (LANE-V05 / ADR-0144): schema.org structured data generated from existing page/website metadata, only when a site
  address is set. No schema change → BUILT IN LANE V by follow-up lane V16. Implementation status: per V16 report.
- OD-130 (LANE-V13): external markup/asset importer starts with assets only. A new feature with its own import surface and
  migration story → NOT built in lane V; Implementation status "Not built; scheduled after Codex verifies lane V." Plan row.

## After-Codex queue (approved, not built in lane V) — coordinator adds plan rows in this order
1. OD-141 nested override paths (schema 28)  2. OD-142 variant-override translations (schema change)
3. OD-080 CMS field defaults / translated fields / scheduling / binding display / export  4. OD-050 visual snapshot diff,
automatic snapshots, images/fonts in libraries  5. OD-130 asset importer.
Still open (owner not asked yet / not approved): central command registry for per-lane sheets (LANE-V08); OD-100 16 MB limit.

## 8:08 PM notes
- LANE-V06 lists E2 as blocked "test files can't be read" — stale; E2 is owned by follow-up lane V12b.
- LANE-V06 out-of-area items (10 undo-compare tests in PersistedHistoryTests; custom code blocks Static Release under the
  strict policy) → follow-up lane V17.
- Proposed OD-145 (LANE-V06): preferred export target saved in the project — recommended default: keep it a per-export choice
  (current behavior). Pending owner answer.
- LANE-V09 left lane C todo items C6 (text bound to page variables), C7 (key-press trigger + page interactions overview),
  lane C 007 performance fixtures and 006 screen-reader announcements unstarted. Pending owner answer whether to build in lane V.

## 2026-11-26 8:09 PM EST — OD-145 approved; lane C leftovers to be built in lane V
- OD-145 (LANE-V06): approved recommended default — the export target stays a choice made at each export, not saved in
  the project. Status **Approved by the owner 2026-11-26 8:09 PM EST (recommended default)**; Implementation status
  "Built (current behavior, unverified)."
- Owner chose to BUILD lane C items C6 (text bound to page variables, SF-1106), C7 (key-press trigger on a focused object +
  page overview of all interactions with jump-to-object, SF-1101), lane C 007 performance fixtures and 006 screen-reader
  announcements now, before the Codex hand-off → follow-up lane V18. C8/C9 stay blocked (OD-070/OD-071 open).

## 8:15 PM — proposed by LANE-V11 (pending owner answer)
- OD-090: moving/resizing objects on the mirrored (right-to-left) canvas — recommended default in LANE-V11.
- Translating component text overrides, collection field values and page names/descriptions — overlaps approved OD-142
  (variant overrides) and OD-080 (translated collection field values); page names/descriptions are new. Coordinator:
  fold into OD-142/OD-080 where they overlap, record the page-name/description part with V11's recommended default.
- Exported text alignment following each language's direction (changes every exported stylesheet).
- Site date/number formatting per language (outside OD-038).
- LANE-V11 also corrected CommandKernelTests/testSelectedMediaAssetUseAndGlobalReferenceInventoryPreserveScope (same defect V05 noted).
- V14: LANE-V11 changed the `siteLanguages` feature-flag summary in SupportSettings.swift believing SupportSettingsTests.swift
  was unreadable (stale — readable since 7:55 PM). Check every string SupportSettingsTests asserts against the current summaries.

## 2026-11-26 8:16 PM EST — OD-090 approved; per-language date/number formatting approved in principle
- OD-090 (LANE-V11): recommended default approved — Status **Approved by the owner 2026-11-26 8:16 PM EST (recommended
  default)**. Implementation status: "Part 1 first half built (moving/resizing stay refused while mirrored; Mirror Layout
  opt-in, lane V11, unverified). Rest not built in lane V: mirrored pointer mapping + mirrored-by-default RTL default
  (after Codex verifies mirrored geometry); part 2 translations of component instance text overrides and page
  titles/descriptions (`locale.translation.v1.<id>.override.<property>`, per-language page metadata); part 3 logical
  `start`/`end` text alignment in export (changes every exported stylesheet). Scheduled after Codex verifies lane V."
  Overlap: collection item values stay under OD-080; variant overrides stay under OD-142.
- New OD (coordinator assigns next free lane E number after OD-090, i.e. OD-091 unless taken): site date and number
  formatting per language (outside OD-038). Status **Approved in principle by the owner 2026-11-26 8:16 PM EST — design
  to be proposed (recommended default and ADR) in the first lane E batch after Codex review**; Implementation status "Not built."
- After-Codex queue (updated order): 1 OD-141, 2 OD-142, 3 OD-090 (parts 1b/2/3), 4 OD-080, 5 OD-050, 6 OD-130,
  7 per-language date/number formatting (OD-091).

## 2026-11-26 8:17 PM EST — last two open items decided
- Central command registry (LANE-V08, SF-xxxx-006 for every lane's sheets): approved — Project Fonts…, Video & Audio…,
  Recolor SVG…, Snapshots…, Languages…, Collections…, History… (and every other lane sheet/command added since batch 17)
  join the central command registry as menu commands, discoverable by keyboard. NOT built in lane V; one cross-lane batch
  after Codex review. Coordinator: record as a new approved OD (next free shared number) with Status **Approved by the owner
  2026-11-26 8:17 PM EST** and add it to the after-Codex queue as item 8. V14 must still check that lane V's new menu
  commands (e.g. Edit > Show History… ⌘Y, File > Project Upgrade Details…) don't collide with each other or existing shortcuts.
- OD-100 (16 MB per video/audio file): approved — Status **Approved by the owner 2026-11-26 8:17 PM EST (recommended
  default)**; Implementation status "Built (lane F01 / V08, unverified)."
- No owner decision is open any more except OD-070 and OD-071 (lane C, C8/C9), which remain Open as before, and any OD the
  still-running lanes (V12b, V16, V17, V18) propose — list those for the owner in the final summary.

## 8:34 PM notes
- LANE-V12b finished E2 (one `siteforge-runtime.<sha256>.js` in Static Release; Development/Preview keep separate readable
  files) and the complete assets.manifest.txt. It proposed OD-123 (authored runtime modules, a per-page runtime parts list
  in Check Website, source maps; outside OD-042) — pending owner answer.
- LANE-V17 fixed 17 undo-compare assertions in 10+1 PersistedHistoryTests tests and added "Mark Custom Code as Reviewed"
  (`ProjectPreferences.build.reviewedCustomCodeDigest`, SHA-256 only; ADR-0037 Amendment 1). V14: verify the new optional
  preferences key decodes strictly, is omitted when empty, round-trips, and that ProjectPreferences comparison/snapshot
  restore/template creation treat it consistently with the other build-preference keys.

## 2026-11-26 8:34 PM EST — OD-123 approved (recommended default)
- OD-123 (LANE-V12b): runtime stays generated-only (menus, Flow, motion, interactions) in one content-hashed file per site
  in Static Release; authors add their own scripts through Custom Code (SF-1107); Check Website shows the bundle in Output
  files and Profile comparison; no source maps. Status **Approved by the owner 2026-11-26 8:34 PM EST (recommended
  default)**; Implementation status "Built (lane V12b, ADR-0124, unverified)." No plan row needed.

## 8:41 PM notes
- LANE-V16 built OD-143 (content-box container width via `contentInset` + one `evaluated` path) and OD-144 (one JSON-LD
  block per page when a site address is set). Implementation status for both: "Built (lane V16, unverified)."
- V14 must fix: `CanvasRendererTests/testContainerQueriesFollowEachCopysContainerOnCanvasPreviewAndExport` (batch 09) builds
  a fixture with a Hug-width container, which document validation rejects, so the test fails before its assertions. Fix
  the fixture to a valid sizing that still exercises the intent; also decide/remove the unreachable "skip Hug-width
  container" branch only if it is provably unreachable in valid documents (document the reasoning; don't weaken tests).

## 2026-11-26 9:55 PM EST — decisions on the V14 findings
Coordinator: record each as an approved decision (V14a's proposed OD number for SF-0605, next free otherwise) with
Status **Approved by the owner 2026-11-26 9:55 PM EST**.
1. Container queries on static-layout pages (V14a, SF-0605-003): the owner chose the ALTERNATIVE, not the recommended
   default — **make them work in the browser**. Static-layout export must give every container-query container a real DOM
   container ancestor (wrap its objects) so `@container` rules match in browsers exactly as on the canvas, without changing
   absolute positions, stacking, accessibility order, interactions/overlays (FlatContainerOutput), motion, localized trees,
   collection pages or the Static Release/integrity outputs. Built in lane V by follow-up lane V19. Schema 27 unchanged.
2. Container-query Show writing plain `display: block` (V14a, SF-0605-003): **fix now**. Show must restore each object's own
   display (flex/grid/inline-flex for containers, text, controls) and must be able to reveal an object hidden at another
   breakpoint or by a less specific rule. Built by lane V19 together with item 1 (same emitter).
3. View > Move Selection Right 1 px on Control-Right Arrow (V14b): **change the shortcut** to one with no macOS system
   collision (Mission Control), consistent with the other nudge commands; update the UI test that presses it and any docs.
   Built by follow-up lane V20.
4. Delete with Uses refusing while a translation or collection item uses the image (V05/V14e, ADR-0087): **keep the
   refusal** (recommended). Record as approved; no code change. The proposed OD is closed as "keep current behavior".

## Cross-tree items for V14 (out-of-area findings of finished lanes, not yet owned)
- LANE-V04: hidden text may still show in exported pages (check every hide path: visibility rules, container-query hide,
  interaction start-hidden, localized trees) — verify and fix.
- LANE-V04: fixed-position objects may be misplaced in Preview and in the responsive audit — verify and fix.
- LANE-V13 added Edit > Show History… with Command-Y: check the whole menu/command tree and the UI tests for shortcut
  collisions (Redo, other lanes' new commands) and native macOS convention; change the shortcut if it collides.
- Many lanes edited WorkspaceShellModel.swift / WorkspaceShellView.swift concurrently: re-read both files whole
  (duplicate members, conflicting state, SwiftUI body size, isolation).
