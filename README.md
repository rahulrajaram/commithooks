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

## How it works

```
INSTALLATION
============

  ./install-git-hooks.sh
         |
         |  1. git config core.hooksPath ~/Documents/commithooks
         |  2. Populate ~/.config/git/ignore (managed block)
         v
  +-------------------------------+        +----------------------------+
  | ~/.config/git/ignore          |        | consumer repo              |
  |-------------------------------|        |----------------------------|
  | # <commithooks:begin>         |        | .githooks/                 |
  | VISION.md                     |        |   pre-commit  <-- you write|
  | .claude/                      |        |   commit-msg  <-- you write|
  | .env                          |        |                            |
  | ...                           |        | src/  tests/  ...          |
  | # <commithooks:end>           |        +----------------------------+
  +-------------------------------+


COMMIT-TIME EXECUTION (pre-commit shown; same pattern for all hooks)
====================================================================

  git commit
       |
       v
  commithooks/pre-commit            <-- git calls this (via core.hooksPath)
  (dispatcher)
       |
       |  1. Set recursion guard
       |  2. Find repo root
       |  3. Look for local hook:
       |       $repo/.githooks/pre-commit
       |       $repo/scripts/git-hooks/pre-commit
       |
       +----[not found]----> no-op baseline (exit 0)
       |
       +----[found]--------> exec $repo/.githooks/pre-commit
                                    |
                                    |  source commithooks/lib/common.sh
                                    |  source commithooks/lib/secrets.sh
                                    |  source commithooks/lib/llm-review.sh
                                    |  source commithooks/lib/lint-*.sh
                                    |
                                    v
                             +------+------+------+------+------+
                             |      |      |      |      |      |
                             v      v      v      v      v      v
                          secrets  LLM   lint   lint   lint   shell
                          scan    review  js    css   haskell check
                             |      |
                             |      +--[flagged]--> add to global
                             |                      gitignore,
                             |                      unstage file
                             |
                             +--[secret found]--> BLOCK commit


PRE-PUSH EXECUTION
===================

  git push
       |
       v
  commithooks/pre-push (dispatcher)
       |
       +----> exec $repo/.githooks/pre-push
                      |
                      v
               reject WIP commits
               validate branch name
               run full test suite
                      |
                      v
               shellcheck + bash -n    <-- runs on ALL shell files
               on all .sh / hook       (final gate before publish)
               scripts
```

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
- `commithooks_rust_deny` — `cargo deny check` (license/advisory/ban checks; skips if cargo-deny not installed or no `deny.toml`)
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

### `lib/lint-css.sh` — CSS project checks

- `commithooks_css_stylelint` — stylelint on staged CSS/SCSS/SASS files (if available)

### `lib/lint-haskell.sh` — Haskell project checks

- `commithooks_haskell_hlint` — hlint on staged `.hs`/`.lhs` files (if available)

### `lib/llm-review.sh` — LLM-based gitignore candidate assessment

- `commithooks_llm_review` — scans staged files and asks an LLM (claude or codex) whether any belong in the global gitignore rather than version control. Files flagged by the LLM are added to `~/.config/git/ignore` and unstaged.
  - `COMMITHOOKS_LLM_CLI=auto` — which CLI to use (`auto` tries claude then codex)
  - `COMMITHOOKS_LLM_TIMEOUT=20` — seconds before the call is abandoned
  - `COMMITHOOKS_LLM_REVIEW_MODE=warn` — `warn` allows the commit to proceed; `block` aborts
  - `COMMITHOOKS_SKIP_LLM_REVIEW=1` — skip entirely (for offline/CI)

### `lib/global-gitignore.sh` — Global gitignore management

- `commithooks_ensure_global_gitignore` — writes or updates a managed block of patterns in `~/.config/git/ignore` (the XDG default that git discovers automatically). Patterns cover planning artifacts, agent state, OS/editor noise, and secrets. Called by `install-git-hooks.sh` on install.
- `commithooks_global_gitignore_has <pattern>` — check if a pattern is already present
- `commithooks_global_gitignore_add <pattern>` — append a pattern if not already present

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

### Method 1: `core.hooksPath` (recommended)

Point git at the commithooks directory directly:

```bash
git config core.hooksPath ~/Documents/commithooks
```

Or use the helper: `./install-git-hooks.sh`

