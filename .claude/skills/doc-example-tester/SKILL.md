---
name: doc-example-tester
description: >
  Generate and validate regression tests for SQL examples in extension
  documentation. Ensures every `-- Example:` block in README.md and doc/*.md
  has a matching test in sql/doc_examples.sql, that the test runs, and that
  documented output matches actual output. Trigger when the user says
  "verify doc examples", "generate doc tests", "update doc_examples.sql",
  or after editing documentation SQL.
allowed-tools: Read, Grep, Glob, Bash(make:*), Edit, AskUserQuestion
---

# Documentation Example Test Generator

You are validating that every SQL example shown to users in documentation has
a matching, passing regression test. Drift between documentation and actual
behavior is a recurring source of user confusion; this skill catches it.

## Step 1: Discover Examples

Find every `-- Example:` block in user-facing docs:

```bash
grep -n "^-- Example:" README.md doc/*.md 2>/dev/null
```

For each match, extract:
- File path and line number
- Description (text after `-- Example:`)
- SQL statements that follow
- Documented output (lines beginning with `--` immediately after the SQL,
  including any `(N rows)` line)

Record the count: **examples found = N**.

## Step 2: Match Against Existing Tests

Read `sql/doc_examples.sql`. Each test block is headed by a comment of the form:

```sql
-- ============================================================================
-- README.md: <description> (~line <N>)
-- ============================================================================
```

Match examples to tests by **file + line number (±5 lines tolerance)**, not by
description (descriptions drift). Build:

| State | Action |
|-------|--------|
| Example has matching test | Leave alone |
| Example has no test | Generate one (Step 3) |
| Test has no matching example | Flag for user — example may have been removed |

## Step 3: Generate Missing Tests

For each unmatched example, append to `sql/doc_examples.sql`:

```sql
-- ============================================================================
-- <file>: <description> (~line <N>)
-- ============================================================================
<SQL from the example>
```

Update `expected/doc_examples.out` with the documented output, formatted to
match `pg_regress` conventions (`\pset format unaligned` if that's the file's
header).

## Step 4: Run Tests

```bash
make installcheck REGRESS=doc_examples
```

Record: **tests executed = M, passed = P, failed = F**.

If `M ≠ N`, investigate before continuing — a missing test slipped through
generation.

## Step 5: Validate Output

For each example, compare the documented output (from Step 1) against the
actual output in `results/doc_examples.out`. Compare:

- Column headers
- Row count (`(N rows)` line)
- Each data row, in order

If any aspect is ambiguous (e.g., output reformatted by `\pset`), flag the
example for manual review rather than silently accepting it.

Record: **examples validated = V, matches = X, mismatches = Y**.

## Step 6: Report

```
## Doc Example Test Report

Examples found:    N
Tests after run:   N (M generated, P unchanged)
Tests executed:    N (P passed, F failed)
Examples validated: N (X matches, Y mismatches)

Counts consistent: Yes / No

### Mismatches
1. README.md:45 "Quick Start"
   Doc shows 3 rows, actual produced 2 rows.
   Doc row 1: "Alice | Widget"
   Actual row 1: "alice | widget"

### Tests with no matching example
1. sql/doc_examples.sql line 80 "Old API demo" — example removed from docs?
```

## Step 7: Triage (if mismatches exist)

For each mismatch, present the doc location, documented vs actual output,
and ask the user via `AskUserQuestion` which to do:

- **Fix documentation** — update the markdown to match actual output
- **Update test** — code is correct, regenerate `expected/doc_examples.out`
- **Bug** — leave the test failing, add `-- TODO: fix` and report
- **Skip** — defer

Do not change documentation or expected output without explicit user choice.
