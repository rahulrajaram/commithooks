#!/usr/bin/env bash
# commithooks/lib/lint-python.sh — Python project checks
# Usage: source "$COMMITHOOKS_DIR/lib/lint-python.sh"

if [ "${_COMMITHOOKS_LINT_PYTHON_LOADED:-}" = "1" ]; then
  return 0
fi
_COMMITHOOKS_LINT_PYTHON_LOADED=1

# Check Python syntax via AST parse on staged .py files.
commithooks_python_syntax() {
  commithooks_require_cmd "python3" || return 0
  local files
  files="$(commithooks_staged_files "py")"
  if [ -z "$files" ]; then
    return 0
  fi
  commithooks_green "[python] Checking syntax..."
  local errors=0
  local f
  while IFS= read -r f; do
    if [ -f "$f" ] && ! python3 -c "import ast; ast.parse(open('$f').read())" 2>/dev/null; then
      commithooks_red "[python] Syntax error in: $f"
      errors=1
    fi
  done <<< "$files"
  return "$errors"
}

# Run ruff check on staged .py files (if available).
commithooks_python_ruff() {
  commithooks_require_cmd "ruff" || return 0
  local files
  files="$(commithooks_staged_files "py")"
  if [ -z "$files" ]; then
    return 0
  fi
  commithooks_green "[python] Running ruff..."
  # shellcheck disable=SC2086
  ruff check $files
}

# Run flake8 for critical errors on staged .py files (if available).
commithooks_python_flake8() {
  commithooks_require_cmd "flake8" || return 0
  local files
  files="$(commithooks_staged_files "py")"
  if [ -z "$files" ]; then
    return 0
  fi
  commithooks_green "[python] Running flake8 (critical errors)..."
  # shellcheck disable=SC2086
  flake8 --select=E9,F63,F7,F82 $files
}

# Run pytest with configurable timeout.
# Set COMMITHOOKS_PYTEST_TIMEOUT (default: 120) seconds.
commithooks_python_test() {
  commithooks_require_cmd "pytest" || return 0
  local timeout="${COMMITHOOKS_PYTEST_TIMEOUT:-120}"
  commithooks_green "[python] Running pytest (timeout: ${timeout}s)..."
  timeout "$timeout" pytest
}
