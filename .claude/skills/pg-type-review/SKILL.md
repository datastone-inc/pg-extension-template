---
name: pg-type-review
description: >
  Review PostgreSQL custom-type implementations for correctness and safety.
  Checks varlena layout, alignment, TOAST handling, in/out/send/recv functions,
  operator class wiring (btree/hash/GiST/GIN), typmod handling, and round-trip
  test coverage. Trigger when adding or modifying a CREATE TYPE, when asked
  to "review my type", "audit custom type", or before merging a feature
  that adds a SQL-level type.
allowed-tools: Read, Grep, Glob, Edit, AskUserQuestion
---

# PostgreSQL Custom Type Review

You are auditing a custom PostgreSQL type implementation. Custom types touch
several risk surfaces simultaneously: memory layout, TOAST, opclass
correctness, and SQL-level wiring. A subtle alignment or detoast bug can
corrupt data silently. Work through each section and produce the report at
the end using the BLOCKER / REQUIRED / SUGGESTION severity model.

## Step 1: Inventory

Find the type's surface area:

```bash
# C side
grep -n 'PG_FUNCTION_INFO_V1' *.c | grep -i '<typename>'
grep -n 'typedef struct.*<TypeStruct>' *.c *.h

# SQL side
grep -nE 'CREATE TYPE|CREATE FUNCTION|CREATE OPERATOR|CREATE OPERATOR CLASS|CREATE CAST' *.sql
```

Build a list of:
- C struct definition
- in / out / send / recv / typmod_in / typmod_out functions
- Constructors and accessors
- Operators (=, <, >, etc.) and their underlying C functions
- Operator classes (btree, hash, GiST, GIN) registered for the type
- Casts to/from the type

## Step 2: Layout & Storage

For the type's C struct:

- [ ] **Fixed-length vs varlena** is consistent between SQL `CREATE TYPE` (`INTERNALLENGTH = N` or `VARIABLE`) and the C struct definition.
- [ ] **Varlena types** start with `char vl_len_[4]` (use the `struct varlena` pattern or the canonical PG idiom: opaque length header followed by data).
- [ ] **`SET_VARSIZE`** is called on every newly-allocated varlena value before return — never returned with uninitialized length header.
- [ ] **`VARSIZE` / `VARDATA`** are used to read; **`VARSIZE_ANY_EXHDR` / `VARDATA_ANY`** are used when the value may be packed (1-byte header).
- [ ] **Alignment** declared in `CREATE TYPE` (`ALIGNMENT = double` etc.) matches the strictest field of the C struct.
- [ ] **`STORAGE`** (`PLAIN` / `EXTENDED` / `EXTERNAL` / `MAIN`) is correct: `PLAIN` for fixed-length, `EXTENDED` for typical varlena, `EXTERNAL` if compression is undesirable.
- [ ] No assumption that `Datum` size equals pointer size (the type works on 32- and 64-bit builds).

**Common bug:** reading a varlena via `VARSIZE` when the caller may have given a packed (short-header) datum. Always `PG_DETOAST_DATUM_PACKED` first if you don't know.

## Step 3: TOAST Detoasting

Every function that takes a varlena argument must detoast it:

- [ ] `PG_DETOAST_DATUM(arg)` — when the function reads but does not modify, and the value won't outlive the call.
- [ ] `PG_DETOAST_DATUM_COPY(arg)` — when the result must outlive the immediate context (e.g., stored in cache).
- [ ] `PG_DETOAST_DATUM_PACKED(arg)` — when the function works with the packed (1-byte header) form to avoid an unnecessary copy.
- [ ] If detoasting via `PG_DETOAST_DATUM`, the result may equal the input (no copy made) — do **not** modify it in place.
- [ ] If a copy was made, `pfree` it before return only if you didn't return it.

**Flag as BLOCKER if:** Varlena argument is read with `VARSIZE` / `VARDATA` without detoasting first. Crashes on TOASTed input.

## Step 4: In / Out Functions

Text representation:

- [ ] **`<typename>_in`** signature: `Datum <typename>_in(PG_FUNCTION_ARGS)` returning the type. Reads `PG_GETARG_CSTRING(0)`.
- [ ] **`<typename>_out`** signature: returns `cstring`. Allocates via `palloc` (caller frees).
- [ ] In-function rejects malformed input with `ereport(ERROR, errcode(ERRCODE_INVALID_TEXT_REPRESENTATION), ...)`.
- [ ] In-function does NOT silently truncate or accept partial input.
- [ ] Round-trip: `out(in(s))` produces a value that re-parses to the same internal form.

## Step 5: Send / Recv Functions (Binary I/O)

Required for `COPY ... BINARY` and binary protocol:

- [ ] **`<typename>_recv`** uses `StringInfo` + `pq_getmsgint` / `pq_getmsgstring` etc. Handles incomplete messages.
- [ ] **`<typename>_send`** uses `StringInfoData buf; pq_begintypsend(&buf); ... PG_RETURN_BYTEA_P(pq_endtypsend(&buf));`.
- [ ] Network byte order: integers via `pq_sendint32` etc., not raw memcpy.
- [ ] Recv validates input — same input-domain checks as the text-`in` function.
- [ ] Round-trip: `send(recv(b))` produces the same bytes.

