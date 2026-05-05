# PostgreSQL Extension Development Constitution

> Full code style, error handling, security, performance, and project-structure
> rules for PostgreSQL backend C extensions in this repository.

## I. Code Style & Formatting

### C Code (PostgreSQL Backend Extensions)

C code MUST use Allman brace style with 4-space indentation (no tabs). Opening
brace on its own line, aligned with the control keyword. Closing brace on its
own line at the same column. C++ is FORBIDDEN.

Naming:
- **Internal C symbols** (variables, static functions, struct fields you own):
  camelCase. This matches a large fraction of PG core (`ExecInitNode`,
  `MemoryContextAlloc`, `LockAcquire`).
- **SQL-callable C functions** (those declared with `PG_FUNCTION_INFO_V1`):
  snake_case. SQL folds unquoted identifiers to lowercase, so the C symbol
  must match the SQL identifier exactly without forcing callers to double-quote.

```c
static char *
processData(const char *inputData, int maxLength)
{
    char *result;
    int   len;

    if (inputData == NULL || maxLength <= 0)
    {
        ereport(ERROR,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("invalid input parameters")));
    }

    len = strlen(inputData);
    result = (char *) palloc(len + 1);
    memcpy(result, inputData, len);
    result[len] = '\0';

    return result;
}
```

### SQL Code

All SQL and PL/pgSQL MUST use UPPERCASE for keywords, lowercase for identifiers.
Table and column names MUST use snake_case. Statements MUST be formatted for
readability with aligned keywords.

```sql
CREATE OR REPLACE FUNCTION process_custom(input custom_type)
  RETURNS TEXT
  LANGUAGE plpgsql
  STABLE
AS $$
BEGIN
  IF input.id IS NULL THEN
    RAISE EXCEPTION 'id cannot be NULL';
  END IF;
  RETURN format('Processing: %s (ID: %s)', input.name, input.id);
END;
$$;
```

Extension SQL files MUST include:
- Copyright notice and SPDX identifier
- File header comment with filename and description
- psql execution guard (`\echo Use "CREATE EXTENSION..." \quit`)

## II. Documentation Standards

### File Headers

Every C and SQL source file MUST begin with a copyright notice and
doxygen-style file header:

```c
/*
 * Copyright (c) <year> <your-org>
 * SPDX-License-Identifier: MIT
 */

/**
 * @file extension_utils.c
 * @brief Utility functions for extension data processing
 * @author <your-name>
 * @date <YYYY-MM-DD>
 */
```

The `@date` tag reflects original file creation; updates tracked via version
control.

### Function Documentation

Function headers MUST document purpose, parameters (`@param`), and return values
(`@return`). For PG_FUNCTION_INFO_V1 functions, `@param` describes SQL-level
arguments (0, 1, etc.), not the C-level fcinfo parameter.

```c
/**
 * @brief Compare two custom types for equality
 * @param 0 First custom type value
 * @param 1 Second custom type value
 * @return Boolean true if equal
 */
PG_FUNCTION_INFO_V1(customtype_eq);
```

### Inline Comments

Inline comments MUST use C++ `//` style. Explain WHY decisions were made, not
WHAT the code does when self-evident.

## III. Regression Coverage

Every shipped change MUST have regression coverage in PostgreSQL's pg_regress
framework. No change merges without a passing test that would have caught its
absence. Test-first is the default cycle — it removes the most ambiguity about
expected behavior — but writing tests and implementation together is acceptable
when that is clearer; what is not acceptable is shipping without a test.

Default cycle:
1. Write regression test in `sql/` defining expected behavior
2. Create expected output in `expected/`
3. Verify test FAILS with current code
4. Implement feature
5. Verify test PASSES
6. Refactor with tests as safety net

Test coverage MUST include:
- Normal operation cases
- Boundary conditions (min/max values, empty input)
- NULL handling (NULLs as each argument, NULL results)
- Error conditions with expected messages
- Index usage verification (EXPLAIN output)
- Extension lifecycle (CREATE/ALTER EXTENSION UPDATE/DROP cycles)

```sql
-- sql/custom_ops.sql
\pset format unaligned

SELECT 'basic_eq'::text AS test, customtype_eq('foo', 'foo');
SELECT 'null_lhs'::text AS test, customtype_eq(NULL, 'foo');
EXPLAIN (COSTS OFF) SELECT * FROM t WHERE col = 'target';
```

Extension lifecycle testing is MANDATORY. CREATE/ALTER EXTENSION
UPDATE/DROP EXTENSION cycles MUST work without errors. Upgrade AND downgrade
paths MUST be tested for each version pair.

