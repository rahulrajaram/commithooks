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

In your repo's `.githooks/commit-msg`:

```bash
#!/usr/bin/env bash
set -euo pipefail
COMMITHOOKS_DIR="${COMMITHOOKS_DIR:-$HOME/Documents/commithooks}"
source "$COMMITHOOKS_DIR/lib/common.sh"
source "$COMMITHOOKS_DIR/lib/commit-msg.sh"

commithooks_validate_conventional_commit "$1"
commithooks_validate_subject_line "$1"
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
  - Default: `^(main|master|develop|release/.+|(feat|fix|chore|docs|refactor|test|ci|hotfix)/.+)$`
- `commithooks_run_full_tests` — auto-detect project type and run test suite
  - Override: `COMMITHOOKS_TEST_CMD="make test"`
  - Timeout: `COMMITHOOKS_TEST_TIMEOUT=300`

### `lib/deps.sh` — Dependency reinstall after lockfile changes

- `commithooks_reinstall_if_changed [prev-ref] [new-ref]` — detect lockfile changes and run the appropriate install command
  - Supports: `Cargo.lock`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `poetry.lock`, `requirements*.txt`, `go.sum`
  - For post-merge: call with no args (compares `ORIG_HEAD` to `HEAD`)
  - For post-checkout: pass `$1` and `$2` (prev-HEAD and new-HEAD)

## Installation methods

### Method 1: Copy into `.git/` (recommended)

Copy dispatchers and lib into the target repo's `.git/` directory:

```bash
SOURCE=~/Documents/commithooks   # or clone from GitHub
GIT_DIR="$(git rev-parse --git-dir)"

# Copy dispatchers
for hook in pre-commit commit-msg pre-push post-checkout post-merge; do
  cp "$SOURCE/$hook" "$GIT_DIR/hooks/$hook"
  chmod +x "$GIT_DIR/hooks/$hook"
done

# Copy library
cp -r "$SOURCE/lib" "$GIT_DIR/lib"
```

Then create `.githooks/` with local hook implementations (see examples above).

### Method 2: `core.hooksPath` (alternative)

Point git at the commithooks directory directly:

```bash
git config core.hooksPath ~/Documents/commithooks
```

Or use the helper: `./install-git-hooks.sh`

Note: `core.hooksPath` overrides `.git/hooks/` entirely. Method 1 avoids this.

### Method 3: `/install-commithooks` skill

If using Claude Code or Codex, run `/install-commithooks` in any repo. The skill auto-detects project type and scaffolds appropriate local hooks.

## Consumer setup.sh (recommended pattern)

Every repo that uses commithooks should include a `setup.sh` so contributors can bootstrap hooks after cloning. Copy the template into your repo and customize:

```bash
cp ~/Documents/commithooks/setup-template.sh ./setup.sh
chmod +x setup.sh
# Add project-specific steps at the bottom of setup.sh
```

The template (`setup-template.sh`) handles:
- Cloning commithooks from GitHub if not available locally
- Copying dispatchers into `.git/hooks/` (skips existing custom hooks)
- Copying `lib/` into `.git/lib/`
- Making `.githooks/` executable
- Unsetting `core.hooksPath` if set

Contributors then run `./setup.sh` once after cloning.

## Self-enforcement

This repo dogfoods Method 1. Dispatchers live in `.git/hooks/`, lib in `.git/lib/`, and local hooks in `.githooks/`:

- **`.githooks/pre-commit`** — blocks sensitive files, scans for secrets, runs `shellcheck` and `bash -n` on staged shell files
- **`.githooks/commit-msg`** — enforces conventional commit format and subject line rules
- **`.githooks/pre-push`** — runs `shellcheck` and `bash -n` on **all** shell files as a final gate before push

## Environment

- `COMMITHOOKS_DIR` — where lib modules are sourced from. Defaults to repo root (for `.githooks/` hooks) or `.git/` (for Method 1 installs in other repos).
- `COMMITHOOKS_SKIP_NOOP=1` silently exits all dispatcher hooks when no local hook is found (without this, `pre-commit` prints an informational message; the other hooks are silent either way).
