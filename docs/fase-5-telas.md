# Fase 5 — perfis por tela e multi-monitor

Contexto: hoje só o Air M4 (com notch); quando o Paulo usar monitor externo, ele fica **em cima** do notebook. Sem monitor físico: lógica em módulos puros com fixtures (notebook em y 0…956 e externo acima, em coordenadas AppKit; no CG o externo tem y negativo) e roteiro ao vivo para o resto.

## O que foi feito (todos com testes)
1. **Display da barra de menus ativa** (`ActiveMenuBarDisplayResolver`, limite do #922): quando `CGSCopyActiveMenuBarDisplayIdentifier` devolve nil, o fallback era `CGMainDisplayID()`; agora é o display sob o ponteiro e só então o principal. **Vermelho comportamental** (3 falhas de asserção contra o resolver que devolvia o principal): fallback pelo ponteiro (externo em cima), ID do sistema de um display já desconectado, e confiar no ID do sistema quando válido. Verde depois.
2. **Rehide temporizado por tela** (`RehideGeometry`): o timer comparava o ponteiro com `NSScreen.main.visibleFrame.maxY`; com o monitor em cima os intervalos de y das telas não se sobrepõem. Agora julga contra a **tela-alvo** da seção (barra de menus ativa), com limites em x e y. **Vermelho comportamental** (2 falhas): ponteiro em outra tela e ponteiro ao lado da tela.
3. **Perfis por UUID de display** (`DisplayProfiles`, `DisplayBarMode`, `DisplayBarPolicy`): por tela, "seguir 'Use Trincano Bar'", "Barra do Trincano" ou "expandir a barra de menus". O UUID é estável entre reconexões. Persistido em `DisplayProfiles` (JSON tolerante: dados corrompidos viram vazio; modo desconhecido vira "seguir"). Padrão = comportamento de antes. Ajuste em Geral, **só aparece com 2 ou mais telas**. A camada de armazenamento continua `UserDefaults` local (sem iCloud, como decidido).
4. **Tela-alvo da seção** (`MenuBarSection.screenForIceBar`): passa a ser a tela com a barra de menus ativa (antes `NSScreen.main`, a tela do foco do teclado); em tela cheia, a do ponteiro. A decisão "usar a Barra" por tela é fixada em cada `show()`, junto com a do notch.
5. **Esconder menus do app** (`MenuBarManager`): usava a opção global `useIceBar` e `NSScreen.main`; agora usa o modo efetivo das seções (perfil/notch) e a tela da barra de menus ativa.
6. **Troca automática ao conectar/desconectar/mudar a principal** (`DisplayTopology` + `DisplayTopologyMonitor`): a cada `didChangeScreenParameters` (debounce 0,3 s) compara os displays por UUID e reage: refaz o cache de itens e invalida geometria; se a Barra estava no display que sumiu, fecha a Barra e esconde a seção. Os perfis valem por UUID e portanto "voltam" sozinhos na reconexão. Testes: conectar, desconectar, trocar a principal, mudar a resolução, lista reordenada = sem mudança, e as reações (Barra só fecha se estava no display removido).

Testes de 3 e 6 foram escritos junto com a implementação (sem registrar o vermelho); 1 e 2 têm vermelho comportamental registrado.

## Dores do upstream: o que dá e o que fica para o roteiro ao vivo
- **#922 (limite do fallback)**: tratado (item 1).
- **#988 (barra se comporta diferente conforme a tela da janela ativa)**: parte da causa era `NSScreen.main` (foco do teclado) usado como "a tela da barra de menus"; itens 2, 4 e 5 trocam por tela-alvo. **Precisa de monitor** para confirmar o espaçamento em tela cheia.
- **#929 (barra do notebook "enorme" ao alternar o foco com monitor externo) e #698 (itens 2–3× maiores)**: não reproduzíveis sem aparelho; hipótese: dimensões/escala medidas na tela errada (agora a tela-alvo é a da barra ativa). Não afirmo correção.
- **#1023 (overlay da tela embutida desenhado como retângulo preto no externo)**: o `MenuBarAppearanceManager` cria um painel por tela; não alterado sem como validar.
- **#223/#188/#797/#703/#783 (Barra só na embutida / só com notch / conjuntos por laptop)**: cobertos pelos perfis por display + a Barra automática da fase 4.

## Roteiro ao vivo (precisa do monitor externo, em cima do notebook)
1. Conectar o monitor: em **Ajustes → Geral** aparece "Displays" com um seletor por tela; logs: `Display change: +1 -0 main:false reconfigured:0`.
2. Definir o notebook como "Trincano Bar" e o externo como "Expandir a barra de menus"; clicar em área vazia da barra de cada tela: a Barra só no notebook, expansão inline no externo.
3. Com a Barra aberta no externo, desconectar o monitor: a Barra fecha sozinha e os itens são relidos.
4. Com o foco do teclado no externo e o ponteiro no notebook, clicar no notch: a Barra abre (fase 4); sem mexer em `NSScreen.main`.
5. Alternar o foco entre as telas várias vezes e conferir o tamanho da barra/Barra do notebook (#929/#698) e, com vídeo em tela cheia num dos monitores, a Barra/overlay no outro (#988/#1023). Anotar prints.
6. Deixar o timer de rehide ("Rehide: timed") e mover o ponteiro entre as telas: só fecha quando o ponteiro sai da barra de menus da tela-alvo.

## Medição

### Comparação pareada de wakeups (pendência da fase 4)
Mesma janela de uptime (9–14 min), mesmas opções e timers (nenhum timer novo na fase 5), `top -l 2 -s 300` + signposts dos mesmos 5 min. **Antes** = main `84b3849` (fase 4); **depois** = esta branch. O uso do Paulo foi diferente nas duas janelas, então a comparação é só indicativa:

| 5 min, mesma janela de uptime | Antes (fase 4) | Depois (fase 5) |
|---|---|---|
| Wakeups ociosos (delta do `top`) | 124 → 222 = **98** (0,33/s) | 253 → 392 = **139** (0,46/s) |
| `poll.windowList` (poll de 5 s) | 60 | 72 |
| `hid.mouseMoved` / `hid.mouseDown` | 2837 / 21 | 2086 / 33 |
| Usos da Barra (`iceBar.show`) / `section.show` | 0 / 0 | 12 / 8 |
| Capturas (`capture.windows`) / `imageCache.update` | 0 / 0 | 87 / 15 |

Leitura honesta: na janela "depois" o Paulo abriu a Barra 12 vezes (cada uma com captura de imagens), o que acorda o processo; na janela "antes" não houve nenhum uso. Os dois números de wakeups **não** isolam o custo ocioso e eu não afirmo regressão nem ausência. O que se pode afirmar: a fase 5 **não adiciona timers** (o `DisplayTopologyMonitor` só reage a `didChangeScreenParametersNotification`), e o poll de 5 s tem o mesmo ritmo (60 a 72 por 5 min, varia com troca de apps). Para fechar a pendência é preciso uma janela sem uso nos dois builds (o `measure-idle.sh` com o Mac parado).

### Memória
Footprint 68 MB (pico 166 MB) e RSS 74 MB aos 14 min **depois de 12 usos da Barra e 87 capturas**; ocioso a 4 min o build desta família fica em 56–59 MB. Sem regressão ociosa conhecida; a alta é uso (cache de imagens).

### Primeiros números reais de uso da Barra (n=12, Air M4, 26.6.2)
`iceBar.show` p50 **34 ms**, p95 58 ms (fora da main); `section.show` p50 1,8 ms, p95 9,5 ms; `section.hide` p50 2,4 ms; `hid.mouseDown` p50 1,8 ms, p95 13,9 ms, máx 34,6 ms (com leitura fresca); `imageCache.update` p50 24 ms. Estes são os números que faltavam na fase 3 (a Barra aparece em ~34 ms: aparece com o cache e atualiza em segundo plano).

### Evidência da fase 4 ao vivo
Nos logs da mesma janela: `Items behind the notch: 1` seguido de `Items behind the notch: 0` quando o Paulo moveu o item do Printaí (`Moving <printai…> to left of <Chrome…>`): a detecção de item atrás do notch funcionou no Air M4. Também 1× `Move events failed, posting fallback` (o fallback atuou) e o `Missing control item…` da abertura.
