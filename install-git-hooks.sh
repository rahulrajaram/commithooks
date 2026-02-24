#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
if [ -z "$repo_root" ]; then
  echo "Not inside a git repository."
  exit 1
fi

commithooks_dir="${COMMITHOOKS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [ ! -d "$commithooks_dir" ]; then
  echo "Shared hooks directory not found: $commithooks_dir" >&2
  exit 1
fi

git config core.hooksPath "$commithooks_dir"
chmod +x \
  "$commithooks_dir/pre-commit" \
  "$commithooks_dir/commit-msg" \
  "$commithooks_dir/pre-push" \
  "$commithooks_dir/post-checkout" \
  "$commithooks_dir/post-merge"
echo "Git hooks set to shared path: $commithooks_dir"
echo " - pre-commit"
echo " - commit-msg"
echo " - pre-push"
echo " - post-checkout"
echo " - post-merge"
