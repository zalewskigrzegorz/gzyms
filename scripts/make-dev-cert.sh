#!/usr/bin/env bash
# One-time per Mac: a self-signed "Gzyms Dev" code-signing identity in the login keychain.
# A stable signature keeps macOS permission grants (Full Disk Access, Accessibility) across rebuilds.
# Trusting it for code signing asks for your password / Touch ID once.
set -euo pipefail
# /usr/bin/openssl (LibreSSL) on purpose: macOS `security import` rejects PKCS#12 files from OpenSSL 3+.
NAME="Gzyms Dev"
if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "$NAME already exists"; exit 0
fi
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cat > "$dir/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$dir/cert.cnf" \
  -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
pass=$(/usr/bin/openssl rand -hex 12)
/usr/bin/openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" -name "$NAME" \
  -out "$dir/id.p12" -passout "pass:$pass" 2>/dev/null
security import "$dir/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$pass" -T /usr/bin/codesign >/dev/null
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db "$dir/cert.pem"
security find-identity -v -p codesigning | grep "\"$NAME\""
