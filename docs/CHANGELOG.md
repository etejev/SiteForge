# SiteForge Development Changelog

This file records user-visible behavior during development. It is not a substitute for Git history or the normative specification.

## Unreleased

### Fixed

- Centered the fresh-document pasteboard and empty-canvas state in the usable
  canvas viewport without changing authored coordinates or blocking empty
  canvas input. Committed plain text and the native inline editor now share
  one viewport rect, font/inset, and baseline calculation, keeping glyphs
  inside their selected bounds across zoom and backing-scale changes.
- Restored the 1100-point constrained Debug/UI-test window width used by real trailing-edge pointer journeys. Explicit placements now fit titled height only, with independent left/right/top/bottom safe edges; the text status pointer journey uses right/bottom placement. XCTest result bundles and logs now use a deterministic project/Actions/local root and are retained together on CI failure.

### Added

- Bounded native Design Inspector solid-fill and opacity editing for Frame,
  Section, Stack, and Grid. Canonical normalized RGBA channels and opacity
  persist through the existing transaction/history/package boundary, while
  native `NSColorWell`/Colors-panel, hexadecimal, percentage-field, and
  `NSStepper` drafts remain editor-only until one typed transaction commits.
  The controls now provide truthful accessible state and participate in native
  focus, cancellation, undo/redo, Save/Close/Open, and mixed/inapplicable
  selection flows. Gradients, layered fills, images, borders, effects, tokens,
  and typography remain unavailable.

- Native Layout Inspector X, Y, Width, and Height fields for applicable Frame,
  Text, Section, Stack, and Grid selections. Locale-aware drafts remain
  noncanonical until Return or focus loss commits one atomic geometry
  transaction; Escape restores the committed display. Mixed and inapplicable
  selections are explicit, and the same stable geometry continues through
  undo/redo, canvas rendering, selection, Layers, accessibility, and packages.
- Section, Stack, and Grid are now real structural Elements and Insert-menu actions. They create stable canonical nodes through the existing atomic insertion/history path, render with calm structural surfaces, and synchronize their resolved geometry across Layers, selection, Inspector, hit testing, accessibility, undo/redo, and save/reopen.
- Canonical schema v4 records explicit v1 structural defaults: Section is 960×320 with 48-point padding; Stack is vertical/start with 24-point padding and gap; Grid uses two equal row-major columns with 24-point padding and gap. Schema-v3 packages remain readable and re-save deterministically as v4.

- Inspector navigation now follows Design, Layout, Content, Interactions, and Accessibility. Content and Interactions provide native accessible unavailable explanations rather than simulated editable controls; they cannot create history or package mutations. Newly inserted Frames now have a deterministic neutral surface, subtle border, and name; selected dimensions/parent context and blue outlines remain editor-only. First launch uses a normal maximized visible-frame window rather than native macOS full screen and respects later user move/resize.
- Blank projects now present a truthful empty canvas with visible named Frame and Text starting actions instead of fabricated root/sample/debug objects. The real actions create one canonical object and deterministically adopt its shared identity/frame into the live renderer, Layers, selection, accessibility, undo/redo, and persistence boundaries. Canvas authored labels and plain text use one top-left/Y-down coordinate convention, with a single tile-boundary text conversion to keep them upright.
- Truthful product navigation foundation: Pages, Layers, Elements, Assets, and Components now have native accessible destinations. Elements provides a stable categorized catalogue; only the existing Frame and plain-Text insertion paths are enabled, while all later element types and Asset/Component work state exactly why they are unavailable without changing a project.

- Full-window product UI foundation: SiteForge configures welcome, loading, recovery/failure, and editor as one native macOS workspace window. First launch uses the usable visible display frame and subsequent valid normal-window restoration; invalid restoration safely falls back. The visual contract documents the native menu, unified chrome, future navigation/inspector architecture, materials, spacing, accessibility states, and clear boundaries for unfinished capabilities.

