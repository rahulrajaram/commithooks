#!/usr/bin/env bash
# commithooks/lib/global-gitignore.sh — Manage ~/.config/git/ignore
#
# Writes environment-specific ignore patterns (AI tooling, agent state,
# OS/editor noise, secrets) into the XDG global gitignore file that git
# discovers automatically — no core.excludesFile configuration required.
# These patterns belong globally, not in any committed .gitignore, because
# they are properties of the developer's machine, not of individual projects.
#
# The managed block is delimited by marker lines so it can be updated in-place
# without clobbering anything the user has written outside the block.
#
# Usage: source "$COMMITHOOKS_DIR/lib/global-gitignore.sh"
#        commithooks_ensure_global_gitignore

if [ "${_COMMITHOOKS_GLOBAL_GITIGNORE_LOADED:-}" = "1" ]; then
  return 0
fi
_COMMITHOOKS_GLOBAL_GITIGNORE_LOADED=1

_COMMITHOOKS_GLOBAL_GITIGNORE_FILE="${COMMITHOOKS_GLOBAL_GITIGNORE_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore}"

_COMMITHOOKS_BLOCK_BEGIN="# <commithooks:begin>"
_COMMITHOOKS_BLOCK_END="# <commithooks:end>"

# ---------------------------------------------------------------------------
# The canonical managed block content.
# Everything between the markers is owned by commithooks and rewritten on
# each install/update.  Do not put custom patterns inside the markers.
# ---------------------------------------------------------------------------
_commithooks_global_gitignore_block() {
  cat <<'BLOCK'
# <commithooks:begin>
# Managed by commithooks — do not edit between these markers by hand.
# Run the commithooks install script to update.

# Planning / AI development artifacts
VISION.md
IMPLEMENTATION_PLAN.md
PROMPT.md
RALPH_PROMPT.md
ralph.yml
CLAUDE.md
AGENTS.md
IDEAS.md
DECISIONS_LOG.txt
RFC_INSTRUCTIONS.md
PHASE_*_SUMMARY.md
**/PHASE_*_SUMMARY.md
**/PHASE_*_IMPLEMENTATION.md
*VALIDATION*.md
*VALIDATION*.txt
ISSUES_FOUND.md
UNDOCUMENTED_APIS*.md

# Agent runtime state
.yarli/
.yarl/
.yore/
.yore-test/
.yore-audit/
.cultivar/
.cultivar.bak/
.cultivar-new/
.claude/
.codex/
.agent/
.ralph/
.haake/
.haake-test/
.workmerge/
.worktrees/
.playwright-mcp/
agent_reports/
yarli.toml

# OS
.DS_Store
Thumbs.db

# Editor
.vscode/
.idea/
*.sublime-*
*.swp
*.swo
*~
.vscode-test

# Secrets / environment
.env
.env.*
*.env
*.env.local
# <commithooks:end>
BLOCK
}

# ---------------------------------------------------------------------------
# commithooks_global_gitignore_has <pattern>
# Returns 0 if <pattern> already appears in the global gitignore file.
# ---------------------------------------------------------------------------
commithooks_global_gitignore_has() {
  local pattern="$1"
  local target="$_COMMITHOOKS_GLOBAL_GITIGNORE_FILE"
  [ -f "$target" ] && grep -qxF "$pattern" "$target" 2>/dev/null
}

# ---------------------------------------------------------------------------
# commithooks_global_gitignore_add <pattern>
# Append <pattern> to the global gitignore file (outside the managed block)
# if it is not already present.
# ---------------------------------------------------------------------------
commithooks_global_gitignore_add() {
  local pattern="$1"
  local target="$_COMMITHOOKS_GLOBAL_GITIGNORE_FILE"
  mkdir -p "$(dirname "$target")"
  [ -f "$target" ] || touch "$target"
  if ! grep -qxF "$pattern" "$target" 2>/dev/null; then
    echo "$pattern" >> "$target"
    return 0  # added
  fi
  return 1  # already present
}

# ---------------------------------------------------------------------------
# commithooks_ensure_global_gitignore
#
# 1. Warn if core.excludesFile points elsewhere.
# 2. Write or update the managed block in the global gitignore file.
# ---------------------------------------------------------------------------
commithooks_ensure_global_gitignore() {
  local target="$_COMMITHOOKS_GLOBAL_GITIGNORE_FILE"

  # Ensure parent dir and file exist
  mkdir -p "$(dirname "$target")"
  [ -f "$target" ] || touch "$target"

  # git auto-discovers ~/.config/git/ignore (XDG default) without any config.
  # Only set core.excludesFile if the user has pointed it somewhere else, so
  # we don't silently override a deliberate choice.
  local current_cfg
  current_cfg="$(git config --global core.excludesFile 2>/dev/null || true)"
  if [ -n "$current_cfg" ] && [ "$current_cfg" != "$target" ]; then
    commithooks_warn "[global-gitignore] core.excludesFile is set to '$current_cfg'."
    commithooks_warn "  Managed patterns will be written to '$target' (XDG default)."
    commithooks_warn "  If you want git to use that file, unset core.excludesFile or point it there."
  fi

  # Check if the managed block is already present and up to date
  local new_block
  new_block="$(_commithooks_global_gitignore_block)"

  if grep -qF "$_COMMITHOOKS_BLOCK_BEGIN" "$target" 2>/dev/null; then
    # Extract existing block and compare
    local existing_block
    existing_block="$(awk \
      "/^${_COMMITHOOKS_BLOCK_BEGIN//\//\\/}/{found=1} found{print} /^${_COMMITHOOKS_BLOCK_END//\//\\/}/{found=0}" \
      "$target")"
    if [ "$existing_block" = "$new_block" ]; then
      return 0  # Already up to date, nothing to do
    fi

    # Replace the existing block in-place
    local tmp
    tmp="$(mktemp)"
    awk \
      -v new_block="$new_block" \
      -v begin="$_COMMITHOOKS_BLOCK_BEGIN" \
      -v end="$_COMMITHOOKS_BLOCK_END" \
      'BEGIN { skip=0; printed=0 }
       $0 == begin { skip=1 }
       skip && $0 == end { skip=0; if (!printed) { print new_block; printed=1 }; next }
       !skip { print }' \
      "$target" > "$tmp" && mv "$tmp" "$target"
    commithooks_green "[global-gitignore] Updated managed block in $target"
  else
    # Append the block (with a preceding blank line for readability)
    printf '\n%s\n' "$new_block" >> "$target"
    commithooks_green "[global-gitignore] Added managed block to $target"
  fi
}
