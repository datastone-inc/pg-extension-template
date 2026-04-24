# pg-extension-template

GitHub template repository for PostgreSQL backend C extensions.

Provides a consistent, pre-configured starting point for extensions, hooks,
callbacks, and PL/pgSQL — ready for TDD with Claude Code and VS Code Copilot.

## What's Included

| File / Directory | Purpose |
|-----------------|---------|
| `CLAUDE.md` | Claude Code project instructions (commands, layout, skills) |
| `.github/copilot-instructions.md` | VS Code Copilot instructions (same content, Copilot format) |
| `.specify/memory/constitution.md` | Governing code style, error handling, security, performance |
| `.claude/skills/code-review/` | PostgreSQL C extension code review checklist |
| `.claude/skills/test-coverage/` | Find missing test cases and coverage gaps |
| `.claude/skills/pg-hook-audit/` | Review PG hooks and callbacks for correctness |
| `.claude/skills/upgrade-path/` | Verify upgrade and downgrade SQL migration scripts |
| `.claude/skills/doc-example-tester/` | Validate SQL examples in documentation |
| `sql/extension_lifecycle.sql` | Mandatory CREATE/ALTER/DROP regression tests |
| `sql/doc_examples.sql` | Documentation example regression tests |
| `expected/` | Expected pg_regress output |
| `new-extension.sh` | Create a new extension repo from a local copy of this template |
| `project_template.md` | Repository structure and doc templates |

## Quick Start

Clone this template once, then create new extension repos from it:

```bash
~/git/pg-extension-template/new-extension.sh pg_myfeature
# or into a specific directory:
~/git/pg-extension-template/new-extension.sh pg_myfeature ~/git
```

This copies only the AI instructions, skills, and test scaffolding,
excludes template-only files (README, CHANGELOG, LICENSE), and initializes a
clean git history.

## Requirements

- PostgreSQL 12+ with development headers (`postgresql-server-dev-XX` or Xcode CLT on macOS)
- `pg_config` on `PATH`

## Agentic AI Usage

### Claude Code

`CLAUDE.md` is read automatically. Invoke skills with natural language:

```
Review my code changes for correctness
Check test coverage
Audit the hook I just added
Verify the upgrade script is complete
```

### VS Code Copilot

`.github/copilot-instructions.md` is loaded automatically. Skills are declared
in the `<skills>` block and loaded on demand.

### speckit

This template is compatible with [speckit](https://github.com/datastone/speckit).
Run `speckit init` in the repo root. The constitution at
`.specify/memory/constitution.md` is picked up automatically.

## Skills Reference

### `code-review`

Full static review of PostgreSQL C extension code. Checks memory, errors,
security, index operator completeness, hook correctness, and constitution compliance.

### `test-coverage`

Analyzes coverage across all SQL-exposed functions. Reports missing NULL, boundary,
error, and index-usage test cases. Can generate skeleton test files.

### `pg-hook-audit`

Dedicated review for any code that registers PostgreSQL hooks (executor, planner,
ProcessUtility, authentication, etc.). Enforces the save/NULL-check/call-chain/
restore pattern.

### `upgrade-path`

Verifies that upgrade scripts (`ext--A--B.sql`) and downgrade scripts
(`ext--B--A.sql`) cover all objects created, modified, or removed between versions.
Generates test SQL for ALTER EXTENSION UPDATE cycles.

### `doc-example-tester`

Finds every `-- Example:` block in README.md and `doc/*.md` and ensures
`sql/doc_examples.sql` has a matching, passing test.

## Development Workflow

See `CLAUDE.md` for commands. The mandatory cycle is:

1. Write failing test in `sql/` and `expected/`
2. `make installcheck` — confirm failure
3. Implement in C
4. `make installcheck` — confirm passing
5. Run `code-review` skill before merging

## License

MIT — see [LICENSE](LICENSE)
