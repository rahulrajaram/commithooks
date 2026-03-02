#!/usr/bin/env bash
# commithooks/lib/llm-review.sh — LLM-based gitignore candidate assessment
#
# At commit time, scans staged files for anything that might belong in the
# global gitignore (~/.config/git/ignore) but isn't there yet.  Invokes a
# local AI CLI (claude or codex) to assess each candidate.  If the LLM
# confirms, the pattern is added to the global gitignore and the file is
# unstaged so it does not get committed.
#
# Usage in .githooks/pre-commit:
#   source "$COMMITHOOKS_DIR/lib/llm-review.sh"
#   commithooks_llm_review
#
# Configuration (environment variables):
#   COMMITHOOKS_LLM_REVIEW_MODE=warn (default) | block
#       warn  — report findings but allow the commit to proceed
#       block — abort the commit if any file is flagged for gitignore
#
#   COMMITHOOKS_LLM_CLI=auto (default) | claude | codex
#       auto  — try claude first, then codex
#
#   COMMITHOOKS_LLM_TIMEOUT=20
#       Seconds before the LLM call is abandoned (default: 20)
#
#   COMMITHOOKS_SKIP_LLM_REVIEW=1
#       Set to skip this check entirely (e.g. for offline/CI environments)

if [ "${_COMMITHOOKS_LLM_REVIEW_LOADED:-}" = "1" ]; then
  return 0
fi
_COMMITHOOKS_LLM_REVIEW_LOADED=1

# Source global-gitignore for helper functions
# shellcheck disable=SC1091
source "${COMMITHOOKS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/global-gitignore.sh"

# ---------------------------------------------------------------------------
# _commithooks_llm_resolve_cli
# Print the path of the first usable LLM CLI, or return 1.
# ---------------------------------------------------------------------------
_commithooks_llm_resolve_cli() {
  local preference="${COMMITHOOKS_LLM_CLI:-auto}"
  local candidates=()

  case "$preference" in
    claude) candidates=(claude) ;;
    codex)  candidates=(codex) ;;
    *)      candidates=(claude codex) ;;
  esac

  local cli
  for cli in "${candidates[@]}"; do
    if command -v "$cli" &>/dev/null; then
      echo "$cli"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# _commithooks_llm_call <cli> <prompt>
