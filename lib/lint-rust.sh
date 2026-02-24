#!/usr/bin/env bash
# commithooks/lib/lint-rust.sh — Rust project checks
# Usage: source "$COMMITHOOKS_DIR/lib/lint-rust.sh"
#
# Set COMMITHOOKS_CARGO_OFFLINE=1 to pass --offline to cargo commands.

if [ "${_COMMITHOOKS_LINT_RUST_LOADED:-}" = "1" ]; then
  return 0
fi
_COMMITHOOKS_LINT_RUST_LOADED=1

_commithooks_cargo_offline_flag() {
  if [ "${COMMITHOOKS_CARGO_OFFLINE:-0}" = "1" ]; then
    echo "--offline"
  fi
}

commithooks_rust_fmt() {
  commithooks_require_cmd "cargo" || return 0
  commithooks_green "[rust] Running cargo fmt --check..."
  cargo fmt --check
}

commithooks_rust_clippy() {
  commithooks_require_cmd "cargo" || return 0
  local offline
  offline="$(_commithooks_cargo_offline_flag)"
  commithooks_green "[rust] Running cargo clippy..."
  # shellcheck disable=SC2086
  cargo clippy $offline -- -D warnings
}

commithooks_rust_test() {
  commithooks_require_cmd "cargo" || return 0
  local offline
  offline="$(_commithooks_cargo_offline_flag)"
  commithooks_green "[rust] Running cargo test..."
  # shellcheck disable=SC2086
  cargo test $offline
}

commithooks_rust_check() {
  commithooks_require_cmd "cargo" || return 0
  local offline
  offline="$(_commithooks_cargo_offline_flag)"
  commithooks_green "[rust] Running cargo check..."
  # shellcheck disable=SC2086
  cargo check $offline
}