- Bounded local Layers drag-and-drop authoring: transactional sibling reorder and frame nesting through stable identities, deterministic insertion previews, exact undo/redo, and noncanonical drag-session state. The source-level pointer capability supports bounded same-page “before row” placement, including compatible cross-parent placement; nesting is available through the shared contextual, named-accessibility, and automation registry paths. An explicitly declared internal drag type keeps generic text and Finder payloads outside the local move path. End-to-end native drag terminal cleanup remains a documented later boundary.
- Reproducible 100-/10,000-node drag-preparation evidence plus a retained running-app Layers contextual reorder/undo/redo screenshot; drag session, payload, preview, and indicators remain excluded from packages, history, autosave/recovery, and preview/export snapshots.

- Final audit-correction closure: strict current-schema helper source is included in the Xcode target and every headless verification/evidence compile; schema-v1/v2 historical payloads use strict isolated adapters and immutable package goldens; lifecycle Save freezes its original lexical destination identity before awaiting coordination; recovery-candidate and current-recovery ownership are distinct; stale pre-adoption recovery cleanup is attempt-gated; and committed plain text is now proven to change only its clipped native canvas-tile pixels.
- A final audit report, explicit residual-risk ledger, and OD-014 for trusted app-owned staging/quarantine/recovery-tombstone retention and reclamation. The macOS same-UID final-rename/unlink race is no longer overstated as universally prevented.

- Native inline plain-text editing on the canvas with stable session/document/page/revision/renderer/node identity, genuine AppKit caret and selection behavior, multiline insertion/deletion/replacement, copy/cut/paste, marked-text composition, and shared pointer, keyboard, menu, contextual, accessibility, and automation activation.
- One atomic canonical `content.text` transaction and exact inverse per completed edit, with deterministic undo/redo, package/history round trips, autosave/recovery, selection/Layers/layout/renderer/hit-test adoption, bounded dirty regions, and exact Escape/stale/cancellation neutrality.
- Reproducible 100-/10,000-object text-command preparation evidence plus retained running-app draft, commit, and cancellation screenshots; draft text, selection ranges, composition, clipboard state, and editor overlays remain excluded from canonical persistence, history, preview, and export-facing snapshots.
- Deterministic edge, center, and authored-guide snapping layered over the existing move/resize preview boundary, with 6/9-point hysteresis, stable priority/tie rules, independent axes, zoom-aware tolerances, Option suppression, typed stale/cancellation neutrality, and no second canonical geometry source.
- Native world-aligned horizontal/vertical rulers, smart-guide and bounded distance overlays, plus stable accessibility labels/identifiers and editor-only overlay isolation from authored rendering, packages, history, preview, and export-facing snapshots.
- Stable page-owned authored guides with pointer and keyboard/accessibility creation, numeric movement, deletion, deterministic ordering, atomic commands/inverses, undo/redo, package/history round trips, and schema-v2 migration.
- Reproducible optimized 100-/10,000-object snapping measurements with raw samples, memory, environment, methodology, and explicit full-scan/frame-pacing limitations.
- Deterministic move and eight-handle resize sessions keyed by stable session, document, page, revision, renderer-generation, and selected-node identities, with exact axis constraints, typed validation/failure outcomes, editor-only previews, and one atomic transaction/inverse per completion.
- Native accessible canvas resize handles plus shared pointer, keyboard, menu, contextual, inspector numeric, accessibility, and automation transform routing; compatible multiple selections move atomically while incompatible or multiple-resize requests are explicitly rejected.
- Transform integration across undo/redo, deterministic package/history round trips, selection, Layers, layout, renderer, hit testing, bounded old/new dirty regions, autosave/recovery, and redacted diagnostics, with retained 100-/10,000-object timing/memory and running-app visual evidence.
- Window-native mixed SwiftUI/AppKit Tab routing at the viewport-preset boundaries, scoped to each workspace window with genuine first-responder transfer, safe pass-through for editing and transient presentation contexts, deterministic teardown, and redacted responder diagnostics for hosted UI failures.
- AppKit-deterministic viewport-preset focus and selection: the native popup preserves the existing layout and accessibility identity while synchronizing real first-responder state with the scene-owned traversal model, rejecting stale or wrong-window focus requests, and supporting pointer plus Up/Down keyboard preset selection.
- Explicit `quick`, `changed`, `half`, and `full` local XCTest levels, with conservative changed-subsystem selection, automatic full-suite fallback for uncertain impact, and selector self-tests inside repository verification. Bare `./sf test`, `./sf verify`, and CI remain full regression gates.
- Transactional frame and bounded plain-text insertion using stable typed node identities, exact parent/page/order ownership, deterministic `.defaulted` geometry/content, one atomic command/inverse, and exact undo/redo restoration.
- One scene-owned editor-only insertion session with inactive, armed, previewing, committing, cancelled, and failed states; unified toolbar, pointer, keyboard, menu, contextual, accessibility, and automation command routing; cancellation and failure preserve canonical state and prior selection.
- Post-commit selection plus Layers, inspector/status, accessibility, layout, renderer, hit-test, package, persisted-history, autosave, and recovery integration, while previews remain excluded from canonical persistence, history, preview/export snapshots, and authored render content.
- Reproducible 100-/10,000-object insertion, layout, and renderer capacity evidence with raw samples, environment, memory, methodology, and explicit performance limitations, plus a running-app insertion/cancellation/undo/redo journey.

