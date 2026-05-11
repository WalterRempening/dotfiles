#!/usr/bin/env bash
# Import Caddy Local Authority root + intermediate CA into all mise-installed Java truststores.
# Usage: sudo ./import-caddy-ca.sh

set -euo pipefail

# Caddy PKI location — check Homebrew first, then user data dir
if [ -d "/opt/homebrew/var/lib/caddy/pki/authorities/local" ]; then
  CADDY_PKI="/opt/homebrew/var/lib/caddy/pki/authorities/local"
elif [ -d "$HOME/Library/Application Support/Caddy/pki/authorities/local" ]; then
  CADDY_PKI="$HOME/Library/Application Support/Caddy/pki/authorities/local"
else
  echo "ERROR: Caddy PKI directory not found"
  exit 1
fi
PASS="changeit"
MISE_JAVA="$HOME/.local/share/mise/installs/java"

CERTS=(
  "caddy-local-ca:$CADDY_PKI/root.crt"
  "caddy-local-intermediate:$CADDY_PKI/intermediate.crt"
)

for entry in "${CERTS[@]}"; do
  file="${entry#*:}"
  if [ ! -f "$file" ]; then
    echo "WARN: $file not found, skipping"
    continue
  fi
  echo "Certificate: ${entry%%:*} → $file"
done
echo ""

for dir in "$MISE_JAVA"/*/; do
  [ -L "${dir%/}" ] && continue

  ver=$(basename "$dir")
  ts="$dir/lib/security/cacerts"
  [ ! -f "$ts" ] && ts="$dir/jre/lib/security/cacerts"
  [ ! -f "$ts" ] && { echo "SKIP $ver — no truststore found"; continue; }

  for entry in "${CERTS[@]}"; do
    alias="${entry%%:*}"
    file="${entry#*:}"
    [ ! -f "$file" ] && continue

    if keytool -list -keystore "$ts" -storepass "$PASS" -alias "$alias" >/dev/null 2>&1; then
      echo "OK   $ver — $alias"
    else
      keytool -importcert -trustcacerts -alias "$alias" -file "$file" -keystore "$ts" -storepass "$PASS" -noprompt >/dev/null 2>&1
      echo "ADD  $ver — $alias"
    fi
  done
done
