# Trincano — plano inicial (fase 0)

Data: 2026-11-07. Só análise e plano; nada implementado. Mac de teste: MacBook Air M4 (Mac16,12), macOS 26.6.2 (25G83), Xcode 26.3, Swift 6.2.4.

Pedido do Paulo: app mais responsivo e inteligente, principalmente em Macs com notch (Air M4 e os MacBook Pro novos, onde o notch é uma pílula).

## 1. Base escolhida: `upstream/macos-26` (6d74d25, 2025-09-20)

| Branch | À frente da main | Situação |
|---|---|---|
| `main` | 0 | Último código de produto é da série 0.11.12 (2024). Sem suporte ao Tahoe. |
| `macos-26` | 77 | Reescrita para o Tahoe: `MenuBarItemService` (XPC), `HIDEventManager`, captura nova, UI nova. Versão `0.11.13-dev.2a`. |
| `macos-26-old` | 44 | Versão anterior da mesma reescrita. Descartar. |
| `profiles` | 7 (37 atrás) | Perfis por tela, parado desde 2024-10 e muito defasado. Só serve de referência de ideia. |

Por que `macos-26`: é o único ramo que roda no Tahoe, e é onde estão os PRs da comunidade (cerca de metade dos ~50 PRs abertos mira `macos-26`). O instalado do Paulo (`/Applications/Ice.app`, 0.11.13-dev.2, Team `K2ATHQPJDP`) é desse mesmo ramo.

Ressalva: o `main` do fork (11edd39) tem 2 commits que o `macos-26` não tem (só templates de issue). Irrelevante. A branch `plano-inicial` parte de `upstream/macos-26`; o `main` do fork continua como espelho do upstream.

## 2. Build em Release no Tahoe

Comando: `xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Release CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build`

- **Compila**: `BUILD SUCCEEDED` em ~37 s (SPM já em cache), 0 erros. 5 avisos: `CGImage(windowListFromArray…)` está marcada como indisponível no SDK 26 (`ScreenCapture.swift:81`), `AppIntents` (inofensivo) e SwiftLint ausente.
- **Rodar**: **não rodei** o build novo. O Ice oficial do Paulo está aberto (PID 5307, 8 dias) com o mesmo bundle id `com.jordanbaird.Ice`, e as permissões (Acessibilidade, Gravação de Tela) pedem o Paulo. Fica como "compila; runtime pendente" até a fase 1 (bundle id próprio, que permite rodar lado a lado).
- **Assinatura**: o Mac só tem a identidade "Printai Local Signing", **não confiável** (0 identidades válidas). Logo o build é ad-hoc. Consequências: (a) o cdhash muda a cada build e o macOS pode pedir as permissões de novo a cada instalação; (b) o `MenuBarItemService` exige `.isFromSameTeam()`, que nunca passa sem Team ID (ver abaixo).

### Linha de base medida (Ice instalado, 8 dias de uptime, M4, Tahoe 26.6.2)

- CPU em repouso: 0,1 a 1,3 %. RSS 28 MB, `phys_footprint` 127 MB (pico 205 MB).
- Logs: `log show --predicate 'subsystem == "com.jordanbaird.Ice"'` volta vazio (logs `debug` não persistem). A fase 1 precisa de logs/`os_signpost` próprios para medir.

### O que quebra no Tahoe (dos PRs/issues do upstream; **a confirmar no runtime na fase 1**)

