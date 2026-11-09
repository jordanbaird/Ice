# Trincano

Fork do [Ice](https://github.com/jordanbaird/Ice) (jordanbaird, GPL-3.0) com suporte ao macOS 26 e foco em Macs com notch. Base: `upstream/macos-26`. Remoto `origin` = PiluVitu/trincano (público), `upstream` = jordanbaird/Ice. PRs só contra a `main` do fork, nunca contra o upstream.

## Estado
O plano das 7 fases foi concluído (a fase 7, Swift 6, entrou pelo PR #12); veja [docs/estado-atual.md](docs/estado-atual.md) (resumo, números de referência e a lista de **pendências abertas**). Uso pessoal; não distribuir (sem Developer ID/notarização).

## Índice de documentação (`docs/`)
- [docs/estado-atual.md](docs/estado-atual.md): estado final, fases e PRs, pendências abertas.
- [docs/plano-inicial.md](docs/plano-inicial.md): base, estado no Tahoe, dores do upstream, mapa de responsividade, notch, identidade, fases e perguntas.
- [docs/decisoes.md](docs/decisoes.md): decisões da fase 1 (identidade, Sparkle removido, créditos GPL, importação do Ice, testes).
- [docs/assinatura.md](docs/assinatura.md): certificado local, troca pelo Developer ID, checagem do XPC.
- [docs/roteiro-teste.md](docs/roteiro-teste.md): roteiro manual da fase 1.
- [docs/fase-2-tahoe.md](docs/fase-2-tahoe.md), [fase-3](docs/fase-3-responsividade.md), [fase-4](docs/fase-4-notch.md), [fase-5](docs/fase-5-telas.md): o que cada fase fez, medições e roteiros ao vivo.
- [docs/identidade/README.md](docs/identidade/README.md): ícone "Barra congelada" e como gerar/verificar.
- [docs/fase-6-acabamento.md](docs/fase-6-acabamento.md): localização PT-BR/en, movimento reduzido, VoiceOver e propostas de ícone.
- [docs/rodada-design/README.md](docs/rodada-design/README.md): rodada de design do Fable (Sobre B, Busca A, Organização A, Geral B, Barra B), PR a PR, com roteiro ao vivo.
- [docs/pendencias.md](docs/pendencias.md): pendências da revisão do Lupa (XPC, chave local, importação, limpeza).

## Comandos
- `scripts/check.sh`: swiftlint (`--strict`) + testes + build Release. Tudo local (CI do GitHub sem minutos).
- `scripts/build.sh [Release|Debug]`: build assinado (`SIGN_IDENTITY` para trocar o certificado). Saída em `build/`.
- `scripts/install.sh`: `ditto` para `/Applications/Trincano.app`; nunca fecha o Ice, só avisa. Avise o Paulo antes (`maestri notify`).
- `scripts/measure-signposts.py`, `scripts/measure-idle.sh`: medição. `scripts/generate-icons.sh`: regenera os PNGs do ícone. `scripts/extract-strings.py check`: catálogo PT-BR.
- Testes: `xcodebuild -project Ice.xcodeproj -scheme TrincanoTests -destination 'platform=macOS' test`. Lógica pura vai em `Ice/Utilities/Pure/` ou `Shared/Utilities/` (compilada direto no alvo de testes; sem host). Recriar o alvo: `ruby scripts/add-test-target.rb`.

## Regras
- Manter LICENSE, cabeçalhos e créditos ao Ice; código-fonte público; sem telemetria e **sem rede** (Sparkle removido).
- Nome/IDs: `Trincano`, `br.com.pilutech.trincano`. Alvo e módulo Swift seguem `Ice`; tipos mantêm prefixo `Ice` (cherry-pick limpo, use `git cherry-pick -x`).
- XPC: nunca desligar a checagem de peer; ver `XPCPeerPolicy`.
- Swift 6 com concorrência estrita (zero avisos); `@unchecked Sendable`/`nonisolated(unsafe)`/`assumeIsolated` só com a invariante comentada. Interface em PT-BR e en (String Catalog); texto novo entra no catálogo.
- Bug: teste que falha primeiro. Lint limpo. Atualizar este arquivo e o `AGENTS.md` (idêntico) a cada fluxo novo.

## Página do catálogo (PRODUTO.md)
- `PRODUTO.md`, na raiz, alimenta a seção "Mais sobre" de https://pilutech.com.br/apps/trincano: o build do repo `pilutech-sites` o puxa da main. O texto foi aprovado pelo Paulo (proposta em `pilutech-sites`, `docs/propostas-produto-md/trincano.md`).
- Mudar o `PRODUTO.md` é mudar texto público: nada interno, sem preço, sem promessa, e só o que o produto já faz. Se o produto mudar, proponha o texto novo antes, em vez de editar direto.
