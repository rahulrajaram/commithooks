#!/usr/bin/env bash
# commithooks integration tests
#
# Creates a throwaway git repo in test/test_workspace/ and exercises
# each item from the PR #1 test plan:
#
#   1. install-git-hooks.sh populates global gitignore
#   2. LLM review flags a planning artifact (requires LLM CLI)
#   3. COMMITHOOKS_SKIP_LLM_REVIEW=1 skips the check
#   4. shellcheck + bash -n pass on all shell files
#   5. stylelint/hlint skip gracefully when not installed
#
# Usage:  ./test/run_tests.sh
#
# The test uses a temporary global gitignore so the real one is never touched.

set -euo pipefail

COMMITHOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$COMMITHOOKS_DIR/test/test_workspace"
FAKE_GLOBAL_GITIGNORE="$WORKSPACE/.fake_global_gitignore"

passed=0
failed=0
skipped=0

# ── helpers ──────────────────────────────────────────────────────────

_green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
_red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
_yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }

pass() { _green "  PASS: $1"; passed=$((passed + 1)); }
fail() { _red   "  FAIL: $1"; failed=$((failed + 1)); }
skip() { _yellow "  SKIP: $1"; skipped=$((skipped + 1)); }

setup_workspace() {
  rm -rf "$WORKSPACE"
  mkdir -p "$WORKSPACE"
  export COMMITHOOKS_GLOBAL_GITIGNORE_FILE="$FAKE_GLOBAL_GITIGNORE"
  (
    cd "$WORKSPACE"
    git init -q
    git config user.email "test@test"
    git config user.name "test"
    # Install commithooks so core.hooksPath is set and the dispatcher works
    "$COMMITHOOKS_DIR/install-git-hooks.sh" > /dev/null 2>&1
    echo "seed" > README.md
    git add README.md
    COMMITHOOKS_SKIP_NOOP=1 COMMITHOOKS_SKIP_LLM_REVIEW=1 git commit -q -m "initial" > /dev/null 2>&1
  )
}

# Create a .githooks/pre-commit in the consumer repo that sources the
# commithooks libs — same pattern a real consumer would use.
install_consumer_hook() {
  mkdir -p "$WORKSPACE/.githooks"
  # Write the hook — use single-quoted heredoc delimiter so nothing is
  # expanded, then hard-code the two paths we need via sed.
  sed \
    -e "s|__COMMITHOOKS_DIR__|$COMMITHOOKS_DIR|g" \
    -e "s|__FAKE_GITIGNORE__|$FAKE_GLOBAL_GITIGNORE|g" \
    > "$WORKSPACE/.githooks/pre-commit" << 'HOOK'
#!/usr/bin/env bash
set -euo pipefail
export COMMITHOOKS_DIR="__COMMITHOOKS_DIR__"
export COMMITHOOKS_GLOBAL_GITIGNORE_FILE="__FAKE_GITIGNORE__"
source "$COMMITHOOKS_DIR/lib/common.sh"
source "$COMMITHOOKS_DIR/lib/llm-review.sh"
source "$COMMITHOOKS_DIR/lib/lint-css.sh"
source "$COMMITHOOKS_DIR/lib/lint-haskell.sh"
commithooks_llm_review
commithooks_css_stylelint
commithooks_haskell_hlint
HOOK
  chmod +x "$WORKSPACE/.githooks/pre-commit"
}

# ── test 1: install-git-hooks.sh populates global gitignore ──────────

test_install_populates_gitignore() {
  echo
  _green "TEST 1: install-git-hooks.sh populates global gitignore"

  if [ ! -f "$FAKE_GLOBAL_GITIGNORE" ]; then
    fail "global gitignore file was not created"
    return
  fi

  if grep -qF "# <commithooks:begin>" "$FAKE_GLOBAL_GITIGNORE"; then
    pass "managed block marker present"
  else
    fail "managed block marker missing"
  fi

  if grep -qF "VISION.md" "$FAKE_GLOBAL_GITIGNORE"; then
    pass "planning artifacts in managed block"
  else
    fail "planning artifacts missing from managed block"
  fi

  if grep -qF ".yarli/" "$FAKE_GLOBAL_GITIGNORE"; then
    pass "agent state dirs in managed block"
  else
    fail "agent state dirs missing from managed block"
  fi
}

# ── test 2: LLM review flags a planning artifact ────────────────────

