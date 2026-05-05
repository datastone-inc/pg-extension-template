---
name: fdw-review
description: >
  Review PostgreSQL Foreign Data Wrapper implementations for correctness and
  completeness. Checks the FDW callback set (scan, modify, direct-modify),
  cost estimation, EXPLAIN integration, pushdown (join, upper-rel, where),
  async (PG 14+) and parallel scan support, validator coverage, and
  CREATE FOREIGN-* SQL wiring. Trigger when adding or modifying an FDW,
  when asked to "review my FDW", "audit FDW callbacks", "check pushdown",
  or before merging an FDW feature.
allowed-tools: Read, Grep, Glob, Edit, AskUserQuestion
---

# Foreign Data Wrapper Review

You are auditing a PostgreSQL FDW. FDWs have the largest API surface of any
extension category in PG: ~20 mandatory callbacks for scan, plus optional
modify, direct-modify, async, and parallel paths. Missing or incorrect
callbacks degrade silently to seq-scan-equivalent behavior or, worse, return
wrong rows. Work through each section and produce the report at the end
using the BLOCKER / REQUIRED / SUGGESTION severity model.

## Step 1: Inventory

Find the FDW boilerplate:

```bash
grep -n 'fdw_handler\|fdwroutine\|FdwRoutine' *.c
grep -n 'PG_FUNCTION_INFO_V1' *.c | grep -iE '_handler|_validator'
grep -nE 'CREATE FOREIGN DATA WRAPPER|CREATE SERVER|CREATE USER MAPPING|CREATE FOREIGN TABLE' *.sql
```

Identify:
- Handler function (returns `fdw_handler` Datum, populates `FdwRoutine`)
- Validator function (validates options on CREATE/ALTER FOREIGN-*)
- The set of `*_hook` callbacks assigned in the `FdwRoutine` struct
- The `OPTIONS` accepted at FDW / SERVER / USER MAPPING / FOREIGN TABLE level

Produce the callback table — which callbacks are populated, which are NULL.

## Step 2: Scan Path — Mandatory Callbacks

The scan path is mandatory. All seven of these MUST be non-NULL for a usable FDW:

- [ ] `GetForeignRelSize` — sets `baserel->rows` and (optionally) `baserel->tuples`. Must call `set_baserel_size_estimates` or compute estimates explicitly.
- [ ] `GetForeignPaths` — calls `add_path` with at least one `ForeignPath`. Cost estimates filled in (`startup_cost`, `total_cost`, `rows`).
- [ ] `GetForeignPlan` — builds a `ForeignScan` plan node. Populates `fdw_exprs` (parameterized expressions) and `fdw_private` (state to carry to executor).
- [ ] `BeginForeignScan` — opens the connection / cursor / file handle. Allocates per-scan state in the right memory context (typically a child of `ExecutorState`).
- [ ] `IterateForeignScan` — returns one `TupleTableSlot` per call, or empty slot on EOF. Slot must be `ExecClearTuple` or `ExecStoreVirtualTuple` correctly.
- [ ] `ReScanForeignScan` — resets the cursor for re-execution (parameterized scans, NestLoop inner side). Must produce identical results as a fresh BeginForeignScan with the same parameters.
- [ ] `EndForeignScan` — closes resources. Called even on error path (PostgreSQL invokes it during ExecutorEnd).

**Common bugs:**
- BeginForeignScan opens a connection in `EXPLAIN` (no rows actually scanned) — wastes connections. Check `eflags & EXEC_FLAG_EXPLAIN_ONLY`.
- IterateForeignScan returns the same `TupleTableSlot` reused without `ExecClearTuple` first — corruption.
- ReScanForeignScan re-opens the connection unnecessarily — slow. Reset the cursor instead where possible.

## Step 3: Cost Estimation

- [ ] `GetForeignRelSize` produces a non-trivial row estimate. Defaulting to 1000 (the PG default) silently kills the planner.
- [ ] If the data source supports remote `EXPLAIN`, use it to get real row estimates.
- [ ] `GetForeignPaths` cost estimates account for: row count, tuple width, network round-trips, remote-side execution time.
- [ ] FDW-level GUCs `fdw_startup_cost` and `fdw_tuple_cost` (or per-server options of the same names) are read and applied.