## IV. PGXS Build System

Extensions MUST use PostgreSQL's PGXS framework. Makefiles MUST define
`EXTENSION`, `DATA`, `MODULES`, and include `PGXS.mk`. Standard targets
required: `all`, `install`, `installcheck`, `clean`.

```makefile
EXTENSION = myextension
DATA = myextension--1.0.0.sql
MODULES = myextension
REGRESS = basic_ops edge_cases extension_lifecycle

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
```

Version upgrade scripts follow naming `extension--oldver--newver.sql` and
downgrade scripts follow `extension--newver--oldver.sql` (if supported). Control
files MUST specify `default_version`, `module_pathname`, and `relocatable`.

Extension versions use semantic versioning (MAJOR.MINOR.PATCH):
- MAJOR: Incompatible API changes, breaking schema modifications
- MINOR: Backward-compatible functionality additions
- PATCH: Backward-compatible bug fixes

## V. Memory and Error Handling

Backend memory management MUST use PostgreSQL's palloc/pfree family exclusively.
Direct malloc/free is FORBIDDEN in backend code.

Error handling MUST use ereport/elog with appropriate levels:

| Level | Use case |
|-------|---------|
| `ERROR` | Invalid input, operational failures |
| `WARNING` | Recoverable issues the user should know about |
| `NOTICE` | Informational messages for the user |
| `DEBUG1`–`DEBUG5` | Internal diagnostics |

Extensions MUST compile cleanly with `-Wall -Wextra -Werror`.

## VI. Security

- User input MUST be validated before use; reject unexpected types/ranges
- SQL injection MUST be prevented — use SPI prepared statements, not string
  concatenation
- Privilege escalation paths MUST be analyzed and documented in comments
- `SECURITY DEFINER` functions require explicit caller permission checks
- Resource exhaustion MUST be considered (memory, CPU, I/O loops)

## VII. Performance

- Index-compatible operators MUST define appropriate B-tree/hash support functions
- Expensive operations SHOULD check for interrupts (`CHECK_FOR_INTERRUPTS()`)
- Large palloc allocations MUST be justified with comments
- Query planner integration MUST provide selectivity/cost estimates where applicable
- Avoid calling palloc inside tight loops; pre-allocate or use memory contexts

## VIII. Hooks and Callbacks

PostgreSQL hooks MUST follow the chain pattern — save the previous hook on load
and call it (if non-NULL) from your handler:

```c
static ExecutorRun_hook_type prev_ExecutorRun = NULL;

static void
myext_ExecutorRun(QueryDesc *queryDesc, ScanDirection direction,
                  uint64 count, bool execute_once) {
  /* Your logic here */

  if (prev_ExecutorRun)
    prev_ExecutorRun(queryDesc, direction, count, execute_once);
  else
    standard_ExecutorRun(queryDesc, direction, count, execute_once);
}

void
_PG_init(void) {
  prev_ExecutorRun = ExecutorRun_hook;
  ExecutorRun_hook = myext_ExecutorRun;
}
```

Hooks MUST NOT assume they are the only registered hook. Calling the previous
hook (or the standard function) is MANDATORY unless there is documented intent
to block the standard behavior.

## IX. Project Structure

Every extension repository MUST include `project_template.md` which defines the
repository structure.

All SQL examples in user documentation MUST have corresponding regression tests
in `sql/doc_examples.sql`. Tests MUST reference the documentation location:

```sql
-- ============================================================================
-- README.md: Basic usage (~line 45)
-- ============================================================================
SELECT process_custom(ROW(1, 'test', NOW())::custom_type);
```

Use the `doc-example-tester` skill to generate and validate these tests.

Code submissions MUST pass all checks in the `code-review` skill checklist before
merge. Use the `test-coverage` skill to identify gaps before submitting.

## X. speckit Integration

This repo uses speckit for structured feature development. Specs live in
`specs/<NNN>-feature-name/`.

speckit artifacts per feature:
- `spec.md` — what to build and why
- `plan.md` — how to build it (implementation design)
- `tasks.md` — ordered, atomic task list
- `data-model.md` — schema and data structures
- `contracts/` — operator/API contracts and test cases

---

**Version**: 4.0.0 | **Ratified**: 2026-05-05

Changes since 3.0.0:
- C style switched to Allman / 4-space / no tabs
- Naming clarified: camelCase for internal C, snake_case forced for SQL-callable
- Top-of-file framing now defers to AGENTS.md for headline rules
- Section X updated: CLAUDE.md no longer exists, AGENTS.md is the source of truth
