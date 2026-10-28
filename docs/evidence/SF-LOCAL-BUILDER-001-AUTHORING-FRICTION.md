# Aurora — observed authoring decisions and friction

## Matched public-control measurements — 2026-10-21

The 2026-10-20 inventory below is historical. Its planned reuse conveniences are
now implemented with focused evidence, following the completed 804-test repair
checkpoint. Current changed-tree integrated and installed acceptance remain pending.

| Matched task | Old actual pointer actions | New actual pointer actions | Boundary |
| --- | --- | --- | --- |
| Duplicate current content with name Related and route /related | 10 | 6 | Duplicate/Rename/Route versus opt-in named copy; same typed values, equal typing excluded |
| Include two missing destinations in current Header | 2 | 1 | Two checkbox edits versus one Include All Pages transaction |
| Choose Text Foreground for a plain Text selection | 2 | 0 | Former target popup/item versus contextual default; not total typography operations |

Actual action arrays are retained as `A2B24BE8-7724-42D1-98B5-3DB8084292CE.json`
under ignored workflow-reuse-20261021 report storage. Setup, undo-to-baseline and
inspection are outside the matched tasks; no elapsed-time/universal savings claim.
The page/navigation audit passes (231.866s); native compact controls (31.913s),
Return/Tab/Escape/context editing (62.482s), and normal Aurora copy/Safari/native
reopen (142.149s) pass. All nine controls and seven Aurora captures inspected.
Header/Footer remain independent. Existing tablet ellipsis for long navigation
labels and authored fixed-layout spacing remain visible, not silently rewritten.
Full website font/layout parity and a new shared-header architecture are excluded.

## Reconciled decision/action inventory — 2026-10-20

The complete sequence below was reviewed against actual event logs, the public
authoring helper and current controls. Counts here are bounded observations,
not a finished matched end-to-end click benchmark. Primary requirements for the
pending reuse slice are SF-0303-002/003/004/005/006, SF-0308-002/003/005/006,
SF-0701-002/003/004/005/006 and SF-0702-003/004/005/006; navigation remains under
the existing connected-structure and SF-0806 contracts. Modules remain Partial.

| Desired result | Observed old sequence | Implemented simplification and evidence | Remaining action / limit |
| --- | --- | --- | --- |
| Edit a linked Button's label, dimensions, styling and destination | `aurora-destinations-actions.log`, first linked action: Content at 339.51s, Layout at 349.68s, Design at 367.09s, Interactions via overflow at 420.04s. A redundant Design click at 377.21s is not a destination change. | Essentials uses existing label/dimension/target registries on Design. Its passing native journey makes zero additional Inspector-destination changes after selecting Design. | Four visits / three between-destination changes are observed in the old operation span. Values/target kind differ in the new journey, so a matched total-click or transaction saving is not yet claimed. Add a comparable public-control audit. |
| Set text family, line height, size, tracking, alignment and foreground | Actual helper `typography` operates six value controls; the linked-action log records those entries from 382.84–417.81s. Some are unchanged defaults and must not be counted as canonical transactions. | Shared typography/foreground are adjacent to Essentials; Return/focus-loss paths and mixed subset registry remain authoritative. | No reduction from six typography value operations is proved. Verify Tab/end-edit, invalid/Escape and compatible multi-edit without forcing unlike Aurora text styles to match. |
| Create a related page with Header, body Section, Text and Footer | Actual destination helper creates a page, then inserts Header, Section, Text and Footer: five primary structural commands before copy, geometry and typography edits. | Existing Duplicate Page remaps internal identities and keeps ordinary editable structure. No new reuse convenience has been implemented yet. | Add opt-in current-page reuse to the existing native page-details workflow, with name/route in one transaction and cancellation; preserve independent custom content. Measure against actual Duplicate → Rename → Route controls. |
| Include newly created pages in Header/Footer navigation | Actual navigation log records 12 inclusion-checkbox activations across the eight Header/Footer inspections. Already-included checkboxes were inspected, not clicked; do not call all 32 checks edits. | Per-page inclusion already uses stable PageIDs and the central registry. | A bounded Include All convenience can compile the same edits atomically per owner while preserving labels/order/custom layout. No cross-page live-linked Header/Footer semantics are authorized or implemented. |
| Ordinary responsive flow | Old per-child overrides and the 574-point compensation are recorded below. | One explicit conversion commits seven compatible nodes, skips two fixed Buttons; one shared padding edit and eight actual Safari widths are reviewed. | Existing overrides remain opt-in; no silent original conversion or universal browser typography parity. Do not replay conversion on the Study. |
| Stable, directly visible editing surfaces | Original slim panes forced overflow; Direction label wrapped; some menu ambiguity was automation-only. | Measured five-tab layout, stable eight-state Inspector sequence, upright text and exact native segments have focused proof. | Final accumulated gate is not green. The latest unrelated notification obstructs title-bar Undo (OD-024); do not misclassify that pointer obstruction as a product command defect. |

