#!/usr/bin/env bash
# commithooks/lib/secrets.sh — Secret/credential scanning
# Usage: source "$COMMITHOOKS_DIR/lib/secrets.sh"

if [ "${_COMMITHOOKS_SECRETS_LOADED:-}" = "1" ]; then
  return 0
fi
_COMMITHOOKS_SECRETS_LOADED=1

# Scan staged diff for common secret patterns.
# Returns 1 if secrets are detected, 0 otherwise.
commithooks_scan_secrets_in_diff() {
  local diff
  diff="$(git diff --cached --unified=0)"
  if [ -z "$diff" ]; then
    return 0
  fi

  local -a patterns=(
    # AWS
    'AKIA[0-9A-Z]{16}'
    'aws_secret_access_key\s*=\s*\S+'
    'aws_access_key_id\s*=\s*\S+'
    # GitHub
    'ghp_[0-9a-zA-Z]{36}'
    'gho_[0-9a-zA-Z]{36}'
    'ghu_[0-9a-zA-Z]{36}'
    'ghs_[0-9a-zA-Z]{36}'
    'github_pat_[0-9a-zA-Z_]{22,}'
    # Slack
    'xoxb-[0-9]{10,}-[0-9a-zA-Z]{20,}'
    'xoxp-[0-9]{10,}-[0-9a-zA-Z]{20,}'
    'xapp-[0-9]{1,}-[A-Za-z0-9]{10,}'
    'xoxs-[0-9a-zA-Z-]{40,}'
    # Google / GCP
    'AIza[0-9A-Za-z_-]{35}'
    # OpenAI
    'sk-[0-9a-zA-Z]{20}T3BlbkFJ[0-9a-zA-Z]{20}'
    'sk-proj-[0-9a-zA-Z_-]{40,}'
    # HuggingFace
    'hf_[0-9a-zA-Z]{34}'
    # Stripe
    'sk_live_[0-9a-zA-Z]{24,}'
    'sk_test_[0-9a-zA-Z]{24,}'
    'pk_live_[0-9a-zA-Z]{24,}'
    'pk_test_[0-9a-zA-Z]{24,}'
    # Private keys
    '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'
    # Generic patterns
    'password\s*=\s*["\x27][^"\x27]{8,}'
    'secret\s*=\s*["\x27][^"\x27]{8,}'
    'api_key\s*=\s*["\x27][^"\x27]{8,}'
    'token\s*=\s*["\x27][^"\x27]{8,}'
  )

  local found=0
  local pattern
  for pattern in "${patterns[@]}"; do
    local matches
    matches="$(echo "$diff" | grep -nEi "$pattern" 2>/dev/null || true)"
    if [ -n "$matches" ]; then
      if [ "$found" -eq 0 ]; then
        commithooks_red "[secrets] Potential secrets detected in staged changes:"
        found=1
      fi
      echo "$matches" | head -5 >&2
    fi
  done

  return "$found"
}

# Block staging of sensitive files.
# Returns 1 if sensitive files are staged, 0 otherwise.
commithooks_block_sensitive_files() {
  local -a sensitive_patterns=(
    '\.env$'
    '\.env\.'
    '\.pem$'
    '\.key$'
    '\.p12$'
    '\.pfx$'
    '\.jks$'
    'credentials\.json$'
    'service[-_]?account.*\.json$'
    'id_rsa$'
    'id_ed25519$'
    'id_ecdsa$'
    '\.keystore$'
    '\.secret$'
    '\.secrets$'
  )

  local staged
  staged="$(git diff --cached --name-only --diff-filter=ACM)"
  if [ -z "$staged" ]; then
    return 0
  fi

  local found=0
  local pattern
  for pattern in "${sensitive_patterns[@]}"; do
    local matches
    matches="$(echo "$staged" | grep -E "$pattern" || true)"
    if [ -n "$matches" ]; then
      if [ "$found" -eq 0 ]; then
        commithooks_red "[secrets] Sensitive files detected in staging area:"
        found=1
      fi
      echo "  $matches" >&2
    fi
  done

  if [ "$found" -eq 1 ]; then
    commithooks_red "Remove them with: git reset HEAD <file>"
  fi

  return "$found"
}
