---
name: pg-hook-audit
description: >
  Review PostgreSQL hook and callback implementations for correctness and safety.
  Checks hook chaining (save/restore previous), NULL guards before calling previous
  hooks, memory context safety, transaction safety, and interrupt handling. Trigger
  when adding or modifying any PostgreSQL hook (ProcessUtility, executor, planner,
  check_password, etc.) or when asked to "audit hooks", "check hook safety", or
  "review callbacks".
allowed-tools: Read, Grep, Glob, Edit, AskUserQuestion
---

# PostgreSQL Hook & Callback Audit

You are auditing PostgreSQL hook implementations. Every hook that violates the
chain pattern can corrupt behavior for other extensions or crash the server.
Work through each check below for every hook found in the code.

## Step 1: Discover All Hooks

Find hook registrations:
```bash
grep -n '_hook\s*=' *.c
grep -n 'ExecutorRun_hook\|ExecutorStart_hook\|ExecutorFinish_hook\|ExecutorEnd_hook' *.c
grep -n 'ProcessUtility_hook\|planner_hook\|post_parse_analyze_hook' *.c
grep -n 'ClientAuthentication_hook\|check_password_hook' *.c
grep -n 'object_access_hook\|emit_log_hook' *.c
grep -n 'shmem_request_hook\|shmem_startup_hook' *.c
```

Build a list of every hook variable assigned in this extension.

## Step 2: Chain Pattern — Save Previous Hook

For each hook `hook_var`, verify in `_PG_init`:

```c
// CORRECT
static SomeHook_type prev_some_hook = NULL;

void _PG_init(void) {
  prev_some_hook = some_hook;      // Save existing handler
  some_hook = my_some_hook;        // Install ours
}
```

**Check:**
- [ ] Previous hook saved to a `static` variable before overwriting
- [ ] The static variable is initialized to `NULL`
- [ ] Saving happens BEFORE assigning the new hook (atomicity in single-threaded
  `_PG_init` is fine, but order matters for clarity)

**Flag as BLOCKER if:** Hook is assigned without saving the previous value.
This silently breaks every other extension that registered the same hook.

## Step 3: Chain Pattern — Call Previous Hook

For each hook handler, verify it calls the previous hook on ALL exit paths:

```c
// CORRECT
static void
my_ExecutorRun(QueryDesc *queryDesc, ScanDirection dir,
               uint64 count, bool execute_once) {
  /* pre-work */

  if (prev_ExecutorRun)
    prev_ExecutorRun(queryDesc, dir, count, execute_once);
  else
    standard_ExecutorRun(queryDesc, dir, count, execute_once);

  /* post-work */
}
```

**Check:**
- [ ] `prev_hook` is NULL-checked before calling
- [ ] Standard function called when `prev_hook` is NULL (not just skipped)
- [ ] Call happens on every code path (check every `if`/`return`/`goto`)
- [ ] For hooks with no "standard" function (e.g., `emit_log_hook`): NULL-check
  and call is still required; skipping the chain when previous is NULL is correct
  only if the hook has no standard fallback

**Flag as BLOCKER if:** Chain call is missing on any code path. The standard
function not being called can cause silent query failures.

## Step 4: Unload Pattern — Restore Previous Hook

If the extension provides `_PG_fini`:

```c
void _PG_fini(void) {
  some_hook = prev_some_hook;   // Restore previous
}
```

**Check:**
- [ ] All hooks restored in `_PG_fini`
- [ ] Restoration happens for every hook registered in `_PG_init`
- [ ] Order of restoration is reverse of registration (if hooks interact)

**Note:** If no `_PG_fini` is present, flag as SUGGESTION: unloading the
extension (e.g., `DROP EXTENSION`) without restoring the hook will leave a
dangling pointer.

## Step 5: Memory Context Safety

- [ ] Hook handlers do not allocate memory in a context that outlives the hook
  invocation unless that is intentional and documented
- [ ] Memory allocated in `TopMemoryContext` or `CacheMemoryContext` is justified
  (these survive transactions and can leak)
- [ ] Temporary work inside a hook uses `CurrentMemoryContext` or a
  short-lived child context
- [ ] If the hook creates a memory context, it deletes it on all exit paths
  including error paths (use PG_TRY/PG_FINALLY or `MemoryContextDelete`)

## Step 6: Transaction & Error Safety

- [ ] Hook handlers that can ERROR use PG_TRY/PG_CATCH if they need cleanup
- [ ] Resources acquired before calling previous hook are released after,
  even if the previous hook throws
- [ ] Hooks in the executor family (ExecutorRun, etc.) properly handle
  `queryDesc->estate` being freed if an error occurs downstream
- [ ] Hooks do not call `CommitTransaction` / `AbortTransaction` directly
- [ ] `CHECK_FOR_INTERRUPTS()` called in loops inside hooks

## Step 7: Concurrency & Shared Memory

- [ ] Hooks that access shared state use appropriate locking
  (`LWLockAcquire`/`LWLockRelease` or spinlocks)
- [ ] `shmem_request_hook` correctly calls `prev_shmem_request_hook` and
  requests its own shared memory segment
- [ ] `shmem_startup_hook` initializes its segment and calls
  `prev_shmem_startup_hook`
- [ ] No use of global C variables (non-static) for per-backend state

## Step 8: Security Hooks

For `ClientAuthentication_hook` or `check_password_hook`:
- [ ] Hook does not inadvertently allow authentication when it should deny
- [ ] Hook does not log passwords or sensitive data
- [ ] Hook calls the previous hook FIRST if order matters for security
  (deny-by-default: previous hook might reject, yours should not bypass)
- [ ] Function is declared with appropriate privilege level

## Step 9: ProcessUtility Hook

For `ProcessUtility_hook`:
- [ ] Calls `prev_ProcessUtility` or `standard_ProcessUtility` on every path
- [ ] The `pstmt`, `queryString`, `readOnlyTree`, `context`, `params`, and
  `dest` arguments are passed through unchanged (unless intentional modification)
- [ ] `completionTag` is updated correctly if modifying query behavior
- [ ] Hook does not intercept statements it doesn't own (use `nodeTag(pstmt->utilityStmt)`)

## Step 10: Test Coverage for Hooks

For each hook, verify these tests exist:

- [ ] Hook is active: load extension, execute a query that triggers the hook,
  verify the hook ran (e.g., via a side-effect table, GUC, or log check)
- [ ] Hook chains correctly: install a second "observer" and verify both ran
  (may require a test helper extension)
- [ ] Hook error handling: trigger an error inside the hook, verify the database
  recovers cleanly (no session crash, no orphaned locks)

## Final Report

```
## Hook Audit Report

### BLOCKERs
1. [file.c:45] ExecutorRun_hook: previous hook not called on ERROR path
   Fix: wrap post-work in PG_TRY and ensure prev_ExecutorRun is called

### REQUIRED
1. [file.c:22] No _PG_fini: dropping the extension leaves dangling hook pointer

### Suggestions
1. [file.c:88] Consider adding CHECK_FOR_INTERRUPTS() in the inner loop

### Hook Summary
| Hook | Save prev | NULL-check | Call prev/std | Restore | Tests |
|------|-----------|------------|---------------|---------|-------|
| ExecutorRun | ✓ | ✓ | ✗ BLOCKER | N/A | ✓ |
```

Call `AskUserQuestion` after the report: fix BLOCKERs automatically, walk through
interactively, or just show the report.
