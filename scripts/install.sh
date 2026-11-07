#!/bin/zsh
# Instala o build em /Applications/Trincano.app com ditto e abre.
# Nunca fecha o Ice: se ele estiver aberto, só avisa (dois gerenciadores brigam pela barra).
set -euo pipefail
cd "${0:A:h}/.."
CONFIG="${1:-Release}"
SRC="build/Build/Products/$CONFIG/Trincano.app"
[[ -d "$SRC" ]] || { echo "Build não encontrado: rode scripts/build.sh primeiro"; exit 1; }
if pgrep -x Ice >/dev/null; then
  echo "AVISO: o Ice está aberto. Feche-o (ou desinstale) antes de usar o Trincano; ele não foi fechado."
fi
pkill -x Trincano 2>/dev/null && sleep 1 || true
rm -rf /Applications/Trincano.app
ditto "$SRC" /Applications/Trincano.app
echo "Instalado em /Applications/Trincano.app"
if pgrep -x Ice >/dev/null; then
  echo "Não abri o Trincano porque o Ice está aberto. Quando o Ice for fechado: open /Applications/Trincano.app"
else
  open /Applications/Trincano.app
fi
