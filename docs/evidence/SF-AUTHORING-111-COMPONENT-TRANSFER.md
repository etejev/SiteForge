# SF-AUTHORING-111 — Transactional cross-project component transfer

Verification checkpoint (2026-10-08): repository/build gates and the complete
non-UI target ran; corrected non-UI coverage is green. The actual-app journey
remains unexecuted because XCTest timed out during runner initialization.

## Scope

This source-only slice advances `SF-0308-001`–`008` and bounded portions of
`SF-0901-001`–`008`, `SF-0902-001`–`008`, and `SF-0905-001`–`008`. The
normative modules remain **Partial** because runtime execution, performance,
broad assistive-technology coverage, future nested components, slots,
variants, media/enum/action properties, remote libraries, and release
acceptance remain deferred.

## Delivered source contract

- Clipboard envelope v2 contains the complete supported component-definition
  closure plus referenced image resources, color tokens, reusable styles, and
  exposed text/visibility bindings. Strict decoding rejects unknown fields,
  duplicate identities, dangling references, cycles, excessive depth/count,
  malformed definitions, and unsupported future component constructs before
  destination mutation.
- Cross-project preparation compares definitions by deterministic structural
  content rather than display name or source identity. Equivalent destination
  definitions are reused; non-equivalent definitions receive remapped stable
  page/node/property/binding identities and deterministic `Copy N` names when
  needed. Every inserted instance is rewritten to the resulting destination
  definition and exposed-property identity.
- Reusable style dependencies are deduplicated by exact semantic content or
  imported with remapped identity and deterministic naming. Existing image
  content-hash and color-token reconciliation remains the single dependency
  path.
- Definition insertion, dependency-property installation, and instance paste
  compile into one existing command-kernel batch. The exact inverse removes
  the entire imported graph and restores the prior document; redo reapplies
  the same prepared identities. Prepared transfers carry document/revision
  identity so stale confirmation is mutation-neutral.
- A native modal preflight names imported, reused, and renamed definitions
  before cross-project mutation. Cancel is neutral; Import and Paste uses the
  prepared atomic command. The summary and actions have stable accessibility
  identity and native keyboard semantics.

The current canonical component model forbids nested component nodes inside a
definition. The transfer validator still detects cyclic/dangling dependency
graphs first, then rejects otherwise well-formed future nested constructs
truthfully rather than partially importing them.

## Source evidence

- `SiteForge/ClipboardTransfer.swift`: envelope v2, dependency closure,
  structural equivalence, identity remapping, and atomic import preparation.
- `SiteForge/WorkspaceShellModel.swift`: scene-owned preflight lifecycle,
  stale document/revision rejection, and renderer/selection adoption.
- `SiteForge/WorkspaceShellView.swift`:
  `ClipboardComponentTransferPreflightView`.
- `Tests/SiteForgeTests/ClipboardTransferTests.swift`: model/security/history/
  persistence source coverage.
- `Tests/SiteForgeUITests/SiteForgeLaunchTests.swift`:
  `testCrossProjectComponentPastePreflightImportUndoRedoAccessibilityJourney`.

## Verification status

The affected production target passed one universal arm64/x86_64 macOS build
after correcting the preflight sheet to use the established pane-padding
token. Swift parser checks, JSON/traceability checks, security/path scans, and
`git diff --check` are the only additional checks authorized for this slice.
The new XCTest source and `./sf verify` were not run and are not claimed.

## Deferred scope

Nested component definitions, slots, variants, media/enum/action properties,
arbitrary per-child style overrides, page/site transfer, foreign clipboard
formats, remote or marketplace libraries, collaboration/connected clipboards,
progressive large-transfer UI, broad accessibility/performance matrices,
preview/export/browser behavior, and release acceptance remain deferred.