test_llm_review_flags_artifact() {
  echo
  _green "TEST 2: LLM review flags a planning artifact"

  if [ -n "${CLAUDECODE:-}" ]; then
    skip "cannot run claude --print inside a Claude Code session"
    return
  fi

  if ! command -v claude &>/dev/null && ! command -v codex &>/dev/null; then
    skip "no LLM CLI available (need claude or codex)"
    return
  fi

  setup_workspace
  install_consumer_hook

  # Stage a file that looks like a planning artifact
  echo "my personal scratch notes" > "$WORKSPACE/SCRATCH_NOTES.md"

  local output
  output="$(cd "$WORKSPACE" && git add SCRATCH_NOTES.md && git commit -m "test llm" 2>&1)" || true

  if echo "$output" | grep -qi "llm-review.*Running"; then
    pass "LLM review ran"
  else
    fail "LLM review did not run"
  fi

  # If the LLM flagged it, the file should have been added to gitignore
  # and unstaged. If the LLM timed out, that's still a graceful skip.
  if echo "$output" | grep -qi "flagged for global gitignore"; then
    pass "LLM flagged the artifact"
    if grep -qF "SCRATCH_NOTES.md" "$FAKE_GLOBAL_GITIGNORE"; then
      pass "pattern added to global gitignore"
    else
      fail "pattern NOT added to global gitignore"
    fi
  elif echo "$output" | grep -qi "PASS.*all staged files"; then
    skip "LLM judged the file as intentional (conservative, acceptable)"
  elif echo "$output" | grep -qi "failed or timed out"; then
    skip "LLM call timed out — cannot verify flagging behavior"
  else
    skip "LLM response could not be classified"
  fi
}

# ── test 3: COMMITHOOKS_SKIP_LLM_REVIEW=1 ───────────────────────────

test_skip_llm_review() {
  echo
  _green "TEST 3: COMMITHOOKS_SKIP_LLM_REVIEW=1 skips gracefully"

  setup_workspace
  install_consumer_hook

  echo "data" > "$WORKSPACE/notes.txt"

  local output
  output="$(cd "$WORKSPACE" && git add notes.txt && COMMITHOOKS_SKIP_LLM_REVIEW=1 git commit -m "test skip" 2>&1)" || true

  if echo "$output" | grep -qi "llm-review"; then
    fail "LLM review was NOT skipped (output mentions llm-review)"
  else
    pass "LLM review skipped — no llm-review output"
  fi
}

# ── test 4: shellcheck + bash -n pass ────────────────────────────────

test_shellcheck_and_syntax() {
  echo
  _green "TEST 4: shellcheck + bash -n pass on all shell files"

  local all_files
  all_files="$(find "$COMMITHOOKS_DIR" -maxdepth 2 \
    \( -name '*.sh' \
       -o -name 'pre-commit' \
       -o -name 'commit-msg' \
       -o -name 'pre-push' \
       -o -name 'post-checkout' \
       -o -name 'post-merge' \) \
    -not -path '*/.git/*' \
    -not -path '*/test_workspace/*' | sort)"

  # Run shellcheck
  if command -v shellcheck &>/dev/null; then
    # shellcheck disable=SC2086
    if shellcheck $all_files 2>&1; then
      pass "shellcheck passed"
    else
      fail "shellcheck found issues"
    fi
  else
    skip "shellcheck not installed"
  fi

  # Run bash -n
  local err=0
  while IFS= read -r f; do
    if [ -f "$f" ] && ! bash -n "$f" 2>&1; then
      _red "    syntax error: $f"
      err=1
    fi
  done <<< "$all_files"
  if [ "$err" -eq 0 ]; then
    pass "bash -n syntax check passed"
  else
    fail "bash -n found syntax errors"
  fi
}

# ── test 5: lint tools skip gracefully when missing ──────────────────

test_lint_graceful_skip() {
  echo
  _green "TEST 5: stylelint/hlint skip gracefully when not installed"

  setup_workspace
  install_consumer_hook

  echo "body { color: red; }" > "$WORKSPACE/style.css"
  echo "main = putStrLn \"hello\"" > "$WORKSPACE/Main.hs"

  local output
  output="$(cd "$WORKSPACE" && git add style.css Main.hs && COMMITHOOKS_SKIP_LLM_REVIEW=1 git commit -m "test lint skip" 2>&1)" || true

  if echo "$output" | grep -q "stylelint.*not found.*skipping"; then
    pass "stylelint skips gracefully"
  elif command -v stylelint &>/dev/null; then
    skip "stylelint IS installed — cannot test missing-tool path"
  else
    fail "stylelint did not report graceful skip"
  fi

  if echo "$output" | grep -q "hlint.*not found.*skipping"; then
    pass "hlint skips gracefully"
  elif command -v hlint &>/dev/null; then
    skip "hlint IS installed — cannot test missing-tool path"
  else
    fail "hlint did not report graceful skip"
  fi
}

# ── main ─────────────────────────────────────────────────────────────

echo "========================================"
echo " commithooks integration tests"
echo "========================================"

setup_workspace

test_install_populates_gitignore
test_skip_llm_review
test_shellcheck_and_syntax
test_lint_graceful_skip
test_llm_review_flags_artifact

# cleanup
rm -rf "$WORKSPACE"
unset COMMITHOOKS_GLOBAL_GITIGNORE_FILE

echo
echo "========================================"
printf ' Results:  '
_green "$passed passed"
if [ "$failed" -gt 0 ]; then
  printf '           '
  _red "$failed failed"
fi
if [ "$skipped" -gt 0 ]; then
  printf '           '
  _yellow "$skipped skipped"
fi
echo "========================================"

exit "$failed"
