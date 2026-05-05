# AGENTS.md

PostgreSQL backend C extension — code runs in-process; a crash kills the server.
Hard rules: use palloc/pfree (never malloc/free), ereport/elog (never printf), C only — no C++.
Style: Allman braces, 4-space indent, no tabs. Internal C symbols camelCase; SQL-callable C functions snake_case.
TDD with pg_regress: write the failing test in sql/ and expected/ before implementing in C.
See .specify/memory/constitution.md for full style/security/perf rules and .claude/skills/ for review skills.
