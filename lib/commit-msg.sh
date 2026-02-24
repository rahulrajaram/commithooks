#!/usr/bin/env bash
# commithooks/lib/commit-msg.sh — Commit message validation
# Usage: source "$COMMITHOOKS_DIR/lib/commit-msg.sh"

if [ "${_COMMITHOOKS_COMMIT_MSG_LOADED:-}" = "1" ]; then
  return 0
fi
_COMMITHOOKS_COMMIT_MSG_LOADED=1

# Validate conventional commit format.
# Usage: commithooks_validate_conventional_commit "$1"
# Configurable via COMMITHOOKS_CC_TYPES (comma-separated, default: feat,fix,docs,style,refactor,perf,test,build,ci,chore,revert)
# Configurable via COMMITHOOKS_CC_MAX_LENGTH (default: 72)
commithooks_validate_conventional_commit() {
  local msg_file="$1"
  local msg
  msg="$(head -1 "$msg_file")"

  # Allow merge commits
  if echo "$msg" | grep -qE '^Merge (branch|pull request|remote-tracking)'; then
    return 0
  fi

  local types="${COMMITHOOKS_CC_TYPES:-feat,fix,docs,style,refactor,perf,test,build,ci,chore,revert}"
  local max_len="${COMMITHOOKS_CC_MAX_LENGTH:-72}"

  # Build regex from types
  local types_regex
  types_regex="$(echo "$types" | tr ',' '|')"

  if ! echo "$msg" | grep -qE "^(${types_regex})(\(.+\))?!?:\s.+"; then
    commithooks_red "[commit-msg] Subject does not follow Conventional Commits format."
    commithooks_red "  Expected: <type>[optional scope]: <description>"
    commithooks_red "  Types: $types"
    commithooks_red "  Got: $msg"
    return 1
  fi

  local len=${#msg}
  if [ "$len" -gt "$max_len" ]; then
    commithooks_red "[commit-msg] Subject line is $len chars (max $max_len)."
    return 1
  fi

  return 0
}

# Validate subject line basics (capitalization, trailing period, length).
# Usage: commithooks_validate_subject_line "$1"
commithooks_validate_subject_line() {
  local msg_file="$1"
  local msg
  msg="$(head -1 "$msg_file")"

  # Allow merge commits
  if echo "$msg" | grep -qE '^Merge (branch|pull request|remote-tracking)'; then
    return 0
  fi

  local max_len="${COMMITHOOKS_SUBJECT_MAX_LENGTH:-72}"
  local errors=0

  # Check length
  local len=${#msg}
  if [ "$len" -gt "$max_len" ]; then
    commithooks_red "[commit-msg] Subject line is $len chars (max $max_len)."
    errors=1
  fi

  # Check for empty subject
  if [ -z "$msg" ]; then
    commithooks_red "[commit-msg] Subject line is empty."
    return 1
  fi

  # Check trailing period
  if echo "$msg" | grep -qE '\.$'; then
    commithooks_red "[commit-msg] Subject line should not end with a period."
    errors=1
  fi

  return "$errors"
}
