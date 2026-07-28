# ADR-0016: Editor-only snapping with canonical authored guides

- Status: Accepted
- Requirements: `SF-0404-001` through `SF-0404-008`

## Decision

Snapping is a deterministic resolver layered over the existing transform draft:
it generates candidates from the active rendered page, resolves X and Y
independently, and returns one adjusted transform operation. The transform
registry revalidates that operation, so preview and commit share the existing
canonical geometry properties and one history entry.

Entry tolerance is 6 logical screen points and exit tolerance is 9 points.
Authored guides outrank object edges, which outrank centers. Equal candidates
sort by distance, stable source identity, source feature, then moving feature.
Hidden, clipped, unavailable, selected, and cross-page objects are excluded;
locked objects remain immutable alignment references. Option temporarily
suppresses snapping.

Candidates, winners, measurements, ruler state, and previews are editor-only.
Only explicitly authored horizontal and vertical guides enter canonical schema
version 3. Guide add, move, and remove use stable `GuideID`, page ownership,
strict validation, atomic commands, exact inverses, and deterministic ordering.

## Consequences and reversibility

The bounded resolver is headless and UI-framework-free. AppKit draws rulers,
authored guides, smart guides, and measurements in the editor overlay plane.
A later spatial index may replace the full scan without changing command,
persistence, or UI contracts. Text-baseline, distribution, rotation/skew,
responsive-breakpoint, and export semantics remain excluded.
