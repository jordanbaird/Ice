# Fase 4 — notch inteligente

Decisões do Paulo: itens que ficariam atrás do notch vão **automaticamente** para a Barra do Trincano, **só na tela com notch**; **clicar no notch abre a Barra**; monitor externo (em cima do notebook) não é alterado aqui (perfis por tela = fase 5).

## Como o macOS se comporta (e o que o código usa)
- `NSScreen.auxiliaryTopLeftArea/RightArea` estão em coordenadas **globais** do AppKit (já incluem a origem da tela; medido no Air M4: notch 179×32 pt entre x 646 e 825 numa tela 1470×956).
- Itens empurrados para trás do notch **continuam na seção visível**, só que invisíveis e sem clique (#715). Detecção: item visível com `bounds.minX < rightSafeArea.minX` (só o eixo x importa; x é igual em coordenadas CG e AppKit).

## O que foi feito
1. **`NotchGeometry`** (puro): notch/pílula derivado só da área segura (sem constantes), `frame`, `leftSafeArea`, `rightSafeArea`, `contains(ponto)` (a borda superior da tela conta como dentro). `NSScreen.notchGeometry` e `frameOfNotch` passam a usá-lo.
2. **Itens obscurecidos na Barra do Trincano**: `cherry-pick -x 68f93bf` do fork lxy1992 (Xinyan Lu), "Show notch-obscured items in Ice Bar": `NotchOverflowResolver` + `itemsForIceBar` mostram na seção "oculta" da Barra os itens visíveis presos atrás do notch, sem mudar o layout real. Os testes do script do fork foram portados para Swift Testing (`NotchOverflowResolverTests`, 5 casos) e o script removido.
3. **`NotchBarPolicy`** (puro) + `MenuBarSection.useIceBar`: em tela com notch e com a opção ligada, a seção usa a Barra em vez de expandir inline quando (a) já há itens atrás do notch (`notchObscuredCount`, atualizado a cada cache) ou (b) a soma das larguras dos itens que apareceriam inline (visíveis + ocultos, + sempre-ocultos se for o caso) não cabe na área à direita do notch menos 8 pt de margem. Isso trata o #570 (expandir passa do notch) sem o usuário ligar a Barra.
4. **Clique no notch** (`NotchClickPolicy`): `HIDEventManager.handleShowOnClick` alterna a Barra (`MenuBarSection.showInBar(on:)`/`hide()`) quando a opção está ligada e o clique cai em `NotchGeometry.contains`. Clique direito no notch continua sem abrir o menu de contexto (#604).
5. **Ajustes** (Geral, só aparecem se alguma tela tem notch): "Use the Trincano Bar for items behind the notch" e "Click the notch to open the Trincano Bar", ambos ligados por padrão (`AutoBarOnNotch`, `ShowBarOnNotchClick`).

## Testes (fixtures, sem aparelho)
`NotchGeometryTests`: Air M4 (medido), MacBook Pro 14" e 16" (dados dos testes do upstream), **pílula sintética** (220×40 pt, só por geometria), tela fora da origem (notebook abaixo de um monitor, deslocado), sem notch, áreas degeneradas, borda superior. `NotchBarPolicyTests` (margem exata, tela maior, desligado, sem notch, já obscurecido) e `NotchClickPolicyTests`. Os testes de política foram escritos junto com a implementação (não foi registrado o vermelho antes), os de geometria falharam primeiro (`cannot find 'NotchGeometry'`).

## Medição (Air M4, 4 min de uptime, ocioso; build instalado desta fase)
CPU 0,0 % · memória 56 MB · RSS 75 MB · footprint/pico 56/153 MB · 5 threads. Mesmos valores da fase 3 (56 MB/152 MB). Poll de janelas: 71 em 5 min (mesmo ritmo das fases anteriores), p50 2,2 ms, fora da main.
Wakeups acumulados: 43→64 em 2 min (~0,15 a 0,2/s). Nas amostras anteriores o contador parecia quase parado; um `sample` de 30 s mostrou só o poll de 5 s (`cacheItemsIfNeeded`) e o timer de 5 s do `IceBarColorManager`, **nenhuma fonte nova** (o código novo só roda ao refazer o cache). O contador do `top` não é comparável entre sessões; a fase 3 já registrava ~0,05/s. Fica anotado como pendência de investigação (reduzir/unir os timers de 5 s) em vez de afirmar regressão ou não.

## Correções da revisão do Lupa (PR #7), com o vermelho registrado
Vermelho (antes da implementação; `xcodebuild test` não compilava): `cannot find 'NotchBarSession' in scope`, `cannot find type 'NotchBarSession' in scope`, `extra argument 'menuBarHeight' in call` e `'nil' requires a contextual type` (as fixtures de `NotchClickResolver`). Depois: 101 testes passando.
1. **Tela pelo ponto do clique** (`NotchClickResolver`): a ação do notch não usa mais `NSScreen.main` (tela do foco do teclado); `HIDEventManager.handleNotchClick` roda antes do `bestScreen` e escolhe a tela pelo `NSEvent.mouseLocation` (dentro estrito primeiro, depois contando as bordas superior/direita). Os outros handlers continuam com `bestScreen`. Testes: foco no externo + clique no notebook deslocado e abaixo, borda superior, logo fora do notch (3 lados), clique direito, desligado, clique no externo, fora de todas as telas.
2. **Vertical** (`NotchOverflowResolver`, novo `menuBarHeight`): o item precisa cruzar a faixa da barra do display-alvo em coordenadas CG (`CGDisplayBounds`, altura = altura do notch); monitores empilhados dividem o mesmo intervalo x. Testes: externo acima e notebook abaixo com o mesmo x (só o item do notebook), e item abaixo da faixa ignorado.
3. **Revalidação na hora de mostrar** (`NotchBarSession`): a decisão usa larguras e contagem **medidas agora** (`liveItemWidths`, `notchObscuredItems`) a cada `show()`, para a mesma tela da Barra, e fica fixa até o `hide()` (sem virar no meio do ciclo). Testes: IDs constantes com largura mudando, transição inline → Barra → inline, decisão fixa sem nova medição, itens já obscurecidos, tela sem notch.

### Pendência mantida (sem afirmar causa): wakeups
Comparação pareada, com as mesmas opções e timers, e contagem de recaches e consultas por tela (signposts já existem: `cacheItems`, `poll.windowList`).

## Não validado ao vivo (precisa do Paulo)
- Clique no notch abrindo/fechando a Barra; a Barra automática quando a seção oculta não cabe; item realmente preso atrás do notch. No layout atual do Paulo `notchObscuredCount` ficou 0 (nenhum log "Items behind the notch" desde a instalação).
- Roteiro: (1) clicar no notch; (2) com a Barra desligada nos ajustes, mostrar a seção oculta com itens suficientes para passar de ~645 pt; (3) conferir se a Barra abre e se os itens presos atrás do notch aparecem nela.
- Pílula dos MacBook Pro novos: sem aparelho; coberta só por fixtures.
