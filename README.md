# pg-extension-template

GitHub template repository for PostgreSQL backend C extensions.

A consistent, pre-configured starting point for extensions, hooks, callbacks,
and PL/pgSQL — ready for TDD with both Claude Code and VS Code Copilot.

## What's Included

| File / Directory | Purpose |
|-----------------|---------|
| `AGENTS.md` | Project rules read on every turn by both Claude Code and VS Code Copilot |
| `.specify/memory/constitution.md` | Full code style, error handling, security, performance |
| `.claude/skills/` | Auto-invoked review skills (Claude Code) |
| `.claude/commands/` | Slash commands for explicit invocation in Claude Code |
| `.github/prompts/` | Equivalent prompt files for VS Code Copilot |
| `new-extension.sh` | Create a new extension repo from this template |
| `overlay.sh` | Overlay AI instructions and skills onto an existing repo |
| `project_template.md` | Repository structure and doc templates |

## Usage

Two modes.

**Bootstrap a new extension repo:**

```bash
~/git/pg-extension-template/new-extension.sh pg_myfeature
# or into a specific directory:
~/git/pg-extension-template/new-extension.sh pg_myfeature ~/git
```

Copies the AI instructions, skills, and test scaffolding into a fresh repo
with clean git history. Excludes template-only files (README, CHANGELOG,
LICENSE).

**Overlay onto an existing extension repo:**

```bash
~/git/pg-extension-template/overlay.sh --target ~/git/your-existing-extension
```

Copies `AGENTS.md`, `.specify/memory/constitution.md`, `.claude/skills/`,
`.claude/commands/`, and `.github/prompts/` into the target repo. Files already
present are skipped (rerun with `--force` to replace). Legacy `CLAUDE.md` and
`.github/copilot-instructions.md` are renamed to `*.bak` so you can merge their
content into `AGENTS.md` before deleting them. Requires a clean git working
tree in the target so you can review the diff afterwards.

The template intentionally provides only AI instructions and skills — no
Makefile, `.control`, C stubs, or test scaffolds. Those belong in the
extension itself, since the template is also used to overlay onto existing
codebases. For a complete worked example with a Makefile, control file,
sources, and tests, see `pg_helloworld` (forthcoming).

## Requirements

- PostgreSQL 14+ with development headers (`postgresql-server-dev-XX` or Xcode CLT on macOS)
- `pg_config` on `PATH`

## Why AGENTS.md Is So Short

Every line of AI instructions is context cost on every turn. Add a rule
only when you've seen a specific failure it would have prevented. The
depth lives in `.specify/memory/constitution.md`, read on demand.

## Personal Preferences (Optional)

Communication style is a per-developer choice, not a project rule. Put it
in `~/.claude/CLAUDE.md` — Claude Code merges it with `AGENTS.md`
automatically. Starter:

```markdown
Be terse. Skip filler.
Be constructively critical: flag concerns directly, don't hedge.
```

For VS Code Copilot, use `github.copilot.chat.codeGeneration.instructions`
in user-scope `settings.json`.

## Skills and Slash Commands

Skills auto-invoke when you describe a task that matches their description
(e.g., "review my changes" triggers `code-review`). For explicit invocation,
each skill has a slash command in both tools.

| Purpose | Skill | Claude Code | VS Code Copilot |
|---------|-------|------------|-----------------|
| Full code review | `code-review` | `/code-review` | `code-review.prompt.md` |
| Hook & callback audit | `pg-hook-audit` | `/audit-hooks` | `audit-hooks.prompt.md` |
| Test coverage gaps | `test-coverage` | `/check-coverage` | `check-coverage.prompt.md` |
| Upgrade/downgrade scripts | `upgrade-path` | `/verify-upgrade` | `verify-upgrade.prompt.md` |
| Doc example tests | `doc-example-tester` | `/test-doc-examples` | `test-doc-examples.prompt.md` |
| FDW review | `fdw-review` | `/fdw-review` | `fdw-review.prompt.md` |
| Custom type review | `pg-type-review` | `/type-review` | `type-review.prompt.md` |

### Skill Summaries

**`code-review`** — Full static review. Memory, errors, security, index
operator completeness, hook correctness, constitution compliance.

**`test-coverage`** — Coverage analysis across SQL-exposed functions.
Reports missing NULL, boundary, error, and index-usage tests.

**`pg-hook-audit`** — Dedicated audit for code that registers PostgreSQL
hooks. Enforces the save / NULL-check / call-chain / restore pattern.

**`upgrade-path`** — Verifies upgrade and downgrade SQL scripts cover all
objects created, modified, or removed between versions.

**`doc-example-tester`** — Ensures every `-- Example:` block in README.md
and `doc/*.md` has a matching, passing test in `sql/doc_examples.sql`.

**`fdw-review`** — Audits Foreign Data Wrappers: callback set, cost estimation,
WHERE / join / upper-rel pushdown, async and parallel scan, validator coverage,
and `CREATE FOREIGN-*` SQL wiring.

**`pg-type-review`** — Audits custom types: varlena layout, alignment, TOAST
handling, in/out/send/recv, operator-class wiring (btree/hash/GiST/GIN),
typmod handling, and round-trip coverage.

## speckit Integration

This template is compatible with [speckit](https://github.com/datastone/speckit).
Run `speckit init` in the repo root. The constitution at
`.specify/memory/constitution.md` is picked up automatically.

## Development Workflow

The mandatory cycle (also stated in `AGENTS.md`):

1. Write failing test in `sql/` and `expected/`
2. `make installcheck` — confirm failure
3. Implement in C
4. `make installcheck` — confirm passing
5. Run `/code-review` (or describe what you changed and let `code-review` auto-invoke) before merging

Build commands:

```bash
make                          # Compile the extension
sudo make install             # Install into PostgreSQL
make installcheck             # Run pg_regress test suite
make clean                    # Remove build artifacts
```

Use a dedicated test database — never test against `postgres`.

## License

MIT — see [LICENSE](LICENSE)