If send/recv are absent, flag as REQUIRED — `pg_dump --format=binary` and replication won't work cleanly.

## Step 6: Operators & Opclass

For each operator on the type:

- [ ] `CREATE OPERATOR` includes `LEFTARG`, `RIGHTARG`, `PROCEDURE`, and where applicable `COMMUTATOR`, `NEGATOR`, `RESTRICT`, `JOIN`.
- [ ] `=` operator declares `MERGES` and `HASHES` if the type can support hash/merge join.
- [ ] Negator pairs are bidirectional (both `=` and `<>` declare each other as negators).

**btree opclass** (for `ORDER BY`, btree index, merge join):

- [ ] All five strategies present: `<` (1), `<=` (2), `=` (3), `>=` (4), `>` (5).
- [ ] Support function 1: comparison function `<typename>_cmp` returning `int32` (negative / zero / positive — not −1 / 0 / 1).
- [ ] **Comparison total ordering**: for any `a, b, c`: if `cmp(a,b) < 0` and `cmp(b,c) < 0`, then `cmp(a,c) < 0`.
- [ ] NULL handling: btree comparison functions are STRICT — registered with `STRICT` in SQL.

**hash opclass** (for hash index, hash join):

- [ ] Strategy 1 only: `=`.
- [ ] Support function 1: hash function `<typename>_hash` returning `Datum` (an `int32` cast).
- [ ] **Equality consistency**: if `<typename>_eq(a, b)` returns true, then `hash(a) == hash(b)`. Always.
- [ ] If the type has multiple internal representations of equal values (e.g., normalized vs unnormalized), the hash function must canonicalize first.

**Flag as BLOCKER if:** hash and equality are inconsistent. Causes silent wrong results in hash joins.

## Step 7: typmod (if applicable)

If the type accepts modifiers like `mytype(precision)`:

- [ ] `typmodin` parses `cstring[]` into a packed `int32`.
- [ ] `typmodout` formats `int32` back to text representation (with parens).
- [ ] Modifier is applied: in/out and operator behavior actually respects the precision.
- [ ] Cast from `mytype` to `mytype(N)` exists if needed.

## Step 8: Memory Discipline

- [ ] No `malloc` / `free` / `strdup` — only `palloc` family.
- [ ] No assumption that `palloc` returns NULL on failure (it throws).
- [ ] Returned varlena values are allocated in `CurrentMemoryContext` (default for `palloc`) — not in a context that has been or will be deleted.
- [ ] Functions that allocate temporary buffers free them on all paths, including error paths (use PG_TRY/PG_FINALLY or rely on memory-context teardown).

## Step 9: SQL Wiring

Read the `--<ver>.sql` file:

- [ ] `CREATE TYPE` shell first, then `CREATE FUNCTION` for in/out, then `CREATE TYPE <name> (INPUT = ..., OUTPUT = ..., ...)` to complete.
- [ ] All ancillary attributes set: `INTERNALLENGTH`, `ALIGNMENT`, `STORAGE`, `CATEGORY`, `PREFERRED`, `PASSEDBYVALUE` (if fixed-length and ≤ Datum size).
- [ ] `CREATE CAST` declarations for any cast functions; `IMPLICIT` only when the cast is genuinely safe (no truncation, no surprises).
- [ ] `COMMENT ON TYPE` and `COMMENT ON FUNCTION` exist for documentation tools.

## Step 10: Test Coverage

For the type, verify `sql/` includes:

- [ ] Round-trip text I/O: `SELECT 'literal'::mytype::text;`
- [ ] Round-trip binary I/O: `COPY (SELECT 'literal'::mytype) TO ... WITH (FORMAT binary);`
- [ ] All operators: positive case, negative case, NULL on each side
- [ ] Index scans use the index: `EXPLAIN (COSTS OFF) SELECT * FROM t WHERE col = ...;`
- [ ] btree sort: `SELECT * FROM t ORDER BY col` returns correct order
- [ ] Hash join: forced via `SET enable_nestloop = off; SET enable_mergejoin = off;`
- [ ] Invalid input: `SELECT 'bad'::mytype;` with `\set ON_ERROR_STOP off` and expected error captured
- [ ] TOAST: insert a value large enough to be toasted (typically > 2KB), read it back

## Final Report

```
## Custom Type Review Report

### BLOCKERs
1. [file.c:42] mytype_eq does not detoast packed input — crashes on TOASTed values
   Fix: replace VARDATA(arg) with VARDATA_ANY(detoasted_arg) after PG_DETOAST_DATUM_PACKED

### REQUIRED
1. [file.c:88] Hash function and equality function disagree on case sensitivity
   Fix: lowercase before hashing or change equality to be case-sensitive

### Suggestions
1. [file.c:120] Send function could use pq_sendint16 instead of pq_sendint32 for the version field

### Coverage Matrix
| Surface | Implemented | Tested |
|---------|------------|--------|
| in/out  | ✓ | ✓ |
| send/recv | ✓ | ✗ |
| btree opclass | ✓ | partial (no NULL ordering test) |
| hash opclass | ✗ | — |
| TOAST round-trip | N/A | ✗ |
```

After presenting the report, call `AskUserQuestion`: walk through BLOCKERs interactively, apply all fixes, or just show the report.
