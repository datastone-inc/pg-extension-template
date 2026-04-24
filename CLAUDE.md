# PostgreSQL Backend Extension Development

## Project Context

This is a PostgreSQL backend C extension. All C code runs inside the PostgreSQL
server process. Correctness and safety are paramount: a crash here brings down the
entire database.

## Critical Rules — Never Violate

- **Memory**: Use `palloc`/`pfree` exclusively. `malloc`/`free` are FORBIDDEN.
- **Language**: C only. C++ is FORBIDDEN in backend code.
- **Errors**: Use `ereport`/`elog`. `printf`/`fprintf` are FORBIDDEN.
- **Test DB**: Never test against the `postgres` database. Use `smokey`.
- **TDD**: Write the regression test BEFORE implementing any feature.
- **Input validation**: Validate all user-supplied input at system boundaries.

## Build & Test Commands

```bash
make                          # Compile the extension
sudo make install             # Install into PostgreSQL
make installcheck             # Run pg_regress test suite
make clean                    # Remove build artifacts

# Test database
createdb smokey
psql -d smokey -c "CREATE EXTENSION myextension;"
psql -d smokey       # Connect for manual testing
```

## TDD Workflow (Mandatory)

1. Write failing test in `sql/<feature>.sql` with expected output in `expected/`
2. Run `make installcheck` — confirm it FAILS
3. Implement the feature in C
4. Run `make installcheck` — confirm it PASSES
5. Run full suite to catch regressions
6. Refactor under green tests

Test files must cover: normal cases, boundary values, NULL handling, error
conditions (with expected messages), index usage (`EXPLAIN` output), and extension
lifecycle (`CREATE`/`ALTER EXTENSION UPDATE`/`DROP EXTENSION`).

## Project Layout

``` code
ext/                       # Root of the extension
sql/                       # pg_regress test scripts
expected/                  # Expected pg_regress output
results/                   # Actual output (git-ignored)
doc/                       # User documentation
specs/                     # speckit specs, plans, tasks
.specify/memory/constitution.md   # Full code style & architecture rules
.claude/skills/            # Specialized agent skills
.claude/plans/             # Claude Code /plan outputs
```

## Code Style (Summary)

- **C**: K&R style, 2-space indent, camelCase for functions/variables
- **SQL**: UPPERCASE keywords, snake_case identifiers
- Every file needs a copyright/doxygen header (see constitution for template)
- Every exposed function needs a full doxygen doc comment

Full style rules, error handling patterns, security requirements, and performance
guidelines: `.specify/memory/constitution.md`

## Available Skills

Invoke these for specialized review and validation tasks:

| Skill | Purpose |
|-------|---------|
| `code-review` | Full PostgreSQL C extension code review |
| `test-coverage` | Find missing test cases and coverage gaps |
| `pg-hook-audit` | Review hooks and callbacks for correctness |
| `upgrade-path` | Verify upgrade and downgrade SQL scripts |
| `doc-example-tester` | Validate SQL examples in documentation |

Skills are in `.claude/skills/`.

## speckit Integration

This repo uses [speckit](https://github.com/datastone/speckit) for structured
feature development:

- `speckit.specify` — turn a feature description into a spec
- `speckit.plan` — generate an implementation plan
- `speckit.tasks` — generate ordered task list
- `speckit.implement` — execute tasks

Constitution (`.specify/memory/constitution.md`) governs all code style and
architecture decisions and takes precedence over these instructions in case of
conflict.
