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

## Avisos do compilador
O aviso `CGImage(windowListFromArray…)` indisponível continua (a API é o único caminho para itens fora da tela); fica documentado no código do `ScreenCapture`. Troca total por ScreenCaptureKit só quando houver um substituto para itens fora da tela.

## Medição (CPU/memória)

Antes = build da `main` rodando para o Paulo (PID 98930, 9 min de uso, Air M4, ocioso, sessão normal, 6 amostras de 10 s com `top`):

| Métrica | Antes (main) | Depois (fase 2) |
|---|---|---|
| CPU ocioso | 0,0 a 0,4 % (mediana 0,1 %) | pendente: precisa rodar o build novo |
| Memória (`mem` do top) | 66 MB | pendente |
| `phys_footprint` / pico | 66 MB / 165 MB | pendente |
| Threads | 5 | pendente |

O "depois" não foi medido porque instalar o build novo fecharia o Trincano que o Paulo está usando. Roteiro: `scripts/install.sh`, 10 min de uso, repetir `top -l 6 -s 10 -pid $(pgrep -x Trincano) -stats pid,cpu,mem,idlew,power,threads` e `footprint $(pgrep -x Trincano)`.