Phase two is planned, not source-complete. The original Aurora and its recovery
remain protected; no new authoring was replayed during the acceptance retry.

Owner follow-up, 2026-10-18. This records the actual public-control workflow;
it is not a claim that the subsequent streamlining work is implemented.
Aurora delivery remains the priority. Preserve its delivered original and
demonstrate later workflow improvements on a normal-command duplicate.

Requirements in scope: bounded SF-0405-003/006, SF-0502-003/005,
SF-0503-003, SF-0506-003/005, SF-0507-003/005, SF-0602-003/005,
SF-0801-002/004/005, SF-1202-003, SF-1203-003/004, SF-1204-003/004,
SF-1205-003/004, SF-1207-003/004. No full-module completion is claimed.

## Sequence and decisions

| Step / intended result | Shipping controls and manual work | Observation / classification | Resolution and recurrence |
| --- | --- | --- | --- |
| Pale coastal hero, independently editable | Assets import; Section Image Fill; Content height/padding; child Frame dimensions and RGBA field | Several Inspector tabs and dimension edits were required. This is real authoring friction, not a fixture need. | Existing tools sufficed. Independent image/overlay/text retained; no handwritten output or project data. Repeated dimensions remained necessary. |
| Retain nested text selection while editing | Layers row, inline editor, Layout Width, Undo/Redo | Real product defect: ordinary isolation synchronization reset the selection container after document changes. | Synchronize only on an actual isolation-root transition. Focused nested-selection regression passes. No per-object workaround remains. |
| Editorial serif and purple eyebrow | Design family, line height, size, tracking, alignment and foreground fields; three separate Text nodes | Many repeated field/tab operations. Georgia was chosen from installed fonts rather than importing an unlicensed/unavailable reference font. | Ordinary canonical typography and scene-local drafts. Layout/Design switches recur for every text object. |
| Center paragraph alignment | Native typography popup | Automation-only ambiguity: Window > Center and the popup's Center were both globally matched. | Scope the real popup item and click its own frame; no product control was replaced. |
| Stack alignment | Native segmented Layout control | Automation-only mistake: treated segmented buttons as menu items. | Drive its actual radio button and verify selection. No production change required. |
| Solid/outlined linked actions | Insert Button, Content label, Layout dimensions, Design fill/foreground/border, color token binding, Interactions Page target | Useful capabilities exist but are buried across tabs and scrolling sections. Reusing a color requires several more controls. | Both actions remain ordinary editable nodes. Shared compiler gaps were fixed rather than patching exported HTML. |
| Match app and website output | Native Preview Website in Safari and Export | Real output defects: collapsed authored line breaks, inert targeted Buttons and omitted Button border. | Pre-wrapped typography; validated destinations emitted as anchors; existing box-style applicability shared. Three exact compiler regressions pass. Untargeted actions remain inert. |
| Create real destinations | Page > New Page; Header/Section/Text/Footer insertion; inline copy and typography; native Save | Repeated scaffolding and settings per page; navigation inclusion had to be updated after new pages were added. | Four real pages retained. Included Pages and mobile-menu controls edited on each Header/Footer. Reusable page/chrome authoring is a candidate, not implemented here. |
| Clear a mistaken Journal title override | Native Site Settings title field | Empty `typeText` did not delete a selected string: automation issue. Separately, Apply on unchanged settings leaves the sheet open with a generic appearance no-change message: real workflow/diagnostic friction. | Select the actual field contents and send Delete, then Apply. The offscreen Reset button was not used. Close no-change sheets normally. No package metadata was mutated directly. |
| Adapt hero to Tablet/Mobile | Existing breakpoint selector; Stack X/Y/width; Text heights; action direction; Fluid Value controls | Real responsive friction: repeated per-box overrides and three endpoint fields per fluid property. Fixed Mobile width plus increasing fluid type exposed overlap at an intermediate 574-point browser width. | Increasing the authored Mobile headline height from 160 to 280 compensated for this sample. This is not automatic layout. Fill/hug/intrinsic sizing, wrapping and typography/container agreement require the subsequent owner-bounded pass. |
| Align committed app text and Safari text | Preview Website and responsive browser inspection | Output used top-aligned text while CanvasTextLayout vertically centers within the authored frame. | Shared plain-Text output now centers vertically, preserves line breaks and clips at the same frame; control typography remains separate. No canonical object offset was added. Focused compiler checks pass 3/3. |
| Read compact container controls | Layout Direction / Reset | Real UI defect: Direction wrapped beside two segments and Reset. | Separate intrinsic-width label/reset row and full-width segments. Updated installed build; reopened Mobile check retained. |
| Navigate Inspector/navigator destinations | Visible tabs and native overflow menus | Real workflow cost: only three destinations fit the current slim panes; repeated overflow access is required. | Kept all destinations operable for this delivery. Owner now requires all five visible at normal sizes; no claim that overflow satisfies that follow-up. |
| Review Safari desktop/mobile and menu | Real browser anchors, native Responsive Design Mode, accessible width/height fields, summary Return/Escape | XCTest exposed Safari as a Disabled root despite a visible loaded page. Standard macOS accessibility could read and operate it. Early immediate menu reads and successive Enter/Space toggles falsely suggested a defect. | Conditional state waits plus sanitized event tracing proved Return opens and Escape closes with focus retained. Temporary page diagnostics were removed. No speculative menu patch. |

