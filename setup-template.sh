#!/usr/bin/env bash
set -euo pipefail
# Copy this file into your repo as setup.sh and customize as needed.
# See: https://github.com/rahulrajaram/commithooks

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
GIT_DIR="$(git -C "$REPO_ROOT" rev-parse --git-dir)"

# Where to find commithooks — clone from GitHub if not available locally
COMMITHOOKS_DIR="${COMMITHOOKS_DIR:-$HOME/Documents/commithooks}"
COMMITHOOKS_REPO="https://github.com/rahulrajaram/commithooks.git"

if [ ! -d "$COMMITHOOKS_DIR/lib" ]; then
  echo "commithooks not found at $COMMITHOOKS_DIR"
  echo "Cloning from $COMMITHOOKS_REPO ..."
  git clone "$COMMITHOOKS_REPO" "$COMMITHOOKS_DIR"
fi

# Copy dispatchers (skip if a non-sample hook already exists)
for hook in pre-commit commit-msg pre-push post-checkout post-merge; do
  src="$COMMITHOOKS_DIR/$hook"
  dst="$GIT_DIR/hooks/$hook"
  [ -f "$src" ] || continue
  if [ -f "$dst" ] && [ "$(cat "$dst")" != "$(cat "$dst.sample" 2>/dev/null || true)" ]; then
    echo "[skip] $hook (existing custom hook)"
    continue
  fi
  cp "$src" "$dst"
  chmod +x "$dst"
  echo "[ok]   $hook"
done

# Copy library modules
rm -rf "${GIT_DIR:?}/lib"
cp -r "$COMMITHOOKS_DIR/lib" "$GIT_DIR/lib"
echo "[ok]   lib/ ($(find "$GIT_DIR/lib" -maxdepth 1 -name '*.sh' | wc -l) modules)"

# Ensure .githooks/ are executable
if [ -d "$REPO_ROOT/.githooks" ]; then
  chmod +x "$REPO_ROOT/.githooks"/* 2>/dev/null || true
fi

# Unset core.hooksPath if set (we use .git/hooks/ directly)
if git -C "$REPO_ROOT" config core.hooksPath &>/dev/null; then
  git -C "$REPO_ROOT" config --unset core.hooksPath
  echo "[fix]  Unset core.hooksPath (using .git/hooks/ directly)"
fi

echo ""
echo "Done. Hooks installed in $GIT_DIR/hooks/"
# Add project-specific setup steps below this line.
