#!/usr/bin/env bash
# commithooks/lib/deps.sh — Dependency reinstall after lockfile changes
# Usage: source "$COMMITHOOKS_DIR/lib/deps.sh"
#
# Designed for post-merge and post-checkout hooks.

if [ "${_COMMITHOOKS_DEPS_LOADED:-}" = "1" ]; then
  return 0
fi
_COMMITHOOKS_DEPS_LOADED=1

# Check if a file changed between two refs and reinstall deps if so.
# For post-merge: pass no args (compares HEAD with ORIG_HEAD).
# For post-checkout: pass prev_head and new_head as $1 and $2.
commithooks_reinstall_if_changed() {
  local prev_ref="${1:-ORIG_HEAD}"
  local new_ref="${2:-HEAD}"

  local changed
  changed="$(git diff --name-only "$prev_ref" "$new_ref" 2>/dev/null || true)"
  if [ -z "$changed" ]; then
    return 0
  fi

  # Cargo (Rust)
  if echo "$changed" | grep -q 'Cargo\.lock'; then
    if command -v cargo &>/dev/null; then
      commithooks_green "[deps] Cargo.lock changed, running cargo build..."
      cargo build 2>&1 || commithooks_warn "[deps] cargo build failed"
    fi
  fi

  # npm (Node.js)
  if echo "$changed" | grep -q 'package-lock\.json'; then
    if command -v npm &>/dev/null; then
      commithooks_green "[deps] package-lock.json changed, running npm install..."
      npm install 2>&1 || commithooks_warn "[deps] npm install failed"
    fi
  fi

  # yarn
  if echo "$changed" | grep -q 'yarn\.lock'; then
    if command -v yarn &>/dev/null; then
      commithooks_green "[deps] yarn.lock changed, running yarn install..."
      yarn install 2>&1 || commithooks_warn "[deps] yarn install failed"
    fi
  fi

  # pnpm
  if echo "$changed" | grep -q 'pnpm-lock\.yaml'; then
    if command -v pnpm &>/dev/null; then
      commithooks_green "[deps] pnpm-lock.yaml changed, running pnpm install..."
      pnpm install 2>&1 || commithooks_warn "[deps] pnpm install failed"
    fi
  fi

  # pip/poetry (Python)
  if echo "$changed" | grep -q 'poetry\.lock'; then
    if command -v poetry &>/dev/null; then
      commithooks_green "[deps] poetry.lock changed, running poetry install..."
      poetry install 2>&1 || commithooks_warn "[deps] poetry install failed"
    fi
  elif echo "$changed" | grep -q 'requirements.*\.txt'; then
    if command -v pip &>/dev/null; then
      local req_file
      req_file="$(echo "$changed" | grep 'requirements.*\.txt' | head -1)"
      commithooks_green "[deps] $req_file changed, running pip install..."
      pip install -r "$req_file" 2>&1 || commithooks_warn "[deps] pip install failed"
    fi
  fi

  # Go
  if echo "$changed" | grep -q 'go\.sum'; then
    if command -v go &>/dev/null; then
      commithooks_green "[deps] go.sum changed, running go mod download..."
      go mod download 2>&1 || commithooks_warn "[deps] go mod download failed"
    fi
  fi
}