- A deterministic scene/window-owned selection model with stable ordered node identities, primary and anchor selection, page/container scope, typed provenance, exact renderer-generation validation, and state-neutral cancellation/stale rejection.
- Unified replacement, Shift-add, Command-toggle, Escape, next/previous, pointer, menu, contextual, Layers navigator, and accessibility selection paths with synchronized inspector and status summaries.
- Editor-only primary/secondary and locked inspection outlines with bounded old/new dirty-region invalidation, compositor-aligned pan/zoom/resize/Retina updates, and structural exclusion from authored content, persistence, history, preview, and export boundaries.
- Retained running-app empty/single/multiple selection screenshots and reproducible optimized 100-/10,000-object command/overlay timing, memory, methodology, and limitation evidence.

- A production AppKit/Core Animation canvas renderer foundation with immutable identity-tagged scenes, bounded content tiles, structurally separate editor overlays, deterministic paint/clipping/visibility rules, reverse-order hit testing, dirty-region invalidation, and compositor-only pan/zoom.
- Stable virtual canvas accessibility identities and focus repair, bounded deterministic cache policy, cancellation/stale-result protection, overlay-free preview snapshots, privacy-preserving renderer signposts and diagnostics, and retained 100-/10,000-object timing/memory/display-link evidence.

- A production, Foundation-only deterministic layout-engine foundation with stable typed node identity, versioned immutable snapshots, revision/generation/viewport-scoped results, exact frame provenance, bounded graph validation, cooperative cancellation, stale-result rejection, and privacy-preserving diagnostics.
- Explicit fixed, intrinsic, and fill sizing; min/max constraints; padding; gap; start/center/end/stretch alignment; horizontal/vertical stacks; nesting; visible/clip overflow; and responsive-width semantics, with percentage/automatic sizing, baseline alignment, and scroll overflow rejected instead of approximated.
- Reproducible optimized 100-/10,000-node layout and isolated WebKit geometry-oracle evidence with raw timings, memory samples, exact declared-width parity, environment, and limitations.

- A production canvas viewport foundation with compile-time-separated world, viewport, and device geometry; deterministic precision and error policies; Retina-aware reversible transforms; 25–800% cursor-anchored zoom; bounded pan; resize, reset, fit-document, and fit-width behavior.
- A native AppKit viewport input and accessibility surface embedded in the existing material-aware SwiftUI shell, with keyboard/menu commands, focus traversal, semantic values/actions, announcements, and scene-owned noncanonical state.
- Actor-isolated immutable viewport-scene preparation tagged by document, revision, scene, and viewport generation, including cancellation/stale-result rejection and deterministic 100-/10,000-object coverage.

