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
  - `./scripts/install-git-hooks.sh`

Cross-project workflow:

- Run `./scripts/install-git-hooks.sh` once in a repo.
- Commit your project-specific hook implementation in either:
  - `.githooks/<hook-name>`
  - or `scripts/git-hooks/<hook-name>`
- Keep shared behavior in this directory for consistency.

## Resolution order

Each hook first tries to run a repository-local hook:

1. `.githooks/<hook-name>`
2. `scripts/git-hooks/<hook-name>`

If no local hook exists, it falls back to a no-op baseline so all repos can still
complete commits safely even without per-repo hook scripts.

## Environment

- `COMMITHOOKS_DIR` sets the shared hook location (default `~/Documents/commithooks`).
- `COMMITHOOKS_SKIP_NOOP=1` exits shared fallback hooks immediately.
