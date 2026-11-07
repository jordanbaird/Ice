#!/bin/zsh
# Gera os PNGs do ícone do app e dos glifos da barra de menus a partir dos SVG em
# docs/identidade/icone/ e registra o SHA-256 dos PNGs do app em docs/identidade/icone/SHA256SUMS
# (o IconAssetsTests confere esse registro, a cor e a ausência de arquivos órfãos).
# Requer: qlmanage e sips (já vêm no macOS).
set -euo pipefail
cd "${0:A:h}/.."
SRC=docs/identidade/icone
ASSETS=Ice/Resources/Assets.xcassets
ICONSET=$ASSETS/AppIcon.appiconset
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Ícone do app: 1024 base, reduzido para cada tamanho do .appiconset.
qlmanage -t -s 1024 -o "$TMP" "$SRC/opcao2-app.svg" >/dev/null 2>&1
BASE="$TMP/opcao2-app.svg.png"
[[ -f "$BASE" ]] || { echo "falha ao renderizar o SVG do app"; exit 1; }
typeset -A SIZES
SIZES=(icon_16x16 16 icon_16x16@2x 32 icon_32x32 32 icon_32x32@2x 64 icon_128x128 128
       icon_128x128@2x 256 icon_256x256 256 icon_256x256@2x 512 icon_512x512 512 icon_512x512@2x 1024)
for name px in "${(@kv)SIZES}"; do
  sips -z "$px" "$px" "$BASE" --out "$ICONSET/$name.png" >/dev/null
done

# Glifos da barra de menus: 18/36/54 px (@1x/@2x/@3x), templates.
render_glyph() {  # svg  nome-do-imageset
  local svg=$1 name=$2 dir=$ASSETS/ControlItemImages/FrostBar/$2.imageset
  mkdir -p "$dir"
  for pair in "18 " "36 @2x" "54 @3x"; do
    local px=${pair%% *} suffix=${pair#* }
    [[ "$suffix" == "$pair" ]] && suffix=""
    mkdir -p "$TMP/g$px"
    qlmanage -t -s "$px" -o "$TMP/g$px" "$svg" >/dev/null 2>&1
    cp "$TMP/g$px/$(basename "$svg").png" "$dir/$name$suffix.png"
  done
}
render_glyph "$SRC/opcao2-barra-escondido.svg" FrostBarFill
render_glyph "$SRC/opcao2-barra-visivel.svg" FrostBarStroke

# Registro de proveniência dos PNGs do app.
( cd "$ICONSET" && shasum -a 256 icon_*.png ) > "$SRC/SHA256SUMS"
echo "OK: $(wc -l < "$SRC/SHA256SUMS" | tr -d ' ') PNGs do app + glifos gerados; hashes em $SRC/SHA256SUMS"
