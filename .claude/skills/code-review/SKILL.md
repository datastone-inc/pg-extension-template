---
name: code-review
description: >
  Full code review checklist for PostgreSQL C extensions. Covers memory
  management, error handling, security (SQL injection, privilege paths), hook
  correctness, index operator completeness, test coverage gaps, and constitution
  compliance. Trigger when asked to review code, before merging a feature, or
  when the user says "review", "check my code", or "is this ready to merge".
allowed-tools: Read, Grep, Glob, Edit, AskUserQuestion
---

# PostgreSQL C Extension Code Review

You are conducting a code review for a PostgreSQL backend C extension. Work
through each section below systematically. Flag every issue, classify it by
severity, and present a consolidated report at the end.

Severity levels:
- **BLOCKER** — must fix before merge (crash risk, data corruption, security)
- **REQUIRED** — must fix but won't cause immediate failure
- **SUGGESTION** — improvement; use judgment

## Step 1: Identify Scope

Determine what to review:
- Default: all files changed since the merge base — `git diff --name-only $(git merge-base HEAD master)..HEAD`
- If only one commit's worth: `git diff --name-only HEAD~1`
- If the user mentioned specific files, review those instead
- Read each C file, SQL file, and the test files together

## Step 2: Memory Management

For every C function, check:

- [ ] All allocations use `palloc`/`palloc0`/`repalloc` — no `malloc`/`calloc`/`strdup`
- [ ] No `free()` calls; `pfree()` used where explicit freeing is needed
- [ ] `palloc` result is not used without NULL check where a subsequent OOM could
  occur (rare in PG — palloc throws on failure, so no NULL check needed, but
  document this assumption)
- [ ] Temporary buffers use an appropriate memory context (CurrentMemoryContext or
  a short-lived context created with `AllocSetContextCreate`)
- [ ] No memory context leaks: contexts created in a function are deleted before
  the function returns on all code paths

**Common patterns to flag:**
```c
char *buf = malloc(n);           // BLOCKER: use palloc
free(result);                    // BLOCKER: use pfree
strdup(str);                     // BLOCKER: use pstrdup
```

## Step 3: Error Handling

For every error/exception path:

- [ ] Errors use `ereport(ERROR, ...)` — no `return NULL` to signal errors silently
- [ ] Error messages include `errcode()` with an appropriate SQLSTATE
- [ ] `errmsg()` strings are lowercase, no trailing period (PostgreSQL convention)
- [ ] `errdetail()` / `errhint()` used where helpful
- [ ] No `printf`/`fprintf`/`write` for error output
- [ ] No bare `exit()` or `abort()` calls
- [ ] PG_TRY/PG_CATCH used correctly when catching exceptions; PG_RE_THROW used
  if not handling the error
- [ ] After a PG_CATCH block, the error state is properly cleared with
  `FlushErrorState()` before resuming normal execution

## Step 4: Security

- [ ] All function arguments from SQL are validated before use
  (type, range, length, NULLness)
- [ ] `SECURITY DEFINER` functions check caller permissions explicitly
  (e.g., `pg_proc.proowner` or a dedicated ACL check)
- [ ] SPI queries use `SPI_prepare` + `SPI_execute_plan` with bound parameters,
  not string concatenation
- [ ] No user-supplied data is used in format strings (`errmsg(user_str)` is wrong;
  use `errmsg("%s", user_str)`)
- [ ] Resource bounds: loops over user-supplied data have a maximum iteration count
- [ ] Extension functions with `PARALLEL SAFE` are actually safe (no shared state)

## Step 5: PostgreSQL Correctness

- [ ] `PG_FUNCTION_INFO_V1` declared for every SQL-callable function
- [ ] `PG_GETARG_*` and `PG_RETURN_*` macros used (not direct fcinfo access)
- [ ] `PG_ARGISNULL` checked before `PG_GETARG_*` for nullable arguments
- [ ] `PG_RETURN_NULL()` used (not `return (Datum)0`) for NULL returns
- [ ] Strict functions: verify `STRICT` is declared in SQL and NULL checks
  are consistent
- [ ] Varlena types: `PG_DETOAST_DATUM` / `PG_DETOAST_DATUM_COPY` used as needed
- [ ] `SET_VARSIZE` used correctly for constructed varlena values
- [ ] No assumptions about `Datum` size vs pointer size across 32/64-bit builds

