#!/usr/bin/env bash

# Detect if script is sourced or executed
_is_sourced() { [[ "${BASH_SOURCE[0]}" != "$0" ]]; }

_main() {
  set -Eeuo pipefail

  # Required environment variables
  : "${GPG_KEY_NAME:?Need to set GPG_KEY_NAME}"
  : "${GPG_KEY_COMMENT:?Need to set GPG_KEY_COMMENT}"
  : "${GPG_KEY_EMAIL:?Need to set GPG_KEY_EMAIL}"
  : "${CLUSTER_NAME:?Need to set CLUSTER_NAME}"
  : "${GPG_PUBLIC_KEY_FILE:?Need to set GPG_PUBLIC_KEY_FILE}"
  : "${GPG_PRIVATE_KEY_FILE:?Need to set GPG_PRIVATE_KEY_FILE}"

  # Expand ~ to $HOME and create directories if needed
  GPG_PUBLIC_KEY_FILE=${GPG_PUBLIC_KEY_FILE/#\~/$HOME}
  GPG_PRIVATE_KEY_FILE=${GPG_PRIVATE_KEY_FILE/#\~/$HOME}
  install -d -m 700 "$(dirname "$GPG_PUBLIC_KEY_FILE")" "$(dirname "$GPG_PRIVATE_KEY_FILE")"

  echo "🔑 Generating GPG key for Flux cluster ($CLUSTER_NAME)..."

  # Ensure GNUPGHOME exists
  export GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg}"
  install -d -m 700 "$GNUPGHOME"
  gpgconf --kill all || true
  rm -f "$GNUPGHOME"/S.gpg-agent* || true

  umask 077
  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR"' RETURN

  ED="$TMPDIR/gpg-ed25519.conf"
  RSA="$TMPDIR/gpg-rsa.conf"
  ERR="$TMPDIR/gpg.err"

  # Preferred config (ed25519 + cv25519)
  cat >"$ED" <<EOF
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: sign
Subkey-Type: ecdh
Subkey-Curve: cv25519
Subkey-Usage: encrypt
Name-Real: ${GPG_KEY_NAME}
Name-Comment: ${GPG_KEY_COMMENT}
Name-Email: ${GPG_KEY_EMAIL}
Expire-Date: 0
%commit
EOF

  # Fallback config (RSA 4096)
  cat >"$RSA" <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Subkey-Type: RSA
Subkey-Length: 4096
Subkey-Usage: encrypt
Name-Real: ${GPG_KEY_NAME}
Name-Comment: ${GPG_KEY_COMMENT}
Name-Email: ${GPG_KEY_EMAIL}
Expire-Date: 0
%commit
EOF

  algo=""
  if gpg --batch --generate-key "$ED" 2>"$ERR"; then
    algo="ed25519/cv25519"
  else
    if grep -qiE 'invalid algorithm|unknown curve|unsupported' "$ERR"; then
      echo "⚠️  ed25519/cv25519 not supported, falling back to RSA-4096…"
      gpg --batch --generate-key "$RSA" 2>>"$ERR"
      algo="rsa4096"
    else
      echo "❌ Failed to generate GPG key:"
      sed -n '1,200p' "$ERR" >&2
      return 1
    fi
  fi

  # Find primary key fingerprint (prefer lookup by email)
  GPG_KEY_FP="$(gpg --with-colons --list-secret-keys --fingerprint "$GPG_KEY_EMAIL" \
    | awk -F: '/^fpr:/ {print $10; exit}')"

  if [[ -z "${GPG_KEY_FP:-}" ]]; then
    GPG_KEY_FP="$(gpg --with-colons --list-secret-keys --fingerprint \
      | awk -F: '$1=="sec"{want=1;next} want && $1=="fpr"{print $10; exit}')"
  fi

  if [[ -z "${GPG_KEY_FP:-}" ]]; then
    echo "❌ Could not determine primary key fingerprint"
    gpg --list-secret-keys --keyid-format=long || true
    gpg --with-colons --list-secret-keys --fingerprint || true
    return 1
  fi

  export GPG_KEY_FP
  echo "✅ Primary key fingerprint: $GPG_KEY_FP"
  echo "   Algorithm: $algo"

  # Export keys
  gpg --export --armor "$GPG_KEY_FP" > "$GPG_PUBLIC_KEY_FILE"
  gpg --export-secret-keys --armor "$GPG_KEY_FP" > "$GPG_PRIVATE_KEY_FILE"

  echo "📤 Public key   → $GPG_PUBLIC_KEY_FILE"
  echo "📤 Private key  → $GPG_PRIVATE_KEY_FILE"

  echo "🧩 Updating .sops.yaml with PGP rule..."
  cat >> .sops.yaml <<EOF
  - path_regex: ^(\./)?clusters/${CLUSTER_NAME}/.+/secret-.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    pgp: "$GPG_KEY_FP"
EOF

  echo "✅ .sops.yaml updated"

  echo "🔐 Creating Kubernetes Secret in flux-system..."
  kubectl -n flux-system create secret generic sops-gpg \
    --from-file=sops.asc="$GPG_PRIVATE_KEY_FILE" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "✅ Secret sops-gpg created"

  echo "💾 Saving public key to ./clusters/${CLUSTER_NAME}/.sops.pub.asc..."
  cat "$GPG_PUBLIC_KEY_FILE" > ./clusters/${CLUSTER_NAME}/.sops.pub.asc
  echo "✅ Public key saved"

  echo "🧩 Patching flux-system kustomization to use SOPS GPG key..."
  envsubst < ./clusters/template/flux-system/patches.yaml >> ./clusters/${CLUSTER_NAME}/flux-system/kustomization.yaml
  echo "✅ flux-system kustomization patched"

  echo
  echo "🎉 All steps completed!"
}

# Run main or return if sourced
if _is_sourced; then
  _main || return $?
else
  _main
fi