**Flag as REQUIRED if:** Row/cost estimates are hardcoded constants. The planner will pick bad join orders.

## Step 4: WHERE-Clause Pushdown

If the data source supports server-side filtering:

- [ ] In `GetForeignPaths` or `GetForeignPlan`, walk `baserel->baserestrictinfo` and split into pushable / non-pushable lists.
- [ ] Pushable expressions are serialized to the remote dialect (carefully — see SQL injection note below).
- [ ] Non-pushable expressions are kept in `local_exprs` and re-evaluated above the ForeignScan.
- [ ] **SQL injection**: any user-supplied identifier or value sent to the remote source MUST be quoted using `quote_identifier` / `quote_literal` or sent as a parameterized query.

**Flag as BLOCKER if:** User input from local SQL is concatenated unquoted into the remote query.

## Step 5: Join Pushdown (Optional)

If implementing `GetForeignJoinPaths`:

- [ ] Only push down joins where both sides are on the same foreign server.
- [ ] Local restrictions on the joined relation are evaluated locally if not pushable.
- [ ] Outer join semantics correctly preserved (LEFT/RIGHT/FULL).
- [ ] EXPLAIN shows the pushed-down join path.

## Step 6: Aggregate / Sort Pushdown (Optional)

If implementing `GetForeignUpperPaths`:

- [ ] Aggregates pushed only when remote dialect's aggregate semantics match PG's exactly (or the difference is documented and tolerated).
- [ ] `ORDER BY` pushed only when remote sort produces PG-compatible collation.
- [ ] `GROUP BY` columns and aggregate expressions are pushable individually.

## Step 7: Modify Path (Optional)

If the FDW supports INSERT / UPDATE / DELETE:

- [ ] `AddForeignUpdateTargets` — adds row-identification columns to the target list.
- [ ] `PlanForeignModify` — builds the remote DML statement.
- [ ] `BeginForeignModify` — prepares the remote statement.
- [ ] `ExecForeignInsert` / `ExecForeignBatchInsert` (PG 14+) — for INSERT.
- [ ] `ExecForeignUpdate` / `ExecForeignDelete` — for UPDATE / DELETE.
- [ ] `EndForeignModify` — closes prepared statements, commits or rolls back depending on transaction outcome (registered via `RegisterXactCallback`).
- [ ] `GetForeignModifyBatchSize` (PG 14+) — controls batched inserts.

**Transaction semantics:**
- [ ] FDW participates in 2PC if the data source supports it; otherwise document as known limitation.
- [ ] Local rollback after a remote commit is a known integrity risk — document it in user docs.

## Step 8: Direct Modify (Optional, Performance)

If implementing `PlanDirectModify`:

- [ ] Triggers prevent direct modify — check for triggers on the foreign table and skip direct path.
- [ ] RETURNING clause is handled correctly (results from the remote DML must be marshalled back).

## Step 9: Async Execution (PG 14+)

If implementing async append (`Append` over multiple foreign scans):

- [ ] `IsForeignPathAsyncCapable` returns true only for paths that actually benefit.
- [ ] `ForeignAsyncRequest` initiates the remote query without blocking.
- [ ] `ForeignAsyncConfigureWait` registers the file descriptor with the wait set.
- [ ] `ForeignAsyncNotify` reads available rows and either returns them or re-arms the wait.
- [ ] On error, the wait set is cleaned up.

## Step 10: Parallel Scan (PG 13+)

If implementing parallel-aware scan:

- [ ] `IsForeignScanParallelSafe` is honest about safety (no shared mutable state).
- [ ] DSM callbacks (`EstimateDSMForeignScan`, `InitializeDSMForeignScan`, `ReInitializeDSMForeignScan`, `InitializeWorkerForeignScan`) handle worker setup correctly.
- [ ] `ShutdownForeignScan` releases resources from each worker on the leader's behalf.

## Step 11: EXPLAIN Integration

- [ ] `ExplainForeignScan` shows the remote query (with sensitive data redacted if applicable).
- [ ] `ExplainForeignModify` shows the remote DML.
- [ ] `ExplainDirectModify` shows the direct modification when used.
- [ ] `EXPLAIN (ANALYZE, VERBOSE)` shows actual row count and remote execution stats.

