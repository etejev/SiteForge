# ADR-0030 — Package v2: pages in bounded members

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Requirements: SF-0301-001, SF-0301-003, SF-0301-004, SF-0301-007, SF-0206-007, SF-1702-001, SF-1702-004, SF-1702-008
- Supersedes: the package v1 size notes in ADR-0001 and ADR-0012 (their limits remain)

## Context

Package v1 stores the canonical document as one `document.json` member capped
at 4 MiB (8 MiB per file, 256 members; ADR-0001, ADR-0012). The editing budget
is 20,000 objects; the stress fixture that fills it is about 7 MiB, so projects
the editor accepts could not be saved (OD-032 interim: refuse truthfully, warn
at 85%). The owner approved package v2 (OD-032, 2026-11-25): bounded members,
every existing bound kept as a security boundary, v1 read by its own decoder,
older builds not opening v2.

## Decision drivers

- Keep every parser, member, member-count and file bound unchanged.
- One strict document decoder: no second canonical document format.
- Older builds keep opening the projects they can represent.
- Deterministic bytes and per-member integrity.

## Considered options

1. One member per page. Rejected: 20,000 pages exceed the 256-member bound.
2. Raise the v1 member limit. Rejected by ADR-0012.
3. **Ordered page members, each a JSON array of whole pages, plus a root.** Chosen.

## Decision

- A document whose canonical encoding fits one member is still written as
  package v1 (unchanged bytes and `minimumPackageReaderVersion` 1).
- A larger one is written as package v2: `document.json` (role `document`) is
  the canonical envelope with the page list replaced by the marker
  `"pages":"app.siteforge.package-v2.pages"`; `pages/0000.json`, `pages/0001.json`, …
  (role `pages`) each hold a JSON array of whole pages in order, packed up to
  the 4 MiB member limit. A page is never split; one page above the limit
  makes the save refused (`projectTooLarge`, nothing written).
- Writing encodes each page with the document encoder settings and verifies
  that the envelope contains exactly that page list once before replacing it.
- Reading v2 joins the members back into the exact canonical bytes and decodes
  them with the unchanged strict decoder. The root must hold the marker once,
  as the document's page list; every member must be one non-empty JSON array of
  objects; page members must be `pages/NNNN.json` without gaps; v1 manifests may
  not carry page members; a v2 manifest must declare minimum reader version 2.
- The manifest's compatibility records the written format, so older builds
  refuse v2 projects with "unsupported package version" instead of misreading them.
- Capacity (SF-0301-007): every save measures the written file against 8 MiB and,
  for v2 or a v1 document near 4 MiB, the largest page against the page limit;
  the status bar warns from 85% of the closer limit.

## Consequences

### Positive

- Projects up to the 8 MiB file limit save and reopen, including the stress
  fixture when its encoding fits; small projects are unchanged.

### Negative or risky

- Older builds cannot open projects saved above 4 MiB.
- A single page cannot exceed about 4 MiB.
- Reading v2 parses each page member once more (JSON validity) before the
  strict decode: bounded by the 8 MiB file limit.

## Verification

Selectors are in `docs/coordination/CODE_FORGE_ACTIVITY.md` (Batch 08). Nothing
has been compiled or run yet.

## Reversal

Stop writing v2 (always write v1 and refuse above 4 MiB again). Keep the v2
reader so projects already saved as v2 still open; a project can then only be
saved again after it shrinks below 4 MiB.
