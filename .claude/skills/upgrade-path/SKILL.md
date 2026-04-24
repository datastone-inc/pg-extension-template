---
name: upgrade-path
description: >
  Verify PostgreSQL extension upgrade and downgrade SQL scripts are complete and
  correct. Checks that all objects created/modified in a new version have
  corresponding migration steps, that downgrade scripts restore prior state,
  and that upgrade paths can be tested end-to-end. Trigger when adding a new
  extension version, when asked to "verify upgrade", "check migration scripts",
  "test upgrade path", or "verify downgrade".
allowed-tools: Read, Grep, Glob, Bash(git:*), Bash(psql:*), AskUserQuestion
---

# Extension Upgrade / Downgrade Path Verification

You are verifying that a PostgreSQL extension's upgrade and downgrade scripts are
complete, correct, and testable. A broken migration script can corrupt a production
database on `ALTER EXTENSION UPDATE`.

## Step 1: Identify Version Pairs

Read the `.control` file to get the current `default_version`. Then:

```bash
ls -1 myextension--*--*.sql 2>/dev/null | sort
```

Build a version graph:
```
1.0.0  ->  1.1.0  (upgrade script: myextension--1.0.0--1.1.0.sql)
1.1.0  ->  1.0.0  (downgrade script: myextension--1.1.0--1.0.0.sql, if present)
```

Identify:
- Latest version (from control file `default_version`)
- All intermediate versions
- Which direction (upgrade / downgrade) each script covers

## Step 2: Collect the Object Inventory

**What the base version creates** (from `myextension--1.0.0.sql`):

```bash
grep -E 'CREATE (FUNCTION|PROCEDURE|TYPE|OPERATOR|OPERATOR CLASS|OPERATOR FAMILY|TABLE|SEQUENCE|VIEW|INDEX|EXTENSION|CAST|AGGREGATE|DOMAIN|SCHEMA)' myextension--1.0.0.sql
```

**What each subsequent version adds/modifies/removes** (from diff between versions
using git, or by reading the upgrade scripts):

For each upgrade script `myextension--A--B.sql`, list:
- Objects CREATED (new in version B)
- Objects ALTERED (modified in version B)  
- Objects DROPPED (removed in version B)

## Step 3: Verify Upgrade Scripts

For each upgrade script (A → B):

### 3a. New objects in B are CREATED in A→B script

For every object that exists in version B but not A:
- [ ] `CREATE FUNCTION` / `CREATE OPERATOR` / `CREATE TYPE` etc. present
- [ ] New columns added to tables: `ALTER TABLE ... ADD COLUMN`
- [ ] New indexes created
- [ ] New GUC parameters registered

**Flag as BLOCKER if:** An object present in the install SQL is absent from the
upgrade script — `ALTER EXTENSION UPDATE` will leave the database without it.

### 3b. Modified objects in B are ALTERED in A→B script

