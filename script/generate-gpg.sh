#!/usr/bin/env bash
set -euo pipefail

# === Required env ===
: "${KEY_NAME:?Need to set KEY_NAME}"
: "${KEY_COMMENT:?Need to set KEY_COMMENT}"
: "${KEY_EMAIL:?Need to set KEY_EMAIL}"
: "${CLUSTER:?Need to set CLUSTER}"
: "${GPG_PUBLIC_KEY_FILE:?Need to set GPG_PUBLIC_KEY_FILE}"
: "${GPG_PRIVATE_KEY_FILE:?Need to set GPG_PRIVATE_KEY_FILE}"

echo "🔑 Generating GPG key for Flux ($CLUSTER)..."

# Tighten perms for output files that will contain keys
umask 077

# Helper: generate ed25519 primary + cv25519 subkey (preferred for SOPS)
gen_ed25519() {
  gpg --batch --generate-key <<'EOF'
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: sign
Subkey-Type: ecdh
Subkey-Curve: cv25519
Subkey-Usage: encrypt
Name-Real: __KEY_NAME__
Name-Comment: __KEY_COMMENT__
Name-Email: __KEY_EMAIL__
Expire-Date: 0
%commit
EOF
}

# Helper: fallback RSA-4096 primary+subkey (if ed25519 unsupported)
gen_rsa() {
  gpg --batch --generate-key <<'EOF'
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Subkey-Type: RSA
Subkey-Length: 4096
Subkey-Usage: encrypt
Name-Real: __KEY_NAME__
Name-Comment: __KEY_COMMENT__
Name-Email: __KEY_EMAIL__
Expire-Date: 0
%commit
EOF
}

# Prepare the batch templates by substituting env vars
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
edtpl="$tmpdir/ed25519.tpl"
rsatpl="$tmpdir/rsa.tpl"

# Build templates with injected metadata
sed -e "s/__KEY_NAME__/${KEY_NAME//\//\\/}/" \
    -e "s/__KEY_COMMENT__/${KEY_COMMENT//\//\\/}/" \
    -e "s/__KEY_EMAIL__/${KEY_EMAIL//\//\\/}/" \
    <(declare -f gen_ed25519 | sed -n '/^gen_ed25519() {$/,/^}/p' | sed '1,1d;$d') > "$edtpl"

sed -e "s/__KEY_NAME__/${KEY_NAME//\//\\/}/" \
    -e "s/__KEY_COMMENT__/${KEY_COMMENT//\//\\/}/" \
    -e "s/__KEY_EMAIL__/${KEY_EMAIL//\//\\/}/" \
    <(declare -f gen_rsa | sed -n '/^gen_rsa() {$/,/^}/p' | sed '1,1d;$d') > "$rsatpl"

# Try ed25519 first, fallback to RSA if algo unsupported
if gpg --batch --generate-key "$edtpl" 2>/tmp/gpg.err; then
  algo="ed25519/cv25519"
else
  if grep -qiE 'invalid algorithm|unknown curve|unsupported' /tmp/gpg.err; then
    echo "⚠️  ed25519/cv25519 not supported by your GnuPG. Falling back to RSA-4096…" >&2
    gpg --batch --generate-key "$rsatpl"
    algo="rsa4096"
  else
    echo "❌ GPG failed:" >&2
    cat /tmp/gpg.err >&2 || true
    exit 1
  fi
fi

# Extract PRIMARY key fingerprint (40 hex chars) – the fpr following the last 'sec'
KEY_FP="$(gpg --list-secret-keys --with-colons --fingerprint \
  | awk -F: '
    $1=="sec" {want=1; next}
    want && $1=="fpr" {fp=$10; want=0}
    END {print fp}
  ')"

if [[ -z "${KEY_FP:-}" ]]; then
  echo "❌ Could not determine primary key fingerprint" >&2
  exit 1
fi

export KEY_FP
echo "✅ Primary key fingerprint: $KEY_FP"
echo "   Algorithm: $algo"

# Export public & private keys (ASCII-armored)
gpg --export        --armor "$KEY_FP" > "$GPG_PUBLIC_KEY_FILE"
gpg --export-secret-keys --armor "$KEY_FP" > "$GPG_PRIVATE_KEY_FILE"

echo "📤 Public key   → $GPG_PUBLIC_KEY_FILE"
echo "📤 Private key  → $GPG_PRIVATE_KEY_FILE"

# Handy snippets:
cat "✅ Done."
