#!/usr/bin/env bash
# commithooks/lib/pre-push.sh — Pre-push checks
# Usage: source "$COMMITHOOKS_DIR/lib/pre-push.sh"

if [ "${_COMMITHOOKS_PRE_PUSH_LOADED:-}" = "1" ]; then
  return 0
fi
_COMMITHOOKS_PRE_PUSH_LOADED=1

# Reject commits with WIP/fixup/squash prefixes in unpushed commits.
# Usage: commithooks_reject_wip_commits <remote> <url>
# Reads stdin lines: <local ref> <local sha> <remote ref> <remote sha>
commithooks_reject_wip_commits() {
  local remote="$1"
  local _url="$2"
  local _local_ref local_sha _remote_ref remote_sha
  local zero="0000000000000000000000000000000000000000"

  while read -r _local_ref local_sha _remote_ref remote_sha; do
    if [ "$local_sha" = "$zero" ]; then
      continue  # branch deletion
    fi

    local range
    if [ "$remote_sha" = "$zero" ]; then
      # New branch — check all commits not on remote
      range="$local_sha --not --remotes=$remote"
    else
      range="$remote_sha..$local_sha"
    fi

    local wip_commits
    # shellcheck disable=SC2086
    wip_commits="$(git log --oneline $range --grep='^WIP' --grep='^fixup!' --grep='^squash!' --grep='^wip:' --grep='^wip ' 2>/dev/null || true)"
    if [ -n "$wip_commits" ]; then
      commithooks_red "[pre-push] Found WIP/fixup/squash commits:"
      echo "$wip_commits" >&2
      commithooks_red "Rebase or amend before pushing."
      return 1
    fi
  done

  return 0
}

# Validate branch name against a configurable pattern.
# Set COMMITHOOKS_BRANCH_PATTERN (default: allows main, master, develop, and type/description branches).
commithooks_check_branch_name() {
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"

  # Skip detached HEAD
  if [ "$branch" = "HEAD" ]; then
    return 0
  fi

  local pattern="${COMMITHOOKS_BRANCH_PATTERN:-^(main|master|develop|release/.+|(feat|fix|chore|docs|refactor|test|ci|hotfix)/.+)$}"

  if ! echo "$branch" | grep -qE "$pattern"; then
    commithooks_red "[pre-push] Branch name '$branch' does not match naming convention."
    commithooks_red "  Expected pattern: $pattern"
    return 1
  fi

  return 0
}

# Run the project's full test suite. Auto-detects project type.
# Set COMMITHOOKS_TEST_CMD to override auto-detection.
# Set COMMITHOOKS_TEST_TIMEOUT (default: 300) seconds.
commithooks_run_full_tests() {
  local timeout="${COMMITHOOKS_TEST_TIMEOUT:-300}"

  if [ -n "${COMMITHOOKS_TEST_CMD:-}" ]; then
    commithooks_green "[pre-push] Running test suite..."
    timeout "$timeout" bash -c "$COMMITHOOKS_TEST_CMD"
    return $?
  fi

  # Auto-detect project type
  if [ -f "Cargo.toml" ]; then
    commithooks_require_cmd "cargo" || return 0
    commithooks_green "[pre-push] Running cargo test..."
    timeout "$timeout" cargo test
    # Run cargo-deny if available (license/advisory checks)
    if command -v cargo-deny &>/dev/null && [ -f "deny.toml" ]; then
      commithooks_green "[pre-push] Running cargo deny check..."
      cargo deny check 2>&1
    fi
  elif [ -f "package.json" ]; then
    if [ -f "node_modules/.package-lock.json" ] || [ -d "node_modules" ]; then
      commithooks_green "[pre-push] Running npm test..."
      timeout "$timeout" npm test
    else
      commithooks_warn "[pre-push] node_modules not found, skipping tests."
    fi
  elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "setup.cfg" ]; then
    commithooks_require_cmd "pytest" || return 0
    commithooks_green "[pre-push] Running pytest..."
    timeout "$timeout" pytest
  elif [ -f "go.mod" ]; then
    commithooks_require_cmd "go" || return 0
    commithooks_green "[pre-push] Running go test..."
    timeout "$timeout" go test ./...
  else
    commithooks_warn "[pre-push] No recognized project type, skipping tests."
  fi
}
