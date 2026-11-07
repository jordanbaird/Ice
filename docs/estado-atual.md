# Trincano: estado ao fim do plano (2026-11-07)

Fork do Ice (GPL-3.0) para o Mac do Paulo (MacBook Air M4 com notch, macOS 26 Tahoe). Uso pessoal; **não** está pronto para distribuição (sem Developer ID/notarização, XPC com limite conhecido).

## As 7 fases (PRs no fork `PiluVitu/trincano`)
| Fase | O que entregou | PR |
|---|---|---|
| 0 | Análise e plano (`plano-inicial.md`) | commit local, depois #1 |
| 1 | Identidade Trincano, Sparkle removido (sem rede), créditos GPL, certificado local, testes, SwiftLint, importação opcional das configurações do Ice | #1 |
| 2 | Tahoe estável: cherry-picks do upstream (#922, #1019, #911), fallback ScreenCaptureKit, retry de PID | #4 |
| 3 | Signposts, memo da geometria do mouse (clique lê fresco), Barra do Trincano aparece com o cache, poll fora da main | #6 |
| 4 | Notch: `NotchGeometry`, Barra automática em tela com notch, itens atrás do notch na Barra, clique no notch | #7 |
| 5 | Telas: perfis por UUID de display, display ativo pelo ponteiro, rehide por tela-alvo, topologia ao conectar/desconectar | #8 |
| 6 | PT-BR/inglês (String Catalog, "Barra do Trincano"), movimento reduzido 150-300 ms, VoiceOver, ícone "Barra congelada" | #9, #11 |
| 7 | Swift 6 e concorrência estrita (zero avisos), `EventTapGroup`/`SignalWait` (taps e espera dos eventos de mover itens) | #12 |

> Nota: ao escrever este documento o PR #12 (fase 7) aparecia **aberto** no GitHub (a `main` ainda sem `SWIFT_VERSION = 6.0`), embora o Lupa tenha informado o merge. Conferir `git log origin/main` e `grep SWIFT_VERSION Ice.xcodeproj/project.pbxproj`.

Cada PR passou pelo Lupa; cada correção importante tem teste (vermelho comportamental quando era bug). Documentos por fase: `fase-2-tahoe.md` … `fase-6-acabamento.md`, `decisoes.md`, `assinatura.md`, `identidade/README.md`.

## Como o código está organizado
- `Ice/` (app, módulo Swift `Ice`), `MenuBarItemService/` (helper XPC), `Shared/` (compartilhado), `Tests/TrincanoTests/` (Swift Testing, sem host).
- **Lógica pura e testada** em `Ice/Utilities/Pure/` e `Shared/Utilities/` (geometria do notch, políticas de Barra/rehide, resolvers de tela, sessões, caches, `EventTapGroup`, `SignalWait`…). Compilada direto no alvo de testes (`scripts/add-test-target.rb`).
- Localização: `Ice/Resources/Localizable.xcstrings` (en + pt-BR); `scripts/extract-strings.py check` falha se faltar chave ou tradução.
- Medição: `os_signpost` (`scripts/measure-signposts.py`), `scripts/measure-idle.sh`.
- Tudo local: `scripts/check.sh` (SwiftLint `--strict` + testes + build Release + catálogo + ícone no bundle), `scripts/build.sh`, `scripts/install.sh`.

## Números de referência (Air M4, 26.6.2)
Ocioso: CPU ~0 %, memória ~56 MB, pico ~153 MB. Barra do Trincano: `iceBar.show` p50 34 ms / p95 58 ms. Poll de janelas ~2-10 ms, fora da thread principal.

## Pendências abertas (detalhes em `pendencias.md`)
Segurança e distribuição
1. **XPC sem certificado**: com o certificado local só o `signing-identifier` é exigido (não prova o certificado). Resolver com Developer ID (volta "mesmo time") ou cdhash/`xpc_connection_*`.
2. **Developer ID/notarização** quando a aprovação da Apple sair; chave de assinatura local sem senha (só uso local).
3. Importação das configurações do Ice: validar tipos/intervalos e prefixos exatos; limpar `SUEnableAutomaticChecks` e Sparkle do `Acknowledgements`.

Visual e acessibilidade
4. **Ícone**: no macOS 26 o ícone PNG aparece numa **placa branca**; fazer o `.icon` no Icon Composer (GUI). Reprodutibilidade do gerador (`qlmanage`/`sips` mudam entre versões do macOS).
5. **VoiceOver**: ações de mover itens no editor de layout (hoje o item é só lido); validar PT-BR e VoiceOver ao vivo.
6. `IceBarColorManager` só atualiza a cor quando a tela é a principal (ruim com monitor externo).

Multi-monitor
7. **Sem monitor externo físico**: #929/#698/#988/#1023 não reproduzidos; roteiro ao vivo em `fase-5-telas.md`.
8. UUID de display ausente exclui a tela da topologia; UUID duplicado duplica a identidade na UI (usar ID de runtime + política).

Qualidade e testes
9. **Integração com o app real**: `MenuBarSection`/`HIDEventManager`/`DisplayTopologyMonitor` só têm testes nas peças puras; falta teste de integração (abrir/fechar/trocar seção durante refresh lento, ação do notch não disparar os demais handlers, snapshot antigo do poll após troca de espaço).
10. Teste que detecte mudança de executor/thread da captura e do timer se as flags do Swift mudarem; `AXHelpers.queue` concorrente (só leitura AX).
11. Wakeups: comparação pareada sem uso para decidir sobre os timers de 5 s (causa não afirmada).
12. Limpeza: referências órfãs do alvo de testes no `pbxproj`; `cursorLocation` do `NotchClickResolver.decide` (parâmetro ignorado); teste do `DurationText.interfaceLocale` com idioma ≠ região.

## Não validado ao vivo (precisa do Paulo)
Clique no notch e Barra automática com item preso atrás do notch; troca de monitor; mover itens e rehide por timer com os `CGEventTap`s reais depois da fase 7; VoiceOver; app em PT-BR.
