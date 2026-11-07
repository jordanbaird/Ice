# Decisões da fase 1

- **Identidade**: nome `Trincano`, bundle id `br.com.pilutech.trincano`, helper `br.com.pilutech.trincano.MenuBarItemService`. O alvo do Xcode e o módulo Swift continuam `Ice` (`PRODUCT_MODULE_NAME = Ice`) e os tipos mantêm o prefixo `Ice` para cherry-pick limpo do upstream. Na interface, "Ice Bar" virou "Trincano Bar" (a tradução para "Barra do Trincano" vem com a localização).
- **Sem atualização e sem rede**: o Sparkle foi removido (pacote, `Updates.swift`, feed e chave EdDSA do upstream, menus, tela Sobre). O app não faz nenhuma requisição de rede.
- **Créditos GPL**: LICENSE intacto; cabeçalhos dos arquivos intactos; README e tela Sobre dizem que é versão modificada do Ice de Jordan Baird, com data, autor da modificação e links do código-fonte, da licença e do Ice original; `NSHumanReadableCopyright` traz o aviso. `FUNDING.yml` do upstream foi removido (apontava doações para o autor original).
- **Importação do Ice**: na primeira abertura, se existirem preferências de `com.jordanbaird.Ice`, o app pergunta uma vez se quer importar (só leitura, só chaves conhecidas, nunca sobrescreve, inclui a posição dos itens de controle).
- **Armazenamento de preferências**: continua `UserDefaults` local. A camada `Defaults` já centraliza as chaves; preparar iCloud fica para uma fase própria (não implementado).
- **Testes**: alvo `TrincanoTests` (Swift Testing, sem host) compila só lógica pura (`Shared/Utilities/XPCPeerPolicy.swift`, `Ice/Utilities/Pure/*.swift`). Para recriar o alvo: `ruby scripts/add-test-target.rb` (gem `xcodeproj`).
- **SwiftLint 0.65.1** (Homebrew). Corrigido o que a versão nova apontou (`scaledToFit()`); `swiftlint lint --strict` limpo.
- **Fora da fase 1** (ficam para as próximas): localização com String Catalog (PT-BR/en), ícone, perfis por tela (monitor externo fica em cima do notebook), Swift 6, Acknowledgements ainda cita o Sparkle (atualizar o PDF/RTF).

## Fase 7: Swift 6 (2026-11-07)

- Os alvos Ice, MenuBarItemService e TrincanoTests usam `SWIFT_VERSION = 6.0` (também em `scripts/add-test-target.rb`); com `SWIFT_STRICT_CONCURRENCY=complete` não há avisos de concorrência.
- Regra: `@unchecked Sendable`, `nonisolated(unsafe)` e `MainActor.assumeIsolated` só com comentário de uma linha dizendo a invariante (por exemplo, "só tocado na fila X"). Estado global mutável usa `OSAllocatedUnfairLock`.
- `RunLoopLocalEventMonitor` foi removido por não ter nenhum uso.

## Fase 7 (revisão do Lupa): espera dos eventos de mover itens
`postEventWithBarrier` e `scrombleEvent` esperam o evento de retorno por `SignalWait.wait` dentro de `EventTapGroup.withGroup`. A espera termina de **uma de três formas** (sinal, timeout ou cancelamento do chamador) e retoma a continuation **exatamente uma vez** (`Gate`); o `withTaskCancellationHandler` envolve a própria continuation (antes ficava numa `Task` separada que terminava logo depois de postar, e um evento de retorno ausente deixava taps vivos, cursor oculto e semáforo ocupado). A limpeza dos taps roda na main em todos os caminhos.
