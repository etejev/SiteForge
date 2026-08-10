# Final Implementation Audit

- Audit date: 2026-08-09
- Baseline: `main` at `a89248e2fd7a` plus the uncommitted audit-correction set reviewed in this report
- Environment: macOS 27.0 (26A5388g), arm64; Xcode 27.0 (27A5194q)
- Scope: `AGENTS.md`; the SiteForge specification; queue, project and implementation status; requirement-evidence index; ADRs and open decisions; canonical model, command/history, persistence/recovery, lifecycle, canvas/layout/renderer/overlay, workspace/accessibility, build scripts, unit tests, UI tests, fixtures, and retained evidence.

## Commands and results

The following commands were run during the audit.

```text
git diff --check
jq empty docs/REQUIREMENT_EVIDENCE.json
scripts/select-test-scope.py --self-test
scripts/check-architecture-boundaries.py
scripts/check-traceability.py
./sf verify
```

- `git diff --check`: passed.
- Requirement-evidence JSON validation: passed.
- Test-scope selector self-test: passed (5 checks).
- Architecture and traceability checks: passed in the final full gate.
- Focused persistence/lifecycle/filesystem gate: 81 tests passed, zero failures.
- Final `./sf verify`: passed on 2026-08-09. It built the application and ran
  288 unit tests plus 29 UI tests (317 total), with zero failures or skips.
  Repository security, traceability (125 bounded requirement records),
  architecture, migration, evidence, fixture-hygiene, and test-scope checks
  all passed.

## Completed audit corrections

The audit patch closes the following concrete defects without broadening the
product scope.

1. **Headless strict-schema composition.** `StrictDecoding.swift` is compiled
   by the application target and every canonical-model/evidence typecheck
   slice. Current schema-v3 decoding now has one explicit closed-key policy;
   repository checks fail if that source leaves the target or the headless
   slices. Affected requirements: `SF-0301-004`, `SF-0301-005`,
   `SF-0303-005`, `SF-0307-004`, `SF-1702-004`, `SF-1902-004`.

2. **Lifecycle pre-adoption safety.** A typed transition attempt now scopes
   authorization and recovery retirement before a document-adoption epoch
   exists. Stale reads clear only their own bookkeeping, and recovery cleanup
   rechecks the attempt inside the backend before its filesystem boundary.
   Lexical destination identities remain stable across Foundation's
   `/var`/`/private/var` spelling changes, while descriptor I/O remains the
   source of actual file identity. Affected requirements: `SF-0301-004`,
   `SF-0306-003`, `SF-0306-004`, `SF-1504-003`, `SF-1504-004`.

3. **Recovery artifact ownership.** Logical recovery retirement now exchanges
   the validated artifact for a versioned, project-bound binary marker. An
   unrelated empty owner-restricted file is rejected and preserved; it cannot
   be mistaken for an owned marker. The save/recovery state is only cleared
   after the owned retirement succeeds. Affected requirements: `SF-0306-003`,
   `SF-0306-004`, `SF-1504-004`, `SF-1603-004`, `SF-1604-004`,
   `SF-1702-004`.

4. **Bounded malformed drag validation.** Parent-chain depth traversal now
   detects cycles and stops at policy depth. A rejected hover returns to an
   active drafting state so a later valid row can commit through the same
   capability; diagnostics use payload-free categories, and unavailable
   accessibility actions announce a concrete reason rather than silently
   returning. Affected requirements: `SF-0408-001` through `SF-0408-008`.

5. **Truthful evidence and status.** Documentation now records schema-v3 and
   history-v2 as current, preserves explicit compatibility limitations, limits
   drag claims to the exercised source-level and contextual paths, and links
   the new test evidence. The requirement-evidence index remains Partial where
   later product acceptance is not proven.

## Findings

### Blocker

None observed after the corrections listed above and the final full gate.

### Critical

None observed after the corrections listed above and the final full gate. The
filesystem contract is intentionally bounded rather than represented as a
universal final-syscall guarantee.

### Major

#### M-01 — macOS cannot make the final pathname rename/unlink identity-conditional

- **Affected requirements:** `SF-0301-004`, `SF-0301-005`, `SF-0306-003`,
  `SF-0306-004`, `SF-1504-003`, `SF-1504-004`, `SF-1603-004`, `SF-1604-004`,
  `SF-1702-004`.
- **Evidence:** `SiteForge/IdentityBoundFileSystem.swift` validates descriptor
  snapshots and staging immediately before `renameatx_np`, but macOS provides
  no expected-inode source argument for that final syscall. A same-UID hostile
  writer can replace a staging or public name after the last validation.
  ADR-0007 and OD-014 describe this platform boundary.
- **Why it matters:** The exercised path, symlink, inode, metadata, and
  controlled-barrier races are protected, but no code-only change can claim
  universal preservation against a continuously racing same-UID process.
- **Bounded remediation:** obtain an owner-approved trusted-root retention and
  reclamation threat model (OD-014), then design any maintenance operation with
  an independently reviewable capability/ownership contract. Do not add
  opportunistic pathname cleanup.
- **Required regression before changing the policy:** deterministic
  same-UID/adversarial replacement coverage using the selected trusted-root
  primitive, including external-byte preservation and retained-artifact
  accounting.

#### M-02 — Native drag terminal cleanup is not end-to-end exercised

- **Affected requirements:** `SF-0408-001`, `SF-0408-002`, `SF-0408-003`,
  `SF-0408-004`, `SF-0408-006`, `SF-0408-008`.