## Step 12: Validator Function

The validator runs on `CREATE`/`ALTER FOREIGN DATA WRAPPER`/`SERVER`/`USER MAPPING`/`FOREIGN TABLE`:

- [ ] Validates option names against an allow-list per object type (`ForeignDataWrapperRelationId`, `ForeignServerRelationId`, etc.).
- [ ] Rejects unknown options with `ereport(ERROR, errcode(ERRCODE_FDW_INVALID_OPTION_NAME), ...)`.
- [ ] Validates option values (port number is integer, host is non-empty, etc.).
- [ ] Reports valid options for the user via `errhint` listing the allowed set.

**Flag as REQUIRED if:** Validator is missing or accepts arbitrary option names — typos silently ignored.

## Step 13: Memory Contexts & Cleanup

- [ ] Per-scan state allocated in a child of `EState`'s context (lives for the scan).
- [ ] Per-connection state in `TopMemoryContext` or a long-lived context, with explicit cleanup on backend exit (`on_proc_exit`).
- [ ] Connection cache (if present) handles backend exit, transaction abort, and `discard all`.
- [ ] No leaked file descriptors or remote cursors on error path.

## Step 14: SQL Wiring

In the extension SQL file:

- [ ] `CREATE FUNCTION <ext>_handler() RETURNS fdw_handler ...`
- [ ] `CREATE FUNCTION <ext>_validator(text[], oid) RETURNS void ...`
- [ ] `CREATE FOREIGN DATA WRAPPER <ext> HANDLER <ext>_handler VALIDATOR <ext>_validator;`
- [ ] Documentation references `CREATE SERVER`, `CREATE USER MAPPING`, `CREATE FOREIGN TABLE` with example options.

## Step 15: Test Coverage

For each callback exercised, verify `sql/` includes:

- [ ] Basic scan: `SELECT * FROM foreign_table;`
- [ ] WHERE pushdown: `EXPLAIN (VERBOSE) SELECT * FROM foreign_table WHERE col = 'x';` — verify remote query
- [ ] Join pushdown (if implemented): EXPLAIN shows pushed join
- [ ] Modify (if implemented): INSERT, UPDATE with WHERE, DELETE with WHERE — verify rows on remote
- [ ] Direct modify (if implemented): EXPLAIN shows direct modify; verify trigger short-circuits it
- [ ] Async (if implemented): `EXPLAIN ANALYZE SELECT FROM (foreign_a UNION ALL foreign_b)` shows async benefit
- [ ] Parallel scan (if implemented): `SET parallel_setup_cost = 0; SET min_parallel_table_scan_size = 0;` and verify parallel plan
- [ ] Validator: invalid option produces expected error
- [ ] Connection failure: server unreachable produces clean error, no leaked state

## Final Report

```
## FDW Review Report

### Callback Inventory
| Callback | Implemented | Notes |
|----------|------------|-------|
| GetForeignRelSize | ✓ | row estimate hardcoded — REQUIRED |
| GetForeignPaths | ✓ | |
| GetForeignPlan | ✓ | |
| BeginForeignScan | ✓ | |
| IterateForeignScan | ✓ | |
| ReScanForeignScan | ✗ | BLOCKER — parameterized scans broken |
| EndForeignScan | ✓ | |
| Modify path | not implemented | OK if read-only |
| Validator | ✗ | REQUIRED — typos silently accepted |

### BLOCKERs
1. [file.c:140] ReScanForeignScan is NULL — NestLoop with foreign table on inner side returns wrong results
   Fix: implement; reset the cursor and re-execute with current parameters

### REQUIRED
1. [file.c:42] GetForeignRelSize uses default rowcount 1000 — planner picks bad join orders
   Fix: query remote source for actual row count or accept option `estimate_size`
2. [file.c:88] WHERE clause concatenated into remote query without quote_literal — SQL injection risk
   Fix: parameterize or quote_literal user-supplied values

### Suggestions
1. Consider implementing async (PG 14+) — significant gain for partitioned foreign tables
```

After presenting the report, call `AskUserQuestion`: walk through BLOCKERs interactively, apply fixes, or just show the report.
