---
name: doc-example-tester
description: Generate and validate regression tests for PostgreSQL extension documentation examples. Ensures all SQL examples in user documentation have corresponding tests in `sql/doc_examples.sql` and that test output matches documented results.
---

# doc-example-tester Skill

## Purpose

Generate and validate regression tests for PostgreSQL extension documentation examples. Ensures:
1. Every `-- Example:` in docs has a test in sql/doc_examples.sql
2. Test SQL matches documented SQL
3. Actual output matches documented output

## When to Use

- User says "generate doc example tests", "update doc_examples.sql", "verify doc examples"
- When documentation SQL examples are added or modified
- To validate that documented output matches actual test results
**CRITICAL:** This skill has mandatory reporting requirements. You MUST:
1. Always present Phase 1 Step 5 Summary with exact counts
2. Always do Phase 2 Interactive Triage if mismatches found
3. Never make changes without user approval in Phase 2
**IMPORTANT:** This skill involves complex multi-step validation. When invoked, use `runSubagent` tool to execute the workflow in a dedicated agent. This ensures proper step tracking and prevents skipped validation.

## Critical Validation Requirement

**Never skip validation steps.** You MUST:
1. Count examples found in documentation
2. Count tests generated/verified
3. Count tests executed
4. Count examples where output was compared
5. **NEW: Validate row counts match exactly**
6. **NEW: Log all comparison details for debugging**

**All counts MUST match.** Report any discrepancies immediately.

**MANDATORY REPORTING:** Always present Step 5 Summary in exact format:
```
✓ Step 1: Found N examples
✓ Step 2: N tests exist (M generated, P unchanged)
✓ Step 3: N tests executed (P passed, F failed)
✓ Step 4: N examples validated (M matches, X mismatches)
✓ All counts match: Yes/No (N=N=N=N)
```

**MANDATORY PHASE 2:** If ANY mismatches found, MUST proceed to Phase 2 Interactive Triage. Do NOT make changes without user approval.

**NEW FAIL-SAFE:** If validation logic cannot clearly parse expected vs actual output, ALWAYS flag for manual review rather than assuming success.

If you find yourself reporting success without validating output, STOP and complete validation first.

## Pattern Specifications

**Documentation Example (required eyecatcher):**
```markdown
```sql
-- Example: <description>
[-- Without extension (stock PostgreSQL):]
<SQL statements>
[-- <inline expected output>]
```
```

**Test Block Header (generated):**
```sql
-- ============================================================================
-- <file>: <description> (~line <N>)
-- ============================================================================
```

**Matching:** Examples and tests are matched by **file + line number** (±5 tolerance), NOT description.

## Workflow

### Phase 1: Bulk Discovery & Validation

**Step 1: Parse Documentation** (use read_file or grep)
- Find all `-- Example:` markers in README.md and doc/*.md
- Extract: file, line number, description, SQL, expected output
- Report: "Found N examples"

**Step 2: Verify/Generate Tests**
- Check sql/doc_examples.sql for matching tests (file + line ±5)
- Generate missing tests if needed
- Report: "N tests exist (M generated, P unchanged)"

**Step 3: Run Tests**
```bash
make installcheck REGRESS=doc_examples
```
- Report: "N tests executed (P passed, F failed)"

**Step 4: Validate Output** (MANDATORY - never skip)
- For EACH example, compare documented output vs actual output in results/doc_examples.out
- **STRICT VALIDATION REQUIREMENTS:**
  1. **Extract documented output**: All lines starting with `-- ` in markdown after SQL query
  2. **Parse row count**: Extract `(N rows)` from documented output 
  3. **Parse data rows**: Extract table data from documented `-- ` comments
  4. **Find actual output**: Locate corresponding SQL in results/doc_examples.out
  5. **Compare row counts**: Documented `(N rows)` MUST match actual row count
  6. **Compare data**: Each documented data row must match actual output row
  7. **Column headers**: Documented column headers must match actual headers
- **FAIL-SAFE RULE**: If parsing is ambiguous or unclear, FLAG for manual review
- **LOGGING**: For each comparison, log: "Doc shows N rows, actual shows M rows"
- Report: "N examples validated (M matches, X mismatches)"

**Step 5: Summary**
```
✓ Step 1: Found N examples
✓ Step 2: N tests exist
✓ Step 3: N tests executed (P passed, F failed)
✓ Step 4: N examples validated (M matches, X mismatches)
✓ All counts match: Yes/No (N=N=N=N)
```

If mismatches found → Phase 2

### Phase 2: Interactive Triage

**MANDATORY when mismatches found.** For each mismatch, show:
- Documentation location and SQL
- Documented expected output (with row count)
- Actual test output (with row count)
- **Detailed comparison**: Row-by-row diff showing exactly what differs
- **Root cause analysis**: "Doc shows N rows but actual shows M rows" or "Row X differs: doc='...' actual='...'"
- Side-by-side diff

**REQUIRED USER INTERACTION:** Present options and WAIT for user choice:
- **[F]ix documentation** - Update markdown with correct output
- **[A]ccept results** - Documentation outdated, code is correct (update both doc and expected/)
- **[B]ug in code** - Add TODO comments, leave failing
- **[S]kip** - Add TODO comments, return later

**DO NOT make changes without user approval.**

## Quick Reference

**Find examples:**
```bash
grep -n "^-- Example:" README.md doc/*.md
```

**Find tests:**
```bash
grep -n "^-- README.md:" sql/doc_examples.sql | grep "~line"
```

**Run tests:**
```bash
make installcheck REGRESS=doc_examples
```

**Compare output:** Read documented output from markdown `-- ` lines and compare to results/doc_examples.out

**CRITICAL DEBUGGING:** When validation reports success but user finds mismatches, the skill logic failed. Always log:
```
Example X: Doc shows "(N rows)" vs Actual shows "(M rows)" 
Example X: Doc row 1: "-- Alice | Widget" vs Actual row 1: "Alice | Widget"
Example X: MISMATCH - Row counts differ: N ≠ M
```

## Success Criteria

- All counts match (examples = tests = executed = validated)
- All output matches OR mismatches explained with [F]ix/[A]ccept/[B]ug/[S]kip
- No validation steps skipped

