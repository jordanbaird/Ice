#!/bin/bash
# One-time setup: create the self-signed certificate that signs every release.
# Usage: ./script/create-release-cert.sh [--import] [--force]
#
# Why: macOS (TCC) remembers Accessibility / Screen Recording grants by the
# app's designated requirement. Ad-hoc builds pin a cdhash that changes on
# every build, so each update looked like a new app and lost its grants.
# Signed with one stable certificate, the requirement becomes
# "identifier com.jordanbaird.Ice and certificate root = <this cert>", which
# stays the same across releases — users grant permissions once.
#
# Keep the .p12 and its password safe (password manager / offline backup).
# Losing it means a new certificate, and every user re-grants once more.
#
#   --import  also import the identity into your login keychain so
#             ./script/build.sh signs local builds the same way
#   --force   overwrite an existing certificate (users will re-grant once)
set -e

NAME="Ice Release"
OUT_DIR="${ICE_SIGNING_DIR:-$HOME/.ice-signing}"
P12="$OUT_DIR/ice-release.p12"
PASS_FILE="$OUT_DIR/ice-release.password"
REPO="cavaldos/Ice"
# The system LibreSSL writes PKCS#12 files that `security import` accepts;
# Homebrew OpenSSL 3 defaults to algorithms macOS cannot read.
OPENSSL=/usr/bin/openssl

IMPORT=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --import) IMPORT=1 ;;
    --force) FORCE=1 ;;
    *) echo "usage: $0 [--import] [--force]"; exit 1 ;;
  esac
done

if [[ -f "$P12" && $FORCE -eq 0 ]]; then
  echo "$P12 already exists — reuse it, do not create a new one."
  echo "A new certificate makes every user re-grant permissions. Pass --force if that is intended."
  exit 1
fi

mkdir -p -m 700 "$OUT_DIR"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

# 20 years: the certificate must outlive the app, since replacing it resets grants.
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 7300 \
  -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

PASSWORD=$("$OPENSSL" rand -hex 24)
"$OPENSSL" pkcs12 -export -name "$NAME" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$P12" -passout "pass:$PASSWORD"
printf '%s' "$PASSWORD" > "$PASS_FILE"
chmod 600 "$P12" "$PASS_FILE"

echo "Created:"
echo "  $P12"
echo "  $PASS_FILE"
"$OPENSSL" x509 -in "$WORK/cert.pem" -noout -subject -enddate -fingerprint -sha1 | sed 's/^/  /'

if [[ $IMPORT -eq 1 ]]; then
  security import "$P12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$PASSWORD" -T /usr/bin/codesign
  echo "Imported \"$NAME\" into the login keychain."
fi

cat <<EOF

Next: add the GitHub secrets the release workflow signs with:

  base64 -i "$P12" | gh secret set MACOS_CERT_P12 -R $REPO
  gh secret set MACOS_CERT_PASSWORD -R $REPO < "$PASS_FILE"

Then back up $OUT_DIR somewhere safe.
EOF
