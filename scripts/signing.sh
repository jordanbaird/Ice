#!/bin/zsh
# Funções de assinatura do Trincano (fazer `source`, não executar).
#
# Identidade padrão: certificado local autoassinado "Trincano Local Signing", guardado
# num keychain próprio (sem senha) em ~/.trincano/signing. O requisito designado do app
# fica "identifier ... and certificate leaf = H..." e não muda entre builds, então o
# macOS (TCC) lembra Acessibilidade e Gravação de Tela.
#
# Override (para o Developer ID quando sair):
#   SIGN_IDENTITY="Developer ID Application: Nome (TEAMID)" scripts/build.sh
#   SIGN_KEYCHAIN=""   # vazio = usa os keychains normais do usuário
# Sem certificado nenhum, use SIGN_IDENTITY=- (ad hoc; o TCC perde as permissões a cada build).

TRINCANO_SIGN_DIR="${TRINCANO_SIGN_DIR:-$HOME/.trincano/signing}"
TRINCANO_KEYCHAIN="$TRINCANO_SIGN_DIR/trincano-signing.keychain-db"
LOCAL_IDENTITY="Trincano Local Signing"

ensure_local_cert() {
  mkdir -p "$TRINCANO_SIGN_DIR" && chmod 700 "$TRINCANO_SIGN_DIR"
  if [[ ! -f "$TRINCANO_KEYCHAIN" ]]; then
    local tmp; tmp="$(mktemp -d)"
    cat > "$tmp/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $LOCAL_IDENTITY
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CNF
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/openssl.cnf" \
      -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
    openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -passout pass:trincano \
      -out "$tmp/id.p12" 2>/dev/null
    security create-keychain -p "" "$TRINCANO_KEYCHAIN"
    security set-keychain-settings "$TRINCANO_KEYCHAIN"   # sem timeout de bloqueio
    security unlock-keychain -p "" "$TRINCANO_KEYCHAIN"
    security import "$tmp/id.p12" -k "$TRINCANO_KEYCHAIN" -P trincano -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k "" "$TRINCANO_KEYCHAIN" >/dev/null
    rm -rf "$tmp"
    echo "Certificado '$LOCAL_IDENTITY' criado em $TRINCANO_KEYCHAIN"
  fi
  security unlock-keychain -p "" "$TRINCANO_KEYCHAIN"
  # O xcodebuild só enxerga identidades dos keychains da lista de busca do usuário.
  if ! security list-keychains -d user | grep -q "trincano-signing"; then
    local current; current=("${(@f)$(security list-keychains -d user | tr -d '" ')}")
    security list-keychains -d user -s "${current[@]}" "$TRINCANO_KEYCHAIN"
  fi
}

# Define SIGN_IDENTITY e SIGN_KEYCHAIN (só se o usuário não passou).
resolve_signing() {
  if [[ -z "${SIGN_IDENTITY+x}" ]]; then
    ensure_local_cert
    SIGN_IDENTITY="$LOCAL_IDENTITY"
    SIGN_KEYCHAIN="$TRINCANO_KEYCHAIN"
  fi
  SIGN_KEYCHAIN="${SIGN_KEYCHAIN-}"
  if [[ -n "$SIGN_KEYCHAIN" ]]; then
    SIGN_FLAGS=(OTHER_CODE_SIGN_FLAGS="--keychain $SIGN_KEYCHAIN")
  else
    SIGN_FLAGS=()
  fi
}
