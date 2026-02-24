#!/usr/bin/env bash
# commithooks/lib/version-sync.sh — Version synchronization checks
# Usage: source "$COMMITHOOKS_DIR/lib/version-sync.sh"

if [ "${_COMMITHOOKS_VERSION_SYNC_LOADED:-}" = "1" ]; then
  return 0
fi
_COMMITHOOKS_VERSION_SYNC_LOADED=1

# Extract version from a file. Supports pyproject.toml, package.json, Cargo.toml,
# __init__.py / __version__.py, and spec.md / *.md with "version:" or "Version:".
_commithooks_extract_version() {
  local file="$1"
  if [ ! -f "$file" ]; then
    return 1
  fi

  case "$file" in
    *package.json)
      grep -oP '"version"\s*:\s*"\K[^"]+' "$file" | head -1
      ;;
    *pyproject.toml|*Cargo.toml)
      grep -oP '^version\s*=\s*"\K[^"]+' "$file" | head -1
      ;;
    *__init__.py|*__version__.py|*_version.py)
      grep -oP '__version__\s*=\s*["\x27]\K[^"\x27]+' "$file" | head -1
      ;;
    *.md)
      grep -oiP '^\s*version:\s*\K\S+' "$file" | head -1
      ;;
    *)
      grep -oP 'version\s*[=:]\s*["\x27]?\K[0-9][0-9.a-zA-Z-]*' "$file" | head -1
      ;;
  esac
}

# Check that version strings match across a list of files.
# Usage: commithooks_check_version_sync "pyproject.toml" "package.json" "src/__init__.py"
# Or set COMMITHOOKS_VERSION_FILES (space-separated).
commithooks_check_version_sync() {
  local -a files
  if [ $# -gt 0 ]; then
    files=("$@")
  elif [ -n "${COMMITHOOKS_VERSION_FILES:-}" ]; then
    read -ra files <<< "$COMMITHOOKS_VERSION_FILES"
  else
    commithooks_warn "[version-sync] No files specified. Set COMMITHOOKS_VERSION_FILES or pass arguments."
    return 0
  fi

  local reference_version=""
  local reference_file=""
  local errors=0

  local f
  for f in "${files[@]}"; do
    if [ ! -f "$f" ]; then
      continue
    fi
    local ver
    ver="$(_commithooks_extract_version "$f")"
    if [ -z "$ver" ]; then
      commithooks_warn "[version-sync] Could not extract version from: $f"
      continue
    fi
    if [ -z "$reference_version" ]; then
      reference_version="$ver"
      reference_file="$f"
    elif [ "$ver" != "$reference_version" ]; then
      commithooks_red "[version-sync] Version mismatch: $reference_file=$reference_version vs $f=$ver"
      errors=1
    fi
  done

  return "$errors"
}

# Ensure version was bumped if source files changed.
# Usage: commithooks_require_version_bump "pyproject.toml" "src/"
# First arg is the version file, remaining args are source directories/files to watch.
commithooks_require_version_bump() {
  if [ $# -lt 2 ]; then
    commithooks_warn "[version-sync] Usage: commithooks_require_version_bump <version-file> <source-path>..."
    return 0
  fi

  local version_file="$1"
  shift
  local -a source_paths=("$@")

  local staged
  staged="$(git diff --cached --name-only)"
  if [ -z "$staged" ]; then
    return 0
  fi

  # Check if any source paths have staged changes
  local source_changed=0
  local sp
  for sp in "${source_paths[@]}"; do
    if echo "$staged" | grep -q "^${sp}"; then
      source_changed=1
      break
    fi
  done

  if [ "$source_changed" -eq 0 ]; then
    return 0
  fi

  # Check if version file was also changed
  if ! echo "$staged" | grep -q "^${version_file}$"; then
    commithooks_red "[version-sync] Source files changed but $version_file was not updated."
    commithooks_red "  Bump the version or stage $version_file before committing."
    return 1
  fi

  return 0
}
