# SiteForge Development Changelog

This file records user-visible behavior during development. It is not a substitute for Git history or the normative specification.

## Unreleased

### Added

- Repository control layer with local build, test, verification, watch, packaging, and bounded Codex work-loop commands.
- Native Swift 6 macOS application project with a shared `SiteForge` scheme, reversible development bundle identifier, and unit and UI test targets.
- Foundation launch screen and smoke coverage for product metadata and application-window startup.
- Native workspace shell with a document window and title bar; Select, Frame, Text, Image, Component, undo, redo, and Preview commands; Pages/Layers navigator; bounded canvas viewport; four-tab inspector; and status bar.
- Stable accessibility identifiers and automated coverage for shell regions, command states, practical minimum sizing, Preview presentation, and keyboard focus order.
- Canonical document, page, node, property, and parent-child primitives with stable typed UUID identities, graph validation, explicit authored/defaulted property state, and deterministic schema-v1 serialization.
- Central typed command registry with validation reasons, atomic draft transactions, exact inverses, functional undo/redo stacks, redo-branch invalidation, cancellation rollback, and privacy-preserving command diagnostics.
- Deterministic versioned SiteForge project packages with stable project identity, canonical document payloads, RFC 3339 creation/modification metadata, declared resources and optional members, compatibility minima, and SHA-256 integrity metadata.
- Actor-isolated package persistence with synchronized staging and atomic replacement, typed actionable failures, privacy-preserving diagnostics, opaque optional-member preservation, and adversarial regression coverage using repository-local fixtures.
- Native New, Open, Save, Save As, Revert, and guarded Close flows using typed SiteForge project panels and the verified atomic package store.
- Coalesced background recovery-package autosaves, durable-file conflict detection, stale-save suppression, newer-only recovery candidates, and explicit Restore, Discard, and Inspect Details choices.
- Document title/status presentation for modified, saving, autosaving, failed, conflicted, and recovered states, with keyboard commands, VoiceOver labels, progress, actionable errors, and privacy-preserving lifecycle diagnostics.
- Deterministic schema-v1 persisted transaction history with stable transaction identity, revision ordering, typed commands, supported inverses, affected stable identifiers, timestamps, and registry-derived non-content labels.
- Compatible Undo and Redo restoration across atomic save, reopen, autosave, and recovery, with explicit durable recovery boundaries and correct redo-branch invalidation.
- Independent isolation for legacy, missing, corrupt, oversized, unsupported, reordered, duplicate, mismatched, or invalid history while preserving the validated canonical document, plus 128-entry and 512-KiB retention limits.
- Approved blank-project defaults: Home at `/`, followed by Not Found at `/404`, each containing only one minimum frame root and no sample content.
- Typed page routes, home/not-found roles, blank/template provenance, and template identity, with non-empty-project and unique-route validation.
- Ordered Pages navigator rows with stable accessibility identifiers, route-aware VoiceOver labels, selected state, and Up/Down Arrow navigation.
- Native SiteForge launch experience with direct New Blank Project and Open Project actions, consistent minimum-window behavior, and full keyboard/accessibility semantics.
- Real-operation loading presentation for package reads, canonical validation, history validation, atomic workspace adoption, and recovery checks, including determinate and indeterminate progress without decorative timing.
- Explicit cancelable and non-cancelable stages, actionable malformed/incompatible/access failures, Retry and Choose Another Project actions, and recovery Restore, Discard, and Inspect Recovery choices.
- Privacy-preserving launch diagnostics, VoiceOver state announcements, deterministic focus targets, a static Reduce Motion progress alternative, and native opaque fallbacks for Reduce Transparency and increased contrast.

### Changed

- Local project discovery ignores Xcode workspaces nested inside `.xcodeproj` bundles, and build products use a portable temporary Derived Data location by default.
- Debug builds use credential-free local ad-hoc signing required to run hosted XCTest processes; Release distribution signing remains disabled.
- The workspace uses native restorable window, toolbar, menu, split-view, keyboard, and accessibility behaviors, with an enforced 1100×700 minimum content size.
- Toolbar and Edit-menu Undo/Redo validation now reflects the real transactional document history while convenience UI state remains separate from the canonical model.
- Canonical document primitives are sendable across the package store's background actor boundary while remaining UI-independent.
- Validated open and recovery operations install history only after off-main revision, identity, ordering, and inverse validation; rejected history establishes a clean non-crossable baseline.
- Canonical document serialization is schema v2. Schema-v1 packages remain readable and deterministically gain minimum page/root identities when legacy documents are empty or rootless.
- New-project creation now establishes the complete approved blank structure as one clean history baseline; it does not record default seeding as user edits.
- File-menu New and Open now enter the same launch coordinator as the initial experience, while package I/O and validation remain in the actor-isolated lifecycle backend.
- Opening a project publishes actual loading stages and checks cancellation before the single validated adoption boundary; the prior canonical document remains active after cancellation or failure.

### Fixed

- Direct or transactional removal can no longer leave a project with an invalid empty page list, and duplicate published routes are rejected before commit.

### Known limitations

- History schema v1 is intentionally bounded to the current command kernel; future command types, checkpoints, coalescing metadata, and migrations require explicit schema support.
- The canvas editing interface and Preview behavior remain bounded placeholders for later work items.
- Workspace translucent/glass materials remain intentionally deferred to `SF-FOUNDATION-009`; the launch experience uses native opaque surfaces and accessibility fallbacks in this slice.
- Local alpha packaging is unsigned and not notarized.
