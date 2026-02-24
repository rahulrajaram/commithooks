#!/usr/bin/env bash
# commithooks/lib/common.sh — Shared utilities for commithooks
# Usage: source "$COMMITHOOKS_DIR/lib/common.sh"

# Guard against double-sourcing
if [ "${_COMMITHOOKS_COMMON_LOADED:-}" = "1" ]; then
  return 0
fi
_COMMITHOOKS_COMMON_LOADED=1

commithooks_red() {
  printf '\033[0;31m%s\033[0m\n' "$*" >&2
}

commithooks_green() {
  printf '\033[0;32m%s\033[0m\n' "$*" >&2
}

commithooks_warn() {
  printf '\033[0;33m%s\033[0m\n' "$*" >&2
}

# List staged files, optionally filtered by extension.
# Usage: commithooks_staged_files "py"  or  commithooks_staged_files
commithooks_staged_files() {
  local ext="${1:-}"
  if [ -n "$ext" ]; then
    git diff --cached --name-only --diff-filter=ACM | grep -E "\.${ext}$" || true
  else
    git diff --cached --name-only --diff-filter=ACM
  fi
}

# Check if a command exists. If not, print a warning and return 1.
# Usage: commithooks_require_cmd "ruff" || return 0
commithooks_require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    commithooks_warn "[commithooks] '$cmd' not found, skipping."
    return 1
  fi
}

# Detect rebase/cherry-pick and skip if active.
# Usage: commithooks_skip_during_rebase && exit 0
commithooks_skip_during_rebase() {
  local git_dir
  git_dir="$(git rev-parse --git-dir 2>/dev/null)" || return 1
  if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ] || [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
    return 0
  fi
  return 1
}
