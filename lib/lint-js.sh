#!/usr/bin/env bash
# commithooks/lib/lint-js.sh — JS/TS project checks
# Usage: source "$COMMITHOOKS_DIR/lib/lint-js.sh"

if [ "${_COMMITHOOKS_LINT_JS_LOADED:-}" = "1" ]; then
  return 0
fi
_COMMITHOOKS_LINT_JS_LOADED=1

_commithooks_js_resolve_tool() {
  local tool="$1"
  if command -v "$tool" &>/dev/null; then
    echo "$tool"
    return 0
  fi
  if [ -x "node_modules/.bin/$tool" ]; then
    echo "node_modules/.bin/$tool"
    return 0
  fi
  return 1
}

# Run oxlint on staged JS/TS files (if available).
commithooks_js_oxlint() {
  local runner
  if ! runner="$(_commithooks_js_resolve_tool "oxlint")"; then
    commithooks_warn "[js] 'oxlint' not found, skipping."
    return 0
  fi
  local files
  files="$(commithooks_staged_files | grep -E '\.(js|jsx|ts|tsx|mjs|cjs)$' || true)"
  if [ -z "$files" ]; then
    return 0
  fi
  commithooks_green "[js] Running oxlint..."
  # shellcheck disable=SC2086
  "$runner" $files
}

# Run eslint on staged JS/TS files (if available).
commithooks_js_eslint() {
  local runner
  if ! runner="$(_commithooks_js_resolve_tool "eslint")"; then
    commithooks_warn "[js] 'eslint' not found, skipping."
    return 0
  fi
  local files
  files="$(commithooks_staged_files | grep -E '\.(js|jsx|ts|tsx|mjs|cjs)$' || true)"
  if [ -z "$files" ]; then
    return 0
  fi
  commithooks_green "[js] Running eslint..."
  # shellcheck disable=SC2086
  "$runner" $files
}

# Run a configurable typecheck command.
# Set COMMITHOOKS_TYPECHECK_CMD (default: "npx tsc --noEmit").
commithooks_js_typecheck() {
  local files
  files="$(commithooks_staged_files | grep -E '\.(ts|tsx)$' || true)"
  if [ -z "$files" ]; then
    return 0
  fi

  local cmd="${COMMITHOOKS_TYPECHECK_CMD:-npx tsc --noEmit}"
  local first_word
  first_word="$(echo "$cmd" | awk '{print $1}')"
  if ! commithooks_require_cmd "$first_word"; then
    if [ "$cmd" = "npx tsc --noEmit" ]; then
      if [ -x "node_modules/.bin/tsc" ]; then
        cmd="node_modules/.bin/tsc --noEmit"
      else
        return 0
      fi
    else
      return 0
    fi
  fi
  commithooks_green "[js] Running typecheck..."
  eval "$cmd"
}
