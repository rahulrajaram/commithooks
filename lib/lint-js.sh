#!/usr/bin/env bash
# commithooks/lib/lint-js.sh — JS/TS project checks
# Usage: source "$COMMITHOOKS_DIR/lib/lint-js.sh"

if [ "${_COMMITHOOKS_LINT_JS_LOADED:-}" = "1" ]; then
  return 0
fi
_COMMITHOOKS_LINT_JS_LOADED=1

# Run oxlint on staged JS/TS files (if available).
commithooks_js_oxlint() {
  commithooks_require_cmd "oxlint" || return 0
  local files
  files="$(commithooks_staged_files | grep -E '\.(js|jsx|ts|tsx|mjs|cjs)$' || true)"
  if [ -z "$files" ]; then
    return 0
  fi
  commithooks_green "[js] Running oxlint..."
  # shellcheck disable=SC2086
  oxlint $files
}

# Run eslint on staged JS/TS files (if available).
commithooks_js_eslint() {
  commithooks_require_cmd "eslint" || return 0
  local files
  files="$(commithooks_staged_files | grep -E '\.(js|jsx|ts|tsx|mjs|cjs)$' || true)"
  if [ -z "$files" ]; then
    return 0
  fi
  commithooks_green "[js] Running eslint..."
  # shellcheck disable=SC2086
  eslint $files
}

# Run a configurable typecheck command.
# Set COMMITHOOKS_TYPECHECK_CMD (default: "npx tsc --noEmit").
commithooks_js_typecheck() {
  local cmd="${COMMITHOOKS_TYPECHECK_CMD:-npx tsc --noEmit}"
  local first_word
  first_word="$(echo "$cmd" | awk '{print $1}')"
  commithooks_require_cmd "$first_word" || return 0
  commithooks_green "[js] Running typecheck..."
  eval "$cmd"
}