## Step 6: Operator & Index Correctness

For any operators registered with a btree or hash opclass:

- [ ] **btree**: comparison function returns negative/zero/positive (not -1/0/1)
  and handles all argument combinations consistently
- [ ] **btree**: `<`, `<=`, `=`, `>=`, `>` operators all defined and consistent
- [ ] **btree**: negator operators declared (`=` negates `<>`, `<` negates `>=`)
- [ ] **hash**: hash function returns the same value for equal inputs (respects
  the equality semantics of the type)
- [ ] Support functions registered in the correct strategy number slots
- [ ] `COMMUTATOR` declared where applicable (e.g., `a < b` commutes with `b > a`)

## Step 7: Hooks & Callbacks

If the code registers any PostgreSQL hooks:

- [ ] Previous hook saved at load: `prev_hook = hook_var; hook_var = my_hook;`
- [ ] Handler calls previous hook (if non-NULL) OR the standard function on
  every exit path — never skips the chain
- [ ] Hook restored on unload if `_PG_fini` is present
- [ ] NULL-checked before calling previous hook:
  ```c
  if (prev_hook) prev_hook(...);
  else standard_hook(...);
  ```
- [ ] No assumption that this extension's hook runs first or last
- [ ] Memory context is appropriate inside the hook (check which context is
  current at hook entry)

## Step 8: PL/pgSQL Functions

For PL/pgSQL (`.sql` files with `LANGUAGE plpgsql`):

- [ ] `RAISE EXCEPTION` used for errors (not RETURN NULL silently)
- [ ] Exception blocks (`EXCEPTION WHEN ...`) handle only the errors they intend to
- [ ] `EXECUTE` with dynamic SQL uses `USING` clause for parameters, not
  string concatenation
- [ ] `SECURITY DEFINER` functions `SET search_path = pg_catalog, pg_temp`
- [ ] Volatile/stable/immutable classification is accurate

## Step 9: Test Coverage

For each C function exposed to SQL, verify the `sql/` directory has tests for:

- [ ] Normal/happy-path cases
- [ ] NULL as each argument
- [ ] Boundary values (max/min, empty string, zero)
- [ ] Expected error conditions (with `\set ON_ERROR_STOP off` around them)
- [ ] Index usage: `EXPLAIN (COSTS OFF)` shows index scan when expected

Also check:
- [ ] `sql/extension_lifecycle.sql` exists and tests CREATE/ALTER/DROP
- [ ] `sql/doc_examples.sql` exists and matches the examples in documentation
- [ ] All `sql/*.sql` files have corresponding entries in `REGRESS` in the Makefile

## Step 10: Code Style & Constitution

- [ ] Copyright/SPDX header present in every new file
- [ ] Doxygen `@file`/`@brief`/`@author`/`@date` header present
- [ ] Every SQL-callable function has a doxygen doc comment
- [ ] Allman style, 4-space indentation (no tabs)
- [ ] Internal C symbols use camelCase; SQL-callable C functions use snake_case
- [ ] Inline comments explain WHY, not WHAT
- [ ] No dead code or commented-out code blocks
- [ ] Compiles without warnings: `make 2>&1 | grep -E 'warning|error'`

## Step 11: Build System

- [ ] `Makefile` has `EXTENSION`, `DATA`, `MODULES`, `REGRESS` defined
- [ ] All test files in `sql/` are listed in `REGRESS`
- [ ] `make clean` removes all generated files
- [ ] `.control` file has `default_version`, `module_pathname`, `relocatable`

## Final Report Format

Present findings in this format:

```
## Code Review Report

### BLOCKERs (must fix before merge)
1. [file.c:42] malloc used instead of palloc — crash risk on OOM
   Fix: replace `malloc(n)` with `palloc(n)`

### REQUIRED
1. [file.c:87] errmsg() string has trailing period — violates PG convention
   Fix: remove period from "invalid value."

### SUGGESTIONS
1. [file.c:110] Consider pfree(buf) after use to return memory promptly

### Test Gaps
1. No test for NULL as second argument to myext_compare()
2. No index usage test (EXPLAIN) for the btree opclass

### Summary
Files reviewed: X | BLOCKERs: N | Required: N | Suggestions: N
```

After presenting the report, call `AskUserQuestion` to ask whether to:
- Walk through BLOCKERs one by one and apply fixes
- Apply all fixes automatically
- Just show the report and stop