This also populates `~/.config/git/ignore` with the managed global gitignore block.

### Method 2: Copy into `.git/`

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

### Method 3: `/install-commithooks` skill

If using Claude Code or Codex, run `/install-commithooks` in any repo. The skill auto-detects project type and scaffolds appropriate local hooks.

## Adding commithooks to a consumer repo

To make your project a commithooks consumer, add hook installation to your existing
dev setup path. The steps are always the same — copy dispatchers and lib into `.git/`:

```bash
COMMITHOOKS="${COMMITHOOKS_DIR:-$HOME/Documents/commithooks}"
GIT_DIR="$(git rev-parse --git-dir)"
if [ -d "$COMMITHOOKS/lib" ]; then
  for hook in pre-commit commit-msg pre-push post-checkout post-merge; do
    [ -f "$COMMITHOOKS/$hook" ] && cp "$COMMITHOOKS/$hook" "$GIT_DIR/hooks/$hook" && chmod +x "$GIT_DIR/hooks/$hook"
  done
  rm -rf "${GIT_DIR:?}/lib" && cp -r "$COMMITHOOKS/lib" "$GIT_DIR/lib"
fi
```

Where to put this depends on your project:

- **`install.sh`** — if your project has a dev setup script, add the snippet above
- **Node (`package.json`)** — add a `"prepare"` or `"postinstall"` script:
  ```json
  "scripts": {
    "prepare": "bash -c 'COMMITHOOKS=${COMMITHOOKS_DIR:-$HOME/Documents/commithooks}; GIT_DIR=$(git rev-parse --git-dir); [ -d $COMMITHOOKS/lib ] && for h in pre-commit commit-msg pre-push post-checkout post-merge; do [ -f $COMMITHOOKS/$h ] && cp $COMMITHOOKS/$h $GIT_DIR/hooks/$h && chmod +x $GIT_DIR/hooks/$h; done && rm -rf ${GIT_DIR}/lib && cp -r $COMMITHOOKS/lib $GIT_DIR/lib || true'"
  }
  ```
- **Rust (`build.rs`)** — run the snippet as a build step
- **Python (`Makefile`)** — add a `hooks` target called from your dev setup
Then create `.githooks/pre-commit` and `.githooks/commit-msg` with your project-specific
checks (see examples above) and commit them to the repo. Contributors get the hook
implementations on clone; the dispatchers and lib get installed on first build/setup.

## Gitignore strategy

Commithooks manages a **global gitignore** at `~/.config/git/ignore` (the XDG default
that git discovers automatically). Running `install-git-hooks.sh` populates it with
patterns for planning artifacts, agent state, OS/editor files, and secrets.

- **Global gitignore** — patterns for the developer's environment, not the project.
  These are invisible across all repos. Examples: `VISION.md`, `.yarli/`, `.claude/`,
  `.env`, `*.swp`.
- **Local `.gitignore`** — patterns inherent to the project's toolchain. These are
  committed and shared with the team. Examples: `target/` (Rust), `node_modules/`,
  `dist/`.

At commit time, `commithooks_llm_review` in the pre-commit hook dynamically assesses
staged files. If the LLM identifies a file as a developer-environment artifact that
is missing from the global gitignore, it adds the pattern automatically and unstages
the file.

## Self-enforcement

This repo dogfoods Method 2. Dispatchers live in `.git/hooks/`, lib in `.git/lib/`, and local hooks in `.githooks/`:

- **`.githooks/pre-commit`** — blocks sensitive files, scans for secrets, runs LLM gitignore assessment, JS/TS lint (`oxlint`/`eslint`), CSS lint (`stylelint`), Haskell lint (`hlint`), plus `shellcheck` and `bash -n` on staged shell files
- **`.githooks/commit-msg`** — enforces conventional commit format and subject line rules
- **`.githooks/pre-push`** — runs `shellcheck` and `bash -n` on **all** shell files as a final gate before push

## Environment

- `COMMITHOOKS_DIR` — where lib modules are sourced from. Defaults to repo root (for `.githooks/` hooks) or `.git/` (for Method 1 installs in other repos).
- `COMMITHOOKS_SKIP_NOOP=1` silently exits all dispatcher hooks when no local hook is found (without this, `pre-commit` prints an informational message; the other hooks are silent either way).
