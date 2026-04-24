# Project Template

> **Location**: Repository root

Templates for extension repository documentation for spec kit repos (specify init ...)
All SQL examples in documentation MUST have corresponding regression tests in `sql/doc_examples.sql`.

## Repository Structure

```
myextension/
├── .specify/
│   └── memory/
│       └── constitution.md    # Governing principles
├── assets/
│   └── datastone-logo.svg
├── code_review_checklist.md
├── project_template.md
├── LICENSE
├── README.md
├── CHANGELOG.md
├── doc/
│   └── user-guide.md
├── sql/                       # pg_regress sql tests
│   └── doc_examples.sql       # documentation examples tests
├── expected/
│   └── doc_examples.out
└── ...
```

## README.md

```markdown
# Extension Name

One-line description of what this extension provides.

## Overview

Explanation of extension purpose and capabilities. What problems does it
solve? Who is it for?

## Installation

Requires PostgreSQL 12+ with development headers.

    make && sudo make install

## Quick Start

    CREATE EXTENSION myextension;
    SELECT my_function('example');

## Documentation

See [doc/user-guide.md](doc/user-guide.md) for detailed usage and API reference.

---

[MIT License](LICENSE) | [Changelog](CHANGELOG.md)
```

For extensions with extensive APIs, add a link to `doc/operator-reference.md`.

## CHANGELOG.md

Follow [Keep a Changelog](https://keepachangelog.com/) format with semantic versioning.

```markdown
# Changelog

## [Unreleased]

## [1.0.0] - 2026-01-07

### Added
- Initial release with core functionality
```

Categories: Added, Changed, Deprecated, Removed, Fixed, Security.

## doc/ Folder

Start minimal, expand as needed:

| File | When to create |
|------|----------------|
| `user-guide.md` | Always - primary documentation |
| `operator-reference.md` | Many operators/functions requiring detailed reference |
| `migration.md` | Breaking changes between major versions |

### user-guide.md

```markdown
# User Guide

## Common Operations

### Operation Name

Explanation with example:

    SELECT operation_example();

## Configuration

GUC parameters or setup requirements, if any.

## Troubleshooting

Common issues and solutions.
```

## Markdown Standards

- Code blocks specify language: ```sql, ```c, ```bash
- Heading hierarchy: # title, ## sections, ### subsections
- Tables use GFM pipe format
- Indented code blocks (4 spaces) acceptable for brief examples

---

**Version**: 1.0.0 | **Last Updated**: 2026-01-07