- A reproducible isolated authoring-engine runway with typed coordinate, hit-test, deterministic layout, HTML/CSS parity, native renderer, accessibility, material, and production 500-asset probes at 100- and 10,000-object scale, retaining raw samples, environment, memory fields, commands, and limitations.
- ADR-0013 selecting a SiteForge-owned deterministic canonical layout engine with an isolated WebKit standards oracle, and ADR-0014 selecting SwiftUI chrome with an AppKit viewport, bounded Core Animation composition, and an optional future Metal backend.

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
- Centralized native macOS material policy for navigator, inspector, unified toolbar/title bar, viewport controls, status, recovery, and launch surfaces, rendered with pass-through `NSVisualEffectView` instances rather than simulated glass.
- Retained visual-regression fixtures for light, dark, Reduce Transparency, Increased Contrast, inactive-window policy, default/minimum sizing, and 10,000-page scrolling.
- Identity-bound package I/O that captures validated bytes, bounded SHA-256 fingerprint, device/inode identity, and security metadata from one no-follow descriptor snapshot, with deterministic barrier-controlled race coverage.
- App-owned recovery validation and typed deletion failures that preserve mismatched artifacts and retain a recovery candidate when deletion must be retried.
- Immutable package-v1/schema-v1 compatibility fixtures for empty and rootless legacy projects, with retained provenance and decoded-package checksums.
- Centralized macOS file-access boundary with native panel authorization, real app-scoped security bookmarks, stale-bookmark repair, coordinated package I/O, relocation support, external file presentation, typed denial/recovery failures, and privacy-preserving diagnostics.
- Unsigned Release-candidate App Sandbox, user-selected read/write, and app-scoped bookmark declarations plus a registered `.siteforge` project-package document type.
- Cooperative cancellation checkpoints inside package container parsing, canonical graph validation, and persisted-history validation, preserving cancellation as distinct from corruption or isolation.
- A canonical decision namespace, machine-checked bounded requirement-evidence index, and retained visual/performance methodology records with explicit authoring and 500-asset limitations.
- Real production-loader UI regression journeys for valid and malformed packages, Retry, recovery discovery, keyboard Restore, and Discard, plus an injectable native accessibility-announcement boundary.
- Scene-owned workspace document contexts with independent canonical sessions, lifecycle/recovery state, history, and convenience state for every native window.
- Verification-enforced headless canonical-model and command/persistence source slices, plus one Debug-only composition seam for automation fixtures and appearance overrides.
- Deterministic bidirectional workspace focus traversal, Preview focus restoration, toolbar shortcut coverage, and PageID-derived navigator-row identifiers with role exposed separately.
- Versioned deterministic resource-index v1 and a bounded content-addressed project resource store with streamed integrity validation, cooperative cancellation, legacy compatibility, and a representative 500-asset fixture without relaxing package parser limits.
- A redacting repository credential scanner with runtime-assembled synthetic positives, a tracked negative fixture, broader token/key/environment-file coverage, binary/document exclusions, private temporary-fixture cleanup, and local/CI verification enforcement.
- One shared repository-local XCTest fixture allocator with throwing cleanup and verification-level residue removal, plus an enforced single native project Open-panel owner.

### Changed