- **Evidence:** `NavigatorLayerRow` creates an editor-only source capability
  through SwiftUI `onDrag`; there is no source-side native drag-end callback
  when a drag finishes outside every target row. Model-level cancellation,
  stale identity, invalid-hover repair, and canonical-neutrality tests pass,
  but the retained UI evidence is a contextual action, not an XCTest-created
  AppKit drag gesture.
- **Why it matters:** No canonical mutation occurs without a validated commit,
  but an editor-only drag capability can remain until a later scene/tool/
  lifecycle boundary.
- **Bounded remediation:** add a window-local AppKit drag-session terminal
  bridge, or retain this as an explicit Partial boundary until native
  end-to-end gesture automation and cancellation evidence exists.
- **Required regression:** begin a native drag, leave every drop target,
  release/cancel, assert session/payload/indicator cleanup, no history entry,
  no canonical mutation, and correct accessibility announcement.

### Minor

#### m-01 — Foundation JSON decoding cannot detect duplicate object keys

- **Affected requirements:** `SF-0301-004`, `SF-0303-005`, `SF-0307-004`.
- **Evidence:** `StrictDecoding.swift` obtains a Foundation keyed container;
  `PersistedHistory.swift` also receives a Foundation JSON object. Duplicate
  keys are collapsed before the exact-key policy observes them.
- **Why it matters:** Current schemas reject missing and unknown keys, but do
  not prove duplicate-key rejection at raw JSON byte level.
- **Bounded remediation:** add a duplicate-preserving JSON parser at the
  package/schema boundary.
- **Required regression:** current document, manifest, and persisted-history
  payloads with duplicate keys must reject without canonical adoption.

#### m-02 — Persisted-history v1 compatibility lacks an immutable historical fixture

- **Affected requirements:** `SF-0307-004`, `SF-0307-005`, `SF-0307-006`.
- **Evidence:** `PersistedHistoryTests` exercises v1 compatibility by mutating
  current output rather than loading a tracked independently produced v1
  `history.json` golden.
- **Why it matters:** an encoder and migration regression could move together.
- **Bounded remediation:** retain a checksummed, provenance-documented v1
  history fixture beside the existing package-v1/schema-v1 fixtures.
- **Required regression:** decode, validate inverse/order, reopen, undo/redo,
  and deterministic current-schema re-save from that immutable input.

#### m-03 — Final XCTest result retains SwiftUI publication and QoS warnings

- **Affected requirements:** `SF-0201-008`, `SF-0203-008`, `SF-1902-008`.
- **Evidence:** the 2026-08-09 final result bundle passed all 317 tests but
  recorded 21 `Publishing changes from within view updates` warnings and two
  Xcode-reported priority-inversion warnings. The result bundle does not
  attribute either category to a unique SiteForge source location.
- **Why it matters:** neither category caused a failing behavior in this run,
  but repeated publication-during-update warnings can become UI instability.
- **Bounded remediation:** add source-attributed runtime-warning capture and
  remove the specific synchronous publication path once identified; do not
  suppress warnings or relax UI assertions.
- **Required regression:** exercise the affected workspace and launch flows
  with the warning capture enabled and assert no SiteForge-attributed warning.

### Observations

- The canvas text tile evidence proves bounded clipped AppKit text pixels, not
  production text shaping, fallback, images, or effects (`SF-0405-006`,
  `SF-0406-001`, `SF-0407-007`).
- Performance samples are local smoke evidence with named environments and
  limits. Large full-scan results that exceed one 60 Hz frame remain explicitly
  non-release and non-incremental evidence (`SF-0401-007`, `SF-0402-007`,
  `SF-0403-007`, `SF-0404-007`, `SF-0405-007`, `SF-0406-007`, `SF-0407-007`,
  `SF-0408-007`, `SF-0501-007`).
- Automated accessibility semantics are covered at the bounded shell level;
  actual VoiceOver speech and the complete OS accessibility-settings matrix
  have not been manually exercised.
- The final XCTest result passed but retained the two warning categories
  described in m-03; they are reported here rather than treated as a clean
  runtime-warning baseline.

## Boundaries confirmed

- Canonical document state remains separate from selection, insertion,
  transform, drag, hover, overlay, viewport, and other editor convenience
  state; repository architecture checks enforce that these editor models are
  not `Codable` canonical content.
- Commands mutate through the central transaction/session boundary and retain
  exact inverse/history behavior; selection and drag convenience actions do
  not create history entries on their own.
- Package reads bind bytes, digest, size, metadata, and file identity to one
  descriptor snapshot. Recovery ownership and retirement retain typed failures
  and do not adopt malformed or unrelated artifacts.
- Headless canonical/layout/renderer evidence slices have no SwiftUI, AppKit,
  or WebKit import leakage where prohibited; Release composition continues to
  ignore automation-only arguments.
- The repository scan, fixture cleanup, path hygiene, unsigned local build,
  and no-publishing/signing/notarization boundaries remain enforced by the
  verification scripts.

## Explicitly excluded future work

This audit does not claim a complete Framer/Webflow-class product. It excludes
the unproven native-drag terminal bridge, pointer nesting, production
keyboard/application-menu drag commands, rich text and production typography,
media/components/assets authoring, broad property and responsive editing,
incremental renderer/layout performance, full export/publishing/plugins,
release signing/notarization, owner-approved hardware budgets, and final
distribution accessibility QA.

## Acceptance record

The final local gate completed on 2026-08-09 in the named environment with 288
unit tests and 29 UI tests (317 total), zero failures, and zero skips. The
commit SHA and hosted CI URL are intentionally recorded by Git and GitHub
Actions after this working-tree audit is committed; this report does not infer
future remote state.
