# Trincano

Fork do [Ice](https://github.com/jordanbaird/Ice) (jordanbaird, GPL-3.0) com suporte ao macOS 26 e foco em Macs com notch. Base: `upstream/macos-26`. Remoto `origin` = PiluVitu/trincano (público), `upstream` = jordanbaird/Ice. PRs só contra a `main` do fork, nunca contra o upstream.

## Índice de documentação (`docs/`)
- [docs/plano-inicial.md](docs/plano-inicial.md): base, estado no Tahoe, dores do upstream, mapa de responsividade, notch, identidade, fases e perguntas.
- [docs/decisoes.md](docs/decisoes.md): decisões da fase 1 (identidade, Sparkle removido, créditos GPL, importação do Ice, testes).
- [docs/assinatura.md](docs/assinatura.md): certificado local, troca pelo Developer ID, checagem do XPC.
- [docs/roteiro-teste.md](docs/roteiro-teste.md): roteiro manual da fase 1.
- [docs/fase-6-acabamento.md](docs/fase-6-acabamento.md): localização PT-BR/en, movimento reduzido, VoiceOver e propostas de ícone.
- [docs/pendencias.md](docs/pendencias.md): pendências da revisão do Lupa (XPC, chave local, importação, limpeza).

## Comandos
- `scripts/check.sh`: swiftlint (`--strict`) + testes + build Release. Tudo local (CI do GitHub sem minutos).
- `scripts/build.sh [Release|Debug]`: build assinado (`SIGN_IDENTITY` para trocar o certificado). Saída em `build/`.
- `scripts/install.sh`: `ditto` para `/Applications/Trincano.app`; nunca fecha o Ice, só avisa.
- Testes: `xcodebuild -project Ice.xcodeproj -scheme TrincanoTests -destination 'platform=macOS' test`. Lógica pura vai em `Ice/Utilities/Pure/` ou `Shared/Utilities/` (compilada direto no alvo de testes; sem host). Recriar o alvo: `ruby scripts/add-test-target.rb`.

## Regras
- Manter LICENSE, cabeçalhos e créditos ao Ice; código-fonte público; sem telemetria e **sem rede** (Sparkle removido).
- Nome/IDs: `Trincano`, `br.com.pilutech.trincano`. Alvo e módulo Swift seguem `Ice`; tipos mantêm prefixo `Ice` (cherry-pick limpo, use `git cherry-pick -x`).
- XPC: nunca desligar a checagem de peer; ver `XPCPeerPolicy`.
- Bug: teste que falha primeiro. Lint limpo. Atualizar este arquivo e o `AGENTS.md` (idêntico) a cada fluxo novo.