## Evidence retained outside the repository

Original-resolution captures and native event/test logs are retained with the
owner-local correction evidence, not committed as generated test artifacts:

- `aurora-home-overlay-editorial-copy-radio.xcresult`: independent overlay,
  eyebrow, headline and copy; stable node identities in the UI event log.
- `aurora-destinations-actions.xcresult`: About, Contact and styled linked actions.
- `aurora-navigation-responsive-settings-noop.xcresult`: all-page navigation,
  Desktop/Tablet/Mobile captures and actual control sequence.
- `aurora-reopen-corrected-artifact.xcresult`: reopened ordinary package and
  readable Direction capture; its final export-confirmation locator failed.
- `aurora-corrected-export-replacement.xcresult`: exact native Replace
  confirmation and successful corrected-artifact export.
- `aurora-safari-desktop-corrected.png`, `aurora-safari-journal-corrected.png`,
  `aurora-safari-about-corrected.png`, `aurora-safari-contact-corrected.png`.
- `aurora-safari-mobile-390-corrected.png` and
  `aurora-safari-mobile-390-menu-confirmed.png`: real Safari responsive viewport.
- `safari-menu-native-event-trace.txt`: category/tag/key/open-state diagnostics
  distinguish genuine input from premature automation conclusions.

Known visual review limits: the generated coast and Georgia differ from the
reference photograph/font. The 574-point overlap required manual height compensation; automatic intermediate-width sizing remains unimplemented.
Inspector shifts have not yet been independently isolated; only the specific
Direction wrap is fixed. No full gate or final delivery acceptance is implied.

## Proposed subsequent review order — not implementation authorization

Historical before-state above is superseded for the bounded owner-authorized
follow-up by `SF-LOCAL-BUILDER-001-RESPONSIVE-WORKFLOW.md`: measured five-tab
rows, stable Inspector sequence, neutral Settings Apply, Design Essentials,
explicit Fill/Hug conversion, installed Study save/reopen and eight-width
Safari review now have focused evidence. The original Aurora is unchanged.
Label/size/destination edits require zero extra Inspector-tab transitions in
the new Essentials journey. Seven nodes convert atomically with two fixed
Buttons explicitly skipped; one shared 32-point padding edit replaces per-child
spacing compensation in the Study. No unmeasured percentage/time savings are
claimed. The accumulated final verification gate remains required.

1. Canonical containing-width fill/hug/intrinsic rules and bounded wrapping;
   preserve deliberate responsive overrides and verify intermediate widths.
2. Stable Inspector field grids/gutters, disclosures, help rows and focus
   scrolling, reproduced from this exact selection/edit sequence.
3. Measure real labels/targets and keep all five destinations visible in each
   sidebar at normal supported sizes without microscopic type or hidden overflow.
4. Consolidate safe direct editing, Return/Tab/end-edit commits and coalesced
   undo; preserve Escape, invalid/stale neutrality and destructive confirmations.
5. Evidence-backed contextual defaults/presets, multi-edit and reusable styles.

The coordinator will bound that pass after Aurora delivery. Demonstrate it on
a duplicate created through the normal app command; preserve the original.
