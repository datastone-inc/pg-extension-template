---
name: test-coverage
description: >
  Analyze test coverage for PostgreSQL C extensions. Identifies SQL-exposed
  functions and operators lacking test cases, finds missing boundary/NULL/error/
  index-usage tests, and checks doc_examples.sql completeness. Trigger when
  the user says "check test coverage", "what's not tested", "test gaps", or
  before marking any feature complete.
allowed-tools: Read, Grep, Glob, Bash(make:*), Bash(pg_config:*), AskUserQuestion
---

# Test Coverage Analysis for PostgreSQL Extensions

You are analyzing test coverage for a PostgreSQL C extension. Work through each
phase and produce a gap report with specific, actionable items.

## Phase 1: Discover Exposed Surface Area

### 1a. Find all SQL-callable functions

Scan the extension SQL file(s) (`*.sql`, excluding `sql/` test files):

```bash
grep -E 'CREATE (OR REPLACE )?FUNCTION' myextension--*.sql
grep -E 'CREATE (OR REPLACE )?PROCEDURE' myextension--*.sql
grep -E 'CREATE OPERATOR' myextension--*.sql
grep -E 'CREATE OPERATOR CLASS' myextension--*.sql
grep -E 'CREATE TYPE' myextension--*.sql
```

Build a list of all public symbols:
- Function names (as they appear in SQL, not C)
- Operator symbols (`+`, `<`, `=`, etc.) with their left/right types
- Types and casts
- Operator classes / families

### 1b. Find all C implementations

Scan the C files for `PG_FUNCTION_INFO_V1`:
```bash
grep -n 'PG_FUNCTION_INFO_V1' *.c *.h 2>/dev/null
```

Cross-reference with the SQL surface to find any C functions not exposed or
any SQL references to missing C functions.

### 1c. Read the Makefile REGRESS list

```bash
grep '^REGRESS' Makefile
```

List all test files that pg_regress will run.

## Phase 2: Analyze Existing Tests

For each test file in `sql/`:

Read the file and note which functions/operators are tested. Build a coverage
matrix:

| Function/Operator | Basic | NULL args | Boundary | Error case | Index (EXPLAIN) |
|-------------------|-------|-----------|----------|------------|----------------|
| `myext_eq(a, b)` | ✓ | ? | ? | ? | ? |

Fill in ✓ (covered), ✗ (missing), or N/A (not applicable).

**NULL handling rules:**
- Every function with nullable arguments MUST test NULL as each argument
- Functions declared STRICT: verify the test confirms they return NULL (not error)
- Functions NOT STRICT: verify they handle NULL explicitly

**Boundary value rules:**
- Numeric types: test MIN_INT/MAX_INT, 0, negative numbers
- Text: test empty string `''`, very long string, strings with special chars
- Composite types: test all-NULL, partially-NULL components
- Dates/timestamps: test epoch, far future, far past

**Error condition rules:**
Each documented error (ereport ERROR) MUST have a test with `\set ON_ERROR_STOP off`
and the expected error message captured in the `.out` file.

**Index usage rules (for index-compatible operators):**
```sql
-- Must appear in sql/ for each operator class:
CREATE INDEX idx_test ON t USING btree (col);  -- or hash, gist, etc.
EXPLAIN (COSTS OFF) SELECT * FROM t WHERE col = 'target';
-- Expected output MUST show "Index Scan" not "Seq Scan"
```

## Phase 3: Check Mandatory Test Files

- [ ] `sql/extension_lifecycle.sql` exists
  - Creates extension from scratch
  - Tests ALTER EXTENSION UPDATE (for each version pair)
  - Tests DROP EXTENSION — verify no orphaned objects
  - Tests reinstall: DROP then CREATE again

- [ ] `sql/doc_examples.sql` exists
  - Every `-- Example:` block in README.md and `doc/*.md` has a test
  - Use the `doc-example-tester` skill for detailed validation

- [ ] All files in `sql/` are listed in the Makefile `REGRESS` line
  - Files in `sql/` but missing from `REGRESS` are silently skipped

## Phase 4: Check PL/pgSQL Coverage

For each PL/pgSQL function:
- [ ] RAISE EXCEPTION paths have test cases
- [ ] EXCEPTION WHEN blocks are exercised
- [ ] Dynamic SQL paths (if any) are tested with both valid and invalid inputs

## Phase 5: Check Operator Class Coverage

For each operator class registered:

**btree:**
- [ ] All 5 strategies tested: `<`, `<=`, `=`, `>=`, `>`
- [ ] Sort order verified: `ORDER BY col` returns rows in expected order
- [ ] Comparison with NULLs (NULLS FIRST / NULLS LAST)

**hash:**
- [ ] Equal values produce same hash (verified indirectly through hash join test)
- [ ] Hash join can be forced: `SET enable_hashjoin = on; SET enable_nestloop = off;`

## Phase 6: Present Gap Report

Format the report as:

```
## Test Coverage Gap Report

### Missing Test Files (add to REGRESS in Makefile)
- No tests exist for: X, Y, Z functions

### NULL Handling Gaps
1. myext_compare(a, b): NULL as first argument not tested
2. myext_format(text): NULL input not tested

### Boundary Value Gaps
1. myext_add(int4, int4): INT_MAX + 1 overflow not tested

### Error Condition Gaps
1. myext_parse(text): invalid format error not tested
   Expected error: 'invalid myext format'

### Index Usage Gaps
1. No EXPLAIN test for btree opclass on myext_type
   Add: CREATE INDEX, then EXPLAIN (COSTS OFF) with WHERE clause

### Extension Lifecycle Gaps
1. sql/extension_lifecycle.sql missing
2. No ALTER EXTENSION UPDATE test for 1.0.0 -> 1.1.0

### Documentation Example Gaps
1. README.md line 45 example not tested in sql/doc_examples.sql

### Summary
Functions with full coverage: N/M
Test files missing from REGRESS: N
Highest-priority gaps: [list top 3]
```

After presenting the report, ask the user:
- Generate skeleton test cases for the top gaps?
- Add to `sql/` and `expected/` automatically?
- Just show the report?