- Canonical document serialization is schema v3: explicitly authored guides are strict, versioned canonical members; schema-v2 documents migrate deterministically to no authored guides, while snap candidates, measurements, ruler interaction, suppression, and previews remain noncanonical.
- The geometry representation carried forward into canonical schema v3 is unchanged: move/resize commits author the existing stable `layout.x`, `layout.y`, `layout.width`, and `layout.height` properties, while transform sessions, pointer drafts, handles, and previews remain noncanonical and excluded from packages, history, preview, and export-facing snapshots.
- Current canonical schema v3 preserves the existing ordered property/provenance representation for frame geometry, initial style, bounded plain text, and authored guides. Schema-v2 packages add only an empty guide collection; supported schema-v1 packages continue through the strict migration adapter.
- Canonical graph validation now uses precomputed child membership and iterative traversal, avoiding quadratic membership checks and recursive-stack growth on bounded large documents.
- Renderer scene revision/generation changes can retain bounded dirty-region planning when authored object identity and surface identity remain compatible, instead of forcing an unrelated full authored-scene raster.

- Local project discovery ignores Xcode workspaces nested inside `.xcodeproj` bundles, and build products use a portable temporary Derived Data location by default.
- Debug builds use credential-free local ad-hoc signing required to run hosted XCTest processes; Release distribution signing remains disabled.
- The workspace uses native restorable window, toolbar, menu, split-view, keyboard, and accessibility behaviors, with an enforced 1100×700 minimum content size.
- Toolbar and Edit-menu Undo/Redo validation now reflects the real transactional document history while convenience UI state remains separate from the canonical model.
- Canonical document primitives are sendable across the package store's background actor boundary while remaining UI-independent.
- Validated open and recovery operations install history only after off-main revision, identity, ordering, and inverse validation; rejected history establishes a clean non-crossable baseline.
- Current canonical document serialization is schema v3. Schema-v2 packages deterministically gain empty authored guides, while schema-v1 packages remain readable and deterministically gain minimum page/root identities when legacy documents are empty or rootless.
- New-project creation now establishes the complete approved blank structure as one clean history baseline; it does not record default seeding as user edits.
- File-menu New and Open now enter the same launch coordinator as the initial experience, while package I/O and validation remain in the actor-isolated lifecycle backend.
- Opening a project publishes actual loading stages and checks cancellation before the single validated adoption boundary; the prior canonical document remains active after cancellation or failure.
- Requirement status now distinguishes verified foundation slices from full generated-site, canvas-renderer, accessibility-release, and performance acceptance; policy and synthetic-page tests are labeled as smoke evidence rather than renderer benchmarks.
- Chrome appearance now resolves native material, opaque accessibility fallback, separator strength, and active-window emphasis from one shared policy while leaving canonical document state and canvas hit testing unchanged.
- The bounded canvas placeholder now adapts to the available viewport so its empty-state copy remains readable at the supported minimum window size.
- Existing package replacement requires the exact previously validated digest, byte count, device, and inode at the descriptor-bound validation seams; same-directory staging commits with exclusive create or an identity-checked atomic swap and preserves owner, group, mode, extended ACL, and approved extended attributes. It intentionally retains ambiguous displaced artifacts rather than reversing/reopening/unlinking a raced name.
- Lifecycle reads, saves, autosaves, recovery writes, and document transitions carry a typed epoch, operation, document/project, revision, destination, and intent identity; a typed pre-adoption transition attempt also gates authorization/recovery retirement before a document boundary can invalidate prior work.
- Manual Save now deterministically cancels or drains pending autosave work. An edit made during Save leaves the captured revision durable while the newer active revision remains modified and recoverable.
- Current canonical schema v3 requires every document, page, node, and guide field and never applies legacy defaults; schema-v2 and schema-v1 compatibility use separate explicit migration adapters.
- Project open, revert, Save, and Save As now pass through one balanced security-scope and file-coordination owner; bookmarks remain machine-local app state rather than portable package content.
- File and Edit commands now resolve the focused window's document context instead of application-global state; Release builds ignore all automation-only process arguments.
- Accessibility evidence now distinguishes semantic automation from OS-level manual inspection and records the real environment and limitations without claiming unperformed VoiceOver speech or accessibility-setting exercise.

### Fixed

