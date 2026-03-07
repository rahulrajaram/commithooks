#!/usr/bin/env bash
# commithooks/lib/lint-haskell.sh — Haskell project checks
# Usage: source "$COMMITHOOKS_DIR/lib/lint-haskell.sh"

if [ "${_COMMITHOOKS_LINT_HASKELL_LOADED:-}" = "1" ]; then
  return 0
fi
_COMMITHOOKS_LINT_HASKELL_LOADED=1

# Run hlint on staged Haskell files (if available).
commithooks_haskell_hlint() {
  commithooks_require_cmd "hlint" || return 0

  local files
  files="$(commithooks_staged_files | grep -E '\.(hs|lhs)$' || true)"
  if [ -z "$files" ]; then
    return 0
  fi

  commithooks_green "[haskell] Running hlint..."
  # shellcheck disable=SC2086
  hlint $files
}
