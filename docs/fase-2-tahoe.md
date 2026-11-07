# Fase 2 — Tahoe estável

Base: `main` do fork (upstream `macos-26` + fase 1). Máquina: MacBook Air M4, macOS 26.6.2.

## O que o Trincano da `main` já fazia no Tahoe (observado, runtime real, Paulo usando)

Logs do Trincano rodando 6+ min (`/usr/bin/log show --predicate 'subsystem == "br.com.pilutech.trincano"'`; atenção: no zsh `log` é um builtin, use `/usr/bin/log`):

| Plano (fase 0) | Observado no 26.6.2 |
|---|---|
| XPC com certificado local (sem Team ID) | **Funciona**: itens aparecem com bundle id de origem (`br.com.pilutech.printai:Item-0`, `com.kyome.RunCat:Item-0`…), o que exige o `sourcePID` do helper. O requisito `signing-identifier` foi aceito em runtime. |
| Menu Bar Layout / mover itens | **Funciona**: vários `Moving <…> to left of <…>`. 3 ocorrências de `Move events failed, posting fallback` (o fallback atua). |
| displayID nil (#922) | Não reproduzido neste Mac (sem erro `CGSCopyActiveMenuBarDisplayIdentifier returned nil`). Fallback adicionado por segurança. |
| CGWindowList nil no 26.5+ (#982) | Não reproduzido: a captura composta funciona para quase todos os itens. SCK entra só se a CGWindowList falhar. |
| Item não capturável some (#1019) | **Reproduzido**: `Some items failed capture: [Menu Bar Item (br.com.pilutech.printai:Item-0)]` (3×). |
| Permissões estáveis entre builds | Requisito designado idêntico entre builds (`certificate leaf = H"206f51…"`). Confirmação de "não pediu de novo" depende do Paulo. |
| Outros erros vistos | `CGSGetScreenRectForWindow failed with error 1000` (1×), `Missing control item for hidden section, clearing menu bar item cache` (1×). Não corrigidos; acompanhar. |

## Mudanças (todas por `cherry-pick -x` ou port parcial, com autoria preservada)

1. `0a476c5` (upstream #922, ac): `getActiveMenuBarDisplayID` cai para `CGMainDisplayID()` se a chamada SkyLight devolver nil. Limite: com o monitor externo em cima do notebook (setup do Paulo) o display do menu bar pode não ser o principal; tratar na fase 5 (perfis por tela).
2. `78a1f1a` + `0397cde` (upstream #1019, 胡伟杰): itens que não podem ser capturados usam o ícone do app como imagem (com tamanho Retina correto) em vez de sumirem do Layout/Barra do Trincano.
   - **Teste red-first**: a regra "fallback nunca substitui captura real; captura real sempre substitui fallback" virou `ImageMergePolicy` (puro) com `ImageMergePolicyTests` (4 testes). Primeiro o teste foi escrito e **falhou** (`cannot find 'ImageMergePolicy' in scope`); depois a política foi extraída e os testes passaram. O script `Tests/check-image-cache.py` do PR foi removido (substituído pelo teste Swift).
3. Port parcial do #982 (keithadler), só `ScreenCapture.swift`: tenta CGWindowList primeiro (única API que captura itens fora da tela) e, se não devolver imagem, usa ScreenCaptureKit. A parte do XPC do #982 **não** foi aplicada (o Trincano mantém a checagem via `XPCPeerPolicy`). Revisão do Lupa (PR #4): o fallback **não bloqueia mais ninguém** (ver "Correções da revisão").
4. `114d2aa` (upstream #911, tducp015): item com `sourcePID` nulo não invalida mais o cache inteiro (laço de re-cache) e o helper não repete a busca AX por 30 s para a mesma janela.

Não aplicados (e por quê):
- #984 (permissão de gravação via ScreenCaptureKit): o teste por título funciona neste Mac (o app está no estado com permissões). O PR devolve `false` no primeiro uso até a atualização assíncrona terminar; risco de pedir permissão à toa. Rever se aparecer o caso.
- #922/#982 partes de XPC e localização, #911 commits 2 e 3 (reparenting do Control Center, AX multiponto): sem sintoma no 26.6.2. Ficam como candidatos.

## Correções da revisão do Lupa (PR #4), todas red-first
1. **SCK sem bloquear a main** (`BackgroundCaptureCache`): `captureWindows` tenta CGWindowList; se falhar, devolve na hora a última imagem do ScreenCaptureKit (ou `nil`) e atualiza em segundo plano, com single-flight por chave, no máximo 2 capturas em voo, timeout de 2 s que libera o slot, resultado tardio descartado (token/geração) e cooldown após falha. Testes: provider travado chamado uma vez em 100 leituras, valor anterior mantido durante a atualização, resultado após `invalidate()` descartado, conclusão idempotente (timeout + resultado real), limite global, sem tempestade de retries.
2. **Coordenadas do SCK** (`SCKGeometry`): `SCStreamConfiguration.sourceRect` é em pontos no espaço do **display**; o código passava coordenadas globais. Agora recorta pela interseção com o display e converte global→local. Testes: display principal, à direita, **acima com origem y negativa (monitor em cima do notebook)**, à esquerda/abaixo, retângulo entre dois displays, fora do display, menor que 1 pt, Retina (escala 2).
3. **sourcePID pendente** (`PendingPIDTracker`): sem invalidar o cache global, o gerenciador lembra as janelas sem PID e `cacheItemsIfNeeded` as reconsulta só quando vencem (30/60/120/300 s de backoff), mesmo com windowIDs estáveis; mudança de apps zera o backoff (e o helper recria o estado, limpando o TTL). Testes com relógio 0/29/31 s, IDs estáveis, falha→sucesso, apps alterados, falha precoce que não escala o backoff.

4. **Slot físico x resultado** (2ª rodada do Lupa): o timeout só expira o *resultado* (a UI segue com a imagem anterior); o slot só é liberado quando o trabalho do SCK realmente termina (`finish`), porque o cancelamento do Swift é cooperativo. Operações órfãs contam no limite de 2 e bloqueiam nova captura da mesma chave. `captureWindowsAsync` checa `Task.isCancelled` antes de cada etapa SCK (conteúdo compartilhado → filtro → captura); isso **não** tem teste unitário (precisa do SCK real), só revisão e a validação em runtime. Testes: provider que ignora cancelamento (duas expiradas + várias leituras não iniciam a terceira antes do término real), mesma chave não reinicia com órfão vivo, resultado tardio após expirar descartado, cooldowns antigos podados.
5. `PendingPIDTracker.appsChanged` agora **reinicia o backoff** (retry imediato; nova falha espera 30 s) e há teste; pendentes fora do prazo nunca pedem varredura (teste, polling a cada 1 s).

## Avisos do compilador
O aviso `CGImage(windowListFromArray…)` indisponível continua (a API é o único caminho para itens fora da tela); fica documentado no código do `ScreenCapture`. Troca total por ScreenCaptureKit só quando houver um substituto para itens fora da tela.

## Medição (CPU/memória)

Mesmo método nas duas medições: Air M4, macOS 26.6.2, uso normal do Paulo, ~9 min de uptime, ocioso, 6 amostras de 10 s (`top -l 6 -s 10 -pid <pid> -stats pid,cpu,mem,idlew,power,threads`), `footprint <pid>`, `ps -o rss`.

| Métrica | Antes (main pós-fase 1, PID 98930) | Depois (main pós-fase 2, PID 63782, build 646915f) |
|---|---|---|
| CPU ocioso | 0,0 a 0,4 % (mediana 0,1 %) | 0,0 a 0,1 % (mediana 0,0 %) |
| Memória (`mem` do top) | 66 MB | 55 MB |
| RSS | 99 MB | 74 MB |
| `phys_footprint` / pico | 66 MB / 165 MB | 55 MB / 152 MB |
| Threads | 5 | 5 (4 logo após abrir) |
| Wakeups ociosos (`idlew`, acumulado) | ~225 ao fim de 9 min | 28 a 31 aos 9 min |

Leitura honesta: é uma amostra por build, com sessões de uso diferentes; a diferença de ~11 MB e menos wakeups é coerente com o fim do laço de re-cache por `sourcePID` nulo, mas **não** prova causa. A fase 3 mede com `os_signpost` e repetições.

## Runtime depois da troca (build instalado com `scripts/install.sh`)

Logs (`/usr/bin/log show --info --debug`, subsystem `br.com.pilutech.trincano`), 12 min após abrir:
- Nenhum `Missing sourcePID`, nenhum `Some items failed capture` (antes: 3× para o item do Printaí em 30 min), nenhum `Unable to display`, nenhum erro de XPC.
- Único erro: `Missing control item for hidden section, clearing menu bar item cache`, 1× na abertura (também aparecia antes; é a etapa de inicialização, ainda a investigar).
- O helper `MenuBarItemService` subiu junto (PID próprio) e os itens continuaram resolvendo o `sourcePID`.
- O Paulo confirmou que não houve novo pedido de permissão entre builds (requisito designado estável `certificate leaf = H"206f51…"`).
- Não exercitados ao vivo: o fallback ScreenCaptureKit (a CGWindowList segue funcionando neste Mac) e o retry de PID com backoff (não há item sem PID agora). Continuam cobertos só por teste unitário.
