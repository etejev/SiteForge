# ADR-0005: Deterministic launch and project-loading stages

- Status: Accepted
- Date: 2026-07-19
- Requirements: SF-0201-004, SF-0201-006, SF-0201-007, SF-0201-008; SF-0301-002, SF-0301-004, SF-0301-006, SF-0301-007, SF-0301-008; SF-1602-004, SF-1602-006, SF-1602-007, SF-1602-008

## Context

SiteForge needs a polished launch surface and useful progress while preserving the package and recovery safety guarantees from ADR-0001 through ADR-0004. Progress must describe actual work rather than a timer, cancellation must not partially install an incoming document, and UI state must remain separate from the canonical model.

## Decision

A main-actor launch coordinator owns presentation state only. Package reads, canonical validation, fingerprinting, history validation, and recovery-package reads remain in the actor-isolated lifecycle backend. The backend emits a bounded sequence of real stages: read package, validate canonical document, validate compatible history, prepare atomic workspace adoption, and check recovery.

Reading and validation stages are safely cancelable because no incoming canonical state has been installed. The short final preparation/adoption boundary and subsequent recovery check are explicitly non-cancelable. Task cancellation is checked before adoption; failure or cancellation returns to the prior launch/workspace presentation and leaves the current session untouched. Only a completely validated candidate is established as the new session baseline.

Determinate progress represents completed validation milestones, while unbounded file reads and recovery lookup use indeterminate presentation. No timer advances progress. Each state provides a non-path status message, deterministic preferred keyboard focus, a VoiceOver announcement, and a specific next action. Reduce Motion replaces animated indeterminate presentation with a static status symbol; Reduce Transparency and increased contrast use native opaque colors and stronger boundaries. ADR-0006 now supplies the shared launch/workspace material policy originally reserved for SF-FOUNDATION-009.

## Consequences

- Launch presentation can be tested as a deterministic state machine without creating a second document model.
- A failed, incompatible, malformed, or canceled open cannot replace the last valid document.
- Main-actor work is limited to state publication and the final session adoption; package and recovery I/O remain off the main actor.
- State diagnostics contain requirement IDs, operation, state, duration, result, failure category, and a hashed document identifier, but no content or complete path.
- New package stages require an explicit update to this sequence, its cancelability rule, accessibility copy, and transition coverage.
