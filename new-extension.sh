#!/usr/bin/env bash
# new-extension.sh — Create a new PostgreSQL extension from this template.
#
# Usage (run from anywhere):
#   /path/to/pg-extension-template/new-extension.sh <extension-name> [parent-dir]
#
# Examples:
#   ~/git/pg-extension-template/new-extension.sh pg_myfeature
#   ~/git/pg-extension-template/new-extension.sh pg_myfeature ~/git
#
# What it does:
#   1. Copies the template into <parent-dir>/<extension-name>
#   2. Detaches git history (clean initial commit)

set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <extension-name> [parent-dir]"
  echo "  extension-name: e.g. pg_myfeature"
  echo "  parent-dir:     where to create the new repo (default: current directory)"
  exit 1
fi

EXTNAME="$1"
PARENT_DIR="${2:-$PWD}"
DEST="$PARENT_DIR/$EXTNAME"

# ── Guard ─────────────────────────────────────────────────────────────────────

if [[ -e "$DEST" ]]; then
  echo "Error: $DEST already exists. Choose a different name or remove it first."
  exit 1
fi

echo "Creating extension: $EXTNAME"
echo "Destination:        $DEST"
echo ""

# ── Copy template (excluding .git and template-only files) ──────────────────

rsync -a \
  --exclude='.git' \
  --exclude='README.md' \
  --exclude='CHANGELOG.md' \
  --exclude='LICENSE' \
  --exclude='project_template.md' \
  --exclude='new-extension.sh' \
  "$TEMPLATE_DIR/" "$DEST/"
echo "Copied template to $DEST"

# ── Fresh git history ─────────────────────────────────────────────────────────

cd "$DEST"
git init
git add -A
git commit -m "chore: initialize $EXTNAME from pg-extension-template"
echo "Initialized clean git repository"
