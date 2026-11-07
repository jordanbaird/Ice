# Fase 3 — medição e responsividade

Máquina: MacBook Air M4, macOS 26.6.2, uso normal do Paulo. Branch `fase-3-responsividade`.

## Ferramentas novas
- `Shared/Utilities/Signposts.swift`: `os_signpost` (subsystem = bundle id, categoria `Performance`) em `section.show/hide`, `iceBar.show`, `search.show`, `cacheItems`, `imageCache.update`, `capture.windows`, `hid.mouseDown`, `hid.mouseMoved`, `poll.windowList` e o evento `poll.itemWindowList`.
- `scripts/measure-signposts.py [minutos]`: n, p50, p95, máximo por signpost e se rodou na thread principal.
- `scripts/measure-idle.sh [amostras]`: 6 amostras de 10 s de CPU/mem/wakeups/threads + footprint + RSS.
- `scripts/synth-mouse-move.swift`: só movimentos do cursor pela barra (sem cliques), usado com aviso ao Paulo.

## Método (antes x depois)
- **Antes** = `main` + só os signposts (commit `a2b8690`, sem mudança de comportamento). **Depois** = `5ff1f49`. Cada build instalado com `ditto`, medido aos 4 min de uptime, ocioso: 6×10 s; depois 4 passadas do cursor pela barra (~950 eventos de movimento); depois signposts dos últimos 8 min.

## Resultados

| Métrica (ocioso, 4 min) | Antes | Depois |
|---|---|---|
| CPU | 0,0 a 0,1 % | 0,0 a 0,2 % (mediana 0,0 %) |
| Memória (`top`) | 59 MB | 56 MB |
| RSS | 82 MB | 76 MB |
| `phys_footprint` / pico | 59 / 148 MB | 56 / 152 MB |
| Threads | 4 | 5 |
| Wakeups ociosos acumulados | 7 | 13 |

Orçamento da fase (CPU ~0 %, sem regressão de memória, wakeups ~30 aos 9 min): **atendido**. O aumento de 7 para 13 wakeups em 4 min (0,03 → 0,05/s) vem de a consulta de janelas agora rodar numa tarefa fora da main; está dentro do orçamento, mas é o único número que piorou.

| Signpost (8 min, build depois x antes) | Antes | Depois |
|---|---|---|
| `poll.windowList` (a cada ~4 s) | 74×, p50 5,8 ms, p95 22,9 ms, máx 37,9 ms, **na main** | 75×, p50 7,4 ms, p95 22,8 ms, máx 44,4 ms, **fora da main** |
| `hid.mouseMoved` (~960 eventos) | p50 0,012 ms, p95 0,031 ms | p50 0,011 ms, p95 0,024 ms |
| `cacheItems` na abertura | 2×, p50 1,33 s, máx 2,58 s | 2×, p50 1,21 s, máx 2,14 s |
| `imageCache.update` | 1×, 136 ms (com 2 capturas, 59 e 95 ms) | 1×, 0,2 ms (sem captura nessa janela) |

Leitura honesta:
- **Ganho comprovado**: a varredura de janelas do poll (até 38 ms, p95 23 ms) saiu da thread principal; antes bloqueava a UI a cada ~4 s. A duração em si não mudou.
- **Não medido por falta de gatilho**: o Paulo usa "mostrar ao clicar", sem "mostrar ao passar"; por isso `hid.mouseMoved` retorna cedo (0,01 ms) nos dois builds e as passadas do cursor **não exercitam** o caminho pesado. O ganho da memoização (lista de janelas + AX por evento) só aparece em clique/hover com a opção ligada e **não foi medido**. Também sem números: `iceBar.show`, `section.show/hide` e `search.show`, que exigem cliques (não autorizados). O build final está instalado com os signposts: depois de algum uso real, rodar `scripts/measure-signposts.py 60`.
- `imageCache.update` 136 ms x 0,2 ms **não** é comparável (no "antes" houve uso de UI que disparou captura; no "depois" não).
- Amostra única por build, sessões diferentes.

## Mudanças
1. Signposts nos caminhos quentes (`a2b8690`).
2. `TimedMemo` (red-first): `HIDEventManager` reaproveita por 250 ms os limites dos itens da barra e por 500 ms o frame do menu do app (AX), em vez de consultar a cada evento; invalidados quando muda o app ativo, o espaço, a tela ou a posição do controle oculto; checagens baratas (notch) antes das caras.
3. `IceBarPresentationPolicy` (red-first): a Barra do Trincano aparece na hora com as imagens em cache e atualiza em segundo plano; só espera se há itens e nenhuma imagem (antes esperava até 1 s sempre).
4. Poll de 5 s: lista de janelas fora da main (medido acima).
5. `temporarilyShow`: o alerta "sem espaço" não é mais `runModal` dentro do fluxo (abre depois que o método retorna).
6. "Missing control item for hidden section" na abertura: causa provável é as janelas dos controles ainda não existirem; agora não grava os IDs como já em cache nessa falha (próximo poll tenta de novo) e o log é `notice`. Continua aparecendo 1× na abertura (esperado); sem regressão.
7. `ImageMergePolicy` evicta imagens de itens que saíram (port manual do `d8978b0` de lxy1992/Ice, com crédito; testes red-first).

## Avaliados e não aplicados
- Timers de 3/5/10 s: o `sample` de 20 s em repouso mostrou só a consulta de 5 s (15 ms de CPU em 20 s) e os wakeups já são ~0,05/s; o timer de 3 s do cache de imagens retorna cedo quando nenhuma UI está aberta. Sem ganho mensurável, não mexi.
- `Task.sleep` de 25 ms (IceBar, busca, LayoutBar): esperas curtas de layout, sem custo ocioso; trocar por evento fica para quando houver medição (`iceBar.show`).
- Fork lxy1992: commits de IceBar ("Defer refresh", "Reuse content", "Give WindowServer time") sobrepõem a mudança 3 e conflitam; vazamento = o `d8978b0` acima. "Show notch-obscured items" fica para a fase 4.
