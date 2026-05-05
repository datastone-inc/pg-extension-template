#!/usr/bin/env bash
# overlay.sh — Overlay this template's AI instructions and review skills onto
# an existing PostgreSQL extension repository.
#
# Usage:
#   /path/to/pg-extension-template/overlay.sh --target /path/to/your/repo [--force]
#
# What it does:
#   - Copies AGENTS.md, .specify/memory/constitution.md, .claude/skills/,
#     .claude/commands/, .github/prompts/ into the target repo.
#   - Skips any path already present unless --force is given.
#   - Renames legacy CLAUDE.md and .github/copilot-instructions.md to *.bak so
#     you can merge their content into AGENTS.md, then delete the .bak files.
#   - Reports added / skipped / flagged paths at the end.
#
# It does NOT touch sql/, expected/, Makefile, .control, or C sources, and does
# not modify git history. Run from a clean working tree so you can review the
# overlay's diff afterwards with `git status` and `git diff`.

set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
FORCE=0

usage()
{
  cat <<EOF
Usage: $0 --target <path> [--force]

  --target <path>   Existing extension repo to overlay the template onto.
  --force           Replace existing files rather than skipping them.
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[[ -n "$TARGET" ]] || usage
TARGET="$(cd "$TARGET" && pwd)"

# ── Guards ────────────────────────────────────────────────────────────────────

if [[ "$TARGET" == "$TEMPLATE_DIR" ]]; then
  echo "Error: target is the template itself."
  exit 1
fi

if ! git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: $TARGET is not inside a git repository."
  exit 1
fi

if ! git -C "$TARGET" diff --quiet -- . \
  || ! git -C "$TARGET" diff --cached --quiet -- .; then
  echo "Error: $TARGET has uncommitted changes in its subtree. Commit or stash"
  echo "them first so you can review the overlay's diff cleanly."
  exit 1
fi

# ── Tracking ──────────────────────────────────────────────────────────────────

added=()
skipped=()
flagged=()

copy_if_absent()
{
  local rel="$1"
  local src="$TEMPLATE_DIR/$rel"
  local dst="$TARGET/$rel"

  [[ -e "$src" ]] || return

  if [[ -e "$dst" && $FORCE -eq 0 ]]; then
    skipped+=("$rel")
    return
  fi

  mkdir -p "$(dirname "$dst")"
  rm -rf "$dst"
  cp -R "$src" "$dst"
  added+=("$rel")
}

# ── Detect legacy files ───────────────────────────────────────────────────────

for legacy in "CLAUDE.md" ".github/copilot-instructions.md"; do
  if [[ -f "$TARGET/$legacy" ]]; then
    mv "$TARGET/$legacy" "$TARGET/$legacy.bak"
    flagged+=("$legacy → $legacy.bak (merge into AGENTS.md, then delete the .bak)")
  fi
done

# ── Copy ──────────────────────────────────────────────────────────────────────

copy_if_absent "AGENTS.md"
copy_if_absent ".specify/memory/constitution.md"

# Per-skill: copy each skill subdirectory independently so new skills land in
# repos that already have an older subset.
for skill in "$TEMPLATE_DIR"/.claude/skills/*/; do
  [[ -d "$skill" ]] || continue
  copy_if_absent ".claude/skills/$(basename "$skill")"
done

for f in "$TEMPLATE_DIR"/.claude/commands/*.md; do
  [[ -f "$f" ]] || continue
  copy_if_absent ".claude/commands/$(basename "$f")"
done

for f in "$TEMPLATE_DIR"/.github/prompts/*.prompt.md; do
  [[ -f "$f" ]] || continue
  copy_if_absent ".github/prompts/$(basename "$f")"
done

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Overlay complete. Target: $TARGET"
echo ""

if (( ${#added[@]} )); then
  echo "Added (${#added[@]}):"
  printf '  + %s\n' "${added[@]}"
fi

if (( ${#skipped[@]} )); then
  echo ""
  echo "Skipped (${#skipped[@]}, already present — rerun with --force to replace):"
  printf '  . %s\n' "${skipped[@]}"
fi

if (( ${#flagged[@]} )); then
  echo ""
  echo "Manual action required (${#flagged[@]}):"
  printf '  ! %s\n' "${flagged[@]}"
fi

echo ""
echo "Review with: git -C \"$TARGET\" status && git -C \"$TARGET\" diff"