# Invoke the CLI with the prompt on stdin; respect timeout.
# Prints the LLM response on stdout, returns 1 on failure/timeout.
# ---------------------------------------------------------------------------
_commithooks_llm_call() {
  local cli="$1"
  local prompt="$2"
  local timeout_secs="${COMMITHOOKS_LLM_TIMEOUT:-20}"

  case "$cli" in
    claude)
      echo "$prompt" \
        | timeout "$timeout_secs" claude --print 2>/dev/null
      ;;
    codex)
      echo "$prompt" \
        | timeout "$timeout_secs" codex --quiet 2>/dev/null
      ;;
    *)
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# _commithooks_is_already_ignored <file>
# Returns 0 if <file> is already covered by gitignore (global or local).
# ---------------------------------------------------------------------------
_commithooks_is_already_ignored() {
  git check-ignore -q "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# commithooks_llm_review
#
# 1. List staged files.
# 2. Filter out files already in gitignore (shouldn't happen, but guard).
# 3. Send the list to the LLM asking: which of these should be globally
#    ignored (developer environment files, not project files)?
# 4. For each file the LLM flags: add the pattern to the global gitignore,
#    unstage the file, and warn the user.
# ---------------------------------------------------------------------------
commithooks_llm_review() {
  # Escape hatch
  [ "${COMMITHOOKS_SKIP_LLM_REVIEW:-0}" = "1" ] && return 0

  local mode="${COMMITHOOKS_LLM_REVIEW_MODE:-warn}"

  # Find a CLI
  local cli
  if ! cli="$(_commithooks_llm_resolve_cli)"; then
    commithooks_warn "[llm-review] No LLM CLI found (tried: claude, codex). Skipping."
    return 0
  fi

  # Gather staged file names
  local staged_files
  staged_files="$(git diff --cached --name-only --diff-filter=ACMRT 2>/dev/null || true)"
  [ -z "$staged_files" ] && return 0

  # Build prompt
  local prompt
  prompt="$(cat <<PROMPT
You are a git pre-commit gitignore advisor. Below is a list of files staged for commit.

Your job: identify files that belong in the developer's GLOBAL gitignore
(~/.config/git/ignore) rather than in version control. These are files that
reveal the developer's personal workflow, tooling, or environment — not files
that are inherent to the project.

## Examples of files that belong in the global gitignore
- Planning/AI artifacts: VISION.md, IMPLEMENTATION_PLAN.md, PROMPT.md, IDEAS.md, PHASE_*_SUMMARY.md
- Agent state directories: .yarli/, .claude/, .codex/, .yore/, .ralph/, .haake/
- Agent output: agent_reports/, artifacts/, yarli.toml
- Editor/OS files: .DS_Store, .vscode/, .idea/, *.swp
- Secrets: .env, *.key, *.pem

## Examples of files that belong in version control
- Source code (.py, .rs, .ts, .js, .go, .sh, .hs, etc.)
- Project config (Cargo.toml, package.json, pyproject.toml, Makefile, etc.)
- Tests
- README.md, CHANGELOG.md, LICENSE.md, CONTRIBUTING.md
- Project-specific .gitignore
- Build config (Dockerfile, CI files, etc.)

## Staged files
${staged_files}

## Instructions
Respond with EXACTLY one of these formats and nothing else:

If all files look like they belong in version control:
  VERDICT: PASS

If any files should be globally ignored:
  VERDICT: IGNORE
  FILES: <one filename per line, each on its own line, no commas>
  REASON: <one concise sentence explaining why>

Be conservative. Only flag files you are confident do not belong in version
control. When in doubt, PASS.
PROMPT
)"

  commithooks_green "[llm-review] Running LLM assessment via '$cli'..."

  local response
  if ! response="$(_commithooks_llm_call "$cli" "$prompt")"; then
    commithooks_warn "[llm-review] LLM call failed or timed out — skipping."
    return 0
  fi

  if [ -z "$response" ]; then
    commithooks_warn "[llm-review] LLM returned empty response — skipping."
    return 0
  fi

  # Parse verdict
  local verdict
  verdict="$(echo "$response" | grep -m1 '^VERDICT:' | sed 's/^VERDICT:[[:space:]]*//' | tr -d '[:space:]')"

  case "${verdict^^}" in
    PASS)
      commithooks_green "[llm-review] PASS — all staged files look intentional."
      return 0
      ;;
    IGNORE)
      local reason
      reason="$(echo "$response" | grep -m1 '^REASON:' | sed 's/^REASON:[[:space:]]*//')"

      # Extract file list (lines between FILES: and REASON:, or after FILES: to end)
      local flagged_files
      flagged_files="$(echo "$response" | awk '/^FILES:/{found=1; sub(/^FILES:[[:space:]]*/, ""); if ($0 != "") print; next} found && /^REASON:/{found=0; next} found{print}')"

      if [ -z "$flagged_files" ]; then
        commithooks_warn "[llm-review] IGNORE verdict but no files listed — skipping."
        return 0
      fi

      commithooks_warn "[llm-review] Files flagged for global gitignore:"
      commithooks_warn "  Reason: ${reason}"

      local added=0
      local file base
      while IFS= read -r file; do
        # Trim whitespace
        file="$(echo "$file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -z "$file" ] && continue

        # Verify the file is actually staged (don't trust LLM blindly)
        if ! echo "$staged_files" | grep -qxF "$file"; then
          commithooks_warn "  $file — not in staged files, skipping"
          continue
        fi

        base="$(basename "$file")"
        commithooks_warn "  $file → adding '$base' to global gitignore"

        if commithooks_global_gitignore_add "$base"; then
          git reset HEAD -- "$file" 2>/dev/null || true
          added=$((added + 1))
        fi
      done <<< "$flagged_files"

      if [ "$added" -gt 0 ]; then
        commithooks_warn "[llm-review] Added $added pattern(s) to global gitignore and unstaged the file(s)."
        if [ "$mode" = "block" ]; then
          commithooks_red "[llm-review] Commit blocked. Review the changes and re-commit."
          return 1
        else
          commithooks_warn "[llm-review] Proceeding with remaining staged files."
        fi
      fi
      return 0
      ;;
    *)
      commithooks_warn "[llm-review] Could not parse LLM response — skipping."
      commithooks_warn "  Response: $(echo "$response" | head -3)"
      return 0
      ;;
  esac
}