- Debug UI-test workspaces now derive their intended frame from the requested content size and the bound window's native chrome, expose requested left/right and top/bottom safe edges, and fit every explicitly placed test window vertically before AppKit can apply a smaller origin-dependent hosted-screen constraint. Generic inline-text coverage uses Command-Return, while dedicated journeys retain real pointer clicks for status Commit/Cancel and toolbar Preview/Undo/Redo; the production 1100×700 content minimum and Release/non-test sizing and placement are unchanged.
- Generic frame/text insertion UI coverage now exercises Undo and Redo through the production keyboard command path, while a dedicated right-aligned journey verifies both toolbar history buttons remain pointer-operable on displays narrower than the unchanged 1100-point production window.
- Workspace Tab traversal now gives the viewport-preset selector real accessibility focus after the Not Found page, crosses the native canvas boundary deterministically in both directions, and retains redacted focus diagnostics with expected/current identifiers and a screenshot.
- Workspace UI-test readiness no longer depends on the far-right Preview toolbar control being pointer-visible. Shared launch helpers now wait for the accessible workspace shell, capture redacted hierarchy/screenshot diagnostics on failure, and use Debug-only deterministic edge placement solely for tests that need offscreen pointer targets; the 1100×700 production minimum is unchanged.
- GitHub Actions failure artifacts now use the official Node 24-based upload-artifact major.

- macOS UI verification now waits for explicit accessible launch/workspace readiness, keyboard-focus settlement, and toolbar hittability; reduced-motion loading keeps a stable static progress element, UI-test windows are deterministically visible, and launched applications are cleaned up after each journey.
- GitHub Actions now uses checkout v5, records its macOS/Xcode environment, and retains the redacted verification log and XCTest result bundle on failure while keeping `./sf verify` as the sole authoritative pipeline.
- Direct or transactional removal can no longer leave a project with an invalid empty page list, and duplicate published routes are rejected before commit.
- New, Open, Revert, recovery Restore, and window Close now share one native Save/Discard/Cancel decision boundary; cancellation and failed saves preserve the exact active document, history, identity, location, fingerprint, and lifecycle presentation.
- Modified untitled projects now autosave to app-owned, project-identity-keyed recovery storage and can be discovered, restored, saved durably, or discarded after relaunch without writing beside user project files.
- Opening no longer rereads a path to fingerprint validated content, and the deterministic concurrent-replacement, delete/recreate, same-inode modification, hard-link, source/destination/ancestor symlink, sparse-input, recovery-collision, and retirement-failure cases preserve the last committed document and external bytes at their exercised seams. The remaining macOS final-syscall limitation is documented in ADR-0007/OD-014.
- Stale lifecycle success, failure, and cancellation can no longer reattach canonical state, metadata, history, recovery state, failure state, or UI phase after New, Open, Revert, Restore, or Close; autosave burst coalescing and revision order are now verified without wall-clock sleeps.
- Terminal or non-incrementable document revisions now fail with a typed actionable error while preserving the exact committed document and command history instead of risking integer overflow.
- External project change or deletion now enters explicit conflict state without replacing the active canonical project; relocation updates the durable URL and persistent access while preserving document content.

### Known limitations

- Current history schema v2 is intentionally bounded to the current command kernel; schema v1 has an explicit compatibility adapter. Future command types, checkpoints, coalescing metadata, immutable historical golden inputs, and migrations require explicit schema support.
- Foundation exact-key checks run after Foundation JSON parsing, which collapses duplicate keys; a duplicate-key-preserving parser remains a future hardening task.
- Trusted app-owned staging/quarantine/recovery-tombstone reclamation requires owner resolution of OD-014. No automatic cleanup claims protection against a hostile same-UID final-syscall race.
- The canvas editing interface and Preview behavior remain bounded placeholders for later work items.
- Local alpha packaging is unsigned and not notarized.
- Final sandbox/distribution verification remains pending owner-approved publisher and trust configuration; the local Release candidate is deliberately unsigned.
