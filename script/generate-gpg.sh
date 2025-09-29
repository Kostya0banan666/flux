#!/usr/bin/env bash
set -euo pipefail

# Check required environment variables
: "${KEY_NAME:?Need to set KEY_NAME}"
: "${KEY_COMMENT:?Need to set KEY_COMMENT}"
: "${KEY_EMAIL:?Need to set KEY_EMAIL}"
: "${CLUSTER:?Need to set CLUSTER}"
: "${PUB_KEY_FILE:?Need to set PUB_KEY_FILE}"
: "${SECRET_KEY_FILE:?Need to set SECRET_KEY_FILE}"

echo "🔑 Generating GPG key for Flux ($CLUSTER)..."

# Generate GPG key (without passphrase, suitable for automated decryption)
gpg --batch --generate-key <<EOF
%no-protection
Key-Type: ed25519
Key-Curve: ed25519
Key-Usage: sign
Subkey-Type: cv25519
Subkey-Usage: encrypt
Name-Real: ${KEY_NAME}
Name-Comment: ${KEY_COMMENT}
Name-Email: ${KEY_EMAIL}
Expire-Date: 0
%commit
EOF

# Retrieve FULL fingerprint (40 characters) of the newly created key
KEY_FP=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/ {print $10}' | tail -n1)
export KEY_FP
echo "✅ Full Fingerprint: $KEY_FP"

# Export public key
gpg --export -a "$KEY_FP" > "$PUB_KEY_FILE"
echo "📤 Public key saved to $PUB_KEY_FILE"

# Export private key
gpg --export-secret-keys -a "$KEY_FP" > "$SECRET_KEY_FILE"
echo "📤 Private key saved to $SECRET_KEY_FILE"

echo "✅ Done! KEY_FP is now available in your current session."
