# Roteiro de teste — fase 1 (Bancada)

Pré-requisito: Ice fechado/desinstalado. `scripts/check.sh` passa.

1. `open /Applications/Trincano.app`. Aparece o pedido de permissões do Trincano (Acessibilidade e Gravação de Tela). Conceder.
2. Se havia Ice instalado, aparece "Import your settings from Ice?". Testar "Import Settings" e "Start Fresh" (em Macs/usuários separados).
3. Reabrir o app depois de recompilar com `scripts/build.sh && scripts/install.sh`: as permissões **não** devem ser pedidas de novo (certificado local estável).
4. Sobre: mostra "Trincano", versão, aviso GPL, links Original Ice / License / Source Code. Não há opção de atualização.
5. Menu do ícone: "Trincano Settings…", "Quit Trincano"; sem "Check for Updates".
6. Rede: `lsof -i -a -p $(pgrep -x Trincano)` e Little Snitch/`nettop` não mostram conexões.
7. Menu Bar Layout carrega os itens (valida o XPC com `signing-identifier`). Se ficar em "Loading menu bar items…", anotar o log: `log stream --predicate 'subsystem == "br.com.pilutech.trincano"'`.
8. `codesign -d -r- /Applications/Trincano.app` mostra `certificate leaf = H"…"` igual entre dois builds.
