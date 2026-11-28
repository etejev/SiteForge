# ADR-0072 — Template pages and bindings (one static page per item)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-035 (approved by the owner 2026-11-26 1:30 PM EST)
- Builds on: ADR-0070 (expression language), ADR-0071 (collections)
- Requirements: SF-1003-001 … SF-1003-008 (detail pages in batch D03, list pages in batch D04)

## Context

OD-035: template pages generate one static page per collection item at
export. Collections (ADR-0071) and expressions (ADR-0070) exist; nothing used
them in output yet.

## Decision

- Storage: `ContentCollection.template: CollectionTemplate?` (key `template`,
  written only when present; an explicit null is refused). A template has
  `pageID`, an optional `title` expression and `bindings` (at most 256,
  sorted by node id then target, one per node and target).
  `CollectionBinding` = `nodeID`, `target` (`text` | `image`) and exactly one
  of `expression` (text) or `fieldID` (image). Still document schema 27,
  history schema 4; editing goes through the existing `setCollections`
  command, so undo, redo, snapshots, comparison and new-from-template already
  carry it.
- Omitted / defaulted / authored (SF-1003-001): an unbound layer keeps its
  designed content on every item page; an expression can supply its own
  fallback with `??`; otherwise the item's value is shown.
- Output (`CollectionTemplates`, used by `MultiPageStaticBuildPlanner.plan`):
  an active template (page exists and is a regular page) is not written
  itself. Each published item becomes `/<collection address>/<item address>`
  (`<collection>/<item>.html`) with the template's layers and identities, the
  page name set from `title` (or the item's first text value, or its address),
  bound Text layers set to the expression's text (HTML-escaped by the existing
  emitter) and bound Image layers set to the item's picture when it has one.
  Drafts are never written. Links to the template page open the first
  published item. The template is left out of generated navigation. Shared
  styles are taken from the first item page only. The sitemap lists item pages.
  Browser Preview opens the first item page when the current page is a
  template.
- Unusable parts keep the author's intent (SF-1003-004): a removed template
  page, a removed layer, a removed or retyped image field, or an expression
  that no longer type-checks never blocks saving or deletes data. They are
  listed by `CollectionTemplates.findings` (`missingPage`, `unsupportedPage`,
  `missingNode`, `unsupportedNode`, `expression`, `imageField`,
  `routeCollision`, `noPublishedItems`), and the affected layer keeps its
  design. An item address used by another page is reported and the build
  refuses it with the existing collision error.
- Rules that block Apply (`CollectionIssue`): `template` (shape, limit,
  duplicates, order) and `duplicateTemplatePage` (one page serves at most one
  collection).
- Editor: Collections gains a **Template** tab: page picker (regular pages),
  page title expression, one expression field per Text layer and one image
  field picker per Image layer, in canvas order. Each expression shows the
  result for the first published item, or the error. Text that is not a valid
  expression yet is shown as typed; Apply keeps the last valid expression.
  Choosing another page clears bindings and keeps the title.
- Diagnostics: `CollectionTemplates.diagnostic` (SF-1003-001, operation,
  sorted collection ids, published item count, duration, first finding kind;
  no names, values or expressions).
- List pages (batch D04, SF-1003-002/003/006): `ContentCollection.lists:
  [CollectionList]` (key `lists`, written only when non-empty; an empty array
  or null is refused). A list has `pageID`, `repeatedNodeID` (its identity),
  optional `filter` (a True or False expression), optional `sortFieldID`,
  `sortDirection` (`ascending` | `descending`), optional `limit`
  (1…10,000), `pageSize` (1…100, default 12), optional `previousNodeID` /
  `nextNodeID` and `bindings` (same rules as template bindings). At most 16
  lists per collection; one list per repeated layer across all collections.
  `CollectionBindingTarget` gains `link` (no expression, no field): a Link or
  Button layer that opens the item's own page. Still document schema 27,
  history schema 4, the same `setCollections` command.
- List resolution (SF-1003-003, `CollectionLists.resolve`): published items
  → filter (true keeps; false or missing leaves out; a filter that does not
  type-check or is not True or False is reported and every published item is
  kept) → order by a text, rich text, number or date field (text ignores case
  and accents and compares digits as numbers, `en_US_POSIX`; items without a
  value last in either direction; ties keep the Items order) → limit → pages
  of `pageSize`. `CollectionListResolution.explanation` states each rule with
  counts and field names only.
- List output (`CollectionLists`): a usable list (page is Home or a regular
  page and not an item template; repeated layer exists and sits directly in
  a Stack or Grid; it does not overlap another list's layer) writes its page
  once per list page: page 1 at the page's own address, then
  `<address>/page/N` (`/page/N` for Home). On each page the repeated layer is
  copied once per item, in order; copy `slot` of a layer has the identity
  `copyID(layer, slot)` (slot 0 keeps the original), the same on every page,
  so styles are generated once from page 1 (`stylePages`). Interactions and
  section links inside a copy follow the copy. Bound layers are filled from
  the item like template bindings; `link` layers open the item's page through
  `itemLinkPageID` (a deterministic identity that is not a document page,
  mapped to the item address in `staticRoutes`). Previous / Next open the
  neighbouring page (`pageLinkID`) and are left out on the first / last page.
  With no matching item the repeated layer is left out. Later pages are not
  in generated navigation; they are in the sitemap. Pictures only a list copy
  shows are exported.
- List findings (SF-1003-004, in `CollectionTemplates.findings` and
  `CollectionLists.findings`, carrying `listID`): `missingPage`, `listPage`,
  `listLayerMissing`, `listNeedsFlow`, `listOverlap`, `listFilter`,
  `listSortField`, `paginationControl`, `noItemPages`, binding findings, and
  `routeCollision` when a later page's address is taken (the build refuses
  it). An unusable list leaves its page as designed. Blocking rules:
  `CollectionIssue` `list` (shape and limits) and `duplicateListLayer`.
- Relative links in folders: pages written in a folder (item pages, later
  list pages, language trees) now use page-relative links and image sources
  in every language. Before D04 the default language's item pages used
  root-relative ones, which broke links and pictures inside `posts/…` pages.
- Editor: Collections gains a **Lists** tab: choose a page and a layer
  inside a Stack or Grid, then per list a live summary ("Shows N of M
  published items on P pages"), filter expression with first-item preview,
  order field and direction, items per page, limit, a field or toggle for
  each Text, Image, Link and Button layer inside the repeated layer, Previous
  and Next pickers, and the list's findings.
- List diagnostics: `CollectionLists.diagnostic` (SF-1003-002, operation,
  sorted collection ids with lists, listed item count, duration, first finding
  kind; no names, values or expressions).

## Consequences

- A list's later pages share the page's SEO overrides; their names get
  ", page N". One list per repeated layer; lists cannot be nested.
- Filters run at build time only (no visitor-side filtering or search).
- Rich text fields are shown as plain text.
- On item pages, Buttons and Links can only open the item's own page (the
  Template tab does not offer it yet); in lists they open each item's page.
- Item pages inherit the template page's SEO overrides (one override applies
  to every item page). Leave the template page title empty to use each item's
  title.

## Reversal

Stop reading `template` and `lists` from collections and build template and
list pages as ordinary pages; stored templates and lists stay readable.
