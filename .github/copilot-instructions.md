# GitHub Copilot Instructions

## Developer Context

This developer works in C and SQL building PostgreSQL backend extensions, hooks,
callbacks, and PL/pgSQL functions. Code runs inside the PostgreSQL server process.

## Response Guidelines

Start responses with substantive content. Skip agreement phrases ("Certainly!"),
validation ("Great question"), and filler introductions ("I'd be happy to help").

When a request is ambiguous, ask one focused clarifying question before proceeding.

Never fabricate PostgreSQL API details or function signatures. If uncertain,
acknowledge it and suggest where to verify (PostgreSQL source, docs).

## Technical Rules (Always Apply)

- Use `palloc`/`pfree` — `malloc`/`free` are FORBIDDEN in backend C code
- Use `ereport`/`elog` for errors — `printf`/`fprintf` are FORBIDDEN
- Never test against the `postgres` database — use a dedicated test DB
- C++ is FORBIDDEN in PostgreSQL backend extensions
- Validate all user input at system boundaries (SQL injection prevention)
- Index-compatible operators must register appropriate support functions

## Development Workflow

TDD is mandatory. Write the `sql/` test and `expected/` output before implementing:

1. Write failing test in `sql/<feature>.sql`
2. Create `expected/<feature>.out`
3. Confirm failure: `make installcheck`
4. Implement in C
5. Confirm pass: `make installcheck`
6. Run full suite to check for regressions

Extension lifecycle tests (`CREATE EXTENSION` / `ALTER EXTENSION UPDATE` /
`DROP EXTENSION`) are mandatory for every version.

## Reference Files

- `CLAUDE.md` — project commands and layout summary
- `.specify/memory/constitution.md` — full code style, error handling, security, performance
- `.claude/skills/` — specialized review and validation skills

## Skills

<skills>
<skill>
<name>doc-example-tester</name>
<description>Generate and validate regression tests for PostgreSQL extension documentation examples. Ensures all SQL examples in user documentation have corresponding tests in `sql/doc_examples.sql` and that test output matches documented results.</description>
<file>.claude/skills/doc-example-tester/SKILL.md</file>
</skill>
<skill>
<name>code-review</name>
<description>Full code review checklist for PostgreSQL C extensions. Covers memory management, error handling, security (SQL injection, privilege paths), index operator correctness, test coverage gaps, and constitution compliance. Use when reviewing a PR, after implementing a feature, or when asked to review code.</description>
<file>.claude/skills/code-review/SKILL.md</file>
</skill>
<skill>
<name>test-coverage</name>
<description>Analyze test coverage for PostgreSQL C extensions. Identifies exposed SQL functions and operators lacking tests, finds missing boundary/NULL/error/index-usage test cases, and checks doc_examples.sql completeness. Use when asked about test gaps or before marking a feature complete.</description>
<file>.claude/skills/test-coverage/SKILL.md</file>
</skill>
<skill>
<name>pg-hook-audit</name>
<description>Review PostgreSQL hook and callback implementations for correctness and safety. Checks hook chaining (save/restore previous), NULL guards before calling previous hooks, memory context safety, transaction safety, and interrupt handling. Use when adding or modifying any ProcessUtility, executor, planner, or other PG hook.</description>
<file>.claude/skills/pg-hook-audit/SKILL.md</file>
</skill>
<skill>
<name>upgrade-path</name>
<description>Verify PostgreSQL extension upgrade and downgrade SQL scripts are complete and correct. Checks that all objects created/modified in a version have corresponding migration steps, that downgrade scripts restore prior state, and that upgrade paths are tested end-to-end. Use after adding a new extension version.</description>
<file>.claude/skills/upgrade-path/SKILL.md</file>
</skill>
</skills>
