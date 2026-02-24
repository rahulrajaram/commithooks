# Shared Git Hooks

This directory hosts reusable hooks for repos in `~/Documents`.

## Why this folder exists

- Keep a single hook implementation shared across projects.
- Let each repo define its own local hook behavior in `.githooks` or `scripts/git-hooks`.
- Keep hook bootstrap and policy checks consistent for all repos that opt in.

## Usage

- Set your repo hook path to this directory:
  - `git config core.hooksPath /path/to/commithooks`
- Or use the helper script:
  - `./install-git-hooks.sh`

Cross-project workflow:

- Run `./install-git-hooks.sh` once in a repo.
- Commit your project-specific hook implementation in either:
  - `.githooks/<hook-name>`
  - or `scripts/git-hooks/<hook-name>`
- Keep shared behavior in this directory for consistency.

## Supported hooks

| Hook | Description |
|---|---|
| `pre-commit` | Runs before commit is created |
| `commit-msg` | Validates commit message |
| `pre-push` | Runs before push (receives remote name + URL) |
| `post-checkout` | Runs after checkout (receives prev-HEAD, new-HEAD, branch-flag) |
| `post-merge` | Runs after merge (receives squash flag) |

## Resolution order

Each hook first tries to run a repository-local hook:

1. `.githooks/<hook-name>`
2. `scripts/git-hooks/<hook-name>`

If no local hook is found (or the file is not executable), it falls back to a no-op
baseline so all repos can still complete commits safely even without per-repo hook
scripts.

## Library modules (`lib/`)

Reusable shell functions that local hooks can source. In your repo's `.githooks/pre-commit`:

```bash
#!/usr/bin/env bash
set -euo pipefail
COMMITHOOKS_DIR="${COMMITHOOKS_DIR:-$HOME/Documents/commithooks}"
source "$COMMITHOOKS_DIR/lib/common.sh"
source "$COMMITHOOKS_DIR/lib/secrets.sh"

commithooks_skip_during_rebase && exit 0
commithooks_block_sensitive_files
commithooks_scan_secrets_in_diff
```

### `lib/common.sh` — Shared utilities

- `commithooks_red()` / `commithooks_green()` / `commithooks_warn()` — colored output
- `commithooks_staged_files [ext]` — list staged files, optionally filtered by extension
- `commithooks_require_cmd <cmd>` — check if command exists, warn and skip if not
- `commithooks_skip_during_rebase` — returns 0 (true) during rebase/cherry-pick

### `lib/secrets.sh` — Secret/credential scanning

- `commithooks_scan_secrets_in_diff` — scans staged diff for 24+ secret patterns (AWS, GitHub, Slack, Google, OpenAI, HuggingFace, Stripe, private keys)
- `commithooks_block_sensitive_files` — blocks staging of `.env`, `.pem`, `.key`, `.p12`, `credentials.json`, `id_rsa`, etc.

### `lib/commit-msg.sh` — Commit message validation

- `commithooks_validate_conventional_commit <msg-file>` — validates conventional commit format
  - Configure types: `COMMITHOOKS_CC_TYPES=feat,fix,docs,...`
  - Configure max length: `COMMITHOOKS_CC_MAX_LENGTH=72`
- `commithooks_validate_subject_line <msg-file>` — checks empty subject, trailing period, length
  - Configure max length: `COMMITHOOKS_SUBJECT_MAX_LENGTH=72`
- Merge commits are automatically allowed through

### `lib/lint-rust.sh` — Rust project checks

- `commithooks_rust_fmt` — `cargo fmt --check`
- `commithooks_rust_clippy` — `cargo clippy -D warnings`
- `commithooks_rust_test` — `cargo test`
- `commithooks_rust_check` — `cargo check`
- Set `COMMITHOOKS_CARGO_OFFLINE=1` for `--offline` flag

### `lib/lint-python.sh` — Python project checks

- `commithooks_python_syntax` — AST parse check on staged `.py` files
- `commithooks_python_ruff` — `ruff check` (if available)
- `commithooks_python_flake8` — `flake8` critical errors (if available)
- `commithooks_python_test` — `pytest` with configurable timeout (`COMMITHOOKS_PYTEST_TIMEOUT=120`)

### `lib/lint-js.sh` — JS/TS project checks

- `commithooks_js_oxlint` — oxlint on staged files (if available)
- `commithooks_js_eslint` — eslint on staged files (if available)
- `commithooks_js_typecheck` — configurable typecheck (`COMMITHOOKS_TYPECHECK_CMD="npx tsc --noEmit"`)

### `lib/version-sync.sh` — Version synchronization

- `commithooks_check_version_sync <file1> <file2> ...` — verify version matches across files
  - Or set `COMMITHOOKS_VERSION_FILES="pyproject.toml package.json"`
- `commithooks_require_version_bump <version-file> <source-path>...` — ensure version was bumped if source files changed

### `lib/pre-push.sh` — Pre-push checks

- `commithooks_reject_wip_commits <remote> <url>` — reject WIP/fixup/squash commits (reads stdin ref lines)
- `commithooks_check_branch_name` — validate branch name against configurable pattern
  - Configure pattern: `COMMITHOOKS_BRANCH_PATTERN='^(main|master|develop|...|feat/.+)$'`
- `commithooks_run_full_tests` — auto-detect project type and run test suite
  - Override: `COMMITHOOKS_TEST_CMD="make test"`
  - Timeout: `COMMITHOOKS_TEST_TIMEOUT=300`

### `lib/deps.sh` — Dependency reinstall after lockfile changes

- `commithooks_reinstall_if_changed [prev-ref] [new-ref]` — detect lockfile changes and run the appropriate install command
  - Supports: `Cargo.lock`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `poetry.lock`, `requirements*.txt`, `go.sum`
  - For post-merge: call with no args (compares `ORIG_HEAD` to `HEAD`)
  - For post-checkout: pass `$1` and `$2` (prev-HEAD and new-HEAD)

## Environment

- `COMMITHOOKS_DIR` sets the shared hook location (default `~/Documents/commithooks`).
- `COMMITHOOKS_SKIP_NOOP=1` exits shared fallback hooks immediately (also suppresses the `pre-commit` informational message when no local hook is found).
