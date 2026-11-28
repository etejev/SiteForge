# ADR-0070 — Build-time expression language

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-036 (approved by the owner 2026-11-26 1:30 PM EST)
- Requirements: SF-1004-001 … SF-1004-008

## Context

OD-036 asks for a small, total, side-effect-free expression language (field
access, string/number/date formatting, comparison, conditional), evaluated at
build time only, with typed validation and no loops or user functions. CMS
collections (OD-035) and template bindings will use it.

## Decision

- Code lives in `SiteForge/DocumentModel.swift` (`SiteExpression…` types,
  `SiteExpressionEngine`). Nothing in the editor or the exported site runs
  authored code; the engine is pure Swift with no I/O, clock or locale.
- Types: text, number (Double), true/false, date (calendar day, `YYYY-MM-DD`,
  no time zone). Any value may be missing.
- Syntax: literals (`12`, `3.5`, `"text"` with `\"`, `\\`, `\n`, `\t`,
  `true`, `false`), dotted field paths (`author.name`), unary `-`, `not`/`!`,
  `* /`, `+ -` (`+` on two numbers or two texts), `??`, `< <= > >=`,
  `== !=`, `and`/`&&`, `or`/`||` (that precedence, highest first after unary),
  parentheses and 25 built-in functions (`SiteExpressionEngine.functionSignatures`),
  including `if(condition, then, else)` and `default(value, fallback)`.
- Typed validation (`SiteExpressionEngine.check(source, schema:)`) against a
  schema of field paths and types; it returns a `SiteExpressionProgram` with
  the result type and the sorted field paths read. Format arguments
  (`round`/`format` decimals, `truncate` length, `formatDate` style, literal
  `date("…")`) must be written directly and are checked here.
- Errors (`SiteExpressionError`) have a category, a Unicode-scalar range for
  highlighting, a message naming only fields, functions and types, and a
  recovery suggestion.
- Totality and limits: at most 2,000 bytes, 512 tokens, 256 syntax nodes and
  32 nesting levels; every intermediate text at most 64 KiB (checked before
  `replace` builds its result). Evaluation visits each node at most once.
  Division by zero, overflow, too-long text and unparsable `date`/`number`
  input give a missing value plus a `SiteExpressionRuntimeFinding`; evaluation
  always finishes.
- Missing values: text parameters read missing as empty text; conditions read
  it as false; arithmetic and date functions give missing; `==` treats missing
  and empty text as equal; ordering with a missing side is false; missing
  renders as nothing.
- Provenance (SF-1004-003): `SiteExpressionEvaluation.decisions` lists, in
  order, which `if` branch was taken, whether a fallback was used, and which
  fields had no value, each with a plain explanation.
- Storage (SF-1004-001/005): `SiteExpression` stores only `version` (1) and
  `source`, exact keys. It is syntax-checked on decode; field types are
  checked when it is used, so a removed field keeps the authored expression
  and the check names the missing field.
- Diagnostics: `SiteExpressionDiagnostic` (requirement ID, operation, sorted
  object identifiers, duration, failure category); never source text or values.
- Number output is locale-independent (`numberText`, `String(format:)` with
  `%.Nf`); date names are English. Localized formatting waits for site
  localization (OD-038).

## Consequences

- No document schema change in this batch: nothing stores expressions yet.
  Template bindings (OD-035, lane D item D3) will store `SiteExpression`
  records and provide the authoring UI (field and function lists, live result,
  error highlight) and build output.
- Floating-point numbers compare exactly (`0.1 + 0.2 == 0.3` is false).

## Reversal

Remove the `SiteExpression…` types; nothing depends on them until bindings land.
