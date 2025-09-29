#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./script/encrypt-secrets.sh [PATH]
# Default PATH = .
ROOT="${1:-.}"

FILES_REGEX='\.ya?ml$'
declare -a TO_ENCRYPT=()

has_mikefarah_yq_v4() {
  command -v yq >/dev/null 2>&1 || return 1
  yq --version 2>/dev/null | grep -q 'github.com/mikefarah/yq' || return 1
  yq --version 2>/dev/null | grep -Eq ' 4\.' || return 1
}

# Simple grep-based fallback
needs_encryption_grep() {
  local file="$1"
  [[ "$file" =~ $FILES_REGEX ]] || return 1
  grep -qE '^\s*sops\s*:' "$file" && return 1
  grep -q 'ENC\[' "$file" && return 1
  grep -qE '^[[:space:]]*kind:[[:space:]]*Secret([[:space:]]|$)' "$file" || return 1
  return 0
}

# Precise yq v4 check
needs_encryption_yq() {
  local file="$1"
  [[ "$file" =~ $FILES_REGEX ]] || return 1
  grep -qE '^\s*sops\s*:' "$file" && return 1
  grep -q 'ENC\[' "$file" && return 1

  local out
  out="$(yq eval-all -r '
    select(.kind == "Secret") |
    ((.data // {}) + (.stringData // {})) |
    to_entries | .[].value
  ' "$file" 2>/dev/null || true)"

  [[ -z "$out" ]] && return 1

  while IFS= read -r line; do
    [[ -z "$line" ]] && return 0
    [[ "$line" =~ ^ENC\[ ]] || return 0
  done <<< "$out"

  return 1
}

NEEDS_FUNC="needs_encryption_grep"
if has_mikefarah_yq_v4; then
  NEEDS_FUNC="needs_encryption_yq"
fi

while IFS= read -r -d '' file; do
  case "$file" in
    ./.git/*|*/.git/*) continue ;;
  esac
  if $NEEDS_FUNC "$file"; then
    TO_ENCRYPT+=("$file")
  fi
done < <( ( [[ -d "$ROOT" ]] && find "$ROOT" -type f -print0 ) || ( [[ -f "$ROOT" ]] && printf '%s\0' "$ROOT" ) )

if ((${#TO_ENCRYPT[@]} == 0)); then
  echo "✅ All Secrets under '$ROOT' are already encrypted."
  exit 0
fi

echo "⚠️  Found unencrypted Secret file(s), encrypting with sops:"
for f in "${TO_ENCRYPT[@]}"; do
  echo "  • $f"
  sops -e -i "$f"
done

echo "✅ Done."