- [ ] Functions with changed signatures: dropped and re-created (PG requires this)
- [ ] Functions with changed bodies only: `CREATE OR REPLACE FUNCTION`
- [ ] Operators changed: old dropped, new created
- [ ] Types changed: migration handled (PG doesn't allow ALTER TYPE lightly)

### 3c. Removed objects are DROPPED in A→B script

- [ ] `DROP FUNCTION IF EXISTS` for removed functions
- [ ] `DROP OPERATOR IF EXISTS` for removed operators
- [ ] `DROP TYPE IF EXISTS` for removed types
- [ ] `IF EXISTS` used on all DROP statements (idempotency)

### 3d. Upgrade script has proper header

- [ ] Copyright/SPDX header
- [ ] psql guard: `\echo Use "ALTER EXTENSION ... UPDATE TO 'B'" \quit`
- [ ] Comment indicating which version pair this covers

## Step 4: Verify Downgrade Scripts

For each downgrade script (B → A), if it exists:

### 4a. Objects added in B are DROPPED

Every object created in the B→A upgrade direction is dropped:
- [ ] All new functions dropped
- [ ] All new types dropped
- [ ] New columns removed: `ALTER TABLE ... DROP COLUMN`
- [ ] New indexes dropped

### 4b. Objects modified in B are RESTORED

- [ ] Modified functions restored to version-A signatures and bodies
- [ ] Modified operators restored

### 4c. Objects removed in B are RE-CREATED

- [ ] Functions removed in B→A are re-created with version-A definition

### 4d. Downgrade leaves database identical to a fresh A install

This is the gold standard. After downgrade, the schema should match
`myextension--A.sql` exactly. Verify by comparing object lists.

**Note:** If downgrade scripts are intentionally not supported, document this
explicitly in the control file or README and flag the missing scripts as
KNOWN LIMITATION rather than BLOCKER.

## Step 5: Check for Skipped Versions

If versions are A → B → C, verify:
- [ ] Direct A → C upgrade script exists OR the multi-hop path A → B → C works
- [ ] PostgreSQL will follow the upgrade path automatically if a direct script
  is missing (it chains through intermediate versions)
- [ ] No version is an island with no path to the current version

## Step 6: Test Execution Plan

For each version pair, generate a test script to go in `sql/extension_lifecycle.sql`
or a dedicated `sql/upgrade_<A>_to_<B>.sql`:

```sql
-- Test upgrade from A to B
DROP EXTENSION IF EXISTS myextension;
CREATE EXTENSION myextension VERSION 'A';

-- Verify version-A state
SELECT extversion FROM pg_extension WHERE extname = 'myextension';
-- Insert test data using version-A API
SELECT myext_func_v1('test');

-- Execute upgrade
ALTER EXTENSION myextension UPDATE TO 'B';

-- Verify version-B state
SELECT extversion FROM pg_extension WHERE extname = 'myextension';
-- Verify new API works
SELECT myext_new_func_in_b('test');
-- Verify old API still works (backward-compatible change)
SELECT myext_func_v1('test');

-- Test downgrade (if supported)
ALTER EXTENSION myextension UPDATE TO 'A';
SELECT extversion FROM pg_extension WHERE extname = 'myextension';
SELECT myext_func_v1('test');

-- Clean up
DROP EXTENSION myextension;
```

Check that this test exists or offer to generate it.

## Step 7: Identify Common Mistakes

Scan each migration script for these patterns:

- [ ] `CREATE FUNCTION` without `IF NOT EXISTS` (not supported in PG < 14,
  fails on re-run) — prefer `CREATE OR REPLACE FUNCTION`
- [ ] `DROP FUNCTION name` without full signature — fails if overloaded versions exist
- [ ] `ALTER TABLE ... ADD COLUMN ... NOT NULL` without a DEFAULT —
  fails on non-empty tables in PG < 11
- [ ] Type changes that require `USING` clause: `ALTER TABLE ... ALTER COLUMN ...
  TYPE new_type USING expression`
- [ ] Missing `CASCADE` when dropping a type or function that other objects depend on
- [ ] Hardcoded schema names (`public.myext_func`) that break with `relocatable = true`

## Final Report

```
## Upgrade Path Report

### Version Graph
1.0.0  →  1.1.0: ✓ script exists
1.1.0  →  1.0.0: ✗ downgrade script missing (REQUIRED if downgrades supported)
1.1.0  →  1.2.0: ✓ script exists

### BLOCKERs
1. myextension--1.0.0--1.1.0.sql: new function myext_new_func() not in script
   Fix: add CREATE FUNCTION myext_new_func(...) to the upgrade script

### REQUIRED
1. No test in sql/ for 1.0.0 → 1.1.0 upgrade path

### KNOWN LIMITATIONS (if applicable)
1. Downgrade from 1.1.0 → 1.0.0 not supported (type change is irreversible)

### Object Coverage Matrix
| Object | In 1.0.0 | In 1.1.0 | In upgrade script | In downgrade script |
|--------|----------|----------|-------------------|---------------------|
| myext_func() | ✓ | ✓ | N/A (unchanged) | N/A |
| myext_new_func() | ✗ | ✓ | ✗ BLOCKER | — |
```

Call `AskUserQuestion` after the report: generate missing migration steps,
generate test SQL, or just show the report.
