# Lane V summary — November 26, 2026 7:00–11:29 PM EST (Code Forge, unverified)

Owner request (6:55 PM): treat every Code Forge batch and file edit as unverified, check dev-doc gaps and Codex code
quality, fix every issue, finish partial features, and leave a clean stopping point for Codex. At 11:28 PM the owner
handed the tree to Codex ("do nothing, codex will begin review"). No lane writes after RP-2026-11-26-VFINAL.

## State for Codex
- Nothing compiled or run: the Windows PC has no Swift toolchain, browser or VoiceOver. Every change was checked by reading.
- Document schema 27, persisted-history schema 4, WebsiteMetadata version 3. No new Swift files (Xcode project untouched).
  New non-Swift files: review reports, ADRs, `Tests/Tooling/interaction_runtime_browser.py`, `Tests/Tooling/test_interaction_runtime_browser.py`.
- Lane V wrote 284 times to 93 files (31 Swift), all through forge_io (ledger `_quick-scratch\WRITE_LEDGER.tsv`).
  Final read checks: bracket balance + duplicate types/members `check()` = [], no iCloud " 2" copies, no locks, no foreign writes.
- Restore points: RP-2026-11-26-V00 (before lane V), -V14 (after the 13 area lanes), -V19 (before the static-layout
  container-query change), -VFINAL (this state). Restore single files, not the whole tree.
- The five former iCloud placeholders (ci.yml, docs/TESTING.md, SupportSettingsTests.swift, flow_runtime_browser.py,
  test_flow_runtime_browser.py) were downloaded at 7:40–7:55 PM and are now normal files; some were edited.

## Reports (scope, fixes, requirement tables, new/changed test selectors, suggested first checks)
V01 b01–03 · V02 b04–06 · V03 b07–08 · V04 b09–11 · V05 b12–14 · V06 b15–17 · V07 lane A · V08 lanes B+F · V09 lane C ·
V10 lane D · V11 lane E · V12 + V12b lane H/E2 · V13 lane I · V14a–e cross-tree · V16 OD-143/144 · V17 undo tests +
custom-code review · V18 lane C6/C7 · V19 static-layout container queries + Show · V20 nudge shortcut · V21 Pan vs text fields.
All at `docs/reviews/LANE-V<NN>-review-2026-11-26.md`. **Start with LANE-V14e**: its consolidated, deduplicated
"Suggested first checks for Codex" list (ordered by compile risk) covers V01–V18; then the first-checks sections of
V19, V20 and V21, written after it.

## Highest-risk changes (verify first)
1. LANE-V19: static-layout export wraps each queried container in a zero-origin content-box wrapper; container-query Show
   no longer writes `display:block`. Compare exported pages in a browser at 390/768/1440 px, dark mode and RTL trees.
2. LANE-V14a: hide rules on static-layout and connected pages, dark-mode ordering, Preview/audit fixed-position origin.
3. LANE-V12b: Static Release writes one `siteforge-runtime.<sha256>.js`; browser harness now runs Static Release sites.
4. LANE-V14b/V20/V21: four shortcut changes, Show History in Focus Mode, edit-boundary for project sheets, Pan/nudge enable rules.
5. LANE-V18: C6 bound text (`state.v1.text`) and C7 key-press triggers in the generated runtime.
6. LANE-V10 Collections Import tab; LANE-V13 history command/upgrade sheet; LANE-V17 `ProjectPreferences.build.reviewedCustomCodeDigest`.

## Owner decisions (full text: LANE-V-OWNER-DECISIONS-2026-11-26.md — not yet applied to OPEN_DECISIONS.md)
- Approved and built (unverified): OD-060, OD-100, OD-101, OD-121, OD-123, OD-143, OD-144, OD-145; container queries working
  in browsers on static-layout pages and Show restoring display (9:55 PM); nudge shortcut change; keep the delete refusal
  for images used by translations/collection items.
- Approved, NOT built (after-Codex queue, in order): OD-141 nested override paths; OD-142 variant-override translations;
  OD-090 rest (mirrored dragging, more translatable text, logical text alignment); OD-080 CMS follow-ups; OD-050 visual
  snapshot diff / automatic snapshots / library images and fonts; OD-130 asset importer; OD-091 date/number formatting
  (approved in principle); central command registry for every new sheet.
- Deferred by decision: SF-1204 authored CSS-rule model and "which rule wins" view.
- Still open: OD-070, OD-071 (lane C C8/C9); V19's proposed OD for revealing, on page-flow pages, an object hidden at a
  breakpoint (current behavior = its recommended default; owner did not answer).

## Not done / needs a Mac (no lane could do these)
Build and run every new/changed selector; UI tests (need measured `scripts/ci-ui-timings.txt`); 10,000/20,000-object timing;
both browser harnesses with Chrome (2 Flow helper checks also need a normal Python); VoiceOver / Full Keyboard Access / 200%
text; Aurora Flow sample + Start card; `REQUIREMENT_EVIDENCE.json`, `IMPLEMENTATION_STATUS.md`, `CHANGELOG.md`,
`CODEX_HANDOFF.md`, `CODEX_QUEUE.md` left to Codex as before. Open question from LANE-V21: single-letter Insert shortcuts and
plain Return may fire while an Inspector text field has focus — check on the Mac.

## Docs not consolidated (owner stopped lane V before the coordinator ran)
OPEN_DECISIONS.md status lines, per-lane DEVELOPMENT_PLAN rows and per-lane activity-log entries were not applied. Each lane
report's "Intended plan / OD status-line changes" section has the exact text.
