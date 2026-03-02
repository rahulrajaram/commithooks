#!/usr/bin/env bash
# commithooks/lib/lint-css.sh — CSS project checks
# Usage: source "$COMMITHOOKS_DIR/lib/lint-css.sh"

if [ "${_COMMITHOOKS_LINT_CSS_LOADED:-}" = "1" ]; then
  return 0
fi
_COMMITHOOKS_LINT_CSS_LOADED=1

_commithooks_css_resolve_stylelint() {
  if command -v stylelint &>/dev/null; then
    echo "stylelint"
    return 0
  fi
  if [ -x "node_modules/.bin/stylelint" ]; then
    echo "node_modules/.bin/stylelint"
    return 0
  fi
  return 1
}

# Run stylelint on staged CSS files (if available).
commithooks_css_stylelint() {
  local runner
  if ! runner="$(_commithooks_css_resolve_stylelint)"; then
    commithooks_warn "[css] 'stylelint' not found, skipping."
    return 0
  fi

  local files
  files="$(commithooks_staged_files | grep -E '\.(css|scss|sass)$' || true)"
  if [ -z "$files" ]; then
    return 0
  fi

  commithooks_green "[css] Running stylelint..."
  # shellcheck disable=SC2086
  "$runner" $files
}
