# ADR-0011: Scene-owned document context and headless boundaries

- Status: Accepted
- Date: 2026-07-19
- Requirements: SF-1801-001, SF-1801-002, SF-1801-003, SF-1801-004, SF-1801-008, SF-1802-008

## Decision

Each native workspace window owns exactly one `WorkspaceDocumentContext`. That context constructs and retains one canonical `DocumentSession`, one `DocumentLifecycleController`, one shell convenience-state owner, and one launch/load coordinator. Application commands resolve these owners through SwiftUI focused-scene values, so the active window is the only command target. The application root owns only the immutable scene composition factory.

Canonical model and command/persistence source slices remain free of SwiftUI and AppKit. Repository verification type-checks the canonical model independently and the complete command-and-persistence engine as a headless Swift 6 slice, rejects UI-framework imports in those slices, and checks scene ownership on every run. This source-slice boundary is intentionally lighter than separate binary frameworks while Milestone 0 remains one application target; it is enforceable and may be promoted to package/framework targets when authoring growth warrants the build overhead.

All automation-only launch scenarios, fixture scale, appearance overrides, recovery locations, window sizing, and modified-start behavior cross one `DebugTestComposition`. It is compiled to accept arguments only under `DEBUG`; its Release resolution discards every argument. Production code may not read process arguments outside that composition owner.

## Consequences

- Opening a second window creates independent canonical identity, history, lifecycle epoch, durable location, recovery state, selection, tool, focus, and zoom state.
- New/Open/Save/Revert/Restore/Close and Undo/Redo commands operate on the focused scene and cannot accidentally mutate another window's session.
- Core transactional and persistence code can be compiled and tested headlessly without UI frameworks. Repository checks prevent dependency-direction regression before authoring modules are added.
- Debug UI journeys retain deterministic fixture injection without teaching Release builds test behavior.
- The current command/history types form one mutually type-checked headless engine slice. Splitting them into separate binary modules remains reversible and is not required to establish dependency direction today.

## Alternatives considered

- Application-global observable document state was rejected because every window would share canonical content, history, file identity, and recovery state.
- Passing document owners through singleton services was rejected because it would obscure lifetime and focused-window routing.
- Shipping automation argument parsing in Release was rejected because local test controls could alter production behavior.
- Immediately creating several framework targets was deferred because enforceable source slices provide the needed boundary without premature packaging churn.
