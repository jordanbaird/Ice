# Pendências (revisão do Lupa, PR #1)

Veredito do Lupa: PR #1 (3ff4ef9) pode seguir para **uso pessoal**, **não** está pronto para distribuição. Itens abaixo ficam para as próximas fases.

## XPC (app ↔ MenuBarItemService)
- Sem Team ID o requisito é só `signing-identifier`, que não prova o certificado. Caminhos:
  1. Requisito leve com **cdhash por build**, ancorado em metadados confiáveis (arquitetura/assinatura de dentro para fora).
     Fonte: https://developer.apple.com/documentation/lightweightcoderequirements/codedirectoryhash
  2. Migrar para `xpc_connection_*` com `identifier` + `certificate leaf` nos dois sentidos.
     Fonte: https://developer.apple.com/documentation/xpc/xpc_connection_set_peer_code_signing_requirement(_:_:)
- Nunca usar cast de handle privado nem autenticação por PID.

## Chave de assinatura local
- Antes de uso mais amplo: keychain com senha, bloqueio e ACL.
- Developer ID nunca neste keychain.
- `scripts/signing.sh:21` e `:43`: `trap` que apague PEM/P12 temporários em caso de falha.
- `scripts/signing.sh:49`: preservar espaços nos caminhos (o `tr -d` atual os remove).

## Importação das preferências do Ice
- `SettingsImportPlan.swift:34`: validar tipos e intervalos dos valores importados.
- `isControlItemKey` (`:19`): usar prefixos exatos, não `contains`.
- Testes com tipos errados e valores não finitos.
- Teste de importação + migrações preservando os valores já existentes no destino.

## Limpeza
- Remover `SUEnableAutomaticChecks` do `Ice/Resources/Info.plist`.
- Remover o Sparkle do `Acknowledgements.rtf` (e do `.pdf`).

## Projeto Xcode
- Limpar referências órfãs dos alvos de teste geradas no `project.pbxproj` por `scripts/add-test-target.rb` (o script recria o alvo e deixa grupos/refs antigas; sugestão do Lupa no PR #4).

## PendingPIDTracker e varredura do host (Lupa, PR #4 ded226a)
- `PendingPIDTrackerTests.pendingNotYetDueNeverTriggersARescan` só prova que nenhum item está vencido. Em `MenuBarItemManager.swift:400`, quando outro pendente vence ou os IDs mudam, `cacheItemsRegardless` reconstrói **todos** os itens; e o helper usa TTL próprio de 30 s, não o backoff 60/120/300 s do host.
- Sugestão: teste de integração com dois pendentes em prazos diferentes contando as consultas AX, ou documentar como otimização futura (consultar só os pendentes vencidos).

## Fase 3 (Lupa, PR #6)
- Teste do snapshot antigo do poll após troca de espaço/app.
- Teste de integração: abrir/fechar/trocar seção durante refresh lento.
- Teste de fiação do `HIDEventManager` (quais chamadas usam `.cached`/`.fresh`) além do `MenuBarHitTester`.

## Wakeups (fase 4, Lupa PR #7)
- Comparação pareada (mesmo build base/depois, mesmas opções e timers) e contagem de recaches/consultas por tela com os signposts; só então decidir sobre os timers de 5 s (poll e `IceBarColorManager`). Causa não afirmada.

## Notch (Lupa, PR #7 eb4e313)
- Teste de integração show/hide/seção com o handler real (`HIDEventManager` + `MenuBarSection`).
- Garantir por teste que a ação do notch já tratada não dispara os handlers seguintes que usam `bestScreen` (hoje: `handleNotchClick` devolve `true` e o monitor retorna antes; só por revisão).

## Limpeza da API do notch (Lupa, PR #7 1eabfbc)
- `HIDEventManager.swift:350` ainda lê `NSEvent.mouseLocation` para passar como `cursorLocation`, que o `NotchClickResolver.decide` ignora de propósito. Remover a leitura e o parâmetro da API de produção (os testes que simulam o cursor da entrega passariam a chamar `resolve(point:...)` direto ou um helper de teste).

## Telas (Lupa, PR #8 11d381e)
- UUID ausente (`CGDisplayCreateUUIDFromDisplayID` nil) hoje exclui o display da topologia: usar o `displayID` efêmero para a sessão/recache, sem gravar perfil.
- UUID duplicado duplica a identidade no `ForEach` do ajuste de Displays: usar ID de runtime na UI e definir uma política para UUID ambíguo; fixtures com UUID nil e duplicado.

## Fase 6 (acabamento)
- `IceBarColorManager` (linha ~68) só atualiza a cor quando `screen == .main` (tela do foco do teclado); com monitor externo a Barra do notebook pode não atualizar a cor. Trocar pela tela-alvo.
- Validar PT-BR ao vivo e VoiceOver com o Paulo; escolher o ícone (ver docs/fase-6-acabamento.md).
