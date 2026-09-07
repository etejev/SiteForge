# SiteForge completion roadmap

Planning baseline: SF-AUTHORING-021 checkpoint plus the uncommitted
SF-AUTHORING-022 component work. This is a dependency map, not acceptance
evidence. IMPLEMENTATION_STATUS and REQUIREMENT_EVIDENCE remain authoritative
for individual requirements. No entire specification chapter is declared
complete by a bounded authoring milestone.

## Chapter coverage

| Specification chapter | Coverage | Remaining deliverable emphasis |
|---|---|---|
| I Product Foundation | Partial | Product-wide scenario and success acceptance |
| II Experience Architecture | Partial | Functional Settings, search, templates and customization |
| III Document and Project Model | Partial | Cross-project transfer, tokens and broader migration paths |
| IV Canvas and Direct Manipulation | Partial | Broader drag/drop, isolation and transform depth |
| V Layout and Styling | Partial | Constraints, advanced layout, tokens/classes and state styles |
| VI Responsive and Adaptive Design | Partial | Custom breakpoints, fluid values, content and comparisons |
| VII Inspector and Authoring Controls | Partial | Remaining property families and broader accessibility matrices |
| VIII Content, Media, and Assets | Partial | Asset organization, vectors, audiovisual and font workflows |
| IX Components and Reuse | Partial, current work unverified | Local definitions first; exposed properties, variants and libraries later |
| X CMS, Data, and Expressions | Not started as a usable workflow | Collections, bindings, expressions and data safety |
| XI Interactions, Motion, and Runtime Behavior | Partial | Link authoring exists; runtime behaviors and motion remain |
| XII Preview, Rendering, and Export | Partial foundation only | Usable preview and semantic static export; publishing later |
| XIII Collaboration and Versioning | Partial foundation only | Local history exists; snapshots, merge and collaboration remain |
| XIV Plugins and Extensibility | Not started as a usable workflow | Permissioned extension lifecycle and APIs |
| XV Native macOS Platform | Partial; distribution owner-blocked | Complete platform matrix; OD-012/013 distribution decisions |
| XVI Quality Attributes | Partial | Cross-feature performance, browser and security acceptance |
| XVII Testing and Verification | Partial | Extend existing gates to each delivered capability |
| XVIII Delivery and Operations | Partial; release owner-blocked | Release trust, support and operational acceptance |
| XIX Implementation Program | Partial | Execute the dependency-ordered production milestones |
| XX Governance and Appendices | Partial | Maintain traceability and resolve release decisions |

## Dependency-ordered deliverable batches

These are **12 provisional planning batches**, not a fixed milestone count,
time estimate or promise that twelve commits finish the specification. Each
batch can require several bounded implementation slices. Exact requirement
acceptance is inspected before promoting a slice to READY.

| Batch | Requirements / prerequisite | Exit observation |
|---|---|---|
| 1 Local components checkpoint | SF-0901-001–008, SF-0905-003–005; current 022 | Create/link/edit/detach/delete safely, compact native controls, persistence, final local and hosted gates |
| 2 Functional Settings | SF-0206-001–008; existing shell and preference scope decisions | Native controls persist at explicit scope, reset/cancel/accessibility work without contaminating documents |
| 3 Reuse depth | SF-0901–0905 modules, SF-0510 module; batch 1 | A bounded exposed-property/style workflow preserves exact inheritance and history |
| 4 Local preview and semantic static output | SF-1201–1204 modules; current nodes/layout/assets/links and batch 1 | Saved supported pages preview and export with semantic structure, truthful unsupported diagnostics and editor-chrome exclusion |
| 5 Portable static website build | SF-1206–1209, SF-1211 modules; batch 4 | Deterministic local folder build includes resources/routes/metadata, reopens in supported browsers and reports failures without partial success |
| 6 Authoring depth and responsive completeness | SF-0403–0409, SF-0502–0511, SF-0601–0606 modules; stable shared resolver | Remaining transforms/layout/styles/cascade workflows have parity across inspector, canvas and output |
| 7 Content and media breadth | SF-0801–0805 modules; resource store and batch 5 | Supported additional media import, organization, recovery and output work without resource loss |
| 8 Runtime interactions | SF-1101 onward and SF-1205; batches 4–5 | Authored behavior runs accessibly with deterministic preview/output semantics |
| 9 CMS and expressions | Chapter X; batches 5 and 8 | Data-bound pages validate, preview and build with explicit offline/error states |
| 10 Versioning and collaboration | Chapter XIII; canonical/history foundation | Snapshots/merge precede network presence, permissions and conflict-safe collaboration |
| 11 Extensions and ecosystem | Chapter XIV; stable model/runtime interfaces | Permissioned plugins cannot bypass document or security boundaries |
| 12 Distribution and full-spec acceptance | Chapters XV–XX; preceding batches and owner decisions | Platform/browser/security/accessibility matrices, release trust, support and readiness signed off |

## Useful local website creation versus full completion

Batches 1–5 target a usable **bounded local static website** workflow. It must
state which existing node/style/layout features export correctly; no silent
fallback to screenshots or claims of preview parity. It is not full CMS,
collaboration, plugins, cloud publishing or release acceptance. Those require
their later batches and any applicable owner decisions. Public distribution,
account changes and signing remain separately authorized boundaries.

Next candidate after 022: inspect SF-0206 and existing settings architecture
for a native Settings slice. If preference scope conflicts with approved
architecture, record that specific decision and choose a dependency-ready
preview/authoring slice instead. Do not implement a competing preference store.