| Quebra | Causa | Fonte |
|---|---|---|
| "Loading menu bar items…" para sempre em build sem Team ID | `.isFromSameTeam()` no XPC rejeita todo peer sem Team ID | PRs [#950](https://github.com/jordanbaird/Ice/pull/950), [#982](https://github.com/jordanbaird/Ice/pull/982), [#1027](https://github.com/jordanbaird/Ice/pull/1027) |
| "Unable to display menu bar items" no 26.4+ | `CGSCopyActiveMenuBarDisplayIdentifier` devolve nil | PR [#922](https://github.com/jordanbaird/Ice/pull/922) |
| Camada de imagens vazia no 26.5+ | `CGWindowListCreateImageFromArray` devolve nil; precisa fallback ScreenCaptureKit | PR #982 |
| Itens que não dá para capturar somem do Layout/Ice Bar | sem imagem por janela | PR [#1019](https://github.com/jordanbaird/Ice/pull/1019) |
| Não compila no Xcode 27 | CompactSlider (`ambiguous use of 'opacity'`) | PR #1027 |
| macOS 27 beta: layout "girando" | mudança de comportamento no 27 | [#965](https://github.com/jordanbaird/Ice/issues/965), PR [#995](https://github.com/jordanbaird/Ice/pull/995) |

Observação sobre o item 1: remover o requisito de mesmo time (como os PRs fazem) **enfraquece** a checagem do XPC. Melhor caminho: certificado estável (ver pergunta Q1). Sem certificado, só relaxar em build de desenvolvimento (`#if DEBUG`), nunca no build de uso.

## 3. Dores reais no upstream (issues abertas; ~400 abertas, o projeto responde pouco)

**Tahoe em geral** — [#823](https://github.com/jordanbaird/Ice/issues/823) e [#760](https://github.com/jordanbaird/Ice/issues/760) ("vai ter versão estável?", 56 e 73 👍) mostram que o ramo `macos-26` está parado há ~14 meses. Comunidade mantém forks soltos ([#966](https://github.com/jordanbaird/Ice/issues/966), `lxy1992/Ice`). Falhas recorrentes: [#711](https://github.com/jordanbaird/Ice/issues/711) / [#679](https://github.com/jordanbaird/Ice/issues/679) "Unable to display menu bar items" (36 e 25 comentários), [#665](https://github.com/jordanbaird/Ice/issues/665) Ice Bar invisível, [#664](https://github.com/jordanbaird/Ice/issues/664) layout quebrado, [#946](https://github.com/jordanbaird/Ice/issues/946) itens caem em "sempre ocultos" no 26.5, [#867](https://github.com/jordanbaird/Ice/issues/867) crash (EXC_BREAKPOINT) no 26.2.

**Notch** (as que mais importam ao Paulo):
- [#715](https://github.com/jordanbaird/Ice/issues/715): item empurrado para dentro do notch **simplesmente some**, e nem o "mostrar ao clicar" o traz de volta.
- [#570](https://github.com/jordanbaird/Ice/issues/570) (14 👍): ao expandir o oculto, itens passam do notch e ficam invisíveis; pede usar o Ice Bar automaticamente quando faltar espaço.
- [#797](https://github.com/jordanbaird/Ice/issues/797) (12 👍) e [#703](https://github.com/jordanbaird/Ice/issues/703) (11 👍): Ice Bar só em telas com notch. Relacionadas: [#223](https://github.com/jordanbaird/Ice/issues/223) (68 👍, só na tela embutida), [#188](https://github.com/jordanbaird/Ice/issues/188) (21 👍), [#303](https://github.com/jordanbaird/Ice/issues/303) (24 👍, por resolução), [#783](https://github.com/jordanbaird/Ice/issues/783) (conjuntos separados para o laptop com monitor externo), [#242](https://github.com/jordanbaird/Ice/issues/242) (barras por tela).
- [#406](https://github.com/jordanbaird/Ice/issues/406) vs [#604](https://github.com/jordanbaird/Ice/issues/604): clicar no notch abre a barra (um quer, outro não) → vira configuração.
- [#82](https://github.com/jordanbaird/Ice/issues/82) (37 👍): fundo preto para "esconder" o notch. [#260](https://github.com/jordanbaird/Ice/issues/260): barra cortada no notch com resolução menor.

**Multi-tela**: [#929](https://github.com/jordanbaird/Ice/issues/929) (barra enorme no MacBook Air com monitor externo), [#698](https://github.com/jordanbaird/Ice/issues/698) (itens 2-3× maiores), [#987](https://github.com/jordanbaird/Ice/issues/987), [#988](https://github.com/jordanbaird/Ice/issues/988), [#1023](https://github.com/jordanbaird/Ice/issues/1023) (overlay da tela embutida desenhado como retângulo preto no externo), [#1028](https://github.com/jordanbaird/Ice/issues/1028) (ícone do Ice pinta por cima do vizinho no Tahoe).

**Lentidão, memória, travamento**: [#819](https://github.com/jordanbaird/Ice/issues/819) (WindowServer cresce 16 KB a cada 2-4 s só com Gravação de Tela; **hipótese a medir**: bate com o timer de 3 s do `MenuBarItemImageCache`), [#530](https://github.com/jordanbaird/Ice/issues/530) (4 GB após muito tempo), [#578](https://github.com/jordanbaird/Ice/issues/578) (CPU > 15 %), [#777](https://github.com/jordanbaird/Ice/issues/777) (congela durante captura de tela), [#908](https://github.com/jordanbaird/Ice/issues/908) (congelou o sistema/kernel panic após 33 h), [#968](https://github.com/jordanbaird/Ice/issues/968) e [#974](https://github.com/jordanbaird/Ice/issues/974) (Ice trava ou deixa menus órfãos quando um dropdown nativo trava; Ice não provado como causa).

**Soluções prontas na comunidade (GPL, reaproveitáveis com crédito)**:
- Fork `lxy1992/Ice` (branches `codex/*`, 18 commits sobre `macos-26`): estabilização no 26, "Evict stale menu bar item images", "Throttle unresolved source PID lookups", "Defer Ice Bar refresh until after first frame", "Reuse Ice Bar content after first frame", "Give WindowServer time to commit Ice Bar", fix de memória e **"Show notch-obscured items in Ice Bar"**.
- PRs [#911](https://github.com/jordanbaird/Ice/pull/911) (cliques falhando no Tahoe com notch; "SourcePID cache thrash"), [#795](https://github.com/jordanbaird/Ice/pull/795) (Ice Bar automático por largura de tela), [#612](https://github.com/jordanbaird/Ice/pull/612) (configuração por tela), [#804](https://github.com/jordanbaird/Ice/pull/804) (expirar CGImages do cache), [#982](https://github.com/jordanbaird/Ice/pull/982), [#922](https://github.com/jordanbaird/Ice/pull/922), [#984](https://github.com/jordanbaird/Ice/pull/984), [#1019](https://github.com/jordanbaird/Ice/pull/1019).
- Regra: `git cherry-pick -x` (preserva a autoria), revisar cada diff, rodar tudo local. Nenhum é adotado às cegas.

## 4. Onde o app perde responsividade e como medir

Mapa (arquivo:linha na base `6d74d25`):

| Ponto | Hoje | Suspeita |
|---|---|---|
| `MenuBarItemManager.swift:57` | `Timer` de 5 s + `runningApplications` com `delay 0.25` + `debounce 1 s` → `cacheItemsIfNeeded()` | Atraso de até ~1 s para refletir mudança; trabalho periódico mesmo parado. |
| `MenuBarItemImageCache.swift:78` | `Timer` de 3 s + mudança de espaço/tela + cor média + cache de itens, `throttle 0.5 s` → captura de imagens | Captura periódica de janelas (ScreenCapture) mesmo sem Ice Bar/Layout aberto; candidata a [#819]. |
| `ScreenCapture.swift:81` | `CGImage(windowListFromArray…)` | Falha no 26.5+; precisa SCK como fallback, e custa mais. |
| `MenuBarManager.swift:142`, `IceBarColorManager.swift:85`, `MenuBarOverlayPanel.swift:196/203` | Timers de 5 s e 10 s para cor média/overlay | Amostragem de cor periódica, mesmo sem mudança. |
| `HIDEventManager.swift` (577 linhas) | `CGEventTap`/`NSEvent` globais, sleeps de 100/250 ms, `isMouseInsideMenuBarItem` consulta lista de janelas a cada evento (linha ~495) | Lista de janelas dentro do caminho de evento do mouse = latência do "mostrar ao passar/clicar". |
| `MenuBarItemManager.temporarilyShow` (~1360) | `getMenuBarItems`, AX para largura do menu do app, `alert.runModal()` se faltar espaço | `runModal` bloqueia a main thread; é o caso do notch (#715/#570). |
| `IceBar.swift:415/432`, `MenuBarSearchPanel.swift:379`, `LayoutBarPaddingView.swift:112` | `Task.sleep` de 25 ms para esperar layout | Esperas fixas; bom candidato a trocar por evento. |
| `AppState.swift:93/117-163`, `MenuBarOverlayPanel.swift:112-211` | Cascata de `debounce/throttle` de 50-100 ms em troca de espaço/tela/app ativo | Soma de atrasos na troca de espaço. |
| 100 % `Task`/Combine em `@MainActor` | Concorrência misturada; Swift 5 mode (`SWIFT_VERSION = 5.0`) | Difícil provar ausência de bloqueio da main sem Swift 6. |

**Como medir (antes/depois, sempre no Air M4 e, se o Paulo tiver, com monitor externo):**
1. **Instrumentar** com `os_signpost` (subsystem do Trincano): `cacheItems`, `imageCache.update`, `captureWindows`, `hover→show`, `click→show`, `iceBar.present`, `section.show/hide`. Medir p50/p95 em `xctrace`/Instruments (Points of Interest) ou `log stream`.
2. **Repouso**: `top -l 20 -s 5 -pid <pid> -stats pid,cpu,mem,idlew,power` e `footprint <pid>` (atual: 0,1-1,3 % CPU, 127 MB). Alvo: wakeups/s menores e CPU ~0 com tudo fechado.
3. **Latência de interação**: tempo entre o evento de mouse e o item visível (signpost + gravação de tela a 60 fps para conferência visual).
4. **Crescimento**: `footprint` do Trincano e do **WindowServer** a cada 5 min por 1 h com e sem Gravação de Tela (testa a hipótese [#819]).
5. **Energia**: `powermetrics --samplers cpu_power -n 12 -i 5000` (sudo; o Paulo roda) ou o campo POWER do `top`.
6. Guardar os números em `docs/medicoes/AAAA-MM-DD-<nome>.md` com versão/commit. Meta mínima por fase: nenhuma métrica piora; a que a fase mira melhora ≥ 30 %.

## 5. A parte "inteligente" para notch

Fatos medidos neste Mac (`swift` direto): tela embutida `frame (0,0,1470,956)` pontos, `safeAreaInsets.top = 32`, `auxiliaryTopLeftArea = (0,924,646,32)`, `auxiliaryTopRightArea = (825,924,645,32)` → **o notch tem 179 pt de largura por 32 pt de altura**, e as áreas auxiliares estão em **coordenadas globais** (o `y` 924 inclui a origem do frame). O código atual (`Extensions.swift:531`, `frameOfNotch`) as usa assim, o que está certo para esta tela na origem; **a verificar com o monitor externo à esquerda/acima** (frame da embutida com origem diferente de zero, cenário de #988). No notch em forma de pílula (MacBook Pro novos) o formato e a largura podem mudar; o plano não assume constante nenhuma, só `auxiliaryTop*Area`.

Detecção (camada pura, testável):
- `NotchGeometry` (nova, sem AppKit): entra `frame`, `safeAreaInsets`, `auxiliaryTopLeft/RightArea`; sai `notchRect?`, `usableLeft` (onde ficam os menus do app), `usableRight` (onde ficam os itens do sistema), tudo em coordenadas globais. Pílula e notch retangular tratados igual (só retângulo envolvente + margem configurável).
- Reagir a `didChangeScreenParametersNotification` e a mudança de resolução (o notch escala; #260).

Comportamento inteligente, por ordem de valor:
1. **Aviso e proteção contra item escondido atrás do notch** (#715, #570): o Trincano calcula a largura total dos itens visíveis + itens do app e detecta quando algum cairia sobre o notch. Resposta configurável: (a) realocar o item para o **Trincano Bar** automaticamente, (b) avisar com um selo discreto no ícone, (c) não fazer nada. Padrão: (a) só nessa tela.
2. **Barra abaixo da barra só onde faz sentido** (#797, #703, #223, #303): "Usar o Ice Bar" vira por tela, com perfis: **tela embutida com notch** = barra automática quando falta espaço; **monitor externo** = expandir inline (há espaço). Auto por largura/notch, conforme PR #795.
3. **Perfis por tela** (#783, #242, PR #612): chave = identificador estável da tela (UUID do display, não o índice). Perfil "Só o laptop" e "Com monitor externo" aplicados quando a topologia muda. Reaproveitar ideias do ramo `profiles`, sem merge (muito defasado).
4. **Clique no notch** (#406 × #604): opção "clicar no notch abre a barra", desligada por padrão (BetterTouchTool etc. usam o notch).
5. **Fundo do notch** (#82): tinta preta sólida para fundir o notch (já existe o formato "inset"; falta preto sólido) e correção de #260.
6. **Mostrar o mínimo de cada vez**: ao expandir o oculto, expandir só até o notch; o resto vai para a barra (#570).
7. **Mais tarde (depois de medir)**: lembrar quais itens o Paulo mais usa (contador local, no Mac, sem rede) para sugerir ficar no visível; "modo foco" que esvazia o visível por tempo/app ativo. Só se o Paulo quiser.

Tudo pequeno, testável com injeção de retângulos (casos: notch largo/pílula, tela sem notch, tela embutida à direita do externo, resolução escalada, itens que cabem justo).

## 6. Identidade

- **Nome exibido**: **Trincano** (`CFBundleDisplayName`/`PRODUCT_NAME`). Tipo Swift (`IceBar`, `MenuBarItem…`) **não muda** (cherry-pick limpo do upstream; só strings visíveis, `Info.plist`, `.xcodeproj` e docs). Na UI "Ice Bar" vira "Trincano Bar" (a confirmar).
- **Bundle id**: `br.com.pilutech.trincano` (app) e `br.com.pilutech.trincano.MenuBarItemService` (helper). Conferir no `project.pbxproj` e no `MenuBarItemServiceConnection.swift` qualquer nome de serviço XPC fixo (a busca por `com.jordanbaird` em `Shared/` e `MenuBarItemService/` não achou nenhum além do pbxproj; revalidar na fase 1).
- **Efeito do novo bundle id**: o macOS vê um app novo → Acessibilidade e Gravação de Tela de novo, `UserDefaults` novos (o plano inclui importar do domínio `com.jordanbaird.Ice`, só leitura), item de login novo, e dá para rodar ao lado do Ice instalado (mas **não ao mesmo tempo gerenciando a barra**).
- **Ícone**: o `designer` só propõe (direção, grade, tokens) depois que o Paulo aprovar o nome; a implementação e os prints ficam comigo. Ícone da barra de menus (ControlItem) também.
- **Créditos GPL-3.0** (obrigatórios): manter `LICENSE` e o cabeçalho de copyright de cada arquivo; README com "Fork do Ice de Jordan Baird (GPL-3.0)" e link; tela Sobre (`AboutSettingsPane.swift:20` hoje aponta para o upstream) com texto "Baseado no Ice de Jordan Baird" + link do upstream + link do código-fonte do fork; aviso de modificação (GPL §5a: "modificado por Paulo/PiluVitu, desde 2026-11") em README e Sobre; `Acknowledgements` (Sparkle, AXSwift, Ifrit, Semaphore, CompactSlider, LaunchAtLogin) mantido; autoria preservada nos cherry-picks (`-x`/Co-authored-by); código-fonte sempre público.
- **Sem copiar** nome, texto ou visual de apps pagos (Bartender etc.).

## 7. Segurança e privacidade (security-audit, modo guia — linha Segurança)

Conferido nesta fase (leitura; `SUPPLY-CHAIN-AND-RELEASE.md`, `CLOUD`/web não se aplicam):
- **ALTO — Sparkle aponta para o upstream.** `Info.plist` tem `SUFeedURL = https://jordanbaird.github.io/ice-releases/appcast.xml` e a `SUPublicEDKey` do Jordan. Um Trincano instalado **aceitaria e instalaria** qualquer release publicada pelo upstream (e substituiria o fork), e consulta a rede sem justificativa. **Bloqueia a fase 1**: zerar feed e chave (atualização desligada) ou usar feed/chave próprios (decisão Q3).
- **MÉDIO — XPC sem checagem de mesmo time em build ad-hoc.** Relaxar `.isFromSameTeam()` (PRs #950/#982/#1027) enfraquece o canal app↔`MenuBarItemService`. Mitigar com certificado estável (Q1) ou limitar a `#if DEBUG`.
- **MÉDIO — código de terceiros.** Forks/PRs entram por `cherry-pick -x` e revisão de diff; nenhum PR é aplicado sem ler. APIs privadas (`CGS*`) já existem no upstream e quebram entre versões do macOS.
- **BAIXO — permissões fortes** (Acessibilidade + Gravação de Tela): documentar no README o que é lido e que nada sai do Mac; imagens de itens ficam só em memória (checar na fase 1 que nada vai para disco).
- **Rede**: só o Sparkle (acima); `git grep` por `URLSession`, telemetria, Sentry, analytics = nada. Manter assim.
- **Para validar**: SBOM/licenças de `Package.resolved` (versões exatas e licenças de Sparkle, AXSwift, Ifrit, Semaphore, CompactSlider, LaunchAtLogin-Modern) na fase 1; runtime do XPC e permissões no Tahoe.

## 8. Pré-requisitos que faltam no repositório

- **Sem alvo de testes** (nada em `*Tests*`) e **SwiftLint não instalado** (o build tem `Run Script: SwiftLint` e avisa). Fase 1: `brew install swiftlint` (versão exata no relatório), criar alvo `TrincanoTests` (Swift Testing) e rodar `xcodebuild test` local; CI do GitHub sem minutos até o mês que vem, então tudo local.
- `SWIFT_VERSION = 5.0` e deployment target `14.0`. Swift 6 estrito vem em fase própria (muita `@MainActor`/Combine; migrar por módulo com `-strict-concurrency=complete` primeiro).
- CompactSlider não compila no SDK do Xcode 27 (#1027): trocar por `Slider` nativo (remove uma dependência) quando for hora de Xcode 27.
- Menos código morto: o ramo tem 18,8 mil linhas Swift em 104 arquivos; `MenuBarItemManager.swift` sozinho tem 1.839.
- Docs: criar `CLAUDE.md` e `AGENTS.md` (índice de `docs/`) e `docs/` com decisões, medições e roteiro de teste. Este commit já traz o índice mínimo.

## 9. Fases (pequenas, com critério de pronto)

Cada fase termina parada para revisão (Lupa revisa, Bancada testa), com relatório que inclui a linha Segurança.

**Fase 1 — Fundação e identidade (nada de feature)**
- Renomear nome/bundle ids/`Info.plist`; zerar Sparkle; Sobre/README com créditos GPL; `CLAUDE.md`/`AGENTS.md`; instalar SwiftLint; criar `TrincanoTests`; assinatura estável (Q1); CI local script `scripts/check.sh` (lint + build + test).
- Pronto quando: build Release limpo, `swiftlint` sem aviso, testes rodam, app abre como "Trincano" ao lado do Ice instalado, Sparkle sem rede, `git grep jordanbaird` só em créditos.

**Fase 2 — Tahoe funcionando (mínimo viável)**
- `cherry-pick -x` e revisão de #922 (displayID), #982 (CGWindowList nil + SCK; XPC só relaxado em DEBUG se não houver cert), #1019 (fallback de ícone), #984 (permissão via SCK), #911 (SourcePID thrash), correções de crash (#989, #956).
- Pronto quando, no Air M4 com 26.6.2: Layout mostra os itens, Ice Bar abre, mover item entre seções funciona, sem "Unable to display", sem crash em 1 h de uso; roteiro manual em `docs/roteiro-teste.md` (Bancada executa).

**Fase 3 — Medição e responsividade**
- `os_signpost` + scripts de medição (seção 4); números "antes". Depois: trocar os timers de 3/5/10 s por gatilhos por evento onde der, captura de imagens só com Ice Bar/Layout aberto ou item mudou, tirar lista de janelas do caminho de evento do mouse, trocar `Task.sleep` fixo por espera de evento, expirar cache (#804, `lxy1992`), testar a hipótese #819.
- Pronto quando: CPU em repouso e wakeups menores; `hover→show` e `click→show` com p95 ≤ 100 ms; footprint e WindowServer estáveis em 1 h; tabela antes/depois no relatório.

**Fase 4 — Notch inteligente**
- `NotchGeometry` pura + testes; aviso/realocação de item atrás do notch; Ice Bar automático por tela; clique no notch configurável; corrigir #260/#929-like; foco primeiro na tela embutida do Air M4 e depois valores que independem de largura (pílula).
- Pronto quando: caso #715 (item empurrado para o notch) e #570 (oculto passando do notch) reproduzidos e resolvidos no Air M4; testes cobrem notch retangular, pílula, sem notch, tela embutida deslocada; sem regressão no externo.

**Fase 5 — Perfis por tela e multi-monitor**
- Perfis por UUID de display, Ice Bar só na embutida/só externo, overlay só na tela certa (#1023, #988, #987, #698).
- Pronto quando: conectar/desconectar o externo aplica o perfil certo sem reiniciar, sem artefatos.

**Fase 6 — Acabamento (UX, acessibilidade, movimento)**
- Transições de 150 a 300 ms com movimento reduzido respeitado (`accessibilityDisplayShouldReduceMotion`); VoiceOver nos controles (hoje só há 2 `accessibilityLabel` em todo o código: `IceBar.swift:460` e `HotkeyRecorder.swift:115`; nenhum uso de `accessibilityDisplayShouldReduceMotion`); ícone final (designer propõe, eu implemento); onboarding curto em português.
- Pronto quando: roteiro de acessibilidade passa (VoiceOver, movimento reduzido, tamanho de texto) e o Paulo aprova os prints.

**Fase 7 — Swift 6 e limpeza** (pode andar em paralelo, por módulo): `-strict-concurrency=complete`, depois Swift 6; quebrar `MenuBarItemManager`; remover código morto.

**Instalação em toda fase que o Paulo testa**: fechar o app, `ditto` para `/Applications/Trincano.app`, abrir de lá. Antes da primeira instalação, resolver Q4 (coexistência com o Ice).

## 10. Riscos

- APIs privadas (`CGS*`) e a captura mudam a cada 26.x e no macOS 27; cada atualização do sistema pode quebrar. Mitigação: testes de geometria puros, fallback documentado, e isolar tudo em `Bridging`.
- Sem certificado, permissões se perdem a cada build (cdhash). Mitigação: Q1.
- Divergir demais do upstream dificulta cherry-picks; por isso não renomear tipos Swift.
- Dois gerenciadores de barra ao mesmo tempo brigam pelos itens: Q4.

## 11. Perguntas para o Paulo

1. **Assinatura (Q1)**: você tem Apple Developer ID ou uma conta Apple (um Personal Team grátis já serve para um certificado "Apple Development" estável)? O Mac só tem o "Printai Local Signing", não confiável. Sem isso o app usa ad-hoc e (a) perde as permissões a cada instalação e (b) o canal XPC fica sem a checagem de mesmo time. Recomendo criar o certificado de desenvolvimento.
2. **Nome (Q2)**: "Trincano" como nome exibido, `br.com.pilutech.trincano` como bundle id (e `.MenuBarItemService` no helper)? E na interface, "Trincano Bar" no lugar de "Ice Bar"?
3. **Atualizações (Q3)**: deixar a atualização automática **desligada** (recomendado: nada de rede) ou montar um feed Sparkle próprio no GitHub Pages do fork, com chave EdDSA nova?
4. **Coexistência (Q4)**: posso fechar o Ice instalado (PID 5307), tirar o item de login dele e **importar** as configurações dele para o Trincano (leitura de `com.jordanbaird.Ice`)? O `/Applications/Ice.app` fica ou eu removo quando o Trincano estiver estável? (Não mexo sem ordem.)
5. **Notch (Q5)**: ao faltar espaço atrás do notch, o padrão deve ser (a) mover o item para a barra abaixo do menu automaticamente, (b) só avisar, (c) nada? Recomendo (a) só na tela com notch. E clicar no notch deve abrir a barra? (Recomendo desligado por padrão.)
6. **Telas (Q6)**: você usa monitor externo? Qual (tamanho/resolução) e onde fica em relação ao Air (esquerda/cima)? É o que diz se a fase 5 importa já agora.
7. **Pílula (Q7)**: você tem acesso a um MacBook Pro novo para validar a pílula? Se não, a fase 4 só valida no notch do Air e simula a pílula com retângulos nos testes.
8. **Escopo (Q8)**: o que você mais quer ganhar de cara — Tahoe estável (fase 2), mais rápido (fase 3) ou notch (fase 4)? Proposta: seguir 1 → 2 → 3 → 4, e subir a 4 se o notch te incomoda hoje.
9. **Idioma (Q9)**: interface em português (PT-BR) além de inglês? O upstream tem PRs de localização (#1002, #983) que dá para aproveitar.
10. **Sincronização (Q10)**: preferências e perfis ficam só neste Mac, sem iCloud nem sincronização; ok? (Recomendo sim.)
