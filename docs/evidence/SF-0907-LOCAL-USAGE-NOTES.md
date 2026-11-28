# SF-0907 — Local component usage notes

## Scope and boundaries

- SF-0907-001/003/005. `component.documentation.v1.usageNotes` is an
  optional authored property on the exact canonical definition root.
  Missing notes have no property or synthetic value. Project schema 20
  accepts the field and rejects its namespace under earlier headers.
  Version-19 documents read with existing identities and no new notes.
- SF-0907-002/004/005/006. Component Details shows the current committed
  note or No usage notes. The native TextEditor has a separate draft.
  Apply or Clear compiles one existing property command and inverse.
  Cancel inside Details discards the draft. Escape dismisses Details and
  discards the draft. Rejected edits retain their draft and explain
  recovery. The component registry checks document, revision, scene,
  definition root, lifecycle and captured selection.
- SF-0907-003/004/005. Local duplication and compatible cross-project
  transfer use the existing definition remapper. Clipboard v2 still
  works for payloads without notes. Clipboard v3 carries authored notes,
  with equivalent definitions reused and different notes resolved by
  the existing import/rename flow. Instance overrides remain independent.
- SF-0907-008. Model diagnostics on note apply and clear record requirement,
  operation, sanitized definition identity, duration and result. Cancel
  records its result. The note itself stays out of diagnostics and dependency
  summaries. Instance expansion strips it before detachment or projection.
  Static output and asset discovery use their existing typed projections.

The canonical text limit is 4,096 UTF-8 bytes. Carriage-return line
endings normalize to line feed, Unicode normalizes to NFC, and surrounding
whitespace is removed. Tabs and internal newlines are supported. Other
controls are rejected. A blank normalized draft clears an existing note.
Applying an identical or already absent value creates no transaction.

Broader SF-0907 examples, catalog generation, component versions, and
scale and assistive-technology acceptance remain pending. Neither OD-018
nor OD-019 is required for this slice.

## Verification and handoff

The isolated baseline is HEAD `013393965a49f925d42fd5d8ba82497bdd83c79b`,
source/test/tool SHA-256
`30b3e067046d0db0b97ce8cec151ed5ca708fe0e786b29c7bbf3daafaa970d25`.
Its prior full local gate counted 890 core and 167 UI passes, three
approved skips, and zero failures/unrun.

The candidate source/test/tool SHA-256 is
`16ac0d194c36884fce132d4663503b705e37c6d025205de306172c8627d3577f`.
With process-scoped Xcode 27.2 (27B52), repository checks, the app build,
build-for-testing, and focused core execution all exited 0. The initial
repository check exited 1 because the headless component registry called
into ClipboardTransfer. The shared graph remapper moved into TransformModel
and the existing architecture check passed unchanged. The final isolated
bundle `component-notes-headless-refactor.xcresult` contains 20 passing methods,
including all five new methods. The other methods cover component binding,
organization, transfer, persisted history, strict schema shape, and the
immutable schema-four legacy package. The new history test reopens both
stacks and verifies that redo clears and undo restores the saved note.
The output test compares resolved pages, native render objects, and
generated text and binary files before and after adding notes.

### Native acceptance

- `SiteForgeUITests/SiteForgeLaunchTests/testComponentOrganizationDependencyInspectionAndWhereUsedJourney`

The extended selector retains the existing dependency inspection and
Where Used assertions and adds the linked-instance entry point, native
Apply, Cancel and Escape, saved-project reopen, and Clear. It reuses the
existing hosted exact inventory entry. The extended journey measured
99.374s on this Mac. The hosted timing inventory remains on its existing
baseline. The integrated `./sf verify` ran on the same source.

The isolated incremental patch applied to the shared checkout. The install
entry in the continuation handoff, the coordinator's AGENTS.md, and the
previous install evidence were preserved. The shared build-for-testing
exited 0 with the same source/test/tool fingerprint as the isolated copy.

The first exact desktop attempt exited 65 before executing its selector.
XCTest timed out enabling UI automation while macOS presented its
authentication dialog. The failure bundle is
`focused-53fe5831-75fe-40b1-941a-9346bc29975d.xcresult`. At that checkpoint, the preceding green owner-local build was still installed.

After owner authentication, the exact selector passed in 99.374s with
exit 0 in `focused-e9c69fb5-5bd7-44db-abee-127245f623d6.xcresult`.
The retained reopened-sheet screenshot shows the note, the exact
definition, and its original Where Used row together. The shared
repository check also exited 0 with a fresh absolute module-cache path
after the first shared check found a duplicate Swift module caused by
reusing the isolated cache through a different path spelling.

### Integrated verification

The shared `./sf verify` exited 0 in
`full-58aea37e-6067-4657-8e62-e140281568f7.xcresult`. The bundle accounts
for 1,065 unique methods: 895 core passes, 167 UI passes, three approved
owner Dark Flow skips, zero failures, and zero unrun. All 170 UI
selectors match the hosted inventory. The extended Details journey
passed in 101.332s in this run. Source/test/tool SHA-256 remained
`16ac0d194c36884fce132d4663503b705e37c6d025205de306172c8627d3577f`.

### Owner-local installation

`scripts/package-owner-local-app.sh --install` exited 0. Owner-local build
`26.11.15` (app version `0.1.0`) was built November 15 at 18:24 Eastern.
Strict code-signature verification exited 0. The installed
`SiteForgeSourceFingerprint`, OwnerTesting provisioning, and shared
source-content calculation all match
`c1b7f1b00ae5d8df9e0ac3e614057f2c7080b8206ca8e983b82381f4594a8276`.
The prior bundle is recoverable through the installer's existing backup.
The installed receipt uses the source-content hash, and the verification
receipt uses the Git binary diff hash.
